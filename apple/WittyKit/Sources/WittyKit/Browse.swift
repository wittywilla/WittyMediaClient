import Foundation

// A film or TV library's page, as the server's own website builds it (web/src/pages/library/VideoLibrary.tsx and
// Filters.tsx): its shelves first, and a grid once anything is asked for, with what's chosen kept as the website
// keeps it in its address, so a saved view means the same everywhere. Also how a library's size is said, and the
// collections an item can be saved to. See docs/APP-DESIGN.md, One mobile design with the website.

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

/// A studio or a network on a library's page, with how many titles it has there.
public struct ShelfBrand: Decodable, Equatable, Identifiable, Hashable {
    public let kind: String?
    public let name: String
    public let key: String
    public let count: Int?

    public var id: String { key }
}

/// A streaming service that lists some of a library's titles: only what's on the server, sorted by who lists it.
public struct ShelfPlatform: Decodable, Equatable, Identifiable, Hashable {
    public let key: String
    public let name: String
    public let count: Int?

    public var id: String { key }
}

/// Everything a library's page starts with, in one answer: `/browse/shelves`.
public struct Shelves: Decodable, Equatable {
    public let categories: [ShelfCategory]?
    public let collections: [ShelfCollection]?
    public let studios: [ShelfBrand]?
    public let networks: [ShelfBrand]?
    public let platforms: [ShelfPlatform]?

    public init(categories: [ShelfCategory]? = nil, collections: [ShelfCollection]? = nil, studios: [ShelfBrand]? = nil,
                networks: [ShelfBrand]? = nil, platforms: [ShelfPlatform]? = nil) {
        self.categories = categories
        self.collections = collections
        self.studios = studios
        self.networks = networks
        self.platforms = platforms
    }

    /// The categories to show, in the server's order; the ones its owner hid are left out.
    public var shown: [ShelfCategory] { (categories ?? []).filter { $0.hidden != true } }

    /// Too small or too bare for shelves: no categories, studios or networks. The website shows such a library
    /// as a grid from the start, whatever collections or services it has.
    public var bare: Bool { shown.isEmpty && (studios ?? []).isEmpty && (networks ?? []).isEmpty }

    /// The logos the page shows, as one lookup: the first 40 studios and networks, as the website's shelves
    /// cut them, and the services.
    public var logos: [LogoRef] {
        (studios ?? []).prefix(40).map { LogoRef(kind: "studio", name: $0.name) }
            + (networks ?? []).prefix(40).map { LogoRef(kind: "network", name: $0.name) }
            + (platforms ?? []).map { LogoRef(kind: "platform", name: $0.name) }
    }
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

    /// The choices that come from the library's facets. A score and watched or not are fixed: see `FilterSection`.
    public static let groups = [
        BrowseFilter(key: "genre", title: "Category", facets: "genres", limit: 24),
        BrowseFilter(key: "kind", title: "Type", facets: "kinds", limit: 24),
        BrowseFilter(key: "studio", title: "Studio", facets: "studios", limit: 16),
        BrowseFilter(key: "network", title: "Network", facets: "networks", limit: 16),
        BrowseFilter(key: "platform", title: "Listed on", facets: "platforms", limit: 24),
        BrowseFilter(key: "decade", title: "Decade", facets: "decades", limit: 24),
        BrowseFilter(key: "year", title: "Year", facets: "years", limit: 10),
        BrowseFilter(key: "content", title: "Age rating", facets: "content", limit: 24),
        BrowseFilter(key: "resolution", title: "Picture", facets: "resolutions", limit: 24),
        BrowseFilter(key: "format", title: "Sound", facets: "formats", limit: 24),
        BrowseFilter(key: "audio", title: "Audio language", facets: "audio", limit: 24),
        BrowseFilter(key: "subtitle", title: "Subtitles", facets: "subtitles", limit: 24),
        BrowseFilter(key: "edition", title: "Edition", facets: "editions", limit: 24),
        BrowseFilter(key: "tag", title: "Tags", facets: "tags", limit: 24),
    ]

    /// The fixed choices, which have no facets: a score, and watched or not.
    public static let scores = ["9", "8", "7", "6"]
    public static let watched = [("no", "Not watched yet"), ("yes", "Watched")]

    /// This group's choices from the library's facets. "No sound" isn't something to look for.
    public func choices(in facets: Facets) -> [Facet] {
        let list = facets[self.facets]
        return key == "format" ? list.filter { $0.value != "none" } : list
    }

    /// A filter's name on the chip that takes it off: the website's LABELS, which say "Tag" where the sheet
    /// says "Tags".
    public static let labels = [
        "genre": "Category", "studio": "Studio", "network": "Network", "kind": "Type", "disc": "On disc", "decade": "Decade",
        "year": "Year", "content": "Age rating", "minRating": "Score", "resolution": "Picture", "audio": "Audio language",
        "subtitle": "Subtitles", "format": "Sound", "tag": "Tag", "edition": "Edition", "series": "Collection",
        "watched": "Watched", "platform": "Listed on", "search": "Words",
    ]

    public static func title(of key: String) -> String { labels[key] ?? key }

