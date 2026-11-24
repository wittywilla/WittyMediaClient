// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Profiles on a shared screen and parental controls, as the server's docs/PROFILES.md describes them:
// switching profile, what a profile may do, screen time and asking a parent for more, and what whoever
// manages a profile can set and see. Every limit is applied by the server. What is here reads its answers,
// decides what to show and when to ask again, and writes limits back so that only what changed is sent.

// MARK: - Switching

/// GET /profiles/household: someone this device can switch to.
public struct HouseholdProfile: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let displayName: String?
    public let kind: String?
    public let hasPassword: Bool?
    public let avatar: String?
    public let current: Bool?

    public init(id: Int64, name: String, displayName: String? = nil, kind: String? = nil, hasPassword: Bool? = nil,
                avatar: String? = nil, current: Bool? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.hasPassword = hasPassword
        self.avatar = avatar
        self.current = current
    }

    public var shownName: String { ProfileNames.shown(name: name, displayName: displayName) }
    public var isCurrent: Bool { current == true }
    /// A tap is enough: no password, and the server lists it so here (the home network).
    public var opensWithTap: Bool { hasPassword == false }
    public var isAdult: Bool { (kind ?? "adult") == "adult" }

    /// The same person as the sign-in screen's tile draws.
    public var asProfile: Profile { Profile(id: id, name: name, displayName: displayName, kind: kind, hasPassword: hasPassword, avatar: avatar) }

    /// Under the name: "Watching now", "Kids", "Guest", or nothing.
    public var note: String {
        if isCurrent { return "Watching now" }
        switch kind {
        case "kids": return "Kids"
        case "guest": return "Guest"
        default: return ""
        }
    }
}

struct HouseholdList: Decodable {
    let profiles: [HouseholdProfile]?
}

public enum SwitchRules {
    /// Switching needs someone to switch to. With nobody listed (the Classic sign-in screen, or away from home),
    /// "Switch profile" signs out, as it always did.
    public static func offersPicker(_ profiles: [HouseholdProfile]) -> Bool { profiles.count > 1 }

    /// What the password box is called: only Kids and Guest profiles can have a PIN.
    public static func secretLabel(_ profile: HouseholdProfile) -> String { profile.isAdult ? "Password" : "Password or PIN" }

    public enum Refusal: Equatable {
        /// The account wants its authenticator's code. `wrong` when one was sent and refused.
        case needsCode(wrong: Bool)
        /// Too many wrong tries: the server's words say how long.
        case wait
        /// A wrong password, or anything else the server put into words. The device stays signed in as it was.
        case refused
    }

    public static func refusal(_ error: APIError, sentCode: Bool) -> Refusal {
        if error.twoFactor { return .needsCode(wrong: sentCode) }
        if error.status == 429 { return .wait }
        return .refused
    }
}

// MARK: - What this profile may do, and its time

/// GET /me/screen-time, and `screenTime` wherever else the server answers it.
public struct ScreenTime: Decodable, Equatable {
    public let allowed: Bool
    /// `allowance`, `bedtime` or `early` when not allowed.
    public let reason: String?
    public let allowanceSec: Int?
    public let usedSec: Int?
    public let extraSec: Int?
    /// -1 = nothing stops it today.
    public let remainingSec: Int?
    public let message: String?
    /// When playing must stop, and when it may start again, in Unix seconds.
    public let until: Int64?
    public let nextAt: Int64?

    public init(allowed: Bool, reason: String? = nil, allowanceSec: Int? = nil, usedSec: Int? = nil, extraSec: Int? = nil,
                remainingSec: Int? = nil, message: String? = nil, until: Int64? = nil, nextAt: Int64? = nil) {
        self.allowed = allowed
        self.reason = reason
        self.allowanceSec = allowanceSec
        self.usedSec = usedSec
        self.extraSec = extraSec
        self.remainingSec = remainingSec
        self.message = message
        self.until = until
        self.nextAt = nextAt
    }

    /// Seconds left, or nil when nothing limits today.
    public var left: Int? {
        guard let remainingSec, remainingSec >= 0 else { return nil }
        return remainingSec
    }
}

/// When a profile may play, and for how long each day. Times are "20:30"; empty means no such limit.
public struct TimeRules: Codable, Equatable {
    public var schoolDayMinutes: Int
    public var weekendMinutes: Int
    public var from: String
    public var schoolNightUntil: String
    public var weekendUntil: String

    public init(schoolDayMinutes: Int = 0, weekendMinutes: Int = 0, from: String = "", schoolNightUntil: String = "", weekendUntil: String = "") {
        self.schoolDayMinutes = schoolDayMinutes
        self.weekendMinutes = weekendMinutes
        self.from = from
        self.schoolNightUntil = schoolNightUntil
        self.weekendUntil = weekendUntil
    }

