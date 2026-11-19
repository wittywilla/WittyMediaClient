// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.MediaMarkers
import com.wittywilla.wittymediaclient.net.SkipRange
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.player.AutoSkip
import com.wittywilla.wittymediaclient.player.AutoSkipper
import com.wittywilla.wittymediaclient.player.PlaybackClock
import com.wittywilla.wittymediaclient.player.SkipKind
import com.wittywilla.wittymediaclient.player.SkipRules
import com.wittywilla.wittymediaclient.player.SkipSpan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Which stretch of a video can be skipped at a moment, from every kind and source the server marks.
class SkipRulesTest {
    // What a 0.8.0 server really answered for an episode whose intro was found by ear.
    private val detected = """{"intro":{"startSec":0,"endSec":20.1},"recap":null,"credits":null,"commercials":[],"source":"detected","sources":{"intro":"detected"}}"""

    private fun markers(text: String) = json.decodeFromString<MediaMarkers>(text)

    private val full = MediaMarkers(
        intro = SkipRange(60.0, 150.0),
        recap = SkipRange(0.0, 60.0),
        credits = SkipRange(2500.0, 2700.0),
        commercials = listOf(SkipRange(1200.0, 1320.0), SkipRange(600.0, 690.0)),
        source = "manual",
        sources = mapOf("intro" to "chapters", "recap" to "skip.json", "credits" to "manual", "commercials" to "edl"),
    )

    @Test
    fun theServersAnswerIsReadWithNothingMarkedAsNothing() {
        val spans = SkipRules.spans(markers(detected), null)
        assertEquals(listOf(SkipSpan(SkipKind.Intro, 0.0, 20.1, "detected")), spans)
        assertEquals(emptyList<SkipSpan>(), SkipRules.spans(markers("""{"intro":null,"recap":null,"credits":null,"commercials":null,"source":"none","sources":{}}"""), null))
    }

    @Test
    fun everyKindAndSourceBecomesAStretch() {
        val spans = SkipRules.spans(full, null)
        assertEquals(listOf(SkipKind.Recap, SkipKind.Intro, SkipKind.Commercial, SkipKind.Commercial, SkipKind.Credits), spans.map { it.kind })
        assertEquals(listOf("skip.json", "chapters", "edl", "edl", "manual"), spans.map { it.source })
        // Adverts come in the order they play, whatever order the file listed them in.
        assertEquals(listOf(600.0, 1200.0), spans.filter { it.kind == SkipKind.Commercial }.map { it.startSec })
    }

    @Test
    fun aStretchThatIsNoStretchIsLeftOut() {
        val odd = MediaMarkers(intro = SkipRange(30.0, 30.0), recap = SkipRange(50.0, 10.0), credits = SkipRange(-5.0, 10.0), commercials = listOf(SkipRange(Double.NaN, 5.0)))
        assertEquals(emptyList<SkipSpan>(), SkipRules.spans(odd, null))
    }

    @Test
    fun anOlderServersIntroStillSkips() {
        // No /media/{id}/markers: the intro that came with the stream stands in, as the app always did.
        val spans = SkipRules.spans(null, SkipRange(5.0, 65.0))
        assertEquals(listOf(SkipSpan(SkipKind.Intro, 5.0, 65.0, "playback")), spans)
        assertEquals(65.0, SkipRules.skipAt(spans, 10.0, 1800.0)?.toSec)
        assertEquals(emptyList<SkipSpan>(), SkipRules.spans(null, null))
        // Once the server has answered, its answer is the whole truth: an intro it no longer marks isn't offered.
        assertEquals(emptyList<SkipSpan>(), SkipRules.spans(MediaMarkers(), SkipRange(5.0, 65.0)))
    }

    @Test
    fun theButtonIsUpForTheStretchAndGoesBeforeItsLastSecond() {
        val spans = SkipRules.spans(full, null)
        assertNull(SkipRules.skipAt(spans, 599.0, 2700.0))
        assertEquals("Skip adverts", SkipRules.skipAt(spans, 600.0, 2700.0)?.label)
        assertEquals(690.0, SkipRules.skipAt(spans, 688.9, 2700.0)?.toSec)
        assertNull(SkipRules.skipAt(spans, 689.2, 2700.0))
        assertEquals("Skip recap", SkipRules.skipAt(spans, 0.0, 2700.0)?.label)
        assertEquals("Skip intro", SkipRules.skipAt(spans, 60.0, 2700.0)?.label)
        assertEquals(150.0, SkipRules.skipAt(spans, 100.0, 2700.0)?.toSec)
        assertNull(SkipRules.skipAt(spans, Double.NaN, 2700.0))
    }

    @Test
    fun aRecapComesBeforeAnIntroItOverlaps() {
        val spans = SkipRules.spans(MediaMarkers(intro = SkipRange(0.0, 90.0), recap = SkipRange(20.0, 50.0)), null)
        assertEquals(SkipKind.Recap, SkipRules.skipAt(spans, 30.0, 1800.0)?.span?.kind)
        assertEquals(SkipKind.Intro, SkipRules.skipAt(spans, 60.0, 1800.0)?.span?.kind)
    }

