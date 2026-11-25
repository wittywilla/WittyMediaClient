// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.player.BUFFER_MAX_MS
import com.wittywilla.wittymediaclient.player.BUFFER_MIN_MS
import com.wittywilla.wittymediaclient.player.bufferForSpeed
import com.wittywilla.wittymediaclient.player.lowerHeight
import com.wittywilla.wittymediaclient.player.stepDownWords
import com.wittywilla.wittymediaclient.player.paceWords
import com.wittywilla.wittymediaclient.player.retryAfter503
import com.wittywilla.wittymediaclient.player.speedText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VideoFetchTest {
    // The buffer is the film's seconds: at 2× twice as many, so the wait it covers stays the same.
    @Test fun bufferGrowsWithSpeed() {
        assertEquals(BUFFER_MIN_MS.toLong(), bufferForSpeed(1f))
        assertEquals(BUFFER_MIN_MS.toLong(), bufferForSpeed(0.5f))
        assertEquals(2L * BUFFER_MIN_MS, bufferForSpeed(2f))
        assertEquals(BUFFER_MAX_MS.toLong(), bufferForSpeed(3f))
        assertEquals(BUFFER_MAX_MS.toLong(), bufferForSpeed(16f))
    }

    // A busy server, or a stream that moved, is asked again soon and a little later each time.
    @Test fun busyIsTriedAgainSoon() {
        assertEquals(1_000L, retryAfter503(1))
        assertEquals(2_000L, retryAfter503(2))
        assertEquals(4_000L, retryAfter503(3))
        assertEquals(4_000L, retryAfter503(9))
    }

    @Test fun speedsAsTheServerReadsThem() {
        assertEquals("2", speedText(2f))
        assertEquals("1.5", speedText(1.5f))
    }

    // The same sizes as the website steps through (web/src/player/pace.ts).
    @Test fun nextSizeDown() {
        assertEquals(1440, lowerHeight(2160))
        assertEquals(720, lowerHeight(1080))
        assertEquals(720, lowerHeight(800))
        assertEquals(480, lowerHeight(720))
        assertEquals(0, lowerHeight(360))
        assertEquals(0, lowerHeight(0))
        assertTrue(stepDownWords(0.7, 2.0, 720).endsWith("so it goes on at 720p."))
    }

    @Test fun slowServerInPlainWords() {
        val words = paceWords(0.666, 2.0)
        assertTrue(words, words.contains("0.67×") && words.contains("the 2× it plays at"))
    }
}
