// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// WittyTV "More info" (Design 2): one programme in full, over the guide, the watch banner and the mini guide. It reads
// `GET /tv/{key}/programme?start=<unix>` (docs/CLIENT-API.md, "More info", feature `tv-programme-info`) and shows the
// programme's logo, title and times, its description, the buttons the server says are on offer, cast and crew, where to
// watch, trailers and the other airings. Whatever the server doesn't say isn't drawn, and the advisory is never shown.

public struct ProgrammeInfo: Decodable, Equatable, Sendable {
    public struct Channel: Decodable, Equatable, Sendable {
        public var key: String
        public var number: String
        public var name: String
        public var catchupDays: Int

        enum CodingKeys: String, CodingKey { case key, number, name, catchupDays }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? ""
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            catchupDays = (try? c.decodeIfPresent(Int.self, forKey: .catchupDays)) ?? 0
            // The number is a number or a word.
            if let n = try? c.decodeIfPresent(Int.self, forKey: .number) { number = String(n) }
            else { number = (try? c.decodeIfPresent(String.self, forKey: .number)) ?? "" }
        }
        public init(key: String, number: String = "", name: String = "", catchupDays: Int = 0) {
            self.key = key
            self.number = number
            self.name = name
            self.catchupDays = catchupDays
        }
    }

    public struct Programme: Decodable, Equatable, Sendable {
        public var start: Int64
        public var end: Int64
        public var kind: String
        public var title: String
        public var sub: String
        public var desc: String
        public var genres: [String]
        public var rating: String
        public var year: Int?
        public var season: Int?
        public var episode: Int?
        public var lengthMin: Int?
        public var studio: String
        public var language: String
        public var country: String
        public var audio: String
        public var hd: Bool
        public var premiere: Bool
        public var new: Bool
        public var repeated: Bool
        public var scores: [Score]

        public struct Score: Decodable, Equatable, Sendable {
            public var value: Double
            public var system: String
        }

        enum CodingKeys: String, CodingKey {
            case start, end, kind, title, sub, desc, genres, rating, year, season, episode, lengthMin, studio, language, country
            case audio, hd, premiere, new, `repeat`, scores
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func s(_ k: CodingKeys) -> String { PlainWords.clean((try? c.decodeIfPresent(String.self, forKey: k)) ?? "", limit: 4000) }
            start = (try? c.decodeIfPresent(Int64.self, forKey: .start)) ?? 0
            end = (try? c.decodeIfPresent(Int64.self, forKey: .end)) ?? 0
            kind = s(.kind)
            title = s(.title)
            sub = s(.sub)
            desc = s(.desc)
            genres = ((try? c.decodeIfPresent([String].self, forKey: .genres)) ?? []).map { PlainWords.clean($0, limit: 40) }
            rating = s(.rating)
            year = try? c.decodeIfPresent(Int.self, forKey: .year)
            season = try? c.decodeIfPresent(Int.self, forKey: .season)
            episode = try? c.decodeIfPresent(Int.self, forKey: .episode)
            lengthMin = try? c.decodeIfPresent(Int.self, forKey: .lengthMin)
            studio = s(.studio)
            language = s(.language)
            country = s(.country)
            audio = s(.audio)
            hd = (try? c.decodeIfPresent(Bool.self, forKey: .hd)) ?? false
            premiere = (try? c.decodeIfPresent(Bool.self, forKey: .premiere)) ?? false
            new = (try? c.decodeIfPresent(Bool.self, forKey: .new)) ?? false
            repeated = (try? c.decodeIfPresent(Bool.self, forKey: .`repeat`)) ?? false
            scores = (try? c.decodeIfPresent([Score].self, forKey: .scores)) ?? []
        }

        public init(start: Int64, end: Int64, title: String, sub: String = "", desc: String = "", kind: String = "broadcast") {
            self.start = start
            self.end = end
            self.title = title
            self.sub = sub
            self.desc = desc
            self.kind = kind
            genres = []
            rating = ""
            studio = ""
            language = ""
            country = ""
            audio = ""
            hd = false
            premiere = false
            new = false
            repeated = false
            scores = []
        }
    }

    public struct Actions: Decodable, Equatable, Sendable {
        public var watch = false, record = false, remind = false, reminded = false, fromStart = false
        public var watchLater = false, inList = false, open = false

        enum CodingKeys: String, CodingKey { case watch, record, remind, reminded, fromStart, watchLater, inList, open }
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func b(_ k: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? false }
            watch = b(.watch); record = b(.record); remind = b(.remind); reminded = b(.reminded)
            fromStart = b(.fromStart); watchLater = b(.watchLater); inList = b(.inList); open = b(.open)
        }
    }

    /// A person in the credits. A person only the guide names has no `personId`: nothing opens for them.
    public struct Person: Decodable, Equatable, Sendable {
        public var personId: Int64?
        public var name: String
        public var character: String
        public var job: String
        public var hasPhoto: Bool

        enum CodingKeys: String, CodingKey { case personId, name, character, job, role, hasPhoto }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try? c.decodeIfPresent(Int64.self, forKey: .personId)
            personId = (id ?? 0) > 0 ? id : nil
            name = PlainWords.clean((try? c.decodeIfPresent(String.self, forKey: .name)) ?? "", limit: 120)
            let role = (try? c.decodeIfPresent(String.self, forKey: .character)) ?? (try? c.decodeIfPresent(String.self, forKey: .role)) ?? ""
            character = PlainWords.clean(role, limit: 120)
            job = PlainWords.clean((try? c.decodeIfPresent(String.self, forKey: .job)) ?? "", limit: 120)
            hasPhoto = (try? c.decodeIfPresent(Bool.self, forKey: .hasPhoto)) ?? false
        }
        public init(personId: Int64?, name: String, character: String = "", job: String = "") {
            self.personId = (personId ?? 0) > 0 ? personId : nil
            self.name = name
            self.character = character
            self.job = job
            hasPhoto = false
        }
        /// Only a person in the library has a page to open.
        public var openable: Bool { personId != nil }
    }

    public struct Department: Decodable, Equatable, Sendable {
        public var label: String
        public var people: [Person]
        enum CodingKeys: String, CodingKey { case label, department, people }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            label = PlainWords.clean((try? c.decodeIfPresent(String.self, forKey: .label)) ?? (try? c.decodeIfPresent(String.self, forKey: .department)) ?? "", limit: 60)
            people = (try? c.decodeIfPresent([Person].self, forKey: .people)) ?? []
        }
    }

    public struct Credits: Decodable, Equatable, Sendable {
        public var cast: [Person]
        public var guests: [Person]
        public var crew: [Department]
        enum CodingKeys: String, CodingKey { case cast, guests, crew }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cast = (try? c.decodeIfPresent([Person].self, forKey: .cast)) ?? []
            guests = (try? c.decodeIfPresent([Person].self, forKey: .guests)) ?? []
            crew = (try? c.decodeIfPresent([Department].self, forKey: .crew)) ?? []
        }
        public var isEmpty: Bool { cast.isEmpty && guests.isEmpty && crew.allSatisfy { $0.people.isEmpty } }
    }

    public struct Trailer: Decodable, Equatable, Sendable {
        public var itemId: Int64
        public var title: String
        public var type: String
        public var durationSec: Int
        enum CodingKeys: String, CodingKey { case itemId, title, type, durationSec }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            itemId = (try? c.decodeIfPresent(Int64.self, forKey: .itemId)) ?? 0
            title = PlainWords.clean((try? c.decodeIfPresent(String.self, forKey: .title)) ?? "", limit: 120)
            type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
            durationSec = (try? c.decodeIfPresent(Int.self, forKey: .durationSec)) ?? 0
        }
    }

    public struct Airing: Decodable, Equatable, Sendable {
        public var channel: String
        public var channelName: String
        public var start: Int64
        public var this: Bool
        enum CodingKeys: String, CodingKey { case channel, key, channelName, name, number, start, this }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            channel = (try? c.decodeIfPresent(String.self, forKey: .channel)) ?? (try? c.decodeIfPresent(String.self, forKey: .key)) ?? ""
            channelName = PlainWords.clean((try? c.decodeIfPresent(String.self, forKey: .channelName)) ?? (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "", limit: 80)
            start = (try? c.decodeIfPresent(Int64.self, forKey: .start)) ?? 0
            this = (try? c.decodeIfPresent(Bool.self, forKey: .this)) ?? false
        }
    }

    public struct Library: Decodable, Equatable, Sendable {
        public var itemId: Int64?
        public var showId: Int64?
    }

    public var channel: Channel
    public var programme: Programme
    public var actions: Actions
    public var library: Library?
    public var credits: Credits?
    public var trailers: [Trailer]
    public var schedule: [Airing]

    enum CodingKeys: String, CodingKey { case channel, programme, actions, library, credits, trailers, schedule }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channel = try c.decode(Channel.self, forKey: .channel)
        programme = try c.decode(Programme.self, forKey: .programme)
        actions = (try? c.decodeIfPresent(Actions.self, forKey: .actions)) ?? Actions()
        library = try? c.decodeIfPresent(Library.self, forKey: .library)
        credits = try? c.decodeIfPresent(Credits.self, forKey: .credits)
        trailers = (try? c.decodeIfPresent([Trailer].self, forKey: .trailers)) ?? []
        schedule = (try? c.decodeIfPresent([Airing].self, forKey: .schedule)) ?? []
    }

    public init(channel: Channel, programme: Programme, actions: Actions = Actions(), library: Library? = nil,
                credits: Credits? = nil, trailers: [Trailer] = [], schedule: [Airing] = []) {
        self.channel = channel
        self.programme = programme
        self.actions = actions
        self.library = library
        self.credits = credits
        self.trailers = trailers
        self.schedule = schedule
    }
}

