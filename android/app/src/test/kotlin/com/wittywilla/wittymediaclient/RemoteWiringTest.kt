// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import android.view.KeyEvent
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Track
import com.wittywilla.wittymediaclient.net.remote.CommandAnswer
import com.wittywilla.wittymediaclient.net.remote.Feature
import com.wittywilla.wittymediaclient.net.remote.MusicFacts
import com.wittywilla.wittymediaclient.net.remote.PlayOnSource
import com.wittywilla.wittymediaclient.net.remote.RemoteCapabilities
import com.wittywilla.wittymediaclient.net.remote.RemoteDevice
import com.wittywilla.wittymediaclient.net.remote.RemoteQueue
import com.wittywilla.wittymediaclient.net.remote.RemoteState
import com.wittywilla.wittymediaclient.net.remote.VideoFacts
import com.wittywilla.wittymediaclient.net.remote.announcedCapabilities
import com.wittywilla.wittymediaclient.net.remote.deviceLine
import com.wittywilla.wittymediaclient.net.remote.handOverCommand
import com.wittywilla.wittymediaclient.net.remote.musicState
import com.wittywilla.wittymediaclient.net.remote.navigateKeyCode
import com.wittywilla.wittymediaclient.net.remote.remoteTracks
import com.wittywilla.wittymediaclient.net.remote.stopsHereAfter
import com.wittywilla.wittymediaclient.net.remote.videoState
import com.wittywilla.wittymediaclient.net.syncplay.ClockSample
import com.wittywilla.wittymediaclient.net.syncplay.PartyClock
import com.wittywilla.wittymediaclient.net.syncplay.PlayerFacts
import com.wittywilla.wittymediaclient.net.syncplay.Room
import com.wittywilla.wittymediaclient.net.syncplay.RoomItem
import com.wittywilla.wittymediaclient.net.syncplay.RoomState
import com.wittywilla.wittymediaclient.net.syncplay.SyncFollower
import com.wittywilla.wittymediaclient.net.syncplay.canEditQueue
import com.wittywilla.wittymediaclient.net.syncplay.hasNext
import com.wittywilla.wittymediaclient.net.syncplay.hasPrevious
import com.wittywilla.wittymediaclient.net.syncplay.keepsInStep
import com.wittywilla.wittymediaclient.net.syncplay.nowKind
import com.wittywilla.wittymediaclient.net.syncplay.partyQueue
import com.wittywilla.wittymediaclient.net.syncplay.queueMoved
import com.wittywilla.wittymediaclient.net.syncplay.queueWithout
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// What this app does with the Remote Protocol and watch parties beyond the wire format: keeping a player in step with
// a room tick by tick (the same tick as the website's and the Apple app's), the queue a party plays, what this device
// reports while it plays, and how it hands what plays here over to another device.
class RemoteWiringTest {
    // MARK: keeping in step

    private fun playing(atMs: Long = 1000, positionSec: Double = 100.0, rate: Double = 1.0, rev: Long = 7) =
        RoomState(rev = rev, seq = 3, itemId = 812, positionSec = positionSec, atMs = atMs, paused = false, rate = rate)

    private val paused = RoomState(rev = 4, seq = 2, itemId = 812, positionSec = 100.0, atMs = 1000, paused = true)

    @Test
    fun nothingIsDoneUntilThePlayerHasTheItemOpen() {
        val orders = SyncFollower().tick(playing(), "loading", 5000.0, 0.0, PlayerFacts(0.0, paused = true, loaded = false))
        assertFalse(orders.play)
        assertNull(orders.seekTo)
        assertNull(orders.report)
        assertEquals(7, orders.rev)
    }

