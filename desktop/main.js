// SPDX-License-Identifier: GPL-3.0-or-later
//
// WittyMediaClient - Apps that connect to a WittyMediaServer, for TV boxes, phones, tablets and desktops.
// Copyright (C) 2026 WittyWilla and contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// WittyMediaClient for Windows, macOS, Linux and FreeBSD: a window with two views, and no
// title bar of the system's. Ours is a local page, which on a Mac has the system's buttons on
// it. Below it, the content view shows the connect screen and then the server's web UI, which
// has no access to Node or to the app beyond reporting its theme colours and asking for Moonlight.
const { app, BaseWindow, Menu, WebContentsView, clipboard, ipcMain, net, powerMonitor, powerSaveBlocker, protocol, safeStorage, session, shell, systemPreferences } = require('electron')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { normalizeAddress } = require('./connect/address.js')
const { judge, judgeMissing, signInFits, admit, fingerprintOf, newNonce } = require('./identity.js')
const guards = require('./guards.js')
const { startDiscovery } = require('./discover.js')
const moonlight = require('./moonlight.js')
const { createClientLog } = require('./clientlog.js')
const state = require('./state.js')
const servers = require('./servers.js')
const tv = require('./tv.js')
const playback = require('./playback.js')
const mac = require('./mac.js')
const p2p = require('./p2p.js')

