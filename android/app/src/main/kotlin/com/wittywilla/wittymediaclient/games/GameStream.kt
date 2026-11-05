package com.wittywilla.wittymediaclient.games

import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.JsonObject
import kotlin.math.floor
import kotlin.math.min

// What arrives on a game's WebSocket (the server's docs/GAMING-API.md, "WebSocket"): binary messages whose first
// byte says what they are, and JSON events as text. This app has no WebRTC stack, so this is how it plays: H.264
// into MediaCodec, or a JPEG a frame where the server has no encoder, and plain PCM sound.

sealed interface StreamMessage {
    // One frame in Annex B, with its parameter sets before each keyframe: `data` from `offset` to its end.
    class Video(val keyframe: Boolean, val data: ByteArray, val offset: Int) : StreamMessage {
        val size: Int get() = data.size - offset
    }

    class Jpeg(val data: ByteArray, val offset: Int) : StreamMessage

    // Signed 16-bit little-endian stereo, at any rate a console uses, such as 32040: whole frames only.
    class Pcm(val rate: Int, val data: ByteArray, val offset: Int, val length: Int) : StreamMessage

    data object Timing : StreamMessage

    class Unknown(val kind: Int) : StreamMessage

    companion object {
        fun parse(data: ByteArray): StreamMessage? {
            if (data.isEmpty()) return null
            return when (val kind = data[0].toInt() and 0xff) {
                1 -> if (data.size < 2) null else Video(data[1].toInt() == 1, data, 2)
                2 -> Jpeg(data, 1)
                3 -> {
                    if (data.size < 5) return null
                    val rate = (data[1].toInt() and 0xff) or ((data[2].toInt() and 0xff) shl 8) or
                        ((data[3].toInt() and 0xff) shl 16) or ((data[4].toInt() and 0xff) shl 24)
                    val length = data.size - 5
                    // A stray byte would swap left and right from then on.
                    Pcm(rate, data, 5, length - length % 4)
                }
                0xF2, 0xF4 -> Timing
                else -> Unknown(kind)
            }
        }
    }
}

// A message from the game, as JSON text. Types this app doesn't know are ignored.
sealed interface GameEvent {
    data class Hello(val video: String) : GameEvent

    // Strength from 0 to 1.
    data class Rumble(val port: Int, val effect: Int, val strength: Double) : GameEvent
    data class Message(val text: String) : GameEvent
    data class Geometry(val width: Int, val height: Int, val aspect: Double?) : GameEvent
    data class Rotation(val turns: Int) : GameEvent
    data class AvInfo(val aspect: Double?, val fps: Double?, val rate: Double?) : GameEvent

    // The game ended itself: leave the player.
    data object Shutdown : GameEvent

    // The game stopped: it crashed, stopped responding, or was stopped from elsewhere.
    data class Ended(val text: String) : GameEvent
    data class Disc(val index: Int, val count: Int) : GameEvent

    // What the core really draws changed.
    data class Frame(val width: Int, val height: Int) : GameEvent
    data class Unknown(val type: String) : GameEvent

    companion object {
        fun parse(text: String): GameEvent? {
            val o = runCatching { json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return null
            fun int(key: String) = o.number(key)?.toInt() ?: 0
            return when (val type = o.text("type")) {
                "" -> null
                "hello" -> Hello(o.text("video"))
                "rumble" -> Rumble(int("port"), int("effect"), ((o.number("strength") ?: 0.0) / 65535).coerceIn(0.0, 1.0))
                "message" -> Message(o.text("text"))
                "geometry" -> Geometry(int("width"), int("height"), o.number("aspect"))
                "rotation" -> Rotation(int("turns"))
                "avinfo" -> AvInfo(o.number("aspect"), o.number("fps"), o.number("rate"))
                "shutdown" -> Shutdown
                "ended" -> Ended(o.text("text"))
                "disc" -> Disc(int("index"), int("count"))
                "frame" -> Frame(int("width"), int("height"))
                else -> Unknown(type)
            }
        }
    }
}

// Which of the server's ways of sending a game this app tries, in order: the WebSocket with H.264, then with a
// JPEG a frame. WebRTC needs a stack this app doesn't carry; ids this app doesn't know are skipped.
object GameModes {
    val supported = listOf("ws-h264", "ws-jpeg")

