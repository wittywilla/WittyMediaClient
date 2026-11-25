// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Every way of adding a server, end to end: the real app, in a data folder of its own each time, against a
// real WittyMediaServer, with nothing stood in for. One way per run:
//
//   --way=found      the server found on the network, chosen, and signed in to with the code from its
//                    Connect a device
//   --way=code       Enter a code, from the list: the servers found are asked, and the one that made it
//                    signs this device in
//   --way=address    Type an address, then the code
//   --way=password   Type an address, then Sign in with a password instead: the server's own sign-in page
//   --way=link       Paste a link: the link (the QR code's) from Connect a device, from away, peer to peer
//   --way=qr         At home, the QR code's link (what scanning it gives): the address the page was opened at and
//                    the code (0.8.5 servers) sign this device in there, with no connection from away
//
//   WMC_SERVER=http://10.91.0.1:19871 WMC_DIRECT=http://... WMC_USER=owner WMC_PASSWORD=... WMC_TEST_DIR=/tmp/x \
//     [WITTYCONNECT=/path/to/wittyconnect] [WMC_SHOTS=/folder] electron test/app/add-server-real.js --way=code
//
// WMC_SERVER is where the app finds the server; WMC_DIRECT where the test itself asks for codes. For "link"
// the app should be unable to reach WMC_SERVER's web port (it's away), and the server must have peer to peer on;
// the D:\build-tools wrapper (remote-access-083/wsl/methods.sh) sets up both, in network namespaces.
const { app, session, webContents } = require('electron')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')

const way = (process.argv.find((a) => a.startsWith('--way=')) || '').slice(6)
const SERVER = process.env.WMC_SERVER
const DIRECT = process.env.WMC_DIRECT || SERVER
const USER = process.env.WMC_USER
const PASSWORD = process.env.WMC_PASSWORD
const DIR = process.env.WMC_TEST_DIR
const SHOTS = process.env.WMC_SHOTS || ''
const WAYS = ['found', 'code', 'address', 'password', 'link', 'qr']
if (!WAYS.includes(way) || !SERVER || !USER || !PASSWORD || !DIR) {
  console.error(`Set WMC_SERVER, WMC_USER, WMC_PASSWORD and WMC_TEST_DIR, and give --way=${WAYS.join('|')}.`)
  process.exit(2)
}
const dataDir = path.join(DIR, way)
fs.rmSync(dataDir, { recursive: true, force: true })
fs.mkdirSync(dataDir, { recursive: true })
app.setPath('userData', dataDir)

const P2P_PAGE = /^http:\/\/p2p-[a-z0-9]{16}\.localhost:\d+\//
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
async function until(what, check, ms = 30000) {
  const end = Date.now() + ms
  let last
  for (;;) {
    try { last = await check(); if (last) return last } catch (err) { last = err }
    if (Date.now() > end) throw new Error(`Waited ${ms / 1000}s for ${what}. Last: ${last && last.message ? last.message : JSON.stringify(last)}`)
    await wait(200)
  }
}
const page = () => webContents.getAllWebContents().find((w) => !w.getURL().includes('titlebar') && !w.getURL().includes('tvmenu'))
const inPage = (code) => page().executeJavaScript(code)
const heading = () => inPage("(document.querySelector('h1') || {}).textContent")
const S = (() => {
  const holder = {}
  new Function('self', fs.readFileSync(path.join(__dirname, '..', '..', 'connect', 'strings.js'), 'utf8'))(holder)
  return holder.WittyStrings
})()
const onHeading = (text, ms) => until(`the screen "${text}"`, async () => (await heading()) === text, ms)
const click = (text) => inPage(`(() => { const b = Array.from(document.querySelectorAll('button')).find((b) => b.textContent.trim().startsWith(${JSON.stringify(text)})); if (!b) return false; b.click(); return true })()`)
const typeInto = (id, text) => inPage(`(() => { const i = document.getElementById(${JSON.stringify(id)}); i.value = ${JSON.stringify(text)}; return true })()`)
async function shot(name) {
  if (!SHOTS) return
  await wait(400)
  fs.mkdirSync(SHOTS, { recursive: true })
  fs.writeFileSync(path.join(SHOTS, `${name}.png`), (await page().capturePage()).toPNG())
}

const json = { 'Content-Type': 'application/json' }
async function signedIn() {
  const login = await fetch(`${DIRECT}/api/login`, { method: 'POST', headers: json, body: JSON.stringify({ name: USER, password: PASSWORD }) })
  assert.ok(login.ok, `the password wasn't accepted: ${login.status}`)
  const { token } = await login.json()
  return { ...json, Authorization: `Bearer ${token}` }
}
// What Connect a device shows: an administrator's takes the password again. `at` is the address the page is
// opened at, which the QR code holds for a device at home.
async function offer(at = DIRECT) {
  const res = await fetch(`${at}/api/connect/offer`, { method: 'POST', headers: await signedIn(), body: JSON.stringify({ password: PASSWORD, otp: process.env.WMC_OTP || '' }) })
  if (!res.ok) assert.fail(`no code: ${res.status} ${await res.text()}`)
  return res.json()
}

