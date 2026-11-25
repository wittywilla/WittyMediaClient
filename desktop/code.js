// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Enter a code: the code a server shows under Connect a device (Settings, Remote Access), typed here.
// The app doesn't know which server on the network made it, so it asks each one it finds, and none of
// them learns the code: as WittyMediaServer's internal/server/api_connect.go says, both ends turn the
// code into two keys with scrypt (Electron has no Argon2); the app sends the first, which only says which code it means; the
// server has to prove it knows the code, bound to its identity key and both random numbers, before the
// app proves it does. A server that didn't make the code can't, and gets nothing more.
const crypto = require('crypto')

// The code's symbols: no I, L, O or U, which read as other symbols across a room.
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
const LENGTH = 8
const SALT = Buffer.from('wittymedia-web-join-v1')
const NONCE_BYTES = 16

// A code as a person typed it: either case, with or without the dash or spaces, and the letters that
// look like digits taken for them. '' when it can't be one.
function cleanCode(typed) {
  let out = ''
  for (let ch of String(typed || '').toUpperCase()) {
    if (ch === ' ' || ch === '-' || ch === '\t') continue
    if (ch === 'O') ch = '0'
    else if (ch === 'I' || ch === 'L') ch = '1'
    if (!ALPHABET.includes(ch)) return ''
    out += ch
    if (out.length > LENGTH) return ''
  }
  return out.length === LENGTH ? out : ''
}

const showCode = (clean) => (clean.length === LENGTH ? `${clean.slice(0, 4)}-${clean.slice(4)}` : clean)

// What a code becomes: the same as the server's p2p.DeriveWebJoin (scrypt, N=2^15, r=8, p=1: 32 MiB).
function derive(clean) {
  const out = crypto.scryptSync(Buffer.from(clean), SALT, 64, { N: 1 << 15, r: 8, p: 1, maxmem: 64 * 1024 * 1024 })
  return { find: out.subarray(0, 32), proof: out.subarray(32) }
}

// The server's p2p.WebJoinProof: each part with its length first, so no two sets of parts read the same.
function webProof(key, role, deviceNonce, serverNonce, identityKey) {
  const m = crypto.createHmac('sha256', key)
  for (const part of [Buffer.from('wittymedia web join 1'), Buffer.from(role), deviceNonce, serverNonce, Buffer.from(identityKey)]) {
    m.update(Buffer.from([part.length >> 8, part.length & 0xff]))
    m.update(part)
  }
  return m.digest()
}

const b64 = (buf) => Buffer.from(buf).toString('base64')
const fromB64 = (s) => { try { return Buffer.from(String(s || ''), 'base64') } catch { return Buffer.alloc(0) } }

// Asks one server, already known by its identity key (from /api/identity, checked by the caller), about
// the code. post(path, body) sends JSON there and resolves { status, data }. Answers
//   { ok: true, token, name }       the server made the code, proved it, and signed this device in
//   { here: false }                 it didn't make the code (the usual answer from other servers)
//   { here: false, restarted }      it made it, but restarted since, which ends codes: its words
//   { error, message?, reason? }    it made it, but no sign-in: refused, a wrong proof, or a liar
async function askServer({ post, identityKey, keys, device, platform }) {
  const deviceNonce = crypto.randomBytes(NONCE_BYTES)
  const find = Buffer.from(keys.find).toString('hex')
  const hello = await post('/connect/hello', { v: 1, find, nonce: b64(deviceNonce) })
  if (hello.status === 404 && hello.data && hello.data.reason === 'restarted') {
    return { here: false, restarted: typeof hello.data.error === 'string' ? hello.data.error : '' }
  }
  if (hello.status === 404 || hello.status === 405) return { here: false }
  const h = hello.data && typeof hello.data === 'object' ? hello.data : {}
  if (hello.status !== 200) return { error: 'refused', message: typeof h.error === 'string' ? h.error : '', reason: typeof h.reason === 'string' ? h.reason : '' }
  const serverNonce = fromB64(h.nonce)
  const said = fromB64(h.proof)
  const expected = webProof(keys.proof, 'server', deviceNonce, serverNonce, identityKey)
  // The server proves first, with the key this app checked it holds. Anything else gets nothing more.
  if (h.publicKey !== identityKey || serverNonce.length !== NONCE_BYTES || said.length !== expected.length || !crypto.timingSafeEqual(said, expected)) {
    return { error: 'liar' }
  }
  const answer = await post('/connect/answer', {
    v: 1, find, nonce: b64(deviceNonce), serverNonce: b64(serverNonce),
    proof: b64(webProof(keys.proof, 'device', deviceNonce, serverNonce, identityKey)), device, platform,
  })
  const a = answer.data && typeof answer.data === 'object' ? answer.data : {}
  if (answer.status !== 200 || typeof a.token !== 'string') {
    return { error: 'refused', message: typeof a.error === 'string' ? a.error : '', reason: typeof a.reason === 'string' ? a.reason : '' }
  }
  return { ok: true, token: a.token, name: typeof a.serverName === 'string' ? a.serverName : '' }
}

module.exports = { cleanCode, showCode, derive, webProof, askServer, ALPHABET, LENGTH }
