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
    var opensOnAppleTV: Bool { opensHere || isPhotos || hasGameScreens || ["music", "audiobooks", "podcasts"].contains(type) }

    /// Games the server plays and streams, which Apple TV has its own screens and player for. A
    /// shared PC's games go through Moonlight instead: see Rigs.swift.
    var hasGameScreens: Bool { type == "games" && !isRigGames }
}

public extension Item {
    var isAudio: Bool { kind == "audio" }
    /// A game the server plays, as opposed to one on someone's own PC.
    var isServerGame: Bool { kind == "game" && !isRigGame }
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
    public let title: String
    public let sub: String?
    public let desc: String?
    public let rating: String?
    public let year: Int?

    /// How far through it is at this moment, from 0 to 1.
    public func fraction(at now: Int64) -> Double {
        guard end > start else { return 0 }
        return min(1, max(0, Double(now - start) / Double(end - start)))
    }

    /// Whole minutes left at this moment, rounded up. Never below one while it's on.
    public func minutesLeft(at now: Int64) -> Int {
        max(1, Int((end - now + 59) / 60))
    }
}

/// One channel from GET /guide. Channels and tuners aren't items, so they don't go through /playback.
public struct GuideChannel: Decodable, Identifiable, Equatable {
    public let key: String
    public let number: String?
    public let name: String
    public let radio: Bool?
    /// Why it can't be tuned. This server never decrypts a broadcast.
    public let encrypted: String?
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
}

/// What GET /tv/{key}/tune answers. AVPlayer always needs `streamUrl`, as it can't set headers.
public struct Tuned: Decodable, Equatable {
    public let url: String?
    public let streamUrl: String?
}
