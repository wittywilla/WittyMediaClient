package com.wittywilla.wittymediaclient

import androidx.media3.common.PlaybackException
import com.wittywilla.wittymediaclient.net.Track
import com.wittywilla.wittymediaclient.player.Found
import com.wittywilla.wittymediaclient.player.PlaybackClock
import com.wittywilla.wittymediaclient.player.Recovery
import com.wittywilla.wittymediaclient.player.RetryBudget
import com.wittywilla.wittymediaclient.player.TrackMatch
import com.wittywilla.wittymediaclient.player.capabilitiesFrom
import com.wittywilla.wittymediaclient.player.clock
import com.wittywilla.wittymediaclient.player.failureWords
import com.wittywilla.wittymediaclient.player.recoveryFor
import com.wittywilla.wittymediaclient.player.seekStepSec
import com.wittywilla.wittymediaclient.player.spokenClock
import com.wittywilla.wittymediaclient.player.watchNextDue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackRulesTest {
    @Test
    fun theOldStreamsTimeIsNeverSavedAfterASwitch() {
        val c = PlaybackClock()
        c.ready()
        assertTrue(c.tick(100.0, 0.0, playing = true))
        c.switching()
        // A new stream starts at 0 with a new offset: reading it now would save the wrong place.
        assertFalse(c.tick(0.0, 500.0, playing = true))
        assertEquals(100.0, c.filmSec, 0.0)
        c.ready()
        assertTrue(c.tick(1.0, 500.0, playing = true))
        assertEquals(501.0, c.filmSec, 0.0)
    }

    @Test
    fun savesEveryTenSecondsAndNotInTheFirstFive() {
        val c = PlaybackClock()
        c.ready()
        assertFalse(c.tick(4.0, 0.0, playing = true))
        assertNull(c.lastPlace())
        assertTrue(c.tick(6.0, 0.0, playing = true))
        assertFalse(c.tick(9.0, 0.0, playing = true))
        assertTrue(c.tick(16.0, 0.0, playing = true))
        assertFalse(c.tick(40.0, 0.0, playing = false))
        assertEquals(40.0, c.lastPlace()!!, 0.0)
    }

    @Test
    fun badTimesAreIgnored() {
        val c = PlaybackClock()
        c.ready()
        c.tick(60.0, 0.0, playing = false)
        assertFalse(c.tick(Double.NaN, 0.0, playing = true))
        assertEquals(60.0, c.filmSec, 0.0)
    }

    @Test
    fun aStreamThatKeepsFailingGivesUp() {
        val b = RetryBudget()
        repeat(RetryBudget.ATTEMPTS) { assertNotNull(b.next()); b.played(1.0) }
        assertNull(b.next())
    }

    @Test
    fun onlyRealPlayingEarnsTheTriesBack() {
        val b = RetryBudget()
        repeat(RetryBudget.ATTEMPTS) { b.next() }
        b.played(RetryBudget.GOOD_AFTER_SEC)
        assertNotNull(b.next())
    }

    @Test
    fun eachFailureHasTheRightWayOut() {
        assertEquals(Recovery.NewStream, recoveryFor(0, 401))
        assertEquals(Recovery.NewStream, recoveryFor(0, 404))
        assertEquals(Recovery.WaitThenNewStream, recoveryFor(0, 503))
        assertEquals(Recovery.WaitThenNewStream, recoveryFor(PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED, null))
        assertEquals(Recovery.Convert, recoveryFor(PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED, null))
        assertEquals(Recovery.GiveUp, recoveryFor(0, 403))
        assertEquals(Recovery.GiveUp, recoveryFor(PlaybackException.ERROR_CODE_UNSPECIFIED, null))
        assertEquals(Recovery.NewStream, recoveryFor(PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW, null))
    }

    @Test
    fun whatsSaidHasNoCodesInIt() {
        for (code in listOf(PlaybackException.ERROR_CODE_IO_UNSPECIFIED, PlaybackException.ERROR_CODE_DECODING_FAILED, PlaybackException.ERROR_CODE_UNSPECIFIED)) {
            assertFalse(failureWords(code, null).contains("ERROR"))
        }
        assertTrue(failureWords(0, 503).contains("busy"))
    }

    @Test
    fun aHeldKeySpeedsUp() {
        assertEquals(10.0, seekStepSec(0), 0.0)
        assertEquals(30.0, seekStepSec(8), 0.0)
        assertEquals(60.0, seekStepSec(24), 0.0)
    }

    @Test
    fun watchNextIsThirtySecondsBeforeTheEnd() {
        assertFalse(watchNextDue(100.0, 200.0, hasNext = true))
        assertTrue(watchNextDue(170.0, 200.0, hasNext = true))
        assertFalse(watchNextDue(170.0, 200.0, hasNext = false))
        assertFalse(watchNextDue(0.0, 0.0, hasNext = true)) // no length known
    }

    @Test
    fun clocksReadAndSpeak() {
        assertEquals("1:02:03", clock(3723.0))
        assertEquals("2:03", clock(123.9))
        assertEquals("1 hour 2 minutes 3 seconds", spokenClock(3723.0))
        assertEquals("0 seconds", spokenClock(-4.0))
    }

    @Test
    fun languagesAreComparedByTheirBase() {
        assertEquals("en", TrackMatch.base("eng"))
        assertEquals("en", TrackMatch.base("en-US"))
        assertEquals("de", TrackMatch.base("ger"))
        assertEquals("", TrackMatch.base("und"))
        assertEquals("fr", TrackMatch.languageFor(Track(language = "fre")))
        assertNull(TrackMatch.languageFor(Track(language = "")))
        assertNull(TrackMatch.languageFor(null))
    }

    @Test
    fun whatADeviceFoundBecomesWhatTheServerHears() {
        val caps = capabilitiesFrom(
            Found(
                videoMimes = setOf("video/avc", "video/hevc", "video/x-vnd.on2.vp9", "video/unknown"),
                audioMimes = setOf("audio/mp4a-latm", "audio/mpeg", "audio/flac"),
                passthrough = setOf("ac3", "eac3"),
                hdr = setOf("hdr10"),
                tenBit = true,
                maxLines = 4320,
                maxChannels = 8,
            ),
        )
        assertEquals(listOf("h264", "hevc", "vp9"), caps.videoCodecs)
        assertEquals(listOf("aac", "ac3", "eac3", "flac", "mp3"), caps.audioCodecs)
        assertEquals(listOf("hdr10"), caps.hdr)
        assertEquals(2160, caps.maxHeight)
        assertEquals(8, caps.maxAudioChannels)
        assertEquals(listOf("h264", "hevc"), caps.hlsVideo)
        assertEquals(listOf("aac", "ac3", "eac3", "mp3"), caps.hlsAudio)
    }

    @Test
    fun aDeviceThatSaysNothingStillGetsTheFloor() {
        val caps = capabilitiesFrom(Found())
        assertEquals(listOf("h264"), caps.videoCodecs)
        assertEquals(listOf("aac"), caps.audioCodecs)
        assertNull(caps.hdr)
        assertNull(caps.maxHeight)
        assertEquals(2, caps.maxAudioChannels)
    }
}
