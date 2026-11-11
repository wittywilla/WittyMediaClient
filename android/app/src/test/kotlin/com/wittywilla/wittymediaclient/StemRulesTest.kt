// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.StemInfo
import com.wittywilla.wittymediaclient.net.StemList
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.player.DecodeStep
import com.wittywilla.wittymediaclient.player.StemGate
import com.wittywilla.wittymediaclient.player.StemResampler
import com.wittywilla.wittymediaclient.player.StemRules
import com.wittywilla.wittymediaclient.player.StemWindow
import com.wittywilla.wittymediaclient.player.blendMix
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Mixing a song's parts in step with the song: which parts, how loud, and which frame.
class StemRulesTest {
    private fun stem(name: String, approximate: Boolean = false, multitrack: Boolean = false) =
        StemInfo(name, "/api/media/11/stems/$name", "audio/flac", 1000, multitrack, if (approximate) "approximate" else "sidecar", approximate)

    // What a 0.8.0 server really answered once it had made the approximate instrumental for a song.
    private val approximateOnly = """{"names":["vocals","instrumental","drums","bass","other"],"separation":{"approximate":{"available":true,"note":"Approximate: made by cancelling what the left and right channels share. The voice is quieter, not gone, and the music is mono."},"external":{"available":false,"reason":"not-configured"}},"stems":[{"name":"instrumental","url":"/api/media/11/stems/instrumental","mime":"audio/mp4","size":1816319,"source":"approximate","approximate":true}]}"""

    @Test
    fun theServersListIsReadAndAnApproximatePartSaysSo() {
        val list = json.decodeFromString<StemList>(approximateOnly)
        assertTrue(list.separation.approximate.available)
        assertEquals("not-configured", list.separation.external.reason)
        val plan = StemRules.plan(list.stems)!!
        assertEquals(listOf("Instrumental (approximate)"), plan.parts.map { it.label })
        assertTrue(plan.approximate)
        // Without a voice of its own the song itself is a fader too, and starts down: karaoke at once.
        assertTrue(plan.withOriginal)
        assertEquals(listOf("instrumental", StemRules.ORIGINAL), plan.faders)
        assertEquals(mapOf("instrumental" to 1.0, StemRules.ORIGINAL to 0.0), StemRules.startLevels(plan))
        // A song with no stems has nothing to mix.
        assertNull(StemRules.plan(json.decodeFromString<StemList>("""{"names":[],"separation":{},"stems":null}""").stems))
    }

    @Test
    fun partsThatWouldDoubleEachOtherArentBothPlayed() {
        // Demucs with two stems: the voice and the music, which make the whole song.
        val two = StemRules.plan(listOf(stem("vocals"), stem("instrumental")))!!
        assertEquals(listOf("vocals", "instrumental"), two.parts.map { it.name })
        assertFalse(two.withOriginal)
        assertFalse(two.approximate)
        // All four, and an instrumental as well: the instrumental is the other three added up.
        val four = StemRules.plan(listOf(stem("instrumental"), stem("other"), stem("vocals"), stem("bass"), stem("drums")))!!
        assertEquals(listOf("vocals", "drums", "bass", "other"), four.parts.map { it.name })
        assertFalse(four.withOriginal)
        // Only some of the music: the instrumental stands for it.
        val some = StemRules.plan(listOf(stem("vocals"), stem("instrumental"), stem("drums")))!!
        assertEquals(listOf("vocals", "instrumental"), some.parts.map { it.name })
        // A voice and drums and nothing else isn't the whole song, so the song itself stays within reach.
        val thin = StemRules.plan(listOf(stem("vocals"), stem("drums")))!!
        assertEquals(listOf("vocals", "drums"), thin.parts.map { it.name })
        assertTrue(thin.withOriginal)
        // A part a newer server lists is played under its own name.
        val newer = StemRules.plan(listOf(stem("vocals"), stem("instrumental"), stem("backing-vocals")))!!
        assertEquals(listOf("Vocals", "Instrumental", "Backing vocals"), newer.parts.map { it.label })
    }

    @Test
    fun aNativeInstrumentsFileIsItsFourTracksAfterTheFullMix() {
        val plan = StemRules.plan(listOf(stem("multitrack", multitrack = true)))!!
        assertEquals(listOf(1, 2, 3, 4), plan.parts.map { it.track })
        assertEquals(listOf("Part 1", "Part 2", "Part 3", "Part 4"), plan.parts.map { it.label })
        assertTrue(plan.parts.all { it.url == "/api/media/11/stems/multitrack" })
        assertFalse(plan.withOriginal)
        // Separate parts win over it.
        assertEquals(listOf("vocals", "instrumental"), StemRules.plan(listOf(stem("multitrack", multitrack = true), stem("vocals"), stem("instrumental")))!!.parts.map { it.name })
    }

