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
    }

    /// How far ahead a start is set, so every part has time to be ready for it.
    private static let lead = 0.1

    private let engine = AVAudioEngine()
    private let mix = AVAudioMixerNode()
    private let pitch = AVAudioUnitTimePitch()
    private var decks: [Deck] = []
    /// Where in the song the parts were at a moment on the device's clock. Nil while they're stopped.
    private var base: (position: Double, host: UInt64)?
    private var changes: NSObjectProtocol?

    /// Opens every part. Throws if one can't be read, which is the cue to play the normal track.
    init(files: [(id: String, url: URL)]) throws {
        guard !files.isEmpty else { throw StemTrouble.unreadable }
        engine.attach(mix)
        engine.attach(pitch)
        for part in files {
            let file = try AVAudioFile(forReading: part.url)
            guard file.length > 0, file.processingFormat.sampleRate > 0 else { throw StemTrouble.unreadable }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mix, format: file.processingFormat)
            decks.append(Deck(id: part.id, node: node, file: file))
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: decks[0].file.processingFormat.sampleRate, channels: 2) else {
            throw StemTrouble.unreadable
        }
        engine.connect(mix, to: pitch, format: format)
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
        let start = max(0, position + Self.lead)
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
        if now >= base.host { return base.position + AVAudioTime.seconds(forHostTime: now - base.host) }
        return base.position - AVAudioTime.seconds(forHostTime: base.host - now)
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

    /// The app's own volume, and karaoke's key in semitones.
    func set(output: Float, key: Double) {
        engine.mainMixerNode.outputVolume = output
        pitch.pitch = Float(key * 100)
        let off = key == 0
        if pitch.bypass != off { pitch.bypass = off }
    }
}
