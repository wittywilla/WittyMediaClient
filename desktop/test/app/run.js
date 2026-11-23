// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Runs the real app, in Electron, against a stand-in server on 127.0.0.1, and checks what
// only the running thing can show: the screens, the keyboard, the sign-in cookie, and what
// a hostile server's page can and can't do. `npm run test:app`. A window is on screen for a
// few seconds.
//
// It can't start anything outside itself or open a native window: searching the network is
// replaced (a socket would ask the Windows firewall), so is opening a browser, the Help
// menu never opens, a download that's let through goes to a test folder without asking, and keeping
// the system from suspending the app is only noted down.
// Set WMC_SHOTS to a folder to get a picture of each screen.
const electron = require('electron')
// Whether the screen is locked: every window is then hidden from its page. macOS says so in the
// console session's flags, which Electron's idle state doesn't always report.
function screenLocked() {
  if (electron.powerMonitor.getSystemIdleState(1) === 'locked') return true
  if (process.platform !== 'darwin') return false
  try { return /"CGSSessionScreenIsLocked"=Yes/.test(require('node:child_process').execFileSync('ioreg', ['-n', 'Root', '-d1'], { encoding: 'utf8' })) } catch { return false }
}
const { app, session, shell, BaseWindow, Menu, powerSaveBlocker, webContents } = electron
const assert = require('node:assert')
const crypto = require('node:crypto')
const fs = require('node:fs')
const http = require('node:http')
const https = require('node:https')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const dataDir = fs.mkdtempSync(path.join(process.env.WMC_TEST_DIR || os.tmpdir(), 'wmc-app-'))
app.setPath('userData', dataDir)
const shots = process.env.WMC_SHOTS || ''
// A window that something else covers isn't painted, and there'd be no picture of it.
if (shots) app.commandLine.appendSwitch('disable-features', 'CalculateNativeWinOcclusion')

// Which run this is: the whole first-time journey, a code approved on a phone, the TV's
// look, or starting with something already remembered.
const scenario = process.argv[2] || 'journey'
// tv-full: a TV's real window, full screen, as Plasma Bigscreen or --tv opens it. Only its start and its menu are
// checked, so the screen is taken over for a few seconds at most.
if (scenario === 'tv-full') process.argv.push('--tv')
if (scenario === 'tv' || scenario === 'pair') {
  process.argv.push('--tv')
  // A TV's window fills the screen, which on a desktop would take it over while the test runs.
  // The same window, only not full screen, shows the same pages.
  class Windowed extends BaseWindow {
    constructor(options) { super({ ...options, fullscreen: false }) }
  }
  const Module = require('node:module')
  const load = Module._load
  Module._load = function loadWindowed(request, ...rest) {
    const loaded = load.call(this, request, ...rest)
    return request === 'electron' ? new Proxy(loaded, { get: (target, name) => (name === 'BaseWindow' ? Windowed : target[name]) }) : loaded
  }
}
// A Mac's title bar leaves the window's buttons and Help to the system.
const MAC = process.platform === 'darwin'
const PORT = 20000 + (process.pid % 30000)
// On another name, as cookies are kept by a machine's name and not by its port.
const OTHER_URL = `http://localhost:${PORT + 1}`
const SEEDS = {
  same: (url, key) => ({ server: url, recent: [{ url, name: 'Remembered', publicKey: key, serverId: SERVER_ID }] }),
  other: (url) => ({ server: url, recent: [{ url, name: 'Remembered', publicKey: rawKey(newKeys()), serverId: SERVER_ID }] }),
  lost: (url) => ({ server: url, recent: [{ url, name: 'Remembered' }] }),
  // Valid JSON, and none of it usable: this used to stop the app from starting.
  damaged: () => ({ server: 7, window: { width: 'wide', height: null }, recent: [null, 7, { url: 'javascript:alert(1)' }] }),
  certificate: (url) => ({ server: url.replace('http:', 'https:'), recent: [] }),
  // Two servers, one of them listed twice as a version before this one could leave it, and nothing in use.
  forget: (url, key) => ({ server: '', recent: [
    { url, name: 'Kept home', publicKey: key, serverId: SERVER_ID, lastSeen: Date.now() },
    { url: OTHER_URL, name: 'Shed', lastSeen: Date.now() - 200 * 86400000 },
    { url: 'http://127.0.0.1:9', name: 'Kept home, before it moved', publicKey: key, serverId: SERVER_ID },
  ] }),
}

// ---------------------------------------------------------------- what can't be real here

const opened = []
const toBrowser = async (url) => { opened.push(url) }
shell.openExternal = toBrowser
const menus = []
const toMenu = function popup(options) { menus.push({ labels: this.items.map((i) => i.label), options }) }
Menu.prototype.popup = toMenu
const blocks = { started: [], running: new Set() }
let nextBlock = 1
const toBlock = (type) => { blocks.started.push(type); blocks.running.add(nextBlock); return nextBlock++ }
powerSaveBlocker.start = toBlock
powerSaveBlocker.stop = (id) => blocks.running.delete(id)
// If these didn't take, the test would really open things. It stops here instead.
assert.strictEqual(shell.openExternal, toBrowser)
assert.strictEqual(Menu.prototype.popup, toMenu)
assert.strictEqual(powerSaveBlocker.start, toBlock)

const discover = require('../../discover.js')
let announce = () => {}
discover.startDiscovery = (onChange) => {
  announce = onChange
  return () => { announce = () => {} }
}

// ---------------------------------------------------------------- the stand-in server

const newKeys = () => crypto.generateKeyPairSync('ed25519')
const rawKey = (keys) => keys.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64')
const fingerprint = (keys) => {
  const hash = crypto.createHash('sha256').update(Buffer.from(rawKey(keys), 'base64')).digest('hex').toUpperCase()
  return `${hash.slice(0, 4)}-${hash.slice(4, 8)}-${hash.slice(8, 12)}`
}

const SERVER_ID = 'ab'.repeat(16)
const TOKEN = 'c0ffee'.repeat(8)
const PAIR_CODE = 'BCDF-GHJK'
// The server's own logo, a picture the app fetches once the server has proved who it is.
const LOGO = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8"><rect width="8" height="8" fill="#2e7d3c"/></svg>'
const DEVICE_SECRET = '5ec7e7'.repeat(10) + 'beef'
const SERVER_PAGE = `<!doctype html><html><head><title>Stand-in</title>
<style>:root { --bg-2: #fafafa; --fg: #111111; --border: #cccccc; }</style></head>
<body><a id="out" href="https://example.invalid/linked">a link</a><h1>Stand-in server</h1></body></html>`

// Three seconds of silence, so a test that plays makes no sound.
function silence(seconds = 3, rate = 8000) {
  const data = Buffer.alloc(seconds * rate * 2)
  const head = Buffer.alloc(44)
  head.write('RIFF', 0)
  head.writeUInt32LE(36 + data.length, 4)
  head.write('WAVEfmt ', 8)
  head.writeUInt32LE(16, 16)
  head.writeUInt16LE(1, 20) // PCM
  head.writeUInt16LE(1, 22) // one channel
  head.writeUInt32LE(rate, 24)
  head.writeUInt32LE(rate * 2, 28)
  head.writeUInt16LE(2, 32)
  head.writeUInt16LE(16, 34)
  head.write('data', 36)
  head.writeUInt32LE(data.length, 40)
  return Buffer.concat([head, data])
}
// A page that plays, counts its timer, and pauses when it's told it's hidden, as a browser tab's would.
const PLAYING_PAGE = `<!doctype html><html><head><title>Playing</title></head><body><h1>Playing</h1>
<audio id="a" src="/silence.wav" loop autoplay></audio>
<script>
window.ticks = 0
window.tickTimes = []
setInterval(() => { window.ticks++; window.tickTimes.push(performance.now()) }, 100)
// The typical time between ticks since a moment: about 100 ms running freely, a second or more once a hidden page's
// timers are slowed. A busy machine misses some ticks, so it's the median gap that tells, not how many there were.
window.tickGap = (since) => {
  const t = window.tickTimes.filter((x) => x >= since)
  const gaps = t.slice(1).map((x, i) => x - t[i]).sort((a, b) => a - b)
  return gaps.length ? gaps[Math.floor(gaps.length / 2)] : Infinity
}
document.addEventListener('visibilitychange', () => { if (document.hidden) document.getElementById('a').pause() })
</script></body></html>`

