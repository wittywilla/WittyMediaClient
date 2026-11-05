package com.wittywilla.wittymediaclient.games

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.core.content.edit
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.io.IOException
import java.util.UUID

// One game being played: started on the server, its stream shown here, its controls sent back, and saved and
// stopped at the end (the server's docs/GAMING-API.md, "Playing a game" and "What a TV app must build itself").

// How a game starts: from the beginning, from the automatic save, from a slot (as the website's ?slot=), or with
// the defaults only (no cheats, no patches).
data class GameStart(val resume: Boolean, val slot: Int? = null, val safeMode: Boolean = false)

// The steps on the way to the first picture, as the website's loading screen names them.
enum class GameStage(val words: String) {
    Prepare("Getting the game ready"),
    Start("Starting the console"),
    Connect("Connecting to this device"),
    Picture("Waiting for the first picture"),
    Playing(""),
}

data class GameProblem(val title: String, val body: String, val retry: Boolean = true, val defaults: Boolean = false)

// The pages of the game menu.
enum class GameMenu { Main, Save, Load, Controllers, More, Discs, Connection }

private const val RECONNECT_WINDOW_MS = 55_000L
private const val TOAST_MS = 3_000L

class GamePlay(private val app: WittyApp, val gameId: Long, private var start: GameStart, val isTv: Boolean, private val scope: CoroutineScope) {
    val api = GamesApi(app.api)
    private val main = Handler(Looper.getMainLooper())
    val input = GameInput(app, scope, isTv)
    private var sound = GameSound(soundLatencySeconds("lowest"))

    // The picture: H.264 decoded on its own thread, or a JPEG a frame. Each says when a picture reaches the screen.
    @Volatile
    private var gotPicture = false
    private val video = H264Player(onPicture = ::pictureArrived, needKeyframe = { socket?.send(ByteString.of(*TimingRequests.keyframe)) })
    private val jpeg = JpegPlayer(onPicture = ::pictureArrived)

    var stage by mutableStateOf(GameStage.Prepare)
        private set
    var unpacked by mutableStateOf<Float?>(null)
        private set
    var problem by mutableStateOf<GameProblem?>(null)
        private set
    var item by mutableStateOf<GameItem?>(null)
        private set
    var session by mutableStateOf<GameSession?>(null)
        private set
    var settings by mutableStateOf(GameSettings.NONE)
        private set
    var controls by mutableStateOf<GameControls?>(null)
        private set
    var consoleName by mutableStateOf("")
        private set

    // The picture's shape and turn, as the game says and changes them.
    var aspect by mutableDoubleStateOf(4.0 / 3.0)
        private set
    var frameSize by mutableStateOf(256 to 240)
        private set
    var turns by mutableIntStateOf(0)
        private set

    // "h264" or "jpeg": which surface the picture goes to.
    var videoKind by mutableStateOf("h264")
        private set

    var menu by mutableStateOf<GameMenu?>(null)
        private set
    var toast by mutableStateOf("")
        private set
    var saving by mutableStateOf(false)
        private set

    // The player should go: saved and stopped, or the game ended itself.
    var finished by mutableStateOf(false)
        private set
    var paused by mutableStateOf(false)
        private set
    var fastForward by mutableStateOf(false)
        private set
    var slowMotion by mutableStateOf(false)
        private set
    var saves by mutableStateOf<List<GameSave>>(emptyList())
        private set
    var disc by mutableIntStateOf(0)
        private set
    var discs by mutableIntStateOf(0)
        private set

    private var modes: List<String> = GameModes.supported
    private var modeIndex = 0
    private var offeredModes: List<String> = emptyList()

    // How the game reaches this device: "auto", or a mode this device chose for itself (the website's Connection).
    var chosenMode by mutableStateOf(chosenModeFor(app))
        private set
    var modeInUse by mutableStateOf("")
        private set
    private var socket: WebSocket? = null
    private var socketSerial = 0
    private var pictureTimer: Job? = null
    private var lostAt = 0L
    private var away = false
    private var pausedForAway = false
    private var stopped = false
    private var toastSerial = 0
    private var began = false
    private var starting: Job? = null

    val deviceId: String by lazy { deviceIdFor(app) }

    // MARK: starting

