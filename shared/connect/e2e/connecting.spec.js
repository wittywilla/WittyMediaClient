// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The connecting screen (connect.js, connectingScreen; WittyMediaClient#173) in a real browser. A slow join, as from
// away through a relay: from the moment the link is given until it ends, the page stays on the connecting screen,
// its steps tick off in order with the one being tried said in words, the time so far moves on, and the slow hint
// comes after a while. The list of servers never shows in between. Cancel goes back to where the link was typed,
// and a join that fails with words alone shows them on the step it stopped at, with Try again and Back.
// The app itself is stood in for by a bridge (window.wittyClient) whose join takes a few seconds.
import { test, expect } from '@playwright/test'

// steps: when (ms after the join starts) each step gets through. ends: when the join answers, and what.
const bridge = (opts) => `(() => {
  const o = ${JSON.stringify(opts)}
  const STEPS = [
    { id: 'read', title: 'Code or link read', doing: 'Reading the code or link…' },
    { id: 'found', title: 'Server found', doing: 'Looking for your server…' },
    { id: 'secure', title: 'Encrypted connection made', doing: 'Looking for a way to reach your server…' },
    { id: 'signin', title: 'Signed in', doing: 'Signing in…' },
  ]
  let started = 0
  let cancelled = false
  window.joinCancelled = () => cancelled
  window.wittyClient = {
    tv: false, supportsDiscovery: true,
    startDiscovery(cb) { setTimeout(() => cb([{ url: 'http://192.168.1.20:9797', name: 'Riverside Media', id: 'srv-1' }]), 50) },
    async recent() { return [{ url: 'http://192.168.1.30:9797', name: 'Lakeside', id: 'srv-2', lastUsed: Date.now() }] },
    async probe() { return { error: 'unreachable' } },
    async open() { return { ok: true } },
    async enterCode() { return { error: 'code-not-found' } },
    enterCodeStop() {},
    invite() {
      started = Date.now()
      cancelled = false
      return new Promise((resolve) => setTimeout(() => resolve(o.result), o.ends))
    },
    async joinProgress() {
      if (!started) return null
      const ms = Date.now() - started
      const passed = STEPS.filter((s, i) => ms >= o.steps[i])
      const at = passed.length < STEPS.length ? passed.length : -1
      const sec = Math.floor(ms / 1000)
      return {
        name: ms >= o.named ? 'Riverside Media' : '', logo: '',
        steps: STEPS.map((s, i) => ({ id: s.id, title: s.title, state: i < passed.length ? 'ok' : i === at ? 'now' : 'wait' })),
        step: at >= 0 ? STEPS[at].id : '', doing: at >= 0 ? STEPS[at].doing : '',
        clock: Math.floor(sec / 60) + ':' + String(sec % 60).padStart(2, '0'),
        slow: ms >= o.slowAt ? 'This can take up to a minute the first time from away.' : '', failure: null,
      }
    },
    joinCancel() { cancelled = true },
  }
})()`

const LINK = 'wittymedia://p2p/12D3KooWQYhTNQdmr3ArTeUHRYzFg94BKyTkoWBDWez9kSCVe2Xo?s=abcdefghijklmnop'

async function giveLink(page) {
  await page.goto('/index.html')
  await page.getByRole('button', { name: 'Type an address', exact: true }).first().click()
  await page.locator('#address').fill(LINK)
  await page.getByRole('button', { name: 'Connect', exact: true }).first().click()
}

// What the page shows, a few times a second, until `until` holds or `secs` pass.
async function watch(page, secs, until) {
  const seen = []
  const end = Date.now() + secs * 1000
  while (Date.now() < end) {
    const now = await page.evaluate(() => ({
      connecting: !!document.querySelector('.connecting .connecting-steps'),
      list: !!document.querySelector('.server') || /On your network|Used before/.test(document.body.innerText),
      states: [...document.querySelectorAll('.connecting-steps .check-step')].map((li) => li.className.replace('check-step', '').trim()).join(','),
      doing: (document.querySelector('.connecting-doing') || {}).textContent || '',
      slow: (document.querySelector('.connecting-slow') || {}).textContent || '',
      clock: (document.querySelector('.connecting-clock') || {}).textContent || '',
      title: (document.querySelector('h1') || {}).textContent || '',
      brand: (document.querySelector('.connecting-brand') || {}).textContent || '',
    }))
    seen.push(now)
    if (until && until(now)) break
    await page.waitForTimeout(250)
  }
  return seen
}