const TITLE_BAR = 32
const CONNECT_PAGE = guards.CONNECT_PAGE
const BAR_PAGE = guards.BAR_PAGE
const TV_MENU_PAGE = guards.TV_MENU_PAGE
const STATUS_TIMEOUT_MS = 5000
// From away, the first answer can wait for a direct connection to be made through two routers.
const AWAY_TIMEOUT_MS = 25000
const AWAY_CONNECT_MS = 45000
const LEARN_AFTER_MS = 15 * 1000
const LEARN_EVERY_MS = 30 * 60 * 1000
const API = '/api/v1' // the contract: docs/CLIENT-API.md
const SESSION_COOKIE = 'wms_token'
const SESSION_DAYS = 90
const COLOUR = /^(#[0-9a-fA-F]{3,8}|rgba?\([\d\s.,%/]+\))$/
// The default theme's own, for the moments no server is deciding.
const BACKGROUND = '#0f1115'
const BAR_THEME = { bg: '#0f1115', fg: '#e8eaf0', border: 'transparent' }
const RESTART_GAP_MS = 10 * 1000
// On a TV: the whole screen from the start, no title bar, and the server's big screen mode.
const TV = tv.wanted(process.argv, process.env)
// FreeBSD's Electron is the system's own and starts this app from the outside, so it
// never counts as packaged. Being inside its archive is what says this is an installed copy.
const INSTALLED = app.isPackaged || __dirname.includes('.asar')
// On a Mac, the system's window buttons and menu bar. A TV is the same everywhere.
const MAC = process.platform === 'darwin' && !TV

const stateFile = () => path.join(app.getPath('userData'), 'state.json')
let saved = {}
let win, bar, content, tvMenu, secure
let server = '' // the origin the content view may show
let lastServer = ''
let stopDiscovery = null
let shown = null // what the connect screen last showed about a server, to hold it to that
let pairing = null // a code on show for someone to approve: { url, at, secret }, and the secret stays here
// The connection to a server away from home, while there is one: { run, id, origin, port, deviceId }.
// `origin` is the address on this computer that the helper answers at (p2p.js).
let tunnel = null
let awayGivenUp = false // the person stopped waiting for a server to be reached from away
let learnTimer = null

const OS_NAMES = { win32: 'Windows', linux: 'Linux', darwin: 'macOS', freebsd: 'FreeBSD' }
const OS_NAME = OS_NAMES[process.platform] || process.platform
const DEVICE = `${OS_NAME} ${os.release()} ${process.arch}, Electron ${process.versions.electron}`

// The sign-in stays in the session's cookie, which no page script can read. Only
// the main process reads it here, to send this app's own reports to that server.
async function reportTarget() {
  if (!server) return null
  const origin = server
  const cookies = await session.defaultSession.cookies.get({ url: origin, name: SESSION_COOKIE })
  const token = cookies.length ? cookies[0].value : ''
  return token ? { origin, token } : null
}

async function postReport(to, body) {
  const res = await fetchJson(to.origin + API + '/logs/client', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${to.token}` }, body,
  })
  res.text().catch(() => {})
  return { status: res.status, retryAfter: res.headers.get('retry-after') }
}

// Only what the main process sees: the server's page reports its own errors.
const log = createClientLog({
  dir: path.join(app.getPath('userData'), 'logs'), app: 'WittyMediaClient desktop', version: app.getVersion(), device: DEVICE,
  target: reportTarget, post: postReport,
})

// Carrying on is safe here: a failed window or request is reported where it
// happens, and these are the ones nobody caught. A failed start ends the app below.
process.on('uncaughtException', (err) => log.noteError('error', 'crash', 'Uncaught error in the main process', err, { page: 'main process' }))
process.on('unhandledRejection', (err) => log.noteError('error', 'crash', 'Unhandled rejection in the main process', err, { page: 'main process' }))

function openLogs() {
  shell.openPath(log.dir)
    .then((problem) => { if (problem) log.info('app', `The logs folder could not be opened: ${problem}`) })
    .catch((err) => log.noteError('info', 'app', 'The logs folder could not be opened', err))
}

function copyDiagnostics() {
  clipboard.writeText(log.diagnostics([`Connected to a server: ${server ? 'yes' : 'no'}`]))
}

function showHelpMenu(at) {
  const { width, height } = win.getContentBounds()
  Menu.buildFromTemplate([
    ...(server ? [{ label: 'Manage servers…', click: manageServers }, { type: 'separator' }] : []),
    { label: 'Open logs folder', click: openLogs },
    { label: 'Copy diagnostic info', click: copyDiagnostics },
    { type: 'separator' },
    { label: 'F6 moves between the page and this bar', enabled: false },
  ]).popup({ window: win, ...guards.menuPoint(at, width, height) })
}

// Everything that can go wrong with a view that the view can't report itself.
function watchContents(wc, name, recover) {
  // A page that keeps crashing doesn't get to do so in a tight loop.
  const mayRecover = guards.budget(1, RESTART_GAP_MS)
  wc.on('render-process-gone', (_e, details) => {
    if (details.reason === 'clean-exit') return
    log.error('crash', `The ${name} stopped: ${details.reason}, exit code ${details.exitCode}`, { page: name })
    if (mayRecover()) recover()
  })
  wc.on('unresponsive', () => log.warn('crash', `The ${name} stopped responding`, { page: name }))
  wc.on('responsive', () => log.info('crash', `The ${name} is responding again`, { page: name }))
  wc.on('preload-error', (_e, _preload, err) => log.noteError('error', 'crash', `The ${name} failed to prepare`, err, { page: name }))
}

const senderIs = (e, check) => { try { return check(e.senderFrame.url) } catch { return false } }
// The page the content view is meant to be showing, and not a frame inside it.
const fromContent = (e) => e.sender === content.webContents && e.senderFrame === e.sender.mainFrame
const fromConnect = (e) => fromContent(e) && senderIs(e, guards.isConnectUrl)
const fromBar = (e) => e.sender === bar.webContents
const fromServerPage = (e) => fromContent(e) && senderIs(e, (url) => server !== '' && new URL(url).origin === server)
const launchMoonlight = moonlight.launcher()

const mayOpenOutside = guards.budget()

function openOutside(url) {
  const address = guards.outsideAddress(url)
  if (!address) return
  if (!mayOpenOutside()) return log.warn('app', 'A page tried to open too many things outside the app')
  shell.openExternal(address).catch((err) => log.noteError('info', 'app', 'A link could not be opened', err))
}

const isF6 = (input) => input.type === 'keyDown' && input.key === 'F6' && !input.control && !input.alt && !input.shift && !input.meta

let windowButtons = true

function layout() {
  const { width, height } = win.getContentBounds()
  const full = TV || win.isFullScreen() || htmlFullScreen
  bar.setVisible(!full)
  if (MAC) {
    const buttons = mac.windowButtonsShown(!full, win.isFullScreen())
    if (buttons !== windowButtons) win.setWindowButtonVisibility(windowButtons = buttons)
  }
  bar.setBounds({ x: 0, y: 0, width, height: TITLE_BAR })
  const top = full ? 0 : TITLE_BAR
  content.setBounds({ x: 0, y: top, width, height: Math.max(0, height - top) })
  if (tvMenu) tvMenu.setBounds({ x: 0, y: 0, width, height })
}

// Back at the top of the app. A remote can't reach a title bar, and this is what's on it.
function openTvMenu() {
  if (!tvMenu) {
    tvMenu = new WebContentsView({ webPreferences: { ...secure, preload: path.join(__dirname, 'titlebar', 'preload.js') } })
    tvMenu.setBackgroundColor('#00000000')
    tvMenu.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
    tvMenu.webContents.on('will-navigate', (e) => e.preventDefault())
    watchContents(tvMenu.webContents, 'TV menu', () => closeTvMenu())
  }
  const details = { hasServer: Boolean(server) }
  const show = () => {
    win.contentView.addChildView(tvMenu)
    layout()
    tvMenu.webContents.focus()
    tvMenu.webContents.send('tv-menu-open', details)
  }
  if (tvMenu.webContents.getURL()) show()
  else tvMenu.webContents.loadURL(TV_MENU_PAGE).then(show).catch((err) => log.noteError('error', 'app', 'The TV menu could not be opened', err))
}

function closeTvMenu() {
  if (!tvMenu) return
  win.contentView.removeChildView(tvMenu)
  content.webContents.focus()
}

let htmlFullScreen = false

function endDiscovery() {
  if (stopDiscovery) stopDiscovery()
  stopDiscovery = null
}

// A load that fails is reported by did-fail-load, which is where it gets dealt with.
const quietly = (loading) => loading.catch(() => {})

// What the app itself loads starts history afresh. Otherwise Back would walk from a
// server's first page to the connect screen, around everything that guards it.
let startedAfresh = false

function showConnect(query) {
  endDiscovery()
  clearTimeout(learnTimer)
  clearInterval(learnTimer)
  sayPath('')
  server = ''
  pairing = null
  startedAfresh = true
  bar.webContents.send('server', '')
  bar.webContents.send('theme', BAR_THEME)
  updateMenu()
  quietly(content.webContents.loadURL(query ? `${CONNECT_PAGE}?${new URLSearchParams(query)}` : CONNECT_PAGE))
}

function showServer(url) {
  endDiscovery()
  managing = ''
  server = new URL(url).origin
  lastServer = server
  shown = null
  pairing = null
  startedAfresh = true
  bar.webContents.send('server', url)
  updateMenu()
  quietly(content.webContents.loadURL(TV ? tv.tenFootAddress(url) : url))
  log.kick()
  // Reached from away, the title bar says how. Reached directly, the app learns the other way.
  sayPath(tunnel && server === tunnel.origin ? p2p.pathWords(tunnel.run.state) : '')
  learnSoon()
}

function saveState() {
  if (!state.save(stateFile(), saved)) log.warn('app', 'What the app remembers could not be saved')
}

// Requests the app itself makes. To the helper's address they carry its secret, as the
// pages' own requests do by cookie.
const viaTunnel = (url) => !!tunnel && String(url).startsWith(tunnel.origin + '/')
const fetchJson = (url, options = {}) => {
  const away = viaTunnel(url)
  const headers = away ? { ...(options.headers || {}), [p2p.HEADER]: tunnel.run.secret } : options.headers
  return net.fetch(url, { credentials: 'omit', redirect: 'error', signal: AbortSignal.timeout(away ? AWAY_TIMEOUT_MS : STATUS_TIMEOUT_MS), ...options, headers })
}

const postJson = (url, body) =>
  fetchJson(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })

// Has the server at this address proved it holds the key we remember for it?
// `at` is where to ask, when that isn't the address the server is remembered by.
async function identify(url, at = url) {
  const nonce = newNonce()
  try {
    const res = await postJson(at + API + '/identity', { nonce })
    if (res.status === 404) return { state: judgeMissing(url, saved.recent) }
    if (!res.ok) {
      log.warn('network', `The identity check was answered with ${res.status}`, { where: url })
      return { state: 'bad' }
    }
    const answer = await guards.readJson(res)
    const result = judge(answer, nonce, url, saved.recent)
    if (result === 'bad' || result === 'different') log.warn('network', `The server's identity check came back as ${result}`, { where: url })
    if (result === 'bad') return { state: 'bad' }
    return { state: result, serverId: answer.serverId, publicKey: answer.publicKey, fingerprint: fingerprintOf(answer.publicKey) }
  } catch (err) {
    log.noteError('warn', 'network', 'The identity check failed', err, { where: url })
    return { state: 'unreachable', why: guards.whyFailed(err) }
  }
}

// Asks an address whether it is a WittyMediaServer and who it says it is. In the main
// process, so no page's security rules decide the answer and no page sees more than the result.
async function check(url) {
  const away = p2p.isP2POrigin(url)
  const r = away ? { url } : normalizeAddress(url)
  if (r.error) return { error: r.error }
  let entry = entryFor(r.url)
  // A connection to some other server has no business staying open.
  if (tunnel && !(entry && entry.p2p && entry.p2p.id === tunnel.id)) closeTunnel()
  let at = r.url
  let first = away ? { error: 'unreachable' } : await statusOf(at)
  if (first.error === 'unreachable' && entry && entry.p2p) {
    // Not there: this device isn't at home. The other way to it, if it has one.
    const via = await reachFromAway(entry)
    if (via.error) return { error: away ? via.error : 'unreachable' }
    at = via.origin
    entry = via.entry
    first = await statusOf(at)
  }
  if (first.error) return { error: first.error }
  const { data } = first
  const name = entry && away ? entry.url : r.url
  return {
    url: name, at, version: guards.cleanText(data.version, 40), name: guards.cleanName(data.brandName || data.name),
    brandLogo: guards.logoVersion(data.brandLogo), setupRequired: data.setupRequired === true, identity: await identify(name, at),
  }
}

async function statusOf(at) {
  try {
    const res = await fetchJson(at + '/api/status')
    const data = await guards.readJson(res)
    if (!data || data.name !== 'WittyMediaServer') {
      log.info('network', 'Something answered that is not a WittyMediaServer', { where: at })
      return { error: 'not-server' }
    }
    return { data }
  } catch (err) {
    log.noteError('warn', 'network', 'A server could not be reached', err, { where: at })
    return { error: guards.whyFailed(err) }
  }
}

// ---------------------------------------------------------------- from away, peer to peer

const keyFile = () => path.join(app.getPath('userData'), 'p2p-key.json')
const helperProgram = () => p2p.helperPath({ resourcesPath: process.resourcesPath, packaged: INSTALLED })
const entryFor = (url) => (saved.recent || []).find((s) => s.url === url)
const sayPath = (words) => { if (bar && !bar.webContents.isDestroyed()) bar.webContents.send('p2p', words) }

// This device's key, made the first time it is wanted.
async function deviceKey(program) {
  let key = p2p.loadKey(keyFile(), safeStorage)
  if (!key) {
    key = await p2p.makeKey(program)
    p2p.saveKey(keyFile(), safeStorage, key)
  }
  log.addSecret(key.key)
  return key
}

function closeTunnel() {
  if (!tunnel) return
  const { run, origin } = tunnel
  tunnel = null
  run.stop()
  sayPath('')
  session.defaultSession.cookies.remove(origin, p2p.COOKIE).catch(() => {})
}

// What the app keeps about reaching a server from away. null forgets it.
function keepP2P(url, info) {
  const entry = entryFor(url)
  if (!entry) return
  const clean = info ? p2p.cleanInfo(info) : null
  if (JSON.stringify(entry.p2p || null) === JSON.stringify(clean)) return
  if (clean) entry.p2p = clean
  else delete entry.p2p
  saveState()
}

// Starts the helper for a server and waits for its address on this computer.
async function openTunnel(info) {
  closeTunnel()
  const program = helperProgram()
  if (!program) {
    log.warn('p2p', 'The connection helper is not installed with this app')
    return { error: 'p2p-missing' }
  }
  let run, ready
  try {
    const key = await deviceKey(program)
    run = new p2p.Tunnel(program, { key: key.key, serverId: info.id, hints: info.hints || [], port: info.port || 0 }, { log: (line) => log.info('p2p', line) })
    ready = await run.ready
    log.addSecret(ready.secret)
    const origin = p2p.originFor(info.id, ready.port)
    // The secret every request to the helper must carry, where no page's script can read it.
    await session.defaultSession.cookies.set({ url: origin, name: p2p.COOKIE, value: ready.secret, httpOnly: true, sameSite: 'strict' })
    tunnel = { run, id: info.id, origin, port: ready.port, deviceId: ready.deviceId }
  } catch (err) {
    if (run) run.stop()
    log.noteError('warn', 'p2p', 'The connection helper could not start', err)
    return { error: 'p2p-failed' }
  }
  const mine = tunnel
  run.on('state', (s) => { if (tunnel === mine) sayPath(server === mine.origin ? p2p.pathWords(s) : '') })
  run.on('addrs', (hints) => {
    if (tunnel !== mine || !hints.length) return
    const entry = (saved.recent || []).find((s) => s.p2p && s.p2p.id === mine.id)
    if (entry) keepP2P(entry.url, { ...entry.p2p, hints })
  })
  run.on('exit', (code) => {
    if (tunnel !== mine) return
    log.warn('p2p', `The connection helper stopped by itself (${code})`)
    const showing = server === mine.origin
    closeTunnel()
    if (showing) showConnect({ lost: '1' })
  })
  return { ok: true }
}

// Reaches a remembered server the other way, and says where on this computer it answers.
// A server only ever reached like this is remembered by that address, which is renamed
// here if the port it had last time was taken.
async function reachFromAway(entry) {
  if (!(tunnel && tunnel.id === entry.p2p.id)) {
    const opened = await openTunnel(entry.p2p)
    if (opened.error) return opened
  }
  const mine = tunnel
  const st = await mine.run.whenConnected(AWAY_CONNECT_MS)
  if (tunnel !== mine) return { error: 'unreachable' } // given up on meanwhile
  if (!p2p.connected(st)) {
    log.warn('p2p', `The server was not reached from away: ${st.error || st.path}`)
    closeTunnel()
    return { error: 'p2p-failed' }
  }
  if (p2p.isP2POrigin(entry.url) && entry.url !== mine.origin) {
    if (saved.server === entry.url) saved.server = mine.origin
    entry.url = mine.origin
  }
  keepP2P(entry.url, { ...entry.p2p, port: mine.port })
  saveState()
  return { ok: true, origin: mine.origin, entry }
}

// The same server, reached another way, is the same sign-in. Only ever called once the
// server at the far end has proved it holds the key remembered for it.
async function carrySignIn(from, to) {
  if (from === to) return
  const jar = session.defaultSession.cookies
  if ((await jar.get({ url: to, name: SESSION_COOKIE })).length) return
  const [kept] = await jar.get({ url: from, name: SESSION_COOKIE })
  if (!kept) return
  await jar.set({ url: to, name: SESSION_COOKIE, value: kept.value, httpOnly: true, sameSite: 'lax', secure: false, expirationDate: kept.expirationDate || Date.now() / 1000 + SESSION_DAYS * 86400 })
}

// While a server is on screen and signed in: asks whether it takes connections from away,
// puts this device on its list if so, and keeps what is needed to find it again. This is
// how a device that was set up at home works when it leaves, with nothing done by hand.
async function learnP2P() {
  const origin = server
  const program = helperProgram()
  if (!origin || !program) return
  const entry = viaTunnel(origin + '/') ? (saved.recent || []).find((s) => s.p2p && s.p2p.id === tunnel.id) : entryFor(origin)
  if (!entry) return
  try {
    const to = await reportTarget()
    if (!to || to.origin !== origin) return // not signed in yet: asked again later
    const key = await deviceKey(program)
    const auth = { Authorization: `Bearer ${to.token}` }
    const res = await fetchJson(`${origin}${API}/p2p?device=${encodeURIComponent(key.deviceId)}`, { headers: auth })
    if (res.status === 404) { res.body?.cancel().catch(() => {}); return } // an older server
    const info = await guards.readJson(res)
    if (server !== origin) return
    if (!res.ok || !info || info.enabled !== true || !p2p.validId(info.serverId)) {
      if (res.ok && info && info.enabled === false && !viaTunnel(origin + '/')) keepP2P(entry.url, null)
      return
    }
    if (info.enrolled !== true) {
      const added = await fetchJson(`${origin}${API}/p2p/devices`, {
        method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: key.deviceId, name: deviceName(), platform: OS_NAME }),
      })
      added.body?.cancel().catch(() => {})
      if (!added.ok) { log.info('p2p', `The server did not add this device to its list: ${added.status}`, { where: origin }); return }
      log.info('p2p', 'This device can now reach its server from away', { where: origin })
    }
    keepP2P(entry.url, { id: info.serverId, hints: p2p.cleanHints(info.addrs).filter((a) => !a.startsWith('/ip4/127.') && !a.startsWith('/ip6/::1/')), port: entry.p2p && entry.p2p.port })
  } catch (err) {
    log.noteError('info', 'p2p', 'Asking the server about connections from away failed', err, { where: origin })
  }
}

