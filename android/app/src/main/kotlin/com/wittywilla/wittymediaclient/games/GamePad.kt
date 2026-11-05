package com.wittywilla.wittymediaclient.games

import android.view.KeyEvent
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

// Controllers into the server's controller states, the way the website's player does it (the server's
// docs/GAMING-API.md, "Controller states" and "The controller as data"): a pad read in the W3C standard layout,
// the console's default mapping with the account's saved layout and profile over it, their dead zone, press
// point, stick-as-D-pad and turbo, then the shortcuts held with Select. The same rules as the Apple player's.

// The buttons of libretro's RetroPad, by bit. Numbers 16 to 23 are one direction of a stick.
object RetroPad {
    const val B = 0
    const val Y = 1
    const val SELECT = 2
    const val START = 3
    const val UP = 4
    const val DOWN = 5
    const val LEFT = 6
    const val RIGHT = 7
    const val A = 8
    const val X = 9
    const val L = 10
    const val R = 11
    const val L2 = 12
    const val R2 = 13
    const val L3 = 14
    const val R3 = 15
    const val LEFT_STICK_LEFT = 16
    const val LEFT_STICK_RIGHT = 17
    const val LEFT_STICK_UP = 18
    const val LEFT_STICK_DOWN = 19
    const val RIGHT_STICK_LEFT = 20
    const val RIGHT_STICK_RIGHT = 21
    const val RIGHT_STICK_UP = 22
    const val RIGHT_STICK_DOWN = 23

    // The names the server's settings use for them.
    val names = mapOf(
        "b" to B, "y" to Y, "select" to SELECT, "start" to START, "up" to UP, "down" to DOWN, "left" to LEFT, "right" to RIGHT,
        "a" to A, "x" to X, "l" to L, "r" to R, "l2" to L2, "r2" to R2, "l3" to L3, "r3" to R3,
    )

    fun bit(id: Int): Int = if (id in 0..15) 1 shl id else 0
    val DPAD = bit(UP) or bit(DOWN) or bit(LEFT) or bit(RIGHT)
}

// A gamepad as the W3C standard gamepad has it, laid out by position: the bottom face button is 0 whatever
// it's called. Buttons go from 0 to 1, axes from -1 to 1 with down positive.
class StandardPadReading(val buttons: DoubleArray = DoubleArray(17), val axes: DoubleArray = DoubleArray(4)) {
    fun button(n: Int): Double = if (n in buttons.indices) buttons[n] else 0.0
    fun copy() = StandardPadReading(buttons.copyOf(), axes.copyOf())

    companion object {
        const val SOUTH = 0
        const val EAST = 1
        const val WEST = 2
        const val NORTH = 3
        const val L1 = 4
        const val R1 = 5
        const val L2 = 6
        const val R2 = 7
        const val SELECT = 8
        const val START = 9
        const val L3 = 10
        const val R3 = 11
        const val UP = 12
        const val DOWN = 13
        const val LEFT = 14
        const val RIGHT = 15
        const val HOME = 16
    }
}

// One player's controller state, as the server takes it: 13 bytes, little-endian.
data class PadState(
    val port: Int = 0,
    val buttons: Int = 0,
    val lx: Int = 0,
    val ly: Int = 0,
    val rx: Int = 0,
    val ry: Int = 0,
    val l2: Int = 0,
    val r2: Int = 0,
) {
    fun pressed(id: Int): Boolean = buttons and RetroPad.bit(id) != 0

    // Nothing held: what's sent when the app leaves or a menu opens.
    val isReleased: Boolean get() = buttons == 0 && lx == 0 && ly == 0 && rx == 0 && ry == 0 && l2 == 0 && r2 == 0

    fun encoded(): ByteArray {
        val out = ByteArray(13)
        out[0] = port.toByte()
        fun put16(at: Int, v: Int) {
            out[at] = (v and 0xff).toByte()
            out[at + 1] = ((v shr 8) and 0xff).toByte()
        }
        put16(1, buttons and 0xffff)
        put16(3, lx)
        put16(5, ly)
        put16(7, rx)
        put16(9, ry)
        out[11] = l2.coerceIn(0, 255).toByte()
        out[12] = r2.coerceIn(0, 255).toByte()
        return out
    }

    // Two states merged: buttons held on either, and the stick pushed furthest.
    fun merged(other: PadState): PadState {
        fun far(a: Int, b: Int) = if (abs(a) >= abs(b)) a else b
        return PadState(
            port, buttons or other.buttons, far(lx, other.lx), far(ly, other.ly), far(rx, other.rx), far(ry, other.ry),
            max(l2, other.l2), max(r2, other.r2),
        )
    }
}

