// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Watch parties: the server's docs/SYNCPLAY.md. The server holds one state for each room and it is the only
// truth: "at server time atMs the position is positionSec". Every player works out from that where it should
// be, and no player ever tells the room where it is. What is here is the arithmetic and the decisions, with
// every clock handed in, so they can be walked through a tick at a time: the server's clock from pings
// (internal/syncplay/clock.go, `ClockOffset` and `BestOffset`), the room's position, the drift rule (`Correct`,
// and web/src/player/sync.ts), and what a player does on each tick (web/src/remote/party.ts).

// MARK: - Messages

/// The drift thresholds, from `GET /syncplay` so that nobody copies the numbers.
public struct SyncDrift: Decodable, Equatable, Sendable {
    /// Closer than this: leave it alone.
    public var stillSec = 0.12
    /// Once nudging, carry on until this close.
    public var settledSec = 0.04
    /// This far off, or more: jump.
    public var seekSec = 3.0
    /// Play this much faster or slower to catch up or fall back.
    public var rate = 0.03

    public init() {}

    private enum CodingKeys: String, CodingKey { case stillSec, settledSec, seekSec, rate }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, _ usual: Double) -> Double {
            let found = (try? values.decodeIfPresent(Double.self, forKey: key)) ?? nil
            guard let found, found.isFinite, found > 0 else { return usual }
            return found
        }
        stillSec = number(.stillSec, 0.12)
        settledSec = number(.settledSec, 0.04)
        seekSec = number(.seekSec, 3)
        rate = min(0.25, number(.rate, 0.03))
    }
}

public struct SyncLimits: Decodable, Equatable, Sendable {
    public var queue = 200
    public var codeLength = 6
    public var pingEverySec = 5.0
    public var seatGraceSec = 120.0

    public init() {}

    private enum CodingKeys: String, CodingKey { case queue, codeLength, pingEverySec, seatGraceSec }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let n = (try? values.decodeIfPresent(Int.self, forKey: .queue)) ?? nil, n > 0 { queue = n }
        if let n = (try? values.decodeIfPresent(Int.self, forKey: .codeLength)) ?? nil, n > 0, n <= 12 { codeLength = n }
        if let n = (try? values.decodeIfPresent(Double.self, forKey: .pingEverySec)) ?? nil, n >= 1 { pingEverySec = n }
        if let n = (try? values.decodeIfPresent(Double.self, forKey: .seatGraceSec)) ?? nil, n > 0 { seatGraceSec = n }
    }
}

/// A room in the list of an account's rooms: one it has a seat in from this sign-in, or is invited to. It
/// never says what the room is playing.
public struct SyncListing: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let hostName: String?
    public let members: Int?
    public let memberId: String?
    public let invited: Bool?

    public var seated: Bool { !(memberId ?? "").isEmpty }
    /// "Started by Sam · 3 watching".
    public var line: String {
        var parts: [String] = []
        if let hostName, !hostName.isEmpty { parts.append("Started by \(PlainWords.clean(hostName, limit: 60))") }
        if let members { parts.append("\(members) watching") }
        return parts.factsLine()
    }
}

/// `GET /syncplay`.
public struct SyncInfo: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let canCreate: Bool
    public let drift: SyncDrift
    public let limits: SyncLimits
    public let rooms: [SyncListing]

    private enum CodingKeys: String, CodingKey { case enabled, canCreate, drift, limits, rooms }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? values.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        canCreate = (try? values.decodeIfPresent(Bool.self, forKey: .canCreate)) ?? false
        drift = (try? values.decodeIfPresent(SyncDrift.self, forKey: .drift)) ?? SyncDrift()
        limits = (try? values.decodeIfPresent(SyncLimits.self, forKey: .limits)) ?? SyncLimits()
        rooms = (try? values.decodeIfPresent([SyncListing].self, forKey: .rooms)) ?? []
    }
}

