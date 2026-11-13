// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

// The server's name editor (docs/plans/DESIGN-2.md 7.6 and 9; the canvas page BrandEditor): the name's letters with a
// colour each, the quick presets, the contrast check and the rail's mark. Apart from the screen, so the rules are tested
// without one. The server's own rules are in internal/brandname: a part is `fg`, `accent`, `token`, `static` or
// `gradient`; the editor's spans are `[{from, to, color, bold}]` over code points (at most 40, in order, not
// overlapping); the mark is `{kind: letter|initials|text|image, text?}`.

object BrandKinds {
    const val FG = "fg"
    const val ACCENT = "accent"
    const val TOKEN = "token"
    const val STATIC = "static"
    const val GRADIENT = "gradient"
}

// How one part is coloured. `stops` are two to four #rrggbb, `angle` the direction in degrees (90: left to right).
@Serializable
data class BrandColor(
    val kind: String = BrandKinds.FG,
    val token: String = "",
    val hex: String = "",
    val stops: List<String> = emptyList(),
    val angle: Int = 0,
) {
    companion object {
        val FG = BrandColor(BrandKinds.FG)
        val ACCENT = BrandColor(BrandKinds.ACCENT)
        fun token(name: String) = BrandColor(BrandKinds.TOKEN, token = name)
        fun fixed(hex: String) = BrandColor(BrandKinds.STATIC, hex = BrandEditor.normalHex(hex) ?: hex)
        fun gradient(stops: List<String>, angle: Int = 90) = BrandColor(BrandKinds.GRADIENT, stops = stops.map { BrandEditor.normalHex(it) ?: it }, angle = angle)
    }
}

// What one letter looks like.
data class BrandLook(val color: BrandColor = BrandColor.FG, val bold: Boolean = false)

@Serializable
data class BrandSpan(val from: Int, val to: Int, val color: BrandColor, val bold: Boolean = false)

// The rail's badge: what it holds. `text` is for the owner's own one or two characters.
data class BrandMarkChoice(val kind: String = BrandEditor.MARK_LETTER, val text: String = "")

// A fixed colour that falls under 4.5:1 on a surface of a theme.
data class BrandContrast(val text: String, val hex: String, val surface: String, val theme: String, val ratio: Double, val need: Double, val readable: String?) {
    val words: String
        get() = "The fixed colour $hex on \"$text\" is ${"%.1f".format(ratio)} to 1 on ${surface} in the $theme theme. " +
            "Words should be at least ${"%.1f".format(need)} to 1." + (readable?.let { " $it would pass." } ?: " Follow the theme instead.")
}

// One theme's three surfaces the name sits on: the page (bg), the side menu and bars (bg-2) and cards (bg-3).
data class BrandSurfaces(val theme: String, val surfaces: List<Pair<String, ThemeColour>>) {
    companion object {
        fun of(theme: AppTheme) = BrandSurfaces(
            theme.name,
            listOf("the page" to theme.background, "the side menu and bars" to theme.panel, "cards" to theme.card),
        )
    }
}

// A draft of the name's look: every letter has its own. The spans, parts and settings come from it.
data class BrandDraft(val name: String, val looks: List<BrandLook>, val mark: BrandMarkChoice = BrandMarkChoice(), val auto: Boolean = false) {
    val letters: List<String> get() = BrandEditor.letters(name)
    val size: Int get() = looks.size

    // What the name has now, as the server draws it.
    val parts: List<BrandPart> get() = BrandEditor.parts(this)
    val spans: List<BrandSpan> get() = BrandEditor.spans(this)
    val tooManySpans: Boolean get() = spans.size > BrandEditor.MAX_SPANS
}

object BrandEditor {
    const val MAX_RUNES = 80
    const val MAX_SPANS = 40
    const val NEED = 4.5
    const val MARK_LETTER = "letter"
    const val MARK_INITIALS = "initials"
    const val MARK_TEXT = "text"
    const val MARK_IMAGE = "image"
    const val MAX_LOGO_BYTES = 2 * 1024 * 1024

    // The name's letters as code points, so a letter outside the basic plane stays one.
    fun letters(name: String): List<String> = points(name).map { String(Character.toChars(it)) }

