// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Runs the real app against a real WittyMediaServer that has peer-to-peer connections on,
// with the real connection helper. Three runs, each a start of the app:
//
//   --phase=home     signs in at the server's address, and waits until the app has put this
//                    device on the server's list and remembered how to reach it from away
//   --phase=away     the same data folder, with that address no longer answering: the app
//                    has to find the server peer to peer by itself, still signed in
//   --phase=invite   a fresh data folder: an invite link pasted on the connect screen
//
//   WMC_SERVER=http://127.0.0.1:19799 WMC_USER=owner WMC_PASSWORD=... WITTYCONNECT=/path/to/wittyconnect \
//     WMC_TEST_DIR=/tmp/wmc-p2p electron test/app/p2p-real.js --phase=home
//
// WMC_SERVER is where the app is told the server is. For "away" to mean anything it should be
// a forwarder to the server that is stopped between the first run and the second, and
// WMC_DIRECT the server's own address, which the test (not the app) keeps using.
const { app, session, webContents } = require('electron')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')

const phase = (process.argv.find((a) => a.startsWith('--phase=')) || '').slice(8)
const SERVER = process.env.WMC_SERVER
const DIRECT = process.env.WMC_DIRECT || SERVER
const USER = process.env.WMC_USER
const PASSWORD = process.env.WMC_PASSWORD
const DIR = process.env.WMC_TEST_DIR
if (!['home', 'away', 'invite'].includes(phase) || !SERVER || !USER || !PASSWORD || !DIR || !process.env.WITTYCONNECT) {
  console.error('Set WMC_SERVER, WMC_USER, WMC_PASSWORD, WMC_TEST_DIR and WITTYCONNECT, and give --phase=home|away|invite.')
  process.exit(2)
}
const dataDir = path.join(DIR, phase === 'invite' ? 'invite' : 'paired')
if (phase !== 'away') fs.rmSync(dataDir, { recursive: true, force: true })
fs.mkdirSync(dataDir, { recursive: true })
app.setPath('userData', dataDir)

const P2P_PAGE = /^http:\/\/p2p-[a-z0-9]{16}\.localhost:\d+\//
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
    await wait(150)
  }
}
const all = () => webContents.getAllWebContents()
const page = () => all().find((w) => !w.getURL().includes('titlebar') && !w.getURL().includes('tvmenu'))
const bar = () => all().find((w) => w.getURL().includes('titlebar'))
const inPage = (code) => page().executeJavaScript(code)
async function press(keyCode) {
  page().sendInputEvent({ type: 'keyDown', keyCode })
  if (keyCode.length === 1 || keyCode === 'Enter') page().sendInputEvent({ type: 'char', keyCode: keyCode === 'Enter' ? '\r' : keyCode })
  page().sendInputEvent({ type: 'keyUp', keyCode })
  await wait(200)
}
const passed = []
async function step(name, run) {
  await run()
  passed.push(name)
  console.log(`ok    ${name}`)
}

const json = { 'Content-Type': 'application/json' }
async function signedIn() {
  const login = await fetch(`${DIRECT}/api/login`, { method: 'POST', headers: json, body: JSON.stringify({ name: USER, password: PASSWORD }) })
  assert.ok(login.ok, `the password wasn't accepted: ${login.status}`)
  const { token, user } = await login.json()
  return { token, user, headers: { ...json, Authorization: `Bearer ${token}` } }
}
const savedState = () => { try { return JSON.parse(fs.readFileSync(path.join(dataDir, 'state.json'), 'utf8')) } catch { return {} } }

// way is the button that opens the box: Enter an address, or Connect from anywhere's Join with a link or code.
async function typeIntoAddress(text, way = 'Enter an address') {
  await until('the connect page', () => page() && page().getURL().includes('connect'))
  await until('its heading', () => inPage("!!document.querySelector('h1')"))
  for (let i = 0; i < 30 && !(await inPage(`document.activeElement.tagName === 'BUTTON' && document.activeElement.textContent.startsWith(${JSON.stringify(way)})`)); i++) await press('Down')
  await press('Enter')
  await until('the address box', () => inPage("document.activeElement.id === 'address'"))
  await inPage(`document.getElementById('address').value = ${JSON.stringify(text)}`)
  await press('Enter')
}

