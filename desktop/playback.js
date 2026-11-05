// Whether the server's page should be kept running as if it were in front: while it plays, so a
// hidden, minimised or covered window never slows or stops what's playing. Plain rules, with nothing
// from Electron, so they can be tested without a window; main.js does what they decide.
//
// Kept awake: Chromium doesn't throttle the page, which then always counts as visible, and the system
// isn't allowed to suspend the app. That costs power, so it's only while something plays or sounds,
// and for a short while after, which covers the gap between one episode and the next. The website can
// say no: its "Keep playing when this tab is in the background", turned off, is <html data-background-play="off">.
// Then the page is told it's hidden like any browser tab, and pauses itself.

const GRACE_MS = 30 * 1000

function create({ apply, setTimer = setTimeout, clearTimer = clearTimeout, grace = GRACE_MS }) {
  let playing = false
  let audible = false
  let allowed = true
  let awake = false
  let timer = null

  const settle = (on) => {
    if (timer) clearTimer(timer)
    timer = null
    if (awake === on) return
    awake = on
    apply(on)
  }

  function update() {
    if (allowed && (playing || audible)) return settle(true)
    if (!awake) return settle(false)
    if (!allowed) return settle(false) // the website said no: at once, not after a while
    if (!timer) timer = setTimer(() => { timer = null; settle(false) }, grace)
  }

  return {
    playing(on) { playing = on === true; update() },
    audible(on) { audible = on === true; update() },
    // What the website says. Anything but a plain no keeps playing.
    allowed(on) { allowed = on !== false; update() },
    // A new page, or none: nothing it did before counts.
    reset() {
      playing = false
      audible = false
      allowed = true
      settle(false)
    },
    get awake() { return awake },
  }
}

module.exports = { create, GRACE_MS }
