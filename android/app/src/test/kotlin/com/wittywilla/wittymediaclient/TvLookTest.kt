package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.TvAppColours
import com.wittywilla.wittymediaclient.net.TvColours
import com.wittywilla.wittymediaclient.net.TvLook
import com.wittywilla.wittymediaclient.net.TvLookChoice
import com.wittywilla.wittymediaclient.net.TvSaved
import com.wittywilla.wittymediaclient.net.TvShape
import com.wittywilla.wittymediaclient.net.TvTheme
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The same checks as Apple's TvLookTests: WittyTV's looks come out as the server's own code works them out.
class TvLookTest {
    // What themeTokens in the server's web/src/pages/tv/tvThemes.ts works out for these, every token, with its two
    // washes (rgb with an opacity) written as #rrggbbaa.
    private val vectors = """[{"id":"classic","over":{},"want":{"bg":"#06164a","panel":"#0a2270","panel2":"#123391","head":"#16389e","ch":"#0c2a84","dim":"#0d2a7c","line":"#4967b5","text":"#ffffff","soft":"#c3c7d4","cell":"#1a43b8","cell2":"#143594","cellText":"#ffffff","cellSoft":"#c8d2ee","live":"#0f6a7f","live2":"#0b5466","liveText":"#ffffff","liveSoft":"#d9e7eb","hi":"#ffd60a","hiText":"#000000","accent":"#ffd60a","accentText":"#000000","keyA":"#ffd60a","keyB":"#4ce06a","keyC":"#7fc7ff","keyText":"#000000","err":"#ffe08a","lite":"#ffffff29","shade":"#00000024"}},{"id":"satellite","over":{},"want":{"bg":"#07090d","panel":"#10131a","panel2":"#22262f","head":"#14171e","ch":"#10131a","dim":"#0c0e13","line":"#6a7181","text":"#ffffff","soft":"#c3c4c5","cell":"#14171e","cell2":"#14171e","cellText":"#ffffff","cellSoft":"#c7c7c9","live":"#2e2300","live2":"#2e2300","liveText":"#ffffff","liveSoft":"#cdcac2","hi":"#ffb300","hiText":"#000000","accent":"#ffb300","accentText":"#000000","keyA":"#ffb300","keyB":"#5fd47d","keyC":"#8cc6ff","keyText":"#000000","err":"#ffd27a","lite":"#ffb3002e","shade":"#00000024"}},{"id":"teletext","over":{},"want":{"bg":"#000000","panel":"#000000","panel2":"#0000d0","head":"#0000d0","ch":"#000000","dim":"#000000","line":"#006e6e","text":"#ffffff","soft":"#c2c2c2","cell":"#000000","cell2":"#000000","cellText":"#ffffff","cellSoft":"#c2c2c2","live":"#003c00","live2":"#003c00","liveText":"#ffffff","liveSoft":"#c2d0c2","hi":"#00ffff","hiText":"#000000","accent":"#ffff00","accentText":"#000000","keyA":"#ff5a5a","keyB":"#00ff00","keyC":"#ffff00","keyText":"#000000","err":"#ff9d9d","lite":"#00ff0038","shade":"#00000024"}},{"id":"listings","over":{},"want":{"bg":"#f5f0e4","panel":"#f5f0e4","panel2":"#eae3d2","head":"#f5f0e4","ch":"#f5f0e4","dim":"#efe9db","line":"#857f72","text":"#1b1813","soft":"#4f4c45","cell":"#f5f0e4","cell2":"#f5f0e4","cellText":"#1b1813","cellSoft":"#4f4c45","live":"#ebdfb8","live2":"#ebdfb8","liveText":"#1b1813","liveSoft":"#4d483b","hi":"#1b1813","hiText":"#ffffff","accent":"#9c1c12","accentText":"#ffffff","keyA":"#1b1813","keyB":"#1b1813","keyC":"#1b1813","keyText":"#ffffff","err":"#9c1c12","lite":"#9c1c121f","shade":"#ffffff33"}},{"id":"classic","over":{"bg":"#f0f0f0"},"want":{"bg":"#f0f0f0","panel":"#e2e2e2","panel2":"#d3d3d3","head":"#cecece","ch":"#e2e2e2","dim":"#e2e2e2","line":"#868686","text":"#000000","soft":"#3a3a3a","cell":"#cecece","cell2":"#d4d4d4","cellText":"#000000","cellSoft":"#313131","live":"#d9d0a3","live2":"#ddd6b1","liveText":"#000000","liveSoft":"#343227","hi":"#9c8407","hiText":"#000000","accent":"#605104","accentText":"#ffffff","keyA":"#605104","keyB":"#605104","keyC":"#605104","keyText":"#ffffff","err":"#605104","lite":"#0000001a","shade":"#00000024"}},{"id":"modern","over":{"bg":"#102030","accent":"#ffb300"},"want":{"bg":"#102030","panel":"#1e2d3c","panel2":"#2d3b49","head":"#313f4d","ch":"#1e2d3c","dim":"#1e2d3c","line":"#616c76","text":"#ffffff","soft":"#c6c9cd","cell":"#313f4d","cell2":"#2b3948","cellText":"#ffffff","cellSoft":"#ced1d4","live":"#5e593c","live2":"#504f3a","liveText":"#ffffff","liveSoft":"#d8d7d0","hi":"#ffffff","hiText":"#000000","accent":"#ffb300","accentText":"#000000","keyA":"#ffb300","keyB":"#ffb300","keyC":"#ffb300","keyText":"#000000","err":"#ffb300","lite":"#ffffff29","shade":"#00000024"}},{"id":"listings","over":{"hi":"#0044cc"},"want":{"bg":"#f5f0e4","panel":"#f5f0e4","panel2":"#eae3d2","head":"#f5f0e4","ch":"#f5f0e4","dim":"#efe9db","line":"#857f72","text":"#1b1813","soft":"#4f4c45","cell":"#f5f0e4","cell2":"#f5f0e4","cellText":"#1b1813","cellSoft":"#4f4c45","live":"#ebdfb8","live2":"#ebdfb8","liveText":"#1b1813","liveSoft":"#4d483b","hi":"#0044cc","hiText":"#ffffff","accent":"#9c1c12","accentText":"#ffffff","keyA":"#1b1813","keyB":"#1b1813","keyC":"#1b1813","keyText":"#ffffff","err":"#9c1c12","lite":"#9c1c121f","shade":"#ffffff33"}},{"id":"satellite","over":{"cell":"#202020","text":"#eeeeee"},"want":{"bg":"#07090d","panel":"#10131a","panel2":"#22262f","head":"#14171e","ch":"#10131a","dim":"#0c0e13","line":"#6f7480","text":"#eeeeee","soft":"#b7b7b8","cell":"#202020","cell2":"#1c1c1d","cellText":"#eeeeee","cellSoft":"#bdbdbd","live":"#514019","live2":"#443617","liveText":"#eeeeee","liveSoft":"#c8c4bb","hi":"#ffb300","hiText":"#000000","accent":"#ffb300","accentText":"#000000","keyA":"#ffb300","keyB":"#5fd47d","keyC":"#8cc6ff","keyText":"#000000","err":"#ffd27a","lite":"#ffb3002e","shade":"#00000024"}},{"id":"custom","over":{"bg":"#000000","cell":"#2a2a2a","live":"#3a3a3a","hi":"#ffffff","accent":"#c9a2ff"},"want":{"bg":"#000000","panel":"#0f0f0f","panel2":"#1f1f1f","head":"#242424","ch":"#0f0f0f","dim":"#0f0f0f","line":"#707070","text":"#ffffff","soft":"#c2c2c2","cell":"#2a2a2a","cell2":"#222222","cellText":"#ffffff","cellSoft":"#cccccc","live":"#3a3a3a","live2":"#303030","liveText":"#ffffff","liveSoft":"#d0d0d0","hi":"#ffffff","hiText":"#000000","accent":"#c9a2ff","accentText":"#000000","keyA":"#c9a2ff","keyB":"#c9a2ff","keyC":"#c9a2ff","keyText":"#000000","err":"#c9a2ff","lite":"#ffffff29","shade":"#00000024"}},{"id":"outline","over":{"live":"#ff0000"},"want":{"bg":"#0f1115","panel":"#16181d","panel2":"#23262d","head":"#16181d","ch":"#16181d","dim":"#16181d","line":"#656973","text":"#ffffff","soft":"#c5c6c7","cell":"#23262d","cell2":"#23262d","cellText":"#ffffff","cellSoft":"#cacbcd","live":"#ff0000","live2":"#ed0202","liveText":"#000000","liveSoft":"#000000","hi":"#7955ff","hiText":"#ffffff","accent":"#b39dff","accentText":"#000000","keyA":"#b39dff","keyB":"#b39dff","keyC":"#b39dff","keyText":"#000000","err":"#b39dff","lite":"#ffffff29","shade":"#ffffff33"}},{"id":"teletext","over":{"accent":"#000000"},"want":{"bg":"#000000","panel":"#000000","panel2":"#0000d0","head":"#0000d0","ch":"#000000","dim":"#000000","line":"#006e6e","text":"#ffffff","soft":"#c2c2c2","cell":"#000000","cell2":"#000000","cellText":"#ffffff","cellSoft":"#c2c2c2","live":"#000000","live2":"#000000","liveText":"#ffffff","liveSoft":"#c2c2c2","hi":"#00ffff","hiText":"#000000","accent":"#adadad","accentText":"#000000","keyA":"#adadad","keyB":"#adadad","keyC":"#adadad","keyText":"#000000","err":"#ff9d9d","lite":"#00ff0038","shade":"#00000024"}},{"id":"compact","over":{"bg":"#ffffff"},"want":{"bg":"#ffffff","panel":"#f0f0f0","panel2":"#e0e0e0","head":"#dbdbdb","ch":"#f0f0f0","dim":"#f0f0f0","line":"#8f8f8f","text":"#000000","soft":"#3d3d3d","cell":"#dbdbdb","cell2":"#e1e1e1","cellText":"#000000","cellSoft":"#353535","live":"#d2cde3","live2":"#dad6e8","liveText":"#000000","liveSoft":"#323136","hi":"#7955ff","hiText":"#ffffff","accent":"#5e5285","accentText":"#ffffff","keyA":"#5e5285","keyB":"#5e5285","keyC":"#5e5285","keyText":"#ffffff","err":"#5e5285","lite":"#0000001a","shade":"#ffffff33"}},{"id":"bigpicture","over":{"hi":"#ff00ff","cell":"#334455"},"want":{"bg":"#0f1115","panel":"#16181d","panel2":"#23262d","head":"#16181d","ch":"#16181d","dim":"#16181d","line":"#656973","text":"#ffffff","soft":"#c5c6c7","cell":"#334455","cell2":"#2d3b49","cellText":"#ffffff","cellSoft":"#ced2d6","live":"#4f587a","live2":"#434b68","liveText":"#ffffff","liveSoft":"#d5d7df","hi":"#ff00ff","hiText":"#000000","accent":"#b39dff","accentText":"#000000","keyA":"#b39dff","keyB":"#b39dff","keyC":"#b39dff","keyText":"#000000","err":"#b39dff","lite":"#ffffff29","shade":"#00000024"}}]"""

