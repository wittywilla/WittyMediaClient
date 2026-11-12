// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import android.view.KeyEvent

// One input model (docs/plans/DESIGN-2.md, section 3): the key map, the zones and the Back ladder, as pure rules so a
// keyboard, a game pad and a TV remote all end in the same actions, and so they can be tested on the JVM. The app's
// key handlers (ui/KeyActions.kt) only turn a key into an action here and carry the action out.

enum class InputAction {
    Move, Select, Back, Options, Search, PrevTab, NextTab, PageUp, PageDown, Top, Dock, Help,
    PlayPause, Play, Pause, Stop, NextTrack, PreviousTrack, SeekBack, SeekForward,
}

enum class InputKind { Keyboard, Gamepad, Remote }

// A key as the system gave it: its code, the modifiers held, whether it is a long press (held past the system's own
// long-press time) and whether it came from a game pad (a pad's A and B are keys of their own, a keyboard's are letters).
data class KeyPress(
    val code: Int,
    val ctrl: Boolean = false,
    val shift: Boolean = false,
    val alt: Boolean = false,
    val long: Boolean = false,
)

// Where focus is, which changes what a few shared keys mean.
data class InputContext(
    val inBar: Boolean = false,
    val nothingFocused: Boolean = false,
    val hasDock: Boolean = false,
)

object KeyMap {
    // The keys that move focus: handled by the focus system, never mapped to something else.
    val MOVES = setOf(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT)

    private val PAD_ONLY = setOf(
        KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_BUTTON_Y,
        KeyEvent.KEYCODE_BUTTON_L1, KeyEvent.KEYCODE_BUTTON_R1, KeyEvent.KEYCODE_BUTTON_L2, KeyEvent.KEYCODE_BUTTON_R2,
        KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_THUMBR, KeyEvent.KEYCODE_BUTTON_THUMBL,
    )

    // Which kind of input a key came from, by the key alone. A key every kind has (the D-pad, OK, Back) is a remote's.
    fun kindOf(code: Int): InputKind = when {
        code in PAD_ONLY -> InputKind.Gamepad
        code in REMOTE_ONLY -> InputKind.Remote
        code in MOVES || code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_BACK -> InputKind.Remote
        else -> InputKind.Keyboard
    }

    private val REMOTE_ONLY = setOf(
        KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_SEARCH, KeyEvent.KEYCODE_CHANNEL_UP, KeyEvent.KEYCODE_CHANNEL_DOWN,
        KeyEvent.KEYCODE_GUIDE, KeyEvent.KEYCODE_INFO, KeyEvent.KEYCODE_TV,
    )

    // The action a key means, or null when it is not in the table (the focus system or the screen handles it).
    // Long presses: OK held is Options (Leanback's), Menu held is Help; a long A on a pad is Options too.
    fun action(key: KeyPress, ctx: InputContext = InputContext()): InputAction? {
        val c = key.code
        if (c in MOVES) return InputAction.Move
        return when (c) {
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BUTTON_A ->
                if (key.long && c != KeyEvent.KEYCODE_ENTER && c != KeyEvent.KEYCODE_NUMPAD_ENTER) InputAction.Options else InputAction.Select
            KeyEvent.KEYCODE_SPACE -> InputAction.Select
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BUTTON_B -> InputAction.Back
            // Backspace is Back only when no text field is being edited: the key handler asks.
            KeyEvent.KEYCODE_DEL -> InputAction.Back
            KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_PERIOD, KeyEvent.KEYCODE_PROG_RED -> InputAction.Options
            KeyEvent.KEYCODE_MENU -> if (key.long) InputAction.Help else InputAction.Options
            KeyEvent.KEYCODE_F10 -> if (key.shift) InputAction.Options else null
            KeyEvent.KEYCODE_BUTTON_Y, KeyEvent.KEYCODE_SEARCH -> InputAction.Search
            KeyEvent.KEYCODE_SLASH -> if (key.shift) InputAction.Help else InputAction.Search
            KeyEvent.KEYCODE_K -> if (key.ctrl) InputAction.Search else null
            KeyEvent.KEYCODE_BUTTON_L1 -> InputAction.PrevTab
            KeyEvent.KEYCODE_BUTTON_R1 -> InputAction.NextTab
            KeyEvent.KEYCODE_LEFT_BRACKET -> if (key.ctrl) InputAction.PrevTab else null
            KeyEvent.KEYCODE_RIGHT_BRACKET -> if (key.ctrl) InputAction.NextTab else null
            // Channel keys are the tabs while the bar has focus, and a page of a long list or guide elsewhere.
            KeyEvent.KEYCODE_CHANNEL_UP -> if (ctx.inBar) InputAction.PrevTab else InputAction.PageUp
            KeyEvent.KEYCODE_CHANNEL_DOWN -> if (ctx.inBar) InputAction.NextTab else InputAction.PageDown
            KeyEvent.KEYCODE_PAGE_UP, KeyEvent.KEYCODE_BUTTON_L2 -> InputAction.PageUp
            KeyEvent.KEYCODE_PAGE_DOWN, KeyEvent.KEYCODE_BUTTON_R2 -> InputAction.PageDown
            KeyEvent.KEYCODE_MOVE_HOME, KeyEvent.KEYCODE_BUTTON_THUMBR -> InputAction.Top
            KeyEvent.KEYCODE_BUTTON_START -> InputAction.Dock
            KeyEvent.KEYCODE_BUTTON_SELECT -> InputAction.Help
            KeyEvent.KEYCODE_TAB -> if (ctx.nothingFocused && ctx.hasDock && !key.shift) InputAction.Dock else null
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> InputAction.PlayPause
            KeyEvent.KEYCODE_MEDIA_PLAY -> InputAction.Play
            KeyEvent.KEYCODE_MEDIA_PAUSE -> InputAction.Pause
            KeyEvent.KEYCODE_MEDIA_STOP -> InputAction.Stop
            KeyEvent.KEYCODE_MEDIA_NEXT -> InputAction.NextTrack
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> InputAction.PreviousTrack
            KeyEvent.KEYCODE_MEDIA_REWIND -> InputAction.SeekBack
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> InputAction.SeekForward
            else -> null
        }
    }
}