    fun begin() {
        if (began) return
        began = true
        input.send = { bytes -> socket?.send(ByteString.of(*bytes)) }
        input.onMenu = { openMenu() }
        input.onNotice = ::say
        input.onShortcut = ::shortcut
        input.loadProfile = { key -> controls?.console?.let { console -> api.resolvePad(key, console, gameId) } }
        starting = scope.launch { startGame() }
    }

    private suspend fun startGame() {
        problem = null
        stage = GameStage.Prepare
        unpacked = null
        gotPicture = false
        try {
            val game = api.item(gameId)
            item = game
            val console = game.console
            // What the controls and the picture need, read while the game gets ready. Either failing still plays.
            val settingsCall = scope.async { runCatching { api.settings(gameId) }.getOrDefault(GameSettings.NONE) }
            val controlsCall = scope.async { runCatching { api.controls(console, deviceId, gameId) }.getOrNull() }
            val consolesCall = scope.async { runCatching { api.consoles() }.getOrDefault(emptyList()) }
            // A game in an archive is unpacked first: ask about once a second, showing how far it's got.
            while (true) {
                val ready = api.prepare(gameId)
                if (ready.ready) break
                unpacked = ready.fraction
                delay(1_000)
            }
            unpacked = null
            stage = GameStage.Start
            settings = settingsCall.await()
            controls = controlsCall.await()
            consoleName = consolesCall.await().firstOrNull { it.id == console }?.name ?: console.uppercase()
            sound.close()
            sound = GameSound(soundLatencySeconds(settings.text("audio.latency", "lowest")))
            sound.setVolume(settings.number("audio.volume", 1.0), settings.flag("audio.mute", false))
            jpeg.smooth = settings.text("display.scaling", "sharp") == "smooth"
            val started = api.play(gameId, start.resume, start.safeMode)
            session = started
            if (started.aspect > 0) aspect = started.aspect
            if (started.width > 0 && started.height > 0) frameSize = started.width to started.height
            turns = started.turns
            disc = started.disc
            discs = started.discs
            for (notice in started.notices) say(notice)
            offeredModes = started.modeIds
            modes = GameModes.order(offeredModes, chosenMode)
            modeIndex = 0
            input.start(GameInput.Setup(controls ?: GameControls(console = console), settings, console, gameId))
            input.setEnabled(menu == null && !away)
            connect()
        } catch (e: CancellationException) {
            throw e
        } catch (e: ApiError) {
            if (e.status == 401) {
                problem = GameProblem("Signed out", "Sign in again to play.", retry = false)
                return
            }
            problem = GameProblem(
                if (e.status == 409 || e.status == 422) "This game can't start" else "The game didn't start",
                e.message.orEmpty(), retry = e.status != 422 && e.status != 404, defaults = e.status >= 500,
            )
        } catch (e: IOException) {
            problem = GameProblem("The server can't be reached", "Check this device's connection, then try again.")
        } catch (e: Exception) {
            ClientLog.warn("games", "Starting a game failed: ${e.javaClass.simpleName}")
            problem = GameProblem("The game didn't start", "Something went wrong on the way. Try again.")
        }
    }

    // Start again after a problem: from the automatic save if there's one, or as asked.
    fun retry(safeMode: Boolean = false) {
        closeSocket()
        stopped = false
        lostAt = 0
        if (session != null) start = GameStart(resume = true, safeMode = safeMode)
        else if (safeMode) start = start.copy(safeMode = true)
        session = null
        starting = scope.launch { startGame() }
    }

    // MARK: the connection

    private fun connect() {
        val sid = session?.id ?: return
        if (stopped) return
        closeSocket()
        val mode = modes.getOrElse(modeIndex) { modes.last() }
        modeInUse = mode
        val kind = GameModes.video(mode)
        videoKind = kind
        if (!gotPicture) stage = GameStage.Connect
        val serial = ++socketSerial
        socket = api.openSocket(sid, kind, Listener(serial))
        pictureTimer?.cancel()
        pictureTimer = scope.launch {
            delay(GameModes.FIRST_PICTURE_MS)
            if (serial == socketSerial && !gotPicture && !stopped) nextMode()
        }
    }

