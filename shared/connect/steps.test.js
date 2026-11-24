// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
const test = require('node:test')
const assert = require('node:assert/strict')
const file = require('../data/connect-steps.json')
const { create } = require('./steps.js')

const steps = create(file)

test('every case in the shared file is answered as the server answers it', () => {
  assert.ok(file.cases.length >= 10)
  for (const c of file.cases) {
    const f = steps.classify(c.reason, c.text, c.step)
    assert.equal(f.code, c.code, JSON.stringify(c))
    assert.equal(f.step, c.at, JSON.stringify(c))
    assert.ok(f.say && f.next)
  }
  assert.deepEqual(steps.steps.map((s) => s.id), ['read', 'found', 'secure', 'signin'])
})

test('a run ticks the steps up to the one that failed, and none after it', () => {
  const r = steps.run('invite', '12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz')
  r.pass('read'); r.pass('found')
  r.fail(steps.classify('', "the server was found, but a direct connection through both routers couldn't be made", 'secure'))
  assert.deepEqual(r.states().map((s) => s.state), ['ok', 'ok', 'fail', 'skip'])

  const late = steps.run('invite')
  ;['read', 'found', 'secure'].forEach(late.pass)
  assert.equal(late.fail(steps.classify('', "the server didn't answer in time", 'signin')).step, 'signin')
  const slow = steps.run('invite')
  ;['read', 'found', 'secure'].forEach(slow.pass)
  assert.equal(slow.fail(steps.of('slow-path', 'secure')).step, 'secure')
})

test('the details hold no secrets once cleaned', () => {
  const { redact } = require('../../desktop/clientlog.js')
  const r = steps.run('invite', '12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz')
  r.note('opening wittymedia://p2p/12D3KooWAbCd?s=SuperSecretInvite123&n=Home')
  r.note('Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789')
  r.fail(steps.classify('', "token=abcdef123456 the server wasn't found", 'found', redact))
  const v = r.view('WittyMediaClient 0.6.3', 'laptop', redact)
  for (const gone of ['SuperSecretInvite123', 'abcdefghijklmnopqrstuvwxyz0123456789', 'abcdef123456', '12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz']) {
    assert.ok(!v.details.includes(gone), `${gone} in ${v.details}`)
  }
  assert.match(v.details, /\[!\] Server found/)
  assert.equal(v.failure.code, 'not-found')
})
