// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// Whether this copy of the app is running on a TV, and what that changes. Plain rules, with
// nothing from Electron, so they can be tested without a window.

// Plasma Bigscreen's session sets these itself: see plasma-bigscreen-common-env in its source.
const BIGSCREEN_PLATFORM = 'mediacenter'
const BIGSCREEN_SHELL = 'org.kde.plasma.bigscreen'

// The session is Plasma Bigscreen: a TV, whatever the app was started with.
function bigscreen(env = {}) {
  return String(env.PLASMA_PLATFORM || '').split(':').includes(BIGSCREEN_PLATFORM) || env.PLASMA_DEFAULT_SHELL === BIGSCREEN_SHELL
}

// --tv and --no-tv decide if they're there, and the session decides if they aren't.
function wanted(argv = [], env = {}) {
  if (argv.includes('--no-tv')) return false
  if (argv.includes('--tv')) return true
  return bigscreen(env)
}

// What a TV needs from Chromium. The sign-in cookie is kept in the system's keyring, whose first
// use opens a set-up wizard over the app, and a TV has nobody with a keyboard to get through
// it. So a TV keeps the cookie in the app's own folder, readable only by this user. The feature
// is the second way Chromium reaches the keyring, through the desktop portal.
//
// Chromium only talks to an on-screen keyboard on Wayland when asked to, and a remote has
// nothing else to type an address with. Version 3 is the one Plasma's keyboard speaks.
function switches(env = {}) {
  const needed = [['password-store', 'basic'], ['disable-features', 'DbusSecretPortal']]
  if (env.XDG_SESSION_TYPE !== 'wayland' && !env.WAYLAND_DISPLAY) return needed
  return [...needed, ['enable-wayland-ime'], ['wayland-text-input-version', '3']]
}

// The address that turns on the server's own TV mode: larger type and the stronger focus. The server's
// page remembers it for this device. It also says what this device is (the server's docs/TV-MODE.md): on
// Plasma Bigscreen a TV, whose editors send to a computer with a QR code; anywhere else a computer started
// with --tv, whose editors offer Leave TV mode instead.
function tenFootAddress(url, onTv = false) {
  const address = new URL(url)
  address.searchParams.set('tv', '1')
  address.searchParams.set('client', onTv ? 'tv' : 'desktop')
  return address.href
}

module.exports = { wanted, bigscreen, switches, tenFootAddress }
