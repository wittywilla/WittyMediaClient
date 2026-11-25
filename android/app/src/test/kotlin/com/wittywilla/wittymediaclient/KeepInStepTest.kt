// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl
import com.wittywilla.wittymediaclient.player.realignNeeded
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class KeepInStepTest {
    // The owner's case, back to normal from 4×, lines up; a small step through the menu doesn't seek.
    @Test fun realignAfterARealChangeOfSpeed() {
        assertTrue(realignNeeded(4f, 1f))
        assertTrue(realignNeeded(1f, 4f))
        assertTrue(realignNeeded(1f, 2f))
        assertFalse(realignNeeded(1f, 1.25f))
        assertFalse(realignNeeded(1.5f, 1.75f))
        assertFalse(realignNeeded(0f, 1f))
    }

    // Live streams: ExoPlayer keeps to the live edge by playing a little faster or slower, within its
    // default range. No speed in that range, from any other in it, lines up (seeks) again.
    @Test fun liveSpeedControlNeverRealigns() {
        val low = DefaultLivePlaybackSpeedControl.DEFAULT_FALLBACK_MIN_PLAYBACK_SPEED
        val high = DefaultLivePlaybackSpeedControl.DEFAULT_FALLBACK_MAX_PLAYBACK_SPEED
        assertTrue(low >= 0.9f && high <= 1.1f)
        var a = low
        while (a <= high) {
            var b = low
            while (b <= high) { assertFalse("$a → $b", realignNeeded(a, b)); b += 0.005f }
            a += 0.005f
        }
    }

    // Live TV has its own player, which never lines up after a change of speed.
    @Test fun liveTvPlayerHasNoRealign() {
        val src = File("src/main/kotlin/com/wittywilla/wittymediaclient/tv/LiveTv.kt").readText()
        assertFalse(src.contains("KeepInStep"))
    }
}