// A mapping made from the console's defaults and the layers over it, applied to readings.
class PadMapper(defaults: Map<String, PadSource?>?, layers: List<Map<String, PadSource?>?> = emptyList(), options: PadOptions? = null, defaultOptions: PadOptions? = null) {
    // RetroPad target to what presses it.
    val map: Map<Int, PadSource>
    val options: PadOptions = (options ?: PadOptions()).over(defaultOptions)

    init {
        val merged = HashMap<Int, PadSource>()
        // Each layer's targets replace what's below, and a null source takes a target away.
        for (layer in listOf(defaults) + layers) {
            for ((key, source) in layer.orEmpty()) {
                val target = key.toIntOrNull() ?: continue
                if (target !in 0..23) continue
                if (source != null) merged[target] = source else merged.remove(target)
            }
        }
        map = merged
    }

    val deadzone: Double get() = (options.deadzone ?: 0.15).coerceIn(0.0, 0.6)
    val threshold: Double get() = (options.threshold ?: 0.5).coerceIn(0.1, 0.9)
    val turboHz: Double get() = (options.turboHz ?: 12.0).coerceIn(2.0, 30.0)
    val noRumble: Boolean get() = options.noRumble == true

    // The sticks after the dead zone, which is a circle: inside it is rest, and the rest of the way is spread
    // over the whole range.
    fun sticks(reading: StandardPadReading): DoubleArray {
        val axes = reading.axes.copyOf()
        for ((xi, yi) in listOf(0 to 1, 2 to 3)) {
            val x = axes[xi]
            val y = axes[yi]
            val m = sqrt(x * x + y * y)
            if (m <= deadzone || m == 0.0) {
                axes[xi] = 0.0
                axes[yi] = 0.0
            } else {
                val scaled = (min(m, 1.0) - deadzone) / (1 - deadzone) / m
                axes[xi] = x * scaled
                axes[yi] = y * scaled
            }
        }
        return axes
    }

    // How far a source is pressed, from 0 to 1.
    private fun value(source: PadSource, reading: StandardPadReading, sticks: DoubleArray): Double {
        source.b?.let { return reading.button(it).coerceIn(0.0, 1.0) }
        val a = source.a ?: return 0.0 // a D-pad as one axis only comes from browsers that can't put a pad in order
        val raw = if (a in 0..3) sticks[a] else 0.0
        val rest = source.r ?: 0
        if (rest != 0) {
            // A trigger that rests at one end counts from there.
            return ((raw - rest) / (-2.0 * rest)).coerceIn(0.0, 1.0)
        }
        return (raw * (source.d ?: 1)).coerceIn(0.0, 1.0)
    }