    enum CodingKeys: String, CodingKey { case schoolDayMinutes, weekendMinutes, from, schoolNightUntil, weekendUntil }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schoolDayMinutes = (try? c.decode(Int.self, forKey: .schoolDayMinutes)) ?? 0
        weekendMinutes = (try? c.decode(Int.self, forKey: .weekendMinutes)) ?? 0
        from = (try? c.decode(String.self, forKey: .from)) ?? ""
        schoolNightUntil = (try? c.decode(String.self, forKey: .schoolNightUntil)) ?? ""
        weekendUntil = (try? c.decode(String.self, forKey: .weekendUntil)) ?? ""
    }

    /// Nothing is limited: the server keeps no rules at all then.
    public var isEmpty: Bool {
        schoolDayMinutes <= 0 && weekendMinutes <= 0 && from.isEmpty && schoolNightUntil.isEmpty && weekendUntil.isEmpty
    }

    /// The allowances a parent chooses from, in minutes; 0 is no limit.
    public static let allowances = [0, 30, 45, 60, 90, 120, 180, 240, 360]

    /// The choices, with one that isn't among them (set from the web, say) kept in its place.
    public static func allowanceChoices(including current: Int) -> [Int] {
        allowances.contains(current) ? allowances : (allowances + [current]).sorted()
    }

    public static func allowanceLabel(_ minutes: Int) -> String {
        if minutes <= 0 { return "No limit" }
        if minutes < 60 { return "\(minutes) minutes" }
        if minutes % 60 == 0 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    /// "HH:MM" as minutes into the day, or nil for anything else. The server reads times the same way.
    public static func minutes(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard clock.utf8.count == 5, parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    public static func clock(_ minutes: Int) -> String {
        let m = min(max(minutes, 0), 24 * 60 - 1)
        return (m / 60 < 10 ? "0" : "") + "\(m / 60):" + (m % 60 < 10 ? "0" : "") + "\(m % 60)"
    }

    /// What the server would refuse, said before it is sent. Nil when the rules are fine.
    public var problem: String? {
        let start = TimeRules.minutes(from) ?? 6 * 60
        for bed in [schoolNightUntil, weekendUntil] where !bed.isEmpty {
            guard let m = TimeRules.minutes(bed) else { return "\(bed) isn't a time of day, such as 20:30." }
            if m <= start { return "Bedtime has to be later in the day than the earliest time." }
        }
        if !from.isEmpty, TimeRules.minutes(from) == nil { return "\(from) isn't a time of day, such as 07:00." }
        return nil
    }
}

/// The age limit for one kind of media. -1 = no limit.
public struct KindLimit: Codable, Equatable {
    public var maxAge: Int
    public var allowUnrated: Bool

    public init(maxAge: Int, allowUnrated: Bool) {
        self.maxAge = maxAge
        self.allowUnrated = allowUnrated
    }

    enum CodingKeys: String, CodingKey { case maxAge, allowUnrated }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxAge = (try? c.decode(Int.self, forKey: .maxAge)) ?? -1
        allowUnrated = (try? c.decode(Bool.self, forKey: .allowUnrated)) ?? false
    }
}

/// GET /me/limits: what the signed-in profile may do, for hiding what is off.
public struct MyLimits: Decodable, Equatable {
    public let limited: Bool?
    public let kind: String?
    public let features: [String: Bool]?
    public let time: TimeRules?
    public let screenTime: ScreenTime?
    /// Whether the parents' PIN is set: "Ask a parent" offers it only then.
    public let parentPin: Bool?
    /// Leaving this profile on this device (switching away, signing out) takes the parents' PIN.
    public let pinToLeave: Bool?

    public init(limited: Bool? = nil, kind: String? = nil, features: [String: Bool]? = nil, time: TimeRules? = nil,
                screenTime: ScreenTime? = nil, parentPin: Bool? = nil, pinToLeave: Bool? = nil) {
        self.limited = limited
        self.kind = kind
        self.features = features
        self.time = time
        self.screenTime = screenTime
        self.parentPin = parentPin
        self.pinToLeave = pinToLeave
    }

    /// Whether a part of the app is offered. Anything the server didn't mention is, so a
    /// feature newer than this app shows as before; the server refuses what is really off.
    public func allows(_ feature: String) -> Bool { features?[feature] ?? true }

    /// The profile has time rules: only then is the time asked after.
    public var isTimed: Bool { !(time?.isEmpty ?? true) }
}

/// The parts of the app a profile's limits can turn off, by the server's names.
public enum ProfileFeature {
    public static let games = "games", recordings = "recordings", downloads = "downloads", sharing = "sharing"
    public static let comments = "comments", remote = "remote", editProfile = "editProfile", liveTv = "liveTv"
}

public enum ScreenTimeRules {
    /// How often the time is asked after while the app is in use.
    public static let askEvery: TimeInterval = 60
    /// The choices under "Ask a parent", in minutes.
    public static let extras = [15, 30, 60]
    /// How long a line about the time left stays up.
    public static let noticeSeconds: TimeInterval = 8

    public static func extraLabel(_ minutes: Int) -> String { minutes == 60 ? "1 hour" : "\(minutes) minutes" }

