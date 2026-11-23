// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The website's video player, as rules the phone and tablet apps share: web/src/player/Controls.tsx, speed.ts,
// viewPrefs.ts, TrackPicker.tsx and VideoPlayer.tsx. docs/APP-DESIGN.md, Playback and the media player.

public enum PlayerTime {
    /// "1:02:03", or "2:03" under an hour, as the website writes a time. Anything odd is 0:00.
    public static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite && seconds > 0 ? Int(seconds) : 0
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

public enum PlayerSpeeds {
    /// Every speed the website offers.
    public static let all: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 3.5, 4, 5, 6, 8, 10, 12, 16]

    /// Those up to the server's limit (Settings, Playback: `maxSpeed`, 4 when it says nothing).
    public static func offered(max: Double?) -> [Double] {
        let limit = (max ?? 0) > 0 ? max! : 4
        return all.filter { $0 <= limit }
    }

    /// "Normal" for 1, "1.5×" otherwise: the speed list's words. The button says "1×".
    public static func words(_ speed: Double) -> String { speed == 1 ? "Normal" : "\(number(speed))×" }
    public static func button(_ speed: Double) -> String { "\(number(speed))×" }

    static func number(_ speed: Double) -> String {
        speed == speed.rounded() ? String(Int(speed)) : String(format: "%g", speed)
    }
}

/// The gear's choices (viewPrefs.ts): for every video on this device, or for one video, which then wins.
public struct ViewPrefs: Codable, Equatable {
    public var seekBar = true
    public var chapterMarks = true
    /// Seconds before the controls hide while playing; 0 never.
    public var hideAfter = 3.5
    /// "fit" keeps the whole picture; "fill" zooms to fill the screen.
    public var picture = "fit"
    /// The on-screen remote, and whether it floats or sits in a strip above the seek bar ("floating", "bar").
    public var remote = false
    public var remoteStyle = "floating"

    public init(seekBar: Bool = true, chapterMarks: Bool = true, hideAfter: Double = 3.5, picture: String = "fit",
                remote: Bool = false, remoteStyle: String = "floating") {
        self.seekBar = seekBar
        self.chapterMarks = chapterMarks
        self.hideAfter = hideAfter
        self.picture = picture
        self.remote = remote
        self.remoteStyle = remoteStyle
    }

    // A saved set from another version, or one with fields this doesn't know, keeps what it can.
    private enum CodingKeys: String, CodingKey { case seekBar, chapterMarks, hideAfter, picture, remote, remoteStyle }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = ViewPrefs()
        seekBar = (try? c.decodeIfPresent(Bool.self, forKey: .seekBar)) ?? base.seekBar
        chapterMarks = (try? c.decodeIfPresent(Bool.self, forKey: .chapterMarks)) ?? base.chapterMarks
        hideAfter = (try? c.decodeIfPresent(Double.self, forKey: .hideAfter)) ?? base.hideAfter
        let shown = (try? c.decodeIfPresent(String.self, forKey: .picture)) ?? base.picture
        picture = shown == "fill" ? "fill" : "fit"
        remote = (try? c.decodeIfPresent(Bool.self, forKey: .remote)) ?? base.remote
        remoteStyle = (try? c.decodeIfPresent(String.self, forKey: .remoteStyle)) == "bar" ? "bar" : "floating"
    }

    /// The website's choices for how long the controls stay.
    public static let hideChoices: [(Double, String)] = [(2, "2 s"), (3.5, "3.5 s"), (6, "6 s"), (0, "Never")]
}

/// How this device asks for video (streaming.ts): the server's choice, Standard, or Robust, which favours staying
/// smooth on a poor connection. Kept on the device as `wms.streaming`, as the website keeps it per browser.
public enum DeviceStreaming: String, CaseIterable {
    case auto, standard, robust

    public var words: String {
        switch self {
        case .auto: return "Server’s choice"
        case .standard: return "Standard"
        case .robust: return "Robust"
        }
    }

    static let key = "wms.streaming"

    public static func load(_ defaults: UserDefaults = .standard) -> DeviceStreaming {
        DeviceStreaming(rawValue: defaults.string(forKey: key) ?? "") ?? .auto
    }

    public static func save(_ choice: DeviceStreaming, _ defaults: UserDefaults = .standard) {
        if choice == .auto { defaults.removeObject(forKey: key) } else { defaults.set(choice.rawValue, forKey: key) }
    }

