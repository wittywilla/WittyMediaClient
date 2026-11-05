package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Loudness
import com.wittywilla.wittymediaclient.player.Biquad
import com.wittywilla.wittymediaclient.player.Equaliser
import com.wittywilla.wittymediaclient.player.FilterKind
import com.wittywilla.wittymediaclient.player.Leveling
import com.wittywilla.wittymediaclient.player.SoundSettings
import com.wittywilla.wittymediaclient.player.gain
import com.wittywilla.wittymediaclient.player.towards
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.log10
import kotlin.math.pow

// The website's Sound panel and Web Audio graph (sound.ts, SoundPanel.tsx, player.tsx), ported from the iPhone's
// SoundLookTests so both apps shape the sound the same way.
class SoundRulesTest {
    @Test
    fun theEqualisersPresetsAreTheWebsites() {
        assertEquals(listOf("Flat", "More bass", "More treble", "Clear voices", "Rock", "Pop", "Classical", "Jazz", "Quiet room", "Speech"), Equaliser.PRESETS.map { it.name })
        assertEquals(listOf("flat", "bass", "treble", "vocal", "rock", "pop", "classical", "jazz", "night", "speech"), Equaliser.PRESETS.map { it.id })
        assertTrue(Equaliser.PRESETS.all { it.gains.size == Equaliser.FREQUENCIES.size })
        assertEquals(listOf(6.0, 5.0, 3.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0), Equaliser.PRESETS.first { it.id == "bass" }.gains)
        assertEquals(listOf(-6.0, -4.0, -2.0, 1.0, 3.0, 4.0, 3.0, 2.0, 0.0, -3.0), Equaliser.PRESETS.first { it.id == "speech" }.gains)
        assertEquals(listOf("31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"), Equaliser.FREQUENCIES.map(Equaliser::hertz))
        assertEquals("+3", Equaliser.decibels(3.0))
        assertEquals("-2", Equaliser.decibels(-2.0))
        assertEquals("0", Equaliser.decibels(0.0))
        assertEquals(FilterKind.LowShelf, Equaliser.kind(0))
        assertEquals(FilterKind.Peaking, Equaliser.kind(5))
        assertEquals(FilterKind.HighShelf, Equaliser.kind(9))
        // A preset is shown by name; the listener's own is "custom", which the panel calls Your own.
        assertEquals("rock", SoundSettings(eqPreset = "rock").presetShown)
        assertEquals("custom", SoundSettings(eqPreset = "custom").presetShown)
    }

    @Test
    fun theFiltersFollowWebAudiosFormulas() {
        val rate = 48_000.0
        fun db(factor: Double) = 20 * log10(factor)
        // Each band, set to a gain, lifts its own frequency by that much and leaves far-off ones alone.
        val peak = Biquad().apply { set(FilterKind.Peaking, 1000.0, Equaliser.Q, 6.0, rate) }
        assertEquals(6.0, db(peak.gainAt(1000.0, rate)), 0.01)
        assertEquals(0.0, db(peak.gainAt(20.0, rate)), 0.1)
        val flat = Biquad().apply { set(FilterKind.Peaking, 1000.0, Equaliser.Q, 0.0, rate) }
        assertEquals(1.0, flat.gainAt(3000.0, rate), 1e-9)
        val low = Biquad().apply { set(FilterKind.LowShelf, 31.0, Equaliser.Q, 6.0, rate) }
        assertEquals(6.0, db(low.gainAt(1.0, rate)), 0.05)
        assertEquals(3.0, db(low.gainAt(31.0, rate)), 0.05)
        assertEquals(0.0, db(low.gainAt(5000.0, rate)), 0.05)
        val high = Biquad().apply { set(FilterKind.HighShelf, 16_000.0, Equaliser.Q, -4.0, rate) }
        assertEquals(-4.0, db(high.gainAt(23_900.0, rate)), 0.2)
        assertEquals(0.0, db(high.gainAt(100.0, rate)), 0.05)
        // The voice cut's filters: Web Audio's Q of 1 dB for the passes.
        val pass = Biquad().apply { set(FilterKind.HighPass, 150.0, 1.0, 0.0, rate) }
        assertEquals(0.0, pass.gainAt(1.0, rate), 0.001)
        assertEquals(1.0, pass.gainAt(5000.0, rate), 0.01)
        assertEquals(10.0.pow(1.0 / 20), pass.gainAt(150.0, rate), 0.01)
        val under = Biquad().apply { set(FilterKind.LowPass, 150.0, 1.0, 0.0, rate) }
        assertEquals(1.0, under.gainAt(1.0, rate), 0.001)
        assertTrue(under.gainAt(5000.0, rate) < 0.01)
        // A steady signal through a flat filter comes out as it went in.
        val through = Biquad().apply { set(FilterKind.Peaking, 500.0, Equaliser.Q, 0.0, rate) }
        assertEquals(0.25, (0 until 10).map { through.run(0.25, 0) }.last(), 1e-9)
        // Levels ease to where they're set, as setTargetAtTime: about 63% of the way in one time constant.
        val step = towards(0.05, rate)
        var level = 0.0
        repeat((0.05 * rate).toInt()) { level += (1 - level) * step }
        assertEquals(1 - 1 / Math.E, level, 0.001)
    }

