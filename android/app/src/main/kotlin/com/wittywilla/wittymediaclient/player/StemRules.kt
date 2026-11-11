// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.StemInfo
import kotlin.math.floor
import kotlin.math.roundToInt

// Mixing a song's separated parts (stems) for karaoke, as rules and arithmetic apart from Android so they can be
// tested. How it stays in step is the point of the design:
//
//   The song itself keeps playing in the one ExoPlayer the queue, the lock screen and the crossfade already use. A
//   processor in that player's own sound chain (StemMixer) counts the frames going through it from the place the
//   player says the stream starts, so it knows which frame of the song it is holding, to the sample. Each part is
//   decoded on a thread of its own into a window of frames numbered the same way, and the processor replaces the
//   song's frames with the parts' frames of the same numbers. There is one clock (the song's own stream of frames),
//   one audio output, and nothing to drift: a part that isn't ready for a frame holds the song for a moment or lets it
//   through as it is, and never plays late.
//
// Several players started together would each run on their own output and drift apart within a song.

// One fader's worth: a part of the song, where it comes from, and which audio track of that file it is.
data class StemPart(val name: String, val label: String, val url: String, val track: Int = 0, val approximate: Boolean = false)

// What the mixer plays for a song. `withOriginal`: the parts don't make the whole song (there's no separate voice, or
// not all of the music), so the song itself is a fader too and nothing is lost.
data class StemPlan(val parts: List<StemPart>, val withOriginal: Boolean) {
    val approximate: Boolean get() = parts.any { it.approximate }
    val faders: List<String> get() = parts.map { it.name } + if (withOriginal) listOf(StemRules.ORIGINAL) else emptyList()
}

object StemRules {
    const val ORIGINAL = "original"
    private val FINE = listOf("drums", "bass", "other")

    // "Vocals", "Instrumental (approximate)", "The song itself".
    fun label(name: String, approximate: Boolean = false): String {
        val words = when (name) {
            "vocals" -> "Vocals"
            "instrumental" -> "Instrumental"
            "drums" -> "Drums"
            "bass" -> "Bass"
            "other" -> "Other instruments"
            ORIGINAL -> "The song itself"
            else -> name.replace('-', ' ').replace('_', ' ').replaceFirstChar { it.uppercase() }
        }
        return if (approximate) "$words (approximate)" else words
    }

    // Which of the listed stems to mix. Parts that would double each other aren't both played: with drums, bass and
    // the rest all there, the instrumental (their sum) is left out, and otherwise it stands for them. A Native
    // Instruments file is used only when there are no separate parts, as its four tracks after the full mix. Null when
    // nothing listed can be played.
    fun plan(stems: List<StemInfo>): StemPlan? {
        val usable = stems.filter { it.name.isNotBlank() && it.url.startsWith("/") && !it.url.startsWith("//") }.distinctBy { it.name }
        val named = usable.filter { !it.multitrack }
        if (named.isEmpty()) {
            val all = usable.firstOrNull { it.multitrack } ?: return null
            return StemPlan((1..4).map { StemPart("part$it", "Part $it", all.url, track = it) }, withOriginal = false)
        }
        fun part(info: StemInfo) = StemPart(info.name, label(info.name, info.approximate), info.url, approximate = info.approximate)
        val byName = named.associateBy { it.name }
        val voice = byName["vocals"]
        val music = byName["instrumental"]
        val fine = FINE.mapNotNull { byName[it] }
        val extra = named.filter { it.name != "vocals" && it.name != "instrumental" && it.name !in FINE }
        val chosen = when {
            fine.size == FINE.size -> listOfNotNull(voice) + fine
            music != null -> listOfNotNull(voice, music)
            else -> listOfNotNull(voice) + fine
        } + extra
        val whole = voice != null && (fine.size == FINE.size || music != null)
        return StemPlan(chosen.map(::part), withOriginal = !whole)
    }

    // Where the faders start: every part up, and the song itself down, so turning the mixer on with only an
    // instrumental is karaoke at once.
    fun startLevels(plan: StemPlan): Map<String, Double> = plan.faders.associateWith { if (it == ORIGINAL) 0.0 else 1.0 }

    // A fader's level, 0 to 1, as what the samples are multiplied by: squared, so the lower half of the fader isn't
    // all of the quiet. 0 is silence and 1 leaves the part as it is.
    fun gain(level: Double): Float {
        val l = if (level.isNaN()) 0.0 else level.coerceIn(0.0, 1.0)
        return (l * l).toFloat()
    }

