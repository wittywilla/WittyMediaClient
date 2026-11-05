import Foundation

// WittyPlay, the server's games, as data. The server runs every game and streams it: a device
// shows the picture, plays the sound and sends controller states (the server's docs/GAMING-API.md).
// So nothing here emulates anything, and no game file ever comes to the device.

/// One game, with what a game's card and page need. Decoded from the same answers as `Item`, which
/// leaves out what only games have.
public struct GameItem: Decodable, Identifiable, Equatable, Hashable {
    public let id: Int64
    public let libraryId: Int64?
    public let title: String
    public let year: Int?
    public let overview: String?
    public let tagline: String?
    public let genres: [String]?
    /// Out of 10.
    public let rating: Double?
    public let contentRating: String?
    public let studio: String?
    public let console: String?
    public let updatedAt: Int64?
    public let progress: Progress?
    public let sizeBytes: Int64?
    public let container: String?
    /// Where the server keeps its pictures. Only whether there is one matters here.
    let poster: String?
    let backdrop: String?

    public var hasPoster: Bool { !(poster ?? "").isEmpty }
    public var hasBackdrop: Bool { !(backdrop ?? "").isEmpty }
    /// A game on someone's own PC, which plays through Moonlight: see Rigs.swift.
    public var isRigGame: Bool { console == "rig" }
    /// Seconds played, which the server keeps as the game's place.
    public var playedSeconds: Double { progress?.positionSec ?? 0 }

    public static func == (a: GameItem, b: GameItem) -> Bool { a.id == b.id && a.updatedAt == b.updatedAt }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct GameItemPage: Decodable {
    public let items: [GameItem]?
    public let total: Int?
}

public struct GameButton: Decodable, Equatable, Hashable {
    public let id: Int
    public let label: String
}

/// What a console's controller has: its names for its buttons, and whether it has sticks or a touch screen.
public struct GamePadShape: Decodable, Equatable {
    public let face: [GameButton]?
    public let shoulder: [GameButton]?
    public let meta: [GameButton]?
    public let sticks: Bool?
    public let pointer: Bool?
    /// The Nintendo 64: games steer with the stick, so arrows push it.
    public let stickFirst: Bool?
    public let art: String?

    public var buttons: [GameButton] { (face ?? []) + (shoulder ?? []) + (meta ?? []) }
}

public struct GameCore: Decodable, Equatable, Hashable {
    public let id: String
    public let name: String?
    public let license: String?
}

public struct GameBIOS: Decodable, Equatable, Hashable {
    public let file: String
    public let `for`: String?
    public let required: Bool?
    public let found: Bool?
}

public struct GameConsole: Decodable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let short: String?
    public let ready: Bool?
    /// Why it can't be played here at all, in the server's words.
    public let unavailable: String?
    public let cores: [GameCore]?
    public let installed: [GameCore]?
    public let pad: GamePadShape?
    /// That library's games for it, when asked with `?library=`.
    public let count: Int?
    public let needsGpu: Bool?
    public let bios: [GameBIOS]?

    public var shortName: String { (short ?? "").isEmpty ? name : short! }
}

public struct GameSaveRef: Decodable, Equatable {
    public let slot: Int
    public let updatedAt: Int64
    public let hasThumb: Bool?
}

public struct GameContinue: Decodable, Equatable, Identifiable {
    public let item: GameItem
    public let plays: Int?
    public let lastPlayed: Int64?
    public let save: GameSaveRef?
    public var id: Int64 { item.id }
}

public struct GameShelf: Decodable, Equatable, Identifiable {
    public let kind: String
    public let name: String
    public let count: Int?
    public let items: [GameItem]?
    public var id: String { kind + "|" + name }
}

/// The games home screen in one answer.
public struct GamesHome: Decodable, Equatable {
    public let hero: [GameItem]?
    public let `continue`: [GameContinue]?
    public let recent: [GameItem]?
    public let favourites: [GameItem]?
    public let favouriteIds: [Int64]?
    public let mostPlayed: [GameItem]?
    public let shelves: [GameShelf]?
}

/// What a game needs in order to play, and whether this server has it.
public struct GameCheck: Decodable, Equatable {
    public let ready: Bool
    /// `core`, `bios` or `unavailable`.
    public let reason: String?
    public let message: String?
    public let core: GameCore?
    public let needsGpu: Bool?
    public let bios: [GameBIOS]?
    public let biosFolder: String?
}

