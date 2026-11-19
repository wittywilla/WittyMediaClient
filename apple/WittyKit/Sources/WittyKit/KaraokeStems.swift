// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Karaoke from a song's separate parts (the server's `karaoke-auto`): what the server says about them, how loud
// each part plays for where the sliders are, what's remembered, and what to do next as the answers come in. The
// website and the Android app follow the same rules. Nothing here plays anything: App/StemPlayer.swift does.

/// One part of a song: the voice, the music, or the whole of it.
public struct KaraokeStem: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// `vocals`, `music` or `full`. Anything newer plays as music.
    public let role: String
    /// Server-relative, fetched with the app's own sign-in.
    public let url: String
    public let mime: String
    public let defaultGain: Double

    public init(id: String, label: String = "", role: String, url: String = "", mime: String = "", defaultGain: Double = 1) {
        self.id = id
        self.label = label.isEmpty ? id.prefix(1).uppercased() + id.dropFirst() : label
        self.role = role
        self.url = url
        self.mime = mime
        self.defaultGain = StemMix.level(defaultGain)
    }

    private enum CodingKeys: String, CodingKey { case id, label, role, url, mime, defaultGain }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  label: (try? c.decodeIfPresent(String.self, forKey: .label)) ?? "",
                  role: (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "music",
                  url: (try? c.decodeIfPresent(String.self, forKey: .url)) ?? "",
                  mime: (try? c.decodeIfPresent(String.self, forKey: .mime)) ?? "",
                  defaultGain: (try? c.decodeIfPresent(Double.self, forKey: .defaultGain)) ?? 1)
    }

    /// What its file is called once fetched, so the decoder knows what it's reading.
    public var fileExtension: String {
        switch mime.lowercased().split(separator: ";").first.map({ $0.trimmingCharacters(in: .whitespaces) }) ?? "" {
        case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac": return "m4a"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/mpeg", "audio/mp3": return "mp3"
        default:
            let path = url.split(separator: "?").first.map(String.init) ?? ""
            let found = (path as NSString).pathExtension.lowercased()
            return ["m4a", "mp4", "flac", "wav", "mp3", "aac", "caf", "aiff", "aif"].contains(found) ? found : "m4a"
        }
    }
}

/// The answer of `POST /media/{id}/karaoke/prepare` and `GET /media/{id}/karaoke`.
public struct KaraokeStatus: Decodable, Equatable, Sendable {
    /// `ready`, `preparing` or `unavailable`.
    public var state: String
    /// `stems` for a real separation, `approximate` for the quick version.
    public var quality: String
    /// `parts` or `blend`: see `StemMix`.
    public var mix: String
    public var stems: [KaraokeStem]
    /// Changes whenever the files do.
    public var version: String
    /// A better version is being made now.
    public var improving: Bool
    /// 0 to 100, or -1 when the server can't say.
    public var progress: Int
    public var canImprove: Bool
    public var reason: String
    public var message: String
    /// Ask again after this many seconds; 0 to stop asking.
    public var pollSec: Double

    public init(state: String, quality: String = "", mix: String = "", stems: [KaraokeStem] = [], version: String = "",
                improving: Bool = false, progress: Int = -1, canImprove: Bool = false, reason: String = "", message: String = "",
                pollSec: Double = 0) {
        self.state = state
        self.quality = quality
        self.mix = mix
        self.stems = stems
        self.version = version
        self.improving = improving
        self.progress = progress
        self.canImprove = canImprove
        self.reason = reason
        self.message = message
        self.pollSec = pollSec
    }

    private enum CodingKeys: String, CodingKey { case state, quality, mix, stems, version, improving, progress, canImprove, reason, message, pollSec }

