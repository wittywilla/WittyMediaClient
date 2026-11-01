#!/usr/bin/env node
// Asks the running app to quit properly, through Chromium's debugging port.
//
//   node app-close.mjs <port>
const port = process.argv[2]
const info = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json()
const ws = new WebSocket(info.webSocketDebuggerUrl)
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject })
ws.send(JSON.stringify({ id: 1, method: 'Browser.close' }))
await new Promise((resolve) => { ws.onclose = resolve; setTimeout(resolve, 5000) })
process.exit(0)
