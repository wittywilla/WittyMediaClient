const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')
const { WINDOW_BUTTONS, windowButtonsAt, windowButtonsShown, doubleClickAction, windowChanged, menu } = require('../mac.js')

const read = (...parts) => fs.readFileSync(path.join(__dirname, '..', ...parts), 'utf8')

test('the window\'s buttons sit in the middle of the title bar, at the left', () => {
  const at = windowButtonsAt(32)
  assert.strictEqual(at.y * 2 + WINDOW_BUTTONS, 32)
  assert.ok(at.x > 0 && at.x < 20)
  assert.ok(Number.isInteger(windowButtonsAt(33).y))
})

test('the window\'s buttons go with the title bar, except in the system\'s full screen', () => {
  assert.strictEqual(windowButtonsShown(true, false), true)
  assert.strictEqual(windowButtonsShown(false, false), false, 'a video taking over the window')
  assert.strictEqual(windowButtonsShown(false, true), true, 'the system shows them at the top of the screen')
})

test('a double-click on the title bar does what the Mac is set to do', () => {
  assert.strictEqual(doubleClickAction('Maximize'), 'zoom')
  assert.strictEqual(doubleClickAction(''), 'zoom', 'not set is the system\'s default')
  assert.strictEqual(doubleClickAction(undefined), 'zoom')
  assert.strictEqual(doubleClickAction('Fill'), 'zoom')
  assert.strictEqual(doubleClickAction('Minimize'), 'minimize')
  assert.strictEqual(doubleClickAction('None'), 'none')
})

test('a window that moved, changed size or was minimised has changed', () => {
  const bounds = { x: 10, y: 20, width: 800, height: 600 }
  const look = (change = {}, minimized = false) => ({ bounds: { ...bounds, ...change }, minimized })
  assert.strictEqual(windowChanged(look(), look()), false)
  for (const change of [{ x: 0 }, { y: 0 }, { width: 1440 }, { height: 900 }]) assert.strictEqual(windowChanged(look(), look(change)), true, JSON.stringify(change))
  assert.strictEqual(windowChanged(look(), look({}, true)), true)
})

test('the menu bar has the system\'s menus, the server\'s and Help', () => {
  const done = []
  const items = menu({
    connected: true, changeServer: () => done.push('change'), zoom: (step) => done.push(step),
    openLogs: () => done.push('logs'), copyDiagnostics: () => done.push('copy'),
  })
  assert.deepStrictEqual(items.map((m) => m.role || m.label), ['appMenu', 'editMenu', 'View', 'Server', 'windowMenu', 'help'])
  const all = items.flatMap((m) => m.submenu || [])
  const named = (label) => all.filter((i) => i.label === label)
  for (const i of [...named('Actual Size'), ...named('Zoom In'), ...named('Zoom Out'), ...named('Change server'), ...named('Open logs folder'), ...named('Copy diagnostic info')]) i.click()
  assert.deepStrictEqual(done, [0, 1, 1, -1, 'change', 'logs', 'copy'])
  assert.ok(all.some((i) => i.role === 'togglefullscreen'))
  // An installed copy has no way to open the developer tools, and nothing here reloads.
  assert.ok(!all.some((i) => /reload|devtools/i.test(i.role || '')))
})

test('Change server is only offered with a server open', () => {
  const change = (connected) => menu({ connected }).flatMap((m) => m.submenu || []).find((i) => i.id === 'change-server')
  assert.strictEqual(change(true).enabled, true)
  assert.strictEqual(change(false).enabled, false)
})

test('on a Mac the title bar leaves the window\'s buttons and Help to the system', () => {
  const css = read('titlebar', 'titlebar.css')
  assert.match(css, /\.mac #help, \.mac \.ctl \{ display: none; \}/)
  assert.match(css, /\.mac body::before \{[^}]*min-width: \d+px/, 'room for the system\'s buttons')
  // The class is there before the bar is drawn, so the other buttons never show.
  const html = read('titlebar', 'index.html')
  assert.ok(html.indexOf('src="platform.js"') < html.indexOf('<body>'))
  assert.match(read('titlebar', 'platform.js'), /classList\.add\('mac'\)/)
})
