// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.ConnectRun
import com.wittywilla.wittymediaclient.net.ConnectSteps
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The steps of connecting from away and why one fails: the server's file (shared/data/connect-steps.json), and its
// cases, which the server and every app answer the same way.
class ConnectStepsTest {
    private val text = File("../../shared/data/connect-steps.json").readText()
    private val steps = ConnectSteps.parse(text)

    @Test
    fun answersEveryCaseInTheSharedFile() {
        val cases = json.parseToJsonElement(text).jsonObject["cases"]!!.jsonArray
        assertTrue(cases.size >= 10)
        for (c in cases) {
            val o = c.jsonObject
            fun s(k: String) = o[k]!!.jsonPrimitive.content
            val f = steps.classify(s("reason"), s("text"), s("step"))
            assertEquals("code for $o", s("code"), f.code)
            assertEquals("step for $o", s("at"), f.step)
            assertTrue(f.say.isNotEmpty() && f.next.isNotEmpty())
        }
        assertEquals(listOf("read", "found", "secure", "signin"), steps.steps.map { it.id })
    }

    @Test
    fun aRunShowsTicksUpToTheFailedStepAndNothingAfter() {
        val run = ConnectRun("invite", "12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz")
        run.pass("read")
        run.pass("found")
        run.fail(steps.classify("", "the server was found, but a direct connection through both routers couldn't be made", "secure"))
        assertEquals(listOf("ok", "ok", "fail", "skip"), run.states(steps.steps).map { it.second })

        // A failure at a later step than the last one passed still ticks the ones before it.
        val code = ConnectRun("code")
        code.fail(steps.of("expired", "signin"))
        assertEquals(listOf("ok", "ok", "ok", "fail"), code.states(steps.steps).map { it.second })

        // A time-out while signing in is shown on signing in, not on finding the server, which got through.
        val late = ConnectRun("invite")
        listOf("read", "found", "secure").forEach(late::pass)
        assertEquals("signin", late.fail(steps.classify("", "the server didn't answer in time", "signin")).step)
        // A connection that turned out unusable is shown on the step it was counted on.
        val slow = ConnectRun("invite")
        listOf("read", "found", "secure").forEach(slow::pass)
        assertEquals("secure", slow.fail(steps.of("slow-path", "secure")).step)
        assertEquals(listOf("ok", "ok", "fail", "skip"), slow.states(steps.steps).map { it.second })
    }

    @Test
    fun detailsHoldNoSecrets() {
        val run = ConnectRun("invite", "12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz")
        run.note("opening wittymedia://p2p/12D3KooWAbCd?s=SuperSecretInvite123&n=Home")
        run.note("Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789")
        run.fail(steps.classify("", "token=abcdef123456 the server wasn't found", "found"))
        val out = run.details(steps.steps, "WittyMediaClient 0.6.3", "Pixel")
        assertFalse(out, out.contains("SuperSecretInvite123"))
        assertFalse(out, out.contains("abcdefghijklmnopqrstuvwxyz0123456789"))
        assertFalse(out, out.contains("abcdef123456"))
        assertTrue(out, out.contains("not-found") && out.contains("[!] Server found") && out.contains("[x] Code or link read"))
        assertFalse("the whole server ID isn't needed", out.contains("12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz"))
    }
}