    @Test
    fun aPausedRoomPausesThePlayerAndPutsItOnThePlaceOnce() {
        val follow = SyncFollower()
        // Close enough on a quick stream: paused where it is.
        val near = follow.tick(paused, "ready", 5000.0, 0.0, PlayerFacts(100.05, paused = false))
        assertTrue(near.pause)
        assertNull(near.seekTo)
        // Ten seconds out: sent to the place, and not asked again for the same place.
        val far = follow.tick(paused, "ready", 5000.0, 100.0, PlayerFacts(90.0, paused = true))
        assertEquals(100.0, far.seekTo!!, 0.0)
        assertNull(follow.tick(paused, "ready", 5000.0, 6000.0, PlayerFacts(90.0, paused = true)).seekTo)
        // A stream the server converts is left within half a second, as a jump there costs a new stream.
        assertNull(SyncFollower().tick(paused, "ready", 5000.0, 0.0, PlayerFacts(100.3, paused = true, cheapSeek = false)).seekTo)
    }

    @Test
    fun aStartSetInTheFutureHoldsAndLooksAgainOnTheMoment() {
        val orders = SyncFollower().tick(playing(atMs = 5300), "ready", 5000.0, 0.0, PlayerFacts(100.0, paused = true))
        assertFalse(orders.play)
        assertEquals(300L, orders.againInMs)
        assertNull(orders.behind)
    }

    @Test
    fun aMovingRoomStartsThePlayerAtItsSpeed() {
        // Two seconds since the start: the room is at 102.
        val orders = SyncFollower().tick(playing(rate = 1.5), "ready", 3000.0, 0.0, PlayerFacts(103.0, paused = true))
        assertTrue(orders.play)
        assertEquals(1.5, orders.rate!!, 1e-9)
        assertEquals(0.0, orders.behind!!, 1e-9)
    }

    @Test
    fun aSmallGapIsClosedByPlayingThreePercentFasterUntilSettled() {
        val follow = SyncFollower()
        // 0.5 s behind at 3000 (room at 102).
        assertEquals(1.03, follow.tick(playing(), "ready", 3000.0, 0.0, PlayerFacts(101.5, paused = false)).rate!!, 1e-9)
        assertTrue(follow.nudging)
        // 0.1 s: under the still line, but a nudge carries on until settled.
        assertEquals(1.03, follow.tick(playing(), "ready", 3000.0, 500.0, PlayerFacts(101.9, paused = false)).rate!!, 1e-9)
        // 0.03 s: settled, back to the room's speed.
        assertEquals(1.0, follow.tick(playing(), "ready", 3000.0, 1000.0, PlayerFacts(101.97, paused = false)).rate!!, 1e-9)
        assertFalse(follow.nudging)
        // Ahead plays slower.
        assertEquals(0.97, SyncFollower().tick(playing(), "ready", 3000.0, 0.0, PlayerFacts(102.5, paused = false)).rate!!, 1e-9)
    }

    @Test
    fun aBigGapIsAJumpAimedAsFarAheadAsTheLastJumpTook() {
        val follow = SyncFollower()
        val first = follow.tick(playing(), "ready", 3000.0, 0.0, PlayerFacts(90.0, paused = false))
        assertEquals(102.0, first.seekTo!!, 1e-9)
        // Not asked again while the first has its chance.
        assertNull(follow.tick(playing(), "ready", 4000.0, 1000.0, PlayerFacts(90.0, paused = false, seeking = true)).seekTo)
        // It landed two seconds later, in step: the next jump aims two seconds ahead.
        follow.tick(playing(), "ready", 5000.0, 2000.0, PlayerFacts(104.0, paused = false))
        assertEquals(2.0, follow.lagSec, 1e-9)
        val again = follow.tick(playing(), "ready", 20000.0, 9000.0, PlayerFacts(100.0, paused = false))
        assertEquals(121.0, again.seekTo!!, 1e-9)
    }