function learnSoon() {
  clearTimeout(learnTimer)
  clearInterval(learnTimer)
  learnTimer = setTimeout(() => {
    learnP2P()
    learnTimer = setInterval(learnP2P, LEARN_EVERY_MS)
  }, LEARN_AFTER_MS)
}

// An invite link, pasted on the connect screen: finds the server, shows it the invite,
// which puts this device on its list, and signs in with the code that comes back.
async function joinByInvite(link) {
  pairing = null
  await finishForgetting()
  const invite = p2p.parseInvite(link)
  if (!invite) return { error: 'invite' }
  const opened = await openTunnel({ id: invite.serverId, hints: invite.hints })
  if (opened.error) return opened
  const mine = tunnel
  const st = await mine.run.whenConnected(AWAY_CONNECT_MS + 15000)
  if (tunnel !== mine) return { error: 'p2p-failed' }
  if (!p2p.connected(st)) { closeTunnel(); return { error: 'p2p-failed' } }
  const answer = await mine.run.enrol(invite.secret, deviceName(), OS_NAME)
  if (tunnel !== mine) return { error: 'p2p-failed' }
  if (!answer.ok) {
    log.warn('p2p', `The invite was refused: ${answer.reason || answer.error}`)
    closeTunnel()
    return { error: 'invite-refused', message: guards.cleanMessage(answer.error) }
  }
  // Who it is, proved: the key it shows now is the one remembered from here on.
  const known = (saved.recent || []).find((s) => s.p2p && s.p2p.id === invite.serverId)
  const name = known ? known.url : mine.origin
  const identity = await identify(name, mine.origin)
  if (!['new', 'same', 'none'].includes(identity.state)) { closeTunnel(); return { error: 'identity' } }
  const info = { id: invite.serverId, hints: invite.hints, port: mine.port }
  const pinned = identity.publicKey && (saved.recent || []).find((s) => s.publicKey === identity.publicKey)
  const url = pinned ? pinned.url : name
  try {
    if (answer.code) {
      const res = await postJson(mine.origin + API + '/pair/redeem', { code: answer.code, device: deviceName(), platform: OS_NAME })
      const data = await guards.readJson(res)
      if (res.ok && data && guards.validToken(data.token)) {
        log.addSecret(data.token)
        await session.defaultSession.cookies.set({
          url: mine.origin, name: SESSION_COOKIE, value: data.token, httpOnly: true, sameSite: 'lax', secure: false,
          expirationDate: Date.now() / 1000 + SESSION_DAYS * 86400,
        })
      } else {
        log.warn('p2p', `The sign-in code that came with the invite was refused: ${res.status}`) // they sign in by hand
      }
    }
  } catch (err) {
    log.noteError('warn', 'p2p', 'Signing in after the invite failed', err)
  }
  saved = state.remember(saved, {
    url, name: guards.cleanName(answer.serverName || invite.name || (pinned && pinned.name)),
    serverId: identity.serverId, publicKey: identity.publicKey, fingerprint: identity.fingerprint, p2p: info, lastSeen: Date.now(),
  })
  saveState()
  showServer(mine.origin)
  return { ok: true }
}