/// The room's one state.
public struct SyncState: Decodable, Equatable, Sendable {
    /// Goes up with every change of any kind.
    public var rev: Int
    /// Goes up with every command.
    public var seq: Int
    /// 0 for a member who may not see it.
    public var itemId: Int64
    public var index: Int
    public var positionSec: Double
    /// The server time at which the position is (or will be) that.
    public var atMs: Double
    public var paused: Bool
    /// The room wants to play, and is holding for members who are still loading.
    public var waiting: Bool
    public var rate: Double

    public init(rev: Int = 0, seq: Int = 0, itemId: Int64 = 0, index: Int = 0, positionSec: Double = 0, atMs: Double = 0,
                paused: Bool = false, waiting: Bool = false, rate: Double = 1) {
        self.rev = rev
        self.seq = seq
        self.itemId = itemId
        self.index = index
        self.positionSec = positionSec
        self.atMs = atMs
        self.paused = paused
        self.waiting = waiting
        self.rate = rate
    }

    private enum CodingKeys: String, CodingKey { case rev, seq, itemId, index, positionSec, atMs, paused, waiting, rate }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rev = (try? values.decodeIfPresent(Int.self, forKey: .rev)) ?? 0
        seq = (try? values.decodeIfPresent(Int.self, forKey: .seq)) ?? 0
        itemId = (try? values.decodeIfPresent(Int64.self, forKey: .itemId)) ?? 0
        index = (try? values.decodeIfPresent(Int.self, forKey: .index)) ?? 0
        positionSec = (try? values.decodeIfPresent(Double.self, forKey: .positionSec)) ?? 0
        atMs = (try? values.decodeIfPresent(Double.self, forKey: .atMs)) ?? 0
        paused = (try? values.decodeIfPresent(Bool.self, forKey: .paused)) ?? false
        waiting = (try? values.decodeIfPresent(Bool.self, forKey: .waiting)) ?? false
        let speed = (try? values.decodeIfPresent(Double.self, forKey: .rate)) ?? 1
        rate = speed.isFinite && speed > 0 ? speed : 1
    }

    /// Where the room is at a server time: the one sum every client does. Until `atMs` it holds at `positionSec`.
    public func position(atServerMs now: Double) -> Double {
        if paused || waiting || now <= atMs { return positionSec }
        return positionSec + (now - atMs) / 1000 * rate
    }

    /// Whether the picture should be moving at that server time.
    public func isPlaying(atServerMs now: Double) -> Bool { !paused && !waiting && now >= atMs }

    /// A start that is set for a moment from now: how long until it, in milliseconds. Nil otherwise.
    public func startsIn(atServerMs now: Double) -> Double? {
        !paused && !waiting && now < atMs ? atMs - now : nil
    }
}

public struct SyncMember: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let userId: Int64
    public let name: String
    public let host: Bool
    public let you: Bool
    /// `ready`, `loading`, `buffering`, `lagging`, `away` or `blocked`.
    public let state: String
    public let rttMs: Double

    public init(id: String, userId: Int64 = 0, name: String = "", host: Bool = false, you: Bool = false, state: String = "loading", rttMs: Double = 0) {
        self.id = id
        self.userId = userId
        self.name = name
        self.host = host
        self.you = you
        self.state = state
        self.rttMs = rttMs
    }

    private enum CodingKeys: String, CodingKey { case id, userId, name, host, you, state, rttMs }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        userId = (try? values.decodeIfPresent(Int64.self, forKey: .userId)) ?? 0
        name = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .name)) ?? "", limit: 60)
        host = (try? values.decodeIfPresent(Bool.self, forKey: .host)) ?? false
        you = (try? values.decodeIfPresent(Bool.self, forKey: .you)) ?? false
        state = (try? values.decodeIfPresent(String.self, forKey: .state)) ?? "loading"
        rttMs = (try? values.decodeIfPresent(Double.self, forKey: .rttMs)) ?? 0
    }
}

/// An entry of the room's queue with enough to show it. One the member may not see is an id of 0 and nothing else.
public struct SyncItem: Decodable, Equatable, Sendable {
    public let id: Int64
    public let title: String?
    public let kind: String?
    public let runtimeSec: Double?

