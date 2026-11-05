import Foundation

// The website's music, audiobook and podcast player, as rules the phone and tablet apps share
// (web/src/audio/: lyrics.ts, art.ts, NowPlaying.tsx, QueuePanel.tsx). docs/APP-DESIGN.md, Playback and the media player.

/// A line of a song, timed in milliseconds from the start.
public struct LyricLine: Decodable, Equatable {
    public let t: Double
    public let end: Double?
    public let text: String
    /// When each word starts, where the file says.
    public let words: [LyricWord]?

    public init(t: Double, end: Double? = nil, text: String, words: [LyricWord]? = nil) {
        self.t = t
        self.end = end
        self.text = text
        self.words = words
    }
}

/// What the server found for a song: `/music/lyrics/{id}`.
public struct Lyrics: Decodable, Equatable {
    public let itemId: Int64?
    public let source: String?
    public let sourceName: String?
    public let creditUrl: String?
    public let synced: Bool?
    public let lines: [LyricLine]?
    public let plain: String?
    public let instrumental: Bool?
    /// The listener's own correction, in milliseconds: later words are a positive number.
    public let offsetMs: Double?
    public let failed: String?
    /// Whether the server may look for words online, whether it has for this song, and whether this person may fix them.
    public let online: Bool?
    public let tried: Bool?
    public let canEdit: Bool?
    /// Another song's look-up is under way: ask again in a few seconds.
    public let retry: Bool?

    public var timed: [LyricLine] { synced == true ? (lines ?? []) : [] }
    public var hasWords: Bool { !timed.isEmpty || !(plain ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The line sung at this moment, or -1 before the first: the website's `lineAt`. `offset` is a timing
    /// the listener is trying out, before it's saved.
    public func lineAt(seconds: Double, offset: Double? = nil) -> Int {
        let ms = seconds * 1000 - (offset ?? offsetMs ?? 0)
        var lo = 0, hi = timed.count - 1, at = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if timed[mid].t <= ms { at = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return at
    }
}

/// What the lyrics panel says when a song has no words, in the website's words (LyricsPanel.tsx, NoLyrics).
public enum LyricWords {
    /// `fixHere` is false where there's no Fix beside the words, as in the apps: the website's own player has one.
    public static func none(_ lyrics: Lyrics, fixHere: Bool = true) -> [String] {
        if lyrics.failed?.isEmpty == false {
            return ["The lyrics source couldn't be reached just now. It'll be tried again next time."]
        }
        if lyrics.tried == true {
            return ["No words found for this song online." + (lyrics.canEdit == true && fixHere ? " Fix lets you search under another name, or add them yourself." : "")]
        }
        if lyrics.online == true { return ["No words found for this song."] }
        return ["No words here. A .lrc file with the same name as the song, beside it, is used first.",
                lyrics.canEdit == true
                    ? "Or find them online for free, if you agree: turn on online lyrics in Settings. Your server sends only the artist, title, album and length."
                    : "Whoever runs this server can also turn on finding them online."]
    }

    /// The timing between Sooner and Later: "On time", or "+0.25 s".
    public static func offset(_ ms: Double) -> String {
        ms == 0 ? "On time" : "\(ms > 0 ? "+" : "")\(String(format: "%.2f", ms / 1000)) s"
    }

    /// A nudge, kept within two minutes either way.
    public static func nudge(_ ms: Double, by: Double) -> Double { max(-120_000, min(120_000, ms + by)) }
}

/// The colour behind the full player, from its artwork, as the website reads it (art.ts): the most colourful bright
/// part of a 16 × 16 copy, lifted so it never vanishes on black. Channels 0–255; a grey for nothing to go on.
public enum ArtColour {
    public static let neutral = (red: 120.0, green: 120.0, blue: 135.0)

    /// `rgba` is the small copy's pixels, four bytes each.
    public static func pick(rgba: [UInt8]) -> (red: Double, green: Double, blue: Double) {
        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        var index = 0
        while index + 3 < rgba.count {
            let red = Double(rgba[index]), green = Double(rgba[index + 1]), blue = Double(rgba[index + 2])
            let high = max(red, green, blue), low = min(red, green, blue)
            let w = (high - low + 8) * (high + 24)
            r += red * w
            g += green * w
            b += blue * w
            weight += w
            index += 4
        }
        guard weight > 0 else { return neutral }
        r /= weight
        g /= weight
        b /= weight
        let peak = max(r, g, b, 1)
        let lift = min(2.2, 190 / peak)
        return (min(255, (r * lift).rounded()), min(255, (g * lift).rounded()), min(255, (b * lift).rounded()))
    }
}

/// The sleep timer's choices: minutes from now, or the end of what's playing.
public enum SleepChoices {
    public static let minutes = [15, 30, 45, 60, 90]

    public static func words(_ minutes: Int) -> String {
        minutes < 60 ? "In \(minutes) minutes" : minutes == 60 ? "In 1 hour" : "In 90 minutes"
    }

    /// "After this song", or for a book or a podcast "At the end of this chapter".
    public static func atTheEnd(books: Bool) -> String { books ? "At the end of this chapter" : "After this song" }
}

/// The speeds Now Playing offers, up to the server's limit.
public enum ListeningSpeeds {
    public static let all: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    public static func offered(max: Double?) -> [Float] {
        let limit = Float((max ?? 0) > 0 ? max! : 4)
        return all.filter { $0 <= limit }
    }
}

/// How the queue panel sums up what's to come: "4 to come · 13:20", or "Nothing after this".
public enum QueueWords {
    public static func toCome(_ durations: [Double]) -> String {
        guard !durations.isEmpty else { return "Nothing after this" }
        return "\(durations.count) to come · \(PlayerTime.format(durations.reduce(0, +)))"
    }
}
