// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.player.PaceStep
import com.wittywilla.wittymediaclient.player.paceStep
import com.wittywilla.wittymediaclient.player.slowerWords
import com.wittywilla.wittymediaclient.player.sustainableRate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The same order as the website (web/src/player/pace.ts): a smaller picture, faster than 1× only once, to
// 720p; then a speed the server keeps up with; at 1× with nothing smaller, words only.
class SpeedCapTest {
    @Test fun lowerThenSlower() {
        assertEquals(PaceStep.Lower, paceStep(1.7, 4.0, 1080, false))
        assertEquals(PaceStep.Slower, paceStep(1.7, 4.0, 720, false))
        assertEquals(PaceStep.Slower, paceStep(1.7, 4.0, 1080, true)) // the viewer's own quality is kept
        assertEquals(PaceStep.Lower, paceStep(0.6, 1.0, 720, false)) // at 1× quality goes on stepping down
        assertEquals(PaceStep.Tell, paceStep(0.6, 1.0, 360, false))
        assertEquals(PaceStep.Tell, paceStep(0.6, 1.0, 1080, true))
    }

    @Test fun theFastestSpeedItKeepsUpWith() {
        assertEquals(1.5, sustainableRate(1.7, 4.0), 0.0)
        assertEquals(2.0, sustainableRate(2.3, 4.0), 0.0)
        assertEquals(1.0, sustainableRate(0.6, 3.0), 0.0) // never below 1×
        assertTrue(slowerWords(4.0, 1.5).contains("can’t keep up at 4× for this video, so it plays at 1.5×"))
    }
}
