package com.wittywilla.wittymediaclient.games

import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt

// The account's touch layout as the website's player reads it (the server's docs/GAMING-API.md, "Touch"): each
// control by its key, its centre as fractions of the play area and its size as a fraction of the shorter side.
// The same sums as the website's, so a layout arranged in a browser works the same here.

data class TouchPoint(val x: Float, val y: Float)

data class TouchArea(val w: Float, val h: Float) {
    val shorter: Float get() = min(w, h)
}

object TouchPad {
    // A finger this near the middle of a D-pad presses nothing.
    private const val DPAD_REST = 0.18

    // A touch stick's own dead zone, from its centre.
    private const val STICK_REST = 0.12

    // A finger counts on a button a little outside it, and on a D-pad further out: thumbs land wide.
    private const val BUTTON_REACH = 1.18
    private const val DPAD_REACH = 1.35
    private const val STICK_REACH = 1.1

    // Which of the D-pad's directions a finger presses, from where it is against the D-pad's centre and half-size:
    // eight slices, so a diagonal presses two.
    fun dpadMask(dx: Double, dy: Double): Int {
        if (hypot(dx, dy) < DPAD_REST) return 0
        val up = RetroPad.bit(RetroPad.UP)
        val down = RetroPad.bit(RetroPad.DOWN)
        val left = RetroPad.bit(RetroPad.LEFT)
        val right = RetroPad.bit(RetroPad.RIGHT)
        return when ((atan2(dy, dx) / (PI / 4)).roundToInt()) {
            0 -> right
            1 -> right or down
            2 -> down
            3 -> down or left
            4, -4 -> left
            -3 -> left or up
            -2 -> up
            -1 -> up or right
            else -> 0
        }
    }

    private data class Stick(val cx: Float, val cy: Float, val half: Float)

    // The first stick shown, where it is in the area.
    private fun stick(controls: List<GameControl>, layout: Map<String, Placement>, area: TouchArea): Stick? {
        for (c in controls) {
            if (!c.isStick) continue
            val p = layout[c.key] ?: continue
            if (p.hidden) continue
            return Stick((p.x * area.w).toFloat(), (p.y * area.h).toFloat(), (p.size * area.shorter / 2).toFloat())
        }
        return null
    }

    fun hasStick(controls: List<GameControl>, layout: Map<String, Placement>): Boolean =
        controls.any { it.isStick && layout[it.key]?.hidden == false }

    // Whether a finger coming down here takes the stick.
    fun onStick(pt: TouchPoint, controls: List<GameControl>, layout: Map<String, Placement>, area: TouchArea): Boolean {
        val s = stick(controls, layout, area) ?: return false
        return hypot((pt.x - s.cx).toDouble(), (pt.y - s.cy).toDouble()) <= s.half * STICK_REACH
    }

    // How far the stick's finger pushes it, from -1 to 1 each way, after its dead zone. Down is positive.
    fun stickPush(pt: TouchPoint?, controls: List<GameControl>, layout: Map<String, Placement>, area: TouchArea): Pair<Double, Double> {
        if (pt == null) return 0.0 to 0.0
        val s = stick(controls, layout, area) ?: return 0.0 to 0.0
        val x = (pt.x - s.cx) / s.half.toDouble()
        val y = (pt.y - s.cy) / s.half.toDouble()
        val m = hypot(x, y)
        if (m < STICK_REST) return 0.0 to 0.0
        val k = (min(1.0, m) - STICK_REST) / (1 - STICK_REST) / m
        return x * k to y * k
    }

    // The RetroPad buttons these fingers hold, the stick's aside.
    fun mask(points: Collection<TouchPoint>, controls: List<GameControl>, layout: Map<String, Placement>, area: TouchArea): Int {
        var held = 0
        for (pt in points) for (c in controls) {
            val p = layout[c.key] ?: continue
            if (p.hidden || c.isStick) continue
            val cx = p.x * area.w
            val cy = p.y * area.h
            val half = p.size * area.shorter / 2
            if (c.kind == "dpad") {
                val dx = (pt.x - cx) / half
                val dy = (pt.y - cy) / half
                if (hypot(dx, dy) <= DPAD_REACH) held = held or dpadMask(dx, dy)
            } else if (hypot(pt.x - cx, pt.y - cy) <= half * BUTTON_REACH) {
                held = held or RetroPad.bit(c.id)
            }
        }
        return held
    }

    // Where a control is drawn: its box, as the website draws it. Meta buttons are about half as tall as wide,
    // shoulders a little more; the rest are square.
    data class Box(val left: Float, val top: Float, val width: Float, val height: Float, val fontSize: Float)

    fun box(c: GameControl, p: Placement, area: TouchArea): Box {
        val k = (p.size * area.shorter).toFloat()
        val h = when (c.kind) {
            "meta" -> k * 0.55f
            "shoulder" -> k * 0.62f
            else -> k
        }
        return Box((p.x * area.w).toFloat() - k / 2, (p.y * area.h).toFloat() - k / 2, k, h, k * if (c.kind == "meta") 0.26f else 0.38f)
    }

    // A console with a touch screen (pad.pointer): a finger on the picture, as the server takes it. 6 bytes: 255,
    // pressed, then X and Y across the whole picture from -32767 to 32767.
    fun pointerMessage(pressed: Boolean, fx: Double, fy: Double): ByteArray {
        fun scale(f: Double) = ((f.coerceIn(0.0, 1.0) * 2 - 1) * 32767).roundToInt()
        val x = scale(fx)
        val y = scale(fy)
        return byteArrayOf(
            255.toByte(), (if (pressed) 1 else 0).toByte(),
            (x and 0xff).toByte(), ((x shr 8) and 0xff).toByte(),
            (y and 0xff).toByte(), ((y shr 8) and 0xff).toByte(),
        )
    }
}
