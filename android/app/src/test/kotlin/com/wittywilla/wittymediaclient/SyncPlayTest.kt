// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.syncplay.ClockKeeper
import com.wittywilla.wittymediaclient.net.syncplay.ClockReading
import com.wittywilla.wittymediaclient.net.syncplay.ClockSample
import com.wittywilla.wittymediaclient.net.syncplay.Drift
import com.wittywilla.wittymediaclient.net.syncplay.Room
import com.wittywilla.wittymediaclient.net.syncplay.RoomEvent
import com.wittywilla.wittymediaclient.net.syncplay.RoomState
import com.wittywilla.wittymediaclient.net.syncplay.RoomTracker
import com.wittywilla.wittymediaclient.net.syncplay.SeatLife
import com.wittywilla.wittymediaclient.net.syncplay.SeatStep
import com.wittywilla.wittymediaclient.net.syncplay.SeekPlan
import com.wittywilla.wittymediaclient.net.syncplay.Step
import com.wittywilla.wittymediaclient.net.syncplay.SyncAct
import com.wittywilla.wittymediaclient.net.syncplay.SyncInfo
import com.wittywilla.wittymediaclient.net.syncplay.bestOffset
import com.wittywilla.wittymediaclient.net.syncplay.clockOffset
import com.wittywilla.wittymediaclient.net.syncplay.closedWords
import com.wittywilla.wittymediaclient.net.syncplay.correct
import com.wittywilla.wittymediaclient.net.syncplay.decide
import com.wittywilla.wittymediaclient.net.syncplay.filmFromPlayer
import com.wittywilla.wittymediaclient.net.syncplay.memberWords
import com.wittywilla.wittymediaclient.net.syncplay.normaliseCode
import com.wittywilla.wittymediaclient.net.syncplay.playerFromFilm
import com.wittywilla.wittymediaclient.net.syncplay.readRoomEvent
import com.wittywilla.wittymediaclient.net.syncplay.reportOwed
import com.wittywilla.wittymediaclient.net.syncplay.roomPositionSec
import com.wittywilla.wittymediaclient.net.syncplay.seekPlan
import com.wittywilla.wittymediaclient.net.syncplay.spacedCode
import com.wittywilla.wittymediaclient.net.syncplay.staleRoom
import com.wittywilla.wittymediaclient.net.syncplay.syncErrorWords
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The server's docs/SYNCPLAY.md, For developers. The clock and drift cases are the server's own
// (internal/syncplay/clock_test.go), so this app, the server and the website agree to the digit.
class SyncPlayTest {
    @Test
    fun clockOffsetIsNtpsSum() {
        // The server's clock is 5000 ms ahead; 40 ms each way; it took 10 ms to answer.
        assertEquals(ClockReading(5000.0, 80.0), clockOffset(1000.0, 6040.0, 6050.0, 1090.0))
        // This device's clock is ahead of the server's.
        assertEquals(ClockReading(-7000.0, 60.0), clockOffset(9000.0, 2030.0, 2030.0, 9060.0))
        assertEquals(ClockReading(0.0, 0.0), clockOffset(500.0, 500.0, 500.0, 500.0))
        // 100 ms out and 20 back: the sum can't know, and is out by half the difference.
        assertEquals(ClockReading(40.0, 120.0), clockOffset(0.0, 100.0, 100.0, 120.0))
    }

    private val samples = listOf(
        ClockSample(0.0, 5450.0, 5450.0, 500.0), // rtt 500, says 5200
        ClockSample(1000.0, 6020.0, 6021.0, 1041.0), // rtt 40, says 5000
        ClockSample(2000.0, 7100.0, 7100.0, 2150.0), // rtt 150, says 5025
        ClockSample(3000.0, 8000.0, 8000.0, 2990.0), // came back before it left: ignored
        ClockSample(Double.NaN, 1.0, 1.0, 1.0),
    )

