const test = require('node:test')
const assert = require('node:assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { load, save, remember, clean, MAX_RECENT } = require('../state.js')

test('remember puts the newest server first, once', () => {
  let s = remember({}, { url: 'http://a', name: 'A' })
  s = remember(s, { url: 'http://b', name: 'B' })
  s = remember(s, { url: 'http://a', name: 'A2' })
  assert.strictEqual(s.server, 'http://a')
  assert.deepStrictEqual(s.recent, [{ url: 'http://a', name: 'A2' }, { url: 'http://b', name: 'B' }])
})

test('remember keeps a bounded list', () => {
  let s = {}
  for (let i = 0; i < MAX_RECENT + 5; i++) s = remember(s, { url: `http://${i}`, name: String(i) })
  assert.strictEqual(s.recent.length, MAX_RECENT)
})

test('a missing or damaged state file is an empty state', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wmc-'))
  const file = path.join(dir, 'state.json')
  assert.deepStrictEqual(load(file), {})
  fs.writeFileSync(file, '{not json')
  assert.deepStrictEqual(load(file), {})
  save(file, { server: 'http://a' })
  assert.deepStrictEqual(load(file), { server: 'http://a' })
  fs.rmSync(dir, { recursive: true })
})

test('what can\'t be used in the file is dropped, so the app still starts', () => {
  assert.deepStrictEqual(clean([]), {})
  assert.deepStrictEqual(clean(null), {})
  assert.deepStrictEqual(clean('text'), {})
  assert.deepStrictEqual(clean({ server: 7, recent: 'x', window: 'big' }), {})
  assert.deepStrictEqual(clean({ server: 'javascript:alert(1)' }), {}, 'not an address')
  assert.deepStrictEqual(clean({ server: 'http://8.8.8.8' }), {}, 'one that would be refused if typed')
  assert.deepStrictEqual(clean({ server: 'http://10.0.0.2/settings' }), {}, 'not in the form the app writes')
  assert.deepStrictEqual(clean({ server: '' }), { server: '' })
  assert.deepStrictEqual(clean({ recent: [null, 7, {}, { url: 7 }, { url: 'file:///x' }] }), { recent: [] })
  const entry = { url: 'http://10.0.0.2:9797', name: 'Home', serverId: 'abc', publicKey: 'key', fingerprint: 'AB-CD' }
  assert.deepStrictEqual(clean({ recent: [entry] }), { recent: [entry] })
  assert.deepStrictEqual(clean({ recent: [{ url: entry.url, name: 7, publicKey: { a: 1 }, extra: 'x' }] }), { recent: [{ url: entry.url }] })
  assert.strictEqual(clean({ recent: Array.from({ length: 50 }, () => entry) }).recent.length, MAX_RECENT)
  assert.deepStrictEqual(clean({ window: { width: 800, height: 600, x: 'y' } }), { window: { width: 800, height: 600 } })
  for (const window of [{ width: '800', height: 600 }, { width: 800 }, { width: -1, height: 600 }, { width: 1e9, height: 600 }, { width: 1.5, height: 600 }]) {
    assert.deepStrictEqual(clean({ window }), {}, JSON.stringify(window))
  }
})

test('saving leaves no temporary file and replaces the whole file', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wmc-'))
  const file = path.join(dir, 'state.json')
  assert.strictEqual(save(file, { server: 'http://a', recent: [{ url: 'http://a', name: 'A long name that makes this one longer' }] }), true)
  assert.strictEqual(save(file, { server: 'http://b' }), true)
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(file, 'utf8')), { server: 'http://b' })
  assert.deepStrictEqual(fs.readdirSync(dir), ['state.json'])
  fs.rmSync(dir, { recursive: true })
})

test('a save that can\'t happen says so, and throws nothing', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wmc-'))
  assert.strictEqual(save(path.join(dir, 'no such folder', 'state.json'), {}), false)
  fs.rmSync(dir, { recursive: true })
})

test('only this user can read the file', { skip: process.platform === 'win32' && 'Windows has no such mode: its data folder is the user\'s own' }, () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wmc-'))
  const file = path.join(dir, 'state.json')
  fs.writeFileSync(file, '{}', { mode: 0o644 })
  save(file, { server: 'http://a' })
  assert.strictEqual(fs.statSync(file).mode & 0o777, 0o600)
  fs.rmSync(dir, { recursive: true })
})

test('a server\'s logo is kept with it, and only as a picture', () => {
  const logo = { version: 'v1', data: 'data:image/png;base64,iVBORw0KGgo=' }
  let s = remember({}, { url: 'http://10.0.0.2:9797', name: 'Home', logo })
  assert.deepStrictEqual(s.recent[0].logo, logo)
  s = remember(s, { url: 'http://10.0.0.2:9797', name: 'Home' })
  assert.deepStrictEqual(s.recent[0].logo, logo, 'left out, the kept one stays')
  s = remember(s, { url: 'http://10.0.0.2:9797', name: 'Home', logo: null })
  assert.strictEqual(s.recent[0].logo, undefined, 'null: the server has none now')
  for (const bad of [
    { version: 'v1', data: 'data:text/html;base64,PHNjcmlwdD4=' },
    { version: 'v1', data: 'javascript:alert(1)' },
    { version: 'v1', data: 'data:image/png;base64,' + 'A'.repeat(400 * 1024) },
    { version: '', data: logo.data },
    'data:image/png;base64,AAAA',
  ]) {
    assert.strictEqual(clean({ recent: [{ url: 'http://10.0.0.2:9797', logo: bad }] }).recent[0].logo, undefined, JSON.stringify(bad).slice(0, 60))
  }
  assert.deepStrictEqual(clean({ recent: [{ url: 'http://10.0.0.2:9797', logo }] }).recent[0].logo, logo)
})
