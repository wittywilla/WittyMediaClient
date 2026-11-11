// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Reaching a server from away, peer to peer: no port opened on anyone's router, nothing
// rented. The connecting is done by a helper program, wittyconnect, built from the server's
// own source (WittyMediaServer, cmd/wittyconnect, under the AGPL: see NOTICE). This file
// starts it, talks to it over its input and output, and keeps this device's key.
//
// The helper gives back an address on this computer. Loading the server from there is
// loading it from home: the same pages, the same sign-in. Only this app can use that
// address, because every request to it must carry a secret the helper makes up each time
// it starts, which this app puts in a cookie no page can read.
//
// docs/P2P.md in the server's repository is the whole design.
const { spawn } = require('child_process')
const { EventEmitter } = require('events')
const fs = require('fs')
const path = require('path')

// A server's or a device's connection ID: an Ed25519 key, in the text form libp2p gives it.
const ID = /^12D3KooW[1-9A-HJ-NP-Za-km-z]{44}$/
const SECRET = /^[A-Za-z0-9_-]{16,64}$/
const KEY = /^[A-Za-z0-9+/]{43}=$/
// A multiaddr, as far as this app needs to know: it only hands them to the helper, which
// reads them properly. What matters here is that nothing else can hide in one.
const ADDR = /^\/(ip4|ip6|dns|dns4|dns6)\/[A-Za-z0-9.:%-]{1,253}(\/[a-zA-Z0-9.-]{1,64}){1,12}$/
const MAX_HINTS = 12
const COOKIE = 'wittyconnect'
const HEADER = 'X-Witty-Connect'
const READY_MS = 15000
const INVITE_SCHEME = 'wittymedia:'

const validId = (id) => typeof id === 'string' && ID.test(id)

function cleanHints(list) {
  if (!Array.isArray(list)) return []
  return list.filter((a) => typeof a === 'string' && a.length <= 400 && ADDR.test(a)).slice(0, MAX_HINTS)
}

// The address the server is loaded from. Its name holds the end of the server's ID, so each
// server has a name of its own on this computer and so cookies of its own: a sign-in for one
// is never sent to another. Names under .localhost never leave the computer.
function originFor(serverId, port) {
  return `http://p2p-${serverId.slice(-16).toLowerCase()}.localhost:${port}`
}

const P2P_ORIGIN = /^http:\/\/p2p-[a-z0-9]{16}\.localhost:(\d{4,5})$/
function isP2POrigin(url) {
  const m = typeof url === 'string' && P2P_ORIGIN.exec(url)
  return !!m && Number(m[1]) >= 1024 && Number(m[1]) <= 65535
}

// What the app keeps about reaching a server this way.
function cleanInfo(info) {
  if (!info || typeof info !== 'object' || !validId(info.id)) return null
  const out = { id: info.id, hints: cleanHints(info.hints) }
  if (Number.isInteger(info.port) && info.port >= 1024 && info.port <= 65535) out.port = info.port
  return out
}

// An invite link: wittymedia://p2p/<server ID>?s=<secret>&n=<name>&a=<address>...
// Nothing in it is believed further than this: the ID is what gets dialled and proved, the
// addresses are only places to try, and the name is only shown.
function parseInvite(text) {
  let u
  try { u = new URL(String(text).trim()) } catch { return null }
  if (u.protocol !== INVITE_SCHEME || u.hostname !== 'p2p') return null
  const id = u.pathname.replace(/^\/+|\/+$/g, '')
  const secret = u.searchParams.get('s') || ''
  if (!validId(id) || !SECRET.test(secret)) return null
  return { serverId: id, secret, name: (u.searchParams.get('n') || '').slice(0, 80), hints: cleanHints(u.searchParams.getAll('a')) }
}

const looksLikeInvite = (text) => /^\s*wittymedia:\/\/p2p\//i.test(String(text))

// Where the helper is: beside the app's own files once installed, in bin/ from a checkout
// (npm run build:connect puts it there), or wherever WITTYCONNECT says.
function helperPath({ resourcesPath, packaged, env = process.env, platform = process.platform, arch = process.arch, exists = fs.existsSync } = {}) {
  const name = platform === 'win32' ? 'wittyconnect.exe' : 'wittyconnect'
  const places = []
  if (!packaged && env.WITTYCONNECT) places.push(env.WITTYCONNECT)
  if (resourcesPath) places.push(path.join(resourcesPath, name))
  // bin/ is named as electron-builder names systems, since packaging copies from it.
  const os = { darwin: 'mac', win32: 'win' }[platform] || platform
  places.push(path.join(__dirname, 'bin', `${os}-${arch}`, name))
  return places.find((p) => exists(p)) || ''
}