    /// A part that can't be read is left out rather than losing the answer.
    private struct Loose: Decodable {
        let stem: KaraokeStem?
        init(from decoder: Decoder) throws { stem = try? KaraokeStem(from: decoder) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
        quality = (try? c.decodeIfPresent(String.self, forKey: .quality)) ?? ""
        mix = (try? c.decodeIfPresent(String.self, forKey: .mix)) ?? ""
        stems = ((try? c.decodeIfPresent([Loose].self, forKey: .stems)) ?? []).compactMap(\.stem)
        version = (try? c.decodeIfPresent(String.self, forKey: .version)) ?? ""
        improving = (try? c.decodeIfPresent(Bool.self, forKey: .improving)) == true
        let told = (try? c.decodeIfPresent(Double.self, forKey: .progress)) ?? -1
        progress = told.isFinite && told >= 0 ? Int(min(100, told)) : -1
        canImprove = (try? c.decodeIfPresent(Bool.self, forKey: .canImprove)) == true
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        message = (try? c.decodeIfPresent(String.self, forKey: .message)) ?? ""
        let wait = (try? c.decodeIfPresent(Double.self, forKey: .pollSec)) ?? 0
        pollSec = wait.isFinite ? max(0, wait) : 0
    }
}

/// Where the Mix's sliders are: Voice, Background Music and Track (the server's docs/CLIENT-API.md, "Karaoke that sets
/// itself up"). Nil means "as the server suggests".
public struct StemLevels: Codable, Equatable, Sendable {
    /// The big Voice slider, 0 to 1.
    public var vocals: Double?
    /// The other two by their ids, `music` (Background Music) and `track` (Track), 0 to 1. What an older version kept
    /// here, a level for each part by its id, is read and then left alone: no slider moves it.
    public var stems: [String: Double]
    /// Sing: the voice off without losing where its slider was. Never kept for another day.
    public var sing = false

    public init(vocals: Double? = nil, stems: [String: Double] = [:], sing: Bool = false) {
        self.vocals = vocals
        self.stems = stems
        self.sing = sing
    }

    private enum CodingKeys: String, CodingKey { case vocals, stems }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vocals = (try? c.decodeIfPresent(Double.self, forKey: .vocals)).map(StemMix.level)
        stems = ((try? c.decodeIfPresent([String: Double].self, forKey: .stems)) ?? [:]).mapValues(StemMix.level)
    }

    /// Moving the Voice slider also turns Sing off.
    public mutating func setVocals(_ level: Double) {
        vocals = StemMix.level(level)
        sing = false
    }

    public mutating func setStem(_ id: String, _ level: Double) { stems[id] = StemMix.level(level) }

    public mutating func toggleSing() { sing.toggle() }

    /// Everything back to what the server suggests.
    public mutating func reset() { self = StemLevels() }
}

/// One slider of the Mix.
public struct StemSlider: Equatable, Sendable, Identifiable {
    /// `vocals` is the same slider as the big one; `music` is Background Music and `track` the whole song.
    public let id: String
    public let label: String
    public let level: Double
    public var isVocals: Bool { id == StemMix.vocalsId }
}

/// How loud each part plays.
public enum StemMix {
    public static let vocalsId = "vocals"
    public static let fullId = "full"
    public static let instrumentalId = "instrumental"
    /// The Mix's other two sliders: everything but the singer, together, and the whole song.
    public static let musicId = "music"
    public static let trackId = "track"

    /// A level kept within 0 to 1.
    public static func level(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 1 }

    /// The quick version: the whole song and the same song without what's in the middle, crossed between.
    public static func isBlend(_ status: KaraokeStatus) -> Bool { status.mix == "blend" }

    /// Whether what the server sent can be mixed at all.
    public static func playable(_ status: KaraokeStatus) -> Bool {
        if isBlend(status) {
            return status.stems.contains { $0.id == fullId } && status.stems.contains { $0.id == instrumentalId }
        }
        return status.stems.contains { $0.role == "vocals" } && status.stems.contains { $0.role != "vocals" && $0.role != "full" }
    }

    /// The parts that are played: a blend's two, or every part but a whole-song copy.
    public static func played(_ status: KaraokeStatus) -> [KaraokeStem] {
        if isBlend(status) { return status.stems.filter { $0.id == fullId || $0.id == instrumentalId } }
        return status.stems.filter { $0.role != "full" }
    }

    /// The part the Vocals slider starts from: the voice, or in a blend the whole song.
    private static func vocalsDefault(_ status: KaraokeStatus) -> Double {
        let from = isBlend(status) ? status.stems.first { $0.id == fullId } : status.stems.first { $0.role == "vocals" }
        return from?.defaultGain ?? 1
    }

    /// Where the Vocals slider is, whether or not Sing is on.
    public static func vocalsLevel(_ status: KaraokeStatus, _ levels: StemLevels) -> Double {
        level(levels.vocals ?? vocalsDefault(status))
    }

