// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import SwiftUI
import WittyKit

// What WittyTV's screens on Apple TV share: this account's look, the guide's channels a page at a
// time, the logos, and reminders. Each is kept as the server's page keeps it (web/src/pages/tv/
// look.ts, GuidePage.tsx and reminders.tsx), so a change made on any device shows here.

/// This account's WittyTV look, as `useLook` works it out on the page.
@MainActor
final class TvLookStore: ObservableObject {
    static let shared = TvLookStore()

    /// What's saved with the account, as it came.
    private var raw: [String: Any] = [:]
    private var owner: String?
    private var suggestion: String?
    private var app = TvAppColours.fallback
    private var askedFor = ""
    @Published private(set) var look = TvLook.resolve(saved: nil, ownerTheme: nil) {
        didSet { dress = TvDress(look) }
    }
    @Published private(set) var loaded = false

    /// The look worked out into colours and sizes once, when it changes: the guide asks for it hundreds of times each
    /// time the highlight moves, and working it out reads every colour from its hex code.
    private(set) var dress = TvDress(TvLook.resolve(saved: nil, ownerTheme: nil))

    /// Asks the server what this account chose, and what the app's theme suggests.
    func load(client: WittyClient, themeId: String?, app: TvAppColours) async {
        self.app = app
        let asking = client.base + "|" + (themeId ?? "")
        if askedFor != asking {
            askedFor = asking
            suggestion = nil
            if let themeId, !themeId.isEmpty { suggestion = try? await client.themeSuggestsTv(themeId) }
        }
        if let data = try? await client.rawUI(), let ui = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            raw = ui["tvLook"] as? [String: Any] ?? [:]
        }
        loaded = true
        resolve()
    }

    /// The owner's starting look comes with every page of the guide.
    func learnOwner(_ guide: Guide) {
        let next = guide.theme
        guard next != owner else { return }
        owner = next
        resolve()
    }

    private func resolve() {
        let saved = (try? JSONSerialization.data(withJSONObject: raw)).flatMap { try? JSONDecoder().decode(TvSaved.self, from: $0) }
        look = TvLook.resolve(saved: saved, suggestion: suggestion, ownerTheme: owner.flatMap { $0.isEmpty ? nil : $0 },
                              app: app)
    }

    /// A change shows at once, and goes to the account to follow it to other devices.
    func change(_ patch: [String: Any?], client: WittyClient) {
        for (key, value) in patch {
            if let value { raw[key] = value } else { raw.removeValue(forKey: key) }
        }
        resolve()
        Task { try? await client.saveTvLook(patch) }
    }

    /// Picks a theme. Custom starts from what's on the screen, so there's nothing to set up to begin with.
    func pick(_ theme: String, client: WittyClient) {
        var patch: [String: Any?] = ["theme": theme]
        if theme == "custom", raw["custom"] == nil {
            patch["custom"] = ["shape": look.shape.rawValue, "font": look.font]
        }
        change(patch, client: client)
    }
}

/// The guide's channels, a page at a time, for the stretch of hours on screen. Only the rows near
/// what's shown are asked for, so a playlist of thousands of channels stays quick. With a page size, only that
/// page's rows are on screen; with none, they're one list that loads as it scrolls. The channels are a set's, narrowed by
/// a filter, and the server finds channels by name and number.
@MainActor
final class GuideStore: ObservableObject {
    struct Filter: Equatable {
        var kind = ""
        var group = ""
        var favourites = false
        /// A channel set's id.
        var set = ""
        /// Only channels whose number starts with this or whose name has it in it.
        var q = ""
        var isAll: Bool { kind.isEmpty && group.isEmpty && !favourites && (self.set.isEmpty || self.set == ChannelSetRules.all) && q.isEmpty }
        /// The set as the server is asked for it: all channels is the same as none.
        var setAsked: String { self.set == ChannelSetRules.all ? "" : self.set }
    }

