package com.wittywilla.wittymediaclient.ui

import android.content.Context
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.AppTheme
import com.wittywilla.wittymediaclient.net.ThemeColour
import com.wittywilla.wittymediaclient.net.ThemeTokens
import com.wittywilla.wittymediaclient.net.ThemeTranslator
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

// Themes and wording are shared data: see shared/data/, bundled as assets. Sizes come from the
// server's design tokens (themes/tokens.json, explained in its docs/DESIGN.md): pixels there are dp
// here. Text is in sp, so it follows the person's own text size.

@Serializable
data class ThemeColours(
    val background: String,
    val panel: String,
    val card: String,
    val border: String,
    val text: String,
    val textSecondary: String,
    val textHint: String = textSecondary,
    val accent: String,
    val onAccent: String,
    val accentText: String = accent,
    val danger: String,
    val ok: String = accent,
)

@Serializable
data class ThemeData(val id: String, val scheme: String, val colours: ThemeColours, val name: String = id)

@Serializable
data class ThemeFile(val defaultTheme: String, val themes: List<ThemeData>)

object Assets {
    private fun read(context: Context, name: String) = context.assets.open(name).bufferedReader().use { it.readText() }

    fun themes(context: Context): ThemeFile = json.decodeFromString(read(context, "themes.json"))

    fun strings(context: Context): Map<String, String> =
        json.decodeFromString<JsonObject>(read(context, "strings.en.json")).mapValues { it.value.jsonPrimitive.content }

    fun notice(context: Context): String = read(context, "NOTICE.txt")
}

// A built-in theme as the server's tokens would give it, for the translation layer: so the first screen has
// colours before any answer, and a server that can't be reached still looks right.
fun ThemeData.asTokens() = ThemeTokens(
    id = id, name = name, scheme = scheme,
    colors = mapOf(
        "bg" to colours.background, "bg-2" to colours.panel, "bg-3" to colours.card, "border" to colours.border,
        "fg" to colours.text, "fg-2" to colours.textSecondary, "fg-3" to colours.textHint, "accent" to colours.accent,
        "accent-fg" to colours.onAccent, "accent-text" to colours.accentText, "danger" to colours.danger, "ok" to colours.ok,
    ),
)

// A built-in theme, translated; one this app doesn't know gets the default look.
fun bundledTheme(file: ThemeFile, id: String): AppTheme =
    ThemeTranslator.translate((file.themes.firstOrNull { it.id == id } ?: file.themes.first { it.id == file.defaultTheme }).asTokens())

// The 4dp grid.
object Space {
    val S1 = 4.dp
    val S2 = 8.dp
    val S3 = 12.dp
    val S4 = 16.dp
    val S5 = 20.dp
    val S6 = 24.dp
    val S8 = 32.dp
    val S10 = 40.dp
    val S12 = 48.dp
    val S16 = 64.dp
}

object Radius {
    val XS = RoundedCornerShape(4.dp)
    val SM = RoundedCornerShape(6.dp)
    val MD = RoundedCornerShape(10.dp) // buttons, fields, posters
    val LG = RoundedCornerShape(14.dp) // panels
    val XL = RoundedCornerShape(20.dp)
    val FULL = RoundedCornerShape(percent = 50) // pills
}

// What differs between a phone in the hand and a TV across the room: the ten-foot rules. A TV's sizes
// in docs/APP-DESIGN.md are TV units, half a dp each here (960x540 dp), so one layout fits both TVs.
data class Metrics(
    val tv: Boolean,
    val gutter: Dp,
    val edge: Dp,
    val cardWidth: Dp,
    val minTarget: Dp,
    val focusRing: Dp = 3.dp,
    val focusScale: Float = 1f,
    // dp in one of the page's units: 1 on a phone or tablet, 0.5 on a TV.
    val unit: Float = 1f,
    val tablet: Boolean = false,
    // The theme's medium radius (docs/APP-DESIGN.md, Themes): corners follow the theme in use.
    val themeRadius: Float = 10f,
)

// A size from the page: points on a phone or tablet, TV units on a TV.
fun Metrics.u(size: Number): Dp = (size.toFloat() * unit).dp