    public init(id: Int64, title: String? = nil, kind: String? = nil, runtimeSec: Double? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.runtimeSec = runtimeSec
    }

    private enum CodingKeys: String, CodingKey { case id, title, kind, runtimeSec }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decodeIfPresent(Int64.self, forKey: .id)) ?? 0
        title = ((try? values.decodeIfPresent(String.self, forKey: .title)) ?? nil).map { PlainWords.clean($0, limit: 200) }
        kind = (try? values.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        runtimeSec = (try? values.decodeIfPresent(Double.self, forKey: .runtimeSec)) ?? nil
    }
}

/// The room, as one member sees it.
public struct SyncRoom: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public var code: String
    public var name: String
    /// `host`, or `everyone`.
    public var policy: String
    public var waitForAll: Bool
    public var hostId: String
    /// This member's seat: sent as `member` with everything else.
    public var you: String
    public var canControl: Bool
    /// This account may not see what's playing now. It keeps its place and controls nothing.
    public var blocked: Bool
    public var members: [SyncMember]
    public var queue: [Int64]
    public var items: [SyncItem]
    public var state: SyncState
    public var serverTimeMs: Double
    public var leadMs: Double

    public init(id: String, code: String = "", name: String = "", policy: String = "host", waitForAll: Bool = true, hostId: String = "",
                you: String = "", canControl: Bool = false, blocked: Bool = false, members: [SyncMember] = [], queue: [Int64] = [],
                items: [SyncItem] = [], state: SyncState = SyncState(), serverTimeMs: Double = 0, leadMs: Double = 300) {
        self.id = id
        self.code = code
        self.name = name
        self.policy = policy
        self.waitForAll = waitForAll
        self.hostId = hostId
        self.you = you
        self.canControl = canControl
        self.blocked = blocked
        self.members = members
        self.queue = queue
        self.items = items
        self.state = state
        self.serverTimeMs = serverTimeMs
        self.leadMs = leadMs
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name, policy, waitForAll, hostId, you, canControl, blocked, members, queue, items, state, serverTimeMs, leadMs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        code = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .code)) ?? "", limit: 12)
        name = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .name)) ?? "", limit: 80)
        policy = (try? values.decodeIfPresent(String.self, forKey: .policy)) ?? "host"
        waitForAll = (try? values.decodeIfPresent(Bool.self, forKey: .waitForAll)) ?? true
        hostId = (try? values.decodeIfPresent(String.self, forKey: .hostId)) ?? ""
        you = (try? values.decodeIfPresent(String.self, forKey: .you)) ?? ""
        canControl = (try? values.decodeIfPresent(Bool.self, forKey: .canControl)) ?? false
        blocked = (try? values.decodeIfPresent(Bool.self, forKey: .blocked)) ?? false
        members = (try? values.decodeIfPresent([SyncMember].self, forKey: .members)) ?? []
        queue = (try? values.decodeIfPresent([Int64].self, forKey: .queue)) ?? []
        items = (try? values.decodeIfPresent([SyncItem].self, forKey: .items)) ?? []
        state = (try? values.decodeIfPresent(SyncState.self, forKey: .state)) ?? SyncState()
        serverTimeMs = (try? values.decodeIfPresent(Double.self, forKey: .serverTimeMs)) ?? 0
        leadMs = (try? values.decodeIfPresent(Double.self, forKey: .leadMs)) ?? 300
    }

    public var isHost: Bool { !you.isEmpty && hostId == you }
    public var me: SyncMember? { members.first { $0.id == you } }
    /// What's playing, when this member may know.
    public var playing: SyncItem? { items.indices.contains(state.index) ? items[state.index] : nil }
    public var hasNext: Bool { state.index < queue.count - 1 }
    public var hasPrevious: Bool { state.index > 0 }

    /// The stream and the answers to commands both carry the room whole; the one with the highest `state.rev`
    /// wins, and an older one is forgotten. Another room's news takes this one's place.
    public func taking(_ incoming: SyncRoom) -> SyncRoom {
        if incoming.id == id, incoming.state.rev < state.rev { return self }
        return incoming
    }

    /// The line under the room's name: what's on, and whether it's held.
    public var line: String {
        if blocked { return "This one isn't available on this account" }
        var words = playing?.title.flatMap { $0.isEmpty ? nil : "Watching \($0)" } ?? ""
        let held = state.waiting ? "waiting for everyone to be ready" : state.paused ? "paused" : ""
        if !held.isEmpty { words += words.isEmpty ? held.prefix(1).uppercased() + String(held.dropFirst()) : " · " + held }
        return words
    }
}

