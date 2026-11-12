// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.PlaybackParams
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicReference

// A song's separated parts, played as one sound. Each part is a file on this device, decoded here; ONE thread adds
// them together, frame for frame, into ONE output, so the parts can't move against each other: where they are is a
// count of frames, not a matter of which player started when. The music player itself carries on, unheard, as the
// clock (KaraokeStems keeps this in step with it). Everything but the thread's own loop is safe to call from the
// main thread, and none of it waits.
internal class StemMixer(private val files: List<File>, private val failed: (StemMixer, String) -> Unit) {
    // Where to go, asked for at `atNanos` (System.nanoTime) with the song moving at `speed`, or standing still.
    private class Seek(val us: Long, val atNanos: Long, val moving: Boolean, val speed: Float)

    private val seek = AtomicReference<Seek?>()

    // How loud each part plays, in the files' order, with the app's own volume already in it.
    @Volatile
    var gains = FloatArray(files.size)

    @Volatile
    var speed = 1f

    @Volatile
    var pitch = 1f

    @Volatile
    private var playing = false

    @Volatile
    private var stopped = false

    // Where the sound coming out is in the song, or -1 while that isn't known (before the first sound, and just
    // after a seek).
    @Volatile
    var positionUs = -1L
        private set

    private val thread = Thread(::run, "karaoke-stems")

    fun start() = thread.start()

    // The thread lets go of the decoders and the output itself, within a few hundredths of a second.
    fun stop() {
        stopped = true
    }

    fun play(on: Boolean) {
        playing = on
    }

    fun seekTo(us: Long, moving: Boolean, speed: Float) {
        positionUs = -1
        seek.set(Seek(us.coerceAtLeast(0), System.nanoTime(), moving, speed.coerceAtLeast(0.1f)))
    }

    // One part: its file, its decoder, and what's decoded and not yet played (two channels, side by side, at the
    // mixer's rate). A part may be 16-bit, 24-bit, 32-bit or float, of any channel count and any sample rate: each is
    // folded to two channels and brought to the mixer's rate here.
    private class Stem(file: File) {
        val extractor = MediaExtractor()
        val codec: MediaCodec
        var rate = 0
        private var channels = 0
        private var encoding = AudioFormat.ENCODING_PCM_16BIT
        private val info = MediaCodec.BufferInfo()
        private var inputDone = false
        var outputDone = false
            private set
        var held = ShortArray(CHUNK * 8)
        var count = 0
        private var dropTo = 0L
        private var nextFrame = -1L
        private var resampler = PcmResampler(1, 1)
        private var raw = FloatArray(0)
        private var stereo = FloatArray(0)
        private var resampled = FloatArray(0)

