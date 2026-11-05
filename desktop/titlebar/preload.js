const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('wittyBar', {
  mac: process.platform === 'darwin',
  send: (action, at) => ipcRenderer.send('window', action, at),
  menu: (action) => ipcRenderer.send('tv-menu', action),
  onMenu: (fn) => ipcRenderer.on('tv-menu-open', (_e, details) => fn(details)),
  onServer: (fn) => ipcRenderer.on('server', (_e, url) => fn(url)),
  onMaximized: (fn) => ipcRenderer.on('maximized', (_e, on) => fn(on)),
  onTheme: (fn) => ipcRenderer.on('theme', (_e, t) => fn(t)),
  onFocus: (fn) => ipcRenderer.on('focus-bar', () => fn()),
  onActive: (fn) => ipcRenderer.on('active', (_e, on) => fn(on)),
})
