import Foundation

// Home as the server's website builds it (web/src/pages/HomePage.tsx and the parts it uses): its sections and the
// order each person saves for them, the greeting, the hero's facts, what the main button says and does, the words
// and badges on a card, "On TV now", "Can't decide?" and the notice of a newer server. See docs/APP-DESIGN.md,
// One mobile design with the website.

// MARK: - Sections

/// One section of Home, as the website's widgets: the hero, the libraries, a row of cards, On TV now or Can't decide?
public struct HomeWidget: Identifiable, Equatable {
    public let id: String
    /// Its name in Customize home.
    public let title: String
    /// The cards of a row. Nil for the sections that aren't rows, and for recommendations that haven't come.
    public let hub: Hub?
}

public enum HomeWidgets {
    public static let hero = "hero"
    public static let libraries = "libraries"
    /// Everything in progress, watching, reading and listening, in one row.
    public static let jump = "jump"
    public static let onNow = "onnow"
    public static let forYou = "foryou"
    public static let shuffle = "shuffle"

    /// Every section in the website's order: the hero, the libraries, Jump back in, On TV now, the recommendations,
    /// Next up, the saved views, what's recently added, and Can't decide? last.
    public static func list(_ home: Home, recommended: Recommended?) -> [HomeWidget] {
        let hubs = home.hubs ?? []
        let byKey = { (key: String) in hubs.first { $0.key == key } }
        let going = ["continue", "continue-reading", "continue-listening"].compactMap(byKey)
        let jumpRow = Hub(key: jump, title: "Jump back in", libraryId: nil,
                          items: going.flatMap { $0.items ?? [] }, shows: going.flatMap { $0.shows ?? [] })
        let picked = recommended.map { Hub(key: forYou, title: $0.title, libraryId: nil, items: $0.items ?? [], shows: $0.shows ?? []) }
        var list = [
            HomeWidget(id: hero, title: "Featured", hub: nil),
            HomeWidget(id: libraries, title: "Your libraries", hub: nil),
            HomeWidget(id: jump, title: "Jump back in", hub: jumpRow),
            HomeWidget(id: onNow, title: "On TV now", hub: nil),
            HomeWidget(id: forYou, title: "Recommended for you", hub: picked),
        ]
        if let next = byKey("nextup") { list.append(HomeWidget(id: next.key, title: next.title, hub: next)) }
        for prefix in ["view-", "recent-"] {
            for hub in hubs where hub.key.hasPrefix(prefix) { list.append(HomeWidget(id: hub.key, title: hub.title, hub: hub)) }
        }
        list.append(HomeWidget(id: shuffle, title: "Can’t decide?", hub: nil))
        // A server that sends the same row twice still shows it once.
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    /// Nothing featured and every row empty: the libraries have nothing in them yet, or are still being looked through.
    public static func isEmpty(_ home: Home) -> Bool {
        (home.featured ?? []).isEmpty && (home.hubs ?? []).allSatisfy(\.isEmpty)
    }
}

/// How a person arranged Home, kept with their account under `home` in `/me/ui`, so it follows them to every
/// device: the sections in their order, and those hidden.
public struct HomeLayout: Codable, Equatable {
    /// Version 2 merged the Continue rows into Jump back in. An order saved before that is dropped once.
    public static let version = 2
    public var v: Int?
    public var order: [String]
    public var hidden: [String]

    public init(order: [String] = [], hidden: [String] = []) {
        v = Self.version
        self.order = order
        self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey { case v, order, hidden }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        v = try? values.decodeIfPresent(Int.self, forKey: .v)
        order = ((try? values.decodeIfPresent([String].self, forKey: .order)) ?? nil) ?? []
        hidden = ((try? values.decodeIfPresent([String].self, forKey: .hidden)) ?? nil) ?? []
    }

    /// What was saved, read as the website reads it: an older version's order is dropped, and a hidden Continue row
    /// hides Jump back in.
    public static func saved(_ saved: HomeLayout?) -> HomeLayout {
        guard let saved else { return HomeLayout() }
        var hidden: [String] = []
        for id in saved.hidden.map({ $0.hasPrefix("continue") ? HomeWidgets.jump : $0 }) where !hidden.contains(id) { hidden.append(id) }
        return HomeLayout(order: saved.v == version ? saved.order : [], hidden: hidden)
    }