    /// Where Background Music or Track is: full unless moved.
    public static func mixLevel(_ id: String, _ levels: StemLevels) -> Double { level(levels.stems[id] ?? 1) }

    /// The gain of every played part, by id, for Voice v, Background Music m and Track t (Sing is v = 0).
    ///
    /// Parts: the voice at t·v, and every other part at t·m times the server's own level for it. Blend (the whole song,
    /// and its music without the voice): the whole song at t·v and the music at t·(m−v), straight lines, so the music
    /// adds up to t·m and the voice to t·v. On the website and Android the music's gain goes negative when the music
    /// is below the voice, taking the music out of the whole song; an `AVAudioMixerNode` can't play a part upside down,
    /// so here it stops at nothing: with the music below the voice, the quick version is the whole song at t·v.
    public static func gains(_ status: KaraokeStatus, _ levels: StemLevels) -> [String: Double] {
        let v = levels.sing ? 0 : vocalsLevel(status, levels)
        let m = mixLevel(musicId, levels)
        let t = mixLevel(trackId, levels)
        var out: [String: Double] = [:]
        if isBlend(status) {
            guard status.stems.contains(where: { $0.id == instrumentalId }) else { return [:] }
            out[fullId] = t * v
            out[instrumentalId] = max(0, t * (m - v))
            return out
        }
        for stem in played(status) {
            out[stem.id] = stem.role == "vocals" ? t * v : t * m * level(stem.defaultGain)
        }
        return out
    }

    /// The Mix: Voice, Background Music and Track, the same whatever version is playing.
    public static func sliders(_ status: KaraokeStatus, _ levels: StemLevels) -> [StemSlider] {
        [StemSlider(id: vocalsId, label: "Voice", level: vocalsLevel(status, levels)),
         StemSlider(id: musicId, label: "Background Music", level: mixLevel(musicId, levels)),
         StemSlider(id: trackId, label: "Track", level: mixLevel(trackId, levels))]
    }

    /// "Separated" for real parts, "Quick version" for the approximate one.
    public static func qualityWords(_ status: KaraokeStatus) -> String {
        switch status.quality {
        case "stems": return "Separated"
        case "approximate": return "Quick version"
        default: return ""
        }
    }

    /// "Preparing karaoke… 40%", without the number when the server can't say.
    public static func preparingWords(_ progress: Int) -> String {
        progress >= 0 ? "Preparing karaoke… \(min(100, progress))%" : "Preparing karaoke…"
    }

    public static func improvingWords(_ progress: Int) -> String {
        progress >= 0 ? "Preparing a better version… \(min(100, progress))%" : "Preparing a better version…"
    }

    public static func percent(_ level: Double) -> String { "\(Int((StemMix.level(level) * 100).rounded()))%" }

    /// A remote's left and right: 5% at a time.
    public static func stepped(_ level: Double, by steps: Int) -> Double {
        StemMix.level(((level * 100).rounded() + Double(steps) * 5) / 100)
    }
}

/// The sliders, kept on the device for each person on each server.
public struct StemLevelsStore {
    private let defaults: UserDefaults
    private let key: String

    public init(server: String, profile: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "wms.karaoke.levels|\(server)|\(profile)"
    }

    public func load() -> StemLevels {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(StemLevels.self, from: data) else { return StemLevels() }
        return saved
    }

    /// Sing isn't written: it starts off every time.
    public func save(_ levels: StemLevels) {
        if levels.vocals == nil, levels.stems.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(levels) {
            defaults.set(data, forKey: key)
        }
    }
}