public enum SyncPlay {
    /// The server's name for watch parties in `/capabilities`.
    public static let feature = "syncplay"
}

// MARK: - Words

public enum SyncWords {
    /// What it says beside each person, in the guide's own words.
    public static func member(_ state: String) -> String {
        switch state {
        case "ready": return "Ready"
        case "loading": return "Loading"
        case "buffering": return "Buffering"
        case "lagging": return "Catching up"
        case "away": return "Away"
        case "blocked": return "Can't watch this one"
        default: return state.prefix(1).uppercased() + String(state.dropFirst())
        }
    }

    /// Why the party is over for this device. Empty for `replaced`: another window took this seat, and this
    /// one steps back without a word.
    public static func closed(_ reason: String) -> String {
        switch reason {
        case "replaced": return ""
        case "removed": return "You were removed from the watch party."
        case "signed-out": return "The watch party ended for this device."
        case "server-stopping": return "The server is restarting, which ends the watch party."
        default: return "The watch party has ended."
        }
    }

    public static let hostOnly = "Only the host controls this watch party."
    public static let blocked = "This one isn't available on this account. You keep your place, and join in again when the party moves on."

    /// Words for a refusal: the server's own sentence, or what its code means when it sent none.
    public static func refusal(_ error: Error) -> String {
        guard let refusal = error as? APIError else { return "The server couldn't be reached." }
        if !refusal.message.isEmpty, !refusal.message.hasPrefix("The server answered with an error") { return refusal.message }
        switch refusal.code {
        case "disabled": return "Watch parties are turned off on this server."
        case "not-allowed": return "This account can't start a watch party. It can join one with a code."
        case "cant-watch": return "This watch party is playing something this account can't watch."
        case "host-only": return hostOnly
        case "not-host": return "Only the host can do that."
        case "no-room", "not-member": return "No such watch party."
        case "no-item": return "That can't be found."
        case "end-of-queue": return "There's nothing more that way."
        case "full": return "This watch party is full."
        case "rate": return "Too many tries. Wait a minute."
        case "too-many": return "Too many watch parties are running."
        default: return "That didn't work."
        }
    }
}

/// A party's code as people type it.
public enum SyncCode {
    /// Capitals, spaces and dashes don't matter: only letters and digits are kept, in capitals, up to the length.
    public static func clean(_ typed: String, length: Int = 6) -> String {
        String(typed.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length))
    }

    /// The keys of Apple TV's code pad, a row at a time: every letter and digit, since a code is typed as it's
    /// read out and the server forgives what its own codes never use.
    public static let padRows = ["ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ0", "123456789"]

    /// As it's shown and read out: in two halves, "KXM 4T7".
    public static func spaced(_ code: String) -> String {
        guard code.count > 3 else { return code }
        let half = code.count / 2
        return String(code.prefix(half)) + " " + String(code.dropFirst(half))
    }
}

/// A queue for a party started from an episode: that episode and the rest of its season after it.
public enum SyncQueue {
    public static func restOfSeason(from episode: Item, among episodes: [Item], limit: Int = 200) -> [Int64] {
        let season = episodes.filter { $0.season == episode.season && $0.isPlayable }
            .sorted { ($0.episode ?? 0, $0.id) < ($1.episode ?? 0, $1.id) }
        guard let at = season.firstIndex(where: { $0.id == episode.id }) else { return [episode.id] }
        return Array(season[at...].prefix(max(1, limit)).map(\.id))
    }
}

