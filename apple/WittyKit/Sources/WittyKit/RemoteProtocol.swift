// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// One WittyMedia client playing on, and steering, another: the server's docs/REMOTE-PROTOCOL.md, which is the
// whole wire format. Every app is both a device (it announces itself, holds a channel, obeys commands and says
// what it is playing) and a controller (it lists devices and sends them commands). Everything goes through the
// server. What is here is the messages and the rules that need no screen and no player: what this device
// announces, what a command means, when a state is worth sending, where a playing device has got to.

// MARK: - Messages

/// What a device can do: the kinds of item it plays, and the features its commands need.
public struct RemoteCapabilities: Codable, Equatable, Sendable {
    public var mediaKinds: [String]
    public var features: [String]

    public init(mediaKinds: [String] = [], features: [String] = []) {
        self.mediaKinds = mediaKinds
        self.features = features
    }

    private enum CodingKeys: String, CodingKey { case mediaKinds, features }

    /// A list that's missing is an empty one: a device that says nothing can do nothing.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mediaKinds = (try? values.decodeIfPresent([String].self, forKey: .mediaKinds)) ?? []
        features = (try? values.decodeIfPresent([String].self, forKey: .features)) ?? []
    }

    public func has(_ feature: String) -> Bool { features.contains(feature) }
    public func plays(_ kind: String) -> Bool { mediaKinds.contains(kind) }
}

/// The server's numbers, so that none is copied here: `GET /remote-control`, `limits`.
public struct RemoteLimits: Decodable, Equatable, Sendable {
    public var stateEveryMs = 500
    public var commandEveryMs = 200
    public var heartbeatSec = 30
    public var idleSec = 75
    public var reconnectSec = 30
    public var ackTimeoutMs = 8000
    public var queueItems = 200

    public init() {}

    private enum CodingKeys: String, CodingKey { case stateEveryMs, commandEveryMs, heartbeatSec, idleSec, reconnectSec, ackTimeoutMs, queueItems }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, _ usual: Int) -> Int {
            let found = (try? values.decodeIfPresent(Int.self, forKey: key)) ?? nil
            return (found ?? 0) > 0 ? (found ?? usual) : usual
        }
        stateEveryMs = number(.stateEveryMs, 500)
        commandEveryMs = number(.commandEveryMs, 200)
        heartbeatSec = number(.heartbeatSec, 30)
        idleSec = number(.idleSec, 75)
        reconnectSec = number(.reconnectSec, 30)
        ackTimeoutMs = number(.ackTimeoutMs, 8000)
        queueItems = number(.queueItems, 200)
    }
}

/// `GET /remote-control`: whether the owner has it on, the versions spoken and what the server knows.
public struct RemoteInfo: Decodable, Equatable, Sendable {
    public let enabled: Bool
    public let v: Int
    public let minV: Int
    public let controlOthers: Bool
    public let features: [String]
    public let mediaKinds: [String]
    public let navigateKeys: [String]
    public let limits: RemoteLimits

    private enum CodingKeys: String, CodingKey { case enabled, v, minV, controlOthers, features, mediaKinds, navigateKeys, limits }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? values.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        v = (try? values.decodeIfPresent(Int.self, forKey: .v)) ?? 1
        minV = (try? values.decodeIfPresent(Int.self, forKey: .minV)) ?? 1
        controlOthers = (try? values.decodeIfPresent(Bool.self, forKey: .controlOthers)) ?? false
        features = (try? values.decodeIfPresent([String].self, forKey: .features)) ?? []
        mediaKinds = (try? values.decodeIfPresent([String].self, forKey: .mediaKinds)) ?? []
        navigateKeys = (try? values.decodeIfPresent([String].self, forKey: .navigateKeys)) ?? []
        limits = (try? values.decodeIfPresent(RemoteLimits.self, forKey: .limits)) ?? RemoteLimits()
    }
}

