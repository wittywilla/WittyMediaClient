// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
const test = require('node:test')
const assert = require('node:assert')
const { EventEmitter } = require('events')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { PassThrough } = require('stream')
const p2p = require('../p2p.js')
const state = require('../state.js')

const SERVER = '12D3KooWK99VoVxNE7XzyBwXEzW7xhK7Gpv85r9F3V3fyKSUKPH5'
const DEVICE = '12D3KooWJWoaqZhDaoEFshF7Rh1bpY9ohihFhzcW6d69Lr2NASuq'
const KEY = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI='
const SECRET = 'abcdefghijklmnopqrstuvwxyz012345'

// A helper that isn't one: what the app writes to it is kept, and the test speaks for it.
function fakeHelper() {
  const child = new EventEmitter()
  child.stdin = new PassThrough()
  child.stdout = new PassThrough()
  child.stderr = new PassThrough()
  child.killed = false
  child.kill = () => { child.killed = true }
  child.written = ''
  child.stdin.on('data', (d) => { child.written += d })
  child.stdin.on('end', () => { child.ended = true })
  child.say = (obj) => child.stdout.write(`${JSON.stringify(obj)}\n`)
  const run = (program, args, options) => {
    run.calls.push({ program, args, options })
    return child
  }
  run.calls = []
  return { child, run }
}

const tick = () => new Promise((resolve) => setImmediate(resolve))

test('an invite link is read, and nothing else is taken for one', () => {
  const link = `wittymedia://p2p/${SERVER}?s=abcdefghijklmnopqrstuv&n=Home+server&a=%2Fip4%2F203.0.113.4%2Fudp%2F4100%2Fquic-v1&a=rubbish`
  assert.deepStrictEqual(p2p.parseInvite(link), { serverId: SERVER, secret: 'abcdefghijklmnopqrstuv', name: 'Home server', hints: ['/ip4/203.0.113.4/udp/4100/quic-v1'] })
  assert.ok(p2p.looksLikeInvite(`  ${link}`))
  for (const bad of [
    '', 'http://192.168.1.20', `https://p2p/${SERVER}?s=abcdefghijklmnopqrstuv`, `wittymedia://item/12`,
    `wittymedia://p2p/${SERVER}`, `wittymedia://p2p/${SERVER}?s=short`, `wittymedia://p2p/not-an-id?s=abcdefghijklmnopqrstuv`,
    `wittymedia://p2p/${SERVER}?s=abcdefghijklmnop<script>`,
  ]) assert.strictEqual(p2p.parseInvite(bad), null, bad)
})

test('addresses that could hide something are dropped', () => {
  const good = ['/ip4/203.0.113.4/tcp/4100', '/ip6/2001:db8::1/udp/4100/quic-v1', `/ip4/198.51.100.2/tcp/4001/p2p/${SERVER}/p2p-circuit`, '/dns4/relay.example.org/tcp/443']
  const bad = ['http://evil.example', '/ip4/1.2.3.4/tcp/1 --flag', '/unix/tmp/x', '', null, 5, '/ip4/1.2.3.4/tcp/1\n/ip4/9.9.9.9/tcp/1', `/ip4/${'1'.repeat(500)}/tcp/1`]
  assert.deepStrictEqual(p2p.cleanHints([...good, ...bad]), good)
  assert.strictEqual(p2p.cleanHints(Array(40).fill(good[0])).length, 12)
  assert.deepStrictEqual(p2p.cleanHints('nope'), [])
})

test('each server gets a name of its own on this computer', () => {
  const origin = p2p.originFor(SERVER, 51234)
  assert.strictEqual(origin, 'http://p2p-9f3v3fyksukph5'.slice(0, 11) + SERVER.slice(-16).toLowerCase() + '.localhost:51234')
  assert.ok(p2p.isP2POrigin(origin))
  assert.notStrictEqual(p2p.originFor(DEVICE, 51234), origin)
  // The name is under .localhost, which no network can answer for.
  assert.strictEqual(new URL(origin).hostname.endsWith('.localhost'), true)
  for (const bad of ['http://127.0.0.1:51234', 'https://p2p-aaaaaaaaaaaaaaaa.localhost:51234', 'http://p2p-aaaaaaaaaaaaaaaa.localhost.evil.example:51234', 'http://p2p-aaaaaaaaaaaaaaaa.localhost:80', 'http://p2p-aaaaaaaaaaaaaaaa.localhost:51234/x', '']) {
    assert.strictEqual(p2p.isP2POrigin(bad), false, bad)
  }
})