    fun state(reading: StandardPadReading, port: Int, nowSeconds: Double = 0.0, applyTurbo: Boolean = true): PadState {
        val sticks = sticks(reading)
        val amounts = DoubleArray(24)
        for ((target, source) in map) amounts[target] = max(amounts[target], value(source, reading, sticks))
        var buttons = 0
        // A button is pressed or not; an analog input, a trigger or a stick, presses it past the press point.
        for (id in 0..15) if (amounts[id] > 0 && amounts[id] >= threshold) buttons = buttons or RetroPad.bit(id)
        fun axis(minus: Int, plus: Int) = ((amounts[plus] - amounts[minus]).coerceIn(-1.0, 1.0) * 32767).roundToInt()
        if (options.stickDpad ?: true) {
            // The left stick steers the D-pad as well.
            if (sticks[0] <= -threshold) buttons = buttons or RetroPad.bit(RetroPad.LEFT)
            if (sticks[0] >= threshold) buttons = buttons or RetroPad.bit(RetroPad.RIGHT)
            if (sticks[1] <= -threshold) buttons = buttons or RetroPad.bit(RetroPad.UP)
            if (sticks[1] >= threshold) buttons = buttons or RetroPad.bit(RetroPad.DOWN)
        }
        if (applyTurbo) buttons = turbo(buttons, options.turbo.orEmpty(), turboHz, nowSeconds)
        return PadState(
            port, buttons,
            axis(RetroPad.LEFT_STICK_LEFT, RetroPad.LEFT_STICK_RIGHT), axis(RetroPad.LEFT_STICK_UP, RetroPad.LEFT_STICK_DOWN),
            axis(RetroPad.RIGHT_STICK_LEFT, RetroPad.RIGHT_STICK_RIGHT), axis(RetroPad.RIGHT_STICK_UP, RetroPad.RIGHT_STICK_DOWN),
            (amounts[RetroPad.L2] * 255).roundToInt(), (amounts[RetroPad.R2] * 255).roundToInt(),
        )
    }

    val hasTurbo: Boolean get() = options.turbo.orEmpty().isNotEmpty()

    companion object {
        // Buttons that repeat while held: pressed for the first half of each beat.
        fun turbo(buttons: Int, ids: List<Int>, hz: Double, nowSeconds: Double): Int {
            if (ids.isEmpty() || hz <= 0) return buttons
            val on = floor(nowSeconds * hz * 2).toLong() % 2 == 0L
            if (on) return buttons
            var out = buttons
            for (id in ids) out = out and RetroPad.bit(id).inv()
            return out
        }
    }
}

// Keys into states: a TV remote by KeyboardEvent.key names, or a keyboard by KeyboardEvent.code names, from the
// console's defaults.remote or defaults.keyboard.
class KeyMapper(map: Map<String, String>?) {
    // Key name to the targets it presses.
    val targets: Map<String, List<Int>>

    init {
        val out = HashMap<String, MutableList<Int>>()
        for ((key, name) in map.orEmpty()) {
            val target = key.toIntOrNull() ?: continue
            if (target !in 0..23) continue
            out.getOrPut(name) { mutableListOf() }.add(target)
        }
        targets = out.mapValues { it.value.sorted() }
    }

    fun knows(name: String): Boolean = targets.containsKey(name)

    fun state(held: Set<String>, port: Int = 0): PadState {
        var buttons = 0
        val push = BooleanArray(24)
        for (name in held) for (target in targets[name].orEmpty()) {
            if (target < 16) buttons = buttons or RetroPad.bit(target) else push[target] = true
        }
        fun axis(minus: Int, plus: Int) = if (push[plus]) 32767 else if (push[minus]) -32767 else 0
        return PadState(
            port, buttons,
            axis(RetroPad.LEFT_STICK_LEFT, RetroPad.LEFT_STICK_RIGHT), axis(RetroPad.LEFT_STICK_UP, RetroPad.LEFT_STICK_DOWN),
            axis(RetroPad.RIGHT_STICK_LEFT, RetroPad.RIGHT_STICK_RIGHT), axis(RetroPad.RIGHT_STICK_UP, RetroPad.RIGHT_STICK_DOWN),
            if (buttons and RetroPad.bit(RetroPad.L2) != 0) 255 else 0, if (buttons and RetroPad.bit(RetroPad.R2) != 0) 255 else 0,
        )
    }
}