    // No picture in time: the next way of sending it, or a problem to show.
    private fun nextMode() {
        if (modeIndex + 1 < modes.size) {
            modeIndex++
            ClientLog.warn("games", "No picture over ${modes[modeIndex - 1]}; trying ${modes[modeIndex]}")
            connect()
        } else {
            closeSocket()
            problem = GameProblem("No picture came", "The game started on the server, but its picture didn't reach this device. Try again.")
        }
    }

    private fun closeSocket() {
        socketSerial++
        pictureTimer?.cancel()
        socket?.close(1000, null)
        socket = null
    }

    private inner class Listener(private val serial: Int) : WebSocketListener() {
        private fun current() = serial == socketSerial

        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (!current()) return
            webSocket.send(ByteString.of(*TimingRequests.decodingOurselves))
            main.post {
                if (current() && !gotPicture) stage = GameStage.Picture
                if (current()) input.setEnabled(menu == null && !away)
            }
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            if (!current()) return
            when (val m = StreamMessage.parse(bytes.toByteArray())) {
                is StreamMessage.Video -> video.submit(m)
                is StreamMessage.Jpeg -> jpeg.submit(m)
                is StreamMessage.Pcm -> sound.play(m)
                else -> {}
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            val event = GameEvent.parse(text) ?: return
            main.post { if (current()) handle(event) }
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            main.post { if (current()) lost(response?.code ?: 0) }
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            main.post { if (current()) lost(0) }
        }
    }

    private fun handle(event: GameEvent) {
        when (event) {
            is GameEvent.Hello -> if (event.video.isNotEmpty()) videoKind = event.video
            is GameEvent.Rumble -> input.rumble(event.port, event.effect, event.strength)
            is GameEvent.Message -> say(event.text)
            is GameEvent.Geometry -> {
                event.aspect?.takeIf { it > 0 }?.let { aspect = it }
                if (event.width > 0 && event.height > 0) frameSize = event.width to event.height
            }
            is GameEvent.Rotation -> turns = event.turns
            is GameEvent.AvInfo -> event.aspect?.takeIf { it > 0 }?.let { aspect = it }
            is GameEvent.Frame -> if (event.width > 0 && event.height > 0) frameSize = event.width to event.height
            is GameEvent.Disc -> {
                disc = event.index
                discs = event.count
            }
            GameEvent.Shutdown -> {
                stopped = true
                closeSocket()
                finished = true
            }
            is GameEvent.Ended -> {
                stopped = true
                closeSocket()
                input.setEnabled(false)
                problem = GameProblem("The game stopped", event.text.ifEmpty { "It stopped on the server." })
            }
            else -> {}
        }
    }

    // The connection dropped. Within the server's minute the game is still there: connect again.
    private fun lost(status: Int) {
        if (stopped || away) return
        socket = null
        if (!gotPicture) {
            if (status == 404) {
                problem = GameProblem("The game stopped", "It isn't running on the server any more.")
                return
            }
            nextMode()
            return
        }
        val now = System.currentTimeMillis()
        if (lostAt == 0L) lostAt = now
        if (now - lostAt > RECONNECT_WINDOW_MS) {
            problem = GameProblem("The connection was lost", "The server saved the game. Resume to carry on.")
            return
        }
        say("Reconnecting…")
        scope.launch {
            delay(1_000)
            if (stopped || away || socket != null) return@launch
            val stillThere = try {
                api.session(session?.id ?: return@launch)
                true
            } catch (e: ApiError) {
                e.status != 404
            } catch (_: IOException) {
                true
            }
            if (!stillThere) {
                problem = GameProblem("The game stopped", "The server saved it and stopped it. Resume to carry on.")
                return@launch
            }
            connect()
        }
    }

    private fun pictureArrived() {
        if (gotPicture) return
        gotPicture = true
        main.post {
            stage = GameStage.Playing
            lostAt = 0
            pictureTimer?.cancel()
            // Started from a slot, as the website's ?slot=: load it once the game is up.
            start.slot?.let { slot ->
                start = start.copy(slot = null)
                act(GameAction("load", slot = slot), "Loaded ${GameWords.slotName(slot).lowercase()}")
            }
        }
    }

    // A new picture has come since this was last asked: for the connection's own keeping track.
    fun surfaceFor(kind: String, surface: Surface?) {
        if (kind == "jpeg") jpeg.setSurface(surface) else video.setSurface(surface)
    }

    // MARK: the app coming and going