// This device's key. With the system's own protection for secrets when there is one (the
// keychain, DPAPI, a keyring), and readable by this user only either way.
function loadKey(file, safe) {
  try {
    const saved = JSON.parse(fs.readFileSync(file, 'utf8'))
    const key = saved.sealed && safe && safe.isEncryptionAvailable()
      ? safe.decryptString(Buffer.from(saved.sealed, 'base64'))
      : saved.key
    if (typeof key === 'string' && KEY.test(key) && validId(saved.deviceId)) return { key, deviceId: saved.deviceId }
  } catch { /* none yet, or unreadable: a new one is made */ }
  return null
}

function saveKey(file, safe, { key, deviceId }) {
  const sealed = safe && safe.isEncryptionAvailable()
  const body = sealed ? { deviceId, sealed: safe.encryptString(key).toString('base64') } : { deviceId, key }
  const temporary = `${file}.${process.pid}.tmp`
  fs.writeFileSync(temporary, JSON.stringify(body), { mode: 0o600 })
  fs.renameSync(temporary, file)
}

function forgetKey(file) {
  try { fs.rmSync(file, { force: true }) } catch { /* nothing more can be done */ }
}

// Runs the helper once to make a key.
function makeKey(program, run = spawn) {
  return new Promise((resolve, reject) => {
    const child = run(program, ['keygen'], { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true })
    let out = ''
    child.stdout.on('data', (d) => { if (out.length < 4096) out += d })
    child.on('error', reject)
    child.on('close', () => {
      try {
        const made = JSON.parse(out)
        if (KEY.test(made.key) && validId(made.deviceId)) return resolve({ key: made.key, deviceId: made.deviceId })
      } catch { /* falls through */ }
      reject(new Error('the connection helper made no key'))
    })
  })
}

const PATHS = ['connecting', 'offline', 'local', 'direct', 'relayed']

// What the helper says about the connection, kept to what the app shows.
function cleanState(s) {
  if (!s || typeof s !== 'object' || !PATHS.includes(s.path)) return { path: 'connecting' }
  const out = { path: s.path }
  if (s.path === 'relayed') out.community = s.community === true
  if (typeof s.transport === 'string' && /^(quic|tcp)$/.test(s.transport)) out.transport = s.transport
  if (typeof s.error === 'string') out.error = s.error.replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 300)
  return out
}

const connected = (s) => s.path === 'local' || s.path === 'direct' || s.path === 'relayed'