        init {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME).orEmpty().startsWith("audio/") }
                ?: throw IllegalStateException("no audio in a part")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(format, null, null, 0)
            codec.start()
        }

        // The rate the mixer plays at, which this part is brought to.
        fun mixAt(mixRate: Int) {
            resampler = PcmResampler(rate, mixRate)
        }

        // To just before the place, so that the decoder has run in by the time it gets there; what's before the
        // place is thrown away by its frame number at this part's own rate.
        fun seekTo(us: Long) {
            extractor.seekTo((us - RUN_IN_US).coerceAtLeast(0), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            codec.flush()
            inputDone = false
            outputDone = false
            count = 0
            dropTo = PcmMix.frameOf(us, rate)
            nextFrame = -1
            resampler.reset()
        }

        // Decodes until this many samples are held, or the part has ended, or a moment has passed.
        fun fill(samples: Int) {
            var tries = 0
            while (count < samples && !outputDone && tries++ < MOST_TRIES) step()
        }

        private fun step() {
            if (!inputDone) {
                val at = codec.dequeueInputBuffer(WAIT_US)
                if (at >= 0) {
                    val size = extractor.readSampleData(codec.getInputBuffer(at)!!, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(at, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(at, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val at = codec.dequeueOutputBuffer(info, WAIT_US)
            if (at == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val format = codec.outputFormat
                encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                if (PcmMix.bytesPer(encoding) == 0) throw IllegalStateException("a part is decoded as encoding $encoding")
                channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                val now = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                if (now != rate) {
                    // The container said one rate and the decoder gives another: the decoder is right.
                    val to = resampler.to
                    rate = now
                    resampler = PcmResampler(rate, to)
                    if (dropTo > 0) dropTo = PcmMix.frameOf(PcmMix.usOf(dropTo, rate), rate)
                }
                return
            }
            if (at < 0) return
            if (info.size > 0) {
                if (channels < 1) throw IllegalStateException("a part has no channels")
                val buffer = codec.getOutputBuffer(at)!!
                buffer.position(info.offset).limit(info.offset + info.size)
                buffer.order(ByteOrder.nativeOrder())
                val frames = info.size / (PcmMix.bytesPer(encoding) * channels)
                if (nextFrame < 0) nextFrame = PcmMix.frameOf(info.presentationTimeUs, rate)
                val drop = PcmMix.toDrop(nextFrame, dropTo, frames)
                nextFrame += frames
                val keep = frames - drop
                if (keep > 0) {
                    if (raw.size < keep * channels) raw = FloatArray(keep * channels)
                    if (stereo.size < keep * 2) stereo = FloatArray(keep * 2)
                    buffer.position(info.offset + drop * channels * PcmMix.bytesPer(encoding))
                    PcmMix.read(buffer, encoding, raw, keep * channels)
                    PcmMix.fold(raw, keep, channels, stereo)
                    val most = resampler.most(keep)
                    if (resampled.size < most * 2) resampled = FloatArray(most * 2)
                    val made = resampler.run(stereo, keep, resampled)
                    if (count + made * 2 > held.size) held = held.copyOf(maxOf(held.size * 2, count + made * 2))
                    for (i in 0 until made * 2) held[count + i] = PcmMix.toShort(resampled[i])
                    count += made * 2
                }
            }
            codec.releaseOutputBuffer(at, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
        }

        fun played(samples: Int) {
            System.arraycopy(held, samples, held, 0, count - samples)
            count -= samples
        }

        fun release() {
            runCatching { codec.stop() }
            runCatching { codec.release() }
            runCatching { extractor.release() }
        }
    }

    private fun run() {
        val stems = ArrayList<Stem>()
        var track: AudioTrack? = null
        try {
            files.forEach { stems += Stem(it) }
            // The parts play at the highest rate among them; the others are brought up to it.
            val rate = stems.maxOf { it.rate }
            stems.forEach { it.mixAt(rate) }
            val out = openOutput(rate)
            track = out
            // The app's own equaliser, its level and the volume leveling, as the music player has them (SoundShaper).
            val shaper = SoundShaper()
            shaper.configure(androidx.media3.common.audio.AudioProcessor.AudioFormat(rate, 2, androidx.media3.common.C.ENCODING_PCM_16BIT))
            shaper.flush()
            val bytes = java.nio.ByteBuffer.allocateDirect(CHUNK * 4).order(ByteOrder.nativeOrder())
            val mixed = ShortArray(CHUNK * 2)
            val stamp = AudioTimestamp()
            var sounding = false
            var base = 0L // the song's frame at the output's frame 0
            var written = 0L
            var cleanSince = System.nanoTime()
            var last: FloatArray? = null
            var setSpeed = 1f
            var setPitch = 1f
            while (!stopped) {
                seek.getAndSet(null)?.let { to ->
                    if (sounding) out.pause()
                    sounding = false
                    out.flush()
                    // A song that's moving has moved on since this was asked for, and will have moved a little more
                    // by the time the decoders are ready: aim ahead, then wait for the moment.
                    var us = to.us
                    if (to.moving) us += ((System.nanoTime() - to.atNanos) / 1000 * to.speed).toLong() + (LEAD_US * to.speed).toLong()
                    val target = PcmMix.frameOf(us, rate)
                    stems.forEach { it.seekTo(us) }
                    shaper.flush()
                    stems.forEach { it.fill(CHUNK * 2) }
                    if (to.moving) {
                        val due = to.atNanos + ((us - to.us) * 1000 / to.speed).toLong()
                        while (!stopped && seek.get() == null) {
                            val left = due - System.nanoTime()
                            if (left <= 0 || left > MOST_WAIT_NS) break
                            Thread.sleep(minOf(left / 1_000_000, 10L).coerceAtLeast(1))
                        }
                    }
                    base = target
                    written = 0
                    cleanSince = System.nanoTime()
                    last = null
                }
                val wantSpeed = speed
                val wantPitch = pitch
                if (wantSpeed != setSpeed || wantPitch != setPitch) {
                    // The player's own speed and the karaoke key, as the output's own.
                    out.playbackParams = PlaybackParams().setSpeed(wantSpeed).setPitch(wantPitch)
                    setSpeed = wantSpeed
                    setPitch = wantPitch
                }
                if (!playing) {
                    if (sounding) out.pause()
                    sounding = false
                    Thread.sleep(IDLE_MS)
                    continue
                }
                stems.forEach { it.fill(CHUNK * 2) }
                val frames = minOf(CHUNK, stems.minOf { it.count } / 2)
                if (frames == 0) {
                    // The end of the song, or a decoder taking its time.
                    Thread.sleep(if (stems.any { it.outputDone }) IDLE_MS else 2)
                    continue
                }
                val now = gains
                if (now.size != stems.size) throw IllegalStateException("levels for other parts")
                PcmMix.mix(stems.map { it.held }, last ?: now, now, mixed, frames, 2)
                last = now
                stems.forEach { it.played(frames * 2) }
                if (!sounding) {
                    out.play()
                    sounding = true
                }
                bytes.clear()
                bytes.asShortBuffer().put(mixed, 0, frames * 2)
                bytes.limit(frames * 4)
                shaper.queueInput(bytes)
                val shaped = shaper.output
                while (shaped.hasRemaining() && !stopped) {
                    val wrote = out.write(shaped, shaped.remaining(), AudioTrack.WRITE_BLOCKING)
                    if (wrote < 0) throw IllegalStateException("the output refused the sound ($wrote)")
                }
                written += frames
                // What's being heard: the output's own word for it where it has one since the last seek, or else
                // what it has taken.
                val heard = if (out.getTimestamp(stamp) && stamp.nanoTime > cleanSince && stamp.framePosition in 1..written) {
                    stamp.framePosition + ((System.nanoTime() - stamp.nanoTime) / 1e9 * rate * setSpeed).toLong()
                } else out.playbackHeadPosition.toLong() and 0xFFFFFFFFL
                positionUs = PcmMix.usOf(base + heard.coerceAtMost(written), rate)
            }
        } catch (e: Throwable) {
            if (!stopped) {
                stopped = true
                failed(this, "${e.javaClass.simpleName} ${e.message.orEmpty()}")
            }
        } finally {
            positionUs = -1
            stems.forEach { it.release() }
            track?.let { runCatching { it.pause(); it.flush() }; runCatching { it.release() } }
        }
    }

    // The output: as little held in it as the device allows, as what it holds is how long a slider takes to be heard.
    private fun openOutput(rate: Int): AudioTrack {
        val least = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        if (least <= 0) throw IllegalStateException("no output at $rate")
        val size = maxOf(least, rate / 1000 * HELD_MS * 4)
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
        val format = AudioFormat.Builder().setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
        val out = if (android.os.Build.VERSION.SDK_INT >= 26) {
            AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(format).setBufferSizeInBytes(size)
                .setTransferMode(AudioTrack.MODE_STREAM).setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY).build()
        } else {
            AudioTrack(attributes, format, size, AudioTrack.MODE_STREAM, AudioManager.AUDIO_SESSION_ID_GENERATE)
        }
        if (out.state != AudioTrack.STATE_INITIALIZED) {
            out.release()
            throw IllegalStateException("the output didn't open")
        }
        return out
    }

    private companion object {
        // About two hundredths of a second of sound mixed at a time, and a tenth held by the output: less ran short on
        // a busy emulator, more is a slider heard late.
        const val CHUNK = 1024
        const val HELD_MS = 100
        const val WAIT_US = 2000L
        const val MOST_TRIES = 200
        const val RUN_IN_US = 100_000L
        const val LEAD_US = 60_000L
        const val MOST_WAIT_NS = 1_000_000_000L
        const val IDLE_MS = 15L
    }
}
