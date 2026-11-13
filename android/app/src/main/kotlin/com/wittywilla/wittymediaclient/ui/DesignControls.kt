// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.input.ImeAction
import com.wittywilla.wittymediaclient.net.DesignPageSpec
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

// The rows of Design 2's pages that change something in place, as the server's controls are (docs/SDUI.md, "Forms and
// controls"): a switch (DesignSwitchRow in DesignPage.kt), a choice, words and a number; and a form's foot. Built from
// the page's own parts, so they look and move as every other row does, on a TV's remote as on a touch screen.

/** A choice: the row says what is chosen, and the choices sit under it as chips. Picking one hands its value to [onPick]. */
@Composable
fun DesignSelectRow(
    title: String,
    value: String,
    options: List<DesignPageSpec.Control.Option>,
    onPick: (String) -> Unit,
    modifier: Modifier = Modifier,
    sub: String = "",
    enabled: Boolean = true,
    why: String = "",
    requestFocus: Boolean = false,
) {
    val shown = options.firstOrNull { it.value == value }?.let { it.label.ifEmpty { it.value } } ?: value
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(LocalDesignSizes.current.gap * 0.6f)) {
        DesignRow(title, value = shown, sub = listOf(sub, if (!enabled) why else "").filter { it.isNotEmpty() }.joinToString(" · "), on = true)
        DesignChips {
            options.forEachIndexed { i, o ->
                DesignChip(
                    o.label.ifEmpty { o.value }, { if (enabled) onPick(o.value) }, on = o.value == value, enabled = enabled,
                    requestFocus = requestFocus && i == 0, focusKey = "design.${designId(title)}.${designId(o.value)}",
                    label = "$title, ${o.label.ifEmpty { o.value }}",
                )
            }
        }
    }
}

/**
 * A number: the row says it with its unit; a touch screen drags the bar under it, a remote or a keyboard steps it with
 * − and +. [onChange] has every step as it is made; [onDone] the value once it has been still for a moment (a drag let
 * go, the last press of +).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DesignSliderRow(
    title: String,
    value: Double,
    min: Double,
    max: Double,
    step: Double,
    modifier: Modifier = Modifier,
    unit: String = "",
    sub: String = "",
    enabled: Boolean = true,
    why: String = "",
    onChange: (Double) -> Unit = {},
    onDone: (Double) -> Unit = {},
) {
    val metrics = LocalMetrics.current
    val stepBy = if (step > 0) step else (max - min) / 20.0
    var shown by remember(value) { mutableDoubleStateOf(value) }
    var moved by remember { mutableStateOf(false) }
    fun set(v: Double) {
        val next = (if (step > 0) min + Math.round((v - min) / step) * step else v).coerceIn(min, maxOf(min, max))
        if (next == shown) return
        shown = next
        moved = true
        onChange(next)
    }
    LaunchedEffect(shown, moved) {
        if (!moved) return@LaunchedEffect
        delay(SETTLE_MS)
        moved = false
        onDone(shown)
    }
    val words = (if (shown == Math.floor(shown)) shown.toLong().toString() else "%.1f".format(shown)) + unit
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(LocalDesignSizes.current.gap * 0.6f)) {
        DesignRow(title, value = words, sub = listOf(sub, if (!enabled) why else "").filter { it.isNotEmpty() }.joinToString(" · "), on = true)
        if (!metrics.tv) {
            NpSlider(
                shown, min, maxOf(min, max), stepBy, title, words, enabled, Modifier.fillMaxWidth().padding(horizontal = LocalDesignSizes.current.gap),
                fill = MaterialTheme.colorScheme.primary, track = MaterialTheme.colorScheme.onBackground.copy(alpha = TRACK_ALPHA),
            ) { set(it) }
        }
        DesignChips {
            DesignChip("−", { set(shown - stepBy) }, enabled = enabled && shown > min, label = "$title, less", focusKey = "design.${designId(title)}.less")
            DesignChip("+", { set(shown + stepBy) }, enabled = enabled && shown < max, label = "$title, more", focusKey = "design.${designId(title)}.more")
        }
    }
}

/** Words: a field under the row's title. [onDone] has them on Enter and when the field loses focus. */
@Composable
fun DesignFieldRow(
    title: String,
    value: String,
    onChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    maxLength: Int = 0,
    input: String = "",
    enabled: Boolean = true,
    why: String = "",
    onDone: (String) -> Unit = {},
) {
    var focused by remember { mutableStateOf(false) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(LocalDesignSizes.current.gap * 0.5f)) {
        WittyField(
            value, onChange, title,
            Modifier.fillMaxWidth().onFocusChanged {
                if (focused && !it.hasFocus) onDone(value)
                focused = it.hasFocus
            },
            kind = if (input == "url") FieldKind.Address else FieldKind.Text,
            imeAction = if (input == "search") ImeAction.Search else ImeAction.Done, onAction = { onDone(value) },
            maxLength = if (maxLength > 0) maxLength else Int.MAX_VALUE, enabled = enabled,
        )
        if (!enabled && why.isNotEmpty()) DesignNote(why)
    }
}

