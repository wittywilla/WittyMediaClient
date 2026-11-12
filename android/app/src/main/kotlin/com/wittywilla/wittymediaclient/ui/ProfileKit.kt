// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.delay

// Pieces the profile and parental-control screens share: a dialog in the app's own look, choosing one or several
// from a list (which works with a remote's arrows as well as a finger), and the wait after too many wrong tries.

// Something over the page, in a panel: its title, then whatever it holds, scrolling when it's long. Back closes it.
// Focus starts inside it and stays there, which a TV needs.
@Composable
fun PanelDialog(title: String, onClose: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    Dialog(onClose, DialogProperties(usePlatformDefaultWidth = false)) {
        CompositionLocalProvider(LocalFocusMemory provides remember { FocusMemory() }) {
            Box(Modifier.fillMaxWidth().fillMaxHeight(DIALOG_MOST).padding(horizontal = metrics.gutter), contentAlignment = Alignment.Center) {
                Column(
                    Modifier
                        .widthIn(max = metrics.u(if (metrics.tv) 880 else 520))
                        .fillMaxWidth()
                        .clip(metrics.corner(20))
                        .background(scheme.background)
                        .verticalScroll(rememberScrollState())
                        .padding(metrics.u(if (metrics.tv) 32 else 20)),
                    verticalArrangement = Arrangement.spacedBy(metrics.u(16)),
                ) {
                    if (title.isNotEmpty()) Text(title, color = scheme.onBackground, style = MaterialTheme.typography.headline, modifier = Modifier.semantics { heading() })
                    content()
                }
            }
        }
    }
}

private const val DIALOG_MOST = 0.9f

// One thing to choose from a list.
data class Pick(val id: String, val label: String, val detail: String = "")

// The check a chosen row ends with; it keeps its room when it isn't chosen, so rows don't shift.
@Composable
fun CheckMark(on: Boolean) {
    Icon(
        Symbols.Check, contentDescription = null, tint = LocalExtraColours.current.accentText,
        modifier = Modifier.size(LocalMetrics.current.u(20)).graphicsLayer { alpha = if (on) 1f else 0f },
    )
}

// Choose one: pressing a row chooses it and closes.
@Composable
fun PickDialog(title: String, options: List<Pick>, chosen: String, onPick: (String) -> Unit, onClose: () -> Unit) {
    PanelDialog(title, onClose) {
        GroupedList(
            "",
            options.mapIndexed { i, o ->
                GroupRow(
                    o.label, onClick = { onPick(o.id); onClose() }, detail = o.detail, chevron = false, selected = o.id == chosen,
                    focusKey = "pick-${o.id}", requestFocus = o.id == chosen || (i == 0 && options.none { it.id == chosen }),
                    trailing = { CheckMark(o.id == chosen) },
                )
            },
        )
    }
}

// Choose several: each row turns on and off, and Done keeps the lot. Back keeps them too, as nothing here is final
// until the page it belongs to is saved.
@Composable
fun MultiPickDialog(title: String, hint: String, options: List<Pick>, chosen: Set<String>, onDone: (Set<String>) -> Unit) {
    var now by remember { mutableStateOf(chosen) }
    val words = LocalWords.current
    PanelDialog(title, { onDone(now) }) {
        if (hint.isNotEmpty()) Text(hint, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
        GroupedList(
            "",
            options.mapIndexed { i, o ->
                GroupRow(
                    o.label, onClick = { now = if (o.id in now) now - o.id else now + o.id }, detail = o.detail, chevron = false,
                    selected = o.id in now, focusKey = "multi-${o.id}", requestFocus = i == 0, trailing = { CheckMark(o.id in now) },
                )
            },
        )
        WittyButton(words["done"].orEmpty(), { onDone(now) }, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, focusKey = "multi-done")
    }
}

// Are you sure: the safe answer has focus.
@Composable
fun AskDialog(question: String, detail: String, yes: String, no: String, onYes: () -> Unit, onNo: () -> Unit) {
    PanelDialog(question, onNo) {
        if (detail.isNotEmpty()) Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.body)
        WittyButton(no, onNo, Modifier.fillMaxWidth(), tall = true, requestFocus = true, focusKey = "ask-no")
        WittyButton(yes, onYes, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, tall = true, focusKey = "ask-yes")
    }
}

// After too many wrong tries the server says how long to wait (Retry-After). This counts it down, so the button
// that would only be refused again stays off until then. `again` goes up with each such answer.
@Composable
fun rememberWait(seconds: Int, again: Int): Int {
    var left by remember { mutableIntStateOf(0) }
    LaunchedEffect(again) {
        left = if (again > 0) seconds.coerceIn(0, MOST_WAIT_SEC) else 0
        while (left > 0) {
            delay(1000)
            left--
        }
    }
    return left
}

private const val MOST_WAIT_SEC = 3600

// "Try again in 40 seconds." / "in 3 minutes."
fun waitWords(s: Map<String, String>, seconds: Int): String =
    if (seconds <= 0) "" else if (seconds < 90) s["waitSeconds"].orEmpty().replace("{n}", seconds.toString())
    else s["waitMinutes"].orEmpty().replace("{n}", ((seconds + 59) / 60).toString())
