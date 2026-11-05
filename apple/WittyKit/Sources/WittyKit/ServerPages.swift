import Foundation

// Which things have this app's own screens, and which open the server's own page inside the app.
// Video is built here. On iPhone and iPad everything else the server does, from music to books,
// photos, disc menus, the TV guide and its settings, is the server's page, so nothing it offers is
// out of reach. Apple TV has no web view, as tvOS doesn't offer WebKit to apps, so it has screens of
// its own for sound, photos and live channels, and says plainly what it can't show.

public enum ServerPages {
    public static let guide = "/tv"
    public static let collections = "/collections"
    public static let settings = "/settings"

    public static func path(_ library: Library) -> String { "/library/\(library.id)" }
    public static func path(_ item: Item) -> String { "/item/\(item.id)" }

    /// A row of songs or chapters shows each album or book once.
    public static func albumsOnce(_ items: [Item]) -> [Item] {
        var seen = Set<String>()
        return items.filter { item in
            guard item.kind == "audio", let album = item.album, !album.isEmpty else { return true }
            return seen.insert((item.albumArtist ?? item.artist ?? "") + "|" + album).inserted
        }
    }

    /// The tracks of one album, in order. Anything without a number comes after those with one.
    public static func tracks(of album: String, in items: [Item]) -> [Item] {
        items.filter { $0.album == album }.sorted {
            let a = $0.track ?? Int.max, b = $1.track ?? Int.max
            return a == b ? $0.title < $1.title : a < b
        }
    }

    /// What plays after this one in a list of tracks. Nothing at the end.
    public static func next(after id: Int64, in list: [Int64]) -> Int64? {
        guard let at = list.firstIndex(of: id), at + 1 < list.count else { return nil }
        return list[at + 1]
    }
}

public extension Library {
    /// Photos, whose pictures Apple TV can show by itself.
    var isPhotos: Bool { type == "photos" }

    /// What has a screen of its own on Apple TV, where nothing can fall back on the server's page.
    var opensOnAppleTV: Bool { opensHere || isPhotos || ["music", "audiobooks", "podcasts"].contains(type) }
}

public extension Item {
    var isAudio: Bool { kind == "audio" }
    var isPhoto: Bool { kind == "photo" }

    /// Whose album a track is on, which is how its album is asked for: the album's artist where
    /// there is one, else the track's own.
    var albumArtistName: String {
        if let albumArtist, !albumArtist.isEmpty { return albumArtist }
        return artist ?? ""
    }

    /// The name to show on a card: a song's album, as a row shows each album once.
    var cardTitle: String {
        if isAudio, let album, !album.isEmpty { return album }
        if let showTitle, !showTitle.isEmpty { return showTitle }
        return title
    }

    /// What goes under the name.
    var cardSubtitle: String {
        if isAudio { return albumArtist ?? artist ?? "" }
        return episodeLabel.isEmpty ? (year.map(String.init) ?? "") : episodeLabel
    }
}

/// One programme in the guide. Times are seconds since 1970, as the server sends them.
public struct GuideProgramme: Decodable, Equatable {
    public let start: Int64
    public let end: Int64
    /// `show`, `filler`, `slate`, `broadcast` or `none`. A slate is the channel's own "back soon".
    public let kind: String?
    public let title: String
    public let sub: String?
    public let desc: String?
    public let genre: String?
    public let rating: String?
    public let year: Int?
    /// What in the library it plays, for a library channel: its backdrop is the programme's picture.
    public let itemId: Int64?
    public let showId: Int64?
    public let season: Int?
    public let episode: Int?

    public init(start: Int64, end: Int64, kind: String? = nil, title: String, sub: String? = nil, desc: String? = nil, genre: String? = nil,
                rating: String? = nil, year: Int? = nil, itemId: Int64? = nil, showId: Int64? = nil, season: Int? = nil, episode: Int? = nil) {
        self.start = start
        self.end = end
        self.kind = kind
        self.title = title
        self.sub = sub
        self.desc = desc
        self.genre = genre
        self.rating = rating
        self.year = year
        self.itemId = itemId
        self.showId = showId
        self.season = season
        self.episode = episode
    }

    /// How far through it is at this moment, from 0 to 1.
    public func fraction(at now: Int64) -> Double {
        guard end > start else { return 0 }
        return min(1, max(0, Double(now - start) / Double(end - start)))
    }

