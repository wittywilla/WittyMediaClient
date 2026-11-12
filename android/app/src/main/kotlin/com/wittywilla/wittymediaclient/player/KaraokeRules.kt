// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Karaoke from a song's separated parts (the server's `karaoke-auto`: docs/LYRICS-KARAOKE.md in its repository). The
// rules here are the website's and the iPhone's: what the server's answer means, how loud each part plays, what's
// remembered, what to ask the server next, and how the parts are added together. Nothing here touches Android, so
// all of it is tested on the JVM (KaraokeRulesTest).

// One part of a song: the voice, a piece of the music, or the whole song.
@Serializable
data class KaraokeStem(
    val id: String = "",
    val label: String = "",
    val role: String = "",
    val url: String = "",
    val mime: String = "",
    val defaultGain: Double = 1.0,
)

// What POST /media/{id}/karaoke/prepare and GET /media/{id}/karaoke both answer.
@Serializable
data class KaraokeAnswer(
    val state: String = "",
    val quality: String = "",
    val mix: String = "",
    val stems: List<KaraokeStem> = emptyList(),
    val version: String = "",
    val improving: Boolean = false,
    val progress: Int = -1,
    val canImprove: Boolean = false,
    val reason: String = "",
    val message: String = "",
    val pollSec: Int = 0,
) {
    val blend: Boolean get() = mix == "blend"

    // The parts the mixer plays, in the order it plays them. A blend is the whole song and its music, and nothing
    // else; anything missing leaves nothing to play. Otherwise every part with an address plays: a part whose role
    // this app doesn't know is music, so nothing of the song is lost, but a whole song among parts would double it.
    val playable: List<KaraokeStem>
        get() {
            val usable = stems.filter { it.id.isNotEmpty() && it.url.isNotEmpty() }.distinctBy { it.id }
            if (blend) {
                val full = usable.firstOrNull { it.id == KaraokeMix.FULL } ?: return emptyList()
                val music = usable.firstOrNull { it.id == KaraokeMix.MUSIC } ?: return emptyList()
                return listOf(full, music)
            }
            return usable.filter { it.role != "full" }.take(KaraokeMix.MOST_STEMS)
        }

    companion object {
        // Null for an answer that isn't one. Fields this app doesn't know are left alone.
        fun parse(text: String): KaraokeAnswer? = runCatching { json.decodeFromString<KaraokeAnswer>(text) }.getOrNull()
    }
}

// What's remembered for a profile: the voice's level, and each part's by its id. Nothing kept means the server's own.
data class KaraokeLevels(val vocals: Double? = null, val stems: Map<String, Double> = emptyMap()) {
    fun toJson(): String = JsonObject(
        buildMap {
            vocals?.let { put("vocals", JsonPrimitive(it)) }
            put("stems", JsonObject(stems.mapValues { JsonPrimitive(it.value) }))
        },
    ).toString()

    companion object {
        // Where a profile's levels are kept in the app's preferences: one for each account on each server.
        fun key(server: String, profile: Long) = "wms.karaoke.levels|$server|$profile"

        // Anything unreadable is nothing remembered; a level outside 0…1 is brought inside.
        fun read(text: String?): KaraokeLevels {
            val o = runCatching { json.parseToJsonElement(text.orEmpty()).jsonObject }.getOrNull() ?: return KaraokeLevels()
            fun level(of: kotlinx.serialization.json.JsonElement?) = runCatching { of?.jsonPrimitive?.doubleOrNull }.getOrNull()?.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0)
            val stems = runCatching { o["stems"]?.jsonObject }.getOrNull().orEmpty().mapNotNull { (id, v) -> level(v)?.let { id to it } }.toMap()
            return KaraokeLevels(level(o["vocals"]), stems)
        }
    }
}

// A slider of the "More" list: which level it moves, and what it's called.
data class KaraokeSlider(val id: String, val label: String)

// What the singer has set: the levels, and Sing, which silences the voice without forgetting where its slider was.
data class KaraokeControls(val levels: KaraokeLevels = KaraokeLevels(), val sing: Boolean = false) {
    // Moving the Vocals slider turns Sing off.
    fun moveVocals(to: Double) = KaraokeControls(levels.copy(vocals = to.coerceIn(0.0, 1.0)), false)

