#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The settings menu every client draws belongs to the server (pkg/sdui/data/settingsmenu.json, which its catalogue
// carries as settingsMenu). The apps keep a copy in shared/data for a server that doesn't send it yet. This copies
// it; with --check (CI) it fails when the copy differs. A server branch without the file yet is only a warning.
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const server = process.env.WMS_SDUI_DATA || join(here, '..', '..', '..', 'WittyMediaServer', 'pkg', 'sdui', 'data')
const from = join(server, 'settingsmenu.json')
const to = join(here, '..', 'data', 'settingsmenu.json')
if (!existsSync(from)) {
  console.warn(`::warning::no settings menu at ${from}: the server branch doesn't have it yet`)
  process.exit(0)
}
const want = readFileSync(from, 'utf8').replace(/\r\n/g, '\n')
JSON.parse(want)
if (process.argv.includes('--check')) {
  const have = existsSync(to) ? readFileSync(to, 'utf8').replace(/\r\n/g, '\n') : ''
  if (have !== want) {
    console.error('shared/data/settingsmenu.json differs from the server\'s: run node shared/scripts/sync-settings-menu.mjs')
    process.exit(1)
  }
  console.log('settings menu: the same as the server\'s')
} else {
  writeFileSync(to, want)
  console.log('settings menu copied from', from)
}