    /// "1 minute", "7 minutes": never less than one.
    public static func minutesWords(_ seconds: Int) -> String {
        let m = max(1, Int((Double(seconds) / 60).rounded()))
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    /// The heading over why playing stopped.
    public static func title(_ time: ScreenTime) -> String {
        switch time.reason {
        case "bedtime": return "That’s all for tonight"
        case "early": return "It’s a bit early"
        default: return "That’s all for today"
        }
    }

    /// The server's own sentence, or a plain one when it sent none.
    public static func message(_ time: ScreenTime) -> String {
        let said = PlainWords.clean(time.message ?? "", limit: 300)
        return said.isEmpty ? "Screen time is over." : said
    }

    /// When playing may start again: "It starts again at 7:00." today, "tomorrow at" otherwise, and
    /// nothing when the server named no time or it is further off than that.
    public static func nextWords(_ time: ScreenTime, now: Date, calendar: Calendar = .current, clock: (Date) -> String) -> String {
        guard let nextAt = time.nextAt, nextAt > 0 else { return "" }
        let next = Date(timeIntervalSince1970: TimeInterval(nextAt))
        guard next > now else { return "" }
        if calendar.isDate(next, inSameDayAs: now) { return "It starts again at \(clock(next))." }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(next, inSameDayAs: tomorrow) {
            return "It starts again tomorrow at \(clock(next))."
        }
        return ""
    }

    /// How long until the time is asked after again: each minute, and just after the moment it runs out, so
    /// the notice comes when the server stops sending and not up to a minute later.
    public static func nextAsk(after time: ScreenTime?, now: TimeInterval) -> TimeInterval {
        guard let time, time.allowed, let until = time.until, until > 0 else { return askEvery }
        let toEnd = Double(until) - now + 1.5
        return toEnd > 0 && toEnd < askEvery ? toEnd : askEvery
    }

    /// The server refused to play because the time is up: 403 with `code: "screen-time"`. What it said about
    /// why and until when is in `screenTime`; without that, its words alone still say it.
    public static func refusal(_ error: Error?) -> ScreenTime? {
        guard let error = error as? APIError, error.status == 403, error.code == "screen-time" else { return nil }
        struct Said: Decodable { let screenTime: ScreenTime? }
        if let said = error.decoded(Said.self)?.screenTime, !said.allowed { return said }
        return ScreenTime(allowed: false, reason: "allowance", remainingSec: 0, message: error.message)
    }

    /// 403 with `code: "feature-off"`: that part is turned off for this profile. The name of the part, if said.
    public static func featureOff(_ error: Error?) -> String? {
        guard let error = error as? APIError, error.status == 403, error.code == "feature-off" else { return nil }
        struct Said: Decodable { let feature: String? }
        return error.decoded(Said.self)?.feature ?? ""
    }

    /// `X-WMS-Screen-Time-Left`, which every answer that plays carries for a profile with time rules.
    public static func left(header: String?) -> Int? {
        guard let header, let seconds = Int(header.trimmingCharacters(in: .whitespaces)), seconds >= 0 else { return nil }
        return seconds
    }

    /// A parents' PIN is 4 to 12 digits.
    public static func pinIsValid(_ pin: String) -> Bool {
        (4...12).contains(pin.count) && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    public static func cleanPin(_ typed: String) -> String { PairRules.digits(typed, limit: 12) }
}

/// Says how long is left, a few times on the way down and never twice for the same mark: ten minutes, five,
/// two and one. More time given starts it again from the top.
public struct ScreenTimeWarner: Equatable {
    /// Seconds left at which a line is shown.
    public static let marks = [600, 300, 120, 60]
    private var said: Int?

    public init() {}

    /// The line to show now, or nil. Call with every answer about the time.
    public mutating func notice(for time: ScreenTime?) -> String? {
        guard let time, time.allowed, let left = time.left else {
            said = nil
            return nil
        }
        guard let mark = ScreenTimeWarner.marks.last(where: { left <= $0 }) else {
            said = nil // more than ten minutes again: a parent gave time
            return nil
        }
        if let said, mark >= said { return nil }
        said = mark
        return "\(ScreenTimeRules.minutesWords(left)) of screen time left"
    }
}

// MARK: - What a settings page offers

/// One board's ratings, youngest first.
public struct RatingSystem: Decodable, Equatable, Identifiable {
    public struct Rating: Decodable, Equatable {
        public let label: String
        public let age: Int
        public init(label: String, age: Int) {
            self.label = label
            self.age = age
        }
    }
    public let id: String
    public let name: String?
    public let country: String?
    public let kinds: [String]?
    public let ratings: [Rating]?

    public init(id: String, name: String? = nil, country: String? = nil, kinds: [String]? = nil, ratings: [Rating]? = nil) {
        self.id = id
        self.name = name
        self.country = country
        self.kinds = kinds
        self.ratings = ratings
    }
}

/// GET /parental/ratings: fixed for a server, so asked for once.
public struct ParentalLists: Decodable, Equatable {
    public let kinds: [String]?
    public let systems: [RatingSystem]?
    public let features: [String]?
    public let avatars: [String]?
    public let avatarColours: [String]?
    public let maxExtraMinutes: Int?

    public init(kinds: [String]? = nil, systems: [RatingSystem]? = nil, features: [String]? = nil, avatars: [String]? = nil,
                avatarColours: [String]? = nil, maxExtraMinutes: Int? = nil) {
        self.kinds = kinds
        self.systems = systems
        self.features = features
        self.avatars = avatars
        self.avatarColours = avatarColours
        self.maxExtraMinutes = maxExtraMinutes
    }

    /// The pictures to offer: the server's, less any this app can't draw.
    public var pictureNames: [String] { (avatars ?? ProfilePicture.names).filter { ProfilePicture.shapes[$0] != nil } }
    public var pictureColours: [String] { (avatarColours ?? ProfilePicture.colourNames).filter { ProfilePicture.colour(named: $0) != nil } }
}

public enum LimitWords {
    /// The one age limit for everything, as the website offers it.
    public static let ageLevels: [(age: Int, label: String, hint: String)] = [
        (0, "Little kids", "G, U, TV-Y, TV-G"),
        (7, "Kids 7+", "adds TV-Y7"),
        (10, "Older kids 10+", "adds PG, TV-PG"),
        (13, "Teens 13+", "adds PG-13, 12A"),
        (16, "Older teens 16+", "adds TV-14, 15, FSK 16"),
        (-1, "Everything", "no age limit"),
    ]

    /// What an age limit is called: one of the levels, or the age itself when it was set to something between.
    public static func ageLabel(_ age: Int) -> String {
        if let level = ageLevels.first(where: { $0.age == age }) { return level.label }
        return age < 0 ? "Everything" : "Up to age \(age)"
    }

    public static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "film": return "Films and videos"
        case "tv": return "TV shows"
        case "game": return "Games"
        case "music": return "Music and audio"
        case "book": return "Books"
        default: return kind
        }
    }