// The page's radii in the same units, following the theme's: asked for as the default theme's 6 small, 10 medium,
// 14 large or 20 extra, they're the theme's radius − 4 (at least 2), its radius, + 4 and + 10. Others stay as they are.
fun Metrics.corner(radius: Int): RoundedCornerShape {
    val r = themeRadius
    val shaped = when (radius) {
        6 -> maxOf(2f, r - 4)
        10 -> r
        14 -> r + 4
        20 -> r + 10
        else -> radius.toFloat()
    }
    return RoundedCornerShape(u(shaped))
}

val PhoneMetrics = Metrics(tv = false, gutter = Space.S4, edge = Space.S2, cardWidth = 124.dp, minTarget = 44.dp)
val TabletMetrics = PhoneMetrics.copy(gutter = Space.S8, cardWidth = 148.dp, tablet = true)

// A TV may crop its picture's edge, so the margins are wide: 90 units, as Apple TV's. Focus is a 4-unit
// ring round the thing and 1.05 larger, as Apple TV draws it.
val TvMetrics = Metrics(
    tv = true, gutter = 45.dp, edge = 30.dp, cardWidth = 168.dp, minTarget = 24.dp,
    focusRing = 2.dp, focusScale = 1.05f, unit = 0.5f,
)

// Apple TV keeps everything inside the picture's safe area, 80 units in from the sides and 60 from the top
// and bottom, and a sign-in screen's margins sit inside that: so its words start 170 units from the edge.
val Metrics.tvSafeSides get() = u(80)
val Metrics.tvSafeEnds get() = u(60)

val LocalMetrics = compositionLocalOf { PhoneMetrics }

// The colours Material's scheme has no place for.
data class ExtraColours(
    val hint: Color,
    val accentText: Color,
    val ok: Color,
    val raised: Color = Color.DarkGray,
    val control: Color = Color.Gray,
    val warn: Color = Color.Yellow,
    val accentPressed: Color = Color.Gray,
    val scrim: Color = Color.Black,
)

val LocalExtraColours = compositionLocalOf { ExtraColours(Color.Gray, Color.White, Color.Green) }

// When the system says to keep animation down, nothing moves unless the viewer moves it.
val LocalReduceMotion = compositionLocalOf { false }

// docs/APP-DESIGN.md, "Type": the phone's sizes in sp, and a TV's in TV units. Sizes it doesn't name,
// such as a poster's title, follow the nearest one that it does.
private class TypeSizes(
    val display: Float, val title: Float, val headline: Float, val section: Float,
    val body: Float, val label: Float, val secondary: Float, val caption: Float, val scale: Float,
    val lineHeight: Float,
)

private val PhoneType = TypeSizes(30f, 24f, 20f, 17f, 15f, 15f, 13f, 12f, scale = 1f, lineHeight = 1.45f)

// A TV uses the sizes Apple TV draws with, so the two TVs look the same (docs/APP-DESIGN.md, On a TV): tvOS's own
// text styles, in TV units. Display is tvOS's Title 1 (76), a page's heading Title 2 (57), the profile name Title 3
// (48), above a row Headline (38), words and buttons 29, captions 25. Lines as tall as San Francisco's.
private val TvType = TypeSizes(76f, 57f, 48f, 38f, 29f, 29f, 29f, 25f, scale = 0.5f, lineHeight = 1.2f)