// What the server says about a request made by the page itself.
async function howTheServerSeesUs() {
  const sessions = await inPage("fetch('/api/v1/sessions').then((r) => r.json())")
  return sessions.find((s) => s.current) || sessions[0]
}

async function reachedPeerToPeer() {
  await until('the server, at the helper\'s address', () => P2P_PAGE.test(page().getURL()), 90000)
  await until('the server\'s own page', () => inPage("document.title.length > 0 && !!document.getElementById('root')"))
  const origin = new URL(page().getURL()).origin
  const us = await until('a signed-in answer', async () => {
    const s = await howTheServerSeesUs()
    return s && s.where ? s : null
  })
  assert.strictEqual(us.where, 'internet', 'the server counts this connection as away from home')
  assert.match(us.via, /^p2p/, `it came peer to peer: ${us.via}`)
  assert.ok(!/^(127\.|10\.|192\.168\.|::1)/.test(us.ip), `and not under an address of this computer or network: ${us.ip}`)
  // The helper's address is of no use to any other program: it wants the secret, which
  // sits in a cookie this page's scripts can't read.
  const bare = await fetch(`http://127.0.0.1:${new URL(origin).port}/api/status`)
  assert.strictEqual(bare.status, 403, 'another program gets nothing from the helper')
  const [secret] = await session.defaultSession.cookies.get({ url: origin, name: 'wittyconnect' })
  assert.ok(secret && secret.httpOnly, 'the secret is kept where no script can read it')
  assert.strictEqual(await inPage("document.cookie.includes('wittyconnect')"), false)
  const words = await until('the path in the title bar', () => bar().executeJavaScript("document.getElementById('path').textContent"))
  assert.match(words, /^Peer to peer/, words)
  return { origin, words, us }
}

