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
    // A part someone named in a .wittyinfo ("dream sequence"): its button says "Skip" and the name.
    Custom("custom", "Skip this part", "Skipped a part", "Other parts someone named"),
    Preview("preview", "Skip preview", "Skipped the preview", "Previews"),
    Credits("credits", "Skip credits", "Skipped the credits", "Credits"),
    ;

    companion object {
        // The server's word for a kind in `segments`. A scene after the credits (postcredits) and anything unknown
        // have no button.
        fun of(kind: String): SkipKind? = when (kind) {
            "recap" -> Recap
            "intro" -> Intro
            "commercial", "commercials" -> Commercial
            "custom" -> Custom
            "preview" -> Preview
            "credits" -> Credits
            else -> null
        }

        // Which wins when two overlap: the first in this list, as the website's markers.ts orders them.
        val ORDER = listOf(Recap, Intro, Commercial, Custom, Preview, Credits)
    }
}

// One stretch that can be skipped. `source` is where the server found it (wittyinfo, manual, skip.json, edl, chapters,
// detected, show), or "playback" for the intro an older server sends with the stream. `name` is what someone called a
// custom part; `fileAuto` that the video's .wittyinfo says to skip it by itself; `toScene` that these credits stop
// where a scene after them starts, so they never count as running to the end.
data class SkipSpan(
    val kind: SkipKind,
    val startSec: Double,
    val endSec: Double,
    val source: String = "",
    val name: String = "",
    val fileAuto: Boolean = false,
    val toScene: Boolean = false,
)

// What to offer now: the stretch playing, and where its button goes.
data class Skip(val span: SkipSpan, val toSec: Double) {
    val label: String get() = SkipRules.labelOf(span)
}

// Which kinds skip themselves, kept on this device (ExtrasPrefs). `fileAuto`: also what a video's .wittyinfo says to
// skip by itself, on unless turned off, as the website's autoSkip.fileAuto.
data class AutoSkip(
    val intro: Boolean = false,
    val recap: Boolean = false,
    val credits: Boolean = false,
    val adverts: Boolean = false,
    val preview: Boolean = false,
    val custom: Boolean = false,
    val fileAuto: Boolean = true,
) {
    fun wants(kind: SkipKind): Boolean = when (kind) {
        SkipKind.Intro -> intro
        SkipKind.Recap -> recap
        SkipKind.Credits -> credits
        SkipKind.Commercial -> adverts
        SkipKind.Preview -> preview
        SkipKind.Custom -> custom
    }

    // This stretch: its kind was asked for, or its file says to skip it and this device follows the file.
    fun wants(span: SkipSpan): Boolean = wants(span.kind) || (span.fileAuto && fileAuto)

    fun with(kind: SkipKind, on: Boolean): AutoSkip = when (kind) {
        SkipKind.Intro -> copy(intro = on)
        SkipKind.Recap -> copy(recap = on)
        SkipKind.Credits -> copy(credits = on)
        SkipKind.Commercial -> copy(adverts = on)
        SkipKind.Preview -> copy(preview = on)
        SkipKind.Custom -> copy(custom = on)
    }
}

object SkipRules {
    // Less than this left of a stretch isn't worth a button.
    const val TAIL_SEC = 1.0

    // Credits that stop this close to the end run to the end: what follows them is the next episode, not more film.
    const val END_SLACK_SEC = 5.0

    // A named part's name is cut here on its button, as the website does.
    private const val NAME_MAX = 40

    private fun usable(range: SkipRange?): Boolean = range != null && usable(range.startSec, range.endSec)

    private fun usable(start: Double, end: Double) = start.isFinite() && end.isFinite() && start >= 0 && end > start

    // "Skip intro", or for a part someone named "Skip dream sequence", as the website's customLabel.
    fun labelOf(span: SkipSpan): String {
        val name = span.name.trim()
        if (span.kind != SkipKind.Custom || name.isEmpty()) return span.kind.label
        val short = if (name.length > NAME_MAX) name.take(NAME_MAX - 1) + "…" else name
        return "Skip " + short.replaceFirstChar { it.lowercaseChar() }
    }