private fun typeScale(t: TypeSizes, sans: TextStyle = TextStyle.Default): Typography {
    fun sp(size: Float) = (size * t.scale).sp
    fun lines(size: Float) = (size * t.scale * t.lineHeight).sp
    return Typography(
        displayLarge = sans.copy(fontSize = sp(t.display * 1.6f), fontWeight = FontWeight.Bold),
        displayMedium = sans.copy(fontSize = sp(t.display * 1.27f), fontWeight = FontWeight.Bold),
        displaySmall = sans.copy(fontSize = sp(t.display), lineHeight = lines(t.display), fontWeight = FontWeight.Bold),
        headlineLarge = sans.copy(fontSize = sp(t.display), fontWeight = FontWeight.SemiBold),
        headlineMedium = sans.copy(fontSize = sp(t.title), lineHeight = lines(t.title), fontWeight = FontWeight.SemiBold),
        headlineSmall = sans.copy(fontSize = sp(t.headline), lineHeight = lines(t.headline), fontWeight = FontWeight.SemiBold),
        titleLarge = sans.copy(fontSize = sp(t.headline), lineHeight = lines(t.headline), fontWeight = FontWeight.SemiBold),
        titleMedium = sans.copy(fontSize = sp(t.section), lineHeight = lines(t.section), fontWeight = FontWeight.SemiBold),
        titleSmall = sans.copy(fontSize = sp(t.label - 1), lineHeight = lines(t.label - 1), fontWeight = FontWeight.Medium),
        bodyLarge = sans.copy(fontSize = sp(t.body), lineHeight = lines(t.body)),
        bodyMedium = sans.copy(fontSize = sp(t.secondary), lineHeight = lines(t.secondary)),
        bodySmall = sans.copy(fontSize = sp(t.caption), lineHeight = lines(t.caption)),
        labelLarge = sans.copy(fontSize = sp(t.label), lineHeight = lines(t.label), fontWeight = FontWeight.Medium),
        labelMedium = sans.copy(fontSize = sp(t.secondary), lineHeight = lines(t.secondary), fontWeight = FontWeight.Medium),
        labelSmall = sans.copy(fontSize = sp(t.caption), lineHeight = lines(t.caption), fontWeight = FontWeight.Medium),
    )
}


// The page's names for the type, so screens say which one they mean.
val Typography.display get() = displaySmall
val Typography.title get() = headlineMedium
val Typography.headline get() = headlineSmall
val Typography.section get() = titleMedium
val Typography.body get() = bodyLarge
val Typography.label get() = labelLarge
val Typography.secondary get() = bodyMedium
val Typography.caption get() = labelSmall

@Composable
fun WittyTheme(theme: AppTheme, metrics: Metrics, reduceMotion: Boolean, words: Map<String, String>, content: @Composable () -> Unit) {
    // A new theme cross-fades in 200 ms, or at once with Reduce Motion.
    @Composable
    fun shown(c: ThemeColour): Color =
        animateColorAsState(Color(c.argb), if (reduceMotion) snap() else tween(THEME_FADE_MS), label = "theme").value
    val accent = shown(theme.accent)
    val onAccent = shown(theme.onAccent)
    val background = shown(theme.background)
    val text = shown(theme.text)
    val panel = shown(theme.panel)
    val card = shown(theme.card)
    val secondary = shown(theme.textSecondary)
    val border = shown(theme.border)
    val danger = shown(theme.danger)
    val control = shown(theme.control)
    val scheme = if (theme.isLight) {
        lightColorScheme(
            primary = accent, onPrimary = onAccent, background = background, onBackground = text,
            surface = panel, onSurface = text, surfaceVariant = card, onSurfaceVariant = secondary,
            outline = border, outlineVariant = control, error = danger,
        )
    } else {
        darkColorScheme(
            primary = accent, onPrimary = onAccent, background = background, onBackground = text,
            surface = panel, onSurface = text, surfaceVariant = card, onSurfaceVariant = secondary,
            outline = border, outlineVariant = control, error = danger,
        )
    }
    val extra = ExtraColours(
        shown(theme.textHint), shown(theme.accentText), shown(theme.ok), shown(theme.raised), control,
        shown(theme.warn), shown(theme.accentPressed), shown(theme.scrim),
    )
    val type = remember(metrics.tv) { typeScale(if (metrics.tv) TvType else PhoneType) }
    CompositionLocalProvider(
        LocalMetrics provides metrics.copy(themeRadius = theme.radius.toFloat()), LocalExtraColours provides extra,
        LocalReduceMotion provides reduceMotion, LocalWords provides words,
    ) {
        MaterialTheme(colorScheme = scheme, typography = type, content = content)
    }
}

private const val THEME_FADE_MS = 200