/// A sound track or a subtitle a device offers. Its id is the playback answer's `index`, as text.
public struct RemoteTrack: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var label: String?
    public var lang: String?

    public init(id: String, label: String? = nil, lang: String? = nil) {
        self.id = id
        self.label = label
        self.lang = lang
    }

    /// What to call it on a remote: its label, its language, or its number.
    public var shownName: String {
        if let label, !label.isEmpty { return PlainWords.clean(label, limit: 80) }
        if let lang, !lang.isEmpty { return Locale.current.localizedString(forLanguageCode: lang) ?? lang }
        return "Track \(id)"
    }
}

/// What a device reports, and what controllers are shown.
public struct RemoteState: Codable, Equatable, Sendable {
    public var v: Int? = RemoteProtocol.version
    /// `idle` (nothing open), `playing`, `paused` or `buffering`.
    public var status: String
    public var itemId: Int64?
    public var positionSec: Double?
    public var durationSec: Double?
    public var rate: Double?
    /// 0 to 1. Left out by a device with no volume of its own.
    public var volume: Double?
    public var muted: Bool?
    public var audio: String?
    public var subtitle: String?
    public var audioTracks: [RemoteTrack]?
    public var subtitleTracks: [RemoteTrack]?
    public var queue: [Int64]?
    public var queueIndex: Int?
    /// Where the device is in its own interface, in a word.
    public var screen: String?

    public init(status: String = "idle", itemId: Int64? = nil, positionSec: Double? = nil, durationSec: Double? = nil, rate: Double? = nil,
                volume: Double? = nil, muted: Bool? = nil, audio: String? = nil, subtitle: String? = nil,
                audioTracks: [RemoteTrack]? = nil, subtitleTracks: [RemoteTrack]? = nil, queue: [Int64]? = nil, queueIndex: Int? = nil,
                screen: String? = nil) {
        self.status = status
        self.itemId = itemId
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.rate = rate
        self.volume = volume
        self.muted = muted
        self.audio = audio
        self.subtitle = subtitle
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.queue = queue
        self.queueIndex = queueIndex
        self.screen = screen
    }

    private enum CodingKeys: String, CodingKey {
        case v, status, itemId, positionSec, durationSec, rate, volume, muted, audio, subtitle, audioTracks, subtitleTracks, queue, queueIndex, screen
    }

    /// Ignore what you don't know, and never fail on a field of the wrong shape: a state that can't be read
    /// whole is still a status.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? values.decodeIfPresent(Int.self, forKey: .v)) ?? nil
        status = (try? values.decodeIfPresent(String.self, forKey: .status)) ?? "idle"
        itemId = (try? values.decodeIfPresent(Int64.self, forKey: .itemId)) ?? nil
        positionSec = (try? values.decodeIfPresent(Double.self, forKey: .positionSec)) ?? nil
        durationSec = (try? values.decodeIfPresent(Double.self, forKey: .durationSec)) ?? nil
        rate = (try? values.decodeIfPresent(Double.self, forKey: .rate)) ?? nil
        volume = (try? values.decodeIfPresent(Double.self, forKey: .volume)) ?? nil
        muted = (try? values.decodeIfPresent(Bool.self, forKey: .muted)) ?? nil
        audio = (try? values.decodeIfPresent(String.self, forKey: .audio)) ?? nil
        subtitle = (try? values.decodeIfPresent(String.self, forKey: .subtitle)) ?? nil
        audioTracks = (try? values.decodeIfPresent([RemoteTrack].self, forKey: .audioTracks)) ?? nil
        subtitleTracks = (try? values.decodeIfPresent([RemoteTrack].self, forKey: .subtitleTracks)) ?? nil
        queue = (try? values.decodeIfPresent([Int64].self, forKey: .queue)) ?? nil
        queueIndex = (try? values.decodeIfPresent(Int.self, forKey: .queueIndex)) ?? nil
        screen = (try? values.decodeIfPresent(String.self, forKey: .screen)) ?? nil
    }

    public var isIdle: Bool { status == "idle" }
    public var isPlaying: Bool { status == "playing" }
}

/// One command, as a controller sends it and as a device receives it (with `id`, `sender` and `sentAt` added
/// by the server on the way).
public struct RemoteCommand: Codable, Equatable, Sendable {
    public struct Sender: Codable, Equatable, Sendable {
        public let userName: String?
    }

