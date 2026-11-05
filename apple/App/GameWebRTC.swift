import AVFoundation
import CoreVideo
import Foundation
import LiveKitWebRTC
import VideoToolbox
import WittyKit

// The server's second stream over WebRTC (WittyMediaServer docs/GAMING-STREAM.md): one
// `POST /play/{sid}/stream` with the hello and the offer; receive-only video and sound; data
// channels `input` (unordered, never resent, binary) and `events` (reliable, JSON both ways).
// libwebrtc is LiveKit's build of it, whose classes start LKRTC. It decodes the picture itself, in
// hardware; frames go to the player's own Metal path, so the person's display settings still apply.
// It plays the sound itself too, through playback only: a game never needs the microphone.

final class GameWebRTCTransport: NSObject, GameTransport, @unchecked Sendable {
    var onMessage: (@Sendable (GameStreamMessage) -> Void)?
    var onEvent: (@Sendable (GameEvent) -> Void)?
    var onEnd: (@Sendable (GameTransportEnd) -> Void)?

    private let offer: URLRequest
    private let hello: GameHello
    private var peer: LKRTCPeerConnection?
    private var input: LKRTCDataChannel?
    private var events: LKRTCDataChannel?
    private var videoTrack: LKRTCVideoTrack?
    private var audioTrack: LKRTCAudioTrack?
    private let lock = NSLock()
    private var closed = false
    private var sentOffer = false
    private var connectedOnce = false
    private var volume: (level: Double, muted: Bool) = (1, false)
    private let frames = PixelsToBGRA()

    init(offer: URLRequest, hello: GameHello) {
        self.offer = offer
        self.hello = hello
    }

    /// One factory for every game: libwebrtc's threads and codecs are made once.
    private static let factory: LKRTCPeerConnectionFactory = {
        #if !os(macOS)
        // Sound to play, never to record: no microphone, no voice processing, heard with the silent switch on.
        let config = LKRTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playback.rawValue
        config.categoryOptions = []
        config.mode = AVAudioSession.Mode.default.rawValue
        LKRTCAudioSessionConfiguration.setWebRTC(config)
        #endif
        return LKRTCPeerConnectionFactory(audioDeviceModuleType: .audioEngine, bypassVoiceProcessing: true,
                                          encoderFactory: LKRTCDefaultVideoEncoderFactory(), decoderFactory: LKRTCDefaultVideoDecoderFactory(),
                                          audioProcessingModule: nil)
    }()