    /// The saved order first, then every section not placed yet, in the website's order.
    public func ordered(_ widgets: [HomeWidget]) -> [HomeWidget] {
        let place = { (id: String, at: Int) -> Int in order.firstIndex(of: id) ?? 1000 + at }
        return widgets.enumerated()
            .sorted { (place($0.element.id, $0.offset), $0.offset) < (place($1.element.id, $1.offset), $1.offset) }
            .map(\.element)
    }

    /// One section moved to a place among them all, as they're shown.
    public func moving(_ id: String, to place: Int, among shown: [String]) -> HomeLayout {
        var ids = shown.filter { $0 != id }
        ids.insert(id, at: max(0, min(ids.count, place)))
        return HomeLayout(order: ids, hidden: hidden)
    }

    /// A section hidden, or shown again.
    public func toggling(_ id: String) -> HomeLayout {
        HomeLayout(order: order, hidden: hidden.contains(id) ? hidden.filter { $0 != id } : hidden + [id])
    }
}

/// The parts of `/me/ui` Home reads. One that can't be read counts as not chosen.
public struct HomeChoices: Decodable, Equatable {
    public let home: HomeLayout?
    /// The newer version an administrator chose Later for, which hides its notice until the next one.
    public let updateLater: String?

    public init(home: HomeLayout? = nil, updateLater: String? = nil) {
        self.home = home
        self.updateLater = updateLater
    }

    private enum CodingKeys: String, CodingKey { case home, updateLater }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        home = (try? values.decodeIfPresent(HomeLayout.self, forKey: .home)) ?? nil
        updateLater = (try? values.decodeIfPresent(String.self, forKey: .updateLater)) ?? nil
    }
}

/// What Home says at the top when nothing is featured.
public enum HomeGreeting {
    /// Morning from 5 to noon, afternoon until 6, evening otherwise.
    public static func words(hour: Int) -> String {
        if hour >= 5 && hour < 12 { return "Good morning" }
        if hour >= 12 && hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    public static func line(hour: Int, name: String) -> String {
        name.isEmpty ? words(hour: hour) : "\(words(hour: hour)), \(name)"
    }
}

// MARK: - Words

/// The website's run times (`fmtRuntime`): "1 h 52 min", "45 min", "30 s". Nothing for nothing.
public enum Runtime {
    public static func words(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        if seconds < 60 { return "\(max(1, Int(seconds.rounded()))) s" }
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600) / 60).rounded())
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}

public extension Item {
    var isDisc: Bool { ["dvd-iso", "dvd-folder", "bluray-iso", "bluray-folder"].contains(kind ?? "") }
    var isBluray: Bool { kind == "bluray-iso" || kind == "bluray-folder" }
    /// An audio CD image, which plays in the server's CD player.
    var isCD: Bool { kind == "cd-image" }
    /// "DVD", "Blu-ray" or "CD", for labels.
    var discName: String { isCD ? "CD" : isBluray ? "Blu-ray" : "DVD" }
    /// A disc known to have menus, which the hero's Disc menu button opens.
    var hasDiscMenus: Bool { isDisc && disc?.hasMenus == true }
}

// MARK: - The hero

/// One fact in the hero's line under the title.
public enum HeroFact: Equatable {
    case text(String)
    /// The age rating, in a box of its own.
    case rating(String)
    /// The score out of 10, after a star.
    case score(String)
}

public enum HeroLook {
    /// The year, how long it is, its age rating, its score, the kind of disc, and up to three genres.
    public static func facts(_ item: Item) -> [HeroFact] {
        var facts: [HeroFact] = []
        if let year = item.year, year != 0 { facts.append(.text(String(year))) }
        let length = Runtime.words(item.runtimeSec)
        if !length.isEmpty { facts.append(.text(length)) }
        if let rating = item.contentRating, !rating.isEmpty { facts.append(.rating(rating)) }
        if let score = item.rating, score != 0 { facts.append(.score(String(format: "%.1f", score))) }
        if item.isDisc { facts.append(.text(item.discName + (item.disc?.hasMenus != false ? " · interactive menus" : ""))) }
        facts += (item.genres ?? []).prefix(3).filter { !$0.isEmpty }.map(HeroFact.text)
        return facts
    }
}

// MARK: - The main button

/// What the main button does with something (web/src/openItem.tsx), in this app's terms.
public enum OpenAction: Equatable {
    /// This app's own video player.
    case player(startOver: Bool)
    /// A song or a chapter, from its album or book.
    case listen
    /// This app's own page for it: a game on someone's own PC.
    case item
    /// The server's own page: a book's reader, a disc's or a CD's player, a game.
    case page(String)
}