// Takes this device off the server's list, and forgets how to reach it from away.
async function forgetP2P(to) {
  const entry = tunnel ? (saved.recent || []).find((s) => s.p2p && s.p2p.id === tunnel.id) : entryFor(server)
  if (!entry || !entry.p2p) return
  const key = p2p.loadKey(keyFile(), safeStorage)
  keepP2P(entry.url, null)
  if (!to || !key) return
  try {
    const res = await fetchJson(`${to.origin}${API}/p2p/devices/${encodeURIComponent(key.deviceId)}`, { method: 'DELETE', headers: { Authorization: `Bearer ${to.token}` } })
    res.body?.cancel().catch(() => {})
  } catch (err) {
    log.noteError('info', 'p2p', 'This device could not be taken off the server\'s list', err)
  }
}

// What the connect screen gets to know, which it then shows to the person. Whatever the screen
// does next, a code it was showing for someone to approve no longer counts.
async function probe(url) {
  pairing = null
  await finishForgetting() // a server removed a moment ago and chosen again starts from nothing
  const found = await check(url)
  if (found.error) return { error: found.error }
  const { identity } = found
  // What a server says about itself only counts once it has proved who it is.
  const logo = identity.state === 'new' || identity.state === 'same' ? await logoOf(found.url, found.brandLogo, found.at) : null
  shown = { url: found.url, state: identity.state, publicKey: identity.publicKey || '', logo }
  return {
    ok: true, url: found.url, version: found.version, name: found.name, setupRequired: found.setupRequired,
    logo: logo ? logo.data : '', identity: { state: identity.state, fingerprint: identity.fingerprint || '', old: identity.state === 'different' ? oldEntryFor(found.url, identity) : '' },
  }
}

// The remembered server that this one, with another key, is answering in place of.
function oldEntryFor(url, identity) {
  const old = (saved.recent || []).find((s) => s.url === url) || (saved.recent || []).find((s) => s.serverId && s.serverId === identity.serverId)
  return old ? old.url : ''
}

// A server's own logo, fetched here because the connect page loads no pictures from anywhere,
// and kept with the saved server by its version, so it's only fetched again when it changes.
async function logoOf(url, version, at = url) {
  if (!version) return null
  const kept = (saved.recent || []).find((s) => s.url === url && s.logo && s.logo.version === version)
  if (kept) return kept.logo
  try {
    const res = await fetchJson(`${at}/api/branding/logo?v=${encodeURIComponent(version)}`)
    const type = guards.logoType(res.headers.get('content-type'))
    if (!res.ok || !type) {
      res.body?.cancel().catch(() => {})
      log.info('network', `The server's logo was answered with ${res.status} ${type || 'and no picture'}`, { where: url })
      return null
    }
    const bytes = await guards.readBytes(res, guards.MAX_LOGO_BYTES)
    return { version, data: `data:${type};base64,${bytes.toString('base64')}` }
  } catch (err) {
    log.noteError('info', 'network', "The server's logo could not be fetched", err, { where: url })
    return null
  }
}

// The logo the person was shown with this server, to keep with it.
const shownLogo = (url) => (shown && shown.url === url ? shown.logo : undefined)

// Asks the server again, and holds the answer to what the person was shown.
async function admitted(url, trust) {
  const found = await check(url)
  if (found.error) return found
  const verdict = admit(found.url, found.identity, shown, trust)
  if (verdict === 'ok') return found
  log.warn('network', `A server was not let in: ${verdict}`, { where: found.url })
  return { error: { changed: 'changed', refused: 'identity', unreachable: 'unreachable' }[verdict] }
}

// Sign-ins made for the old key must never reach whoever holds the new one.
async function forgetSignIn(url) {
  const { origin } = new URL(url)
  await session.defaultSession.cookies.remove(origin, SESSION_COOKIE)
  await session.defaultSession.clearStorageData({ origin, storages: ['cookies', 'localstorage'] })
}

// `at` is where it is reached, when that isn't the address it is remembered by: a sign-in
// kept for either goes when it no longer fits, and one that fits is good at both.
async function dropUnfitSignIn(url, identity, at = url) {
  if (!signInFits(url, identity, saved.recent)) {
    await forgetSignIn(url)
    if (at !== url) await session.defaultSession.cookies.remove(at, SESSION_COOKIE)
  } else if (at !== url) {
    await carrySignIn(url, at)
  }
}

// The server has just proved who it is: that is when it was last reached. One that proves a key
// remembered at another address is the same server, moved: its entry follows it, its sign-in
// comes along, and nothing is left behind at the old address.
async function rememberServer(url, name, identity, logo) {
  const now = { url, serverId: identity.serverId, publicKey: identity.publicKey }
  const moved = (saved.recent || []).filter((s) => s.url !== url && servers.sameServer(s, now))
  saved = state.remember(saved, { url, name, serverId: identity.serverId, publicKey: identity.publicKey, fingerprint: identity.fingerprint, logo, lastSeen: Date.now() })
  saveState()
  for (const old of moved) {
    try {
      if (old.publicKey && old.publicKey === identity.publicKey) await carrySignIn(old.url, url)
      await clearOrigin(old.url, !(saved.recent || []).some((s) => new URL(s.url).hostname === new URL(old.url).hostname))
      log.info('app', 'A remembered server answered at a new address, and its entry moved with it', { where: url })
    } catch (err) {
      log.noteError('warn', 'app', 'What was kept for a server\'s old address could not be cleared', err, { where: old.url })
    }
  }
}

// ---------------------------------------------------------------- forgetting servers

// How long a removal can be taken back. Until then nothing but the list has changed.
const UNDO_MS = 8000
let undoable = null // { taken, timer }: the removal that Undo would put back
let finishing = Promise.resolve()

// Everything the browser session holds for one address: storage, service workers and cache, and
// its cookies, unless another remembered server on the same machine shares them (servers.js).
const STORAGES = ['filesystem', 'indexdb', 'localstorage', 'shadercache', 'websql', 'serviceworkers', 'cachestorage']
const DATA_TYPES = ['cache', 'cacheStorage', 'fileSystems', 'indexedDB', 'localStorage', 'serviceWorkers', 'webSQL', 'backgroundFetch']
async function clearOrigin(origin, cookies = true) {
  const ses = session.defaultSession
  if (cookies) for (const cookie of await ses.cookies.get({ url: origin })) await ses.cookies.remove(origin, cookie.name)
  await ses.clearStorageData({ origin, storages: STORAGES })
  // The HTTP cache for that address too, where this Electron can clear it for one address.
  if (typeof ses.clearData === 'function') await ses.clearData({ origins: [origin], dataTypes: DATA_TYPES }).catch(() => {})
}

