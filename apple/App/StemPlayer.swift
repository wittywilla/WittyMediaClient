// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import AVFoundation
import WittyKit

// A song's separate parts, played together. Each part is a file on this device with its own player in one audio
// engine, and every player is told to start at the same moment from the same place in its file, so the parts stay
// together to the sample. The app's usual player keeps playing, silenced, and is the clock: this follows it.

/// Why the parts couldn't be had.
enum StemTrouble: Error {
    /// Together they are more than this device should be asked to keep.
    case tooBig
    case refused(Int)
    case unreadable

    var words: String {
        switch self {
        case .tooBig: return "This song's karaoke parts are too big for this device, so this is the normal track."
        case .refused, .unreadable: return KaraokeMachine.failedWords
        }
    }
}

/// Fetches the parts into a folder, with the app's own sign-in, and stops as soon as they add up to too much.
final class StemFetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// The most all of a song's parts may come to.
    static let cap: Int64 = 400 * 1024 * 1024

    private let lock = NSLock()
    private var sizes: [Int: Int64] = [:]
    private var targets: [Int: URL] = [:]
    private var troubles: [Int: Error] = [:]
    private var waiting: [Int: CheckedContinuation<Void, Error>] = [:]
    private var tooBig = false
    private var session: URLSession!

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// The session holds on to this until it's told it can go.
    func finish() { session.invalidateAndCancel() }

    /// Every part, side by side. Throws if any of them can't be had; leaving cancels them all.
    static func fetch(_ stems: [KaraokeStem], client: WittyClient, into folder: URL) async throws -> [(id: String, url: URL)] {
        let fetcher = StemFetcher()
        defer { fetcher.finish() }
        var files: [(id: String, url: URL)] = []
        var requests: [(URLRequest, URL)] = []
        for (index, stem) in stems.enumerated() {
            guard let from = client.mediaURL(stem.url) else { throw StemTrouble.unreadable }
            var request = URLRequest(url: from)
            for (name, value) in client.authHeaders { request.setValue(value, forHTTPHeaderField: name) }
            let to = folder.appendingPathComponent("\(index).\(stem.fileExtension)")
            requests.append((request, to))
            files.append((stem.id, to))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (request, to) in requests {
                group.addTask { try await fetcher.one(request, to: to) }
            }
            try await group.waitForAll()
        }
        return files
    }

    private func one(_ request: URLRequest, to target: URL) async throws {
        let task = session.downloadTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                lock.lock()
                targets[task.taskIdentifier] = target
                waiting[task.taskIdentifier] = done
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock()
        sizes[downloadTask.taskIdentifier] = max(totalBytesWritten, totalBytesExpectedToWrite)
        let over = sizes.values.reduce(0, +) > Self.cap
        if over { tooBig = true }
        lock.unlock()
        if over { session.getAllTasks { $0.forEach { $0.cancel() } } }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        let target = targets[downloadTask.taskIdentifier]
        lock.unlock()
        var trouble: Error?
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(status) {
            trouble = StemTrouble.refused(status)
        } else if let target {
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: location, to: target)
            } catch {
                trouble = error
            }
        }
        if let trouble {
            lock.lock()
            troubles[downloadTask.taskIdentifier] = trouble
            lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let done = waiting.removeValue(forKey: task.taskIdentifier)
        let trouble: Error? = tooBig ? StemTrouble.tooBig : (troubles[task.taskIdentifier] ?? error)
        lock.unlock()
        if let trouble { done?.resume(throwing: trouble) } else { done?.resume() }
    }
}

/// The parts of one song, ready to play together.
@MainActor
final class StemPlayer {
    private struct Deck {
        let id: String
        let node: AVAudioPlayerNode
        let file: AVAudioFile
        /// The singer is in this part: Voice settings' pan applies to it.
        let voice: Bool
    }

    /// How far ahead a start is set, so every part has time to be ready for it.
    private static let lead = 0.1

    private let engine = AVAudioEngine()
    private let mix = AVAudioMixerNode()
    private let pitch = AVAudioUnitTimePitch()
    /// The app's equaliser, preamp and volume levelling, as the song's own tap applies them (SoundEngine.swift).
    private let eq = AVAudioUnitEQ(numberOfBands: Equaliser.frequencies.count)
    private var shapeVersion = -1
    /// The song's speed, which the parts follow: 1 is normal.
    private var rate = 1.0
    private var decks: [Deck] = []
    /// Where in the song the parts were at a moment on the device's clock. Nil while they're stopped.
    private var base: (position: Double, host: UInt64)?
    private var changes: NSObjectProtocol?

