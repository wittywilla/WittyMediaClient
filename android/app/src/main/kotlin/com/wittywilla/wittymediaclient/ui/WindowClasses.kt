// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import com.wittywilla.wittymediaclient.net.InputAction
import com.wittywilla.wittymediaclient.net.InputContext

// The window size classes of docs/plans/DESIGN-2.md (layout.breakpoints): compact below 600 dp, medium below 840, expanded
// below 1200, large from there. A phone is compact, a tablet or a Chromebook window medium and up, and a window's
// class changes as it is resized.
enum class WindowClass { Compact, Medium, Expanded, Large }

object WindowClasses {
    fun of(widthDp: Int): WindowClass = when {
        widthDp < DesignTokens.Layout.Breakpoints.Compact.max -> WindowClass.Compact
        widthDp < DesignTokens.Layout.Breakpoints.Medium.max -> WindowClass.Medium
        widthDp < DesignTokens.Layout.Breakpoints.Expanded.max -> WindowClass.Expanded
        else -> WindowClass.Large
    }
}

// The keys of a keyboard on a phone, tablet or Chromebook: `/` and Ctrl+K search, Esc goes back, `?` shows the keys,
// Ctrl+[ and Ctrl+] move between the bottom bar's tabs. A text field has had the key first, so typing is never taken.
fun windowKeys(nav: Nav): Modifier = Modifier.onKeyEvent { e ->
    if (!nav.current.signedIn) return@onKeyEvent false
    // The layout editor: Ctrl+Shift+L, or Start on a pad, from a page (docs/plans/DESIGN-2.md 7.5).
    if (nav.has("sdui-experiences") && nav.current.let { it == Route.Home || it is Route.Sdui } && e.type == androidx.compose.ui.input.key.KeyEventType.KeyDown &&
        ((e.isCtrlPressed && e.isShiftPressed && e.key == androidx.compose.ui.input.key.Key.L) || e.key == androidx.compose.ui.input.key.Key.ButtonStart)
    ) { nav.push(Route.You(YouNative.EditLayout)); return@onKeyEvent true }
    when (e.action(InputContext())) {
        InputAction.Search -> { if (nav.current != Route.Search) nav.reset(Route.Search); true }
        InputAction.Help -> { InputInUse.helpOpen = true; true }
        InputAction.Back -> if (nav.backStaysInApp) { nav.back(); true } else false
        InputAction.PrevTab -> stepTab(nav, -1)
        InputAction.NextTab -> stepTab(nav, 1)
        else -> false
    }
}

private val PHONE_TABS = listOf(Route.Home, Route.Search, Route.Profile)

private fun stepTab(nav: Nav, by: Int): Boolean {
    val i = PHONE_TABS.indexOf(nav.current)
    val to = PHONE_TABS.getOrNull(i + by) ?: return false
    if (i < 0) return false
    nav.reset(to)
    return true
}
