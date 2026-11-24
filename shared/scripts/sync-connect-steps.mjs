#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The steps of connecting from away and why one fails belong to the server (pkg/connectsteps/steps.json): its
// Recent tries uses the same codes the apps show. The apps keep a copy in shared/data. This copies it; with --check
// (CI) it fails when the copy differs. A server branch without the file yet is only a warning.
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const server = process.env.WMS_CONNECT_STEPS || join(here, '..', '..', '..', 'WittyMediaServer', 'pkg', 'connectsteps')
const from = join(server, 'steps.json')
const to = join(here, '..', 'data', 'connect-steps.json')
if (!existsSync(from)) {
  console.warn(`::warning::no connect steps at ${from}: the server branch doesn't have them yet`)
  process.exit(0)
}
const want = readFileSync(from, 'utf8').replace(/\r\n/g, '\n')
JSON.parse(want)
if (process.argv.includes('--check')) {
  const have = existsSync(to) ? readFileSync(to, 'utf8').replace(/\r\n/g, '\n') : ''
  if (have !== want) {
    console.error('shared/data/connect-steps.json differs from the server\'s: run node shared/scripts/sync-connect-steps.mjs')
    process.exit(1)
  }
  console.log('connect steps: the same as the server\'s')
} else {
  writeFileSync(to, want)
  console.log('connect steps copied from', from)
}
