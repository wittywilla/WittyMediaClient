// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.games

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Surface
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.util.ArrayDeque

// How a running game reaches this device, whatever carries it. The player only sees this interface, so a new way of
// streaming is a new transport and nothing else. Version 2's (docs/GAMING-STREAM.md) messages are the same over WebRTC
// and a WebSocket.

interface GameTransport {
    // What the game sends. Media comes on the transport's own thread, as it arrives; the rest may come on any thread.
    interface Receiver {
        // Connected: input can go now.
        fun opened()
        fun media(message: StreamMessage)
        fun event(event: GameEvent)

        // Closed or failed. `status` is the HTTP status of a refused connection, or 0.
        fun lost(status: Int)

        // A transport that draws its own picture (WebRTC) says when the first one is on screen.
        fun shown() {}
    }

    // Where a transport that draws its own picture draws it. The WebSockets' pictures go through the player's decoders.
    fun attachSurface(surface: Surface?) {}

    // For a transport that plays its own sound.
    fun setVolume(level: Double, muted: Boolean) {}

    // A pad state, a touch, a timing request: binary, unordered, never resent.
    fun send(message: ByteArray)

    // An event for the server, as JSON. Version 1 has none and ignores it.
    fun sendEvent(event: JsonObject)

    // The decoder lost its place.
    fun requestKeyframe()
    fun close()
}

// One of the server's ways of sending a game, from a session's `modes` or GET /games/modes. `stream` is the version of
// /play/{sid}/stream it goes by: this app speaks GAME_STREAM, and a higher one means it needs updating.
const val GAME_STREAM = 2

data class GameModeInfo(val id: String, val stream: Int = 0) {
    companion object {
        fun from(element: JsonElement): GameModeInfo? = when (element) {
            is JsonObject -> element["id"]?.let { (it as? JsonPrimitive)?.content }?.let { id ->
                GameModeInfo(id, (element["stream"] as? JsonPrimitive)?.intOrNull ?: 1)
            }
            else -> null
        }
    }
}

// Everything this device says about itself to a version 2 server, the same over any transport.
data class StreamHello(
    val app: String,
    val device: String,
    val name: String,
    val watch: Boolean = true,
    // h264, or jpeg for a picture a frame. An empty list means no preference, which a server answers with H.264.
    val video: List<String> = listOf("h264"),
    // pcm until this app decodes Opus.
    val audio: List<String> = listOf("pcm"),
    val seats: List<Int> = listOf(0),
    val hz: Float = 60f,
    val width: Int = 0,
    val height: Int = 0,
    val latency: String = "auto",
    val maxKbps: Int = 0,
) {
    fun toJson(type: Boolean): JsonObject = buildJsonObject {
        if (type) put("type", "hello")
        put("v", 2)
        put("app", app.take(64))
        put("device", device.take(64))
        put("name", name.take(40))
        put("watch", watch)
        put("video", buildJsonArray { video.forEach { add(JsonPrimitive(it)) } })
        put("audio", buildJsonArray { audio.forEach { add(JsonPrimitive(it)) } })
        put("seats", buildJsonArray { seats.forEach { add(JsonPrimitive(it)) } })
        put("display", buildJsonObject {
            put("hz", hz)
            put("width", width)
            put("height", height)
        })
        put("latency", latency)
        put("maxKbps", maxKbps)
    }
}

// How much later than the quickest lately frames are arriving, from each version 2 frame's 90 kHz timestamp against
// when it came (the web player's ArrivalDelay). TCP's buffers hide a full link from the server; these reports show it.
class ArrivalDelay(private val windowMs: Long = 10_000) {
    // (when, arrival minus timestamp) for the window's lowest, kept as a rising queue.
    private val lows = ArrayDeque<Pair<Long, Double>>()
    private var worst = 0.0

    fun frame(arrivedMs: Long, timestamp90k: Long) {
        val offset = arrivedMs - timestamp90k / 90.0
        while (lows.isNotEmpty() && lows.peekLast()!!.second >= offset) lows.pollLast()
        lows.addLast(arrivedMs to offset)
        while (lows.isNotEmpty() && lows.peekFirst()!!.first < arrivedMs - windowMs) lows.pollFirst()
        val delay = offset - (lows.peekFirst()?.second ?: offset)
        if (delay > worst) worst = delay
    }

    // The worst of the half second since this was last asked, and a fresh start for the next.
    fun takeWorst(): Int {
        val out = worst
        worst = 0.0
        return Math.round(out).toInt()
    }
}

private const val REPORT_MS = 500L

// A version 2 stream's first message must be the hello, as text (docs/GAMING-STREAM.md). Until it has gone, binary
// messages are dropped (pad states are sent again every 250 ms, and the stream starts with a keyframe anyway) and
// events wait, a few at most, to follow it in order. From any thread.
class HelloFirst(private val writeText: (String) -> Unit, private val writeBinary: (ByteArray) -> Unit) {
    private val lock = Any()
    private var greeted = false
    private val waiting = ArrayList<String>()

