// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.player.KaraokeAnswer
import com.wittywilla.wittymediaclient.player.KaraokeControls
import com.wittywilla.wittymediaclient.player.KaraokeEffect
import com.wittywilla.wittymediaclient.player.KaraokeEvent
import com.wittywilla.wittymediaclient.player.KaraokeLevels
import com.wittywilla.wittymediaclient.player.KaraokeMachine
import com.wittywilla.wittymediaclient.player.KaraokeMix
import com.wittywilla.wittymediaclient.player.KaraokeState
import com.wittywilla.wittymediaclient.player.KaraokeStem
import com.wittywilla.wittymediaclient.player.KaraokeWords
import com.wittywilla.wittymediaclient.player.PcmMix
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Karaoke from a song's separated parts (the server's `karaoke-auto`): the same rules as the website's and the
// iPhone's.
class KaraokeRulesTest {
    private fun stem(id: String, role: String, gain: Double = 1.0, label: String = id.replaceFirstChar(Char::uppercase)) =
        KaraokeStem(id, label, role, "/api/media/12/stems/$id?v=1a2b", "audio/mp4", gain)

    private val parts = KaraokeAnswer(
        state = "ready", quality = "stems", mix = "parts", version = "1a2b",
        stems = listOf(stem("vocals", "vocals", 0.9), stem("drums", "music"), stem("bass", "music", 0.8), stem("other", "music")),
    )
    private val blend = KaraokeAnswer(
        state = "ready", quality = "approximate", mix = "blend", version = "q1", improving = true, progress = 40, pollSec = 3,
        stems = listOf(stem("full", "full"), stem("instrumental", "music", label = "Music")),
    )

    private fun assertLevels(expected: List<Double>, actual: List<Double>) {
        assertEquals(expected.size, actual.size)
        expected.zip(actual).forEach { (e, a) -> assertEquals(e, a, 1e-9) }
    }

    @Test
    fun theServersAnswerIsRead() {
        val text = """{"state":"ready","quality":"stems","mix":"parts","stems":[
            {"id":"vocals","label":"Vocals","role":"vocals","url":"/api/media/12/stems/vocals?v=1a2b","mime":"audio/mp4","defaultGain":1,"later":true},
            {"id":"instrumental","label":"Music","role":"music","url":"/api/media/12/stems/instrumental?v=1a2b","mime":"audio/mp4","defaultGain":0.9},
            {"id":"choir","label":"Choir","role":"something-new","url":"/api/media/12/stems/choir?v=1a2b","mime":"audio/flac"},
            {"id":"full","label":"Song","role":"full","url":"/api/media/12/stems/full?v=1a2b"},
            {"id":"ghost","label":"Ghost","role":"music","url":""}],
            "version":"1a2b","improving":false,"progress":-1,"canImprove":false,"reason":"","message":"","pollSec":0,"somethingNew":{"a":1}}"""
        val answer = KaraokeAnswer.parse(text)!!
        assertEquals("ready", answer.state)
        assertEquals("1a2b", answer.version)
        assertEquals(-1, answer.progress)
        assertEquals(5, answer.stems.size)
        // A role this app doesn't know plays as music; the whole song among parts, and a part with no address, don't.
        assertEquals(listOf("vocals", "instrumental", "choir"), answer.playable.map { it.id })
        assertEquals(1.0, answer.playable[2].defaultGain, 0.0)
        assertEquals(listOf("Voice", "Background Music", "Track"), KaraokeMix.sliders(answer).map { it.label })

        val waiting = KaraokeAnswer.parse("""{"state":"preparing","stems":null,"progress":40,"pollSec":3}""")!!
        assertEquals(40, waiting.progress)
        assertTrue(waiting.stems.isEmpty())
        val no = KaraokeAnswer.parse("""{"state":"unavailable","reason":"mono","message":"This recording is mono."}""")!!
        assertEquals("mono", no.reason)
        assertEquals(-1, no.progress)
        assertNull(KaraokeAnswer.parse("<html>"))
        assertNull(KaraokeAnswer.parse(""))
        // A blend is the whole song and its music, or nothing.
        assertEquals(listOf("full", "instrumental"), blend.playable.map { it.id })
        assertTrue(blend.copy(stems = blend.stems.take(1)).playable.isEmpty())
    }