public extension WittyClient {
    /// One programme in full; `start` is any moment in it, in Unix seconds. A 404 means it isn't there for this profile.
    func programmeInfo(channel key: String, start: Int64) async throws -> ProgrammeInfo {
        try await get("/tv/\(WittyClient.pathPart(key))/programme?start=\(start)")
    }
}

public enum MoreInfo {
    /// The programme as `DesignPageSpec` data: the eyebrow is the channel, the title and times lead, the description under
    /// them; then the buttons the server offered, facts, cast and crew, trailers and other airings. The advisory is
    /// never in it.
    public static func spec(_ info: ProgrammeInfo, now: Date = Date(), zone: TimeZone = .current) -> DesignPageSpec {
        let p = info.programme
        var sections: [DesignPageSpec.Section] = []
        var actions: [DesignPageSpec.Action] = []
        let a = info.actions
        if a.watch { actions.append(.A1(p.start * 1 <= Int64(now.timeIntervalSince1970) ? "Watch now" : "Watch")) }
        if a.fromStart { actions.append(.A2("Watch from the start")) }
        if a.record { actions.append(.A2("Record")) }
        if a.remind || a.reminded { actions.append(.A2(a.reminded ? "Remove reminder" : "Remind me")) }
        if a.open, info.library != nil { actions.append(.A2("Open item page")) }
        if a.watchLater { actions.append(.A2(a.inList ? "Remove from watch list" : "Add to watch list")) }

        var facts: [DesignPageSpec.Row] = []
        func fact(_ title: String, _ value: String) { if !value.isEmpty { facts.append(DesignPageSpec.Row(title: title, value: value, pressable: false)) } }
        fact("Genres", p.genres.factsLine())
        fact("Rating", p.rating)
        fact("Year", p.year.map(String.init) ?? "")
        if let s = p.season, let e = p.episode { fact("Episode", "Season \(s) · Episode \(e)") }
        fact("Length", p.lengthMin.map { "\($0) min" } ?? "")
        fact("Studio", p.studio)
        fact("Language", p.language)
        fact("Country", p.country)
        fact("Sound", p.audio)
        fact("Score", p.scores.map { "\($0.system) \(trim($0.value))" }.factsLine())
        var flags: [String] = []
        if p.new { flags.append("New") }
        if p.premiere { flags.append("Premiere") }
        if p.repeated { flags.append("Repeat") }
        if p.hd { flags.append("HD") }
        fact("This airing", flags.factsLine())
        if !p.desc.isEmpty { sections.append(.secN("", p.desc)) }
        if !facts.isEmpty { sections.append(.secR("About", facts)) }

        if let credits = info.credits, !credits.isEmpty {
            let people = credits.cast + credits.guests
            if !people.isEmpty {
                sections.append(.secR("Cast", people.prefix(24).enumerated().map { personRow($1, "cast\($0)") }))
            }
            for d in credits.crew where !d.people.isEmpty {
                sections.append(.secR(d.label.isEmpty ? "Crew" : d.label, d.people.prefix(8).enumerated().map { personRow($1, "\(d.label)\($0)") }))
            }
        }
        if !info.trailers.isEmpty {
            sections.append(.secR("Trailers and clips", info.trailers.map {
                DesignPageSpec.Row(id: "trailer-\($0.itemId)", title: $0.title, value: $0.durationSec > 0 ? duration($0.durationSec) : $0.type)
            }))
        }
        let others = info.schedule.filter { !$0.this }
        if !others.isEmpty {
            sections.append(.secR("Also on", others.prefix(8).map {
                DesignPageSpec.Row(id: "airing-\($0.channel)-\($0.start)", title: $0.channelName.isEmpty ? $0.channel : $0.channelName,
                                   value: when($0.start, now: now, zone: zone))
            }))
        }
        let number = info.channel.number.isEmpty ? "" : "Ch \(info.channel.number) · "
        let eyebrow = "WittyTV · \(number)\(info.channel.name)"
        let lead = [when(p.start, now: now, zone: zone) + (p.end > p.start ? " – " + clock(p.end, zone: zone) : ""), p.sub].filter { !$0.isEmpty }.factsLine()
        return DesignPageSpec(eyebrow: eyebrow, title: p.title, lead: lead, sections: sections, actions: actions, layer: true)
    }