    @Test
    fun theQuickestPingIsTheOneTrusted() {
        assertEquals(ClockReading(5000.0, 40.0), bestOffset(samples))
        assertNull(bestOffset(emptyList()))
        assertNull(bestOffset(samples.drop(3)))
    }

    @Test
    fun theLastEightPingsAreKeptAndBadOnesNeverCount() {
        val clock = ClockKeeper(keep = 8)
        assertFalse(clock.known)
        assertEquals(0.0, clock.rttMs, 0.0)
        // Five quick ones on joining, then the server's pace.
        assertEquals(300, clock.nextPingMs(5))
        samples.forEach { clock.add(it) }
        assertEquals(5000, clock.nextPingMs(5))
        assertEquals(40.0, clock.rttMs, 0.0)
        assertEquals(15_000.0, clock.serverNow(10_000.0), 0.0)
        // Eight slower pings push the best one out: the best of what's left is used.
        repeat(8) { i -> clock.add(ClockSample(i * 10.0, 5100.0 + i * 10, 5100.0 + i * 10, i * 10.0 + 200)) }
        assertEquals(ClockReading(5000.0, 200.0), clock.best)
        // A ping that makes no sense doesn't push a good one out either.
        repeat(20) { clock.add(ClockSample(3000.0, 8000.0, 8000.0, 2990.0)) }
        assertTrue(clock.known)
        clock.again()
        assertEquals(300, clock.nextPingMs(5))
        assertTrue(clock.known)
    }

    @Test
    fun driftIsCorrectedAsTheServerAndTheWebsiteDo() {
        // The same cases as internal/syncplay/clock_test.go TestCorrect and web/src/player/sync.test.mjs.
        val cases = listOf(
            Triple(0.0, false, Step(1.0)), Triple(0.1, false, Step(1.0)), Triple(-0.1, false, Step(1.0)),
            Triple(0.2, false, Step(1.03)), Triple(-0.2, false, Step(0.97)),
            // Once nudging it carries on past "close enough to leave alone", to "settled".
            Triple(0.1, true, Step(1.03)), Triple(-0.05, true, Step(0.97)), Triple(0.03, true, Step(1.0)),
            Triple(2.9, false, Step(1.03)), Triple(3.0, false, Step(1.0, 3.0)), Triple(-45.0, true, Step(1.0, -45.0)),
        )
        cases.forEach { (behind, nudging, want) -> assertEquals("behind $behind nudging $nudging", want, correct(behind, nudging)) }
        // The numbers are the server's, when it sends others.
        assertEquals(Step(1.1), correct(0.3, false, Drift(stillSec = 0.2, settledSec = 0.1, seekSec = 5.0, rate = 0.1)))
        assertEquals(Step(1.0), correct(0.15, false, Drift(stillSec = 0.2, settledSec = 0.1, seekSec = 5.0, rate = 0.1)))
    }

    @Test
    fun theRoomsPositionAtAServerTime() {
        // internal/syncplay/clock_test.go TestPositionAt.
        val s = RoomState(positionSec = 60.0, atMs = 10_000, rate = 1.0, paused = false)
        mapOf(9_000.0 to 60.0, 10_000.0 to 60.0, 10_500.0 to 60.5, 70_000.0 to 120.0).forEach { (ms, want) -> assertEquals(want, roomPositionSec(s, ms), 0.0) }
        assertEquals(63.0, roomPositionSec(s.copy(rate = 1.5), 12_000.0), 0.0)
        assertEquals(60.0, roomPositionSec(s.copy(paused = true), 99_000.0), 0.0)
        assertEquals(60.0, roomPositionSec(s.copy(waiting = true), 99_000.0), 0.0)
    }