    @Test
    fun partsPlayAtVoiceBackgroundMusicAndTrack() {
        assertEquals(0.9, KaraokeMix.vocalsDefault(parts), 0.0)
        // The voice at t·v, every other part at t·m times its own level.
        assertLevels(listOf(0.9, 1.0, 0.8, 1.0), KaraokeMix.gains(parts, KaraokeControls()))
        val set = KaraokeControls().moveVocals(0.25).move(KaraokeMix.BACKGROUND, 0.5)
        assertLevels(listOf(0.25, 0.5, 0.4, 0.5), KaraokeMix.gains(parts, set))
        val quiet = set.move(KaraokeMix.TRACK, 0.5)
        assertLevels(listOf(0.125, 0.25, 0.2, 0.25), KaraokeMix.gains(parts, quiet))
        assertEquals(0.25, KaraokeMix.level(parts, set.levels, KaraokeMix.VOCALS), 0.0)
        assertEquals(0.5, KaraokeMix.level(parts, set.levels, KaraokeMix.BACKGROUND), 0.0)
        assertEquals(1.0, KaraokeMix.level(parts, set.levels, KaraokeMix.TRACK), 0.0)
        // Levels stay inside 0…1, whatever asks, and an id that isn't a slider changes nothing.
        assertLevels(listOf(1.0, 0.0, 0.0, 0.0), KaraokeMix.gains(parts, KaraokeControls().moveVocals(7.0).move(KaraokeMix.BACKGROUND, -1.0)))
        assertEquals(KaraokeControls(), KaraokeControls().move("drums", 0.2))
        // The same three sliders for every version.
        assertEquals(listOf("vocals", "music", "track"), KaraokeMix.sliders(parts).map { it.id })
        assertEquals(KaraokeMix.sliders(parts), KaraokeMix.sliders(blend))
    }

    @Test
    fun aBlendIsTheWholeSongLessItsMusic() {
        // gain(full) = t·v, gain(instrumental) = t·(m−v): straight lines, and the music adds up to t·m.
        assertLevels(listOf(1.0, 0.0), KaraokeMix.gains(blend, KaraokeControls()))
        assertLevels(listOf(0.0, 1.0), KaraokeMix.gains(blend, KaraokeControls().moveVocals(0.0)))
        assertLevels(listOf(0.25, 0.75), KaraokeMix.gains(blend, KaraokeControls().moveVocals(0.25)))
        val quieter = KaraokeControls().moveVocals(0.25).move(KaraokeMix.BACKGROUND, 0.5).move(KaraokeMix.TRACK, 0.5)
        assertLevels(listOf(0.125, 0.125), KaraokeMix.gains(blend, quieter))
        // The music below the voice: its gain goes negative, taking the music out of the whole song.
        assertLevels(listOf(1.0, -1.0), KaraokeMix.gains(blend, KaraokeControls().move(KaraokeMix.BACKGROUND, 0.0)))
        // The voice's own level comes from the whole song's in a blend.
        val soft = blend.copy(stems = listOf(stem("full", "full", 0.6), stem("instrumental", "music", 0.5)))
        assertEquals(0.6, KaraokeMix.vocalsDefault(soft), 0.0)
        assertLevels(listOf(0.6, 0.4), KaraokeMix.gains(soft, KaraokeControls()))
    }

