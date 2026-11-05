import Foundation

// The website's music videos, as rules the phone and tablet apps share: a music library's Music videos tab and its
// Home shelf (web/src/pages/music/MusicVideos.tsx, the video tile of creators/parts.tsx and gallery.ts), and Now
// Playing's Watch the video (audio/NowPlaying.tsx, music/links.ts). docs/CLIENT-API.md, Music videos.

/// The song or the video at one end of a tie, as `/music/links/{id}` and `/music/videos` send it.
public struct MusicLinkSide: Decodable, Equatable {
    public let id: Int64
    public let libraryId: Int64
    public let title: String
    /// A song's artist (its album's when it has none of its own), or a video's.
    public let artist: String
    public let album: String?
    public let runtimeSec: Double
    public let updatedAt: Int64?

    private enum CodingKeys: String, CodingKey { case id, libraryId, title, artist, album, runtimeSec, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        libraryId = (try? c.decodeIfPresent(Int64.self, forKey: .libraryId)) ?? 0
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        artist = (try? c.decodeIfPresent(String.self, forKey: .artist)) ?? ""
        album = try? c.decodeIfPresent(String.self, forKey: .album)
        runtimeSec = (try? c.decodeIfPresent(Double.self, forKey: .runtimeSec)) ?? 0
        updatedAt = try? c.decodeIfPresent(Int64.self, forKey: .updatedAt)
    }
}

/// A song tied to a music video, with what's at both ends.
public struct MusicLink: Decodable, Equatable {
    public let songId: Int64
    public let videoId: Int64
    /// `tied`, or `suggested` for an administrator to look at.
    public let state: String
    /// Why: `isrc`, `recording`, `name`, `close` or `hand`.
    public let how: String
    /// Where the song starts in the video, in milliseconds. Nil when the two don't line up.
    public let syncMs: Int64?
    public let by: String?
    public let song: MusicLinkSide
    public let video: MusicLinkSide
}

/// What one song or music video is tied to: `/music/links/{id}`. Only administrators get `suggested`.
public struct MusicLinks: Decodable, Equatable {
    public let itemId: Int64
    /// `song`, `video`, or empty for anything that can't be tied.
    public let role: String
    public let tied: [MusicLink]
    public let suggested: [MusicLink]
    public let canEdit: Bool

    private enum CodingKeys: String, CodingKey { case itemId, role, tied, suggested, canEdit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = (try? c.decodeIfPresent(Int64.self, forKey: .itemId)) ?? 0
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? ""
        tied = (try? c.decodeIfPresent([MusicLink].self, forKey: .tied)) ?? []
        suggested = (try? c.decodeIfPresent([MusicLink].self, forKey: .suggested)) ?? []
        canEdit = (try? c.decodeIfPresent(Bool.self, forKey: .canEdit)) ?? false
    }
}

/// A music video in a music library's Music videos: the creator video card (`VideoCard`), with the song it's tied
/// to when this person may see that song.
public struct MusicVideoCard: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let libraryId: Int64
    public let title: String
    public let durationSec: Double
    public let vertical: Bool
    public let creatorId: Int64
    /// Whose it is: the artist.
    public let creator: String
    public let hasAvatar: Bool
    public let uploadDate: String
    /// Plays on this server, and what the source said when it was archived.
    public let views: Int64
    public let origViews: Int64
    public let positionSec: Double
    public let watched: Bool
    public let updatedAt: Int64
    public let song: MusicLinkSide?
    public let syncMs: Int64?

    private enum CodingKeys: String, CodingKey {
        case id, libraryId, title, durationSec, vertical, creatorId, creator, hasAvatar, uploadDate, views, origViews, positionSec, watched,
             updatedAt, song, syncMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        libraryId = (try? c.decodeIfPresent(Int64.self, forKey: .libraryId)) ?? 0
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        durationSec = (try? c.decodeIfPresent(Double.self, forKey: .durationSec)) ?? 0
        vertical = (try? c.decodeIfPresent(Bool.self, forKey: .vertical)) ?? false
        creatorId = (try? c.decodeIfPresent(Int64.self, forKey: .creatorId)) ?? 0
        creator = (try? c.decodeIfPresent(String.self, forKey: .creator)) ?? ""
        hasAvatar = (try? c.decodeIfPresent(Bool.self, forKey: .hasAvatar)) ?? false
        uploadDate = (try? c.decodeIfPresent(String.self, forKey: .uploadDate)) ?? ""
        views = (try? c.decodeIfPresent(Int64.self, forKey: .views)) ?? 0
        origViews = (try? c.decodeIfPresent(Int64.self, forKey: .origViews)) ?? 0
        positionSec = (try? c.decodeIfPresent(Double.self, forKey: .positionSec)) ?? 0
        watched = (try? c.decodeIfPresent(Bool.self, forKey: .watched)) ?? false
        updatedAt = (try? c.decodeIfPresent(Int64.self, forKey: .updatedAt)) ?? 0
        song = try? c.decodeIfPresent(MusicLinkSide.self, forKey: .song)
        syncMs = try? c.decodeIfPresent(Int64.self, forKey: .syncMs)
    }

    /// The website's `viewsOf`: what the source said, plus plays here.
    public var allViews: Int64 { views + origViews }

    /// How far through it this person is, from 0 to 1: nothing once it's watched.
    public var progress: Double {
        guard !watched, durationSec > 0, positionSec > 0 else { return 0 }
        return min(1, positionSec / durationSec)
    }

    /// "1.2K views · 3 weeks ago", as under a video tile.
    public func facts(now: Date = Date()) -> String {
        [allViews > 0 ? "\(MusicVideos.shortCount(allViews)) views" : "", MusicVideos.ago(uploadDate, now: now)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The words on the song under the tile: "On Its Album", or "In your music" for a song with no album.
    public var songWords: String? {
        guard let song else { return nil }
        if let album = song.album, !album.isEmpty { return "On \(album)" }
        return "In your music"
    }
}

/// A page of music videos: `/music/videos`.
public struct MusicVideoPage: Decodable, Equatable {
    public let videos: [MusicVideoCard]
    public let more: Bool

    private enum CodingKeys: String, CodingKey { case videos, more }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videos = (try? c.decodeIfPresent([MusicVideoCard].self, forKey: .videos)) ?? []
        more = (try? c.decodeIfPresent(Bool.self, forKey: .more)) ?? false
    }
}