    public static func profileKind(_ kind: String?) -> String {
        switch kind {
        case "kids": return "Kids"
        case "guest": return "Guest"
        default: return "Adult"
        }
    }

    /// The ages worth offering for a kind: each one where some system's next rating begins, and the one set now.
    public static func ages(for kind: String, in systems: [RatingSystem], including current: Int? = nil) -> [Int] {
        var ages = Set<Int>()
        for system in systems where (system.kinds ?? []).contains(kind) {
            for rating in system.ratings ?? [] { ages.insert(rating.age) }
        }
        if let current, current >= 0 { ages.insert(current) }
        return ages.sorted()
    }

    /// The highest rating of each system an age lets through: "PG-13, 12A, FSK 12".
    public static func allowed(at age: Int, kind: String, in systems: [RatingSystem]) -> String {
        var out: [String] = []
        for system in systems where (system.kinds ?? []).contains(kind) {
            if let top = (system.ratings ?? []).last(where: { $0.age <= age }), !out.contains(top.label) { out.append(top.label) }
        }
        return out.joined(separator: ", ")
    }

    /// One choice in a kind's list: "For everyone (G, U)", "Up to age 13 (PG-13, 12A)".
    public static func ageChoice(_ age: Int, kind: String, in systems: [RatingSystem]) -> String {
        if age < 0 { return "No age limit" }
        let ratings = allowed(at: age, kind: kind, in: systems)
        return (age == 0 ? "For everyone" : "Up to age \(age)") + (ratings.isEmpty ? "" : " (\(ratings))")
    }

    public struct FeatureSwitch: Equatable {
        public let id: String
        public let label: String
        public let hint: String
    }

    /// The switches under "What they can do", worded for the kind of profile. Share links are for adult accounts
    /// whatever is chosen; Kids and Guest profiles read comments and never write them.
    public static func featureSwitches(profileKind: String?, offered: [String]?) -> [(feature: FeatureSwitch, fixedOff: Bool)] {
        let adult = (profileKind ?? "adult") == "adult"
        let all: [(FeatureSwitch, Bool)] = [
            (FeatureSwitch(id: "games", label: "Games", hint: "Play games here or on a game PC. Off hides game libraries too."), false),
            (FeatureSwitch(id: "recordings", label: "Recording Live TV", hint: "Record programmes and keep recording rules."), false),
            (FeatureSwitch(id: "downloads", label: "Downloads", hint: "Save a copy of a photo or video to their device."), false),
            (FeatureSwitch(id: "sharing", label: "Share links",
                           hint: adult ? "Make links that open a photo, video or album without signing in." : "Only for adult accounts."), !adult),
            (FeatureSwitch(id: "comments", label: "Comments",
                           hint: adult ? "Read and write comments." : "Read comments. Kids and Guest profiles never write them."), false),
            (FeatureSwitch(id: "remote", label: "Use away from home",
                           hint: "Off keeps this profile to your home network: it is signed out everywhere else."), false),
            (FeatureSwitch(id: "editProfile", label: "Change their own name and picture",
                           hint: "Their username and password stay with whoever manages them."), false),
        ]
        guard let offered else { return all.map { (feature: $0.0, fixedOff: $0.1) } }
        return all.filter { offered.contains($0.0.id) }.map { (feature: $0.0, fixedOff: $0.1) }
    }