// MARK: - The server's clock

/// One ping's four times, in milliseconds. t0: this clock when it was sent; t1: the server's when that arrived;
/// t2: the server's when it answered; t3: this clock when the answer arrived.
public struct SyncSample: Equatable, Sendable {
    public let t0, t1, t2, t3: Double

    public init(t0: Double, t1: Double, t2: Double, t3: Double) {
        self.t0 = t0
        self.t1 = t1
        self.t2 = t2
        self.t3 = t3
    }
}

public enum SyncClock {
    /// NTP's sum for one ping. `offset` is how far the server's clock is ahead of this one, and `rtt` the time
    /// spent on the wire there and back.
    public static func offset(t0: Double, t1: Double, t2: Double, t3: Double) -> (offset: Double, rtt: Double) {
        (((t1 - t0) + (t2 - t3)) / 2, (t3 - t0) - (t2 - t1))
    }

    /// From several pings, the offset of the one with the shortest round trip: it was held up least on the way,
    /// so its two halves are most nearly equal, which is what the sum assumes. A ping that came back before it
    /// left (a clock that jumped) is ignored. Nil with nothing usable.
    public static func best(_ samples: [SyncSample]) -> (offset: Double, rtt: Double)? {
        var found: (offset: Double, rtt: Double)?
        for sample in samples {
            let one = offset(t0: sample.t0, t1: sample.t1, t2: sample.t2, t3: sample.t3)
            if one.rtt < 0 || one.rtt.isNaN || one.offset.isNaN { continue }
            if found == nil || one.rtt < (found?.rtt ?? .infinity) { found = one }
        }
        return found
    }
}

/// The server's clock as this device knows it: the last eight pings, and the best of them.
public struct SyncTime: Equatable, Sendable {
    public static let kept = 8
    public private(set) var samples: [SyncSample] = []
    /// How far the server's clock is ahead of this one, in milliseconds.
    public private(set) var offsetMs = 0.0
    /// The best round trip, for the room to set its starts by.
    public private(set) var rttMs = 0.0
    public private(set) var known = false

    public init() {}

    public mutating func add(_ sample: SyncSample) {
        samples = Array((samples + [sample]).suffix(Self.kept))
        if let best = SyncClock.best(samples) {
            offsetMs = best.offset
            rttMs = best.rtt
            known = true
        }
    }

    /// Until a ping has come back, the room's own `serverTimeMs` is the best there is.
    public mutating func guess(serverTimeMs: Double, localMs: Double) {
        if !known, serverTimeMs > 0 { offsetMs = serverTimeMs - localMs }
    }

    public func serverNow(localMs: Double) -> Double { localMs + offsetMs }

    /// How long to wait before ping number `count` (from 0): four or five quickly on joining, then the heartbeat.
    public static func wait(beforePing count: Int, everySec: Double) -> Double {
        if count == 0 { return 0 }
        return count < 5 ? 0.3 : max(1, everySec)
    }
}

// MARK: - Keeping in step

/// What to do about being out of step: play at `rate` (a multiple of the room's), or jump by `seekBy` seconds.
public struct SyncStep: Equatable, Sendable {
    public var rate: Double
    public var seekBy: Double

    public init(rate: Double, seekBy: Double = 0) {
        self.rate = rate
        self.seekBy = seekBy
    }
}

public enum SyncRules {
    /// The drift rule. `behind`: seconds this player is behind where the room is (negative: ahead). `nudging`:
    /// whether it is already playing faster or slower, which carries on until it's settled rather than stopping
    /// the moment it is merely close.
    public static func correct(behind: Double, nudging: Bool, drift: SyncDrift = SyncDrift()) -> SyncStep {
        let off = abs(behind)
        if off >= drift.seekSec { return SyncStep(rate: 1, seekBy: behind) }
        if off < (nudging ? drift.settledSec : drift.stillSec) { return SyncStep(rate: 1) }
        return SyncStep(rate: behind > 0 ? 1 + drift.rate : 1 - drift.rate)
    }
}

