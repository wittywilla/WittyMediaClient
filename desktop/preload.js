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
    open: (server) => ipcRenderer.invoke('open-server', server),
    redeem: (url, code) => ipcRenderer.invoke('redeem', url, code),
    openLogs: () => ipcRenderer.send('open-logs'),
    ...(TV ? { topBack: () => ipcRenderer.send('tv-back', false) } : {}),
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
  // The web UI swaps a stylesheet in <head> and sets data-theme when the theme changes.
  window.addEventListener('DOMContentLoaded', () => {
    report()
    let timer = null
    const later = () => { clearTimeout(timer); timer = setTimeout(report, 150) }
    new MutationObserver(later).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    new MutationObserver(later).observe(document.head, { childList: true })
    // A new stylesheet only applies once loaded, which is after it was added.
    document.head.addEventListener('load', later, true)
  })
}