    @Test
    fun theRoomIsToldReadyOnceAndBufferingOnlyAfterARealStall() {
        val follow = SyncFollower()
        val ready = follow.tick(playing(rev = 9), "loading", 3000.0, 0.0, PlayerFacts(102.0, paused = false))
        assertEquals("ready", ready.report)
        assertEquals(9, ready.rev)
        // Not said twice within a second, even while the room hasn't caught up.
        assertNull(follow.tick(playing(rev = 9), "loading", 3200.0, 200.0, PlayerFacts(102.2, paused = false)).report)
        assertEquals("ready", follow.tick(playing(rev = 9), "loading", 4100.0, 1100.0, PlayerFacts(103.1, paused = false)).report)
        // A stall: nothing for the first moment, then buffering.
        val stalled = PlayerFacts(103.1, paused = false, canPlay = false)
        assertNull(follow.tick(playing(rev = 9), "ready", 4200.0, 2200.0, stalled).report)
        assertEquals("buffering", follow.tick(playing(rev = 9), "ready", 5300.0, 3300.0, stalled).report)
        // The room's word is "ready" already: nothing to say.
        assertNull(SyncFollower().tick(playing(), "ready", 3000.0, 0.0, PlayerFacts(102.0, paused = false)).report)
        // Not listed yet: nothing to say either.
        assertNull(SyncFollower().tick(playing(), null, 3000.0, 0.0, PlayerFacts(102.0, paused = false)).report)
    }

    @Test
    fun anEndedPlayerWaitsForTheRoomToMoveOn() {
        val orders = SyncFollower().tick(playing(), "ready", 3000.0, 0.0, PlayerFacts(5400.0, paused = true, ended = true))
        assertFalse(orders.play)
        assertNull(orders.seekTo)
    }

    @Test
    fun thePartyClockGuessesFromTheRoomUntilAPingAnswers() {
        val clock = PartyClock()
        assertEquals(500.0, clock.serverNow(500.0), 0.0)
        clock.guess(serverTimeMs = 10_000, localMs = 1000.0)
        assertEquals(10_500.0, clock.serverNow(1500.0), 0.0)
        // The server's clock 5000 ahead, by a 40 ms ping.
        clock.add(ClockSample(1000.0, 6020.0, 6021.0, 1041.0))
        assertEquals(6500.0, clock.serverNow(1500.0), 0.0)
        assertEquals(40.0, clock.rttMs, 0.0)
    }

    // MARK: the queue

    private val room = Room(
        id = "r", you = "b", canControl = true, queue = listOf(10, 11, 12, 13), items = listOf(RoomItem(11, "Two", "video"), RoomItem(12, "Three", "audio")),
        state = RoomState(itemId = 11, index = 1),
    )

    @Test
    fun takingOutOrMovingKeepsWhatPlaysPlaying() {
        assertEquals(listOf(10L, 11, 13) to 1, queueWithout(room, 2))
        assertEquals(listOf(11L, 12, 13) to 0, queueWithout(room, 0))
        assertNull(queueWithout(room, 1))
        assertNull(queueWithout(room, 9))
        assertEquals(listOf(11L, 10, 12, 13) to 0, queueMoved(room, 1, -1))
        assertEquals(listOf(10L, 12, 11, 13) to 2, queueMoved(room, 2, -1))
        assertEquals(listOf(10L, 11, 13, 12) to 1, queueMoved(room, 2, 1))
        assertNull(queueMoved(room, 3, 1))
    }

    @Test
    fun theQueueIsChangedOnlyByAControllerWhoSeesAllOfIt() {
        assertTrue(canEditQueue(room))
        assertFalse(canEditQueue(room.copy(canControl = false)))
        assertFalse(canEditQueue(room.copy(queue = listOf(10, 0, 12))))
        assertTrue(room.hasNext)
        assertTrue(room.hasPrevious)
        assertFalse(room.copy(state = RoomState(index = 3)).hasNext)
    }

