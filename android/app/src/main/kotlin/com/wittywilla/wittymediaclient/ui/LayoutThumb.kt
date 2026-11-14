// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
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
import com.wittywilla.wittymediaclient.net.SduiWire
import com.wittywilla.wittymediaclient.net.Wire

// A small wireframe of a look's layout: the menu and where it is, its style, Home's arrangement, the cards and the dock, drawn in
// the colours it is given (the previewed theme's, by default the theme in use) from the experience's `wire`. Used wherever
// looks are chosen.
@Composable
// A phone's layout is drawn upright, the shape of a phone's screen, as Apple's chooser draws it.
fun LayoutThumb(wire: SduiWire, name: String, modifier: Modifier = Modifier, selected: Boolean = false, bg: Color = MaterialTheme.colorScheme.background, panel: Color = MaterialTheme.colorScheme.surface, card: Color = MaterialTheme.colorScheme.surfaceVariant, accent: Color = MaterialTheme.colorScheme.primary, ink: Color = MaterialTheme.colorScheme.onSurfaceVariant, portrait: Boolean = false) {
    val corner = if (portrait) 14.dp else 6.dp
    Canvas(
        modifier.fillMaxWidth().aspectRatio(if (portrait) 0.56f else 16f / 10f).clip(RoundedCornerShape(corner))
            .border(if (selected) 3.dp else 1.dp, if (selected) accent else Color.Gray.copy(alpha = 0.4f), RoundedCornerShape(corner))
            .semantics { contentDescription = "$name layout" + if (selected) ", selected" else "" },
    ) {
        drawWire(wire, bg, panel, card, accent, ink, portrait)
    }
}

private fun DrawScope.box(x: Float, y: Float, w: Float, h: Float, c: Color, r: Float = 2f) = drawRoundRect(c, Offset(x, y), Size(w, h), CornerRadius(r, r))