    // `chosen` is "auto", or the one mode this device was told to use, where the server offers it.
    fun order(offered: List<String>, chosen: String = "auto"): List<String> {
        val ids = offered.filter { it in supported }.distinct().ifEmpty { supported }
        return if (chosen in ids) listOf(chosen) else ids
    }

    // The website's names for them.
    val names = mapOf("auto" to "Automatic (recommended)", "ws-h264" to "WebSocket with H.264", "ws-jpeg" to "WebSocket with JPEG (most compatible)")

    fun video(mode: String): String = if (mode == "ws-jpeg") "jpeg" else "h264"

    // Move on to the next mode when no picture has come in this long.
    const val FIRST_PICTURE_MS = 12_000L
}

// Asking the server for things on the WebSocket's timing channel: here only "send a keyframe", for a decoder
// that lost its place.
object TimingRequests {
    val keyframe = byteArrayOf(0xF7.toByte())

    // Frames are decoded here, so a browser's own keyframe requests mean nothing.
    val decodingOurselves = byteArrayOf(0xF8.toByte())
}

// H.264 in Annex B: finding the units, and the picture's size from its sequence parameter set.
object AnnexB {
    const val SPS = 7
    const val PPS = 8
    const val IDR = 5

    // Where each unit starts (just after its start code) and ends, in data[from until data.size].
    fun units(data: ByteArray, from: Int = 0): List<IntRange> {
        val starts = ArrayList<Pair<Int, Int>>() // position of the start code, its length
        var i = from
        while (i + 2 < data.size) {
            if (data[i].toInt() == 0 && data[i + 1].toInt() == 0) {
                if (data[i + 2].toInt() == 1) {
                    starts += i to 3
                    i += 3
                    continue
                }
                if (i + 3 < data.size && data[i + 2].toInt() == 0 && data[i + 3].toInt() == 1) {
                    starts += i to 4
                    i += 4
                    continue
                }
            }
            i++
        }
        val out = ArrayList<IntRange>(starts.size)
        for ((n, start) in starts.withIndex()) {
            val begin = start.first + start.second
            var end = if (n + 1 < starts.size) starts[n + 1].first else data.size
            // Trailing zeros belong to the next start code, not to this unit.
            while (end > begin && n + 1 < starts.size && data[end - 1].toInt() == 0) end--
            if (end > begin) out += begin until end
        }
        return out
    }

    fun type(data: ByteArray, unit: IntRange): Int = data[unit.first].toInt() and 0x1f

    // The unit's bytes with its start code, for MediaCodec's csd buffers.
    fun withStartCode(data: ByteArray, unit: IntRange): ByteArray =
        byteArrayOf(0, 0, 0, 1) + data.copyOfRange(unit.first, unit.last + 1)

    // A sequence parameter set's picture size, after cropping, or null if it can't be read.
    fun spsSize(sps: ByteArray): Pair<Int, Int>? = runCatching { SpsReader(unescape(sps)).size() }.getOrNull()

    // Without the bytes added to stop a start code appearing inside a unit (00 00 03).
    private fun unescape(unit: ByteArray): ByteArray {
        val out = java.io.ByteArrayOutputStream(unit.size)
        var zeros = 0
        for (b in unit) {
            val v = b.toInt() and 0xff
            if (zeros >= 2 && v == 3) {
                zeros = 0
                continue
            }
            out.write(v)
            zeros = if (v == 0) zeros + 1 else 0
        }
        return out.toByteArray()
    }

    private class SpsReader(private val b: ByteArray) {
        private var bit = 8 // past the unit's header byte

        fun u(n: Int): Int {
            var v = 0
            repeat(n) {
                val byte = b[bit / 8].toInt() and 0xff
                v = (v shl 1) or ((byte shr (7 - bit % 8)) and 1)
                bit++
            }
            return v
        }

        fun ue(): Int {
            var zeros = 0
            while (u(1) == 0) zeros++
            return (1 shl zeros) - 1 + if (zeros > 0) u(zeros) else 0
        }