    @Test
    fun whatAPlayerDoesTwiceASecond() {
        val playing = RoomState(positionSec = 100.0, atMs = 10_000, rate = 1.0, paused = false)
        // In step: play at the room's speed.
        assertEquals(SyncAct.Play(1.0, null, false), decide(playing, 20_000.0, 110.05, nudging = false))
        // A little behind: 3% faster, and carry on until settled.
        assertEquals(SyncAct.Play(1.03, null, true), decide(playing, 20_000.0, 109.5, false))
        assertEquals(SyncAct.Play(1.03, null, true), decide(playing, 20_000.0, 109.9, true))
        assertEquals(SyncAct.Play(1.0, null, false), decide(playing, 20_000.0, 109.97, true))
        // Ahead: slower.
        assertEquals(SyncAct.Play(0.97, null, true), decide(playing, 20_000.0, 111.0, false))
        // Three seconds or more: jump to where the room is.
        assertEquals(SyncAct.Play(1.0, 110.0, false), decide(playing, 20_000.0, 50.0, true))
        assertEquals(SyncAct.Play(1.0, 110.0, false), decide(playing, 20_000.0, 113.0, false))
        // A jump that takes this player two seconds to load lands where the room will be.
        assertEquals(SyncAct.Play(1.0, 112.0, false), decide(playing, 20_000.0, 50.0, false, loadSec = 2.0))

        // The room's own speed is kept, and nudged from.
        val fast = playing.copy(rate = 1.5)
        assertEquals(SyncAct.Play(1.5, null, false), decide(fast, 20_000.0, 115.0, false))
        assertEquals(1.5 * 1.03, (decide(fast, 20_000.0, 114.5, false) as SyncAct.Play).speed, 1e-12)

        // A start set in the future: hold, paused, at the place, until the moment comes.
        assertEquals(SyncAct.Hold(null), decide(playing, 9_700.0, 100.2, false))
        assertEquals(SyncAct.Hold(100.0), decide(playing, 9_700.0, 96.0, false))
        assertEquals(SyncAct.Play(1.0, null, false), decide(playing, 10_050.0, 100.0, false))

        // Paused or waiting: pause, and move only when more than half a second away.
        val paused = playing.copy(paused = true)
        assertEquals(SyncAct.Hold(null), decide(paused, 99_000.0, 100.4, false))
        assertEquals(SyncAct.Hold(100.0), decide(paused, 99_000.0, 100.6, false))
        assertEquals(SyncAct.Hold(100.0), decide(playing.copy(waiting = true), 99_000.0, 20.0, true))
    }

    @Test
    fun aConvertedStreamsClockIsMappedToTheFilms() {
        // A stream converted from 600 s into the film counts from 0 there.
        assertEquals(612.5, filmFromPlayer(12.5, 600.0), 0.0)
        assertEquals(12.5, playerFromFilm(612.5, 600.0), 0.0)
        assertEquals(12.5, filmFromPlayer(12.5, 0.0), 0.0)
        assertEquals(0.0, filmFromPlayer(-1.0, 0.0), 0.0)

        // A file played as it is, or a finished conversion: anywhere, in the player.
        assertEquals(SeekPlan.InPlayer(300.0), seekPlan(300.0, 0.0, "native", 5400.0, 5400.0))
        assertEquals(SeekPlan.InPlayer(5400.0), seekPlan(9999.0, 0.0, "native", null, 5400.0))
        // A growing stream that starts at 600: within what exists, in the player, at its own time.
        assertEquals(SeekPlan.InPlayer(30.0), seekPlan(630.0, 600.0, "restart", 45.0, 5400.0))
        // Past what exists so far, or before where it starts: a new stream from there.
        assertEquals(SeekPlan.NewStream(700.0), seekPlan(700.0, 600.0, "restart", 45.0, 5400.0))
        assertEquals(SeekPlan.NewStream(120.0), seekPlan(120.0, 600.0, "restart", 45.0, 5400.0))
        assertEquals(SeekPlan.NewStream(630.0), seekPlan(630.0, 600.0, "restart", null, 5400.0))
        assertEquals(SeekPlan.None, seekPlan(630.0, 0.0, "none", 45.0, 5400.0))

        // The room compares in the film's time, so two members on different streams agree.
        val room = RoomState(positionSec = 612.0, atMs = 0, paused = false)
        val direct = decide(room, 500.0, filmFromPlayer(612.5, 0.0), false)
        val converted = decide(room, 500.0, filmFromPlayer(12.5, 600.0), false)
        assertEquals(direct, converted)
        assertEquals(SyncAct.Play(1.0, null, false), converted)
    }