/// A saved state. Slot 0 is the automatic one, written when a game stops.
public struct GameSave: Decodable, Equatable, Identifiable {
    public let slot: Int
    public let updatedAt: Int64
    public let size: Int64?
    public let hasThumb: Bool?
    public let core: String?
    public var id: Int { slot }
}

/// What a person keeps about a game.
public struct GamePersonal: Decodable, Equatable {
    public let favourite: Bool
    public let note: String?
    public let plays: Int?
    public let lastPlayed: Int64?
    public let hasBattery: Bool?
}

public struct GameCredit: Decodable, Equatable, Hashable {
    public let name: String?
    public let text: String?
    public let site: String?
    public let url: String?
    public let license: String?
}

/// The rest of a game's details, from `GET /games/{id}/metadata`.
public struct GameDetails: Decodable, Equatable {
    public let status: String?
    public let players: Int?
    public let publisher: String?
    public let released: String?
    public let franchise: String?
    public let credits: [GameCredit]?
}

/// How a game is being played: one of the server's ways of sending it.
public struct GameMode: Decodable, Equatable {
    public let id: String
    public let video: [String]?

    public init(id: String, video: [String]? = nil) {
        self.id = id
        self.video = video
    }

    /// Either an object or, from older servers, just its name.
    public init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self.init(id: name)
            return
        }
        struct Full: Decodable { let id: String; let video: [String]? }
        let full = try Full(from: decoder)
        self.init(id: full.id, video: full.video)
    }
}

public struct GameDeviceType: Decodable, Equatable, Hashable {
    public let id: Int
    public let name: String
}

public struct GamePortDevices: Decodable, Equatable {
    public let port: Int
    public let current: Int?
    public let types: [GameDeviceType]?
}

/// A game being played, from `POST /games/{id}/play`.
public struct GameSession: Decodable, Equatable {
    public let id: String
    public let itemId: Int64?
    public let title: String?
    public let console: String?
    public let core: String?
    public let width: Int?
    public let height: Int?
    /// Width over height, which the picture is shown at whatever shape the video is.
    public let aspect: Double?
    public let fps: Double?
    public let sampleRate: Double?
    public let resumed: Bool?
    public let encoder: String?
    /// Quarter turns to draw the picture by.
    public let turns: Int?
    public let disc: Int?
    public let discs: Int?
    public let modes: [GameMode]?
    public let devices: [GamePortDevices]?
    public let safeMode: Bool?
    public let maxSpeed: Double?
    public let notices: [String]?
}

/// How far a game in an archive has got with being unpacked.
public struct GamePrepare: Decodable, Equatable {
    public let state: String
    public let done: Int64?
    public let total: Int64?

    public var ready: Bool { state == "ready" }
    /// From 0 to 1, or nil while it can't be told.
    public var fraction: Double? {
        guard let done, let total, total > 0 else { return nil }
        return min(1, Double(done) / Double(total))
    }
}

/// Something done to a running game: `POST /play/{sid}/action`.
public struct GameAction: Encodable, Equatable {
    public let type: String
    public var slot: Int?
    public var on: Bool?
    public var value: Double?
    public var port: Int?
    public var device: Int?

    public static func save(_ slot: Int) -> GameAction { GameAction(type: "save", slot: slot) }
    public static func load(_ slot: Int) -> GameAction { GameAction(type: "load", slot: slot) }
    public static let reset = GameAction(type: "reset")
    public static func pause(_ on: Bool) -> GameAction { GameAction(type: "pause", on: on) }
    public static func disc(_ slot: Int) -> GameAction { GameAction(type: "disc", slot: slot) }
    public static func speed(_ value: Double) -> GameAction { GameAction(type: "speed", value: value) }
    public static func rewind(_ on: Bool) -> GameAction { GameAction(type: "rewind", on: on) }
    public static func advance(_ frames: Int) -> GameAction { GameAction(type: "advance", value: Double(frames)) }
    public static let undo = GameAction(type: "undo")
    public static func device(port: Int, device: Int) -> GameAction { GameAction(type: "device", port: port, device: device) }
}

// MARK: - Settings