    fun move(answer: KaraokeAnswer, id: String, to: Double) =
        if (KaraokeMix.isVocals(answer, id)) moveVocals(to) else copy(levels = levels.copy(stems = levels.stems + (id to to.coerceIn(0.0, 1.0))))

    fun toggleSing() = copy(sing = !sing)

    // Everything back to what the server said.
    fun reset() = KaraokeControls()
}

object KaraokeMix {
    const val FULL = "full"
    const val MUSIC = "instrumental"
    const val VOCALS = "vocals"
    const val MOST_STEMS = 8
    const val STEP = 0.05

    private fun level(gain: Double) = if (gain.isFinite()) gain.coerceIn(0.0, 1.0) else 1.0

    // The part the big Vocals slider moves, where the voice is a part of its own.
    fun vocalsStem(answer: KaraokeAnswer): KaraokeStem? = if (answer.blend) null else answer.playable.firstOrNull { it.role == "vocals" }

    fun isVocals(answer: KaraokeAnswer, id: String) = if (answer.blend) id == VOCALS else id == vocalsStem(answer)?.id

    // The voice's level as the server set it: the vocals part's, or the whole song's in a blend.
    fun vocalsDefault(answer: KaraokeAnswer): Double =
        level((if (answer.blend) answer.playable.firstOrNull { it.id == FULL } else vocalsStem(answer))?.defaultGain ?: 1.0)

    // Where the Vocals slider stands, whatever Sing is doing.
    fun vocals(answer: KaraokeAnswer, levels: KaraokeLevels): Double = levels.vocals ?: vocalsDefault(answer)

    // Where a slider of the "More" list stands.
    fun level(answer: KaraokeAnswer, levels: KaraokeLevels, id: String): Double =
        if (isVocals(answer, id)) vocals(answer, levels)
        else levels.stems[id] ?: level(answer.playable.firstOrNull { it.id == id }?.defaultGain ?: 1.0)

    // The sliders of "More": one for each part by its name, or Vocals and Music for a blend.
    fun sliders(answer: KaraokeAnswer): List<KaraokeSlider> =
        if (answer.blend) {
            if (answer.playable.isEmpty()) emptyList() else listOf(KaraokeSlider(VOCALS, "Vocals"), KaraokeSlider(MUSIC, "Music"))
        } else answer.playable.map { KaraokeSlider(it.id, it.label.ifEmpty { it.id.replaceFirstChar(Char::uppercase) }) }

    // How loud each playable part plays, in the mixer's order. Parts: each at its own level, the voice's being the
    // Vocals slider. A blend, with the voice at v and the music at m: the whole song at m·v and the music at m·(1−v),
    // straight lines, as the two are the same recording.
    fun gains(answer: KaraokeAnswer, controls: KaraokeControls): List<Double> {
        val v = if (controls.sing) 0.0 else vocals(answer, controls.levels)
        val parts = answer.playable
        if (answer.blend) {
            if (parts.isEmpty()) return emptyList()
            val m = level(answer, controls.levels, MUSIC)
            return listOf(m * v, m * (1 - v))
        }
        val voice = vocalsStem(answer)?.id
        return parts.map { if (it.id == voice) v else level(answer, controls.levels, it.id) }
    }

    // A TV remote's left and right: 5% at a time, on the 5% marks.
    fun nudge(level: Double, up: Boolean): Double = ((Math.round(level / STEP) + if (up) 1 else -1) * STEP).coerceIn(0.0, 1.0)
}

// MARK: what to ask the server, and when

sealed interface KaraokeState {
    data object Idle : KaraokeState

    // Asked to prepare, and no answer yet.
    data object Asked : KaraokeState
    data class Preparing(val progress: Int) : KaraokeState
    data class Ready(val answer: KaraokeAnswer) : KaraokeState
    data class Unavailable(val message: String) : KaraokeState

    // The parts couldn't be played: the normal track plays, and this says so.
    data class Fallback(val message: String) : KaraokeState
}

sealed interface KaraokeEvent {
    // Karaoke opened on a song, or the song changed under it.
    data class Open(val song: Long) : KaraokeEvent
    data object Close : KaraokeEvent
    data class Answered(val answer: KaraokeAnswer) : KaraokeEvent