const stand = { keys: newKeys(), redeemed: [], loggedOut: [], cookies: [], asked: 0, polled: [], pairAnswers: [], codeAsks: [] }
const STAND_CODE = 'K7QM-2XHD'
const codeKit = require('../../code.js')
let standCode = null // its keys, made when first asked: Argon2 takes a moment

function answerRequest(req, res) {
  const send = (status, body, type = 'application/json', extra = {}) => {
    res.writeHead(status, { 'Content-Type': type, ...extra })
    res.end(type === 'application/json' ? JSON.stringify(body) : body)
  }
  let body = ''
  req.on('data', (d) => { body += d })
  req.on('end', () => {
    stand.asked++
    if (req.headers.cookie) stand.cookies.push(req.headers.cookie)
    const route = req.url.split('?')[0]
    if (route === '/api/status') return send(200, { name: 'WittyMediaServer', version: '0.0.1', brandName: 'Test\u0007 home', brandLogo: 'v1' })
    if (route === '/api/branding/logo') {
      stand.logos = (stand.logos || 0) + 1
      return send(200, LOGO, 'image/svg+xml')
    }
    if (route === '/api/v1/identity') {
      const { nonce } = JSON.parse(body)
      const message = Buffer.from(`WittyMediaServer identity v1\n${SERVER_ID}\n${nonce}`)
      return send(200, {
        serverId: SERVER_ID, algorithm: 'ed25519', publicKey: rawKey(stand.keys), fingerprint: 'AB12-CD34-EF56',
        signature: crypto.sign(null, message, stand.keys.privateKey).toString('base64'),
      })
    }
    if (route === '/api/v1/pair/redeem') {
      const { code } = JSON.parse(body)
      stand.redeemed.push(code)
      return code === '123456' ? send(200, { token: TOKEN }) : send(403, { error: 'That code is not right.', reason: 'bad-code' })
    }
    if (route === '/api/v1/connect/hello' || route === '/api/v1/connect/answer') {
      stand.codeAsks.push(body)
      const b = JSON.parse(body)
      standCode = standCode || codeKit.derive(codeKit.cleanCode(STAND_CODE))
      const key = rawKey(stand.keys)
      if (b.find !== Buffer.from(standCode.find).toString('hex')) return send(404, { error: "This server didn't make that code.", reason: 'not-here' })
      if (route === '/api/v1/connect/hello') {
        stand.serverNonce = crypto.randomBytes(16)
        const proof = codeKit.webProof(standCode.proof, 'server', Buffer.from(b.nonce, 'base64'), stand.serverNonce, key)
        return send(200, { nonce: stand.serverNonce.toString('base64'), publicKey: key, proof: proof.toString('base64') })
      }
      const want = codeKit.webProof(standCode.proof, 'device', Buffer.from(b.nonce, 'base64'), Buffer.from(b.serverNonce, 'base64'), key).toString('base64')
      return b.proof === want ? send(200, { status: 'approved', token: TOKEN, serverName: 'Test home' }) : send(401, { error: 'That code is not right.', reason: 'wrong-code' })
    }
    if (route === '/api/v1/pair/start') {
      return send(200, { code: PAIR_CODE, deviceSecret: DEVICE_SECRET, expiresInSec: 600, intervalSec: 1, approvePath: '/pair', approveUrl: `/pair?code=${PAIR_CODE}` })
    }
    if (route === '/api/v1/pair/poll') {
      stand.polled.push(JSON.parse(body).deviceSecret)
      const answer = stand.pairAnswers.shift() || 'pending'
      if (answer === 'approved') return send(200, { status: 'approved', token: TOKEN, user: { name: 'test' } })
      if (answer === 'denied') return send(403, { status: 'denied', error: 'the sign-in was refused' })
      return send(200, { status: 'pending', intervalSec: 1 })
    }
    if (route === '/api/v1/logout') {
      stand.loggedOut.push(req.headers.authorization)
      return send(200, { ok: true })
    }
    if (route === '/silence.wav') return send(200, silence(), 'audio/wav')
    if (route === '/playing') return send(200, PLAYING_PAGE, 'text/html')
    if (route === '/redirect-out') return send(302, '', 'text/plain', { Location: 'https://example.invalid/redirected' })
    if (route === '/framed') return send(200, '<!doctype html><iframe src="/redirect-out"></iframe>', 'text/html')
    return send(200, SERVER_PAGE, 'text/html')
  })
}

// ---------------------------------------------------------------- driving it

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
async function until(what, check, ms = 8000) {
  const end = Date.now() + ms
  let last
  for (;;) {
    try {
      last = await check()
      if (last) return last
    } catch (err) { last = err }
    if (Date.now() > end) throw new Error(`Waited for ${what}. Last: ${last && last.message ? last.message : JSON.stringify(last)}`)
    await wait(50)
  }
}

const views = () => {
  const all = webContents.getAllWebContents()
  return {
    bar: all.find((w) => w.getURL().includes('titlebar')),
    page: all.find((w) => !w.getURL().includes('titlebar')),
  }
}
const inPage = (code) => views().page.executeJavaScript(code)
const inBar = (code) => views().bar.executeJavaScript(code)
const heading = () => inPage("(document.querySelector('h1') || {}).textContent")
const focused = () => inPage('document.activeElement.textContent || document.activeElement.id')
const pageText = () => inPage('document.body.innerText')
// Focus moves a moment after a key: a busy machine (CI's macOS runner) hadn't moved it 40 ms later. Wait for it.
const focusOn = (expected, why = '') => until(`focus on ${JSON.stringify(expected)}${why ? ` (${why})` : ''}`, async () => (await focused()) === expected)
const focusStarts = (start, why = '') => until(`focus on ${JSON.stringify(start)}…${why ? ` (${why})` : ''}`, async () => String(await focused()).startsWith(start))
const clickText = (text) => inPage(`Array.from(document.querySelectorAll('button')).find((b) => b.textContent.startsWith(${JSON.stringify(text)})).click()`)
const onHeading = (text) => until(`the screen "${text}"`, async () => (await heading()) === text)

async function key(keyCode, modifiers = []) {
  const { page } = views()
  page.sendInputEvent({ type: 'keyDown', keyCode, modifiers })
  if (keyCode.length === 1) page.sendInputEvent({ type: 'char', keyCode, modifiers })
  page.sendInputEvent({ type: 'keyUp', keyCode, modifiers })
  await wait(40)
}

async function shot(name) {
  if (!shots) return
  await wait(150)
  fs.mkdirSync(shots, { recursive: true })
  const { page, bar } = views()
  // There's nothing to capture until the window's first paint has reached the screen.
  const capture = (view) => until(`a picture of ${name}`, () => view.capturePage().then((image) => (image.isEmpty() ? null : image)))
  fs.writeFileSync(path.join(shots, `${name}.png`), (await capture(page)).toPNG())
  if (scenario !== 'tv') fs.writeFileSync(path.join(shots, `${name}-bar.png`), (await capture(bar)).toPNG()) // a TV has no title bar
}

