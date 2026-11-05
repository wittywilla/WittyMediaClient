import AVFoundation
import Accelerate
import MediaToolbox
import os
import WittyKit

// What happens to the sound between the player and the speakers, as the website's Web Audio graph does it
// (web/src/audio/sound.ts): the voice taken down, the key moved, the equaliser and its level, the volume leveling, and
// a copy of the spectrum for the visualizer. AVPlayer still plays: this is an audio tap on each song, which keeps going
// with the screen locked. Nothing changes the sound until something is turned on.

/// What the taps read on the audio thread, copied at the start of each buffer.
struct SoundShape: Equatable {
    var eqOn = false
    var gains = [Double](repeating: 0, count: 10)
    var preampDb = 0.0
    var loudnessDb = 0.0
    var vocalCut = 0.0
    var keyShift = 0.0
}

/// A second-order filter, with Web Audio's own formulas (the Audio EQ Cookbook), one state per channel.
private struct Biquad {
    enum Kind { case lowpass, highpass, peaking, lowshelf, highshelf }
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var z1 = [0.0, 0.0], z2 = [0.0, 0.0]

    mutating func set(_ kind: Kind, frequency: Double, q: Double, gainDb: Double, rate: Double) {
        let w0 = 2 * Double.pi * min(frequency, rate * 0.49) / rate
        let cosw = cos(w0), sinw = sin(w0)
        let a = pow(10, gainDb / 40)
        var nb0 = 1.0, nb1 = 0.0, nb2 = 0.0, na0 = 1.0, na1 = 0.0, na2 = 0.0
        switch kind {
        case .lowpass, .highpass:
            // Web Audio's Q for these is in dB.
            let alpha = sinw / (2 * pow(10, q / 20))
            if kind == .lowpass {
                nb0 = (1 - cosw) / 2; nb1 = 1 - cosw; nb2 = (1 - cosw) / 2
            } else {
                nb0 = (1 + cosw) / 2; nb1 = -(1 + cosw); nb2 = (1 + cosw) / 2
            }
            na0 = 1 + alpha; na1 = -2 * cosw; na2 = 1 - alpha
        case .peaking:
            let alpha = sinw / (2 * q)
            nb0 = 1 + alpha * a; nb1 = -2 * cosw; nb2 = 1 - alpha * a
            na0 = 1 + alpha / a; na1 = -2 * cosw; na2 = 1 - alpha / a
        case .lowshelf, .highshelf:
            let alpha = sinw / 2 * sqrt(2)
            let k = 2 * sqrt(a) * alpha
            if kind == .lowshelf {
                nb0 = a * ((a + 1) - (a - 1) * cosw + k)
                nb1 = 2 * a * ((a - 1) - (a + 1) * cosw)
                nb2 = a * ((a + 1) - (a - 1) * cosw - k)
                na0 = (a + 1) + (a - 1) * cosw + k
                na1 = -2 * ((a - 1) + (a + 1) * cosw)
                na2 = (a + 1) + (a - 1) * cosw - k
            } else {
                nb0 = a * ((a + 1) + (a - 1) * cosw + k)
                nb1 = -2 * a * ((a - 1) + (a + 1) * cosw)
                nb2 = a * ((a + 1) + (a - 1) * cosw - k)
                na0 = (a + 1) - (a - 1) * cosw + k
                na1 = 2 * ((a - 1) - (a + 1) * cosw)
                na2 = (a + 1) - (a - 1) * cosw - k
            }
        }
        b0 = nb0 / na0; b1 = nb1 / na0; b2 = nb2 / na0; a1 = na1 / na0; a2 = na2 / na0
    }

    @inline(__always) mutating func run(_ x: Double, _ channel: Int) -> Double {
        let y = b0 * x + z1[channel]
        z1[channel] = b1 * x - a1 * y + z2[channel]
        z2[channel] = b2 * x - a2 * y
        return y
    }
}

/// One song's tap: its own filters and delay lines, reading the engine's shape.
final class SoundTap: @unchecked Sendable {
    static let ring = 2048
    private static let grain = 2048.0
    private static let lineSize = 8192

    private unowned let engine: SoundEngine
    private var rate = 44_100.0
    private var usable = false
    private var version = -1
    private var shape = SoundShape()
    private var eq = [Biquad](repeating: Biquad(), count: 10)
    private var sideHigh = Biquad(), bass = Biquad(), air = Biquad()
    // Levels move smoothly to where they're set, as setTargetAtTime does.
    private var wet = 0.0, preamp = 1.0, loudness = 1.0
    private var lines = [[Float]](repeating: [Float](repeating: 0, count: SoundTap.lineSize), count: 2)
    private var write = 0
    private var phase = 0.0
    /// What's heard of each buffer, made ready before the audio starts rather than on its thread.
    private var mono = [Float](repeating: 0, count: 4096)

