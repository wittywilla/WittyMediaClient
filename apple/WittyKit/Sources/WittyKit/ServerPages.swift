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

/// One channel from GET /guide. Channels and tuners aren't items, so they don't go through /playback.
public struct GuideChannel: Decodable, Identifiable, Equatable {
    public let key: String
    public let number: String?
    public let name: String
    public let radio: Bool?
    /// Why it can't be tuned. This server never decrypts a broadcast.
    public let encrypted: String?

    public var id: String { key }
    public var canTune: Bool { (encrypted ?? "").isEmpty }
    public var label: String { [number, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ") }
}

public struct Guide: Decodable, Equatable {
    public let channels: [GuideChannel]?
}

/// What GET /tv/{key}/tune answers. AVPlayer always needs `streamUrl`, as it can't set headers.
public struct Tuned: Decodable, Equatable {
    public let url: String?
    public let streamUrl: String?
}
