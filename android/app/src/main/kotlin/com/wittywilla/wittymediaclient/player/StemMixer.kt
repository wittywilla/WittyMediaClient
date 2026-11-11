// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Timeline
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import com.wittywilla.wittymediaclient.net.Api
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

// A song's parts mixed in place of the song, in the listening player's own sound chain, before the equaliser, the
// volume leveling and the key (SoundShaper.kt and the player's pitch), which then treat the mix as they treat any song.
// Why it is done here, and how it stays in step, is at the top of StemRules.kt. With no mix asked for, or for any
// song but the one it was asked for, the sound passes through untouched.

// What the screen is told about a mix.
enum class StemState { Loading, InStep, CatchingUp, Failed }

// One song's mix: its parts, each with a decoder and a fader, for as long as karaoke wants it. Made on the main
// thread, read on the player's.
class StemSession(val itemId: Long, val plan: StemPlan, api: Api, levels: Map<String, Double>) {
    class Part(val info: StemPart, val decoder: StemDecoder) {
        @Volatile
        var level = 1f
        internal var heard = 0f // where the fader has got to, on the player's thread
    }

    @Volatile
    var failure = ""
        private set

    // Where the mixer has got to. A part that couldn't be read ends it, whatever the mixer last said.
    @Volatile
    internal var progress = StemState.Loading

    val state: StemState get() = if (failure.isNotEmpty()) StemState.Failed else progress

    @Volatile
    var originalLevel = 0f

    internal var originalHeard = 0f

    val parts: List<Part> = plan.parts.map { part ->
        Part(part, StemDecoder(api.http, api.mediaUrl(part.url), part.track, StemWindow(WINDOW_FRAMES)) { why -> fail(why) })
    }

    init {
        levels.forEach { (name, level) -> setLevel(name, level) }
        parts.forEach { it.decoder.start() }
    }

    fun setLevel(name: String, level: Double) {
        val gain = StemRules.gain(level)
        if (name == StemRules.ORIGINAL) originalLevel = gain else parts.firstOrNull { it.info.name == name }?.level = gain
    }

    private fun fail(why: String) {
        failure = why.ifEmpty { "The parts couldn't be read." }
    }

    fun close() {
        parts.forEach { it.decoder.close() }
    }

    private companion object {
        // Three seconds at 48 kHz: about half a megabyte a part.
        const val WINDOW_FRAMES = 144_000
    }
}

// The mix that's on, for the whole app: set from karaoke, read by the player's processor.
object StemMixing {
    @Volatile
    var session: StemSession? = null
        private set

    val active: Boolean get() = session != null

    // Starts mixing this song's parts, in place of whatever was being mixed. The song carries on as it is until the
    // parts are in step. Throws when an address in the plan isn't the server's own.
    fun start(itemId: Long, plan: StemPlan, api: Api, levels: Map<String, Double>): StemSession {
        val made = StemSession(itemId, plan, api, levels)
        session?.close()
        session = made
        return made
    }

    fun stop() {
        session?.close()
        session = null
    }
}

