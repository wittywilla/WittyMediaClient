// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.BrandColor
import com.wittywilla.wittymediaclient.net.BrandEditor
import com.wittywilla.wittymediaclient.net.BrandKinds
import com.wittywilla.wittymediaclient.net.BrandMarkChoice
import com.wittywilla.wittymediaclient.net.BrandName
import com.wittywilla.wittymediaclient.net.BrandPart
import com.wittywilla.wittymediaclient.net.BrandServerView
import com.wittywilla.wittymediaclient.net.BrandSurfaces
import com.wittywilla.wittymediaclient.net.LetterSelection
import com.wittywilla.wittymediaclient.net.LogoFile
import com.wittywilla.wittymediaclient.net.ThemeColour
import com.wittywilla.wittymediaclient.net.ThemeTokens
import com.wittywilla.wittymediaclient.net.ThemeTranslator
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The server's name editor (docs/plans/DESIGN-2.md 7.6 and 9): the rules apart from the screen.
class BrandEditorTest {
    private fun accented(d: com.wittywilla.wittymediaclient.net.BrandDraft) =
        d.parts.filter { it.color?.kind == BrandKinds.ACCENT }.joinToString("|") { it.text }

    @Test fun `words split as the server splits them`() {
        fun cut(name: String) = BrandEditor.words(name).joinToString("|") { name.substring(it.first, it.last + 1) }
        assertEquals("Witty|Media|Server", cut("WittyMediaServer"))
        assertEquals("Witty|Media|Server", cut("Witty Media Server"))
        assertEquals("Willow's|Movies", cut("Willow's Movies"))
        assertEquals("Kim's|TV|Room", cut("Kim's TV Room"))
        assertEquals("My|TV|Room", cut("MyTVRoom"))
        assertEquals("TVs", cut("TVs"))
        assertEquals("Movies|4K", cut("Movies4K"))
        assertEquals("HDTV", cut("HDTV"))
        assertEquals("Witty-|Media-|Server", cut("Witty-Media-Server"))
    }

    @Test fun `the default name is the server's automatic split`() {
        val d = BrandEditor.autoDraft(BrandName.DEFAULT)
        assertEquals("Media", accented(d))
        assertEquals(listOf("Witty", "Media", "Server"), d.parts.map { it.text })
        assertTrue(BrandEditor.matchesAuto(d))
        assertEquals("auto", BrandEditor.settings(d)["brandColouring"])
        assertEquals("", BrandEditor.settings(d)["brandSpans"])
        // the default name is sent as no name
        assertEquals("", BrandEditor.settings(d)["brandName"])
    }

    @Test fun `parts from the server give a look for each letter`() {
        val parts = listOf(
            BrandPart("Witty"),
            BrandPart("Media", color = BrandColor.fixed("#B4491F")),
            BrandPart("Server", color = BrandColor.gradient(listOf("#1e9be0", "#3ad29f"), 90), bold = true),
        )
        val d = BrandEditor.fromParts("WittyMediaServer", parts)
        assertEquals(16, d.size)
        assertEquals(BrandColor.FG, d.looks[0].color)
        assertEquals("#b4491f", d.looks[7].color.hex)
        assertTrue(d.looks[12].bold)
        assertEquals(parts.map { it.text }, d.parts.map { it.text })
        assertFalse(BrandEditor.matchesAuto(d))
    }

    @Test fun `an accent part from an older server reads as the accent kind`() {
        val d = BrandEditor.fromParts("A B", listOf(BrandPart("A "), BrandPart("B", accent = true)))
        assertEquals(BrandColor.ACCENT, d.looks[2].color)
    }