    /// One line under a profile's name about its limits: "Kids 7+ · 1 hour a day · no Live TV".
    public static func summary(_ access: Access?) -> String {
        guard let access else { return "No limits" }
        var parts: [String] = []
        if access.maxAge >= 0 { parts.append(ageLabel(access.maxAge)) }
        if !access.libraries.isEmpty { parts.append(access.libraries.count == 1 ? "1 library" : "\(access.libraries.count) libraries") }
        if let time = access.time, !time.isEmpty {
            if time.schoolDayMinutes > 0 { parts.append("\(TimeRules.allowanceLabel(time.schoolDayMinutes)) on school days") }
            else if time.weekendMinutes > 0 { parts.append("\(TimeRules.allowanceLabel(time.weekendMinutes)) at weekends") }
            else { parts.append("set hours") }
        }
        if !access.liveTv { parts.append("no Live TV") }
        if !access.off.isEmpty { parts.append(access.off.count == 1 ? "1 thing turned off" : "\(access.off.count) things turned off") }
        return parts.isEmpty ? "No limits" : parts.factsLine()
    }
}

// MARK: - A profile's limits

/// A profile's limits, as `GET /users` gives them and `PUT /users/{id}/access` takes them. Everything is read
/// with a stand-in for what is missing.
public struct Access: Codable, Equatable {
    public var maxAge: Int
    public var allowUnrated: Bool
    public var libraries: [Int64]
    public var blockGenres: [String]
    public var onlyGenres: [String]
    public var blockTags: [String]
    public var allowCollections: [Int64]
    public var blockCollections: [Int64]
    public var liveTv: Bool
    public var libraryChannels: Bool
    public var tunerChannels: Bool
    public var kinds: [String: KindLimit]
    /// What the profile may not do, by the server's feature names.
    public var off: [String]
    public var time: TimeRules?

    public init(maxAge: Int = -1, allowUnrated: Bool = true, libraries: [Int64] = [], blockGenres: [String] = [], onlyGenres: [String] = [],
                blockTags: [String] = [], allowCollections: [Int64] = [], blockCollections: [Int64] = [], liveTv: Bool = true,
                libraryChannels: Bool = true, tunerChannels: Bool = true, kinds: [String: KindLimit] = [:], off: [String] = [],
                time: TimeRules? = nil) {
        self.maxAge = maxAge
        self.allowUnrated = allowUnrated
        self.libraries = libraries
        self.blockGenres = blockGenres
        self.onlyGenres = onlyGenres
        self.blockTags = blockTags
        self.allowCollections = allowCollections
        self.blockCollections = blockCollections
        self.liveTv = liveTv
        self.libraryChannels = libraryChannels
        self.tunerChannels = tunerChannels
        self.kinds = kinds
        self.off = off
        self.time = time
    }

    enum CodingKeys: String, CodingKey {
        case maxAge, allowUnrated, libraries, blockGenres, onlyGenres, blockTags, allowCollections, blockCollections
        case liveTv, libraryChannels, tunerChannels, kinds, off, time
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxAge = (try? c.decode(Int.self, forKey: .maxAge)) ?? -1
        allowUnrated = (try? c.decode(Bool.self, forKey: .allowUnrated)) ?? true
        libraries = (try? c.decode([Int64].self, forKey: .libraries)) ?? []
        blockGenres = (try? c.decode([String].self, forKey: .blockGenres)) ?? []
        onlyGenres = (try? c.decode([String].self, forKey: .onlyGenres)) ?? []
        blockTags = (try? c.decode([String].self, forKey: .blockTags)) ?? []
        allowCollections = (try? c.decode([Int64].self, forKey: .allowCollections)) ?? []
        blockCollections = (try? c.decode([Int64].self, forKey: .blockCollections)) ?? []
        liveTv = (try? c.decode(Bool.self, forKey: .liveTv)) ?? true
        libraryChannels = (try? c.decode(Bool.self, forKey: .libraryChannels)) ?? true
        tunerChannels = (try? c.decode(Bool.self, forKey: .tunerChannels)) ?? true
        kinds = (try? c.decode([String: KindLimit].self, forKey: .kinds)) ?? [:]
        off = (try? c.decode([String].self, forKey: .off)) ?? []
        let rules = try? c.decode(TimeRules.self, forKey: .time)
        time = (rules?.isEmpty ?? true) ? nil : rules
    }