    /// A chosen value in words, as the website says it (Filters.tsx, `friendly`).
    public static func words(_ key: String, _ value: String) -> String {
        switch key {
        case "audio", "subtitle": return languageName(value)
        case "minRating": return "\(value) or more"
        case "decade": return "\(value)s"
        case "watched": return value == "yes" ? "Watched" : "Not watched yet"
        case "kind": return ["video": "Video files", "dvd": "DVDs", "bluray": "Blu-rays", "disc": "DVDs and Blu-rays", "show": "TV shows"][value] ?? value
        case "disc": return ["movie": "Films", "tv": "TV series", "music": "Music"][value] ?? value
        case "resolution": return ["4k": "4K", "1080p": "1080p", "720p": "720p", "sd": "SD"][value] ?? value
        default: return value
        }
    }

    /// The website's names for the language codes files and discs use (api.ts, `LANGS`), then the system's, then
    /// the code as it is.
    private static let languages = [
        "en": "English", "nl": "Dutch", "fr": "French", "de": "German", "es": "Spanish", "it": "Italian", "pt": "Portuguese", "ja": "Japanese",
        "zh": "Chinese", "ko": "Korean", "ru": "Russian", "sv": "Swedish", "da": "Danish", "no": "Norwegian", "fi": "Finnish", "pl": "Polish",
        "cs": "Czech", "hu": "Hungarian", "el": "Greek", "tr": "Turkish", "he": "Hebrew", "ar": "Arabic", "hi": "Hindi", "th": "Thai",
        "eng": "English", "dut": "Dutch", "nld": "Dutch", "fre": "French", "fra": "French", "ger": "German", "deu": "German", "spa": "Spanish",
        "ita": "Italian", "por": "Portuguese", "jpn": "Japanese", "chi": "Chinese", "zho": "Chinese", "kor": "Korean", "rus": "Russian", "und": "Unknown",
        "gre": "Greek", "rum": "Romanian", "cze": "Czech", "ice": "Icelandic", "per": "Persian", "baq": "Basque", "slo": "Slovak", "mac": "Macedonian",
        "alb": "Albanian", "arm": "Armenian", "geo": "Georgian", "bur": "Burmese", "may": "Malay", "wel": "Welsh", "tib": "Tibetan", "mul": "Several languages", "zxx": "None",
    ]

    public static func languageName(_ code: String) -> String {
        guard !code.isEmpty else { return "Unknown" }
        let lower = code.lowercased()
        if let name = languages[lower] { return name }
        if let name = Locale(identifier: "en").localizedString(forLanguageCode: lower), name.lowercased() != lower { return name }
        return code.uppercased()
    }
}

/// One part of the website's Filters sheet, in its order: the facet groups, with a score and watched or not
/// after the age rating.
public enum FilterSection: Equatable, Identifiable {
    case facets(BrowseFilter)
    case score
    case watched

    public var id: String {
        switch self {
        case .facets(let filter): return filter.key
        case .score: return "minRating"
        case .watched: return "watched"
        }
    }

    public var title: String {
        switch self {
        case .facets(let filter): return filter.title
        case .score: return "Score"
        case .watched: return "Watched"
        }
    }

    public static let all: [FilterSection] = {
        let groups = BrowseFilter.groups.map(FilterSection.facets)
        let at = (groups.firstIndex { $0.id == "content" } ?? groups.count - 1) + 1
        return Array(groups[..<at]) + [.score, .watched] + Array(groups[at...])
    }()
}

// MARK: - A library page's address

/// Everything a film or TV library's page shows, as the website keeps it in its address
/// (`/library/3?genre=Drama&sort=rating&desc=1`). A saved view is this, written down.
public struct LibraryState: Equatable, Hashable {
    /// A sort someone chose. None is the shelves, or Title A to Z in a grid.
    public var sort: String?
    public var descending = false
    /// Fixed for one shuffle, so the next page is the same shuffle.
    public var seed: Int?
    public var filters: [String: String] = [:]
    /// "All films": the grid with nothing chosen.
    public var all = false

    public init(sort: String? = nil, descending: Bool = false, seed: Int? = nil, filters: [String: String] = [:], all: Bool = false) {
        self.sort = sort
        self.descending = descending
        self.seed = seed
        self.filters = filters
        self.all = all
    }

    /// The filters that are on, in the website's order.
    public var chosen: [(key: String, value: String)] { BrowseQuery(library: 0, filters: filters).chosen }

    /// Something asked for: a grid rather than shelves.
    public var asGrid: Bool { !chosen.isEmpty || sort != nil || all }

    /// A library with nothing to put on shelves is a grid from the start.
    public func grid(bare: Bool) -> Bool { asGrid || bare }

    /// The sort to show as chosen: Title A to Z is what a grid is in until another is chosen.
    public func shownSort(grid: Bool) -> String? { sort ?? (grid ? "title" : nil) }

    /// Whether the sort can be turned round. Shuffle has no direction, and Newest and Oldest are each other's.
    public var turns: Bool {
        guard let sort, LibrarySort.all.contains(where: { $0.key == sort }) else { return false }
        return !["shuffle", "newest", "oldest"].contains(sort)
    }

