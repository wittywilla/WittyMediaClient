import Foundation

// The rest of the website's music player, as rules the phone and tablet apps share: the Sound panel and what it
// changes (web/src/audio/sound.ts, SoundPanel.tsx, player.tsx), karaoke (Karaoke.tsx, lyrics.ts), the visualizer's
// choices (NowPlaying.tsx, backdrop.ts), Read (ReadPanel.tsx) and Fix (LyricsPanel.tsx).

// MARK: - Sound

public struct EqPreset: Equatable {
    public let id: String
    public let name: String
    public let gains: [Double]
}

public enum Equaliser {
    public static let frequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    public static let presets: [EqPreset] = [
        EqPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EqPreset(id: "bass", name: "More bass", gains: [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]),
        EqPreset(id: "treble", name: "More treble", gains: [0, 0, 0, 0, 0, 0, 1, 3, 5, 6]),
        EqPreset(id: "vocal", name: "Clear voices", gains: [-2, -2, -1, 0, 2, 4, 4, 2, 0, -1]),
        EqPreset(id: "rock", name: "Rock", gains: [4, 3, 1, -1, -1, 0, 2, 3, 4, 4]),
        EqPreset(id: "pop", name: "Pop", gains: [-1, 0, 2, 3, 3, 1, 0, 0, 1, 1]),
        EqPreset(id: "classical", name: "Classical", gains: [3, 2, 1, 0, 0, 0, 0, 1, 2, 3]),
        EqPreset(id: "jazz", name: "Jazz", gains: [3, 2, 1, 1, -1, -1, 0, 1, 2, 3]),
        EqPreset(id: "night", name: "Quiet room", gains: [-4, -3, -1, 0, 1, 2, 1, 0, -2, -3]),
        EqPreset(id: "speech", name: "Speech", gains: [-6, -4, -2, 1, 3, 4, 3, 2, 0, -3]),
    ]

    /// "31", "1k", "16k".
    public static func hertz(_ frequency: Double) -> String {
        frequency >= 1000 ? "\(PlayerSpeeds.number(frequency / 1000))k" : PlayerSpeeds.number(frequency)
    }

    /// "+3", "0", "-2".
    public static func decibels(_ gain: Double) -> String { "\(gain > 0 ? "+" : "")\(PlayerSpeeds.number(gain))" }
}

/// How it sounds on this device, as the website keeps it per browser (`wms.sound`). The voice and the key are for
/// one sitting, so they're never kept.
public struct SoundSettings: Codable, Equatable {
    public enum Leveling: String, Codable, CaseIterable { case off, track, album }

    public var volume = 1.0
    public var muted = false
    public var eqOn = false
    public var eqPreset = "flat"
    public var eqGains = Equaliser.presets[0].gains
    /// dB, with the equaliser.
    public var preamp = 0.0
    public var replayGain = Leveling.off
    public var gapless = true
    /// Seconds; 0 for none.
    public var crossfade = 0.0
    /// Also between songs of one album, which are often meant to run together.
    public var crossfadeAlbums = false
    /// 0 to 1.
    public var vocalCut = 0.0
    /// Semitones.
    public var keyShift = 0.0

    public init() {}

    private enum CodingKeys: String, CodingKey { case volume, muted, eqOn, eqPreset, eqGains, preamp, replayGain, gapless, crossfade, crossfadeAlbums }

    private static func within(_ value: Double?, _ low: Double, _ high: Double, _ otherwise: Double) -> Double {
        guard let value, value.isFinite else { return otherwise }
        return min(high, max(low, value))
    }

    /// What's saved, with anything odd put right, as the website's loadSound.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = Self.within(try? c.decodeIfPresent(Double.self, forKey: .volume), 0, 1, 1)
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) == true
        eqOn = (try? c.decodeIfPresent(Bool.self, forKey: .eqOn)) == true
        eqPreset = (try? c.decodeIfPresent(String.self, forKey: .eqPreset)) ?? "flat"
        if let gains = try? c.decodeIfPresent([Double].self, forKey: .eqGains), gains.count == Equaliser.frequencies.count {
            eqGains = gains.map { Self.within($0, -12, 12, 0) }
        }
        preamp = Self.within(try? c.decodeIfPresent(Double.self, forKey: .preamp), -12, 12, 0)
        replayGain = (try? c.decodeIfPresent(Leveling.self, forKey: .replayGain)) ?? .off
        gapless = (try? c.decodeIfPresent(Bool.self, forKey: .gapless)) != false
        crossfade = Self.within(try? c.decodeIfPresent(Double.self, forKey: .crossfade), 0, 12, 0)
        crossfadeAlbums = (try? c.decodeIfPresent(Bool.self, forKey: .crossfadeAlbums)) == true
    }

    /// Whether anything changes the sound at all: until then it plays straight through.
    public var changesSound: Bool { eqOn || replayGain != .off || vocalCut > 0 || keyShift != 0 }

    /// The preset shown: one of them, or "custom" for the listener's own.
    public var presetShown: String { Equaliser.presets.contains { $0.id == eqPreset } ? eqPreset : "custom" }

    /// The crossfade's choices, in the website's words.
    public static let crossfades: [Double] = [0, 2, 4, 6, 8, 12]
    public static func crossfadeWords(_ seconds: Double) -> String { seconds > 0 ? "\(PlayerSpeeds.number(seconds)) seconds" : "Off" }
    public static func levelingWords(_ choice: Leveling) -> String {
        switch choice {
        case .off: return "Off"
        case .track: return "Each song the same"
        case .album: return "Keep each album's balance"
        }
    }

    /// How long to cross into the next song: none within an album unless asked, as songs there often run together.
    public func fade(from album: String?, to next: String?) -> Double {
        guard crossfade > 0 else { return 0 }
        if !crossfadeAlbums, let next, !next.isEmpty, next == album { return 0 }
        return crossfade
    }
}