    @Test
    fun readyAndBufferingAreReportedOnceTheRoomDoesntKnow() {
        assertEquals("ready", reportOwed("loading", rightItem = true, playerReady = true, nearSec = 0.3, roomMoving = false))
        assertEquals("ready", reportOwed("buffering", true, true, 1.5, true))
        assertEquals("ready", reportOwed("lagging", true, true, 0.0, true))
        assertNull(reportOwed("ready", true, true, 0.3, true))
        // Not there yet: nothing to say while the room thinks so too.
        assertNull(reportOwed("loading", true, false, 0.0, true))
        assertNull(reportOwed("loading", true, true, 5.0, true))
        assertNull(reportOwed("loading", false, true, 0.0, true))
        // A stall while the room plays is said; while it's paused nobody is waiting on it.
        assertEquals("buffering", reportOwed("ready", true, false, 0.0, true))
        assertNull(reportOwed("ready", true, false, 0.0, false))
    }

    private val roomJson =
        """{"id":"9a7b","code":"GPSHRT","name":"Friday film","policy":"host","waitForAll":true,"hostId":"2038","you":"90c9","canControl":false,"blocked":false,"members":[{"id":"2038","userId":1,"name":"admin","host":true,"state":"loading","rttMs":0},{"id":"90c9","userId":2,"name":"Sam","host":false,"you":true,"state":"ready","rttMs":18.5}],"queue":[1,2],"state":{"rev":2,"seq":0,"itemId":1,"index":0,"positionSec":0,"atMs":1794414622226,"paused":true,"waiting":false,"rate":1},"serverTimeMs":1794414622332,"leadMs":300,"items":[{"id":1,"title":"Metropolis Test","kind":"video","runtimeSec":420},{"id":2,"title":"Night Shift","kind":"video","runtimeSec":420}],"somethingNew":[1]}"""

    @Test
    fun aRoomIsReadAsTheServerSendsIt() {
        val room = json.decodeFromString<Room>(roomJson)
        assertEquals("GPSHRT", room.code)
        assertEquals("Sam", room.me?.name)
        assertFalse(room.isHost)
        assertEquals("Metropolis Test", room.title)
        assertEquals(2L, room.state.rev)
        assertTrue(room.state.paused)
        assertEquals(RoomEvent.Changed(room), readRoomEvent(SseEvent("room", roomJson)))
        assertEquals(RoomEvent.Closed("removed"), readRoomEvent(SseEvent("closed", """{"reason":"removed"}""")))
        assertNull(readRoomEvent(SseEvent("confetti", "{}")))
        assertNull(readRoomEvent(SseEvent("room", "{")))
        // A stale command's refusal carries the room as it is now.
        assertEquals(room, staleRoom("""{"code":"stale","error":"someone else changed the watch party first","room":$roomJson}"""))
        assertNull(staleRoom("""{"code":"stale"}"""))

        val info = json.decodeFromString<SyncInfo>(
            """{"canCreate":true,"drift":{"rate":0.03,"seekSec":3,"settledSec":0.04,"stillSec":0.12},"enabled":true,"limits":{"awaySec":20,"codeLength":6,"pingEverySec":5,"seatGraceSec":120},"rooms":[{"id":"9f3c","name":"Friday film","hostName":"Sam","members":3,"invited":true}],"serverTimeMs":1794414581733}""",
        )
        assertTrue(info.enabled && info.canCreate)
        assertEquals(Drift(), info.drift)
        assertTrue(info.rooms.single().invited)
    }