    private fun all(c: TvColours) = mapOf(
        "bg" to c.bg, "panel" to c.panel, "panel2" to c.panel2, "head" to c.head, "ch" to c.ch, "dim" to c.dim, "line" to c.line, "text" to c.text, "soft" to c.soft,
        "cell" to c.cell, "cell2" to c.cell2, "cellText" to c.cellText, "cellSoft" to c.cellSoft, "live" to c.live, "live2" to c.live2, "liveText" to c.liveText,
        "liveSoft" to c.liveSoft, "hi" to c.hi, "hiText" to c.hiText, "accent" to c.accent, "accentText" to c.accentText, "keyA" to c.keyA, "keyB" to c.keyB,
        "keyC" to c.keyC, "keyText" to c.keyText, "err" to c.err, "lite" to c.lite, "shade" to c.shade,
    )

    private fun saved(text: String) = TvSaved.from(json.parseToJsonElement(text))

    @Test
    fun coloursMatchTheServersOwnCode() {
        for (v in json.parseToJsonElement(vectors) as JsonArray) {
            val o = v.jsonObject
            val id = o.getValue("id").jsonPrimitive.content
            val over = o.getValue("over").jsonObject.mapValues { it.value.jsonPrimitive.content }
            val got = all(TvLook.colours(id, over, TvAppColours.fallback))
            for ((name, want) in o.getValue("want").jsonObject) assertEquals("$id $over: $name", want.jsonPrimitive.content, got[name])
        }
    }