const results = []
async function step(name, run) {
  try {
    await run()
    results.push(`ok    ${name}`)
  } catch (err) {
    results.push(`FAIL  ${name}\n      ${err.message}`)
    throw err
  }
}

const stateFile = () => JSON.parse(fs.readFileSync(path.join(dataDir, 'state.json'), 'utf8'))
const signInCookies = (url) => session.defaultSession.cookies.get({ url, name: 'wms_token' })
// The wording the app itself was given: this also runs from inside a package.
const S = (() => {
  const holder = {}
  new Function('self', fs.readFileSync(path.join(__dirname, '..', '..', 'connect', 'strings.js'), 'utf8'))(holder)
  return holder.WittyStrings
})()

// A throwaway certificate nothing trusts. Made here, as a private key doesn't belong in a repository.
function selfSigned() {
  const dir = fs.mkdtempSync(path.join(dataDir, 'tls-'))
  const [key, cert] = [path.join(dir, 'key.pem'), path.join(dir, 'cert.pem')]
  const made = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=127.0.0.1', '-keyout', key, '-out', cert], { stdio: 'ignore' })
  return made.status === 0 ? { key: fs.readFileSync(key), cert: fs.readFileSync(cert) } : null
}

const onConnect = (ms) => until('the connect page', () => {
  const { page } = views()
  return page && page.getURL().includes('connect')
}, ms)

async function seeded(url) {
  await app.whenReady()
  if (scenario === 'same') {
    await step('a remembered server opens straight away, with no code', async () => {
      await until('the server page', () => views().page && views().page.getURL().startsWith(url))
      await until('the page to load', async () => (await heading()) === 'Stand-in server')
      assert.deepStrictEqual(stand.redeemed, [])
      await until('the button to change server', async () => (await inBar("document.getElementById('change').hidden")) === false)
      assert.strictEqual(stateFile().recent[0].name, 'Remembered', 'its name is kept')
    })
    const win = BaseWindow.getAllWindows()[0]
    const audio = (what) => inPage(`(() => { const a = document.getElementById('a'); return ${what} })()`)
    await step('what plays keeps playing with the window out of sight, and the system lets the app run', async () => {
      await views().page.loadURL(`${url}/playing`)
      await until('it to play', () => audio('a.currentTime > 0.3'))
      await until('the app kept running', () => blocks.running.size === 1)
      assert.deepStrictEqual(blocks.started, ['prevent-app-suspension'])
      win.hide()
      await wait(500)
      const before = await audio('({ t: a.currentTime, ticks: window.ticks, at: performance.now() })')
      await wait(1500)
      const after = await audio(`({ t: a.currentTime, ticks: window.ticks, gap: window.tickGap(${before.at}), seen: document.visibilityState, paused: a.paused })`)
      assert.strictEqual(after.seen, 'visible', 'never told it is hidden, so nothing pauses')
      assert.strictEqual(after.paused, false)
      // Looped three seconds: it moved on, whichever way round it went.
      assert.ok(after.t !== before.t, `still playing: ${before.t} then ${after.t}`)
      // Slowed, a hidden page's timer runs once a second at most; a loaded CI machine can still drop a tick or two.
      assert.ok(after.ticks - before.ticks >= 3 && after.gap < 500, `timers not slowed: ${after.ticks - before.ticks} ticks in 1.5 s, typically ${Math.round(after.gap)} ms apart`)
    })
    await step('with the website\'s setting off, the page is told it is hidden, like a browser tab, and pauses', async () => {
      await inPage("document.documentElement.dataset.backgroundPlay = 'off'; 0")
      await until('the page to learn it is hidden', async () => (await inPage('document.visibilityState')) === 'hidden')
      await until('it to pause', () => audio('a.paused'))
      await until('the system to be let go', () => blocks.running.size === 0)
      // Shown, and in front: a window covered by other apps' windows is still hidden to the page on
      // macOS, and a test can't count on taking the focus from whatever the person is using.
      win.setAlwaysOnTop(true)
      win.show()
      await inPage("delete document.documentElement.dataset.backgroundPlay; 0")
      // A locked screen hides every window from its page, whatever the app does: that can't be checked then.
      if (screenLocked()) console.log('      (the screen is locked, so being visible again is not checked)')
      else await until('visible again', async () => (await inPage('document.visibilityState')) === 'visible').catch(async (e) => {
        throw new Error(`${e.message} (window visible ${win.isVisible()}, minimised ${win.isMinimized()}, focused ${win.isFocused()}, page says ${await inPage('document.visibilityState')})`)
      })
      win.setAlwaysOnTop(false)
    })
  }
  if (scenario === 'other') {
    await session.defaultSession.cookies.set({ url, name: 'wms_token', value: 'an-old-sign-in', httpOnly: true })
    await step('another key at the remembered server stops at the warning', async () => {
      await onConnect()
      await onHeading(S.identityTitle)
      assert.match(await pageText(), new RegExp(fingerprint(stand.keys)))
      assert.strictEqual(stand.cookies.length, 0, 'the old sign-in went nowhere')
      assert.strictEqual(await inBar("document.getElementById('change').hidden"), true)
    })
    await step('trusting it forgets the old sign-in before the new server sees a thing', async () => {
      await clickText(S.identityTrust)
      await until('the server page', () => views().page.getURL().startsWith(url))
      await until('the page to load', async () => (await heading()) === 'Stand-in server')
      assert.strictEqual((await signInCookies(url)).length, 0)
      assert.deepStrictEqual(stand.cookies, [])
      assert.strictEqual(stateFile().recent[0].publicKey, rawKey(stand.keys))
    })
  }
  if (scenario === 'lost') {
    await step('a server that has gone says so, and the list is still there', async () => {
      await onConnect()
      await onHeading(S.addTitle)
      assert.ok((await pageText()).includes(S.errLost))
      assert.ok((await pageText()).includes('Remembered'))
      assert.strictEqual(stateFile().server, url, 'it is still the one to try next time')
    })
  }
  if (scenario === 'damaged') {
    await step('a state file full of nonsense doesn\'t stop the app starting', async () => {
      await onConnect()
      await onHeading(S.addTitle)
      assert.ok(!(await pageText()).toLowerCase().includes(S.recentServers.toLowerCase()))
    })
  }
  if (scenario === 'certificate') {
    const https = url.replace('http:', 'https:')
    await step('a bad certificate is refused, and says that is why', async () => {
      await onConnect()
      await until('the message', async () => (await pageText()).includes(S.errCertificate))
      assert.strictEqual(stand.asked, 0, 'nothing got as far as being asked')
    })
    await step('typing that address says the same', async () => {
      await clickText(S.wayAddress)
      await onHeading(S.addressTitle)
      await inPage(`document.getElementById('address').value = ${JSON.stringify(https)}`)
      await clickText(S.connect)
      await until('the message', async () => (await inPage("document.getElementById('address-error').textContent")) === S.errCertificate)
      assert.strictEqual(stand.asked, 0)
    })
    await step('a page with that certificate doesn\'t load, whoever asks', async () => {
      await assert.rejects(views().page.loadURL(https), /ERR_CERT/)
      assert.strictEqual(stand.asked, 0)
      const log = fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')
      assert.match(log, /A certificate was refused/)
    })
  }
  const log = fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')
  assert.ok(!/"kind":"crash"/.test(log), `nothing went unhandled: ${log}`)
}