public enum OpenLook {
    /// Worded for what it is: Read, Listen, Insert disc, and Play or Resume for the rest.
    public static func label(_ item: Item) -> String {
        let started = item.resumeSeconds != nil
        switch item.kind {
        case "book": return started ? "Continue reading" : "Read"
        case "audio": return started ? "Continue listening" : "Listen"
        case "game": return "Play"
        case "cd-image": return started ? "Continue the disc" : "Insert disc"
        default: return started ? "Resume" : "Play"
        }
    }

    public static func action(_ item: Item) -> OpenAction {
        switch item.kind {
        case "book": return .page((item.reader ?? "").isEmpty ? "/item/\(item.id)" : "/read/\(item.id)")
        case "game": return item.isRigGame ? .item : .page("/game/\(item.id)")
        case "cd-image": return .page("/cd/\(item.id)?play=1")
        case "audio": return .listen
        case "video": return .player(startOver: item.resumeSeconds == nil)
        default: return .page("/play/\(item.id)")
        }
    }

    /// A disc's menus, from the hero.
    public static func discMenu(_ item: Item) -> String { "/play/\(item.id)?mode=menu" }
}

// MARK: - Cards

public enum CardShape: Equatable {
    case poster, wide, square
}

/// The plates on a card's picture: the kind of disc at the top left, and watched or how many are left at the right.
public enum CardBadge: Equatable {
    case disc(String)
    case seen
    case unwatched(Int)
}

/// A card's words, shape and plates, as the website's ItemCard and ShowCard (web/src/components/common.tsx).
public struct CardLook: Equatable {
    public let title: String
    public let subtitle: String
    public let shape: CardShape
    public let badges: [CardBadge]
    /// How far through, from 0 to 1, for the bar along the bottom. Nil for no bar.
    public let progress: Double?

    /// Episodes are wide stills with their show's name, unless told otherwise; songs and CDs are square.
    public static func item(_ item: Item, wide: Bool? = nil) -> CardLook {
        let wide = wide ?? (item.showId != nil)
        let audio = item.kind == "audio" || item.isCD
        let length = item.kind == "book" || audio ? "" : Runtime.words(item.runtimeSec)
        let year = item.year.flatMap { $0 == 0 ? nil : String($0) }
        var progress: Double?
        if let p = item.progress, p.watched != true, let total = p.durationSec, total > 0 {
            let fraction = min(1, (p.positionSec ?? 0) / total)
            if fraction > 0 { progress = fraction }
        }
        var badges: [CardBadge] = []
        if item.isDisc || item.isCD { badges.append(.disc(item.discName)) }
        if item.progress?.watched == true { badges.append(.seen) }
        let subtitle: String
        if item.showId != nil {
            subtitle = [item.episodeLabel, wide ? item.title : Runtime.words(item.runtimeSec)].filter { !$0.isEmpty }.joined(separator: " · ")
        } else if audio {
            subtitle = [item.albumArtist, item.artist].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        } else if item.kind == "book" {
            subtitle = (item.artist?.isEmpty == false ? item.artist : nil) ?? year ?? ""
        } else {
            subtitle = [year ?? "", length].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let showTitle = item.showTitle ?? ""
        return CardLook(title: !showTitle.isEmpty && wide ? showTitle : item.title, subtitle: subtitle,
                        shape: audio ? .square : wide ? .wide : .poster, badges: badges, progress: progress)
    }

    /// "2019 · 3 seasons", with how many episodes are left, or a tick once they're all watched.
    public static func show(_ show: Show) -> CardLook {
        let seasons = show.seasonCount ?? 0
        let subtitle = [show.year.flatMap { $0 == 0 ? nil : String($0) }, "\(seasons) \(seasons == 1 ? "season" : "seasons")"]
            .compactMap { $0 }.joined(separator: " · ")
        var badges: [CardBadge] = []
        if let left = show.unwatched, let all = show.episodeCount, left > 0, left < all { badges.append(.unwatched(left)) }
        if show.unwatched == 0 { badges.append(.seen) }
        return CardLook(title: show.title, subtitle: subtitle, shape: .poster, badges: badges, progress: nil)
    }
}

// MARK: - On TV now

public enum OnNowLook {
    /// How many channels Home asks for.
    public static let limit = 16

    /// Favourites first, the rest in the server's order.
    public static func ordered(_ channels: [GuideChannel]) -> [GuideChannel] {
        channels.enumerated()
            .sorted { ($0.element.favourite == true ? 0 : 1, $0.offset) < ($1.element.favourite == true ? 0 : 1, $1.offset) }
            .map(\.element)
    }

