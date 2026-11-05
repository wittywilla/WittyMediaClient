package com.wittywilla.wittymediaclient.games

import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.os.CombinedVibration
import android.os.VibrationEffect
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.roundToInt

// Controllers into the server's controller states, on Android. Gamepads come as key and joystick events, read
// into the W3C standard layout that the console's mappings and the account's profiles are written in; each gets
// the next free player, 1 to 4, and keeps it while it's connected. A keyboard plays by the console's keyboard
// layout. A TV's remote is for the menus only (docs/APP-DESIGN.md, "Games everywhere"): Back opens the game menu,
// and so does Start and Select together on a pad. Everything is let go when the menu opens or the app leaves.

// Where the app's activity hands controller events while a game is on screen. Nothing else changes in it.
object GameInputHub {
    @Volatile
    var handler: GameInput? = null

    fun key(event: KeyEvent): Boolean = handler?.onKey(event) ?: false
    fun motion(event: MotionEvent): Boolean = handler?.onMotion(event) ?: false
}

// A player and what they play with, for the menu.
data class GamePlayerInfo(val deviceId: Int, val port: Int, val name: String, val profile: String)

private const val HEARTBEAT_MS = 250L
private const val RUMBLE_MS = 1_000L

class GameInput(context: Context, private val scope: CoroutineScope, private val isTv: Boolean) : InputManager.InputDeviceListener {
    // Everything the game needs to know about a console's controller.
    class Setup(val controls: GameControls, val settings: GameSettings, val console: String, val game: Long)

    private class Pad(val deviceId: Int, var port: Int, val name: String, val key: String, var mapper: PadMapper, var shortcuts: PadShortcuts) {
        val reading = StandardPadReading()
        val keyDpad = BooleanArray(4) // up, down, left, right from keys
        val hatDpad = BooleanArray(4) // the same from a hat
        var digitalL2 = 0.0
        var digitalR2 = 0.0
        var analogL2 = 0.0
        var analogR2 = 0.0
        var state = PadState(port)

        // Buttons held when play came back, from the press that closed the menu: not the game's until let go.
        var masked = 0
        var profile = ""
        var strong = 0.0
        var weak = 0.0
        var rumbledAt = 0L
    }

    private val inputManager = context.getSystemService(Context.INPUT_SERVICE) as InputManager
    private val main = Handler(Looper.getMainLooper())
    private var setup: Setup? = null
    private val pads = LinkedHashMap<Int, Pad>()
    private var keyboard = KeyMapper(null)
    private val keysHeld = HashSet<String>()
    private var keyShortcuts = emptyMap<String, PadShortcut>()
    private var touchMask = 0
    private var touchStick = 0 to 0
    private var keysUsed = false
    private var touchUsed = false
    private val sent = HashMap<Int, PadState>()
    private var pointerDown = false
    private var pointer: ByteArray? = null
    private var pointerReleases = 0
    private var started = false

    // While false, nothing reaches the game: the menu is open, or the app is away.
    var enabled = false
        private set

    var send: (ByteArray) -> Unit = {}
    var onShortcut: (PadShortcut, Boolean) -> Unit = { _, _ -> }
    var onMenu: () -> Unit = {}
    var onNotice: (String) -> Unit = {}
    var loadProfile: suspend (String) -> ResolvedPad? = { null }

    // For the screen: who plays as whom, and whether a controller is in use (the touch controls step aside).
    var players by mutableStateOf<List<GamePlayerInfo>>(emptyList())
        private set
    var controllerInUse by mutableStateOf(false)
        private set

    fun start(with: Setup) {
        setup = with
        keyboard = KeyMapper(with.controls.saved.keyboard ?: with.controls.defaults.keyboard)
        keyShortcuts = buildMap {
            for (s in listOf(PadShortcut.QuickSave, PadShortcut.QuickLoad, PadShortcut.FastForward, PadShortcut.Rewind, PadShortcut.Slow, PadShortcut.Pause, PadShortcut.Advance)) {
                val name = with.settings.text("hotkeys.key.${s.setting}", "")
                if (name.isNotEmpty() && !keyboard.knows(name)) put(name, s)
            }
        }
        for (pad in pads.values) pad.mapper = mapperFor(pad.name, null)
        if (!started) {
            started = true
            inputManager.registerInputDeviceListener(this, main)
            for (id in InputDevice.getDeviceIds()) InputDevice.getDevice(id)?.let { if (isController(it)) attach(it.id, it, announce = false) }
            main.postDelayed(beat, HEARTBEAT_MS)
        }
        GameInputHub.handler = this
    }

