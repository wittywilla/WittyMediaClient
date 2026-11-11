#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Copies the shared connect screen into the desktop app and turns the shared
// wording into a script, because a page on the app's own scheme can't fetch JSON.
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const shared = join(here, '..', '..', 'shared')
const out = join(here, '..', 'connect')

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
cpSync(join(shared, 'connect'), out, { recursive: true, filter: (p) => !p.endsWith('.test.js') })
const strings = readFileSync(join(shared, 'data', 'strings.en.json'), 'utf8')
writeFileSync(join(out, 'strings.js'), `self.WittyStrings = ${strings.trim()}\n`)
