package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

// WittyTV's themes on Android TV, drawn natively as Apple TV draws them (apple/WittyKit's TvLook.swift). The choice
// follows the account, as it does in the server's page: what someone chose, or what the app's theme suggests, or else
// what the server's owner set. This is web/src/pages/tv/tvThemes.ts and look.ts in the server's repository: every colour
// token, each theme's shape (its proportions, drawn natively to match tvthemes.css), and the viewer's other choices.
// TvLookTest holds this to what that code works out.

// What's saved in an account, under `tvLook` in GET /me/ui. A look saved before there were themes held a layout and
// colours instead. Anything of the wrong kind counts as not chosen, as the page reads it.
data class TvSaved(
    val theme: String? = null,
    val custom: Custom? = null,
    val themeColours: Map<String, Map<String, String>>? = null,
    val layout: String? = null,
    val colours: String? = null,
    val customBg: String? = null,
    val customAccent: String? = null,
    val density: String? = null,
    val hours: Double? = null,
    val nowLine: Boolean? = null,
    val progress: Boolean? = null,
    val subtitles: Boolean? = null,
    val logos: Boolean? = null,
    val art: Boolean? = null,
    val preview: String? = null,
    val previewSide: String? = null,
    val previewW: Double? = null,
    val previewSound: Boolean? = null,
    // From before there was a side and a width.
    val previewPos: String? = null,
    val previewSize: String? = null,
) {
    data class Custom(val shape: String, val font: String? = null)

    companion object {
        private fun text(e: JsonElement?) = (e as? JsonPrimitive)?.takeIf { it.isString }?.content
        private fun flag(e: JsonElement?) = (e as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
        private fun number(e: JsonElement?) = (e as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull

        private fun custom(e: JsonElement?): Custom? {
            val o = e as? JsonObject ?: return null
            val shape = text(o["shape"]) ?: return null
            val font = o["font"]
            if (font != null && font !is kotlinx.serialization.json.JsonNull && text(font) == null) return null
            return Custom(shape, text(font))
        }

        private fun themeColours(e: JsonElement?): Map<String, Map<String, String>>? {
            val o = e as? JsonObject ?: return null
            return o.mapValues { (_, v) ->
                val inner = v as? JsonObject ?: return null
                inner.mapValues { (_, c) -> text(c) ?: return null }
            }
        }

        // tvLook as the account has it; any JSON at all.
        fun from(e: JsonElement?): TvSaved {
            val o = e as? JsonObject ?: return TvSaved()
            return TvSaved(
                theme = text(o["theme"]), custom = custom(o["custom"]), themeColours = themeColours(o["themeColours"]),
                layout = text(o["layout"]), colours = text(o["colours"]), customBg = text(o["customBg"]), customAccent = text(o["customAccent"]),
                density = text(o["density"]), hours = number(o["hours"]), nowLine = flag(o["nowLine"]), progress = flag(o["progress"]),
                subtitles = flag(o["subtitles"]), logos = flag(o["logos"]), art = flag(o["art"]), preview = text(o["preview"]),
                previewSide = text(o["previewSide"]), previewW = number(o["previewW"]), previewSound = flag(o["previewSound"]),
                previewPos = text(o["previewPos"]), previewSize = text(o["previewSize"]),
            )
        }
    }
}

// Every colour the guide draws with, each as `#rrggbb`, or `#rrggbbaa` for the two washes (`lite` over a cell's
// progress, `shade`). Every pairing that's drawn can be read.
data class TvColours(
    val bg: String, val panel: String, val panel2: String, val head: String, val ch: String, val dim: String, val line: String, val text: String, val soft: String,
    val cell: String, val cell2: String, val cellText: String, val cellSoft: String, val live: String, val live2: String, val liveText: String, val liveSoft: String,
    val hi: String, val hiText: String, val accent: String, val accentText: String, val keyA: String, val keyB: String, val keyC: String, val keyText: String,
    val err: String, val lite: String, val shade: String,
)

// The colours of the app's theme, for the themes that follow it.
data class TvAppColours(
    val bg: String, val bg2: String, val bg3: String, val bg4: String, val fg: String, val fg2: String,
    val accent: String, val accentText: String, val accentFg: String, val border: String, val danger: String = "#ff5c6c",
) {
    companion object {
        val fallback = TvAppColours(
            bg = "#0f1115", bg2 = "#16181d", bg3 = "#23262d", bg4 = "#30343c", fg = "#ffffff", fg2 = "#c9ccd3",
            accent = "#7955ff", accentText = "#b39dff", accentFg = "#ffffff", border = "#4a4f5a",
        )
    }
}

// Row heights on a phone, a desktop and a TV, before the viewer's row size.
data class TvRows(val phone: Double, val desktop: Double, val tv: Double)

// How the guide is built: its proportions, corners, rules and type. A theme is a shape with colours and a name;
// Custom is a shape and colours someone chose.
enum class TvShape(val id: String) {
    Box("box"), Modern("modern"), Receiver("receiver"), Teletext("teletext"), Listings("listings"), Cinema("cinema"), Outline("outline"), Compact("compact");

    val rows: TvRows
        get() = when (this) {
            Box -> TvRows(56.0, 64.0, 72.0)
            Modern -> TvRows(64.0, 76.0, 80.0)
            Receiver -> TvRows(56.0, 58.0, 70.0)
            Teletext -> TvRows(52.0, 50.0, 64.0)
            Listings -> TvRows(60.0, 62.0, 72.0)
            Cinema -> TvRows(56.0, 54.0, 64.0)
            Outline -> TvRows(60.0, 66.0, 76.0)
            Compact -> TvRows(44.0, 40.0, 56.0)
        }

    // How much of the page's width the preview starts at.
    val previewShare: Double
        get() = when (this) {
            Modern -> 0.38
            Cinema -> 0.48
            Outline -> 0.36
            Compact -> 0.22
            else -> 0.34
        }

    // The side the preview starts on.
    val side: String get() = if (this == Cinema) "left" else "right"

    // The programme's picture and title art at the top.
    val art: Boolean get() = this == Modern || this == Outline

    // Cells say time, year and genre, rather than the episode.
    val details: Boolean get() = this == Modern || this == Cinema || this == Outline || this == Compact

    // The highlighted row's channel takes the highlight's colour.
    val rowHighlight: Boolean get() = this == Modern || this == Cinema

    val title: String
        get() = when (this) {
            Box -> "Cable box"
            Modern -> "Modern"
            Receiver -> "Receiver"
            Teletext -> "Teletext"
            Listings -> "Newspaper"
            Cinema -> "Big picture"
            Outline -> "Outline"
            Compact -> "Compact"
        }

    companion object {
        fun of(id: String?): TvShape? = entries.firstOrNull { it.id == id }
    }
}

// One of WittyTV's themes. `follows`: its colours come from the app's theme until someone changes them.
data class TvTheme(val id: String, val name: String, val blurb: String, val shape: TvShape, val follows: Boolean) {
    companion object {
        val all = listOf(
            TvTheme("modern", "Modern", "Clean and calm, with the programme's picture up top and a big preview.", TvShape.Modern, true),
            TvTheme("classic", "Classic", "The chunky blue box of the early 2000s, bevelled and square.", TvShape.Box, false),
            TvTheme("satellite", "Satellite", "A receiver's display: black and amber, thin rules, digits like an LED.", TvShape.Receiver, false),
            TvTheme("teletext", "Teletext", "Blocky letters and eight flat colours on black, page number and all.", TvShape.Teletext, false),
            TvTheme("listings", "Newspaper", "The listings page: ink on paper, serif type and hairline rules.", TvShape.Listings, false),
            TvTheme("bigpicture", "Big picture", "The preview comes first and takes half the width, over a short grid.", TvShape.Cinema, true),
            TvTheme("outline", "Outline", "Light and open: cells are outlines, and only the highlight is filled.", TvShape.Outline, true),
            TvTheme("compact", "Compact", "Small type and tight rows, for seeing the most channels at once.", TvShape.Compact, true),
            TvTheme("custom", "Custom", "Your own: choose the layout, type and colours, and it stays yours.", TvShape.Modern, true),
        )

        fun byId(id: String?): TvTheme? = all.firstOrNull { it.id == id }
    }
}

// How WittyTV looks for this viewer: the theme and where it came from, its shape, type and colours, and the rest of
// what they chose. What they haven't chosen has the page's defaults.
data class TvLookChoice(
    val theme: String,
    val shape: TvShape,
    // A Custom theme's type: "", "system", "narrow", "mono" or "serif". "" is the layout's own.
    val font: String,
    val source: Source,
    val colours: TvColours,
    // The colours this theme was changed to, if any.
    val overrides: Map<String, String>,
    val density: String,
    // 0 is what fits the screen.
    val hours: Double,
    val nowLine: Boolean,
    val progress: Boolean,
    val subtitles: Boolean,
    val logos: Boolean,
    val art: Boolean,
    // "highlight", "last" or "off".
    val preview: String,
    val previewSide: String,
    val previewW: Double?,
    val previewSound: Boolean,
) {
    enum class Source { You, App, Owner }

    // The highlight and the background, as dark or light, for logos that come in both.
    val bgIsDark: Boolean get() = TvLook.readableOn(TvLook.solid(colours.bg)) == "#ffffff"
    val hiIsDark: Boolean get() = TvLook.readableOn(TvLook.solid(colours.hi)) == "#ffffff"
}

data class TvChosen(val theme: String, val colours: Map<String, String>)

object TvLook {
    private val themes = TvTheme.all.map { it.id }.toSet()
    private const val AA = 4.5

    private val own: Map<String, Map<String, String>> = mapOf(
        "classic" to mapOf(
            "bg" to "#06164a", "panel" to "#0a2270", "panel-2" to "#123391", "head" to "#16389e", "cell" to "#1a43b8", "cell-2" to "#143594", "live" to "#0f6a7f",
            "live-2" to "#0b5466", "ch" to "#0c2a84", "dim" to "#0d2a7c", "line" to "#6f94f2", "text" to "#ffffff", "soft" to "#d6e2ff", "hi" to "#ffd60a",
            "accent" to "#ffd60a", "key-a" to "#ffd60a", "key-b" to "#4ce06a", "key-c" to "#7fc7ff", "err" to "#ffe08a", "lite" to "#ffffff29",
        ),
        "satellite" to mapOf(
            "bg" to "#07090d", "panel" to "#10131a", "panel-2" to "#22262f", "head" to "#14171e", "cell" to "#14171e", "cell-2" to "#14171e", "live" to "#2e2300",
            "live-2" to "#2e2300", "ch" to "#10131a", "dim" to "#0c0e13", "line" to "#6a7181", "text" to "#ffffff", "soft" to "#dcdfe6", "hi" to "#ffb300",
            "accent" to "#ffb300", "key-a" to "#ffb300", "key-b" to "#5fd47d", "key-c" to "#8cc6ff", "err" to "#ffd27a", "lite" to "#ffb3002e",
        ),
        "teletext" to mapOf(
            "bg" to "#000000", "panel" to "#000000", "panel-2" to "#0000d0", "head" to "#0000d0", "cell" to "#000000", "cell-2" to "#000000", "live" to "#003c00",
            "live-2" to "#003c00", "ch" to "#000000", "dim" to "#000000", "line" to "#00d8d8", "text" to "#ffffff", "soft" to "#00ffff", "hi" to "#00ffff",
            "accent" to "#ffff00", "key-a" to "#ff5a5a", "key-b" to "#00ff00", "key-c" to "#ffff00", "err" to "#ff9d9d", "lite" to "#00ff0038",
        ),
        "listings" to mapOf(
            "bg" to "#f5f0e4", "panel" to "#f5f0e4", "panel-2" to "#eae3d2", "head" to "#f5f0e4", "cell" to "#f5f0e4", "cell-2" to "#f5f0e4", "live" to "#ebdfb8",
            "live-2" to "#ebdfb8", "ch" to "#f5f0e4", "dim" to "#efe9db", "line" to "#6b6252", "text" to "#1b1813", "soft" to "#4d463a", "hi" to "#1b1813",
            "accent" to "#9c1c12", "key-a" to "#1b1813", "key-b" to "#1b1813", "key-c" to "#1b1813", "err" to "#9c1c12", "lite" to "#9c1c121f",
        ),
    )

    private val legacy: Map<String, Map<String, String>> = mapOf(
        "midnight" to mapOf("bg" to "#000000", "cell" to "#2a2a2a", "live" to "#3a3a3a", "hi" to "#ffffff", "accent" to "#c9a2ff"),
        "cable" to mapOf("bg" to "#06164a", "cell" to "#1a43b8", "live" to "#0f6a7f", "hi" to "#ffd60a", "accent" to "#ffd60a"),
        "satellite" to mapOf("bg" to "#07090d", "cell" to "#2b3039", "live" to "#4d3700", "hi" to "#ffb300", "accent" to "#ffb300"),
    )

    // What a theme came to before there were themes: a layout and a set of colours.
    internal data class Legacy(val theme: String, val custom: TvSaved.Custom?, val colours: Map<String, String>)

    private data class Chosen(val theme: String, val source: TvLookChoice.Source, val custom: TvSaved.Custom?, val colours: Map<String, String>)

    // Which theme this account has, and what it changed in it. The app's theme can suggest one, and the owner's look
    // comes with the guide.
    fun choice(saved: TvSaved?, suggestion: String? = null, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?): TvChosen {
        val full = choose(saved, suggestion, ownerTheme, ownerLayout, ownerSkin)
        return TvChosen(full.theme, full.colours)
    }

    private fun choose(saved: TvSaved?, suggestion: String?, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?): Chosen {
        val mine = upgrade(saved ?: TvSaved(), ownerLayout, ownerSkin)
        fun yours(theme: String) = mine.themeColours?.get(theme) ?: emptyMap()
        mine.theme?.let { if (isTheme(it)) return Chosen(it, TvLookChoice.Source.You, mine.custom, yours(it)) }
        suggestion?.let { if (isTheme(it) && it != "custom") return Chosen(it, TvLookChoice.Source.App, mine.custom, yours(it)) }
        ownerTheme?.let { if (isTheme(it) && it != "custom") return Chosen(it, TvLookChoice.Source.Owner, mine.custom, yours(it)) }
        if (ownerLayout != null || ownerSkin != null) {
            val was = fromLegacy(ownerLayout, ownerSkin, null, null)
            return Chosen(was.theme, TvLookChoice.Source.Owner, mine.custom ?: was.custom, mine.themeColours?.get(was.theme) ?: was.colours)
        }
        return Chosen("classic", TvLookChoice.Source.Owner, mine.custom, yours("classic"))
    }

    // Reads a look saved in any earlier form, as the page's upgradeSaved does.
    internal fun upgrade(raw: TvSaved, ownerLayout: String?, ownerSkin: String?): TvSaved {
        var out = raw
        if (out.previewSide == null && raw.previewPos != null) {
            out = out.copy(previewSide = if (raw.previewPos == "tl" || raw.previewPos == "bl") "left" else "right")
        }
        if (out.previewW == null) {
            mapOf("s" to 220.0, "m" to 320.0, "l" to 460.0)[raw.previewSize]?.let { out = out.copy(previewW = it) }
        }
        if (!isTheme(raw.theme) && (raw.layout != null || raw.colours != null)) {
            val was = fromLegacy(raw.layout ?: ownerLayout, raw.colours ?: ownerSkin, raw.customBg, raw.customAccent)
            out = out.copy(theme = was.theme)
            if (was.custom != null) out = out.copy(custom = was.custom)
            if (was.colours.isNotEmpty()) out = out.copy(themeColours = mapOf(was.theme to was.colours))
        }
        if (!isTheme(out.theme)) out = out.copy(theme = null)
        if (out.custom != null && TvShape.of(out.custom?.shape) == null) out = out.copy(custom = null)
        return out
    }

    fun colours(saved: TvSaved?, suggestion: String? = null, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?, app: TvAppColours = TvAppColours.fallback): TvColours =
        resolve(saved, suggestion, ownerTheme, ownerLayout, ownerSkin, app).colours

    // The whole look, as the page's `useLook` works it out.
    fun resolve(saved: TvSaved?, suggestion: String? = null, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?, app: TvAppColours = TvAppColours.fallback): TvLookChoice {
        val mine = upgrade(saved ?: TvSaved(), ownerLayout, ownerSkin)
        val chosen = choose(saved, suggestion, ownerTheme, ownerLayout, ownerSkin)
        val custom = chosen.custom ?: TvSaved.Custom("modern", "")
        val shape = if (chosen.theme == "custom") TvShape.of(custom.shape) ?: TvShape.Modern else TvTheme.byId(chosen.theme)?.shape ?: TvShape.Box
        val hours = (mine.hours ?: 0.0).let { if (it in listOf(0.0, 1.5, 2.0, 3.0, 4.0)) it else 0.0 }
        return TvLookChoice(
            theme = chosen.theme, shape = shape, font = if (chosen.theme == "custom") custom.font ?: "" else "", source = chosen.source,
            colours = colours(chosen.theme, chosen.colours, app), overrides = chosen.colours.filterValues { isHex(it) },
            density = mine.density?.takeIf { it in listOf("compact", "normal", "large") } ?: "normal", hours = hours,
            nowLine = mine.nowLine ?: true, progress = mine.progress ?: true, subtitles = mine.subtitles ?: true, logos = mine.logos ?: true, art = mine.art ?: true,
            preview = mine.preview?.takeIf { it in listOf("highlight", "last", "off") } ?: "highlight",
            previewSide = mine.previewSide?.takeIf { it == "left" || it == "right" } ?: shape.side,
            previewW = mine.previewW, previewSound = mine.previewSound ?: false,
        )
    }

    private fun isTheme(id: String?) = id != null && id in themes

    internal fun fromLegacy(layout: String?, colours: String?, customBg: String?, customAccent: String?): Legacy {
        var mine = emptyMap<String, String>()
        if (customBg != null && customAccent != null && isHex(customBg) && isHex(customAccent)) mine = mapOf("bg" to customBg, "accent" to customAccent, "hi" to customAccent)
        if (layout == "streaming") {
            if (colours == "theme") return Legacy("modern", null, emptyMap())
            return Legacy("modern", null, if (colours == "custom") mine else legacy[colours ?: "midnight"] ?: legacy.getValue("midnight"))
        }
        return when (colours) {
            "satellite" -> Legacy("satellite", null, emptyMap())
            "midnight" -> Legacy("custom", TvSaved.Custom("box", ""), legacy.getValue("midnight"))
            "theme" -> Legacy("custom", TvSaved.Custom("box", "system"), emptyMap())
            "custom" -> Legacy("custom", TvSaved.Custom("box", ""), mine)
            else -> Legacy("classic", null, emptyMap())
        }
    }

    // What a theme says for clients that only know the two earlier looks, kept beside it.
    fun legacyOf(id: String, shape: TvShape): Pair<String, String> = when {
        id == "satellite" -> "classic" to "satellite"
        id == "classic" || id == "teletext" -> "classic" to "cable"
        shape == TvShape.Box -> "classic" to "theme"
        else -> "streaming" to "theme"
    }

    // A row's height, from the shape, the width of the page and the viewer's row size.
    fun rowHeight(shape: TvShape, width: Double, density: String): Double {
        val rows = shape.rows
        val base = if (width < 560) rows.phone else if (width >= 1800) rows.tv else rows.desktop
        val times = if (density == "compact") 0.8 else if (density == "large") 1.25 else 1.0
        return round(base * times)
    }

    const val PREVIEW_MIN = 180.0

    // The preview's named sizes. Any width between works too.
    val previewSizes = listOf(220.0 to "Small", 320.0 to "Medium", 460.0 to "Large", 640.0 to "Extra large", 880.0 to "Huge")

    // What the page can spare for the preview, so the words beside it and the guide below keep room.
    fun previewLimit(pageWidth: Double, pageHeight: Double): Double {
        val byWidth = pageWidth * 0.6
        val byHeight = (pageHeight * 0.46 - 44) * (16.0 / 9)
        return round(max(PREVIEW_MIN, min(byWidth, byHeight)))
    }

    // How wide the preview starts: a share of the page that suits the shape, held to what fits.
    fun previewAuto(shape: TvShape, pageWidth: Double, pageHeight: Double): Double {
        val most = previewLimit(pageWidth, pageHeight)
        return round(min(most, max(PREVIEW_MIN, pageWidth * shape.previewShare)))
    }

    // Its colours.

    internal fun colours(id: String, overrides: Map<String, String>, app: TvAppColours): TvColours {
        val set = overrides.filterValues { isHex(it) }
        val hiFollowsText = id == "modern" || id == "bigpicture"
        if (set.isEmpty()) {
            own[id]?.let { base ->
                return derive(
                    mapOf("bg" to base.getValue("bg"), "cell" to base.getValue("cell"), "live" to base.getValue("live"), "hi" to base.getValue("hi"),
                        "accent" to base.getValue("accent"), "text" to base.getValue("text")),
                    base,
                )
            }
            // Following the app's theme: only its own colours.
            val hi = if (hiFollowsText) app.fg else app.accent
            val hiText = if (hiFollowsText) app.bg else app.accentFg
            return TvColours(
                bg = app.bg, panel = app.bg2, panel2 = app.bg3, head = app.bg2, ch = app.bg2, dim = app.bg2, line = app.border, text = app.fg, soft = app.fg2,
                cell = app.bg3, cell2 = app.bg3, cellText = app.fg, cellSoft = app.fg2, live = app.bg4, live2 = app.bg4, liveText = app.fg, liveSoft = app.fg2,
                hi = hi, hiText = hiText, accent = app.accentText, accentText = app.bg, keyA = hi, keyB = hi, keyC = hi, keyText = hiText, err = app.danger,
                lite = alpha(app.accent, 0.24), shade = alpha(app.bg, 0.12),
            )
        }
        val base = own[id] ?: mapOf(
            "bg" to app.bg, "panel" to app.bg2, "panel-2" to app.bg3, "head" to app.bg2, "cell" to app.bg3, "cell-2" to app.bg3, "live" to app.bg4, "live-2" to app.bg4,
            "ch" to app.bg2, "dim" to app.bg2, "line" to app.border, "text" to app.fg, "soft" to app.fg2, "hi" to if (hiFollowsText) app.fg else app.accent,
            "accent" to app.accentText,
        )
        // A new background with no word on the text: the text goes with it, and so do cells that were worked out for
        // the old one.
        val text = set["text"] ?: set["bg"]?.let { readableOn(it) } ?: base.getValue("text")
        val bg = set["bg"] ?: base.getValue("bg")
        val cell = set["cell"] ?: if (set["bg"] != null) mix(bg, readableOn(bg), 0.14) else base.getValue("cell")
        val accent = set["accent"] ?: base.getValue("accent")
        val live = set["live"] ?: if (set["bg"] != null || set["accent"] != null || set["cell"] != null) mix(cell, accent, 0.22) else base.getValue("live")
        return derive(mapOf("bg" to bg, "cell" to cell, "live" to live, "hi" to (set["hi"] ?: base.getValue("hi")), "accent" to accent, "text" to text), base)
    }

    private fun derive(c: Map<String, String>, base: Map<String, String>): TvColours {
        val bg = c.getValue("bg")
        val text = legible(c.getValue("text"), listOf(bg))
        fun lift(t: Double) = underText(mix(bg, text, t), text, bg)
        fun fromBase(key: String, t: Double) = if (base["bg"] == bg) underText(base.getValue(key), text, bg) else lift(t)
        val panel = fromBase("panel", 0.06)
        val panel2 = fromBase("panel-2", 0.12)
        val head = fromBase("head", 0.14)
        val ch = fromBase("ch", 0.06)
        val dim = fromBase("dim", 0.06)
        val page = listOf(bg, panel, panel2, head, ch, dim)
        val accent = legible(c.getValue("accent"), page)
        val hi = legible(c.getValue("hi"), listOf(bg), need = 3.0)
        val cell = c.getValue("cell")
        val live = c.getValue("live")
        val onCell = onCells(text, cell, if (base["cell"] == cell) base.getValue("cell-2") else mix(cell, bg, 0.18))
        val onLive = onCells(text, live, if (base["live"] == live) base.getValue("live-2") else mix(live, bg, 0.18))
        fun key(k: String) = if (base["accent"] == accent) base[k] ?: accent else accent
        val err = legible(if (base["err"] != null && base["bg"] == bg) base.getValue("err") else accent, page)
        val lite = if (base["lite"] != null && base["bg"] == bg) base.getValue("lite") else if (readableOn(bg) == "#ffffff") alpha("#ffffff", 0.16) else alpha("#000000", 0.1)
        val shade = if (readableOn(hi) == "#ffffff") alpha("#ffffff", 0.2) else alpha("#000000", 0.14)
        return TvColours(
            bg = bg, panel = panel, panel2 = panel2, head = head, ch = ch, dim = dim,
            line = legible(fromBase("line", 0.34), listOf(bg), need = 3.0), text = text, soft = softOn(text, page),
            cell = cell, cell2 = onCell.second, cellText = onCell.first, cellSoft = onCell.third,
            live = live, live2 = onLive.second, liveText = onLive.first, liveSoft = onLive.third,
            hi = hi, hiText = readableOn(hi), accent = accent, accentText = readableOn(accent),
            keyA = key("key-a"), keyB = key("key-b"), keyC = key("key-c"), keyText = readableOn(key("key-a")),
            err = err, lite = lite, shade = shade,
        )
    }

    // Text for a cell and its gradient's other end: a cell can be any colour, and the page another.
    private fun onCells(text: String, cell: String, second: String): Triple<String, String, String> {
        val t = if (contrast(text, cell) >= AA) text else readableOn(cell)
        val other = underText(second, t, cell)
        return Triple(t, other, softOn(t, listOf(cell, other)))
    }

    private fun legible(colour: String, surfaces: List<String>, need: Double = AA): String {
        fun ok(c: String) = surfaces.all { contrast(c, it) >= need }
        for (towards in listOf(readableOn(surfaces[0]), readableOn(colour))) {
            var c = colour
            var tries = 0
            while (tries < 12 && !ok(c)) {
                c = mix(c, towards, 0.15)
                tries++
            }
            if (ok(c)) return c
            if (ok(towards)) return towards
        }
        return readableOn(surfaces[0])
    }

    private fun underText(surface: String, text: String, readsOn: String): String {
        var s = surface
        var tries = 0
        while (tries < 12 && contrast(text, s) < AA) {
            s = mix(s, readsOn, 0.2)
            tries++
        }
        return if (contrast(text, s) >= AA) s else readsOn
    }

    private fun softOn(text: String, surfaces: List<String>): String {
        for (t in listOf(0.24, 0.16, 0.08)) {
            val c = mix(text, surfaces[0], t)
            if (surfaces.all { contrast(c, it) >= AA }) return c
        }
        return text
    }

    // Colour sums.

    fun isHex(value: String): Boolean =
        value.length == 7 && value.startsWith("#") && value.drop(1).all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }

    // Half away from zero, as Swift and JavaScript's Math.round do for the positive numbers here.
    private fun round(x: Double) = floor(x + 0.5)

    private fun hex2(v: Int) = (if (v < 16) "0" else "") + v.toString(16)

    // `#rrggbb` with an opacity, as `#rrggbbaa`.
    internal fun alpha(hex: String, amount: Double): String = solid(hex) + hex2(round(amount * 255).toInt())

    // The colour without its opacity.
    fun solid(hex: String): String = hex.take(7)

    private fun channels(hex: String): List<Double> {
        val digits = hex.drop(1)
        if (digits.length < 6) return listOf(0.0, 0.0, 0.0)
        return listOf(0, 2, 4).map { (digits.substring(it, it + 2).toIntOrNull(16) ?: 0).toDouble() }
    }

    internal fun mix(a: String, b: String, t: Double): String {
        val x = channels(a)
        val y = channels(b)
        return "#" + x.zip(y).joinToString("") { (p, q) -> hex2(round(max(0.0, min(255.0, p + (q - p) * t))).toInt()) }
    }

    private fun luminance(hex: String): Double {
        val c = channels(hex).map { v ->
            val s = v / 255
            if (s <= 0.03928) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    fun contrast(a: String, b: String): Double {
        val x = luminance(a)
        val y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    fun readableOn(bg: String): String = if (contrast(bg, "#ffffff") >= contrast(bg, "#000000")) "#ffffff" else "#000000"

    // A channel's own colour, pushed far enough from the background to be seen.
    fun channelAccent(accent: String?, bg: String): String? {
        if (accent == null || !isHex(accent)) return null
        val away = readableOn(solid(bg))
        var a: String = accent
        var tries = 0
        while (tries < 10 && contrast(a, solid(bg)) < AA) {
            a = mix(a, away, 0.15)
            tries++
        }
        return a
    }
}
