#if os(tvOS)
import AVFoundation
import CoreMedia
import ImageIO
import Metal
import MetalKit
import VideoToolbox
import WittyKit

// What turns a game's stream into a picture and sound on Apple TV. The server runs the game; this
// only decodes. H.264 goes through VideoToolbox, a JPEG frame through ImageIO, and both are drawn
// with Metal, so the person's picture settings (sharp pixels, scanlines, a curved screen) happen
// here as they do in the browser. Sound is plain PCM into AVAudioEngine.

// MARK: - The picture

/// What the person chose for the picture, from `display.*`, ready for the shader.
struct PictureLook: Equatable {
    var scaling = "sharp"
    var scanlines: Float = 0
    var curve: Float = 0
    var mask: Float = 0
    var vignette: Float = 0
    var lcdGrid: Float = 0
    var brightness: Float = 1
    var contrast: Float = 1
    var saturation: Float = 1
    var gamma: Float = 1
    var cropX: Float = 0
    var cropY: Float = 0

    init() {}

    init(_ s: GameSettings) {
        scaling = s.text("display.scaling", "sharp")
        scanlines = Float(s.number("display.scanlines", 0))
        curve = Float(s.number("display.curve", 0))
        mask = Float(s.number("display.mask", 0))
        vignette = Float(s.number("display.vignette", 0))
        lcdGrid = Float(s.number("display.lcdGrid", 0))
        brightness = Float(s.number("display.brightness", 1))
        contrast = Float(s.number("display.contrast", 1))
        saturation = Float(s.number("display.saturation", 1))
        gamma = Float(s.number("display.gamma", 1))
        cropX = Float(min(0.2, max(0, s.number("display.cropX", 0) / 100)))
        cropY = Float(min(0.2, max(0, s.number("display.cropY", 0) / 100)))
    }
}

