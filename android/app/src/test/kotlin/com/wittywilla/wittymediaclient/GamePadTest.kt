package com.wittywilla.wittymediaclient

import android.view.KeyEvent
import com.wittywilla.wittymediaclient.games.AndroidPad
import com.wittywilla.wittymediaclient.games.GameControls
import com.wittywilla.wittymediaclient.games.GameSettings
import com.wittywilla.wittymediaclient.games.KeyMapper
import com.wittywilla.wittymediaclient.games.PadMapper
import com.wittywilla.wittymediaclient.games.PadOptions
import com.wittywilla.wittymediaclient.games.PadShortcut
import com.wittywilla.wittymediaclient.games.PadShortcuts
import com.wittywilla.wittymediaclient.games.PadSource
import com.wittywilla.wittymediaclient.games.PadState
import com.wittywilla.wittymediaclient.games.RetroPad
import com.wittywilla.wittymediaclient.games.StandardPadReading
import com.wittywilla.wittymediaclient.games.keyboardCodeName
import com.wittywilla.wittymediaclient.games.remoteKeyName
import com.wittywilla.wittymediaclient.games.resumes
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Controllers into the server's controller states (the server's docs/GAMING-API.md, "Controller states"), with
// the SNES's own defaults as the local server sends them.
class GamePadTest {
    private val snes: GameControls = json.decodeFromString(
        """{"console":"snes","pad":{"face":[{"id":1,"label":"Y"},{"id":9,"label":"X"},{"id":0,"label":"B"},{"id":8,"label":"A"}],
        "shoulder":[{"id":10,"label":"L"},{"id":11,"label":"R"}],"meta":[{"id":2,"label":"Select"},{"id":3,"label":"Start"}],"art":"four"},
        "controls":[{"key":"dpad","id":-1,"label":"D-pad","kind":"dpad"},{"key":"b8","id":8,"label":"A","kind":"face"}],
        "defaults":{"gamepad":{"0":{"b":0},"1":{"b":2},"10":{"b":4},"11":{"b":5},"2":{"b":8},"3":{"b":9},"4":{"b":12},"5":{"b":13},"6":{"b":14},"7":{"b":15},"8":{"b":1},"9":{"b":3}},
        "remote":{"0":"MediaPlayPause","2":"MediaRewind","3":"MediaFastForward","4":"ArrowUp","5":"ArrowDown","6":"ArrowLeft","7":"ArrowRight","8":"Enter"},
        "keyboard":{"0":"KeyZ","1":"KeyA","10":"KeyQ","11":"KeyW","2":"ShiftRight","3":"Enter","4":"ArrowUp","5":"ArrowDown","6":"ArrowLeft","7":"ArrowRight","8":"KeyX","9":"KeyS"},
        "options":{"deadzone":0.15,"threshold":0.5,"stickDpad":true,"turboHz":12},
        "touch":{"landscape":{"b8":{"x":0.955,"y":0.62,"size":0.15,"opacity":0.55}},"portrait":{}}},
        "saved":{"gamepad":{},"keyboard":null,"touch":{}},"profiles":[],"game":0}""",
    )

    private fun reading(vararg pressed: Int, axes: DoubleArray = DoubleArray(4)) =
        StandardPadReading(DoubleArray(17).also { b -> pressed.forEach { b[it] = 1.0 } }, axes)

    @Test
    fun aStateIsThirteenLittleEndianBytes() {
        val s = PadState(port = 2, buttons = 0x0109, lx = -32767, ly = 32767, rx = 1, ry = -1, l2 = 255, r2 = 7)
        assertArrayEquals(
            byteArrayOf(2, 0x09, 0x01, 0x01, 0x80.toByte(), 0xFF.toByte(), 0x7F, 1, 0, 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 7),
            s.encoded(),
        )
        assertTrue(PadState(1).isReleased)
    }