    public var v: Int? = RemoteProtocol.version
    public var id: String?
    public var type: String
    public var itemId: Int64?
    public var queue: [Int64]?
    public var queueIndex: Int?
    public var positionSec: Double?
    public var bySec: Double?
    public var audio: String?
    public var subtitle: String?
    public var level: Double?
    public var muted: Bool?
    public var rate: Double?
    public var key: String?
    public var from: String?
    public var sender: Sender?

    public init(_ type: String, itemId: Int64? = nil, queue: [Int64]? = nil, queueIndex: Int? = nil, positionSec: Double? = nil,
                bySec: Double? = nil, audio: String? = nil, subtitle: String? = nil, level: Double? = nil, muted: Bool? = nil,
                rate: Double? = nil, key: String? = nil, from: String? = nil) {
        self.type = type
        self.itemId = itemId
        self.queue = queue
        self.queueIndex = queueIndex
        self.positionSec = positionSec
        self.bySec = bySec
        self.audio = audio
        self.subtitle = subtitle
        self.level = level
        self.muted = muted
        self.rate = rate
        self.key = key
        self.from = from
    }

    private enum CodingKeys: String, CodingKey {
        case v, id, type, itemId, queue, queueIndex, positionSec, bySec, audio, subtitle, level, muted, rate, key, from, sender
    }

    /// A command is never ignored, so it is never unreadable either: whatever came with a field of the wrong
    /// shape is read as far as it goes, and the device answers that it can't.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? values.decodeIfPresent(Int.self, forKey: .v)) ?? nil
        id = (try? values.decodeIfPresent(String.self, forKey: .id)) ?? nil
        type = (try? values.decodeIfPresent(String.self, forKey: .type)) ?? ""
        itemId = (try? values.decodeIfPresent(Int64.self, forKey: .itemId)) ?? nil
        queue = (try? values.decodeIfPresent([Int64].self, forKey: .queue)) ?? nil
        queueIndex = (try? values.decodeIfPresent(Int.self, forKey: .queueIndex)) ?? nil
        positionSec = (try? values.decodeIfPresent(Double.self, forKey: .positionSec)) ?? nil
        bySec = (try? values.decodeIfPresent(Double.self, forKey: .bySec)) ?? nil
        audio = (try? values.decodeIfPresent(String.self, forKey: .audio)) ?? nil
        subtitle = (try? values.decodeIfPresent(String.self, forKey: .subtitle)) ?? nil
        level = (try? values.decodeIfPresent(Double.self, forKey: .level)) ?? nil
        muted = (try? values.decodeIfPresent(Bool.self, forKey: .muted)) ?? nil
        rate = (try? values.decodeIfPresent(Double.self, forKey: .rate)) ?? nil
        key = (try? values.decodeIfPresent(String.self, forKey: .key)) ?? nil
        from = (try? values.decodeIfPresent(String.self, forKey: .from)) ?? nil
        sender = (try? values.decodeIfPresent(Sender.self, forKey: .sender)) ?? nil
    }
}