async function run() {
  await app.whenReady()
  if (phase === 'home') {
    await step('at home: the server is found at its address and a code signs in', async () => {
      await typeIntoAddress(SERVER.replace(/^http:\/\//, ''))
      await until('the number pad', () => inPage("!!document.querySelector('.pad')"))
      const me = await signedIn()
      // A code that signs the device in as an administrator takes that administrator's password
      // again (WMC_OTP too, for an account with two-factor sign-in), as an invite link does.
      const invite = await fetch(`${DIRECT}/api/pair/invite`, { method: 'POST', headers: me.headers, body: JSON.stringify({ userId: me.user.id, password: PASSWORD, otp: process.env.WMC_OTP || '' }) })
      assert.ok(invite.ok, `no code: ${invite.status}`)
      for (const digit of String((await invite.json()).code).replace(/\D/g, '')) await press(digit)
      await until('the server page', () => page().getURL().startsWith(SERVER))
    })
    await step('within a minute the app has put this device on the server\'s list, by itself', async () => {
      const entry = await until('what it remembers', () => (savedState().recent || []).find((s) => s.p2p && s.p2p.id), 60000)
      assert.match(entry.p2p.id, /^12D3KooW/)
      assert.ok(entry.p2p.hints.length > 0, 'with somewhere to look for it')
      const me = await signedIn()
      const devices = await (await fetch(`${DIRECT}/api/v1/p2p/devices`, { headers: me.headers })).json()
      assert.ok(devices.some((d) => /WittyMediaClient/.test(d.name)), JSON.stringify(devices))
      const key = JSON.parse(fs.readFileSync(path.join(dataDir, 'p2p-key.json'), 'utf8'))
      assert.ok(key.deviceId && (key.sealed || key.key), 'and has a key of its own, kept in its data folder')
    })
  } else if (phase === 'away') {
    await step('away: the address no longer answers, and the app says it is reaching the server from away', async () => {
      await assert.rejects(fetch(`${SERVER}/api/status`, { signal: AbortSignal.timeout(3000) }), 'the test needs the home address to be gone')
      await until('the waiting screen or the server', () => page() && (page().getURL().includes('away=1') || P2P_PAGE.test(page().getURL())), 20000)
    })
    await step('it finds the server peer to peer and is still signed in', async () => {
      const got = await reachedPeerToPeer()
      console.log(`      ${got.words}; the server sees ${got.us.ip} (${got.us.where}, ${got.us.via})`)
      const me = await inPage("fetch('/api/v1/me').then((r) => r.status)")
      assert.strictEqual(me, 200, 'the sign-in made at home works here')
    })
    await step('the home address is still how the server is remembered', async () => {
      const s = savedState()
      assert.strictEqual(s.server, SERVER)
      assert.ok(s.recent[0].p2p.port > 1023, 'with the port the helper used, for next time')
    })
  } else {
    let link
    await step('an invite link pasted on the connect screen is accepted', async () => {
      const me = await signedIn()
      // An invite that signs the device in as an administrator takes that administrator's
      // password again (WMC_OTP too, for an account with two-factor sign-in).
      const made = await fetch(`${DIRECT}/api/v1/p2p/invite`, { method: 'POST', headers: me.headers, body: JSON.stringify({ password: PASSWORD, otp: process.env.WMC_OTP || '' }) })
      assert.ok(made.ok, `no invite: ${made.status}`)
      link = (await made.json()).link
      await typeIntoAddress(link, 'Join with a link or code')
    })
    await step('the app joins, signs in with the code that comes back, and shows the server', async () => {
      const got = await reachedPeerToPeer()
      console.log(`      ${got.words}; the server sees ${got.us.ip} (${got.us.where}, ${got.us.via})`)
      const s = savedState()
      assert.ok(P2P_PAGE.test(s.server + '/'), 'a server only known from away is remembered by the helper\'s address')
      assert.ok(s.recent[0].publicKey, 'with the key it proved')
    })
    await step('the invite is spent', async () => {
      const again = await fetch(`${DIRECT}/api/v1/p2p/devices`, { headers: (await signedIn()).headers })
      const devices = await again.json()
      assert.ok(devices.some((d) => d.how === 'invite'), JSON.stringify(devices))
    })
    await step('Change server signs out, takes the device off the list and stops the helper', async () => {
      const origin = new URL(page().getURL()).origin
      bar().executeJavaScript("document.getElementById('change').click()")
      await until('the connect screen', () => page().getURL().includes('connect'))
      await until('the helper gone', async () => {
        try { await fetch(`http://127.0.0.1:${new URL(origin).port}/`, { signal: AbortSignal.timeout(1000) }); return false } catch { return true }
      }, 10000)
      const devices = await (await fetch(`${DIRECT}/api/v1/p2p/devices`, { headers: (await signedIn()).headers })).json()
      assert.ok(!devices.some((d) => d.how === 'invite'), 'the device is off the server\'s list')
      assert.strictEqual((await session.defaultSession.cookies.get({ url: origin })).length, 0, 'and nothing of the sign-in is left')
    })
  }
  const log = fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')
  assert.ok(!/"kind":"crash"/.test(log), `nothing went unhandled: ${log}`)
}

require(path.join(__dirname, '..', '..', 'main.js'))
run().then(() => {
  console.log(`\nAll ${passed.length} passed (${phase}) on ${process.platform} ${process.arch}, Electron ${process.versions.electron}.`)
  app.exit(0)
}).catch((err) => {
  console.error(`\nFAILED after ${passed.length} passed: ${err.stack || err.message}`)
  try { console.error(fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8').split('\n').slice(-25).join('\n')) } catch { /* no log */ }
  app.exit(1)
})