    fun length(name: String): Int = name.codePointCount(0, name.length)

    // The code points of a name (String.codePoints needs Android 7).
    private fun points(name: String): IntArray {
        val out = ArrayList<Int>(name.length)
        var i = 0
        while (i < name.length) {
            val c = name.codePointAt(i)
            out += c
            i += Character.charCount(c)
        }
        return out.toIntArray()
    }

    // MARK: words (internal/brandname.Words, rule for rule)

    private fun isMark(c: Int): Boolean = when (Character.getType(c)) {
        Character.NON_SPACING_MARK.toInt(), Character.ENCLOSING_MARK.toInt(), Character.COMBINING_SPACING_MARK.toInt() -> true
        else -> false
    }

    private fun joiner(c: Int): Boolean = Character.getType(c) == Character.DASH_PUNCTUATION.toInt() || "_/&+|·:".contains(String(Character.toChars(c)))

    private fun breaksBefore(r: IntArray, start: Int, i: Int): Boolean {
        val c = r[i]
        var p = -1
        for (j in i - 1 downTo start) if (!isMark(r[j])) { p = j; break }
        if (p < 0 || isMark(c)) return false
        val prev = r[p]
        when {
            Character.isUpperCase(c) -> when {
                Character.isLowerCase(prev) -> return true
                Character.isUpperCase(prev) || Character.isDigit(prev) -> return i + 2 < r.size && Character.isLowerCase(r[i + 1]) && Character.isLowerCase(r[i + 2])
                joiner(prev) -> for (j in start until p) if (Character.isLetter(r[j]) || Character.isDigit(r[j])) return true
            }
            Character.isDigit(c) -> return Character.isLowerCase(prev)
        }
        return false
    }

    // The words of a name as [start, end) letter offsets.
    fun words(name: String): List<IntRange> {
        val r = points(name)
        val out = ArrayList<IntRange>()
        var start = -1
        for ((i, c) in r.withIndex()) {
            if (Character.isWhitespace(c) || Character.isSpaceChar(c)) {
                if (start >= 0) { out += start until i; start = -1 }
                continue
            }
            if (start < 0) { start = i; continue }
            if (breaksBefore(r, start, i)) { out += start until i; start = i }
        }
        if (start >= 0) out += start until r.size
        return out
    }

    fun wordAt(name: String, index: Int): IntRange? = words(name).firstOrNull { index in it }

    // MARK: drafts

    private fun fg() = BrandLook()

    fun plain(name: String) = BrandDraft(name, List(length(name)) { fg() })

    // The server's automatic split: every other word, starting with the second, in the accent.
    fun autoDraft(name: String, mark: BrandMarkChoice = BrandMarkChoice()): BrandDraft {
        val looks = MutableList(length(name)) { fg() }
        words(name).forEachIndexed { n, w -> if (n % 2 == 1) for (i in w) looks[i] = BrandLook(BrandColor.ACCENT) }
        return BrandDraft(name, looks, mark, auto = true)
    }

    // What the server sent: its parts (each with the colour it is drawn in) become one look a letter.
    fun fromParts(name: String, parts: List<BrandPart>, mark: BrandMarkChoice = BrandMarkChoice()): BrandDraft {
        val shown = BrandName.parts(name, parts)
        val text = shown.joinToString("") { it.text }
        val looks = ArrayList<BrandLook>()
        for (p in shown) repeat(length(p.text)) { looks += BrandLook(p.color ?: if (p.accent) BrandColor.ACCENT else BrandColor.FG, p.bold) }
        val draft = BrandDraft(text, looks, mark)
        return draft.copy(auto = matchesAuto(draft))
    }

    fun matchesAuto(d: BrandDraft): Boolean = autoDraft(d.name).looks == d.looks

    // A new name keeps the looks of the letters it still has at the same places: the rest are plain.
    fun renamed(d: BrandDraft, name: String): BrandDraft {
        val clipped = letters(name).take(MAX_RUNES).joinToString("")
        val n = length(clipped)
        val looks = List(n) { d.looks.getOrNull(it) ?: fg() }
        return d.copy(name = clipped, looks = looks, auto = false)
    }

