// SPDX-License-Identifier: GPL-3.0-or-later
//
// WittyMediaClient - Apps that connect to a WittyMediaServer, for TV boxes, phones, tablets and desktops.
// Copyright (C) 2026 WittyWilla and contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// Runs before every page in the main view, in its own isolated world. The
// connect screen, on the app's own scheme, gets a small bridge. A server's page gets
// very little: it can report its colours, so the title bar matches, and ask for
// Moonlight, which the main process checks strictly (see moonlight.js).
const { contextBridge, ipcRenderer } = require('electron')

const TV = process.argv.includes('--wittymedia-tv')
// What has its own idea of Back in the server's page, so it isn't this app's to answer. The page says
// in <html data-own-back>. A server older than that gets this list, as it was when it stopped changing.
const OLDER_OWN_BACK = '[role=dialog], [role=alertdialog], [role=menu], .modal, .picker-backdrop, .view-settings, .audio-bar.full, .reader, .player:not(.mini):not(.inline)'

function pageHasOwnBack() {
  try {
    return !!document.querySelector(document.documentElement.dataset.ownBack || OLDER_OWN_BACK)
  } catch {
    return false // the page's own selector, and not one a browser can read
  }
}

// A TV's Back arrives as Escape from Plasma Bigscreen and HDMI-CEC remotes, and as BrowserBack
// from others. The server's page goes back a page on BrowserBack, and on Escape only closes what
// is open. So Escape that nothing used goes back here, and the top of the app opens the menu.
function listenForBack() {
  window.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.altKey || e.metaKey) return
    if (e.key !== 'Escape' && e.key !== 'BrowserBack' && e.key !== 'GoBack') return
    if (document.fullscreenElement || pageHasOwnBack()) return
    if (e.key !== 'Escape') { ipcRenderer.send('tv-back', false); return }
    if (!e.isTrusted) return // a controller's B: the page follows it with GoBack
    // Listeners on the page come after this one, so look once they've all had their turn.
    setTimeout(() => { if (!e.defaultPrevented && !e.cancelBubble) ipcRenderer.send('tv-back', true) }, 0)
  }, true)
}

if (location.protocol === 'wittymedia-app:') {
  contextBridge.exposeInMainWorld('wittyClient', {
    supportsDiscovery: true,
    startDiscovery: (onServers) => {
      ipcRenderer.removeAllListeners('servers')
      ipcRenderer.on('servers', (_e, servers) => onServers(servers))
      ipcRenderer.send('discover-start')
    },
    probe: (url) => ipcRenderer.invoke('probe', url),
    recent: () => ipcRenderer.invoke('recent'),
    // Removing remembered servers: by address, with a few seconds in which it can be taken back.
    forget: (urls) => ipcRenderer.invoke('forget', urls),
    forgetUndo: () => ipcRenderer.invoke('forget-undo'),
    forgetFinish: () => ipcRenderer.invoke('forget-finish'),
    serverMenu: (url, at) => ipcRenderer.send('server-menu', url, at),
    // Opened from the menu while a server is in use (Manage servers): which one, and back to it.
    managing: () => ipcRenderer.invoke('managing'),
    manageBack: () => ipcRenderer.send('manage-back'),
    onForgetAsk: (ask) => {
      ipcRenderer.removeAllListeners('forget-ask')
      ipcRenderer.on('forget-ask', (_e, url) => ask(url))
    },
    open: (server) => ipcRenderer.invoke('open-server', server),
    redeem: (url, code) => ipcRenderer.invoke('redeem', url, code),
    // Enter a code: one from a server's Connect a device, asked of the servers this app can reach (code.js).
    enterCode: (code, only) => ipcRenderer.invoke('enter-code', code, only),
    enterCodeStop: () => ipcRenderer.send('enter-code-stop'),
    // A code shown here for a phone to approve. The secret that collects the sign-in stays in the app.
    pairStart: (url) => ipcRenderer.invoke('pair-start', url),
    pairPoll: () => ipcRenderer.invoke('pair-poll'),
    pairPin: () => ipcRenderer.invoke('pair-pin'),
    pairStop: () => ipcRenderer.send('pair-stop'),
    // An invite link to a server away from home, and giving up on reaching one.
    invite: (link) => ipcRenderer.invoke('p2p-invite', link),
    awayStop: () => ipcRenderer.send('p2p-stop'),
    // The From away screen.
    awayInfo: () => ipcRenderer.invoke('away-info'),
    awayChoice: (stop) => ipcRenderer.send('away-choice', stop === true),
    openLogs: () => ipcRenderer.send('open-logs'),
    ...(TV ? { tv: true, topBack: () => ipcRenderer.send('tv-back', false) } : {}),
  })
} else {
  if (TV) listenForBack()
  contextBridge.exposeInMainWorld('wittyClient', {
    moonlight: {
      status: () => ipcRenderer.invoke('moonlight-status'),
      launch: (args) => ipcRenderer.invoke('moonlight-launch', args),
    },
  })
  const report = () => {
    const css = getComputedStyle(document.documentElement)
    ipcRenderer.send('theme', {
      bg: css.getPropertyValue('--bg-2').trim(),
      fg: css.getPropertyValue('--fg').trim(),
      border: css.getPropertyValue('--border').trim(),
    })
  }
  // "Keep playing when this tab is in the background": the website marks it turned off as
  // <html data-background-play="off">. Missing, as on older servers, it's on.
  let backgroundPlay = null
  const reportBackgroundPlay = () => {
    const on = document.documentElement.dataset.backgroundPlay !== 'off'
    if (on !== backgroundPlay) ipcRenderer.send('background-play', backgroundPlay = on)
  }
  // The web UI swaps a stylesheet in <head> and sets data-theme when the theme changes.
  window.addEventListener('DOMContentLoaded', () => {
    report()
    reportBackgroundPlay()
    new MutationObserver(reportBackgroundPlay).observe(document.documentElement, { attributes: true, attributeFilter: ['data-background-play'] })
    let timer = null
    const later = () => { clearTimeout(timer); timer = setTimeout(report, 150) }
    new MutationObserver(later).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    new MutationObserver(later).observe(document.head, { childList: true })
    // A new stylesheet only applies once loaded, which is after it was added.
    document.head.addEventListener('load', later, true)
  })
}
