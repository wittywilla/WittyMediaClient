// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
const test = require('node:test')
const assert = require('node:assert')
const servers = require('../servers.js')
const state = require('../state.js')
const { originFor } = require('../p2p.js')

const DAY = servers.DAY_MS
const NOW = 2_000_000_000_000
const A = { url: 'http://192.168.1.20:9797', name: 'Home', serverId: 'a'.repeat(32), publicKey: 'KEYA', lastSeen: NOW - 2 * DAY }
const B = { url: 'http://192.168.1.30:9797', name: 'Shed', serverId: 'b'.repeat(32), publicKey: 'KEYB', lastSeen: NOW - 200 * DAY }
const OLD = { url: 'http://10.0.0.9:9797', name: 'Before identity' }

test('one server is one entry, by who it is and not by where', () => {
  assert.ok(servers.sameServer(A, { ...A, url: 'http://10.0.0.1:9797' }), 'the same ID at a new address')
  assert.ok(servers.sameServer({ url: 'http://x', publicKey: 'K' }, { url: 'http://y', publicKey: 'K' }), 'the same key with no ID')
  assert.ok(servers.sameServer(OLD, { url: OLD.url, name: 'Other name' }), 'the same address')
  assert.ok(!servers.sameServer(A, B))
  assert.ok(!servers.sameServer(OLD, { url: 'http://10.0.0.10:9797' }), 'two with no identity are only the same at one address')
})

test('a list with one server twice is merged: the most recent kept, what it lacks filled in, the rest untouched', () => {
  const moved = { url: 'http://192.168.1.99:9797', name: 'Home', serverId: A.serverId, publicKey: 'KEYA', logo: { version: 'v1', data: 'x' }, lastSeen: NOW }
  const typed = { url: 'http://home.lan:9797', name: 'Home', publicKey: 'KEYA', p2p: { id: 'p', hints: [] } }
  const { list, gone } = servers.merge([{ url: A.url, name: 'Home', serverId: A.serverId, publicKey: 'KEYA', lastSeen: 5 }, B, moved, OLD, typed, { ...OLD, name: 'again' }])
  assert.deepStrictEqual(list.map((s) => s.url), [A.url, B.url, OLD.url])
  assert.deepStrictEqual(list[0], { url: A.url, name: 'Home', serverId: A.serverId, publicKey: 'KEYA', lastSeen: NOW, logo: moved.logo, p2p: typed.p2p })
  assert.deepStrictEqual(list[1], B)
  assert.deepStrictEqual(gone, [moved.url, typed.url])
  assert.deepStrictEqual(servers.merge(list), { list, gone: [] }, 'doing it again changes nothing')
})

test('a state file written by an older version, with duplicates, is merged when it is read', () => {
  const read = state.clean({ server: A.url, recent: [
    { url: A.url, name: 'Home', serverId: A.serverId, publicKey: 'KEYA' },
    { url: 'http://192.168.1.99:9797', name: 'Home old', serverId: A.serverId, publicKey: 'KEYA' },
    { url: B.url, name: 'Shed' },
  ] })
  assert.deepStrictEqual(read.recent.map((s) => s.url), [A.url, B.url])
  assert.deepStrictEqual(read.merged, ['http://192.168.1.99:9797'])
  assert.ok(!JSON.stringify(read).includes('merged'), 'which is never written back')
  assert.strictEqual(state.clean(JSON.parse(JSON.stringify(read))).merged, undefined)
})

test('remembering a server that moved updates its entry, and says when it was reached', () => {
  let s = state.remember({}, { ...A, logo: undefined })
  s = state.remember(s, B)
  s = state.remember(s, { url: 'http://192.168.1.99:9797', name: 'Home', serverId: A.serverId, publicKey: 'KEYA', lastSeen: NOW })
  assert.deepStrictEqual(s.recent.map((r) => r.url), ['http://192.168.1.99:9797', B.url])
  assert.strictEqual(s.recent[0].lastSeen, NOW)
  assert.deepStrictEqual(state.clean(s).recent, s.recent, 'and it survives being saved and read')
})

test('when a server was last reached, and which are old', () => {
  assert.strictEqual(servers.daysSince(A, NOW), 2)
  assert.strictEqual(servers.daysSince(OLD, NOW), null, 'not known')
  assert.strictEqual(servers.daysSince({ lastSeen: NOW + DAY }, NOW), 0, 'a clock that went back')
  assert.ok(servers.isStale(B, NOW))
  assert.ok(!servers.isStale(A, NOW))
  assert.ok(!servers.isStale(OLD, NOW), 'not marked on a guess')
  assert.deepStrictEqual(servers.notReachedFor([A, B, OLD], 90, NOW), [B])
  assert.deepStrictEqual(servers.notReachedFor([A, B, OLD], 365, NOW), [])
  assert.deepStrictEqual(servers.notReachedFor([A, B, OLD], 1, NOW), [A, B], 'one whose time is not known is never chosen')
})

