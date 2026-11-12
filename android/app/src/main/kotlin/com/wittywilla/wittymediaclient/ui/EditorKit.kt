// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The pieces the layout editor and the name editor share, in the look's tokens: the label above a group, a row of choices
// where the chosen one is filled, and a round colour swatch. Every one is a named button of 44 dp or more (66 on a TV);
// focus shows through Pressable, as everywhere in the app.

// The small capital label above a group, as the canvas draws it.
@Composable
fun EdLabel(text: String, modifier: Modifier = Modifier, accent: Boolean = false) {
    val metrics = LocalMetrics.current
    Text(
        text.uppercase(), color = if (accent) LocalExtraColours.current.accentText else MaterialTheme.colorScheme.onSurfaceVariant,
        fontSize = (12 * (if (metrics.tv) 1.4f else 1f)).sp, fontWeight = FontWeight.Bold, letterSpacing = 0.08.sp,
        modifier = modifier.padding(top = metrics.u(18), bottom = metrics.u(6)).semantics { heading() },
    )
}

// One of a few, side by side: the chosen one filled. `spoken` is what a screen reader says for each ("Navigation: Top").
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EdChoices(
    options: List<Pair<String, String>>, current: String, spoken: String, modifier: Modifier = Modifier,
    enabled: Boolean = true, focusKey: String? = null, onPick: (String) -> Unit,
) {
    val metrics = LocalMetrics.current
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        options.forEach { (value, label) ->
            val on = value == current
            WittyButton(
                label, { onPick(value) }, Modifier.semantics { this.selected = on }, kind = if (on) ButtonKind.Primary else ButtonKind.Secondary,
                enabled = enabled, pill = true, focusKey = focusKey?.let { "$it~$value" },
            )
        }
    }
}

// A round swatch: a plain colour, or a gradient. The chosen one has a ring a gap out from it.
@Composable
fun Swatch(
    colour: Color?, brush: Brush?, spoken: String, chosen: Boolean, modifier: Modifier = Modifier, focusKey: String? = null, onClick: () -> Unit,
) {
    val metrics = LocalMetrics.current
    val size: Dp = if (metrics.tv) metrics.u(66) else 44.dp
    val ring = MaterialTheme.colorScheme.onBackground
    Pressable(
        onClick, modifier.size(size), shape = CircleShape, label = spoken, selected = chosen, state = if (chosen) "Chosen" else null,
        focusKey = focusKey, ring = true, clip = false,
    ) {
        Box(Modifier.size(size), contentAlignment = Alignment.Center) {
            val dot = Modifier.size(size * 0.82f)
                .then(if (chosen) Modifier.border(3.dp, ring, CircleShape).padding(3.dp) else Modifier.border(1.dp, MaterialTheme.colorScheme.outline, CircleShape))
            val filled = when {
                brush != null -> Modifier.background(brush, CircleShape)
                colour != null -> Modifier.background(colour, CircleShape)
                else -> Modifier
            }
            Box(dot.then(filled))
        }
    }
}

@Composable
fun EdColumn(modifier: Modifier = Modifier, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(LocalMetrics.current.u(8)), content = content)
}