    @Test fun `spans are runs of the letters that are not plain, in order`() {
        var d = BrandEditor.plain("WittyMediaServer")
        d = BrandEditor.painted(d, (5..9).toSet(), BrandColor.fixed("#b4491f"))
        d = BrandEditor.bolded(d, (10..15).toSet(), true)
        val spans = d.spans
        assertEquals(2, spans.size)
        assertEquals(5, spans[0].from); assertEquals(10, spans[0].to)
        assertEquals(10, spans[1].from); assertEquals(16, spans[1].to); assertTrue(spans[1].bold)
        val settings = BrandEditor.settings(d)
        val parsed = json.parseToJsonElement(settings.getValue("brandSpans")).jsonArray
        assertEquals("static", parsed[0].jsonObject["color"]!!.jsonObject["kind"]!!.jsonPrimitive.content)
        assertEquals("#b4491f", parsed[0].jsonObject["color"]!!.jsonObject["hex"]!!.jsonPrimitive.content)
        assertEquals("true", parsed[1].jsonObject["bold"]!!.jsonPrimitive.content)
        // and back again
        val back = BrandEditor.fromSpans("WittyMediaServer", settings.getValue("brandSpans"))
        assertEquals(d.looks, back!!.looks)
    }

    @Test fun `a gradient is written with its stops and direction`() {
        val d = BrandEditor.presetGradient(BrandEditor.plain("Kim"), listOf("#0a6aa8", "#1e9be0", "#3aa84a"), 135)
        val o = json.parseToJsonElement(BrandEditor.spansJson(d.spans)).jsonArray[0].jsonObject["color"]!!.jsonObject
        assertEquals("gradient", o["kind"]!!.jsonPrimitive.content)
        assertEquals(3, o["stops"]!!.jsonArray.size)
        assertEquals("135", o["angle"]!!.jsonPrimitive.content)
    }

    @Test fun `plain and one colour are the servers quick modes`() {
        val plain = BrandEditor.presetPlain(BrandEditor.autoDraft("Witty Media"))
        val s = BrandEditor.settings(plain)
        assertEquals("one", s["brandColouring"]); assertEquals("", s["brandSpans"]); assertEquals("Witty Media", s["brandName"])
        val one = BrandEditor.presetOneColour(BrandEditor.plain("Witty Media"))
        assertTrue(BrandEditor.settings(one)["brandSpans"]!!.contains("accent"))
    }

    @Test fun `two tone puts the first word plain and the rest in the accent`() {
        val d = BrandEditor.presetTwoTone(BrandEditor.plain("WittyMediaServer"))
        assertEquals("MediaServer", accented(d))
        // a one-word name: its second half
        assertEquals("ty", accented(BrandEditor.presetTwoTone(BrandEditor.plain("Witty"))).let { it.takeLast(2) })
    }

    @Test fun `rainbow stays inside the servers forty spans even for a long name`() {
        val long = "A".repeat(10) + " " + "B".repeat(69)
        assertEquals(80, BrandEditor.length(long))
        val d = BrandEditor.presetRainbow(BrandEditor.plain(long))
        assertTrue(d.spans.size <= BrandEditor.MAX_SPANS)
        assertNull(BrandEditor.problem(d))
        val short = BrandEditor.presetRainbow(BrandEditor.plain("Witty"))
        assertEquals(5, short.spans.size)
        assertTrue(short.parts.all { it.color?.kind == BrandKinds.STATIC })
    }

    @Test fun `too many coloured pieces are refused with words`() {
        var d = BrandEditor.plain("A".repeat(80))
        for (i in 0 until 80 step 2) d = BrandEditor.painted(d, setOf(i), BrandColor.fixed("#ff0000"))
        assertEquals(40, d.spans.size)
        assertNull(BrandEditor.problem(d))
        d = BrandEditor.painted(d, setOf(1), BrandColor.ACCENT)
        assertTrue(d.tooManySpans)
        assertNotNull(BrandEditor.problem(d))
    }

    @Test fun `renaming keeps the looks of the letters that stay`() {
        val d = BrandEditor.presetOneColour(BrandEditor.plain("Kim"))
        val longer = BrandEditor.renamed(d, "Kim's")
        assertEquals(5, longer.size)
        assertEquals(BrandColor.ACCENT, longer.looks[2].color)
        assertEquals(BrandColor.FG, longer.looks[4].color)
        assertEquals(2, BrandEditor.renamed(d, "Ki").size)
        assertEquals(80, BrandEditor.length(BrandEditor.renamed(d, "x".repeat(200)).name))
    }