    @Test
    fun onlyVideosAreKeptInStepHere() {
        assertEquals("video", room.nowKind)
        assertTrue(keepsInStep(room.nowKind))
        assertEquals("audio", room.copy(state = RoomState(itemId = 12, index = 2)).nowKind)
        assertFalse(keepsInStep("audio"))
        assertFalse(keepsInStep("dvd-iso"))
        // Something this account can't see says no kind; the server has already said whether it may.
        assertTrue(keepsInStep(room.copy(state = RoomState(itemId = 0, index = 0)).nowKind))
    }

    @Test
    fun anEpisodeBringsTheRestOfItsSeason() {
        fun ep(id: Long, season: Int, episode: Int, show: Long = 5) = Item(id = id, showId = show, season = season, episode = episode)
        val two = ep(2, 1, 2)
        val all = listOf(ep(4, 1, 4), ep(1, 1, 1), two, ep(3, 1, 3), ep(9, 2, 1), ep(7, 1, 5, show = 6))
        assertEquals(listOf(2L, 3, 4), partyQueue(two, all))
        assertEquals(listOf(2L, 3), partyQueue(two, all, max = 2))
        assertEquals(listOf(30L), partyQueue(Item(id = 30), all))
    }

    // MARK: what this device reports

    private val english = Track(index = 1, language = "en", languageName = "English", channels = 6)
    private val commentary = Track(index = 2, language = "en", languageName = "English", title = "Commentary", channels = 2)

    @Test
    fun tracksAreListedByThePlaybackAnswersIndex() {
        val listed = remoteTracks(listOf(english, commentary, english))
        assertEquals(listOf("1", "2"), listed.map { it.id })
        assertEquals("English · 5.1", listed[0].label)
        assertEquals("English · Commentary · Stereo", listed[1].label)
    }

    @Test
    fun aVideoSaysWhereItIsAndWhatCanBeChosen() {
        val state = videoState(
            VideoFacts(
                itemId = 812, status = "playing", positionSec = 1312.4, durationSec = 5400.0, rate = 1.03000001, volume = 0.6, muted = false,
                audioIndex = 1, subtitleIndex = -1, audio = listOf(english, commentary), queue = RemoteQueue(listOf(812, 813), 0), screen = "player",
            ),
        )
        assertEquals("playing", state.status)
        assertEquals(1.03, state.rate, 0.0)
        assertEquals("1", state.audio)
        assertEquals("off", state.subtitle)
        assertEquals(listOf(812L, 813), state.queue)
        // A queue that has moved on without this item isn't this item's.
        assertTrue(videoState(VideoFacts(900, "paused", 0.0, 0.0, 1.0, null, false, null, -1, queue = RemoteQueue(listOf(812, 813), 0))).queue.isEmpty())
        // A TV says nothing of a volume it doesn't have.
        assertFalse(videoState(VideoFacts(900, "paused", 0.0, 0.0, 1.0, null, false, null, -1)).toJson().contains("volume"))
    }

    @Test
    fun musicSaysItsQueueOnlyWhenItLinesUp() {
        val facts = MusicFacts(21, playing = true, loading = false, positionSec = 30.0, durationSec = 200.0, rate = 1.0, volume = 0.8, muted = false, queue = listOf(20, 21, 22), queueIndex = 1)
        assertEquals(listOf(20L, 21, 22), musicState(facts).queue)
        assertEquals(1, musicState(facts).queueIndex)
        assertTrue(musicState(facts.copy(queueIndex = 0)).queue.isEmpty())
        assertEquals("buffering", musicState(facts.copy(loading = true)).status)
        assertEquals("paused", musicState(facts.copy(playing = false)).status)
    }

    @Test
    fun theArrowsAndSelectAreTheRemotesOwnKeys() {
        assertEquals(KeyEvent.KEYCODE_DPAD_UP, navigateKeyCode("up"))
        assertEquals(KeyEvent.KEYCODE_DPAD_CENTER, navigateKeyCode("select"))
        assertEquals(KeyEvent.KEYCODE_MENU, navigateKeyCode("menu"))
        // Back, Home and Play/Pause are done by the app itself.
        assertNull(navigateKeyCode("back"))
        assertNull(navigateKeyCode("playpause"))
        assertNull(navigateKeyCode("jump"))
    }