/// A device as a controller is shown it.
public struct RemoteDevice: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let userId: Int64
    public let userName: String
    public let capabilities: RemoteCapabilities
    /// Its channel is open. Commands only reach a device that is online.
    public let online: Bool
    /// Signed in as the account asking.
    public let mine: Bool
    /// Announced by the very sign-in asking: this app itself.
    public let thisSession: Bool
    public let state: RemoteState
    /// When it last reported, in the server's milliseconds.
    public let stateAt: Double
    public let title: String
    public let itemKind: String
    /// It is playing something this account may not see: the state then holds no item, place or tracks.
    public let hidden: Bool

    public init(id: String, name: String, kind: String = "other", userId: Int64 = 0, userName: String = "",
                capabilities: RemoteCapabilities = RemoteCapabilities(), online: Bool = true, mine: Bool = true, thisSession: Bool = false,
                state: RemoteState = RemoteState(), stateAt: Double = 0, title: String = "", itemKind: String = "", hidden: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.userId = userId
        self.userName = userName
        self.capabilities = capabilities
        self.online = online
        self.mine = mine
        self.thisSession = thisSession
        self.state = state
        self.stateAt = stateAt
        self.title = title
        self.itemKind = itemKind
        self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, userId, userName, capabilities, online, mine, thisSession, state, stateAt, title, itemKind, hidden
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .name)) ?? "", limit: 60)
        kind = (try? values.decodeIfPresent(String.self, forKey: .kind)) ?? "other"
        userId = (try? values.decodeIfPresent(Int64.self, forKey: .userId)) ?? 0
        userName = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .userName)) ?? "", limit: 60)
        capabilities = (try? values.decodeIfPresent(RemoteCapabilities.self, forKey: .capabilities)) ?? RemoteCapabilities()
        online = (try? values.decodeIfPresent(Bool.self, forKey: .online)) ?? false
        mine = (try? values.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
        thisSession = (try? values.decodeIfPresent(Bool.self, forKey: .thisSession)) ?? false
        state = (try? values.decodeIfPresent(RemoteState.self, forKey: .state)) ?? RemoteState()
        stateAt = (try? values.decodeIfPresent(Double.self, forKey: .stateAt)) ?? 0
        title = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .title)) ?? "", limit: 200)
        itemKind = (try? values.decodeIfPresent(String.self, forKey: .itemKind)) ?? ""
        hidden = (try? values.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
    }
}

/// `GET /remote-control/devices`, and the `snapshot` event.
public struct RemoteDeviceList: Decodable, Equatable, Sendable {
    public let serverTimeMs: Double
    public let devices: [RemoteDevice]

    private enum CodingKeys: String, CodingKey { case serverTimeMs, devices }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        serverTimeMs = (try? values.decodeIfPresent(Double.self, forKey: .serverTimeMs)) ?? 0
        devices = (try? values.decodeIfPresent([RemoteDevice].self, forKey: .devices)) ?? []
    }
}

/// What was agreed when a device announced itself.
public struct RemoteAnnounced: Decodable, Equatable, Sendable {
    public let v: Int?
    public let deviceId: String
    public let name: String?
    public let capabilities: RemoteCapabilities?
    public let heartbeatSec: Int?
    public let openWithinSec: Int?
    public let serverTimeMs: Double?
}

/// The answer to a command: the device said it has done it. `sourceStopped` only for a `cast`.
public struct RemoteCommandAnswer: Decodable, Equatable, Sendable {
    public let ok: Bool?
    public let sourceStopped: Bool?
}

public enum RemoteProtocol {
    /// The version of the protocol this app speaks.
    public static let version = 1
    /// The server's name for all of this in `/capabilities`.
    public static let feature = "remote-protocol"
}

// MARK: - Being a device

/// Which Apple device this is, for what it announces.
public enum RemotePlatform: String, Equatable, Sendable {
    case tv, phone, tablet
}

public enum RemoteAbility {
    /// What this app really does on each device, and nothing it doesn't.
    ///
    /// - Every one plays films, episodes and other video, and music, audiobooks and podcasts, in its own players.
    ///   Discs with menus, books, games and photos open the server's own pages, which no command can drive.
    /// - `volume` is the player's own volume. Apple TV has none an app may set (the TV or the receiver has it),
    ///   so it's left out there and the state carries no `volume`.
    /// - `navigate` is the TV remote's keys. A phone or tablet is touched, not steered, so it isn't announced there.
    public static func capabilities(_ platform: RemotePlatform) -> RemoteCapabilities {
        switch platform {
        case .tv:
            return RemoteCapabilities(mediaKinds: ["video", "audio"], features: ["seek", "queue", "audio", "subtitles", "rate", "navigate"])
        case .phone, .tablet:
            return RemoteCapabilities(mediaKinds: ["video", "audio"], features: ["seek", "volume", "queue", "audio", "subtitles", "rate"])
        }
    }

    /// The keys Apple TV answers. Any other is refused in words.
    public static let navigateKeys = ["up", "down", "left", "right", "select", "back", "home", "menu", "playpause"]

