// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.key
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription

// WittyTV's Dock, the third of its four fixed places (docs/plans/DESIGN-2.md, section 4): one row under the grid that
// never moves and holds, in this order, Look, Day, Channels, Filter, Recordings and Record. Every theme draws it in its
// own colours and cell shapes (`dress`); none rearranges it. Each button shows its key, which does the same from
// anywhere in the guide. Down from the last channel row reaches it, so do the options key, a pad's X or Start and a
// remote's Menu; Up returns to the cell the grid had.

class DockEntry(val key: Char, val label: String, val enabled: Boolean = true, val action: () -> Unit)

// The keys of the dock, as a rule the guide's key handler and the tests share: letter, or null when it is not one.
object DockKeys {
    const val LOOK = 'L'
    const val DAY = 'D'
    const val CHANNELS = 'C'
    const val FILTER = 'F'
    const val RECORDINGS = 'R'
    const val RECORD = 'E'
    val ORDER = listOf(LOOK, DAY, CHANNELS, FILTER, RECORDINGS, RECORD)

    // The key that opens the dock itself rather than a button of it: the options keys and a pad's Start.
    fun opensDock(code: Int): Boolean = code == KeyEvent.KEYCODE_MENU || code == KeyEvent.KEYCODE_BUTTON_X ||
        code == KeyEvent.KEYCODE_BUTTON_START || code == KeyEvent.KEYCODE_PERIOD

    // A letter key's button, for a keyboard on a TV or Chromebook.
    fun forKeyCode(code: Int): Char? {
        if (code !in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z) return null
        val letter = 'A' + (code - KeyEvent.KEYCODE_A)
        return letter.takeIf { it in ORDER }
    }
}

@Composable
fun GuideDock(
    dress: TvDress,
    entries: List<DockEntry>,
    first: FocusRequester,
    // Up from any button: back to the cell the grid had. True when it went.
    onUp: () -> Boolean,
    modifier: Modifier = Modifier,
) {
    val p = dress.paint
    Row(
        modifier
            .fillMaxWidth()
            .background(p.panel)
            .padding(horizontal = dress.pt(dress.edge - 8), vertical = dress.pt(8))
            .defaultMinSize(minHeight = dress.pt(com.wittywilla.wittymediaclient.ui.DesignTokens.Tv.Dock.height - 16))
            .semantics { contentDescription = "Guide controls" }
            .onPreviewKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && e.key.nativeKeyCode == KeyEvent.KEYCODE_DPAD_UP) onUp() else false
            }
            .focusGroup(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
    ) {
        entries.forEachIndexed { i, e ->
            TvButton(
                dress, e.action, kind = TvButtonKind.Button, enabled = e.enabled, label = e.label,
                focusRequester = if (i == 0) first else null,
            ) { ink, style ->
                // The key it answers to, in a small cap of the theme's own key colour.
                Box(
                    Modifier.size(dress.pt(26)).background(p.panel2, RoundedCornerShape(dress.pt(6))),
                    contentAlignment = Alignment.Center,
                ) { Text(e.key.toString(), style = dress.font(com.wittywilla.wittymediaclient.ui.DesignTokens.Tv.Dock.hintSize.toFloat() * 0.6f, W.Bold), color = p.text, maxLines = 1) }
                Text(if (dress.capitals) e.label.uppercase() else e.label, style = style, color = ink, maxLines = 1)
            }
        }
    }
}