    private static func personRow(_ p: ProgrammeInfo.Person, _ slot: String) -> DesignPageSpec.Row {
        // A person only the guide names has no page: the row says who and what, and isn't a stop for focus.
        let part = p.character.isEmpty ? p.job : p.character
        return DesignPageSpec.Row(id: p.personId.map { "person-\($0)" } ?? "guide-" + DesignPageSpec.slug(slot), title: p.name, value: part, pressable: p.openable)
    }

    private static func trim(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    private static func duration(_ sec: Int) -> String { sec >= 3600 ? "\(sec / 3600) hr \(sec % 3600 / 60) min" : "\(max(1, sec / 60)) min" }

    static func clock(_ unix: Int64, zone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: .current) ?? "h:mm a"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    /// "Tonight 7:30 PM" style: today's time alone, other days with their weekday.
    static func when(_ unix: Int64, now: Date, zone: TimeZone) -> String {
        guard unix > 0 else { return "" }
        var cal = Calendar.current
        cal.timeZone = zone
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        if cal.isDate(date, inSameDayAs: now) { return "Today " + clock(unix, zone: zone) }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow " + clock(unix, zone: zone) }
        let f = DateFormatter()
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date) + " " + clock(unix, zone: zone)
    }
}

public extension WittyClient {
    /// Adds a library title (or a show) to Watch later, or takes it off (`POST`/`DELETE /collections/watch-later/items`).
    func setWatchLater(item: Int64?, show: Int64?, on: Bool) async throws {
        struct Body: Encodable { let items: [Int64]; let shows: [Int64] }
        let body = Body(items: item.map { [$0] } ?? [], shows: show.map { [$0] } ?? [])
        _ = try await call(on ? "POST" : "DELETE", "/collections/watch-later/items", body: try JSONEncoder().encode(body))
    }
}
