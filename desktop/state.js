// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// What the app remembers between runs: the current server, recent servers with
// the identity key each one proved, and the window size. No passwords or
// tokens: the sign-in stays in the browser session, as it does in a browser.
const fs = require('fs')
const { normalizeAddress } = require('./connect/address.js')
const { isP2POrigin, cleanInfo } = require('./p2p.js')
const { merge, sameServer } = require('./servers.js')

const MAX_RECENT = 8
const MIN_WINDOW = 100
const MAX_WINDOW = 32768
const LIMITS = { name: 80, serverId: 128, publicKey: 64, fingerprint: 32 }
// A server's own logo, as the picture itself, so the list can show it before the server answers.
const LOGO = /^data:image\/(png|jpeg|webp|gif|svg\+xml);base64,[A-Za-z0-9+/]+={0,2}$/
const MAX_LOGO = 360 * 1024

// A server is remembered by its address, or, for one only ever reached from away, by the
// address on this computer that the peer-to-peer helper gives it (p2p.js).
const isServerUrl = (url) => typeof url === 'string' && (normalizeAddress(url).url === url || isP2POrigin(url))

function cleanEntry(entry) {
  if (!entry || typeof entry !== 'object' || !isServerUrl(entry.url)) return null
  const out = { url: entry.url }
  for (const [key, max] of Object.entries(LIMITS)) {
    if (typeof entry[key] === 'string' && entry[key] && entry[key].length <= max) out[key] = entry[key]
  }
  const logo = cleanLogo(entry.logo)
  if (logo) out.logo = logo
  // How to reach it from away: its connection ID, and where it was last found.
  const p2p = cleanInfo(entry.p2p)
  if (p2p) out.p2p = p2p
  // When it was last reached, in milliseconds. Left out by a version that didn't keep it.
  if (Number.isSafeInteger(entry.lastSeen) && entry.lastSeen > 0) out.lastSeen = entry.lastSeen
  // The person stopped this computer connecting to it from away (the menu's From away).
  if (entry.awayOff === true) out.awayOff = true
  return out
}

function cleanLogo(logo) {
  if (!logo || typeof logo !== 'object') return null
  const { version, data } = logo
  if (typeof version !== 'string' || !version || version.length > 64) return null
  if (typeof data !== 'string' || data.length > MAX_LOGO || !LOGO.test(data)) return null
  return { version, data }
}

const windowSide = (n) => Number.isInteger(n) && n >= MIN_WINDOW && n <= MAX_WINDOW

// The file may have been damaged, or written by something else. What can't be
// used is dropped here, so nothing later has to wonder, and the app still starts.
function clean(s) {
  const out = {}
  if (!s || typeof s !== 'object' || Array.isArray(s)) return out
  if (s.server === '' || isServerUrl(s.server)) out.server = s.server
  // One entry for each server: a list written before servers were told apart by who they are can
  // have the same one twice, at two addresses. `merged` says which addresses went, for main.js to
  // clear what was kept for them; it is never written to the file.
  if (Array.isArray(s.recent)) {
    const tidy = merge(s.recent.map(cleanEntry).filter(Boolean))
    out.recent = tidy.list.slice(0, MAX_RECENT)
    if (tidy.gone.length) Object.defineProperty(out, 'merged', { value: tidy.gone, enumerable: false })
  }
  // Servers taken off the list whose data hasn't been cleared yet: finished the next time the app starts.
  if (Array.isArray(s.forgetting)) {
    const waiting = s.forgetting.map(cleanEntry).filter(Boolean).slice(0, MAX_RECENT * 2)
    if (waiting.length) out.forgetting = waiting
  }
  if (s.window && windowSide(s.window.width) && windowSide(s.window.height)) out.window = { width: s.window.width, height: s.window.height }
  return out
}

function load(file) {
  try {
    return clean(JSON.parse(fs.readFileSync(file, 'utf8')))
  } catch { return {} }
}

// Written beside the file and moved over it, so a crash leaves the old one whole,
// and only this user can read it. Says whether it worked: losing this is no reason
// to stop anything else. Windows can refuse the move while something scans the
// file, and then writing it in place is better than not at all.
function save(file, state) {
  const text = JSON.stringify(state)
  const temporary = `${file}.${process.pid}.tmp`
  try {
    const fd = fs.openSync(temporary, 'w', 0o600)
    try {
      fs.writeFileSync(fd, text)
      fs.fsyncSync(fd)
    } finally {
      fs.closeSync(fd)
    }
    fs.renameSync(temporary, file)
    return true
  } catch {
    try { fs.rmSync(temporary, { force: true }) } catch { /* nothing more can be done */ }
    try {
      fs.writeFileSync(file, text, { mode: 0o600 })
      return true
    } catch { return false }
  }
}

// The most recent first, once per address and once per server. A logo left out keeps the one
// already kept for that address; null says the server has none now.
function remember(state, server) {
  const entry = { url: server.url, name: server.name }
  for (const key of ['serverId', 'publicKey', 'fingerprint']) if (server[key]) entry[key] = server[key]
  const before = (state.recent || []).find((s) => s.url === server.url) || (state.recent || []).find((s) => sameServer(s, server))
  if (Number.isSafeInteger(server.lastSeen) && server.lastSeen > 0) entry.lastSeen = server.lastSeen
  else if (before && before.lastSeen) entry.lastSeen = before.lastSeen
  const logo = cleanLogo(server.logo === undefined ? before && before.logo : server.logo)
  if (logo) entry.logo = logo
  // The way to reach it from away stays with it, unless this says otherwise (null forgets it).
  const p2p = cleanInfo(server.p2p === undefined ? before && before.p2p : server.p2p)
  if (p2p) entry.p2p = p2p
  if (before && before.awayOff) entry.awayOff = true
  const others = (state.recent || []).filter((s) => !sameServer(s, server))
  return { ...state, server: server.url, recent: [entry, ...others].slice(0, MAX_RECENT) }
}

module.exports = { load, save, remember, clean, MAX_RECENT }