const forgetDeps = {
  p2pOrigin: p2p.originFor,
  clearOrigin,
  tokenAt: async (origin) => {
    const [kept] = await session.defaultSession.cookies.get({ url: origin, name: SESSION_COOKIE })
    return kept ? kept.value : ''
  },
  signOut: async (origin, token) => {
    const res = await fetchJson(origin + API + '/logout', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: '{}', signal: AbortSignal.timeout(servers.SIGN_OUT_TIMEOUT_MS),
    })
    res.body?.cancel().catch(() => {})
  },
  revokeDevice: async (origin, token) => {
    const key = p2p.loadKey(keyFile(), safeStorage)
    if (!key) return
    const res = await fetchJson(`${origin}${API}/p2p/devices/${encodeURIComponent(key.deviceId)}`, {
      method: 'DELETE', headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(servers.SIGN_OUT_TIMEOUT_MS),
    })
    res.body?.cancel().catch(() => {})
  },
  closeTunnel: (id) => { if (tunnel && tunnel.id === id) closeTunnel() },
  forgetDeviceKey: () => p2p.forgetKey(keyFile()),
}

// Takes servers off the list. What is kept for them goes when the time to undo is over, when
// anything is connected to, or the next time the app starts, whichever is first.
function forgetServers(urls) {
  const wanted = (Array.isArray(urls) ? urls : []).filter((u) => typeof u === 'string').slice(0, state.MAX_RECENT)
  finishForgetting() // an earlier removal can no longer be undone
  const { state: next, taken } = servers.takeOut(saved, wanted)
  if (!taken.length) return { ok: true, removed: [] }
  saved = next
  // The server in use went with them: the app no longer opens it, unless Undo puts it back.
  const inUse = saved.server && taken.some((t) => servers.originsOf(t.entry, p2p.originFor).includes(new URL(saved.server).origin) || t.entry.url === saved.server) ? saved.server : ''
  if (inUse) saved.server = ''
  saveState()
  log.info('app', `${taken.length === 1 ? 'A server was' : `${taken.length} servers were`} removed from this computer${inUse ? ', the one in use among them' : ''}`)
  undoable = { taken, inUse, timer: setTimeout(finishForgetting, UNDO_MS) }
  return { ok: true, removed: taken.map((t) => t.entry.url), undoMs: UNDO_MS }
}

function undoForget() {
  if (!undoable) return { ok: false }
  clearTimeout(undoable.timer)
  saved = servers.putBack(saved, undoable.taken)
  if (undoable.inUse && !saved.server) saved.server = undoable.inUse
  undoable = null
  saveState()
  return { ok: true }
}

// One at a time, each after the last, and answers when nothing is left waiting.
function finishForgetting() {
  if (undoable) clearTimeout(undoable.timer)
  undoable = null
  // Only what is waiting now: a removal made after this one keeps its own time to be undone.
  const batch = [...(saved.forgetting || [])]
  finishing = finishing.then(async () => {
    for (const entry of batch) {
      if (!(saved.forgetting || []).includes(entry)) continue
      try {
        const done = await servers.forget(entry, saved.recent, forgetDeps)
        if (done.failed.length) log.warn('app', 'Some of what was kept for a removed server could not be cleared', { where: entry.url })
      } catch (err) {
        log.noteError('warn', 'app', 'A removed server could not be forgotten completely', err, { where: entry.url })
      }
      const left = (saved.forgetting || []).filter((s) => s !== entry)
      if (left.length) saved.forgetting = left
      else delete saved.forgetting
      saveState()
    }
  })
  return finishing
}

// A list that had one server twice was made one entry each when it was read: what was kept for
// the addresses that went has no entry to belong to any more.
async function clearMergedAway() {
  for (const url of saved.merged || []) {
    if ((saved.recent || []).some((s) => servers.originsOf(s, p2p.originFor).includes(url))) continue
    await clearOrigin(url, !(saved.recent || []).some((s) => new URL(s.url).hostname === new URL(url).hostname)).catch((err) => log.noteError('warn', 'app', 'What was kept for a duplicate entry could not be cleared', err, { where: url }))
  }
  if ((saved.merged || []).length) {
    log.info('app', `The list of servers had the same server more than once: ${saved.merged.length} duplicate entries were merged`)
    saveState()
  }
}

const dayOf = (s, now) => servers.daysSince(s, now)
function recentForPage() {
  const now = Date.now()
  return (saved.recent || []).map((s) => ({
    url: s.url, name: s.name, logo: s.logo ? s.logo.data : '', id: s.serverId || '', days: dayOf(s, now), stale: servers.isStale(s, now),
  }))
}

// Goes to a server someone chose, without a code: they sign in on its own page.
async function openServer(request) {
  pairing = null
  const found = await admitted(String(request && request.url), request && request.trust === true)
  if (found.error) return { error: found.error }
  try {
    await dropUnfitSignIn(found.url, found.identity, found.at)
  } catch (err) {
    log.noteError('warn', 'app', 'An old sign-in could not be forgotten', err, { where: found.url })
    return { error: 'identity' }
  }
  await rememberServer(found.url, found.name, found.identity, shownLogo(found.url))
  showServer(found.at)
  return { ok: true }
}

// A code typed on this device. The sign-in goes straight into the browser
// session as the server's own HttpOnly cookie, so no page script can read it.
async function redeem(url, code) {
  pairing = null
  if (!guards.validCode(code)) return { error: 'invalid' }
  const found = await admitted(url, false)
  if (found.error) return { error: found.error }
  let res, answer
  try {
    res = await postJson(found.at + API + '/pair/redeem', {
      code, device: `${os.hostname()} (WittyMediaClient)`.slice(0, 60), platform: OS_NAME,
    })
    answer = await guards.readJson(res)
  } catch (err) {
    log.noteError('warn', 'network', 'Signing in with a code failed', err, { where: found.url })
    return { error: guards.whyFailed(err) === 'certificate' ? 'certificate' : 'unreachable' }
  }
  const data = answer && typeof answer === 'object' ? answer : {}
  if (!res.ok || !guards.validToken(data.token)) {
    log.warn('network', `Signing in with a code was refused: ${res.status} ${guards.cleanMessage(data.reason)}`, { where: found.url })
    return { message: guards.cleanMessage(data.error), reason: guards.cleanMessage(data.reason) }
  }
  return keepSignIn(found, data.token)
}

async function keepSignIn(found, token) {
  log.addSecret(token)
  try {
    await dropUnfitSignIn(found.url, found.identity, found.at)
    await session.defaultSession.cookies.set({
      url: found.at, name: SESSION_COOKIE, value: token, httpOnly: true, sameSite: 'lax',
      secure: found.at.startsWith('https:'), expirationDate: Date.now() / 1000 + SESSION_DAYS * 86400,
    })
  } catch (err) {
    log.noteError('error', 'app', 'The sign-in could not be kept', err, { where: found.url })
    return { error: 'unreachable' }
  }
  await rememberServer(found.url, found.name, found.identity, shownLogo(found.url))
  showServer(found.at)
  return { ok: true }
}

const deviceName = () => `${os.hostname()} (WittyMediaClient)`.slice(0, 60)