    /// `time` is always written, as null when there are no rules: leaving it out would mean "keep what it has".
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxAge, forKey: .maxAge)
        try c.encode(allowUnrated, forKey: .allowUnrated)
        try c.encode(libraries, forKey: .libraries)
        try c.encode(blockGenres, forKey: .blockGenres)
        try c.encode(onlyGenres, forKey: .onlyGenres)
        try c.encode(blockTags, forKey: .blockTags)
        try c.encode(allowCollections, forKey: .allowCollections)
        try c.encode(blockCollections, forKey: .blockCollections)
        try c.encode(liveTv, forKey: .liveTv)
        try c.encode(libraryChannels, forKey: .libraryChannels)
        try c.encode(tunerChannels, forKey: .tunerChannels)
        try c.encode(kinds, forKey: .kinds)
        try c.encode(off, forKey: .off)
        if let time, !time.isEmpty { try c.encode(time, forKey: .time) } else { try c.encodeNil(forKey: .time) }
    }

    public func allows(_ feature: String) -> Bool { !off.contains(feature) }

    public mutating func set(_ feature: String, on: Bool) {
        off.removeAll { $0 == feature }
        if !on { off.append(feature) }
    }

    /// How a collection's titles are treated: "" by their rating, "allow" always, "block" never.
    public func rule(forCollection id: Int64) -> String {
        if blockCollections.contains(id) { return "block" }
        return allowCollections.contains(id) ? "allow" : ""
    }

    public mutating func setRule(_ rule: String, forCollection id: Int64) {
        allowCollections.removeAll { $0 == id }
        blockCollections.removeAll { $0 == id }
        if rule == "allow" { allowCollections.append(id) }
        if rule == "block" { blockCollections.append(id) }
    }

    /// Tags typed with commas between, tidied.
    public static func tags(from typed: String) -> [String] {
        var out: [String] = []
        for part in typed.split(separator: ",") {
            let tag = part.trimmingCharacters(in: .whitespaces)
            if !tag.isEmpty, !out.contains(tag) { out.append(tag) }
        }
        return out
    }

    /// The JSON to send for a change: only the limits that differ from what the profile had. The server keeps
    /// whatever isn't named, so a limit this app has never heard of is left as it was. Nil when nothing changed.
    public func changes(from old: Access) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let before = try? JSONDecoder().decode([String: JSONValue].self, from: encoder.encode(old)),
              let after = try? JSONDecoder().decode([String: JSONValue].self, from: encoder.encode(self)) else { return nil }
        var changed: [String: JSONValue] = [:]
        for (key, value) in after where before[key] != value { changed[key] = value }
        guard !changed.isEmpty else { return nil }
        return try? encoder.encode(changed)
    }
}

/// What a new Kids or Guest profile is given before anyone opens its limits: an age, nothing unrated, and Live
/// TV from the server's own channels for Kids only. The website starts them the same way. Only these are sent:
/// naming the switches here would turn on the ones a new profile of its kind starts without.
public struct NewProfileLimits: Encodable, Equatable {
    public let maxAge: Int
    public let allowUnrated: Bool
    public let liveTv: Bool
    public let libraryChannels: Bool
    public let tunerChannels: Bool

    /// Nil for an adult, who starts with no limits.
    public init?(kind: String, maxAge: Int) {
        guard kind == "kids" || kind == "guest" else { return nil }
        self.maxAge = maxAge
        allowUnrated = false
        liveTv = kind == "kids"
        libraryChannels = kind == "kids"
        tunerChannels = false
    }
}

/// GET /users: an account this one may manage, with its limits.
public struct ManagedUser: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let displayName: String?
    public let isAdmin: Bool?
    public let kind: String?
    public let hasPassword: Bool?
    public let avatar: String?
    public let access: Access?

    public init(id: Int64, name: String, displayName: String? = nil, isAdmin: Bool? = nil, kind: String? = nil, hasPassword: Bool? = nil,
                avatar: String? = nil, access: Access? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.isAdmin = isAdmin
        self.kind = kind
        self.hasPassword = hasPassword
        self.avatar = avatar
        self.access = access
    }

    public var shownName: String { ProfileNames.shown(name: name, displayName: displayName) }
    public var isAdult: Bool { (kind ?? "adult") == "adult" }

    /// "@mia · Kids": who this is, under the name.
    public var role: String { isAdmin == true ? "Administrator" : LimitWords.profileKind(kind) }

    /// Whether limits, the report and extra time are offered for it from `me`. Nobody limits an administrator,
    /// and nobody their own account.
    public func canBeLimited(by me: Int64?) -> Bool { isAdmin != true && id != me }
}

/// GET /users/{id}/activity: what a profile watched, its screen time by day, and what it was refused.
public struct ProfileActivity: Decodable, Equatable {
    public struct Day: Decodable, Equatable {
        /// YYYYMMDD, by the server's calendar.
        public let day: Int
        public let screenSec: Int?
        public let extraSec: Int?
    }
    public struct Watched: Decodable, Equatable {
        public let day: Int
        public let itemId: Int64?
        public let title: String?
        public let showTitle: String?
        public let kind: String?
        public let seconds: Double?
        public let lastAt: Int64?
    }
    public struct Event: Decodable, Equatable {
        public let at: Int64?
        public let kind: String?
        public let title: String?
        public let detail: String?
    }
    public let days: [Day]?
    public let watched: [Watched]?
    public let events: [Event]?
    public let screenTime: ScreenTime?
}

