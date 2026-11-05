import Foundation

// A film or TV library's page, as the server's own website builds it (web/src/pages/library/VideoLibrary.tsx):
// its categories first, then rows, and a grid once a sort is chosen. Also how a library's size is said,
// and the collections an item can be saved to. See docs/APP-DESIGN.md, One mobile design with the website.

/// A picture standing for a category: the backdrop of something in it.
public struct CategoryArt: Decodable, Equatable, Hashable {
    public let type: String
    public let id: Int64
    public let v: Int64?

    public var isShow: Bool { type == "show" }
}

/// A genre as a library groups it, with how many titles it has.
public struct ShelfCategory: Decodable, Equatable, Identifiable, Hashable {
    public let key: String
    public let name: String
    public let count: Int?
    public let hidden: Bool?
    public let art: [CategoryArt]?

    public var id: String { key }
}

/// A collection a library offers on its page.
public struct ShelfCollection: Decodable, Equatable, Identifiable, Hashable {
    public let id: Int64?
    public let key: String?
    public let name: String
    public let count: Int?
    public let art: [CategoryArt]?
}

/// Everything a library's page starts with, in one answer: `/browse/shelves`.
public struct Shelves: Decodable, Equatable {
    public let categories: [ShelfCategory]?
    public let collections: [ShelfCollection]?

    public init(categories: [ShelfCategory]? = nil, collections: [ShelfCollection]? = nil) {
        self.categories = categories
        self.collections = collections
    }

    /// The categories to show, in the server's order; the ones its owner hid are left out.
    public var shown: [ShelfCategory] { (categories ?? []).filter { $0.hidden != true } }
}

/// One title in a browse answer: a film (an item) or a whole show.
public struct BrowseRow: Decodable, Equatable, Identifiable {
    public let type: String
    public let item: Item?
    public let show: Show?

    public var id: String { show.map { "show\($0.id)" } ?? item.map { "item\($0.id)" } ?? type }
}

public struct BrowseResult: Decodable, Equatable {
    public let results: [BrowseRow]?
    public let total: Int?

    public var items: [Item] { (results ?? []).compactMap(\.item) }
    public var shows: [Show] { (results ?? []).compactMap(\.show) }
}

/// How a library can be sorted, in the website's order and words.
public struct LibrarySort: Equatable, Identifiable, Hashable {
    public let key: String
    public let label: String
    /// Whether it runs from the most to the least: newest added, highest rated.
    public let descending: Bool

    public var id: String { key }

    public static let all = [
        LibrarySort(key: "shuffle", label: "Shuffle", descending: false),
        LibrarySort(key: "added", label: "Recently added", descending: true),
        LibrarySort(key: "title", label: "Title A to Z", descending: false),
        LibrarySort(key: "newest", label: "Newest", descending: false),
        LibrarySort(key: "oldest", label: "Oldest", descending: false),
        LibrarySort(key: "rating", label: "Highest rated", descending: true),
        LibrarySort(key: "quality", label: "Best quality", descending: true),
    ]
}

/// What a browse asks the server for. Nothing typed by anyone goes in unescaped.
public struct BrowseQuery: Equatable, Hashable {
    public var library: Int64
    public var sort: String = "title"
    public var descending = false
    /// The website's filters by their names (`genre`, `decade`, `minRating`, `watched`…): see `BrowseFilter`.
    public var filters: [String: String] = [:]
    /// Fixed for one shuffle, so the next page is the same shuffle.
    public var seed: Int?

    public init(library: Int64, sort: String = "title", descending: Bool = false, filters: [String: String] = [:], seed: Int? = nil) {
        self.library = library
        self.sort = sort
        self.descending = descending
        self.filters = filters
        self.seed = seed
    }

    /// The filters that are set, in the website's order.
    public var chosen: [(key: String, value: String)] {
        BrowseFilter.keys.compactMap { key in filters[key].flatMap { $0.isEmpty ? nil : (key, $0) } }
    }