// What the shortcut button and another can do, by the person's hotkeys.pad.* settings.
enum class PadShortcut(val setting: String, val fallback: String) {
    Menu("menu", "b"),
    FastForward("fastForward", "r"),
    Rewind("rewind", "l"),
    QuickSave("quickSave", "r2"),
    QuickLoad("quickLoad", "l2"),
    Slow("slow", "x"),
    Pause("pause", "y"),
    Advance("advance", "right"),
    Screenshot("screenshot", "a"),
    ;

    // Held for as long as the buttons are, rather than done once.
    val isHeld: Boolean get() = this == FastForward || this == Rewind || this == Slow
}

// Shortcuts held with a modifier, as the website's player has them. Start and Select together always open the
// menu. A button used for a shortcut isn't seen by the game until it's let go.
class PadShortcuts(settings: GameSettings?, consoleButtons: Set<Int>) {
    private val modifier: Int
    private val combos: Boolean = settings?.flag("hotkeys.padCombos", true) ?: true
    private val byBit: Map<Int, PadShortcut>

    // Whether the console has the modifier: if not, the game never sees it.
    private val consoleHasModifier: Boolean
    private var last = 0
    private var hidden = 0
    private val running = HashMap<Int, PadShortcut>()

    init {
        val modifierId = RetroPad.names[settings?.text("hotkeys.padModifier", "select") ?: "select"] ?: RetroPad.SELECT
        modifier = RetroPad.bit(modifierId)
        consoleHasModifier = consoleButtons.isEmpty() || modifierId in consoleButtons
        val table = HashMap<Int, PadShortcut>()
        for (shortcut in PadShortcut.entries) {
            val name = settings?.text("hotkeys.pad.${shortcut.setting}", shortcut.fallback) ?: shortcut.fallback
            val id = RetroPad.names[name] ?: continue
            val bit = RetroPad.bit(id)
            if (bit != modifier && !table.containsKey(bit)) table[bit] = shortcut
        }
        byBit = table
    }

    data class Result(val buttons: Int, val started: List<PadShortcut>, val ended: List<PadShortcut>)

    // Ends every shortcut in progress, for a controller that went away or a menu that opened. Answers the held
    // ones, which have to be told to stop.
    fun endAll(): List<PadShortcut> {
        val held = running.values.filter { it.isHeld }.sortedBy { it.ordinal }
        running.clear()
        hidden = 0
        last = 0
        return held
    }

    // What the game should see of these buttons, and which shortcuts began or ended.
    fun filter(buttons: Int): Result {
        val down = buttons and last.inv()
        val started = mutableListOf<PadShortcut>()
        val ended = mutableListOf<PadShortcut>()
        val menuPair = RetroPad.bit(RetroPad.START) or RetroPad.bit(RetroPad.SELECT)
        if (buttons and menuPair == menuPair && down and menuPair != 0) {
            started += PadShortcut.Menu
            hidden = hidden or menuPair
        } else if (combos && buttons and modifier != 0) {
            for ((bit, shortcut) in byBit) if (down and bit != 0) {
                started += shortcut
                hidden = hidden or bit
                running[bit] = shortcut
            }
        }
        // Let go: the button counts again, and a held shortcut stops.
        val iterator = running.entries.iterator()
        while (iterator.hasNext()) {
            val (bit, shortcut) = iterator.next()
            if (buttons and bit == 0) {
                if (shortcut.isHeld) ended += shortcut
                iterator.remove()
            }
        }
        hidden = hidden and buttons
        last = buttons
        var seen = buttons and hidden.inv()
        if (!consoleHasModifier) seen = seen and modifier.inv()
        return Result(seen, started.sortedBy { it.ordinal }, ended.sortedBy { it.ordinal })
    }
}