    @Test
    fun singSilencesTheVoiceAndRemembersItsSlider() {
        val set = KaraokeControls().moveVocals(0.7)
        val singing = set.toggleSing()
        assertTrue(singing.sing)
        assertEquals(0.7, singing.levels.vocals!!, 0.0)
        assertLevels(listOf(0.0, 1.0, 0.8, 1.0), KaraokeMix.gains(parts, singing))
        assertLevels(listOf(0.0, 1.0), KaraokeMix.gains(blend, singing))
        // And back.
        assertLevels(listOf(0.7, 1.0, 0.8, 1.0), KaraokeMix.gains(parts, singing.toggleSing()))
        // Moving the Voice slider turns Sing off; the others don't.
        assertFalse(singing.moveVocals(0.2).sing)
        assertFalse(singing.move(KaraokeMix.VOCALS, 0.2).sing)
        assertTrue(singing.move(KaraokeMix.BACKGROUND, 0.2).sing)
        // Sing starts off.
        assertFalse(KaraokeControls().sing)
    }

    @Test
    fun resetGoesBackToTheServersLevels() {
        val set = KaraokeControls().moveVocals(0.1).move(KaraokeMix.TRACK, 0.1).toggleSing().reset()
        assertEquals(KaraokeControls(), set)
        assertLevels(listOf(0.9, 1.0, 0.8, 1.0), KaraokeMix.gains(parts, set))
    }

    @Test
    fun aRemoteMovesALevelFivePercentAtATime() {
        assertEquals(0.55, KaraokeMix.nudge(0.5, true), 1e-9)
        assertEquals(0.45, KaraokeMix.nudge(0.5, false), 1e-9)
        assertEquals(0.55, KaraokeMix.nudge(0.52, true), 1e-9)
        assertEquals(1.0, KaraokeMix.nudge(1.0, true), 0.0)
        assertEquals(0.0, KaraokeMix.nudge(0.0, false), 0.0)
    }

    @Test
    fun levelsAreKeptForEachProfile() {
        val levels = KaraokeControls().moveVocals(0.35).move(KaraokeMix.BACKGROUND, 0.5).move(KaraokeMix.TRACK, 0.0).levels
        assertEquals(levels, KaraokeLevels.read(levels.toJson()))
        assertEquals(KaraokeLevels(), KaraokeLevels.read(KaraokeLevels().toJson()))
        // Nothing kept, and anything unreadable, is the server's own levels.
        assertEquals(KaraokeLevels(), KaraokeLevels.read(null))
        assertEquals(KaraokeLevels(), KaraokeLevels.read("not json"))
        assertEquals(KaraokeLevels(1.0, 0.0), KaraokeLevels.read("""{"vocals":4,"music":-2,"track":"loud","new":1}"""))
        // What an older version kept, a level for each part, keeps only the voice's.
        assertEquals(KaraokeLevels(0.4), KaraokeLevels.read("""{"vocals":0.4,"stems":{"drums":0.1}}"""))
        assertEquals(KaraokeLevels(), KaraokeLevels.read("""{"vocals":"x","stems":[1]}"""))
        // One place for each account on each server.
        val keys = setOf(KaraokeLevels.key("https://a.example", 1), KaraokeLevels.key("https://a.example", 2), KaraokeLevels.key("https://b.example", 1))
        assertEquals(3, keys.size)
        assertEquals(KaraokeLevels.key("https://a.example", 1), KaraokeLevels.key("https://a.example", 1))
    }

    private fun KaraokeMachine.then(event: KaraokeEvent) = on(event)