/// What to do next for one song's karaoke, as the server's answers come in. It asks for nothing itself: each step
/// hands back what the app should now do.
public struct KaraokeMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Asked the server to prepare; no answer yet.
        case asked
        case preparing(progress: Int)
        case ready(quality: String, version: String)
        case unavailable(message: String)
        /// The parts couldn't be played: the normal track plays, and this says why.
        case fallback(message: String)
    }

    public enum Effect: Equatable, Sendable {
        /// `POST …/karaoke/prepare`, after this many seconds.
        case prepare(after: Double)
        /// `GET …/karaoke`, after this many seconds.
        case poll(after: Double)
        /// Fetch and start these parts.
        case load(version: String)
        /// Fetch these parts and change to them where the song is, without stopping it.
        case swap(version: String)
        /// Stop the parts and let the normal track be heard.
        case stop
    }

    public static let noWords = "Karaoke isn't available for this song."
    public static let failedWords = "The karaoke version couldn't be played, so this is the normal track."
    public static let longestWait = 30.0

    public private(set) var phase: Phase = .idle
    public private(set) var song: Int64?
    /// The last answer that was `ready`: what's playing, or about to.
    public private(set) var status: KaraokeStatus?
    /// Whether a better version is on its way, and how far along.
    public private(set) var improving = false
    public private(set) var progress = -1
    /// The version asked to be loaded.
    public private(set) var wanted: String?
    private var failures = 0
    private var lastWait = 3.0

    public init() {}

    /// Karaoke opened on a song: ask once.
    public mutating func open(song id: Int64) -> [Effect] {
        guard song != id || phase == .idle else { return [] }
        let playing = wanted != nil
        self = KaraokeMachine()
        song = id
        phase = .asked
        return (playing ? [.stop] : []) + [.prepare(after: 0)]
    }

    /// Karaoke closed, or another song: nothing is left of this one.
    public mutating func reset() -> [Effect] {
        let had = phase != .idle
        self = KaraokeMachine()
        return had ? [.stop] : []
    }

    /// How long to wait after this many failures in a row: doubling from the server's own wait, never past 30 s.
    public static func backoff(failures: Int, base: Double) -> Double {
        let start = max(1, base)
        return min(longestWait, start * pow(2, Double(max(0, min(failures, 10)))))
    }

    /// The server couldn't be reached. Nothing changes but when to ask again.
    public mutating func networkFailed() -> [Effect] {
        guard song != nil else { return [] }
        switch phase {
        case .idle, .fallback: return []
        case .asked:
            failures += 1
            return [.prepare(after: Self.backoff(failures: failures, base: lastWait))]
        default:
            failures += 1
            return [.poll(after: Self.backoff(failures: failures, base: lastWait))]
        }
    }

    /// A part wouldn't load or play: back to the normal track for the rest of this song.
    public mutating func stemsFailed(_ words: String = "") -> [Effect] {
        guard song != nil, phase != .idle else { return [] }
        phase = .fallback(message: words.isEmpty ? Self.failedWords : words)
        improving = false
        wanted = nil
        status = nil
        return [.stop]
    }

    /// An answer from either route.
    public mutating func answered(_ answer: KaraokeStatus) -> [Effect] {
        guard song != nil, phase != .idle else { return [] }
        failures = 0
        if answer.pollSec > 0 { lastWait = answer.pollSec }
        // Once it has fallen back it stays there: asking again mid-song would only fail again.
        if case .fallback = phase { return [] }
        let again: [Effect] = answer.pollSec > 0 ? [.poll(after: answer.pollSec)] : []
        switch answer.state {
        case "ready":
            guard StemMix.playable(answer) else {
                let stop: [Effect] = wanted != nil ? [.stop] : []
                wanted = nil
                status = nil
                improving = false
                phase = .unavailable(message: answer.message.isEmpty ? Self.noWords : answer.message)
                return stop + again
            }
            improving = answer.improving
            progress = answer.progress
            phase = .ready(quality: answer.quality, version: answer.version)
            let before = wanted
            status = answer
            guard before != answer.version else { return answer.improving ? again : [] }
            wanted = answer.version
            let first: Effect = before == nil ? .load(version: answer.version) : .swap(version: answer.version)
            return [first] + (answer.improving ? again : [])
        case "preparing":
            // What's already playing carries on while a new one is made.
            if wanted != nil {
                improving = true
                progress = answer.progress
            } else {
                phase = .preparing(progress: answer.progress)
            }
            return again
        default:
            let stop: [Effect] = wanted != nil ? [.stop] : []
            wanted = nil
            status = nil
            improving = false
            phase = .unavailable(message: answer.message.isEmpty ? Self.noWords : answer.message)
            return stop + again
        }
    }
}

extension WittyClient {
    /// Asks the server to get a song's karaoke parts ready. Safe to ask twice; asked once when karaoke opens.
    public func prepareKaraoke(item: Int64) async throws -> KaraokeStatus {
        try JSONDecoder().decode(KaraokeStatus.self, from: try await call("POST", "/media/\(item)/karaoke/prepare"))
    }

    /// How a song's karaoke parts are coming along.
    public func karaoke(item: Int64) async throws -> KaraokeStatus { try await get("/media/\(item)/karaoke") }
}