    @Test
    fun aThemeThatFollowsTheAppHasTheAppsColours() {
        val app = TvAppColours.fallback
        val modern = TvLook.colours("modern", emptyMap(), app)
        assertEquals(app.bg, modern.bg)
        assertEquals(app.bg3, modern.panel2)
        assertEquals(app.bg4, modern.live)
        assertEquals(app.fg, modern.hi)
        assertEquals(app.bg, modern.hiText)
        assertEquals(app.bg, modern.accentText)
        assertEquals(app.danger, modern.err)
        assertEquals("the accent at 24%", "#7955ff3d", modern.lite)
        val outline = TvLook.colours("outline", emptyMap(), app)
        assertEquals(app.accent, outline.hi)
        assertEquals(app.accentFg, outline.hiText)
        assertEquals(app.accent, outline.keyA)
    }

    @Test
    fun yourChoiceThenTheAppsThenTheOwners() {
        fun theme(saved: TvSaved?, owner: String?, suggestion: String? = null, layout: String? = null, skin: String? = null) =
            TvLook.choice(saved, suggestion, owner, layout, skin).theme
        assertEquals("teletext", theme(TvSaved(theme = "teletext"), "listings"))
        assertEquals("listings", theme(null, "listings"))
        assertEquals("an app theme's suggestion comes before the owner's", "modern", theme(null, "listings", suggestion = "modern"))
        assertEquals("compact", theme(TvSaved(theme = "compact"), "listings", suggestion = "modern"))
        assertEquals("nothing suggests someone's Custom", "listings", theme(null, "listings", suggestion = "custom"))
        assertEquals("listings", theme(TvSaved(theme = "no such theme"), "listings"))
        assertEquals("classic", theme(null, null))
        // An owner can't start people on someone's Custom.
        assertEquals("classic", theme(null, "custom"))
        assertEquals("satellite", theme(null, null, layout = "classic", skin = "satellite"))
        assertEquals(TvLookChoice.Source.App, TvLook.resolve(null, "modern", "listings", null, null).source)
        assertEquals(TvLookChoice.Source.Owner, TvLook.resolve(null, null, "listings", null, null).source)
    }

