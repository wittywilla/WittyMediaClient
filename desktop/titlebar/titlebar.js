const win = window.wittyBar
const change = document.getElementById('change')
const help = document.getElementById('help')
const maximize = document.getElementById('maximize')

for (const action of ['minimize', 'maximize', 'close']) {
  document.getElementById(action).addEventListener('click', () => win.send(action))
}
change.addEventListener('click', () => win.send('change-server'))
// Under the button, so it opens in the same place from the keyboard as from the mouse.
help.addEventListener('click', () => {
  const box = help.getBoundingClientRect()
  win.send('help', { x: Math.round(box.left), y: Math.round(box.bottom) })
})
document.body.addEventListener('dblclick', (e) => { if (e.target === document.body || e.target.id === 'title') win.send('maximize') })

// Left and right move along the bar, and Escape goes back to the page.
const buttons = () => Array.from(document.querySelectorAll('button:not([hidden])'))
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    e.preventDefault()
    win.send('focus-page')
    return
  }
  if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight' && e.key !== 'Home' && e.key !== 'End') return
  e.preventDefault()
  const all = buttons()
  const at = all.indexOf(document.activeElement)
  if (e.key === 'Home') all[0].focus()
  else if (e.key === 'End') all[all.length - 1].focus()
  else all[(at + (e.key === 'ArrowLeft' ? -1 : 1) + all.length) % all.length].focus()
})
win.onFocus(() => help.focus())

win.onServer((url) => {
  // A button about to vanish can't keep the focus: it goes back to the start of the bar.
  if (!url && document.activeElement === change) help.focus()
  change.hidden = !url
})
win.onMaximized((on) => {
  maximize.classList.toggle('is-maximized', on)
  maximize.setAttribute('aria-label', on ? 'Restore' : 'Maximize')
  maximize.title = on ? 'Restore' : 'Maximize'
})
win.onTheme((t) => {
  const root = document.documentElement.style
  root.setProperty('--bg', t.bg)
  root.setProperty('--fg', t.fg)
  root.setProperty('--border', t.border)
})