    // Read by the visualizer and the mono check, under the lock.
    private var lock = os_unfair_lock()
    private var heard = [Float](repeating: 0, count: SoundTap.ring)
    private var heardAt = 0
    private var sideEnergy = 0.0, midEnergy = 0.0

    init(engine: SoundEngine) { self.engine = engine }

    func prepare(_ format: AudioStreamBasicDescription, maxFrames: Int) {
        if maxFrames > mono.count { mono = [Float](repeating: 0, count: maxFrames) }
        rate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        let float = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let separate = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        usable = float && separate && format.mBitsPerChannel == 32 && format.mChannelsPerFrame >= 1 && format.mChannelsPerFrame <= 2
        version = -1
    }

    private func refresh() {
        let (now, at) = engine.current()
        guard at != version else { return }
        version = at
        shape = now
        for (index, frequency) in Equaliser.frequencies.enumerated() {
            let kind: Biquad.Kind = index == 0 ? .lowshelf : index == Equaliser.frequencies.count - 1 ? .highshelf : .peaking
            eq[index].set(kind, frequency: frequency, q: 1.1, gainDb: now.gains[index], rate: rate)
        }
        sideHigh.set(.highpass, frequency: 150, q: 1, gainDb: 0, rate: rate)
        bass.set(.lowpass, frequency: 150, q: 1, gainDb: 0, rate: rate)
        air.set(.highpass, frequency: 9000, q: 1, gainDb: 0, rate: rate)
    }

    private func read(_ line: [Float], _ at: Double) -> Float {
        var p = at.truncatingRemainder(dividingBy: Double(Self.lineSize))
        if p < 0 { p += Double(Self.lineSize) }
        let i = Int(p)
        let f = Float(p - Double(i))
        return line[i] * (1 - f) + line[(i + 1) % Self.lineSize] * f
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard usable, frames > 0, frames <= mono.count else { return }
        refresh()
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) ?? first : first
        let stereo = buffers.count > 1
        let ratio = pow(2, shape.keyShift / 12)
        let shifting = shape.keyShift != 0
        let cutting = shape.vocalCut > 0 || wet > 0.0005
        let wetTarget = shape.vocalCut
        let preTarget = shape.eqOn ? pow(10, shape.preampDb / 20) : 1
        let loudTarget = pow(10, shape.loudnessDb / 20)
        let step = 1 / max(1, rate * 0.05)
        var side2 = 0.0, mid2 = 0.0
        for i in 0..<frames {
            var l = Double(first[i]), r = Double(right[i])
            // The key: two reading points drifting through a short delay, crossfaded (pitch-worklet.js).
            if shifting || phase != 0 {
                let a = phase, b = (phase + Self.grain / 2).truncatingRemainder(dividingBy: Self.grain)
                let ga = Float(0.5 - 0.5 * cos(2 * .pi * a / Self.grain)), gb = Float(0.5 - 0.5 * cos(2 * .pi * b / Self.grain))
                lines[0][write] = Float(l)
                lines[1][write] = Float(r)
                if shifting {
                    l = Double(read(lines[0], Double(write) - a - 1) * ga + read(lines[0], Double(write) - b - 1) * gb)
                    r = Double(read(lines[1], Double(write) - a - 1) * ga + read(lines[1], Double(write) - b - 1) * gb)
                    phase += 1 - ratio
                    if phase >= Self.grain { phase -= Self.grain } else if phase < 0 { phase += Self.grain }
                } else {
                    phase = 0
                }
                write = (write + 1) % Self.lineSize
            }
            // The voice: a singer is mixed in the middle, so left minus right leaves them out; the bass under
            // 150 Hz and some air over 9 kHz go back in.
            if cutting {
                wet += (wetTarget - wet) * step
                let side = 0.7 * l - 0.7 * r
                let middle = (l + r) / 2
                side2 += side * side
                mid2 += middle * middle
                let high = sideHigh.run(side, 0)
                let wl = high + bass.run(l, 0) + air.run(l, 0) * 0.6
                let wr = high + bass.run(r, 1) + air.run(r, 1) * 0.6
                l = l * (1 - wet) + wl * wet
                r = r * (1 - wet) + wr * wet
            }
            if shape.eqOn {
                for band in 0..<eq.count {
                    l = eq[band].run(l, 0)
                    r = eq[band].run(r, 1)
                }
            }
            preamp += (preTarget - preamp) * step
            loudness += (loudTarget - loudness) * step
            l *= preamp * loudness
            r *= preamp * loudness
            first[i] = Float(l)
            if stereo { right[i] = Float(r) }
            mono[i] = Float((l + r) / 2)
        }
        os_unfair_lock_lock(&lock)
        for i in 0..<frames {
            heard[heardAt] = mono[i]
            heardAt = (heardAt + 1) % Self.ring
        }
        if cutting {
            sideEnergy = side2
            midEnergy = mid2
        }
        os_unfair_lock_unlock(&lock)
    }

    /// The last 2048 samples heard, oldest first.
    func lastHeard() -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return Array(heard[heardAt...] + heard[..<heardAt])
    }

    /// Whether there's anything off-centre: close to nothing means it's mono. Nil in silence.
    func nearlyMono() -> Bool? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard midEnergy > 1e-5 else { return nil }
        return sideEnergy / midEnergy < 0.01
    }
}

