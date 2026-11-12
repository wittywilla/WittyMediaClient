// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import android.view.KeyEvent
import com.wittywilla.wittymediaclient.net.BackLadder
import com.wittywilla.wittymediaclient.net.BackState
import com.wittywilla.wittymediaclient.net.BackStep
import com.wittywilla.wittymediaclient.net.DoublePress
import com.wittywilla.wittymediaclient.net.FocusMemory
import com.wittywilla.wittymediaclient.net.Heading
import com.wittywilla.wittymediaclient.net.InputAction
import com.wittywilla.wittymediaclient.net.InputContext
import com.wittywilla.wittymediaclient.net.InputKind
import com.wittywilla.wittymediaclient.net.KeyLegend
import com.wittywilla.wittymediaclient.net.KeyMap
import com.wittywilla.wittymediaclient.net.KeyPress
import com.wittywilla.wittymediaclient.net.Zone
import com.wittywilla.wittymediaclient.net.Zones
import com.wittywilla.wittymediaclient.ui.DesignTokens
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class InputRulesTest {
    private fun act(code: Int, ctx: InputContext = InputContext(), ctrl: Boolean = false, shift: Boolean = false, long: Boolean = false) =
        KeyMap.action(KeyPress(code, ctrl = ctrl, shift = shift, long = long), ctx)

    @Test fun `the key map table of the design contract`() {
        val table = listOf(
            KeyEvent.KEYCODE_DPAD_UP to InputAction.Move, KeyEvent.KEYCODE_DPAD_LEFT to InputAction.Move,
            KeyEvent.KEYCODE_DPAD_CENTER to InputAction.Select, KeyEvent.KEYCODE_BUTTON_A to InputAction.Select,
            KeyEvent.KEYCODE_ENTER to InputAction.Select, KeyEvent.KEYCODE_SPACE to InputAction.Select,
            KeyEvent.KEYCODE_BACK to InputAction.Back, KeyEvent.KEYCODE_BUTTON_B to InputAction.Back, KeyEvent.KEYCODE_ESCAPE to InputAction.Back,
            KeyEvent.KEYCODE_BUTTON_X to InputAction.Options, KeyEvent.KEYCODE_MENU to InputAction.Options, KeyEvent.KEYCODE_PERIOD to InputAction.Options,
            KeyEvent.KEYCODE_BUTTON_Y to InputAction.Search, KeyEvent.KEYCODE_SEARCH to InputAction.Search, KeyEvent.KEYCODE_SLASH to InputAction.Search,
            KeyEvent.KEYCODE_BUTTON_L1 to InputAction.PrevTab, KeyEvent.KEYCODE_BUTTON_R1 to InputAction.NextTab,
            KeyEvent.KEYCODE_BUTTON_L2 to InputAction.PageUp, KeyEvent.KEYCODE_BUTTON_R2 to InputAction.PageDown,
            KeyEvent.KEYCODE_PAGE_UP to InputAction.PageUp, KeyEvent.KEYCODE_PAGE_DOWN to InputAction.PageDown,
            KeyEvent.KEYCODE_MOVE_HOME to InputAction.Top, KeyEvent.KEYCODE_BUTTON_THUMBR to InputAction.Top,
            KeyEvent.KEYCODE_BUTTON_START to InputAction.Dock, KeyEvent.KEYCODE_BUTTON_SELECT to InputAction.Help,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE to InputAction.PlayPause, KeyEvent.KEYCODE_MEDIA_PLAY to InputAction.Play,
            KeyEvent.KEYCODE_MEDIA_PAUSE to InputAction.Pause, KeyEvent.KEYCODE_MEDIA_STOP to InputAction.Stop,
            KeyEvent.KEYCODE_MEDIA_NEXT to InputAction.NextTrack, KeyEvent.KEYCODE_MEDIA_PREVIOUS to InputAction.PreviousTrack,
            KeyEvent.KEYCODE_MEDIA_REWIND to InputAction.SeekBack, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD to InputAction.SeekForward,
        )
        for ((code, want) in table) assertEquals("key $code", want, act(code))
    }

    @Test fun `modified keys and long presses`() {
        assertEquals(InputAction.Search, act(KeyEvent.KEYCODE_K, ctrl = true))
        assertNull(act(KeyEvent.KEYCODE_K))
        assertEquals(InputAction.PrevTab, act(KeyEvent.KEYCODE_LEFT_BRACKET, ctrl = true))
        assertEquals(InputAction.NextTab, act(KeyEvent.KEYCODE_RIGHT_BRACKET, ctrl = true))
        assertNull(act(KeyEvent.KEYCODE_LEFT_BRACKET))
        assertEquals(InputAction.Help, act(KeyEvent.KEYCODE_SLASH, shift = true))
        assertEquals(InputAction.Options, act(KeyEvent.KEYCODE_F10, shift = true))
        assertNull(act(KeyEvent.KEYCODE_F10))
        // A long OK or A is options; a long Menu is help; a held Enter on a keyboard stays Select.
        assertEquals(InputAction.Options, act(KeyEvent.KEYCODE_DPAD_CENTER, long = true))
        assertEquals(InputAction.Options, act(KeyEvent.KEYCODE_BUTTON_A, long = true))
        assertEquals(InputAction.Help, act(KeyEvent.KEYCODE_MENU, long = true))
        assertEquals(InputAction.Select, act(KeyEvent.KEYCODE_ENTER, long = true))
    }

    @Test fun `channel keys are tabs in the bar and pages elsewhere, and Tab opens the dock only from nothing`() {
        assertEquals(InputAction.PrevTab, act(KeyEvent.KEYCODE_CHANNEL_UP, InputContext(inBar = true)))
        assertEquals(InputAction.NextTab, act(KeyEvent.KEYCODE_CHANNEL_DOWN, InputContext(inBar = true)))
        assertEquals(InputAction.PageUp, act(KeyEvent.KEYCODE_CHANNEL_UP))
        assertEquals(InputAction.PageDown, act(KeyEvent.KEYCODE_CHANNEL_DOWN))
        assertNull(act(KeyEvent.KEYCODE_TAB))
        assertNull(act(KeyEvent.KEYCODE_TAB, InputContext(nothingFocused = true)))
        assertEquals(InputAction.Dock, act(KeyEvent.KEYCODE_TAB, InputContext(nothingFocused = true, hasDock = true)))
        assertNull(act(KeyEvent.KEYCODE_TAB, InputContext(nothingFocused = true, hasDock = true), shift = true))
    }

    @Test fun `every key kind is told apart`() {
        assertEquals(InputKind.Gamepad, KeyMap.kindOf(KeyEvent.KEYCODE_BUTTON_X))
        assertEquals(InputKind.Remote, KeyMap.kindOf(KeyEvent.KEYCODE_MENU))
        assertEquals(InputKind.Remote, KeyMap.kindOf(KeyEvent.KEYCODE_DPAD_CENTER))
        assertEquals(InputKind.Keyboard, KeyMap.kindOf(KeyEvent.KEYCODE_PERIOD))
    }

    @Test fun `the generated key map names every action the rules know`() {
        for (kind in listOf(DesignTokens.INPUT_KEYBOARD, DesignTokens.INPUT_GAMEPAD, DesignTokens.INPUT_REMOTE)) {
            for (a in listOf("move", "select", "back", "options", "search", "tabPrev", "tabNext", "pageUp", "pageDown", "top", "dock", "help")) {
                assertTrue("missing $a", kind.containsKey(a))
            }
        }
        assertEquals(listOf("X", "HoldA"), DesignTokens.INPUT_GAMEPAD["options"])
    }

    @Test fun `zones move by one press and never wrap`() {
        assertEquals(Zone.Bar, Zones.move(Zone.Stage, Heading.Up, atEdge = true, hasDock = false))
        assertNull(Zones.move(Zone.Stage, Heading.Up, atEdge = false, hasDock = false))
        assertEquals(Zone.Stage, Zones.move(Zone.Bar, Heading.Down, true, false))
        assertNull(Zones.move(Zone.Bar, Heading.Up, true, false))
        assertNull(Zones.move(Zone.Stage, Heading.Down, true, hasDock = false))
        assertEquals(Zone.Dock, Zones.move(Zone.Stage, Heading.Down, true, hasDock = true))
        assertEquals(Zone.Stage, Zones.move(Zone.Dock, Heading.Up, true, true))
        for (h in Heading.values()) assertNull("a layer holds focus", Zones.move(Zone.Layer, h, true, true))
        assertFalse(DesignTokens.Nav.WRAP)
    }

    @Test fun `back unwinds layer, dock, stage, bar, then leaves`() {
        assertEquals(BackStep.CloseLayer, BackLadder.next(BackState(true, Zone.Stage, false)))
        assertEquals(BackStep.CloseLayer, BackLadder.next(BackState(false, Zone.Layer, true)))
        assertEquals(BackStep.DockToStage, BackLadder.next(BackState(false, Zone.Dock, false)))
        assertEquals(BackStep.StageToBar, BackLadder.next(BackState(false, Zone.Stage, false)))
        assertEquals(BackStep.BarToHome, BackLadder.next(BackState(false, Zone.Bar, false)))
        assertEquals(BackStep.Leave, BackLadder.next(BackState(false, Zone.Bar, true)))
        // The table in the tokens names the same order.
        assertEquals(listOf("layer", "dock", "stage", "bar", "home", "exit"), DesignTokens.Nav.BACK_LADDER)
    }

    @Test fun `focus memory returns to the last card of a group else the first`() {
        val m = FocusMemory()
        assertEquals("a", m.recall("shelf1", "a"))
        m.remember("shelf1", "c")
        m.remember("shelf2", "x")
        assertEquals("c", m.recall("shelf1", "a"))
        assertEquals("x", m.recall("shelf2", "q"))
        m.forget("shelf1")
        assertEquals("a", m.recall("shelf1", "a"))
    }

    @Test fun `a double press is two of the same key inside the window`() {
        val d = DoublePress(400)
        assertFalse(d.press(KeyEvent.KEYCODE_DPAD_UP, 1000))
        assertTrue(d.press(KeyEvent.KEYCODE_DPAD_UP, 1300))
        assertFalse("a third is a new first", d.press(KeyEvent.KEYCODE_DPAD_UP, 1400))
        assertFalse(d.press(KeyEvent.KEYCODE_DPAD_DOWN, 1500))
        assertFalse(d.press(KeyEvent.KEYCODE_DPAD_UP, 2500))
    }

    @Test fun `the key legend follows the input in use and hides on touch`() {
        assertTrue(KeyLegend.hints(null, true).isEmpty())
        val pad = KeyLegend.hints(InputKind.Gamepad, true)
        assertEquals("A", pad.first { it.words == "Select" }.glyph)
        assertEquals("X", pad.first { it.words == "Options" }.glyph)
        assertTrue(pad.any { it.glyph == "Start" })
        assertFalse(KeyLegend.hints(InputKind.Gamepad, false).any { it.glyph == "Start" })
        assertEquals("Menu", KeyLegend.hints(InputKind.Remote, false).first { it.words == "Options" }.glyph)
    }

    @Test fun `the generated tv numbers are the contract's`() {
        assertEquals(4, DesignTokens.Tv.FOCUS_RING)
        assertEquals(1.06f, DesignTokens.Tv.FOCUS_SCALE, 0f)
        assertEquals(66, DesignTokens.Tv.TARGET_MIN)
        assertEquals(90, DesignTokens.Tv.GUTTER)
        assertEquals(112, DesignTokens.Tv.DOCK_HEIGHT)
        assertEquals(0.18f, DesignTokens.Tv.SHELF_PEEK, 0f)
        assertEquals(listOf("compact", "medium", "expanded").size, 3)
        assertEquals(600, DesignTokens.Breakpoints.COMPACT)
    }
}

