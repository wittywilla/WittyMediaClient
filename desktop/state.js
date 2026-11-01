// What the app remembers between runs: the current server, recent servers with
// the identity key each one proved, and the window size. No passwords or
// tokens: the sign-in stays in the browser session, as it does in a browser.
const fs = require('fs')
const { normalizeAddress } = require('./connect/address.js')

const MAX_RECENT = 8
const MIN_WINDOW = 100
const MAX_WINDOW = 32768
const LIMITS = { name: 80, serverId: 128, publicKey: 64, fingerprint: 32 }

const isServerUrl = (url) => typeof url === 'string' && normalizeAddress(url).url === url

function cleanEntry(entry) {
  if (!entry || typeof entry !== 'object' || !isServerUrl(entry.url)) return null
  const out = { url: entry.url }
  for (const [key, max] of Object.entries(LIMITS)) {
    if (typeof entry[key] === 'string' && entry[key] && entry[key].length <= max) out[key] = entry[key]
  }
  return out
}

const windowSide = (n) => Number.isInteger(n) && n >= MIN_WINDOW && n <= MAX_WINDOW

// The file may have been damaged, or written by something else. What can't be
// used is dropped here, so nothing later has to wonder, and the app still starts.
function clean(s) {
  const out = {}
  if (!s || typeof s !== 'object' || Array.isArray(s)) return out
  if (s.server === '' || isServerUrl(s.server)) out.server = s.server
  if (Array.isArray(s.recent)) out.recent = s.recent.map(cleanEntry).filter(Boolean).slice(0, MAX_RECENT)
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

// The most recent first, once per address and once per server.
function remember(state, server) {
  const entry = { url: server.url, name: server.name }
  for (const key of ['serverId', 'publicKey', 'fingerprint']) if (server[key]) entry[key] = server[key]
  const others = (state.recent || []).filter((s) => s.url !== server.url && (!server.serverId || s.serverId !== server.serverId))
  return { ...state, server: server.url, recent: [entry, ...others].slice(0, MAX_RECENT) }
}

module.exports = { load, save, remember, clean, MAX_RECENT }