    /// What goes in the request: nothing for the server's choice.
    public var asked: String? { self == .auto ? nil : rawValue }

    /// Whether to time the connection first: chosen here, or the server sends viewers robust streams.
    public func measures(serverMode: String?) -> Bool { self == .auto ? serverMode == "robust" : self == .robust }
}

/// The on-screen remote's keys (Remote.tsx). A video file has no menus, angles or numbers: those are for discs.
public enum RemoteKey: String, CaseIterable {
    case eject, topmenu, menu, `return`, up, down, left, right, enter, audio, subtitle, angle, prev, next, rew, ff, play, pause, stop
    case digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9

    public static let discOnly: Set<RemoteKey> = [.topmenu, .menu, .return, .up, .down, .left, .right, .enter, .angle,
                                                  .digit0, .digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9]

    /// Whether the key does anything for a video file with these tracks.
    public func worksForFile(audioTracks: Int, subtitleTracks: Int) -> Bool {
        if Self.discOnly.contains(self) { return false }
        if self == .audio { return audioTracks > 1 }
        if self == .subtitle { return subtitleTracks > 0 }
        return true
    }

    /// Seconds a key moves through a file: rewind 10, previous a minute back, forward 30, next a minute on.
    public var jump: Double? {
        switch self {
        case .rew: return -10
        case .prev: return -60
        case .ff: return 30
        case .next: return 60
        default: return nil
        }
    }
}

/// Where the floating remote is, how big and how see-through: kept on the device (`wms.remote.geom`).
public struct RemoteGeometry: Codable, Equatable {
    public static let alphas: [Double] = [0.92, 0.75, 0.55, 0.35]
    public var x: Double?
    public var y: Double?
    public var scale = 1.0
    public var alpha = 0.92

    public init(x: Double? = nil, y: Double? = nil, scale: Double = 1, alpha: Double = 0.92) {
        self.x = x
        self.y = y
        self.scale = min(1.6, max(0.6, scale))
        self.alpha = alpha
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try? c.decodeIfPresent(Double.self, forKey: .x)
        y = try? c.decodeIfPresent(Double.self, forKey: .y)
        scale = min(1.6, max(0.6, ((try? c.decodeIfPresent(Double.self, forKey: .scale)) ?? 1) ?? 1))
        alpha = ((try? c.decodeIfPresent(Double.self, forKey: .alpha)) ?? nil) ?? 0.92
    }

    /// The next see-through step.
    public var nextAlpha: Double {
        let at = Self.alphas.firstIndex(of: alpha) ?? -1
        return Self.alphas[(at + 1) % Self.alphas.count]
    }

    static let key = "wms.remote.geom"

    public static func load(_ defaults: UserDefaults = .standard) -> RemoteGeometry {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(RemoteGeometry.self, from: data) else { return RemoteGeometry() }
        return saved
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// The website's keyboard shortcuts for a video file (Controls.tsx).
public enum PlayerShortcuts {
    public static let file: [(keys: String, what: String)] = [
        ("Space or K", "Play or pause"),
        ("← and →", "Back 10 seconds, forward 10 seconds"),
        ("Page Up and Page Down", "Forward or back a minute (on the timeline)"),
        ("Home and End", "The start or the end (on the timeline)"),
        ("↑ and ↓", "Volume up or down"),
        ("M", "Mute or unmute"),
        ("I", "Details of what’s playing"),
        ("< and >", "Slower or faster"),
        ("F", "Fullscreen"),
        ("R", "Show or hide the remote"),
        ("Esc", "Close a window, or shrink the player"),
        ("?", "This list"),
    ]
}

/// Where the gear's choices are kept on this device: as the website keeps them per browser.
public struct ViewPrefsStore {
    public enum Scope: String { case item, global }

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static let globalKey = "wms.view"
    static func itemKey(_ id: Int64) -> String { "wms.view.item.\(id)" }

    private func read(_ key: String) -> ViewPrefs? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ViewPrefs.self, from: data)
    }

