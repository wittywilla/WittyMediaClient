#!/usr/bin/env node
// Builds WittyMediaClient for FreeBSD: `npm run package:freebsd`, on FreeBSD.
//
// Electron publishes nothing for FreeBSD, and electron-builder has no way to make a package
// there, but FreeBSD's ports tree builds Electron itself. So this package holds only the app, and
// depends on the system's Electron: the same code as every other desktop, under a megabyte, and
// security updates to Electron come with `pkg upgrade`.
//
// `--stage-only` stops before `pkg create`, for a look at what would go in. It works anywhere.
import { spawnSync } from 'node:child_process'
import { chmodSync, cpSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const here = dirname(fileURLToPath(import.meta.url))
const desktop = join(here, '..', '..')
const out = join(desktop, 'out')
const work = join(out, 'freebsd')
const stage = join(work, 'stage')
const pkg = JSON.parse(readFileSync(join(desktop, 'package.json'), 'utf8'))
const stageOnly = process.argv.includes('--stage-only')
const NAME = pkg.build.linux.executableName
const USER_DATA = '~/.config/WittyMediaClient ~/.config/WittyMedia'

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options })
  if (result.status !== 0) throw new Error(`${command} ${args.join(' ')} failed`)
  return result
}

// The newest Electron the system's package repository actually has. A port is added
// long before it's built for everyone, and each one is retired within months of its last release.
function electronPort() {
  if (process.env.WMC_ELECTRON) return process.env.WMC_ELECTRON
  if (stageOnly) return 'electron42'
  const found = spawnSync('pkg', ['rquery', '-a', '%n'], { encoding: 'utf8' })
  const ports = (found.stdout || '').split('\n').filter((n) => /^electron[0-9]+$/.test(n))
  if (!ports.length) throw new Error('This package repository has no Electron. Set WMC_ELECTRON to say which to depend on.')
  return ports.sort((a, b) => Number(b.slice(8)) - Number(a.slice(8)))[0]
}

function freebsdAbi() {
  if (stageOnly) return 'FreeBSD:*:*'
  return spawnSync('pkg', ['config', 'ABI'], { encoding: 'utf8' }).stdout.trim()
}

const fileArch = (abi) => (abi.endsWith(':aarch64') ? 'arm64' : abi.split(':').pop())

function writeDesktopEntry(to) {
  const { category, description, desktop: { entry } } = pkg.build.linux
  const fields = { ...entry, Comment: description, Categories: category }
  const lines = ['[Desktop Entry]', 'Type=Application', `Exec=${NAME} %U`, `Icon=${NAME}`, ...Object.entries(fields).map(([k, v]) => `${k}=${v}`)]
  writeFileSync(to, `${lines.join('\n')}\n`)
}

function buildAppArchive(to) {
  const app = join(work, 'app')
  rmSync(app, { recursive: true, force: true })
  mkdirSync(app, { recursive: true })
  for (const item of pkg.build.files) {
    const name = item.replace('/**', '')
    cpSync(join(desktop, name), join(app, name), { recursive: true })
  }
  const { build: _build, devDependencies: _dev, ...shipped } = pkg
  writeFileSync(join(app, 'package.json'), `${JSON.stringify(shipped, null, 2)}\n`)
  cpSync(join(desktop, 'package-lock.json'), join(app, 'package-lock.json'))
  run('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], { cwd: app, shell: process.platform === 'win32' })
  rmSync(join(app, 'package-lock.json'))
  const asar = require('@electron/asar')
  return asar.createPackage(app, to)
}

function listFiles(root) {
  return readdirSync(root, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => relative(root, join(entry.parentPath, entry.name)).split(sep).join('/'))
}

rmSync(work, { recursive: true, force: true })
const prefix = join(stage, 'usr', 'local')
const shareDir = join(prefix, 'share', NAME)
for (const dir of [shareDir, join(prefix, 'bin'), join(prefix, 'share', 'applications'), join(prefix, 'share', 'icons', 'hicolor', '512x512', 'apps')]) mkdirSync(dir, { recursive: true })

const port = electronPort()
await buildAppArchive(join(shareDir, 'app.asar'))
const launcher = readFileSync(join(here, `${NAME}.sh`), 'utf8').replaceAll('%%ELECTRON%%', port)
writeFileSync(join(prefix, 'bin', NAME), launcher)
chmodSync(join(prefix, 'bin', NAME), 0o755)
cpSync(join(here, 'uninstall.sh'), join(shareDir, 'uninstall.sh'))
chmodSync(join(shareDir, 'uninstall.sh'), 0o755)
writeDesktopEntry(join(prefix, 'share', 'applications', `${NAME}.desktop`))
cpSync(join(desktop, 'build', 'icon.png'), join(prefix, 'share', 'icons', 'hicolor', '512x512', 'apps', `${NAME}.png`))
cpSync(join(desktop, '..', 'LICENSE'), join(shareDir, 'LICENSE'))
cpSync(join(desktop, '..', 'NOTICE'), join(shareDir, 'NOTICE'))

const abi = freebsdAbi()
const version = pkg.version.replaceAll('-', '.')
const manifest = {
  name: NAME,
  origin: `multimedia/${NAME}`,
  version,
  comment: pkg.build.linux.synopsis,
  desc: 'WittyMediaClient: a window around the web interface of a WittyMediaServer that you run yourself.',
  maintainer: 'wittywilla@users.noreply.github.com',
  www: pkg.homepage,
  abi,
  prefix: '/usr/local',
  licenselogic: 'single',
  licenses: ['APACHE20'],
  categories: ['multimedia'],
  deps: { [port]: { origin: `devel/${port}`, version: '*' } },
  messages: [
    { message: `WittyMediaClient is installed. Start it from your desktop's menu, or with: ${NAME}\nTo remove it, and choose what happens to your settings: ${NAME} --uninstall\n`, type: 'install' },
    { message: `WittyMediaClient has been removed.\nA package can't reach home folders, so your settings, saved sign-ins, logs and caches are still there.\nTo remove your own, run:\n  rm -rf ${USER_DATA}\nElectron stays, as other programs may use it. To remove it if nothing else needs it: pkg autoremove\n`, type: 'remove' },
  ],
}
writeFileSync(join(work, 'manifest.json'), JSON.stringify(manifest, null, 2))
const plist = [...listFiles(stage).map((file) => `/${file}`), `@dir /usr/local/share/${NAME}`].join('\n')
writeFileSync(join(work, 'plist'), `${plist}\n`)

if (stageOnly) {
  console.log(`Staged for ${port} in ${stage}`)
} else {
  run('pkg', ['create', '-M', join(work, 'manifest.json'), '-r', stage, '-p', join(work, 'plist'), '-o', work])
  const target = join(out, `${NAME}-${pkg.version}-freebsd-${fileArch(abi)}.pkg`)
  renameSync(join(work, `${NAME}-${version}.pkg`), target)
  rmSync(work, { recursive: true, force: true })
  console.log(`Built ${target}, depending on ${port}.`)
}
