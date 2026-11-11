#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Writes the AltStore source (apps.json) for a release: the file someone adds to AltStore or SideStore
// to install the iPhone and iPad app and be offered its updates.
//
//   node scripts/altstore-source.mjs --ipa out/wittymediaclient-0.8.0-ios.ipa --tag v0.8.0 \
//     --info Info.json [--entitlements entitlements.json] [--project apple/project.yml] \
//     [--repo wittywilla/WittyMediaClient] [--date 2026-11-11T00:00:00Z] [--notes "..."] \
//     [--previous apps.json] [--out apps.json]
//
// Nothing here is guessed. The bundle identifier, version, lowest iOS and what the app asks permission
// for are read from the built app's Info.plist (--info, as JSON: `plutil -convert json`), the
// entitlements from the file XcodeGen wrote for the target (--entitlements, as JSON; none means the
// target has none), and the size from the IPA itself. With --project, each is checked against
// apple/project.yml, and the script stops if they disagree. Without --info, project.yml alone is used.
//
// Only the iOS app is listed. AltStore and SideStore install to iPhone and iPad, not to Apple TV, and
// both apps have the same bundle identifier, so the tvOS IPA is a file on the release and not an entry.
//
// It uses nothing outside Node, so the release can run it without installing anything.
import { readFileSync, statSync, writeFileSync } from 'node:fs'
import { basename } from 'node:path'

