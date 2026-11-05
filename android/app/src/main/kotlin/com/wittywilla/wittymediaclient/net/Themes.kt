package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

// Every theme the server has, in the app: docs/APP-DESIGN.md, Themes. A theme comes as data, the CSS variables of
// the server's theme (GET /themes/{id}/tokens.json), and is translated here into the roles the app draws with.
// The same layer as Apple's WittyKit Theme.swift, rule for rule. Nothing here touches Android, so it's tested
// as plain Kotlin.

// One colour, red, green, blue and alpha from 0 to 1.
data class ThemeColour(val red: Double, val green: Double, val blue: Double, val alpha: Double = 1.0) {
    val hex: String
        get() {
            fun byte(v: Double) = "%02x".format(Math.round(max(0.0, min(1.0, v)) * 255).toInt())
            val rgb = "#" + byte(red) + byte(green) + byte(blue)
            return if (alpha >= 1) rgb else rgb + byte(alpha)
        }

    // Moved `amount` of the way towards another, alpha included.
    fun mixed(other: ThemeColour, amount: Double) = ThemeColour(
        red + (other.red - red) * amount, green + (other.green - green) * amount,
        blue + (other.blue - blue) * amount, alpha + (other.alpha - alpha) * amount,
    )

    fun opacity(value: Double) = copy(alpha = value)

    // Drawn over an opaque colour: what the eye sees.
    fun over(base: ThemeColour) = ThemeColour(
        red * alpha + base.red * (1 - alpha), green * alpha + base.green * (1 - alpha), blue * alpha + base.blue * (1 - alpha),
    )