    // The server couldn't be asked. Lasting is a refusal that asking again won't change.
    data class Failed(val message: String, val lasting: Boolean) : KaraokeEvent
    data class StemsFailed(val message: String) : KaraokeEvent
}

sealed interface KaraokeEffect {
    // Ask the server after this many seconds: POST prepare, or GET.
    data class Ask(val afterSec: Int, val prepare: Boolean) : KaraokeEffect

    // Fetch these parts and play them, taking over from any playing now where the song is.
    data class Load(val answer: KaraokeAnswer) : KaraokeEffect

    // Stop the parts and let the normal track be heard.
    data object Unload : KaraokeEffect
}

data class KaraokeMachine(
    val state: KaraokeState = KaraokeState.Idle,
    val song: Long = 0,
    // Asks that have failed in a row.
    val failures: Int = 0,
    // The version of the parts last asked to play.
    val loaded: String? = null,
) {
    fun on(event: KaraokeEvent): Pair<KaraokeMachine, List<KaraokeEffect>> = when (event) {
        is KaraokeEvent.Open -> KaraokeMachine(KaraokeState.Asked, event.song) to listOf(KaraokeEffect.Unload, KaraokeEffect.Ask(0, true))
        KaraokeEvent.Close -> KaraokeMachine() to listOf(KaraokeEffect.Unload)
        is KaraokeEvent.Answered -> answered(event.answer)
        is KaraokeEvent.Failed -> when {
            state == KaraokeState.Idle || state is KaraokeState.Fallback -> this to emptyList()
            event.lasting -> copy(state = KaraokeState.Unavailable(event.message.ifEmpty { NOT_NOW }), failures = 0, loaded = null) to unloadIfPlaying()
            // The network: as it was, and asked again later and later, up to every half minute.
            else -> copy(failures = failures + 1) to listOf(KaraokeEffect.Ask(backoff(failures + 1), state == KaraokeState.Asked))
        }
        is KaraokeEvent.StemsFailed ->
            if (state is KaraokeState.Ready) copy(state = KaraokeState.Fallback(event.message.ifEmpty { NORMAL_TRACK }), loaded = null) to listOf(KaraokeEffect.Unload)
            else this to emptyList()
    }

    private fun unloadIfPlaying() = if (state is KaraokeState.Ready) listOf(KaraokeEffect.Unload) else emptyList()

    private fun answered(answer: KaraokeAnswer): Pair<KaraokeMachine, List<KaraokeEffect>> {
        if (state == KaraokeState.Idle || state is KaraokeState.Fallback) return this to emptyList()
        val again = if (answer.pollSec > 0) listOf(KaraokeEffect.Ask(answer.pollSec.coerceAtMost(MOST_WAIT_SEC), false)) else emptyList()
        return when (answer.state) {
            "ready" -> when {
                answer.playable.isEmpty() -> copy(state = KaraokeState.Fallback(NORMAL_TRACK), failures = 0, loaded = null) to listOf(KaraokeEffect.Unload)
                else -> {
                    // New parts, or better ones than are playing: those take over. The same ones carry on.
                    val load = if (state !is KaraokeState.Ready || loaded != answer.version) listOf(KaraokeEffect.Load(answer)) else emptyList()
                    // A better version being made is watched for, whatever the server says about asking again.
                    val watch = again.ifEmpty { if (answer.improving) listOf(KaraokeEffect.Ask(DEFAULT_POLL_SEC, false)) else emptyList() }
                    copy(state = KaraokeState.Ready(answer), failures = 0, loaded = answer.version) to load + watch
                }
            }
            "preparing" -> copy(state = KaraokeState.Preparing(answer.progress), failures = 0, loaded = null) to
                unloadIfPlaying() + again.ifEmpty { listOf(KaraokeEffect.Ask(DEFAULT_POLL_SEC, false)) }
            else -> copy(state = KaraokeState.Unavailable(answer.message.ifEmpty { NOT_NOW }), failures = 0, loaded = null) to unloadIfPlaying() + again
        }
    }

    companion object {
        const val DEFAULT_POLL_SEC = 3
        const val MOST_WAIT_SEC = 30
        const val NOT_NOW = "Karaoke isn't available for this song."
        const val NORMAL_TRACK = "The song's separated parts couldn't be played, so this is the normal track."
        const val TOO_LARGE = "The song's separated parts are too large to keep on this device, so this is the normal track."

        // 6, 12, 24, then every 30 seconds.
        fun backoff(failures: Int): Int = (DEFAULT_POLL_SEC.toLong() shl failures.coerceIn(0, 10)).coerceAtMost(MOST_WAIT_SEC.toLong()).toInt()
    }
}