    @Test
    fun karaokeIsAskedForOnceThenWatched() {
        var (m, effects) = KaraokeMachine().then(KaraokeEvent.Open(12))
        assertEquals(KaraokeState.Asked, m.state)
        assertEquals(listOf(KaraokeEffect.Unload, KaraokeEffect.Ask(0, true)), effects)

        m.then(KaraokeEvent.Answered(KaraokeAnswer(state = "preparing", progress = 40, pollSec = 5))).let { m = it.first; effects = it.second }
        assertEquals(KaraokeState.Preparing(40), m.state)
        assertEquals(listOf(KaraokeEffect.Ask(5, false)), effects)
        // No word on when to ask again while it's being made: every three seconds.
        assertEquals(listOf(KaraokeEffect.Ask(3, false)), m.then(KaraokeEvent.Answered(KaraokeAnswer(state = "preparing"))).second)

        m.then(KaraokeEvent.Answered(blend)).let { m = it.first; effects = it.second }
        assertEquals(KaraokeState.Ready(blend), m.state)
        assertEquals(listOf(KaraokeEffect.Load(blend), KaraokeEffect.Ask(3, false)), effects)

        // The same version again: nothing is fetched twice.
        val further = blend.copy(progress = 80)
        m.then(KaraokeEvent.Answered(further)).let { m = it.first; effects = it.second }
        assertEquals(KaraokeState.Ready(further), m.state)
        assertEquals(listOf(KaraokeEffect.Ask(3, false)), effects)
        // Still improving, with no word on asking again: it's watched all the same.
        assertEquals(listOf(KaraokeEffect.Ask(3, false)), m.then(KaraokeEvent.Answered(further.copy(pollSec = 0))).second)

        // The better version: its parts take over, and the asking stops.
        m.then(KaraokeEvent.Answered(parts)).let { m = it.first; effects = it.second }
        assertEquals(KaraokeState.Ready(parts), m.state)
        assertEquals(listOf(KaraokeEffect.Load(parts)), effects)
        assertTrue(m.then(KaraokeEvent.Answered(parts)).second.isEmpty())

        // Another song starts over; leaving ends it.
        m.then(KaraokeEvent.Open(13)).let { m = it.first; effects = it.second }
        assertEquals(KaraokeMachine(KaraokeState.Asked, 13), m)
        assertEquals(listOf(KaraokeEffect.Unload, KaraokeEffect.Ask(0, true)), effects)
        m.then(KaraokeEvent.Close).let { m = it.first; effects = it.second }
        assertEquals(KaraokeMachine(), m)
        assertEquals(listOf(KaraokeEffect.Unload), effects)
        // An answer that comes after leaving changes nothing.
        assertEquals(KaraokeMachine() to emptyList<KaraokeEffect>(), m.then(KaraokeEvent.Answered(parts)))
    }

    @Test
    fun whyNotIsSaidInTheServersWords() {
        val asked = KaraokeMachine().then(KaraokeEvent.Open(12)).first
        val (no, effects) = asked.then(KaraokeEvent.Answered(KaraokeAnswer(state = "unavailable", reason = "mono", message = "This recording is mono.")))
        assertEquals(KaraokeState.Unavailable("This recording is mono."), no.state)
        assertTrue(effects.isEmpty())
        // Busy: said, and asked again when the server says to.
        val (busy, again) = asked.then(KaraokeEvent.Answered(KaraokeAnswer(state = "unavailable", reason = "busy", message = "Busy.", pollSec = 10)))
        assertEquals(KaraokeState.Unavailable("Busy."), busy.state)
        assertEquals(listOf(KaraokeEffect.Ask(10, false)), again)
        // No words from the server, a state this app doesn't know, and a refusal: still something to read.
        assertEquals(KaraokeState.Unavailable(KaraokeMachine.NOT_NOW), asked.then(KaraokeEvent.Answered(KaraokeAnswer(state = "unavailable"))).first.state)
        assertEquals(KaraokeState.Unavailable(KaraokeMachine.NOT_NOW), asked.then(KaraokeEvent.Answered(KaraokeAnswer(state = "queued-somewhere"))).first.state)
        val (refused, none) = asked.then(KaraokeEvent.Failed("You can't open this.", lasting = true))
        assertEquals(KaraokeState.Unavailable("You can't open this."), refused.state)
        assertTrue(none.isEmpty())
        // Parts that were playing stop when the server takes them away.
        val playing = asked.then(KaraokeEvent.Answered(parts)).first
        assertEquals(listOf(KaraokeEffect.Unload), playing.then(KaraokeEvent.Answered(KaraokeAnswer(state = "unavailable", message = "Off."))).second)
        assertEquals(listOf(KaraokeEffect.Unload, KaraokeEffect.Ask(3, false)), playing.then(KaraokeEvent.Answered(KaraokeAnswer(state = "preparing"))).second)
    }