// A code shown on this screen, which someone already signed in approves on a phone or a computer:
// docs/CLIENT-API.md in the server's repository. The page gets the code and the address to show;
// the secret that collects the sign-in never leaves this process.
async function pairStart(url) {
  pairing = null
  const found = await admitted(url, false)
  if (found.error) return { error: found.error }
  let res, answer
  try {
    res = await postJson(found.at + API + '/pair/start', { device: deviceName(), platform: OS_NAME })
    answer = await guards.readJson(res)
  } catch (err) {
    log.noteError('warn', 'network', 'Asking for a code to show failed', err, { where: found.url })
    return { error: guards.whyFailed(err) === 'certificate' ? 'certificate' : 'unreachable' }
  }
  const data = answer && typeof answer === 'object' ? answer : {}
  if (!res.ok || !guards.validPairCode(data.code) || !guards.validDeviceSecret(data.deviceSecret)) {
    log.warn('network', `Asking for a code to show was refused: ${res.status}`, { where: found.url })
    return { message: guards.cleanMessage(data.error) }
  }
  pairing = { url: found.url, at: found.at, secret: data.deviceSecret }
  return {
    ok: true, code: data.code, intervalSec: guards.pollSeconds(data.intervalSec),
    approveAt: guards.serverPage(found.url, data.approvePath, '/pair'),
    scan: guards.serverPage(found.url, data.approveUrl, `/pair?code=${encodeURIComponent(data.code)}`),
  }
}

// Has someone approved the code? Approved, the sign-in is kept as a typed code's is.
async function pairPoll() {
  const asked = pairing
  if (!asked) return { status: 'expired' }
  let res, answer
  try {
    res = await postJson(asked.at + API + '/pair/poll', { deviceSecret: asked.secret })
    answer = await guards.readJson(res)
  } catch (err) {
    log.noteError('info', 'network', 'Asking whether a code was approved failed', err, { where: asked.url })
    return { status: 'lost' }
  }
  // The screen moved on while this was asked: whatever the answer, it isn't wanted now.
  if (pairing !== asked) return { status: 'expired' }
  const data = answer && typeof answer === 'object' ? answer : {}
  if (data.status === 'pending' || data.status === 'slow-down') return { status: data.status, intervalSec: guards.pollSeconds(data.intervalSec, 0) }
  pairing = null
  if (data.status === 'denied') return { status: 'denied' }
  if (data.status !== 'approved' || !res.ok || !guards.validToken(data.token)) {
    if (data.status === 'approved') log.warn('network', 'A code was approved, but the sign-in that came with it was not one', { where: asked.url })
    return { status: 'expired' }
  }
  const found = await admitted(asked.url, false)
  if (found.error) return { error: found.error }
  return keepSignIn(found, data.token)
}

