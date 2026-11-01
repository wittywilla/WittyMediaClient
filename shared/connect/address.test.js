const test = require('node:test')
const assert = require('node:assert')
const { normalizeAddress, cleanRecent } = require('./address.js')
const { cases } = require('../data/connection-cases.json')

for (const c of cases) {
  test(`address ${JSON.stringify(c.input)}`, () => {
    assert.deepStrictEqual(normalizeAddress(c.input), c.url ? { url: c.url } : { error: c.error })
  })
}

test('what a browser remembered only gives back proper addresses', () => {
  assert.deepStrictEqual(cleanRecent([{ url: 'http://192.168.1.20:9797', name: 'Home' }]), [{ url: 'http://192.168.1.20:9797', name: 'Home' }])
  for (const bad of [null, 'text', 7, {}, { length: 2 }]) assert.deepStrictEqual(cleanRecent(bad), [])
  assert.deepStrictEqual(cleanRecent([null, 7, {}, { url: 7 }, { url: 'javascript:alert(1)' }, { url: 'file:///etc/passwd' }, { url: 'http://8.8.8.8' }]), [])
  assert.deepStrictEqual(cleanRecent([{ url: 'http://10.0.0.2/settings?x=1', name: 7 }]), [{ url: 'http://10.0.0.2', name: '' }])
  assert.strictEqual(cleanRecent(Array.from({ length: 50 }, () => ({ url: 'http://10.0.0.2' }))).length, 8)
})