/// The shader's uniforms. Laid out as the Metal struct below is.
private struct LookUniforms {
    var rect: SIMD4<Float> = .zero          // left, top, right, bottom in clip space
    var cropMin: SIMD2<Float> = .zero
    var cropMax: SIMD2<Float> = .one
    var source: SIMD2<Float> = .one         // the core's own pixels
    var texture: SIMD2<Float> = .one        // the decoded picture's pixels
    var output: SIMD2<Float> = .one         // the picture's size on screen, in pixels
    var effects: SIMD4<Float> = .zero       // scanlines, curve, mask, vignette
    var colour: SIMD4<Float> = .one         // brightness, contrast, saturation, gamma
    var lcdGrid: Float = 0
    var turns: Int32 = 0
    var sharp: Int32 = 1
    var pad: Int32 = 0
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Look {
    float4 rect; float2 cropMin; float2 cropMax; float2 source; float2 texture; float2 output;
    float4 effects; float4 colour; float lcdGrid; int turns; int sharp; int pad;
};
struct VOut { float4 pos [[position]]; float2 uv; };

vertex VOut game_vertex(uint vid [[vertex_id]], constant Look &look [[buffer(0)]]) {
    float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
    float2 c = corners[vid];
    VOut o;
    o.pos = float4(mix(look.rect.x, look.rect.z, c.x), mix(look.rect.y, look.rect.w, c.y), 0, 1);
    // Turned clockwise: the screen's top right shows the picture's top left.
    float2 uv = c;
    for (int i = 0; i < look.turns; i++) { uv = float2(uv.y, 1.0 - uv.x); }
    o.uv = uv;
    return o;
}

fragment float4 game_fragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]],
                              constant Look &look [[buffer(0)]]) {
    float2 uv = in.uv;
    float curve = look.effects.y;
    if (curve > 0.0) {
        // The glass of an old TV bulges: the picture bends away towards its corners.
        float2 cc = uv * 2.0 - 1.0;
        cc *= 1.0 + curve * 0.18 * dot(cc.yx, cc.yx);
        uv = cc * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return float4(0, 0, 0, 1); }
    }
    float2 t = mix(look.cropMin, look.cropMax, uv);
    if (look.sharp == 1) {
        // Sharp pixels that still scale evenly: each texel is solid, and only its edge blends.
        float2 texel = t * look.texture;
        float2 scale = max(float2(1.0), look.output / max(look.texture * (look.cropMax - look.cropMin), float2(1.0)));
        float2 range = 0.5 - 0.5 / scale;
        float2 d = fract(texel) - 0.5;
        float2 f = (d - clamp(d, -range, range)) * scale + 0.5;
        t = (floor(texel) + f) / look.texture;
    }
    float3 col = tex.sample(smp, t).rgb;
    float4 c = look.colour;
    col = pow(max(col, float3(0.0)), float3(1.0 / max(c.w, 0.1)));
    col = (col - 0.5) * c.y + 0.5;
    col *= c.x;
    float l = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = mix(float3(l), col, c.z);
    float rows = look.source.y;
    if (look.effects.x > 0.0 && rows > 0.0) {
        // Dark lines between the console's own rows.
        float y = fract(t.y * rows);
        float line = 0.5 + 0.5 * cos((y - 0.5) * 6.2831853);
        col *= 1.0 - look.effects.x * (1.0 - line) * 0.9;
    }
    if (look.lcdGrid > 0.0 && rows > 0.0) {
        float2 p = fract(t * look.source);
        float edge = step(0.86, max(p.x, p.y));
        col *= 1.0 - look.lcdGrid * edge * 0.7;
    }
    if (look.effects.z > 0.0) {
        // The red, green and blue stripes of a tube's phosphors, by screen pixel.
        int k = int(in.pos.x) % 3;
        float3 m = k == 0 ? float3(1.0, 0.7, 0.7) : (k == 1 ? float3(0.7, 1.0, 0.7) : float3(0.7, 0.7, 1.0));
        col *= mix(float3(1.0), m * 1.2, look.effects.z);
    }
    if (look.effects.w > 0.0) {
        float2 v = uv * (1.0 - uv.yx);
        float vig = pow(clamp(v.x * v.y * 18.0, 0.0, 1.0), 0.35);
        col *= mix(1.0, vig, look.effects.w);
    }
    return float4(clamp(col, 0.0, 1.0), 1.0);
}
"""

/// Draws the newest frame, as soon as it's decoded, at the person's shape and look. It never waits
/// for a display refresh of its own: a frame goes up the moment it exists.
final class GamePictureRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let nearest: MTLSamplerState
    private let linear: MTLSamplerState
    private var cache: CVMetalTextureCache?
    private let lock = NSLock()
    private var texture: MTLTexture?
    private var holder: CVMetalTexture?
    private(set) var frames = 0

    /// Set from the main thread.
    var look = PictureLook()
    var layout: (settings: GameSettings, aspect: Double, frame: (width: Double, height: Double), turns: Int, inset: Double)
        = (GameSettings(values: [:]), 4.0 / 3.0, (0, 0), 0, 0)

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let describe = MTLRenderPipelineDescriptor()
            describe.vertexFunction = library.makeFunction(name: "game_vertex")
            describe.fragmentFunction = library.makeFunction(name: "game_fragment")
            describe.colorAttachments[0].pixelFormat = view.colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: describe)
        } catch {
            ClientLog.shared.warn("games", "The picture couldn't be set up: \((error as NSError).code)")
            return nil
        }
        let s = MTLSamplerDescriptor()
        s.minFilter = .nearest
        s.magFilter = .nearest
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        guard let n = device.makeSamplerState(descriptor: s) else { return nil }
        s.minFilter = .linear
        s.magFilter = .linear
        guard let l = device.makeSamplerState(descriptor: s) else { return nil }
        nearest = n
        linear = l
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        view.device = device
        view.delegate = self
    }

    /// A decoded H.264 frame, from any thread.
    func show(_ pixels: CVPixelBuffer) {
        guard let cache else { return }
        var made: CVMetalTexture?
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixels, nil, .bgra8Unorm, w, h, 0, &made)
        guard let made, let tex = CVMetalTextureGetTexture(made) else { return }
        lock.lock()
        texture = tex
        holder = made
        frames += 1
        lock.unlock()
    }

    /// A JPEG frame, decoded already, from any thread.
    func show(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                      space: CGColorSpaceCreateDeviceRGB(),
                                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let bytes = context.data else { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: d) else { return }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        lock.lock()
        texture = tex
        holder = nil
        frames += 1
        lock.unlock()
    }

    /// Forgets the picture, for a new game or a new connection.
    func clear() {
        lock.lock()
        texture = nil
        holder = nil
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let tex = texture
        lock.unlock()
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let tex {
            let size = view.drawableSize
            let inset = min(0.45, max(0, layout.inset / 100))
            let box = (width: Double(size.width) * (1 - inset), height: Double(size.height) * (1 - inset))
            let fit = PictureLayout.fit(settings: layout.settings, aspect: layout.aspect, frame: layout.frame, turns: layout.turns, box: box)
            let w = Float(fit.width / Double(size.width)), h = Float(fit.height / Double(size.height))
            var u = LookUniforms()
            u.rect = SIMD4(-w, h, w, -h)
            u.cropMin = SIMD2(look.cropX, look.cropY)
            u.cropMax = SIMD2(1 - look.cropX, 1 - look.cropY)
            let source = layout.frame.width > 0 ? SIMD2(Float(layout.frame.width), Float(layout.frame.height)) : SIMD2(Float(tex.width), Float(tex.height))
            u.source = source
            u.texture = SIMD2(Float(tex.width), Float(tex.height))
            u.output = fit.turns % 2 == 1 ? SIMD2(Float(fit.height), Float(fit.width)) : SIMD2(Float(fit.width), Float(fit.height))
            u.effects = SIMD4(look.scanlines, look.curve, look.mask, look.vignette)
            u.colour = SIMD4(look.brightness, look.contrast, look.saturation, look.gamma)
            u.lcdGrid = look.lcdGrid
            u.turns = Int32(fit.turns)
            u.sharp = look.scaling == "sharp" ? 1 : 0
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&u, length: MemoryLayout<LookUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&u, length: MemoryLayout<LookUniforms>.stride, index: 0)
            encoder.setFragmentTexture(tex, index: 0)
            encoder.setFragmentSamplerState(look.scaling == "pixel" ? nearest : linear, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

// MARK: - H.264

/// Annex B frames into pictures. A new decoder for new parameter sets; until a keyframe has come,
/// nothing is decoded, and a frame that fails asks for the next keyframe.
final class GameVideoDecoder {
    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var sps: Data?
    private var pps: Data?
    private var waitingForKeyframe = true
    let output: (CVPixelBuffer) -> Void
    /// Says the stream needs a keyframe, which the server is told with 0xF7.
    let needKeyframe: () -> Void

    init(output: @escaping (CVPixelBuffer) -> Void, needKeyframe: @escaping () -> Void) {
        self.output = output
        self.needKeyframe = needKeyframe
    }

    deinit { reset() }

    func reset() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        format = nil
        sps = nil
        pps = nil
        waitingForKeyframe = true
    }

    func decode(_ annexB: Data, keyframe: Bool) {
        let frame = AnnexB.frame(annexB)
        if let newSPS = frame.sps, let newPPS = frame.pps, newSPS != sps || newPPS != pps || session == nil {
            makeSession(sps: newSPS, pps: newPPS)
        }
        if keyframe { waitingForKeyframe = false }
        guard !waitingForKeyframe, let session, let format, !frame.picture.isEmpty else { return }
        let avcc = AnnexB.lengthPrefixed(frame.picture)
        var block: CMBlockBuffer?
        let length = avcc.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr,
              let block else { return }
        let copied = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == noErr else { return }
        var sample: CMSampleBuffer?
        var size = length
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                        sampleBufferOut: &sample) == noErr, let sample else { return }
        var info = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: &info) { [weak self] status, _, image, _, _ in
            guard status == noErr, let image else { return }
            self?.output(image)
        }
        if status != noErr {
            // The picture has lost track: wait for a whole one.
            waitingForKeyframe = true
            needKeyframe()
            if status == kVTInvalidSessionErr { reset() }
        }
    }

    private func makeSession(sps: Data, pps: Data) {
        reset()
        var described: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { s in
            pps.withUnsafeBytes { p in
                let pointers = [s.bindMemory(to: UInt8.self).baseAddress!, p.bindMemory(to: UInt8.self).baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: pointers,
                                                                           parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &described)
            }
        }
        guard status == noErr, let described else { return }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        // Apple TV decodes H.264 in hardware by itself.
        var made: VTDecompressionSession?
        guard VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: described, decoderSpecification: nil,
                                           imageBufferAttributes: attributes as CFDictionary, outputCallback: nil, decompressionSessionOut: &made) == noErr,
              let made else { return }
        VTSessionSetProperty(made, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = made
        format = described
        self.sps = sps
        self.pps = pps
        waitingForKeyframe = true
    }
}

/// A JPEG, decoded off the network's thread.
func decodeGameJPEG(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}

// MARK: - Sound

/// PCM as it comes, at whatever rate the console makes it. What's waiting to be played is kept
/// short, by the person's `audio.latency`: past that, a little is left out to catch up, as the
/// browser's player does.
final class GameSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private let lock = NSLock()
    private var queuedFrames = 0
    private let queue = DispatchQueue(label: "wittyplay.sound", qos: .userInteractive)
    var latency = 0.05
    private var started = false

    init() {
        engine.attach(player)
    }

    func setVolume(_ volume: Double, muted: Bool) {
        queue.async { [player] in player.volume = muted ? 0 : Float(min(1, max(0, volume))) }
    }

    func play(_ samples: Data, rate: Int) {
        guard rate >= 8000, rate <= 192_000, samples.count >= 4 else { return }
        queue.async { [weak self] in self?.schedule(samples, rate: rate) }
    }

    private func schedule(_ samples: Data, rate: Int) {
        if format?.sampleRate != Double(rate) {
            guard let fresh = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2) else { return }
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: fresh)
            format = fresh
            lock.lock()
            queuedFrames = 0
            lock.unlock()
        }
        guard let format else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let frames = samples.count / 4
        lock.lock()
        let waiting = Double(queuedFrames) / Double(rate)
        lock.unlock()
        // Behind by more than the person allows: leave this piece out.
        if waiting > latency + Double(frames) / Double(rate) { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                channels[0][i] = Float(Int16(littleEndian: s[2 * i])) / 32768
                channels[1][i] = Float(Int16(littleEndian: s[2 * i + 1])) / 32768
            }
        }
        lock.lock()
        queuedFrames += frames
        lock.unlock()
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.queuedFrames = max(0, self.queuedFrames - frames)
            self.lock.unlock()
        }
        if !player.isPlaying { player.play() }
        started = true
    }

    /// Lets what's waiting go, for a pause or a menu, so nothing old plays after.
    func flush() {
        queue.async { [weak self] in
            guard let self else { return }
            self.player.stop()
            self.lock.lock()
            self.queuedFrames = 0
            self.lock.unlock()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.player.stop()
            self.engine.stop()
        }
    }
}

// MARK: - The connection

/// One WebSocket to a game. Everything that arrives goes to `onMessage` or `onEvent` on the
/// socket's own thread; controller states go out as they come.
final class GameSocket: NSObject, URLSessionWebSocketDelegate {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var closed = false
    var onMessage: (@Sendable (GameStreamMessage) -> Void)?
    var onEvent: (@Sendable (GameEvent) -> Void)?
    /// Called once, when it closes or fails, unless it was closed here.
    var onClose: (@Sendable (String) -> Void)?

    func open(_ request: URLRequest) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        // A keyframe of a big game is more than the usual megabyte.
        task.maximumMessageSize = 32 << 20
        self.session = session
        self.task = task
        task.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .success(.data(let data)):
                if let message = GameStreamMessage.parse(data) { self.onMessage?(message) }
                self.receive()
            case .success(.string(let text)):
                if let event = GameEvent.parse(text) { self.onEvent?(event) }
                self.receive()
            case .success:
                self.receive()
            case .failure(let error):
                self.finish("The connection to the game was lost (\((error as NSError).code)).")
            }
        }
    }

    func send(_ data: Data) {
        guard !closed else { return }
        task?.send(.data(data)) { _ in }
    }

    private func finish(_ why: String) {
        guard !closed else { return }
        closed = true
        onClose?(why)
        session?.invalidateAndCancel()
    }

    func close() {
        guard !closed else { return }
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish("The game's connection closed.")
    }
}
#endif
