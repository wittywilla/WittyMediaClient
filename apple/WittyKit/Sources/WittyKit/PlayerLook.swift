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

    public init(seekBar: Bool = true, chapterMarks: Bool = true, hideAfter: Double = 3.5, picture: String = "fit") {
        self.seekBar = seekBar
        self.chapterMarks = chapterMarks
        self.hideAfter = hideAfter
        self.picture = picture
    }

    // A saved set from another version, or one with fields this doesn't know, keeps what it can.
    private enum CodingKeys: String, CodingKey { case seekBar, chapterMarks, hideAfter, picture }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = ViewPrefs()
        seekBar = (try? c.decodeIfPresent(Bool.self, forKey: .seekBar)) ?? base.seekBar
        chapterMarks = (try? c.decodeIfPresent(Bool.self, forKey: .chapterMarks)) ?? base.chapterMarks
        hideAfter = (try? c.decodeIfPresent(Double.self, forKey: .hideAfter)) ?? base.hideAfter
        let shown = (try? c.decodeIfPresent(String.self, forKey: .picture)) ?? base.picture
        picture = shown == "fill" ? "fill" : "fit"
    }

    /// The website's choices for how long the controls stay.
    public static let hideChoices: [(Double, String)] = [(2, "2 s"), (3.5, "3.5 s"), (6, "6 s"), (0, "Never")]
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
        tracks.map { track in
            TrackTile(id: track.index, title: languageName(track), sub: track.title ?? "",
                      detail: [track.codec?.uppercased(), track.channels.flatMap { $0 > 0 ? "\($0) ch" : nil }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                      active: track.index == chosen)
        }
    }

    /// Off first, then every subtitle track.
    public static func subtitles(_ tracks: [Track], chosen: Int?) -> [TrackTile] {
        [TrackTile(id: -1, title: "Off", sub: "", detail: "", active: chosen == nil || (chosen ?? -1) < 0)]
            + tracks.map { track in
                TrackTile(id: track.index, title: languageName(track), sub: track.title ?? "", detail: track.codec?.uppercased() ?? "",
                          active: track.index == chosen)
            }
    }

    static func languageName(_ track: Track) -> String {
        if let name = track.languageName, !name.isEmpty { return name }
        guard let code = track.language, !code.isEmpty, code != "und" else { return "Unknown" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}

public enum Scenes {
    /// Which chapter the film is in: the last one that has started, half a second's grace.
    public static func current(_ starts: [Double], at time: Double) -> Int {
        max(0, starts.filter { $0 <= time + 0.5 }.count - 1)
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
}

/// What to watch after something with no next episode: `/items/{id}/recommend`.
public struct Recommendation: Decodable, Equatable {
    public let item: Item?
    public let show: Show?
}
