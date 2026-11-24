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
const { cleanCode } = require('./code.js')

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

// An invite link: wittymedia://p2p/<server ID>?s=<secret>&n=<name>&a=<address>...&h=<home>&c=<code>
// Nothing in it is believed further than this: the ID is what gets dialled and proved, the
// addresses are only places to try, and the name is only shown. h and c (from 0.8.5, in the QR
// code on Connect a device) are the web address the server's page was opened at and the code
// beside the QR code: asked there first, at home, where the server has to prove it made the code
// (code.js). Both or neither.
function parseInvite(text) {
  let u
  try { u = new URL(String(text).trim()) } catch { return null }
  if (u.protocol !== INVITE_SCHEME || u.hostname !== 'p2p') return null
  const id = u.pathname.replace(/^\/+|\/+$/g, '')
  const secret = u.searchParams.get('s') || ''
  if (!validId(id) || !SECRET.test(secret)) return null
  const home = inviteHome(u.searchParams.get('h') || '')
  const code = cleanCode(u.searchParams.get('c') || '')
  const both = !!home && !!code
  return {
    serverId: id, secret, name: shownName(u.searchParams.get('n') || '', 80), hints: cleanHints(u.searchParams.getAll('a')),
    home: both ? home : '', code: both ? code : '',
  }
}

// A web address fit for an invite's h: http or https, a host and maybe a port, nothing else (the
// server's p2p.InviteHome). '' when it isn't one.
function inviteHome(text) {
  if (text.length > 200) return ''
  let u
  try { u = new URL(text) } catch { return '' }
  if ((u.protocol !== 'http:' && u.protocol !== 'https:') || !u.hostname || u.username || u.password || u.search || u.hash) return ''
  if (u.pathname !== '/') return ''
  return `${u.protocol}//${u.host}`
}

// A name that came in a link, fit to show: no control characters, and none of the invisible ones
// that turn text around, so a name can't be made to read as something else beside it.
const INVISIBLE = /[\p{Cc}\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]/gu
const shownName = (text, max) => Array.from(String(text).replace(INVISIBLE, '').trim()).slice(0, max).join('').trim()

const looksLikeInvite = (text) => /^\s*wittymedia:\/\/p2p\//i.test(String(text))

// Where the helper is: beside the app's own files once installed, in bin/ from a checkout
// (npm run build:connect puts it there), or wherever WITTYCONNECT says. On FreeBSD the app is an
// app.asar run by the system's Electron, whose resources folder isn't ours: there the helper is
// beside app.asar (build/freebsd/package.mjs), since nothing runs from inside an archive.
function helperPath({ resourcesPath, packaged, env = process.env, platform = process.platform, arch = process.arch, exists = fs.existsSync, here = __dirname } = {}) {
  const name = platform === 'win32' ? 'wittyconnect.exe' : 'wittyconnect'
  const places = []
  if (!packaged && env.WITTYCONNECT) places.push(env.WITTYCONNECT)
  if (resourcesPath) places.push(path.join(resourcesPath, name))
  if (/\.asar$/i.test(here)) places.push(path.join(path.dirname(here), name))
  // bin/ is named as electron-builder names systems, since packaging copies from it.
  const os = { darwin: 'mac', win32: 'win' }[platform] || platform
  places.push(path.join(here, 'bin', `${os}-${arch}`, name))
  return places.find((p) => exists(p)) || ''
}

// This device's key. With the system's own protection for secrets when there is one (the
// keychain, DPAPI, a keyring), and readable by this user only either way.
function loadKey(file, safe) {
  try {
    const saved = JSON.parse(fs.readFileSync(file, 'utf8'))
    const protectedNow = !!(safe && safe.isEncryptionAvailable())
    const key = saved.sealed && protectedNow
      ? safe.decryptString(Buffer.from(saved.sealed, 'base64'))
      : saved.key
    if (typeof key === 'string' && KEY.test(key) && validId(saved.deviceId)) {
      // Kept in the clear because the system had no protection for secrets then, and has now:
      // sealed from here on.
      if (!saved.sealed && protectedNow) {
        try { saveKey(file, safe, { key, deviceId: saved.deviceId }) } catch { /* tried again next time */ }
      }
      return { key, deviceId: saved.deviceId }
    }
  } catch { /* none yet, or unreadable: a new one is made */ }
  return null
}

// A key sealed by the system that the system can't open right now (a keyring that is locked, or
// not running yet): it is still this device's key, and must not be replaced by a new one, which
// would also have to be kept in the clear.
function keyLocked(file, safe) {
  try {
    const saved = JSON.parse(fs.readFileSync(file, 'utf8'))
    return typeof saved.sealed === 'string' && saved.sealed !== '' && !(safe && safe.isEncryptionAvailable())
  } catch { return false }
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
  if (s.path === 'relayed') {
    out.community = s.community === true
    // What the relay said it allows (a relay that carries whole connections says so before use).
    const int = (v, lo, hi) => (Number.isInteger(v) && v >= lo && v <= hi ? v : 0)
    if (out.community) {
      const kbps = int(s.relayKbps, 100, 10000000)
      const height = int(s.relayMaxHeight, 144, 4320)
      if (kbps) out.relayKbps = kbps
      if (height) out.relayMaxHeight = height
      if (typeof s.relayAllows === 'string' && s.relayAllows) out.relayAllows = s.relayAllows.replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 300)
    }
  }
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

