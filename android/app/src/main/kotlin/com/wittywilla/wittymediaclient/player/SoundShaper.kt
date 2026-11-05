package com.wittywilla.wittymediaclient.player

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.pow
import kotlin.math.roundToInt

// What happens to the sound between the player and the speakers, as the website's Web Audio graph does it
// (web/src/audio/sound.ts): the voice taken down, the equaliser and its level, and the volume leveling; and a copy of
// what's heard for the visualizer and the mono check. The iPhone does the same with an audio tap (SoundEngine.swift).
// The key is the player's own pitch (PlaybackParameters), and the volume its own volume, after this.

// What the processor reads, copied at the start of each buffer.
data class SoundShape(
    val eqOn: Boolean = false,
    val gains: List<Double> = Equaliser.PRESETS[0].gains,
    val preampDb: Double = 0.0,
    val loudnessDb: Double = 0.0,
    val vocalCut: Double = 0.0,
)

// The shape for the whole app, set from the screens and the service, read on the player's thread; and the processor
// the visualizer listens to.
object SoundShaping {
    @Volatile
    var shape = SoundShape()
        private set

    @Volatile
    var version = 0
        private set

    @Volatile
    var heard: SoundShaper? = null

    @Synchronized
    fun set(change: (SoundShape) -> SoundShape) {
        val next = change(shape)
        if (next != shape) {
            shape = next
            version++
        }
    }

    // Whether this recording has anything off-centre to take away. Nil in silence, or with the voice left alone.
    fun nearlyMono(): Boolean? = heard?.nearlyMono()
}

// One player's processor: its own filters and levels, reading the shared shape. PCM in 16 bits or floats, one or two
// channels; anything else passes by untouched.
@OptIn(UnstableApi::class)
class SoundShaper : BaseAudioProcessor() {
    private var rate = 44_100.0
    private var version = -1
    private var shape = SoundShape()
    private val eq = Array(Equaliser.FREQUENCIES.size) { Biquad() }
    private val sideHigh = Biquad()
    private val bass = Biquad()
    private val air = Biquad()
    // Levels move smoothly to where they're set, as setTargetAtTime does: the voice and the leveling over 50 ms, the
    // equaliser's level over 20.
    private var wet = 0.0
    private var preamp = 1.0
    private var loudness = 1.0
    private var slow = 0.0
    private var quick = 0.0

    // What was heard, for the visualizer, and how much was off-centre, for the mono check. Under the lock.
    private val lock = Any()
    private val ring = FloatArray(RING)
    private var written = 0L
    private var heardRate = 44_100
    private var sideEnergy = 0.0
    private var midEnergy = 0.0

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val pcm = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT || inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        if (!pcm || inputAudioFormat.channelCount !in 1..2) return AudioProcessor.AudioFormat.NOT_SET
        return inputAudioFormat
    }

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        version = -1
        eq.forEach { it.clear() }
        sideHigh.clear()
        bass.clear()
        air.clear()
    }

    private fun refresh(sampleRate: Int) {
        val now = SoundShaping.version
        if (now == version && sampleRate.toDouble() == rate) return
        version = now
        rate = sampleRate.toDouble()
        shape = SoundShaping.shape
        for ((band, frequency) in Equaliser.FREQUENCIES.withIndex()) {
            eq[band].set(Equaliser.kind(band), frequency, Equaliser.Q, shape.gains.getOrElse(band) { 0.0 }, rate)
        }
        // A singer is usually mixed dead centre, so left minus right leaves them out, and with them the bass and kick,
        // which are put back from below 150 Hz, with some air from above 9 kHz.
        sideHigh.set(FilterKind.HighPass, 150.0, 1.0, 0.0, rate)
        bass.set(FilterKind.LowPass, 150.0, 1.0, 0.0, rate)
        air.set(FilterKind.HighPass, 9000.0, 1.0, 0.0, rate)
        slow = towards(0.05, rate)
        quick = towards(0.02, rate)
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val format = inputAudioFormat
        val frames = inputBuffer.remaining() / format.bytesPerFrame
        if (frames == 0) return
        val input = inputBuffer.order(ByteOrder.nativeOrder())
        val output = replaceOutputBuffer(frames * format.bytesPerFrame)
        refresh(format.sampleRate)
        val floats = format.encoding == C.ENCODING_PCM_FLOAT
        val stereo = format.channelCount == 2
        val wetTarget = shape.vocalCut
        val cutting = wetTarget > 0 || wet > 0.0005
        val preTarget = if (shape.eqOn) 10.0.pow(shape.preampDb / 20) else 1.0
        val loudTarget = 10.0.pow(shape.loudnessDb / 20)
        var side2 = 0.0
        var mid2 = 0.0
        val heard = FloatArray(frames)
        for (i in 0 until frames) {
            var l = if (floats) input.float.toDouble() else input.short / 32768.0
            var r = if (!stereo) l else if (floats) input.float.toDouble() else input.short / 32768.0
            if (cutting) {
                wet += (wetTarget - wet) * slow
                val side = 0.7 * l - 0.7 * r
                val middle = (l + r) / 2
                side2 += side * side
                mid2 += middle * middle
                val high = sideHigh.run(side, 0)
                val wl = high + bass.run(l, 0) + air.run(l, 0) * 0.6
                val wr = high + bass.run(r, 1) + air.run(r, 1) * 0.6
                l = l * (1 - wet) + wl * wet
                r = r * (1 - wet) + wr * wet
            }
            if (shape.eqOn) {
                for (band in eq) {
                    l = band.run(l, 0)
                    r = band.run(r, 1)
                }
            }
            preamp += (preTarget - preamp) * quick
            loudness += (loudTarget - loudness) * slow
            l *= preamp * loudness
            r *= preamp * loudness
            if (floats) {
                output.putFloat(l.toFloat())
                if (stereo) output.putFloat(r.toFloat())
            } else {
                output.putShort((l * 32767).roundToInt().coerceIn(-32768, 32767).toShort())
                if (stereo) output.putShort((r * 32767).roundToInt().coerceIn(-32768, 32767).toShort())
            }
            heard[i] = ((l + r) / 2).toFloat()
        }
        inputBuffer.position(inputBuffer.limit())
        output.flip()
        synchronized(lock) {
            heardRate = format.sampleRate
            for (sample in heard) {
                ring[(written % RING).toInt()] = sample
                written++
            }
            if (cutting) {
                // As over the website's 1024 samples.
                sideEnergy = side2 * 1024 / frames
                midEnergy = mid2 * 1024 / frames
            } else {
                sideEnergy = 0.0
                midEnergy = 0.0
            }
        }
    }

    // The 2048 samples heard a fifth of a second before the last one made: this runs about the output's buffer ahead
    // of the speaker. False before there's enough.
    fun lastHeard(into: FloatArray): Boolean = synchronized(lock) {
        val lag = minOf((heardRate * LAG_SEC).toLong(), (RING - into.size).toLong())
        val end = written - lag
        if (end < into.size) return false
        val start = end - into.size
        for (i in into.indices) into[i] = ring[((start + i) % RING).toInt()]
        true
    }

    fun nearlyMono(): Boolean? = synchronized(lock) { nearlyMono(sideEnergy, midEnergy) }

    override fun onReset() {
        synchronized(lock) {
            written = 0
            sideEnergy = 0.0
            midEnergy = 0.0
        }
    }

    private companion object {
        const val RING = 32_768
        const val LAG_SEC = 0.2
    }
}