    @Test
    fun creditsWithSomethingAfterThemAreSkippedAndCreditsToTheEndBringUpNext() {
        // A scene after the credits: the button goes to it.
        val before = SkipRules.spans(MediaMarkers(credits = SkipRange(2500.0, 2640.0)), null)
        assertEquals(2640.0, SkipRules.skipAt(before, 2550.0, 2700.0)?.toSec)
        assertNull(SkipRules.upNextFrom(before, 2700.0))
        // Credits to the end: nothing to skip to, so no button, and "next episode" comes up as they start.
        val toEnd = SkipRules.spans(MediaMarkers(credits = SkipRange(2500.0, 2700.0)), null)
        assertNull(SkipRules.skipAt(toEnd, 2550.0, 2700.0))
        assertEquals(2500.0, SkipRules.upNextFrom(toEnd, 2700.0))
        assertEquals(SkipKind.Credits, SkipRules.endCreditsAt(toEnd, 2550.0, 2700.0)?.kind)
        assertNull(SkipRules.endCreditsAt(toEnd, 2400.0, 2700.0))
        // Credits shorter than the usual half minute change nothing: the usual rule already covers them.
        val short = SkipRules.spans(MediaMarkers(credits = SkipRange(2685.0, 2700.0)), null)
        assertNull(SkipRules.upNextFrom(short, 2700.0))
        // "Credits" marked in the first half are a mistake, and never end an episode early.
        val wrong = SkipRules.spans(MediaMarkers(credits = SkipRange(100.0, 2700.0)), null)
        assertNull(SkipRules.upNextFrom(wrong, 2700.0))
        assertNull(SkipRules.endCreditsAt(wrong, 200.0, 2700.0))
        // With no length known there's no telling what follows, so nothing is offered.
        assertNull(SkipRules.skipAt(before, 2550.0, 0.0))
        assertNull(SkipRules.upNextFrom(toEnd, 0.0))
    }

    @Test
    fun theTargetNeverPassesTheEnd() {
        assertEquals(100.0, SkipRules.target(SkipSpan(SkipKind.Commercial, 50.0, 130.0), 100.0), 0.0)
        assertEquals(130.0, SkipRules.target(SkipSpan(SkipKind.Commercial, 50.0, 130.0), 0.0), 0.0)
    }

    @Test
    fun aConversionThatStartsPartWayStillHasItsIntroWhereTheFilmHasIt() {
        // An HLS conversion asked for from 12 s into the film: the player's clock starts at 0, the film's doesn't.
        val spans = SkipRules.spans(markers(detected), null)
        val clock = PlaybackClock()
        clock.ready()
        clock.tick(playerSec = 2.0, offsetSec = 12.0, playing = true)
        val skip = SkipRules.skipAt(spans, clock.filmSec, 240.0)
        assertEquals(20.1, skip!!.toSec, 0.0)
        // In the player's own time that is 8.1 s on: the film's time less the stream's offset.
        assertEquals(8.1, skip.toSec - 12.0, 1e-9)
        // The same stream a minute in is past the intro, though the player says 50 s.
        clock.tick(playerSec = 50.0, offsetSec = 12.0, playing = true)
        assertNull(SkipRules.skipAt(spans, clock.filmSec, 240.0))
        // And a stream that starts after the intro never shows the button at all.
        val later = PlaybackClock()
        later.ready()
        later.tick(playerSec = 0.0, offsetSec = 600.0, playing = true)
        assertNull(SkipRules.skipAt(spans, later.filmSec, 240.0))
    }

    @Test
    fun autoSkipIsPerKindAndOnceForEachStretch() {
        val intro = SkipSpan(SkipKind.Intro, 0.0, 20.1, "detected")
        val recap = SkipSpan(SkipKind.Recap, 20.1, 50.0, "manual")
        val auto = AutoSkipper()
        assertFalse(auto.due(intro, AutoSkip()))
        assertFalse(auto.due(null, AutoSkip(intro = true)))
        assertTrue(auto.due(intro, AutoSkip(intro = true)))
        assertFalse(auto.due(recap, AutoSkip(intro = true)))
        // Asking isn't doing: it stays due until it has happened.
        assertTrue(auto.due(intro, AutoSkip(intro = true)))
        auto.did(intro)
        // Going back into the intro afterwards is someone wanting to watch it.
        assertFalse(auto.due(intro, AutoSkip(intro = true)))
        // Another stretch of the same kind, as the next advert break, is its own.
        val breaks = listOf(SkipSpan(SkipKind.Commercial, 600.0, 690.0), SkipSpan(SkipKind.Commercial, 1200.0, 1320.0))
        val adverts = AutoSkip(adverts = true)
        assertTrue(auto.due(breaks[0], adverts))
        auto.did(breaks[0])
        assertTrue(auto.due(breaks[1], adverts))
        // Pressing the button oneself settles it too.
        auto.pressed(recap)
        assertFalse(auto.due(recap, AutoSkip(recap = true)))
    }

