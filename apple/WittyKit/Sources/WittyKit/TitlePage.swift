import Foundation

// A film's, an episode's, a disc's and a show's page, as the server's own website builds them at phone size
// (web/src/pages/ItemPage.tsx, ShowPage.tsx and components/edit/TitleExtras.tsx): the words, the facts and
// which rows go behind "⋯", worked out here so every screen says them the same way.

/// What else `GET /items/{id}` says that only an item's page shows. Read beside `Item` from the same answer, so
/// the item every list uses stays small. Anything that can't be read counts as absent: a page never fails over
/// one odd fact.
public struct ItemFacts: Decodable, Equatable {
    public let rating: Double?
    /// The poster's source; empty when there's none, and `cache:frame-…` or `cache:thumb-…` for a frame of the video.
    public let poster: String?
    public let backdrop: String?
    public let provider: String?
    public let providerId: String?
    public let width: Int?
    public let height: Int?
    public let videoCodec: String?
    public let container: String?
    public let audioLangs: [String]?
    public let subLangs: [String]?
    public let sizeBytes: Int64?
    public let path: String?
    public let disc: DiscInfo?
    /// How a disc starts and whether it plays the tray, with the server's defaults already applied.
    public let startMode: String?
    public let insertEffect: Bool?
    /// Which of a disc's titles was being watched.
    public let discTitle: Int?

    private enum CodingKeys: String, CodingKey {
        case rating, poster, backdrop, provider, providerId, width, height, videoCodec, container, audioLangs, subLangs
        case sizeBytes, path, disc, startMode, insertEffect, progress
    }

    private struct DiscProgress: Decodable { let discTitle: Int? }

    public init(rating: Double? = nil, poster: String? = nil, backdrop: String? = nil, provider: String? = nil, providerId: String? = nil,
                width: Int? = nil, height: Int? = nil, videoCodec: String? = nil, container: String? = nil, audioLangs: [String]? = nil,
                subLangs: [String]? = nil, sizeBytes: Int64? = nil, path: String? = nil, disc: DiscInfo? = nil, startMode: String? = nil,
                insertEffect: Bool? = nil, discTitle: Int? = nil) {
        self.rating = rating
        self.poster = poster
        self.backdrop = backdrop
        self.provider = provider
        self.providerId = providerId
        self.width = width
        self.height = height
        self.videoCodec = videoCodec
        self.container = container
        self.audioLangs = audioLangs
        self.subLangs = subLangs
        self.sizeBytes = sizeBytes
        self.path = path
        self.disc = disc
        self.startMode = startMode
        self.insertEffect = insertEffect
        self.discTitle = discTitle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = try? c.decodeIfPresent(Double.self, forKey: .rating)
        poster = try? c.decodeIfPresent(String.self, forKey: .poster)
        backdrop = try? c.decodeIfPresent(String.self, forKey: .backdrop)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        providerId = (try? c.decodeIfPresent(String.self, forKey: .providerId)) ?? (try? c.decodeIfPresent(Int64.self, forKey: .providerId)).flatMap { $0.map(String.init) }
        width = try? c.decodeIfPresent(Int.self, forKey: .width)
        height = try? c.decodeIfPresent(Int.self, forKey: .height)
        videoCodec = try? c.decodeIfPresent(String.self, forKey: .videoCodec)
        container = try? c.decodeIfPresent(String.self, forKey: .container)
        audioLangs = try? c.decodeIfPresent([String].self, forKey: .audioLangs)
        subLangs = try? c.decodeIfPresent([String].self, forKey: .subLangs)
        sizeBytes = (try? c.decodeIfPresent(Int64.self, forKey: .sizeBytes)) ?? (try? c.decodeIfPresent(Double.self, forKey: .sizeBytes)).flatMap { $0.map { Int64($0) } }
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        disc = try? c.decodeIfPresent(DiscInfo.self, forKey: .disc)
        startMode = try? c.decodeIfPresent(String.self, forKey: .startMode)
        insertEffect = try? c.decodeIfPresent(Bool.self, forKey: .insertEffect)
        discTitle = (try? c.decodeIfPresent(DiscProgress.self, forKey: .progress))??.discTitle
    }
}

