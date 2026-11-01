#!/usr/bin/env node
// Looks inside the running app through Chromium's debugging port, which the test started it with.
// Checks that it really opened: its windows, what they show, and that a page can't reach the app.
//
//   node app-smoke.mjs <port> [screenshot.png]
//
// Needs Node 22 or newer for its built-in WebSocket.
import { writeFileSync } from 'node:fs'

const [port, shot] = process.argv.slice(2)
const fail = (why) => { console.error(`FAIL: ${why}`); process.exit(1) }
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

async function targets() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
      if (list.filter((t) => t.type === 'page').length >= 2) return list
    } catch { /* not up yet */ }
    await sleep(1000)
  }
  fail('the app never showed its pages on the debugging port')
}

function connect(url) {
  const ws = new WebSocket(url)
  let next = 1
  const waiting = new Map()
  ws.onmessage = (m) => {
    const data = JSON.parse(m.data)
    if (data.id && waiting.has(data.id)) { waiting.get(data.id)(data); waiting.delete(data.id) }
  }
  return new Promise((resolve) => {
    ws.onopen = () => resolve({
      send: (method, params = {}) => new Promise((done) => {
        const id = next++
        waiting.set(id, done)
        ws.send(JSON.stringify({ id, method, params }))
      }),
      eval: async function (expression) {
        const r = await this.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
        if (r.result.exceptionDetails) fail(`evaluating ${expression}: ${JSON.stringify(r.result.exceptionDetails)}`)
        return r.result.result.value
      },
      close: () => ws.close(),
    })
  })
}

const list = await targets()
const bar = list.find((t) => t.url.includes('titlebar/index.html'))
const content = list.find((t) => t.url.includes('connect/index.html'))
if (!bar) fail(`no title bar: ${JSON.stringify(list.map((t) => t.url))}`)
if (!content) fail(`no connect screen: ${JSON.stringify(list.map((t) => t.url))}`)

const barPage = await connect(bar.webSocketDebuggerUrl)
const shown = await barPage.eval('document.getElementById("title").textContent')
console.log(`title bar says: ${shown}`)
if (shown !== 'WittyMediaClient') fail('the title bar has the wrong name')
barPage.close()

const page = await connect(content.webSocketDebuggerUrl)
for (let i = 0; i < 30; i++) {
  if (await page.eval('document.readyState') === 'complete') break
  await sleep(500)
}
const text = await page.eval('document.body.innerText')
console.log(`connect screen says: ${text.replace(/\s+/g, ' ').slice(0, 120)}`)
if (!text.trim()) fail('the connect screen is empty')
const reach = await page.eval('[typeof require, typeof process, typeof module].join()')
console.log(`what the page can reach of Node: ${reach}`)
if (reach !== 'undefined,undefined,undefined') fail('the page can reach Node')
const info = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()
console.log(`browser: ${info.Browser}`)
if (shot) {
  const r = await page.send('Page.captureScreenshot', { format: 'png' })
  writeFileSync(shot, Buffer.from(r.result.data, 'base64'))
}
page.close()
console.log('OPENED')
