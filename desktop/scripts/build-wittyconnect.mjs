#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Builds wittyconnect, the helper that reaches a server from away (p2p.js), into bin/, where
// packaging picks it up and a checkout finds it.
//
// The helper isn't this repository's code. It is part of WittyMediaServer (cmd/wittyconnect,
// under the AGPL-3.0-or-later) and is built from a checkout of that: the folder in
// WITTYMEDIASERVER_SRC, or a WittyMediaServer folder beside this repository. Its
// third-party notices are written beside it, and ship with it.
//
//   node scripts/build-wittyconnect.mjs                 for this computer
//   node scripts/build-wittyconnect.mjs --all           for every system the app is packaged for
//   node scripts/build-wittyconnect.mjs --if-available  don't fail when Go or the server's source is missing
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const desktop = join(here, '..')
const args = process.argv.slice(2)
const lenient = args.includes('--if-available')

// The names electron-builder gives systems and processors, and Go's for the same.
const TARGETS = {
  'mac-arm64': ['darwin', 'arm64'], 'mac-x64': ['darwin', 'amd64'],
  'win-x64': ['windows', 'amd64'], 'linux-x64': ['linux', 'amd64'], 'linux-arm64': ['linux', 'arm64'],
  'freebsd-x64': ['freebsd', 'amd64'], 'freebsd-arm64': ['freebsd', 'arm64'],
}
const OS = { darwin: 'mac', win32: 'win', linux: 'linux', freebsd: 'freebsd' }
const mine = `${OS[process.platform] || process.platform}-${process.arch}`

function give(message) {
  if (lenient) {
    console.warn(`\nNOT BUILT: ${message}\nThis package will have no connection helper, and the app in it can't reach a server from away.\n`)
    process.exit(0)
  }
  console.error(message)
  process.exit(1)
}

const source = [process.env.WITTYMEDIASERVER_SRC, join(desktop, '..', '..', 'WittyMediaServer')]
  .filter(Boolean).map((p) => resolve(p)).find((p) => existsSync(join(p, 'cmd', 'wittyconnect', 'main.go')))
if (!source) give('WittyMediaServer\'s source wasn\'t found. Set WITTYMEDIASERVER_SRC to a checkout that has cmd/wittyconnect.')
try { execFileSync('go', ['version'], { stdio: 'ignore' }) } catch { give('Go isn\'t installed, and the helper is a Go program.') }

const wanted = args.includes('--all') ? Object.keys(TARGETS).filter((t) => !t.startsWith('freebsd-')) : [args.find((a) => TARGETS[a]) || mine]
for (const target of wanted) {
  if (!TARGETS[target]) give(`No helper is built for ${target}.`)
  const [goos, goarch] = TARGETS[target]
  const out = join(desktop, 'bin', target)
  mkdirSync(out, { recursive: true })
  const program = join(out, goos === 'windows' ? 'wittyconnect.exe' : 'wittyconnect')
  console.log(`wittyconnect for ${target}, from ${source}`)
  execFileSync('go', ['build', '-trimpath', '-ldflags=-s -w', '-o', program, './cmd/wittyconnect'], {
    cwd: source, stdio: 'inherit', env: { ...process.env, GOOS: goos, GOARCH: goarch, CGO_ENABLED: '0', GOWORK: 'off', GOFLAGS: '-mod=mod' },
  })
  // Every library in it, with each license's text: it ships beside the helper.
  execFileSync('go', ['run', './internal/licenses/gen', '-notices', './cmd/wittyconnect', join(out, 'THIRD-PARTY-NOTICES.wittyconnect.txt')], {
    cwd: source, stdio: 'inherit', env: { ...process.env, GOWORK: 'off', GOFLAGS: '-mod=mod' },
  })
}
