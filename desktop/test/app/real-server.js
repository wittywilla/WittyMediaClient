// Runs the real app against a real WittyMediaServer, with key presses alone, and plays a video.
// For platforms only reachable in a virtual machine or on a device, so nothing here assumes much:
//
//   WMC_SERVER=http://10.0.2.2:8096 WMC_USER=me WMC_PASSWORD=... npm run test:real -- --tv
//
// The server needs a film in its first library. The password is only used to ask the server
// for a security code, as someone would on its /pair page. WMC_SHOTS is a folder for pictures,
// and WMC_APP is an installed app.asar to test instead of this folder.
const { app, webContents } = require('electron')
const assert = require('node:assert')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')

const SERVER = process.env.WMC_SERVER
const USER = process.env.WMC_USER
const PASSWORD = process.env.WMC_PASSWORD
const SHOTS = process.env.WMC_SHOTS || ''
const TV = process.argv.includes('--tv')
if (!SERVER || !USER || !PASSWORD) {
  console.error('Set WMC_SERVER, WMC_USER and WMC_PASSWORD.')
  process.exit(2)
}

const dataDir = fs.mkdtempSync(path.join(process.env.WMC_TEST_DIR || os.tmpdir(), 'wmc-real-'))
app.setPath('userData', dataDir)

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
async function until(what, check, ms = 30000) {
  const end = Date.now() + ms
  let last
  for (;;) {
    try {
      last = await check()
      if (last) return last
    } catch (err) { last = err }
    if (Date.now() > end) throw new Error(`Waited for ${what}. Last: ${last && last.message ? last.message : JSON.stringify(last)}`)
    await wait(100)
  }
}

const all = () => webContents.getAllWebContents()
const page = () => all().find((w) => !w.getURL().includes('titlebar'))
const tvMenu = () => all().find((w) => w.getURL().includes('tvmenu'))
const inPage = (code) => page().executeJavaScript(code)
const focused = () => inPage("(document.activeElement.innerText || document.activeElement.getAttribute('aria-label') || document.activeElement.id || document.activeElement.tagName).trim().slice(0, 60)")

async function press(keyCode, to = page()) {
  to.sendInputEvent({ type: 'keyDown', keyCode })
  // A button acts on the character a key makes, and Enter makes one too.
  if (keyCode.length === 1 || keyCode === 'Enter') to.sendInputEvent({ type: 'char', keyCode: keyCode === 'Enter' ? '\r' : keyCode })
  to.sendInputEvent({ type: 'keyUp', keyCode })
  await wait(250)
}

async function shot(name, from = page()) {
  if (!SHOTS) return
  await wait(400)
  fs.mkdirSync(SHOTS, { recursive: true })
  const image = await until(`a picture of ${name}`, () => from.capturePage().then((i) => (i.isEmpty() ? null : i)))
  fs.writeFileSync(path.join(SHOTS, `${name}.png`), image.toPNG())
}

const passed = []
async function step(name, run) {
  await run()
  passed.push(name)
  console.log(`ok    ${name}`)
}

// Moves with one arrow at a time until focus is where it's wanted, as a remote has to.
async function arrowTo(what, isThere, keys = ['Down'], tries = 30) {
  const trail = []
  for (let i = 0; i < tries; i++) {
    if (await inPage(`(() => { const el = document.activeElement; return (${isThere})(el) })()`)) return
    const key = keys[i % keys.length]
    await press(key)
    trail.push(`${key}: ${await focused()}`)
  }
  throw new Error(`The arrows never reached ${what}. They went:\n      ${trail.join('\n      ')}`)
}

// Heads for something on the screen, the way someone holding a remote would.
async function arrowTowards(what, finder, tries = 25) {
  const trail = []
  for (let i = 0; i < tries; i++) {
    const way = await inPage(`(() => {
      const target = ${finder}
      if (!target) return 'none'
      if (document.activeElement === target || target.contains(document.activeElement)) return 'here'
      const a = document.activeElement.getBoundingClientRect(), b = target.getBoundingClientRect()
      if (a.bottom <= b.top) return 'Down'
      if (a.top >= b.bottom) return 'Up'
      return a.right <= b.left ? 'Right' : 'Left'
    })()`)
    if (way === 'here') return
    await press(way === 'none' ? 'Down' : way)
    trail.push(`${way}: ${await focused()}`)
  }
  throw new Error(`The arrows never reached ${what}. They went: ${trail.join(', ')}`)
}

async function securityCode() {
  const headers = { 'Content-Type': 'application/json' }
  const login = await fetch(`${SERVER}/api/login`, { method: 'POST', headers, body: JSON.stringify({ name: USER, password: PASSWORD }) })
  assert.ok(login.ok, `the password wasn't accepted: ${login.status}`)
  const { token, user } = await login.json()
  const invite = await fetch(`${SERVER}/api/pair/invite`, { method: 'POST', headers: { ...headers, Authorization: `Bearer ${token}` }, body: JSON.stringify({ userId: user.id }) })
  assert.ok(invite.ok, `no code was given: ${invite.status}`)
  return String((await invite.json()).code).replace(/\D/g, '')
}

