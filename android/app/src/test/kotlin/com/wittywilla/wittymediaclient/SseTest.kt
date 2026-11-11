// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.SseParser
import com.wittywilla.wittymediaclient.net.errorCode
import com.wittywilla.wittymediaclient.net.sseBackoffMs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SseTest {
    private fun feed(text: String): List<SseEvent> {
        val parser = SseParser()
        return text.split("\n").mapNotNull { parser.line(it.removeSuffix("\r")) }
    }

    @Test
    fun anEventIsItsNameAndItsData() {
        val got = feed("event: hello\ndata: {\"v\":1}\n\nevent: command\ndata: {\"id\":\"c1\"}\n\n")
        assertEquals(listOf(SseEvent("hello", "{\"v\":1}"), SseEvent("command", "{\"id\":\"c1\"}")), got)
    }

    @Test
    fun keepAlivesAndUnknownFieldsAreSkipped() {
        val got = feed(": still here\n\nid: 7\nretry: 100\nevent: room\ndata: {}\n\n: still here\n\n")
        assertEquals(listOf(SseEvent("room", "{}")), got)
    }

    @Test
    fun severalDataLinesJoinAndCarriageReturnsGo() {
        assertEquals(listOf(SseEvent("message", "a\nb")), feed("data: a\r\ndata: b\r\n\r\n"))
    }

    @Test
    fun anEventNameWithNoDataIsNothing() {
        assertEquals(emptyList<SseEvent>(), feed("event: bye\n\n"))
        val parser = SseParser()
        assertNull(parser.line("event: x"))
    }

    @Test
    fun theNameDoesNotLeakIntoTheNextEvent() {
        assertEquals(listOf(SseEvent("a", "1"), SseEvent("message", "2")), feed("event: a\ndata: 1\n\ndata: 2\n\n"))
    }

    @Test
    fun waitsGrowAndStopGrowing() {
        assertEquals(listOf(1000L, 2000L, 4000L, 8000L, 16000L, 30000L, 30000L), (0..6).map { sseBackoffMs(it) })
        assertEquals(1000L, sseBackoffMs(-3))
    }

    @Test
    fun aRefusalsCodeIsRead() {
        assertEquals("screen-time", errorCode("{\"error\":\"Time's up\",\"code\":\"screen-time\"}"))
        assertEquals("", errorCode("{\"error\":\"no\"}"))
        assertEquals("", errorCode("<html>"))
        assertEquals("offline", ApiError(409, "x", code = "offline").code)
    }
}