// The tap's callbacks, which can't hold anything of their own: the tap's storage is its SoundTap.
private func tapInit(_ tap: MTAudioProcessingTap, _ clientInfo: UnsafeMutableRawPointer?, _ storage: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    storage.pointee = clientInfo
}

private func tapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<SoundTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func tapPrepare(_ tap: MTAudioProcessingTap, _ maxFrames: CMItemCount, _ format: UnsafePointer<AudioStreamBasicDescription>) {
    Unmanaged<SoundTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee, maxFrames: Int(maxFrames))
}

private func tapUnprepare(_ tap: MTAudioProcessingTap) {}

private func tapProcess(_ tap: MTAudioProcessingTap, _ frames: CMItemCount, _ flags: MTAudioProcessingTapFlags,
                        _ list: UnsafeMutablePointer<AudioBufferList>, _ framesOut: UnsafeMutablePointer<CMItemCount>,
                        _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    guard MTAudioProcessingTapGetSourceAudio(tap, frames, list, flagsOut, nil, framesOut) == noErr else { return }
    Unmanaged<SoundTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().process(list, frames: Int(framesOut.pointee))
}

/// The sound for the whole app: what the taps do, and which one the visualizer listens to.
final class SoundEngine: @unchecked Sendable {
    static let shared = SoundEngine()

    private var lock = os_unfair_lock()
    private var shape = SoundShape()
    private var version = 0
    private weak var heard: SoundTap?
    // The spectrum, as Web Audio's analyser gives it: 2048 samples, Blackman window, smoothed 0.6, -100 to -30 dB.
    private let fft = vDSP.FFT(log2n: 11, radix: .radix2, ofType: DSPSplitComplex.self)
    private var smoothed = [Float](repeating: 0, count: SoundTap.ring / 2)
    private let window = vDSP.window(ofType: Float.self, usingSequence: .blackman, count: SoundTap.ring, isHalfWindow: false)

    func current() -> (SoundShape, Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (shape, version)
    }

    func set(_ change: (inout SoundShape) -> Void) {
        os_unfair_lock_lock(&lock)
        var next = shape
        change(&next)
        if next != shape {
            shape = next
            version += 1
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Puts a tap on a song. Its tracks are looked at first, which a stream answers quickly.
    @discardableResult
    func attach(to item: AVPlayerItem) async -> SoundTap? {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return nil }
        let state = SoundTap(engine: self)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(state).toOpaque(),
            init: tapInit, finalize: tapFinalize, prepare: tapPrepare, unprepare: tapUnprepare, process: tapProcess)
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else {
            Unmanaged.passUnretained(state).release()
            return nil
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        await MainActor.run { item.audioMix = mix }
        return state
    }

    /// The song the visualizer listens to.
    func listen(to tap: SoundTap?) {
        os_unfair_lock_lock(&lock)
        heard = tap
        os_unfair_lock_unlock(&lock)
    }

    private var listened: SoundTap? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return heard
    }

    /// This moment's levels, 0 to 255, in 1024 bins. False with nothing to read.
    func spectrum(into bins: inout [UInt8]) -> Bool {
        guard let tap = listened, let fft else { return false }
        let samples = vDSP.multiply(tap.lastHeard(), window)
        let half = SoundTap.ring / 2
        var real = [Float](repeating: 0, count: half), imaginary = [Float](repeating: 0, count: half)
        var outReal = [Float](repeating: 0, count: half), outImaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                outReal.withUnsafeMutableBufferPointer { ore in
                    outImaginary.withUnsafeMutableBufferPointer { oim in
                        var input = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                        var output = DSPSplitComplex(realp: ore.baseAddress!, imagp: oim.baseAddress!)
                        samples.withUnsafeBytes { raw in
                            vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &input, 1, vDSP_Length(half))
                        }
                        fft.forward(input: input, output: &output)
                        vDSP.absolute(output, result: &magnitudes)
                    }
                }
            }
        }
        // vDSP's forward transform is twice the textbook one; Web Audio divides by the size.
        let scale = 1 / Float(SoundTap.ring * 2)
        if bins.count != magnitudes.count { bins = [UInt8](repeating: 0, count: magnitudes.count) }
        for k in 0..<magnitudes.count {
            smoothed[k] = 0.6 * smoothed[k] + 0.4 * magnitudes[k] * scale
            let db = 20 * log10(max(smoothed[k], 1e-12))
            bins[k] = UInt8(max(0, min(255, (db + 100) / 70 * 255)))
        }
        return true
    }

    func nearlyMono() -> Bool? { listened?.nearlyMono() }
}
