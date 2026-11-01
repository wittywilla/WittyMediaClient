// What a reading can check of the FreeBSD package and the Linux entry, on any system.
const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const here = path.join(__dirname, '..')
const folder = path.join(here, 'build', 'freebsd')
const launcher = fs.readFileSync(path.join(folder, 'wittymediaclient.sh'), 'utf8')
const uninstall = fs.readFileSync(path.join(folder, 'uninstall.sh'), 'utf8')
const { build, desktopName, productName } = JSON.parse(fs.readFileSync(path.join(here, 'package.json'), 'utf8'))

test('the launcher clears what the other platforms switch off inside their own Electron', () => {
  for (const name of ['ELECTRON_RUN_AS_NODE', 'NODE_OPTIONS']) assert.match(launcher, new RegExp(`unset[^\\n]*\\b${name}\\b`))
  assert.strictEqual(build.electronFuses.runAsNode, false)
  assert.strictEqual(build.electronFuses.enableNodeOptionsEnvironmentVariable, false)
})

test('the launcher starts the installed archive, and passes on what it was given', () => {
  assert.match(launcher, /exec "\$electron" \/usr\/local\/share\/wittymediaclient\/app\.asar \$no_sound "\$@"/)
  assert.match(launcher, /"\$electron" \/usr\/local\/share\/wittymediaclient\/app\.asar "\$@" &/)
})

test('a sound server the launcher started goes when the app does', () => {
  assert.match(launcher, /sndiod -d/)
  assert.match(launcher, /kill "\$sound_server"/)
})

test('the window, the command and the entry are known by one name', () => {
  assert.strictEqual(desktopName, `${build.linux.executableName}.desktop`)
  assert.strictEqual(build.linux.desktop.entry.StartupWMClass, build.linux.executableName)
  assert.strictEqual(build.linux.desktop.entry.Name, productName)
})

for (const [name, file] of [['launcher', 'wittymediaclient.sh'], ['uninstaller', 'uninstall.sh']]) {
  test(`the ${name} is plain sh that parses`, { skip: process.platform === 'win32' && 'no sh here' }, () => {
    assert.strictEqual(spawnSync('sh', ['-n', path.join(folder, file)]).status, 0)
  })
}

test('the uninstaller asks in plain words, about the program and your data apart', () => {
  assert.match(uninstall, /ask "Remove the program\?"/)
  assert.match(uninstall, /ask "Delete your \$KEPT too\?"/)
  assert.match(uninstall, /Type yes to go ahead/)
  assert.match(uninstall, /--dry-run/)
  assert.match(uninstall, /What's left:/)
})

test('the uninstaller only ever deletes the two folders that are the app\'s', () => {
  const deletions = uninstall.split('\n').filter((line) => /^\s*(if )?\brm\b/.test(line))
  assert.strictEqual(deletions.length, 1)
  assert.match(deletions[0], /rm -rf -- "\$folder"/)
  assert.match(uninstall, /for name in WittyMediaClient WittyMedia; do/)
})

test('every package that adds a launcher entry says what it left when it goes', () => {
  for (const kind of ['deb', 'rpm', 'pacman']) assert.strictEqual(build[kind].afterRemove, 'build/linux/after-remove.sh')
  assert.ok(build.linux.target.some((t) => t.target === 'pacman'))
})

test('the removal message reaches every package manager that removes it', { skip: process.platform === 'win32' && 'no bash here' }, () => {
  const script = fs.readFileSync(path.join(here, 'build', 'linux', 'after-remove.sh'), 'utf8')
    .replace(/\$\{executable\}/g, 'not-here-at-all').replace(/\$\{sanitizedProductName\}/g, 'NotHereAtAll')
  const says = (arg) => spawnSync('bash', ['-c', script, 'after-remove', arg], { encoding: 'utf8' }).stdout.includes('has been removed')
  for (const removing of ['remove', '0', '0.2.2-1']) assert.strictEqual(says(removing), true, removing)
  for (const upgrading of ['upgrade', '1']) assert.strictEqual(says(upgrading), false, upgrading)
})