    fun painted(d: BrandDraft, picked: Set<Int>, color: BrandColor): BrandDraft =
        d.copy(looks = d.looks.mapIndexed { i, l -> if (i in picked) l.copy(color = color) else l }, auto = false)

    fun bolded(d: BrandDraft, picked: Set<Int>, bold: Boolean): BrandDraft =
        d.copy(looks = d.looks.mapIndexed { i, l -> if (i in picked) l.copy(bold = bold) else l }, auto = false)

    // MARK: presets (the canvas: Accent on "Media", Two-tone, One colour, Plain, Rainbow letters, Gradient)

    val RAINBOW = listOf("#ff5c6c", "#ff9f43", "#ffd84a", "#3ddc84", "#1e9be0", "#b57bff")
    val DEFAULT_GRADIENT = listOf("#1e9be0", "#3ad29f")

    fun presetAccentOnMedia(d: BrandDraft): BrandDraft = autoDraft(d.name, d.mark)

    // The first word plain, the rest in the accent; a one-word name, its second half.
    fun presetTwoTone(d: BrandDraft): BrandDraft {
        val ws = words(d.name)
        val n = length(d.name)
        val from = if (ws.size >= 2) ws[1].first else n / 2
        return d.copy(looks = List(n) { if (it >= from) BrandLook(BrandColor.ACCENT) else fg() }, auto = false)
    }

    fun presetOneColour(d: BrandDraft): BrandDraft = d.copy(looks = List(length(d.name)) { BrandLook(BrandColor.ACCENT) }, auto = false)

    fun presetPlain(d: BrandDraft): BrandDraft = plain(d.name).copy(mark = d.mark)

    // A fixed colour for each letter in turn, or for each pair or more when the name is longer than the server's
    // forty spans.
    fun presetRainbow(d: BrandDraft): BrandDraft {
        val n = length(d.name)
        val group = max(1, (n + MAX_SPANS - 1) / MAX_SPANS)
        val letters = letters(d.name)
        var hue = 0
        val looks = ArrayList<BrandLook>(n)
        var i = 0
        while (i < n) {
            val plainLetter = letters[i].isBlank()
            val take = min(group, n - i)
            val look = if (plainLetter) fg() else BrandLook(BrandColor.fixed(RAINBOW[hue++ % RAINBOW.size]))
            repeat(take) { looks += look }
            i += take
        }
        return d.copy(looks = looks, auto = false)
    }

    fun presetGradient(d: BrandDraft, stops: List<String> = DEFAULT_GRADIENT, angle: Int = 90): BrandDraft =
        d.copy(looks = List(length(d.name)) { BrandLook(BrandColor.gradient(stops, angle)) }, auto = false)

    // MARK: parts and spans

    private fun sameLook(a: BrandLook, b: BrandLook) = a == b

    // The draft as the server would send it back: neighbouring letters that look the same are one part.
    fun parts(d: BrandDraft): List<BrandPart> {
        val letters = letters(d.name)
        if (letters.isEmpty()) return emptyList()
        val out = ArrayList<BrandPart>()
        var start = 0
        for (i in 1..letters.size) {
            if (i == letters.size || !sameLook(d.looks[i], d.looks[start])) {
                val look = d.looks[start]
                out += BrandPart(letters.subList(start, i).joinToString(""), look.color.kind == BrandKinds.ACCENT, look.color, look.bold)
                start = i
            }
        }
        return out
    }

    // What `brandSpans` carries: only the letters that aren't plain, runs of the same look as one span.
    fun spans(d: BrandDraft): List<BrandSpan> {
        val out = ArrayList<BrandSpan>()
        var i = 0
        while (i < d.looks.size) {
            val look = d.looks[i]
            if (look == fg()) { i++; continue }
            var j = i + 1
            while (j < d.looks.size && d.looks[j] == look) j++
            out += BrandSpan(i, j, look.color, look.bold)
            i = j
        }
        return out
    }

    fun spansJson(spans: List<BrandSpan>): String {
        if (spans.isEmpty()) return ""
        return buildJsonArray {
            for (s in spans) add(
                buildJsonObject {
                    put("from", s.from)
                    put("to", s.to)
                    put("color", colourJson(s.color))
                    if (s.bold) put("bold", true)
                },
            )
        }.toString()
    }

