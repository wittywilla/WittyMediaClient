// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The connect screen's pages (choose a server, its address, a code from the server, signing in with a code,
// showing a code to approve on a phone) in a real browser, at the sizes people use, desktop and TV. Each is one
// card, centred both ways, with a logo and a name at its top (the app's, or the server's once one is chosen),
// and fits without scrolling on any screen 720 pixels tall or more: WittyMediaServer's docs/DESIGN.md,
// "Standalone pages". The app itself is stood in for by a bridge (window.wittyClient) with two servers.
// Set SHOTS to a folder for a picture of each.
import { test, expect } from '@playwright/test'
import { mkdirSync } from 'node:fs'

const SIZES = [[1280, 720], [1366, 768], [1440, 900], [1920, 1080], [360, 640], [390, 844]]
const TV_SIZES = [[1920, 1080], [1280, 720]]
const shots = process.env.SHOTS || ''
if (shots) mkdirSync(shots, { recursive: true })

// The app's side, as the desktop app's preload gives it, answering at once.
const bridge = (tv) => `window.wittyClient = {
  tv: ${tv}, supportsDiscovery: true,
  startDiscovery(cb) { setTimeout(() => cb([{ url: 'http://192.168.1.20:9797', name: 'Riverside Media', id: 'srv-1' }]), 50) },
  async recent() { return [{ url: 'http://192.168.1.30:9797', name: 'Lakeside', id: 'srv-2', lastUsed: Date.now() }] },
  async probe(address) { return { ok: true, url: 'http://192.168.1.20:9797', name: 'Riverside Media', version: '0.8.3-alpha', identity: { state: 'new', fingerprint: 'AB12 CD34 EF56' } } },
  async open() { return { ok: true } },
  async redeem() { return { error: 'credentials' } },
  async enterCode() { return { error: 'code-not-found' } },
  enterCodeStop() {},
  async pairStart() { return { ok: true, code: 'QDLJ-SKDB', approveAt: '192.168.1.20:9797/pair', scan: 'http://192.168.1.20:9797/pair?c=QDLJ-SKDB', pin: '481902', pinSec: 30, intervalSec: 60 } },
  async pairPoll() { return { status: 'waiting' } }, async pairPin() { return { pin: '481902', pinSec: 30 } }, pairStop() {},
}`

const click = (page, name) => page.getByRole('button', { name, exact: true }).first().click()
// Each page: how to reach it from the start, and the words that say it's there.
const PAGES = [
  { id: 'choose', go: async () => {}, ready: 'Add a server', tv: true },
  { id: 'address', go: (p) => click(p, 'Type an address'), ready: 'Server address', tv: true },
  { id: 'enter-code', go: (p) => click(p, 'Enter a code'), ready: 'Connect' },
  { id: 'sign-in-code', go: (p) => p.locator('.server', { hasText: '192.168.1.20' }).first().click(), ready: 'Sign in with a password instead' },
  { id: 'tv-code', go: (p) => p.locator('.server', { hasText: '192.168.1.20' }).first().click(), ready: 'Use a password instead', tvOnly: true },
  { id: 'tv-pair', go: async (p) => { await p.locator('.server', { hasText: '192.168.1.20' }).first().click(); await click(p, 'Show a code on this screen instead') }, ready: 'QDLJ-SKDB', tvOnly: true },
]

for (const pg of PAGES) {
  for (const tv of pg.tvOnly ? [true] : pg.tv ? [false, true] : [false]) {
    for (const [width, height] of tv ? TV_SIZES : SIZES) {
      const at = `${pg.id}${tv ? ' TV' : ''} ${width}x${height}`
      test(at, async ({ page }) => {
        await page.setViewportSize({ width, height })
        await page.addInitScript(bridge(tv))
        await page.goto('/index.html')
        await pg.go(page)
        await expect(page.getByText(pg.ready, { exact: false }).first()).toBeVisible()
        await page.evaluate(() => document.fonts.ready.then(() => document.getAnimations().forEach((a) => { try { a.finish() } catch (e) { /* done */ } })))
        const m = await page.evaluate(() => {
          const card = document.querySelector('[data-standalone-card]') || document.body
          const r = card.getBoundingClientRect()
          const brand = card.querySelector('.lockup, .server-pill')
          const mark = brand && brand.querySelector('img.mark, svg.mark')
          const mr = mark ? mark.getBoundingClientRect() : { width: 0, height: 0 }
          const root = document.scrollingElement
          return { left: r.left, right: innerWidth - r.right, top: r.top, bottom: innerHeight - r.bottom, scroll: root.scrollHeight - innerHeight, wide: root.scrollWidth - innerWidth,
            card: card !== document.body, name: brand ? brand.innerText.trim() : '', mark: mr.width > 8 && mr.height > 8 && (mark.tagName !== 'IMG' || (mark.complete && mark.naturalWidth > 0)) }
        })
        if (shots) await page.screenshot({ path: `${shots}/${pg.id}${tv ? '-tv' : ''}-${width}x${height}.png` })
        expect(m.card, `${at}: one card`).toBe(true)
        expect(m.wide, `${at}: no sideways scrolling`).toBeLessThanOrEqual(1)
        expect(Math.abs(m.left - m.right), `${at}: centred across`).toBeLessThanOrEqual(4)
        expect(m.mark, `${at}: a logo`).toBe(true)
        expect(m.name.length, `${at}: a name`).toBeGreaterThan(0)
        if (height >= 720) {
          expect(m.scroll, `${at}: no scrolling`).toBeLessThanOrEqual(1)
          expect(Math.abs(m.top - m.bottom), `${at}: centred down`).toBeLessThanOrEqual(4)
        }
      })
    }
  }
}