    const val STEP = 0.1

    // One press of − or +.
    fun stepped(level: Double, up: Boolean): Double = ((level + if (up) STEP else -STEP) * 10).roundToInt().coerceIn(0, 10) / 10.0

    // "100%", "0%".
    fun percent(level: Double): String = "${(level.coerceIn(0.0, 1.0) * 100).roundToInt()}%"

    // The number of the frame playing at a time in the song, and back. Rounded to the nearest, so the same time gives
    // the same frame for every part.
    fun frameAt(positionUs: Long, rate: Int): Long = Math.floorDiv(positionUs * rate + 500_000, 1_000_000L)
    fun usAt(frame: Long, rate: Int): Long = if (rate <= 0) 0 else frame * 1_000_000L / rate
}

// What a part's decoder should do next.
sealed interface DecodeStep {
    data object Idle : DecodeStep
    data object Decode : DecodeStep
    data class Seek(val to: Long) : DecodeStep
}

// The frames of one part that are decoded and waiting, numbered as the song's frames are: two channels of 16 bits, in
// a ring that holds a few seconds. The decoder's thread writes and the player's thread reads, so everything is under
// the lock, which neither holds for longer than a copy.
class StemWindow(val capacity: Int) {
    private val data = ShortArray(capacity * 2)
    private var base = 0L // the first frame kept
    private var end = 0L // one past the last
    private var ended = false // the part has no more: past `end` it is silent

    val first: Long @Synchronized get() = base
    val next: Long @Synchronized get() = end
    val finished: Boolean @Synchronized get() = ended

    // Start again from this frame: a seek.
    @Synchronized
    fun reset(at: Long) {
        base = at
        end = at
        ended = false
    }

    @Synchronized
    fun room(): Int = capacity - (end - base).toInt()

    // Has every frame from `at` for `frames`? Past the end of a part that has finished counts: it is silence there.
    @Synchronized
    fun covers(at: Long, frames: Int): Boolean = at >= base && (at + frames <= end || ended)

    // Frames before this one have been played and can go.
    @Synchronized
    fun forget(before: Long) {
        if (before > base) base = minOf(before, end)
    }

    // Adds frames after the last, as many as there's room for. Says how many went in.
    @Synchronized
    fun write(src: ShortArray, fromFrame: Int, frames: Int): Int {
        val count = minOf(frames, room())
        for (i in 0 until count) {
            val slot = slot(end + i)
            data[slot] = src[(fromFrame + i) * 2]
            data[slot + 1] = src[(fromFrame + i) * 2 + 1]
        }
        end += count
        return count
    }

    // Adds silence after the last: a part whose decoder landed a little after the place asked for.
    @Synchronized
    fun pad(frames: Int): Int {
        val count = minOf(frames, room())
        for (i in 0 until count) {
            val slot = slot(end + i)
            data[slot] = 0
            data[slot + 1] = 0
        }
        end += count
        return count
    }

    @Synchronized
    fun finish() {
        ended = true
    }

    // Adds this part to a mix, its level moving evenly from `gainFrom` to `gainTo` across the frames so a fader never
    // clicks. `into` is two channels, -1 to 1. Frames the part doesn't have (past its end) add nothing.
    @Synchronized
    fun addInto(at: Long, frames: Int, into: FloatArray, gainFrom: Float, gainTo: Float) {
        if (gainFrom == 0f && gainTo == 0f) return
        for (i in 0 until frames) {
            val frame = at + i
            if (frame < base || frame >= end) continue
            val gain = (gainFrom + (gainTo - gainFrom) * (i + 1) / frames) / 32768f
            val slot = slot(frame)
            into[i * 2] += data[slot] * gain
            into[i * 2 + 1] += data[slot + 1] * gain
        }
    }

    // What the decoder should do, given the frame the mixer is at. Further back than what's kept, or further ahead
    // than `jump` past it, is a seek; otherwise it decodes until `ahead` frames are waiting.
    @Synchronized
    fun step(need: Long, ahead: Int, jump: Int): DecodeStep = when {
        need < base -> DecodeStep.Seek(need)
        ended -> DecodeStep.Idle
        need > end + jump -> DecodeStep.Seek(need)
        end - maxOf(need, base) >= minOf(ahead, capacity) -> DecodeStep.Idle
        else -> DecodeStep.Decode
    }