    @Test
    fun aLostNetworkKeepsWhatThereIsAndAsksLessOften() {
        assertEquals(listOf(6, 12, 24, 30, 30, 30), (1..6).map(KaraokeMachine::backoff))
        assertEquals(30, KaraokeMachine.backoff(1000))
        var m = KaraokeMachine().then(KaraokeEvent.Open(12)).first
        // The first ask itself: asked to prepare again.
        m.then(KaraokeEvent.Failed("", lasting = false)).let {
            assertEquals(KaraokeState.Asked, it.first.state)
            assertEquals(listOf(KaraokeEffect.Ask(6, true)), it.second)
        }
        m = m.then(KaraokeEvent.Answered(blend)).first
        val waits = ArrayList<Int>()
        repeat(5) {
            val (next, effects) = m.then(KaraokeEvent.Failed("", lasting = false))
            // The parts carry on playing.
            assertEquals(KaraokeState.Ready(blend), next.state)
            assertFalse(effects.any { it is KaraokeEffect.Unload || it is KaraokeEffect.Load })
            waits += (effects.single() as KaraokeEffect.Ask).also { assertFalse(it.prepare) }.afterSec
            m = next
        }
        assertEquals(listOf(6, 12, 24, 30, 30), waits)
        // An answer puts the count back.
        m = m.then(KaraokeEvent.Answered(blend)).first
        assertEquals(0, m.failures)
        assertEquals(listOf(KaraokeEffect.Ask(6, false)), m.then(KaraokeEvent.Failed("", lasting = false)).second)
        // A server's own wait is never longer than half a minute here.
        assertEquals(listOf(KaraokeEffect.Ask(30, false)), m.then(KaraokeEvent.Answered(blend.copy(pollSec = 900))).second)
    }

    @Test
    fun partsThatWontPlayFallBackToTheNormalTrack() {
        val playing = KaraokeMachine().then(KaraokeEvent.Open(12)).first.then(KaraokeEvent.Answered(blend)).first
        val (fell, effects) = playing.then(KaraokeEvent.StemsFailed(""))
        assertEquals(KaraokeState.Fallback(KaraokeMachine.NORMAL_TRACK), fell.state)
        assertEquals(listOf(KaraokeEffect.Unload), effects)
        assertEquals(KaraokeState.Fallback(KaraokeMachine.TOO_LARGE), playing.then(KaraokeEvent.StemsFailed(KaraokeMachine.TOO_LARGE)).first.state)
        // It stays that way for this song, whatever arrives late; another song tries again.
        assertEquals(fell to emptyList<KaraokeEffect>(), fell.then(KaraokeEvent.Answered(parts)))
        assertEquals(fell to emptyList<KaraokeEffect>(), fell.then(KaraokeEvent.Failed("", lasting = false)))
        assertEquals(KaraokeState.Asked, fell.then(KaraokeEvent.Open(13)).first.state)
        // Ready with nothing playable is the same.
        val (empty, unload) = KaraokeMachine().then(KaraokeEvent.Open(12)).first.then(KaraokeEvent.Answered(blend.copy(stems = emptyList())))
        assertEquals(KaraokeState.Fallback(KaraokeMachine.NORMAL_TRACK), empty.state)
        assertEquals(listOf(KaraokeEffect.Unload), unload)
        // A failure with nothing playing isn't one.
        assertEquals(KaraokeMachine(), KaraokeMachine().then(KaraokeEvent.StemsFailed("")).first)
    }