    @Test
    fun savedSoundSettingsArePutRightAndTheVoiceAndKeyAreNotKept() {
        val saved = SoundSettings.read("""{"volume":3,"eqOn":true,"eqGains":[20,0,0,0,0,0,0,0,0,-40],"preamp":-30,"replayGain":"loud","gapless":false,"crossfade":99,"vocalCut":1,"keyShift":4}""")
        assertEquals(1.0, saved.volume, 0.0)
        assertEquals(12.0, saved.eqGains.first(), 0.0)
        assertEquals(-12.0, saved.eqGains.last(), 0.0)
        assertEquals(-12.0, saved.preamp, 0.0)
        assertEquals(Leveling.Off, saved.replayGain)
        assertFalse(saved.gapless)
        assertEquals(12.0, saved.crossfade, 0.0)
        assertEquals(0.0, saved.vocalCut, 0.0)
        assertEquals(0.0, saved.keyShift, 0.0)
        assertTrue(saved.eqOn)
        // A short list of gains is from somewhere else: the flat ones stand.
        val short = SoundSettings.read("""{"eqGains":[1,2]}""")
        assertEquals(Equaliser.PRESETS[0].gains, short.eqGains)
        assertTrue(short.gapless)
        assertEquals(SoundSettings(), SoundSettings.read(null))
        assertEquals(SoundSettings(), SoundSettings.read("not json"))
        assertEquals(Leveling.Album, SoundSettings.read("""{"replayGain":"album"}""").replayGain)
        // What's kept reads back the same, without the voice and the key.
        val mine = SoundSettings(volume = 0.5, eqOn = true, eqPreset = "custom", eqGains = List(10) { it - 5.0 }, preamp = -3.0, replayGain = Leveling.Track, crossfade = 6.0, crossfadeAlbums = true, vocalCut = 1.0, keyShift = 3.0)
        assertEquals(mine.copy(vocalCut = 0.0, keyShift = 0.0), SoundSettings.read(mine.toJson()))
    }

    @Test
    fun crossfadeLeavesAnAlbumAloneUnlessAsked() {
        var sound = SoundSettings()
        assertEquals(0.0, sound.fade("A", "B"), 0.0)
        sound = sound.copy(crossfade = 6.0)
        assertEquals(6.0, sound.fade("A", "B"), 0.0)
        assertEquals(0.0, sound.fade("A", "A"), 0.0)
        // A song with no album isn't in one.
        assertEquals(6.0, sound.fade("", ""), 0.0)
        assertEquals(6.0, sound.fade(null, null), 0.0)
        sound = sound.copy(crossfadeAlbums = true)
        assertEquals(6.0, sound.fade("A", "A"), 0.0)
        assertEquals(listOf("Off", "2 seconds", "4 seconds", "6 seconds", "8 seconds", "12 seconds"), SoundSettings.CROSSFADES.map(SoundSettings::crossfadeWords))
    }

    @Test
    fun levelingNeverClips() {
        val tagged = Loudness(trackDb = -6.0, albumDb = -4.0, trackPeak = 0.5)
        assertEquals(0.0, tagged.gain(Leveling.Off), 0.0)
        assertEquals(-6.0, tagged.gain(Leveling.Track), 0.0)
        assertEquals(-4.0, tagged.gain(Leveling.Album), 0.0)
        // +8 asked for, but the peak leaves room for only about 6.
        val quiet = Loudness(trackDb = 8.0, trackPeak = 0.5)
        assertEquals(-20 * log10(0.5), quiet.gain(Leveling.Track), 0.001)
        // Album mode falls back to the song's values, and a file with no peak may rise up to 12.
        assertEquals(8.0, quiet.copy(trackPeak = null).gain(Leveling.Album), 0.0)
        assertEquals(12.0, Loudness(trackDb = 15.0).gain(Leveling.Track), 0.0)
        assertEquals(0.0, Loudness().gain(Leveling.Album), 0.0)
        assertEquals(listOf("Off", "Each song the same", "Keep each album's balance"), Leveling.entries.map { it.words })
    }
}
