package com.wittywilla.wittymediaclient.games

import android.content.Context
import android.media.AudioAttributes
import android.os.Handler
import android.os.Looper
import android.view.Surface
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.webrtc.DataChannel
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.EglRenderer
import org.webrtc.GlRectDrawer
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.VideoFrame
import org.webrtc.VideoSink
import org.webrtc.VideoTrack
import org.webrtc.audio.JavaAudioDeviceModule
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

// Version 2 of the game stream over WebRTC (the server's docs/GAMING-STREAM.md), the first choice: late frames are dropped
// rather than waited for, so it's the best on a lossy network. libwebrtc decodes H.264 with MediaCodec and its own audio
// device plays the Opus sound; the picture goes through a VideoSink onto the player's own surface.

// Where a session's version 2 stream is: the server's /api/v1/play/{sid}/stream, which takes a POST (WebRTC) and a
// WebSocket. `rewriteAnswer` is for testing against a stand-in on this machine only, see the debug build's StandInActivity.
data class StreamEndpoint(val url: String, val rewriteAnswer: ((String) -> String)? = null)

// How long to wait before falling back to the WebSocket (docs/GAMING-STREAM.md, "Finding it").
const val ICE_WAIT_MS = 5_000L
const val WEBRTC_PICTURE_MS = 8_000L
private const val GATHER_MS = 1_500L

// One factory, one GL context and one audio device for the app's life: they're slow to make and safe to share.
private object WebRtc {
    @Volatile
    private var made = false
    lateinit var egl: EglBase
    lateinit var factory: PeerConnectionFactory

    @Synchronized
    fun ready(context: Context) {
        if (made) return
        PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context.applicationContext).createInitializationOptions())
        egl = EglBase.create()
        val audio = JavaAudioDeviceModule.builder(context.applicationContext)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setUseHardwareAcousticEchoCanceler(false)
            .setUseHardwareNoiseSuppressor(false)
            .createAudioDeviceModule()
        factory = PeerConnectionFactory.builder()
            .setAudioDeviceModule(audio)
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(egl.eglBaseContext))
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(egl.eglBaseContext, false, false))
            .createPeerConnectionFactory()
        made = true
    }
}

