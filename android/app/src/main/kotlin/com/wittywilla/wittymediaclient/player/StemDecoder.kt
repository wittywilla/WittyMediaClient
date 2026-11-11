// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaDataSource
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.locks.LockSupport

// One part of a song, decoded on a thread of its own into its window (StemRules.kt), a few seconds ahead of where the
// mixer is. The mixer says which frame it needs and at what sample rate; this keeps the window filled from there,
// seeks when the song does, and stops decoding when the window is full. It never plays anything itself.

// The part's file, read from the server with the app's own connection: the sign-in goes in a header, to this server
// only, as for every other request. Read mostly from front to back, with a new request when the reader jumps.
private class ServerFile(private val http: OkHttpClient, private val url: String) : MediaDataSource() {
    private var call: Call? = null
    private var response: Response? = null
    private var stream: InputStream? = null
    private var at = -1L
    private var length = -1L

    @Volatile
    private var closed = false

    private fun open(from: Long) {
        shut()
        val request = Request.Builder().url(url).apply { if (from > 0) header("Range", "bytes=$from-") }.build()
        val made = http.newCall(request)
        call = made
        val answer = made.execute()
        if (!answer.isSuccessful || (from > 0 && answer.code != 206)) {
            val code = answer.code
            answer.close()
            throw IOException("The part wasn't sent ($code).")
        }
        response = answer
        stream = answer.body.byteStream()
        at = from
        if (length < 0) {
            // "bytes 100-199/2000", or the whole length when it's sent from the start.
            length = answer.header("Content-Range")?.substringAfter('/')?.toLongOrNull() ?: if (from == 0L) answer.body.contentLength() else -1L
        }
    }

    private fun shut() {
        runCatching { response?.close() }
        response = null
        stream = null
        call = null
        at = -1
    }

    @Synchronized
    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (closed) throw IOException("closed")
        if (size == 0) return 0
        if (length in 0..position) return -1
        val gap = position - at
        if (stream == null || gap < 0 || gap > SKIP_MOST) open(position) else if (gap > 0) skip(gap)
        val input = stream ?: throw IOException("closed")
        var got = 0
        // As much as was asked for, where it can be had: a short read costs the reader another call.
        while (got < size) {
            val n = input.read(buffer, offset + got, size - got)
            if (n < 0) break
            got += n
        }
        at += got
        return if (got == 0) -1 else got
    }

    private fun skip(bytes: Long) {
        val input = stream ?: return
        var left = bytes
        val scratch = ByteArray(8 * 1024)
        while (left > 0) {
            val n = input.read(scratch, 0, minOf(left, scratch.size.toLong()).toInt())
            if (n < 0) throw IOException("The part ended early.")
            left -= n
        }
        at += bytes
    }

    @Synchronized
    override fun getSize(): Long {
        if (length < 0 && !closed) runCatching { open(0) }
        return length
    }

    // From another thread, to end a read that's waiting on the network.
    fun abort() {
        closed = true
        runCatching { call?.cancel() }
    }

    @Synchronized
    override fun close() {
        closed = true
        shut()
    }

    private companion object {
        // Reading on past a small gap is quicker than asking again.
        const val SKIP_MOST = 64L * 1024
    }
}