    private func write(_ key: String, _ prefs: ViewPrefs?) {
        if let prefs, let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// What applies to this video, and where it comes from.
    public func load(item: Int64) -> (prefs: ViewPrefs, scope: Scope) {
        if let own = read(Self.itemKey(item)) { return (own, .item) }
        return (read(Self.globalKey) ?? ViewPrefs(), .global)
    }

    /// Kept for this video alone, or for every video (which takes this video's own away).
    public func save(_ prefs: ViewPrefs, item: Int64, scope: Scope) {
        switch scope {
        case .item: write(Self.itemKey(item), prefs)
        case .global:
            write(Self.globalKey, prefs)
            write(Self.itemKey(item), nil)
        }
    }
}

/// A big square choice in the track picker: the language, then the track's own name, then its format.
public struct TrackTile: Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let sub: String
    public let detail: String
    public let active: Bool

    /// Sound tracks, as the website's picker shows them.
    public static func audio(_ tracks: [Track], chosen: Int?) -> [TrackTile] {
        TrackWords.audioList(tracks).map { track, name in
            TrackTile(id: track.index, title: name.title, sub: name.sub, detail: name.detail, active: track.index == chosen)
        }
    }

    /// Off first, then every subtitle track.
    public static func subtitles(_ tracks: [Track], chosen: Int?) -> [TrackTile] {
        [TrackTile(id: -1, title: "Off", sub: "", detail: "", active: chosen == nil || (chosen ?? -1) < 0)]
            + TrackWords.subtitleList(tracks).map { track, name in
                TrackTile(id: track.index, title: name.title, sub: name.sub, detail: name.detail, active: track.index == chosen)
            }
    }
}

/// A track's name in three parts: the language, the track's own name and marks, and what kind it is.
public struct TrackName: Equatable {
    public let title: String
    public let sub: String
    public let detail: String

