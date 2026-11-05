// The connect screen: choose a server found on the network or type an address,
// then prove it with a security code. It works from a TV remote, a keyboard or a
// mouse. Platforms that can do more than a web page (the desktop app) provide
// window.wittyClient: a web page can't search the network or check a signature.
(function () {
  const S = self.WittyStrings
  const app = document.getElementById('app')
  const announcer = document.getElementById('announce')
  const CODE_LENGTH = 6
  const NONE_AFTER_MS = 6000

  const ERRORS = {
    empty: S.errEmpty, scheme: S.errScheme, credentials: S.errCredentials, invalid: S.errInvalid,
    'public-http': S.errPublicHttp, unreachable: S.errUnreachable, 'not-server': S.errNotServer,
    identity: S.identityBad, certificate: S.errCertificate,
  }

  // Without a native bridge: a plain web page on a smart TV.
  const webBridge = {
    supportsDiscovery: false,
    // Whatever an address came from, only one that passes the rules is ever asked or opened.
    async probe(address) {
      const { url, error } = self.WittyAddress.normalizeAddress(address)
      if (error) return { error }
      try {
        const res = await fetch(url + '/api/status', { credentials: 'omit' })
        const data = await res.json()
        if (!data || data.name !== 'WittyMediaServer') return { error: 'not-server' }
        return { ok: true, url, version: data.version, name: data.brandName || data.name, identity: { state: 'none' } }
      } catch (e) { return { error: 'unreachable' } }
    },
    async recent() {
      try { return self.WittyAddress.cleanRecent(JSON.parse(localStorage.getItem('wmc.recent') || '[]')) } catch (e) { return [] }
    },
    async open(server) {
      const { url, error } = self.WittyAddress.normalizeAddress(server.url)
      if (error) return { error }
      try { localStorage.setItem('wmc.recent', JSON.stringify([{ url, name: server.name }])) } catch (e) { /* private mode */ }
      location.href = url
      return { ok: true }
    },
  }
  const bridge = self.wittyClient || webBridge

  let screenBack = null
  let onScreenKey = null
  let found = []
  let renderFound = null // set while the server list is on screen
  let userMoved = false
  let listAvailable = bridge.supportsDiscovery // is there a list to go back to?
  let listFocus = '' // what was chosen from the list, to come back to: an address, or ENTER_ADDRESS
  let screen = 0 // which screen this is, so an answer that arrives late can tell it has been left
  const ENTER_ADDRESS = 'enter-address'

  // Roles and aria-* are attributes: as properties, older browsers ignore them.
  function el(tag, props, ...kids) {
    const n = document.createElement(tag)
    for (const k of Object.keys(props || {})) {
      if (k === 'role' || k.indexOf('aria-') === 0) n.setAttribute(k, props[k])
      else n[k] = props[k]
    }
    for (const k of kids) n.appendChild(typeof k === 'string' ? document.createTextNode(k) : k)
    return n
  }

  function button(label, onclick, opts) {
    const b = el('button', { type: 'button', onclick, className: (opts && opts.className) || '' }, label)
    if (opts && opts.sub) b.appendChild(el('span', { className: 'sub', textContent: opts.sub }))
    if (opts && opts.url) b.dataset.url = opts.url
    return b
  }

  // Written for the older browsers built into smart TVs.
  function show(...kids) {
    screen++
    renderFound = null
    userMoved = false
    screenBack = null
    onScreenKey = null
    app.textContent = ''
    for (const k of kids) app.appendChild(k)
    // Focus lands on a control, so a screen reader wouldn't otherwise hear which screen this is.
    const title = app.querySelector('h1')
    if (title) {
      announcer.textContent = title.textContent
      document.title = `${title.textContent} - ${S.appName}`
    }
    const first = app.querySelector('input') || app.querySelector('button.primary') || app.querySelector('button')
    if (first) first.focus()
    return screen
  }

  // Asking a server can take seconds. This says so, and Back or Cancel leaves it.
  function waitScreen() {
    const turn = show(el('h1', { textContent: S.connecting }), el('div', { className: 'row' }, button(S.cancel, () => listScreen())))
    screenBack = () => listScreen()
    return turn
  }

  const serverButton = (s) => button(s.name || s.url, () => { listFocus = s.url; choose(s.url) }, { sub: s.url, url: s.url })

  async function listScreen(message) {
    const turn = ++screen
    let recent = []
    try { recent = await bridge.recent() } catch (e) { /* nothing remembered, then */ }
    if (turn !== screen) return undefined
    listAvailable = bridge.supportsDiscovery || recent.length > 0
    if (!listAvailable) return addressScreen(message)

    const foundList = el('div', { className: 'list' })
    const recentList = el('div', { className: 'list' }, ...recent.map(serverButton))
    const recentHeading = el('h2', { textContent: S.recentServers })
    const status = el('p', { role: 'status', textContent: S.findSearching })
    const children = [el('h1', { textContent: S.findTitle })]
    if (message) children.push(el('p', { className: 'error', role: 'alert', textContent: message }))
    if (bridge.supportsDiscovery) {
      children.push(el('h2', { textContent: S.foundServers }), status, foundList)
    } else {
      children.push(el('p', { textContent: S.findNotSupported }))
    }
    if (recent.length) {
      children.push(recentHeading, recentList)
    }
    const enterAddress = button(S.enterAddress, () => { listFocus = ENTER_ADDRESS; addressScreen() })
    children.push(el('div', { className: 'row' }, enterAddress))
    if (bridge.openLogs) children.push(button(S.openLogs, () => bridge.openLogs(), { className: 'link' }))
    children.push(el('p', { className: 'legal', textContent: S.legalConnect }))
    show(...children)

    // Servers come and go while this is on screen: keep focus on the same one,
    // and offer the first one found until the person has moved themselves.
    renderFound = () => {
      const focusedUrl = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.url : ''
      const hadFocus = foundList.contains(document.activeElement)
      const focusedIndex = Array.from(foundList.children).indexOf(document.activeElement)
      foundList.textContent = ''
      for (const s of found) foundList.appendChild(serverButton(s))
      status.textContent = found.length ? '' : (Date.now() - startedAt > NONE_AFTER_MS ? S.findNone : S.findSearching)
      // A remembered server that has just been found is listed once, under what was found. This comes
      // before focus moves, so nothing below can land on a row that's about to be hidden.
      Array.from(recentList.children).forEach((b) => {
        const twin = Array.from(foundList.children).find((f) => f.dataset.url === b.dataset.url)
        const wasFocused = document.activeElement === b
        b.hidden = !!twin
        if (wasFocused && twin) twin.focus()
      })
      recentHeading.hidden = recentList.children.length > 0 && Array.from(recentList.children).every((b) => b.hidden)
      const same = Array.from(foundList.children).find((b) => b.dataset.url === focusedUrl)
      if (same && hadFocus) same.focus()
      else if (hadFocus) {
        // The focused server went away. Without this, a remote has nothing to move from: its
        // remembered row if it has one, the next server, or the first thing left.
        const remembered = Array.from(recentList.children).find((b) => b.dataset.url === focusedUrl && !b.hidden)
        const neighbour = foundList.children[Math.min(focusedIndex, foundList.children.length - 1)]
        const fallback = remembered || neighbour || app.querySelector('button:not([hidden])')
        if (fallback) fallback.focus()
      } else if (!userMoved && foundList.firstChild) foundList.firstChild.focus()
    }
    const startedAt = Date.now()
    renderFound()
    // Coming back: to the thing that was chosen, and discovery leaves it there.
    const cameFrom = listFocus === ENTER_ADDRESS ? enterAddress : Array.from(app.querySelectorAll('button:not([hidden])')).find((b) => b.dataset.url === listFocus)
    if (cameFrom) {
      cameFrom.focus()
      userMoved = true
    }
    if (bridge.supportsDiscovery) setTimeout(() => { if (renderFound) renderFound() }, NONE_AFTER_MS + 100)
    return undefined
  }

  function addressScreen(message, value) {
    const input = el('input', {
      id: 'address', type: 'text', value: value || '', autocapitalize: 'off', spellcheck: false,
      autocomplete: 'off', inputMode: 'url', placeholder: '192.168.1.20',
      'aria-describedby': 'address-hint address-error',
    })
    const error = el('p', { id: 'address-error', className: 'error', role: 'alert', textContent: message || '' })
    const say = (text) => {
      error.textContent = text
      input.setAttribute('aria-invalid', text ? 'true' : 'false')
    }
    say(message || '')
    const go = button(S.connect, () => submit(input, say, go), { className: 'primary' })
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); go.click() } })
    const row = el('div', { className: 'row' }, go)
    if (listAvailable) row.appendChild(button(S.back, () => listScreen()))
    show(
      el('h1', { textContent: S.addressTitle }),
      el('p', { id: 'address-hint', textContent: S.addressHint }),
      el('label', { htmlFor: 'address', textContent: S.addressLabel }),
      input, error, row,
      el('p', { className: 'legal', textContent: S.legalConnect }),
    )
    if (listAvailable) screenBack = () => listScreen()
  }

  async function ask(url) {
    try { return await bridge.probe(url) } catch (e) { return { error: 'unreachable' } }
  }

  async function submit(input, say, go) {
    const r = self.WittyAddress.normalizeAddress(input.value)
    if (r.error) { say(ERRORS[r.error]); input.focus(); return }
    const turn = screen
    go.disabled = true
    go.textContent = S.connecting
    const server = await ask(r.url)
    if (turn !== screen) return
    go.disabled = false
    go.textContent = S.connect
    if (server.error) { say(ERRORS[server.error]); input.focus(); return }
    next(server)
  }

  async function choose(url, message) {
    const turn = waitScreen()
    const server = await ask(url)
    if (turn !== screen) return undefined
    if (server.error) return addressScreen(ERRORS[server.error], url)
    return next(server, message)
  }

  // What this server needs before it can be opened.
  function next(server, message) {
    const state = server.identity ? server.identity.state : 'none'
    if (state === 'different') return identityScreen(server, message)
    if (state === 'bad') return addressScreen(S.identityBad, server.url)
    if (state === 'new' && bridge.redeem && !server.setupRequired) return codeScreen(server, message)
    return enter({ url: server.url, name: server.name })
  }

  // The app has the last word: the server may no longer be what the person just saw.
  async function enter(request) {
    const turn = waitScreen()
    let r
    try { r = await bridge.open(request) } catch (e) { r = { error: 'unreachable' } }
    if (turn !== screen || !r || !r.error) return undefined
    if (r.error === 'changed') return choose(request.url, S.identityChanged)
    return addressScreen(ERRORS[r.error] || S.errInvalid, request.url)
  }

  function identityScreen(server, message) {
    const children = [
      el('h1', { textContent: S.identityTitle }),
      el('p', { textContent: S.identityHint }),
    ]
    if (message) children.push(el('p', { className: 'error', role: 'alert', textContent: message }))
    children.push(
      el('p', { className: 'fingerprint', textContent: `${server.url} · ${S.fingerprintLabel}: ${(server.identity && server.identity.fingerprint) || ''}` }),
      button(S.back, () => listScreen(), { className: 'primary' }),
      el('div', { className: 'row' }, button(S.identityTrust, () => enter({ url: server.url, name: server.name, trust: true }))),
    )
    show(...children)
    screenBack = () => listScreen()
  }

  function codeScreen(server, message) {
    let code = ''
    let busy = false
    // The row of dots is for the eye. A screen reader gets the same thing in words.
    const display = el('div', { className: 'code', 'aria-hidden': 'true' })
    const progress = el('p', { className: 'code-status', role: 'status' })
    const error = el('p', { className: 'error', role: 'alert', textContent: message || '' })
    const paint = () => {
      display.textContent = '•'.repeat(code.length) + '–'.repeat(CODE_LENGTH - code.length)
      progress.textContent = `${code.length} ${S.codeEntered}`
    }
    const send = async () => {
      busy = true
      progress.textContent = S.connecting
      const turn = screen
      let r
      try { r = await bridge.redeem(server.url, code) } catch (e) { r = { error: 'unreachable' } }
      busy = false
      if (r.ok || turn !== screen) return
      if (r.error === 'changed') { choose(server.url, S.identityChanged); return }
      code = ''
      paint()
      error.textContent = r.message || ERRORS[r.error] || S.errInvalid
    }
    const type = (digit) => {
      if (busy || code.length >= CODE_LENGTH) return
      code += digit
      error.textContent = ''
      paint()
      if (code.length === CODE_LENGTH) send()
    }
    const erase = () => {
      if (busy) return
      code = code.slice(0, -1)
      paint()
    }
    const pad = el('div', { className: 'pad', role: 'group', 'aria-label': S.codeLabel })
    for (const d of ['1', '2', '3', '4', '5', '6', '7', '8', '9']) pad.appendChild(button(d, () => type(d)))
    pad.appendChild(button(S.codeDelete, erase))
    pad.appendChild(button('0', () => type('0')))
    paint()
    const usePassword = button(S.usePassword, () => enter({ url: server.url, name: server.name }))
    show(
      el('h1', { textContent: S.codeTitle }),
      el('p', { textContent: S.codeHint }),
      display, progress, error, pad,
      el('div', { className: 'row' }, usePassword, button(S.back, () => listScreen())),
      el('p', { className: 'fingerprint', textContent: `${S.fingerprintLabel}: ${(server.identity && server.identity.fingerprint) || ''}` }),
    )
    screenBack = () => listScreen()
    onScreenKey = (e) => {
      if (/^[0-9]$/.test(e.key)) { if (!e.repeat) type(e.key); return true }
      if (e.key === 'Backspace') { erase(); return true }
      return false
    }
  }

  // Arrow keys move to the nearest control in that direction. Inside a text box
  // left and right belong to the text, so only up and down leave it.
  function moveFocus(dir) {
    const cur = document.activeElement
    const all = Array.from(app.querySelectorAll('button:not(:disabled):not([hidden]), input'))
    if (!all.length) return false
    if (!all.includes(cur)) { all[0].focus(); return true }
    const a = cur.getBoundingClientRect()
    const ax = a.left + a.width / 2, ay = a.top + a.height / 2
    let best = null, bestScore = Infinity
    for (const n of all) {
      if (n === cur) continue
      const b = n.getBoundingClientRect()
      const dx = b.left + b.width / 2 - ax, dy = b.top + b.height / 2 - ay
      const along = dir === 'left' ? -dx : dir === 'right' ? dx : dir === 'up' ? -dy : dy
      const across = dir === 'left' || dir === 'right' ? Math.abs(dy) : Math.abs(dx)
      if (along <= 1) continue
      const score = along + across * 2
      if (score < bestScore) { bestScore = score; best = n }
    }
    if (best) best.focus()
    return !!best
  }

  const DIRS = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right' }
  // Back on a remote: GoBack on many boxes, 461 on webOS, 10009 on Tizen.
  const isBack = (e) => e.key === 'Escape' || e.key === 'GoBack' || e.key === 'BrowserBack' || e.keyCode === 461 || e.keyCode === 10009

  document.addEventListener('keydown', (e) => {
    // Ctrl+1 or Alt+Left mean something else, to the system if not to this page.
    if (e.ctrlKey || e.altKey || e.metaKey) return
    if (isBack(e)) {
      if (screenBack) { e.preventDefault(); screenBack() }
      else if (bridge.topBack) bridge.topBack() // nowhere further back: a TV needs a way out
      return
    }
    if (onScreenKey && onScreenKey(e)) { e.preventDefault(); return }
    const dir = DIRS[e.key]
    if (!dir) return
    if (document.activeElement && document.activeElement.tagName === 'INPUT' && (dir === 'left' || dir === 'right')) return
    userMoved = true
    if (moveFocus(dir)) e.preventDefault()
  })

  if (bridge.supportsDiscovery) {
    bridge.startDiscovery((servers) => {
      found = servers
      if (renderFound) renderFound()
    })
  }

  // A message from the app, such as "the saved server has gone away".
  const params = new URLSearchParams(location.search)
  // Only the app sends this. In a plain web page, a link can't send someone off to look at a server.
  const mismatch = self.wittyClient ? params.get('mismatch') : ''
  if (mismatch) choose(mismatch)
  else listScreen(params.get('certificate') ? S.errCertificate : params.get('lost') ? S.errLost : '')
})()