/// What the follower needs to know about the player on each tick.
public struct SyncPlayerFacts: Equatable, Sendable {
    /// The film's time where the player is, in seconds.
    public var positionSec: Double
    /// The player is paused (not playing and not trying to).
    public var paused: Bool
    /// It has a stream open at all.
    public var loaded: Bool
    /// It has enough to play from where it is.
    public var canPlay: Bool
    /// A seek hasn't landed yet.
    public var seeking: Bool
    public var ended: Bool
    /// A seek is quick (a file, or a stream listed whole), so a paused picture can be put on the exact frame.
    /// False for a stream that starts again from wherever it's sent.
    public var cheapSeek: Bool

    public init(positionSec: Double, paused: Bool, loaded: Bool = true, canPlay: Bool = true, seeking: Bool = false, ended: Bool = false, cheapSeek: Bool = true) {
        self.positionSec = positionSec
        self.paused = paused
        self.loaded = loaded
        self.canPlay = canPlay
        self.seeking = seeking
        self.ended = ended
        self.cheapSeek = cheapSeek
    }
}

/// What the player is to do after a tick. Everything left nil or false stays as it is.
public struct SyncOrders: Equatable, Sendable {
    public var pause = false
    public var play = false
    /// The speed to play at: the room's, times the nudge.
    public var rate: Double?
    /// Jump to this place in the film.
    public var seekTo: Double?
    /// Look again after this many milliseconds: a start that is set for a moment from now is kept to the
    /// millisecond, not to the next tick.
    public var againInMs: Double?
    /// `ready` or `buffering`, to tell the room, with `rev`.
    public var report: String?
    public var rev = 0
    /// How far behind the room this player is, in seconds (negative: ahead), for the log. Nil while held.
    public var behind: Double?

    public init() {}
}

/// Keeps one player in step with a room: the web player's tick (web/src/remote/party.ts), with nothing of the
/// player or the clock in it. Feed it the room and the player's facts about twice a second, and whenever the
/// room changes, and do what it answers.
public struct SyncFollower: Equatable, Sendable {
    public var drift: SyncDrift
    public private(set) var nudging = false
    /// When the last jump was asked for, in this device's milliseconds; nil once it has landed.
    private var seekAt: Double?
    /// How long the last jump took, in seconds: a jump while playing aims ahead by that much.
    public private(set) var lagSec = 0.0
    /// A paused picture is sent to a place once: if it can't get there (past the end), asking again won't help.
    private var lastStill: Double?
    private var saidAt = -Double.infinity
    private var stalledSince: Double?

    public init(drift: SyncDrift = SyncDrift()) { self.drift = drift }

    /// A new item was opened: nothing about the last one's seeks or stalls carries over.
    public mutating func reset() {
        nudging = false
        seekAt = nil
        lastStill = nil
        stalledSince = nil
    }