public enum ReportWords {
    /// "45 min", "1 h 20 min", "2 h".
    public static func duration(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }

    /// Today in a line: "20 min of 1 h used." or "20 min of screen time.", and why it stopped when it has.
    public static func today(_ time: ScreenTime?) -> String {
        let used = duration(Double(time?.usedSec ?? 0))
        var line = "\(used) of screen time."
        if let allowance = time?.allowanceSec, allowance >= 0 { line = "\(used) of \(duration(Double(allowance))) used." }
        if let time, !time.allowed { line += " " + ScreenTimeRules.message(time) }
        return line
    }

    /// The days anything is known about, newest first.
    public static func days(_ activity: ProfileActivity) -> [Int] {
        Set((activity.days ?? []).map(\.day) + (activity.watched ?? []).map(\.day)).sorted(by: >)
    }

    /// A day number as a date in the calendar given. Nil for a number that isn't a day.
    public static func date(day: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.year = day / 10000
        parts.month = (day / 100) % 100
        parts.day = day % 100
        guard (1...12).contains(parts.month ?? 0), (1...31).contains(parts.day ?? 0) else { return nil }
        return calendar.date(from: parts)
    }

    /// Under a day's name: "1 h 5 min of screen time, with 15 min extra given".
    public static func dayTotal(_ day: ProfileActivity.Day?) -> String {
        guard let day else { return "" }
        var line = "\(duration(Double(day.screenSec ?? 0))) of screen time"
        if let extra = day.extraSec, extra > 0 { line += ", with \(duration(Double(extra))) extra given" }
        return line
    }

    public static func watched(_ row: ProfileActivity.Watched) -> String {
        let title = PlainWords.clean(row.title ?? "", limit: 120)
        let show = PlainWords.clean(row.showTitle ?? "", limit: 120)
        let name = title.isEmpty ? "A title that has gone" : title
        return show.isEmpty ? name : "\(show): \(name)"
    }

    /// One thing the profile was refused, or was given, in a sentence.
    public static func event(_ event: ProfileActivity.Event) -> String {
        let title = PlainWords.clean(event.title ?? "", limit: 120)
        let detail = PlainWords.clean(event.detail ?? "", limit: 120)
        switch event.kind {
        case "blocked":
            return "Asked for a hidden title: \(title)" + (detail.isEmpty ? "" : " (\(detail))")
        case "extra":
            return "Was given more time: \(detail) minutes, by \(title == "PIN" ? "the parents’ PIN" : title)"
        case "time":
            let why = ["allowance": "the day’s time was used up", "bedtime": "it was past bedtime", "early": "it was too early"][detail]
            return "Tried to play when time was up" + (why.map { ": \($0)" } ?? "")
        case "feature":
            let what = ["games": "games", "recordings": "recording", "downloads": "downloads", "sharing": "share links", "comments": "comments"][detail]
            return "Tried something that is turned off" + (what.map { ": \($0)" } ?? "")
        default:
            return PlainWords.clean(event.kind ?? "", limit: 60)
        }
    }
}

// MARK: - The calls

extension WittyClient {
    /// The profiles this device can switch to. Empty where the server doesn't show its profiles to it.
    public func household() async throws -> [HouseholdProfile] {
        let list: HouseholdList = try await get("/profiles/household")
        return list.profiles ?? []
    }

    /// Signs this device in as another profile and out of this one, in one step. A wrong password is a 403 and
    /// the device stays as it was; an account with two-step sign-in answers with `twoFactor` until `code` is right.
    /// `parentPin`: leaving a kids' profile kept on this device. Without it the server answers 403 with the code
    /// "parent-pin"; a wrong one is "wrong-pin", and 429 after too many.
    public func switchProfile(name: String, password: String, code: String = "", device: String, parentPin: String = "") async throws -> LoginResult {
        var fields = ["name": name, "password": password, "device": device]
        if !code.isEmpty { fields["code"] = code }
        if !parentPin.isEmpty { fields["parentPin"] = parentPin }
        return try await ask("POST", "/profiles/switch", fields)
    }

    /// Signs out of a kids' profile kept on this device, with the parents' PIN. The sign-in ends when it is right.
    public func logout(pin: String) async throws {
        struct Leave: Encodable { let pin: String }
        _ = try await call("POST", "/logout", body: try JSONEncoder().encode(Leave(pin: pin)))
    }

    public func myLimits() async throws -> MyLimits { try await get("/me/limits") }
    public func screenTime() async throws -> ScreenTime { try await get("/me/screen-time") }

    /// "Ask a parent", with the parents' PIN. A wrong one is a 403 with the server's words; 429 after too many.
    public func askParent(minutes: Int, pin: String) async throws -> ScreenTime {
        struct Ask: Encodable { let minutes: Int; let pin: String }
        return try await ask("POST", "/me/screen-time/extra", Ask(minutes: minutes, pin: pin))
    }