    @Test
    fun theChoicesAreKeptPerKind() {
        var choices = AutoSkip()
        SkipKind.entries.forEach { assertFalse(choices.wants(it)) }
        choices = choices.with(SkipKind.Credits, true).with(SkipKind.Commercial, true)
        assertEquals(AutoSkip(credits = true, adverts = true), choices)
        assertTrue(choices.wants(SkipKind.Credits))
        assertFalse(choices.wants(SkipKind.Intro))
        assertEquals(AutoSkip(adverts = true), choices.with(SkipKind.Credits, false))
    }

    // A 0.8.1 server's answer for a film with a .wittyinfo: every part in `segments`, a preview only marked, a part
    // someone named that skips itself, and a scene after the credits.
    private val wittyinfo = """{"intro":{"startSec":30,"endSec":95},"recap":null,"credits":{"startSec":5400,"endSec":5600},"commercials":[],
        "preview":{"startSec":5650,"endSec":5700,"action":"mark"},"postCredits":{"startSec":5580,"endSec":5640},"custom":[{"startSec":2000,"endSec":2100,"label":"Dream sequence","action":"auto"}],
        "segments":[{"kind":"intro","startSec":30,"endSec":95,"action":"button","source":"wittyinfo"},
        {"kind":"custom","startSec":2000,"endSec":2100,"label":"Dream sequence","action":"auto","source":"wittyinfo"},
        {"kind":"credits","startSec":5400,"endSec":5600,"action":"button","source":"wittyinfo"},
        {"kind":"postcredits","startSec":5580,"endSec":5640,"action":"button","source":"wittyinfo"},
        {"kind":"preview","startSec":5650,"endSec":5700,"action":"mark","source":"wittyinfo"},
        {"kind":"chapter-art","startSec":1,"endSec":2,"action":"button","source":"wittyinfo"}],
        "source":"wittyinfo","sources":{"intro":"wittyinfo","credits":"wittyinfo"}}"""

    @Test
    fun aWittyinfosPartsComeFromItsSegments() {
        val spans = SkipRules.spans(markers(wittyinfo), null)
        // The scene after the credits, a part only marked and a kind this app doesn't know have no button.
        assertEquals(listOf(SkipKind.Intro, SkipKind.Custom, SkipKind.Credits), spans.map { it.kind })
        val custom = spans.single { it.kind == SkipKind.Custom }
        assertEquals("Dream sequence", custom.name)
        assertTrue(custom.fileAuto)
        assertEquals("Skip dream sequence", SkipRules.labelOf(custom))
        assertEquals("Skipped dream sequence", SkipRules.doneOf(custom))
        assertEquals("Skip intro", SkipRules.labelOf(spans.first()))
    }

    @Test
    fun creditsStopWhereASceneAfterThemStarts() {
        val spans = SkipRules.spans(markers(wittyinfo), null)
        val credits = spans.single { it.kind == SkipKind.Credits }
        assertEquals(5580.0, credits.endSec, 0.0)
        assertTrue(credits.toScene)
        // Not "to the end": the button takes you to the scene, and the next episode doesn't start over it.
        val skip = SkipRules.skipAt(spans, 5450.0, 5700.0)
        assertEquals(SkipKind.Credits, skip?.span?.kind)
        assertEquals(5580.0, skip!!.toSec, 0.0)
        assertNull(SkipRules.upNextFrom(spans, 5700.0))
        assertNull(SkipRules.skipAt(spans, 5600.0, 5700.0))
    }

    @Test
    fun theOlderFieldsCarryTheNewKindsToo() {
        val noSegments = MediaMarkers(
            preview = SkipRange(100.0, 160.0), custom = listOf(SkipRange(300.0, 360.0, "Opening song")),
            credits = SkipRange(500.0, 600.0, action = "mark"),
        )
        val spans = SkipRules.spans(noSegments, null)
        assertEquals(listOf(SkipKind.Custom, SkipKind.Preview), spans.map { it.kind })
        assertEquals("Skip opening song", SkipRules.skipAt(spans, 310.0, 900.0)?.label)
        assertEquals("Skip preview", SkipRules.skipAt(spans, 110.0, 900.0)?.label)
    }

    @Test
    fun aFileSaysWhatSkipsItselfUnlessTurnedOff() {
        val spans = SkipRules.spans(markers(wittyinfo), null)
        val custom = spans.single { it.kind == SkipKind.Custom }
        val intro = spans.single { it.kind == SkipKind.Intro }
        assertTrue(AutoSkip().wants(custom))
        assertFalse(AutoSkip().wants(intro))
        assertFalse(AutoSkip(fileAuto = false).wants(custom))
        assertTrue(AutoSkip(fileAuto = false, custom = true).wants(custom))
        assertTrue(AutoSkipper().due(custom, AutoSkip()))
    }

    @Test
    fun aLongNameIsCutOnItsButton() {
        val name = "A very long name that somebody gave to this part of the film"
        val label = SkipRules.labelOf(SkipSpan(SkipKind.Custom, 0.0, 10.0, name = name))
        assertEquals("Skip " + name.take(39).replaceFirstChar(Char::lowercaseChar) + "…", label)
        assertEquals("Skip this part", SkipRules.labelOf(SkipSpan(SkipKind.Custom, 0.0, 10.0)))
    }
}