    @Test
    fun aChangedColourComesWithItsTheme() {
        val saved = TvSaved(theme = "classic", themeColours = mapOf("classic" to mapOf("hi" to "#ff0000"), "modern" to mapOf("hi" to "#00ff00")))
        assertEquals(mapOf("hi" to "#ff0000"), TvLook.choice(saved, null, null, null, null).colours)
    }

    @Test
    fun aLookSavedBeforeThereWereThemes() {
        fun was(layout: String?, colours: String?, bg: String? = null, accent: String? = null) =
            TvLook.choice(TvSaved(layout = layout, colours = colours, customBg = bg, customAccent = accent), null, null, null, null)
        assertEquals("classic", was("classic", "cable").theme)
        assertEquals("satellite", was("classic", "satellite").theme)
        assertEquals("modern", was("streaming", "theme").theme)
        assertEquals("#ffd60a", was("streaming", "cable").colours["hi"])
        val own = was("classic", "custom", bg = "#101010", accent = "#ffb300")
        assertEquals("custom", own.theme)
        assertEquals(mapOf("bg" to "#101010", "accent" to "#ffb300", "hi" to "#ffb300"), own.colours)
        // The old box with the app's colours is Custom on the box's shape, in plain type.
        val box = TvLook.resolve(TvSaved(layout = "classic", colours = "theme"), null, null, null, null)
        assertEquals("custom", box.theme)
        assertEquals(TvShape.Box, box.shape)
        assertEquals("system", box.font)
    }

    @Test
    fun aBadColourIsIgnored() {
        val c = TvLook.colours("classic", mapOf("hi" to "yellow", "bg" to "#12"), TvAppColours.fallback)
        assertEquals(TvLook.colours("classic", emptyMap(), TvAppColours.fallback), c)
    }

    @Test
    fun eachThemesShape() {
        val shapes = TvTheme.all.associate { it.id to it.shape }
        assertEquals(
            mapOf("modern" to TvShape.Modern, "classic" to TvShape.Box, "satellite" to TvShape.Receiver, "teletext" to TvShape.Teletext, "listings" to TvShape.Listings,
                "bigpicture" to TvShape.Cinema, "outline" to TvShape.Outline, "compact" to TvShape.Compact, "custom" to TvShape.Modern),
            shapes,
        )
        val custom = TvLook.resolve(TvSaved(theme = "custom", custom = TvSaved.Custom("listings", "mono")), null, null, null, null)
        assertEquals(TvShape.Listings, custom.shape)
        assertEquals("mono", custom.font)
        val wrong = TvLook.resolve(TvSaved(theme = "custom", custom = TvSaved.Custom("no such shape")), null, null, null, null)
        assertEquals(TvShape.Modern, wrong.shape)
        assertEquals("only Custom takes a type of its own", "", TvLook.resolve(TvSaved(theme = "teletext", custom = TvSaved.Custom("listings", "serif")), null, null, null, null).font)
    }