test('what is remembered about a server from away survives being saved, and only that', () => {
  const origin = p2p.originFor(SERVER, 51234)
  const saved = state.clean({
    server: origin,
    recent: [
      { url: origin, name: 'Away only', p2p: { id: SERVER, hints: ['/ip4/203.0.113.4/tcp/4100', 'http://evil'], port: 51234, extra: 'x' } },
      { url: 'http://192.168.1.20:9797', name: 'Home', p2p: { id: 'nonsense' } },
      { url: 'http://192.168.1.21:9797', name: 'Other', p2p: { id: DEVICE, port: 80 } },
    ],
  })
  assert.strictEqual(saved.server, origin)
  assert.deepStrictEqual(saved.recent[0].p2p, { id: SERVER, hints: ['/ip4/203.0.113.4/tcp/4100'], port: 51234 })
  assert.strictEqual(saved.recent[1].p2p, undefined)
  assert.deepStrictEqual(saved.recent[2].p2p, { id: DEVICE, hints: [] })
  // Remembering the server again keeps the way to it; saying null forgets it.
  const again = state.remember(saved, { url: origin, name: 'Away only' })
  assert.deepStrictEqual(again.recent[0].p2p, saved.recent[0].p2p)
  assert.strictEqual(state.remember(saved, { url: origin, name: 'Away only', p2p: null }).recent[0].p2p, undefined)
})

test('the helper is looked for where it is installed', () => {
  const at = (found, options) => p2p.helperPath({ exists: (p) => found.includes(p), platform: 'linux', arch: 'x64', env: {}, ...options })
  const installed = path.join('/opt/app/resources', 'wittyconnect')
  assert.strictEqual(at([installed], { resourcesPath: '/opt/app/resources', packaged: true }), installed)
  assert.strictEqual(at([], { resourcesPath: '/opt/app/resources', packaged: true }), '')
  // A path from the environment is for a checkout only: an installed app never runs one.
  assert.strictEqual(at(['/tmp/evil', installed], { resourcesPath: '/opt/app/resources', packaged: true, env: { WITTYCONNECT: '/tmp/evil' } }), installed)
  assert.strictEqual(at(['/tmp/mine'], { packaged: false, env: { WITTYCONNECT: '/tmp/mine' } }), '/tmp/mine')
  assert.ok(p2p.helperPath({ exists: () => true, platform: 'win32', arch: 'x64', env: {}, resourcesPath: 'C:\\app', packaged: true }).endsWith('wittyconnect.exe'))
})

test('the device key is kept for this user only, sealed when the system can', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wmc-p2p-'))
  const file = path.join(dir, 'p2p-key.json')
  try {
    assert.strictEqual(p2p.loadKey(file, null), null)
    p2p.saveKey(file, null, { key: KEY, deviceId: DEVICE })
    assert.deepStrictEqual(p2p.loadKey(file, null), { key: KEY, deviceId: DEVICE })
    if (process.platform !== 'win32') assert.strictEqual(fs.statSync(file).mode & 0o077, 0)
    // With the system's protection, the key itself isn't in the file.
    const safe = {
      isEncryptionAvailable: () => true,
      encryptString: (s) => Buffer.from(s.split('').reverse().join('')),
      decryptString: (b) => b.toString().split('').reverse().join(''),
    }
    p2p.saveKey(file, safe, { key: KEY, deviceId: DEVICE })
    assert.ok(!fs.readFileSync(file, 'utf8').includes(KEY))
    assert.deepStrictEqual(p2p.loadKey(file, safe), { key: KEY, deviceId: DEVICE })
    assert.strictEqual(p2p.loadKey(file, null), null) // sealed, and nothing here can open it
    fs.writeFileSync(file, '{"key":"short","deviceId":"x"}')
    assert.strictEqual(p2p.loadKey(file, null), null)
    p2p.forgetKey(file)
    assert.strictEqual(fs.existsSync(file), false)
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
})

test('a key is made by the helper', async () => {
  const { child, run } = fakeHelper()
  const made = p2p.makeKey('/x/wittyconnect', run)
  child.stdout.end(`${JSON.stringify({ key: KEY, deviceId: DEVICE })}\n`)
  await tick()
  child.emit('close', 0)
  assert.deepStrictEqual(await made, { key: KEY, deviceId: DEVICE })
  assert.deepStrictEqual(run.calls[0].args, ['keygen'])
  const other = fakeHelper()
  const failed = p2p.makeKey('/x/wittyconnect', other.run)
  other.child.stdout.end('not json')
  await tick()
  other.child.emit('close', 1)
  await assert.rejects(failed)
})

