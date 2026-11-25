// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
// The steps of connecting from away and why one can fail, in the server's words (its pkg/connectsteps/steps.json,
// kept as shared/data/connect-steps.json): the same codes as the server's Recent tries, and the same sentences on
// every app. Loaded by the desktop app's main process and by Node's tests; the page only shows what it is given.
(function (root) {
  const ORDER = ['read', 'found', 'secure', 'signin']

  function create(file) {
    const codes = (file && file.codes) || []
    const steps = (file && file.steps) || []
    const unknown = codes.find((c) => c.code === 'unknown') || { code: 'unknown', step: '', say: 'Something went wrong.', next: '' }
    // The hint while connecting takes a while, and after how many seconds (steps.json's "slow").
    const slow = { after: Number(file && file.slow && file.slow.after) || 10, say: String((file && file.slow && file.slow.say) || '') }

    // The failure behind a server's reason ("expired") and an error's words: a reason first, then the words; with
    // neither known, "unknown" at `step`, the step being tried.
    function classify(reason, text, step, clean) {
      const r = String(reason || '').trim()
      const words = String(text || '')
      const lower = words.toLowerCase()
      const pick = (c) => ({ step: c.step || step || '', code: c.code, say: c.say, next: c.next, error: (clean ? clean(words) : words).slice(0, 400) })
      if (r) {
        const c = codes.find((x) => (x.reasons || []).includes(r))
        if (c) return pick(c)
      }
      if (lower) {
        const c = codes.find((x) => (x.match || []).some((m) => lower.includes(m)))
        if (c) return pick(c)
      }
      return pick(unknown)
    }

    // One go at connecting: the steps that got through, the one that failed, and what the app saw.
    function run(kind, server) {
      const started = Date.now()
      const passed = []
      const log = []
      let failure = null
      let name = ''
      const elapsed = () => `+${((Date.now() - started) / 1000).toFixed(1)}s`
      const r = {
        kind,
        note(line) { if (log.length < 60) log.push(`${elapsed()} ${String(line).slice(0, 300)}`) },
        pass(step) { if (!passed.includes(step)) passed.push(step); r.note(`ok: ${step}`) },
        // Shown on the step being tried: words that belong to an earlier step that got through move on to the next.
        fail(f) {
          const last = Math.max(-1, ...passed.map((s) => ORDER.indexOf(s)))
          const at = ORDER.indexOf(f.step)
          failure = (at < 0 || at < last) ? { ...f, step: ORDER[Math.min(last + 1, ORDER.length - 1)] } : f
          r.note(`failed: ${failure.step} (${failure.code})${failure.error ? ': ' + failure.error : ''}`)
          return failure
        },
        get failure() { return failure },
        // The server's name, once the invite or the server says it.
        named(n) { if (n) name = String(n).slice(0, 80) },
        get name() { return name },
        // While connecting, for the connecting screen: each step done, being tried now, still to come, or failed;
        // what the step being tried is doing; how long it has taken; and the slow hint once it has taken a while.
        progress(now = Date.now()) {
          const at = failure ? -1 : steps.findIndex((s) => !passed.includes(s.id))
          const list = r.states().map((s, i) => ({ ...s, state: s.state !== 'skip' || failure ? s.state : i === at ? 'now' : 'wait' }))
          const step = at >= 0 ? steps[at] : null
          const ms = Math.max(0, now - started)
          return {
            kind, name, steps: list, step: step ? step.id : '', doing: step ? (step.doing || step.title) : '',
            ms, clock: clock(ms), slow: !failure && slow.say && ms >= slow.after * 1000 ? slow.say : '', failure,
          }
        },
        states() {
          const at = steps.findIndex((s) => failure && s.id === failure.step)
          return steps.map((s, i) => ({
            id: s.id, title: s.title,
            state: at >= 0 && i === at ? 'fail' : at >= 0 && i > at ? 'skip' : (passed.includes(s.id) || at > i) ? 'ok' : 'skip',
          }))
        },
        // Copy details: plain text to paste to whoever runs the server, passed through `clean` (no keys or tokens).
        details(app, device, clean) {
          const c = clean || ((x) => x)
          const lines = [
            'WittyMediaClient connection check',
            `When: ${new Date(started).toISOString().replace('T', ' ').slice(0, 19)} UTC`,
            `App: ${app}`,
            `Device: ${device}`,
            `Joining: ${kind}${server ? ` (server …${String(server).slice(-8)})` : ''}`,
            ...r.states().map((s) => `[${s.state === 'ok' ? 'x' : s.state === 'fail' ? '!' : ' '}] ${s.title}`),
          ]
          if (failure) {
            lines.push(`Failed: ${failure.step}, ${failure.code}`, failure.say, `Next: ${failure.next}`)
            if (failure.error) lines.push(`Error: ${failure.error}`)
          }
          lines.push('Log:', ...log.map((l) => `  ${l}`))
          return c(lines.join('\n'))
        },
        // What the connect screen is given to show.
        view(app, device, clean) {
          return { kind, steps: r.states(), failure, details: r.details(app, device, clean) }
        },
      }
      return r
    }

    return { steps, codes, slow, classify, of: (code, step) => classify(code, '', step), run, ORDER }
  }

  // How long connecting has taken, as a clock: 0:07, 1:02.
  function clock(ms) {
    const s = Math.floor(Math.max(0, ms) / 1000)
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
  }

  const api = { create, ORDER, clock }
  if (typeof module !== 'undefined' && module.exports) module.exports = api
  else root.WittySteps = api
})(typeof self !== 'undefined' ? self : this)
