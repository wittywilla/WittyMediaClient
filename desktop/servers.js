// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The rules for the servers this computer remembers: which two entries are one server, tidying
// a list that has the same server twice, which ones haven't been reached for a while, and what
// forgetting one takes away. Plain rules with nothing from Electron, so they can be tested alone;
// main.js gives `forget` the things that reach the disk and the network.
const DAY_MS = 24 * 60 * 60 * 1000
// What "Remove servers not reached for…" offers, in days, and when a server is marked as old.
const STALE_CHOICES = [30, 90, 180, 365]
const STALE_AFTER_DAYS = 90
const SIGN_OUT_TIMEOUT_MS = 3000

// One server is one entry, wherever it answers: the ID and key it proved say who it is. A server
// too old to have either is only ever the same as itself at the same address.
function sameServer(a, b) {
  if (!a || !b) return false
  if (a.url === b.url) return true
  if (a.serverId && a.serverId === b.serverId) return true
  return !!a.publicKey && a.publicKey === b.publicKey
}

// A list with the same server in it more than once becomes one entry each. The first, which is
// the most recent, is the one kept; what it lacks comes from the older ones. Says which addresses
// went, so what was kept for them can go too.
function merge(list) {
  const kept = []
  const gone = []
  for (const entry of list || []) {
    const first = kept.find((k) => sameServer(k, entry))
    if (!first) { kept.push({ ...entry }); continue }
    for (const key of ['name', 'serverId', 'publicKey', 'fingerprint', 'logo', 'p2p']) {
      if (first[key] === undefined && entry[key] !== undefined) first[key] = entry[key]
    }
    if ((entry.lastSeen || 0) > (first.lastSeen || 0)) first.lastSeen = entry.lastSeen
    if (entry.url !== first.url) gone.push(entry.url)
  }
  return { list: kept, gone }
}

// Whole days since it was last reached, or null when that isn't known: remembered by a version
// of the app that didn't keep it.
function daysSince(entry, now) {
  if (!entry || !Number.isFinite(entry.lastSeen) || entry.lastSeen <= 0) return null
  return Math.max(0, Math.floor((now - entry.lastSeen) / DAY_MS))
}

const isStale = (entry, now) => { const d = daysSince(entry, now); return d !== null && d >= STALE_AFTER_DAYS }

// The servers not reached for this many days. One whose last time isn't known is never chosen on
// a guess: it goes by hand, or with Remove all.
function notReachedFor(list, days, now) {
  return (list || []).filter((s) => { const d = daysSince(s, now); return d !== null && d >= days })
}

// Every address on this computer that holds something of this server: its own, and the one the
// peer-to-peer helper answers at for it.
function originsOf(entry, p2pOrigin) {
  const out = [entry.url]
  if (entry.p2p && entry.p2p.id && entry.p2p.port && p2pOrigin) {
    const away = p2pOrigin(entry.p2p.id, entry.p2p.port)
    if (!out.includes(away)) out.push(away)
  }
  return out
}

// Cookies belong to a machine's name, whatever the port: two servers on one machine share them.
const hostOf = (url) => { try { return new URL(url).hostname } catch { return '' } }

// Takes servers out of the list and puts them where they wait to be forgotten. Nothing else has
// happened yet, so putting one back is all an undo has to do.
function takeOut(state, urls) {
  const recent = state.recent || []
  const going = recent.filter((s) => urls.includes(s.url))
  if (!going.length) return { state, taken: [] }
  const taken = going.map((entry) => ({ entry, index: recent.indexOf(entry), current: state.server === entry.url }))
  const next = {
    ...state,
    recent: recent.filter((s) => !going.includes(s)),
    forgetting: [...(state.forgetting || []), ...going],
  }
  if (taken.some((t) => t.current)) next.server = ''
  return { state: next, taken }
}

// Undo: back where it was, and nothing was lost because nothing had been deleted.
function putBack(state, taken) {
  const waiting = (state.forgetting || [])
  const back = (taken || []).filter((t) => waiting.some((s) => s.url === t.entry.url))
  if (!back.length) return state
  const recent = [...(state.recent || [])].filter((s) => !back.some((t) => sameServer(t.entry, s)))
  for (const t of [...back].sort((a, b) => a.index - b.index)) recent.splice(Math.min(t.index, recent.length), 0, t.entry)
  const next = { ...state, recent, forgetting: waiting.filter((s) => !back.some((t) => t.entry.url === s.url)) }
  if (!next.forgetting.length) delete next.forgetting
  return next
}

// Forgets one server for good: everything this computer holds for it and nothing of any other.
// `deps` reaches the disk and the network:
//   tokenAt(origin)         the sign-in kept for an address, or ''
//   clearOrigin(origin, cookies)  storage, service workers and cache of that address, and its cookies if asked
//   signOut(origin, token)  tells the server to end that session
//   revokeDevice(origin, token)  takes this device off the server's peer-to-peer list
//   closeTunnel(id)         stops the helper if it is connected to this server
//   forgetDeviceKey()       deletes this device's peer-to-peer key
//   p2pOrigin(id, port)
// `remaining` is every server still remembered. Telling the server is the only part that can
// take time or fail, and it does neither to the rest: local things go first.
async function forget(entry, remaining, deps) {
  const origins = originsOf(entry, deps.p2pOrigin)
  const shared = (origin) => (remaining || []).some((s) => originsOf(s, deps.p2pOrigin).includes(origin))
  // Another remembered server on the same machine has its sign-in in the same cookies: they stay,
  // and so does the session on the server, as there is no telling whose it is.
  const sharedHost = (origin) => (remaining || []).some((s) => originsOf(s, deps.p2pOrigin).some((o) => hostOf(o) === hostOf(origin)))
  const sessions = []
  for (const origin of origins) {
    if (shared(origin) || sharedHost(origin)) continue // another remembered server lives there: it is theirs
    try {
      const token = await deps.tokenAt(origin)
      if (token) sessions.push({ origin, token })
    } catch { /* no sign-in to end, then */ }
  }
  const failed = []
  for (const origin of origins) {
    if (shared(origin)) continue
    try { await deps.clearOrigin(origin, !sharedHost(origin)) } catch { failed.push(origin) }
  }
  // The key is this device's, for every server it reaches from away: it goes with the last of them.
  if (entry.p2p && !(remaining || []).some((s) => s.p2p) && deps.forgetDeviceKey) deps.forgetDeviceKey()
  // Reached directly if it can be: the helper's address only answers while the helper runs.
  const told = []
  const seen = new Set()
  for (const { origin, token } of sessions) {
    if (seen.has(token)) continue
    seen.add(token)
    const at = sessions.find((s) => s.token === token && s.origin === entry.url) ? entry.url : origin
    told.push((async () => {
      if (entry.p2p && deps.revokeDevice) await deps.revokeDevice(at, token).catch(() => {})
      await deps.signOut(at, token).catch(() => {})
    })())
  }
  await Promise.all(told)
  // The helper stays up until the server has been told: for a server only reached from away, it is the way there.
  if (entry.p2p && deps.closeTunnel) deps.closeTunnel(entry.p2p.id)
  return { origins: origins.filter((o) => !shared(o)), sessions: sessions.length, failed }
}

module.exports = { sameServer, merge, daysSince, isStale, notReachedFor, originsOf, takeOut, putBack, forget, STALE_CHOICES, STALE_AFTER_DAYS, SIGN_OUT_TIMEOUT_MS, DAY_MS }