/// A DVD's or a Blu-ray's own description: its titles and which is the film.
public struct DiscInfo: Decodable, Equatable {
    public let label: String?
    public let hasMenus: Bool?
    public let mainTitle: Int?
    public let titles: [DiscTitle]?
    public let scrambled: Bool?
    /// "movie" or "tv": a film, or episodes of a series.
    public let content: String?

    public init(label: String? = nil, hasMenus: Bool? = nil, mainTitle: Int? = nil, titles: [DiscTitle]? = nil, scrambled: Bool? = nil, content: String? = nil) {
        self.label = label
        self.hasMenus = hasMenus
        self.mainTitle = mainTitle
        self.titles = titles
        self.scrambled = scrambled
        self.content = content
    }
}

public struct DiscTitle: Decodable, Equatable {
    public let number: Int
    public let wide: Bool?
    /// "pal" or "ntsc" on a DVD; a Blu-ray's resolution, such as "1080p".
    public let standard: String?

    public init(number: Int, wide: Bool? = nil, standard: String? = nil) {
        self.number = number
        self.wide = wide
        self.standard = standard
    }
}

/// What else `GET /shows/{id}` says about the show that only its page shows.
public struct ShowFacts: Decodable, Equatable {
    public let libraryId: Int64?
    public let genres: [String]?
    public let contentRating: String?
    public let network: String?
    public let status: String?
    public let provider: String?
    public let providerId: String?
    /// Its own episode layout: "cards", "list", or empty for the server's.
    public let view: String?

    private enum CodingKeys: String, CodingKey { case libraryId, genres, contentRating, network, status, provider, providerId, view }
    private enum Outer: String, CodingKey { case show }

    public init(libraryId: Int64? = nil, genres: [String]? = nil, contentRating: String? = nil, network: String? = nil, status: String? = nil,
                provider: String? = nil, providerId: String? = nil, view: String? = nil) {
        self.libraryId = libraryId
        self.genres = genres
        self.contentRating = contentRating
        self.network = network
        self.status = status
        self.provider = provider
        self.providerId = providerId
        self.view = view
    }

    /// Read from the whole answer, whose `show` holds these.
    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let c = try outer.nestedContainer(keyedBy: CodingKeys.self, forKey: .show)
        libraryId = try? c.decodeIfPresent(Int64.self, forKey: .libraryId)
        genres = try? c.decodeIfPresent([String].self, forKey: .genres)
        contentRating = try? c.decodeIfPresent(String.self, forKey: .contentRating)
        network = try? c.decodeIfPresent(String.self, forKey: .network)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        providerId = (try? c.decodeIfPresent(String.self, forKey: .providerId)) ?? (try? c.decodeIfPresent(Int64.self, forKey: .providerId)).flatMap { $0.map(String.init) }
        view = try? c.decodeIfPresent(String.self, forKey: .view)
    }
}

/// Which kind of title a metadata route is about.
public enum TitleTarget: String {
    case item, show
}

/// A title's extras, versions, studios and the rest beyond its row: `/meta/{target}/{id}/attached`.
public struct TitleAttached: Decodable, Equatable {
    public struct Extra: Decodable, Equatable {
        public struct Link: Decodable, Equatable { public let extraType: String? }
        public let item: Item
        public let link: Link?
    }

    public struct Version: Decodable, Equatable {
        public struct Link: Decodable, Equatable { public let label: String? }
        public let item: Item
        public let link: Link?
        /// The other version's height, as "· 1080p" needs it: the item that comes with it is the usual small one.
        public let height: Int?

        private enum CodingKeys: String, CodingKey { case item, link }
        private enum Size: String, CodingKey { case height }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            item = try c.decode(Item.self, forKey: .item)
            link = try? c.decodeIfPresent(Link.self, forKey: .link)
            height = try? c.nestedContainer(keyedBy: Size.self, forKey: .item).decodeIfPresent(Int.self, forKey: .height)
        }
    }

    public let extras: [Extra]?
    public let versions: [Version]?
    public let studios: [String]?
    public let director: String?
    public let edition: [String]?
    public let tags: [String]?
    public let hasLogo: Bool?
}

