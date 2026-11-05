import Foundation

// The website's shell at phone size, as rules the phone and tablet apps share: the places in the menu and the strip
// (web/src/shell/useNav.tsx, navModel.ts, TopBar.tsx, Sidebar.tsx), the line at the foot of every page
// (components/common.tsx VersionTag, LegalNote) and the activity button's summary (activity.ts).

/// One place in the menu and the strip.
public struct NavPlace: Equatable, Identifiable {
    /// "home", "tv", "lib:3", "collections", "couch", "m:<module>:<page>".
    public let id: String
    public let label: String
    /// The website's address for it.
    public let path: String
    /// A library's type, or "module:<icon>".
    public let kind: String?

    public init(id: String, label: String, path: String, kind: String? = nil) {
        self.id = id
        self.label = label
        self.path = path
        self.kind = kind
    }

    public var libraryId: Int64? { id.hasPrefix("lib:") ? Int64(id.dropFirst(4)) : nil }
}

/// A page a module adds to the server's menus: `/modules/web`.
public struct ModulePage: Decodable, Equatable {
    public let id: String
    public let title: String
    public let `where`: String?
    public let icon: String?
}

public struct ModuleBundle: Decodable, Equatable {
    public let id: String
    public let pages: [ModulePage]?
}

/// How someone arranged the menu: their own in `/me/ui` "nav", or the owner's `navDefault` in `/prefs`.
public struct NavPrefs: Codable, Equatable {
    public var order: [String]?
    public var hidden: [String]?
    public var grouped: Bool?
    public var groups: [String: String]?

    public init(order: [String]? = nil, hidden: [String]? = nil, grouped: Bool? = nil, groups: [String: String]? = nil) {
        self.order = order
        self.hidden = hidden
        self.grouped = grouped
        self.groups = groups
    }

    /// The owner's arrangement, which `/prefs` sends as JSON in a string.
    public static func owner(_ text: String?) -> NavPrefs? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NavPrefs.self, from: data)
    }
}

public enum NavPlaces {
    /// Everything this person could have in the main menu: Home, TV guide, the libraries (commercials only when the
    /// owner put them there), Collections once there's a library, Game PCs if they may, and modules' pages.
    public static func all(libraries: [Library], gamePCs: Bool, modulePages: [(module: String, page: ModulePage)]) -> [NavPlace] {
        var list = [NavPlace(id: "home", label: "Home", path: "/"), NavPlace(id: "tv", label: "TV guide", path: "/tv")]
        list += libraries.filter { $0.type != "commercials" || $0.showMain == true }
            .map { NavPlace(id: "lib:\($0.id)", label: $0.name, path: "/library/\($0.id)", kind: $0.type) }
        if !libraries.isEmpty { list.append(NavPlace(id: "collections", label: "Collections", path: "/collections")) }
        if gamePCs { list.append(NavPlace(id: "couch", label: "Game PCs", path: "/couch")) }
        for (module, page) in modulePages where page.where == "main" {
            list.append(NavPlace(id: "m:\(module):\(page.id)", label: page.title, path: "/m/\(module)/\(page.id)", kind: "module:\(page.icon ?? "")"))
        }
        return list
    }

    /// In the person's order, without what they hid (navModel.ts arrange).
    public static func arrange(_ items: [NavPlace], _ prefs: NavPrefs) -> [NavPlace] {
        let order = prefs.order ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let hidden = Set(prefs.hidden ?? [])
        return items.enumerated()
            .map { (item: $1, rank: rank[$1.id] ?? order.count + $0) }
            .sorted { $0.rank < $1.rank }
            .map(\.item)
            .filter { !hidden.contains($0.id) }
    }

    static let groupOfKind: [String: String] = [
        "movies": "Watch", "shows": "Watch", "anime": "Watch", "videos": "Watch", "shorts": "Watch", "channels": "Watch",
        "musicvideos": "Watch", "photos": "Watch", "commercials": "Watch",
        "music": "Listen", "podcasts": "Listen", "audiobooks": "Listen", "radio": "Listen",
        "books": "Read", "comics": "Read", "games": "Play",
    ]

    /// Which of Watch, Listen, Read and Play a place goes under when someone groups the menu, or none.
    public static func group(_ place: NavPlace, _ prefs: NavPrefs) -> String? {
        if let chosen = prefs.groups?[place.id] { return chosen.isEmpty ? nil : chosen }
        if place.id == "couch" { return "Play" }
        guard place.id.hasPrefix("lib:") else { return nil }
        return groupOfKind[place.kind ?? ""] ?? "Watch"
    }

    /// The strip: the arranged places but Home and TV guide, which are on the bar.
    public static func strip(_ arranged: [NavPlace]) -> [NavPlace] { arranged.filter { $0.id != "home" && $0.id != "tv" } }

    /// The website's pages that show the strip rather than Back: the bar's own and the strip's.
    public static func isTop(path: String, strip: [NavPlace]) -> Bool {
        ["/", "/tv", "/search", "/you", "/settings"].contains(path) || strip.contains { $0.path == path }
    }
}

