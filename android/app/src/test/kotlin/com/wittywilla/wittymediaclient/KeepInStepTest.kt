// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.player.realignNeeded
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

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
}
