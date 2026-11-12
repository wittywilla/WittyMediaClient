// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.remote

import com.wittywilla.wittymediaclient.net.sseBackoffMs

// The life of this app as a device (docs/REMOTE-PROTOCOL.md, Being a device and Life of a device): announce, open
// the channel, and when the channel ends decide from why it ended what comes next. Nothing here touches a network
// or a clock: it is told what happened and when, and answers with the next step.

sealed interface LifeStep {
    // Announce (again), sending the id kept from before: an id the server has forgotten does no harm.
    data class Announce(val afterMs: Long) : LifeStep
    // Open the channel for the id already held.
    data class Open(val afterMs: Long) : LifeStep
    // Nothing more until something outside changes (a sign-in, the switch, the server's setting).
    data class Stop(val why: StopReason) : LifeStep
}

enum class StopReason { Replaced, Removed, SignedOut, Disabled, TooOld, TooMany }

class DeviceLife(private val reconnectSec: Int = 30) {
    var deviceId: String = ""
        private set
    var online: Boolean = false
        private set
    private var failures = 0
    private var offlineSinceMs: Long? = null

    fun start(): LifeStep = LifeStep.Announce(0)

    // The server's answer to an announcement: whatever id comes back is the one to use.
    fun announced(id: String): LifeStep {
        deviceId = id
        offlineSinceMs = null
        return LifeStep.Open(0)
    }

    // The channel's hello: controllers can see this device now.
    fun opened() {
        online = true
        failures = 0
        offlineSinceMs = null
    }

    // An announcement or a channel the server refused.
    fun refused(status: Int, code: String, retryAfterSec: Int = 0): LifeStep {
        online = false
        return when {
            code == "disabled" -> LifeStep.Stop(StopReason.Disabled)
            code == "version" -> LifeStep.Stop(StopReason.TooOld)
            code == "no-session" || status == 401 -> LifeStep.Stop(StopReason.SignedOut)
            // The server has forgotten this device, or it was never this sign-in's: announce for a new id.
            code == "no-device" || status == 404 -> LifeStep.Announce(0)
            // Sixteen devices for one account: wait a good while rather than knock every second.
            code == "too-many" -> LifeStep.Announce(maxOf(retryAfterSec * 1000L, TOO_MANY_WAIT_MS))
            status == 429 -> LifeStep.Announce(maxOf(retryAfterSec * 1000L, backoff()))
            else -> LifeStep.Announce(backoff())
        }
    }

    // The network failed before the server answered at all.
    fun lost(nowMs: Long): LifeStep = closed(null, nowMs)

    // The channel ended. `reason` is the server's `bye`, or null when it simply dropped.
    fun closed(reason: String?, nowMs: Long): LifeStep {
        val wasOnline = online
        online = false
        return when (reason) {
            // The same device opened another channel: the newer one is the one, and this one has nothing to do.
            "replaced" -> LifeStep.Stop(StopReason.Replaced)
            "removed" -> LifeStep.Stop(StopReason.Removed)
            "signed-out" -> LifeStep.Stop(StopReason.SignedOut)
            // No state reached the server for too long, and it has forgotten this device.
            "idle" -> { offlineSinceMs = null; LifeStep.Announce(0) }
            "server-stopping" -> { offlineSinceMs = null; LifeStep.Announce(SERVER_STOPPING_WAIT_MS) }
            else -> {
                // A drop: the server keeps the device for reconnectSec. Within that, the same channel again brings
                // it back as the same device; after it, announce.
                if (wasOnline || offlineSinceMs == null) offlineSinceMs = offlineSinceMs ?: nowMs
                val wait = backoff()
                val since = offlineSinceMs ?: nowMs
                if (deviceId.isNotEmpty() && nowMs + wait - since < reconnectSec * 1000L) LifeStep.Open(wait) else LifeStep.Announce(wait)
            }
        }
    }

    // Saying goodbye: the next start is a new announcement, with the old id for what it's worth.
    fun left() {
        online = false
        failures = 0
        offlineSinceMs = null
    }

    private fun backoff(): Long = sseBackoffMs(failures).also { failures++ }

    companion object {
        const val SERVER_STOPPING_WAIT_MS = 4000L
        const val TOO_MANY_WAIT_MS = 60_000L
    }
}

// When to report state (docs/REMOTE-PROTOCOL.md, Report state): on every change, every five seconds or so while
// playing, and at least every heartbeat whatever happens. Never closer together than the server allows; a report it
// refused for coming too soon goes again, as the latest state, a moment later.
class Heartbeat(private val stateEveryMs: Long = 500, heartbeatSec: Int = 30) {
    // A little early, so a slow request never lets the server think this device has gone.
    private val idleEveryMs = (minOf(heartbeatSec, 30) * 1000L - EARLY_MS).coerceAtLeast(MIN_IDLE_MS)
    private var lastSentMs: Long? = null
    private var notBeforeMs = 0L
    private var lastSent: String? = null

    // Whether to send `state` now. `playing` is whether a position is moving.
    fun due(nowMs: Long, state: String, playing: Boolean): Boolean {
        val last = lastSentMs ?: return nowMs >= notBeforeMs
        if (nowMs < notBeforeMs || nowMs - last < stateEveryMs) return false
        if (state != lastSent) return true
        return nowMs - last >= if (playing) PLAYING_EVERY_MS else idleEveryMs
    }

    fun sent(nowMs: Long, state: String) {
        lastSentMs = nowMs
        lastSent = state
    }

    // 429: the latest goes again after what Retry-After says, or a moment.
    fun refused(nowMs: Long, retryAfterSec: Int) {
        notBeforeMs = nowMs + maxOf(retryAfterSec * 1000L, stateEveryMs * 2)
        lastSent = null
    }

    // A new channel: the server may know nothing of this device's state.
    fun reset() {
        lastSentMs = null
        lastSent = null
        notBeforeMs = 0
    }

    companion object {
        const val PLAYING_EVERY_MS = 5000L
        private const val EARLY_MS = 5000L
        private const val MIN_IDLE_MS = 5000L
    }
}
