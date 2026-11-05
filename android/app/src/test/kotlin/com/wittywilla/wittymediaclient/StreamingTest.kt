package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.player.Streaming
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamingTest {
    @Test
    fun anythingUnknownFollowsTheServer() {
        assertEquals("auto", Streaming.clean(null))
        assertEquals("auto", Streaming.clean(""))
        assertEquals("auto", Streaming.clean("fast"))
        assertEquals("robust", Streaming.clean("robust"))
        assertEquals("standard", Streaming.clean("standard"))
    }

    @Test
    fun measuresOnlyWhenRobustCanApply() {
        assertTrue(Streaming.measures("robust", ""))
        assertTrue(Streaming.measures("robust", "standard"))
        assertTrue(Streaming.measures("auto", "robust"))
        assertFalse(Streaming.measures("auto", "standard"))
        assertFalse(Streaming.measures("auto", ""))
        assertFalse(Streaming.measures("standard", "robust"))
    }

    @Test
    fun kilobitsASecond() {
        // 500 KB in a second is 4000 kbit/s.
        assertEquals(4000, Streaming.kbps(500_000, 1000))
        assertEquals(8000, Streaming.kbps(500_000, 500))
    }

    @Test
    fun tooLittleTellsNothing() {
        assertNull(Streaming.kbps(10_000, 1000))
        assertNull(Streaming.kbps(500_000, 0))
    }
}