    @Test
    fun anAddressThatIsntTheServersOwnIsNeverPlayed() {
        assertNull(StemRules.plan(listOf(StemInfo("vocals", "https://elsewhere.example/v.flac"), StemInfo("instrumental", "//elsewhere.example/i.flac"), StemInfo("", "/api/media/1/stems/x"))))
    }

    @Test
    fun aFadersLevelIsSilentAtTheBottomAndUntouchedAtTheTop() {
        assertEquals(0f, StemRules.gain(0.0), 0f)
        assertEquals(1f, StemRules.gain(1.0), 0f)
        assertEquals(0.25f, StemRules.gain(0.5), 1e-6f)
        assertEquals(1f, StemRules.gain(3.0), 0f)
        assertEquals(0f, StemRules.gain(-1.0), 0f)
        assertEquals(0f, StemRules.gain(Double.NaN), 0f)
        assertEquals(0.9, StemRules.stepped(1.0, up = false), 0.0)
        assertEquals(1.0, StemRules.stepped(1.0, up = true), 0.0)
        assertEquals(0.0, StemRules.stepped(0.1, up = false), 0.0)
        assertEquals(0.0, StemRules.stepped(0.0, up = false), 0.0)
        // Ten presses down and ten up come back to exactly where they started.
        var level = 1.0
        repeat(10) { level = StemRules.stepped(level, up = false) }
        assertEquals(0.0, level, 0.0)
        repeat(10) { level = StemRules.stepped(level, up = true) }
        assertEquals(1.0, level, 0.0)
        assertEquals("70%", StemRules.percent(0.7))
    }

    @Test
    fun aTimeInTheSongIsOneFrameForEveryPart() {
        assertEquals(0, StemRules.frameAt(0, 44_100))
        assertEquals(44_100, StemRules.frameAt(1_000_000, 44_100))
        assertEquals(48_000L * 3600, StemRules.frameAt(3_600_000_000, 48_000))
        // To the nearest frame, the same way each time.
        assertEquals(1, StemRules.frameAt(23, 44_100))
        assertEquals(0, StemRules.frameAt(11, 44_100))
        assertEquals(1_000_000, StemRules.usAt(44_100, 44_100))
        // There and back is the same frame anywhere in a three-hour recording.
        for (frame in listOf(1L, 999L, 44_099L, 123_456_789L, 44_100L * 3 * 3600)) assertEquals(frame, StemRules.frameAt(StemRules.usAt(frame, 44_100), 44_100))
    }

    private fun ramp(from: Int, frames: Int): ShortArray = ShortArray(frames * 2) { ((from + it / 2) * (if (it % 2 == 0) 1 else -1)).toShort() }

    @Test
    fun theWindowHoldsFramesByTheirNumberInTheSong() {
        val w = StemWindow(1000)
        w.reset(5000)
        assertFalse(w.covers(5000, 1))
        assertEquals(400, w.write(ramp(0, 400), 0, 400))
        assertTrue(w.covers(5000, 400))
        assertFalse(w.covers(5000, 401))
        assertFalse(w.covers(4999, 10))
        val mix = FloatArray(8)
        w.addInto(5100, 4, mix, 1f, 1f)
        assertArrayEquals(floatArrayOf(100f, -100f, 101f, -101f, 102f, -102f, 103f, -103f).map { it / 32768f }.toFloatArray(), mix, 1e-7f)
        // Adding again adds: two parts in one mix.
        w.addInto(5100, 4, mix, 1f, 1f)
        assertEquals(200f / 32768f, mix[0], 1e-7f)
    }

    @Test
    fun theWindowGoesRoundWithoutLosingItsPlace() {
        val w = StemWindow(1000)
        w.reset(0)
        var written = 0
        var read = 0L
        // Three times round the ring, written in odd-sized pieces and read behind.
        while (written < 3300) {
            val piece = minOf(170, 3300 - written)
            w.forget(read)
            val went = w.write(ramp(written, piece), 0, piece)
            written += went
            if (written - read > 600) {
                val mix = FloatArray(2 * 300)
                assertTrue(w.covers(read, 300))
                w.addInto(read, 300, mix, 1f, 1f)
                for (i in 0 until 300) assertEquals(((read + i).toInt().toShort()) / 32768f, mix[i * 2], 1e-7f)
                read += 300
            }
        }
        assertEquals(3300L, w.next)
        // What was played has gone, and asking for it again is a seek.
        assertFalse(w.covers(0, 10))
        assertEquals(DecodeStep.Seek(0), w.step(0, 500, 500))
    }

    @Test
    fun aFullWindowTakesOnlyWhatFits() {
        val w = StemWindow(100)
        w.reset(0)
        assertEquals(100, w.write(ramp(0, 150), 0, 150))
        assertEquals(0, w.room())
        assertEquals(0, w.write(ramp(0, 10), 0, 10))
        w.forget(40)
        assertEquals(40, w.room())
        assertEquals(40, w.write(ramp(100, 50), 0, 50))
        assertTrue(w.covers(40, 100))
    }

