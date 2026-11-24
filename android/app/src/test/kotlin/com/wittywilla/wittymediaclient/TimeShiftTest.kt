// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.Span
import com.wittywilla.wittymediaclient.net.TimeShiftRules
import com.wittywilla.wittymediaclient.net.TimeShiftRules.Seek
import com.wittywilla.wittymediaclient.net.Timeline
import com.wittywilla.wittymediaclient.net.Tuned
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Start over, rewinding past the buffer and skipping breaks, as server #648 and the web player have them.
class TimeShiftTest {
    private val breaks = listOf(Span(600, 660), Span(1200, 1290))

    @Test fun breakThePictureIsIn() {
        assertEquals(breaks[0], TimeShiftRules.breakAt(breaks, 600.0))
        assertEquals(breaks[1], TimeShiftRules.breakAt(breaks, 1289.9))
        assertNull(TimeShiftRules.breakAt(breaks, 660.0))
        assertNull(TimeShiftRules.breakAt(breaks, null))
    }

    @Test fun shiftedHintAlwaysPointsBackToLive() {
        assertEquals("News · 7 min behind live · Right, then Back to live", TimeShiftRules.behindHint("News", 420.0))
        // Mid-seek, before the picture's schedule time is known: no minutes, and never the catch-up wording.
        assertEquals("News · Right, then Back to live", TimeShiftRules.behindHint("News", 0.0))
    }

    @Test fun seeksWithinTheWindowMoveThePicture() {
        assertEquals(Seek.Within(70.0), TimeShiftRules.plan(970.0, 1000.0, 100.0, 40.0, 130.0, 5000.0))
    }

    @Test fun furtherBackRestartsFromThere() {
        assertEquals(Seek.Restart(500), TimeShiftRules.plan(500.7, 1000.0, 100.0, 40.0, 130.0, 5000.0))
        assertEquals(Seek.Restart(300), TimeShiftRules.plan(100.0, 1000.0, 100.0, 40.0, 130.0, 5000.0, earliest = 300.0))
        // Skipping a break that ends past what's loaded.
        assertEquals(Seek.Restart(660), TimeShiftRules.plan(660.5, 610.0, 100.0, 40.0, 110.0, 5000.0))
    }

    @Test fun atLiveGoesBackToTheChannel() {
        assertEquals(Seek.Live, TimeShiftRules.plan(4980.0, 1000.0, 100.0, 40.0, 130.0, 5000.0))
    }

    @Test fun aLongPauseStartsAgainWhereItPaused() {
        assertFalse(TimeShiftRules.restartAfterPause(0, 60_000, 300.0))
        assertTrue(TimeShiftRules.restartAfterPause(0, 280_000, 300.0))
        assertFalse(TimeShiftRules.restartAfterPause(0, 25_000, 10.0))
    }

    @Test fun startOverIsOfferedOnceAProgrammeHasBegun() {
        val p = GuideProgramme(start = 1000, end = 2800, kind = "show", title = "Film")
        assertTrue(TimeShiftRules.canStartOver(Tuned(now = p, startOver = true), 1100))
        assertFalse(TimeShiftRules.canStartOver(Tuned(now = p, startOver = true), 1010))
        assertFalse(TimeShiftRules.canStartOver(Tuned(now = p, startOver = false), 1100))
        assertFalse(TimeShiftRules.canStartOver(Tuned(now = p.copy(kind = "slate"), startOver = true), 1100))
    }

    @Test fun addresses() {
        assertEquals("/tv/lib-4/startover?viewer=v1&streamToken=1&from=1000", TimeShiftRules.path("lib-4", 1000, "v1"))
        assertEquals("/tv/lib-4/startover?viewer=v1&streamToken=1", TimeShiftRules.path("lib-4", null, "v1"))
        assertEquals("/tv/lib-4/leave?viewer=v1&shift=1", TimeShiftRules.leavePath("lib-4", "v1", true))
        assertTrue(TimeShiftRules.isLibrary("lib-4"))
        assertFalse(TimeShiftRules.isLibrary("tun-4"))
    }

    @Test fun readsTheServersAnswer() {
        val t = json.decodeFromString<Tuned>(
            """{"url":"/api/tv/lib-4/shift/v1/playlist.m3u8","startOver":true,"serverTime":5000,"bufferSec":300,
              "timeline":{"programme":{"start":0,"end":1300,"kind":"show","title":"Film"},"breaks":[{"start":600,"end":660}],"from":0,"live":5000,"earliest":0}}""",
        )
        assertEquals(Timeline(GuideProgramme(start = 0, end = 1300, kind = "show", title = "Film"), listOf(Span(600, 660)), 0, 5000, 0), t.timeline)
        assertEquals(5000L, t.serverTime)
        assertEquals(300.0, t.bufferSec, 0.0)
    }
}