    /// "Ask a parent", with the name and password of someone who manages this profile.
    public func askParent(minutes: Int, name: String, password: String) async throws -> ScreenTime {
        struct Ask: Encodable { let minutes: Int; let name: String; let password: String }
        return try await ask("POST", "/me/screen-time/extra", Ask(minutes: minutes, name: name, password: password))
    }

    public func parentalLists() async throws -> ParentalLists { try await get("/parental/ratings") }

    /// The accounts this one may manage: everyone for an administrator, Kids profiles for an adult allowed to.
    public func managedUsers() async throws -> [ManagedUser] { try await list("/users") }

    /// Adds a profile. A Kids or Guest profile starts with `limits`; the server fills in the rest as it does for
    /// any new profile of that kind.
    public func addProfile(name: String, password: String, kind: String, displayName: String, avatar: String, limits: NewProfileLimits?) async throws {
        struct New: Encodable {
            let name: String, password: String, kind: String, displayName: String, avatar: String
            let access: NewProfileLimits?
        }
        try await tell("POST", "/users", New(name: name, password: password, kind: kind, displayName: displayName, avatar: avatar, access: limits))
    }

    /// Removes a profile this account manages, and its watch history with it. An administrator's needs `current`.
    public func removeProfile(_ id: Int64, current: String = "", code: String = "") async throws {
        var fields: [String: String] = [:]
        if !current.isEmpty { fields["current"] = current }
        if !code.isEmpty { fields["code"] = code }
        _ = try await call("DELETE", "/users/\(id)", body: try JSONEncoder().encode(fields))
    }

    /// A profile's names and picture. Only what isn't nil changes; `avatar` is "name:colour", or "" for the initial.
    public func setProfileLook(userId: Int64, displayName: String? = nil, username: String? = nil, avatar: String? = nil) async throws -> User {
        struct Look: Encodable { let displayName: String?; let username: String?; let avatar: String? }
        return try await ask("PUT", "/users/\(userId)/profile", Look(displayName: displayName, username: username, avatar: avatar))
    }

    /// Saves limits: `changes` is `Access.changes(from:)`, so what didn't change isn't sent and stays as it is.
    /// `clearPassword` takes a Kids or Guest profile's password away, so it opens with a tap at home.
    public func saveAccess(userId: Int64, changes: Data?, clearPassword: Bool = false) async throws -> ManagedUser {
        var body = Data("{".utf8)
        if let changes {
            body.append(Data("\"access\":".utf8))
            body.append(changes)
        }
        if clearPassword { body.append(Data(((changes == nil ? "" : ",") + "\"clearPassword\":true").utf8)) }
        body.append(Data("}".utf8))
        return try JSONDecoder().decode(ManagedUser.self, from: try await call("PUT", "/users/\(userId)/access", body: body))
    }

    /// A new password or PIN for a profile this account manages.
    public func setProfilePassword(userId: Int64, password: String) async throws {
        try await tell("PUT", "/users/\(userId)/password", ["password": password])
    }

    public func profileActivity(_ id: Int64, days: Int = 14) async throws -> ProfileActivity { try await get("/users/\(id)/activity?days=\(days)") }

    /// Forgets what was written down about a profile. Today's screen time stays.
    public func clearProfileActivity(_ id: Int64) async throws { _ = try await call("DELETE", "/users/\(id)/activity") }

    /// More time today for a profile this account manages, from the parent's own device.
    public func giveTime(to id: Int64, minutes: Int) async throws -> ScreenTime {
        try await ask("POST", "/users/\(id)/screen-time/extra", ["minutes": minutes])
    }

    public func parentPinIsSet() async throws -> Bool {
        struct Said: Decodable { let set: Bool? }
        let said: Said = try await get("/parental/pin")
        return said.set == true
    }

    /// Sets the parents' PIN, or removes it with `pin` empty. It asks for the administrator's own password, and
    /// their authenticator's code with two-step sign-in. Answers whether a PIN is now set.
    public func setParentPin(_ pin: String, current: String, code: String = "") async throws -> Bool {
        struct Said: Decodable { let set: Bool? }
        var fields = ["pin": pin, "current": current]
        if !code.isEmpty { fields["code"] = code }
        let said: Said = try await ask("PUT", "/parental/pin", fields)
        return said.set == true
    }

    /// Every genre the server's films and shows have, for the limits that hide or keep to some.
    public func allGenres() async throws -> [String] {
        async let films: [String] = list("/genres")
        async let shows: [String] = list("/shows/genres")
        let both = (try? await films) ?? []
        let more = (try? await shows) ?? []
        return Array(Set(both + more)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Leaving a kids' profile

extension APIError {
    /// The server wants the parents' PIN before this profile is left on this device.
    public var needsParentPin: Bool { status == 403 && code == "parent-pin" }
    /// The parents' PIN typed was wrong.
    public var wrongParentPin: Bool { status == 403 && code == "wrong-pin" }
}
