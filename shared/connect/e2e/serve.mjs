// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The connect screen as the apps carry it (desktop/scripts/sync-shared.mjs): its files, the wording as a
// script and the family's marks, served on 127.0.0.1 for the browser tests. `node serve.mjs <port>`.
import { createServer } from 'node:http'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, extname, join, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const connect = join(here, '..')
const shared = join(connect, '..')
const port = Number(process.argv[2] || 18095)
const mark = (name) => `data:image/svg+xml;base64,${readFileSync(join(shared, 'brand', `mark-${name}.svg`)).toString('base64')}`
const made = {
  '/strings.js': () => `self.WittyStrings = ${readFileSync(join(shared, 'data', 'strings.en.json'), 'utf8').trim()}\n`,
  '/brand.js': () => `self.WittyBrand = ${JSON.stringify({ client: mark('client'), server: mark('server') })}\n`,
}
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }
createServer((req, res) => {
  const path = new URL(req.url, 'http://x').pathname
  const file = normalize(join(connect, path))
  const body = made[path] ? made[path]() : file.startsWith(connect) && !file.includes('e2e') && existsSync(file) && extname(file) ? readFileSync(file) : null
  if (!body) { res.writeHead(404); res.end(); return }
  res.writeHead(200, { 'Content-Type': (TYPES[extname(path)] || 'application/octet-stream') + '; charset=utf-8' })
  res.end(body)
}).listen(port, '127.0.0.1', () => console.log(`connect screen on http://127.0.0.1:${port}`))