// One run of the helper, for one server. Events: 'state' (cleanState), 'addrs' (hints to
// keep), 'exit'. It stops when stop() is called, and by itself if this app dies: the helper
// exits when its input closes.
class Tunnel extends EventEmitter {
  constructor(program, config, { run = spawn, log = () => {} } = {}) {
    super()
    this.state = { path: 'connecting' }
    this.stopped = false
    this.enrolling = null
    this.buffer = ''
    this.ready = new Promise((resolve, reject) => {
      this.resolveReady = resolve
      this.rejectReady = reject
    })
    this.ready.catch(() => {}) // whoever started it hears of a failure from start()
    const timer = setTimeout(() => this.fail(new Error('the connection helper did not start in time')), READY_MS)
    this.ready.finally(() => clearTimeout(timer)).catch(() => {})
    try {
      this.child = run(program, [], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true })
    } catch (err) {
      this.fail(err)
      return
    }
    this.child.on('error', (err) => this.fail(err))
    this.child.on('exit', (code) => {
      this.fail(new Error(`the connection helper stopped (${code})`))
      if (this.enrolling) this.enrolling({ ok: false, error: 'The connection was lost.' })
      this.emit('exit', code)
    })
    this.child.stdout.setEncoding('utf8')
    this.child.stdout.on('data', (d) => this.read(d))
    // What the helper logs is the app's to keep, one line at a time, never more than a little.
    this.child.stderr.setEncoding('utf8')
    this.child.stderr.on('data', (d) => { for (const line of String(d).split('\n')) if (line.trim()) log(line.trim().slice(0, 400)) })
    this.child.stdin.on('error', () => {}) // the helper went first: 'exit' says so
    // The configuration holds this device's key, so it goes down the pipe, never on the
    // command line, where other programs could read it.
    this.write(config)
  }

  fail(err) {
    if (this.rejectReady) this.rejectReady(err)
    this.rejectReady = this.resolveReady = null
  }

  write(obj) {
    if (!this.child || this.stopped) return
    try { this.child.stdin.write(`${JSON.stringify(obj)}\n`) } catch { /* 'exit' says so */ }
  }

  read(chunk) {
    this.buffer += chunk
    if (this.buffer.length > 1 << 20) this.buffer = '' // a helper gone wrong: nothing it says is used
    let at
    while ((at = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, at)
      this.buffer = this.buffer.slice(at + 1)
      let e
      try { e = JSON.parse(line) } catch { continue }
      if (e && typeof e === 'object') this.handle(e)
    }
  }

  handle(e) {
    switch (e.event) {
      case 'ready':
        if (Number.isInteger(e.port) && e.port >= 1024 && e.port <= 65535 && SECRET.test(e.secret) && validId(e.deviceId) && this.resolveReady) {
          this.port = e.port
          this.secret = e.secret
          this.resolveReady({ port: e.port, secret: e.secret, deviceId: e.deviceId })
          this.rejectReady = this.resolveReady = null
        }
        break
      case 'state':
        this.state = cleanState(e.state)
        this.emit('state', this.state)
        break
      case 'addrs':
        this.emit('addrs', cleanHints(e.addrs))
        break
      case 'enrol':
        if (this.enrolling) {
          const done = this.enrolling
          this.enrolling = null
          const r = e.result && typeof e.result === 'object' ? e.result : {}
          done({
            ok: r.ok === true, code: typeof r.code === 'string' && /^[0-9]{6}$/.test(r.code) ? r.code : '',
            reason: typeof r.reason === 'string' ? r.reason.slice(0, 40) : '', error: typeof r.error === 'string' ? r.error.slice(0, 300) : '',
            serverName: typeof r.serverName === 'string' ? r.serverName.slice(0, 80) : '',
          })
        }
        break
      case 'error':
        this.fail(new Error(typeof e.error === 'string' ? e.error.slice(0, 300) : 'the connection helper failed'))
        break
      default: // a newer helper may say more
    }
  }

  // Shows the server an invite's secret. One at a time.
  enrol(secret, name, platform) {
    return new Promise((resolve) => {
      if (this.enrolling || this.stopped) return resolve({ ok: false, error: 'busy' })
      this.enrolling = resolve
      this.write({ cmd: 'enrol', secret, name, platform })
    })
  }

  networkChanged() { this.write({ cmd: 'network-changed' }) }

  // Resolves with the state once requests can be sent, or the state as it is when time runs out.
  whenConnected(ms) {
    return new Promise((resolve) => {
      if (connected(this.state)) return resolve(this.state)
      const done = (s) => { clearTimeout(timer); this.off('state', seen); this.off('exit', gone); resolve(s) }
      const seen = (s) => { if (connected(s)) done(s) }
      const gone = () => done({ path: 'offline', error: 'The connection helper stopped.' })
      const timer = setTimeout(() => done(this.state), ms)
      this.on('state', seen)
      this.on('exit', gone)
    })
  }

  stop() {
    if (this.stopped) return
    this.stopped = true
    this.removeAllListeners('state')
    this.removeAllListeners('addrs')
    if (!this.child) return
    // Closing its input is how it is told to stop; the signal is for one that doesn't listen.
    try { this.child.stdin.end() } catch { /* already gone */ }
    const child = this.child
    setTimeout(() => { try { child.kill() } catch { /* already gone */ } }, 1500).unref()
  }
}

// In words, for the title bar: how the server is being reached right now.
function pathWords(s) {
  switch (s && s.path) {
    case 'local': return 'Peer to peer · same network'
    case 'direct': return 'Peer to peer · direct'
    case 'relayed': return s.community ? 'Peer to peer · through a relay' : 'Peer to peer · connecting directly…'
    case 'offline': return 'Peer to peer · reconnecting…'
    case 'connecting': return 'Peer to peer · connecting…'
    default: return ''
  }
}

module.exports = {
  Tunnel, parseInvite, looksLikeInvite, originFor, isP2POrigin, cleanInfo, cleanHints, cleanState, connected, validId,
  helperPath, loadKey, saveKey, forgetKey, makeKey, pathWords, COOKIE, HEADER,
}
