// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.MediaMarkers
import com.wittywilla.wittymediaclient.net.SkipRange

// What can be skipped in a video, and when to offer it: the website's rule (web/src/player/markers.ts) with the
// choices this app adds, apart from both players' screens so it can be tested without one. Every time here is the
// film's own, which is the player's time plus the stream's offset: a conversion that starts part-way through still
// has its intro where the film has it.

enum class SkipKind(val key: String, val label: String, val done: String, val setting: String) {
    Recap("recap", "Skip recap", "Skipped the recap", "Recaps"),
    Intro("intro", "Skip intro", "Skipped the intro", "Intros"),
    Commercial("commercials", "Skip adverts", "Skipped the adverts", "Adverts"),
    Credits("credits", "Skip credits", "Skipped the credits", "Credits"),
}

// One stretch that can be skipped. `source` is where the server found it (manual, skip.json, edl, chapters, detected,
// show), or "playback" for the intro an older server sends with the stream.
data class SkipSpan(val kind: SkipKind, val startSec: Double, val endSec: Double, val source: String = "")

// What to offer now: the stretch playing, and where its button goes.
data class Skip(val span: SkipSpan, val toSec: Double) {
    val label: String get() = span.kind.label
}

// Which kinds skip themselves, kept on this device (ExtrasPrefs).
data class AutoSkip(val intro: Boolean = false, val recap: Boolean = false, val credits: Boolean = false, val adverts: Boolean = false) {
    fun wants(kind: SkipKind): Boolean = when (kind) {
        SkipKind.Intro -> intro
        SkipKind.Recap -> recap
        SkipKind.Credits -> credits
        SkipKind.Commercial -> adverts
    }

    fun with(kind: SkipKind, on: Boolean): AutoSkip = when (kind) {
        SkipKind.Intro -> copy(intro = on)
        SkipKind.Recap -> copy(recap = on)
        SkipKind.Credits -> copy(credits = on)
        SkipKind.Commercial -> copy(adverts = on)
    }
}

object SkipRules {
    // Less than this left of a stretch isn't worth a button.
    const val TAIL_SEC = 1.0

    // Credits that stop this close to the end run to the end: what follows them is the next episode, not more film.
    const val END_SLACK_SEC = 5.0

    private fun usable(range: SkipRange?): Boolean =
        range != null && range.startSec.isFinite() && range.endSec.isFinite() && range.startSec >= 0 && range.endSec > range.startSec

    // Every stretch the server marked, of every kind and from every source. With no answer from /media/{id}/markers
    // (an older server, or the request failed) the intro that came with the item or the stream stands in, as before.
    fun spans(markers: MediaMarkers?, fallbackIntro: SkipRange?): List<SkipSpan> {
        if (markers == null) {
            return if (usable(fallbackIntro)) listOf(SkipSpan(SkipKind.Intro, fallbackIntro!!.startSec, fallbackIntro.endSec, "playback")) else emptyList()
        }
        fun one(kind: SkipKind, range: SkipRange?) =
            if (usable(range)) SkipSpan(kind, range!!.startSec, range.endSec, markers.sources[kind.key].orEmpty().ifEmpty { markers.source }) else null
        return listOfNotNull(one(SkipKind.Recap, markers.recap), one(SkipKind.Intro, markers.intro)) +
            markers.commercials.mapNotNull { one(SkipKind.Commercial, it) }.sortedBy { it.startSec } +
            listOfNotNull(one(SkipKind.Credits, markers.credits))
    }

    private fun inside(span: SkipSpan, nowSec: Double) = nowSec >= span.startSec && nowSec < span.endSec - TAIL_SEC

    // Do these credits run to the end of the video? Unknown lengths count as yes: there's nothing known to skip to.
    fun runsToEnd(span: SkipSpan, durationSec: Double): Boolean = durationSec <= 0 || span.endSec >= durationSec - END_SLACK_SEC

    // The stretch playing at `nowSec`, if skipping it is worth a button: more than a second of it is left, and for
    // credits there is something after them. Credits that run to the end are what "next episode" is for (upNextFrom).
    // A recap comes before an intro when the two overlap, as on the website.
    fun skipAt(spans: List<SkipSpan>, nowSec: Double, durationSec: Double): Skip? {
        if (!nowSec.isFinite()) return null
        for (kind in listOf(SkipKind.Recap, SkipKind.Intro, SkipKind.Commercial, SkipKind.Credits)) {
            val span = spans.firstOrNull { it.kind == kind && inside(it, nowSec) } ?: continue
            if (kind == SkipKind.Credits && runsToEnd(span, durationSec)) continue
            return Skip(span, target(span, durationSec))
        }
        return null
    }

    // Where the button goes: the end of the stretch, never past the end of the video.
    fun target(span: SkipSpan, durationSec: Double): Double =
        if (durationSec > 0) span.endSec.coerceAtMost(durationSec) else span.endSec

    // When "next episode" should come up: from where the credits start, when they run to the end and that is earlier
    // than the usual 30 seconds before it. Null leaves the usual rule alone.
    fun upNextFrom(spans: List<SkipSpan>, durationSec: Double): Double? {
        if (durationSec <= 0) return null
        val credits = spans.lastOrNull { it.kind == SkipKind.Credits && runsToEnd(it, durationSec) } ?: return null
        // Credits "starting" in the first half are a mistake in the marking, not an ending.
        if (credits.startSec < durationSec / 2) return null
        return credits.startSec.takeIf { it < durationSec - WATCH_NEXT_BEFORE_END_SEC }
    }

    // The credits that run to the end, while they're on: with auto-skip for credits, the next episode starts here.
    fun endCreditsAt(spans: List<SkipSpan>, nowSec: Double, durationSec: Double): SkipSpan? {
        if (durationSec <= 0) return null
        return spans.lastOrNull { it.kind == SkipKind.Credits && runsToEnd(it, durationSec) && it.startSec >= durationSec / 2 && nowSec >= it.startSec && nowSec < durationSec - TAIL_SEC }
    }
}

// Skipping by itself, once for each stretch: someone who goes back into an intro they were taken past wants to watch
// it, and isn't taken past it again.
class AutoSkipper {
    private val done = HashSet<SkipSpan>()

    // Should this stretch skip itself now? Asking doesn't count as doing it: `did` says it happened.
    fun due(span: SkipSpan?, choices: AutoSkip): Boolean = span != null && choices.wants(span.kind) && span !in done

    fun did(span: SkipSpan) {
        done += span
    }

    // A person pressed the button themselves: the same stretch needn't skip itself later either.
    fun pressed(span: SkipSpan) {
        done += span
    }
}
