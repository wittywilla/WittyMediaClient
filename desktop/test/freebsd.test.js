// What a reading can check of the FreeBSD package, on any system.
const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')

const here = path.join(__dirname, '..')
const launcher = fs.readFileSync(path.join(here, 'packaging', 'freebsd', 'wittymedia.sh'), 'utf8')
const { build, desktopName } = JSON.parse(fs.readFileSync(path.join(here, 'package.json'), 'utf8'))

test('the launcher clears what the other platforms switch off inside their own Electron', () => {
  for (const name of ['ELECTRON_RUN_AS_NODE', 'NODE_OPTIONS']) assert.match(launcher, new RegExp(`unset[^\\n]*\\b${name}\\b`))
  assert.strictEqual(build.electronFuses.runAsNode, false)
  assert.strictEqual(build.electronFuses.enableNodeOptionsEnvironmentVariable, false)
})

test('the launcher starts the installed archive, and passes on what it was given', () => {
  assert.match(launcher, /exec "\$electron" \/usr\/local\/share\/wittymedia\/app\.asar "\$@"/)
})

test('the window and the launcher entry are known by one name', () => {
  assert.strictEqual(desktopName, `${build.linux.executableName}.desktop`)
  assert.strictEqual(build.linux.desktop.entry.StartupWMClass, build.linux.executableName)
})
