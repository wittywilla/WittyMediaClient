const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')
const { wanted, switches, tenFootAddress } = require('../tv.js')

test('Plasma Bigscreen is recognised from what its session sets', () => {
  assert.strictEqual(wanted([], { PLASMA_PLATFORM: 'mediacenter' }), true)
  assert.strictEqual(wanted([], { PLASMA_PLATFORM: 'mediacenter:tv' }), true)
  assert.strictEqual(wanted([], { PLASMA_DEFAULT_SHELL: 'org.kde.plasma.bigscreen' }), true)
})

test('a desktop session stays a desktop', () => {
  assert.strictEqual(wanted([], {}), false)
  assert.strictEqual(wanted([], { PLASMA_PLATFORM: 'desktop', XDG_CURRENT_DESKTOP: 'KDE' }), false)
  assert.strictEqual(wanted([], { PLASMA_PLATFORM: 'phone:handset' }), false)
})

test('the flags beat the session', () => {
  assert.strictEqual(wanted(['--tv'], {}), true)
  assert.strictEqual(wanted(['--no-tv'], { PLASMA_PLATFORM: 'mediacenter' }), false)
  assert.strictEqual(wanted(['--tv', '--no-tv'], {}), false)
})

test('the on-screen keyboard is only asked for on Wayland', () => {
  const hasKeyboard = (env) => switches(env).some(([name]) => name === 'enable-wayland-ime')
  assert.strictEqual(hasKeyboard({ XDG_SESSION_TYPE: 'x11' }), false)
  assert.strictEqual(hasKeyboard({}), false)
  assert.strictEqual(hasKeyboard({ XDG_SESSION_TYPE: 'wayland' }), true)
  assert.strictEqual(hasKeyboard({ WAYLAND_DISPLAY: 'wayland-0' }), true)
})

test('a TV never opens the keyring's set-up wizard', () => {
  for (const env of [{}, { XDG_SESSION_TYPE: 'wayland' }]) {
    const asked = new Map(switches(env))
    assert.strictEqual(asked.get('password-store'), 'basic')
    assert.strictEqual(asked.get('disable-features'), 'DbusSecretPortal')
  }
})

test('the big screen address keeps the server and what was asked for', () => {
  assert.strictEqual(tenFootAddress('http://192.168.1.20:8096'), 'http://192.168.1.20:8096/?tv=1')
  assert.strictEqual(tenFootAddress('https://media.example/home?x=1'), 'https://media.example/home?x=1&tv=1')
  assert.strictEqual(new URL(tenFootAddress('http://a.example')).origin, 'http://a.example')
})

test('the launcher entry suits a TV launcher and a desktop menu alike', () => {
  const { build } = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'))
  const { entry } = build.linux.desktop
  const { category } = build.linux
  assert.strictEqual(entry.Terminal, 'false', 'Bigscreen leaves out anything run in a terminal')
  assert.strictEqual(entry.NoDisplay, undefined, 'and anything hidden')
  assert.ok(!/(^|;)Game(;|$)/.test(category), 'a Game goes in the row for games')
  assert.ok(category.includes('AudioVideo'))
})
