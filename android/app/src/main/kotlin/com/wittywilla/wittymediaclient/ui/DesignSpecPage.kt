// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.wittywilla.wittymediaclient.net.BackStep
import com.wittywilla.wittymediaclient.net.DesignPageSpec

// A Design 2 page drawn from its data (net/DesignPageSpec.kt): every row, chip, card and action reports its id through
// [onPress]. Focus starts at the spec's start; a layer's Back calls [onClose]. [extra] is drawn after the sections, for
// what a spec can't say (a text field, a slider, a QR code).
@Composable
fun DesignSpecPage(
    spec: DesignPageSpec,
    onPress: (String) -> Unit,
    modifier: Modifier = Modifier,
    tag: String = "",
    enabled: (String) -> Boolean = { true },
    busy: (String) -> Boolean = { false },
    onClose: (() -> Unit)? = null,
    extra: (@Composable ColumnScope.() -> Unit)? = null,
) {
    if (spec.back == BackStep.CloseLayer && onClose != null) BackHandler { onClose() }
    val start = spec.startFocus
    DesignPage(
        spec.title, modifier, eyebrow = spec.eyebrow, lead = spec.lead, foot = spec.foot, tag = tag,
        actions = if (spec.actions.isEmpty()) null else {
            {
                spec.actions.forEach { a ->
                    WittyButton(
                        a.title, { onPress(a.id) }, kind = if (a.primary) ButtonKind.Primary else ButtonKind.Secondary,
                        busy = busy(a.id), enabled = enabled(a.id), requestFocus = a.id == start, focusKey = "design.${a.id}",
                    )
                }
            }
        },
    ) {
        DesignSpecSections(spec, onPress, enabled)
        if (extra != null) extra()
    }
}

/** A spec's sections alone, for a screen with its own head and frame. */
@Composable
fun DesignSpecSections(spec: DesignPageSpec, onPress: (String) -> Unit, enabled: (String) -> Boolean = { true }) {
    val start = spec.startFocus
    spec.sections.forEach { s ->
        DesignSection(s.heading) {
            when (s.kind) {
                DesignPageSpec.Kind.rows -> s.rows.forEach { r ->
                    DesignRow(
                        r.title, value = r.value, sub = r.detail, on = r.on, enabled = enabled(r.id), requestFocus = r.id == start,
                        focusKey = "design.${r.id}", onClick = if (r.pressable) ({ onPress(r.id) }) else null,
                    )
                }
                DesignPageSpec.Kind.chips -> DesignChips {
                    s.chips.forEach { c -> DesignChip(c.title, { onPress(c.id) }, on = c.on, enabled = enabled(c.id), requestFocus = c.id == start, focusKey = "design.${c.id}") }
                }
                DesignPageSpec.Kind.note -> DesignNote(s.note, tone = s.tone)
                DesignPageSpec.Kind.cards -> {
                    val sizes = LocalDesignSizes.current
                    val cols = DesignPageSpec.columns(s, phone = sizes.phone, tablet = !sizes.phone && !LocalMetrics.current.tv)
                    DesignCards(s.cards.size, columns = cols) { i ->
                        val c = s.cards[i]
                        DesignCard(c.title, { onPress(c.id) }, sub = c.subtitle, on = c.on, enabled = enabled(c.id), swatch = c.swatches.mapNotNull { hexColour(it) })
                    }
                }
            }
        }
    }
}

private fun hexColour(hex: String): Color? {
    val h = hex.removePrefix("#")
    if (h.length != 6) return null
    return h.toLongOrNull(16)?.let { Color(0xFF000000 or it) }
}