    fun stop() {
        releaseAll()
        enabled = false
        if (GameInputHub.handler === this) GameInputHub.handler = null
        inputManager.unregisterInputDeviceListener(this)
        main.removeCallbacks(beat)
        main.removeCallbacks(turbo)
        for (pad in pads.values) stopRumble(pad)
        pads.clear()
        started = false
    }

    // While the menu is open nothing reaches the game, and everything held is let go.
    fun setEnabled(on: Boolean) {
        if (on == enabled) return
        enabled = on
        if (!on) {
            releaseAll()
        } else {
            for (pad in pads.values) {
                val raw = pad.mapper.state(pad.reading, pad.port, now(), applyTurbo = false)
                pad.masked = raw.buttons
            }
        }
    }

    // MARK: controllers

    private fun isController(device: InputDevice): Boolean {
        val s = device.sources
        return !device.isVirtual && (s and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD || s and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK)
    }

    private fun mapperFor(name: String, resolved: ResolvedPad?): PadMapper {
        val controls = setup?.controls ?: GameControls()
        return PadMapper(controls.defaults.gamepad, listOf(controls.saved.gamepad[name], resolved?.map), resolved?.options, controls.defaults.options)
    }

    private fun freePort(): Int {
        val taken = pads.values.map { it.port }.toSet()
        return (0..3).firstOrNull { it !in taken } ?: 3
    }

    private fun attach(deviceId: Int, device: InputDevice?, announce: Boolean): Pad {
        pads[deviceId]?.let { return it }
        val name = device?.name?.takeIf { it.isNotBlank() } ?: "Controller"
        val key = AndroidPad.profileKey(device?.vendorId ?: 0, device?.productId ?: 0, name)
        val consoleButtons = setup?.controls?.pad?.buttons?.map { it.id }?.toSet().orEmpty()
        val pad = Pad(deviceId, freePort(), name, key, mapperFor(name, null), PadShortcuts(setup?.settings, consoleButtons))
        pads[deviceId] = pad
        refreshPlayers()
        if (announce) onNotice("$name is player ${pad.port + 1}")
        scope.launch {
            val resolved = runCatching { loadProfile(key) }.getOrNull()
            if (pads[deviceId] === pad && resolved != null) {
                pad.mapper = mapperFor(name, resolved)
                pad.profile = resolved.profile?.name.orEmpty()
                refreshPlayers()
                updateTurbo()
            }
        }
        updateTurbo()
        return pad
    }

    private fun detach(deviceId: Int) {
        val pad = pads.remove(deviceId) ?: return
        stopRumble(pad)
        // Fast-forward or rewind held on it stops with it.
        for (s in pad.shortcuts.endAll()) onShortcut(s, false)
        emit(pad.port)
        refreshPlayers()
        onNotice("${pad.name} is disconnected")
        updateTurbo()
    }

    // Someone chose which player a controller is: whoever was there takes its old place.
    fun movePlayer(deviceId: Int, port: Int) {
        val pad = pads[deviceId] ?: return
        val other = pads.values.firstOrNull { it.port == port && it !== pad }
        val old = pad.port
        pad.port = port
        other?.port = old
        emit(old)
        emit(port)
        refreshPlayers()
    }

    private fun refreshPlayers() {
        players = pads.values.sortedBy { it.port }.map { GamePlayerInfo(it.deviceId, it.port, it.name, it.profile) }
        controllerInUse = pads.isNotEmpty() || keysUsed
    }

    override fun onInputDeviceAdded(deviceId: Int) {
        val device = InputDevice.getDevice(deviceId) ?: return
        if (isController(device)) attach(deviceId, device, announce = true)
    }

