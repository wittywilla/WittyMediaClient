// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.CssColour
import com.wittywilla.wittymediaclient.net.Look
import com.wittywilla.wittymediaclient.net.SceneLayer
import com.wittywilla.wittymediaclient.net.SceneStop
import kotlin.math.cos
import kotlin.math.sin

// The experience's finish (docs/THEMES.md, "A scene" and "A finish"): the theme's scene behind the page, glass panels and
// glossy buttons, and the type set. All of it comes from `GET /theme`'s `look`; with none, the page is its colour.

val LocalLook = compositionLocalOf { Look.NONE }

fun CssColour.toColor(): Color = Color(r.toFloat(), g.toFloat(), b.toFloat(), a.toFloat())

private fun List<SceneStop>.brushColours() = map { it.colour.toColor() }

// The scene's layers, bottom first, under everything the page draws. Positions are percent of the window. An image layer
// (a picture of the theme) is not drawn yet.
fun Modifier.scene(layers: List<SceneLayer>): Modifier = if (layers.isEmpty()) this else drawBehind {
    for (layer in layers) when (layer) {
        is SceneLayer.Gradient -> {
            // CSS angles: 180 is top to bottom, 90 left to right.
            val rad = Math.toRadians(layer.angle)
            val dx = sin(rad).toFloat()
            val dy = -cos(rad).toFloat()
            val half = (kotlin.math.abs(dx * size.width) + kotlin.math.abs(dy * size.height)) / 2f
            val c = Offset(size.width / 2, size.height / 2)
            val stops = layer.stops.map { (it.at / 100.0).toFloat().coerceIn(0f, 1f) to it.colour.toColor() }.toTypedArray()
            drawRect(Brush.linearGradient(*stops, start = Offset(c.x - dx * half, c.y - dy * half), end = Offset(c.x + dx * half, c.y + dy * half)))
        }
        is SceneLayer.Radial -> {
            val cx = size.width * (layer.x / 100.0).toFloat()
            val cy = size.height * (layer.y / 100.0).toFloat()
            val radius = size.width * (layer.w / 100.0).toFloat() / 2f
            drawCircle(Brush.radialGradient(listOf(layer.colour.toColor(), Color.Transparent), center = Offset(cx, cy), radius = radius.coerceAtLeast(1f)), radius, Offset(cx, cy))
        }
        is SceneLayer.Shape -> {
            val cx = size.width * (layer.x / 100.0).toFloat()
            val cy = size.height * (layer.y / 100.0).toFloat()
            val r = size.width * (layer.size / 100.0).toFloat()
            val paint: Brush = if (layer.stops.size >= 2) Brush.verticalGradient(layer.stops.brushColours(), startY = cy - r, endY = cy + r) else SolidColourBrush(layer.colour?.toColor() ?: Color.Transparent)
            if (layer.kind == "hill") {
                // A wide low mound: an ellipse sitting on its x, y.
                val p = Path().apply { addOval(androidx.compose.ui.geometry.Rect(cx - r, cy - r * 0.45f, cx + r, cy + r * 0.45f)) }
                drawPath(p, paint)
            } else drawCircle(paint, r / 2f, Offset(cx, cy))
        }
        is SceneLayer.Image -> Unit
    }
}

private fun SolidColourBrush(c: Color): Brush = Brush.linearGradient(listOf(c, c))

// A glass panel (hi over lo, a hairline edge) in the amount the look asks for.
@Composable
fun Modifier.glass(shape: Shape): Modifier {
    val look = LocalLook.current
    val recipe = look.glassRecipe ?: return this
    if (look.glass.factor == 0f) return this
    val f = look.glass.factor
    return background(Brush.verticalGradient(listOf(recipe.hi.toColor().scaled(f), recipe.lo.toColor().scaled(f))), shape)
        .border(1.dp, recipe.edge.toColor().scaled(f), shape)
}

// A glossy button's body: highlight on the upper half, then the upper and lower body colours, an edge round it.
@Composable
fun Modifier.gloss(shape: Shape): Modifier {
    val look = LocalLook.current
    val recipe = look.glossRecipe ?: return this
    if (look.gloss.factor == 0f) return this
    val f = look.gloss.factor
    return background(Brush.verticalGradient(0f to recipe.highlight.toColor().scaled(f), 0.5f to recipe.upper.toColor().scaled(f), 0.5001f to recipe.lower.toColor().scaled(f), 1f to recipe.lower.toColor().scaled(f)), shape)
        .border(1.dp, recipe.edge.toColor().scaled(f), shape)
}

private fun Color.scaled(f: Float) = if (f >= 1f) this else copy(alpha = alpha * f)

// The type set's face. Humanist and rounded use the system's nearest; mono and serif the system's own.
fun typeFace(set: String): FontFamily = when (set) {
    "rounded" -> FontFamily(android.graphics.Typeface.create("sans-serif-rounded", android.graphics.Typeface.NORMAL))
    "humanist" -> FontFamily(android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL))
    "mono" -> FontFamily.Monospace
    "serif" -> FontFamily.Serif
    else -> FontFamily.Default
}
