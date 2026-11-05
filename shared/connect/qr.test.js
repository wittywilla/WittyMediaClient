// The QR encoder. Every version and mask it makes was read back by a phone-grade decoder (the
// system's own on a Mac) while it was written; these hold it to what was read then, and check
// the parts of a symbol any reader looks for first.
const test = require('node:test')
const assert = require('node:assert')
const crypto = require('node:crypto')
const { encode, MAX_VERSION } = require('./qr.js')

const picture = (rows) => rows.map((row) => row.map((dark) => (dark ? '1' : '0')).join('')).join('\n')
const digest = (rows) => crypto.createHash('sha256').update(picture(rows)).digest('hex')

test('makes the same symbols that were read back while it was written', () => {
  const pair = encode('http://127.0.0.1:9797/pair?code=BCDF-GHJK')
  assert.deepStrictEqual([pair.version, pair.mask], [3, 1])
  assert.strictEqual(digest(pair.rows), '03d72a730e751665e12ec0370ba03014de7dc64755b77553c6ff7ef9a82464da')
  const hello = encode('HELLO')
  assert.deepStrictEqual([hello.version, hello.mask], [1, 4])
  assert.strictEqual(digest(hello.rows), 'c346c75add5698735afe3f7eb4f3e6c57ccefd9563f45f65c6d76aa518fb6f91')
})

test('a longer address takes a bigger symbol, up to a limit', () => {
  let last = 0
  for (const length of [10, 40, 80, 120, 160, 213]) {
    const { version, rows } = encode('x'.repeat(length))
    assert.ok(version >= last && version <= MAX_VERSION, `${length} bytes`)
    assert.strictEqual(rows.length, version * 4 + 17)
    for (const row of rows) assert.strictEqual(row.length, rows.length)
    last = version
  }
  assert.strictEqual(encode('x'.repeat(214)), null)
  assert.ok(encode('é'.repeat(100)), 'two bytes each in UTF-8')
  assert.strictEqual(encode('é'.repeat(107)), null)
})

test('has the three finder patterns, the timing lines and the dark module', () => {
  const { rows } = encode('http://192.168.1.20:9797/pair?code=BCDF-GHJK')
  const size = rows.length
  for (const [x0, y0] of [[0, 0], [size - 7, 0], [0, size - 7]]) {
    for (let y = 0; y < 7; y++) {
      for (let x = 0; x < 7; x++) {
        const ring = Math.max(Math.abs(x - 3), Math.abs(y - 3))
        assert.strictEqual(rows[y0 + y][x0 + x], ring !== 2, `finder at ${x0},${y0}`)
      }
    }
  }
  for (let i = 8; i < size - 8; i++) {
    assert.strictEqual(rows[6][i], i % 2 === 0)
    assert.strictEqual(rows[i][6], i % 2 === 0)
  }
  assert.strictEqual(rows[size - 8][8], true)
})

test('says its error correction level and mask the same way in both places', () => {
  for (const text of ['HELLO', 'http://127.0.0.1:9797/pair?code=BCDF-GHJK', 'x'.repeat(150)]) {
    const { rows, mask } = encode(text)
    const size = rows.length
    const bit = (x, y) => (rows[y][x] ? 1 : 0)
    let first = 0
    let second = 0
    const a = [[8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 7], [8, 8], [7, 8], [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8]]
    a.forEach(([x, y], i) => { first |= bit(x, y) << i })
    for (let i = 0; i < 8; i++) second |= bit(size - 1 - i, 8) << i
    for (let i = 8; i < 15; i++) second |= bit(8, size - 15 + i) << i
    assert.strictEqual(first, second, text)
    const format = (first ^ 0x5412) >>> 10
    assert.strictEqual(format >>> 3, 0, 'level M')
    assert.strictEqual(format & 7, mask)
  }
})