/// Where the sound settings are kept on this device.
public struct SoundStore {
    static let key = "wms.sound"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> SoundSettings {
        guard let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(SoundSettings.self, from: data) else { return SoundSettings() }
        return saved
    }

    public func save(_ settings: SoundSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.key) }
    }
}

/// The volume correction a file is tagged with: `/music/loudness/{id}`.
public struct Loudness: Decodable, Equatable {
    public let trackDb: Double?
    public let albumDb: Double?
    public let trackPeak: Double?
    public let albumPeak: Double?

    public init(trackDb: Double?, albumDb: Double?, trackPeak: Double?, albumPeak: Double?) {
        self.trackDb = trackDb
        self.albumDb = albumDb
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
    }

    /// The change in dB for this choice, never so loud that the file's own peak would clip.
    public func gain(_ choice: SoundSettings.Leveling) -> Double {
        guard choice != .off else { return 0 }
        let album = choice == .album
        let db = (album ? albumDb ?? trackDb : trackDb ?? albumDb) ?? 0
        let peak = (album ? albumPeak ?? trackPeak : trackPeak ?? albumPeak) ?? 0
        let room = peak > 0 ? -20 * log10(peak) : 12
        return min(db, room)
    }
}

// MARK: - Karaoke

public struct LyricWord: Decodable, Equatable {
    public let t: Double
    public let text: String
}

public struct TimedWord: Equatable {
    public let text: String
    public let from: Double
    public let to: Double
}

public enum Karaoke {
    /// The voice: on, lower, lowest.
    public static let vocals: [(Double, String)] = [(0, "Voice on"), (0.6, "Voice lower"), (1, "Voice lowest")]
    static let countFromMs = 3000.0
    static let longGapMs = 5000.0

    /// When each word of a line is sung: its own times, or spread by length over the line, as the website's wordTimes.
    public static func words(_ line: LyricLine, next: Double?) -> [TimedWord] {
        let end = line.end ?? next ?? line.t + 5000
        if let words = line.words, !words.isEmpty {
            return words.enumerated().map { at, word in
                TimedWord(text: word.text, from: word.t, to: at + 1 < words.count ? words[at + 1].t : min(end, word.t + 1500))
            }
        }
        // Each word with the space after it.
        var parts: [String] = []
        var current = ""
        for character in line.text {
            current.append(character)
            if character.isWhitespace {
                parts.append(current)
                current = ""
            }
        }
        if !current.isEmpty { parts.append(current) }
        let singing = min(end - line.t, max(1200, Double(line.text.count) * 95))
        let total = Double(max(1, parts.reduce(0) { $0 + $1.count }))
        var at = line.t
        return parts.map { text in
            let span = Double(text.count) / total * singing
            defer { at += span }
            return TimedWord(text: text, from: at, to: at + span)
        }
    }

    /// How far through a word is, 0 to 1.
    public static func fill(_ word: TimedWord, at ms: Double) -> Double {
        ms <= word.from ? 0 : ms >= word.to ? 1 : (ms - word.from) / max(1, word.to - word.from)
    }

    /// The count-in before a line after a break: 3, 2, 1, or 0 for none.
    public static func countIn(_ lines: [LyricLine], at ms: Double) -> Int {
        let at = lineIndex(lines, ms)
        guard at + 1 < lines.count else { return 0 }
        let up = lines[at + 1]
        let here = at >= 0 ? lines[at] : nil
        let left = up.t - ms
        let quiet = here == nil || up.t - (here!.end ?? here!.t) > 0 || here!.text.isEmpty
        let longGap = here == nil || up.t - here!.t >= longGapMs
        return left > 0 && left <= countFromMs && quiet && longGap ? Int((left / 1000).rounded(.up)) : 0
    }

    public static func lineIndex(_ lines: [LyricLine], _ ms: Double) -> Int {
        var lo = 0, hi = lines.count - 1, at = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].t <= ms { at = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return at
    }

    /// "Key +2", "Key 0".
    public static func keyWords(_ semitones: Double) -> String { "Key \(semitones > 0 ? "+" : "")\(PlayerSpeeds.number(semitones))" }

    /// "Words on time", "Words +0.3 s".
    public static func timingWords(_ ms: Double) -> String {
        ms == 0 ? "Words on time" : "Words \(ms > 0 ? "+" : "")\(String(format: "%.1f", ms / 1000)) s"
    }