    @Published private(set) var rows: [Int: GuideChannel] = [:]
    @Published private(set) var total: Int?
    @Published private(set) var groups: [String] = []
    @Published private(set) var lineup: [GuideChannel] = [] {
        didSet {
            lineupHasBoth = lineup.contains { $0.kind == "tuner" } && lineup.contains { $0.kind == "library" }
            lineupAnyFavourite = lineup.contains { $0.favourite == true }
        }
    }
    /// What the guide's bar asks of the lineup, worked out when it changes rather than each time the highlight
    /// moves: a lineup can be ten thousand channels long.
    private(set) var lineupHasBoth = false
    private(set) var lineupAnyFavourite = false
    @Published var error = ""
    @Published private(set) var filter = Filter()
    /// Rows a page, or 0 for all of them in one list; and the first row of the page on screen.
    @Published private(set) var pageSize = 0
    @Published private(set) var pageStart = 0
    /// The sets this profile can choose from.
    @Published private(set) var sets: [ChannelSet] = []
    @Published private(set) var canShare = false
    private var fetchFrom: Int64 = 0
    private var loaded = Set<String>()
    private var client = WittyClient(base: "")

    /// How many rows are asked for at once.
    var fetchSize: Int { GuidePaging.fetchSize(pageSize: pageSize) }
    /// The rows on screen: the page's, or all of them.
    var shown: Range<Int> { GuidePaging.rows(start: pageStart, size: pageSize, total: total ?? 0) }

    func use(_ client: WittyClient) {
        self.client = client
    }

    /// A changed filter starts the rows afresh, at the first page.
    func setFilter(_ next: Filter) {
        guard next != filter else { return }
        filter = next
        loaded.removeAll()
        rows = [:]
        total = nil
        pageStart = 0
    }

    /// A new page size keeps the row with the highlight on screen.
    func setPageSize(_ size: Int, keeping row: Int) {
        guard size != pageSize else { return }
        pageSize = size
        pageStart = GuidePaging.pageStart(of: row, size: size)
    }

    /// The page holding a row comes on screen.
    func showPage(holding row: Int) {
        let start = GuidePaging.pageStart(of: row, size: pageSize)
        if start != pageStart { pageStart = start }
    }

    /// A new stretch of hours keeps the rows until the new ones come, so the highlight has somewhere to be.
    func setFrom(_ from: Int64) {
        let start = (from / GuideRules.fetchSpan) * GuideRules.fetchSpan
        if start != fetchFrom {
            fetchFrom = start
            loaded.removeAll()
        }
    }

    /// Everything again, as the page does every few minutes while it's open.
    func refresh() {
        loaded.removeAll()
    }

    func ensure(_ row: Int) async {
        let size = fetchSize
        let page = max(0, row) / size
        let asked = filter
        let key = "\(fetchFrom)|\(asked.kind)|\(asked.group)|\(asked.favourites)|\(asked.set)|\(asked.q)|\(size)|\(page)"
        guard !loaded.contains(key) else { return }
        loaded.insert(key)
        do {
            let g = try await client.guidePage(GuideRules.query(from: fetchFrom, offset: page * size, limit: size, kind: asked.kind, group: asked.group,
                                                                favourites: asked.favourites, set: asked.setAsked, q: asked.q))
            guard asked == filter else { return }
            TvLookStore.shared.learnOwner(g)
            total = g.total ?? (g.channels ?? []).count
            let fresh = g.groups ?? []
            groups = asked.isAll ? fresh : Array(Set(groups + fresh)).sorted()
            var next = rows
            for (i, c) in (g.channels ?? []).enumerated() { next[(g.offset ?? page * size) + i] = c }
            rows = next
            error = ""
        } catch {
            loaded.remove(key)
            if !(error is CancellationError) { self.error = (error as? APIError)?.message ?? "The guide couldn't be loaded." }
        }
    }

    /// Every channel's number and name: for favourites, Last, and finding a channel by its key. Without the
    /// schedule's other fields where the server can leave them out.
    func loadLineup() async {
        if let all = try? await client.channelList(limit: 20000) { lineup = uniqued(all.channels ?? []) }
    }

    /// The sets there are, and the one to show: the one remembered while it's still there, otherwise all.
    func loadSets(remembered: String?) async -> String {
        guard let list = try? await client.channelSets() else { return ChannelSetRules.all }
        sets = list.sets
        canShare = list.canShare
        return ChannelSetRules.chosen(remembered, in: list.sets)
    }