    @Test fun `a letter outside the basic plane stays one letter`() {
        assertEquals(3, BrandEditor.letters("a😀b").size)
        assertEquals(3, BrandEditor.length("a😀b"))
    }

    @Test fun `the selection takes letters, a range with Space and the arrows, and words`() {
        var sel = LetterSelection()
        sel = sel.tap(3).tap(5)
        assertEquals(setOf(3, 5), sel.picked)
        sel = sel.tap(3)
        assertEquals(setOf(5), sel.picked)
        // Space starts a range, arrows extend it, Space ends it
        var r = LetterSelection(cursor = 5).space()
        r = r.move(1, 16).move(1, 16).move(1, 16)
        assertEquals(setOf(5, 6, 7, 8), r.picked)
        r = r.move(-1, 16)
        assertEquals(setOf(5, 6, 7), r.picked)
        r = r.space().move(3, 16)
        assertEquals(setOf(5, 6, 7), r.picked)
        assertEquals((5..9).toSet(), LetterSelection().onlyWord(5..9).picked)
        assertEquals(setOf(0, 1), LetterSelection(picked = setOf(0, 1, 7)).within(3).picked)
        assertEquals(16, LetterSelection().all(16).picked.size)
        assertTrue(LetterSelection().all(3).none().picked.isEmpty())
    }

    @Test fun `focus landing on a letter moves the cursor and a started range follows`() {
        val r = LetterSelection(cursor = 2).space().moveTo(5, 16)
        assertEquals((2..5).toSet(), r.picked)
    }

    @Test fun `the mark shows the first letter, the initials or the owners own`() {
        assertEquals("W", BrandEditor.markShown("WittyMediaServer", BrandMarkChoice()))
        assertEquals("WMS", BrandEditor.markShown("WittyMediaServer", BrandMarkChoice(BrandEditor.MARK_INITIALS)))
        assertEquals("KM", BrandEditor.markShown("Kim's Movies", BrandMarkChoice(BrandEditor.MARK_INITIALS)))
        assertEquals("km", BrandEditor.markShown("x", BrandMarkChoice(BrandEditor.MARK_TEXT, "km")))
        assertEquals("W", BrandEditor.markShown("", BrandMarkChoice()))
    }

    @Test fun `the mark is saved as the server reads it`() {
        assertEquals("", BrandEditor.markJson(BrandMarkChoice()))
        assertEquals("""{"kind":"initials"}""", BrandEditor.markJson(BrandMarkChoice(BrandEditor.MARK_INITIALS)))
        assertEquals("""{"kind":"image"}""", BrandEditor.markJson(BrandMarkChoice(BrandEditor.MARK_IMAGE)))
        assertEquals("""{"kind":"text","text":"KM"}""", BrandEditor.markJson(BrandMarkChoice(BrandEditor.MARK_TEXT, " KM ")))
        assertEquals(BrandMarkChoice(BrandEditor.MARK_TEXT, "KM"), BrandEditor.markFrom("""{"kind":"text","text":"KM"}"""))
        assertEquals(BrandMarkChoice(), BrandEditor.markFrom(""))
        assertEquals(BrandMarkChoice(), BrandEditor.markFrom("not json"))
    }

    @Test fun `your own mark must be one or two characters`() {
        val base = BrandEditor.autoDraft("Kim")
        assertNotNull(BrandEditor.problem(base.copy(mark = BrandMarkChoice(BrandEditor.MARK_TEXT, ""))))
        assertNotNull(BrandEditor.problem(base.copy(mark = BrandMarkChoice(BrandEditor.MARK_TEXT, "abc"))))
        assertNull(BrandEditor.problem(base.copy(mark = BrandMarkChoice(BrandEditor.MARK_TEXT, "ab"))))
    }

    private fun theme(id: String, bg: String, panel: String, card: String, fg: String): com.wittywilla.wittymediaclient.net.AppTheme =
        ThemeTranslator.translate(
            ThemeTokens(id = id, name = id, scheme = if (id == "light") "light" else "dark", colors = mapOf("bg" to bg, "bg-2" to panel, "bg-3" to card, "fg" to fg)),
        )