/**
 * One row of a spec with a control, drawn as its kind is: [onValue] has the new value as the server's control would
 * carry it (a bool, a string or a number), as the docs say when to send it: a switch at once, a choice when picked,
 * words on Enter or leaving the field, a number once it settles.
 */
@Composable
fun DesignControlRow(row: DesignPageSpec.Row, control: DesignPageSpec.Control, value: JsonElement?, onValue: (JsonElement) -> Unit, requestFocus: Boolean = false) {
    val c = control.copy(value = value ?: control.value)
    val enabled = !c.disabled
    val sub = listOf(row.detail, if (!enabled) c.why else "").filter { it.isNotEmpty() }.joinToString(" · ")
    when (c.kind) {
        DesignPageSpec.Control.SWITCH -> DesignSwitchRow(row.title, c.on, { onValue(JsonPrimitive(it)) }, sub = sub, enabled = enabled, requestFocus = requestFocus)
        DesignPageSpec.Control.SELECT -> DesignSelectRow(row.title, c.text, c.options, { onValue(JsonPrimitive(it)) }, sub = row.detail, enabled = enabled, why = c.why, requestFocus = requestFocus)
        DesignPageSpec.Control.SLIDER -> DesignSliderRow(
            row.title, c.number, c.min, c.max, c.step, unit = c.unit, sub = row.detail, enabled = enabled, why = c.why,
            onDone = { onValue(JsonPrimitive(c.snap(it))) },
        )
        DesignPageSpec.Control.FIELD -> {
            var text by remember(c.text) { mutableStateOf(c.text) }
            DesignFieldRow(
                row.title, text, { text = it }, maxLength = c.maxLength, input = c.input,
                enabled = enabled, why = c.why, onDone = { if (it != c.text) onValue(JsonPrimitive(it)) },
            )
        }
        // A kind this app doesn't know yet: what it says, read only.
        else -> DesignRow(row.title, value = c.text, sub = sub)
    }
}

/** A form's foot: Save (its words), and Cancel when there is one. Save is the page's main action. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DesignForm(
    submitLabel: String,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
    cancelLabel: String = "",
    onCancel: () -> Unit = {},
    busy: Boolean = false,
    enabled: Boolean = true,
    problem: String = "",
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth()) {
        content()
        DesignNote(problem, Modifier.padding(top = LocalDesignSizes.current.gap), error = true)
        DesignActions(actions = {
            WittyButton(submitLabel, onSubmit, kind = ButtonKind.Primary, busy = busy, enabled = enabled, focusKey = "design.form-submit")
            if (cancelLabel.isNotEmpty()) WittyButton(cancelLabel, onCancel, kind = ButtonKind.Secondary, focusKey = "design.form-cancel")
        })
    }
}

private const val SETTLE_MS = 450L
private const val TRACK_ALPHA = 0.22f