    public mutating func tick(state: SyncState, me: SyncMember?, serverNowMs: Double, localMs: Double, player: SyncPlayerFacts) -> SyncOrders {
        var orders = SyncOrders()
        orders.rev = state.rev
        guard player.loaded else { return orders }
        let target = state.position(atServerMs: serverNowMs)
        let playing = state.isPlaying(atServerMs: serverNowMs)

        func jump(_ orders: inout SyncOrders, playing: Bool) {
            // Another isn't tried until the last has had its chance: a converted stream starts again from the
            // new place, which takes seconds.
            if player.seeking { return }
            if let asked = seekAt, localMs - asked < 5000 { return }
            if !playing {
                if lastStill == target { return }
                lastStill = target
            } else {
                lastStill = nil
            }
            seekAt = localMs
            orders.seekTo = max(0, target + (playing ? lagSec : 0))
        }

        if !playing {
            if !player.paused { orders.pause = true }
            if abs(target - player.positionSec) > (player.cheapSeek ? 0.08 : 0.5) { jump(&orders, playing: false) }
            if let wait = state.startsIn(atServerMs: serverNowMs) { orders.againInMs = max(0, wait) }
            if nudging {
                nudging = false
                orders.rate = state.rate
            }
        } else if !player.ended {
            if player.paused { orders.play = true }
            let behind = target - player.positionSec
            orders.behind = behind
            let step = SyncRules.correct(behind: behind, nudging: nudging, drift: drift)
            if step.seekBy != 0 {
                jump(&orders, playing: true)
                nudging = false
                orders.rate = state.rate
            } else {
                nudging = step.rate != 1
                orders.rate = state.rate * step.rate
            }
        }

        // Telling the room how this player is doing, when the room has it wrong.
        let ready = player.canPlay && !player.seeking && abs(target - player.positionSec) < 2
        if ready {
            stalledSince = nil
            if let asked = seekAt {
                lagSec = min(10, max(0, (localMs - asked) / 1000))
                seekAt = nil
            }
        } else if playing, stalledSince == nil {
            stalledSince = localMs
        }
        guard let me, localMs - saidAt >= 1000 else { return orders }
        if ready, me.state != "ready" {
            saidAt = localMs
            orders.report = "ready"
        } else if !ready, playing, me.state == "ready", let since = stalledSince, localMs - since > 800 {
            saidAt = localMs
            orders.report = "buffering"
        }
        return orders
    }
}

/// What a member does when the room's stream ends: SYNCPLAY.md, "Seats, and coming back".
public enum SyncLife {
    public enum Next: Equatable, Sendable {
        /// The party is over for this device, with words to show (none when another window took the seat).
        case over(String)
        /// The connection dropped: the seat is kept for two minutes, so take it again after this many seconds.
        case rejoin(afterSec: Double)
    }

    /// `reason` is the `closed` event's, nil when the stream dropped with no word. `refusal` is a refusal to
    /// open the stream or to join again.
    public static func after(closed reason: String?, refusal: APIError? = nil, backoff: inout Backoff) -> Next {
        if let reason { return .over(SyncWords.closed(reason)) }
        if let refusal, (400..<500).contains(refusal.status), refusal.status != 429 { return .over(SyncWords.closed("closed")) }
        return .rejoin(afterSec: min(15, backoff.next()))
    }
}

// MARK: - The routes

public struct SyncStart: Encodable, Equatable, Sendable {
    public var itemId: Int64?
    public var items: [Int64]?
    public var index: Int?
    public var positionSec: Double?
    public var name: String?
    public var policy: String
    public var waitForAll: Bool
    public var device: String

    /// One title, or a queue of them starting at `index`.
    public init(items: [Int64], index: Int = 0, positionSec: Double = 0, name: String = "", everyone: Bool = false, waitForAll: Bool = true, device: String) {
        if items.count > 1 {
            self.items = items
            self.index = index
        } else {
            itemId = items.first
        }
        self.positionSec = positionSec > 0 ? positionSec : nil
        let named = PlainWords.clean(name, limit: 60)
        self.name = named.isEmpty ? nil : named
        policy = everyone ? "everyone" : "host"
        self.waitForAll = waitForAll
        self.device = device
    }
}

extension WittyClient {
    private func roomPath(_ room: String) -> String { "/syncplay/rooms/\(Self.pathPart(room))" }

    /// Whether watch parties are on, whether this account may start one, the numbers, and this account's rooms.
    public func syncInfo(device: String) async throws -> SyncInfo { try await get("/syncplay?device=\(Self.queryValue(device))") }

    public func syncCreate(_ start: SyncStart) async throws -> SyncRoom { try await ask("POST", "/syncplay/rooms", start) }

    public func syncJoin(code: String, device: String) async throws -> SyncRoom {
        try await ask("POST", "/syncplay/join", ["code": SyncCode.clean(code, length: 12), "device": device])
    }