const passed = []
async function step(name, run) {
  await run()
  passed.push(name)
  console.log(`ok    ${name}`)
}

// Signed in, as the server sees it, at the page the app shows.
async function onServerSignedIn(ms = 30000) {
  await until('the server\'s own page, signed in', async () => !page().getURL().startsWith('wittymedia-app:')
    && (await inPage("fetch('/api/v1/me').then((r) => r.status, () => 0)")) === 200, ms)
  const me = await inPage("fetch('/api/v1/me').then((r) => r.json())")
  assert.strictEqual(me.name, USER, 'signed in as whoever made the code')
  const origin = new URL(page().getURL()).origin
  const [cookie] = await session.defaultSession.cookies.get({ url: origin, name: 'wms_token' })
  assert.ok(cookie && cookie.httpOnly, 'the sign-in is a cookie no page can read')
  assert.strictEqual(await inPage("document.cookie.includes('wms_token')"), false)
  return origin
}
const savedState = () => { try { return JSON.parse(fs.readFileSync(path.join(dataDir, 'state.json'), 'utf8')) } catch { return {} } }

async function run() {
  await app.whenReady()
  await until('the connect page', () => page() && page().getURL().includes('connect') && inPage("!!document.querySelector('h1')"))
  await onHeading(S.addTitle)
  await shot(`${way}-1-list`)
  const host = SERVER.replace(/^https?:\/\//, '')

  if (way === 'found' || way === 'code' || way === 'address') {
    const made = await offer()
    assert.match(made.code, /^[0-9A-Z]{4}-[0-9A-Z]{4}$/)
    if (way === 'found') {
      await step('the server is found on the network, with its address and nothing more', async () => {
        await until('a server found on the network', () => inPage(`Array.from(document.querySelectorAll('button.server')).some((b) => b.textContent.includes(${JSON.stringify(host)}) && b.textContent.includes(${JSON.stringify(S.foundOnNetwork)}))`), 30000)
        await shot('found-2-found')
        await inPage(`Array.from(document.querySelectorAll('button.server')).find((b) => b.textContent.includes(${JSON.stringify(host)})).click()`)
      })
    } else if (way === 'address') {
      await step('its address is typed, and it is asked who it is', async () => {
        assert.ok(await click(S.wayAddress))
        await onHeading(S.addressTitle)
        await typeInto('address', host)
        await shot('address-2-typed')
        assert.ok(await click(S.connect))
      })
    }
    if (way === 'code') {
      await step('Enter a code: the code from Connect a device, typed loosely', async () => {
        assert.ok(await click(S.wayCode))
        await onHeading(S.codeEnterTitle)
        await typeInto('code', ` ${made.code.toLowerCase().replace('-', ' ')} `)
        await shot('code-2-typed')
        assert.ok(await click(S.connect))
      })
    } else {
      await step('the server proved who it is, and asks for the code', async () => {
        await onHeading(S.codeSignInTitle, 20000)
        assert.ok((await inPage('document.body.innerText')).includes(S.signInPassword))
        await typeInto('code', made.code)
        await shot(`${way}-3-sign-in`)
        assert.ok(await click(S.connect))
      })
    }
    let origin
    await step('the server that made the code signs this device in, and it is remembered by its address', async () => {
      origin = await onServerSignedIn()
      assert.strictEqual(origin, new URL(SERVER).origin)
      const s = savedState()
      assert.strictEqual(s.server, origin)
      assert.ok(s.recent[0].publicKey, 'with the key it proved')
      await shot(`${way}-4-signed-in`)
    })
    await step('the code is spent', async () => {
      const again = await fetch(`${DIRECT}/api/connect/offer`, { method: 'DELETE', headers: await signedIn() })
      assert.ok(again.ok)
      const sessions = await (await fetch(`${DIRECT}/api/v1/sessions`, { headers: await signedIn() })).json()
      assert.ok(sessions.some((x) => /WittyMediaClient/.test(x.device || '')), JSON.stringify(sessions).slice(0, 400))
    })
  } else if (way === 'password') {
    await step('its address is typed, and Sign in with a password opens its own sign-in page', async () => {
      assert.ok(await click(S.wayAddress))
      await onHeading(S.addressTitle)
      await typeInto('address', host)
      assert.ok(await click(S.connect))
      await onHeading(S.codeSignInTitle, 20000)
      assert.ok(await click(S.signInPassword))
      await until('the server\'s sign-in page', async () => page().getURL().startsWith(SERVER) && (await inPage("!!document.querySelector('input[type=password], button')")), 30000)
      await shot('password-3-server-sign-in')
      // Its own sign-in: who's watching first, then that profile's password.
      await until('the password field', async () => {
        if (await inPage("!!document.querySelector('input[type=password]')")) return true
        await inPage(`(() => { const b = Array.from(document.querySelectorAll('button, a')).find((x) => x.textContent.trim().endsWith(${JSON.stringify(USER)})); if (b) b.click() })()`)
        return false
      }, 30000)
    })
    await step('the password signs in there', async () => {
      await inPage(`(() => {
        const set = (el, v) => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, v); el.dispatchEvent(new Event('input', { bubbles: true })) }
        const name = document.querySelector('input[autocomplete=username], input[name=username], input[type=text]')
        if (name) set(name, ${JSON.stringify(USER)})
        set(document.querySelector('input[type=password]'), ${JSON.stringify(PASSWORD)})
        Array.from(document.querySelectorAll('button')).find((b) => b.textContent.trim() === 'Sign in').click()
      })()`)
      await onServerSignedIn()
      await shot('password-4-signed-in')
    })
  } else if (way === 'link') {
    let made
    await step('Paste a link: the link the QR code holds, from Connect a device', async () => {
      await assert.rejects(fetch(`${SERVER}/api/status`, { signal: AbortSignal.timeout(3000) }), 'the test needs the server\'s web port out of reach: this device is away')
      made = await offer()
      assert.ok(made.away && /^wittymedia:\/\/p2p\//.test(made.link), `peer to peer is on, so there is a link: ${JSON.stringify(made).slice(0, 200)}`)
      assert.ok(await click(S.wayLink))
      await onHeading(S.linkTitle)
      await typeInto('address', made.link)
      await shot('link-2-pasted')
      assert.ok(await click(S.connect))
    })
    await step('the app finds the server peer to peer, joins, and is signed in', async () => {
      await until('the server, at the helper\'s address', () => P2P_PAGE.test(page().getURL()), 90000)
      const origin = await onServerSignedIn(60000)
      const s = savedState()
      assert.ok(P2P_PAGE.test(`${s.server}/`), 'a server only known from away is remembered by the helper\'s address')
      assert.ok(s.recent[0].publicKey && s.recent[0].p2p, 'with the key it proved, and how to reach it again')
      const sessions = await inPage("fetch('/api/v1/sessions').then((r) => r.json())")
      const us = sessions.find((x) => x.current) || sessions[0]
      assert.match(us.via, /^p2p/, `it came peer to peer: ${us.via}`)
      assert.ok(origin)
      await shot('link-4-signed-in')
    })
    await step('the link and the code beside it are spent', async () => {
      const devices = await (await fetch(`${DIRECT}/api/v1/p2p/devices`, { headers: await signedIn() })).json()
      assert.ok(devices.some((d) => d.how === 'invite'), JSON.stringify(devices).slice(0, 300))
    })
  } else if (way === 'qr') {
    await step('At home, the QR code: it holds the address its page was opened at and the code', async () => {
      const made = await offer(SERVER)
      const qr = made.qrLink || ''
      const hidden = qr.replace(/([?&][sc]=)[^&]*/g, '$1…')
      assert.ok(/[?&]h=/.test(qr) && /[?&]c=/.test(qr), `the QR code holds the address at home and the code: ${hidden}`)
      assert.strictEqual(new URL(qr).searchParams.get('h'), new URL(SERVER).origin, `the address the page was opened at: ${hidden}`)
      assert.ok(await click(S.wayLink))
      await onHeading(S.linkTitle)
      await typeInto('address', qr)
      await shot('qr-2-pasted')
      assert.ok(await click(S.connect))
    })
    await step('the server there signs this device in, at its own address, not peer to peer', async () => {
      const origin = await onServerSignedIn()
      assert.strictEqual(origin, new URL(SERVER).origin)
      const s = savedState()
      assert.strictEqual(s.server, origin)
      assert.ok(s.recent[0].publicKey, 'with the key it proved')
      const sessions = await inPage("fetch('/api/v1/sessions').then((r) => r.json())")
      const us = sessions.find((x) => x.current) || sessions[0]
      assert.doesNotMatch(String(us.via || ''), /^p2p/, `it came to the web port: ${us.via}`)
      await shot('qr-4-signed-in')
    })
  }
  const log = fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8')
  assert.ok(!/"kind":"crash"/.test(log), `nothing went unhandled: ${log}`)
}

require(path.join(__dirname, '..', '..', 'main.js'))
run().then(() => {
  console.log(`RESULT ${way}: WORKS (${passed.length} steps) on ${process.platform} ${process.arch}, Electron ${process.versions.electron}`)
  app.exit(0)
}).catch(async (err) => {
  try { await shot(`${way}-9-failed`) } catch { /* no page */ }
  let words = ''
  try { words = await inPage("document.body.innerText.replace(/\\s+/g, ' ').slice(0, 500)") } catch { /* no page */ }
  console.error(`RESULT ${way}: FAILS after ${passed.length} steps: ${err.stack || err.message}\n  The screen says: ${words}`)
  try { console.error(fs.readFileSync(path.join(dataDir, 'logs', 'client.log'), 'utf8').split('\n').slice(-15).join('\n')) } catch { /* no log */ }
  app.exit(1)
})