// The words under the controls.
object KaraokeWords {
    private fun percent(progress: Int) = if (progress < 0) "" else " ${progress.coerceAtMost(100)}%"

    // What's said while there are no parts playing: being made, why not, or that the normal track is playing. Empty
    // once they play.
    fun status(state: KaraokeState, playing: Boolean): String = when (state) {
        KaraokeState.Idle, KaraokeState.Asked -> "Preparing karaoke…"
        is KaraokeState.Preparing -> "Preparing karaoke…${percent(state.progress)}"
        is KaraokeState.Ready -> if (playing) "" else "Preparing karaoke…"
        is KaraokeState.Unavailable -> state.message
        is KaraokeState.Fallback -> state.message
    }

    fun quality(answer: KaraokeAnswer): String = when (answer.quality) {
        "stems" -> "Separated"
        "approximate" -> "Quick version"
        else -> ""
    }

    fun improving(answer: KaraokeAnswer): String = if (answer.improving) "Preparing a better version…${percent(answer.progress)}" else ""
}

// MARK: adding the parts together

object PcmMix {
    // Which frame of a recording a time is.
    fun frameOf(us: Long, rate: Int): Long = Math.round(us * rate / 1_000_000.0)

    fun usOf(frame: Long, rate: Int): Long = Math.round(frame * 1_000_000.0 / rate)

    // How many frames at the start of a decoded block are before the place being sought, and so thrown away.
    fun toDrop(firstFrame: Long, targetFrame: Long, frames: Int): Int = (targetFrame - firstFrame).coerceIn(0, frames.toLong()).toInt()

    // One decoded block, as stereo floats from -1 to 1. Any channel count: one is put in both sides; three or more are
    // folded into two the usual way (the centre into both at -3 dB, a 5.1's low-frequency channel left out, the rest
    // to their side), scaled so the fold can't be louder than the loudest channel.
    fun fold(input: FloatArray, frames: Int, channels: Int, out: FloatArray) {
        when (channels) {
            1 -> for (f in 0 until frames) {
                out[f * 2] = input[f]
                out[f * 2 + 1] = input[f]
            }
            2 -> System.arraycopy(input, 0, out, 0, frames * 2)
            else -> {
                var leftWeight = 1f
                var rightWeight = 1f
                val weights = FloatArray(channels) { c ->
                    when {
                        c < 2 -> 1f
                        c == 2 -> CENTRE.also { leftWeight += it; rightWeight += it }
                        c == 3 && channels >= 6 -> 0f
                        c % 2 == 0 -> CENTRE.also { leftWeight += it }
                        else -> CENTRE.also { rightWeight += it }
                    }
                }
                for (f in 0 until frames) {
                    var l = 0f
                    var r = 0f
                    for (c in 0 until channels) {
                        val v = input[f * channels + c] * weights[c]
                        when {
                            c == 0 -> l += v
                            c == 1 -> r += v
                            c == 2 -> { l += v; r += v }
                            c % 2 == 0 -> l += v
                            else -> r += v
                        }
                    }
                    out[f * 2] = l / leftWeight
                    out[f * 2 + 1] = r / rightWeight
                }
            }
        }
    }

    // Bytes in one sample of an output encoding the mixer reads, or 0 for one it doesn't.
    fun bytesPer(encoding: Int): Int = when (encoding) {
        android.media.AudioFormat.ENCODING_PCM_16BIT -> 2
        android.media.AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
        android.media.AudioFormat.ENCODING_PCM_32BIT, android.media.AudioFormat.ENCODING_PCM_FLOAT -> 4
        android.media.AudioFormat.ENCODING_PCM_8BIT -> 1
        else -> 0
    }