    fun open(hello: String, after: ByteArray? = null) = synchronized(lock) {
        if (greeted) return
        writeText(hello)
        after?.let(writeBinary)
        waiting.forEach(writeText)
        waiting.clear()
        greeted = true
    }

    fun binary(message: ByteArray) {
        synchronized(lock) { if (!greeted) return }
        writeBinary(message)
    }

    fun text(event: String) {
        synchronized(lock) {
            if (!greeted) {
                if (waiting.size < MOST_WAITING_EVENTS) waiting += event
                return
            }
        }
        writeText(event)
    }

    private companion object {
        const val MOST_WAITING_EVENTS = 16
    }
}

// Version 2 over a WebSocket: GET /play/{sid}/stream. The hello goes first, as text; the server answers with the
// stream's description, then the picture from a keyframe. Its delayMs reports go twice a second.
class WebSocketV2Transport(api: GamesApi, endpoint: StreamEndpoint, hello: StreamHello, private val receiver: GameTransport.Receiver) : GameTransport {
    private val main = Handler(Looper.getMainLooper())
    private val delay = ArrivalDelay()

    @Volatile
    private var closed = false

    // OkHttp sends what was asked for before the socket opened as soon as it opens, ahead of the hello that goes in
    // onOpen. The player sends pad states every 250 ms and asks for keyframes whenever it likes, so on a connection
    // that takes a while to open (from away, peer to peer) one of those went first, and the server refused the
    // connection: "the first message must be the hello, as text". Nothing goes out before the hello now.
    private val gate = HelloFirst(
        writeText = { opened?.send(it) },
        writeBinary = { opened?.send(ByteString.of(*it)) },
    )

    // The socket as onOpen hands it over, which can be before the constructor has finished.
    @Volatile
    private var opened: WebSocket? = null

    private val socket: WebSocket = api.openWebSocketUrl(endpoint.url, Listener(hello))

    private val report: Runnable = object : Runnable {
        override fun run() {
            if (closed) return
            val worst = synchronized(delay) { delay.takeWorst() }
            sendEvent(buildJsonObject {
                put("type", "report")
                put("delayMs", worst)
            })
            main.postDelayed(this, REPORT_MS)
        }
    }

    override fun send(message: ByteArray) = gate.binary(message)

    override fun sendEvent(event: JsonObject) = gate.text(event.toString())

    override fun requestKeyframe() = send(TimingRequests.keyframe)

    override fun close() {
        closed = true
        main.removeCallbacks(report)
        socket.close(1000, null)
    }

    private inner class Listener(private val hello: StreamHello) : WebSocketListener() {
        private var described = false

        override fun onOpen(webSocket: WebSocket, response: Response) {
            opened = webSocket
            gate.open(hello.toJson(type = true).toString(), TimingRequests.decodingOurselves)
            main.postDelayed(report, REPORT_MS)
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            val message = StreamMessage.parse(bytes.toByteArray()) ?: return
            if (message is StreamMessage.Video && message.timestamp90k >= 0) {
                synchronized(delay) { delay.frame(SystemClock.elapsedRealtime(), message.timestamp90k) }
            }
            receiver.media(message)
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            val event = GameEvent.parse(text) ?: return
            // The stream's description is the answer to the hello: input can go from here.
            if (event is GameEvent.Stream && !described) {
                described = true
                receiver.opened()
            }
            receiver.event(event)
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            closed = true
            receiver.lost(response?.code ?: 0)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            closed = true
            receiver.lost(0)
        }
    }
}

// Which transport a mode goes by. `video` is webrtc (which draws and plays for itself), h264 or jpeg (over a WebSocket).
data class GameRoute(val stream: Int, val video: String) {
    val modeId: String get() = when (video) {
        "webrtc" -> "webrtc"
        "jpeg" -> "ws-jpeg"
        else -> "ws-h264"
    }

    companion object {
        // The ways to try, best first: the server's order, of the modes this app can use on its stream version (WebRTC
        // first). A chosen mode (the menu's Connection) is the only one tried where offered.
        fun plan(offered: List<GameModeInfo>, chosen: String = "auto"): List<GameRoute> {
            val usable = offered.filter { it.stream == GAME_STREAM }.map { it.id }.filter { it in GameModes.supported }.distinct()
            val tried = if (chosen in usable) listOf(chosen) else usable
            return tried.map { GameRoute(GAME_STREAM, if (it == "webrtc") "webrtc" else GameModes.video(it)) }
        }

        // The server streams only in a newer version than this app speaks: it needs updating, nothing else will do.
        fun needsUpdate(offered: List<GameModeInfo>) = offered.none { it.stream == GAME_STREAM } && offered.any { it.stream > GAME_STREAM }
    }
}

// The JSON a stream's seat list is, for both reading it and the seats a device asks for.
fun seatsRequest(ports: List<Int>, take: Boolean = false): JsonObject = buildJsonObject {
    put("type", "seats")
    put("ports", JsonArray(ports.map { JsonPrimitive(it) }))
    if (take) put("take", true)
}