    public var line: String { [title, sub, detail].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// How a video's sound tracks and subtitles are named in every native player: the same rule as Android's
/// (player/TrackWords.kt) and the website's picker. The language first, then the track's own name, then what kind it
/// is. A track nobody labelled is "Track 2" or "Subtitles 2", never "Unknown".
public enum TrackWords {
    /// The older three-letter codes files carry, and the newer ones, as two letters Locale knows.
    private static let twoLetter: [String: String] = [
        "alb": "sq", "sqi": "sq", "ara": "ar", "arm": "hy", "hye": "hy", "baq": "eu", "eus": "eu", "bul": "bg", "bur": "my", "mya": "my",
        "cat": "ca", "ces": "cs", "cze": "cs", "chi": "zh", "zho": "zh", "dan": "da", "deu": "de", "ger": "de", "dut": "nl", "nld": "nl",
        "ell": "el", "gre": "el", "eng": "en", "est": "et", "fas": "fa", "per": "fa", "fin": "fi", "fra": "fr", "fre": "fr", "geo": "ka",
        "kat": "ka", "heb": "he", "hin": "hi", "hrv": "hr", "hun": "hu", "ice": "is", "isl": "is", "ind": "id", "ita": "it", "jpn": "ja",
        "kor": "ko", "lav": "lv", "lit": "lt", "mac": "mk", "mkd": "mk", "may": "ms", "msa": "ms", "nob": "nb", "nno": "nn", "nor": "no",
        "pol": "pl", "por": "pt", "ron": "ro", "rum": "ro", "rus": "ru", "slk": "sk", "slo": "sk", "slv": "sl", "spa": "es", "srp": "sr",
        "swe": "sv", "tam": "ta", "tel": "te", "tha": "th", "tur": "tr", "ukr": "uk", "urd": "ur", "vie": "vi", "wel": "cy", "cym": "cy",
    ]

    /// "English" for eng, en, en-US, or the server's own name for it; "" when there's no language to name.
    public static func language(_ track: Track) -> String {
        if let name = track.languageName?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        return languageOf(track.language ?? "")
    }

    public static func languageOf(_ code: String) -> String {
        let raw = code.trimmingCharacters(in: .whitespaces).lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        if raw.isEmpty || ["und", "unknown", "zxx", "mul"].contains(raw) { return "" }
        let two = twoLetter[raw] ?? raw
        let name = Locale(identifier: "en").localizedString(forLanguageCode: two) ?? ""
        return name.isEmpty || name.lowercased() == two ? code.trimmingCharacters(in: .whitespaces) : name
    }

    public static func channels(_ n: Int?) -> String {
        switch n ?? 0 {
        case 0: return ""
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case let other: return "\(other) channels"
        }
    }

    /// Subtitles' formats in words: nobody knows what SUBRIP or HDMV_PGS_SUBTITLE means.
    public static func subtitleKind(_ codec: String?) -> String {
        let c = (codec ?? "").lowercased()
        if c == "ass" || c == "ssa" { return "Styled text" }
        if ["pgs", "dvd_sub", "dvdsub", "dvb_sub", "dvbsub", "vobsub", "xsub"].contains(where: { c.contains($0) }) { return "Pictures" }
        return c.isEmpty ? "" : "Text"
    }

    private static func own(_ track: Track, language: String) -> String {
        let title = (track.title ?? "").trimmingCharacters(in: .whitespaces)
        let l = title.lowercased()
        if title.isEmpty || l == language.lowercased() || l == (track.language ?? "").lowercased() { return "" }
        return title
    }

    private static func marks(_ track: Track, title: String) -> [String] {
        let t = title.lowercased()
        var marks: [String] = []
        if track.forced == true && !t.contains("forced") { marks.append("Forced") }
        if track.sdh == true && !t.contains("sdh") && !t.contains("hearing") { marks.append("SDH") }
        if track.commentary == true && !t.contains("comment") { marks.append("Commentary") }
        return marks
    }

    private static func name(_ track: Track, number: Int, fallback: String, detail: String) -> TrackName {
        let lang = Self.language(track)
        let ownName = Self.own(track, language: lang)
        let title = !lang.isEmpty ? lang : !ownName.isEmpty ? ownName : "\(fallback) \(number)"
        let sub = ([lang.isEmpty ? "" : ownName] + marks(track, title: ownName)).filter { !$0.isEmpty }.joined(separator: " · ")
        return TrackName(title: title, sub: sub, detail: detail)
    }

    /// `number` counts from 1 in the list as shown.
    public static func audio(_ track: Track, number: Int) -> TrackName {
        name(track, number: number, fallback: "Track", detail: [(track.codec ?? "").uppercased(), channels(track.channels)].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    public static func subtitle(_ track: Track, number: Int) -> TrackName {
        name(track, number: number, fallback: "Subtitles", detail: subtitleKind(track.codec))
    }

    /// Lists as shown: one row per track, numbered from 1.
    public static func audioList(_ tracks: [Track]) -> [(Track, TrackName)] {
        unique(tracks).enumerated().map { ($1, audio($1, number: $0 + 1)) }
    }

    public static func subtitleList(_ tracks: [Track]) -> [(Track, TrackName)] {
        unique(tracks).enumerated().map { ($1, subtitle($1, number: $0 + 1)) }
    }

    private static func unique(_ tracks: [Track]) -> [Track] {
        var seen = Set<Int>()
        return tracks.filter { seen.insert($0.index).inserted }
    }
}

public enum Scenes {
    /// Which chapter the film is in: the last one that has started, half a second's grace.
    public static func current(_ starts: [Double], at time: Double) -> Int {
        max(0, starts.filter { $0 <= time + 0.5 }.count - 1)
    }

    /// When a scene's picture is taken, as the website and Android take it: a quarter of the way in, between 2 and 20
    /// seconds, past a fade from black or a studio's logo and still in the scene.
    public static func pictureSec(_ chapters: [Chapter], _ index: Int, duration: Double) -> Int {
        guard chapters.indices.contains(index) else { return 0 }
        let from = chapters[index].start
        let to = chapters.indices.contains(index + 1) ? chapters[index + 1].start : (duration > from ? duration : from + 8)
        return Int((from + min(20, max(2, (to - from) / 4))).rounded(.down))
    }

    /// A chapter's name, or "Scene 3" when it has none.
    public static func name(_ chapters: [Chapter], _ index: Int) -> String {
        guard chapters.indices.contains(index), let title = chapters[index].title, !title.isEmpty else { return "Scene \(index + 1)" }
        return title
    }
}

/// The server's settings a player reads: `/prefs`.
public struct ServerPrefs: Decodable, Equatable {
    /// The fastest speed offered; 4 when it says nothing.
    public let maxSpeed: Double?
    /// False when the owner has taken the visualizer off the server.
    public let visualizer: Bool?
    /// The owner's arrangement of the menu, as JSON: see NavPrefs.owner.
    public let navDefault: String?
    /// How a show's episodes are laid out when it has no layout of its own: "cards" or "list".
    public let episodeView: String?
}

/// What to watch after something with no next episode: `/items/{id}/recommend`.
public struct Recommendation: Decodable, Equatable {
    public let item: Item?
    public let show: Show?
}