    private fun colourJson(c: BrandColor): JsonObject = buildJsonObject {
        put("kind", c.kind)
        when (c.kind) {
            BrandKinds.TOKEN -> put("token", c.token)
            BrandKinds.STATIC -> put("hex", c.hex)
            BrandKinds.GRADIENT -> {
                put("stops", buildJsonArray { c.stops.forEach { add(JsonPrimitive(it)) } })
                if (c.angle != 0) put("angle", c.angle)
            }
        }
    }

    // What `GET /settings` calls brandSpans, as a draft: spans over a name, the rest plain.
    fun fromSpans(name: String, raw: String, mark: BrandMarkChoice = BrandMarkChoice()): BrandDraft? {
        if (raw.isBlank()) return null
        val n = length(name)
        val looks = MutableList(n) { fg() }
        val array = runCatching { json.parseToJsonElement(raw).jsonArray }.getOrNull() ?: return null
        for (e in array) {
            val o = e as? JsonObject ?: return null
            val from = o["from"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: return null
            val to = o["to"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: return null
            val color = colourFrom(o["color"] as? JsonObject) ?: return null
            val bold = o["bold"]?.jsonPrimitive?.contentOrNull == "true"
            for (i in from until min(to, n)) if (i >= 0) looks[i] = BrandLook(color, bold)
        }
        return BrandDraft(name, looks, mark)
    }

    private fun colourFrom(o: JsonObject?): BrandColor? {
        o ?: return null
        val kind = o["kind"]?.jsonPrimitive?.contentOrNull ?: return null
        return BrandColor(
            kind, o["token"]?.jsonPrimitive?.contentOrNull.orEmpty(), o["hex"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            (o["stops"] as? JsonArray)?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty(), o["angle"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0,
        )
    }

    // MARK: saving (PUT /settings: brandName, brandColouring, brandSpans, brandMark)

    // The four settings, together, so a new name never keeps colours chosen for the old one. The automatic split and
    // the plain name are the server's own quick modes; anything else is spans, which win when set.
    fun settings(d: BrandDraft): Map<String, String> {
        val spans = spans(d)
        val plain = spans.isEmpty()
        val auto = matchesAuto(d)
        return mapOf(
            "brandName" to if (d.name == BrandName.DEFAULT) "" else d.name,
            "brandColouring" to if (auto) "auto" else if (plain) "one" else "auto",
            "brandSpans" to if (auto || plain) "" else spansJson(spans),
            "brandMark" to markJson(d.mark),
        )
    }

    fun problem(d: BrandDraft): String? = when {
        length(d.name) > MAX_RUNES -> "The name can be at most $MAX_RUNES characters."
        d.tooManySpans -> "That is more than $MAX_SPANS differently coloured pieces. Use a gradient, or colour words rather than letters."
        d.mark.kind == MARK_TEXT && length(d.mark.text.trim()) !in 1..2 -> "Your own mark is one or two characters."
        else -> null
    }

    // MARK: the mark

    fun markJson(m: BrandMarkChoice): String = when (m.kind) {
        MARK_INITIALS -> """{"kind":"initials"}"""
        MARK_IMAGE -> """{"kind":"image"}"""
        MARK_TEXT -> buildJsonObject { put("kind", "text"); put("text", m.text.trim()) }.toString()
        else -> ""
    }

    fun markFrom(raw: String): BrandMarkChoice {
        if (raw.isBlank()) return BrandMarkChoice()
        val o = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return BrandMarkChoice()
        val kind = o["kind"]?.jsonPrimitive?.contentOrNull.orEmpty()
        return if (kind in listOf(MARK_LETTER, MARK_INITIALS, MARK_TEXT, MARK_IMAGE)) BrandMarkChoice(kind, o["text"]?.jsonPrimitive?.contentOrNull.orEmpty()) else BrandMarkChoice()
    }

    // The characters the badge draws: the first letter, the initials (the first letter of each word, at most three) or
    // the owner's own.
    fun markShown(name: String, m: BrandMarkChoice): String {
        val shown = name.ifEmpty { BrandName.DEFAULT }
        return when (m.kind) {
            MARK_TEXT -> m.text.trim().take(2)
            MARK_INITIALS -> words(shown).take(3).joinToString("") { String(Character.toChars(points(shown)[it.first])) }.uppercase()
            else -> letters(shown.trim()).firstOrNull()?.uppercase().orEmpty()
        }
    }

    // MARK: hex and colours

    fun normalHex(text: String): String? {
        val t = text.trim().removePrefix("#")
        val digits = when (t.length) {
            3 -> t.map { "$it$it" }.joinToString("")
            6 -> t
            else -> return null
        }
        if (digits.any { it !in "0123456789abcdefABCDEF" }) return null
        return "#" + digits.lowercase()
    }

    // MARK: contrast (the server's rule: a fixed colour, or a gradient's stop, under 4.5:1 on a surface of the theme)

    private fun fixedHexes(c: BrandColor): List<String> = when (c.kind) {
        BrandKinds.STATIC -> listOf(c.hex)
        BrandKinds.GRADIENT -> c.stops
        else -> emptyList()
    }

    // A lighter or darker version of `hex` that reads on `surface`: moved towards white on a dark surface, black on a
    // light one, until it does.
    fun readable(hex: String, surface: ThemeColour): String? {
        val colour = ThemeColour.parse(hex) ?: return null
        val target = if (surface.luminance < 0.4) ThemeColour.WHITE else ThemeColour.BLACK
        for (step in 1..20) {
            val tried = colour.mixed(target, step * 0.05)
            if (tried.contrast(surface) >= NEED) return tried.hex
        }
        return null
    }

    // Every part in a fixed colour that is hard to read on a surface of a theme. Parts that follow the theme are the
    // theme's to get right. Administrators can still save it.
    fun contrast(d: BrandDraft, themes: List<BrandSurfaces>): List<BrandContrast> {
        val out = ArrayList<BrandContrast>()
        for (p in d.parts) {
            val color = p.color ?: continue
            for (hex in fixedHexes(color).distinct()) {
                val ink = ThemeColour.parse(hex) ?: continue
                for (t in themes) for ((surface, bg) in t.surfaces) {
                    val ratio = Math.round(ink.contrast(bg) * 100) / 100.0
                    if (ratio < NEED) out += BrandContrast(p.text, hex, surface, t.theme, ratio, NEED, readable(hex, bg))
                }
            }
        }
        return out.distinctBy { Triple(it.text, it.hex, it.theme + it.surface) }
    }

    // MARK: drawing helpers

    // The colour a token names in a theme: the same names the server's theme tokens have, with or without dashes.
    fun tokenColour(name: String, theme: AppTheme): ThemeColour? = when (name.lowercase().replace("-", "").replace("_", "")) {
        "fg", "text", "ink" -> theme.text
        "fg2", "textsecondary" -> theme.textSecondary
        "fg3", "texthint", "hint" -> theme.textHint
        "accent" -> theme.accent
        "accent2", "accentpressed" -> theme.accentPressed
        "accenttext" -> theme.accentText
        "brandaccent" -> theme.brandAccent
        "ok", "success" -> theme.ok
        "warn", "warning" -> theme.warn
        "danger", "error" -> theme.danger
        "bg", "background" -> theme.background
        "bg2", "panel" -> theme.panel
        "bg3", "card" -> theme.card
        "bg4", "raised" -> theme.raised
        "border" -> theme.border
        else -> null
    }

    // The colours of a gradient across `count` letters of one line. A single line only moves sideways, so the part of
    // the direction that points across counts: 90 degrees runs left to right, 270 right to left, 0 and 180 stay at the
    // middle colour.
    fun gradientLetters(stops: List<String>, angle: Int, count: Int): List<ThemeColour> {
        val colours = stops.mapNotNull { ThemeColour.parse(it) }
        if (colours.isEmpty() || count <= 0) return emptyList()
        if (colours.size == 1) return List(count) { colours[0] }
        val across = sin(Math.toRadians(angle.toDouble()))
        return List(count) { i ->
            val u = if (count == 1) 0.5 else i.toDouble() / (count - 1)
            val t = (0.5 + (u - 0.5) * across).coerceIn(0.0, 1.0)
            val x = t * (colours.size - 1)
            val a = min(x.toInt(), colours.size - 2)
            colours[a].mixed(colours[a + 1], x - a)
        }
    }

    // MARK: Hue, saturation and value, for the colour picker

    data class Hsv(val h: Double, val s: Double, val v: Double) {
        val hex: String
            get() {
                val c = v * s
                val x = c * (1 - abs((h / 60.0) % 2 - 1))
                val m = v - c
                val (r, g, b) = when {
                    h < 60 -> Triple(c, x, 0.0)
                    h < 120 -> Triple(x, c, 0.0)
                    h < 180 -> Triple(0.0, c, x)
                    h < 240 -> Triple(0.0, x, c)
                    h < 300 -> Triple(x, 0.0, c)
                    else -> Triple(c, 0.0, x)
                }
                fun byte(f: Double) = "%02x".format(((f + m) * 255).roundToInt().coerceIn(0, 255))
                return "#" + byte(r) + byte(g) + byte(b)
            }

        companion object {
            fun of(hex: String): Hsv {
                val c = ThemeColour.parse(hex) ?: return Hsv(0.0, 0.0, 1.0)
                val mx = max(c.red, max(c.green, c.blue))
                val mn = min(c.red, min(c.green, c.blue))
                val d = mx - mn
                val h = when {
                    d == 0.0 -> 0.0
                    mx == c.red -> 60 * (((c.green - c.blue) / d) % 6)
                    mx == c.green -> 60 * ((c.blue - c.red) / d + 2)
                    else -> 60 * ((c.red - c.green) / d + 4)
                }
                return Hsv(if (h < 0) h + 360 else h, if (mx == 0.0) 0.0 else d / mx, mx)
            }
        }
    }
}

// Which letters are chosen, for colouring: tap one, or a word, or press Space and move with the arrows to take a range.
data class LetterSelection(val picked: Set<Int> = emptySet(), val cursor: Int = 0, val anchor: Int? = null, val base: Set<Int> = emptySet()) {
    fun tap(i: Int): LetterSelection = copy(picked = if (i in picked) picked - i else picked + i, cursor = i, anchor = null, base = emptySet())

    fun onlyWord(range: IntRange): LetterSelection = copy(picked = range.toSet(), cursor = range.first, anchor = null, base = emptySet())

    fun all(count: Int): LetterSelection = copy(picked = (0 until count).toSet(), anchor = null, base = emptySet())

    fun none(): LetterSelection = copy(picked = emptySet(), anchor = null, base = emptySet())

    // Space: starts a range at the letter the cursor is on, and a second Space ends it, keeping what it took.
    fun space(): LetterSelection = if (anchor == null) copy(anchor = cursor, base = picked, picked = picked + cursor) else copy(anchor = null, base = emptySet())

    // An arrow: the cursor moves; with a range started, the range follows it.
    fun move(by: Int, count: Int): LetterSelection {
        if (count <= 0) return this
        val to = (cursor + by).coerceIn(0, count - 1)
        val a = anchor ?: return copy(cursor = to)
        val range = if (a <= to) a..to else to..a
        return copy(cursor = to, picked = base + range)
    }

    // The cursor put on a letter (focus landed on it): a started range follows.
    fun moveTo(i: Int, count: Int): LetterSelection = if (i == cursor) this else move(i - cursor, count)

    // The same letters after the name changed length.
    fun within(count: Int): LetterSelection = copy(picked = picked.filter { it < count }.toSet(), cursor = cursor.coerceIn(0, max(0, count - 1)), anchor = null, base = emptySet())
}

// A logo's file, checked before it is sent (the server's own rule is the same: PNG or JPEG, at most 2 MB, 16 to 4096
// pixels a side). The sizes are read from the file's own header, so it needs no decoder.
object LogoFile {
    const val MIN = 16
    const val MAX = 4096

    enum class Kind(val mime: String) { Png("image/png"), Jpeg("image/jpeg") }

    data class Info(val kind: Kind, val width: Int, val height: Int) {
        val square: Boolean get() = abs(width - height) <= max(2, min(width, height) / 50)
    }

    fun kindOf(b: ByteArray): Kind? = when {
        b.size > 8 && b[0] == 0x89.toByte() && b[1] == 'P'.code.toByte() && b[2] == 'N'.code.toByte() && b[3] == 'G'.code.toByte() -> Kind.Png
        b.size > 3 && b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte() && b[2] == 0xFF.toByte() -> Kind.Jpeg
        else -> null
    }

    private fun be(b: ByteArray, at: Int, n: Int): Int = (0 until n).fold(0) { acc, i -> (acc shl 8) or (b[at + i].toInt() and 0xff) }

    fun read(b: ByteArray): Info? {
        val kind = kindOf(b) ?: return null
        if (kind == Kind.Png) {
            if (b.size < 24) return null
            return Info(kind, be(b, 16, 4), be(b, 20, 4))
        }
        var i = 2
        while (i + 9 < b.size) {
            if (b[i] != 0xFF.toByte()) { i++; continue }
            val marker = b[i + 1].toInt() and 0xff
            if (marker == 0xFF) { i++; continue }
            if (marker in 0xC0..0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) return Info(kind, be(b, i + 7, 2), be(b, i + 5, 2))
            if (marker == 0xD8 || marker in 0xD0..0xD7 || marker == 0x01) { i += 2; continue }
            i += 2 + be(b, i + 2, 2)
        }
        return null
    }

    // The words to show when a file can't be used, or null when it can.
    fun problem(b: ByteArray): String? {
        if (b.size > BrandEditor.MAX_LOGO_BYTES) return "The logo must be 2 MB or smaller."
        val info = read(b) ?: return "Use a PNG or JPEG image."
        if (info.width < MIN || info.height < MIN || info.width > MAX || info.height > MAX) return "The logo must be between $MIN and $MAX pixels on each side."
        return null
    }
}

// GET /theme's `brand`, as far as the editor needs it: what the server drew, the mark it will use and its own contrast
// warnings (a fixed colour under 4.5:1 on a surface of the theme in force).
data class BrandServerView(val parts: List<BrandPart>, val mark: BrandMarkChoice, val shown: String, val imageUrl: String, val warnings: List<BrandServerWarning>) {
    companion object {
        fun from(theme: JsonObject): BrandServerView? {
            val brand = runCatching { theme["brand"]?.jsonObject }.getOrNull() ?: return null
            val parts = runCatching { json.decodeFromJsonElement(kotlinx.serialization.builtins.ListSerializer(BrandPart.serializer()), brand["parts"] ?: JsonArray(emptyList())) }.getOrDefault(emptyList())
            val mark = runCatching { brand["mark"]?.jsonObject }.getOrNull()
            val kind = mark?.get("kind")?.jsonPrimitive?.contentOrNull.orEmpty().ifEmpty { BrandEditor.MARK_LETTER }
            val warnings = (brand["warnings"] as? JsonArray).orEmpty().mapNotNull { w ->
                val o = w as? JsonObject ?: return@mapNotNull null
                BrandServerWarning(
                    o["text"]?.jsonPrimitive?.contentOrNull.orEmpty(), o["surface"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                    o["ratio"]?.jsonPrimitive?.contentOrNull?.toDoubleOrNull() ?: 0.0, o["need"]?.jsonPrimitive?.contentOrNull?.toDoubleOrNull() ?: BrandEditor.NEED,
                )
            }
            return BrandServerView(
                parts, BrandMarkChoice(kind, mark?.get("text")?.jsonPrimitive?.contentOrNull.orEmpty()),
                mark?.get("shown")?.jsonPrimitive?.contentOrNull.orEmpty(), mark?.get("imageUrl")?.jsonPrimitive?.contentOrNull.orEmpty(), warnings,
            )
        }
    }
}

data class BrandServerWarning(val text: String, val surface: String, val ratio: Double, val need: Double) {
    val words: String get() = "\"$text\" is ${"%.1f".format(ratio)} to 1 on the theme's ${surfaceName(surface)}; words should be at least ${"%.1f".format(need)} to 1."

    private fun surfaceName(s: String) = when (s) {
        "bg" -> "page"
        "bg2" -> "side menu and bars"
        "bg3" -> "cards"
        else -> s
    }
}