test('a slow join stays on the connecting screen, its steps advancing, and never shows the list', async ({ page }) => {
  await page.addInitScript(bridge({ steps: [200, 2500, 6000, 99999], named: 2500, slowAt: 4000, ends: 7000, result: { ok: true } }))
  await giveLink(page)
  const seen = await watch(page, 9)
  const after = seen.slice(seen.findIndex((x) => x.connecting))
  expect(after.length, 'the connecting screen showed').toBeGreaterThan(10)
  expect(after.every((x) => x.connecting), 'it stayed on the connecting screen').toBe(true)
  expect(seen.some((x) => x.list), 'the list of servers never showed').toBe(false)
  // Empty only for the moment before the app's first answer about the join.
  const states = [...new Set(after.map((x) => x.states).filter(Boolean))]
  expect(states).toEqual(['now,wait,wait,wait', 'ok,now,wait,wait', 'ok,ok,now,wait', 'ok,ok,ok,now'].filter((s) => states.includes(s)))
  expect(states.length, 'the steps advanced').toBeGreaterThanOrEqual(3)
  expect(after.some((x) => x.doing === 'Looking for a way to reach your server…')).toBe(true)
  expect(after.some((x) => /Riverside Media/.test(x.brand)), 'the server is named once known').toBe(true)
  expect(after.every((x) => !/Riverside Media/.test(x.title)), 'and only once').toBe(true)
  expect(after.some((x) => x.slow.startsWith('This can take up to a minute')), 'the slow hint').toBe(true)
  expect(after[0].slow, 'no hint before it has taken a while').toBe('')
  expect(new Set(after.map((x) => x.clock)).size, 'the time so far moves on').toBeGreaterThan(3)
})

test('Cancel stops the join and goes back to where the link was typed', async ({ page }) => {
  await page.addInitScript(bridge({ steps: [200, 99999, 99999, 99999], named: 99999, slowAt: 99999, ends: 60000, result: { ok: true } }))
  await giveLink(page)
  await expect(page.locator('.connecting .connecting-steps')).toBeVisible()
  await page.getByRole('button', { name: 'Cancel', exact: true }).click()
  await expect(page.locator('#address')).toBeVisible()
  expect(await page.evaluate(() => window.joinCancelled())).toBe(true)
})

test('words alone show on the step it stopped at, with Try again and Back', async ({ page }) => {
  await page.addInitScript(bridge({ steps: [200, 99999, 99999, 99999], named: 99999, slowAt: 99999, ends: 1500, result: { error: 'invite-refused', message: 'That invite was used.' } }))
  await giveLink(page)
  await expect(page.locator('.connecting .check-step.fail')).toContainText('That invite was used.')
  await expect(page.locator('.connecting .check-step.fail')).toContainText('Server found')
  await expect(page.getByRole('button', { name: 'Try again', exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Back', exact: true }).last().click()
  await expect(page.locator('#address')).toBeVisible()
})

// With SHOTS set to a folder: a picture of the connecting screen part way, at the sizes people use.
for (const [width, height] of [[1280, 720], [390, 844]]) {
  test(`picture ${width}x${height}`, async ({ page }) => {
    test.skip(!process.env.SHOTS, 'SHOTS not set')
    await page.setViewportSize({ width, height })
    await page.addInitScript(bridge({ steps: [200, 1500, 99999, 99999], named: 1500, slowAt: 3000, ends: 60000, result: { ok: true } }))
    await giveLink(page)
    await expect(page.locator('.connecting-slow')).not.toBeEmpty({ timeout: 10000 })
    await page.screenshot({ path: `${process.env.SHOTS}/connecting-${width}x${height}.png` })
  })
}
