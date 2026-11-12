// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// What the guide gained for a server with thousands of channels: channel sets (which channels the guide shows, in
// which order), pages of them, finding one by name or number, watching a programme from its start, and recording
// options. Each is offered only when the server names it in its capabilities, so an older server's guide is as it
// was. The server's side is in its docs (live TV); these rules are what the apps draw from, held by ChannelSetsTests.

/// The capability names live TV's newer parts go by.
public enum TvFeature {
    /// Channel sets, and `set=` on the guide.
    public static let sets = "tv-sets"
    /// `q`, `locate` and `lite` on the guide.
    public static let paging = "tv-guide-paging"
    /// Watching a programme of an archived channel from its start.
    public static let catchup = "tv-catchup"
    /// Padding, and new-only, any-channel and keep-the-newest series rules.
    public static let dvrRules = "tv-dvr-rules-2"
}

// MARK: - Sets

/// One choice of which channels the guide shows: all of them, favourites, someone's own set, a source or a group.
public struct ChannelSet: Decodable, Equatable, Identifiable {
    public let id: String
    /// `all`, `favourites`, `custom`, `source` or `group`.
    public let kind: String
    public let name: String
    /// How many channels this profile may see in it.
    public let count: Int?
    public let shared: Bool?
    public let editable: Bool?
    public let mine: Bool?
    /// A source's kind of tuner, such as `iptv`.
    public let driver: String?

    public init(id: String, kind: String, name: String, count: Int? = nil, shared: Bool? = nil, editable: Bool? = nil, mine: Bool? = nil, driver: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.count = count
        self.shared = shared
        self.editable = editable
        self.mine = mine
        self.driver = driver
    }

    public var isCustom: Bool { kind == "custom" }
    /// This account may change it: its own, or a shared one for an administrator.
    public var canEdit: Bool { isCustom && editable == true }
    /// Made by this account, whether or not it's shared.
    public var isMine: Bool { isCustom && (mine ?? (shared != true)) }
}

/// GET /tv-sets.
public struct ChannelSetList: Decodable, Equatable {
    public let sets: [ChannelSet]
    /// Whether this account may share a set with every profile: administrators only.
    public let canShare: Bool

    public init(sets: [ChannelSet], canShare: Bool = false) {
        self.sets = sets
        self.canShare = canShare
    }

    private enum CodingKeys: String, CodingKey { case sets, canShare }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sets = try values.decodeIfPresent([ChannelSet].self, forKey: .sets) ?? []
        canShare = try values.decodeIfPresent(Bool.self, forKey: .canShare) ?? false
    }
}

/// One custom set with its channels, in its order.
public struct ChannelSetDetail: Decodable, Equatable {
    public let id: String
    public let name: String
    public let shared: Bool
    public let editable: Bool
    public let channels: [String]

    public init(id: String, name: String, shared: Bool = false, editable: Bool = true, channels: [String] = []) {
        self.id = id
        self.name = name
        self.shared = shared
        self.editable = editable
        self.channels = channels
    }

    private enum CodingKeys: String, CodingKey { case id, name, shared, editable, channels }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // The path takes the number; the guide takes "set:7". Either way round, it's kept as the guide's.
        if let text = try? values.decode(String.self, forKey: .id) {
            id = text.hasPrefix("set:") ? text : "set:" + text
        } else {
            id = "set:\(try values.decode(Int64.self, forKey: .id))"
        }
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        shared = try values.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        editable = try values.decodeIfPresent(Bool.self, forKey: .editable) ?? true
        channels = try values.decodeIfPresent([String].self, forKey: .channels) ?? []
    }
}

/// A heading of the set picker and the sets under it.
public struct ChannelSetSection: Equatable {
    public let title: String
    public let sets: [ChannelSet]
}

public enum ChannelSetRules {
    /// Every channel: what the guide shows when nothing else is chosen, or what was chosen has gone.
    public static let all = "all"
    public static let nameLimit = 40
    public static let setLimit = 50
    public static let channelLimit = 5000