    public func path(offset: Int = 0, limit: Int) -> String {
        var parts = ["library=\(library)", "sort=\(WittyClient.queryValue(sort))"]
        if descending { parts.append("desc=1") }
        for (key, value) in chosen { parts.append("\(key)=\(WittyClient.queryValue(value))") }
        if let seed { parts.append("seed=\(seed)") }
        parts.append("limit=\(max(1, limit))")
        if offset > 0 { parts.append("offset=\(offset)") }
        return "/browse?" + parts.joined(separator: "&")
    }
}

/// One choice in a filter, and how many titles it has.
public struct Facet: Decodable, Equatable, Hashable, Identifiable {
    public let value: String
    public let label: String?
    public let count: Int?

    public var id: String { value }
}

/// What a library's titles can be filtered by: `/browse/facets`. Groups the server leaves out, or sends as
/// null, are empty.
public struct Facets: Decodable, Equatable {
    public let groups: [String: [Facet]]

    public init(groups: [String: [Facet]]) { self.groups = groups }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var groups: [String: [Facet]] = [:]
        for key in container.allKeys {
            // A group this app doesn't know the shape of is left out, rather than failing the rest.
            if let list = try? container.decodeIfPresent([Facet].self, forKey: key) { groups[key.stringValue] = list }
        }
        self.groups = groups
    }

    public subscript(_ name: String) -> [Facet] { groups[name] ?? [] }
}

/// The website's filters (web/src/pages/library/Filters.tsx): the query key, its name, and which facets offer it.
public struct BrowseFilter: Equatable, Identifiable {
    public let key: String
    public let title: String
    public let facets: String
    /// How many choices show before "more".
    public let limit: Int

    public var id: String { key }

    public static let keys = ["genre", "studio", "network", "kind", "disc", "decade", "year", "content", "minRating", "resolution",
                              "audio", "subtitle", "format", "tag", "edition", "series", "watched", "platform", "search"]

    /// In the order the website's Filters sheet has them.
    public static let groups = [
        BrowseFilter(key: "genre", title: "Category", facets: "genres", limit: 24),
        BrowseFilter(key: "kind", title: "Type", facets: "kinds", limit: 24),
        BrowseFilter(key: "studio", title: "Studio", facets: "studios", limit: 16),
        BrowseFilter(key: "network", title: "Network", facets: "networks", limit: 16),
        BrowseFilter(key: "decade", title: "Decade", facets: "decades", limit: 24),
        BrowseFilter(key: "year", title: "Year", facets: "years", limit: 10),
        BrowseFilter(key: "content", title: "Age rating", facets: "content", limit: 24),
        BrowseFilter(key: "resolution", title: "Picture", facets: "resolutions", limit: 24),
        BrowseFilter(key: "audio", title: "Audio language", facets: "audio", limit: 24),
        BrowseFilter(key: "subtitle", title: "Subtitles", facets: "subtitles", limit: 24),
    ]

    /// The fixed choices, which have no facets: a score, and watched or not.
    public static let scores = ["9", "8", "7", "6"]
    public static let watched = [("no", "Not watched yet"), ("yes", "Watched")]

    /// A filter's name on the chip that takes it off.
    public static func title(of key: String) -> String {
        switch key {
        case "minRating": return "Score"
        case "watched": return "Watched"
        case "search": return "Words"
        case "disc": return "On disc"
        case "series": return "Collection"
        default: return groups.first { $0.key == key }?.title ?? key.capitalized
        }
    }

    /// A chosen value in words, as the website says it.
    public static func words(_ key: String, _ value: String) -> String {
        switch key {
        case "minRating": return "\(value) or more"
        case "watched": return watched.first { $0.0 == value }?.1 ?? value
        case "kind": return ["video": "Video files", "dvd": "DVDs", "bluray": "Blu-rays", "disc": "DVDs and Blu-rays", "show": "TV shows"][value] ?? value
        case "resolution": return ["4k": "4K", "1080p": "1080p", "720p": "720p", "sd": "SD"][value] ?? value
        default: return value
        }
    }
}