    /// The announcement itself.
    public static func announcement(name: String, platform: RemotePlatform, deviceId: String) -> RemoteAnnouncement {
        RemoteAnnouncement(v: RemoteProtocol.version, name: PlainWords.clean(name, limit: 60), kind: platform.rawValue,
                           capabilities: capabilities(platform), deviceId: deviceId.isEmpty ? nil : deviceId)
    }
}

public struct RemoteAnnouncement: Encodable, Equatable, Sendable {
    public let v: Int
    public let name: String
    public let kind: String
    public let capabilities: RemoteCapabilities
    public let deviceId: String?
}

/// What a command asks of this device, once it has been read and found to make sense.
public enum RemoteAction: Equatable, Sendable {
    /// Open `queue[index]` and play it; `positionSec` nil means from the account's own resume point.
    case play(queue: [Int64], index: Int, positionSec: Double?, audio: Int?, subtitle: Int?)
    case pause, resume, stop
    case seekTo(Double)
    case seekBy(Double)
    case next, previous
    case volume(Double)
    case mute(Bool)
    case audio(Int)
    /// -1 is no subtitles, as the playback routes have it.
    case subtitle(Int)
    case rate(Double)
    case navigate(String)
    /// It can't be done, and why, for the person holding the controller.
    case refuse(String)

    public static let cantDoThat = "This device can't do that."
    public static let nothingPlaying = "Nothing is playing."

    /// A track id is the playback answer's `index` as text; "off" is -1.
    public static func trackIndex(_ id: String?) -> Int? {
        guard let id else { return nil }
        if id == "off" { return -1 }
        return Int(id)
    }

    /// Reads a command against what this device announced. The server already checks all this; a device still
    /// answers anything it's sent, and never does what it never said it could.
    public static func read(_ command: RemoteCommand, abilities: RemoteCapabilities) -> RemoteAction {
        func needs(_ feature: String, _ action: RemoteAction) -> RemoteAction {
            abilities.has(feature) ? action : .refuse(cantDoThat)
        }
        switch command.type {
        case "play":
            var queue = command.queue ?? []
            var index = command.queueIndex ?? 0
            if queue.isEmpty, let id = command.itemId { queue = [id]; index = 0 }
            guard !queue.isEmpty, queue.indices.contains(index), queue[index] > 0 else { return .refuse("That command doesn't say what to play.") }
            if let id = command.itemId, id != queue[index] { return .refuse("That command doesn't say what to play.") }
            if queue.count > 1, !abilities.has("queue") { return .refuse(cantDoThat) }
            let at = command.positionSec.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let subtitle = trackIndex(command.subtitle)
            return .play(queue: queue, index: index, positionSec: at, audio: trackIndex(command.audio).flatMap { $0 >= 0 ? $0 : nil }, subtitle: subtitle)
        case "pause": return .pause
        case "resume": return .resume
        case "stop": return .stop
        case "seek":
            if let to = command.positionSec, to.isFinite { return needs("seek", .seekTo(max(0, to))) }
            if let by = command.bySec, by.isFinite { return needs("seek", .seekBy(by)) }
            return .refuse("That command doesn't say where to go.")
        case "next": return needs("queue", .next)
        case "previous": return needs("queue", .previous)
        case "volume":
            guard let level = command.level, level.isFinite else { return .refuse("That command doesn't say how loud.") }
            return needs("volume", .volume(min(1, max(0, level))))
        case "mute":
            guard let muted = command.muted else { return .refuse("That command doesn't say whether to mute.") }
            return needs("volume", .mute(muted))
        case "audio":
            guard let index = trackIndex(command.audio), index >= 0 else { return .refuse("That command doesn't say which sound track.") }
            return needs("audio", .audio(index))
        case "subtitle":
            guard let index = trackIndex(command.subtitle) else { return .refuse("That command doesn't say which subtitles.") }
            return needs("subtitles", .subtitle(index))
        case "rate":
            guard let rate = command.rate, rate.isFinite, rate >= 0.25, rate <= 4 else { return .refuse("That speed can't be used.") }
            return needs("rate", .rate(rate))
        case "navigate":
            guard let key = command.key, RemoteAbility.navigateKeys.contains(key) else { return .refuse("This device doesn't have that key.") }
            return needs("navigate", .navigate(key))
        default:
            return .refuse(cantDoThat)
        }
    }
}

