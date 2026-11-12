// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

// Surfaces step by tone, not by shadow on the page (docs/plans/DESIGN-2.md, section 1): 0 is the page, 1 a panel with a
// hairline, 2 a lifted card, 3 an overlay. The fill and line are theme colours by the token's names, the shadow is the
// token's (phones and tablets draw it; a TV doesn't).
object Elevation {
    // The theme colour a token name stands for, in this app's scheme.
    @Composable
    fun colour(name: String): Color {
        val scheme = MaterialTheme.colorScheme
        val extra = LocalExtraColours.current
        return when (name) {
            "bg" -> scheme.background
            "bg2" -> scheme.surface
            "bg3" -> scheme.surfaceVariant
            "bg4" -> extra.raised
            "border" -> scheme.outline
            "borderStrong" -> extra.control
            else -> Color.Transparent
        }
    }
}

@Composable
fun Modifier.elevated(level: Int, shape: Shape, radius: androidx.compose.ui.unit.Dp = 10.dp): Modifier {
    val fillName: String; val lineName: String; val shadows: List<Map<String, Double>>
    when (level.coerceIn(0, 3)) {
        0 -> { fillName = DesignTokens.Elevation.N0.fill; lineName = DesignTokens.Elevation.N0.line; shadows = DesignTokens.Elevation.N0.shadow }
        1 -> { fillName = DesignTokens.Elevation.N1.fill; lineName = DesignTokens.Elevation.N1.line; shadows = DesignTokens.Elevation.N1.shadow }
        2 -> { fillName = DesignTokens.Elevation.N2.fill; lineName = DesignTokens.Elevation.N2.line; shadows = DesignTokens.Elevation.N2.shadow }
        else -> { fillName = DesignTokens.Elevation.N3.fill; lineName = DesignTokens.Elevation.N3.line; shadows = DesignTokens.Elevation.N3.shadow }
    }
    val fill = Elevation.colour(fillName)
    val noLine = lineName.isEmpty() || lineName == "none"
    val line = if (noLine) Color.Transparent else Elevation.colour(lineName)
    var m = this
    if (!LocalMetrics.current.tv) {
        for (s in shadows) m = m.cssShadow((s["y"] ?: 0.0).toFloat().dp, (s["blur"] ?: 0.0).toFloat().dp, Color.Black.copy(alpha = (s["opacity"] ?: 0.0).toFloat()), radius)
    }
    m = m.background(fill, shape)
    return if (noLine) m else m.border(1.dp, line, shape)
}