    @Test
    fun theConsolesDefaultsMapByPosition() {
        val mapper = PadMapper(snes.defaults.gamepad, defaultOptions = snes.defaults.options)
        // The bottom face button is the SNES's B, the right one its A.
        assertEquals(RetroPad.bit(RetroPad.B), mapper.state(reading(StandardPadReading.SOUTH), 0).buttons)
        assertEquals(RetroPad.bit(RetroPad.A), mapper.state(reading(StandardPadReading.EAST), 0).buttons)
        assertEquals(RetroPad.bit(RetroPad.START), mapper.state(reading(StandardPadReading.START), 0).buttons)
        assertEquals(RetroPad.bit(RetroPad.UP) or RetroPad.bit(RetroPad.L), mapper.state(reading(StandardPadReading.UP, StandardPadReading.L1), 0).buttons)
    }

    @Test
    fun aProfileLayerReplacesAndTakesAway() {
        val profile = mapOf("8" to PadSource(b = 0), "0" to null)
        val mapper = PadMapper(snes.defaults.gamepad, listOf(profile))
        // A is now the bottom button, and nothing presses B.
        assertEquals(RetroPad.bit(RetroPad.A), mapper.state(reading(StandardPadReading.SOUTH), 0).buttons)
        assertEquals(0, mapper.state(reading(StandardPadReading.EAST), 0).buttons)
    }

    @Test
    fun theLeftStickSteersTheDpadPastThePressPoint() {
        val mapper = PadMapper(snes.defaults.gamepad, defaultOptions = snes.defaults.options)
        assertEquals(0, mapper.state(reading(axes = doubleArrayOf(0.1, 0.0, 0.0, 0.0)), 0).buttons) // inside the dead zone
        assertEquals(RetroPad.bit(RetroPad.RIGHT), mapper.state(reading(axes = doubleArrayOf(0.95, 0.0, 0.0, 0.0)), 0).buttons)
        assertEquals(RetroPad.bit(RetroPad.UP), mapper.state(reading(axes = doubleArrayOf(0.0, -0.9, 0.0, 0.0)), 0).buttons)
        val off = PadMapper(snes.defaults.gamepad, options = PadOptions(stickDpad = false))
        assertEquals(0, off.state(reading(axes = doubleArrayOf(0.95, 0.0, 0.0, 0.0)), 0).buttons)
    }

    @Test
    fun sticksAndTriggersAreAnalog() {
        // A console with sticks: 16-23 are a stick's directions, triggers are their own bytes.
        val map = mapOf("17" to PadSource(a = 0, d = 1), "16" to PadSource(a = 0, d = -1), "12" to PadSource(b = 6), "13" to PadSource(b = 7))
        val mapper = PadMapper(map, options = PadOptions(deadzone = 0.0, stickDpad = false))
        val r = StandardPadReading(DoubleArray(17).also { it[6] = 0.25; it[7] = 0.8 }, doubleArrayOf(-1.0, 0.0, 0.0, 0.0))
        val s = mapper.state(r, 1)
        assertEquals(-32767, s.lx)
        assertEquals(64, s.l2)
        assertEquals(204, s.r2)
        // Past the press point a trigger sets its button too; short of it, not.
        assertTrue(s.pressed(RetroPad.R2))
        assertFalse(s.pressed(RetroPad.L2))
    }

    @Test
    fun turboRepeatsWhileHeld() {
        val mapper = PadMapper(snes.defaults.gamepad, options = PadOptions(turbo = listOf(RetroPad.B), turboHz = 10.0))
        val held = reading(StandardPadReading.SOUTH)
        assertTrue(mapper.state(held, 0, nowSeconds = 0.01).pressed(RetroPad.B))
        assertFalse(mapper.state(held, 0, nowSeconds = 0.06).pressed(RetroPad.B))
        assertTrue(mapper.state(held, 0, nowSeconds = 0.11).pressed(RetroPad.B))
    }