/// Moving along a queue, for `next` and `previous`.
public enum RemoteQueue {
    /// The entry after or before `index`, or nil at either end.
    public static func step(_ queue: [Int64], from index: Int, by step: Int) -> Int? {
        let next = index + step
        return queue.indices.contains(next) ? next : nil
    }

    /// Where an item is in a queue, nil when the queue isn't about it.
    public static func place(of item: Int64, in queue: [Int64]) -> Int? { queue.firstIndex(of: item) }
}

/// When a state is worth sending: at once when something changed that a controller would show, every few
/// seconds while playing so controllers stay close, and at least as often as the heartbeat. Never closer
/// together than the server allows, and after a `429` the latest goes a moment later. It keeps no clock of
/// its own: every time is handed in, in milliseconds.
public struct RemoteReporter: Equatable, Sendable {
    /// No two reports closer than this. The server allows 500 ms after a burst; one a second leaves room.
    public var gapMs: Double
    public var playingEveryMs: Double
    public var heartbeatMs: Double
    private var last: RemoteState?
    private var lastAt: Double?
    private var holdUntil = 0.0

    public init(limits: RemoteLimits = RemoteLimits()) {
        gapMs = max(1000, Double(limits.stateEveryMs) * 2)
        playingEveryMs = 5000
        // Well inside the heartbeat, so that one lost report doesn't reach `idleSec`.
        heartbeatMs = max(5000, Double(limits.heartbeatSec) * 1000 - 5000)
    }

    /// Whether `state` should be sent now.
    public func due(_ state: RemoteState, nowMs: Double) -> Bool {
        guard nowMs >= holdUntil else { return false }
        guard let last, let lastAt else { return true }
        let since = nowMs - lastAt
        if since < gapMs { return false }
        if Self.differs(last, state, afterMs: since) { return true }
        return since >= (state.isPlaying ? playingEveryMs : heartbeatMs)
    }

    public mutating func sent(_ state: RemoteState, nowMs: Double) {
        last = state
        lastAt = nowMs
    }

    /// The server said slow down. Nothing is lost: the latest state goes once the wait is over.
    public mutating func refused(nowMs: Double, retryAfterSec: Int) {
        holdUntil = nowMs + Double(max(1, retryAfterSec)) * 1000
    }

    /// Forgets what was sent, so the next state goes whatever it is: a channel that has just opened.
    public mutating func reset() {
        last = nil
        lastAt = nil
        holdUntil = 0
    }

    /// Whether a controller would show something else. Time passing while it plays is not a change; a seek is.
    public static func differs(_ old: RemoteState, _ new: RemoteState, afterMs: Double) -> Bool {
        var a = old, b = new
        a.positionSec = nil
        b.positionSec = nil
        if a != b { return true }
        let was = old.positionSec ?? 0, now = new.positionSec ?? 0
        let expected = old.isPlaying ? was + afterMs / 1000 * (old.rate ?? 1) : was
        return abs(now - expected) > 1.5
    }
}

/// What a device does when its channel ends: REMOTE-PROTOCOL.md, "Being a device" and "Life of a device".
public enum DeviceLife {
    public enum Next: Equatable, Sendable {
        /// Nothing more: it was told to stop, or a newer channel of its own is the one.
        case stop
        /// Announce and open the channel again after this many seconds.
        case again(afterSec: Double)
    }

    /// After a `bye`. `nil` is a channel that dropped with no word.
    public static func after(bye reason: String?, backoff: inout Backoff) -> Next {
        switch reason {
        case "replaced", "removed", "signed-out": return .stop
        // The server thought it had gone: it hasn't, so it says so again at once.
        case "idle":
            backoff.reset()
            return .again(afterSec: 0)
        // A restart takes a few seconds.
        case "server-stopping": return .again(afterSec: 3)
        default: return .again(afterSec: backoff.next())
        }
    }

