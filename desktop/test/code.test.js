// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
const test = require('node:test')
const assert = require('node:assert')
const code = require('../code.js')

test('a code is read as people type it, and nothing else is taken for one', () => {
  for (const typed of ['K7QM-2XHD', 'k7qm2xhd', ' k7qm 2xhd ', 'K7QM\t2XHD']) assert.strictEqual(code.cleanCode(typed), 'K7QM2XHD', typed)
  assert.strictEqual(code.cleanCode('O1IL-ABCD'), '0111ABCD', 'letters that look like digits are the digits')
  for (const bad of ['', 'K7QM', 'K7QM-2XHU', 'K7QM-2XHDX', '123456', 'wittymedia://p2p/x', 'http://192.168.1.20:9797', 'K7QM-2XH!', null, undefined]) {
    assert.strictEqual(code.cleanCode(bad), '', String(bad))
  }
  assert.strictEqual(code.showCode('K7QM2XHD'), 'K7QM-2XHD')
})

// The same values as the server's internal/p2p/webjoin_test.go: the wire format, held at both ends.
test('the keys and proofs are the server\'s', () => {
  const keys = code.derive('K7QM2XHD')
  assert.strictEqual(Buffer.from(keys.find).toString('hex'), '7570bed5d42ed757a21d20977ab7222b47d6a3ad37e493928f642d59bda56ed9')
  assert.strictEqual(Buffer.from(keys.proof).toString('hex'), '5258c623e6e31dee14dc3a9139e33dae09f7b558b63211be3989babcb0e6002d')
  const dn = Buffer.from([...Array(16).keys()])
  const sn = Buffer.from([...Array(16).keys()].map((i) => 100 + i))
  assert.strictEqual(code.webProof(keys.proof, 'server', dn, sn, 'ed25519-key-text').toString('hex'), '7e3132a96c5430476c4ea7c809fa9ef4748f853b0af4ba078d35a4f3f02af2fe')
})

// A server stood in for: it holds the code's keys when it made it, and answers as api_connect.go does.
function standIn({ made, key = 'server-key', lie = false, refuse = '' }) {
  const keys = made ? code.derive(made) : null
  const seen = []
  let serverNonce = null
  const post = async (path, body) => {
    seen.push({ path, body })
    if (path === '/connect/hello') {
      if (!keys || body.find !== Buffer.from(keys.find).toString('hex')) return { status: 404, data: { reason: 'not-here' } }
      serverNonce = require('crypto').randomBytes(16)
      const proofKey = lie ? Buffer.alloc(32, 7) : keys.proof
      return { status: 200, data: { nonce: serverNonce.toString('base64'), publicKey: key, proof: code.webProof(proofKey, 'server', Buffer.from(body.nonce, 'base64'), serverNonce, key).toString('base64') } }
    }
    if (refuse) return { status: 403, data: { error: 'Whoever made that code has signed out.', reason: refuse } }
    const want = code.webProof(keys.proof, 'device', Buffer.from(body.nonce, 'base64'), serverNonce, key).toString('base64')
    return body.proof === want ? { status: 200, data: { token: 't'.repeat(64), serverName: 'Den' } } : { status: 401, data: { reason: 'wrong-code' } }
  }
  return { post, seen }
}

test('asking servers about a code', async () => {
  const keys = code.derive('K7QM2XHD')
  const ask = (s, identityKey = 'server-key') => code.askServer({ post: s.post, identityKey, keys, device: 'Desk', platform: 'Linux' })

  // The server that made it: it proves itself, then this device does, and is signed in.
  const right = standIn({ made: 'K7QM2XHD' })
  assert.deepStrictEqual(await ask(right), { ok: true, token: 't'.repeat(64), name: 'Den' })
  // The code itself never goes anywhere: only the lookup key and proofs.
  assert.ok(!JSON.stringify(right.seen).includes('K7QM'), 'the code was sent')

  // Another server on the network: it didn't make it, and hears nothing more than the lookup key.
  const other = standIn({ made: 'ABCD1234' })
  assert.deepStrictEqual(await ask(other), { here: false })
  assert.strictEqual(other.seen.length, 1)

  // The server that made it, restarted since (0.8.5 ends codes on a restart): its words, and nothing more sent.
  const words = 'This code expired because the server restarted. Show a new code on the server.'
  let asked = 0
  const restarted = { post: async () => { asked++; return { status: 404, data: { reason: 'restarted', error: words } } } }
  assert.deepStrictEqual(await ask(restarted), { here: false, restarted: words })
  assert.strictEqual(asked, 1)

  // One that claims it did but can't prove it, or proves it under another key: no answer is sent.
  for (const liar of [standIn({ made: 'K7QM2XHD', lie: true }), standIn({ made: 'K7QM2XHD', key: 'another-key' })]) {
    assert.deepStrictEqual(await ask(liar), { error: 'liar' })
    assert.strictEqual(liar.seen.length, 1, 'the device answered a server that proved nothing')
  }

  // The server's own refusal comes back in its words.
  const refused = await ask(standIn({ made: 'K7QM2XHD', refuse: 'expired' }))
  assert.strictEqual(refused.error, 'refused')
  assert.strictEqual(refused.reason, 'expired')
})