    @Test
    fun theWordsUnderTheControls() {
        assertEquals("Preparing karaoke…", KaraokeWords.status(KaraokeState.Asked, false))
        assertEquals("Preparing karaoke… 40%", KaraokeWords.status(KaraokeState.Preparing(40), false))
        assertEquals("Preparing karaoke…", KaraokeWords.status(KaraokeState.Preparing(-1), false))
        assertEquals("This recording is mono.", KaraokeWords.status(KaraokeState.Unavailable("This recording is mono."), false))
        assertEquals(KaraokeMachine.NORMAL_TRACK, KaraokeWords.status(KaraokeState.Fallback(KaraokeMachine.NORMAL_TRACK), false))
        // Ready, and still being fetched; then playing, and nothing more to say.
        assertEquals("Preparing karaoke…", KaraokeWords.status(KaraokeState.Ready(parts), false))
        assertEquals("", KaraokeWords.status(KaraokeState.Ready(parts), true))
        assertEquals("Separated", KaraokeWords.quality(parts))
        assertEquals("Quick version", KaraokeWords.quality(blend))
        assertEquals("", KaraokeWords.quality(parts.copy(quality = "")))
        assertEquals("Preparing a better version… 40%", KaraokeWords.improving(blend))
        assertEquals("Preparing a better version…", KaraokeWords.improving(blend.copy(progress = -1)))
        assertEquals("", KaraokeWords.improving(parts))
    }

    @Test
    fun thePartsAreAddedFrameForFrame() {
        val a = shortArrayOf(1000, -1000, 2000, -2000)
        val b = shortArrayOf(500, 500, 500, 500)
        val out = ShortArray(4)
        val level = floatArrayOf(1f, 0.5f)
        PcmMix.mix(listOf(a, b), level, level, out, 2, 2)
        assertArrayEquals(shortArrayOf(1250, -750, 2250, -1750), out)
        // Too loud is held at the top and the bottom, not wrapped round.
        val loud = shortArrayOf(30000, -30000)
        PcmMix.mix(listOf(loud, loud), floatArrayOf(1f, 1f), floatArrayOf(1f, 1f), out, 1, 2)
        assertEquals(Short.MAX_VALUE, out[0])
        assertEquals(Short.MIN_VALUE, out[1])
        // Silent is silent, and only as many frames as asked are written.
        val kept = shortArrayOf(7, 7, 7, 7)
        PcmMix.mix(listOf(a), floatArrayOf(0f), floatArrayOf(0f), kept, 1, 2)
        assertArrayEquals(shortArrayOf(0, 0, 7, 7), kept)
        // A level that has moved gets there in a straight line across the block, both channels alike.
        val flat = ShortArray(8) { 1000 }
        val ramp = ShortArray(8)
        PcmMix.mix(listOf(flat), floatArrayOf(0f), floatArrayOf(1f), ramp, 4, 2)
        assertArrayEquals(shortArrayOf(250, 250, 500, 500, 750, 750, 1000, 1000), ramp)
        // One channel.
        val mono = ShortArray(2)
        PcmMix.mix(listOf(shortArrayOf(100, 200), shortArrayOf(1, 2)), floatArrayOf(1f, 1f), floatArrayOf(1f, 1f), mono, 2, 1)
        assertArrayEquals(shortArrayOf(101, 202), mono)
    }

    @Test
    fun aSeekLandsOnTheSameFrameInEveryPart() {
        assertEquals(44100L, PcmMix.frameOf(1_000_000, 44100))
        assertEquals(48000L * 90, PcmMix.frameOf(90_000_000, 48000))
        assertEquals(1_000_000L, PcmMix.usOf(48000, 48000))
        assertEquals(0L, PcmMix.frameOf(0, 44100))
        // A block that starts before the place loses what's before it; one after it loses nothing; one wholly before
        // it is thrown away.
        assertEquals(24, PcmMix.toDrop(1000, 1024, 1024))
        assertEquals(0, PcmMix.toDrop(2048, 1024, 1024))
        assertEquals(1024, PcmMix.toDrop(0, 4096, 1024))
        assertNotNull(PcmMix)
    }
}