    /// After a refusal to announce or to open the channel.
    public static func after(refusal error: APIError, backoff: inout Backoff) -> Next {
        // Turned off, or not a sign-in, or signed out: nothing to keep trying for.
        if error.status == 401 || error.status == 403 { return .stop }
        // This app is too old for the server: trying again changes nothing.
        if error.code == "version" { return .stop }
        if error.retryAfter > 0 { return .again(afterSec: Double(min(error.retryAfter, 60))) }
        return .again(afterSec: backoff.next())
    }

    /// Whether to hold the channel. In front it is always held. Behind other apps iOS stops this one unless it
    /// is playing sound (or a picture floating over them), so only then: a channel left open by a stopped app
    /// would show a device that can't answer.
    public static func holdsChannel(inFront: Bool, playingBehind: Bool) -> Bool { inFront || playingBehind }
}

// MARK: - Being a controller

/// The server's clock, near enough for a progress bar: the difference between `serverTimeMs` and this
/// device's clock when the answer arrived.
public struct RemoteClock: Equatable, Sendable {
    public private(set) var aheadMs = 0.0

    public init() {}

    public mutating func learn(serverTimeMs: Double, localMs: Double) {
        if serverTimeMs > 0 { aheadMs = serverTimeMs - localMs }
    }

    public func serverNow(localMs: Double) -> Double { localMs + aheadMs }
}

public enum RemoteLook {
    /// Where a device is now: `positionSec + (serverNow - stateAt) / 1000 × rate` while it plays, kept inside
    /// the item.
    public static func position(_ state: RemoteState, stateAt: Double, serverNowMs: Double) -> Double {
        var at = state.positionSec ?? 0
        if state.isPlaying, stateAt > 0 { at += max(0, serverNowMs - stateAt) / 1000 * (state.rate ?? 1) }
        if let length = state.durationSec, length > 0 { at = min(at, length) }
        return at.isFinite ? max(0, at) : 0
    }