@OptIn(UnstableApi::class)
class StemMixer : BaseAudioProcessor() {
    private val gate = StemGate()
    private var playing: Long? = null // the item whose sound is coming through, when the player says
    private var anchor = 0L // the song's frame that the first frame after the last flush is
    private var counted = 0L // frames through since then
    private var blend = 0f // 0 the song as it is, 1 the mix
    private var mixed: StemSession? = null
    private var dry = FloatArray(0)
    private var wet = FloatArray(0)

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val pcm = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT || inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        if (!pcm || inputAudioFormat.channelCount !in 1..2) return AudioProcessor.AudioFormat.NOT_SET
        return inputAudioFormat
    }

    // The player has started, sought or moved to another song: it says where in which song the next frame is. That
    // is the one thing everything is counted from.
    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        val rate = inputAudioFormat.sampleRate
        anchor = if (rate > 0) StemRules.frameAt(streamMetadata.positionOffsetUs, rate) else 0
        counted = 0
        playing = runCatching {
            val timeline = streamMetadata.timeline
            val period = streamMetadata.periodUid
            if (timeline.isEmpty || period == null) null
            else {
                val window = timeline.getPeriodByUid(period, Timeline.Period()).windowIndex
                timeline.getWindow(window, Timeline.Window()).mediaItem.mediaId.toLongOrNull()
            }
        }.getOrNull()
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val format = inputAudioFormat
        val frames = inputBuffer.remaining() / format.bytesPerFrame
        if (frames == 0) return
        val session = StemMixing.session?.takeIf { it.itemId == playing && it.failure.isEmpty() }
        if (session !== mixed) {
            // Another song, or the mixer turned on or off: nothing carries over.
            mixed = session
            gate.reset()
            blend = 0f
        }
        if (session == null) {
            pass(inputBuffer, frames, format)
            return
        }
        val at = anchor + counted
        var ready = true
        for (part in session.parts) {
            part.decoder.want(at, format.sampleRate)
            if (!part.decoder.window.covers(at, frames)) ready = false
        }
        val now = gate.decide(ready, SystemClock.elapsedRealtime())
        session.progress = when (now) {
            StemGate.Now.Mix -> StemState.InStep
            StemGate.Now.Hold -> StemState.CatchingUp
            StemGate.Now.Plain -> StemState.Loading
        }
        // Held: nothing is taken, so the player waits with the song exactly where it is until the parts are there.
        if (now == StemGate.Now.Hold) return
        if (now == StemGate.Now.Plain && blend == 0f) {
            pass(inputBuffer, frames, format)
            return
        }
        if (dry.size < frames * 2) {
            dry = FloatArray(frames * 2)
            wet = FloatArray(frames * 2)
        }
        val floats = format.encoding == C.ENCODING_PCM_FLOAT
        val stereo = format.channelCount == 2
        val input = inputBuffer.order(ByteOrder.nativeOrder())
        for (i in 0 until frames) {
            val l = if (floats) input.float else input.short / 32768f
            val r = if (!stereo) l else if (floats) input.float else input.short / 32768f
            dry[i * 2] = l
            dry[i * 2 + 1] = r
            wet[i * 2] = 0f
            wet[i * 2 + 1] = 0f
        }
        val original: Float
        if (now == StemGate.Now.Mix) {
            for (part in session.parts) {
                val to = part.level
                part.decoder.window.addInto(at, frames, wet, part.heard, to)
                part.heard = to
            }
            original = session.originalLevel
        } else {
            // Going back to the song as it is while the parts catch up: the slide ends on the song itself.
            original = 1f
        }
        blend = blendMix(dry, wet, frames, session.originalHeard, original, blend, if (now == StemGate.Now.Mix) 1f else 0f, 1f / (format.sampleRate * SLIDE_SEC))
        session.originalHeard = original
        val output = replaceOutputBuffer(frames * format.bytesPerFrame)
        for (i in 0 until frames) {
            val l = wet[i * 2]
            val r = wet[i * 2 + 1]
            if (stereo) {
                if (floats) { output.putFloat(l); output.putFloat(r) } else { output.putShort(short(l)); output.putShort(short(r)) }
            } else {
                val m = (l + r) / 2
                if (floats) output.putFloat(m) else output.putShort(short(m))
            }
        }
        output.flip()
        counted += frames
    }

    private fun short(sample: Float): Short = (sample * 32767f).roundToInt().coerceIn(-32768, 32767).toShort()

    // The song as it is, bit for bit.
    private fun pass(inputBuffer: ByteBuffer, frames: Int, format: AudioProcessor.AudioFormat) {
        val bytes = frames * format.bytesPerFrame
        val output = replaceOutputBuffer(bytes)
        val end = inputBuffer.limit()
        inputBuffer.limit(inputBuffer.position() + bytes)
        output.put(inputBuffer)
        inputBuffer.limit(end)
        output.flip()
        counted += frames
    }

    override fun onReset() {
        playing = null
        mixed = null
        gate.reset()
        blend = 0f
    }

    private companion object {
        // Going between the song and the mix takes a fiftieth of a second: no click, and no time to hear the voice.
        const val SLIDE_SEC = 0.02f
    }
}