class WebRtcV2Transport(
    context: Context,
    private val api: GamesApi,
    private val endpoint: StreamEndpoint,
    private val hello: StreamHello,
    private val receiver: GameTransport.Receiver,
) : GameTransport {
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val closed = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val shownOnce = AtomicBoolean(false)
    private val pc: PeerConnection
    private val input: DataChannel
    private val events: DataChannel
    private val renderer = EglRenderer("wittyplay")
    private var surface: Surface? = null
    private var video: VideoTrack? = null
    private var sound: org.webrtc.AudioTrack? = null
    private var volume = 1.0

    // Every frame goes to the surface; the first says a picture is showing.
    private val sink = VideoSink { frame: VideoFrame ->
        renderer.onFrame(frame)
        if (shownOnce.compareAndSet(false, true)) receiver.shown()
    }

    init {
        WebRtc.ready(context)
        renderer.init(WebRtc.egl.eglBaseContext, EglBase.CONFIG_PLAIN, GlRectDrawer())
        val config = PeerConnection.RTCConfiguration(emptyList()).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_ONCE
        }
        pc = WebRtc.factory.createPeerConnection(config, Observer()) ?: throw IllegalStateException("No peer connection")
        if (hello.watch) {
            pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
            pc.addTransceiver(MediaStreamTrack.MediaType.MEDIA_TYPE_AUDIO, RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
        }
        input = pc.createDataChannel("input", DataChannel.Init().apply {
            ordered = false
            maxRetransmits = 0
        })
        events = pc.createDataChannel("events", DataChannel.Init().apply { ordered = true })
        events.registerObserver(EventsObserver())
        input.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(previous: Long) {}
            override fun onStateChange() {
                if (input.state() == DataChannel.State.OPEN) receiver.opened()
            }
            override fun onMessage(buffer: DataChannel.Buffer) {}
        })
        offer()
        // No connection in time: the WebSocket takes over.
        main.postDelayed({ if (!connected.get() && !closed.get()) lose("no connection in ${ICE_WAIT_MS / 1000} s") }, ICE_WAIT_MS)
    }

    private fun offer() {
        pc.createOffer(object : Sdp() {
            override fun onCreateSuccess(description: SessionDescription) {
                pc.setLocalDescription(object : Sdp() {
                    override fun onSetSuccess() {
                        // Every candidate in the offer: the server answers with all of its own, so nothing trickles.
                        main.postDelayed({ send() }, GATHER_MS)
                        gatheredEarly = { main.post { send() } }
                    }
                }, description)
            }
        }, MediaConstraints())
    }

    @Volatile
    private var gatheredEarly: (() -> Unit)? = null
    private val sent = AtomicBoolean(false)

    private fun send() {
        if (closed.get() || !sent.compareAndSet(false, true)) return
        val local = pc.localDescription?.description ?: return lose("no offer")
        scope.launch {
            try {
                val body = buildJsonObject {
                    put("hello", hello.toJson(type = false))
                    put("sdp", local)
                }
                val answer = json.parseToJsonElement(api.postStream(endpoint.url, body.toString())) as JsonObject
                val sdp = (answer["sdp"] as? JsonPrimitive)?.content ?: return@launch lose("no answer")
                val shown = endpoint.rewriteAnswer?.invoke(sdp) ?: sdp
                (answer["stream"] as? JsonObject)?.let { stream -> GameEvent.parse(JsonObject(stream + ("type" to JsonPrimitive("stream"))).toString())?.let(receiver::event) }
                pc.setRemoteDescription(object : Sdp() {
                    override fun onSetFailure(error: String?) = lose("the answer was refused: $error")
                }, SessionDescription(SessionDescription.Type.ANSWER, shown))
            } catch (e: com.wittywilla.wittymediaclient.net.ApiError) {
                lose("the server refused WebRTC (${e.status})", e.status)
            } catch (e: Exception) {
                lose("the offer failed: ${e.javaClass.simpleName}")
            }
        }
    }

    private fun lose(why: String, status: Int = 0) {
        if (closed.getAndSet(true)) return
        ClientLog.warn("games", "WebRTC: $why")
        receiver.lost(status)
    }

    override fun attachSurface(surface: Surface?) {
        if (this.surface === surface) return
        if (this.surface != null) renderer.releaseEglSurface {}
        this.surface = surface
        if (surface != null) renderer.createEglSurface(surface)
    }

    override fun setVolume(level: Double, muted: Boolean) {
        volume = if (muted) 0.0 else level.coerceIn(0.0, 1.0)
        runCatching { sound?.setVolume(volume) }
    }

    override fun send(message: ByteArray) {
        if (input.state() == DataChannel.State.OPEN) input.send(DataChannel.Buffer(ByteBuffer.wrap(message), true))
    }

    override fun sendEvent(event: JsonObject) {
        if (events.state() == DataChannel.State.OPEN) events.send(DataChannel.Buffer(ByteBuffer.wrap(event.toString().toByteArray()), false))
    }

    // libwebrtc asks for keyframes itself (PLI) when its decoder loses its place.
    override fun requestKeyframe() {}

    override fun close() {
        closed.set(true)
        main.removeCallbacksAndMessages(null)
        scope.cancel()
        video?.removeSink(sink)
        runCatching { input.unregisterObserver(); events.unregisterObserver() }
        runCatching { pc.close() }
        runCatching { pc.dispose() }
        runCatching { renderer.release() }
    }

    private inner class EventsObserver : DataChannel.Observer {
        override fun onBufferedAmountChange(previous: Long) {}
        override fun onStateChange() {}
        override fun onMessage(buffer: DataChannel.Buffer) {
            if (buffer.binary) return
            val bytes = ByteArray(buffer.data.remaining()).also { buffer.data.get(it) }
            GameEvent.parse(String(bytes))?.let(receiver::event)
        }
    }

    private inner class Observer : PeerConnection.Observer {
        override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
            when (state) {
                PeerConnection.IceConnectionState.CONNECTED, PeerConnection.IceConnectionState.COMPLETED -> connected.set(true)
                PeerConnection.IceConnectionState.FAILED, PeerConnection.IceConnectionState.CLOSED -> if (!closed.get()) lose("ICE $state")
                // A moment's loss on Wi-Fi recovers by itself; a lasting one fails.
                else -> {}
            }
        }

        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
            if (state == PeerConnection.IceGatheringState.COMPLETE) gatheredEarly?.invoke()
        }

        override fun onTrack(transceiver: RtpTransceiver) {
            when (val track = transceiver.receiver.track()) {
                is VideoTrack -> {
                    video = track
                    track.addSink(sink)
                }
                is org.webrtc.AudioTrack -> {
                    sound = track
                    runCatching { track.setVolume(volume) }
                }
            }
        }

        override fun onSignalingChange(state: PeerConnection.SignalingState) {}
        override fun onIceConnectionReceivingChange(receiving: Boolean) {}
        override fun onIceCandidate(candidate: IceCandidate) {}
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
        override fun onAddStream(stream: MediaStream) {}
        override fun onRemoveStream(stream: MediaStream) {}
        override fun onDataChannel(channel: DataChannel) {}
        override fun onRenegotiationNeeded() {}
        override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
    }

    private abstract class Sdp : SdpObserver {
        override fun onCreateSuccess(description: SessionDescription) {}
        override fun onSetSuccess() {}
        override fun onCreateFailure(error: String?) {}
        override fun onSetFailure(error: String?) {}
    }
}

// For testing against a stand-in on this machine from an emulator: the stand-in's candidates say 127.0.0.1, which the
// emulator reaches as 10.0.2.2.
fun rewriteLoopback(sdp: String, to: String): String =
    sdp.lines().joinToString("\r\n") { line ->
        if (line.startsWith("a=candidate:") || line.startsWith("c=IN IP4 127.0.0.1")) line.replace(" 127.0.0.1 ", " $to ").replace("IP4 127.0.0.1", "IP4 $to") else line
    }
