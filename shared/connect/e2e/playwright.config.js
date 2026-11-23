// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The shared connect screen in Chromium, served by serve.mjs.
import { defineConfig, devices } from '@playwright/test'

const port = 18095

export default defineConfig({
  testDir: '.',
  workers: 2,
  retries: 0,
  reporter: [['list']],
  use: { baseURL: `http://127.0.0.1:${port}`, trace: 'retain-on-failure' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: { command: `node serve.mjs ${port}`, url: `http://127.0.0.1:${port}/index.html`, reuseExistingServer: false, timeout: 30_000 },
})