    /// The picker's sections, in the server's order within each, leaving out any with nothing in it.
    public static func sections(_ sets: [ChannelSet]) -> [ChannelSetSection] {
        let parts: [(String, (ChannelSet) -> Bool)] = [
            ("All & Favourites", { $0.kind == "all" || $0.kind == "favourites" }),
            ("My sets", { $0.isMine }),
            ("Shared", { $0.isCustom && !$0.isMine }),
            ("Sources", { $0.kind == "source" }),
            ("Groups", { $0.kind == "group" }),
        ]
        return parts.compactMap { title, test in
            let found = sets.filter(test)
            return found.isEmpty ? nil : ChannelSetSection(title: title, sets: found)
        }
    }

    /// The set before or after this one, in the picker's order, going round at either end: the remote's way of
    /// changing set without opening the picker. A set that isn't there starts from the first.
    public static func cycle(_ current: String, in sets: [ChannelSet], by step: Int) -> String? {
        let ordered = sections(sets).flatMap(\.sets)
        guard !ordered.isEmpty else { return nil }
        guard let at = ordered.firstIndex(where: { $0.id == current }) else { return ordered[0].id }
        let n = ordered.count
        return ordered[((at + step) % n + n) % n].id
    }

    /// The set to show: the one this device remembers while the server still has it, otherwise all channels.
    public static func chosen(_ remembered: String?, in sets: [ChannelSet]) -> String {
        guard let remembered, !remembered.isEmpty, sets.contains(where: { $0.id == remembered }) else { return all }
        return remembered
    }

    /// Where this device keeps its choice: one per server and account, as two people on one TV choose their own.
    public static func storageKey(server: String, account: Int64?) -> String {
        "wms.tv.set.\(server).\(account ?? 0)"
    }

    /// The number a custom set goes by in an address: "set:7" is 7. Nothing for any other kind.
    public static func pathId(_ id: String) -> String? {
        guard id.hasPrefix("set:") else { return nil }
        let number = String(id.dropFirst(4))
        return !number.isEmpty && number.allSatisfy(\.isASCII) && number.allSatisfy(\.isNumber) ? number : nil
    }

    /// What a set is called, for the guide's bar.
    public static func name(of id: String, in sets: [ChannelSet]) -> String {
        sets.first { $0.id == id }?.name ?? (id == all || id.isEmpty ? "All channels" : id)
    }

