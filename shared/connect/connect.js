// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The connect screen: choose a server found on the network or type an address,
// then prove it with a security code, or show a code to approve from a phone. It works
// from a TV remote, a keyboard or a mouse. Platforms that can do more than a web page (the
// desktop app) provide window.wittyClient: a web page can't search the network or check a
// signature. It looks as docs/APP-DESIGN.md says: Signing in, screens 1, 2, 3, 7 and 8.
(function () {
  const S = self.WittyStrings
  const app = document.getElementById('app')
  const announcer = document.getElementById('announce')
  const CODE_LENGTH = 6
  const NONE_AFTER_MS = 6000
  const SHAKE_MS = 400
  const SVG = 'http://www.w3.org/2000/svg'

  const ERRORS = {
    empty: S.errEmpty, scheme: S.errScheme, credentials: S.errCredentials, invalid: S.errInvalid,
    'public-http': S.errPublicHttp, unreachable: S.errUnreachable, 'not-server': S.errNotServer,
    identity: S.identityBad, certificate: S.errCertificate,
    // Reaching a server from away, peer to peer (the desktop app; see its p2p.js).
    invite: S.errInvite, 'invite-refused': S.errInviteRefused, 'p2p-missing': S.errAwayMissing, 'p2p-failed': S.errAwayFailed,
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
  // A TV's look: the words on the left, what to do on the right, sized for across the room.
  if (bridge.tv) document.documentElement.className += ' tv'

  let screenBack = null
  let onScreenKey = null
  let onLeave = null // what a screen stops when another takes its place
  let found = []
  let renderFound = null // set while the server list is on screen
  let userMoved = false
  let listAvailable = bridge.supportsDiscovery // is there a list to go back to?
  let listFocus = '' // what was chosen from the list, to come back to: an address, or ENTER_ADDRESS
  let connecting = '' // the server whose card shows a spinner while it's asked
  let screen = 0 // which screen this is, so an answer that arrives late can tell it has been left
  const ENTER_ADDRESS = 'enter-address'
  let toast = null // what was just removed, to say so on the list with a way to take it back
  const canForget = typeof bridge.forget === 'function'
  // The words with their {gaps} filled in.
  const fill = (words, values) => String(words || '').replace(/\{(\w+)\}/g, (all, key) => (values[key] === undefined ? all : String(values[key])))
  const nameOf = (s) => s.name || hostOf(s.url)
  const STALE_CHOICES = [[30, 'staleDays30'], [90, 'staleDays90'], [180, 'staleDays180'], [365, 'staleDays365']]

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

  function svg(tag, attrs, ...kids) {
    const n = document.createElementNS(SVG, tag)
    for (const k of Object.keys(attrs || {})) n.setAttribute(k, attrs[k])
    for (const k of kids) n.appendChild(k)
    return n
  }

  // The page loads no images, so its few icons are drawn here, in the colour of their words.
  // On a 24 grid, as Material Symbols and SF Symbols are.
  const ICONS = {
    back: ['M15 5l-7 7 7 7'],
    next: ['M9 5l7 7-7 7'],
    link: ['M10.2 13.8a4 4 0 0 0 5.66 0l3.2-3.2a4 4 0 0 0-5.66-5.66l-1.1 1.1', 'M13.8 10.2a4 4 0 0 0-5.66 0l-3.2 3.2a4 4 0 0 0 5.66 5.66l1.1-1.1'],
    erase: ['M9 5h10.5A1.5 1.5 0 0 1 21 6.5v11a1.5 1.5 0 0 1-1.5 1.5H9l-6.5-7z', 'M12 9.5l5 5', 'M17 9.5l-5 5'],
    rack: ['M4.5 4.5h15a1.5 1.5 0 0 1 1.5 1.5v3.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 9.5V6a1.5 1.5 0 0 1 1.5-1.5z',
      'M4.5 13h15a1.5 1.5 0 0 1 1.5 1.5V18a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18v-3.5A1.5 1.5 0 0 1 4.5 13z', 'M7 7.75h.01', 'M7 16.25h.01'],
    bin: ['M4.5 7h15', 'M9.5 7V5a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v2', 'M6.5 7l.8 11.6a1.5 1.5 0 0 0 1.5 1.4h6.4a1.5 1.5 0 0 0 1.5-1.4L17.5 7', 'M10 11v5.5', 'M14 11v5.5'],
    warning: ['M12 2.6c.6 0 1.1.3 1.4.8l9 15.8c.6 1.1-.2 2.4-1.4 2.4H3c-1.2 0-2-1.3-1.4-2.4l9-15.8c.3-.5.8-.8 1.4-.8zM10.9 8.5v6h2.2v-6zm0 8v2.2h2.2v-2.2z'],
  }
  const icon = (name, className) => svg('svg', { viewBox: '0 0 24 24', class: `icon ${name} ${className || ''}`, 'aria-hidden': 'true' },
    ...ICONS[name].map((d) => svg('path', { d })))

  // The server's own icon (web/public/icon.svg in WittyMediaServer), drawn from its geometry.
  let marks = 0
  function mark(className) {
    const fill = `url(#mark-${++marks})`
    return svg('svg', { viewBox: '0 0 64 64', class: `mark ${className || ''}`, 'aria-hidden': 'true' },
      svg('defs', {}, svg('linearGradient', { id: `mark-${marks}`, x1: '0', y1: '0', x2: '1', y2: '1' },
        svg('stop', { offset: '0', class: 'mark-from' }), svg('stop', { offset: '1', class: 'mark-to' }))),
      svg('rect', { width: '64', height: '64', rx: '14', class: 'mark-tile' }),
      svg('circle', { cx: '32', cy: '32', r: '20', fill: 'none', stroke: fill, 'stroke-width': '5' }),
      svg('path', { d: 'M27 23l14 9-14 9z', fill }))
  }

  const wordmark = (last) => el('span', { className: 'wordmark' }, 'Witty', el('span', { className: 'media', textContent: 'Media' }), last)

  // A server's picture: its own logo, which the app fetched once it proved who it is, or the mark.
  const serverMark = (logo) => (typeof logo === 'string' && logo.indexOf('data:image/') === 0
    ? el('img', { className: 'mark logo', src: logo, alt: '' }) : mark())

  // The app is WittyMediaClient until a server has been added; then the screens of that server
  // carry its own name (WittyMediaServer, as the wordmark, when it has none of its own) and logo.
  function lockup(server) {
    if (!server) return el('div', { className: 'lockup' }, mark(), wordmark('Client'))
    return el('div', { className: 'lockup' }, serverMark(server.logo), serverName(server.name, 'wordmark'))
  }

  // A server's name: its own, or WittyMediaServer styled as the wordmark when it has none.
  const serverName = (name, className) => (name && name !== 'WittyMediaServer'
    ? el('span', { className: `${className} own`, textContent: name })
    : el('span', { className }, 'Witty', el('span', { className: 'media', textContent: 'Media' }), 'Server'))
  const spinner = (className) => el('span', { className: `spinner ${className || ''}`, 'aria-hidden': 'true' })
  const legal = () => el('p', { className: 'legal', textContent: S.legalConnect })

  // kind: primary, secondary, quiet, destructive or key (docs/APP-DESIGN.md, Buttons).
  function button(label, onclick, opts) {
    const o = opts || {}
    const b = el('button', { type: 'button', onclick, className: `${o.kind || 'secondary'} ${o.className || ''}` })
    if (o.icon) b.appendChild(icon(o.icon))
    b.appendChild(el('span', { className: 'label', textContent: label }))
    if (o.label) b.setAttribute('aria-label', o.label)
    return b
  }

  // While busy, a spinner stands in for the words, and the button keeps its size and its focus.
  function setBusy(b, on, words) {
    if (!b.querySelector('.spinner')) b.appendChild(spinner())
    if (on) b.classList.add('busy')
    else b.classList.remove('busy')
    if (on) b.setAttribute('aria-busy', 'true')
    else b.removeAttribute('aria-busy')
    b.querySelector('.label').textContent = words
  }

  // A problem, said where it happened. Empty, it takes no room, but it stays in the page: a
  // live region has to be there before it speaks. The icon comes after it so that CSS can
  // hide it with the words, and is drawn before it.
  function problem(words, id) {
    const p = el('p', { className: 'error', role: 'alert', textContent: words || '' })
    if (id) p.id = id
    return { node: el('div', { className: 'problem' }, p, icon('warning')), say: (text) => { p.textContent = text } }
  }

  // An outlined field whose label rises onto the outline. The outline is a fieldset, as its
  // legend leaves the gap in the line for the label to sit in.
  const field = (input, label, iconName) => el('div', { className: 'field' }, input,
    el('label', { htmlFor: input.id, textContent: label }),
    el('fieldset', { 'aria-hidden': 'true' }, el('legend', {}, el('span', { textContent: label }))),
    icon(iconName, 'lead'))

  // One screen. What it says goes first and what can be done second: one column here, and the
  // left and right halves of a TV. back is the way back, on screen and on Escape; escape is
  // Escape alone, where the screen's own main button already goes back. lockup is the app's
  // unless a screen gives a server's, or false for none.
  function show(parts) {
    if (onLeave) {
      const leave = onLeave
      onLeave = null
      leave()
    }
    screen++
    renderFound = null
    userMoved = false
    screenBack = parts.back || parts.escape || null
    onScreenKey = null
    app.textContent = ''
    app.className = `${parts.className || ''}${parts.back ? ' with-back' : ''}`
    if (parts.back) app.appendChild(button(S.back, parts.back, { kind: 'quiet', icon: 'back', className: 'back' }))
    const brand = parts.lockup === undefined ? lockup() : parts.lockup
    app.appendChild(el('div', { className: 'words' }, ...(brand ? [brand] : []), ...parts.words))
    app.appendChild(el('div', { className: 'actions' }, ...(parts.actions || [])))
    if (parts.foot) app.appendChild(el('div', { className: 'foot' }, ...parts.foot))
    // Focus lands on a control, so a screen reader wouldn't otherwise hear which screen this is.
    const title = app.querySelector('h1')
    if (title) {
      announcer.textContent = title.textContent
      document.title = `${title.textContent} - ${S.appName}`
    }
    const first = parts.focus || app.querySelector('input') || app.querySelector('.actions .primary') || app.querySelector('.actions button')
    if (first) first.focus()
    return screen
  }

  // Asking a server can take seconds. This says so, and Back or Cancel leaves it.
  // stop is told when the person gives up waiting.
  const waitScreen = (text, stop) => {
    const leave = () => { if (stop) stop(); listScreen() }
    return show({
      escape: leave,
      className: 'centred',
      words: [spinner('large'), el('h1', { textContent: text || S.connecting })],
      actions: [button(S.cancel, leave)],
    })
  }

  const hostOf = (url) => { try { return new URL(url).host } catch (e) { return url } }

  // A saved server: its logo and name over its address. One only found on the network says
  // nothing about itself until it's added: the plain server icon, and its address alone.
  function serverCard(s, opts) {
    const o = opts || {}
    const picture = o.found ? el('span', { className: 'glyph' }, icon('rack')) : serverMark(s.logo)
    // A remembered server also says when it was last reached, so an old one can be told from one in use.
    const reached = o.found || !canForget ? '' : reachedWords(s)
    // A server only ever reached from away has no address to show: it says so instead ("From
    // away", as "Reached from away" beside "Reached 3 days ago" would say it twice).
    const where = [s.awayOnly ? (reached ? S.rowAway : S.awayOnly) : s.name ? hostOf(s.url) : '', reached].filter(Boolean).join(' · ')
    const words = o.found ? [hostOf(s.url), S.foundOnNetwork] : [s.name || hostOf(s.url), where]
    const card = el('button', { type: 'button', className: 'server', onclick: () => { listFocus = s.url; choose(s.url, '', card) } },
      picture, el('span', { className: 'who' }, el('span', { className: 'name', textContent: words[0] }), el('span', { className: 'where', textContent: words[1] })))
    if (managed && s.url === managed && !o.found) card.appendChild(el('span', { className: 'pill', textContent: S.inUse }))
    else if (o.lastUsed) card.appendChild(el('span', { className: 'pill', textContent: S.lastUsed }))
    else if (s.stale && !o.found) card.appendChild(el('span', { className: 'pill stale', textContent: S.staleServer }))
    card.appendChild(icon('next', 'chevron'))
    card.appendChild(spinner())
    card.dataset.url = s.url
    if (s.url === connecting) busyCard(card)
    return card
  }

  function reachedWords(s) {
    if (typeof s.days !== 'number') return S.lastReachedUnknown
    if (s.days === 0) return S.lastReachedToday
    return s.days === 1 ? S.lastReachedYesterday : fill(S.lastReachedDays, { days: s.days })
  }

  // A remembered server with its remove button beside it. Delete or Backspace on the card does the
  // same, and so does its right-click menu.
  function recentRow(s, opts, remove) {
    const card = serverCard(s, opts)
    if (!canForget) return card
    const bin = button('', () => remove(s), { kind: 'quiet', icon: 'bin', className: 'remove', label: fill(S.removeServerNamed, { name: nameOf(s) }) })
    bin.title = S.removeServer
    bin.dataset.remove = s.url
    card.setAttribute('aria-keyshortcuts', 'Delete')
    card.addEventListener('keydown', (e) => {
      if (e.ctrlKey || e.altKey || e.metaKey || (e.key !== 'Delete' && e.key !== 'Backspace')) return
      e.preventDefault()
      remove(s)
    })
    card.addEventListener('contextmenu', (e) => {
      e.preventDefault()
      if (bridge.serverMenu) bridge.serverMenu(s.url, { x: Math.round(e.clientX), y: Math.round(e.clientY) })
      else remove(s)
    })
    return el('div', { className: 'row' }, card, bin)
  }

  // Takes servers off this device. The app holds on to what it kept for them for a few seconds, so
  // Undo puts everything back; after that it is gone, and the server is told the sign-in is over.
  async function forgetNow(list, all, focusAfter) {
    let r
    try { r = await bridge.forget(list.map((s) => s.url)) } catch (e) { r = { ok: false } }
    if (!r || !r.ok || !r.removed.length) return listScreen()
    const words = list.length === 1 ? fill(S.removedServer, { name: nameOf(list[0]) }) : fill(S.removedCount, { count: r.removed.length })
    toast = { words, back: list[0].url, undoMs: r.undoMs || 8000, names: list.map(nameOf).join(', '), count: r.removed.length }
    if (list.some((s) => s.url === managed)) managed = ''
    // Somewhere sensible for the keyboard and a remote: the next server, the one before, or the address button.
    const left = all.filter((s) => !list.includes(s))
    const at = all.indexOf(list[0])
    const neighbour = all.slice(at + 1).find((s) => left.includes(s)) || all.slice(0, at).reverse().find((s) => left.includes(s))
    listFocus = focusAfter || (neighbour ? neighbour.url : ENTER_ADDRESS)
    return listScreen()
  }

  function toastNode() {
    const mine = toast
    toast = null
    const node = el('div', { className: 'toast', role: 'status' }, el('span', { textContent: mine.words }))
    const timer = setTimeout(() => { if (node.parentNode) node.parentNode.removeChild(node) }, mine.undoMs)
    node.appendChild(button(S.undo, async () => {
      clearTimeout(timer)
      let r
      try { r = await bridge.forgetUndo() } catch (e) { r = { ok: false } }
      listFocus = mine.back
      await refreshManaged()
      await listScreen()
      if (r && r.ok) announcer.textContent = mine.count > 1 ? fill(S.removeUndoneMany, { count: mine.count }) : fill(S.removeUndone, { name: mine.names })
    }, { kind: 'quiet', className: 'undo' }))
    return node
  }

  // The device's own setting: saved servers listed above the ones found (on by default).
  const SAVED_FIRST = 'savedServersFirst'
  function savedFirst() {
    try { return localStorage.getItem(SAVED_FIRST) !== '0' } catch (e) { return true }
  }
  function savedFirstSwitch() {
    const box = el('input', { type: 'checkbox', checked: savedFirst() })
    box.setAttribute('role', 'switch')
    box.setAttribute('aria-describedby', 'saved-first-hint')
    box.addEventListener('change', () => {
      try { localStorage.setItem(SAVED_FIRST, box.checked ? '1' : '0') } catch (e) { /* this visit only */ }
      listFocus = ''
      listScreen().then(() => { const again = app.querySelector('.pref input'); if (again) again.focus() })
    })
    return el('label', { className: 'pref' }, box, el('span', {}, el('span', { textContent: S.savedServersFirst }), el('small', { id: 'saved-first-hint', className: 'caption', textContent: S.savedServersFirstHint })))
  }

  // Yes or no, with the safe answer first and focused.
  function confirmScreen(title, body, yes, onYes) {
    show({
      escape: () => listScreen(),
      className: 'warning',
      words: [el('h1', { textContent: title }), el('p', { className: 'lead', textContent: body })],
      actions: [button(S.cancel, () => listScreen(), { kind: 'primary' }), button(yes, onYes, { kind: 'destructive' })],
    })
  }

  const namesOf = (list) => list.map(nameOf).join(', ')
  // A removal that takes the server in use says it signs out of it here.
  const inUseNote = (list, body) => (managed && list.some((s) => s.url === managed) ? `${body} ${S.removeConfirmInUse}` : body)

  // Opened from the menu while a server is in use (Manage servers): which one it is. The list
  // says so, offers the way back to it, and asks before removing it.
  let managed = ''
  async function refreshManaged() {
    if (!bridge.managing || !params.get('manage')) { managed = ''; return }
    try { managed = (await bridge.managing()).url || '' } catch (e) { managed = '' }
  }

  function removeAllScreen(recent) {
    confirmScreen(S.removeAllTitle, inUseNote(recent, fill(S.removeAllBody, { count: recent.length, names: namesOf(recent) })), S.removeAllServers, () => forgetNow(recent, recent))
  }

  // Which servers haven't been reached for a while: the person chooses how long, sees which those
  // are, and only then says yes. One whose last time isn't known is never chosen on a guess.
  function removeOldScreen(recent) {
    const said = el('p', { className: 'lead', role: 'status' })
    const choices = STALE_CHOICES.map(([days, key]) => button(S[key], () => {
      const old = recent.filter((s) => typeof s.days === 'number' && s.days >= days)
      if (!old.length) { said.textContent = S.removeOldNone; return }
      confirmScreen(S.removeOldConfirmTitle, inUseNote(old, fill(S.removeOldConfirmBody, { period: S[key], count: old.length, names: namesOf(old) })), S.remove, () => forgetNow(old, recent))
    }))
    show({
      back: () => listScreen(),
      words: [el('h1', { textContent: S.removeOldTitle }), el('p', { className: 'lead', textContent: S.removeOldHint }), said],
      actions: choices,
      focus: choices[0],
    })
  }

  function busyCard(card) {
    card.classList.add('busy')
    card.setAttribute('aria-busy', 'true')
  }

  function idleCards() {
    for (const c of Array.from(app.querySelectorAll('.server.busy'))) {
      c.classList.remove('busy')
      c.removeAttribute('aria-busy')
    }
  }

  async function listScreen(message) {
    const turn = ++screen
    let recent = []
    try { recent = await bridge.recent() } catch (e) { /* nothing remembered, then */ }
    if (turn !== screen) return undefined
    listAvailable = bridge.supportsDiscovery || recent.length > 0
    if (!listAvailable) return addressScreen(message)
    connecting = ''
    knownIds = {}
    for (const s of recent) if (s.id) knownIds[s.url] = s.id

    const lastUsed = recent.length ? recent[0].url : ''
    const foundList = el('div', { className: 'list' })
    const removeOne = (s) => (managed && s.url === managed
      ? confirmScreen(fill(S.removeConfirmTitle, { name: nameOf(s) }), `${fill(S.removeConfirmBody, { name: nameOf(s), address: hostOf(s.url) })} ${S.removeConfirmInUse}`, S.remove, () => forgetNow([s], recent))
      : forgetNow([s], recent))
    const recentList = el('div', { className: 'list' }, ...recent.map((s) => recentRow(s, { lastUsed: s.url === lastUsed }, removeOne)))
    if (bridge.onForgetAsk) bridge.onForgetAsk((url) => { const s = recent.find((r) => r.url === url); if (s && renderFound) removeOne(s) })
    // Found now and used before is one server, listed once: told by who it is, not only by where.
    const isSaved = (f) => recent.some((s) => s.url === f.url || (s.id && s.id === f.id))
    const recentHeading = el('h2', { textContent: S.recentServers })
    const status = el('p', { role: 'status', textContent: S.findSearching })
    const searching = el('div', { className: 'note' }, spinner(), status)
    const words = [el('h1', { className: 'display', textContent: S.findTitle }), el('p', { className: 'lead', textContent: S.findSubtitle })]
    if (message) words.push(problem(message).node)
    const actions = []
    const current = managed ? recent.find((s) => s.url === managed) : null
    if (current) actions.push(button(fill(S.backToServer, { name: nameOf(current) }), () => bridge.manageBack(), { kind: 'primary', icon: 'back', className: 'manage-back' }))
    const foundPart = bridge.supportsDiscovery
      ? [el('h2', {}, S.foundServers, el('span', { className: 'dot', 'aria-hidden': 'true' })), searching, foundList]
      : [el('div', { className: 'note' }, el('p', { textContent: S.findNotSupported }))]
    const savedPart = []
    if (toast) savedPart.push(toastNode())
    if (recent.length) {
      savedPart.push(recentHeading, recentList)
      const manage = [savedFirstSwitch(recent.length > 0)]
      if (canForget) {
        manage.unshift(
          button(S.removeOldServers, () => { listFocus = ENTER_ADDRESS; removeOldScreen(recent) }, { kind: 'quiet' }),
          button(S.removeAllServers, () => { listFocus = ENTER_ADDRESS; removeAllScreen(recent) }, { kind: 'quiet' }))
      }
      savedPart.push(el('div', { className: 'links manage', role: 'group', 'aria-label': S.manageServers }, ...manage))
    }
    // Saved servers first (the setting, on unless turned off): what this device has used is in
    // reach at once, the last one used on top, and what is found on the network goes below it.
    const savedOnTop = savedFirst() && recent.length > 0
    if (savedOnTop) actions.push(...savedPart, ...foundPart)
    else actions.push(...foundPart, ...savedPart)
    // The main action until there's a server to choose.
    const enterAddress = button(S.enterAddress, () => { listFocus = ENTER_ADDRESS; addressScreen() }, { icon: 'link', kind: recent.length ? 'secondary' : 'primary', className: 'enter' })
    actions.push(enterAddress)
    // For a device that has never been at home with its server: it shows a code to type in there.
    if (bridge.joinAway) actions.push(button(S.joinAway, () => joinAwayScreen(), { kind: 'quiet', icon: 'link', className: 'join-away' }))
    const foot = []
    if (bridge.openLogs) foot.push(button(S.openLogs, () => bridge.openLogs(), { kind: 'quiet', className: 'small' }))
    foot.push(legal())
    show({ words, actions, foot, escape: current ? () => bridge.manageBack() : undefined })

    // Servers come and go while this is on screen: keep focus on the same one,
    // and offer the first one found until the person has moved themselves.
    renderFound = () => {
      const focusedUrl = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.url : ''
      const hadFocus = foundList.contains(document.activeElement)
      const focusedIndex = Array.from(foundList.children).indexOf(document.activeElement)
      foundList.textContent = ''
      // A server that's found and also saved is listed once, under Used before, with its own name.
      for (const s of found) if (!isSaved(s)) foundList.appendChild(serverCard(s, { found: true }))
      const stillLooking = Date.now() - startedAt <= NONE_AFTER_MS
      // Shown before it speaks, or a screen reader may not hear it.
      searching.className = found.length ? 'note gone' : stillLooking ? 'note searching' : 'note'
      status.textContent = found.length ? '' : (stillLooking ? S.findSearching : S.findNone)
      enterAddress.className = `${found.length || recent.length ? 'secondary' : 'primary'} enter`
      const same = Array.from(foundList.children).find((b) => b.dataset.url === focusedUrl)
      if (same && hadFocus) same.focus()
      else if (hadFocus) {
        // The focused server went away. Without this, a remote has nothing to move from: its
        // remembered row if it has one, the next server, or the first thing left.
        const remembered = Array.from(recentList.querySelectorAll('.server')).find((b) => b.dataset.url === focusedUrl)
        const neighbour = foundList.children[Math.min(focusedIndex, foundList.children.length - 1)]
        const fallback = remembered || neighbour || app.querySelector('.actions button:not([hidden])')
        if (fallback) fallback.focus()
      } else if (!userMoved && !savedOnTop && foundList.firstChild) foundList.firstChild.focus()
    }
    const startedAt = Date.now()
    renderFound()
    // Coming back: to the thing that was chosen, and discovery leaves it there.
    const cameFrom = listFocus === ENTER_ADDRESS ? enterAddress : Array.from(app.querySelectorAll('button:not([hidden])')).find((b) => b.dataset.url === listFocus)
    if (cameFrom) {
      cameFrom.focus()
      userMoved = true
    } else if (savedOnTop && !current) {
      // The last one used has focus, and a server found later doesn't take it.
      const last = recentList.querySelector('.server')
      if (last) { last.focus(); userMoved = true }
    }
    // Opened from the menu while a server is in use: the way back to it comes first.
    if (current) { const back = app.querySelector('.manage-back'); if (back) { back.focus(); userMoved = true } }
    if (bridge.supportsDiscovery) setTimeout(() => { if (renderFound) renderFound() }, NONE_AFTER_MS + 100)
    return undefined
  }

  function addressScreen(message, value) {
    const input = el('input', {
      id: 'address', type: 'text', value: value || '', autocapitalize: 'off', spellcheck: false,
      autocomplete: 'off', inputMode: 'url', placeholder: '192.168.1.20',
      'aria-describedby': 'address-hint address-error',
    })
    const error = problem('', 'address-error')
    const say = (text) => {
      error.say(text)
      input.setAttribute('aria-invalid', text ? 'true' : 'false')
    }
    say(message || '')
    const go = button(S.connect, () => submit(input, say, go), { kind: 'primary' })
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); go.click() } })
    show({
      back: listAvailable ? () => listScreen() : null,
      words: [el('h1', { textContent: S.addressTitle }), el('p', { id: 'address-hint', className: 'lead', textContent: S.addressHint })]
        .concat(bridge.invite ? [el('p', { className: 'lead', textContent: S.inviteHint })] : []),
      actions: [field(input, S.addressLabel, 'link'), error.node, go],
      foot: [legal()],
    })
  }

  async function ask(url) {
    try { return await bridge.probe(url) } catch (e) { return { error: 'unreachable' } }
  }

  async function submit(input, say, go) {
    if (go.classList.contains('busy')) return
    // An invite link instead of an address: the app that can use one takes it from here.
    if (bridge.invite && /^\s*wittymedia:\/\/p2p\//i.test(input.value)) {
      const turn = screen
      setBusy(go, true, S.inviteConnecting)
      let joined
      try { joined = await bridge.invite(input.value) } catch (e) { joined = { error: 'p2p-failed' } }
      if (turn !== screen || joined.ok) return
      setBusy(go, false, S.connect)
      say(joined.message || ERRORS[joined.error] || S.errInvite)
      input.focus()
      return
    }
    const r = self.WittyAddress.normalizeAddress(input.value)
    if (r.error) { say(ERRORS[r.error]); input.focus(); return }
    const turn = screen
    setBusy(go, true, S.connecting)
    const server = await ask(r.url)
    if (turn !== screen) return
    setBusy(go, false, S.connect)
    if (server.error) { say(ERRORS[server.error]); input.focus(); return }
    next(server)
  }

  // From the list, the chosen card shows a spinner and the list stays; Escape stops it.
  async function choose(url, message, card) {
    let turn
    if (card) {
      turn = ++screen // what was being asked before this no longer counts
      idleCards()
      connecting = url
      busyCard(card)
      announcer.textContent = S.connecting
      screenBack = () => {
        ++screen
        connecting = ''
        idleCards()
        screenBack = null
      }
    } else {
      turn = waitScreen()
    }
    let server = await ask(url)
    if (turn !== screen) return undefined
    // Not where it was, but on the network now under the same ID: asked there instead. It still has
    // to prove it is the same server, and then its entry moves with it.
    const moved = server.error === 'unreachable' && card ? movedTo(url) : ''
    if (moved) {
      server = await ask(moved)
      if (turn !== screen) return undefined
    }
    connecting = ''
    if (server.error) return addressScreen(ERRORS[server.error], url)
    return next(server, message)
  }

  let knownIds = {} // each remembered address's server ID, as the list last had them
  function movedTo(url) {
    const id = knownIds[url]
    const now = id && found.find((f) => f.id === id && f.url !== url)
    return now ? now.url : ''
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

  const fingerprintOf = (server) => (server.identity && server.identity.fingerprint) || ''

  function identityScreen(server, message) {
    const said = problem(message || '')
    // A reinstalled server is a different server to this app: the old one can go, and this one is added as new.
    const old = canForget && server.identity && server.identity.old
    const removeOld = async () => {
      try { await bridge.forget([old]); await bridge.forgetFinish() } catch (e) { /* the list says what is left */ }
      listFocus = ''
      listScreen(S.removedOldOne)
    }
    show({
      escape: () => listScreen(),
      className: 'warning',
      words: [el('div', { className: 'badge' }, icon('warning')), el('h1', { textContent: S.identityTitle }), el('p', { className: 'lead', textContent: S.identityHint })]
        .concat(old ? [el('p', { className: 'lead', textContent: S.reinstalledHint })] : []),
      actions: [
        el('div', { className: 'facts' },
          el('p', { className: 'where', textContent: server.url }),
          el('p', { className: 'caption', textContent: S.fingerprintLabel }),
          el('p', { className: 'fingerprint', textContent: fingerprintOf(server) })),
        said.node,
        button(S.back, () => listScreen(), { kind: 'primary' }),
        button(S.identityTrust, () => enter({ url: server.url, name: server.name, trust: true }), { kind: 'destructive' }),
      ].concat(old ? [button(S.removeOldOne, removeOld)] : []),
    })
  }

  // The server, as the code and pairing screens name it: its mark and its name, in a pill.
  const serverPill = (server) => el('div', { className: 'server-pill' }, serverMark(server.logo), serverName(server.name, 'name'))

  const reduceMotion = () => !!(self.matchMedia && self.matchMedia('(prefers-reduced-motion: reduce)').matches)

  function codeScreen(server, message) {
    let code = ''
    let checking = false
    // The boxes are for the eye. A screen reader gets the same thing in words.
    const boxes = []
    const display = el('div', { className: 'code', 'aria-hidden': 'true' })
    for (let i = 0; i < CODE_LENGTH; i++) display.appendChild(boxes[i] = el('span', { className: 'box' }))
    const progress = el('p', { className: 'code-status', role: 'status' })
    const said = problem(message || '')
    const paintBoxes = () => {
      boxes.forEach((b, i) => {
        b.textContent = code.charAt(i)
        b.className = i === code.length && !checking ? 'box next' : 'box'
      })
      display.className = checking ? 'code checking' : 'code'
    }
    const paint = () => {
      progress.textContent = `${code.length} ${S.codeEntered}`
      paintBoxes()
    }
    const send = async () => {
      checking = true
      progress.textContent = S.connecting
      paintBoxes()
      const turn = screen
      let r
      try { r = await bridge.redeem(server.url, code) } catch (e) { r = { error: 'unreachable' } }
      checking = false
      if (r.ok || turn !== screen) return
      if (r.error === 'changed') { choose(server.url, S.identityChanged); return }
      code = ''
      progress.textContent = `0 ${S.codeEntered}`
      said.say(r.message || ERRORS[r.error] || S.errInvalid)
      // A wrong code shakes the boxes once, then they empty.
      if (reduceMotion()) { paintBoxes(); return }
      display.className = 'code shake'
      setTimeout(() => { if (turn === screen) paintBoxes() }, SHAKE_MS)
    }
    const type = (digit) => {
      if (checking || code.length >= CODE_LENGTH) return
      code += digit
      said.say('')
      paint()
      if (code.length === CODE_LENGTH) send()
    }
    const erase = () => {
      if (checking) return
      code = code.slice(0, -1)
      paint()
    }
    const pad = el('div', { className: 'pad', role: 'group', 'aria-label': S.codeLabel })
    for (const d of ['1', '2', '3', '4', '5', '6', '7', '8', '9']) pad.appendChild(button(d, () => type(d), { kind: 'key' }))
    pad.appendChild(button('', erase, { kind: 'key', icon: 'erase', label: S.codeDelete }))
    pad.appendChild(button('0', () => type('0'), { kind: 'key', className: 'zero' }))
    paint()
    const links = el('div', { className: 'links' }, button(S.usePassword, () => enter({ url: server.url, name: server.name }), { kind: 'quiet' }))
    if (bridge.pairStart) links.appendChild(button(S.showCodeInstead, () => pairScreen(server), { kind: 'quiet' }))
    show({
      back: () => listScreen(),
      className: 'compact',
      lockup: false,
      words: [el('h1', { textContent: S.codeTitle }), serverPill(server), el('p', { className: 'lead', textContent: S.codeHint }), display, progress, said.node],
      actions: [pad, links],
      foot: [el('p', { className: 'fingerprint caption', textContent: `${S.fingerprintLabel}: ${fingerprintOf(server)}` })],
      focus: pad.firstChild,
    })
    onScreenKey = (e) => {
      if (/^[0-9]$/.test(e.key)) { if (!e.repeat) type(e.key); return true }
      if (e.key === 'Backspace') { erase(); return true }
      return false
    }
  }

  // Black on white whatever the theme, with its own margin: cameras read nothing else reliably.
  function qrCode(text) {
    const symbol = self.WittyQR && self.WittyQR.encode(text)
    if (!symbol) return null
    const size = symbol.rows.length
    let d = ''
    symbol.rows.forEach((row, y) => {
      for (let x = 0; x < size; x++) {
        if (!row[x]) continue
        let run = 1
        while (x + run < size && row[x + run]) run++
        d += `M${x} ${y}h${run}v1h-${run}z`
        x += run - 1
      }
    })
    return svg('svg', { viewBox: `0 0 ${size} ${size}`, 'shape-rendering': 'crispEdges', role: 'img', 'aria-label': S.pairScan }, svg('path', { d }))
  }

  // The code is shown here, and someone already signed in approves it on a phone or a
  // computer, so nobody types a password with a remote. The app keeps the secret that
  // collects the sign-in; this page only sees the code.
  function pairScreen(server) {
    let round = 0
    const hint = el('p', { className: 'lead', textContent: S.pairHint })
    const where = el('p', { className: 'approve-at' })
    const shown = el('span', { 'aria-hidden': 'true' })
    const spoken = el('span', { className: 'sr-only' })
    const code = el('p', { className: 'pair-code' }, shown, spoken)
    const waitWords = el('span', { textContent: S.connecting })
    const waiting = el('p', { className: 'waiting', role: 'status' }, spinner(), waitWords)
    const said = problem('')
    const picture = el('div', { className: 'qr-card' })
    const qr = el('figure', { className: 'qr' }, picture, el('figcaption', { className: 'caption', textContent: S.pairScan }))
    const again = button(S.pairNew, () => begin(), { kind: 'primary' })
    const usePassword = button(S.usePassword, () => enter({ url: server.url, name: server.name }), { kind: 'quiet' })
    const links = el('div', { className: 'links' }, button(S.codeTitle, () => codeScreen(server), { kind: 'quiet' }), usePassword,
      button(S.changeServer, () => listScreen(), { kind: 'quiet' }))
    // Secure pairing: the PIN shown now, as large as the code, and when it changes.
    const pinShown = el('span', { className: 'pin-digits', 'aria-hidden': 'true' })
    const pinSpoken = el('span', { className: 'sr-only' })
    const pinLeft = el('span', { className: 'caption pin-left' })
    const pin = el('div', { className: 'pair-pin' }, el('p', { className: 'caption', textContent: S.pairPin }), el('p', { className: 'pair-code' }, pinShown, pinSpoken), pinLeft, el('p', { className: 'caption', textContent: S.pairPinHint }))
    pin.hidden = true
    let pinTimer = 0
    const showPin = (mine, digits, seconds) => {
      clearInterval(pinTimer)
      pinShown.textContent = digits.length === 6 ? digits.slice(0, 3) + ' ' + digits.slice(3) : digits
      pinSpoken.textContent = `${S.pairPin} ${digits.split('').join(' ')}`
      let left = seconds
      pinLeft.textContent = fill(S.pairPinChanges, { seconds: left })
      pin.hidden = false
      pinTimer = setInterval(async () => {
        if (turn !== screen || mine !== round) { clearInterval(pinTimer); return }
        left -= 1
        if (left > 0) { pinLeft.textContent = fill(S.pairPinChanges, { seconds: left }); return }
        clearInterval(pinTimer)
        let r
        try { r = await bridge.pairPin() } catch (e) { r = { error: 'lost' } }
        if (turn !== screen || mine !== round) return
        if (r.pin) showPin(mine, r.pin, r.pinSec || 30)
        else if (r.error === 'expired') ended(S.pairExpired)
        else setTimeout(() => showPin(mine, digits, 1), 2000) // ask again shortly
      }, 1000)
    }
    const codeShown = (on) => { hint.hidden = where.hidden = code.hidden = qr.hidden = !on; if (!on) { pin.hidden = true; clearInterval(pinTimer) } }

    const ended = (words) => {
      codeShown(false)
      waiting.hidden = true
      said.say(words)
      again.hidden = false
      again.focus()
    }
    const poll = (mine, seconds) => setTimeout(async () => {
      if (turn !== screen || mine !== round) return
      let r
      try { r = await bridge.pairPoll() } catch (e) { r = { status: 'lost' } }
      if (turn !== screen || mine !== round || r.ok) return // signed in: the app opens the server
      if (r.error === 'changed') { choose(server.url, S.identityChanged); return }
      if (r.error) { ended(ERRORS[r.error] || S.errInvalid); return }
      if (r.status === 'denied') { ended(S.pairDenied); return }
      if (r.status === 'expired') { ended(S.pairExpired); return }
      // A network that blinks is no reason to give up on a code that's still good.
      waitWords.textContent = r.status === 'lost' ? S.errLost : S.pairWaiting
      poll(mine, r.status === 'slow-down' ? Math.max(seconds, r.intervalSec || 0) + 1 : seconds)
    }, seconds * 1000)
    const begin = async () => {
      const mine = ++round
      const hadFocus = document.activeElement === again
      codeShown(false)
      again.hidden = true
      said.say('')
      waiting.hidden = false
      waitWords.textContent = S.connecting
      if (hadFocus) usePassword.focus()
      let r
      try { r = await bridge.pairStart(server.url) } catch (e) { r = { error: 'unreachable' } }
      if (turn !== screen || mine !== round) return
      if (r.error === 'changed') { choose(server.url, S.identityChanged); return }
      if (!r.ok) { ended(r.message || ERRORS[r.error] || S.errInvalid); return }
      where.textContent = r.approveAt
      shown.textContent = r.code
      spoken.textContent = r.code.replace(/[^A-Za-z0-9]/g, '').split('').join(' ') // letter by letter
      picture.textContent = ''
      const picturePart = qrCode(r.scan)
      if (picturePart) picture.appendChild(picturePart)
      codeShown(true)
      qr.hidden = !picturePart
      if (r.pin && bridge.pairPin) showPin(mine, r.pin, r.pinSec || 30)
      waitWords.textContent = S.pairWaiting
      poll(mine, r.intervalSec || 3)
    }

    const turn = show({
      back: () => codeScreen(server),
      className: 'compact',
      lockup: lockup(server),
      words: [el('h1', { textContent: S.pairTitle }), hint, where, code, pin, said.node],
      actions: [qr, waiting, again, links],
      focus: usePassword,
    })
    onLeave = () => {
      round++
      clearInterval(pinTimer)
      if (bridge.pairStop) bridge.pairStop()
    }
    begin()
  }

  // Arrow keys move to the nearest control in that direction. Inside a text box
  // left and right belong to the text, so only up and down leave it.
  // Join from away: the code in a card, as large as a TV's at home, then a spinner until someone
  // signed in to the server has typed it in there. A code that ran out, or was refused, says so
  // and offers a new one. docs/APP-DESIGN.md, From away.
  function joinAwayScreen() {
    const shown = el('span', { 'aria-hidden': 'true' })
    const spoken = el('span', { className: 'sr-only' })
    const code = el('p', { className: 'pair-code' }, shown, spoken)
    const waiting = el('p', { className: 'waiting', role: 'status' }, spinner(), el('span', { textContent: S.joinAwayWaiting }))
    const said = problem('')
    const again = button(S.pairNew, () => begin(), { kind: 'primary' })
    const leave = () => { bridge.joinAway.stop(); listScreen() }
    const turn = show({
      back: leave,
      words: [el('h1', { textContent: S.joinAwayTitle }), el('p', { className: 'lead', textContent: S.joinAwayHint })],
      actions: [code, waiting, said.node, again],
    })
    onLeave = () => bridge.joinAway.stop()
    async function begin() {
      said.say('')
      again.hidden = true
      code.hidden = true
      waiting.hidden = false
      let r
      try { r = await bridge.joinAway.start() } catch (e) { r = { error: 'p2p-failed' } }
      if (turn !== screen) return
      if (!r.code) { ended(ERRORS[r.error] || S.errAwayFailed); return }
      shown.textContent = r.code
      spoken.textContent = r.code.split('').filter((c) => c !== '-').join(' ')
      code.hidden = false
      let done
      try { done = await bridge.joinAway.wait() } catch (e) { done = { error: 'p2p-failed' } }
      if (turn !== screen || done.ok || done.error === 'stopped') return
      ended(done.error === 'expired' ? S.joinAwayExpired : done.error === 'refused' ? S.joinAwayRefused : ERRORS[done.error] || S.errAwayFailed)
    }
    function ended(words) {
      code.hidden = true
      waiting.hidden = true
      said.say(words)
      again.hidden = false
      again.focus()
    }
    begin()
  }

  // From away, for the server in use, opened from Help: how it is reached now, whether this device
  // is on its list and what the list calls it, then Stop (which asks first) or Connect again.
  async function fromAwayScreen() {
    let info
    try { info = await bridge.awayInfo() } catch (e) { info = { server: false } }
    const back = () => bridge.manageBack()
    if (!info.server) { back(); return }
    const row = (label, value) => el('p', { className: 'away-row' }, el('span', { className: 'caption', textContent: label }), el('span', { textContent: value }))
    const now = info.now === 'home' ? S.awayAtHomeNow : info.now || S.awayNoWay
    const ready = info.state === 'ready'
    const rows = [row(S.awayNow, now), row(S.rowAway, ready ? S.awayReady : S.awayNotSetUp)]
    if (ready && info.device) rows.push(row(S.awayDevice, info.device))
    const hint = info.state === 'off' ? S.awayOffHint : ready ? S.awayReadyHint : S.awaySetUpHint
    const actions = [el('div', { className: 'facts' }, ...rows), el('p', { className: 'lead', textContent: hint })]
    if (info.state === 'off') actions.push(button(S.awayStart, () => bridge.awayChoice(false), { kind: 'secondary' }))
    else if (ready) {
      actions.push(button(S.awayStop, () => show({
        escape: () => fromAwayScreen(),
        className: 'warning',
        words: [el('h1', { textContent: S.awayStop }), el('p', { className: 'lead', textContent: S.awayStopConfirm })],
        actions: [button(S.cancel, () => fromAwayScreen(), { kind: 'primary' }), button(S.awayStop, () => bridge.awayChoice(true), { kind: 'destructive' })],
      }), { kind: 'destructive', className: 'wide' }))
    }
    show({ back, words: [el('h1', { textContent: S.rowAway }), el('p', { className: 'lead', textContent: S.awayHint })], actions })
  }

  function moveFocus(dir) {
    const cur = document.activeElement
    const all = Array.from(app.querySelectorAll('button:not(:disabled):not([hidden]), input')).filter((n) => n.offsetWidth > 0 || n.offsetHeight > 0)
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
  else if (self.wittyClient && params.get('away')) waitScreen(S.awayConnecting, () => { if (bridge.awayStop) bridge.awayStop() })
  else if (self.wittyClient && params.get('manage')) refreshManaged().then(() => listScreen())
  else if (bridge.awayInfo && params.get('from-away')) fromAwayScreen()
  else listScreen(params.get('certificate') ? S.errCertificate : params.get('lost') ? S.errLost : params.get('away-failed') ? S.errAwayFailed : '')
})()