    // Away from the app: let go of everything, pause the game if the person's settings say so, and close the
    // connection. The server keeps the game for a minute with nobody connected, then saves and stops it.
    fun disappeared() {
        if (away) return
        away = true
        input.setEnabled(false)
        sound.hold(true)
        val sid = session?.id
        if (sid != null && !stopped && gotPicture && settings.flag("emulation.pauseHidden", true) && !paused) {
            pausedForAway = true
            scope.launch { runCatching { api.action(sid, GameAction("pause", on = true)) } }
        }
        closeSocket()
    }

    fun appeared() {
        if (!away) return
        away = false
        sound.hold(false)
        val sid = session?.id ?: return
        if (stopped || problem != null) return
        scope.launch {
            val stillThere = try {
                api.session(sid)
                true
            } catch (e: ApiError) {
                e.status != 404
            } catch (_: IOException) {
                true
            }
            if (!stillThere) {
                problem = GameProblem("The game was saved", "It stopped on the server while you were away. Resume to carry on from there.")
                return@launch
            }
            if (pausedForAway) {
                pausedForAway = false
                runCatching { api.action(sid, GameAction("pause", on = false)) }
            }
            lostAt = 0
            connect()
        }
    }

    // MARK: the menu

    fun openMenu(page: GameMenu = GameMenu.Main) {
        if (problem != null || saving) return
        menu = page
        input.setEnabled(false)
        if (page == GameMenu.Save || page == GameMenu.Load) loadSaves()
    }

    fun closeMenu() {
        menu = null
        if (!away) input.setEnabled(true)
    }

    // Back in the menu goes up a page, and from its first page back to the game.
    fun menuBack() {
        when (menu) {
            null -> openMenu()
            GameMenu.Main -> closeMenu()
            GameMenu.Discs, GameMenu.Connection -> menu = GameMenu.More
            else -> menu = GameMenu.Main
        }
    }

    fun showMenu(page: GameMenu) {
        menu = page
        if (page == GameMenu.Save || page == GameMenu.Load) loadSaves()
    }

    private fun loadSaves() {
        scope.launch { runCatching { api.saves(gameId) }.onSuccess { saves = it } }
    }

    val quickSlot: Int get() = settings.number("states.quickSlot", 1.0).toInt().coerceIn(1, 99)
    val confirms: Boolean get() = settings.flag("states.confirm", true)

    fun say(words: String) {
        if (words.isBlank()) return
        toast = words
        val mine = ++toastSerial
        main.postDelayed({ if (toastSerial == mine) toast = "" }, TOAST_MS)
    }

    private fun act(action: GameAction, done: String = "", after: () -> Unit = {}) {
        val sid = session?.id ?: return
        scope.launch {
            try {
                api.action(sid, action)
                say(done)
                after()
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                say(e.message.orEmpty())
            } catch (_: Exception) {
                say("That didn't work. Try again.")
            }
        }
    }

    fun save(slot: Int) {
        closeMenu()
        act(GameAction("save", slot = slot), "Saved to ${GameWords.slotName(slot).lowercase()}")
    }

    fun load(slot: Int) {
        closeMenu()
        act(GameAction("load", slot = slot), "Loaded ${GameWords.slotName(slot).lowercase()}")
    }

    fun reset() {
        closeMenu()
        act(GameAction("reset"), "Reset")
    }

    fun undoLoad() {
        closeMenu()
        act(GameAction("undo"), "Undone")
    }

    fun changeDisc(n: Int) {
        closeMenu()
        act(GameAction("disc", slot = n), "Disc ${n + 1}")
    }

    fun pause(on: Boolean) {
        closeMenu()
        act(GameAction("pause", on = on)) { paused = on }
    }

    // A connection mode of this device's own choosing, kept for next time, and used straight away.
    fun useMode(mode: String) {
        chosenMode = mode
        app.getSharedPreferences("wittyplay", Context.MODE_PRIVATE).edit { putString("mode", mode) }
        closeMenu()
        if (session == null || stopped) return
        modes = GameModes.order(offeredModes, mode)
        modeIndex = 0
        connect()
    }