test('taking a server out leaves the others as they were, and undo puts it back in its place', () => {
  const before = { server: B.url, recent: [A, B, OLD], window: { width: 800, height: 600 } }
  const { state: after, taken } = servers.takeOut(before, [B.url])
  assert.deepStrictEqual(after.recent, [A, OLD])
  assert.strictEqual(after.server, '', 'it was the one in use')
  assert.deepStrictEqual(after.forgetting, [B])
  assert.deepStrictEqual(after.window, before.window)
  assert.deepStrictEqual(state.clean(JSON.parse(JSON.stringify(after))).forgetting, [B], 'what is waiting to be forgotten survives a restart')
  const back = servers.putBack(after, taken)
  assert.deepStrictEqual(back.recent, [A, B, OLD])
  assert.strictEqual(back.forgetting, undefined)
  assert.deepStrictEqual(servers.takeOut(before, ['http://nobody']).taken, [])
  const all = servers.takeOut(before, [A.url, B.url, OLD.url])
  assert.deepStrictEqual(all.state.recent, [])
  assert.deepStrictEqual(servers.putBack(all.state, all.taken).recent, [A, B, OLD])
})

// A stand-in for the browser session and the network: what each address holds.
function world(held) {
  const calls = []
  const deps = {
    p2pOrigin: originFor,
    tokenAt: async (origin) => (held[origin] && held[origin].token) || '',
    clearOrigin: async (origin, cookies) => { calls.push(['clear', origin]); if (cookies) delete held[origin]; else delete held[origin].storage },
    signOut: async (origin, token) => { calls.push(['signOut', origin, token]) },
    revokeDevice: async (origin, token) => { calls.push(['revoke', origin, token]) },
    closeTunnel: (id) => calls.push(['closeTunnel', id]),
    forgetDeviceKey: () => calls.push(['forgetKey']),
  }
  return { calls, deps, held }
}

test('forgetting a server clears everything at its addresses, tells it, and touches nothing of another', async () => {
  const away = { id: '12D3KooW' + 'x'.repeat(44), hints: [], port: 40123 }
  const a = { ...A, p2p: away }
  const awayOrigin = originFor(away.id, away.port)
  const w = world({ [A.url]: { token: 'TA', storage: 1 }, [awayOrigin]: { token: 'TA' }, [B.url]: { token: 'TB', storage: 1 } })
  const done = await servers.forget(a, [B], w.deps)
  assert.deepStrictEqual(Object.keys(w.held), [B.url], 'only the other server is left')
  assert.deepStrictEqual(w.held[B.url], { token: 'TB', storage: 1 })
  assert.deepStrictEqual(done, { origins: [A.url, awayOrigin], sessions: 2, failed: [] })
  assert.deepStrictEqual(w.calls, [
    ['clear', A.url], ['clear', awayOrigin], ['forgetKey'],
    ['revoke', A.url, 'TA'], ['signOut', A.url, 'TA'], ['closeTunnel', away.id],
  ], 'local things first, the one sign-in ended once, and the helper stopped last')
})

test('the device key stays while another server is reached from away with it', async () => {
  const p2p = { id: 'id-one', hints: [], port: 40001 }
  const w = world({ [A.url]: { token: 'TA' } })
  await servers.forget({ ...A, p2p }, [{ ...B, p2p: { id: 'id-two', hints: [], port: 40002 } }], w.deps)
  assert.ok(!w.calls.some((c) => c[0] === 'forgetKey'))
  assert.ok(w.calls.some((c) => c[0] === 'revoke'), 'this device still comes off the removed server\'s list')
})

test('a server that cannot be told is forgotten all the same, and one with no sign-in is not asked', async () => {
  const w = world({ [A.url]: { token: 'TA' }, [OLD.url]: {} })
  w.deps.signOut = async () => { throw new Error('unreachable') }
  await servers.forget(A, [OLD], w.deps)
  assert.deepStrictEqual(Object.keys(w.held), [OLD.url])
  const quiet = world({ [OLD.url]: {} })
  await servers.forget(OLD, [], quiet.deps)
  assert.deepStrictEqual(quiet.calls, [['clear', OLD.url]])
})

test('an address another remembered server answers at now is theirs, and is left alone', async () => {
  const w = world({ [A.url]: { token: 'TNEW' } })
  const done = await servers.forget({ ...OLD, url: A.url }, [A], w.deps)
  assert.deepStrictEqual(w.held, { [A.url]: { token: 'TNEW' } })
  assert.deepStrictEqual(done.origins, [])
  assert.deepStrictEqual(w.calls, [])
})

test('storage that will not clear is reported, and the rest still goes', async () => {
  const w = world({ [A.url]: { token: 'TA' } })
  w.deps.clearOrigin = async () => { throw new Error('busy') }
  const done = await servers.forget(A, [], w.deps)
  assert.deepStrictEqual(done.failed, [A.url])
  assert.ok(w.calls.some((c) => c[0] === 'signOut'))
})

test('two servers on one machine share its cookies: removing one leaves them, and ends no session', async () => {
  const twin = { url: 'http://192.168.1.20:9800', name: 'Second on the same machine' }
  const w = world({ [A.url]: { token: 'TA', storage: 1 }, [twin.url]: { token: 'TA', storage: 1 } })
  await servers.forget(twin, [A], w.deps)
  assert.deepStrictEqual(w.held, { [A.url]: { token: 'TA', storage: 1 }, [twin.url]: { token: 'TA' } }, 'its storage went, the shared cookies stayed')
  assert.deepStrictEqual(w.calls, [['clear', twin.url]])
})