internal fun DrawScope.drawWire(s: SduiWire, bg: Color, panel: Color, card: Color, accent: Color, ink: Color, portrait: Boolean = false) {
    val w = size.width
    val h = size.height
    drawRect(bg)
    val u = w / 100f
    val glass = Wire.glass(s)
    val soft = ink.copy(alpha = 0.5f)
    var left = 0f
    var top = 0f
    var bottom = 0f
    // The menu: where it goes decides what is left for the page; its style decides how its items are drawn.
    fun item(x: Float, y: Float, iw: Float, ih: Float, on: Boolean) {
        when (s.style) {
            "pill", "gloss" -> box(x, y, iw, ih, if (on) accent else soft, ih / 2)
            "under" -> { box(x, y, iw, ih, soft, 1f); if (on) box(x, y + ih + 0.8f * u, iw, 0.9f * u, accent, 0f) }
            "tele" -> box(x, y, iw, ih, if (on) accent else Color(0xFF2E7D32), 0f)
            "cable", "bevel" -> box(x, y, iw, ih, if (on) accent else soft, 0.5f)
            else -> box(x, y, iw, ih, if (on) accent else soft)
        }
    }
    when (s.nav) {
        "side" -> { box(0f, 0f, 22 * u, h, panel, 0f); left = 22 * u; for (i in 0 until 4) item(3 * u, (8 + i * 9) * u, 16 * u, 3 * u, i == 0) }
        "rail" -> { box(0f, 0f, 9 * u, h, panel, 0f); left = 9 * u; box(2.5f * u, 4 * u, 4 * u, 4 * u, accent); for (i in 0 until 4) item(3 * u, (14 + i * 8) * u, 3 * u, 3 * u, i == 0) }
        // A phone's tabs float in a rounded bar with a dot each, as the app draws them.
        "bottom" -> if (portrait) {
            val bh = 10 * u
            box(6 * u, h - bh - 4 * u, w - 12 * u, bh, panel, bh / 2); bottom = bh + 6 * u
            for (i in 0 until 4) drawCircle(if (i == 0) accent else soft, 2.2f * u, Offset((22 + i * 19) * u, h - 4 * u - bh / 2))
        } else { box(0f, h - 9 * u, w, 9 * u, panel, 0f); bottom = 9 * u; for (i in 0 until 4) item((18 + i * 18) * u, h - 6 * u, 6 * u, 3 * u, i == 0) }
        "none" -> Unit
        else -> {
            val tall = if (s.style == "crossbar") 12 * u else 9 * u
            box(0f, 0f, w, tall, panel.copy(alpha = if (glass) 0.8f else 1f), 0f); top = tall
            when (s.brand) { "centre" -> box(w / 2 - 4 * u, 3 * u, 8 * u, 3 * u, accent); "top" -> box(3 * u, 1.2f * u, 8 * u, 2 * u, accent); else -> box(3 * u, 3 * u, 8 * u, 3 * u, accent) }
            for (i in 0 until 4) item((20 + i * 12) * u, 3.2f * u, 8 * u, 2.6f * u, i == 0)
        }
    }
    val x0 = left + 3 * u
    val x1 = w - 3 * u
    var y = top + 3 * u
    val dockH = if (s.dock) 8 * u else 0f
    val limit = h - bottom - dockH - 2 * u
    // A phone's screen, upright, as Apple's chooser draws it: a hero a third of the page, then rows of posters.
    if (portrait && s.home != "list" && s.home != "cross") {
        val pw = x1 - x0
        if (s.home == "hero" || s.home == "banner" || s.home == "carousel") {
            val hh = (limit - y) * (if (s.home == "banner") 0.2f else 0.3f)
            box(x0, y, pw, hh, card, 4f)
            box(x0, y, pw, hh * 0.5f, accent.copy(alpha = 0.18f), 4f)
            for (i in 0 until 3) box(x0 + pw * 0.06f, y + hh * (0.3f + i * 0.16f), pw * (if (i == 0) 0.5f else 0.36f), hh * 0.07f, ink.copy(alpha = 0.5f), 1f)
            box(x0 + pw * 0.06f, y + hh * 0.8f, pw * 0.2f, hh * 0.11f, accent, 2f)
            y += hh + h * 0.03f
        }
        val wide = s.cards == "landscape" || s.cards == "logo" || s.cards == "block"
        val across = if (wide) 2 else 4
        val gap = w * 0.03f
        val cw = (pw - gap * (across - 1)) / across
        val ch = if (wide) cw * 0.56f else cw / 0.62f
        var rowY = y
        while (rowY + h * 0.03f + ch <= limit) {
            box(x0, rowY, pw * 0.3f, h * 0.014f, ink.copy(alpha = 0.4f), 1f)
            rowY += h * 0.03f
            for (i in 0 until across) {
                val cx = x0 + i * (cw + gap)
                box(cx, rowY, cw, ch, card, cw * 0.14f)
                // A plate card's name sits on a band of the accent at its foot.
                if (s.cards == "plate") box(cx, rowY + ch * 0.74f, cw, ch * 0.26f, accent.copy(alpha = 0.55f), cw * 0.14f)
            }
            rowY += ch + h * 0.03f
        }
        if (s.dock) box(left + 3 * u, h - bottom - dockH, w - left - 6 * u, 6 * u, panel, 3f)
        return
    }
    when (s.home) {
        "hero" -> { box(left, top, w - left, 26 * u, card, 0f); box(x0, top + 14 * u, 22 * u, 3 * u, ink); box(x0, top + 19 * u, 10 * u, 4 * u, accent, 3f); y = top + 29 * u }
        "banner" -> { box(x0, y, x1 - x0, 16 * u, card, 4f); box(x0 + 3 * u, y + 11 * u, 8 * u, 3 * u, accent); y += 19 * u }
        "carousel" -> { val cw = 20 * u; val mid = left + (w - left) / 2; box(mid - cw / 2, y, cw, 30 * u, card, 3f); box(mid - cw * 1.5f - 2 * u, y + 4 * u, cw * 0.8f, 24 * u, card.copy(alpha = 0.6f), 3f); box(mid + cw * 0.7f + 2 * u, y + 4 * u, cw * 0.8f, 24 * u, card.copy(alpha = 0.6f), 3f); y += 33 * u }
        "cross" -> { for (i in 0 until 5) box(x0 + i * 16 * u, y, 12 * u, 4 * u, if (i == 2) accent else soft, 2f); var yy = y + 8 * u; while (yy + 5 * u < limit) { box(x0 + 26 * u, yy, 30 * u, 3 * u, card, 2f); yy += 6 * u }; y = limit }
        "widgets" -> { val gw = (x1 - x0 - 2 * u) / 2; box(x0, y, gw, 14 * u, card, 3f); box(x0 + gw + 2 * u, y, gw, 14 * u, card, 3f); box(x0, y + 16 * u, x1 - x0, 12 * u, card, 3f); y += 31 * u }
        "list" -> { var yy = y; while (yy + 6 * u < limit) { box(x0, yy, 6 * u, 4 * u, accent.copy(alpha = 0.7f)); box(x0 + 9 * u, yy, (x1 - x0) - 9 * u, 4 * u, card, 2f); yy += 7 * u }; y = limit }
        else -> Unit
    }
    // Rows of cards in the shape the look draws them.
    if (s.home != "list" && s.home != "cross") {
        val (cw, ch) = when (s.cards) { "landscape", "block" -> 18 * u to 10 * u; "logo" -> 11 * u to 7 * u; else -> 9 * u to 13 * u }
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