    @Test
    fun startAndSelectTogetherOpenTheMenuAndTheGameSeesNeither() {
        val shortcuts = PadShortcuts(null, setOf(0, 1, 2, 3, 8, 9, 10, 11))
        val both = RetroPad.bit(RetroPad.START) or RetroPad.bit(RetroPad.SELECT)
        val r = shortcuts.filter(both)
        assertEquals(listOf(PadShortcut.Menu), r.started)
        assertEquals(0, r.buttons)
        // Let go of both: nothing more happens, and the buttons count again afterwards.
        assertEquals(0, shortcuts.filter(0).buttons)
        assertEquals(RetroPad.bit(RetroPad.START), shortcuts.filter(RetroPad.bit(RetroPad.START)).buttons)
    }

    @Test
    fun selectWithRFastForwardsWhileHeld() {
        val shortcuts = PadShortcuts(GameSettings.of(mapOf("hotkeys.pad.fastForward" to "r")), setOf(0, 2, 3, 11))
        val select = RetroPad.bit(RetroPad.SELECT)
        val r = RetroPad.bit(RetroPad.R)
        assertEquals(select, shortcuts.filter(select).buttons)
        val on = shortcuts.filter(select or r)
        assertEquals(listOf(PadShortcut.FastForward), on.started)
        assertEquals(select, on.buttons) // R is the shortcut's, not the game's
        val off = shortcuts.filter(select)
        assertEquals(listOf(PadShortcut.FastForward), off.ended)
    }

    @Test
    fun keysPressByName() {
        val keys = KeyMapper(snes.defaults.keyboard)
        assertEquals(RetroPad.bit(RetroPad.A) or RetroPad.bit(RetroPad.UP), keys.state(setOf("KeyX", "ArrowUp")).buttons)
        assertTrue(keys.knows("Enter"))
        assertFalse(keys.knows("KeyP"))
        val remote = KeyMapper(snes.defaults.remote)
        assertEquals(RetroPad.bit(RetroPad.B), remote.state(setOf("MediaPlayPause")).buttons)
    }

    @Test
    fun androidNamesTurnIntoTheWebsNames() {
        assertEquals(StandardPadReading.SOUTH, AndroidPad.standardButton(KeyEvent.KEYCODE_BUTTON_A))
        assertEquals(StandardPadReading.WEST, AndroidPad.standardButton(KeyEvent.KEYCODE_BUTTON_X))
        assertEquals(StandardPadReading.NORTH, AndroidPad.standardButton(KeyEvent.KEYCODE_BUTTON_Y))
        assertEquals(StandardPadReading.SELECT, AndroidPad.standardButton(KeyEvent.KEYCODE_BUTTON_SELECT))
        assertEquals(StandardPadReading.RIGHT, AndroidPad.standardButton(KeyEvent.KEYCODE_DPAD_RIGHT))
        assertEquals("KeyX", keyboardCodeName(KeyEvent.KEYCODE_X))
        assertEquals("Digit7", keyboardCodeName(KeyEvent.KEYCODE_7))
        assertEquals("ShiftRight", keyboardCodeName(KeyEvent.KEYCODE_SHIFT_RIGHT))
        assertEquals("F2", keyboardCodeName(KeyEvent.KEYCODE_F2))
        assertEquals("Enter", remoteKeyName(KeyEvent.KEYCODE_DPAD_CENTER))
        assertEquals("MediaPlayPause", remoteKeyName(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        assertEquals("054c:0ce6", AndroidPad.profileKey(0x054c, 0x0ce6, "DualSense"))
        assertEquals("id:Some Pad", AndroidPad.profileKey(0, 0, "Some Pad"))
    }

    @Test
    fun resumeFollowsTheSetting() {
        assertTrue(resumes("ask", hasAutoSave = true))
        assertTrue(resumes("always", hasAutoSave = true))
        assertFalse(resumes("never", hasAutoSave = true))
        assertFalse(resumes("ask", hasAutoSave = false))
    }
}
