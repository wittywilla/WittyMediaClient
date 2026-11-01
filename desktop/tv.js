// Whether this copy of the app is running on a TV, and what that changes. Plain rules, with
// nothing from Electron, so they can be tested without a window.

// Plasma Bigscreen's session sets these itself: see plasma-bigscreen-common-env in its source.
const BIGSCREEN_PLATFORM = 'mediacenter'
const BIGSCREEN_SHELL = 'org.kde.plasma.bigscreen'

// --tv and --no-tv decide if they're there, and the session decides if they aren't.
function wanted(argv = [], env = {}) {
  if (argv.includes('--no-tv')) return false
  if (argv.includes('--tv')) return true
  return String(env.PLASMA_PLATFORM || '').split(':').includes(BIGSCREEN_PLATFORM) || env.PLASMA_DEFAULT_SHELL === BIGSCREEN_SHELL
}

// What a TV needs from Chromium. The sign-in cookie is kept in the system's keyring, whose first
// use opens a set-up wizard over the app, and a TV has nobody with a keyboard to get through
// it. So a TV keeps the cookie in the app's own folder, readable only by this user.
//
// Chromium only talks to an on-screen keyboard on Wayland when asked to, and a remote has
// nothing else to type an address with. Version 3 is the one Plasma's keyboard speaks.
function switches(env = {}) {
  const needed = [['password-store', 'basic']]
  if (env.XDG_SESSION_TYPE !== 'wayland' && !env.WAYLAND_DISPLAY) return needed
  return [...needed, ['enable-wayland-ime'], ['wayland-text-input-version', '3']]
}

// The address that turns on the server's own big screen mode: larger type and the stronger
// focus. The server's page remembers it for this device.
function tenFootAddress(url) {
  const address = new URL(url)
  address.searchParams.set('tv', '1')
  return address.href
}

module.exports = { wanted, switches, tenFootAddress }