    @Test fun `a fixed colour under 4_5 to 1 on a surface is warned about, in each theme`() {
        val dark = BrandSurfaces.of(theme("midnight", "#0f1115", "#171a21", "#1f232c", "#e8eaf0"))
        val light = BrandSurfaces.of(theme("light", "#ffffff", "#f7f8fa", "#f0f1f5", "#0e1013"))
        var d = BrandEditor.plain("WittyMediaServer")
        d = BrandEditor.painted(d, (5..9).toSet(), BrandColor.fixed("#b4491f"))
        val warnings = BrandEditor.contrast(d, listOf(dark, light))
        // rust on the dark surfaces is about 3 to 1; on white it passes
        assertTrue(warnings.isNotEmpty())
        assertTrue(warnings.all { it.text == "Media" && it.theme == "midnight" })
        assertTrue(warnings.all { it.ratio < 4.5 })
        assertNotNull(warnings.first().readable)
        assertTrue(ThemeColour.parse(warnings.first().readable)!!.contrast(ThemeColour.parse("#0f1115")!!) >= 4.5)
        assertTrue(warnings.first().words.contains("to 1"))
    }

    @Test fun `parts that follow the theme are never warned about`() {
        val dark = BrandSurfaces.of(theme("midnight", "#0f1115", "#171a21", "#1f232c", "#e8eaf0"))
        val d = BrandEditor.presetOneColour(BrandEditor.plain("Kim"))
        assertTrue(BrandEditor.contrast(d, listOf(dark)).isEmpty())
        val tok = BrandEditor.painted(d, setOf(0), BrandColor.token("danger"))
        assertTrue(BrandEditor.contrast(tok, listOf(dark)).isEmpty())
    }

    @Test fun `every stop of a gradient is checked`() {
        val dark = BrandSurfaces.of(theme("midnight", "#0f1115", "#171a21", "#1f232c", "#e8eaf0"))
        val d = BrandEditor.presetGradient(BrandEditor.plain("Kim"), listOf("#ffffff", "#101820"))
        val w = BrandEditor.contrast(d, listOf(dark))
        assertTrue(w.isNotEmpty())
        assertTrue(w.all { it.hex == "#101820" })
    }

    @Test fun `the theme token names the server uses resolve in a theme`() {
        val t = theme("midnight", "#0f1115", "#171a21", "#1f232c", "#e8eaf0")
        assertEquals(t.ok, BrandEditor.tokenColour("ok", t))
        assertEquals(t.accentText, BrandEditor.tokenColour("accent-text", t))
        assertEquals(t.accentText, BrandEditor.tokenColour("accentText", t))
        assertEquals(t.warn, BrandEditor.tokenColour("warn", t))
        assertEquals(t.text, BrandEditor.tokenColour("fg", t))
        assertNull(BrandEditor.tokenColour("nonsense", t))
    }

    @Test fun `a gradient runs across the letters from the first stop to the last`() {
        val c = BrandEditor.gradientLetters(listOf("#000000", "#ffffff"), 90, 5)
        assertEquals(5, c.size)
        assertEquals("#000000", c.first().hex)
        assertEquals("#ffffff", c.last().hex)
        val back = BrandEditor.gradientLetters(listOf("#000000", "#ffffff"), 270, 5)
        assertEquals("#ffffff", back.first().hex)
        val three = BrandEditor.gradientLetters(listOf("#ff0000", "#00ff00", "#0000ff"), 90, 3)
        assertEquals("#00ff00", three[1].hex)
        assertTrue(BrandEditor.gradientLetters(emptyList(), 90, 3).isEmpty())
    }

    @Test fun `hue saturation and value round trip a colour`() {
        for (hex in listOf("#b4491f", "#1e9be0", "#ffffff", "#000000", "#3ddc84")) {
            assertEquals(hex, BrandEditor.Hsv.of(hex).hex)
        }
        assertEquals("#ff0000", BrandEditor.Hsv(0.0, 1.0, 1.0).hex)
        assertEquals("#00ff00", BrandEditor.Hsv(120.0, 1.0, 1.0).hex)
    }