    /// Where a channel is in what's on screen, by its key or number.
    func locate(_ target: String) async -> Int? {
        guard let found = try? await client.channelList(set: filter.setAsked, q: filter.q, locate: target, limit: 1) else { return nil }
        return found.located.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// A number typed on the remote: in what's on screen, or failing that among all channels.
    func locateNumber(_ number: String) async -> LocateOutcome {
        let here = await locate(number)
        if here != nil || filter.isAll { return LocateRules.outcome(inSet: here, inAll: nil) }
        let all = try? await client.channelList(locate: number, limit: 1)
        return LocateRules.outcome(inSet: nil, inAll: all?.located)
    }

    /// Marks a channel a favourite or not, at once, then tells the server.
    func setFavourite(_ channel: GuideChannel, _ on: Bool) async throws {
        for (i, c) in rows where c.key == channel.key { rows[i] = c.with(favourite: on) }
        lineup = lineup.map { $0.key == channel.key ? $0.with(favourite: on) : $0 }
        try await client.setFavourite(channel.key, on)
    }
}

/// Channel logos from the logo service, asked for once per name.
@MainActor
final class TvLogos: ObservableObject {
    static let shared = TvLogos()
    @Published private(set) var known: [String: LogoInfo] = [:]
    private var asked = Set<String>()

    private func key(_ b: GuideBrand) -> String { b.kind + "|" + b.name.lowercased() }

    func info(_ brand: GuideBrand?) -> LogoInfo? { brand.flatMap { known[key($0)] } }

    func ask(_ brands: [GuideBrand], client: WittyClient) async {
        let fresh = brands.filter { asked.insert(key($0)).inserted }
        guard !fresh.isEmpty, let found = try? await client.lookupLogos(fresh) else { return }
        for logo in found { known[logo.kind + "|" + logo.name.lowercased()] = logo }
    }
}

/// "Tell me when this starts": the account's reminders, asked for once, and the one coming due.
@MainActor
final class TvReminders: ObservableObject {
    static let shared = TvReminders()
    @Published private(set) var list: [TvReminder] = []
    @Published var due: TvReminder?
    private var shown = Set<Int64>()
    private var loadedFor = ""
    private var waiting: Task<Void, Never>?
    private var client = WittyClient(base: "")

    func has(_ channel: String, _ start: Int64) -> Bool { list.contains { $0.channel == channel && $0.start == start } }

    func load(client: WittyClient) async {
        self.client = client
        guard loadedFor != client.base + client.token else { return }
        loadedFor = client.base + client.token
        list = ((try? await client.reminders()) ?? []).sorted { $0.start < $1.start }
        watch()
    }

    /// Sets a reminder, or takes it away. Answers what to say.
    @discardableResult
    func toggle(_ channel: String, _ p: GuideProgramme) async -> String {
        if let found = list.first(where: { $0.channel == channel && $0.start == p.start }) {
            do {
                try await client.removeReminder(found.id)
                list.removeAll { $0.id == found.id }
                watch()
                return "Reminder for \(p.title) removed"
            } catch { return (error as? APIError)?.message ?? "That didn't work. Try again." }
        }
        do {
            let r = try await client.addReminder(channel: channel, title: p.title, sub: p.sub, start: p.start, end: p.end)
            list = (list + [r]).sorted { $0.start < $1.start }
            watch()
            return "We'll tell you when \(p.title) starts"
        } catch { return (error as? APIError)?.message ?? "That didn't work. Try again." }
    }

    /// Once a reminder has been seen it goes: the server would drop it once the programme ends anyway.
    func dismiss(_ r: TvReminder) {
        if due?.id == r.id { due = nil }
        list.removeAll { $0.id == r.id }
        let c = client
        Task { try? await c.removeReminder(r.id) }
        watch()
    }

    /// One wait, for the next reminder: a TV left on does nothing until one is due.
    private func watch() {
        waiting?.cancel()
        let now = Int64(Date().timeIntervalSince1970)
        if due == nil, let next = ReminderRules.due(list, shown: shown, now: now) {
            shown.insert(next.id)
            due = next
        }
        guard let at = ReminderRules.nextCheck(list, shown: shown, now: now) else { return }
        waiting = Task { [weak self] in
            let wait = max(1, at - Int64(Date().timeIntervalSince1970))
            try? await Task.sleep(nanoseconds: UInt64(min(wait, 3600)) * 1_000_000_000)
            if Task.isCancelled { return }
            self?.watch()
        }
    }
}
#endif
