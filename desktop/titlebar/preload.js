const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('wittyBar', {
  send: (action, at) => ipcRenderer.send('window', action, at),
  onServer: (fn) => ipcRenderer.on('server', (_e, url) => fn(url)),
  onMaximized: (fn) => ipcRenderer.on('maximized', (_e, on) => fn(on)),
  onTheme: (fn) => ipcRenderer.on('theme', (_e, t) => fn(t)),
  onFocus: (fn) => ipcRenderer.on('focus-bar', () => fn()),
})