    /// Whole minutes left at this moment, rounded up. Never below one while it's on.
    public func minutesLeft(at now: Int64) -> Int {
        max(1, Int((end - now + 59) / 60))
    }

    public func isOn(at now: Int64) -> Bool { start <= now && now < end }
}

/// Whether a channel is encrypted, in the server's words: every client shows the same.
public struct GuideSecurity: Decodable, Equatable {
    /// `clear`, `encrypted` or `unknown`.
    public let state: String
    public let label: String
    public let detail: String
}

/// The same station another way, for one that can't be watched as it is.
public struct GuideAlternative: Decodable, Equatable {
    public let key: String
    public let number: String
    public let name: String
}

/// The name a channel's logo goes by in the logo service.
public struct GuideBrand: Decodable, Equatable {
    public let kind: String
    public let name: String
}

/// One channel from GET /guide. Channels and tuners aren't items, so they don't go through /playback.
public struct GuideChannel: Decodable, Identifiable, Equatable {
    public let key: String
    /// `library` or `tuner`.
    public let kind: String?
    public let number: String?
    public let name: String
    public let group: String?
    public let radio: Bool?
    public let hd: Bool?
    public let atsc3: Bool?
    /// Why it can't be tuned. This server never decrypts a broadcast.
    public let encrypted: String?
    /// Whether Record is offered: the server's word alone, and missing means no. Only tuner channels the
    /// profile may record ever have it; no app works it out for itself (docs/APP-DESIGN.md, On a TV).
    public let canRecord: Bool?
    public let noRecord: String?
    public let security: GuideSecurity?
    public let alternative: GuideAlternative?
    public let notices: [String]?
    public let description: String?
    public let categories: [String]?
    /// The channel's own colour.
    public let accent: String?
    public var favourite: Bool?
    public let brand: GuideBrand?
    /// The owner's picture for it, as an address on the server. Not every channel has one.
    public let logo: String?
    public let programmes: [GuideProgramme]?

    public var id: String { key }
    public var canTune: Bool { (encrypted ?? "").isEmpty }
    public var label: String { [number, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ") }

    public func on(at now: Int64) -> GuideProgramme? {
        programmes?.first { $0.start <= now && now < $0.end }
    }

    public func next(after now: Int64) -> GuideProgramme? {
        programmes?.filter { $0.start > now }.min { $0.start < $1.start }
    }

    /// The same channel marked a favourite or not, as the guide shows it at once.
    public func with(favourite: Bool) -> GuideChannel {
        var copy = self
        copy.favourite = favourite
        return copy
    }
}

public extension ServerPages {
    /// The channel so many steps along, going round at the ends, as a remote's channel buttons do.
    /// Only those that can be tuned count.
    static func channel(from key: String, by step: Int, in channels: [GuideChannel]) -> GuideChannel? {
        let usable = channels.filter(\.canTune)
        guard !usable.isEmpty else { return nil }
        guard let at = usable.firstIndex(where: { $0.key == key }) else { return usable[0] }
        let count = usable.count
        return usable[((at + step) % count + count) % count]
    }
}

public struct Guide: Decodable, Equatable {
    public let channels: [GuideChannel]?
    /// The look the server's owner starts people on. `layout` and `skin` are from before there were themes.
    public let theme: String?
    public let layout: String?
    public let skin: String?
    /// How many channels there are with what was asked, and where this page of them starts.
    public let total: Int?
    public let offset: Int?
    /// The channel groups there are, for the guide's filters.
    public let groups: [String]?
}

/// What GET /tv/{key}/tune answers. AVPlayer always needs `streamUrl`, as it can't set headers.
public struct Tuned: Decodable, Equatable {
    public let url: String?
    public let streamUrl: String?
    public let key: String?
    public let number: String?
    public let name: String?
    public let logo: String?
    public let accent: String?
    /// What's on and what's next, which the banner shows.
    public let now: GuideProgramme?
    public let next: GuideProgramme?
    /// What a library channel is really playing, when that isn't the programme (a bumper, say).
    public let playing: GuideProgramme?
    public let notices: [String]?
    public let alternative: GuideAlternative?
    public let security: GuideSecurity?
    /// Where the channel is in what's on, and the server's clock then, for counting progress.
    public let positionSec: Double?
    public let serverTime: Double?
    public let countProgress: Bool?
}