class StemDecoder(
    private val http: OkHttpClient,
    private val url: String,
    // Which audio track of the file: 0 for a part in a file of its own.
    private val track: Int,
    val window: StemWindow,
    private val failed: (String) -> Unit,
) {
    @Volatile
    private var need = -1L

    @Volatile
    private var rate = 0

    @Volatile
    private var closed = false
    private var file: ServerFile? = null
    private val thread = Thread({ work() }, "stem-decoder")

    fun start() {
        thread.isDaemon = true
        thread.priority = Thread.NORM_PRIORITY - 1
        thread.start()
    }

    // The mixer, on the player's thread: the frame it's at, at the song's sample rate. Cheap, and never waits.
    fun want(frame: Long, sampleRate: Int) {
        rate = sampleRate
        need = frame
        LockSupport.unpark(thread)
    }

    fun close() {
        closed = true
        file?.abort()
        LockSupport.unpark(thread)
    }

    // What the decoder is in the middle of.
    private var extractor: MediaExtractor? = null
    private var codec: MediaCodec? = null
    private val info = MediaCodec.BufferInfo()
    private var sourceRate = 0
    private var sourceChannels = 2
    private var sourceEncoding = AudioFormat.ENCODING_PCM_16BIT
    private var raw = false // already PCM (a WAV): read as it is, with no codec
    private var inputDone = false
    private var outputDone = false
    private var cursor = -1L // the number, in the song's frames, of the next frame to come out; -1 until a seek lands
    private var outRate = 0
    private var resampler: StemResampler? = null
    private var pcm = ShortArray(0)
    private var resampled = ShortArray(0)
    private var rawBuffer: ByteBuffer? = null

    private fun work() {
        try {
            open()
            while (!closed) {
                val wantRate = rate
                val wantFrame = need
                if (wantRate <= 0 || wantFrame < 0) {
                    LockSupport.parkNanos(IDLE_NS)
                    continue
                }
                if (wantRate != outRate) retune(wantRate, wantFrame)
                window.forget(wantFrame)
                when (val step = window.step(wantFrame, wantRate * AHEAD_SEC, wantRate * JUMP_SEC)) {
                    DecodeStep.Idle -> LockSupport.parkNanos(IDLE_NS)
                    is DecodeStep.Seek -> seek(step.to)
                    DecodeStep.Decode -> if (outputDone) window.finish() else pump()
                }
            }
        } catch (e: Exception) {
            if (!closed) failed(e.message ?: e.javaClass.simpleName)
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor?.release() }
            runCatching { file?.close() }
        }
    }

    private fun open() {
        val source = ServerFile(http, url)
        file = source
        val made = MediaExtractor()
        extractor = made
        made.setDataSource(source)
        val audio = (0 until made.trackCount).filter { made.getTrackFormat(it).getString(MediaFormat.KEY_MIME).orEmpty().startsWith("audio/") }
        val index = audio.getOrNull(track) ?: throw IOException("This file has no such part.")
        val format = made.getTrackFormat(index)
        made.selectTrack(index)
        val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
        sourceRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        sourceChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        if (mime == MediaFormat.MIMETYPE_AUDIO_RAW) {
            raw = true
            sourceEncoding = if (Build.VERSION.SDK_INT >= 24 && format.containsKey(MediaFormat.KEY_PCM_ENCODING)) format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
            rawBuffer = ByteBuffer.allocateDirect(RAW_CHUNK).order(ByteOrder.nativeOrder())
        } else {
            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
        }
        if (sourceRate <= 0 || sourceChannels <= 0) throw IOException("This part's sound can't be read.")
    }

    // The song's sample rate is known (or changed): everything decoded so far was numbered for another.
    private fun retune(newRate: Int, at: Long) {
        outRate = newRate
        resampler = if (sourceRate == newRate) null else StemResampler(sourceRate, newRate)
        seek(at)
    }

    private fun seek(frame: Long) {
        val media = extractor ?: return
        media.seekTo(StemRules.usAt(frame, outRate), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        runCatching { codec?.flush() }
        inputDone = false
        outputDone = false
        cursor = -1
        resampler?.reset()
        window.reset(frame)
    }

    // One turn: a piece of the file in, and whatever sound is ready out.
    private fun pump() {
        if (raw) {
            pumpRaw()
            return
        }
        val decoder = codec ?: return
        val media = extractor ?: return
        if (!inputDone) {
            val slot = decoder.dequeueInputBuffer(WAIT_US)
            if (slot >= 0) {
                val buffer = decoder.getInputBuffer(slot) ?: throw IOException("The decoder gave no room.")
                val size = media.readSampleData(buffer, 0)
                if (size < 0) {
                    decoder.queueInputBuffer(slot, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    inputDone = true
                } else {
                    decoder.queueInputBuffer(slot, 0, size, media.sampleTime, 0)
                    media.advance()
                }
            }
        }
        val out = decoder.dequeueOutputBuffer(info, WAIT_US)
        when {
            out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                val format = decoder.outputFormat
                val newRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                sourceChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                sourceEncoding = if (Build.VERSION.SDK_INT >= 24 && format.containsKey(MediaFormat.KEY_PCM_ENCODING)) format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                // The decoder's own word on the rate wins over the file's (HE-AAC says half in its header).
                if (newRate != sourceRate) {
                    sourceRate = newRate
                    resampler = if (sourceRate == outRate) null else StemResampler(sourceRate, outRate)
                }
            }
            out >= 0 -> {
                val buffer = decoder.getOutputBuffer(out)
                if (buffer != null && info.size > 0) {
                    buffer.position(info.offset).limit(info.offset + info.size)
                    deliver(buffer.order(ByteOrder.nativeOrder()), info.presentationTimeUs)
                }
                decoder.releaseOutputBuffer(out, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    outputDone = true
                    window.finish()
                }
            }
        }
    }

    private fun pumpRaw() {
        val media = extractor ?: return
        val buffer = rawBuffer ?: return
        buffer.clear()
        val size = media.readSampleData(buffer, 0)
        if (size < 0) {
            outputDone = true
            window.finish()
            return
        }
        val time = media.sampleTime
        media.advance()
        buffer.position(0).limit(size)
        deliver(buffer, time)
    }

    // Decoded sound, whatever its shape, into the window as two channels of 16 bits at the song's rate, each frame
    // under its number in the song.
    private fun deliver(sound: ByteBuffer, timeUs: Long) {
        val bytes = when (sourceEncoding) {
            AudioFormat.ENCODING_PCM_FLOAT, ENCODING_32BIT -> 4
            ENCODING_24BIT -> 3
            AudioFormat.ENCODING_PCM_8BIT -> 1
            else -> 2
        }
        val frames = sound.remaining() / (bytes * sourceChannels)
        if (frames <= 0) return
        if (pcm.size < frames * 2) pcm = ShortArray(frames * 2)
        for (i in 0 until frames) {
            var left = 0
            var right = 0
            for (c in 0 until sourceChannels) {
                val sample = when (sourceEncoding) {
                    AudioFormat.ENCODING_PCM_FLOAT -> (sound.float * 32767f).toInt().coerceIn(-32768, 32767)
                    ENCODING_32BIT -> sound.int shr 16
                    ENCODING_24BIT -> {
                        val a = sound.get().toInt() and 0xff
                        val b = sound.get().toInt() and 0xff
                        val c2 = sound.get().toInt()
                        if (sound.order() == ByteOrder.LITTLE_ENDIAN) (c2 shl 8) or b else (a.toByte().toInt() shl 8) or b
                    }
                    AudioFormat.ENCODING_PCM_8BIT -> ((sound.get().toInt() and 0xff) - 128) shl 8
                    else -> sound.short.toInt()
                }
                // The first two channels are left and right; a part with more keeps to those.
                if (c == 0) left = sample
                if (c == 1) right = sample
            }
            if (sourceChannels == 1) right = left
            pcm[i * 2] = left.toShort()
            pcm[i * 2 + 1] = right.toShort()
        }
        // Where this piece starts, in the song's frames: said by its time the first time after a seek, counted after.
        if (cursor < 0) cursor = StemRules.frameAt(timeUs, outRate)
        val shaper = resampler
        if (shaper == null) {
            put(pcm, frames)
        } else {
            val most = shaper.most(frames)
            if (resampled.size < most * 2) resampled = ShortArray(most * 2)
            put(resampled, shaper.run(pcm, frames, resampled))
        }
    }

    // Into the window after its last frame: what came before the place asked for is dropped, a short gap after it is
    // silence, and when the window is full this waits for the mixer to move on, or to ask for somewhere else.
    private fun put(sound: ShortArray, frames: Int) {
        var from = 0
        var left = frames
        val next = window.next
        if (cursor < next) {
            val drop = minOf(left.toLong(), next - cursor).toInt()
            from += drop
            left -= drop
            cursor += drop
        } else if (cursor > next) {
            window.pad((cursor - next).coerceAtMost(window.capacity.toLong()).toInt())
        }
        while (left > 0 && !closed) {
            val went = window.write(sound, from, left)
            from += went
            left -= went
            cursor += went
            if (left == 0) break
            val wanted = need
            window.forget(wanted)
            // The song jumped while this waited: what's left of this piece is for the old place.
            if (window.step(wanted, 1, outRate * JUMP_SEC) is DecodeStep.Seek) return
            if (window.room() == 0) LockSupport.parkNanos(IDLE_NS)
        }
    }

    private companion object {
        const val AHEAD_SEC = 2
        const val JUMP_SEC = 1
        const val IDLE_NS = 15_000_000L
        const val WAIT_US = 5_000L
        const val RAW_CHUNK = 256 * 1024

        // AudioFormat's own names for these arrived in Android 12.
        const val ENCODING_24BIT = 21
        const val ENCODING_32BIT = 22
    }
}