    // WCAG relative luminance.
    val luminance: Double
        get() {
            fun linear(c: Double) = if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

    fun contrast(other: ThemeColour): Double {
        val a = luminance
        val b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // As an Android colour int, ARGB.
    val argb: Int
        get() {
            fun c(v: Double) = Math.round(max(0.0, min(1.0, v)) * 255).toInt()
            return (c(alpha) shl 24) or (c(red) shl 16) or (c(green) shl 8) or c(blue)
        }

    companion object {
        val WHITE = ThemeColour(1.0, 1.0, 1.0)
        val BLACK = ThemeColour(0.0, 0.0, 0.0)
        val INK = parse("#0e1013")!!

        // #RGB, #RRGGBB or #RRGGBBAA; anything else is null, so a fallback is used.
        fun parse(text: String?): ThemeColour? {
            var digits = text?.trim() ?: return null
            if (!digits.startsWith("#")) return null
            digits = digits.drop(1)
            if (digits.any { it !in "0123456789abcdefABCDEF" }) return null
            if (digits.length == 3) digits = digits.map { "$it$it" }.joinToString("")
            if (digits.length != 6 && digits.length != 8) return null
            val value = digits.toLong(16)
            return if (digits.length == 6) {
                ThemeColour(((value shr 16) and 0xff) / 255.0, ((value shr 8) and 0xff) / 255.0, (value and 0xff) / 255.0)
            } else {
                ThemeColour(((value shr 24) and 0xff) / 255.0, ((value shr 16) and 0xff) / 255.0, ((value shr 8) and 0xff) / 255.0, (value and 0xff) / 255.0)
            }
        }
    }
}

// What the app draws with, translated from a theme.
data class AppTheme(
    val id: String,
    val name: String,
    val isLight: Boolean,
    val background: ThemeColour,
    val panel: ThemeColour,
    val card: ThemeColour,
    val raised: ThemeColour,
    val border: ThemeColour,
    val control: ThemeColour,
    val text: ThemeColour,
    val textSecondary: ThemeColour,
    val textHint: ThemeColour,
    val accent: ThemeColour,
    val accentPressed: ThemeColour,
    val onAccent: ThemeColour,
    val accentText: ThemeColour,
    val danger: ThemeColour,
    val ok: ThemeColour,
    val warn: ThemeColour,
    val scrim: ThemeColour,
    // The medium radius: buttons, fields, posters.
    val radius: Double,
)

// GET /themes/{id}/tokens.json. Lengths are kept loose: one an uploaded theme wrote oddly is left out, not the theme.
@Serializable
data class ThemeTokens(
    val id: String = "",
    val name: String? = null,
    val scheme: String? = null,
    val colors: Map<String, String>? = null,
    val lengths: Map<String, JsonElement>? = null,
    val webOnly: Boolean? = null,
) {
    fun length(key: String): Double? {
        val raw = lengths?.get(key) as? JsonPrimitive ?: return null
        return raw.doubleOrNull ?: raw.content.toDoubleOrNull()
    }
}

// GET /themes: what's on offer, with four colours each to draw a swatch before its tokens are read.
@Serializable
data class ThemeList(val themes: List<ThemeSummary> = emptyList(), val default: String = "") {
    @Serializable
    data class ThemeSummary(
        val id: String = "",
        val name: String = "",
        val scheme: String = "",
        val webOnly: Boolean = false,
        val builtin: Boolean = false,
        val modTime: Long = 0,
        val preview: Preview? = null,
    ) {
        val shownName: String get() = cleanName(name).ifEmpty { id }
    }

    @Serializable
    data class Preview(val bg: String? = null, val surface: String? = null, val text: String? = null, val accent: String? = null)
}

// The person's own look from the theme maker, kept in their account under `customTheme` in GET /me/ui.
@Serializable
data class ThemeMakerInput(
    val name: String = "",
    val scheme: String = "dark",
    val accent: String = "",
    val tint: String = "",
    val corners: String = "soft",
)

@Serializable
data class MeUi(val customTheme: ThemeMakerInput? = null)

// A name a theme gives itself, as plain words of sensible length.
fun cleanName(name: String): String =
    name.filter { !it.isISOControl() }.trim().replace(Regex("\\s+"), " ").take(40)

object ThemeTranslator {
    // The default theme's colours: the last fallback for anything a theme lacks.
    val WITTY = mapOf(
        "bg" to "#0f1115", "bg-2" to "#171a21", "bg-3" to "#1f232c", "bg-4" to "#2a2f3a", "border" to "#e8eaf01a",
        "control-line" to "#e8eaf033", "fg" to "#e8eaf0", "fg-2" to "#a9afbd", "fg-3" to "#848b99", "accent" to "#7955ff",
        "accent-2" to "#6a45f0", "accent-fg" to "#ffffff", "accent-text" to "#9174ff", "danger" to "#ff5c6c", "ok" to "#3ad29f",
        "warn" to "#e0a030", "overlay" to "#00000099",
    )

    private fun base(key: String) = ThemeColour.parse(WITTY.getValue(key))!!

    // A theme from its tokens, with its list entry's preview for anything the tokens lack: docs/APP-DESIGN.md,
    // Themes, Translation.
    fun translate(tokens: ThemeTokens, preview: ThemeList.Preview? = null): AppTheme {
        val colors = tokens.colors.orEmpty()
        fun token(key: String) = ThemeColour.parse(colors[key]) ?: ThemeColour.parse(colors[key.lowercase()])
        val background = token("bg") ?: ThemeColour.parse(preview?.bg) ?: base("bg")
        val text = token("fg") ?: ThemeColour.parse(preview?.text) ?: base("fg")
        val accent = token("accent") ?: ThemeColour.parse(preview?.accent) ?: base("accent")
        val panel = token("bg-2") ?: background.mixed(text, 0.04)
        val card = token("bg-3") ?: ThemeColour.parse(preview?.surface) ?: background.mixed(text, 0.09)
        val raised = token("bg-4") ?: card.mixed(text, 0.06)
        val onAccent = token("accent-fg")
            ?: if (ThemeColour.WHITE.contrast(accent) >= ThemeColour.INK.contrast(accent)) ThemeColour.WHITE else ThemeColour.INK
        val isLight = when (tokens.scheme) {
            "light" -> true
            "dark" -> false
            else -> background.luminance > 0.4
        }
        val radius = tokens.length("radius")?.takeIf { it in 0.0..40.0 } ?: 10.0
        return AppTheme(
            id = tokens.id,
            name = cleanName(tokens.name.orEmpty()).ifEmpty { tokens.id },
            isLight = isLight,
            background = background,
            panel = panel,
            card = card,
            raised = raised,
            border = token("border") ?: text.opacity(0.10),
            control = token("control-line") ?: text.opacity(0.20),
            text = text,
            textSecondary = token("fg-2") ?: text.opacity(0.72).over(background),
            textHint = token("fg-3") ?: text.opacity(0.55).over(background),
            accent = accent,
            accentPressed = token("accent-2") ?: accent.mixed(ThemeColour.BLACK, 0.10),
            onAccent = onAccent,
            accentText = token("accent-text") ?: accent,
            danger = token("danger") ?: base("danger"),
            ok = token("ok") ?: base("ok"),
            warn = token("warn") ?: base("warn"),
            scrim = token("overlay") ?: ThemeColour.BLACK.opacity(0.6),
            radius = radius,
        )
    }

    // The person's own look, made exactly as the website's theme maker makes it.
    fun translateMade(input: ThemeMakerInput): AppTheme {
        val made = ThemeMaker.make(input)
        val tokens = ThemeTokens(
            id = CUSTOM_THEME, name = input.name, scheme = if (input.scheme == "light") "light" else "dark",
            colors = made.vars, lengths = mapOf("radius" to JsonPrimitive(made.radius)),
        )
        return translate(tokens)
    }

    const val CUSTOM_THEME = "custom"
}

// The server's theme maker (web/src/ui/themeMaker.ts, makeTheme), step for step: a whole theme from a few choices,
// every colour checked as it's made so anything picked is readable. Tested against
// shared/data/theme-maker-examples.json, worked out by running the website's own code. JavaScript's Math.round
// rounds halves up and its % keeps the dividend's sign; Kotlin's Math.round and rem do the same for these values.
object ThemeMaker {
    data class Made(val vars: Map<String, String>, val radius: Int, val adjusted: Boolean)

    private data class Rgb(val a: Double, val b: Double, val c: Double)

    fun isHex(s: String) = s.length == 7 && s.startsWith("#") && s.drop(1).all { it in "0123456789abcdefABCDEF" }

    private fun toRgb(h: String) = Rgb(h.substring(1, 3).toInt(16) / 255.0, h.substring(3, 5).toInt(16) / 255.0, h.substring(5, 7).toInt(16) / 255.0)

    private fun toHex(c: Rgb): String {
        fun byte(v: Double) = "%02x".format(floor(max(0.0, min(1.0, v)) * 255 + 0.5).toInt())
        return "#" + byte(c.a) + byte(c.b) + byte(c.c)
    }

    private fun luminance(c: Rgb): Double {
        fun f(v: Double) = if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        return 0.2126 * f(c.a) + 0.7152 * f(c.b) + 0.0722 * f(c.c)
    }

    fun contrast(a: String, b: String): Double {
        val la = luminance(toRgb(a))
        val lb = luminance(toRgb(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private fun toHsl(c: Rgb): Rgb {
        val (r, g, b) = c
        val mx = maxOf(r, g, b)
        val mn = minOf(r, g, b)
        val l = (mx + mn) / 2
        val d = mx - mn
        if (d == 0.0) return Rgb(0.0, 0.0, l)
        val s = d / (1 - abs(2 * l - 1))
        val h = when (mx) {
            r -> ((g - b) / d + 6) % 6
            g -> (b - r) / d + 2
            else -> (r - g) / d + 4
        }
        return Rgb(h / 6, s, l)
    }

    private fun fromHsl(hsl: Rgb): Rgb {
        val (h, s, l) = hsl
        val c = (1 - abs(2 * l - 1)) * s
        val x = c * (1 - abs((h * 6) % 2 - 1))
        val m = l - c / 2
        val i = ((floor(h * 6).toInt() % 6) + 6) % 6
        val (r, g, b) = listOf(Rgb(c, x, 0.0), Rgb(x, c, 0.0), Rgb(0.0, c, x), Rgb(0.0, x, c), Rgb(x, 0.0, c), Rgb(c, 0.0, x))[i]
        return Rgb(r + m, g + m, b + m)
    }

    private fun shade(hue: Double, sat: Double, l: Double) = toHex(fromHsl(Rgb(hue, sat, l)))

    // The colour, moved in lightness only as far as it takes to reach `need` against all of `on`.
    private fun reach(color: String, on: List<String>, need: Double, lighter: Boolean): String {
        val (h, s, start) = toHsl(toRgb(color))
        var l = start
        repeat(220) {
            val c = toHex(fromHsl(Rgb(h, s, l)))
            if (on.all { contrast(c, it) >= need }) return c
            l = max(0.0, min(1.0, l + if (lighter) 0.005 else -0.005))
        }
        return if (lighter) "#ffffff" else "#000000"
    }

    private val CORNERS = mapOf("square" to 2, "soft" to 10, "round" to 18)
    private const val INK = "#0e1013"

    fun make(i: ThemeMakerInput): Made {
        val dark = i.scheme == "dark"
        val accent0 = if (isHex(i.accent)) i.accent else "#7955ff"
        val tintHsl = toHsl(toRgb(if (isHex(i.tint)) i.tint else accent0))
        val hue = tintHsl.a
        val tintSat = tintHsl.b
        // Surfaces take the tint's hue, held back so the page stays calm.
        val sat = min(tintSat, if (dark) 0.32 else 0.28)
        fun surface(dk: Double, lt: Double) = shade(hue, sat, if (dark) dk else lt)
        val bg = surface(0.07, 0.96)
        val bg2 = surface(0.1, 0.995)
        val bg3 = surface(0.14, 0.92)
        val bg4 = surface(0.19, 0.86)
        val surfaces = listOf(bg, bg2, bg3)
        fun text(dk: Double, lt: Double, s: Double = 0.12) = reach(shade(hue, min(sat, s), if (dark) dk else lt), surfaces, 4.5, dark)
        // A label on the accent is white or ink, whichever reads better; if neither reaches 4.5:1 the accent moves just enough.
        val label = if (contrast("#ffffff", accent0) >= contrast(INK, accent0)) "#ffffff" else INK
        val accent = reach(accent0, listOf(label), 4.5, label == INK)
        val a = toHsl(toRgb(accent))
        val hover = toHex(fromHsl(Rgb(a.a, a.b, max(0.0, min(1.0, a.c + if (label == INK) 0.06 else -0.06)))))
        fun status(c: String) = reach(c, surfaces, 4.5, dark)
        return Made(
            vars = mapOf(
                "bg" to bg, "bg-2" to bg2, "bg-3" to bg3, "bg-4" to bg4,
                "fg" to text(0.93, 0.1), "fg-2" to text(0.72, 0.3), "fg-3" to text(0.6, 0.38),
                "accent" to accent, "accent-2" to reach(hover, listOf(label), 4.5, label == INK), "accent-fg" to label,
                "accent-text" to reach(accent, surfaces, 4.5, dark),
                "control-line" to reach(bg4, surfaces, 3.0, dark),
                "danger" to status(if (dark) "#ff5c6c" else "#cf2537"), "ok" to status(if (dark) "#3ad29f" else "#117b50"),
                "warn" to status(if (dark) "#e0a030" else "#9b5d00"),
            ),
            radius = CORNERS[i.corners] ?: 10,
            adjusted = accent.lowercase() != accent0.lowercase(),
        )
    }
}