    // rowHeight, previewAuto and previewLimit in tvThemes.ts for a 1920 by 1080 screen.
    @Test
    fun rowsAndThePreviewAsTheServerSizesThemOnATv() {
        val rows = mapOf(
            TvShape.Box to listOf(58.0, 72.0, 90.0), TvShape.Modern to listOf(64.0, 80.0, 100.0), TvShape.Receiver to listOf(56.0, 70.0, 88.0),
            TvShape.Teletext to listOf(51.0, 64.0, 80.0), TvShape.Listings to listOf(58.0, 72.0, 90.0), TvShape.Cinema to listOf(51.0, 64.0, 80.0),
            TvShape.Outline to listOf(61.0, 76.0, 95.0), TvShape.Compact to listOf(45.0, 56.0, 70.0),
        )
        for ((shape, want) in rows) assertEquals(shape.id, want, listOf("compact", "normal", "large").map { TvLook.rowHeight(shape, 1920.0, it) })
        val preview = mapOf(
            TvShape.Box to 653.0, TvShape.Modern to 730.0, TvShape.Receiver to 653.0, TvShape.Teletext to 653.0, TvShape.Listings to 653.0,
            TvShape.Cinema to 805.0, TvShape.Outline to 691.0, TvShape.Compact to 422.0,
        )
        for ((shape, want) in preview) assertEquals(shape.id, want, TvLook.previewAuto(shape, 1920.0, 1080.0), 0.0)
        assertEquals(805.0, TvLook.previewLimit(1920.0, 1080.0), 0.0)
    }

    @Test
    fun theOtherChoicesAndTheirDefaults() {
        val plain = TvLook.resolve(null, null, "satellite", null, null)
        assertEquals("normal", plain.density)
        assertEquals(0.0, plain.hours, 0.0)
        assertTrue(plain.nowLine && plain.progress && plain.subtitles && plain.logos && plain.art)
        assertEquals("highlight", plain.preview)
        assertEquals("right", plain.previewSide)
        assertFalse(plain.previewSound)
        assertEquals("Big picture starts on the left", "left", TvLook.resolve(null, null, "bigpicture", null, null).previewSide)

        val look = TvLook.resolve(
            saved("""{"theme":"compact","density":"large","hours":3,"nowLine":false,"progress":false,"subtitles":false,"logos":false,"art":false,"preview":"last","previewSide":"left","previewW":500,"previewSound":true}"""),
            null, null, null, null,
        )
        assertEquals("large", look.density)
        assertEquals(3.0, look.hours, 0.0)
        assertFalse(look.nowLine || look.progress || look.subtitles || look.logos || look.art)
        assertEquals("last", look.preview)
        assertEquals("left", look.previewSide)
        assertEquals(500.0, look.previewW!!, 0.0)
        assertTrue(look.previewSound)
        assertEquals("only the hours the page offers", 0.0, TvLook.resolve(TvSaved(hours = 7.0), null, null, null, null).hours, 0.0)
    }

    @Test
    fun aPreviewPlacedBeforeThereWereSides() {
        val look = TvLook.resolve(saved("""{"previewPos":"bl","previewSize":"l"}"""), null, null, null, null)
        assertEquals("left", look.previewSide)
        assertEquals(460.0, look.previewW!!, 0.0)
    }

    @Test
    fun whatAnOlderAppIsToldBesideTheTheme() {
        // legacyOf in tvThemes.ts, for each theme on its own shape.
        val want = mapOf(
            "modern" to ("streaming" to "theme"), "classic" to ("classic" to "cable"), "satellite" to ("classic" to "satellite"), "teletext" to ("classic" to "cable"),
            "listings" to ("streaming" to "theme"), "bigpicture" to ("streaming" to "theme"), "outline" to ("streaming" to "theme"), "compact" to ("streaming" to "theme"),
            "custom" to ("streaming" to "theme"),
        )
        for (theme in TvTheme.all) assertEquals(theme.id, want[theme.id], TvLook.legacyOf(theme.id, theme.shape))
        assertEquals("classic" to "theme", TvLook.legacyOf("custom", TvShape.Box))
    }

    @Test
    fun aChannelsOwnColourIsMadeVisible() {
        assertNull(TvLook.channelAccent(null, "#000000"))
        assertEquals("#ff0000", TvLook.channelAccent("#ff0000", "#000000"))
        val pushed = TvLook.channelAccent("#101010", "#000000")!!
        assertTrue(TvLook.contrast(pushed, "#000000") >= 4.5)
    }

    @Test
    fun accountChoicesReadTheLookAndLeaveTheRest() {
        val ui = json.parseToJsonElement("""{"homeRows":["a"],"tvLook":{"theme":"satellite","logos":false,"density":"large","hours":2,"custom":{"shape":"box","font":""},"preview":7}}""").jsonObject
        val look = TvSaved.from(ui["tvLook"])
        assertEquals("satellite", look.theme)
        assertEquals(false, look.logos)
        assertEquals(2.0, look.hours!!, 0.0)
        assertEquals("box", look.custom?.shape)
        assertNull("something of the wrong kind is as if it weren't chosen", look.preview)
    }
}