    public static func programme(_ channel: GuideChannel, at now: Double) -> GuideProgramme? {
        channel.programmes?.first { Double($0.start) <= now && Double($0.end) > now }
    }

    /// What's on, or why there's nothing.
    public static func title(_ channel: GuideChannel, at now: Double) -> String {
        if let on = programme(channel, at: now), !on.title.isEmpty { return on.title }
        return channel.kind == "library" ? "Off air" : "No guide data"
    }

    /// The channel's name, and how long is left of what's on.
    public static func detail(_ channel: GuideChannel, at now: Double) -> String {
        guard let on = programme(channel, at: now) else { return channel.name }
        return "\(channel.name) · \(left(Double(on.end) - now)) left"
    }

    /// How far into what's on, from 0 to 1.
    public static func fraction(_ channel: GuideChannel, at now: Double) -> Double {
        guard let on = programme(channel, at: now), on.end > on.start else { return 0 }
        return min(1, max(0, (now - Double(on.start)) / Double(on.end - on.start)))
    }

    /// "12 min", "1h 5m", "2h" (the guide's `fmtLeft`). Never under a minute.
    public static func left(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return minutes % 60 != 0 ? "\(hours)h \(minutes % 60)m" : "\(hours)h"
    }

    public static func spoken(_ channel: GuideChannel, at now: Double) -> String {
        let on = programme(channel, at: now)?.title ?? ""
        return "Channel \(channel.number ?? ""), \(channel.name): \(on.isEmpty ? "nothing listed" : on)"
    }
}

// MARK: - Can't decide?

public enum ShuffleLook {
    /// The year, how long it is, and two genres.
    public static func facts(_ item: Item) -> String {
        [item.year.flatMap { $0 == 0 ? nil : String($0) } ?? "", Runtime.words(item.runtimeSec), (item.genres ?? []).prefix(2).joined(separator: ", ")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - A newer server

/// One version's notes, in the changelog's Markdown.
public struct UpdateChange: Decodable, Equatable {
    public let version: String?
    public let notes: String?

    public init(version: String?, notes: String?) {
        self.version = version
        self.notes = notes
    }
}

/// What `/update` says, for administrators. Only what the notice uses.
public struct UpdateStatus: Decodable, Equatable {
    public struct Latest: Decodable, Equatable {
        public let version: String?
        public let changes: [UpdateChange]?
    }

    public let current: String?
    public let latest: Latest?
    /// `apply`, `installer` or `docker`: a server in Docker is updated by its owner, so the notice says how.
    public let method: String?
}

public enum UpdateNews {
    /// For administrators only, until they choose Later for that version.
    public static func shows(update: String?, isAdmin: Bool, later: String?) -> Bool {
        guard let update, !update.isEmpty, isAdmin else { return false }
        return later != update
    }

    public static func title(_ version: String) -> String { "WittyMediaServer \(version) is available" }

    /// The newest version's first change in a few words, and how many more changes there are since this one. The
    /// changelog leads each change with its point in bold.
    public static func headline(_ changes: [UpdateChange]) -> (first: String, more: Int) {
        var first = ""
        var count = 0
        for change in changes {
            for line in (change.notes ?? "").components(separatedBy: "\n") {
                guard let point = match(#"^[-*+] (.*)$"#, in: line) else { continue }
                count += 1
                guard first.isEmpty else { continue }
                var words = match(#"^\*\*(.+?)\*\*"#, in: point) ?? point
                words = replace(#"\*\*|__|`|\[([^\]]*)\]\([^)]*\)"#, in: words, with: "$1").trimmingCharacters(in: .whitespacesAndNewlines)
                if words.hasSuffix(".") || words.hasSuffix(":") { words.removeLast() }
                if words.count > 90 {
                    words = replace(#"\s+\S*$"#, in: String(words.prefix(88)), with: "") + "…"
                }
                first = words
            }
        }
        return (first, max(0, count - (first.isEmpty ? 0 : 1)))
    }

    /// What the notice says under its title.
    public static func sentence(_ status: UpdateStatus) -> String {
        let (first, more) = headline(status.latest?.changes ?? [])
        guard !first.isEmpty else { return "A newer version of the server is ready to install." }
        return first + (more > 0 ? ", and \(more) more \(more == 1 ? "change" : "changes")" : "") + "."
    }

    /// The main button: Docker is updated by its owner.
    public static func action(_ status: UpdateStatus?) -> String { status?.method == "docker" ? "How to update" : "Update" }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let found = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              found.numberOfRanges > 1, let range = Range(found.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
