package com.wittywilla.wittymediaclient.games

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Rect
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import com.wittywilla.wittymediaclient.diag.ClientLog
import java.nio.ByteBuffer
import java.util.ArrayDeque

// The picture and the sound, on this device. Latency is the point (the server's docs/GAMING-API.md, "Modes"):
// a frame goes to the decoder the moment it arrives and to the screen the moment it's decoded, nothing waits to
// smooth anything out, and sound that falls behind is dropped rather than played late.

private const val AVC = "video/avc"

// Frames waiting for the decoder. More than this and the stream is behind: drop them and carry on from the next
// keyframe, as the server does when this device falls behind.
private const val MOST_WAITING = 3

// H.264 frames from the WebSocket, through MediaCodec, onto a surface. Everything happens on its own thread.
class H264Player(
    // A new picture is on the screen.
    private val onPicture: () -> Unit,
    // The decoder lost its place and needs a keyframe to carry on.
    private val needKeyframe: () -> Unit,
) {
    private val thread = HandlerThread("game-video", android.os.Process.THREAD_PRIORITY_DISPLAY).apply { start() }
    private val handler = Handler(thread.looper)
    private var surface: Surface? = null
    private var codec: MediaCodec? = null
    private var size: Pair<Int, Int>? = null
    private val waiting = ArrayDeque<StreamMessage.Video>()
    private val inputs = ArrayDeque<Int>()
    private var needsKeyframe = true
    private var stamp = 0L
    private var closed = false
    private var failed = false

    // Where the picture goes. Null while there's no screen to draw on, such as in the background.
    fun setSurface(to: Surface?) = handler.post {
        if (surface === to) return@post
        release()
        surface = to
        needsKeyframe = true
        if (to != null) needKeyframe()
    }

    // From the socket's thread.
    fun submit(frame: StreamMessage.Video) {
        handler.post { take(frame) }
    }

    fun close() {
        handler.post {
            closed = true
            release()
            thread.quitSafely()
        }
    }

    private fun take(frame: StreamMessage.Video) {
        if (closed || surface == null) return
        if (needsKeyframe && !frame.keyframe) return
        if (frame.keyframe) startFor(frame)
        if (codec == null) return
        needsKeyframe = false
        waiting.addLast(frame)
        if (waiting.size > MOST_WAITING) {
            waiting.clear()
            needsKeyframe = true
            needKeyframe()
            return
        }
        feed()
    }

    // A keyframe carries its parameter sets: a new size, or no decoder yet, makes a decoder for it.
    private fun startFor(frame: StreamMessage.Video) {
        val units = AnnexB.units(frame.data, frame.offset)
        val sps = units.firstOrNull { AnnexB.type(frame.data, it) == AnnexB.SPS } ?: return
        val pps = units.firstOrNull { AnnexB.type(frame.data, it) == AnnexB.PPS }
        val spsBytes = frame.data.copyOfRange(sps.first, sps.last + 1)
        val shape = AnnexB.spsSize(spsBytes) ?: (640 to 480)
        if (codec != null && shape == size) return
        release()
        val out = surface ?: return
        try {
            val format = MediaFormat.createVideoFormat(AVC, shape.first, shape.second)
            format.setByteBuffer("csd-0", ByteBuffer.wrap(AnnexB.withStartCode(frame.data, sps)))
            if (pps != null) format.setByteBuffer("csd-1", ByteBuffer.wrap(AnnexB.withStartCode(frame.data, pps)))
            // As soon as possible, and nothing held back to reorder: the server sends no B-frames.
            format.setInteger(MediaFormat.KEY_PRIORITY, 0)
            val decoder = MediaCodec.createDecoderByType(AVC)
            if (Build.VERSION.SDK_INT >= 30 && lowLatency(decoder.codecInfo)) format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            // What some chips call it themselves; others ignore keys they don't know.
            format.setInteger("vendor.low-latency.enable", 1)
            format.setInteger("vendor.qti-ext-dec-low-latency.enable", 1)
            decoder.setCallback(object : MediaCodec.Callback() {
                override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
                    if (codec !== this@H264Player.codec) return
                    inputs.addLast(index)
                    feed()
                }

                override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                    if (codec !== this@H264Player.codec) return
                    runCatching { codec.releaseOutputBuffer(index, true) }
                    onPicture()
                }

                override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                    if (codec !== this@H264Player.codec) return
                    ClientLog.warn("games", "The video decoder stopped: ${e.diagnosticInfo}")
                    release()
                    needsKeyframe = true
                    needKeyframe()
                }

                override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {}
            }, handler)
            decoder.configure(format, out, null, 0)
            decoder.start()
            codec = decoder
            size = shape
        } catch (e: Exception) {
            // No picture comes, and the player moves on to a JPEG a frame.
            if (!failed) ClientLog.warn("games", "No H.264 decoder for ${shape.first}x${shape.second}: ${e.javaClass.simpleName}")
            failed = true
            release()
        }
    }

    private fun lowLatency(info: MediaCodecInfo): Boolean = runCatching {
        Build.VERSION.SDK_INT >= 30 && info.getCapabilitiesForType(AVC).isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency)
    }.getOrDefault(false)

    private fun feed() {
        val decoder = codec ?: return
        while (waiting.isNotEmpty() && inputs.isNotEmpty()) {
            val frame = waiting.removeFirst()
            val index = inputs.removeFirst()
            try {
                val buffer = decoder.getInputBuffer(index) ?: continue
                buffer.clear()
                if (buffer.capacity() < frame.size) {
                    // Too big for the decoder's buffers: skip to the next keyframe.
                    decoder.queueInputBuffer(index, 0, 0, stamp, 0)
                    needsKeyframe = true
                    waiting.clear()
                    needKeyframe()
                    return
                }
                buffer.put(frame.data, frame.offset, frame.size)
                stamp += 16_666
                decoder.queueInputBuffer(index, 0, frame.size, stamp, if (frame.keyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
            } catch (e: IllegalStateException) {
                release()
                needsKeyframe = true
                needKeyframe()
                return
            }
        }
    }

    private fun release() {
        val decoder = codec ?: return
        codec = null
        size = null
        inputs.clear()
        waiting.clear()
        runCatching { decoder.stop() }
        runCatching { decoder.release() }
    }
}

// The fallback: a JPEG a frame, drawn straight onto the surface. Only the newest waiting frame is drawn.
class JpegPlayer(private val onPicture: () -> Unit) {
    private val thread = HandlerThread("game-jpeg", android.os.Process.THREAD_PRIORITY_DISPLAY).apply { start() }
    private val handler = Handler(thread.looper)
    private var surface: Surface? = null
    private var newest: StreamMessage.Jpeg? = null
    private var reuse: Bitmap? = null
    private val paint = Paint()
    private val whole = Rect()

    // Sharp scaling keeps an old console's pixels square-edged.
    @Volatile
    var smooth = false

    fun setSurface(to: Surface?) = handler.post { surface = to }

    fun submit(frame: StreamMessage.Jpeg) {
        val first: Boolean
        synchronized(this) {
            first = newest == null
            newest = frame
        }
        if (first) handler.post { draw() }
    }

    fun close() = handler.post {
        surface = null
        thread.quitSafely()
    }

    private fun draw() {
        val frame = synchronized(this) { newest.also { newest = null } } ?: return
        val out = surface ?: return
        val options = BitmapFactory.Options().apply {
            inMutable = true
            inBitmap = reuse
        }
        val picture = runCatching { BitmapFactory.decodeByteArray(frame.data, frame.offset, frame.data.size - frame.offset, options) }.getOrNull()
            ?: runCatching { BitmapFactory.decodeByteArray(frame.data, frame.offset, frame.data.size - frame.offset) }.getOrNull()
            ?: return
        reuse = picture
        val canvas = runCatching { if (Build.VERSION.SDK_INT >= 26) out.lockHardwareCanvas() else out.lockCanvas(null) }.getOrNull() ?: return
        try {
            paint.isFilterBitmap = smooth
            whole.set(0, 0, canvas.width, canvas.height)
            canvas.drawBitmap(picture, null, whole, paint)
        } finally {
            runCatching { out.unlockCanvasAndPost(canvas) }
        }
        onPicture()
    }
}

// Signed 16-bit stereo at the console's own rate, into an AudioTrack kept within the person's audio.latency.
class GameSound(latencySeconds: Double) {
    private var track: AudioTrack? = null
    private var rate = 0
    private var written = 0L
    private var playing = false
    private val most = latencySeconds.coerceIn(0.03, 0.3)

    @Volatile
    private var volume = 1f

    @Volatile
    private var held = false

    fun setVolume(level: Double, muted: Boolean) {
        volume = if (muted) 0f else level.toFloat().coerceIn(0f, 1f)
        track?.setVolume(volume)
    }

    // While the menu is up or the app is away: nothing plays, and what was waiting is let go.
    fun hold(on: Boolean) {
        held = on
        synchronized(this) {
            track?.let {
                runCatching { it.pause() }
                runCatching { it.flush() }
            }
            playing = false
            written = 0
        }
    }

    // From the socket's thread. Never waits: what doesn't fit is dropped.
    fun play(pcm: StreamMessage.Pcm) {
        if (held || pcm.length <= 0 || pcm.rate !in 4000..192000) return
        synchronized(this) {
            val out = trackFor(pcm.rate) ?: return
            val frames = pcm.length / 4
            val queued = written - (out.playbackHeadPosition.toLong() and 0xffffffffL)
            // Too far behind: drop this, so what's heard stays close to what's seen.
            if (playing && queued + frames > most * rate) return
            if (playing && queued <= 0) {
                // Ran dry: start again from here, a little ahead.
                runCatching { out.pause(); out.flush() }
                playing = false
                written = 0
            }
            val n = out.write(pcm.data, pcm.offset, pcm.length, AudioTrack.WRITE_NON_BLOCKING)
            if (n > 0) written += n / 4
            if (!playing && written >= rate * most / 2) {
                runCatching { out.play() }
                playing = true
            }
        }
    }

    private fun trackFor(at: Int): AudioTrack? {
        if (track != null && rate == at) return track
        release()
        rate = at
        val minimum = AudioTrack.getMinBufferSize(at, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val bytes = maxOf(minimum, (at * 4 * most * 2).toInt())
        val made = runCatching {
            val builder = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(at).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                .setBufferSizeInBytes(bytes)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setSessionId(AudioManager.AUDIO_SESSION_ID_GENERATE)
            if (Build.VERSION.SDK_INT >= 26) builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            builder.build()
        }.getOrNull()
        made?.setVolume(volume)
        track = made
        written = 0
        playing = false
        return made
    }

    private fun release() {
        track?.let {
            runCatching { it.pause() }
            runCatching { it.release() }
        }
        track = null
        playing = false
        written = 0
    }

    fun close() = synchronized(this) { release() }
}
