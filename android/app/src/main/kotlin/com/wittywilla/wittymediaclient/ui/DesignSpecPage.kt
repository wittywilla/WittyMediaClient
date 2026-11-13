// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import com.wittywilla.wittymediaclient.net.BackStep
import com.wittywilla.wittymediaclient.net.DesignPageSpec
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

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
    // A picture for a card, in place of its swatch: a look's layout (W4's LayoutThumb), say.
    preview: (DesignPageSpec.Card) -> (@Composable () -> Unit)? = { null },
    // A row's control changed (outside a form): the row's id and the new value, to run the row's action with.
    onValue: (String, JsonElement) -> Unit = { _, _ -> },
    // A form's Save, with every named control's value; and its Cancel.
    onSubmit: (JsonObject) -> Unit = {},
    onCancel: () -> Unit = {},
    formBusy: Boolean = false,
    problem: String = "",
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
        // Inside a form a change is only held until Save; outside one it goes at once.
        var edits by remember(spec) { mutableStateOf(mapOf<String, JsonElement>()) }
        val change: (String, JsonElement) -> Unit = { id, v ->
            if (spec.form != null) {
                val row = spec.sections.flatMap { it.rows }.firstOrNull { it.id == id }
                edits = edits + ((row?.control?.name?.ifEmpty { null } ?: id) to v)
            } else onValue(id, v)
        }
        val current: (DesignPageSpec.Row) -> JsonElement? = { r -> edits[r.control?.name?.ifEmpty { null } ?: r.id] }
        val form = spec.form
        if (form != null) {
            DesignForm(form.submitLabel, { onSubmit(spec.formValues(edits)) }, cancelLabel = form.cancelLabel, onCancel = onCancel, busy = formBusy, problem = problem) {
                DesignSpecSections(spec, onPress, enabled, preview, current, change)
            }
        } else {
            DesignSpecSections(spec, onPress, enabled, preview, current, change)
            DesignNote(problem, error = true)
        }
        if (extra != null) extra()
    }
}

/** A spec's sections alone, for a screen with its own head and frame. */
@Composable
fun DesignSpecSections(
    spec: DesignPageSpec,
    onPress: (String) -> Unit,
    enabled: (String) -> Boolean = { true },
    preview: (DesignPageSpec.Card) -> (@Composable () -> Unit)? = { null },
    value: (DesignPageSpec.Row) -> JsonElement? = { null },
    onValue: (String, JsonElement) -> Unit = { _, _ -> },
) {
    val start = spec.startFocus
    spec.sections.forEach { s ->
        DesignSection(s.heading) {
            when (s.kind) {
                DesignPageSpec.Kind.rows -> s.rows.forEach { r ->
                    val control = r.control
                    if (control != null) {
                        DesignControlRow(r, control, value(r), { onValue(r.id, it) }, requestFocus = r.id == start)
                        return@forEach
                    }
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
                        DesignCard(c.title, { onPress(c.id) }, sub = c.subtitle, on = c.on, enabled = enabled(c.id), swatch = c.swatches.mapNotNull { hexColour(it) }, preview = preview(c), focusKey = "design.${c.id}", requestFocus = c.id == start)
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