// Android's names for a pad's buttons, which are by position as the W3C standard gamepad's are: a Nintendo pad's
// A, on the right, arrives as BUTTON_B. So the console's mappings, written in W3C numbers, need no translating.
object AndroidPad {
    fun standardButton(keyCode: Int): Int? = when (keyCode) {
        KeyEvent.KEYCODE_BUTTON_A -> StandardPadReading.SOUTH
        KeyEvent.KEYCODE_BUTTON_B -> StandardPadReading.EAST
        KeyEvent.KEYCODE_BUTTON_X -> StandardPadReading.WEST
        KeyEvent.KEYCODE_BUTTON_Y -> StandardPadReading.NORTH
        KeyEvent.KEYCODE_BUTTON_L1 -> StandardPadReading.L1
        KeyEvent.KEYCODE_BUTTON_R1 -> StandardPadReading.R1
        KeyEvent.KEYCODE_BUTTON_L2 -> StandardPadReading.L2
        KeyEvent.KEYCODE_BUTTON_R2 -> StandardPadReading.R2
        KeyEvent.KEYCODE_BUTTON_SELECT -> StandardPadReading.SELECT
        KeyEvent.KEYCODE_BUTTON_START -> StandardPadReading.START
        KeyEvent.KEYCODE_BUTTON_THUMBL -> StandardPadReading.L3
        KeyEvent.KEYCODE_BUTTON_THUMBR -> StandardPadReading.R3
        KeyEvent.KEYCODE_DPAD_UP -> StandardPadReading.UP
        KeyEvent.KEYCODE_DPAD_DOWN -> StandardPadReading.DOWN
        KeyEvent.KEYCODE_DPAD_LEFT -> StandardPadReading.LEFT
        KeyEvent.KEYCODE_DPAD_RIGHT -> StandardPadReading.RIGHT
        else -> null
    }

    // The key a profile names this controller by: vendor:product in lowercase hex, or its name where it has no numbers.
    fun profileKey(vendorId: Int, productId: Int, name: String): String =
        if (vendorId > 0 || productId > 0) "%04x:%04x".format(vendorId and 0xffff, productId and 0xffff) else "id:" + name.take(60)
}

// A key pressed on a TV remote, by the KeyboardEvent.key name the console's defaults.remote uses.
fun remoteKeyName(keyCode: Int): String? = when (keyCode) {
    KeyEvent.KEYCODE_DPAD_UP -> "ArrowUp"
    KeyEvent.KEYCODE_DPAD_DOWN -> "ArrowDown"
    KeyEvent.KEYCODE_DPAD_LEFT -> "ArrowLeft"
    KeyEvent.KEYCODE_DPAD_RIGHT -> "ArrowRight"
    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> "Enter"
    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> "MediaPlayPause"
    KeyEvent.KEYCODE_MEDIA_REWIND -> "MediaRewind"
    KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> "MediaFastForward"
    else -> null
}