    @Test
    fun aFaderMovesAcrossABufferAndAPartThatEndedIsSilence() {
        val w = StemWindow(100)
        w.reset(0)
        w.write(ShortArray(20) { 16384 }, 0, 10)
        val mix = FloatArray(20)
        w.addInto(0, 10, mix, 0f, 1f)
        assertEquals(0.05f, mix[0], 1e-6f)
        assertEquals(0.5f, mix[18], 1e-6f)
        assertTrue((1 until 10).all { mix[it * 2] > mix[(it - 1) * 2] })
        // A fader at the bottom adds nothing, and costs nothing.
        val silent = FloatArray(20)
        w.addInto(0, 10, silent, 0f, 0f)
        assertTrue(silent.all { it == 0f })
        // Past the end of a part that has finished there's nothing to wait for.
        assertFalse(w.covers(5, 10))
        w.finish()
        assertTrue(w.covers(5, 10))
        assertTrue(w.covers(500, 10))
        val tail = FloatArray(20)
        w.addInto(5, 10, tail, 1f, 1f)
        assertEquals(0.5f, tail[0], 1e-6f)
        assertEquals(0.5f, tail[8], 1e-6f)
        assertEquals(0f, tail[10], 0f)
        // Padding is silence that counts as there.
        val p = StemWindow(100)
        p.reset(1000)
        assertEquals(30, p.pad(30))
        assertTrue(p.covers(1000, 30))
    }

    @Test
    fun theDecoderKeepsAheadAndSeeksOnlyForAJump() {
        val w = StemWindow(1000)
        w.reset(0)
        assertEquals(DecodeStep.Decode, w.step(0, 500, 300))
        w.write(ramp(0, 499), 0, 499)
        assertEquals(DecodeStep.Decode, w.step(0, 500, 300))
        w.write(ramp(0, 1), 0, 1)
        assertEquals(DecodeStep.Idle, w.step(0, 500, 300))
        // The song moves on, so there's more to decode.
        assertEquals(DecodeStep.Decode, w.step(100, 500, 300))
        // A little ahead of what's decoded is caught up by decoding; a long way ahead, or behind, is a seek.
        assertEquals(DecodeStep.Decode, w.step(700, 500, 300))
        assertEquals(DecodeStep.Seek(801), w.step(801, 500, 300))
        w.forget(200)
        assertEquals(DecodeStep.Seek(100), w.step(100, 500, 300))
        // A finished part has nothing more to decode, but can still be sought back into.
        w.finish()
        assertEquals(DecodeStep.Idle, w.step(450, 500, 300))
        assertEquals(DecodeStep.Idle, w.step(5000, 500, 300))
        assertEquals(DecodeStep.Seek(10), w.step(10, 500, 300))
        // Asked to keep more ahead than it can hold, it stops when it's full rather than never.
        val small = StemWindow(100)
        small.reset(0)
        small.write(ramp(0, 100), 0, 100)
        assertEquals(DecodeStep.Idle, small.step(0, 500, 300))
    }

    @Test
    fun aPartAtAnotherRateComesOutAtTheSongs() {
        // 22.05 kHz to 44.1: every sample, and the one half-way to the next.
        val up = StemResampler(22_050, 44_100)
        val src = ramp(0, 100).also { for (i in it.indices) it[i] = (it[i] * 100).toShort() }
        val out = ShortArray(up.most(100) * 2)
        val made = up.run(src, 100, out)
        assertEquals(198, made)
        assertEquals(0, out[0].toInt())
        assertEquals(50, out[2].toInt())
        assertEquals(100, out[4].toInt())
        assertEquals(-50, out[3].toInt())
        // The next piece carries on across the join without a step: 9900 was the last, 10000 comes next.
        val more = ramp(100, 100).also { for (i in it.indices) it[i] = (it[i] * 100).toShort() }
        val made2 = up.run(more, 100, out)
        assertEquals(200, made2)
        assertEquals(9900, out[0].toInt())
        assertEquals(9950, out[2].toInt())
        assertEquals(10000, out[4].toInt())
        // 48 kHz to 44.1 over many odd pieces gives the right number of frames, to within one.
        val down = StemResampler(48_000, 44_100)
        var total = 0
        var fed = 0
        val pieces = listOf(1024, 333, 4096, 17, 2048, 1, 4801)
        val buffer = ShortArray(down.most(4801) * 2)
        repeat(20) { for (n in pieces) { total += down.run(ShortArray(n * 2), n, buffer); fed += n } }
        val expected = fed.toLong() * 44_100 / 48_000
        assertTrue("made $total, expected about $expected", kotlin.math.abs(total - expected) <= 1)
        // After a seek it starts from a whole frame again.
        up.reset()
        assertEquals(198, up.run(src, 100, out))
        assertEquals(0, out[0].toInt())
    }