/// A collection of the person's own, or one shared with them.
public struct TitleCollection: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let ownerId: Int64?
    public let name: String
    public let kind: String?
    public let count: Int?
    /// One the server keeps itself, such as Liked songs: nothing is added to it by hand.
    public let system: String?
    /// A title whose picture stands for the collection.
    public let coverId: Int64?

    /// Only a hand-made collection takes titles; a smart one fills itself.
    public var takesTitles: Bool { kind != "smart" }
    /// A playlist songs can be added to, as the website's "Add to a playlist" lists them.
    public var isPlaylist: Bool { kind == "manual" && (system ?? "").isEmpty }
}

public enum LibraryWords {
    /// "35 titles", "1 episode", "2,286 games": the website's words for each kind of library.
    public static func count(_ count: Int, type: String) -> String {
        let nouns: [String: (String, String)] = [
            "movies": ("title", "titles"), "discs": ("disc", "discs"), "videos": ("video", "videos"),
            "commercials": ("commercial", "commercials"), "shows": ("episode", "episodes"), "anime": ("episode", "episodes"),
            "games": ("game", "games"), "music": ("track", "tracks"), "audiobooks": ("file", "files"),
            "podcasts": ("episode", "episodes"), "books": ("book", "books"), "photos": ("picture", "pictures"),
            "shorts": ("video", "videos"), "channels": ("video", "videos"), "musicvideos": ("video", "videos"),
            "radio": ("station", "stations"),
        ]
        let (one, many) = nouns[type] ?? ("item", "items")
        let number = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return "\(number) \(count == 1 ? one : many)"
    }

    /// What a library page counts: films, shows, discs or videos.
    public static func titles(_ count: Int, type: String) -> String {
        let noun: (String, String)
        switch type {
        case "shows", "anime": noun = ("show", "shows")
        case "discs": noun = ("disc", "discs")
        case "videos": noun = ("video", "videos")
        default: noun = ("film", "films")
        }
        return "\(count) \(count == 1 ? noun.0 : noun.1)"
    }
}

/// Titles chosen from what this profile watches: `/me/recommended`.
public struct Recommended: Decodable, Equatable {
    public let because: String?
    public let items: [Item]?
    public let shows: [Show]?

    public init(because: String?, items: [Item]?, shows: [Show]?) {
        self.because = because
        self.items = items
        self.shows = shows
    }

    /// "Because you watch …" when the server says why, as the website names the row.
    public var title: String {
        guard let because, !because.isEmpty else { return "Recommended for you" }
        return "Because you watch \(because)"
    }
}

/// Search results by what they are, as docs/APP-DESIGN.md's Search has them: Films, Shows, Music, Books…
public struct SearchGroup: Equatable, Identifiable {
    public let title: String
    public let items: [Item]
    public let shows: [Show]

    public var id: String { title }
}

public enum SearchGroups {
    /// Each group's name, in the order they're shown, by the kind of library a result is in.
    static let order: [(title: String, types: Set<String>)] = [
        ("Films", ["movies"]),
        ("Shows", ["shows", "anime"]),
        ("Discs", ["discs"]),
        ("Videos", ["videos", "channels", "musicvideos", "shorts", "commercials"]),
        ("Music", ["music"]),
        ("Audiobooks", ["audiobooks"]),
        ("Podcasts", ["podcasts"]),
        ("Books", ["books"]),
        ("Games", ["games"]),
        ("Photos", ["photos"]),
        ("Radio", ["radio"]),
    ]

    /// Shows go with the Shows; anything in a library this device doesn't know goes last, as "Everything else".
    public static func group(items: [Item], shows: [Show], libraryTypes: [Int64: String]) -> [SearchGroup] {
        var groups: [SearchGroup] = []
        var placed = Set<Int64>()
        for (title, types) in order {
            let mine = items.filter { item in item.libraryId.flatMap { libraryTypes[$0] }.map(types.contains) ?? false }
            placed.formUnion(mine.map(\.id))
            let showsHere = title == "Shows" ? shows : []
            if !mine.isEmpty || !showsHere.isEmpty { groups.append(SearchGroup(title: title, items: mine, shows: showsHere)) }
        }
        let rest = items.filter { !placed.contains($0.id) }
        if !rest.isEmpty { groups.append(SearchGroup(title: groups.isEmpty ? "Results" : "Everything else", items: rest, shows: [])) }
        return groups
    }
}
