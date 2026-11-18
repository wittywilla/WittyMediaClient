// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.ThemeColour
import com.wittywilla.wittymediaclient.net.ThemeList
import com.wittywilla.wittymediaclient.net.ThemeMaker
import com.wittywilla.wittymediaclient.net.ThemeMakerInput
import com.wittywilla.wittymediaclient.net.ThemeTokens
import com.wittywilla.wittymediaclient.net.ThemeTranslator
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.ui.ThemeFile
import com.wittywilla.wittymediaclient.ui.asTokens
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// docs/APP-DESIGN.md, Themes: the translation and the theme maker, as Apple's ThemeTests check them.
class ThemeTest {
    // The server's rule for words over a picture (its PR 444): each theme says how solid the page-colour scrim behind a
    // hero's words is, and the app draws with it, from the server's tokens and from the bundled themes alike.
    @Test
    fun theHeroScrimComesFromTheTheme() {
        assertEquals(0.86, ThemeTranslator.translate(ThemeTokens(id = "x", tv = ThemeTokens.Tv(heroScrim = 0.86))).heroScrim, 1e-9)
        assertEquals(ThemeTranslator.DEFAULT_HERO_SCRIM, ThemeTranslator.translate(ThemeTokens(id = "x")).heroScrim, 1e-9)
        assertEquals(ThemeTranslator.DEFAULT_HERO_SCRIM, ThemeTranslator.translate(ThemeTokens(id = "x", tv = ThemeTokens.Tv(heroScrim = 4.0))).heroScrim, 1e-9)
        val file = json.decodeFromString(ThemeFile.serializer(), File("../../shared/data/themes.json").readText())
        for (theme in file.themes) {
            val scrim = theme.heroScrim
            assertTrue(theme.id, scrim != null && scrim > 0.5 && scrim <= 1.0)
            val drawn = ThemeTranslator.translate(theme.asTokens())
            assertEquals(theme.id, scrim!!, drawn.heroScrim, 1e-9)
            assertEquals(theme.id, ThemeColour.parse(theme.colours.focus), drawn.focus)
        }
    }

    @Test
    fun theThemeMakerMatchesTheWebsite() {
        val examples = json.parseToJsonElement(File("../../shared/data/theme-maker-examples.json").readText()).jsonObject
        val cases = examples.getValue("cases").jsonArray
        assertTrue(cases.size >= 6)
        for (case in cases) {
            val input = json.decodeFromJsonElement(ThemeMakerInput.serializer(), case.jsonObject.getValue("input"))
            val want = case.jsonObject.getValue("output").jsonObject
            val made = ThemeMaker.make(input)
            assertEquals(input.name, want.getValue("radius").jsonPrimitive.content.toInt(), made.radius)
            assertEquals(input.name, want.getValue("adjusted").jsonPrimitive.content.toBoolean(), made.adjusted)
            val vars = (want.getValue("vars") as JsonObject).mapValues { it.value.jsonPrimitive.content }
            assertEquals(input.name, vars, made.vars)
        }
    }

    @Test
    fun coloursAreReadAsTheWebWritesThem() {
        assertEquals("#aabbcc", ThemeColour.parse("#abc")!!.hex)
        assertEquals("#e8eaf01a", ThemeColour.parse("#E8EAF01A")!!.hex)
        assertNull(ThemeColour.parse("rgb(1,2,3)"))
        assertNull(ThemeColour.parse("#12345"))
    }

    @Test
    fun aThemeComesThroughWithItsOwnColoursAndCorners() {
        val tokens = ThemeTokens(
            id = "midnight", name = "Midnight", scheme = "dark",
            colors = mapOf("bg" to "#0B1120", "bg-2" to "#111A2E", "fg" to "#E6ECF7", "accent" to "#2F6FED", "accent-fg" to "#FFFFFF"),
            lengths = mapOf("radius" to kotlinx.serialization.json.JsonPrimitive(14)),
        )
        val t = ThemeTranslator.translate(tokens)
        assertEquals("#0b1120", t.background.hex)
        assertEquals("#111a2e", t.panel.hex)
        assertEquals(14.0, t.radius, 0.0)
        assertFalse(t.isLight)
        // Missing roles fall back as the table says: border is text at 10%, control at 20%.
        assertEquals("#e6ecf71a", t.border.hex)
        assertEquals("#e6ecf733", t.control.hex)
        assertEquals(t.accent, t.accentText)
    }

    @Test
    fun aThemeWithOnlyAPreviewStillLooksLikeItself() {
        val preview = ThemeList.Preview(bg = "#f6f2ea", surface = "#ece6da", text = "#221d16", accent = "#a14b1b")
        val t = ThemeTranslator.translate(ThemeTokens(id = "paper"), preview)
        assertEquals("#f6f2ea", t.background.hex)
        assertEquals("#ece6da", t.card.hex)
        assertTrue(t.isLight)
        assertEquals(10.0, t.radius, 0.0)
        // White doesn't read on that brown as well as ink does.
        assertEquals(ThemeColour.WHITE, t.onAccent)
    }

    @Test
    fun anOddRadiusIsLeftOut() {
        val tokens = json.decodeFromString<ThemeTokens>("""{"id":"x","lengths":{"radius":"12","sidebar":"wide"}}""")
        assertEquals(12.0, ThemeTranslator.translate(tokens).radius, 0.0)
        val wild = json.decodeFromString<ThemeTokens>("""{"id":"x","lengths":{"radius":400}}""")
        assertEquals(10.0, ThemeTranslator.translate(wild).radius, 0.0)
    }

    @Test
    fun aPersonsOwnLookIsTheMakersColours() {
        val input = ThemeMakerInput(name = "Mine", scheme = "light", accent = "#e0457b", tint = "#e0457b", corners = "round")
        val t = ThemeTranslator.translateMade(input)
        assertEquals(ThemeMaker.make(input).vars.getValue("bg"), t.background.hex)
        assertEquals(18.0, t.radius, 0.0)
        assertTrue(t.isLight)
    }
}