/// A setting's value, which may be any of JSON's kinds.
public enum SettingValue: Decodable, Equatable {
    case number(Double)
    case text(String)
    case flag(Bool)
    case none

    public init(from decoder: Decoder) throws {
        let one = try decoder.singleValueContainer()
        if one.decodeNil() { self = .none }
        else if let b = try? one.decode(Bool.self) { self = .flag(b) }
        else if let n = try? one.decode(Double.self) { self = .number(n) }
        else if let s = try? one.decode(String.self) { self = .text(s) }
        else { self = .none }
    }

    public var number: Double? {
        switch self {
        case .number(let n): return n
        case .text(let s): return Double(s)
        case .flag(let b): return b ? 1 : 0
        case .none: return nil
        }
    }

    public var text: String? {
        switch self {
        case .text(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .flag(let b): return b ? "true" : "false"
        case .none: return nil
        }
    }

    public var flag: Bool? {
        switch self {
        case .flag(let b): return b
        case .number(let n): return n != 0
        case .text(let s): return s == "true" ? true : (s == "false" ? false : nil)
        case .none: return nil
        }
    }
}

/// A person's settings for a game, as the server worked them out from every level.
public struct GameSettings: Decodable, Equatable {
    public struct Resolved: Decodable, Equatable {
        public let values: [String: SettingValue]?
    }
    public struct Limits: Decodable, Equatable {
        public let maxSpeed: Double?
        public let rewindBytes: Int64?
    }
    public let resolved: Resolved?
    public let limits: Limits?

    public init(values: [String: SettingValue]) {
        resolved = Resolved(values: values)
        limits = nil
    }

    public func number(_ key: String, _ fallback: Double) -> Double { resolved?.values?[key]?.number ?? fallback }
    public func text(_ key: String, _ fallback: String) -> String { resolved?.values?[key]?.text ?? fallback }
    public func flag(_ key: String, _ fallback: Bool) -> Bool { resolved?.values?[key]?.flag ?? fallback }
}

/// The picture behind the controller screen.
public struct GameBackground: Decodable, Equatable {
    public let version: Int64?
    public let fit: String?
    public let x: Double?
    public let y: Double?
    public let dim: Double?
}

// MARK: - Controllers

/// One input of a W3C standard gamepad: `{"b": n}` a button, `{"a": n, "d": ±1}` one direction of an
/// axis (with `r` for a trigger that rests at one end), `{"h": n, "d": 1...4}` a D-pad as one axis.
public struct PadSource: Codable, Equatable, Hashable {
    public var b: Int?
    public var a: Int?
    public var d: Int?
    public var h: Int?
    public var r: Int?

    public init(b: Int? = nil, a: Int? = nil, d: Int? = nil, h: Int? = nil, r: Int? = nil) {
        self.b = b
        self.a = a
        self.d = d
        self.h = h
        self.r = r
    }

    public static func button(_ n: Int) -> PadSource { PadSource(b: n) }
    public static func axis(_ n: Int, _ direction: Int) -> PadSource { PadSource(a: n, d: direction) }
}

/// How sticks and turbo behave. Applying these is the app's job: the server only keeps them.
public struct PadOptions: Codable, Equatable {
    public var deadzone: Double?
    public var threshold: Double?
    public var stickDpad: Bool?
    public var turbo: [Int]?
    public var turboHz: Double?
    public var noRumble: Bool?

    public init(deadzone: Double? = nil, threshold: Double? = nil, stickDpad: Bool? = nil, turbo: [Int]? = nil, turboHz: Double? = nil, noRumble: Bool? = nil) {
        self.deadzone = deadzone
        self.threshold = threshold
        self.stickDpad = stickDpad
        self.turbo = turbo
        self.turboHz = turboHz
        self.noRumble = noRumble
    }