// A key on a keyboard, by the KeyboardEvent.code name the console's defaults.keyboard uses.
fun keyboardCodeName(keyCode: Int): String? = when (keyCode) {
    in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> "Key" + ('A' + (keyCode - KeyEvent.KEYCODE_A))
    in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> "Digit" + (keyCode - KeyEvent.KEYCODE_0)
    in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> "Numpad" + (keyCode - KeyEvent.KEYCODE_NUMPAD_0)
    in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F12 -> "F" + (keyCode - KeyEvent.KEYCODE_F1 + 1)
    KeyEvent.KEYCODE_DPAD_UP -> "ArrowUp"
    KeyEvent.KEYCODE_DPAD_DOWN -> "ArrowDown"
    KeyEvent.KEYCODE_DPAD_LEFT -> "ArrowLeft"
    KeyEvent.KEYCODE_DPAD_RIGHT -> "ArrowRight"
    KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_DPAD_CENTER -> "Enter"
    KeyEvent.KEYCODE_NUMPAD_ENTER -> "NumpadEnter"
    KeyEvent.KEYCODE_SPACE -> "Space"
    KeyEvent.KEYCODE_TAB -> "Tab"
    KeyEvent.KEYCODE_DEL -> "Backspace"
    KeyEvent.KEYCODE_FORWARD_DEL -> "Delete"
    KeyEvent.KEYCODE_ESCAPE -> "Escape"
    KeyEvent.KEYCODE_SHIFT_LEFT -> "ShiftLeft"
    KeyEvent.KEYCODE_SHIFT_RIGHT -> "ShiftRight"
    KeyEvent.KEYCODE_CTRL_LEFT -> "ControlLeft"
    KeyEvent.KEYCODE_CTRL_RIGHT -> "ControlRight"
    KeyEvent.KEYCODE_ALT_LEFT -> "AltLeft"
    KeyEvent.KEYCODE_ALT_RIGHT -> "AltRight"
    KeyEvent.KEYCODE_COMMA -> "Comma"
    KeyEvent.KEYCODE_PERIOD -> "Period"
    KeyEvent.KEYCODE_SLASH -> "Slash"
    KeyEvent.KEYCODE_SEMICOLON -> "Semicolon"
    KeyEvent.KEYCODE_APOSTROPHE -> "Quote"
    KeyEvent.KEYCODE_LEFT_BRACKET -> "BracketLeft"
    KeyEvent.KEYCODE_RIGHT_BRACKET -> "BracketRight"
    KeyEvent.KEYCODE_MINUS -> "Minus"
    KeyEvent.KEYCODE_EQUALS -> "Equal"
    KeyEvent.KEYCODE_BACKSLASH -> "Backslash"
    KeyEvent.KEYCODE_GRAVE -> "Backquote"
    KeyEvent.KEYCODE_PAGE_UP -> "PageUp"
    KeyEvent.KEYCODE_PAGE_DOWN -> "PageDown"
    KeyEvent.KEYCODE_MOVE_HOME -> "Home"
    KeyEvent.KEYCODE_MOVE_END -> "End"
    else -> null
}

// The server's names for its save slots.
object GameWords {
    fun slotName(slot: Int): String = when (slot) {
        0 -> "Automatic save"
        100 -> "Before the last load"
        101 -> "Before starting over"
        else -> "Slot $slot"
    }

    // Only these can be saved to: 0, 100 and 101 are the server's own, for loading.
    fun canSaveTo(slot: Int): Boolean = slot in 1..99

    // "2 h 5 min", or "12 min", as the website says it.
    fun played(seconds: Double): String {
        val total = max(0, seconds.toInt())
        val hours = total / 3600
        val minutes = ((total % 3600) / 60.0).roundToInt()
        return if (hours > 0) "$hours h $minutes min" else "${max(1, minutes)} min"
    }

    // "just now", "5 minutes ago", "yesterday", or a date.
    fun ago(unix: Long, nowMillis: Long = System.currentTimeMillis()): String {
        val s = nowMillis / 1000.0 - unix
        return when {
            s < 90 -> "just now"
            s < 3600 -> "${(s / 60).roundToInt()} minutes ago"
            s < 86400 -> (s / 3600).roundToInt().let { if (it == 1) "1 hour ago" else "$it hours ago" }
            s < 86400 * 2 -> "yesterday"
            s < 86400 * 30 -> "${(s / 86400).roundToInt()} days ago"
            else -> java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date(unix * 1000))
        }
    }

    fun players(n: Int): String = if (n == 1) "1 player" else "Up to $n players"

    fun size(bytes: Long): String = when {
        bytes <= 0 -> ""
        bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1e9)
        else -> "${max(1, (bytes / 1e6).roundToInt())} MB"
    }
}

// What Play does when a game has an automatic save, by the person's states.resume setting: "ask" offers Resume
// with Start over beside it, "always" resumes, "never" starts from the beginning with the save still there.
fun resumes(resumeSetting: String, hasAutoSave: Boolean): Boolean = hasAutoSave && resumeSetting != "never"
