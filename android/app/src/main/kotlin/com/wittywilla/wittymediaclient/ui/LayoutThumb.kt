// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.ThumbSpec

// A small wireframe of a look's layout: the menu and where it is, Home's arrangement, the cards and the dock, drawn in the
// colours it is given (the previewed theme's, by default the theme in use). Used wherever looks are chosen.
@Composable
fun LayoutThumb(spec: ThumbSpec, name: String, modifier: Modifier = Modifier, bg: Color = MaterialTheme.colorScheme.background, panel: Color = MaterialTheme.colorScheme.surface, card: Color = MaterialTheme.colorScheme.surfaceVariant, accent: Color = MaterialTheme.colorScheme.primary, ink: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Canvas(modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(6.dp)).semantics { contentDescription = "$name layout" }) {
        drawWire(spec, bg, panel, card, accent, ink)
    }
}

private fun DrawScope.box(x: Float, y: Float, w: Float, h: Float, c: Color, r: Float = 2f) = drawRoundRect(c, Offset(x, y), Size(w, h), CornerRadius(r, r))

internal fun DrawScope.drawWire(s: ThumbSpec, bg: Color, panel: Color, card: Color, accent: Color, ink: Color) {
    val w = size.width
    val h = size.height
    drawRect(bg)
    val u = w / 100f
    // The menu: where it goes decides what is left for the page.
    var left = 0f
    var top = 0f
    var bottom = 0f
    when (s.nav) {
        "sidebar" -> { box(0f, 0f, 22 * u, h, panel, 0f); left = 22 * u; for (i in 0 until 4) box(3 * u, (8 + i * 9) * u, 16 * u, 3 * u, if (i == 0) accent else ink.copy(alpha = 0.5f)) }
        "rail", "side" -> { box(0f, 0f, 9 * u, h, panel, 0f); left = 9 * u; box(2.5f * u, 4 * u, 4 * u, 4 * u, accent); for (i in 0 until 4) box(3 * u, (14 + i * 8) * u, 3 * u, 3 * u, ink.copy(alpha = 0.5f)) }
        "bottom" -> { box(0f, h - 9 * u, w, 9 * u, panel, 0f); bottom = 9 * u; for (i in 0 until 4) box((18 + i * 18) * u, h - 6 * u, 6 * u, 3 * u, if (i == 0) accent else ink.copy(alpha = 0.5f)) }
        "crossbar" -> { box(0f, 0f, w, 12 * u, panel, 0f); top = 12 * u; for (i in 0 until 5) box((8 + i * 16) * u, 4 * u, 8 * u, 4 * u, if (i == 2) accent else ink.copy(alpha = 0.5f)) }
        "none" -> Unit
        else -> { box(0f, 0f, w, 9 * u, panel.copy(alpha = if (s.glass) 0.8f else 1f), 0f); top = 9 * u; box(3 * u, 3 * u, 8 * u, 3 * u, accent); for (i in 0 until 4) box((20 + i * 12) * u, 3.2f * u, 8 * u, 2.6f * u, ink.copy(alpha = 0.5f)) }
    }
    val x0 = left + 3 * u
    val x1 = w - 3 * u
    var y = top + 3 * u
    val dockH = if (s.dock) 8 * u else 0f
    val limit = h - bottom - dockH - 2 * u
    when (s.home) {
        "billboard" -> { box(left, top, w - left, 26 * u, card, 0f); box(x0, top + 14 * u, 22 * u, 3 * u, ink); box(x0, top + 19 * u, 10 * u, 4 * u, accent, 3f); y = top + 29 * u }
        "banner" -> { box(x0, y, x1 - x0, 16 * u, card, 4f); box(x0 + 3 * u, y + 11 * u, 8 * u, 3 * u, accent); y += 19 * u }
        "carousel" -> { val cw = 20 * u; box(left + (w - left) / 2 - cw / 2, y, cw, 30 * u, card, 3f); box(left + (w - left) / 2 - cw * 1.5f - 2 * u, y + 4 * u, cw * 0.8f, 24 * u, card.copy(alpha = 0.6f), 3f); box(left + (w - left) / 2 + cw * 0.7f + 2 * u, y + 4 * u, cw * 0.8f, 24 * u, card.copy(alpha = 0.6f), 3f); y += 33 * u }
        "widgets" -> { val gw = (x1 - x0 - 2 * u) / 2; box(x0, y, gw, 14 * u, card, 3f); box(x0 + gw + 2 * u, y, gw, 14 * u, card, 3f); box(x0, y + 16 * u, x1 - x0, 12 * u, card, 3f); y += 31 * u }
        "list" -> { var yy = y; while (yy + 6 * u < limit) { box(x0, yy, 6 * u, 4 * u, accent.copy(alpha = 0.7f)); box(x0 + 9 * u, yy, (x1 - x0) - 9 * u, 4 * u, card, 2f); yy += 7 * u }; y = limit }
        else -> Unit
    }
    // Rows of cards in the shape the look draws them.
    if (s.home != "list") {
        val (cw, ch) = when (s.cards) { "wide", "block" -> 18 * u to 10 * u; "square" -> 11 * u to 11 * u; else -> 9 * u to 13 * u }
        var rowY = y
        while (rowY + ch < limit) {
            box(x0, rowY, 12 * u, 2.2f * u, ink.copy(alpha = 0.6f), 1f)
            rowY += 4 * u
            var x = x0
            while (x + cw <= x1 && rowY + ch <= limit) { box(x, rowY, cw, ch, card, if (s.cards == "plate") 4f else 2f); x += cw + 2 * u }
            rowY += ch + 4 * u
        }
    }
    if (s.dock) box(left + 3 * u, h - bottom - dockH, w - left - 6 * u, 6 * u, panel, 3f)
}