const JOIN_CODE = /^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/

// What the helper says about joining, kept to what the app uses: whether the server took the
// code, which server it is and where, and the sign-in code that came with it.
function cleanJoined(r) {
  if (!r || typeof r !== 'object' || r.ok !== true || !validId(r.serverId)) {
    return { ok: false, reason: r && typeof r.reason === 'string' ? r.reason.slice(0, 40) : '', error: r && typeof r.error === 'string' ? r.error.slice(0, 300) : '' }
  }
  return {
    ok: true, serverId: r.serverId, hints: cleanHints(r.addrs),
    code: typeof r.code === 'string' && /^[0-9]{6}$/.test(r.code) ? r.code : '',
    serverName: typeof r.serverName === 'string' ? r.serverName.slice(0, 80) : '',
  }
}

// Joining a server from away by a code this device shows ("wittyconnect join"): someone signed in
// types the code into the server. code resolves with the code to show; result with the server's
// answer ({ ok, serverId, hints, code, serverName }) or { ok: false, error } ('expired' when the
// fifteen minutes ran out). stop() gives up.
class JoinRun {
  constructor(program, config, { run = spawn, log = () => {} } = {}) {
    this.stopped = false
    this.buffer = ''
    let gotCode
    let gotResult
    this.code = new Promise((resolve) => { gotCode = resolve })
    this.result = new Promise((resolve) => { gotResult = resolve })
    this.finish = (r) => { gotCode(''); gotResult(r); gotCode = gotResult = () => {} }
    this.showCode = (c) => { gotCode(c); gotCode = () => {} }
    try {
      this.child = run(program, ['join'], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true })
    } catch (err) {
      this.finish({ ok: false, error: 'p2p-failed' })
      return
    }
    this.child.on('error', () => this.finish({ ok: false, error: 'p2p-failed' }))
    this.child.on('exit', () => this.finish({ ok: false, error: this.stopped ? 'stopped' : 'p2p-failed' }))
    this.child.stdout.setEncoding('utf8')
    this.child.stdout.on('data', (d) => this.read(d))
    this.child.stderr.setEncoding('utf8')
    this.child.stderr.on('data', (d) => { for (const line of String(d).split('\n')) if (line.trim()) log(line.trim().slice(0, 400)) })
    this.child.stdin.on('error', () => {})
    // The key goes down the pipe, never on the command line.
    try { this.child.stdin.write(`${JSON.stringify(config)}\n`) } catch { /* 'exit' says so */ }
  }

  read(chunk) {
    this.buffer += chunk
    if (this.buffer.length > 1 << 16) this.buffer = ''
    let at
    while ((at = this.buffer.indexOf('\n')) >= 0) {
      const line = this.buffer.slice(0, at)
      this.buffer = this.buffer.slice(at + 1)
      let e
      try { e = JSON.parse(line) } catch { continue }
      if (!e || typeof e !== 'object') continue
      if (e.event === 'code' && JOIN_CODE.test(e.code)) this.showCode(e.code)
      else if (e.event === 'joined') this.finish(cleanJoined(e.result))
      else if (e.event === 'error') this.finish({ ok: false, error: e.error === 'expired' ? 'expired' : 'p2p-failed' })
    }
  }

  stop() {
    if (this.stopped) return
    this.stopped = true
    this.finish({ ok: false, error: 'stopped' })
    if (!this.child) return
    try { this.child.stdin.end() } catch { /* already gone */ }
    const child = this.child
    setTimeout(() => { try { child.kill() } catch { /* already gone */ } }, 1500).unref()
  }
}

// A relay's limits, short: "4 Mbit/s, 720p".
function relayLimits(s) {
  const parts = []
  if (s.relayKbps) parts.push(s.relayKbps >= 1000 ? `${+(s.relayKbps / 1000).toFixed(1)} Mbit/s` : `${s.relayKbps} kbit/s`)
  if (s.relayMaxHeight) parts.push(`${s.relayMaxHeight}p`)
  return parts.join(', ')
}

// In words, for the title bar: how the server is being reached right now. Through a relay,
// what the relay allows is said too, so a smaller picture has its reason in sight.
function pathWords(s) {
  switch (s && s.path) {
    case 'local': return 'Peer to peer · same network'
    case 'direct': return 'Peer to peer · direct'
    case 'relayed': {
      if (!s.community) return 'Peer to peer · connecting directly…'
      const limits = relayLimits(s)
      return limits ? `Peer to peer · through a relay · ${limits}` : 'Peer to peer · through a relay'
    }
    case 'offline': return 'Peer to peer · reconnecting…'
    case 'connecting': return 'Peer to peer · connecting…'
    default: return ''
  }
}

module.exports = {
  Tunnel, JoinRun, cleanJoined, parseInvite, inviteHome, shownName, looksLikeInvite, originFor, isP2POrigin, cleanInfo, cleanHints, cleanState, connected, validId,
  helperPath, loadKey, keyLocked, saveKey, forgetKey, makeKey, pathWords, COOKIE, HEADER,
}