    public func query(library: Int64) -> BrowseQuery {
        BrowseQuery(library: library, sort: sort ?? "title", descending: descending, filters: filters, seed: seed)
    }

    /// A sort starts in its own direction; a shuffle gets a new order each time it's chosen.
    public mutating func choose(_ choice: LibrarySort, seed shuffle: Int) {
        sort = choice.key
        descending = choice.descending
        seed = choice.key == "shuffle" ? shuffle : nil
    }

    /// A filter set, or taken off with nothing.
    public mutating func set(_ key: String, _ value: String) {
        filters[key] = value.isEmpty ? nil : value
    }

    /// A saved view's query, as the website reads an address: `genre=Sci-Fi+%26+Fantasy&sort=rating&desc=1`.
    public init(query: String) {
        var fields: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first.map({ Self.formDecode(String($0)) }), fields[name] == nil else { continue }
            fields[name] = parts.count > 1 ? Self.formDecode(String(parts[1])) : ""
        }
        self.init()
        for key in BrowseFilter.keys { if let value = fields[key], !value.isEmpty { filters[key] = value } }
        if let sort = fields["sort"], !sort.isEmpty { self.sort = sort }
        descending = fields["desc"] == "1"
        seed = fields["seed"].flatMap { Int($0) }
        all = fields["view"] == "all"
    }

    /// What Save this view keeps: the filters, then the sort and its direction (not a shuffle's seed).
    public var savedQuery: String { written(whole: false) }

    /// All of it, for the server's own page of the library: a shuffle's seed and "All films" too.
    public var address: String { written(whole: true) }

    private func written(whole: Bool) -> String {
        var parts = chosen.map { "\($0.key)=\(Self.formEncode($0.value))" }
        if let sort { parts.append("sort=\(Self.formEncode(sort))") }
        if descending { parts.append("desc=1") }
        if whole, let seed { parts.append("seed=\(seed)") }
        if whole, all { parts.append("view=all") }
        return parts.joined(separator: "&")
    }

    /// The name Save this view suggests: what's chosen, in words.
    public var suggestedName: String {
        String(chosen.map { BrowseFilter.words($0.key, $0.value) }.joined(separator: ", ").prefix(60))
    }

    /// As a browser writes a form: letters, digits and `*-._` as they are, a space as `+`, the rest escaped.
    static func formEncode(_ text: String) -> String {
        var out = ""
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
                out.unicodeScalars.append(Unicode.Scalar(byte))
            case UInt8(ascii: " "):
                out += "+"
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    static func formDecode(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}

/// A view someone saved of a library: `/views`.
public struct SavedView: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let libraryId: Int64?
    public let name: String
    public let query: String?
    public let pinned: Bool?
    public let position: Int?

    public var state: LibraryState { LibraryState(query: query ?? "") }
}

/// Whether streaming listings are on, for which region and how fresh: `/listings/status`.
public struct ListingStatus: Decodable, Equatable {
    public let enabled: Bool?
    public let region: String?
    /// Seconds since 1970 of the newest listing, or 0.
    public let newest: Int64?
    public let attribution: String?
}

/// A library's scan, while there is one: `GET /libraries/{id}/scan`.
public struct ScanState: Decodable, Equatable {
    public struct Progress: Decodable, Equatable {
        public let done: Int?
        public let found: Int?

        public init(done: Int? = nil, found: Int? = nil) {
            self.done = done
            self.found = found
        }
    }

    public let scanning: Bool?
    public let progress: Progress?

    /// "Scanning… 12/40", as the website's button says it; "?" until the files are counted.
    public static func words(_ progress: Progress) -> String {
        "Scanning… \(progress.done ?? 0)/\(progress.found.map(String.init) ?? "?")"
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

    /// A category's row shows 20; when it has more, its "See all" says how many.
    public static func seeAll(_ count: Int?) -> String {
        guard let count, count > 20 else { return "See all" }
        return "See all \(count)"
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

/// Home's rows in the website's order (web/src/pages/HomePage.tsx): everything in progress as one
/// "Jump back in" row, then the recommendations, then every other row as the server sent it.
public enum HomeRows {
    public static let jumpBackIn = "jump"

    public static func rows(_ home: Home, recommended: Recommended? = nil) -> [Hub] {
        let hubs = home.hubs ?? []
        let going = hubs.filter { $0.key.hasPrefix("continue") }
        var rows: [Hub] = []
        let jump = Hub(key: jumpBackIn, title: "Jump back in", libraryId: nil,
                       items: going.flatMap { $0.items ?? [] }, shows: going.flatMap { $0.shows ?? [] })
        if !jump.isEmpty { rows.append(jump) }
        if let recommended {
            let row = Hub(key: "foryou", title: recommended.title, libraryId: nil, items: recommended.items, shows: recommended.shows)
            if !row.isEmpty { rows.append(row) }
        }
        rows += hubs.filter { !$0.key.hasPrefix("continue") && !$0.isEmpty }
        // A server that sends the same row twice still shows it once.
        var seen = Set<String>()
        return rows.filter { seen.insert($0.key).inserted }
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
