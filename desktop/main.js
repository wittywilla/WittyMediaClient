// WittyMediaClient for Windows, macOS, Linux and FreeBSD: a window with two views, and no
// title bar of the system's. Ours is a local page, which on a Mac has the system's buttons on
// it. Below it, the content view shows the connect screen and then the server's web UI, which
// has no access to Node or to the app beyond reporting its theme colours and asking for Moonlight.
const { app, BaseWindow, Menu, WebContentsView, clipboard, ipcMain, net, powerSaveBlocker, protocol, session, shell, systemPreferences } = require('electron')
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
const tv = require('./tv.js')
const playback = require('./playback.js')
const mac = require('./mac.js')

const TITLE_BAR = 32
const CONNECT_PAGE = guards.CONNECT_PAGE
const BAR_PAGE = guards.BAR_PAGE
const TV_MENU_PAGE = guards.TV_MENU_PAGE
const STATUS_TIMEOUT_MS = 5000
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
let pairing = null // a code on show for someone to approve: { url, secret }, and the secret stays here

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
  server = new URL(url).origin
  lastServer = server
  shown = null
  pairing = null
  startedAfresh = true
  bar.webContents.send('server', url)
  updateMenu()
  quietly(content.webContents.loadURL(TV ? tv.tenFootAddress(url) : url))
  log.kick()
}

function saveState() {
  if (!state.save(stateFile(), saved)) log.warn('app', 'What the app remembers could not be saved')
}

const fetchJson = (url, options) =>
  net.fetch(url, { credentials: 'omit', redirect: 'error', signal: AbortSignal.timeout(STATUS_TIMEOUT_MS), ...options })

const postJson = (url, body) =>
  fetchJson(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })

// Has the server at this address proved it holds the key we remember for it?
async function identify(url) {
  const nonce = newNonce()
  try {
    const res = await postJson(url + API + '/identity', { nonce })
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
  const r = normalizeAddress(url)
  if (r.error) return { error: r.error }
  try {
    const res = await fetchJson(r.url + '/api/status')
    const data = await guards.readJson(res)
    if (!data || data.name !== 'WittyMediaServer') {
      log.info('network', 'Something answered that is not a WittyMediaServer', { where: r.url })
      return { error: 'not-server' }
    }
    return {
      url: r.url, version: guards.cleanText(data.version, 40), name: guards.cleanName(data.brandName || data.name),
      brandLogo: guards.logoVersion(data.brandLogo), setupRequired: data.setupRequired === true, identity: await identify(r.url),
    }
  } catch (err) {
    log.noteError('warn', 'network', 'A server could not be reached', err, { where: r.url })
    return { error: guards.whyFailed(err) }
  }
}

// What the connect screen gets to know, which it then shows to the person. Whatever the screen
// does next, a code it was showing for someone to approve no longer counts.
async function probe(url) {
  pairing = null
  const found = await check(url)
  if (found.error) return { error: found.error }
  const { identity } = found
  // What a server says about itself only counts once it has proved who it is.
  const logo = identity.state === 'new' || identity.state === 'same' ? await logoOf(found.url, found.brandLogo) : null
  shown = { url: found.url, state: identity.state, publicKey: identity.publicKey || '', logo }
  return {
    ok: true, url: found.url, version: found.version, name: found.name, setupRequired: found.setupRequired,
    logo: logo ? logo.data : '', identity: { state: identity.state, fingerprint: identity.fingerprint || '' },
  }
}

// A server's own logo, fetched here because the connect page loads no pictures from anywhere,
// and kept with the saved server by its version, so it's only fetched again when it changes.
async function logoOf(url, version) {
  if (!version) return null
  const kept = (saved.recent || []).find((s) => s.url === url && s.logo && s.logo.version === version)
  if (kept) return kept.logo
  try {
    const res = await fetchJson(`${url}/api/branding/logo?v=${encodeURIComponent(version)}`)
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

async function dropUnfitSignIn(url, identity) {
  if (!signInFits(url, identity, saved.recent)) await forgetSignIn(url)
}

function rememberServer(url, name, identity, logo) {
  saved = state.remember(saved, { url, name, serverId: identity.serverId, publicKey: identity.publicKey, fingerprint: identity.fingerprint, logo })
  saveState()
}

// Goes to a server someone chose, without a code: they sign in on its own page.
async function openServer(request) {
  pairing = null
  const found = await admitted(String(request && request.url), request && request.trust === true)
  if (found.error) return { error: found.error }
  try {
    await dropUnfitSignIn(found.url, found.identity)
  } catch (err) {
    log.noteError('warn', 'app', 'An old sign-in could not be forgotten', err, { where: found.url })
    return { error: 'identity' }
  }
  rememberServer(found.url, found.name, found.identity, shownLogo(found.url))
  showServer(found.url)
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
    res = await postJson(found.url + API + '/pair/redeem', {
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
    await dropUnfitSignIn(found.url, found.identity)
    await session.defaultSession.cookies.set({
      url: found.url, name: SESSION_COOKIE, value: token, httpOnly: true, sameSite: 'lax',
      secure: found.url.startsWith('https:'), expirationDate: Date.now() / 1000 + SESSION_DAYS * 86400,
    })
  } catch (err) {
    log.noteError('error', 'app', 'The sign-in could not be kept', err, { where: found.url })
    return { error: 'unreachable' }
  }
  rememberServer(found.url, found.name, found.identity, shownLogo(found.url))
  showServer(found.url)
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
    res = await postJson(found.url + API + '/pair/start', { device: deviceName(), platform: OS_NAME })
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
  pairing = { url: found.url, secret: data.deviceSecret }
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
    res = await postJson(asked.url + API + '/pair/poll', { deviceSecret: asked.secret })
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
  saved.server = ''
  saveState()
  if (origin) await forgetSignIn(origin).catch((err) => log.noteError('warn', 'app', 'The sign-in could not be forgotten', err, { where: origin }))
  showConnect()
  if (!to) return
  try {
    const res = await fetchJson(to.origin + API + '/logout', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${to.token}` }, body: '{}' })
    res.body?.cancel().catch(() => {})
    if (!res.ok) log.info('network', `Ending the session was answered with ${res.status}`, { where: to.origin })
  } catch (err) {
    log.noteError('info', 'network', 'The session on the server could not be ended', err, { where: to.origin })
  }
}

// What the last run was using, if it still is who it was.
async function startUp() {
  const url = saved.server && !normalizeAddress(saved.server).error ? saved.server : ''
  if (!url) return showConnect()
  const identity = await identify(url)
  if (identity.state === 'unreachable') return showConnect(identity.why === 'certificate' ? { certificate: '1' } : { lost: '1' })
  if (identity.state === 'different' || identity.state === 'bad') return showConnect({ mismatch: url })
  await dropUnfitSignIn(url, identity)
  if (identity.state !== 'none') {
    const known = (saved.recent || []).find((s) => s.url === url)
    rememberServer(url, known ? known.name : 'WittyMediaServer', identity)
  }
  return showServer(url)
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
    connected: Boolean(server), changeServer: () => leaveServer(), zoom: zoomPage, openLogs, copyDiagnostics,
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
ipcMain.handle('recent', (e) => (fromConnect(e) ? (saved.recent || []).map(({ url, name, logo }) => ({ url, name, logo: logo ? logo.data : '' })) : []))
ipcMain.handle('redeem', (e, url, code) => (fromConnect(e) ? redeem(String(url), String(code)) : { error: 'invalid' }))
ipcMain.handle('open-server', (e, request) => (fromConnect(e) ? openServer(request) : { error: 'invalid' }))
ipcMain.handle('pair-start', (e, url) => (fromConnect(e) ? pairStart(String(url)) : { error: 'invalid' }))
ipcMain.handle('pair-poll', (e) => (fromConnect(e) ? pairPoll() : { status: 'expired' }))
ipcMain.on('pair-stop', (e) => { if (fromConnect(e)) pairing = null })

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
    if (MAC) Menu.setApplicationMenu(macMenu())
  }).catch((err) => {
    // There's no window and never will be, and an app with none can't be closed.
    log.noteError('error', 'crash', 'The app could not start', err, { page: 'main process' })
    log.drainSync()
    app.exit(1)
  })
  app.on('window-all-closed', () => app.quit())
  app.on('before-quit', () => { log.flush() }) // one last try, which may not finish
  app.on('will-quit', () => log.drainSync())
}