    override fun onInputDeviceRemoved(deviceId: Int) = detach(deviceId)

    override fun onInputDeviceChanged(deviceId: Int) {}

    // MARK: events

    private fun isPadEvent(event: KeyEvent): Boolean {
        if (event.source and InputDevice.SOURCE_GAMEPAD != InputDevice.SOURCE_GAMEPAD) return false
        if (pads.containsKey(event.deviceId)) return true
        val device = event.device
        // A remote that calls itself a gamepad has no face buttons and no sticks.
        return device == null || device.isVirtual || isController(device) || KeyEvent.isGamepadButton(event.keyCode)
    }

    private fun isKeyboard(event: KeyEvent): Boolean = event.device?.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC

    fun onKey(event: KeyEvent): Boolean {
        if (!enabled) return false
        val code = event.keyCode
        val down = event.action == KeyEvent.ACTION_DOWN
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) return false
        when (code) {
            // The system's and the app's own: volume, and Back, which opens the game menu.
            KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN, KeyEvent.KEYCODE_VOLUME_MUTE, KeyEvent.KEYCODE_POWER,
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_HOME, KeyEvent.KEYCODE_APP_SWITCH,
            -> return false
            KeyEvent.KEYCODE_BUTTON_MODE, KeyEvent.KEYCODE_MENU -> {
                if (down && event.repeatCount == 0) onMenu()
                return true
            }
        }
        if (isPadEvent(event)) {
            val pad = attach(event.deviceId, event.device, announce = false)
            if (event.repeatCount > 0) return true
            val value = if (down) 1.0 else 0.0
            when (code) {
                KeyEvent.KEYCODE_DPAD_UP -> pad.keyDpad[0] = down
                KeyEvent.KEYCODE_DPAD_DOWN -> pad.keyDpad[1] = down
                KeyEvent.KEYCODE_DPAD_LEFT -> pad.keyDpad[2] = down
                KeyEvent.KEYCODE_DPAD_RIGHT -> pad.keyDpad[3] = down
                KeyEvent.KEYCODE_BUTTON_L2 -> pad.digitalL2 = value
                KeyEvent.KEYCODE_BUTTON_R2 -> pad.digitalR2 = value
                else -> AndroidPad.standardButton(code)?.let { pad.reading.buttons[it] = value }
            }
            update(pad)
            return true
        }
        if (isKeyboard(event)) {
            if (code == KeyEvent.KEYCODE_ESCAPE) {
                if (down && event.repeatCount == 0) onMenu()
                return true
            }
            val name = keyboardCodeName(code) ?: return false
            keyShortcuts[name]?.let { shortcut ->
                if (event.repeatCount == 0) {
                    if (down) onShortcut(shortcut, true) else if (shortcut.isHeld) onShortcut(shortcut, false)
                }
                return true
            }
            if (!keyboard.knows(name)) return false
            if (event.repeatCount > 0) return true
            if (down) keysHeld += name else keysHeld -= name
            if (!keysUsed) {
                keysUsed = true
                refreshPlayers()
            }
            emit(0)
            return true
        }
        // A TV's remote is for the menus: OK opens the game menu as Back does, and its arrows stay off the game.
        if (isTv && remoteKeyName(code) != null) {
            if (code == KeyEvent.KEYCODE_DPAD_CENTER && down && event.repeatCount == 0) onMenu()
            return true
        }
        return false
    }

    fun onMotion(event: MotionEvent): Boolean {
        if (!enabled) return false
        if (event.source and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK || event.actionMasked != MotionEvent.ACTION_MOVE) return false
        val device = event.device
        val pad = attach(event.deviceId, device, announce = false)
        fun has(axis: Int) = device?.getMotionRange(axis, event.source) != null
        fun axis(a: Int) = event.getAxisValue(a).toDouble()
        val r = pad.reading
        r.axes[0] = axis(MotionEvent.AXIS_X)
        r.axes[1] = axis(MotionEvent.AXIS_Y)
        // Most pads put the right stick on Z and RZ; some on RX and RY, where others put their triggers.
        val rightOnZ = device == null || has(MotionEvent.AXIS_Z) || has(MotionEvent.AXIS_RZ)
        r.axes[2] = axis(if (rightOnZ) MotionEvent.AXIS_Z else MotionEvent.AXIS_RX)
        r.axes[3] = axis(if (rightOnZ) MotionEvent.AXIS_RZ else MotionEvent.AXIS_RY)
        pad.analogL2 = max(axis(MotionEvent.AXIS_LTRIGGER), axis(MotionEvent.AXIS_BRAKE)).coerceIn(0.0, 1.0)
        pad.analogR2 = max(axis(MotionEvent.AXIS_RTRIGGER), axis(MotionEvent.AXIS_GAS)).coerceIn(0.0, 1.0)
        val hatX = axis(MotionEvent.AXIS_HAT_X)
        val hatY = axis(MotionEvent.AXIS_HAT_Y)
        pad.hatDpad[0] = hatY < -0.5
        pad.hatDpad[1] = hatY > 0.5
        pad.hatDpad[2] = hatX < -0.5
        pad.hatDpad[3] = hatX > 0.5
        update(pad)
        return true
    }

    private fun now() = SystemClock.elapsedRealtime() / 1000.0

    private fun update(pad: Pad) {
        val r = pad.reading
        r.buttons[StandardPadReading.UP] = if (pad.keyDpad[0] || pad.hatDpad[0]) 1.0 else 0.0
        r.buttons[StandardPadReading.DOWN] = if (pad.keyDpad[1] || pad.hatDpad[1]) 1.0 else 0.0
        r.buttons[StandardPadReading.LEFT] = if (pad.keyDpad[2] || pad.hatDpad[2]) 1.0 else 0.0
        r.buttons[StandardPadReading.RIGHT] = if (pad.keyDpad[3] || pad.hatDpad[3]) 1.0 else 0.0
        r.buttons[StandardPadReading.L2] = max(pad.digitalL2, pad.analogL2)
        r.buttons[StandardPadReading.R2] = max(pad.digitalR2, pad.analogR2)
        if (!controllerInUse) refreshPlayers()
        if (!enabled) return
        val raw = pad.mapper.state(r, pad.port, now())
        pad.masked = pad.masked and raw.buttons
        val shown = pad.shortcuts.filter(raw.buttons and pad.masked.inv())
        for (s in shown.started) if (s == PadShortcut.Menu) onMenu() else onShortcut(s, true)
        for (s in shown.ended) onShortcut(s, false)
        pad.state = raw.copy(buttons = shown.buttons)
        emit(pad.port)
    }

    // What one player holds now: every pad on that port, and for the first, the keyboard and the touch controls.
    private fun stateOf(port: Int): PadState {
        var out = PadState(port)
        for (pad in pads.values) if (pad.port == port) out = out.merged(pad.state)
        if (port == 0) {
            if (keysHeld.isNotEmpty()) out = out.merged(keyboard.state(keysHeld, 0))
            if (touchMask != 0 || touchStick != (0 to 0)) out = out.merged(PadState(0, touchMask, touchStick.first, touchStick.second))
        }
        return out
    }

    private fun emit(port: Int) {
        if (!enabled) return
        val state = stateOf(port)
        if (sent[port] == state) return
        sent[port] = state
        send(state.encoded())
    }

    // The touch controls' fingers, as the first player.
    fun setTouch(mask: Int, stickX: Double, stickY: Double) {
        touchMask = mask
        touchStick = (stickX.coerceIn(-1.0, 1.0) * 32767).roundToInt() to (stickY.coerceIn(-1.0, 1.0) * 32767).roundToInt()
        if (!touchUsed && (mask != 0 || touchStick != (0 to 0))) touchUsed = true
        emit(0)
    }

    // A finger on a console's touch screen. Sent at once, again while held, and a release a few times over.
    fun setPointer(pressed: Boolean, fx: Double, fy: Double) {
        if (!enabled) return
        val message = TouchPad.pointerMessage(pressed, fx, fy)
        pointer = message
        pointerDown = pressed
        pointerReleases = if (pressed) 0 else 3
        send(message)
    }

    // The menu's Press Start and Press Select: held for about 200 ms, as a remote can't reach them.
    fun press(target: Int) {
        val state = stateOf(0).let { it.copy(buttons = it.buttons or RetroPad.bit(target)) }
        send(state.encoded())
        main.postDelayed({ send(stateOf(0).encoded()) }, 200)
    }

    private fun releaseAll() {
        for (pad in pads.values) {
            for (s in pad.shortcuts.endAll()) onShortcut(s, false)
            pad.state = PadState(pad.port)
        }
        keysHeld.clear()
        touchMask = 0
        touchStick = 0 to 0
        for (port in sent.keys.toList()) {
            val released = PadState(port)
            sent[port] = released
            send(released.encoded())
        }
        if (pointerDown) {
            pointerDown = false
            pointer?.let { send(TouchPad.pointerMessage(false, 0.5, 0.5)) }
        }
    }

    // Again every 250 ms, so a lost state corrects itself. Repeats don't count as playing.
    private val beat: Runnable = object : Runnable {
        override fun run() {
            if (enabled) {
                for ((port, state) in sent) send(state.encoded())
                val p = pointer
                if (p != null && (pointerDown || pointerReleases > 0)) {
                    send(p)
                    if (!pointerDown) pointerReleases--
                }
            }
            val now = SystemClock.elapsedRealtime()
            for (pad in pads.values) if ((pad.strong > 0 || pad.weak > 0) && now - pad.rumbledAt > RUMBLE_MS / 2) rumble(pad)
            main.postDelayed(this, HEARTBEAT_MS)
        }
    }

    // Buttons that repeat while held: a beat at twice the turbo rate.
    private val turbo: Runnable = object : Runnable {
        override fun run() {
            val with = pads.values.filter { it.mapper.hasTurbo }
            if (with.isEmpty()) return
            for (pad in with) update(pad)
            main.postDelayed(this, (500 / with.maxOf { it.mapper.turboHz }).toLong().coerceAtLeast(16))
        }
    }

    private fun updateTurbo() {
        main.removeCallbacks(turbo)
        if (pads.values.any { it.mapper.hasTurbo }) main.post(turbo)
    }

    // MARK: rumble

    // A game's rumble on that player's controller: effect 0 is the strong motor, 1 the weak one.
    fun rumble(port: Int, effect: Int, strength: Double) {
        for (pad in pads.values) if (pad.port == port) {
            if (effect == 1) pad.weak = strength else pad.strong = strength
            rumble(pad)
        }
    }

    private fun rumble(pad: Pad) {
        if (pad.mapper.noRumble) return
        val device = InputDevice.getDevice(pad.deviceId) ?: return
        pad.rumbledAt = SystemClock.elapsedRealtime()
        fun amplitude(v: Double) = (v * 255).roundToInt().coerceIn(0, 255)
        runCatching {
            if (Build.VERSION.SDK_INT >= 31) {
                val manager = device.vibratorManager
                val ids = manager.vibratorIds
                if (ids.isEmpty()) return
                if (pad.strong <= 0 && pad.weak <= 0) {
                    manager.cancel()
                    return
                }
                val both = CombinedVibration.startParallel()
                fun add(id: Int, v: Double) {
                    if (amplitude(v) > 0) both.addVibrator(id, VibrationEffect.createOneShot(RUMBLE_MS, amplitude(v)))
                }
                if (ids.size >= 2) {
                    add(ids[0], pad.strong)
                    add(ids[1], pad.weak)
                } else {
                    add(ids[0], max(pad.strong, pad.weak))
                }
                manager.vibrate(both.combine())
            } else {
                @Suppress("DEPRECATION")
                val vibrator = device.vibrator
                if (!vibrator.hasVibrator()) return
                val level = max(pad.strong, pad.weak)
                if (level <= 0) {
                    vibrator.cancel()
                } else if (Build.VERSION.SDK_INT >= 26) {
                    vibrator.vibrate(VibrationEffect.createOneShot(RUMBLE_MS, amplitude(level).coerceAtLeast(1)))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(RUMBLE_MS)
                }
            }
        }
    }

    private fun stopRumble(pad: Pad) {
        pad.strong = 0.0
        pad.weak = 0.0
        rumble(pad)
    }
}
