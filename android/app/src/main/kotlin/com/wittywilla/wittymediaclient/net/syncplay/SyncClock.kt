// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.syncplay

// The server's clock, as a watch party needs it: to a few tens of milliseconds. The same sums as the server's
// internal/syncplay/clock.go (ClockOffset, BestOffset), which the tests check against its own cases.

data class ClockSample(val t0: Double, val t1: Double, val t2: Double, val t3: Double)

data class ClockReading(val offsetMs: Double, val rttMs: Double)

// NTP's sum for one ping. t0: this device's clock when it sent; t1: the server's when that arrived; t2: the
// server's when it answered; t3: this device's when the answer arrived. offset is how far the server's clock is
// ahead, rtt the time on the wire there and back.
fun clockOffset(t0: Double, t1: Double, t2: Double, t3: Double): ClockReading =
    ClockReading(((t1 - t0) + (t2 - t3)) / 2, (t3 - t0) - (t2 - t1))

// From several pings, the one with the shortest round trip: it was held up least, so its two halves are most
// nearly equal, which is what the sum assumes. A ping that came back before it left (a clock jumped) is ignored.
fun bestOffset(samples: List<ClockSample>): ClockReading? {
    var best: ClockReading? = null
    for (s in samples) {
        val r = clockOffset(s.t0, s.t1, s.t2, s.t3)
        if (r.rttMs < 0 || r.rttMs.isNaN() || r.offsetMs.isNaN()) continue
        if (best == null || r.rttMs < best.rttMs) best = r
    }
    return best
}

// The last few pings, and the best of them. Times are from a clock that never jumps (the time since the device
// started), never the wall clock: a person changing the time must not move the film.
class ClockKeeper(private val keep: Int = 8) {
    private val samples = ArrayDeque<ClockSample>()
    private var pings = 0

    val best: ClockReading? get() = bestOffset(samples)
    val known: Boolean get() = best != null

    fun add(sample: ClockSample) {
        pings++
        // One that makes no sense is never kept, so it can't push a good one out.
        val r = clockOffset(sample.t0, sample.t1, sample.t2, sample.t3)
        if (r.rttMs < 0 || r.rttMs.isNaN() || r.offsetMs.isNaN()) return
        samples.addLast(sample)
        while (samples.size > keep) samples.removeFirst()
    }

    fun serverNow(localMs: Double): Double = localMs + (best?.offsetMs ?: 0.0)

    // What to send as rttMs with each ping: the best so far, 0 before any.
    val rttMs: Double get() = best?.rttMs ?: 0.0

    // How long until the next ping: a handful a few hundred milliseconds apart on joining, then the server's pace.
    fun nextPingMs(pingEverySec: Int): Long = if (pings < JOIN_PINGS) JOIN_GAP_MS else pingEverySec.coerceAtLeast(1) * 1000L

    // After a reconnect: measure afresh, quickly, but keep using what is known until then.
    fun again() {
        pings = 0
    }

    companion object {
        const val JOIN_PINGS = 5
        const val JOIN_GAP_MS = 300L
    }
}