    /// What's set here, over what's set in `under`.
    public func over(_ under: PadOptions?) -> PadOptions {
        PadOptions(deadzone: deadzone ?? under?.deadzone, threshold: threshold ?? under?.threshold, stickDpad: stickDpad ?? under?.stickDpad,
                   turbo: turbo ?? under?.turbo, turboHz: turboHz ?? under?.turboHz, noRumble: noRumble ?? under?.noRumble)
    }
}

/// A RetroPad target and the input that presses it. A nil source means nothing presses it.
public typealias PadMap = [String: PadSource?]

/// The controller as data, from `GET /consoles/{console}/controls`.
public struct GameControls: Decodable, Equatable {
    public struct Defaults: Decodable, Equatable {
        public let gamepad: PadMap?
        /// RetroPad target to a `KeyboardEvent.key` name, for a TV remote.
        public let remote: [String: String]?
        /// RetroPad target to a `KeyboardEvent.code` name.
        public let keyboard: [String: String]?
        public let options: PadOptions?
    }
    public struct Saved: Decodable, Equatable {
        /// Layouts by the pad's model name.
        public let gamepad: [String: PadMap]?
    }
    public struct Target: Decodable, Equatable, Hashable {
        public let id: Int
        public let label: String
        public let group: String?
    }
    public let console: String?
    public let pad: GamePadShape?
    public let defaults: Defaults?
    public let saved: Saved?
    public let targets: [Target]?
}

/// What a controller should do here, from `GET /game-profiles/resolve`.
public struct ResolvedPad: Decodable, Equatable {
    public struct Profile: Decodable, Equatable {
        public let id: Int64
        public let name: String?
    }
    public let map: PadMap?
    public let options: PadOptions?
    public let profile: Profile?
}

// MARK: - Words

public enum GameWords {
    /// The server's names for its save slots.
    public static func slotName(_ slot: Int) -> String {
        switch slot {
        case 0: return "Automatic save"
        case 100: return "Before the last load"
        case 101: return "Before starting over"
        default: return "Slot \(slot)"
        }
    }

    /// Only these can be saved to: 0, 100 and 101 are the server's own, for loading.
    public static func canSave(to slot: Int) -> Bool { (1...99).contains(slot) }

    /// "2 h 5 min", or "12 min", as the website says it.
    public static func played(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = Int((Double(total % 3600) / 60).rounded())
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(max(1, minutes)) min"
    }

    /// "just now", "5 minutes ago", "yesterday", or the date.
    public static func ago(_ unix: Int64, now: Date = Date()) -> String {
        let s = now.timeIntervalSince1970 - Double(unix)
        if s < 90 { return "just now" }
        if s < 3600 { return "\(Int((s / 60).rounded())) minutes ago" }
        if s < 86400 {
            let h = Int((s / 3600).rounded())
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        if s < 86400 * 2 { return "yesterday" }
        if s < 86400 * 30 { return "\(Int((s / 86400).rounded())) days ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: Double(unix)))
    }

    /// "1 player" or "Up to 4 players".
    public static func players(_ n: Int) -> String { n == 1 ? "1 player" : "Up to \(n) players" }

    /// A release date as the server writes it, "1994", "1994-03" or "1994-03-11", for people.
    public static func released(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first else { return date }
        guard parts.count >= 2, (1...12).contains(parts[1]) else { return String(year) }
        var c = DateComponents()
        c.year = year
        c.month = parts[1]
        c.day = parts.count >= 3 ? parts[2] : 1
        c.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let when = calendar.date(from: c) else { return String(year) }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate(parts.count >= 3 ? "yMMMMd" : "yMMMM")
        return formatter.string(from: when)
    }
}

/// What Play does when a game has an automatic save, by the person's `states.resume` setting.
public enum ResumeChoice: Equatable {
    /// Resume is the main button, and Start over beside it.
    case offer
    /// Play resumes, as the person asked.
    case always
    /// Play starts from the beginning; the save is still there to load.
    case never

    public init(setting: String) {
        switch setting {
        case "always": self = .always
        case "never": self = .never
        default: self = .offer
        }
    }

    /// Whether the main button resumes, given whether there's anything to resume.
    public func resumes(hasAutoSave: Bool) -> Bool { hasAutoSave && self != .never }
}

/// How to start a game.
public enum GameStart: Hashable {
    case fresh
    case resume
    /// Start, then load this slot, as the website's `?slot=`.
    case slot(Int)
    /// Defaults only, no cheats and no patches.
    case safe(resume: Bool)

    public var resumes: Bool {
        switch self {
        case .resume: return true
        case .safe(let resume): return resume
        case .fresh, .slot: return false
        }
    }

    public var safeMode: Bool { if case .safe = self { return true } else { return false } }

    public var slotToLoad: Int? { if case .slot(let n) = self { return n } else { return nil } }
}
