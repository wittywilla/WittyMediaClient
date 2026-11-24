// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable

// Time-shift for everyone (server #648), as web/src/pages/tv/timeshift.ts has it: a library channel's programme
// started over for this viewer only, its breaks skipped, and rewinding further back than the stream keeps.
// Times are the schedule's, in Unix seconds; the stream's program date-times say where the picture is in it.

@Serializable
data class Span(val start: Long = 0, val end: Long = 0)

// What GET /tv/{key}/startover and /timeline say about the programme a start-over stream is in.
@Serializable
data class Timeline(
    val programme: GuideProgramme = GuideProgramme(),
    val breaks: List<Span> = emptyList(),
    val from: Long? = null,
    val live: Long = 0,
    val earliest: Long = 0,
)

object TimeShiftRules {
    // A start over closer to live than this is live: the player goes back to the shared stream.
    const val LIVE_EDGE_SEC = 20

    sealed interface Seek {
        data object Live : Seek
        data class Within(val to: Double) : Seek
        data class Restart(val at: Long) : Seek
    }

    fun isLibrary(key: String) = key.startsWith("lib-")

    // The break the picture is in at moment t, if any.
    fun breakAt(breaks: List<Span>?, t: Double?): Span? {
        if (t == null || breaks == null) return null
        return breaks.firstOrNull { it.start <= t && t < it.end }
    }

    // A seek to schedule moment target, with the picture at media time cur (schedule moment sched) and media times
    // winStart..winEnd loaded: within them it's a seek; further back, the viewer's stream starts again from there;
    // at live, back to the channel everyone shares.
    fun plan(target: Double, sched: Double, cur: Double, winStart: Double, winEnd: Double, live: Double, earliest: Double = Double.NEGATIVE_INFINITY): Seek {
        if (target >= live - LIVE_EDGE_SEC) return Seek.Live
        val at = maxOf(earliest, target)
        val to = cur + (at - sched)
        if (to >= winStart - 0.5 && to <= winEnd) return Seek.Within(maxOf(winStart, to))
        return Seek.Restart(kotlin.math.floor(at).toLong())
    }

    // After a pause longer than the stream keeps (less a margin), start again from where it paused.
    fun restartAfterPause(pausedMs: Long, nowMs: Long, bufferSec: Double): Boolean {
        val keep = maxOf(30.0, bufferSec - 30)
        return (nowMs - pausedMs) / 1000.0 > keep
    }

    // Whether Start over is worth offering: a programme that began more than a moment ago.
    fun canStartOver(tuned: Tuned?, now: Long): Boolean {
        if (tuned == null) return false
        val p = tuned.now ?: return false
        if (tuned.startOver != true || p.kind == "slate" || p.end <= p.start) return false
        return now - p.start > LIVE_EDGE_SEC
    }

    // With a short-lived pass in the stream's address, as tune has it.
    fun path(key: String, from: Long?, viewer: String): String =
        "/tv/${GuideRules.pathPart(key)}/startover?viewer=${GuideRules.pathPart(viewer)}&streamToken=1" + (from?.let { "&from=$it" } ?: "")

    fun leavePath(key: String, viewer: String, shift: Boolean): String =
        "/tv/${GuideRules.pathPart(key)}/leave?viewer=${GuideRules.pathPart(viewer)}" + if (shift) "&shift=1" else ""
}
