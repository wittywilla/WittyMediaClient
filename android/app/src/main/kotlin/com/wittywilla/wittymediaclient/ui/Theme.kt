package com.wittywilla.wittymediaclient.ui

import android.content.Context
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
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.toColorInt
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
data class ThemeData(val id: String, val scheme: String, val colours: ThemeColours)

@Serializable
data class ThemeFile(val defaultTheme: String, val themes: List<ThemeData>)

object Assets {
    private fun read(context: Context, name: String) = context.assets.open(name).bufferedReader().use { it.readText() }

    fun themes(context: Context): ThemeFile = json.decodeFromString(read(context, "themes.json"))

    fun strings(context: Context): Map<String, String> =
        json.decodeFromString<JsonObject>(read(context, "strings.en.json")).mapValues { it.value.jsonPrimitive.content }

    fun notice(context: Context): String = read(context, "NOTICE.txt")
}

private fun c(hex: String) = Color(hex.toColorInt())

// A theme uploaded to the server has no entry here, and gets the default look.
fun pickTheme(file: ThemeFile, id: String): ThemeData =
    file.themes.firstOrNull { it.id == id } ?: file.themes.first { it.id == file.defaultTheme }

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

// What differs between a phone in the hand and a TV across the room: the ten-foot rules.
data class Metrics(
    val tv: Boolean,
    val gutter: Dp,
    val edge: Dp,
    val cardWidth: Dp,
    val minTarget: Dp,
    val textScale: Float,
    val focusRing: Dp = 3.dp,
    val focusScale: Float = 1f,
)

val PhoneMetrics = Metrics(tv = false, gutter = Space.S4, edge = Space.S2, cardWidth = 124.dp, minTarget = 44.dp, textScale = 1f)
val TabletMetrics = PhoneMetrics.copy(gutter = Space.S8, cardWidth = 148.dp)

// A TV may crop its picture's edge, so the margins are wide; the base text grows by a quarter.
val TvMetrics = Metrics(tv = true, gutter = 58.dp, edge = 27.dp, cardWidth = 168.dp, minTarget = 48.dp, textScale = 1.25f, focusScale = 1.05f)

val LocalMetrics = compositionLocalOf { PhoneMetrics }

// The colours Material's scheme has no place for.
data class ExtraColours(val hint: Color, val accentText: Color, val ok: Color)

val LocalExtraColours = compositionLocalOf { ExtraColours(Color.Gray, Color.White, Color.Green) }

// When the system says to keep animation down, nothing moves unless the viewer moves it.
val LocalReduceMotion = compositionLocalOf { false }

private fun scaled(size: Int, scale: Float): TextUnit = (size * scale).sp

private fun typeScale(s: Float, sans: TextStyle = TextStyle.Default) = Typography(
    displayLarge = sans.copy(fontSize = scaled(48, s), fontWeight = FontWeight.Bold),
    displayMedium = sans.copy(fontSize = scaled(38, s), fontWeight = FontWeight.Bold),
    displaySmall = sans.copy(fontSize = scaled(30, s), fontWeight = FontWeight.Bold),
    headlineLarge = sans.copy(fontSize = scaled(30, s), fontWeight = FontWeight.SemiBold),
    headlineMedium = sans.copy(fontSize = scaled(24, s), fontWeight = FontWeight.SemiBold),
    headlineSmall = sans.copy(fontSize = scaled(20, s), fontWeight = FontWeight.SemiBold),
    titleLarge = sans.copy(fontSize = scaled(20, s), fontWeight = FontWeight.SemiBold),
    titleMedium = sans.copy(fontSize = scaled(17, s), fontWeight = FontWeight.SemiBold),
    titleSmall = sans.copy(fontSize = scaled(14, s), fontWeight = FontWeight.Medium),
    bodyLarge = sans.copy(fontSize = scaled(15, s), lineHeight = scaled(22, s)),
    bodyMedium = sans.copy(fontSize = scaled(13, s), lineHeight = scaled(19, s)),
    bodySmall = sans.copy(fontSize = scaled(12, s), lineHeight = scaled(17, s)),
    labelLarge = sans.copy(fontSize = scaled(14, s), fontWeight = FontWeight.Medium),
    labelMedium = sans.copy(fontSize = scaled(13, s), fontWeight = FontWeight.Medium),
    labelSmall = sans.copy(fontSize = scaled(11, s), fontWeight = FontWeight.Medium),
)

@Composable
fun WittyTheme(theme: ThemeData, metrics: Metrics, reduceMotion: Boolean, content: @Composable () -> Unit) {
    val t = theme.colours
    val scheme = remember(theme) {
        if (theme.scheme == "light") {
            lightColorScheme(
                primary = c(t.accent), onPrimary = c(t.onAccent), background = c(t.background), onBackground = c(t.text),
                surface = c(t.panel), onSurface = c(t.text), surfaceVariant = c(t.card), onSurfaceVariant = c(t.textSecondary),
                outline = c(t.border), error = c(t.danger),
            )
        } else {
            darkColorScheme(
                primary = c(t.accent), onPrimary = c(t.onAccent), background = c(t.background), onBackground = c(t.text),
                surface = c(t.panel), onSurface = c(t.text), surfaceVariant = c(t.card), onSurfaceVariant = c(t.textSecondary),
                outline = c(t.border), error = c(t.danger),
            )
        }
    }
    val extra = remember(theme) { ExtraColours(c(t.textHint), c(t.accentText), c(t.ok)) }
    val type = remember(metrics.textScale) { typeScale(metrics.textScale) }
    CompositionLocalProvider(LocalMetrics provides metrics, LocalExtraColours provides extra, LocalReduceMotion provides reduceMotion) {
        MaterialTheme(colorScheme = scheme, typography = type, content = content)
    }
}