    private fun slot(frame: Long): Int = Math.floorMod(frame, capacity.toLong()).toInt() * 2
}

// Brings a part recorded at one sample rate to the song's, a chunk at a time, by drawing a straight line between
// neighbouring samples. Two channels of 16 bits in and out. Parts are almost always at the song's own rate, where this
// isn't used at all.
class StemResampler(private val from: Int, private val to: Int) {
    private val step = from.toDouble() / to
    private var at = 0.0 // where the next output frame is, in input frames from the start of the next chunk
    private var lastL: Short = 0
    private var lastR: Short = 0

    fun reset() {
        at = 0.0
    }

    // The most frames one chunk of `frames` can come out as.
    fun most(frames: Int): Int = (frames.toLong() * to / from).toInt() + 2

    // `out` must hold most(frames) frames. Says how many frames were written.
    fun run(src: ShortArray, frames: Int, out: ShortArray): Int {
        if (frames <= 0) return 0
        var made = 0
        while (true) {
            val whole = floor(at).toInt()
            if (whole + 1 >= frames) break
            val part = at - whole
            // Frame -1 is the last of the chunk before, kept so the line carries across the join.
            val l0 = if (whole < 0) lastL else src[whole * 2]
            val r0 = if (whole < 0) lastR else src[whole * 2 + 1]
            val l1 = src[(whole + 1) * 2]
            val r1 = src[(whole + 1) * 2 + 1]
            out[made * 2] = (l0 + (l1 - l0) * part).roundToInt().toShort()
            out[made * 2 + 1] = (r0 + (r1 - r0) * part).roundToInt().toShort()
            made++
            at += step
        }
        lastL = src[(frames - 1) * 2]
        lastR = src[(frames - 1) * 2 + 1]
        at -= frames
        return made
    }
}

// Whether to mix, hold the song or let it through as it is, a buffer at a time.
//
// Until every part has the frames for the place the song is at, the song plays as it is: turning the mixer on never
// stops the music. Once they are in step it mixes. If they then fall behind (a seek, or a slow network) the song is
// held for a moment rather than letting the voice back in, and if the parts still aren't there after `giveUpMs` it
// goes back to playing as it is until they are.
class StemGate(private val giveUpMs: Long = 4_000, private val idleMs: Long = 300) {
    enum class Now { Mix, Hold, Plain }

    private var inStep = false
    private var heldSince = -1L
    private var lastAsked = -1L

    // True while the parts are being played in place of the song.
    val mixing: Boolean get() = inStep

    fun decide(ready: Boolean, nowMs: Long): Now {
        // Time the player wasn't asking for sound (paused) isn't time spent waiting for the parts.
        if (heldSince >= 0 && lastAsked >= 0 && nowMs - lastAsked > idleMs) heldSince += nowMs - lastAsked
        lastAsked = nowMs
        if (ready) {
            inStep = true
            heldSince = -1
            return Now.Mix
        }
        if (!inStep) return Now.Plain
        if (heldSince < 0) heldSince = nowMs
        if (nowMs - heldSince < giveUpMs) return Now.Hold
        inStep = false
        heldSince = -1
        return Now.Plain
    }

    // The mixer was turned off, or the song changed.
    fun reset() {
        inStep = false
        heldSince = -1
        lastAsked = -1
    }
}

// The arithmetic of one buffer, on plain arrays: the parts already added into `wet`, the song itself in `dry`, both
// two channels from -1 to 1. What comes out is the song as it is while `blend` is 0, the mix while it is 1, and a
// short slide between the two so that going from one to the other isn't a click. Says where the slide got to.
fun blendMix(dry: FloatArray, wet: FloatArray, frames: Int, originalFrom: Float, originalTo: Float, blend: Float, blendTo: Float, blendStep: Float): Float {
    var b = blend
    for (i in 0 until frames) {
        if (b < blendTo) b = minOf(blendTo, b + blendStep) else if (b > blendTo) b = maxOf(blendTo, b - blendStep)
        val own = originalFrom + (originalTo - originalFrom) * (i + 1) / frames
        for (c in 0..1) {
            val at = i * 2 + c
            val mixed = wet[at] + dry[at] * own
            wet[at] = dry[at] * (1 - b) + mixed * b
        }
    }
    return b
}
