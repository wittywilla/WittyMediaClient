// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.BrandName
import com.wittywilla.wittymediaclient.net.BrandPart
import com.wittywilla.wittymediaclient.net.ServerStatus
import com.wittywilla.wittymediaclient.net.ThemeTokens
import com.wittywilla.wittymediaclient.net.ThemeTranslator
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The custom coloured server name has to survive every frame: its parts come from /api/status and are drawn in brandAccent.
class BrandNameTest {
    @Test fun `the server's coloured parts are kept in order`() {
        val parts = listOf(BrandPart("Willow's "), BrandPart("Movies", accent = true))
        assertEquals(parts, BrandName.parts("Willow's Movies", parts))
        assertEquals("Willow's Movies", BrandName.plain("Willow's Movies", parts))
    }

    @Test fun `parts that do not add up to the name are not trusted`() {
        val parts = listOf(BrandPart("Other", accent = true))
        assertEquals(listOf(BrandPart("Willow's Movies")), BrandName.parts("Willow's Movies", parts))
    }

    @Test fun `no name draws the default with Media in the accent`() {
        val p = BrandName.parts("", emptyList())
        assertEquals("WittyMediaServer", p.joinToString("") { it.text })
        assertEquals(listOf(false, true, false), p.map { it.accent })
    }

    @Test fun `a status reads brandParts and an older one without them still reads`() {
        val s = json.decodeFromString<ServerStatus>("""{"name":"x","brandName":"A B","brandParts":[{"text":"A "},{"text":"B","accent":true}]}""")
        assertEquals(listOf(BrandPart("A "), BrandPart("B", true)), s.brandParts)
        val old = json.decodeFromString<ServerStatus>("""{"name":"x","brandName":"A B"}""")
        assertTrue(old.brandParts.isEmpty())
    }

    @Test fun `the theme's brandAccent and focus are read, else derived`() {
        val given = ThemeTranslator.translate(ThemeTokens(id = "t", colors = mapOf("bg" to "#000000", "fg" to "#ffffff", "accent" to "#7955ff", "accent-text" to "#9174ff", "brandAccent" to "#ffcc00", "focus" to "#00ff88")))
        assertEquals("#ffcc00", given.brandAccent.hex)
        assertEquals("#00ff88", given.focus.hex)
        val derived = ThemeTranslator.translate(ThemeTokens(id = "t", colors = mapOf("bg" to "#000000", "fg" to "#ffffff", "accent" to "#7955ff", "accent-text" to "#9174ff")))
        assertEquals(derived.accentText, derived.brandAccent)
        assertEquals(derived.text, derived.focus)
    }
}