    // Reads `samples` samples of a decoder's output, from where the buffer is, as floats from -1 to 1. The buffer is in
    // the device's own byte order.
    fun read(from: java.nio.ByteBuffer, encoding: Int, out: FloatArray, samples: Int) {
        when (encoding) {
            android.media.AudioFormat.ENCODING_PCM_16BIT -> for (i in 0 until samples) out[i] = from.short / 32768f
            android.media.AudioFormat.ENCODING_PCM_FLOAT -> for (i in 0 until samples) out[i] = from.float
            android.media.AudioFormat.ENCODING_PCM_32BIT -> for (i in 0 until samples) out[i] = (from.int / 2147483648.0).toFloat()
            android.media.AudioFormat.ENCODING_PCM_8BIT -> for (i in 0 until samples) out[i] = ((from.get().toInt() and 0xFF) - 128) / 128f
            android.media.AudioFormat.ENCODING_PCM_24BIT_PACKED -> {
                val little = from.order() == java.nio.ByteOrder.LITTLE_ENDIAN
                for (i in 0 until samples) {
                    val a = from.get().toInt() and 0xFF
                    val b = from.get().toInt() and 0xFF
                    val c = from.get().toInt()
                    val v = if (little) (c shl 16) or (b shl 8) or a else ((a shl 24) shr 8) or (b shl 8) or (c and 0xFF)
                    out[i] = v / 8388608f
                }
            }
        }
    }

    // A float sample as 16 bits, held at the top rather than wrapping round.
    fun toShort(v: Float): Short = Math.round(v * 32767f).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()

    private const val CENTRE = 0.7071f

    // Adds the parts, frame for frame, into `out`: 16-bit, with the channels side by side. Each part's level moves in
    // a straight line across the block from `from` to `to`, so a slider doesn't click, and what's too loud is held at
    // the top rather than wrapping round.
    fun mix(inputs: List<ShortArray>, from: FloatArray, to: FloatArray, out: ShortArray, frames: Int, channels: Int) {
        for (f in 0 until frames) {
            val part = if (frames <= 1) 1f else (f + 1).toFloat() / frames
            for (c in 0 until channels) {
                val at = f * channels + c
                var sum = 0f
                for (i in inputs.indices) sum += inputs[i][at] * (from[i] + (to[i] - from[i]) * part)
                out[at] = Math.round(sum).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            }
        }
    }
}

// A part at another sample rate, brought to the mixer's: stereo floats in, stereo floats out, straight lines between
// samples. Kept across blocks, so a block's edge makes no click; reset after a seek.
class PcmResampler(private val from: Int, val to: Int) {
    private val step = from.toDouble() / to
    // Where the next output sample falls, in input frames from the start of the next block; -1 is the last frame of
    // the block before.
    private var at = 0.0
    private var lastL = 0f
    private var lastR = 0f
    private var primed = false

    val same: Boolean get() = from == to

    // Output frames `frames` input frames make at most.
    fun most(frames: Int): Int = (frames / step).toInt() + 2

    fun reset() {
        at = 0.0
        primed = false
    }

    // Writes the block's samples at the output rate into out from frame 0, and says how many frames that was.
    fun run(input: FloatArray, frames: Int, out: FloatArray): Int {
        if (frames <= 0) return 0
        if (same) {
            System.arraycopy(input, 0, out, 0, frames * 2)
            return frames
        }
        if (!primed) {
            // The first block starts on its own first sample.
            at = 0.0
            primed = true
        }
        var made = 0
        while (at < frames - 1) {
            val i = kotlin.math.floor(at).toInt()
            val part = (at - i).toFloat()
            val al = if (i < 0) lastL else input[i * 2]
            val ar = if (i < 0) lastR else input[i * 2 + 1]
            val bl = input[(i + 1) * 2]
            val br = input[(i + 1) * 2 + 1]
            out[made * 2] = al + (bl - al) * part
            out[made * 2 + 1] = ar + (br - ar) * part
            made++
            at += step
        }
        at -= frames
        lastL = input[(frames - 1) * 2]
        lastR = input[(frames - 1) * 2 + 1]
        return made
    }
}
