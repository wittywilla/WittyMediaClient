// The app's decisions about what a page or the network may do, kept apart from
// Electron so each can be tested on its own. Nothing here touches a window.
const MAX_ANSWER_BYTES = 64 * 1024 // far more than any answer the app reads before signing in
const MAX_NAME = 80
const MAX_MESSAGE = 300
const MAX_TOKEN = 512
const CODE_DIGITS = 6
// A person following links doesn't get near this. A hostile page opening things does.
const OUTSIDE_PER_WINDOW = 5
const OUTSIDE_WINDOW_MS = 30 * 1000

// The app's own pages have a scheme of their own, which nothing outside can serve.
const PAGE_SCHEME = 'wittymedia-app'
const CONNECT_PAGE = `${PAGE_SCHEME}://connect/index.html`
const BAR_PAGE = `${PAGE_SCHEME}://titlebar/index.html`
const TV_MENU_PAGE = `${PAGE_SCHEME}://titlebar/tvmenu.html`
const PAGE_TYPES = { html: 'text/html; charset=utf-8', css: 'text/css; charset=utf-8', js: 'text/javascript; charset=utf-8' }

// Exactly the app's own connect page, whatever is asked of it.
function isConnectUrl(url) {
  try {
    const u = new URL(url)
    return `${u.protocol}//${u.host}${u.pathname}` === CONNECT_PAGE
  } catch { return false }
}

// Which file an address on the app's scheme means: only one directly inside one of
// these two folders, by a plain name, so there's no way to spell anything else.
function pageFile(url) {
  try {
    const u = new URL(url)
    const m = /^\/([a-z]+\.(html|css|js))$/.exec(u.pathname)
    if (u.protocol !== `${PAGE_SCHEME}:` || !m || !['connect', 'titlebar'].includes(u.host)) return null
    return { folder: u.host, name: m[1], type: PAGE_TYPES[m[2]] }
  } catch { return null }
}

const originOf = (url) => { try { return new URL(url).origin } catch { return '' } }

// What to do about a page going somewhere. Only the server's own origin stays in
// the app: the connect page is only ever opened by the app itself, not by a page.
//   allow    carry on
//   stop     stay where it is
//   outside  stay, and offer the address to the person's browser
function navigation(url, { server = '', lastServer = '', redirect = false } = {}) {
  const origin = originOf(url)
  if (server && origin === server) return 'allow'
  // A redirect isn't someone following a link, so nobody asked for a browser to open.
  // And a load still under way when someone pressed Change server isn't a link either.
  if (redirect || origin === lastServer) return 'stop'
  return 'outside'
}

// Only web and mail links leave the app: anything else could open programs or files.
function outsideAddress(url) {
  try {
    const u = new URL(url)
    return ['http:', 'https:', 'mailto:'].includes(u.protocol) && u.href.length <= 2048 ? u.href : ''
  } catch { return '' }
}

// At most so many in a window of time, so a page can't bury the screen.
function budget(max = OUTSIDE_PER_WINDOW, windowMs = OUTSIDE_WINDOW_MS, now = Date.now) {
  let times = []
  return () => {
    const t = now()
    times = times.filter((at) => t - at < windowMs)
    if (times.length >= max) return false
    times.push(t)
    return true
  }
}

// A server's page may save what the server sends, including a file its script
// made (blob:). Nothing else may ask for a save, and nothing can when no server is open.
function downloadAllowed(url, server) {
  if (!server) return false
  try {
    const u = new URL(url)
    if (!['http:', 'https:', 'blob:'].includes(u.protocol)) return false
    return u.origin === server
  } catch { return false }
}

// A server's logo: a picture of one of these kinds, and no bigger than this.
const LOGO_TYPES = ['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/svg+xml']
const MAX_LOGO_BYTES = 256 * 1024
const logoType = (contentType) => {
  const type = String(contentType || '').split(';')[0].trim().toLowerCase()
  return LOGO_TYPES.includes(type) ? type : ''
}
// /api/status → brandLogo: the version of the logo, which also names it in the address.
const logoVersion = (value) => (typeof value === 'string' && /^[\x21-\x7e]{1,64}$/.test(value) ? value : '')