    // What's said once a stretch skipped itself: "Skipped the intro", "Skipped dream sequence".
    fun doneOf(span: SkipSpan): String {
        val name = span.name.trim()
        return if (span.kind == SkipKind.Custom && name.isNotEmpty()) "Skipped " + name.replaceFirstChar { it.lowercaseChar() } else span.kind.done
    }

    // Where a scene after the credits starts, when there is one inside these credits or just after them.
    private fun sceneAfter(markers: MediaMarkers, creditsStart: Double, creditsEnd: Double): Double? {
        val scene = markers.postCredits?.takeIf { usable(it) }?.startSec
            ?: markers.segments.firstOrNull { it.kind == "postcredits" && usable(it.startSec, it.endSec) }?.startSec
            ?: return null
        return scene.takeIf { it > creditsStart && it <= creditsEnd + END_SLACK_SEC }
    }

    // Every stretch the server marked that can have a button, of every kind and from every source. With no answer from
    // /media/{id}/markers (an older server, or the request failed) the intro that came with the item or the stream
    // stands in, as before. A part that is only marked ("mark") and a scene after the credits never have a button, and
    // credits with such a scene after them stop where it starts, so skipping them doesn't skip it.
    fun spans(markers: MediaMarkers?, fallbackIntro: SkipRange?): List<SkipSpan> {
        if (markers == null) {
            return if (usable(fallbackIntro)) listOf(SkipSpan(SkipKind.Intro, fallbackIntro!!.startSec, fallbackIntro.endSec, "playback")) else emptyList()
        }
        fun span(kind: SkipKind, start: Double, end: Double, source: String, label: String, action: String): SkipSpan? {
            if (action == "mark" || !usable(start, end)) return null
            val scene = if (kind == SkipKind.Credits) sceneAfter(markers, start, end) else null
            val name = if (kind == SkipKind.Custom) label.trim() else ""
            return SkipSpan(kind, start, if (scene != null) minOf(scene, end) else end, source, name, action == "auto", scene != null)
        }
        if (markers.segments.isNotEmpty()) {
            return markers.segments.mapNotNull { seg ->
                SkipKind.of(seg.kind)?.let { span(it, seg.startSec, seg.endSec, seg.source, seg.label, seg.action) }
            }.sortedWith(compareBy({ SkipKind.ORDER.indexOf(it.kind) }, { it.startSec }))
        }
        fun one(kind: SkipKind, range: SkipRange?): SkipSpan? =
            range?.let { span(kind, it.startSec, it.endSec, markers.sources[kind.key].orEmpty().ifEmpty { markers.source }, it.label, it.action) }
        return listOfNotNull(one(SkipKind.Recap, markers.recap), one(SkipKind.Intro, markers.intro)) +
            markers.commercials.mapNotNull { one(SkipKind.Commercial, it) }.sortedBy { it.startSec } +
            markers.custom.mapNotNull { one(SkipKind.Custom, it) }.sortedBy { it.startSec } +
            listOfNotNull(one(SkipKind.Preview, markers.preview), one(SkipKind.Credits, markers.credits))
    }

    private fun inside(span: SkipSpan, nowSec: Double) = nowSec >= span.startSec && nowSec < span.endSec - TAIL_SEC

    // Do these credits run to the end of the video? Unknown lengths count as yes: there's nothing known to skip to.
    fun runsToEnd(span: SkipSpan, durationSec: Double): Boolean = !span.toScene && (durationSec <= 0 || span.endSec >= durationSec - END_SLACK_SEC)

    // The stretch playing at `nowSec`, if skipping it is worth a button: more than a second of it is left, and for
    // credits there is something after them. Credits that run to the end are what "next episode" is for (upNextFrom).
    // A recap comes before an intro when the two overlap, as on the website.
    fun skipAt(spans: List<SkipSpan>, nowSec: Double, durationSec: Double): Skip? {
        if (!nowSec.isFinite()) return null
        for (kind in SkipKind.ORDER) {
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
    fun due(span: SkipSpan?, choices: AutoSkip): Boolean = span != null && choices.wants(span) && span !in done

    fun did(span: SkipSpan) {
        done += span
    }

    // A person pressed the button themselves: the same stretch needn't skip itself later either.
    fun pressed(span: SkipSpan) {
        done += span
    }
}