    @Test
    fun onlyATvTakesKeysAndOnlyAPhoneOrTabletHasAVolume() {
        val tv = announcedCapabilities(tv = true)
        assertTrue(Feature.NAVIGATE in tv.features)
        assertFalse(Feature.VOLUME in tv.features)
        val phone = announcedCapabilities(tv = false)
        assertFalse(Feature.NAVIGATE in phone.features)
        assertTrue(Feature.VOLUME in phone.features)
        assertEquals(listOf("video", "audio"), phone.mediaKinds)
    }

    // MARK: handing over

    private val den = RemoteDevice(id = "den", name = "Den", online = true, capabilities = RemoteCapabilities(listOf("video", "audio"), listOf(Feature.SEEK, Feature.QUEUE)))

    @Test
    fun whatPlaysHereIsCastWhenThisIsADevice() {
        val here = PlayOnSource(812, "Puddle Day", "video", positionSec = 754.5, audio = "2", subtitle = "off", playingHere = true)
        val cast = handOverCommand(here, "me", den)
        assertEquals("cast", cast["type"]!!.jsonPrimitive.content)
        assertEquals("me", cast["from"]!!.jsonPrimitive.content)
        // Not announced: an ordinary play at the place, with the tracks, and this device stops itself.
        val play = handOverCommand(here, "", den)
        assertEquals("play", play["type"]!!.jsonPrimitive.content)
        assertEquals(754.5, play["positionSec"]!!.jsonPrimitive.content.toDouble(), 0.0)
        assertEquals("2", play["audio"]!!.jsonPrimitive.content)
        assertTrue(stopsHereAfter(here, sentCast = false, answer = CommandAnswer(ok = true)))
        // A cast the server stopped this device for needs nothing more; one it couldn't stop, this device stops.
        assertFalse(stopsHereAfter(here, sentCast = true, answer = CommandAnswer(ok = true, sourceStopped = true)))
        assertTrue(stopsHereAfter(here, sentCast = true, answer = CommandAnswer(ok = true, sourceStopped = false)))
    }

    @Test
    fun aTitleFromItsPageStartsFromTheResumePointAndAQueueGoesAsOne() {
        val title = PlayOnSource(812, "Puddle Day", "video")
        val play = handOverCommand(title, "me", den)
        assertEquals("play", play["type"]!!.jsonPrimitive.content)
        assertNull(play["positionSec"])
        assertFalse(stopsHereAfter(title, sentCast = false, answer = CommandAnswer(ok = true)))
        val songs = PlayOnSource(21, "Song", "audio", queue = listOf(20, 21, 22), queueIndex = 1, positionSec = 30.0, playingHere = true)
        val queued = handOverCommand(songs, "", den)
        assertEquals(1, queued["queueIndex"]!!.jsonPrimitive.content.toInt())
        // A device without a queue gets the song alone.
        val single = handOverCommand(songs, "", den.copy(capabilities = RemoteCapabilities(listOf("audio"), emptyList())))
        assertEquals(21L, single["itemId"]!!.jsonPrimitive.content.toLong())
    }

    @Test
    fun aDevicesLineSaysWhatItIsDoing() {
        assertEquals("Not connected", deviceLine(den.copy(online = false)))
        assertEquals("Nothing playing", deviceLine(den))
        val busy = den.copy(title = "Puddle Day", state = RemoteState(status = "playing", itemId = 812))
        assertEquals("Playing Puddle Day", deviceLine(busy))
        assertEquals("Paused: Puddle Day · Sam", deviceLine(busy.copy(state = busy.state.copy(status = "paused"), mine = false, userName = "Sam")))
        assertEquals("Playing something you can't see", deviceLine(den.copy(hidden = true, state = RemoteState(status = "playing"))))
    }
}