test('the helper gets its configuration down the pipe, and the app hears what it says', async () => {
  const { child, run } = fakeHelper()
  const logged = []
  const t = new p2p.Tunnel('/x/wittyconnect', { key: KEY, serverId: SERVER, hints: [], port: 0 }, { run, log: (l) => logged.push(l) })
  await tick()
  // Nothing secret on the command line, where other programs could read it.
  assert.deepStrictEqual(run.calls[0].args, [])
  assert.deepStrictEqual(JSON.parse(child.written), { key: KEY, serverId: SERVER, hints: [], port: 0 })

  const states = []
  t.on('state', (s) => states.push(s))
  child.stdout.write('not json\n')
  child.say({ event: 'ready', port: 80, secret: SECRET, deviceId: DEVICE }) // not a port the helper may name
  child.say({ event: 'ready', port: 51234, secret: SECRET, deviceId: DEVICE })
  assert.deepStrictEqual(await t.ready, { port: 51234, secret: SECRET, deviceId: DEVICE })
  child.say({ event: 'state', state: { path: 'relayed', relay: 'x', community: false, error: 'a\nb', attempts: 3 } })
  child.say({ event: 'state', state: { path: 'made-up' } })
  child.say({ event: 'something-new', x: 1 })
  child.stderr.write('level=INFO msg="hello"\n')
  await tick()
  assert.deepStrictEqual(states, [{ path: 'relayed', community: false, error: 'a b' }, { path: 'connecting' }])
  assert.deepStrictEqual(logged, ['level=INFO msg="hello"'])

  // Waiting for a path that carries requests.
  const waiting = t.whenConnected(5000)
  child.say({ event: 'state', state: { path: 'direct', transport: 'quic' } })
  assert.deepStrictEqual(await waiting, { path: 'direct', transport: 'quic' })
  assert.deepStrictEqual(await t.whenConnected(1), { path: 'direct', transport: 'quic' })

  const hints = new Promise((resolve) => t.on('addrs', resolve))
  child.say({ event: 'addrs', addrs: ['/ip4/203.0.113.4/tcp/4100', 'javascript:alert(1)'] })
  assert.deepStrictEqual(await hints, ['/ip4/203.0.113.4/tcp/4100'])

  // An invite: asked through the helper, answered with only what a code and a name can be.
  child.written = ''
  const enrolled = t.enrol('abcdefghijklmnopqrstuv', 'This PC', 'Linux')
  await tick()
  assert.deepStrictEqual(JSON.parse(child.written), { cmd: 'enrol', secret: 'abcdefghijklmnopqrstuv', name: 'This PC', platform: 'Linux' })
  assert.deepStrictEqual(await t.enrol('x', 'y', 'z'), { ok: false, error: 'busy' })
  child.say({ event: 'enrol', result: { ok: true, code: '123456', serverName: 'Home', addrs: ['x'], extra: { a: 1 } } })
  assert.deepStrictEqual(await enrolled, { ok: true, code: '123456', reason: '', error: '', serverName: 'Home' })
  const refused = t.enrol('abcdefghijklmnopqrstuv', 'This PC', 'Linux')
  child.say({ event: 'enrol', result: { ok: false, reason: 'expired', error: 'That invite has expired.', code: 'not-a-code' } })
  assert.deepStrictEqual(await refused, { ok: false, code: '', reason: 'expired', error: 'That invite has expired.', serverName: '' })

  // Stopping closes its input, which is how it is told; nothing more is heard from it.
  t.stop()
  await tick()
  assert.strictEqual(child.ended, true)
  const heard = states.length
  child.say({ event: 'state', state: { path: 'offline' } })
  await tick()
  assert.strictEqual(states.length, heard)
})

test('a helper that fails to start, or dies, is noticed', async () => {
  const dead = fakeHelper()
  const t = new p2p.Tunnel('/x/wittyconnect', { key: KEY, serverId: SERVER }, { run: dead.run })
  dead.child.say({ event: 'error', error: 'this device has no connection key' })
  await assert.rejects(t.ready, /no connection key/)

  const gone = fakeHelper()
  const t2 = new p2p.Tunnel('/x/wittyconnect', { key: KEY, serverId: SERVER }, { run: gone.run })
  gone.child.say({ event: 'ready', port: 51234, secret: SECRET, deviceId: DEVICE })
  await t2.ready
  const exited = new Promise((resolve) => t2.on('exit', resolve))
  const waiting = t2.whenConnected(5000)
  const enrolling = t2.enrol('abcdefghijklmnopqrstuv', 'a', 'b')
  gone.child.emit('exit', 1)
  assert.strictEqual(await exited, 1)
  assert.strictEqual((await waiting).path, 'offline')
  assert.strictEqual((await enrolling).ok, false)

  const t3 = new p2p.Tunnel('/nowhere', {}, { run: () => { throw new Error('ENOENT') } })
  await assert.rejects(t3.ready, /ENOENT/)
})

test('the path is said in words', () => {
  assert.strictEqual(p2p.pathWords({ path: 'direct' }), 'Peer to peer · direct')
  assert.match(p2p.pathWords({ path: 'relayed', community: true }), /relay/)
  assert.match(p2p.pathWords({ path: 'relayed', community: false }), /connecting directly/)
  assert.match(p2p.pathWords({ path: 'offline' }), /reconnecting/)
  assert.strictEqual(p2p.pathWords(null), '')
})
