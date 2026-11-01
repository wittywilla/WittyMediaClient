// Works with arrows, OK and Back alone. Up and down go round the list, and Back closes it.
(function () {
  const close = () => window.wittyBar.menu('close')

  document.getElementById('stay').addEventListener('click', close)
  document.getElementById('change').addEventListener('click', () => window.wittyBar.menu('change-server'))
  document.getElementById('quit').addEventListener('click', () => window.wittyBar.menu('quit'))

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || e.key === 'BrowserBack' || e.key === 'GoBack') {
      e.preventDefault()
      close()
      return
    }
    if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return
    e.preventDefault()
    const list = Array.from(document.querySelectorAll('button')).filter((b) => !b.hidden)
    const here = list.indexOf(document.activeElement)
    const step = e.key === 'ArrowDown' ? 1 : -1
    list[(here + step + list.length) % list.length].focus()
  })

  window.wittyBar.onMenu(({ hasServer }) => {
    document.getElementById('change').hidden = !hasServer
    document.getElementById('stay').focus()
  })
  window.wittyBar.onTheme((t) => {
    const root = document.documentElement.style
    root.setProperty('--bg', t.bg)
    root.setProperty('--fg', t.fg)
    if (t.border !== 'transparent') root.setProperty('--border', t.border)
  })
})()