    @Test fun `hex colours are normalised`() {
        assertEquals("#b4491f", BrandEditor.normalHex("B4491F"))
        assertEquals("#aabbcc", BrandEditor.normalHex("#ABC"))
        assertNull(BrandEditor.normalHex("#12345"))
        assertNull(BrandEditor.normalHex("zzzzzz"))
    }

    @Test fun `the server's brand in GET theme is read with its colours, mark and warnings`() {
        val theme = json.parseToJsonElement(
            """{"brand":{"parts":[{"text":"Witty","color":{"kind":"fg"}},{"text":"Media","color":{"kind":"static","hex":"#b4491f"},"bold":true}],
               "mark":{"kind":"text","text":"WM","shown":"WM"},"warnings":[{"text":"Media","surface":"bg2","ratio":3.1,"need":4.5}]}}""",
        ).jsonObject
        val v = BrandServerView.from(theme)!!
        assertEquals(2, v.parts.size)
        assertEquals("#b4491f", v.parts[1].color!!.hex)
        assertTrue(v.parts[1].bold)
        assertEquals(BrandMarkChoice("text", "WM"), v.mark)
        assertEquals("WM", v.shown)
        assertEquals(1, v.warnings.size)
        assertTrue(v.warnings[0].words.contains("side menu and bars"))
        assertNull(BrandServerView.from(json.parseToJsonElement("{}").jsonObject))
    }

    @Test fun `a status with coloured parts keeps their kinds`() {
        val s = json.decodeFromString<com.wittywilla.wittymediaclient.net.ServerStatus>(
            """{"brandName":"A B","brandParts":[{"text":"A "},{"text":"B","accent":true,"color":{"kind":"token","token":"ok"}}]}""",
        )
        assertEquals("ok", s.brandParts[1].color!!.token)
        assertEquals(BrandKinds.TOKEN, s.brandParts[1].color!!.kind)
        assertEquals(s.brandParts, BrandName.parts("A B", s.brandParts))
    }

    // A logo is checked before it is sent: the server's own rule is PNG or JPEG, at most 2 MB, 16 to 4096 a side.
    private fun png(w: Int, h: Int): ByteArray {
        val b = ByteArray(33)
        byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 0x0d, 0x0a, 0x1a, 0x0a).copyInto(b)
        byteArrayOf(0, 0, 0, 13, 'I'.code.toByte(), 'H'.code.toByte(), 'D'.code.toByte(), 'R'.code.toByte()).copyInto(b, 8)
        for (i in 0..3) b[16 + i] = (w shr (24 - 8 * i)).toByte()
        for (i in 0..3) b[20 + i] = (h shr (24 - 8 * i)).toByte()
        return b
    }

    private fun jpeg(w: Int, h: Int): ByteArray = byteArrayOf(
        0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0, 4, 0, 0,
        0xFF.toByte(), 0xC0.toByte(), 0, 11, 8, (h shr 8).toByte(), h.toByte(), (w shr 8).toByte(), w.toByte(), 1, 1, 0x11, 0,
    )

    @Test fun `a logo's kind and size are read from its own header`() {
        assertEquals(LogoFile.Info(LogoFile.Kind.Png, 512, 512), LogoFile.read(png(512, 512)))
        assertEquals(LogoFile.Info(LogoFile.Kind.Jpeg, 300, 200), LogoFile.read(jpeg(300, 200)))
        assertTrue(LogoFile.read(png(512, 512))!!.square)
        assertFalse(LogoFile.read(jpeg(300, 200))!!.square)
        assertNull(LogoFile.read("GIF89a".toByteArray()))
    }

    @Test fun `a logo that the server would refuse is refused first`() {
        assertNull(LogoFile.problem(png(512, 512)))
        assertNull(LogoFile.problem(jpeg(64, 64)))
        assertNotNull(LogoFile.problem(png(8, 8)))
        assertNotNull(LogoFile.problem(png(5000, 100)))
        assertNotNull(LogoFile.problem("<svg/>".toByteArray()))
        assertNotNull(LogoFile.problem(ByteArray(BrandEditor.MAX_LOGO_BYTES + 1)))
    }
}
