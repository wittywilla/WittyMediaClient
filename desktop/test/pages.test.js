// Things about the app's own pages and how it is packaged that a reading can check.
const test = require('node:test')
const assert = require('node:assert')
const fs = require('node:fs')
const path = require('node:path')

const here = path.join(__dirname, '..')
const shared = path.join(here, '..', 'shared')
const read = (...parts) => fs.readFileSync(path.join(...parts), 'utf8')
const css = read(shared, 'connect', 'connect.css')
const themes = JSON.parse(read(shared, 'data', 'themes.json'))
const packageFile = JSON.parse(read(here, 'package.json'))

// The Content-Security-Policy of a page, as name -> value.
function policy(html) {
  const m = /Content-Security-Policy" content="([^"]+)"/.exec(html)
  assert.ok(m, 'the page has a policy')
  return Object.fromEntries(m[1].split(';').map((d) => {
    const [name, ...value] = d.trim().split(/\s+/)
    return [name, value.join(' ')]
  }))
}

for (const [name, html] of [['connect', read(shared, 'connect', 'index.html')], ['title bar', read(here, 'titlebar', 'index.html')], ['TV menu', read(here, 'titlebar', 'tvmenu.html')]]) {
  test(`the ${name} page can only load its own files`, () => {
    const p = policy(html)
    assert.strictEqual(p['default-src'], "'none'")
    assert.strictEqual(p['script-src'], "'self'")
    assert.strictEqual(p['style-src'], "'self'")
    // These two don't fall back to default-src.
    assert.strictEqual(p['base-uri'], "'none'")
    assert.strictEqual(p['form-action'], "'none'")
    assert.ok(!/<script(?![^>]*\bsrc=)/.test(html), 'no script in the page itself')
    assert.ok(!/\son[a-z]+=/.test(html), 'no handlers in the page itself')
    assert.ok(!/\sstyle=/.test(html), 'no styles in the page itself')
  })
}

test('the connect screen uses the default theme\'s colours, under the server\'s names', () => {
  const colours = themes.themes.find((t) => t.id === themes.defaultTheme).colours
  const names = {
    '--bg': 'background', '--bg-2': 'panel', '--bg-3': 'card', '--bg-4': 'border', '--fg': 'text', '--fg-2': 'textSecondary',
    '--fg-3': 'textHint', '--accent': 'accent', '--accent-fg': 'onAccent', '--accent-text': 'accentText', '--danger': 'danger',
  }
  for (const [token, key] of Object.entries(names)) {
    const m = new RegExp(`${token}:\\s*(#[0-9a-fA-F]{6})\\b`).exec(css)
    assert.ok(m, `${token} is set`)
    assert.strictEqual(m[1].toLowerCase(), colours[key], token)
  }
})

test('the connect screen has no one-off colours or sizes outside its tokens', () => {
  const rules = css.replace(/\/\*[\s\S]*?\*\//g, '').replace(/:root\s*\{[\s\S]*?\n\}/, '')
  assert.deepStrictEqual(rules.match(/#[0-9a-fA-F]{3,8}\b/g), null, 'colours')
  assert.deepStrictEqual(rules.match(/font-size:\s*[\d.]+(px|rem|em)/g), null, 'font sizes')
  assert.deepStrictEqual(rules.match(/border-radius:\s*[\d.]+(px|rem|em)/g), null, 'corners')
})

test('the connect screen respects what people asked their system for', () => {
  assert.match(css, /prefers-reduced-motion:\s*reduce/)
  assert.match(css, /prefers-contrast:\s*more/)
  assert.match(css, /forced-colors:\s*active/)
  assert.match(css, /button:focus, input:focus \{ outline: var\(--focus-width\) solid var\(--focus\)/, 'a ring that doesn\'t depend on a pointer')
})

// How far apart two colours are to the eye, as WCAG measures it.
function contrast(a, b) {
  const lum = (hex) => {
    const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
  }
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

test('its text and focus ring can be read on what they sit on', () => {
  const token = (name) => new RegExp(`${name}:\\s*(#[0-9a-fA-F]{6})\\b`).exec(css)[1]
  for (const surface of ['--bg', '--bg-3']) {
    for (const text of ['--fg', '--fg-2', '--danger', '--accent-text']) {
      assert.ok(contrast(token(text), token(surface)) >= 4.5, `${text} on ${surface}`)
    }
    assert.ok(contrast(token('--control-line'), token(surface)) >= 3, `field outline on ${surface}`)
  }
  assert.ok(contrast(token('--fg-3'), token('--bg')) >= 4.5, 'captions on the page')
  assert.ok(contrast(token('--accent-fg'), token('--accent')) >= 4.5, 'text on the main button')
  assert.ok(contrast(token('--accent-fg'), token('--accent-2')) >= 4.5, 'text on the main button, hovered')
})

test('the title bar has real, named buttons', () => {
  const html = read(here, 'titlebar', 'index.html')
  const buttons = html.match(/<button[^>]*>/g)
  assert.strictEqual(buttons.length, 5)
  for (const b of buttons) assert.match(b, /type="button"/)
  for (const id of ['minimize', 'maximize', 'close']) assert.match(html, new RegExp(`id="${id}"[^>]*aria-label="`))
  assert.match(html, /role="toolbar"/)
  assert.ok(!/&#x/.test(html), 'no text characters standing in for icons')
})

test('every file the app loads is in the package', () => {
  const { files } = packageFile.build
  for (const source of ['main.js', 'discover.js', 'state.js']) {
    for (const [, name] of read(here, source).matchAll(/require\('\.\/([^']+)'\)/g)) {
      const top = name.split('/')[0]
      assert.ok(files.includes(name) || files.includes(`${top}/**`), `${source} needs ${name}`)
    }
  }
})

test('the package turns off what a packaged app doesn\'t need', () => {
  const fuses = packageFile.build.electronFuses
  assert.strictEqual(fuses.runAsNode, false)
  assert.strictEqual(fuses.enableNodeOptionsEnvironmentVariable, false)
  assert.strictEqual(fuses.enableNodeCliInspectArguments, false)
  assert.strictEqual(fuses.onlyLoadAppFromAsar, true)
  assert.strictEqual(fuses.enableEmbeddedAsarIntegrityValidation, true)
  assert.strictEqual(fuses.enableCookieEncryption, true)
  assert.strictEqual(fuses.grantFileProtocolExtraPrivileges, false)
})

test('versions are pinned exactly', () => {
  for (const group of [packageFile.dependencies, packageFile.devDependencies]) {
    for (const [name, version] of Object.entries(group)) assert.match(version, /^\d+\.\d+\.\d+$/, name)
  }
})