// The four zones of a screen and how directional input moves between them.
enum class Zone { Bar, Stage, Dock, Layer }

enum class Heading { Up, Down, Left, Right }

object Zones {
    // Where one press of `heading` goes when focus is in `zone` and has nowhere further to go inside it ("atEdge"), or null
    // to stay put. A layer holds focus until it closes. Down from the bar goes to the stage (where it last had focus);
    // up from the stage's first row goes to the bar's current tab; the dock sits under the stage and is entered with Down
    // from the stage's last row; up from the dock returns to the same place in the stage. Wrapping never happens.
    fun move(zone: Zone, heading: Heading, atEdge: Boolean, hasDock: Boolean): Zone? {
        if (!atEdge || zone == Zone.Layer) return null
        return when (zone) {
            Zone.Bar -> if (heading == Heading.Down) Zone.Stage else null
            Zone.Stage -> when (heading) {
                Heading.Up -> Zone.Bar
                Heading.Down -> if (hasDock) Zone.Dock else null
                else -> null
            }
            Zone.Dock -> if (heading == Heading.Up) Zone.Stage else null
            Zone.Layer -> null
        }
    }
}

// What Back does next: unwinds the layer, then the dock, then the stage to the bar, then the bar to Home, then leaves.
enum class BackStep { CloseLayer, DockToStage, StageToBar, BarToHome, Leave }

data class BackState(val layerOpen: Boolean, val zone: Zone, val barOnHome: Boolean)

object BackLadder {
    fun next(s: BackState): BackStep = when {
        s.layerOpen || s.zone == Zone.Layer -> BackStep.CloseLayer
        s.zone == Zone.Dock -> BackStep.DockToStage
        s.zone == Zone.Stage -> BackStep.StageToBar
        !s.barOnHome -> BackStep.BarToHome
        else -> BackStep.Leave
    }
}

// Where each group of focusable things last had focus, so coming back to a group lands on the same card ("last-or-first").
class FocusMemory {
    private val last = HashMap<String, String>()

    fun remember(group: String, key: String) {
        last[group] = key
    }

    fun recall(group: String, first: String): String = last[group] ?: first

    fun forget(group: String) {
        last.remove(group)
    }

    val size get() = last.size
}

// Two quick presses of the same key (a remote's double Up goes to the top).
class DoublePress(private val windowMs: Long = 400) {
    private var lastCode = 0
    private var lastAt = Long.MIN_VALUE / 2

    fun press(code: Int, nowMs: Long): Boolean {
        val twice = code == lastCode && nowMs - lastAt <= windowMs
        lastCode = if (twice) 0 else code
        lastAt = if (twice) Long.MIN_VALUE / 2 else nowMs
        return twice
    }
}

// The key legend in a Dock: which keys do what for the input in use. Hidden when nothing but touch or a mouse is.
data class KeyHint(val glyph: String, val words: String)

object KeyLegend {
    private val GLYPHS = mapOf(
        InputKind.Gamepad to mapOf(InputAction.Select to "A", InputAction.Back to "B", InputAction.Options to "X", InputAction.Search to "Y", InputAction.PrevTab to "LB", InputAction.NextTab to "RB", InputAction.Dock to "Start"),
        InputKind.Remote to mapOf(InputAction.Select to "OK", InputAction.Back to "Back", InputAction.Options to "Menu", InputAction.Search to "Search"),
        InputKind.Keyboard to mapOf(InputAction.Select to "Enter", InputAction.Back to "Esc", InputAction.Options to ".", InputAction.Search to "/", InputAction.PrevTab to "Ctrl+[", InputAction.NextTab to "Ctrl+]"),
    )
    private val WORDS = mapOf(
        InputAction.Select to "Select", InputAction.Back to "Back", InputAction.Options to "Options", InputAction.Search to "Search",
        InputAction.PrevTab to "Previous tab", InputAction.NextTab to "Next tab", InputAction.Dock to "Controls",
    )

    // `kind` null means nothing has used a key, pad or remote yet (touch): no legend.
    fun hints(kind: InputKind?, hasDock: Boolean): List<KeyHint> {
        if (kind == null) return emptyList()
        val table = GLYPHS.getValue(kind)
        return InputAction.values().filter { it in table && (hasDock || it != InputAction.Dock) }
            .map { KeyHint(table.getValue(it), WORDS.getValue(it)) }
    }
}