    /// The devices a list shows: not this app itself, connected ones first, then by name.
    public static func listed(_ devices: [RemoteDevice]) -> [RemoteDevice] {
        devices.filter { !$0.thisSession }.sorted {
            if $0.online != $1.online { return $0.online }
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// A `device` event is the device whole: it takes the place of the one with its id, or joins the list.
    public static func merged(_ device: RemoteDevice, into devices: [RemoteDevice]) -> [RemoteDevice] {
        devices.filter { $0.id != device.id } + [device]
    }

    /// The line under a device's name.
    public static func line(_ device: RemoteDevice, serverNowMs: Double) -> String {
        if !device.online { return "Not connected" }
        if device.state.isIdle { return "Nothing playing" }
        if device.hidden { return "Playing something" }
        var words = device.title.isEmpty ? "Playing" : device.title
        words += " · " + PlayerTime.format(position(device.state, stateAt: device.stateAt, serverNowMs: serverNowMs))
        if let length = device.state.durationSec, length > 0 { words += " of " + PlayerTime.format(length) }
        switch device.state.status {
        case "paused": words += " · paused"
        case "buffering": words += " · buffering"
        default: break
        }
        return words
    }

    /// A symbol for the kind of device.
    public static func symbol(_ kind: String) -> String {
        switch kind {
        case "tv": return "tv"
        case "phone": return "iphone"
        case "tablet": return "ipad"
        case "desktop": return "desktopcomputer"
        case "web": return "globe"
        default: return "display"
        }
    }

    /// Whether something of this kind can be started there.
    public static func canPlay(kind: String, on device: RemoteDevice) -> Bool {
        device.online && device.capabilities.plays(kind.isEmpty ? "video" : kind)
    }

    /// The speeds a remote offers: the protocol takes 0.25 to 4.
    public static let rates: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    /// Words for a command that failed. The server's own sentence when it sent one (for `refused` that is
    /// the device's reason); otherwise what its code means.
    public static func words(_ error: Error) -> String {
        guard let refusal = error as? APIError else { return "The server couldn't be reached." }
        if !refusal.code.isEmpty, !refusal.message.isEmpty, !refusal.message.hasPrefix("The server answered with an error") {
            return refusal.message
        }
        switch refusal.code {
        case "bad-command": return "That device was sent something it can't read."
        case "version": return "This app needs updating to work with this server."
        case "disabled": return "Playing on other devices is turned off on this server."
        case "no-session": return "Sign in again to use this."
        case "not-allowed-there": return "The account that device is signed in as may not play that."
        case "no-device": return "That device has gone."
        case "no-item": return "That can't be found."
        case "offline": return "That device isn't connected."
        case "unsupported": return "That device can't do that."
        case "refused": return "That device said no."
        case "nothing-playing": return "Nothing is playing there."
        case "rate": return "Too fast. Try again in a moment."
        case "too-many": return "Too many devices are connected."
        case "busy": return "That device is busy. Try again in a moment."
        case "timeout": return "That device didn't answer."
        default:
            if refusal.status == 413 { return "That was too long to send." }
            return refusal.message.isEmpty ? "That didn't work." : refusal.message
        }
    }
}

extension RemoteTrack {
    /// The tracks of a playback answer, as a device lists them: the answer's `index` as text.
    public static func list(_ tracks: [Track]?) -> [RemoteTrack] {
        (tracks ?? []).prefix(64).map { RemoteTrack(id: String($0.index), label: $0.label, lang: $0.language) }
    }

    /// The id of the subtitles in use: "off" for none.
    public static func subtitleId(_ index: Int?) -> String? {
        guard let index else { return nil }
        return index < 0 ? "off" : String(index)
    }
}

// MARK: - The routes

extension WittyClient {
    /// Whether the owner has this on, and the server's limits.
    public func remoteInfo() async throws -> RemoteInfo { try await get("/remote-control") }

    /// Whether this profile may use it at all: `features.remote` of `/me/limits`. A server that doesn't say
    /// (or has no such route) means yes.
    public func remoteAllowed() async -> Bool {
        struct Limits: Decodable {
            struct Features: Decodable { let remote: Bool? }
            let features: Features?
        }
        guard let limits: Limits = try? await get("/me/limits") else { return true }
        return limits.features?.remote ?? true
    }

    public func remoteAnnounce(_ announcement: RemoteAnnouncement) async throws -> RemoteAnnounced {
        try await ask("POST", "/remote-control/devices", announcement)
    }

    public func remoteChannelPath(_ deviceId: String) -> String { "/remote-control/devices/\(Self.pathPart(deviceId))/channel" }

    public func remoteReport(_ deviceId: String, _ state: RemoteState) async throws {
        try await tell("POST", "/remote-control/devices/\(Self.pathPart(deviceId))/state", state)
    }

    public func remoteAck(_ deviceId: String, command: String, ok: Bool, error: String = "") async throws {
        struct Ack: Encodable {
            let id: String
            let ok: Bool
            let error: String?
        }
        let words = String(PlainWords.clean(error).prefix(200))
        try await tell("POST", "/remote-control/devices/\(Self.pathPart(deviceId))/ack", Ack(id: command, ok: ok, error: ok || words.isEmpty ? nil : words))
    }

    public func remoteForget(_ deviceId: String) async throws {
        _ = try await call("DELETE", "/remote-control/devices/\(Self.pathPart(deviceId))")
    }

    public func remoteDevices() async throws -> RemoteDeviceList { try await get("/remote-control/devices") }

    public static let remoteEventsPath = "/remote-control/events"

    /// Sends a command and waits for the device's answer: the server allows it eight seconds.
    @discardableResult
    public func remoteSend(_ command: RemoteCommand, to deviceId: String) async throws -> RemoteCommandAnswer {
        let data = try await call("POST", "/remote-control/devices/\(Self.pathPart(deviceId))/commands",
                                  body: try JSONEncoder().encode(command), wait: 12)
        return (try? JSONDecoder().decode(RemoteCommandAnswer.self, from: data)) ?? RemoteCommandAnswer(ok: true, sourceStopped: nil)
    }
}