    /// What's wrong with a name for a set, or nil when it will do. Names are unique among this account's own.
    public static func nameProblem(_ name: String, among sets: [ChannelSet], renaming id: String? = nil) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return "Give the set a name." }
        if clean.count > nameLimit { return "A set's name can be \(nameLimit) characters at most." }
        if sets.contains(where: { $0.isMine && $0.id != id && $0.name.compare(clean, options: [.caseInsensitive]) == .orderedSame }) {
            return "You already have a set called \(clean)."
        }
        return nil
    }

    /// The list with one entry moved up (a negative step) or down. A move past either end leaves it as it is.
    public static func moved<T>(_ list: [T], at index: Int, by step: Int) -> [T] {
        let to = index + step
        guard list.indices.contains(index), list.indices.contains(to), step != 0 else { return list }
        var out = list
        let item = out.remove(at: index)
        out.insert(item, at: to)
        return out
    }

    /// A channel ticked or unticked in the channel picker: a new one goes at the end.
    public static func toggled(_ channels: [String], _ key: String) -> [String] {
        channels.contains(key) ? channels.filter { $0 != key } : channels + [key]
    }

    /// The custom sets' ids in the order shown, for PUT /tv-sets/order.
    public static func customOrder(_ sets: [ChannelSet]) -> [String] { sets.filter(\.isCustom).map(\.id) }

    /// The whole list with its custom sets in a new order and everything else where it was, as the server will
    /// list it once it has been told.
    public static func reordered(_ sets: [ChannelSet], ids: [String]) -> [ChannelSet] {
        let custom = sets.filter(\.isCustom)
        let byId = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order = ids.compactMap { byId[$0] }
        order += custom.filter { !ids.contains($0.id) }
        var next = order.makeIterator()
        return sets.map { $0.isCustom ? (next.next() ?? $0) : $0 }
    }

    /// The server's `q`: a number that starts with it, or a name that has it in it, whatever the case.
    public static func matches(_ channel: GuideChannel, _ q: String) -> Bool {
        let words = q.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty { return true }
        return (channel.number ?? "").hasPrefix(words) || channel.name.range(of: words, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

// MARK: - Pages

/// The guide a page at a time, or all of it in one list that loads as it scrolls.
public enum GuidePaging {
    /// The choices of how many channels a page has. 0 is all of them.
    public static let sizes = [25, 50, 75, 100, 0]
    /// Rows asked for at a time when they're all in one list.
    public static let chunk = 100
    /// Where this device keeps its choice.
    public static let storageKey = "wms.tv.guide.pageSize"

    /// A size kept on this device, if it's still one of the choices; otherwise all in one list, as the guide always was.
    public static func size(stored: Int?) -> Int {
        guard let stored, sizes.contains(stored) else { return 0 }
        return stored
    }

    public static func sizeName(_ size: Int) -> String { size > 0 ? "\(size)" : "All" }

    /// How many rows to ask for at once: a page's worth, or a chunk of the one list. An older server's guide is
    /// asked in the smaller pieces it always was.
    public static func fetchSize(pageSize: Int, paging: Bool) -> Int {
        pageSize > 0 ? pageSize : paging ? chunk : GuideRules.page
    }

    /// The first row of the page holding a row.
    public static func pageStart(of index: Int, size: Int) -> Int {
        guard size > 0 else { return 0 }
        let row = max(0, index)
        return row - row % size
    }

    /// The rows a page shows.
    public static func rows(start: Int, size: Int, total: Int) -> Range<Int> {
        let total = max(0, total)
        guard size > 0 else { return 0..<total }
        let from = min(max(0, start), total)
        return from..<min(total, from + size)
    }

    public static func next(start: Int, size: Int, total: Int) -> Int? {
        guard size > 0, start + size < total else { return nil }
        return start + size
    }

    public static func previous(start: Int, size: Int) -> Int? {
        guard size > 0, start > 0 else { return nil }
        return max(0, start - size)
    }

    /// "51–100 of 10,423", or "10,423 channels" when they're all in one list.
    public static func words(start: Int, size: Int, total: Int, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        func n(_ x: Int) -> String { f.string(from: NSNumber(value: x)) ?? String(x) }
        if total <= 0 { return "No channels" }
        let shown = rows(start: start, size: size, total: total)
        if size <= 0 || (shown.lowerBound == 0 && shown.upperBound == total) {
            return total == 1 ? "1 channel" : "\(n(total)) channels"
        }
        return "\(n(shown.lowerBound + 1))–\(n(shown.upperBound)) of \(n(total))"
    }

    /// The channel list without the schedule (`list=1&lite=1`): for the channel picker, finding a channel and
    /// dialling a number. Only what's given is sent.
    public static func listQuery(set: String = "", q: String = "", locate: String = "", offset: Int = 0, limit: Int) -> String {
        "/guide?list=1&lite=1&offset=\(max(0, offset))&limit=\(max(1, limit))"
            + (set.isEmpty ? "" : "&set=\(WittyClient.queryValue(set))")
            + (q.isEmpty ? "" : "&q=\(WittyClient.queryValue(q))")
            + (locate.isEmpty ? "" : "&locate=\(WittyClient.queryValue(locate))")
    }
}

// MARK: - Going to a channel

/// Where a channel asked for by its number turned up.
public enum LocateOutcome: Equatable {
    /// In the set on screen, at this row.
    case here(Int)
    /// Not in the set on screen, but among all channels, at this row: offer to show all channels.
    case inAll(Int)
    case nowhere
}

public enum LocateRules {
    /// What a number typed on a remote or a pad means: digits, and the dot or dash of a subchannel (4.1, 4-1).
    public static func number(_ typed: String) -> String {
        String(typed.trimmingCharacters(in: .whitespaces).filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-") }.prefix(12))
    }

    /// Whether, when it's not in the set, all channels are worth asking too.
    public static func shouldTryAll(set: String) -> Bool { !set.isEmpty && set != ChannelSetRules.all }

    /// The answer from the set and, when it was asked, from all channels. `located` is -1 when it isn't there.
    public static func outcome(inSet: Int?, inAll: Int?) -> LocateOutcome {
        if let inSet, inSet >= 0 { return .here(inSet) }
        if let inAll, inAll >= 0 { return .inAll(inAll) }
        return .nowhere
    }

    /// The same, from this device's own list of channels, for a server without `locate`.
    public static func index(of number: String, in channels: [GuideChannel]) -> Int? {
        let wanted = LocateRules.number(number)
        guard !wanted.isEmpty else { return nil }
        return channels.firstIndex { ($0.number ?? "") == wanted } ?? channels.firstIndex { $0.key == number }
    }
}

// MARK: - From the start

public enum CatchupRules {
    /// "Watch from the start": a programme that has started, on a channel whose source keeps that far back, and
    /// that's a real programme rather than a gap or the channel's own "back soon".
    public static func canWatchFromStart(_ programme: GuideProgramme?, on channel: GuideChannel, now: Int64) -> Bool {
        guard let programme, let days = channel.catchupDays, days > 0, channel.canTune else { return false }
        guard programme.kind != "slate", programme.kind != "none", programme.end > programme.start else { return false }
        return programme.start <= now && programme.start >= now - Int64(days) * 86400
    }

    /// GET /tv/{key}/catchup: the programme's own times, and this player's name so leaving stops it.
    public static func query(key: String, start: Int64, end: Int64, viewer: String) -> String {
        "/tv/\(WittyClient.pathPart(key))/catchup?start=\(start)&end=\(end)&viewer=\(WittyClient.pathPart(viewer))&streamToken=1"
    }
}

// MARK: - Recording options

/// How a recording or a series is made, with `tv-dvr-rules-2`.
public struct RecordingOptions: Equatable {
    /// Minutes before the start and after the end, 0 to 60.
    public var padBefore: Int
    public var padAfter: Int
    /// A series: skip an episode this rule already recorded.
    public var newOnly: Bool
    /// A series: on whichever channel it's on, not only this one.
    public var anyChannel: Bool
    /// A series: keep the newest this many, 0 for all.
    public var keep: Int

    public static let paddings = [0, 1, 2, 5, 10, 15, 30, 60]
    public static let keeps = [0, 1, 3, 5, 10]
    public static let most = 60

    public init(padBefore: Int = 0, padAfter: Int = 0, newOnly: Bool = false, anyChannel: Bool = false, keep: Int = 0) {
        self.padBefore = min(RecordingOptions.most, max(0, padBefore))
        self.padAfter = min(RecordingOptions.most, max(0, padAfter))
        self.newOnly = newOnly
        self.anyChannel = anyChannel
        self.keep = max(0, keep)
    }

    /// "Keep all", "Keep the newest 5".
    public static func keepName(_ n: Int) -> String { n <= 0 ? "Keep all" : n == 1 ? "Keep the newest one" : "Keep the newest \(n)" }

    /// "No padding", "1 min before, 5 min after".
    public var paddingWords: String {
        switch (padBefore, padAfter) {
        case (0, 0): return "No padding"
        case (let b, 0): return "\(b) min before"
        case (0, let a): return "\(a) min after"
        case (let b, let a): return "\(b) min before, \(a) min after"
        }
    }

    /// A series rule's options in a line, for the list of series.
    public var seriesWords: String {
        [anyChannel ? "Any channel" : "", newOnly ? "New episodes only" : "", keep > 0 ? RecordingOptions.keepName(keep) : "",
         padBefore + padAfter > 0 ? paddingWords : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