/// Where the song under a music video goes: its album, when it's in this library and has one; else its artist.
public enum MusicVideoSongPlace: Equatable {
    case album(library: Int64, album: String, artist: String)
    case artist(library: Int64, name: String)
}

public enum MusicVideos {
    /// How many the Music videos tab asks for at a time.
    public static let pageSize = 120
    /// How many the Home shelf shows: the newest.
    public static let shelfSize = 12

    /// Whether there's anywhere music videos could come from: a music videos library this person can see. A music
    /// library then has the Music videos tab and its shelf (`hasMusicVideos`).
    public static func available(in libraries: [Library]) -> Bool { libraries.contains { $0.type == "musicvideos" } }

    /// The tab's question: by artist, a page at a time, matching words when there are any.
    public static func path(search: String, offset: Int, limit: Int = pageSize) -> String {
        var path = "/music/videos?limit=\(limit)&offset=\(offset)"
        if !search.isEmpty { path += "&search=\(WittyClient.queryValue(search))" }
        return path
    }

    /// The Home shelf's question: the newest.
    public static let latestPath = "/music/videos?limit=\(shelfSize)&sort=latest"

    /// "1 video", "120+ videos": how many are showing, and whether there are more.
    public static func count(_ n: Int, more: Bool) -> String { "\(n.formatted())\(more ? "+" : "") \(n == 1 ? "video" : "videos")" }

    /// What an empty tab says.
    public static func empty(searching: Bool) -> (title: String, text: String) {
        searching ? ("Nothing matches that", "")
            : ("No music videos yet", "Add a library of the kind Music videos & concerts, and its videos appear here by artist.")
    }

    public static func songPlace(_ song: MusicLinkSide, library: Int64) -> MusicVideoSongPlace {
        if song.libraryId == library, let album = song.album, !album.isEmpty {
            return .album(library: library, album: album, artist: song.artist)
        }
        return .artist(library: song.libraryId, name: song.artist)
    }

    public enum End { case video, song }

    /// Where to be in the other one (`placeIn`): the song's place in the video is the song's time plus where the song
    /// starts in it. Nil when they don't line up, or when that place is in the first second or the last two.
    public static func place(in end: End, at seconds: Double, syncMs: Int64?, length: Double) -> Double? {
        guard let syncMs else { return nil }
        let offset = Double(syncMs) / 1000
        let t = end == .video ? seconds + offset : seconds - offset
        if t < 1 || (length > 0 && t > length - 2) { return nil }
        return t
    }

    /// A music video's page, from a place in it when there is one.
    public static func watchPath(videoId: Int64, at seconds: Double? = nil) -> String {
        guard let seconds, seconds >= 1 else { return "/watch/\(videoId)" }
        return "/watch/\(videoId)?t=\(Int(seconds.rounded(.down)))"
    }

    /// Watch the video from a song that's playing: the video's page, at the same place when the two line up.
    public static func watchPath(_ link: MusicLink, songAt seconds: Double) -> String {
        watchPath(videoId: link.videoId, at: place(in: .video, at: seconds, syncMs: link.syncMs, length: link.video.runtimeSec))
    }

    /// 1234 -> "1.2K" (`fmtCount`).
    public static func shortCount(_ n: Int64) -> String {
        func short(_ value: Double, _ unit: String) -> String {
            var words = String(format: "%.1f", value)
            if words.hasSuffix(".0") { words.removeLast(2) }
            return words + unit
        }
        if n >= 1_000_000_000 { return short(Double(n) / 1e9, "B") }
        if n >= 1_000_000 { return short(Double(n) / 1e6, "M") }
        if n >= 1_000 { return short(Double(n) / 1e3, "K") }
        return String(n)
    }

    /// "today", "yesterday", "3 weeks ago" from a date the server writes as `2024-05-31` (`timeAgo`). Nothing for a
    /// date it can't read.
    public static func ago(_ date: String, now: Date = Date()) -> String {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts[0].count == 4, parts.dropFirst().allSatisfy({ $0.count == 2 }),
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return "" }
        var day = DateComponents()
        day.year = Int(parts[0])
        day.month = parts.count > 1 ? Int(parts[1]) : 1
        day.day = parts.count > 2 ? Int(parts[2]) : 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let month = day.month, (1...12).contains(month), let d = day.day, (1...31).contains(d),
              let then = calendar.date(from: day) else { return "" }
        let days = Int((now.timeIntervalSince(then) / 86400).rounded(.down))
        if days < 1 { return "today" }
        if days < 2 { return "yesterday" }
        if days < 7 { return "\(days) days ago" }
        if days < 30 { return "\(days / 7) \(days < 14 ? "week" : "weeks") ago" }
        if days < 365 { return "\(days / 30) \(days < 60 ? "month" : "months") ago" }
        return "\(days / 365) \(days < 730 ? "year" : "years") ago"
    }

    /// A creator with no picture: their initial on a colour of their own, from their name (`hsl(h 35% 36%)`).
    public static func avatarColour(_ name: String) -> String { CategoryLook.hsl(Double(CategoryLook.hue(name)), 0.35, 0.36) }
}