/// The line at the foot of every page: "WittyMediaServer 0.4.0" and its stage, "ALPHA".
public enum VersionTag {
    public static func parts(_ version: String?) -> (number: String, stage: String) {
        let text = version ?? ""
        guard let match = text.range(of: #"^v?(\d+\.\d+\.\d+)(?:-([a-zA-Z]+)[.\d]*)?"#, options: .regularExpression) else {
            return (text.isEmpty ? "dev" : text, text == "dev" ? "DEV" : "")
        }
        let found = String(text[match])
        let core = found.hasPrefix("v") ? String(found.dropFirst()) : found
        let pieces = core.split(separator: "-", maxSplits: 1)
        let number = String(pieces[0])
        let stage = pieces.count > 1 ? String(pieces[1].prefix { $0.isLetter }).uppercased() : ""
        return (number, stage)
    }
}

/// What the server is busy with, for the activity button and its panel: `/system/tasks` (activity.ts).
public struct ActivityTasks: Decodable, Equatable {
    public struct Access: Decodable, Equatable {
        public let enabled: Bool?
        public let visible: Bool?
        public let readOnly: Bool?
    }
    public struct Summary: Decodable, Equatable {
        public let active: Int?
        public let queued: Int?
        public let paused: Int?
        public let percent: Double?
    }
    public struct Task: Decodable, Equatable, Identifiable {
        public let id: String
        public let type: String?
        public let title: String?
        public let state: String?
        public let phase: String?
        public let libraryName: String?
        public let steps: [String]?
        public let step: Int?
        public let item: String?
        public let done: Double?
        public let total: Double?
        public let unit: String?
        public let percent: Double?
        public let etaSec: Double?
        public let startedAt: Double?
        public let finishedAt: Double?
        public let by: String?
        public let result: String?
        public let error: String?
        public let fix: String?
        public let problemCount: Int?
        public let canPause: Bool?
        public let canResume: Bool?
        public let canCancel: Bool?
        public let canRetry: Bool?

        /// "Waiting", "Running", "Pausing…" (asked to pause and carrying on to a point it can), "Finished".
        public var stateWords: String {
            if state == "running", canResume == true { return "Pausing…" }
            switch state {
            case "queued": return "Waiting"
            case "running": return "Running"
            case "paused": return "Paused"
            case "failed": return "Failed"
            case "done": return "Finished"
            case "cancelled": return "Cancelled"
            default: return state?.capitalized ?? ""
            }
        }

        /// "1,204 of 3,000 files", "1.2 GB of 4.0 GB".
        public var countWords: String {
            let done = self.done ?? 0, total = self.total ?? 0
            if unit == "bytes" {
                return total > 0 ? "\(ActivityWords.bytes(done)) of \(ActivityWords.bytes(total))" : done > 0 ? ActivityWords.bytes(done) : ""
            }
            let unit = (self.unit ?? "").isEmpty ? "" : " \(self.unit!)"
            if total > 0 { return "\(Int(done).formatted()) of \(Int(total).formatted())\(unit)" }
            return done > 0 ? "\(Int(done).formatted())\(unit)" : ""
        }
    }
    public let access: Access?
    public let tasks: [Task]?
    public let recent: [Task]?
    public let summary: Summary?

    public var shown: Bool { access?.visible == true }
    public var busy: Int { (summary?.active ?? 0) + (summary?.queued ?? 0) }

    /// The button's name, as the website's buttonLabel.
    public func label(unseenProblems: Int = 0) -> String {
        let active = summary?.active ?? 0, queued = summary?.queued ?? 0, paused = summary?.paused ?? 0
        let percent = summary?.percent ?? -1
        let going = active - paused
        var parts: [String] = []
        if going > 0 { parts.append("\(going) running") }
        if paused > 0 { parts.append("\(paused) paused") }
        if queued > 0 { parts.append("\(queued) waiting") }
        if percent >= 0, going > 0 { parts.append("\(Int(percent.rounded()))% done") }
        if unseenProblems > 0 { parts.append("\(unseenProblems) failed") }
        return parts.isEmpty ? "Activity: nothing going on" : "Activity: \(parts.joined(separator: ", "))"
    }

    /// The tasks under their libraries' names, in order, the server's own work last ("This server").
    public static func grouped(_ tasks: [Task]) -> [(name: String, tasks: [Task])] {
        var groups: [String: [Task]] = [:]
        for task in tasks { groups[task.libraryName ?? "", default: []].append(task) }
        let named = groups.keys.filter { !$0.isEmpty }.sorted { $0.localizedCompare($1) == .orderedAscending }
        return named.map { ($0, groups[$0]!) } + (groups[""].map { [("This server", $0)] } ?? [])
    }
}

public enum ActivityWords {
    public static func bytes(_ n: Double) -> String {
        if n < 1024 { return "\(Int(n.rounded())) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var v = n / 1024, i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return "\(v >= 100 ? String(Int(v.rounded())) : String(format: "%.1f", v)) \(units[i])"
    }
}
