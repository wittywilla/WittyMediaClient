// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.player.Found
import com.wittywilla.wittymediaclient.player.capabilitiesFrom
import com.wittywilla.wittymediaclient.player.withoutPassthrough
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PassthroughSpeedTest {
    // A TV box that sends AC-3 and E-AC-3 to the receiver as they are, and has its own AC-3 decoder too.
    private val box = Found(
        audioMimes = setOf("audio/mp4a-latm", "audio/ac3", "audio/opus"),
        passthrough = setOf("ac3", "eac3"),
    )

    // At 1× it takes them as they are; at another speed it asks for sound it decodes, which Media3 can stretch.
    @Test fun fasterAsksForSoundItDecodes() {
        val normal = capabilitiesFrom(box)
        assertTrue(normal.audioCodecs.orEmpty().containsAll(listOf("ac3", "eac3")))
        val faster = capabilitiesFrom(withoutPassthrough(box))
        assertFalse("ac3" in faster.audioCodecs.orEmpty())
        assertFalse("eac3" in faster.audioCodecs.orEmpty())
        assertFalse("eac3" in faster.hlsAudio.orEmpty())
        assertTrue(faster.audioCodecs.orEmpty().containsAll(listOf("aac", "opus")))
    }

    @Test fun nothingPassesThroughNothingChanges() {
        val phone = Found(audioMimes = setOf("audio/mp4a-latm", "audio/flac"))
        assertEquals(capabilitiesFrom(phone), capabilitiesFrom(withoutPassthrough(phone)))
    }
}