// Leaving a server leaves no valid sign-in behind, on this computer or on the server.
// The cookie goes first and at once, so nothing that happens next can reach it.
async function leaveServer() {
  const to = await reportTarget().catch(() => null)
  const origin = server
  await forgetP2P(to)
  saved.server = ''
  saveState()
  if (origin) await forgetSignIn(origin).catch((err) => log.noteError('warn', 'app', 'The sign-in could not be forgotten', err, { where: origin }))
  showConnect()
  if (!to) { closeTunnel(); return }
  try {
    const res = await fetchJson(to.origin + API + '/logout', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${to.token}` }, body: '{}' })
    res.body?.cancel().catch(() => {})
    if (!res.ok) log.info('network', `Ending the session was answered with ${res.status}`, { where: to.origin })
  } catch (err) {
    log.noteError('info', 'network', 'The session on the server could not be ended', err, { where: to.origin })
  }
  closeTunnel()
}

// ---------------------------------------------------------------- managing servers

// The list of remembered servers, opened from the menu while a server is in use. Nothing is
// left: the sign-in stays, and Back returns to the server. The one in use can be removed from
// here too (it is then signed out, after the time to undo); the list says which it is.
let managing = ''
function manageServers() {
  if (!saved.server) { if (!server) showConnect(); return }
  managing = saved.server
  showConnect({ manage: '1' })
}

// Back from the list to the server in use, if it is still remembered.
function backFromManaging() {
  const url = managing
  managing = ''
  if (url && saved.server === url) return startUp()
  return showConnect()
}

// What the list shows about the server in use while managing: its address, or '' for none.
const managedNow = () => (managing && saved.server === managing ? managing : '')

// What the last run was using, if it still is who it was.
async function startUp() {
  await clearMergedAway()
  await finishForgetting() // removals the last run didn't get to finish
  const url = saved.server && (p2p.isP2POrigin(saved.server) || !normalizeAddress(saved.server).error) ? saved.server : ''
  if (!url) return showConnect()
  const entry = entryFor(url)
  let at = url
  let identity = p2p.isP2POrigin(url) ? { state: 'unreachable' } : await identify(url)
  if (identity.state === 'unreachable' && identity.why !== 'certificate' && entry && entry.p2p) {
    // Not at home: the other way, with something on screen to say so while it is found.
    showConnect({ away: '1' })
    awayGivenUp = false
    const via = await reachFromAway(entry)
    if (awayGivenUp) return undefined // they are choosing something else by now
    if (via.error) return showConnect({ 'away-failed': '1' })
    at = via.origin
    identity = await identify(via.entry.url, at)
    if (tunnel === null || tunnel.origin !== at) return undefined // given up on while it was asked
    if (identity.state !== 'same' && !(identity.state === 'none' && !via.entry.publicKey)) {
      closeTunnel()
      return showConnect(identity.state === 'unreachable' ? { 'away-failed': '1' } : { mismatch: via.entry.url })
    }
    await dropUnfitSignIn(via.entry.url, identity, at)
    return showServer(at)
  }
  if (identity.state === 'unreachable') return showConnect(identity.why === 'certificate' ? { certificate: '1' } : { lost: '1' })
  if (identity.state === 'different' || identity.state === 'bad') return showConnect({ mismatch: url })
  await dropUnfitSignIn(url, identity)
  if (identity.state !== 'none') {
    const known = (saved.recent || []).find((s) => s.url === url)
    await rememberServer(url, known ? known.name : 'WittyMediaServer', identity)
  }
  return showServer(at)
}

function guardContent(wc) {
  wc.setWindowOpenHandler(({ url }) => { openOutside(url); return { action: 'deny' } })
  // The app's own loads don't come through will-navigate, so this is only ever a page asking.
  const stay = (redirect) => (e, url) => {
    const next = guards.navigation(url, { server, lastServer, redirect })
    if (next === 'allow') return
    e.preventDefault()
    if (next === 'outside') openOutside(url)
  }
  wc.on('will-navigate', stay(false))
  wc.on('will-redirect', stay(true))
  wc.on('will-attach-webview', (e) => e.preventDefault())
  // A server that can't be reached goes back to the connect screen and says so.
  wc.on('did-fail-load', (_e, code, desc, url, isMainFrame) => {
    if (!isMainFrame || code === -3) return
    log.warn('network', `A page failed to load: ${desc} (${code})`, { where: url })
    if (server) showConnect(guards.isCertificateCode(code) ? { certificate: '1' } : { lost: '1' })
  })
  wc.on('enter-html-full-screen', () => { htmlFullScreen = true; layout() })
  wc.on('leave-html-full-screen', () => { htmlFullScreen = false; layout() })
  wc.on('did-finish-load', () => {
    if (startedAfresh) wc.navigationHistory.clear()
    startedAfresh = false
    wc.focus()
  })
  keepPlaying(wc)
}

// What plays keeps playing when the window is hidden, minimised or covered (see playback.js). Kept
// awake, the page isn't throttled, so it never learns it's out of sight and pauses, and the system
// isn't allowed to suspend the app; the screen may still turn off.
let awakeBlocker = null
const awake = playback.create({
  apply(on) {
    if (!content || content.webContents.isDestroyed()) return
    content.webContents.setBackgroundThrottling(!on)
    if (on && awakeBlocker === null) awakeBlocker = powerSaveBlocker.start('prevent-app-suspension')
    if (!on && awakeBlocker !== null) {
      powerSaveBlocker.stop(awakeBlocker)
      awakeBlocker = null
    }
    log.info('app', on ? 'Something is playing: kept running in the background' : 'Nothing playing: the page may be slowed in the background')
  },
})

function keepPlaying(wc) {
  wc.on('media-started-playing', () => awake.playing(true))
  wc.on('media-paused', () => awake.playing(false))
  wc.on('audio-state-changed', (e) => awake.audible(e.audible))
  // A new page starts from nothing; moving around inside the server's own page doesn't.
  wc.on('did-start-navigation', (details) => { if (details.isMainFrame && !details.isSameDocument) awake.reset() })
  wc.on('render-process-gone', () => awake.reset())
}

// The app's own pages, from inside its package. No page needs anything from file://, so it
// has no special standing here, and a page on the app's own scheme can only reach these.
function servePages() {
  protocol.handle(guards.PAGE_SCHEME, async (request) => {
    const page = guards.pageFile(request.url)
    if (!page) return new Response('', { status: 404 })
    try {
      const body = await fs.promises.readFile(path.join(__dirname, page.folder, page.name))
      return new Response(body, {
        headers: { 'Content-Type': page.type, 'Content-Security-Policy': "frame-ancestors 'none'", 'X-Content-Type-Options': 'nosniff', 'Cache-Control': 'no-store' },
      })
    } catch {
      return new Response('', { status: 404 })
    }
  })
}

// The Mac's menu bar, which is where the title bar's Help is on a Mac.
function macMenu() {
  return Menu.buildFromTemplate(mac.menu({
    connected: Boolean(server), changeServer: () => leaveServer(), manageServers, zoom: zoomPage, openLogs, copyDiagnostics,
  }))
}

function updateMenu() {
  const item = MAC && Menu.getApplicationMenu() && Menu.getApplicationMenu().getMenuItemById('change-server')
  if (item) item.enabled = Boolean(server)
}

// In half steps, as Electron's own menu does. Nought is back to normal.
function zoomPage(step) {
  const wc = content.webContents
  wc.setZoomLevel(step ? wc.getZoomLevel() + step / 2 : 0)
}

// A double-click on the title bar does what the Mac is set to do. The system can answer it
// itself, so the app only does it if, a moment later, the window hasn't changed.
function titleDoubleClicked() {
  const action = mac.doubleClickAction(systemPreferences.getUserDefault('AppleActionOnDoubleClick', 'string'))
  if (action === 'none') return
  const look = () => ({ bounds: win.getBounds(), minimized: win.isMinimized() })
  const before = look()
  setTimeout(() => {
    if (win.isDestroyed() || mac.windowChanged(before, look())) return
    if (action === 'minimize') win.minimize()
    else if (win.isMaximized()) win.unmaximize()
    else win.maximize()
  }, mac.SETTLE_MS)
}

function createWindow() {
  const size = saved.window || {}
  // On a Mac the window keeps the system's buttons, over the left of the app's own title bar.
  const frame = MAC ? { titleBarStyle: 'hidden', trafficLightPosition: mac.windowButtonsAt(TITLE_BAR) } : { frame: false }
  win = new BaseWindow({
    width: size.width || 1280, height: size.height || 800, minWidth: 480, minHeight: 360, fullscreen: TV,
    ...frame, backgroundColor: '#0f1115', title: 'WittyMediaClient', show: true,
  })
  win.setMenu(null)

  secure = {
    contextIsolation: true, sandbox: true, nodeIntegration: false, nodeIntegrationInSubFrames: false, webSecurity: true, webviewTag: false,
    spellcheck: false, safeDialogs: true, devTools: !INSTALLED,
  }
  bar = new WebContentsView({ webPreferences: { ...secure, preload: path.join(__dirname, 'titlebar', 'preload.js') } })
  content = new WebContentsView({ webPreferences: { ...secure, preload: path.join(__dirname, 'preload.js'), autoplayPolicy: 'no-user-gesture-required', additionalArguments: TV ? ['--wittymedia-tv'] : [] } })
  // Before a page is ready, or while a server answers, a view is white unless told otherwise.
  bar.setBackgroundColor(BACKGROUND)
  content.setBackgroundColor(BACKGROUND)
  win.contentView.addChildView(bar)
  win.contentView.addChildView(content)
  guardContent(content.webContents)
  watchContents(content.webContents, 'page', () => showConnect(server ? { lost: '1' } : undefined))
  watchContents(bar.webContents, 'title bar', () => { quietly(bar.webContents.loadURL(BAR_PAGE)) })
  bar.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  bar.webContents.on('will-navigate', (e) => e.preventDefault())
  // The bar is a separate page, so Tab never reaches it from the one below. F6 does,
  // as it moves between panes in most programs. Nothing on a page can take it away.
  content.webContents.on('before-input-event', (e, input) => {
    if (!isF6(input) || !bar.getVisible()) return
    e.preventDefault()
    bar.webContents.focus()
    bar.webContents.send('focus-bar')
  })
  bar.webContents.on('before-input-event', (e, input) => {
    if (!isF6(input)) return
    e.preventDefault()
    content.webContents.focus()
  })

  layout()
  win.on('resize', () => {
    layout()
    // The size to come back to: not the whole screen, if that's what it is now.
    const { width, height } = win.getNormalBounds()
    saved.window = { width, height }
  })
  win.on('enter-full-screen', layout)
  win.on('leave-full-screen', layout)
  win.on('maximize', () => bar.webContents.send('maximized', true))
  win.on('unmaximize', () => bar.webContents.send('maximized', false))
  // The title fades with the system's buttons when another window is in front.
  if (MAC) {
    win.on('focus', () => bar.webContents.send('active', true))
    win.on('blur', () => bar.webContents.send('active', false))
  }
  win.on('closed', () => { endDiscovery(); saveState(); app.quit() })

  bar.webContents.loadURL(BAR_PAGE).then(startUp).catch((err) => {
    log.noteError('error', 'crash', 'The window could not be got ready', err, { page: 'main process' })
    showConnect()
  })
}

ipcMain.handle('probe', (e, url) => (fromConnect(e) ? probe(String(url)) : { error: 'invalid' }))
ipcMain.handle('recent', (e) => (fromConnect(e) ? recentForPage() : []))
ipcMain.handle('forget', (e, urls) => (fromConnect(e) ? forgetServers(urls) : { ok: false }))
ipcMain.handle('forget-undo', (e) => (fromConnect(e) ? undoForget() : { ok: false }))
// Opened from the menu while a server is in use: which one, and the way back to it.
ipcMain.handle('managing', (e) => (fromConnect(e) ? { url: managedNow() } : { url: '' }))
ipcMain.on('manage-back', (e) => { if (fromConnect(e)) backFromManaging() })
// The undo on screen has gone, or the person said yes to a question that had no undo.
ipcMain.handle('forget-finish', async (e) => { if (fromConnect(e)) await finishForgetting(); return { ok: true } })
// Right-click on a remembered server. The page does the removing, as it does for its own button.
ipcMain.on('server-menu', (e, url, at) => {
  if (!fromConnect(e) || !entryFor(String(url))) return
  const page = e.sender
  const { width, height } = win.getContentBounds()
  const point = guards.menuPoint(at, width, height)
  Menu.buildFromTemplate([
    { label: 'Remove this server', click: () => { if (!page.isDestroyed()) page.send('forget-ask', String(url)) } },
  ]).popup({ window: win, ...(point.x === undefined ? {} : { x: point.x, y: point.y + (bar.getVisible() ? TITLE_BAR : 0) }) })
})
ipcMain.handle('redeem', (e, url, code) => (fromConnect(e) ? redeem(String(url), String(code)) : { error: 'invalid' }))
ipcMain.handle('open-server', (e, request) => (fromConnect(e) ? openServer(request) : { error: 'invalid' }))
ipcMain.handle('pair-start', (e, url) => (fromConnect(e) ? pairStart(String(url)) : { error: 'invalid' }))
ipcMain.handle('pair-poll', (e) => (fromConnect(e) ? pairPoll() : { status: 'expired' }))
ipcMain.on('pair-stop', (e) => { if (fromConnect(e)) pairing = null })
ipcMain.handle('p2p-invite', (e, link) => (fromConnect(e) ? joinByInvite(String(link).slice(0, 4096)) : { error: 'invite' }))
// Giving up on a server being reached from away: whatever comes of it isn't wanted now.
ipcMain.on('p2p-stop', (e) => { if (fromConnect(e)) { awayGivenUp = true; closeTunnel() } })

ipcMain.on('discover-start', (e) => {
  if (!fromConnect(e)) return
  endDiscovery()
  const page = e.sender
  stopDiscovery = startDiscovery((servers) => { if (!page.isDestroyed()) page.send('servers', servers) })
})

ipcMain.on('open-logs', (e) => { if (fromConnect(e)) openLogs() })

// The website's "Keep playing when this tab is in the background": false only when it's turned off.
ipcMain.on('background-play', (e, on) => { if (fromServerPage(e)) awake.allowed(on !== false) })

// Theme colours from the server's page: checked strictly, since a page decides them.
ipcMain.on('theme', (e, t) => {
  if (!fromServerPage(e) || !t) return
  const ok = (c) => typeof c === 'string' && COLOUR.test(c)
  // A hairline in a form this check doesn't know mustn't stop the rest applying.
  if (!ok(t.bg) || !ok(t.fg)) return
  const theme = { bg: t.bg, fg: t.fg, border: ok(t.border) ? t.border : 'transparent' }
  bar.webContents.send('theme', theme)
  if (tvMenu) tvMenu.webContents.send('theme', theme)
})

// A game on someone's own PC, handed to the Moonlight app. The page gets a yes or a no.
ipcMain.handle('moonlight-status', (e) => (fromServerPage(e) ? moonlight.status() : { installed: false }))
ipcMain.handle('moonlight-launch', (e, args) => (fromServerPage(e) ? launchMoonlight(args) : { ok: false, error: moonlight.REFUSED }))

ipcMain.on('window', (e, action, at) => {
  if (!fromBar(e)) return
  if (action === 'minimize') win.minimize()
  else if (action === 'maximize') { if (win.isMaximized()) win.unmaximize(); else win.maximize() }
  else if (action === 'close') win.close()
  else if (action === 'change-server') leaveServer()
  else if (action === 'help') showHelpMenu(at)
  else if (action === 'double-click' && MAC) titleDoubleClicked()
  else if (action === 'focus-page') content.webContents.focus()
})

// Back on a TV: Escape that the page didn't use goes back, and with nowhere to go it's the menu.
ipcMain.on('tv-back', (e, stepBack) => {
  if (!TV || !(fromConnect(e) || fromServerPage(e))) return
  const { navigationHistory } = content.webContents
  if (!navigationHistory.canGoBack()) openTvMenu()
  else if (stepBack === true) navigationHistory.goBack()
})

ipcMain.on('tv-menu', (e, action) => {
  if (!TV || !tvMenu || e.sender !== tvMenu.webContents) return
  if (action === 'close') closeTvMenu()
  else if (action === 'change-server') { closeTvMenu(); leaveServer() }
  else if (action === 'manage-servers') { closeTvMenu(); manageServers() }
  else if (action === 'quit') win.close()
})

// Every page gets the sandbox, whatever made it. The default menu's shortcuts aren't for this app,
// and a Mac gets its own once the app is ready.
app.enableSandbox()
if (TV && process.platform !== 'win32' && process.platform !== 'darwin') for (const [name, value] of tv.switches(process.env)) app.commandLine.appendSwitch(name, value)
Menu.setApplicationMenu(null)
protocol.registerSchemesAsPrivileged([{ scheme: guards.PAGE_SCHEME, privileges: { standard: true, secure: true } }])

// One window only: a second launch brings the first to the front.
if (!app.requestSingleInstanceLock()) app.quit()
else {
  app.on('second-instance', () => {
    if (!win || win.isDestroyed()) return
    if (win.isMinimized()) win.restore()
    win.focus()
  })
  log.info('app', `Started, version ${app.getVersion()}, ${DEVICE}`)
  // Listening doesn't change the answer: without preventDefault a bad certificate stays refused.
  app.on('certificate-error', (_e, _wc, url, error, _cert, _done, isMainFrame) => {
    log.warn('network', `A certificate was refused: ${error}${isMainFrame ? ', for the page itself' : ''}`, { where: url })
  })
  // Left alone, Electron answers a request for a client certificate with the first one it
  // finds, which tells a server who someone is. Nothing here uses them, so it gets none.
  app.on('select-client-certificate', (e, _wc, url, _list, done) => {
    e.preventDefault()
    log.warn('network', 'A server asked for a client certificate and got none', { where: url })
    done(null)
  })
  app.on('child-process-gone', (_e, details) => {
    if (details.reason === 'clean-exit') return
    log.error('crash', `A ${details.type} process stopped: ${details.reason}, exit code ${details.exitCode}${details.name ? `, ${details.name}` : ''}`, { page: 'main process' })
  })
  app.whenReady().then(() => {
    saved = state.load(stateFile())
    servePages()
    // The spell checker can fetch dictionaries from a third party. Nothing here uses it. Turning
    // it off isn't enough to stop that: it still fetches for the languages it has.
    session.defaultSession.setSpellCheckerEnabled(false)
    if (process.platform !== 'darwin') session.defaultSession.setSpellCheckerLanguages([])
    // Pages may go fullscreen and copy text, and the server's own may lock the mouse for a
    // game. Camera, location and the rest stay off. WebRTC to receive a stream and the
    // Gamepad API don't ask for anything.
    const allowed = (perm, url) => moonlight.permissionAllowed(perm, url, server)
    session.defaultSession.setPermissionRequestHandler((_wc, perm, done, details) => done(allowed(perm, details.requestingUrl)))
    session.defaultSession.setPermissionCheckHandler((_wc, perm, origin) => allowed(perm, origin))
    // Someone signed in through the server's page: reports waiting can go now.
    session.defaultSession.cookies.on('changed', (_e, cookie, _cause, removed) => { if (!removed && cookie.name === SESSION_COOKIE) log.kick() })
    // A server's page can save what the server sends. Nothing else can ask for a save.
    const maySave = guards.budget()
    session.defaultSession.on('will-download', (e, item) => {
      if (guards.downloadAllowed(item.getURL(), server) && maySave()) return
      e.preventDefault()
      log.warn('network', 'A download was refused', { where: item.getURL().slice(0, 200) })
    })
    createWindow()
    // Waking up is often waking up somewhere else: a connection from away is looked at again.
    powerMonitor.on('resume', () => { if (tunnel) tunnel.run.networkChanged() })
    if (MAC) Menu.setApplicationMenu(macMenu())
  }).catch((err) => {
    // There's no window and never will be, and an app with none can't be closed.
    log.noteError('error', 'crash', 'The app could not start', err, { page: 'main process' })
    log.drainSync()
    app.exit(1)
  })
  app.on('window-all-closed', () => app.quit())
  app.on('before-quit', () => { closeTunnel(); log.flush() }) // one last try, which may not finish
  app.on('will-quit', () => log.drainSync())
}
