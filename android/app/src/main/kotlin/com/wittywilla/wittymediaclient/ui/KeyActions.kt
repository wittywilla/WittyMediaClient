// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.InputAction
import com.wittywilla.wittymediaclient.net.InputContext
import com.wittywilla.wittymediaclient.net.InputKind
import com.wittywilla.wittymediaclient.net.KeyHint
import com.wittywilla.wittymediaclient.net.KeyLegend
import com.wittywilla.wittymediaclient.net.KeyMap
import com.wittywilla.wittymediaclient.net.KeyPress
import androidx.compose.ui.text.style.TextOverflow

// The input model's wiring (docs/plans/DESIGN-2.md, section 3): which kind of input the person last used, the key legend
// that follows it, and the keys every screen answers the same (the rules are in net/InputRules.kt).

object InputInUse {
    // The last kind of input used: a key, a pad or a remote. Null until one is, and again after a touch, so the legend
    // is hidden on a touch screen. A TV starts with its remote.
    var kind by mutableStateOf<InputKind?>(null)

    // The key help sheet (held Menu, a pad's Select, or `?`).
    var helpOpen by mutableStateOf(false)

    // On a TV, a key that only a keyboard has (the digits of a remote's number pad, typing a code) says nothing about
    // the input: a TV never shows PC shortcuts (Esc, Ctrl+[), so only a pad or a remote's own keys change the legend.
    fun note(code: Int, tv: Boolean = false) {
        // Moves and OK come from any kind: they change nothing once a kind is known.
        val seen = KeyMap.kindOf(code).let { if (tv && it == InputKind.Keyboard) InputKind.Remote else it }
        if (kind == null || seen != InputKind.Remote || kind == InputKind.Remote) kind = seen
    }

    fun touched() {
        kind = null
    }
}

// A key event as the rules see it.
fun KeyEvent.press(long: Boolean = false) = KeyPress(
    code = nativeKeyEvent.keyCode, ctrl = isCtrlPressed, shift = isShiftPressed, alt = nativeKeyEvent.isAltPressed, long = long,
)

// The action a Compose key event means, once it is a key down (a repeat counts once).
fun KeyEvent.action(ctx: InputContext = InputContext()): InputAction? {
    if (type != KeyEventType.KeyDown || nativeKeyEvent.repeatCount != 0) return null
    return KeyMap.action(press(), ctx)
}

// Options on a thing that has them: the options keys and a pad's X do what holding OK does.
fun Modifier.optionsKey(onOptions: (() -> Unit)?): Modifier =
    if (onOptions == null) this else onPreviewKeyEvent { e ->
        if (e.action() == InputAction.Options && e.nativeKeyEvent.keyCode != android.view.KeyEvent.KEYCODE_DPAD_CENTER &&
            e.nativeKeyEvent.keyCode != android.view.KeyEvent.KEYCODE_BUTTON_A
        ) {
            onOptions()
            true
        } else false
    }

// The keys, in glyphs, for the input in use: a row of small caps and their words. Nothing on a touch screen.
@Composable
fun KeyLegendRow(modifier: Modifier = Modifier, hasDock: Boolean = false) {
    val hints = KeyLegend.hints(InputInUse.kind, hasDock)
    if (hints.isEmpty()) return
    val metrics = LocalMetrics.current
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 32 else 16)), verticalAlignment = Alignment.CenterVertically) {
        hints.forEach { KeyHintView(it) }
    }
}

@Composable
fun KeyHintView(hint: KeyHint) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val size = if (metrics.tv) DesignTokens.Tv.Dock.hintSize.toInt() else 13
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 12 else 6))) {
        Box(
            Modifier
                .defaultMinSize(minWidth = metrics.u(if (metrics.tv) 36 else 22), minHeight = metrics.u(if (metrics.tv) 36 else 22))
                .border(metrics.u(if (metrics.tv) 2 else 1), scheme.outline, RoundedCornerShape(metrics.u(if (metrics.tv) 8 else 5)))
                .padding(horizontal = metrics.u(if (metrics.tv) 8 else 5)),
            contentAlignment = Alignment.Center,
        ) { Text(hint.glyph, color = scheme.onBackground, fontSize = metrics.u(size).value.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        Text(hint.words, color = scheme.onSurfaceVariant, fontSize = metrics.u(size).value.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// Every key and what it does, for the input in use: opened by held Menu, a pad's Select, or `?`. Back closes it.
@Composable
fun KeyHelpSheet(onClose: () -> Unit) {
    val metrics = LocalMetrics.current
    val kind = InputInUse.kind ?: InputKind.Keyboard
    val scheme = MaterialTheme.colorScheme
    androidx.activity.compose.BackHandler(onBack = onClose)
    val rows = KeyLegend.hints(kind, true)
    com.wittywilla.wittymediaclient.tv.TvLayer(onClose) {
        Box(Modifier.padding(metrics.gutter), contentAlignment = Alignment.Center) {
            Column(
                Modifier.widthIn(max = metrics.u(900)).background(scheme.surface, RoundedCornerShape(metrics.u(32))).padding(metrics.u(48)),
                verticalArrangement = Arrangement.spacedBy(metrics.u(20)),
            ) {
                Text("Keys", color = scheme.onSurface, style = MaterialTheme.typography.headline, modifier = Modifier.semantics { heading() })
                rows.forEach { KeyHintView(it) }
                Text("Back closes this.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
            }
        }
    }
}