/// Which streaming services list a title: `/meta/{target}/{id}/listings`.
public struct TitleListings: Decodable, Equatable {
    public struct Platform: Decodable, Equatable {
        public let key: String
        public let name: String
    }

    public let platforms: [Platform]?
    /// Seconds since 1970.
    public let asOf: Int64?
    public let region: String?
    public let attribution: String?
}

/// The logo service's answer for one name (`POST /logos/lookup`): a logo, or only the name.
public struct LogoAnswer: Decodable, Equatable {
    public let id: Int64?
    public let kind: String
    public let name: String
    public let has: Bool?
    public let version: Int64?
    /// A picture with a background of its own, which can't change colour: it goes on a white plate.
    public let opaque: Bool?

    public init(id: Int64?, kind: String, name: String, has: Bool?, version: Int64?, opaque: Bool?) {
        self.id = id
        self.kind = kind
        self.name = name
        self.has = has
        self.version = version
        self.opaque = opaque
    }

    /// The key a page keeps an answer under, as the website matches them: case and spaces at the ends don't count.
    public static func key(_ kind: String, _ name: String) -> String {
        kind + "|" + name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// The short legal notices every client shows in the same words: `GET /legal/notices`.
public struct LegalNotices: Decodable, Equatable {
    public struct Notice: Decodable, Equatable {
        public let text: String
        public let section: String?
    }

    public let linkText: String?
    public let notices: [String: Notice]?

    /// One notice's words and where its link goes. An unknown kind is a newer server's, and is nothing here.
    public func notice(_ kind: String) -> (words: String, link: String, path: String)? {
        guard let notice = notices?[kind], !notice.text.isEmpty else { return nil }
        let section = notice.section ?? ""
        return (PlainWords.clean(notice.text, limit: 2000), linkText.map { PlainWords.clean($0, limit: 40) } ?? "Legal",
                "/settings/legal" + (section.isEmpty ? "" : "#" + section))
    }
}

// MARK: - The rules

public enum TitleLook {
    // MARK: Words

    /// "1 h 52 min", "48 min", "40 s"; nothing for nothing (fmtRuntime).
    public static func runtime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        if seconds < 60 { return "\(max(1, Int(seconds.rounded()))) s" }
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600) / 60).rounded())
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }

    /// "1:02:05" or "4:07": a place in something (fmtTime).
    public static func clock(_ seconds: Double?) -> String {
        var s = seconds ?? 0
        if !s.isFinite || s < 0 { s = 0 }
        let h = Int(s / 3600), m = Int(s.truncatingRemainder(dividingBy: 3600) / 60), sec = Int(s.truncatingRemainder(dividingBy: 60))
        let two = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
        return h > 0 ? "\(h):\(two(m)):\(two(sec))" : "\(m):\(two(sec))"
    }

    private static let codecs = ["h264": "H.264", "hevc": "HEVC", "h265": "HEVC", "mpeg2video": "MPEG-2", "mpeg1video": "MPEG-1", "mpeg4": "MPEG-4",
                                 "vc1": "VC-1", "av1": "AV1", "vp9": "VP9", "vp8": "VP8", "prores": "ProRes"]

    /// Video codecs by the names people know.
    public static func codec(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return "" }
        return codecs[code.lowercased()] ?? code.uppercased()
    }

    private static let languages = [
        "en": "English", "nl": "Dutch", "fr": "French", "de": "German", "es": "Spanish", "it": "Italian", "pt": "Portuguese", "ja": "Japanese",
        "zh": "Chinese", "ko": "Korean", "ru": "Russian", "sv": "Swedish", "da": "Danish", "no": "Norwegian", "fi": "Finnish", "pl": "Polish",
        "cs": "Czech", "hu": "Hungarian", "el": "Greek", "tr": "Turkish", "he": "Hebrew", "ar": "Arabic", "hi": "Hindi", "th": "Thai",
        "eng": "English", "dut": "Dutch", "nld": "Dutch", "fre": "French", "fra": "French", "ger": "German", "deu": "German", "spa": "Spanish",
        "ita": "Italian", "por": "Portuguese", "jpn": "Japanese", "chi": "Chinese", "zho": "Chinese", "kor": "Korean", "rus": "Russian", "und": "Unknown",
        // The older bibliographic codes discs use.
        "gre": "Greek", "rum": "Romanian", "cze": "Czech", "ice": "Icelandic", "per": "Persian", "baq": "Basque", "slo": "Slovak", "mac": "Macedonian",
        "alb": "Albanian", "arm": "Armenian", "geo": "Georgian", "bur": "Burmese", "may": "Malay", "wel": "Welsh", "tib": "Tibetan", "mul": "Several languages", "zxx": "None",
    ]

    /// A language code by its English name; any other is named by the system, or shown as it is.
    public static func language(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return "Unknown" }
        let lower = code.lowercased()
        if let name = languages[lower] { return name }
        if lower.allSatisfy({ $0.isLetter }), (2...3).contains(lower.count),
           let name = Locale(identifier: "en").localizedString(forLanguageCode: lower), !name.isEmpty, name.lowercased() != lower {
            return name
        }
        return code.uppercased()
    }

    /// A list of languages, each named once, in the order they first come.
    public static func languages(_ codes: [String]?) -> String {
        var seen = Set<String>()
        return (codes ?? []).map(language).filter { seen.insert($0).inserted }.joined(separator: ", ")
    }

    /// The first four genres, and whether there are more ("…").
    public static func genres(_ list: [String]?) -> (shown: [String], more: Bool) {
        let all = list ?? []
        return (Array(all.prefix(4)), all.count > 4)
    }

    /// "Featurette", "Behind the scenes": a bonus feature's kind, or "Extra".
    public static func extraName(_ type: String?) -> String {
        let words = (type?.isEmpty == false ? type! : "extra").replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// "Director's cut · 1080p": another version's button.
    public static func versionLabel(_ version: TitleAttached.Version) -> String {
        let label = version.link?.label ?? ""
        let name = label.isEmpty ? version.item.title : label
        return name + ((version.height ?? 0) > 0 ? " · \(version.height!)p" : "")
    }

    /// "S1 · E2" without the season, for the playlist's number column; a dash when it has none.
    public static func playlistNumber(_ episode: Item) -> String {
        let label = episode.episodeLabel
        guard !label.isEmpty else { return "–" }
        if let range = label.range(of: #"^S\d+ · "#, options: .regularExpression) { return String(label[range.upperBound...]) }
        return label
    }

    /// Who may save to a collection: anyone who may post, and kids to their own lists. Not a guest.
    public static func canSave(isAdmin: Bool, kind: String?) -> Bool {
        isAdmin || kind == nil || kind == "" || kind == "adult" || kind == "kids"
    }

    // MARK: Discs

    public static func isDisc(_ item: Item) -> Bool { ["dvd-iso", "dvd-folder", "bluray-iso", "bluray-folder"].contains(item.kind ?? "") }
    public static func isBluray(_ item: Item) -> Bool { ["bluray-iso", "bluray-folder"].contains(item.kind ?? "") }
    /// "DVD" or "Blu-ray", for labels.
    public static func discName(_ item: Item) -> String { isBluray(item) ? "Blu-ray" : "DVD" }

    /// Whether the disc's main menu comes first, or the film, with the server's default applied.
    public static func startsWithMenu(_ facts: ItemFacts) -> Bool { (facts.startMode ?? "menu") != "title" }
    public static func trayEffect(_ facts: ItemFacts) -> Bool { facts.insertEffect != false }
    /// An encrypted disc can't be played: nothing here bypasses copy protection.
    public static func playable(_ item: Item, _ facts: ItemFacts) -> Bool { !(isDisc(item) && facts.disc?.scrambled == true) }

    /// The server's player for Insert: as the disc's own settings start it.
    public static func insertPath(_ item: Item, _ facts: ItemFacts) -> String {
        "/play/\(item.id)?mode=\(startsWithMenu(facts) ? "menu" : "title")\(trayEffect(facts) ? "&insert=1" : "")"
    }

    /// "Insert DVD starts with the disc menu · with the tray effect — change it in Disc settings."
    public static func discHint(_ item: Item, _ facts: ItemFacts, admin: Bool) -> String {
        "Insert \(discName(item)) starts with the \(startsWithMenu(facts) ? "disc menu" : "main feature")"
            + (trayEffect(facts) ? " · with the tray effect" : "") + (admin ? " — change it in Disc settings." : ".")
    }

    // MARK: The page's parts

    /// Under the poster: the library's name, or the show, its season and the episode's number.
    public struct Crumb: Equatable {
        public enum Goes: Equatable { case library(Int64), show(Int64, season: Int?), nowhere }
        public let words: String
        public let goes: Goes
    }

    public static func crumbs(_ item: Item, libraryName: String?) -> [Crumb] {
        guard let show = item.showId else {
            guard let library = item.libraryId, let name = libraryName else { return [] }
            return [Crumb(words: name, goes: .library(library))]
        }
        var crumbs = [Crumb(words: item.showTitle ?? "", goes: .show(show, season: nil))]
        if let season = item.season { crumbs.append(Crumb(words: season == 0 ? "Specials" : "Season \(season)", goes: .show(show, season: season))) }
        if !item.episodeLabel.isEmpty { crumbs.append(Crumb(words: item.episodeLabel, goes: .nowhere)) }
        return crumbs
    }

    /// One fact in the table under the synopsis. A wide one (the file) takes the whole row.
    public struct Fact: Equatable {
        public let key: String
        public let value: String
        public let wide: Bool

        public init(_ key: String, _ value: String, wide: Bool = false) {
            self.key = key
            self.value = value
            self.wide = wide
        }
    }

    public static func facts(_ item: Item, _ facts: ItemFacts, admin: Bool) -> [Fact] {
        var list: [Fact] = []
        let disc = isDisc(item)
        let main = facts.disc?.titles?.first { $0.number == facts.disc?.mainTitle }
        if let width = facts.width, width > 0 {
            var words = "\(width)×\(facts.height ?? 0) \(codec(facts.videoCodec))"
            if disc, let main {
                let standard = main.standard ?? ""
                words += " · \(isBluray(item) ? standard : standard.uppercased()) \(main.wide == true ? "16:9" : "4:3")"
            }
            list.append(Fact("Video", words))
        }
        if !(facts.audioLangs ?? []).isEmpty { list.append(Fact("Audio", languages(facts.audioLangs))) }
        if !(facts.subLangs ?? []).isEmpty { list.append(Fact("Subtitles", languages(facts.subLangs))) }
        let source = disc ? "\(discName(item)) \((item.kind ?? "").hasSuffix("-iso") ? "image" : "folder")" : (facts.container ?? "").uppercased()
        let size = (facts.sizeBytes ?? 0) > 0 ? "· " + String(format: "%.2f GB", Double(facts.sizeBytes!) / 1e9) : ""
        list.append(Fact("Source", "\(source) \(size)".trimmingCharacters(in: .whitespaces)))
        if disc, let info = facts.disc {
            list.append(Fact("Disc", "\(info.label ?? "") · \(info.titles?.count ?? 0) titles\(info.hasMenus == true ? " · menus" : "")"))
        }
        if admin { list.append(Fact("File", facts.path ?? "", wide: true)) }
        return list
    }

    /// How many columns the facts take: as many of at least 170 as fit, 24 apart.
    public static func factColumns(width: Double) -> Int { max(1, Int((width + 24) / 194)) }

    /// What "⋯" holds on a phone: everything but the main action and Save.
    public enum MoreRow: Equatable {
        case resumeDisc(String, path: String)
        case discFromStart(String, path: String)
        case mainMenu(path: String)
        case discSettings
        case playFromStart
        case nextEpisode(Int64)
        case artwork, edit, refresh

        public var words: String {
            switch self {
            case .resumeDisc(let words, _), .discFromStart(let words, _): return words
            case .mainMenu: return "Main menu"
            case .discSettings: return "Disc settings"
            case .playFromStart: return "Play from start"
            case .nextEpisode: return "Next episode"
            case .artwork: return "Artwork"
            case .edit: return "Edit"
            case .refresh: return "Refresh"
            }
        }
    }

    public static func moreRows(_ item: Item, _ facts: ItemFacts, admin: Bool) -> [MoreRow] {
        var rows: [MoreRow] = []
        if isDisc(item) {
            if let at = item.progress?.resumeSec, at > 0 {
                let title = facts.discTitle.flatMap { $0 > 0 ? $0 : nil } ?? facts.disc?.mainTitle.flatMap { $0 > 0 ? $0 : nil } ?? 1
                rows.append(.resumeDisc("Resume from \(clock(item.progress?.positionSec))", path: "/play/\(item.id)?mode=title&ttn=\(title)"))
            } else {
                rows.append(.discFromStart(facts.disc?.content == "tv" ? "Play from the start" : "Play movie", path: "/play/\(item.id)?mode=title&start=0"))
            }
            if facts.disc?.hasMenus == true { rows.append(.mainMenu(path: "/play/\(item.id)?mode=menu")) }
            if admin { rows.append(.discSettings) }
        } else {
            if let at = item.progress?.resumeSec, at > 0 { rows.append(.playFromStart) }
            if let next = item.nextId { rows.append(.nextEpisode(next)) }
        }
        if admin {
            rows += [.artwork, .edit]
            if isDisc(item) || item.showId == nil { rows.append(.refresh) }
        }
        return rows
    }

    /// The server's own page for an administrator's tools: the edit window at its Artwork or Match part, or the
    /// page itself, whose "⋯" has Refresh and Disc settings.
    public static func editPath(_ target: TitleTarget, _ id: Int64, section: String? = nil) -> String {
        "/\(target.rawValue)/\(id)" + (section.map { "?edit=\($0)" } ?? "")
    }

    /// Where the website's links on a title's page go.
    public static func genrePath(library: Int64, _ genre: String) -> String { "/library/\(library)?genre=\(WittyClient.queryValue(genre))" }
    public static func tagPath(library: Int64, _ tag: String) -> String { "/library/\(library)?tag=\(WittyClient.queryValue(tag))" }
    public static func platformPath(library: Int64, _ key: String) -> String { "/library/\(library)?platform=\(WittyClient.queryValue(key))" }
    public static func brandPath(_ kind: String, _ name: String, library: Int64) -> String {
        "/brand/\(kind)/\(WittyClient.queryValue(name))?library=\(library)"
    }

    /// Where the details came from, as markdown with its links, under the synopsis. Shows have no Wikidata line.
    public static func credit(provider: String?, id: String?, show: Bool = false) -> String? {
        let ref = WittyClient.queryValue(id ?? "")
        let ccBySA = "[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)"
        switch provider ?? "" {
        case "wikidata" where !show:
            return "Facts from [Wikidata](https://www.wikidata.org/wiki/\(ref)); plot summary from Wikipedia, shared under \(ccBySA)."
        case "tvmaze": return "TV information from [TVmaze](https://www.tvmaze.com/shows/\(ref)), shared under \(ccBySA)."
        case "tvdb": return "Metadata provided by [TheTVDB](https://thetvdb.com). Please consider adding missing information or subscribing."
        case "anilist": return "Anime information from [AniList](https://anilist.co/anime/\(ref))."
        // A show's page credits only TMDB's TV side.
        case "tmdb-tv",
             "tmdb" where !show:
            return "Details from [TMDB](https://www.themoviedb.org). This product uses the TMDB API but is not endorsed or certified by TMDB."
        default: return nil
        }
    }

    /// "Listed for GB, as of 05/11/2026. Data from JustWatch." after "Nothing plays from these services."
    public static func listedNote(_ listings: TitleListings, date: (Date) -> String) -> String {
        var words = "You're looking at your own copy, on your own server. Listed for \(listings.region ?? "")"
        if let asOf = listings.asOf, asOf > 0 { words += ", as of \(date(Date(timeIntervalSince1970: TimeInterval(asOf))))" }
        return words + ". " + (listings.attribution ?? "")
    }

    // MARK: A show

    /// "10 ep · 3 left", "10 ep · watched", or just "10 ep" before anything has been watched.
    public static func seasonLine(_ season: Season) -> String {
        let count = season.episodeCount ?? 0
        let left = season.unwatched
        if let left, left > 0, left < count { return "\(count) ep · \(left) left" }
        if left == 0 { return "\(count) ep · watched" }
        return "\(count) ep"
    }

    /// The season a show opens at: the one asked for, else the next episode's, else the first that isn't Specials.
    /// -1 is Other videos, the episodes with no season.
    public static func openingSeason(_ detail: ShowDetail, asked: Int?) -> Int {
        if let asked { return asked }
        if let next = detail.episodes?.first(where: { $0.id == detail.nextUpId }), let season = next.season { return season }
        let seasons = detail.seasons ?? []
        return seasons.first { $0.number > 0 }?.number ?? seasons.first?.number ?? 0
    }

    public static func episodes(_ detail: ShowDetail, season: Int) -> [Item] {
        uniqued(detail.episodes ?? []).filter { ($0.season ?? -1) == season || (season == -1 && $0.season == nil) }
    }

    /// The episodes with no season, under Other videos.
    public static func otherVideos(_ detail: ShowDetail) -> [Item] { (detail.episodes ?? []).filter { $0.season == nil } }

    /// "Play S1 · E1" or "Resume S1 · E2", and what a screen reader says for Resume.
    public static func playLabel(_ next: Item) -> (words: String, spoken: String?) {
        let label = next.episodeLabel
        if let at = next.progress?.resumeSec, at > 0 {
            return ("Resume \(label)".trimmingCharacters(in: .whitespaces), "Resume \(label) from \(clock(next.progress?.positionSec))")
        }
        return ("Play \(label.isEmpty ? next.title : label)", nil)
    }

    /// "3 seasons · 24 episodes", as the website counts them.
    public static func seasonsLine(seasons: Int, episodes: Int) -> String {
        "\(seasons) \(seasons == 1 ? "season" : "seasons") · \(episodes) episodes"
    }

    /// The episode layout: the show's own, else the server's, else cards.
    public static func episodeView(chosen: String?, show: String?, server: String?) -> String {
        for view in [chosen, show, server] { if let view, !view.isEmpty { return view } }
        return "cards"
    }

    /// "Aired · runtime" under an episode's title.
    public static func episodeLine(_ episode: Item) -> String {
        [episode.aired ?? "", runtime(episode.runtimeSec)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Sizes

    /// The title's size: 28 on a phone, growing with the width up to 44 (clamp(1.75rem, 1.3rem + 1.9vw, 2.75rem)).
    public static func titleSize(width: Double) -> Double { min(max(20.8 + width * 0.019, 28), 44) }

    /// The backdrop's height: 38% of the window's, between 240 and 560.
    public static func heroHeight(window: Double) -> Double { min(max(window * 0.38, 240), 560) }

    /// A frame of the video as a poster, which is shown whole on a colour of its own.
    public static func isFrame(poster: String?) -> Bool {
        let poster = poster ?? ""
        return poster.hasPrefix("cache:thumb-") || poster.hasPrefix("cache:frame-")
    }

    /// That colour's hue, worked out from the title so it never changes (artHue).
    public static func artHue(_ title: String) -> Int {
        var hue = 0
        for scalar in title.unicodeScalars {
            hue = (hue * 31 + Int(String(scalar).utf16.first ?? 0)) % 360
        }
        return hue
    }

    /// HSL to red, green and blue from 0 to 1, for the frame's colour.
    public static func rgb(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let a = saturation * min(lightness, 1 - lightness)
        func channel(_ n: Double) -> Double {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return lightness - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return (channel(0), channel(8), channel(4))
    }
}
