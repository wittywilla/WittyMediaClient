const test = require('node:test')
const assert = require('node:assert')
const { create, GRACE_MS } = require('../playback.js')

// A clock that only moves when the test says so.
function setUp() {
  const changes = []
  const timers = new Map()
  let next = 1
  let now = 0
  const awake = create({
    apply: (on) => changes.push(on),
    setTimer: (fn, ms) => { timers.set(next, { fn, at: now + ms }); return next++ },
    clearTimer: (id) => timers.delete(id),
  })
  const pass = (ms) => {
    now += ms
    for (const [id, t] of [...timers]) if (t.at <= now) { timers.delete(id); t.fn() }
  }
  return { awake, changes, pass }
}

test('kept awake while something plays, and only told once', () => {
  const { awake, changes } = setUp()
  awake.playing(true)
  awake.audible(true)
  awake.playing(true)
  assert.deepStrictEqual(changes, [true])
  assert.strictEqual(awake.awake, true)
})

test('let go a while after it stops, which covers the gap before the next episode', () => {
  const { awake, changes, pass } = setUp()
  awake.playing(true)
  awake.playing(false)
  pass(GRACE_MS - 1)
  assert.deepStrictEqual(changes, [true], 'still awake just before')
  awake.playing(true)
  pass(GRACE_MS * 2)
  assert.deepStrictEqual(changes, [true], 'the next one started in time')
  awake.playing(false)
  pass(GRACE_MS)
  assert.deepStrictEqual(changes, [true, false])
})

test('sound alone keeps it awake, as from a page that plays through Web Audio', () => {
  const { awake, changes, pass } = setUp()
  awake.audible(true)
  awake.audible(false)
  pass(GRACE_MS)
  assert.deepStrictEqual(changes, [true, false])
})

test('the website turning it off lets go at once, and nothing keeps it awake until it is on again', () => {
  const { awake, changes } = setUp()
  awake.playing(true)
  awake.allowed(false)
  assert.deepStrictEqual(changes, [true, false])
  awake.audible(true)
  assert.deepStrictEqual(changes, [true, false])
  awake.allowed(true)
  assert.deepStrictEqual(changes, [true, false, true])
  awake.allowed('nonsense')
  assert.strictEqual(awake.awake, true, 'only a plain no turns it off')
})

test('a new page starts from nothing, with the website\'s choice back to on', () => {
  const { awake, changes, pass } = setUp()
  awake.allowed(false)
  awake.playing(true)
  awake.reset()
  assert.deepStrictEqual(changes, [])
  awake.playing(true)
  awake.reset()
  assert.deepStrictEqual(changes, [true, false], 'at once, not after the wait')
  pass(GRACE_MS)
  assert.deepStrictEqual(changes, [true, false])
})