async function run() {
  await app.whenReady()
  await until('the connect page', () => page() && page().getURL().includes('connect'))

  await step('the connect screen opens', async () => {
    await until('its heading', () => inPage("document.querySelector('h1') && document.querySelector('h1').textContent"))
    await shot('01-connect')
  })

  await step('the arrows reach "Enter an address", and an address can be typed', async () => {
    await arrowTo('Enter an address', "(el) => el.tagName === 'BUTTON' && el.textContent.startsWith('Enter an address')")
    await press('Enter')
    await until('the address box', () => inPage("document.activeElement.id === 'address'"))
    for (const c of SERVER.replace(/^http:\/\//, '')) await press(c)
    await shot('02-address')
    await press('Enter')
  })

  await step('the server is recognised, and asks for a code', async () => {
    await until('the number pad', () => inPage("!!document.querySelector('.pad')"))
    await shot('03-code')
  })

  await step('a real security code signs in', async () => {
    for (const digit of await securityCode()) await press(digit)
    await until('the server page', () => page().getURL().startsWith(SERVER))
    await until('the page to draw', () => inPage("!!document.querySelector('.content, main')"))
    await wait(1500)
    if (TV) {
      assert.ok(await inPage("document.documentElement.classList.contains('ten-foot')"), 'the server is in big screen mode')
      const size = await inPage('parseFloat(getComputedStyle(document.body).fontSize)')
      console.log(`      body text is ${size}px at ${await inPage('innerWidth')}x${await inPage('innerHeight')}`)
    }
    await shot('04-home')
  })

  await step('the arrows and OK reach a film', async () => {
    await arrowTowards('a film', "document.querySelector('a[href*=\"/item/\"], a[href*=\"/show/\"]')")
    await shot('05-focus-on-card')
    await press('Enter')
    await until('its page', () => inPage("!!Array.from(document.querySelectorAll('button')).find((b) => /play|resume/i.test(b.innerText))"))
    await shot('06-item')
  })

  await step('the arrows and OK start it playing', async () => {
    await arrowTowards('Play', "Array.from(document.querySelectorAll('button')).find((b) => /^(play|resume)/i.test(b.innerText.trim()))")
    await press('Enter')
    await until('a video', () => inPage("!!document.querySelector('video') && document.querySelector('video').readyState >= 2"), 45000)
  })

  await step('the video really plays: its clock moves and frames are decoded', async () => {
    const reading = "(() => { const v = document.querySelector('video'); const q = v.getVideoPlaybackQuality(); return { time: v.currentTime, paused: v.paused, frames: q.totalVideoFrames, dropped: q.droppedVideoFrames, width: v.videoWidth, height: v.videoHeight, src: v.currentSrc.replace(/\\?.*/, '') } })()"
    const first = await inPage(reading)
    await wait(6000)
    const later = await inPage(reading)
    console.log(`      ${JSON.stringify(first)}\n      ${JSON.stringify(later)}`)
    assert.ok(later.time > first.time + 2, 'the clock moved')
    assert.ok(later.frames > first.frames, 'frames were decoded')
    assert.ok(later.width > 0 && later.height > 0, 'it has a picture')
    await shot('07-playing')
    if (SHOTS) {
      // The middle of a real frame, drawn by the page: all one colour would mean no picture.
      const spread = await inPage("(() => { const v = document.querySelector('video'); const c = document.createElement('canvas'); c.width = 64; c.height = 36; const g = c.getContext('2d'); g.drawImage(v, 0, 0, 64, 36); const d = g.getImageData(0, 0, 64, 36).data; const seen = new Set(); for (let i = 0; i < d.length; i += 4) seen.add(d[i] >> 4 | (d[i + 1] >> 4) << 4 | (d[i + 2] >> 4) << 8); return seen.size })()")
      console.log(`      ${spread} different colours in a frame`)
      assert.ok(spread > 8, 'the frame has a picture in it')
    }
  })

  await step('Back leaves the player', async () => {
    await press('Escape')
    await until('the player to step aside', () => inPage("!document.querySelector('.player:not(.mini):not(.inline)')"), 8000)
    await shot('08-after-back')
  })

  if (TV) {
    await step('Back all the way out reaches the menu, and never the connect screen', async () => {
      await until('the menu', async () => {
        if (tvMenu()) return true
        await press('Escape')
        return false
      }, 15000)
      assert.ok(page().getURL().startsWith(SERVER), 'still on the server')
      await until('its first button', () => tvMenu().executeJavaScript("document.activeElement.id === 'stay'"))
      await shot('09-menu', tvMenu())
    })
    await step('the menu works with arrows, and Back closes it', async () => {
      await press('Down', tvMenu())
      assert.strictEqual(await tvMenu().executeJavaScript('document.activeElement.id'), 'change')
      await press('Down', tvMenu())
      assert.strictEqual(await tvMenu().executeJavaScript('document.activeElement.id'), 'quit')
      await press('Escape', tvMenu())
      await wait(300)
      assert.strictEqual(await page().executeJavaScript('document.hasFocus()'), true, 'focus is back on the page')
    })
  }
  const log = fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')
  assert.ok(!/"kind":"crash"/.test(log), `nothing went unhandled: ${log}`)
}

require(path.join(process.env.WMC_APP || path.join(__dirname, '..', '..'), 'main.js'))
run().then(() => {
  console.log(`\nAll ${passed.length} passed on ${process.platform} ${process.arch}, Electron ${process.versions.electron}, Chromium ${process.versions.chrome}.`)
  fs.rmSync(dataDir, { recursive: true, force: true })
  app.exit(0)
}).catch((err) => {
  console.error(`\nFAILED after ${passed.length} passed: ${err.message}`)
  if (SHOTS) shot('failed').catch(() => {}).finally(() => app.exit(1))
  else app.exit(1)
})
