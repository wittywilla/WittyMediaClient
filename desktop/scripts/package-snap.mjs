// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// `npm run package:snap`: electron-builder's snap, with build/linux/snapcraft-shim first on PATH so
// the snapcraft.yaml it writes works with snapcraft 8 and later (see the shim). Never published to the
// Snap Store from here: built from a tag, electron-builder would try, and there is no store account.
import { spawnSync } from 'node:child_process'
import { chmodSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const shim = path.join(here, '..', 'build', 'linux', 'snapcraft-shim')
chmodSync(path.join(shim, 'snapcraft'), 0o755) // a checkout on another system may have lost the bit
const env = { ...process.env, PATH: `${shim}${path.delimiter}${process.env.PATH}` }
const bin = process.platform === 'win32' ? 'electron-builder.cmd' : 'electron-builder'
const r = spawnSync(path.join(here, '..', 'node_modules', '.bin', bin), ['--linux', 'snap', '--x64', '--publish', 'never', ...process.argv.slice(2)], { stdio: 'inherit', env })
process.exit(r.status ?? 1)