        fun se(): Int {
            val k = ue()
            return if (k % 2 == 1) (k + 1) / 2 else -(k / 2)
        }

        private fun skipScalingList(size: Int) {
            var last = 8
            var next = 8
            for (j in 0 until size) {
                if (next != 0) next = (last + se() + 256) % 256
                if (next != 0) last = next
            }
        }

        fun size(): Pair<Int, Int> {
            val profile = u(8)
            u(16) // constraint flags, level
            ue() // seq_parameter_set_id
            var chroma = 1
            if (profile in setOf(100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135)) {
                chroma = ue()
                if (chroma == 3) u(1)
                ue()
                ue()
                u(1)
                if (u(1) == 1) for (i in 0 until if (chroma != 3) 8 else 12) if (u(1) == 1) skipScalingList(if (i < 6) 16 else 64)
            }
            ue() // log2_max_frame_num
            when (ue()) {
                0 -> ue()
                1 -> {
                    u(1)
                    se()
                    se()
                    repeat(ue()) { se() }
                }
            }
            ue() // max_num_ref_frames
            u(1)
            val widthMbs = ue() + 1
            val heightUnits = ue() + 1
            val frameMbsOnly = u(1)
            if (frameMbsOnly == 0) u(1)
            u(1)
            var width = widthMbs * 16
            var height = heightUnits * 16 * (2 - frameMbsOnly)
            if (u(1) == 1) {
                val left = ue()
                val right = ue()
                val top = ue()
                val bottom = ue()
                val cropX = if (chroma == 0 || chroma == 3) 1 else 2
                val cropY = (if (chroma == 1) 2 else 1) * (2 - frameMbsOnly)
                width -= (left + right) * cropX
                height -= (top + bottom) * cropY
            }
            return width to height
        }
    }
}

// Where the picture goes in the space there is, by the person's display.* settings and the game's shape.
data class PictureFit(val width: Float, val height: Float, val turns: Int) {
    companion object {
        // aspect: the session's, width over height. frameW/H: what the core really draws, for square pixels and
        // whole multiples. boxW/H: the space there is.
        fun fit(settings: GameSettings, aspect: Double, frameW: Double, frameH: Double, sessionTurns: Int, boxW: Float, boxH: Float): PictureFit {
            val rotate = settings.text("display.rotate", "0").toIntOrNull() ?: 0
            val turns = (((sessionTurns + rotate / 90) % 4) + 4) % 4
            var shape = when (settings.text("display.aspect", "original")) {
                "4:3" -> 4.0 / 3.0
                "16:9" -> 16.0 / 9.0
                "square" -> if (frameH > 0) frameW / frameH else aspect
                "custom" -> settings.number("display.aspectCustom", 1.33).coerceIn(0.5, 3.0)
                "stretch" -> 0.0
                else -> aspect
            }
            if (shape <= 0 || !shape.isFinite()) {
                if (settings.text("display.aspect", "original") == "stretch") return PictureFit(boxW, boxH, turns)
                shape = if (frameH > 0) frameW / frameH else 4.0 / 3.0
            }
            // Turned a quarter, the picture is as tall as it was wide.
            val shown = if (turns % 2 == 1) 1 / shape else shape
            var h = min(boxH.toDouble(), boxW / shown)
            val sourceHeight = if (turns % 2 == 1) frameW else frameH
            if (settings.flag("display.integer", false) && sourceHeight > 0 && h >= sourceHeight) {
                h = floor(h / sourceHeight) * sourceHeight
            }
            return PictureFit((h * shown).toFloat(), h.toFloat(), turns)
        }
    }
}

// Which of a port's device types is plugged in. A session may name the base type (1, a joypad) where its list
// has the console's own kind of it (257, a subclass of the joypad, as libretro numbers them).
fun currentDevice(d: GamePortDevices): Int =
    d.types.firstOrNull { it.id == d.current }?.id ?: d.types.firstOrNull { it.id and 0xff == d.current && it.id > 0xff }?.id ?: d.current

// How much sound may wait to be played before some is dropped to catch up, by audio.latency.
fun soundLatencySeconds(setting: String): Double = when (setting) {
    "smooth" -> 0.16
    "balanced" -> 0.09
    else -> 0.05
}
