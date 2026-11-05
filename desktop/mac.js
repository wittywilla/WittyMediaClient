// What is different on a Mac: the system draws the window's buttons and has the menu bar.
// Plain rules, with nothing from Electron, so they can be tested without a window.

// How tall the red, yellow and green buttons are, in points, which is what centres them. On
// macOS 27 the system's own title bar is as tall as the app's, and it puts them 9 points in.
const WINDOW_BUTTONS = 14
// How long the system takes to start answering a double-click on the title bar itself.
const SETTLE_MS = 250

// Where the window's buttons go: at the left, in the middle of the app's own title bar.
const windowButtonsAt = (barHeight) => ({ x: 9, y: Math.round((barHeight - WINDOW_BUTTONS) / 2) })

// The buttons hide with the title bar when a video takes over the window. In the system's
// full screen they stay, as the system shows them itself when the pointer reaches the top.
const windowButtonsShown = (barShown, fullScreen) => barShown || fullScreen

// What a double-click on the title bar is set to do, in System Settings > Desktop & Dock.
// Not set is the system's default, Zoom. Fill takes the screen, which zooming does here too.
// The system answers a double-click on the bar itself, and the page never sees it, so this
// is for one that reaches the page anyway.
function doubleClickAction(setting) {
  if (setting === 'Minimize') return 'minimize'
  if (setting === 'None') return 'none'
  return 'zoom'
}

// Whether the window moved, changed size or was minimised between two looks at it.
function windowChanged(before, after) {
  const a = before.bounds
  const b = after.bounds
  return before.minimized !== after.minimized || a.x !== b.x || a.y !== b.y || a.width !== b.width || a.height !== b.height
}

// The menu bar. Electron's roles give the system's own names, keys and items, and the
// Edit menu is what makes copy, paste and select all work at all. Zooming is for the page,
// whichever part of the window has the focus, as zooming the title bar would break it.
function menu({ connected, changeServer, zoom, openLogs, copyDiagnostics }) {
  return [
    { role: 'appMenu' },
    { role: 'editMenu' },
    {
      label: 'View',
      submenu: [
        { label: 'Actual Size', accelerator: 'Command+0', click: () => zoom(0) },
        { label: 'Zoom In', accelerator: 'Command+Plus', click: () => zoom(1) },
        // The same without Shift, as in every other Mac app.
        { label: 'Zoom In', accelerator: 'Command+=', visible: false, click: () => zoom(1) },
        { label: 'Zoom Out', accelerator: 'Command+-', click: () => zoom(-1) },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    { label: 'Server', submenu: [{ id: 'change-server', label: 'Change server', enabled: connected, click: changeServer }] },
    { role: 'windowMenu' },
    { role: 'help', submenu: [{ label: 'Open logs folder', click: openLogs }, { label: 'Copy diagnostic info', click: copyDiagnostics }] },
  ]
}

module.exports = { WINDOW_BUTTONS, SETTLE_MS, windowButtonsAt, windowButtonsShown, doubleClickAction, windowChanged, menu }
