// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Runs each of the real-app tests in its own Electron, one after the other: see run.js.
const { spawnSync } = require('node:child_process')
const path = require('node:path')
const electron = require('electron')

const run = path.join(__dirname, 'run.js')
const failed = ['journey', 'code', 'pair', 'tv', 'tv-full', 'same', 'other', 'lost', 'damaged', 'certificate', 'forget'].filter((scenario) =>
  spawnSync(electron, [run, scenario], { stdio: 'inherit', windowsHide: false, timeout: 120000 }).status !== 0)
if (failed.length) {
  console.error(`failed: ${failed.join(', ')}`)
  process.exit(1)
}