const TARGET = 'WittyMedia-iOS'
const NAME = 'WittyMediaClient'
const DEVELOPER = 'WittyWilla'
const SUBTITLE = 'Watch and listen from your WittyMediaServer'
const DESCRIPTION = [
  'WittyMediaClient connects to your own WittyMediaServer: films, shows, music, audiobooks, podcasts, photos, live TV and games, from your server to this device.',
  'It needs a WittyMediaServer to connect to. This build is unsigned: AltStore or SideStore signs it with your own Apple ID when it installs.',
].join('\n\n')
// The default theme's accent from the themes every client shares, without the #, as AltStore wants it.
const themes = JSON.parse(readFileSync(new URL('../shared/data/themes.json', import.meta.url), 'utf8'))
const TINT = themes.themes.find((theme) => theme.id === themes.defaultTheme).colours.accent.replace(/^#/, '').toUpperCase()

// What a signer needs that a free Apple ID can't give, so that a build carrying one would install and
// then fail, or not install at all. Each is matched as the start of an entitlement's name.
const NOT_ON_A_FREE_ACCOUNT = [
  ['aps-environment', 'push notifications'],
  ['com.apple.developer.aps-environment', 'push notifications'],
  ['com.apple.developer.icloud', 'iCloud'],
  ['com.apple.developer.ubiquity', 'iCloud'],
  ['com.apple.developer.associated-domains', 'associated domains (universal links)'],
  ['com.apple.developer.networking.multicast', 'multicast networking'],
  ['com.apple.developer.networking.networkextension', 'network extensions'],
  ['com.apple.developer.networking.vpn', 'VPN'],
  ['com.apple.developer.in-app-payments', 'Apple Pay'],
  ['com.apple.developer.siri', 'Siri'],
  ['com.apple.developer.carplay', 'CarPlay'],
  ['com.apple.developer.applesignin', 'Sign in with Apple'],
  ['com.apple.developer.usernotifications', 'special notifications'],
  ['com.apple.developer.nfc', 'NFC'],
]
// A free Apple ID can have these, but the signer gives the app its own, so what the code names won't match.
const CHANGED_BY_THE_SIGNER = [
  ['com.apple.security.application-groups', 'App Groups: AltStore and SideStore make a group of their own for each Apple ID, so a group named in the code is not the one the app gets'],
  ['keychain-access-groups', 'keychain groups: they start with the signer\'s team, not the project\'s'],
]
// What every signer adds itself: not the app's own, and AltStore leaves them out of a source.
const ADDED_BY_SIGNING = ['application-identifier', 'com.apple.developer.team-identifier', 'get-task-allow']

function fail(why) {
  console.error(`altstore-source: ${why}`)
  process.exit(1)
}

function warn(what) {
  // An annotation on the run when GitHub is running it, a plain line otherwise.
  console.error(process.env.GITHUB_ACTIONS ? `::warning title=AltStore source::${what}` : `warning: ${what}`)
}

function options(argv) {
  const known = ['ipa', 'tag', 'info', 'entitlements', 'project', 'repo', 'date', 'notes', 'previous', 'out', 'icon-url']
  const found = {}
  for (let i = 0; i < argv.length; i += 2) {
    const name = argv[i].replace(/^--/, '')
    if (!argv[i].startsWith('--') || !known.includes(name)) fail(`unknown option ${argv[i]}`)
    if (argv[i + 1] === undefined) fail(`${argv[i]} needs a value`)
    found[name] = argv[i + 1]
  }
  return found
}

const readJson = (path) => {
  try { return JSON.parse(readFileSync(path, 'utf8')) } catch (error) { return fail(`can't read ${path} as JSON: ${error.message}`) }
}

// The few facts this needs from apple/project.yml, read by the shape XcodeGen's file has. It isn't a
// YAML reader: it finds one target's block and the settings above the targets, and nothing more.
function fromProject(path) {
  const text = readFileSync(path, 'utf8').replace(/\r\n/g, '\n')
  const strip = (value) => value.replace(/\s+#.*$/, '').trim().replace(/^["']|["']$/g, '')
  const first = (block, key) => {
    const match = block.match(new RegExp(`^\\s*${key}:\\s*(.+)$`, 'm'))
    return match ? strip(match[1]) : undefined
  }
  const start = text.search(/^targets:\s*$/m)
  if (start < 0) fail(`${path} has no targets`)
  const shared = text.slice(0, start)
  const targets = text.slice(start)
  const at = targets.search(new RegExp(`^  ${TARGET}:\\s*$`, 'm'))
  if (at < 0) fail(`${path} has no target ${TARGET}`)
  const rest = targets.slice(at + 1)
  const next = rest.search(/^  [A-Za-z0-9_-]+:\s*$/m)
  const target = next < 0 ? rest : rest.slice(0, next + 1)
  const deployment = shared.match(/^\s*deploymentTarget:\s*\n((?:\s+.*\n)+?)(?=\s{0,2}\S)/m)
  // Entitlements are listed under `entitlements:` then `properties:`, one key to a line at the next depth.
  const entitlements = []
  const block = target.match(/^(\s+)entitlements:\s*\n((?:\1\s+.*\n?)+)/m)
  if (block) {
    const properties = block[2].match(/^(\s+)properties:\s*\n((?:\1\s+.*\n?)+)/m)
    if (properties) {
      const depth = properties[2].match(/^(\s+)/)[1].length
      for (const line of properties[2].split('\n')) {
        const key = line.match(/^(\s+)([A-Za-z0-9._-]+):/)
        if (key && key[1].length === depth) entitlements.push(key[2])
      }
    }
  }
  return {
    bundleIdentifier: first(target, 'PRODUCT_BUNDLE_IDENTIFIER') ?? first(shared, 'PRODUCT_BUNDLE_IDENTIFIER'),
    version: first(target, 'MARKETING_VERSION') ?? first(shared, 'MARKETING_VERSION'),
    build: first(target, 'CURRENT_PROJECT_VERSION') ?? first(shared, 'CURRENT_PROJECT_VERSION'),
    minOSVersion: deployment ? first(deployment[1], 'iOS') : undefined,
    privacy: Object.fromEntries([...target.matchAll(/^\s*(NS[A-Za-z]+UsageDescription):\s*(.+)$/gm), ...shared.matchAll(/^\s*(NS[A-Za-z]+UsageDescription):\s*(.+)$/gm)].map((m) => [m[1], strip(m[2])])),
    entitlements,
  }
}

// The same facts from the built app, which is what a device is actually given.
function fromInfo(info) {
  const families = info.UIDeviceFamily ?? []
  if (!families.includes(1) || !families.includes(2)) fail(`the app's UIDeviceFamily is ${JSON.stringify(families)}: it has to hold 1 (iPhone) and 2 (iPad) to be one IPA for both`)
  if (info.CFBundleSupportedPlatforms && !info.CFBundleSupportedPlatforms.includes('iPhoneOS')) fail(`the app was built for ${info.CFBundleSupportedPlatforms}, not iPhoneOS`)
  return {
    bundleIdentifier: info.CFBundleIdentifier,
    version: info.CFBundleShortVersionString,
    build: info.CFBundleVersion,
    minOSVersion: info.MinimumOSVersion,
    privacy: Object.fromEntries(Object.entries(info).filter(([key]) => /^NS.*UsageDescription$/.test(key))),
  }
}

const sameVersion = (a, b) => {
  const parts = (v) => String(v).split('.').map(Number)
  const [x, y] = [parts(a), parts(b)]
  return Array.from({ length: Math.max(x.length, y.length) }, (_, i) => (x[i] ?? 0) === (y[i] ?? 0)).every(Boolean)
}

const opts = options(process.argv.slice(2))
for (const needed of ['ipa', 'tag']) if (!opts[needed]) fail(`--${needed} is needed`)
if (!opts.info && !opts.project) fail('give --info (the built app\'s Info.plist as JSON), --project (apple/project.yml), or both')

const project = opts.project ? fromProject(opts.project) : undefined
const built = opts.info ? fromInfo(readJson(opts.info)) : undefined
const facts = { ...project, ...built }

if (project && built) {
  if (project.bundleIdentifier !== built.bundleIdentifier) fail(`the app says its bundle identifier is ${built.bundleIdentifier}, and ${opts.project} says ${project.bundleIdentifier}`)
  if (project.minOSVersion && !sameVersion(project.minOSVersion, built.minOSVersion)) fail(`the app needs iOS ${built.minOSVersion}, and ${opts.project} says ${project.minOSVersion}`)
}
for (const [key, value] of Object.entries({ bundleIdentifier: facts.bundleIdentifier, version: facts.version, minOSVersion: facts.minOSVersion })) {
  if (!value) fail(`couldn't find the app's ${key}`)
}

// Entitlements: the generated file when there is one, or else what project.yml lists for the target.
const entitlements = (opts.entitlements ? Object.keys(readJson(opts.entitlements)) : project?.entitlements ?? [])
  .filter((name) => !ADDED_BY_SIGNING.includes(name))
  .sort()
for (const name of entitlements) {
  const refused = NOT_ON_A_FREE_ACCOUNT.find(([prefix]) => name.startsWith(prefix))
  const changed = CHANGED_BY_THE_SIGNER.find(([prefix]) => name.startsWith(prefix))
  if (refused) warn(`${name}: a free Apple ID can't sign for ${refused[1]}, so a sideloaded copy won't have it`)
  else if (changed) warn(`${name}: ${changed[1]}`)
}

const repo = opts.repo ?? process.env.GITHUB_REPOSITORY ?? 'wittywilla/WittyMediaClient'
if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) fail(`--repo should be owner/name, not ${repo}`)
if (!/^[A-Za-z0-9_.+-]+$/.test(opts.tag)) fail(`--tag ${opts.tag} isn't a tag name this can put in an address`)
const date = new Date(opts.date ?? Date.now())
if (Number.isNaN(date.getTime())) fail(`--date ${opts.date} isn't a date`)
const size = statSync(opts.ipa).size
if (size === 0) fail(`${opts.ipa} is empty`)

const site = `https://github.com/${repo}`
const iconURL = opts['icon-url'] ?? `https://raw.githubusercontent.com/${repo}/${opts.tag}/desktop/build/icon.png`
const notes = opts.notes ?? `WittyMediaClient ${opts.tag.replace(/^v/, '')}. What changed: ${site}/blob/${opts.tag}/CHANGELOG.md`

const version = {
  version: facts.version,
  ...(facts.build ? { buildVersion: String(facts.build) } : {}),
  date: date.toISOString().replace(/\.\d{3}Z$/, 'Z'),
  localizedDescription: notes,
  downloadURL: `${site}/releases/download/${opts.tag}/${basename(opts.ipa)}`,
  size,
  minOSVersion: facts.minOSVersion,
}

// Earlier releases stay listed, newest first, so AltStore can offer an older one to an older iOS.
let earlier = []
if (opts.previous) {
  const before = readJson(opts.previous).apps?.find((app) => app.bundleIdentifier === facts.bundleIdentifier)
  earlier = (before?.versions ?? []).filter((v) => v.downloadURL !== version.downloadURL && !(v.version === version.version && v.buildVersion === version.buildVersion))
}

const source = {
  name: NAME,
  // Older AltStore and SideStore tell sources apart by this; newer ones use the address the file came from.
  identifier: `${facts.bundleIdentifier}.source`,
  subtitle: SUBTITLE,
  description: DESCRIPTION,
  iconURL,
  website: site,
  tintColor: TINT,
  featuredApps: [facts.bundleIdentifier],
  apps: [
    {
      name: NAME,
      bundleIdentifier: facts.bundleIdentifier,
      developerName: DEVELOPER,
      subtitle: SUBTITLE,
      localizedDescription: DESCRIPTION,
      iconURL,
      tintColor: TINT,
      category: 'entertainment',
      screenshots: [],
      versions: [version, ...earlier],
      // AltStore shows these before installing, and refuses an app that asks for one that isn't listed.
      appPermissions: {
        entitlements,
        privacy: facts.privacy ?? {},
      },
      // The same facts once more, flat, for versions of AltStore and SideStore from before `versions`.
      version: version.version,
      versionDate: version.date,
      versionDescription: version.localizedDescription,
      downloadURL: version.downloadURL,
      size: version.size,
    },
  ],
  news: [],
}

const text = `${JSON.stringify(source, null, 2)}\n`
if (opts.out) {
  writeFileSync(opts.out, text)
  console.error(`altstore-source: wrote ${opts.out}: ${NAME} ${version.version} (${version.buildVersion ?? 'no build number'}), iOS ${version.minOSVersion} or later, ${size} bytes, ${entitlements.length} entitlements`)
} else {
  process.stdout.write(text)
}