    @Test
    fun theHighestRevIsTheTruth() {
        val room = json.decodeFromString<Room>(roomJson)
        fun at(rev: Long) = room.copy(state = room.state.copy(rev = rev))
        val tracker = RoomTracker()
        assertTrue(tracker.offer(at(5)))
        assertFalse(tracker.offer(at(4))) // an older one, arriving late
        assertEquals(5L, tracker.room?.state?.rev)
        assertTrue(tracker.offer(at(5))) // the same again, with titles asked afresh, say
        assertTrue(tracker.offer(at(9)))
        // Another room starts from whatever it says.
        assertTrue(tracker.offer(at(1).copy(id = "other")))
        tracker.clear()
        assertNull(tracker.room)
    }

    @Test
    fun codesAreTypedAnyOldWay() {
        assertEquals("KXM4T7", normaliseCode("kxm4t7"))
        assertEquals("KXM4T7", normaliseCode(" kxm - 4t7 "))
        assertEquals("KXM4T7", normaliseCode("K X M-4_T.7"))
        assertEquals("", normaliseCode(" - "))
        assertEquals("KXM 4T7", spacedCode("KXM4T7"))
        assertEquals("ABCD", spacedCode("ABCD"))
    }

    @Test
    fun everyRefusalAndEndingHasItsSentence() {
        val codes = listOf(
            400 to "bad-request", 403 to "disabled", 403 to "not-allowed", 403 to "cant-watch", 403 to "host-only", 403 to "not-host", 404 to "no-room", 404 to "not-member",
            404 to "no-item", 409 to "stale", 409 to "end-of-queue", 409 to "full", 429 to "rate", 429 to "too-many", 413 to "",
        )
        codes.forEach { (status, code) ->
            val said = syncErrorWords(status, code, "only the host controls this watch party")
            assertTrue("$code: $said", said.first().isUpperCase() && said.endsWith(".") && !said.contains("only the host controls this watch party"))
        }
        assertEquals("Only the host controls this watch party.", syncErrorWords(403, "host-only"))
        assertEquals("Something new.", syncErrorWords(418, "teapot", "Something new."))
        listOf("closed", "removed", "replaced", "signed-out", "server-stopping", "gone", "never-heard-of-it").forEach { assertTrue(closedWords(it).endsWith(".")) }
        assertEquals("Catching up", memberWords("lagging"))
        assertEquals("Can't watch this one", memberWords("blocked"))
        listOf("ready", "loading", "buffering", "away").forEach { assertTrue(memberWords(it).isNotEmpty()) }
        assertEquals("", memberWords("dancing"))
    }

    @Test
    fun aDroppedConnectionComesBackWithinTheSeatsGrace() {
        val seat = SeatLife(seatGraceSec = 120)
        assertFalse(seat.reconnecting)
        assertEquals(SeatStep.Rejoin(1000), seat.dropped(10_000))
        assertTrue(seat.reconnecting)
        assertEquals(SeatStep.Rejoin(2000), seat.dropped(11_000))
        assertEquals(SeatStep.Rejoin(4000), seat.refused(503, "", 13_000))
        seat.opened()
        assertFalse(seat.reconnecting)
        // Back to a short wait after a stream that opened.
        assertEquals(SeatStep.Rejoin(1000), seat.dropped(50_000))
        assertEquals(SeatStep.Rejoin(2000), seat.dropped(100_000))
        // Two minutes down: the seat has been given up.
        assertEquals(SeatStep.Over("gone"), seat.dropped(171_000))

        // The server saying the room or the seat has gone ends it at once.
        assertEquals(SeatStep.Over("gone"), SeatLife().refused(404, "no-room", 0))
        assertEquals(SeatStep.Over("gone"), SeatLife().refused(404, "not-member", 0))
        assertEquals(SeatStep.Over("gone"), SeatLife().refused(403, "cant-watch", 0))
        assertEquals(SeatStep.Over("closed"), SeatLife().refused(403, "disabled", 0))
        assertEquals(SeatStep.Over("signed-out"), SeatLife().refused(401, "", 0))
        assertTrue(SeatLife().refused(429, "rate", 0) is SeatStep.Rejoin)
    }
}