    private var isClosed: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }

    /// True the first time only.
    private func markClosed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if closed { return false }
        closed = true
        return true
    }

    func open() {
        let config = LKRTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.continualGatheringPolicy = .gatherOnce
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            finish(.unreachable)
            return
        }
        self.peer = peer
        let receive = LKRTCRtpTransceiverInit()
        receive.direction = .recvOnly
        peer.addTransceiver(of: .video, init: receive)
        peer.addTransceiver(of: .audio, init: receive)
        let unordered = LKRTCDataChannelConfiguration()
        unordered.isOrdered = false
        unordered.maxRetransmits = 0
        input = peer.dataChannel(forLabel: "input", configuration: unordered)
        events = peer.dataChannel(forLabel: "events", configuration: LKRTCDataChannelConfiguration())
        input?.delegate = self
        events?.delegate = self
        peer.offer(for: constraints) { [weak self] sdp, _ in
            guard let self, let sdp, !self.isClosed else {
                self?.finish(.unreachable)
                return
            }
            peer.setLocalDescription(sdp) { [weak self] error in
                guard let self else { return }
                if error != nil { self.finish(.unreachable); return }
                // Every candidate goes in the one offer. Gathering is quick at home; it's not waited on for long.
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in self?.sendOffer() }
            }
        }
        // No connection within 5 seconds of the offer (gathered for up to 2): the WebSocket instead.
        DispatchQueue.global().asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, !self.isClosed, !self.connectedOnce else { return }
            self.finish(.unreachable)
        }
    }

    /// The offer, once, with the candidates gathered, and the answer back.
    private func sendOffer() {
        lock.lock()
        if sentOffer || closed {
            lock.unlock()
            return
        }
        sentOffer = true
        lock.unlock()
        guard let peer, let local = peer.localDescription else { return finish(.unreachable) }
        var request = offer
        request.httpBody = GameStreamOffer.body(hello: hello, sdp: local.sdp)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self, !self.isClosed else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data, let answer = GameStreamOffer.answer(data) else {
                self.finish(GameStreamOffer.end(status: status))
                return
            }
            peer.setRemoteDescription(LKRTCSessionDescription(type: .answer, sdp: answer.sdp)) { [weak self] error in
                guard let self else { return }
                if error != nil { self.finish(.unreachable); return }
                self.takeTracks()
            }
        }.resume()
    }

    /// The picture to the player; the sound at the person's volume.
    private func takeTracks() {
        guard let peer else { return }
        for transceiver in peer.transceivers {
            if let track = transceiver.receiver.track as? LKRTCVideoTrack, videoTrack == nil {
                videoTrack = track
                track.add(self)
            } else if let track = transceiver.receiver.track as? LKRTCAudioTrack, audioTrack == nil {
                audioTrack = track
                applyVolume()
            }
        }
    }

    func sendInput(_ data: Data) {
        guard !isClosed, let input, input.readyState == .open else { return }
        input.sendData(LKRTCDataBuffer(data: data, isBinary: true))
    }

    func sendEvent(_ text: String) {
        guard !isClosed, let events, events.readyState == .open else { return }
        events.sendData(LKRTCDataBuffer(data: Data(text.utf8), isBinary: false))
    }

    /// libwebrtc asks for keyframes itself.
    func askKeyframe() {}

    func setVolume(_ level: Double, muted: Bool) {
        volume = (level, muted)
        applyVolume()
    }

    private func applyVolume() {
        // A gain from 0 to 10, where 1 is as it came.
        audioTrack?.source.volume = volume.muted ? 0 : max(0, min(1, volume.level))
    }

    private func finish(_ end: GameTransportEnd) {
        guard markClosed() else { return }
        tearDown()
        onEnd?(end)
    }

    func close() {
        guard markClosed() else { return }
        tearDown()
    }

    private func tearDown() {
        videoTrack?.remove(self)
        input?.close()
        events?.close()
        peer?.close()
    }
}

extension GameWebRTCTransport: LKRTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        if newState == .complete { sendOffer() }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        switch newState {
        case .connected, .completed:
            connectedOnce = true
        case .failed:
            // Before it ever connected, another way; after, a dropped connection the game waits for.
            finish(connectedOnce ? .dropped : .unreachable)
        default:
            break
        }
    }
}

extension GameWebRTCTransport: LKRTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {}

    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        if buffer.isBinary {
            // Timing answers and frame records, as on the WebSocket.
            if let message = GameStreamMessage.parse(buffer.data) { onMessage?(message) }
        } else if let event = GameEvent.parse(String(decoding: buffer.data, as: UTF8.self)) {
            onEvent?(event)
        }
    }
}

extension GameWebRTCTransport: LKRTCVideoRenderer {
    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: LKRTCVideoFrame?) {
        guard !isClosed, let frame, let buffer = frame.buffer as? LKRTCCVPixelBuffer,
              let pixels = frames.bgra(buffer.pixelBuffer) else { return }
        onMessage?(.picture(pixels))
    }
}

/// libwebrtc's hardware decoder gives NV12; the player's Metal path draws BGRA.
final class PixelsToBGRA {
    private var session: VTPixelTransferSession?
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)

    func bgra(_ pixels: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA { return pixels }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        if pool == nil || poolSize != (width, height) {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            poolSize = (width, height)
        }
        if session == nil { VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session) }
        guard let pool, let session else { return nil }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let out,
              VTPixelTransferSessionTransferImage(session, from: pixels, to: out) == noErr else { return nil }
        return out
    }
}