    @Test
    fun theSongPlaysAsItIsUntilThePartsAreInStep() {
        val gate = StemGate(giveUpMs = 4000)
        // Turned on mid-song: nothing stops while the parts load.
        assertEquals(StemGate.Now.Plain, gate.decide(ready = false, nowMs = 0))
        assertEquals(StemGate.Now.Plain, gate.decide(ready = false, nowMs = 9000))
        assertFalse(gate.mixing)
        assertEquals(StemGate.Now.Mix, gate.decide(ready = true, nowMs = 9010))
        assertTrue(gate.mixing)
    }

    @Test
    fun afterASeekTheSongIsHeldRatherThanLettingTheVoiceBackIn() {
        val gate = StemGate(giveUpMs = 4000)
        gate.decide(true, 0)
        // A seek: the parts aren't there yet. Held, not played plain.
        var now = 10L
        while (now < 4000) {
            assertEquals(StemGate.Now.Hold, gate.decide(false, now))
            now += 10
        }
        // They arrive: in step again without a note of the voice.
        assertEquals(StemGate.Now.Mix, gate.decide(true, now))
        // A part that never arrives doesn't hold the song for ever.
        now += 10
        val from = now
        while (now - from < 4000) {
            assertEquals(StemGate.Now.Hold, gate.decide(false, now))
            now += 10
        }
        assertEquals(StemGate.Now.Plain, gate.decide(false, now))
        assertFalse(gate.mixing)
        assertEquals(StemGate.Now.Plain, gate.decide(false, now + 10))
        // And when it does turn up, the mix comes back.
        assertEquals(StemGate.Now.Mix, gate.decide(true, now + 20))
    }

    @Test
    fun timePausedIsntTimeSpentWaiting() {
        val gate = StemGate(giveUpMs = 4000, idleMs = 300)
        gate.decide(true, 0)
        assertEquals(StemGate.Now.Hold, gate.decide(false, 100))
        // Paused for a minute: the player asks for nothing. Coming back, the wait carries on where it was.
        assertEquals(StemGate.Now.Hold, gate.decide(false, 60_100))
        assertEquals(StemGate.Now.Hold, gate.decide(false, 60_200))
        gate.reset()
        assertEquals(StemGate.Now.Plain, gate.decide(false, 60_300))
    }

    @Test
    fun theMixIsThePartsAndTheSongAtItsOwnLevel() {
        val dry = floatArrayOf(0.5f, -0.5f, 0.5f, -0.5f)
        // Fully mixing, the song itself turned right down: only the parts are heard.
        var wet = floatArrayOf(0.2f, 0.1f, 0.2f, 0.1f)
        assertEquals(1f, blendMix(dry, wet, 2, 0f, 0f, 1f, 1f, 0.01f), 0f)
        assertArrayEquals(floatArrayOf(0.2f, 0.1f, 0.2f, 0.1f), wet, 1e-6f)
        // The song itself up as well: the parts with the song under them.
        wet = floatArrayOf(0.2f, 0.1f, 0.2f, 0.1f)
        blendMix(dry, wet, 2, 1f, 1f, 1f, 1f, 0.01f)
        assertArrayEquals(floatArrayOf(0.7f, -0.4f, 0.7f, -0.4f), wet, 1e-6f)
        // Not mixing: the song exactly as it is, whatever the parts hold.
        wet = floatArrayOf(0.9f, 0.9f, 0.9f, 0.9f)
        assertEquals(0f, blendMix(dry, wet, 2, 0f, 0f, 0f, 0f, 0.01f), 0f)
        assertArrayEquals(dry, wet, 0f)
    }

    @Test
    fun goingBetweenTheSongAndTheMixIsASlideNotAStep() {
        val frames = 200
        val dry = FloatArray(frames * 2) { 1f }
        val wet = FloatArray(frames * 2) { 0f }
        // From the song (1) to parts that are silent (0), a hundredth at a time.
        val reached = blendMix(dry, wet, frames, 0f, 0f, 0f, 1f, 0.01f)
        assertEquals(1f, reached, 1e-4f)
        assertEquals(0.99f, wet[0], 1e-4f)
        assertEquals(0.5f, wet[49 * 2], 1e-4f)
        assertEquals(0f, wet[150 * 2], 1e-4f)
        for (i in 1 until frames) assertTrue(wet[i * 2] <= wet[(i - 1) * 2] + 1e-6f)
        // A buffer too short to finish in carries on in the next.
        val part = blendMix(FloatArray(20) { 1f }, FloatArray(20), 10, 0f, 0f, 1f, 0f, 0.01f)
        assertEquals(0.9f, part, 1e-4f)
    }
}