    // Voice settings (WittyKit's VoiceFx.swift, the website's fxChain.ts): the singer's part goes through its own bus,
    // tone, compression, doubling, echo and reverb before the mix; every other part through the music's bus and its
    // tone. Each unit is bypassed while its control is off, so a song sounds as it was made.
    private let voiceBus = AVAudioMixerNode()
    private let voiceTone = AVAudioUnitEQ(numberOfBands: 4)
    private let squeeze = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let doubling = AVAudioUnitDelay()
    private let echo = AVAudioUnitDelay()
    private let room = AVAudioUnitReverb()
    private var roomShape = -1
    private let musicBus = AVAudioMixerNode()
    private let musicTone = AVAudioUnitEQ(numberOfBands: 3)

    /// Opens every part. Throws if one can't be read, which is the cue to play the normal track. `voice` names the
    /// parts the singer is in: the vocals, or in the quick version the whole song (its voice is what's left without
    /// the music, so Voice settings there are close, not exact).
    init(files: [(id: String, url: URL)], voice: Set<String> = [StemMix.vocalsId]) throws {
        guard !files.isEmpty else { throw StemTrouble.unreadable }
        engine.attach(mix)
        engine.attach(eq)
        engine.attach(pitch)
        for unit in [voiceBus, voiceTone, squeeze, doubling, echo, room, musicBus, musicTone] as [AVAudioNode] { engine.attach(unit) }
        for (index, frequency) in Equaliser.frequencies.enumerated() {
            let band = eq.bands[index]
            band.filterType = index == 0 ? .lowShelf : index == Equaliser.frequencies.count - 1 ? .highShelf : .parametric
            band.frequency = Float(frequency)
            // Q 1.1, as the song's own filters have it, in octaves.
            band.bandwidth = Float(2 * asinh(1 / (2 * 1.1)) / log(2))
            band.gain = 0
            band.bypass = false
        }
        for part in files {
            let file = try AVAudioFile(forReading: part.url)
            guard file.length > 0, file.processingFormat.sampleRate > 0 else { throw StemTrouble.unreadable }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: voice.contains(part.id) ? voiceBus : musicBus, format: file.processingFormat)
            decks.append(Deck(id: part.id, node: node, file: file, voice: voice.contains(part.id)))
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: decks[0].file.processingFormat.sampleRate, channels: 2) else {
            throw StemTrouble.unreadable
        }
        // The voice: its bus, tone, compression, doubling, echo, reverb, then the mix. The music: its bus, its tone, the mix.
        engine.connect(voiceBus, to: voiceTone, format: format)
        engine.connect(voiceTone, to: squeeze, format: format)
        engine.connect(squeeze, to: doubling, format: format)
        engine.connect(doubling, to: echo, format: format)
        engine.connect(echo, to: room, format: format)
        engine.connect(room, to: mix, format: format)
        engine.connect(musicBus, to: musicTone, format: format)
        engine.connect(musicTone, to: mix, format: format)
        let tones: [(AVAudioUnitEQFilterType, Float)] = [(.highPass, 20), (.lowShelf, 200), (.parametric, 3000), (.highShelf, 10000)]
        for (band, tone) in zip(voiceTone.bands, tones) {
            band.filterType = tone.0
            band.frequency = tone.1
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
        let music: [(AVAudioUnitEQFilterType, Float, Float)] = [(.lowShelf, 120, 1), (.highShelf, 6000, 1), (.parametric, 2500, 1.6)]
        for (band, tone) in zip(musicTone.bands, music) {
            band.filterType = tone.0
            band.frequency = tone.1
            band.bandwidth = tone.2
            band.gain = 0
            band.bypass = false
        }
        doubling.delayTime = 0.025
        doubling.feedback = 0
        doubling.lowPassCutoff = 12000
        echo.lowPassCutoff = 9000
        engine.connect(mix, to: eq, format: format)
        engine.connect(eq, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
        pitch.bypass = true
        engine.prepare()
        // Headphones in or out stops the engine: forget where it was, and the next look starts it again.
        changes = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.base = nil }
        }
    }

    /// Starts every part from this place in the song, at one shared moment.
    func play(from position: Double) throws {
        for deck in decks { deck.node.stop() }
        if !engine.isRunning { try engine.start() }
        let host = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: Self.lead)
        let start = max(0, position + Self.lead * rate)
        for deck in decks {
            let rate = deck.file.processingFormat.sampleRate
            let frame = AVAudioFramePosition((start * rate).rounded())
            guard frame < deck.file.length else { continue }
            let count = min(deck.file.length - frame, AVAudioFramePosition(UInt32.max))
            deck.node.scheduleSegment(deck.file, startingFrame: frame, frameCount: AVAudioFrameCount(count), at: nil, completionHandler: nil)
        }
        let when = AVAudioTime(hostTime: host)
        for deck in decks { deck.node.play(at: when) }
        base = (start, host)
    }

    /// Where the parts are in the song. Nil while they're stopped.
    func position() -> Double? {
        guard let base, engine.isRunning else { return nil }
        let now = mach_absolute_time()
        if now >= base.host { return base.position + AVAudioTime.seconds(forHostTime: now - base.host) * rate }
        return base.position - AVAudioTime.seconds(forHostTime: base.host - now) * rate
    }

    /// Silence, keeping everything ready to start again.
    func halt() {
        guard base != nil || engine.isRunning else { return }
        for deck in decks { deck.node.stop() }
        base = nil
        engine.pause()
    }

    func shutdown() {
        halt()
        engine.stop()
        if let changes { NotificationCenter.default.removeObserver(changes) }
        changes = nil
    }

    func set(gains: [String: Double]) {
        for deck in decks { deck.node.volume = Float(gains[deck.id] ?? 0) }
    }

    /// The app's own volume, karaoke's key in semitones, and the song's speed. A new speed starts the parts again
    /// from where they are, so the place they report stays true.
    func set(output: Float, key: Double, speed: Double) {
        engine.mainMixerNode.outputVolume = output
        pitch.pitch = Float(key * 100)
        let next = min(max(speed, 1.0 / 32), 32)
        if abs(next - rate) > 0.0001 {
            rate = next
            pitch.rate = Float(next)
            base = nil
        }
        let off = key == 0 && abs(rate - 1) < 0.0001
        if pitch.bypass != off { pitch.bypass = off }
        shape()
    }

    /// Voice settings, heard at once. The website's compressor (threshold and ratio) becomes the system's dynamics
    /// processor: the same threshold, its headroom narrowing as the ratio rises, and the same make-up gain.
    func set(fx: VoiceFx) {
        let n = fx.nodes
        let bands = voiceTone.bands
        bands[0].frequency = Float(max(20, n.lowCutHz))
        bands[0].bypass = n.lowCutHz <= 20
        bands[1].gain = Float(n.bassDb)
        bands[2].gain = Float(n.presenceDb)
        bands[3].gain = Float(n.airDb)
        voiceTone.bypass = n.lowCutHz <= 20 && n.bassDb == 0 && n.presenceDb == 0 && n.airDb == 0
        squeeze.bypass = n.compression <= 0
        if n.compression > 0 {
            let unit = squeeze.audioUnit
            AudioUnitSetParameter(unit, AudioUnitParameterID(kDynamicsProcessorParam_Threshold), kAudioUnitScope_Global, 0,
                                  AudioUnitParameterValue(n.thresholdDb), 0)
            AudioUnitSetParameter(unit, AudioUnitParameterID(kDynamicsProcessorParam_HeadRoom), kAudioUnitScope_Global, 0,
                                  AudioUnitParameterValue(max(0.5, 24 / n.ratio)), 0)
            AudioUnitSetParameter(unit, AudioUnitParameterID(kDynamicsProcessorParam_OverallGain), kAudioUnitScope_Global, 0,
                                  AudioUnitParameterValue(n.makeUpDb), 0)
        }
        doubling.wetDryMix = Float(VoiceFxNodes.wetDry(n.double))
        doubling.bypass = n.double <= 0
        echo.delayTime = max(0.06, min(2, n.echoTime))
        echo.feedback = Float(min(80, max(0, n.echoFeedback * 100)))
        echo.wetDryMix = Float(VoiceFxNodes.wetDry(n.echo))
        echo.bypass = n.echo <= 0
        let shape = VoiceFxNodes.roomIndex(n.room)
        if shape != roomShape {
            roomShape = shape
            let rooms: [AVAudioUnitReverbPreset] = [.smallRoom, .mediumRoom, .largeRoom, .mediumHall, .largeHall]
            room.loadFactoryPreset(rooms[shape])
        }
        room.wetDryMix = Float(VoiceFxNodes.wetDry(n.reverb))
        room.bypass = n.reverb <= 0
        for deck in decks where deck.voice { deck.node.pan = Float(max(-1, min(1, n.pan))) }
        let music = musicTone.bands
        music[0].gain = Float(n.musicBassDb)
        music[1].gain = Float(n.musicTrebleDb)
        music[2].gain = Float(n.pocketDb)
        musicTone.bypass = n.musicBassDb == 0 && n.musicTrebleDb == 0 && n.pocketDb == 0
    }

    /// The equaliser and levelling as the rest of the app has them now.
    private func shape() {
        let (now, version) = SoundEngine.shared.current()
        guard version != shapeVersion else { return }
        shapeVersion = version
        for (index, band) in eq.bands.enumerated() where index < now.gains.count {
            band.gain = Float(now.eqOn ? now.gains[index] : 0)
        }
        eq.globalGain = Float(min(max((now.eqOn ? now.preampDb : 0) + now.loudnessDb, -96), 24))
        eq.bypass = !now.eqOn && now.loudnessDb == 0
    }
}