class ShelfRulesTest {
    // A TV page: 870 dp of content, 45 dp of margin, 12 dp between cards, a layout card 210 dp wide.
    @Test fun `a shelf with more cards than fit shows a peek of the next`() {
        val w = com.wittywilla.wittymediaclient.net.ShelfRules.cardWidth(915f, 12f, 210f, 0.18f, 20)
        // Four whole cards, four gaps and 0.18 of the next fill the room to the edge.
        assertEquals(915f, 4 * w + 4 * 12f + 0.18f * w, 0.01f)
        assertTrue("stays close to the layout's", w in 168f..252f)
    }

    @Test fun `a short shelf keeps the layout's width`() {
        assertEquals(210f, com.wittywilla.wittymediaclient.net.ShelfRules.cardWidth(915f, 12f, 210f, 0.18f, 3), 0f)
    }

    @Test fun `a change over a fifth is not made`() {
        // Room for 1.6 cards of 300: fitting two and a peek would shrink them by more than a fifth.
        assertEquals(300f, com.wittywilla.wittymediaclient.net.ShelfRules.cardWidth(550f, 24f, 300f, 0.18f, 10), 0f)
    }

    @Test fun `bad input is left alone`() {
        assertEquals(0f, com.wittywilla.wittymediaclient.net.ShelfRules.cardWidth(900f, 12f, 0f, 0.18f, 9), 0f)
        assertEquals(210f, com.wittywilla.wittymediaclient.net.ShelfRules.cardWidth(0f, 12f, 210f, 0.18f, 9), 0f)
    }
}
