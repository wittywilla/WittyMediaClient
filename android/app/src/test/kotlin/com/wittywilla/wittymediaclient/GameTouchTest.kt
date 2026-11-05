package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.games.GameControl
import com.wittywilla.wittymediaclient.games.Placement
import com.wittywilla.wittymediaclient.games.RetroPad
import com.wittywilla.wittymediaclient.games.TouchArea
import com.wittywilla.wittymediaclient.games.TouchPad
import com.wittywilla.wittymediaclient.games.TouchPoint
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The touch layout, read with the website player's own sums, on the SNES's landscape layout from the local server.
class GameTouchTest {
    private val controls = listOf(
        GameControl("dpad", -1, "D-pad", "dpad"),
        GameControl("b8", 8, "A", "face"),
        GameControl("b0", 0, "B", "face"),
        GameControl("b3", 3, "Start", "meta"),
        GameControl("b10", 10, "L", "shoulder"),
    )
    private val layout = mapOf(
        "dpad" to Placement(0.13, 0.62, 0.36),
        "b8" to Placement(0.955, 0.62, 0.15),
        "b0" to Placement(0.87, 0.79, 0.15),
        "b3" to Placement(0.565, 0.91, 0.108),
        "b10" to Placement(0.1, 0.14, 0.12),
    )
    private val area = TouchArea(2000f, 1000f)

    @Test
    fun theDpadHasEightSlices() {
        val up = RetroPad.bit(RetroPad.UP)
        val right = RetroPad.bit(RetroPad.RIGHT)
        assertEquals(0, TouchPad.dpadMask(0.1, 0.1))
        assertEquals(right, TouchPad.dpadMask(0.8, 0.0))
        assertEquals(up, TouchPad.dpadMask(0.0, -0.8))
        assertEquals(up or right, TouchPad.dpadMask(0.6, -0.6))
        assertEquals(RetroPad.bit(RetroPad.LEFT), TouchPad.dpadMask(-0.8, 0.05))
    }

    @Test
    fun fingersPressWhatTheyAreOn() {
        // A at (1910, 620), the D-pad at (260, 620) and 180 to each side.
        assertEquals(RetroPad.bit(RetroPad.A), TouchPad.mask(listOf(TouchPoint(1910f, 620f)), controls, layout, area))
        assertEquals(RetroPad.bit(RetroPad.RIGHT), TouchPad.mask(listOf(TouchPoint(400f, 620f)), controls, layout, area))
        val both = TouchPad.mask(listOf(TouchPoint(1910f, 620f), TouchPoint(260f, 480f)), controls, layout, area)
        assertEquals(RetroPad.bit(RetroPad.A) or RetroPad.bit(RetroPad.UP), both)
        // The middle of the screen presses nothing.
        assertEquals(0, TouchPad.mask(listOf(TouchPoint(1000f, 400f)), controls, layout, area))
        // A hidden control can't be pressed.
        assertEquals(0, TouchPad.mask(listOf(TouchPoint(1910f, 620f)), controls, layout + ("b8" to Placement(0.955, 0.62, 0.15, hidden = true)), area))
    }

    @Test
    fun aStickFollowsTheThumbFromItsCentre() {
        val stick = listOf(GameControl("stick", -1, "Stick", "stick"))
        val at = mapOf("stick" to Placement(0.2, 0.5, 0.3))
        // The centre is (400, 500) and the edge 150 away.
        assertTrue(TouchPad.onStick(TouchPoint(450f, 500f), stick, at, area))
        assertFalse(TouchPad.onStick(TouchPoint(700f, 500f), stick, at, area))
        val (x, y) = TouchPad.stickPush(TouchPoint(550f, 500f), stick, at, area)
        assertEquals(1.0, x, 1e-9)
        assertEquals(0.0, y, 1e-9)
        assertEquals(0.0 to 0.0, TouchPad.stickPush(TouchPoint(405f, 500f), stick, at, area))
        assertTrue(TouchPad.hasStick(stick, at))
    }

    @Test
    fun controlsAreSizedAsTheWebsiteDrawsThem() {
        val start = TouchPad.box(controls[3], layout.getValue("b3"), area)
        assertEquals(108f, start.width, 0.01f)
        assertEquals(108f * 0.55f, start.height, 0.01f)
        val l = TouchPad.box(controls[4], layout.getValue("b10"), area)
        assertEquals(120f * 0.62f, l.height, 0.01f)
    }

    @Test
    fun theStylusIsAcrossTheWholePicture() {
        assertArrayEquals(byteArrayOf(255.toByte(), 1, 0x01, 0x80.toByte(), 0xFF.toByte(), 0x7F), TouchPad.pointerMessage(true, 0.0, 1.0))
        assertArrayEquals(byteArrayOf(255.toByte(), 0, 0, 0, 0, 0), TouchPad.pointerMessage(false, 0.5, 0.5))
    }
}