// Reads an answer from an address nobody has proved yet, up to a limit.
async function readJson(res, limit = MAX_ANSWER_BYTES) {
  return JSON.parse((await readBytes(res, limit)).toString('utf8'))
}

async function readBytes(res, limit) {
  const tooBig = () => Object.assign(new Error('The answer was too long'), { tooBig: true })
  if (Number(res.headers.get('content-length')) > limit) throw tooBig()
  const parts = []
  let total = 0
  if (res.body) {
    const reader = res.body.getReader()
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      total += value.length
      if (total > limit) {
        reader.cancel().catch(() => {})
        throw tooBig()
      }
      parts.push(value)
    }
  }
  return Buffer.concat(parts)
}

// Which error the connect screen shows for a failed request.
function whyFailed(err) {
  if (err && (err.tooBig || err instanceof SyntaxError)) return 'not-server'
  const text = `${(err && err.message) || ''} ${(err && err.cause && err.cause.message) || ''}`
  return /ERR_(CERT|SSL|BAD_SSL)/.test(text) ? 'certificate' : 'unreachable'
}

// Chromium's certificate failures are numbered from -200 to -299 (net_error_list.h).
const isCertificateCode = (code) => code <= -200 && code > -300

// Free text from a server or the network, before it is kept or shown.
function cleanText(value, max) {
  return String(value == null ? '' : value).replace(/\p{Cc}/gu, '').trim().slice(0, max)
}

const cleanName = (name) => cleanText(name, MAX_NAME) || 'WittyMediaServer'
const cleanMessage = (message) => cleanText(message, MAX_MESSAGE)
const validCode = (code) => typeof code === 'string' && code.length === CODE_DIGITS && /^[0-9]+$/.test(code)
// A cookie's value: one line of plain characters, with nothing that ends the cookie.
const validToken = (token) => typeof token === 'string' && token.length > 0 && token.length <= MAX_TOKEN && /^[\x21\x23-\x2b\x2d-\x3a\x3c-\x5b\x5d-\x7e]+$/.test(token)
// A code to show for someone to approve, as the server writes it (BCDF-GHJK), and the secret
// that collects the sign-in once they have. Nothing else gets as far as the screen or the server.
const validPairCode = (code) => typeof code === 'string' && /^[A-Z0-9]{2,8}(-[A-Z0-9]{2,8}){0,2}$/.test(code)
const validDeviceSecret = (secret) => typeof secret === 'string' && /^[0-9A-Za-z_-]{32,128}$/.test(secret)

// A page of the server's, from a path the server gave, and only ever on that server.
function serverPage(origin, path, fallback) {
  const wanted = typeof path === 'string' && /^\/[\x21-\x7e]{0,200}$/.test(path) ? path : fallback
  try {
    const u = new URL(wanted, origin)
    if (u.origin === origin) return u.href
  } catch { /* the fallback, then */ }
  return new URL(fallback, origin).href
}

// How long to wait before asking again, from what the server said: never so often it's rude.
function pollSeconds(value, fallback = 3) {
  return Number.isInteger(value) && value >= 1 ? Math.min(value, 60) : fallback
}

// Where the title bar asked for its menu: a point in the window, or wherever the pointer is.
function menuPoint(at, width, height) {
  if (!at || !Number.isInteger(at.x) || !Number.isInteger(at.y)) return {}
  return at.x >= 0 && at.y >= 0 && at.x <= width && at.y <= height ? { x: at.x, y: at.y } : {}
}

module.exports = {
  PAGE_SCHEME, CONNECT_PAGE, BAR_PAGE, TV_MENU_PAGE, isConnectUrl, pageFile, navigation, outsideAddress, budget, downloadAllowed, readJson, whyFailed, isCertificateCode,
  cleanText, cleanName, cleanMessage, validCode, validToken, validPairCode, validDeviceSecret, serverPage, pollSeconds, menuPoint,
  readBytes, logoType, logoVersion, MAX_ANSWER_BYTES, MAX_NAME, MAX_LOGO_BYTES,
}