    /// The line under the controls, in the website's words.
    public static func note(mono: Bool, vocalCut: Double, keyShift: Double, timed: Bool, hasWordTimes: Bool) -> String {
        if mono { return "This recording is close to mono, so there's no way to separate the voice from it." }
        if vocalCut > 0 { return "The voice is turned down by removing what's in the middle of the mix. Echoes of it, and songs that spread it wide, will still come through." }
        if keyShift != 0 { return "A changed key can warble a little on long notes." }
        if timed && !hasWordTimes { return "Lines are timed; the fill within a line is an estimate." }
        return ""
    }
}

// MARK: - The visualizer

/// The visualizer's choices, kept for the person on the server with their other interface choices (`/me/ui`,
/// `musicPlayer`).
public struct VisualizerPrefs: Codable, Equatable {
    public static let styles: [(id: String, name: String)] = [("bars", "Bars"), ("waves", "Waves"), ("drift", "Drift")]
    public static let shuffleChoices = [0, 15, 30, 60, 120, 300, 600]

    public var viz = true
    public var style = "bars"
    public var slow = false
    public var shuffleEvery = 0
    public var shufflePool = "mine"

    public init() {}

    private enum CodingKeys: String, CodingKey { case viz, style, slow, shuffleEvery, shufflePool }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viz = (try? c.decodeIfPresent(Bool.self, forKey: .viz)) != false
        let saved = (try? c.decodeIfPresent(String.self, forKey: .style)) ?? "bars"
        style = saved.count <= 48 ? saved : "bars"
        slow = (try? c.decodeIfPresent(Bool.self, forKey: .slow)) == true
        let every = (try? c.decodeIfPresent(Int.self, forKey: .shuffleEvery)) ?? 0
        shuffleEvery = Self.shuffleChoices.contains(every) ? every : 0
        shufflePool = (try? c.decodeIfPresent(String.self, forKey: .shufflePool)) == "all" ? "all" : "mine"
    }

    /// The style drawn here: one of the player's own, or Bars for an effect only the website's plugin draws.
    public var nativeStyle: String { Self.styles.contains { $0.id == style } ? style : "bars" }

    /// "Off: stay on this one", "Every 15 seconds", "Every minute", "Every 2 minutes".
    public static func everyWords(_ seconds: Int) -> String {
        seconds == 0 ? "Off: stay on this one" : seconds < 60 ? "Every \(seconds) seconds" : seconds == 60 ? "Every minute" : "Every \(seconds / 60) minutes"
    }
}

/// Bars, Waves and Drift read the sound as 23 levels from low to high (backdrop.ts).
public enum VisualizerLevels {
    public static let count = 23

    /// The bins of a 1024-bin spectrum each level takes the loudest of.
    public static func bins(_ level: Int) -> Range<Int> {
        let n = Double(count)
        let a = Int(2 * pow(170, Double(level) / n))
        let b = max(a + 1, Int(2 * pow(170, Double(level + 1) / n)))
        return a..<b
    }

    /// A level from its loudest bin (0 to 255), higher ones lifted a little.
    public static func level(peak: UInt8, at level: Int) -> Double {
        pow(Double(peak) / 255 * (1 + Double(level) / Double(count) * 0.45), 3)
    }
}

// MARK: - Read and Fix

/// Something beside an album to read: `/music/extras/{id}`.
public struct Extra: Decodable, Equatable, Identifiable {
    public let name: String
    public let kind: String
    public let size: Int?
    public var id: String { name }
    public var isBooklet: Bool { kind == "booklet" }
}

/// Another version of a song's words, from `/music/lyrics/{id}/search`.
public struct FoundLyrics: Decodable, Equatable, Identifiable {
    public let provider: String
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let durationSec: Double?
    public let hasSynced: Bool
    public let instrumental: Bool?

    /// "Timed · same length", "Words only · 12 s different".
    public func facts(songSeconds: Double?) -> String {
        let kind = instrumental == true ? "No words" : hasSynced ? "Timed" : "Words only"
        guard let durationSec, let songSeconds, durationSec > 0, songSeconds > 0 else { return kind }
        let off = abs(durationSec - songSeconds)
        return "\(kind) · \(off < 3 ? "same length" : "\(Int(off.rounded())) s different")"
    }
}

public enum LyricFile {
    /// An LRC time: "01:02.50".
    public static func stamp(_ ms: Double) -> String {
        let total = max(0, Int(ms))
        return String(format: "%02d:%02d.%02d", total / 60000, (total / 1000) % 60, (total % 1000) / 10)
    }

    /// Tap along's lines: the words, one line each, without the blank ones.
    public static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The timed lines as a file.
    public static func lrc(times: [Double], lines: [String]) -> String {
        zip(times, lines).map { "[\(stamp($0))]\($1)" }.joined(separator: "\n") + "\n"
    }

    /// What Edit starts with: the timed lines, or the plain words.
    public static func draft(_ lyrics: Lyrics) -> String {
        let timed = lyrics.timed
        return timed.isEmpty ? (lyrics.plain ?? "") : timed.map { "[\(stamp($0.t))]\($0.text)" }.joined(separator: "\n")
    }
}