    fun setDevice(port: Int, device: Int) {
        val sid = session?.id ?: return
        scope.launch {
            try {
                api.action(sid, GameAction("device", port = port, device = device))
                session = session?.let { s -> s.copy(devices = s.devices.map { if (it.port == port) it.copy(current = device) else it }) }
            } catch (e: ApiError) {
                say(e.message.orEmpty())
            } catch (_: IOException) {
                say("That didn't work. Try again.")
            }
        }
    }

    // Press Start and Press Select, for what a remote or the screen can't reach.
    fun press(target: Int) {
        closeMenu()
        main.postDelayed({ input.press(target) }, 150)
    }

    fun toggleFastForward() {
        closeMenu()
        speed(if (fastForward) 1.0 else settings.number("emulation.ffSpeed", 2.0)) { fastForward = !fastForward; slowMotion = false }
    }

    fun toggleSlowMotion() {
        closeMenu()
        speed(if (slowMotion) 1.0 else settings.number("emulation.slowSpeed", 0.5)) { slowMotion = !slowMotion; fastForward = false }
    }

    private fun speed(value: Double, after: () -> Unit) = act(GameAction("speed", value = value), after = after)

    // A shortcut held with the shortcut button, or a keyboard's.
    private fun shortcut(s: PadShortcut, on: Boolean) {
        val sid = session?.id ?: return
        when (s) {
            PadShortcut.Menu -> if (on) openMenu()
            PadShortcut.QuickSave -> if (on) act(GameAction("save", slot = quickSlot), "Saved to slot $quickSlot")
            PadShortcut.QuickLoad -> if (on) act(GameAction("load", slot = quickSlot), "Loaded slot $quickSlot")
            PadShortcut.FastForward -> {
                fastForward = on
                act(GameAction("speed", value = if (on) settings.number("emulation.ffSpeed", 2.0) else 1.0))
            }
            PadShortcut.Slow -> {
                slowMotion = on
                act(GameAction("speed", value = if (on) settings.number("emulation.slowSpeed", 0.5) else 1.0))
            }
            PadShortcut.Rewind -> scope.launch {
                try {
                    api.action(sid, GameAction("rewind", on = on))
                } catch (e: ApiError) {
                    if (on) say(e.message.orEmpty())
                } catch (_: IOException) {
                }
            }
            PadShortcut.Pause -> if (on) act(GameAction("pause", on = !paused)) { paused = !paused }
            PadShortcut.Advance -> if (on) act(GameAction("advance", value = 1.0))
            PadShortcut.Screenshot -> {}
        }
    }

    // MARK: stopping

    // Save and quit: the answer comes once everything is written, so the next device carries on from here.
    fun quit() {
        if (saving) return
        val sid = session?.id
        menu = null
        saving = true
        stopped = true
        starting?.cancel()
        input.stop()
        closeSocket()
        sound.hold(true)
        scope.launch {
            if (sid != null) {
                try {
                    api.stop(sid)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: ApiError) {
                    if (e.status != 404) say(e.message.orEmpty())
                } catch (_: Exception) {
                }
            }
            saving = false
            finished = true
        }
    }

    // Leaving the screen for good, any way at all: nothing is left running, and the server still saves.
    fun close() {
        starting?.cancel()
        input.stop()
        closeSocket()
        video.close()
        jpeg.close()
        sound.close()
        val sid = session?.id
        if (!stopped && sid != null) {
            stopped = true
            val api = api
            app.scope.launch { runCatching { api.stop(sid) } }
        }
    }

    companion object {
        // This device's own name for touch layouts, which belong to the device that saved them.
        fun deviceIdFor(context: Context): String {
            val prefs = context.getSharedPreferences("wittyplay", Context.MODE_PRIVATE)
            prefs.getString("device", null)?.let { return it }
            val made = "android-" + UUID.randomUUID().toString().replace("-", "").take(16)
            prefs.edit { putString("device", made) }
            return made
        }

        fun chosenModeFor(context: Context): String =
            context.getSharedPreferences("wittyplay", Context.MODE_PRIVATE).getString("mode", "auto") ?: "auto"

        // Whether the touch controls show on this device, its own choice.
        fun touchShown(context: Context): Boolean = context.getSharedPreferences("wittyplay", Context.MODE_PRIVATE).getBoolean("touch", true)

        fun setTouchShown(context: Context, on: Boolean) {
            context.getSharedPreferences("wittyplay", Context.MODE_PRIVATE).edit { putBoolean("touch", on) }
        }
    }
}