async function run() {
  const listener = http.createServer(answerRequest)
  await new Promise((resolve) => listener.listen(0, '127.0.0.1', resolve))
  const url = `http://127.0.0.1:${listener.address().port}`

  const firstKeys = stand.keys
  const saved = []
  await app.whenReady()
  // After the app's own listener, and so that no download ever asks where to save.
  session.defaultSession.on('will-download', (_e, item) => {
    saved.push(item.getURL())
    item.setSavePath(path.join(dataDir, `download-${saved.length}`))
  })
  await until('the connect page', () => {
    const { page } = views()
    return page && page.getURL().includes('connect')
  })

  await step('the connect screen opens, with no server yet', async () => {
    await onHeading(S.addTitle)
    assert.strictEqual(await inPage("document.getElementById('announce').textContent"), S.addTitle, 'a screen reader hears which screen this is')
    assert.strictEqual(await inPage('document.title'), `${S.addTitle} - ${S.appName}`)
    // The three other ways, in this order, the first the main one while there's nothing to choose.
    assert.deepStrictEqual(await inPage("Array.from(document.querySelectorAll('.ways button')).map((b) => b.textContent)"), [S.wayCode, S.wayLink, S.wayAddress])
    assert.strictEqual(await inPage("document.querySelector('.ways button').classList.contains('primary')"), true)
    assert.strictEqual(await inPage("!!document.querySelector('.anywhere')"), false, 'no second panel of ways')
    assert.strictEqual(await inBar("document.getElementById('change').hidden"), true)
    assert.strictEqual(await inPage("document.querySelector('main').hasAttribute('aria-live')"), false, 'the whole page is not read out on every change')
    assert.strictEqual(await inPage("document.querySelector('.lockup').textContent"), S.appName, 'the app is WittyMediaClient until a server is added')
    await shot('list-empty')
  })

  await step('a found server takes focus, as one press has to select it, and says nothing about itself', async () => {
    announce([{ id: SERVER_ID, name: 'Home', url: 'http://10.0.0.2:9797' }, { id: 'cd'.repeat(16), name: 'Shed', url: 'http://10.0.0.3:9797' }])
    await until('a found server', async () => (await focused()) === `10.0.0.2:9797${S.foundOnNetwork}`)
    assert.ok(!/Home|Shed/.test(await pageText()), 'not the name it announces, until it is added')
    await shot('list-found')
    await key('Down')
    await focusStarts('10.0.0.3:9797', 'down moves to the next')
    await key('Down')
    await focusOn(S.wayCode)
    assert.strictEqual(await inPage("document.querySelector('.ways button').classList.contains('primary')"), false, 'with servers found, none of the other ways is the main one')
  })

  await step('the address screen: labelled, with a way back that needs no keyboard', async () => {
    await clickText(S.wayAddress)
    await onHeading(S.addressTitle)
    await focusOn('address')
    assert.strictEqual(await inPage("document.querySelector('label').htmlFor"), 'address')
    assert.strictEqual(await inPage("document.getElementById('address-error').getAttribute('role')"), 'alert')
    assert.match(await inPage("document.getElementById('address').getAttribute('aria-describedby')"), /address-error/)
    await shot('address')
    await key('Escape')
    await onHeading(S.addTitle)
    await focusOn(S.wayAddress, 'back puts focus where it was')
    await clickText(S.wayAddress)
    await onHeading(S.addressTitle)
    await clickText(S.back)
    await onHeading(S.addTitle)
    await clickText(S.wayAddress)
    await onHeading(S.addressTitle)
  })

  await step('a bad address says why, on the field', async () => {
    await inPage("document.getElementById('address').value = 'media.example.com'")
    await clickText(S.connect)
    await until('the error', async () => (await inPage("document.getElementById('address-error').textContent")) === S.errPublicHttp)
    assert.strictEqual(await inPage("document.getElementById('address').getAttribute('aria-invalid')"), 'true')
    await shot('address-error')
  })

  await step('a new server asks for a code and shows the key it worked out', async () => {
    await inPage(`document.getElementById('address').value = ${JSON.stringify(url)}`)
    await clickText(S.connect)
    await onHeading(S.codeSignInTitle)
    assert.match(await pageText(), new RegExp(fingerprint(firstKeys)))
    await focusOn('code')
    assert.strictEqual(await inPage("document.querySelector('label').htmlFor"), 'code')
    assert.strictEqual(await inPage("document.getElementById('code-error').getAttribute('role')"), 'alert')
    assert.ok((await pageText()).includes(S.signInPassword), 'with the password as the other way')
    // Proved, it's added: its own name and logo, which the app fetched, as the page loads no pictures itself.
    assert.strictEqual(await inPage("document.querySelector('.server-pill').textContent"), 'Test home')
    assert.match(await inPage("document.querySelector('.server-pill img.logo').src"), /^data:image\/svg\+xml;base64,/)
    await shot('code')
  })

  await step('the tallest screen fits the window, and nothing runs off the side when it is narrow', async () => {
    const win = BaseWindow.getAllWindows()[0]
    const [width, height] = win.getSize()
    const fits = () => inPage('({ tall: document.documentElement.scrollHeight <= innerHeight, wide: document.documentElement.scrollWidth <= innerWidth })')
    // At the window's default size, 1280 by 800. A screen too small to hold that (as on some CI
    // machines) shrinks the window, and then only the width can be held to it.
    const roomy = width >= 1280 && height >= 800
    await until('the default size to fit', async () => (roomy ? (await fits()).tall : true) && (await fits()).wide)
    win.setSize(480, 700)
    await wait(200)
    assert.strictEqual((await fits()).wide, true, 'no sideways scrolling at the narrowest')
    await shot('code-narrow')
    win.setSize(width, height)
    await wait(200)
  })

  const typeCode = async (text) => {
    await inPage(`document.getElementById('code').value = ${JSON.stringify(text)}`)
    await clickText(S.connect)
  }
  await step('a wrong code is refused and can be tried again', async () => {
    await typeCode('000000') // six digits: a code from the server's Sign in a TV page
    await until('the refusal', async () => (await inPage("document.getElementById('code-error').textContent")) === 'That code is not right.')
    assert.deepStrictEqual(stand.redeemed, ['000000'])
    await typeCode('hello')
    await until('the refusal', async () => (await inPage("document.getElementById('code-error').textContent")) === S.errCodeFormat)
    await typeCode('ABCD-1234') // a code this server didn't make
    await until('the refusal', async () => (await inPage("document.getElementById('code-error').textContent")) === S.errCodeNotFound)
    assert.strictEqual(await inPage("document.getElementById('code').getAttribute('aria-invalid')"), 'true')
    await shot('code-refused')
  })

  await step('a key that changes on the code screen gets no code, and the new one is shown', async () => {
    const asked = stand.codeAsks.length
    stand.keys = newKeys()
    await typeCode(STAND_CODE)
    await until('the warning', async () => (await pageText()).includes(S.identityChanged))
    assert.strictEqual(stand.codeAsks.length, asked, 'nothing about the code left this computer')
    assert.match(await pageText(), new RegExp(fingerprint(stand.keys)))
    assert.strictEqual((await signInCookies(url)).length, 0)
    await shot('code-changed')
  })

  await step('the right code signs in, as a cookie no page can read, and the code itself never left', async () => {
    // The sign-in screen now names the new key, and it is that one the code goes to.
    await onHeading(S.codeSignInTitle)
    await typeCode(' k7qm 2xhd ')
    await until('the server page', () => views().page.getURL().startsWith(url))
    const [cookie] = await signInCookies(url)
    assert.strictEqual(cookie.value, TOKEN)
    assert.strictEqual(cookie.httpOnly, true)
    await until('the page to load', async () => (await heading()) === 'Stand-in server')
    assert.strictEqual(await inPage('document.cookie'), '')
    assert.ok(!stand.codeAsks.some((b) => /K7QM|2XHD/i.test(b)), 'the code was sent')
    const [entry] = stateFile().recent
    assert.strictEqual(entry.publicKey, rawKey(stand.keys))
    assert.strictEqual(entry.name, 'Test home', 'a control character in the name was taken out')
    assert.strictEqual(entry.logo.version, 'v1', 'the logo is kept with it')
    assert.strictEqual(Buffer.from(entry.logo.data.split(',')[1], 'base64').toString(), LOGO)
    assert.strictEqual(stateFile().server, url)
  })

  await step('a server\'s page only gets Moonlight, and the main process agrees it is that page', async () => {
    assert.deepStrictEqual(await inPage('Object.keys(window.wittyClient)'), ['moonlight'])
    assert.strictEqual(await inPage('typeof require + typeof process'), 'undefinedundefined')
    const { installed } = await inPage('window.wittyClient.moonlight.status()')
    if (!installed) {
      const answer = await inPage("window.wittyClient.moonlight.launch(['stream', 'pc.local', 'A game'])")
      assert.match(answer.error, /isn't installed/, 'not refused as coming from the wrong page')
    }
    const refused = await inPage("window.wittyClient.moonlight.launch(['stream', '--evil', 'A game'])")
    assert.match(refused.error, /isn't something/)
  })

  await step('the title bar takes the server\'s colours', async () => {
    await until('the colours', async () => (await inBar("document.documentElement.style.getPropertyValue('--bg')")) === '#fafafa')
    assert.strictEqual(await inBar("document.getElementById('change').hidden"), false)
    await shot('server')
  })

  await step('F6 reaches the title bar, the keys move along it, and Escape comes back', async () => {
    const shown = await inBar("Array.from(document.querySelectorAll('button')).filter((b) => b.offsetParent).map((b) => b.id)")
    assert.deepStrictEqual(shown, MAC ? ['change'] : ['help', 'change', 'minimize', 'maximize', 'close'])
    await key('F6')
    await until('focus in the bar', () => inBar(`document.hasFocus() && document.activeElement.id === '${shown[0]}'`))
    const bar = views().bar
    const press = async (keyCode) => {
      bar.sendInputEvent({ type: 'keyDown', keyCode })
      bar.sendInputEvent({ type: 'keyUp', keyCode })
      await wait(40)
    }
    await press('Right')
    assert.strictEqual(await inBar('document.activeElement.id'), shown[1 % shown.length])
    await press('Left')
    await press('Left')
    assert.strictEqual(await inBar('document.activeElement.id'), shown[shown.length - 1], 'it wraps round')
    await press('Home')
    assert.strictEqual(await inBar('document.activeElement.id'), shown[0])
    await press('Escape')
    await until('focus back on the page', () => inPage('document.hasFocus()'))
  })

  if (!MAC) {
    await step('Help opens under its button', async () => {
      await inBar("document.getElementById('help').click()")
      await until('the menu', () => menus.length === 1)
      // A separator has no label: undefined on Linux, '' on Windows. Connecting from away is
      // offered only where the connect helper has been built (npm run build:connect).
      const labels = menus[0].labels.map((l) => l || undefined).filter((l) => !/from away/i.test(l || ''))
      assert.deepStrictEqual(labels.slice(0, 3), ['Manage servers…', undefined, 'Open logs folder'], 'with a server open')
      assert.ok(Number.isInteger(menus[0].options.x) && menus[0].options.y > 0)
    })
  } else {
    await step('on a Mac, Help and Change server are in the menu bar, and zooming is for the page', async () => {
      const menu = Menu.getApplicationMenu()
      const help = menu.items.find((m) => m.role === 'help')
      assert.deepStrictEqual(help.submenu.items.map((i) => i.label), ['Open logs folder', 'Copy diagnostic info'])
      assert.strictEqual(menu.getMenuItemById('change-server').enabled, true, 'with a server open')
      assert.ok(menu.getMenuItemById('manage-servers'), 'Manage Servers is in the Server menu')
      assert.ok(menu.items.some((m) => m.role === 'editmenu' || m.role === 'editMenu'), 'or copy and paste do nothing')
      assert.deepStrictEqual(BaseWindow.getAllWindows()[0].getWindowButtonPosition(), { x: 9, y: 9 })
      const zoomIn = menu.items.find((m) => m.label === 'View').submenu.items.find((i) => i.label === 'Zoom In')
      zoomIn.click()
      assert.strictEqual(views().page.getZoomLevel(), 0.5)
      assert.strictEqual(views().bar.getZoomLevel(), 0, 'the title bar stays as it is')
      menu.items.find((m) => m.label === 'View').submenu.items.find((i) => i.label === 'Actual Size').click()
      assert.strictEqual(views().page.getZoomLevel(), 0)
    })
  }

  await step('a link goes to the browser, and the page stays', async () => {
    opened.length = 0
    await inPage("document.getElementById('out').click()")
    await until('the browser', () => opened.length === 1)
    assert.strictEqual(opened[0], 'https://example.invalid/linked')
    assert.ok(views().page.getURL().startsWith(url))
  })

  await step('a page can\'t open programs or files, or reach the connect page', async () => {
    opened.length = 0
    await inPage("window.open('file:///C:/Windows/System32/calc.exe'); window.open('ms-settings:'); window.open('javascript:alert(1)')")
    await wait(150)
    assert.deepStrictEqual(opened, [])
    for (const place of ['wittymedia-app://connect/index.html?mismatch=https://example.invalid', 'file:///C:/Windows/win.ini']) {
      await inPage(`location.href = ${JSON.stringify(place)}; 0`)
      await wait(250)
      assert.ok(views().page.getURL().startsWith(url), `still on the server, not ${place}`)
    }
    assert.deepStrictEqual(opened, [])
  })

  await step('a redirect away, for the page or a frame in it, opens nothing', async () => {
    opened.length = 0
    await inPage("location.href = '/redirect-out'; 0")
    await wait(300)
    assert.ok(views().page.getURL().startsWith(url), 'still on the server')
    await views().page.loadURL(`${url}/framed`)
    await wait(300)
    assert.deepStrictEqual(opened, [])
    await views().page.loadURL(url)
    await until('the page again', async () => (await heading()) === 'Stand-in server')
  })

  await step('a page can only open so many things outside', async () => {
    opened.length = 0
    await inPage("for (let i = 0; i < 30; i++) window.open('https://example.invalid/' + i); 0")
    await wait(300)
    assert.ok(opened.length <= 5, `${opened.length} opened`)
  })

  await step('a page can save what its server sends, and nothing else', async () => {
    saved.length = 0
    const refusals = await inPage(`(async () => {
      const a = document.createElement('a')
      a.href = 'data:text/plain,not from the server'
      a.download = 'refused.txt'
      a.click()
      return true
    })()`)
    assert.strictEqual(refusals, true)
    await wait(200)
    const before = fs.readdirSync(dataDir).filter((f) => f.startsWith('download-') && fs.existsSync(path.join(dataDir, f)))
    assert.deepStrictEqual(before.filter((f) => fs.statSync(path.join(dataDir, f)).size > 0), [], 'nothing saved')
    await inPage(`(() => {
      const a = document.createElement('a')
      a.href = URL.createObjectURL(new Blob(['made by the server page']))
      a.download = 'allowed.txt'
      a.click()
    })()`)
    await until('the file', () => fs.readdirSync(dataDir).some((f) => f.startsWith('download-') && fs.statSync(path.join(dataDir, f)).size > 0))
  })

  await step('Change server ends the session here and on the server', async () => {
    assert.strictEqual((await signInCookies(url)).length, 1)
    await inBar("document.getElementById('change').click()")
    await onHeading(S.addTitle)
    assert.strictEqual((await signInCookies(url)).length, 0)
    await until('the sign-out', () => stand.loggedOut.length === 1)
    assert.strictEqual(stand.loggedOut[0], `Bearer ${TOKEN}`)
    assert.strictEqual(stateFile().server, '')
    await until('the bar\'s own colours', async () => (await inBar("document.documentElement.style.getPropertyValue('--bg')")) === '#0f1115')
    assert.strictEqual(await inBar("document.getElementById('change').hidden"), true)
    if (MAC) assert.strictEqual(Menu.getApplicationMenu().getMenuItemById('change-server').enabled, false)
    assert.deepStrictEqual(await inPage('Object.keys(window.wittyClient).includes("probe")'), true)
    assert.ok((await pageText()).toLowerCase().includes(S.recentServers.toLowerCase()))
    assert.strictEqual(await inPage("document.querySelectorAll('.server img.logo').length"), 1, 'shown before the server answers')
    await shot('list-recent')
  })

  await step('a remembered server that is also found is listed once, under Used before, with its own name', async () => {
    announce([{ id: SERVER_ID, name: 'Announced', url }, { id: 'cd'.repeat(16), name: 'Shed', url: 'http://10.0.0.3:9797' }])
    await until('the other server', async () => (await pageText()).includes('10.0.0.3:9797'))
    const rows = await inPage(`Array.from(document.querySelectorAll('.server')).map((b) => b.querySelector('.name').textContent)`)
    assert.deepStrictEqual(rows, ['Test home', '10.0.0.3:9797'], 'the saved one first, once, then what was found')
    assert.strictEqual(await inPage('document.activeElement.dataset.url'), url, 'the last one used has focus, and a server found later does not take it')
    assert.ok(!(await pageText()).includes('Announced'))
    // Show saved servers first, turned off: the order as it was, found first. Kept on this device.
    await inPage(`(() => { const b = document.querySelector('.pref input'); b.click() })()`)
    await until('the found server on top', async () => (await inPage(`document.querySelector('.server .name').textContent`)) === '10.0.0.3:9797')
    assert.strictEqual(await inPage(`localStorage.getItem('savedServersFirst')`), '0')
    await inPage(`document.querySelector('.pref input').click()`)
    await until('the saved server on top again', async () => (await inPage(`document.querySelector('.server .name').textContent`)) === 'Test home')
    announce([])
    await until('nothing found', async () => (await inPage(`document.querySelectorAll('.server').length`)) === 1)
  })

  await step('a remembered server opens straight away, with nothing to prove again', async () => {
    const logos = stand.logos
    await clickText('Test home')
    await until('the server page', () => views().page.getURL().startsWith(url))
    assert.strictEqual(stand.logos, logos, 'a kept logo is only fetched again when its version changes')
    await until('the page to load', async () => (await heading()) === 'Stand-in server')
    await inBar("document.getElementById('change').click()")
    await onHeading(S.addTitle)
  })

  if (MAC) {
    await step('Manage Servers keeps the server in use, marks it, and Back returns to it still signed in', async () => {
      await clickText('Test home')
      await until('the server page', () => views().page.getURL().startsWith(url))
      await until('the page to load', async () => (await heading()) === 'Stand-in server')
      const cookies = (await signInCookies(url)).length
      Menu.getApplicationMenu().getMenuItemById('manage-servers').click()
      await onHeading(S.addTitle)
      assert.ok((await pageText()).includes(S.inUse), 'the one in use says so')
      assert.strictEqual(await focused(), S.backToServer.replace('{name}', 'Test home'), 'the way back has focus')
      assert.strictEqual((await signInCookies(url)).length, cookies, 'still signed in')
      assert.strictEqual(stateFile().server, url, 'and still the server this app opens')
      await key('Escape')
      await until('the server page again', () => views().page.getURL().startsWith(url))
      await inBar("document.getElementById('change').click()")
      await onHeading(S.addTitle)
    })
  }

  await step('another key at a known address gets a warning, and the person decides about that key', async () => {
    const pinned = rawKey(stand.keys)
    stand.keys = newKeys()
    await clickText('Test home')
    await onHeading(S.identityTitle)
    assert.match(await pageText(), new RegExp(fingerprint(stand.keys)))
    assert.strictEqual(stateFile().recent[0].publicKey, pinned, 'still the old key')
    await shot('identity')
    // A third key appears after they read the second. Saying yes to one isn't saying yes to the other.
    stand.keys = newKeys()
    await clickText(S.identityTrust)
    await until('the warning', async () => (await pageText()).includes(S.identityChanged))
    assert.strictEqual(await heading(), S.identityTitle)
    assert.match(await pageText(), new RegExp(fingerprint(stand.keys)))
    assert.strictEqual(stateFile().recent[0].publicKey, pinned, 'still the old key')
    await shot('identity-changed')
    await clickText(S.identityTrust)
    await until('the server page', () => views().page.getURL().startsWith(url))
    assert.strictEqual(stateFile().recent[0].publicKey, rawKey(stand.keys))
  })

  await step('nothing went to the server with a sign-in it did not earn', async () => {
    assert.ok(stand.cookies.every((c) => c.includes(TOKEN)))
    const log = fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')
    assert.ok(!log.includes(TOKEN), 'the sign-in is not in the log')
    assert.ok(!/"kind":"crash"/.test(log), 'nothing crashed or went unhandled')
  })

  await step('a page that crashes goes back to the connect screen and says so', async () => {
    views().page.forcefullyCrashRenderer()
    await onConnect()
    await until('the message', async () => (await pageText()).includes(S.errLost))
  })

  await step('a title bar that crashes comes back, or the window couldn\'t be closed', async () => {
    views().bar.forcefullyCrashRenderer()
    await until('the bar', () => inBar("document.getElementById('close') !== null"))
  })

  listener.close()
}

// Removing remembered servers: one, with Undo; the old ones; all of them. What is checked is what
// is left on this computer and what the servers were told.
async function forgetting(url) {
  await app.whenReady()
  await onConnect()
  await onHeading(S.addTitle)
  const names = () => inPage(`Array.from(document.querySelectorAll('.server .name')).map((n) => n.textContent)`)
  const cookieAt = (at, value) => session.defaultSession.cookies.set({ url: at, name: 'wms_token', value, httpOnly: true })
  const kept = async (at) => (await signInCookies(at)).map((c) => c.value)

  await step('a list with one server twice is one entry each, and says when each was reached', async () => {
    assert.deepStrictEqual(await names(), ['Kept home', 'Shed'])
    assert.deepStrictEqual(stateFile().recent.map((s) => s.url), [url, OTHER_URL])
    const text = await pageText()
    assert.ok(text.includes(S.lastReachedToday) && text.includes(S.lastReachedDays.replace('{days}', '200')) && text.includes(S.staleServer), text)
    assert.strictEqual(await inPage(`document.querySelector('[data-remove="${OTHER_URL}"]').getAttribute('aria-label')`), 'Remove Shed')
    await shot('list-remove')
  })

  await cookieAt(url, 'a'.repeat(48))
  await cookieAt(OTHER_URL, 'b'.repeat(48))

  await step('Delete on a server removes it, says so, and puts focus on the one beside it', async () => {
    await inPage(`document.querySelector('.server[data-url="${OTHER_URL}"]').focus()`)
    await key('Delete')
    await until('the row to go', async () => (await names()).length === 1)
    assert.ok((await pageText()).includes('Removed Shed.'))
    assert.strictEqual(await inPage('document.activeElement.dataset.url'), url)
    assert.deepStrictEqual(stateFile().recent.map((s) => s.url), [url])
    assert.deepStrictEqual(stateFile().forgetting.map((s) => s.url), [OTHER_URL])
    assert.deepStrictEqual(await kept(OTHER_URL), ['b'.repeat(48)], 'nothing is deleted while it can be undone')
    assert.deepStrictEqual(stand.loggedOut, [])
    await shot('list-removed')
  })

  await step('Undo puts it back where it was, still signed in, and the server heard nothing', async () => {
    await clickText(S.undo)
    await until('the row to come back', async () => (await names()).length === 2)
    assert.deepStrictEqual(await names(), ['Kept home', 'Shed'])
    assert.strictEqual(await inPage('document.activeElement.dataset.url'), OTHER_URL)
    assert.strictEqual(stateFile().forgetting, undefined)
    assert.deepStrictEqual(await kept(OTHER_URL), ['b'.repeat(48)])
    assert.deepStrictEqual(stand.loggedOut, [])
  })

  await step('a right-click on a remembered server offers to remove it', async () => {
    const before = menus.length
    await inPage(`document.querySelector('.server[data-url="${OTHER_URL}"]').dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 40, clientY: 40 }))`)
    await until('the menu', () => menus.length === before + 1)
    assert.deepStrictEqual(menus[menus.length - 1].labels, ['Remove this server'])
  })

  await step('servers not reached for a while are named before anything goes, and Escape keeps them', async () => {
    await clickText(S.removeOldServers)
    await onHeading(S.removeOldTitle)
    await clickText(S.staleDays365)
    await until('the answer', async () => (await pageText()).includes(S.removeOldNone))
    await clickText(S.staleDays90)
    await onHeading(S.removeOldConfirmTitle)
    const text = await pageText()
    assert.ok(text.includes('Shed') && !text.includes('Kept home'), text)
    assert.strictEqual(await focused(), S.cancel, 'the safe answer has focus')
    await shot('remove-old')
    await key('Escape')
    await onHeading(S.addTitle)
    assert.strictEqual((await names()).length, 2)
  })

  await step('its button removes it; once Undo has gone its sign-in is ended there and everything kept for it is cleared', async () => {
    await inPage(`document.querySelector('[data-remove="${OTHER_URL}"]').click()`)
    await until('the row to go', async () => (await names()).length === 1)
    await until('the sign-out', () => stand.loggedOut.length === 1, 15000)
    assert.strictEqual(stand.loggedOut[0], `Bearer ${'b'.repeat(48)}`)
    await until('its cookie to go', async () => (await kept(OTHER_URL)).length === 0)
    await until('the list of what is waiting to empty', () => stateFile().forgetting === undefined)
    assert.deepStrictEqual(await kept(url), ['a'.repeat(48)], 'the other server is still signed in')
    assert.deepStrictEqual(stateFile().recent.map((s) => s.name), ['Kept home'])
    await until('the undo to go', async () => !(await pageText()).includes(S.undo))
  })

  await step('Remove all asks first, with what will go, and then nothing is left', async () => {
    await clickText(S.removeAllServers)
    await onHeading(S.removeAllTitle)
    assert.ok((await pageText()).includes('Kept home'))
    assert.strictEqual(await focused(), S.cancel)
    await shot('remove-all')
    await inPage(`document.querySelector('button.destructive').click()`)
    await onHeading(S.addTitle)
    await until('an empty list', async () => (await names()).length === 0)
    assert.strictEqual(await focused(), S.wayAddress, 'focus is somewhere a key can move from')
    await inPage('window.wittyClient.forgetFinish()')
    await until('the sign-out', () => stand.loggedOut.length === 2)
    assert.deepStrictEqual(await kept(url), [])
    const left = stateFile()
    assert.deepStrictEqual([left.recent, left.server, left.forgetting], [[], '', undefined])
    noCrash()
  })
}

async function standIn() {
  const listener = http.createServer(answerRequest)
  await new Promise((resolve) => listener.listen(0, '127.0.0.1', resolve))
  return `http://127.0.0.1:${listener.address().port}`
}

async function typeAddress(url) {
  await clickText(S.wayAddress)
  await onHeading(S.addressTitle)
  await inPage(`document.getElementById('address').value = ${JSON.stringify(url)}`)
  await clickText(S.connect)
}

const noCrash = () => {
  const log = fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')
  assert.ok(!/"kind":"crash"/.test(log), `nothing went unhandled: ${log}`)
  return log
}

// Enter a code, from the list: every server found or remembered is asked, and the one that made it signs in.
async function byCode() {
  const url = await standIn()
  await app.whenReady()
  await onConnect()
  await step('Enter a code asks the servers found, and the one that made it signs this device in', async () => {
    await onHeading(S.addTitle)
    announce([{ id: 'cd'.repeat(16), name: 'Shed', url: 'http://10.0.0.3:9797' }, { id: SERVER_ID, name: 'Home', url }])
    await clickText(S.wayCode)
    await onHeading(S.codeEnterTitle)
    await focusOn('code')
    await shot('enter-code')
    await inPage("document.getElementById('code').value = 'ABCD-1234'")
    await clickText(S.connect)
    await until('the refusal', async () => (await inPage("document.getElementById('code-error').textContent")) === S.errCodeNotFound)
    await shot('enter-code-not-found')
    await inPage(`document.getElementById('code').value = ${JSON.stringify(STAND_CODE.toLowerCase())}`)
    await clickText(S.connect)
    await until('the server page', () => views().page.getURL().startsWith(url), 20000)
    const [cookie] = await signInCookies(url)
    assert.strictEqual(cookie.value, TOKEN)
    assert.ok(!stand.codeAsks.some((b) => /K7QM|2XHD/i.test(b)), 'the code was sent')
    assert.strictEqual(stateFile().recent[0].publicKey, rawKey(stand.keys))
    noCrash()
  })
}

// A code shown on a TV and approved on a phone.
async function approved() {
  const url = await standIn()
  await app.whenReady()
  await onConnect()
  await step('leaving a code on show stops asking about it', async () => {
    await onHeading(S.addTitle)
    await typeAddress(url)
    await onHeading(S.codeTitle)
    await clickText(S.showCodeInstead)
    await onHeading(S.pairTitle)
    await until('a question', () => stand.polled.length >= 1)
    await key('Escape')
    await onHeading(S.codeTitle)
    const asked = stand.polled.length
    await wait(2500)
    assert.strictEqual(stand.polled.length, asked)
  })
  await step('a code approved on a phone signs in, as a cookie no page can read', async () => {
    stand.pairAnswers = ['pending', 'approved']
    await clickText(S.showCodeInstead)
    await onHeading(S.pairTitle)
    await until('the server page', () => views().page.getURL().startsWith(url))
    const [cookie] = await signInCookies(url)
    assert.strictEqual(cookie.value, TOKEN)
    assert.strictEqual(cookie.httpOnly, true)
    assert.ok(stand.polled.every((secret) => secret === DEVICE_SECRET))
    assert.deepStrictEqual(stand.redeemed, [], 'no code was typed')
    assert.strictEqual(stateFile().recent[0].publicKey, rawKey(stand.keys))
    await until('the page to load', async () => (await heading()) === 'Stand-in server')
    const log = noCrash()
    assert.ok(!log.includes(TOKEN) && !log.includes(DEVICE_SECRET), 'neither secret is in the log')
  })
}

// The TV's look: the words on the left half, what to do on the right, sized for the room.
async function onTv() {
  const url = await standIn()
  await app.whenReady()
  // The TV's window can take longer to come up on a machine still busy with the run before.
  await onConnect(20000)
  BaseWindow.getAllWindows()[0].setSize(1280, 720)
  const halves = (left, right) => inPage(`(() => {
    const l = document.querySelector(${JSON.stringify(left)}).getBoundingClientRect()
    const r = document.querySelector(${JSON.stringify(right)}).getBoundingClientRect()
    return l.right <= innerWidth / 2 && r.left >= innerWidth / 2
  })()`)
  await step('on a TV, the words are on the left and the servers on the right, and focus is plain to see', async () => {
    await onHeading(S.addTitle)
    assert.strictEqual(await inPage("document.documentElement.classList.contains('tv')"), true)
    announce([{ id: SERVER_ID, name: 'Home', url: 'http://10.0.0.2:9797' }, { id: 'cd'.repeat(16), name: 'Shed', url: 'http://10.0.0.3:9797' }])
    await until('a found server', async () => (await focused()).startsWith('10.0.0.2:9797'))
    assert.strictEqual(await halves('.words', '.actions'), true)
    // The lockup reads from across the room: a 72 mark, in TV units.
    // A TV unit is a 1920th of the width, or a 1080th of the height where the window is wider than 16:9.
    const unit = 'Math.min(innerWidth / 1920, innerHeight / 1080)'
    const mark = await inPage(`({ size: document.querySelector('.lockup .mark').getBoundingClientRect().width, unit: ${unit} })`)
    assert.ok(Math.abs(mark.size - 72 * mark.unit) < 1, JSON.stringify(mark))
    // Four TV units wide.
    const ring = await inPage(`({ width: parseFloat(getComputedStyle(document.activeElement).outlineWidth), unit: ${unit} })`)
    // Chromium draws a ring a whole number of device pixels wide: 2.67 is 2 on a screen with one to a pixel.
    assert.ok(Math.abs(ring.width - 4 * ring.unit) <= 1, JSON.stringify(ring))
    await shot('tv-list')
  })
  await step('on a TV, Back leaves the address screen for the list', async () => {
    await clickText(S.wayAddress)
    await onHeading(S.addressTitle)
    // Every button on a TV is a pill, and a focused field shows the ring and not a second, accent outline.
    const connect = await inPage(`(() => { const b = Array.from(document.querySelectorAll('button')).find((x) => x.textContent === ${JSON.stringify(S.connect)}); return { radius: parseFloat(getComputedStyle(b).borderTopLeftRadius), height: b.getBoundingClientRect().height } })()`)
    assert.ok(connect.radius >= connect.height / 2, JSON.stringify(connect))
    // A 1px border is one device pixel: 0.666667px in CSS on a display scaled to 150%.
    const border = await inPage("(() => { const w = parseFloat(getComputedStyle(document.querySelector('.field fieldset')).borderTopWidth); return { w, px: w * devicePixelRatio } })()")
    assert.ok(border.w > 0 && border.w <= 1 && Math.round(border.px) === 1, JSON.stringify(border))
    await shot('tv-address')
    await key('Escape')
    await onHeading(S.addTitle)
  })
  await step('on a TV, the code boxes are on the left and the number pad on the right', async () => {
    // :focus only matches while the window has the system's focus, which another app in front or a
    // sleeping display takes away; the page is told it has it, as a TV's own window always does.
    const page = views().page
    if (!page.debugger.isAttached()) page.debugger.attach('1.3')
    await page.debugger.sendCommand('Emulation.setFocusEmulationEnabled', { enabled: true })
    await typeAddress(url)
    await onHeading(S.codeTitle)
    assert.strictEqual(await halves('.code', '.pad'), true)
    // A focused key fills with text instead of taking a ring.
    const key1 = () => inPage('(() => { const s = getComputedStyle(document.activeElement); return [document.activeElement.textContent, s.outlineStyle, s.backgroundColor].join() })()')
    let seen = ''
    await until('the key to fill', async () => (seen = await key1()) === '1,none,rgb(232, 234, 240)').catch((e) => { throw new Error(`${e.message} (focus, outline, fill: ${seen})`) })
    await key('4')
    await shot('tv-code')
  })
  await step('on a TV, a code shown here has its QR code on the right', async () => {
    await clickText(S.showCodeInstead)
    await until('the code', async () => (await pageText()).includes(PAIR_CODE))
    assert.strictEqual(await halves('.pair-code', '.qr'), true)
    await shot('tv-pair')
  })
  await step('with Reduce Motion nothing moves by itself, and in forced colours the QR code stays black on white', async () => {
    const { debugger: devtools } = views().page
    if (!devtools.isAttached()) devtools.attach('1.3')
    const media = (name, value) => devtools.sendCommand('Emulation.setEmulatedMedia', { features: [{ name, value }] })
    await media('prefers-reduced-motion', 'reduce')
    assert.strictEqual(await inPage("getComputedStyle(document.querySelector('.waiting .spinner')).animationName"), 'none')
    await media('forced-colors', 'active')
    assert.strictEqual(await inPage("getComputedStyle(document.querySelector('.qr-card')).backgroundColor"), 'rgb(255, 255, 255)')
    await shot('tv-pair-forced-colours')
    devtools.detach()
    noCrash()
  })
}

// A full-screen TV window starts on the connect page, Back with nowhere to go opens the TV menu, and Back closes it.
// Both used to wait for a page loading in a view that wasn't shown, which never finished: a blank TV, then no menu.
async function tvFullScreen() {
  await app.whenReady()
  const connect = () => webContents.getAllWebContents().find((w) => w.getURL().startsWith('wittymedia-app://connect'))
  const menu = () => webContents.getAllWebContents().find((w) => w.getURL().includes('tvmenu'))
  await step('a full-screen TV window opens on the connect page', async () => {
    await until('the connect page', () => connect() && !connect().isLoading(), 20000)
    await until('its heading', () => connect().executeJavaScript("(document.querySelector('h1') || {}).textContent"), 8000)
    assert.strictEqual(await connect().executeJavaScript("document.documentElement.classList.contains('tv')"), true)
  })
  await step('Back with nowhere to go opens the TV menu, and Back closes it', async () => {
    const press = async (to, keyCode) => {
      to.sendInputEvent({ type: 'keyDown', keyCode })
      to.sendInputEvent({ type: 'keyUp', keyCode })
      await wait(100)
    }
    await press(connect(), 'Escape')
    await until('the TV menu', () => menu() && !menu().isLoading() && menu().isFocused(), 8000)
    await press(menu(), 'Escape')
    await until('the page to have the keys again', () => connect().isFocused(), 8000)
  })
}

// Started in this order because Electron must have the app's file before it is ready, and
// a remembered server has to be answering by the time the app asks it who it is.
function start() {
  if (scenario === 'journey') {
    require('../../main.js')
    return run()
  }
  if (scenario === 'tv-full') {
    require('../../main.js')
    return tvFullScreen()
  }
  if (scenario === 'pair' || scenario === 'tv' || scenario === 'code') {
    require('../../main.js')
    return scenario === 'pair' ? approved() : scenario === 'code' ? byCode() : onTv()
  }
  const url = `http://127.0.0.1:${PORT}`
  fs.writeFileSync(path.join(dataDir, 'state.json'), JSON.stringify(SEEDS[scenario](url, rawKey(stand.keys))))
  if (scenario === 'certificate') {
    const tls = selfSigned()
    if (!tls) {
      results.push('skip  no openssl here to make a certificate with')
      return Promise.resolve()
    }
    https.createServer(tls, answerRequest).listen(PORT, '127.0.0.1')
  } else if (scenario !== 'lost') {
    http.createServer(answerRequest).listen(PORT, '127.0.0.1')
  }
  if (scenario === 'forget') http.createServer(answerRequest).listen(PORT + 1)
  require('../../main.js')
  return scenario === 'forget' ? forgetting(url) : seeded(url)
}

start().then(() => 0, (err) => {
  console.error(err)
  try { console.error(fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')) } catch { /* no log yet */ }
  return 1
}).then((code) => {
  console.log(`-- ${scenario}\n${results.join('\n')}`)
  console.log(code ? 'FAILED' : `passed: ${results.length} steps`)
  try { fs.rmSync(dataDir, { recursive: true, force: true, maxRetries: 3 }) } catch { /* the system's temporary folder will do */ }
  app.exit(code)
})