    /// A room this account is invited to, or already has a seat in.
    public func syncJoin(room: String, device: String) async throws -> SyncRoom {
        try await ask("POST", "/syncplay/join", ["roomId": room, "device": device])
    }

    public func syncEventsPath(_ room: SyncRoom) -> String { "\(roomPath(room.id))/events?member=\(Self.queryValue(room.you))" }

    /// A command to the room. The answer is the room after it, which everyone's player then follows, this
    /// one's included. Refused with `stale` because someone else got there first, their change is the room now.
    public func syncCommand(_ room: SyncRoom, _ type: String, positionSec: Double? = nil, index: Int? = nil, rate: Double? = nil,
                            items: [Int64]? = nil, ifSeq: Int? = nil) async throws -> SyncRoom {
        struct Body: Encodable {
            let member: String
            let type: String
            let positionSec: Double?
            let index: Int?
            let rate: Double?
            let items: [Int64]?
            let ifSeq: Int?
        }
        struct Stale: Decodable { let room: SyncRoom }
        do {
            return try await ask("POST", "\(roomPath(room.id))/command",
                                 Body(member: room.you, type: type, positionSec: positionSec, index: index, rate: rate, items: items, ifSeq: ifSeq))
        } catch let refusal as APIError where refusal.code == "stale" {
            if let now = refusal.decoded(Stale.self)?.room { return now }
            throw refusal
        }
    }

    public func syncReport(_ room: SyncRoom, state: String, rev: Int) async throws {
        struct Body: Encodable {
            let member: String
            let state: String
            let rev: Int
        }
        try await tell("POST", "\(roomPath(room.id))/report", Body(member: room.you, state: state, rev: rev))
    }

    /// The clock and the heartbeat. `t0` is this device's clock when it was sent; the answer's `t1` and `t2`
    /// are the server's when it arrived and when the answer left.
    public func syncPing(_ room: SyncRoom, t0: Double, rttMs: Double) async throws -> (t1: Double, t2: Double) {
        struct Body: Encodable {
            let member: String
            let t0: Double
            let rttMs: Double
        }
        struct Answer: Decodable {
            let t1: Double
            let t2: Double
        }
        let answer: Answer = try await ask("POST", "\(roomPath(room.id))/ping", Body(member: room.you, t0: t0, rttMs: rttMs))
        return (answer.t1, answer.t2)
    }

    public func syncLeave(_ room: SyncRoom) async throws {
        try await tell("POST", "\(roomPath(room.id))/leave", ["member": room.you])
    }

    /// The host's switches. Whatever is left nil stays as it is.
    public func syncSet(_ room: SyncRoom, name: String? = nil, everyone: Bool? = nil, waitForAll: Bool? = nil) async throws {
        struct Body: Encodable {
            let member: String
            let name: String?
            let policy: String?
            let waitForAll: Bool?
        }
        try await tell("PUT", roomPath(room.id), Body(member: room.you, name: name, policy: everyone.map { $0 ? "everyone" : "host" }, waitForAll: waitForAll))
    }

    public func syncMakeHost(_ room: SyncRoom, member: String) async throws {
        try await tell("POST", "\(roomPath(room.id))/host", ["member": room.you, "to": member])
    }

    public func syncRemove(_ room: SyncRoom, member: String) async throws {
        try await tell("POST", "\(roomPath(room.id))/kick", ["member": room.you, "whom": member])
    }

    /// Those accounts then find the room in their own list and may join it without the code.
    public func syncInvite(_ room: SyncRoom, users: [Int64]) async throws {
        struct Body: Encodable {
            let member: String
            let userIds: [Int64]
        }
        try await tell("POST", "\(roomPath(room.id))/invite", Body(member: room.you, userIds: users))
    }

    /// Ends the party for everyone: the host's, or an administrator's.
    public func syncEnd(_ room: SyncRoom) async throws {
        _ = try await call("DELETE", "\(roomPath(room.id))?member=\(Self.queryValue(room.you))")
    }
}
