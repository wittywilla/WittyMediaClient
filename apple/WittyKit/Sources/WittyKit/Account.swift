import Foundation

// What a signed-in person can see and change about their own account, as the web's Settings → You
// does: two-step sign-in, where they're signed in, and signing a TV in. The calls are on WittyClient.

/// GET /me/2fa. `available` is false for Kids and Guest profiles, which can't have it.
public struct TwoFactorState: Decodable, Equatable {
    public let on: Bool
    public let recoveryLeft: Int?
    public let available: Bool?

    public init(on: Bool, recoveryLeft: Int? = nil, available: Bool? = nil) {
        self.on = on
        self.recoveryLeft = recoveryLeft
        self.available = available
    }
}

/// The secret an authenticator app needs, and the `otpauth:` address that carries it.
public struct TwoFactorSetup: Decodable, Equatable {
    public let secret: String
    public let uri: String

    /// The key as it's easiest to type: in groups of four.
    public var groupedSecret: String {
        var groups: [String] = []
        var rest = Substring(secret)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(4)))
            rest = rest.dropFirst(4)
        }
        return groups.joined(separator: " ")
    }
}

struct RecoveryCodes: Decodable {
    let recovery: [String]?
}

/// One place an account is signed in, from GET /sessions.
public struct SignedInDevice: Decodable, Identifiable, Equatable {
    public let id: String
    public let device: String?
    public let createdAt: Int64?
    public let lastSeen: Int64?
    public let ip: String?
    /// `machine`, `home`, `vpn` or `internet`.
    public let place: String?
    public let current: Bool?

    enum CodingKeys: String, CodingKey {
        case id, device, createdAt, lastSeen, ip, current
        case place = "where"
    }

    public init(id: String, device: String?, createdAt: Int64? = nil, lastSeen: Int64? = nil, ip: String? = nil,
                place: String? = nil, current: Bool? = nil) {
        self.id = id
        self.device = device
        self.createdAt = createdAt
        self.lastSeen = lastSeen
        self.ip = ip
        self.place = place
        self.current = current
    }

    /// The server's name for it, cleaned: it was written by whatever signed in.
    public var name: String {
        let cleaned = PlainWords.clean(device ?? "", limit: 80)
        return cleaned.isEmpty ? "Unknown device" : cleaned
    }

    public var kind: DeviceKind { DeviceKind.of(name) }
    public var isThisDevice: Bool { current == true }
}

/// What sort of thing signed in, from the name it gave, for its icon.
public enum DeviceKind: String, Equatable {
    case phone, tablet, tv, computer, browser

    public static func of(_ name: String) -> DeviceKind {
        let words = name.lowercased()
        func has(_ any: String...) -> Bool { any.contains { words.contains($0) } }
        // A TV first: "Android TV" is not a phone, and "Apple TV" is not a computer.
        if has("apple tv", "android tv", "google tv", "fire tv", "shield", "bigscreen", "chromecast")
            || words.split(whereSeparator: { !$0.isLetter }).contains("tv") {
            return .tv
        }
        if has("ipad", "tablet", "galaxy tab", "pixel tablet") { return .tablet }
        if has("iphone", "android", "pixel", "phone", "galaxy", "oneplus") { return .phone }
        // The server names a browser's sign-in "Chrome on macOS" and the like.
        if has("chrome", "firefox", "safari", "edge", "opera", "browser") { return .browser }
        if has("mac", "windows", "linux", "freebsd", "desktop", "plasma", "vision") { return .computer }
        return .browser
    }
}

/// POST /pair/info: the device waiting with a code, and who it can be signed in as.
public struct PairInfo: Decodable, Equatable {
    public let code: String?
    public let device: String?
    public let platform: String?
    public let ip: String?
    public let expiresAt: Int64?
    public let profiles: [PairChoice]?

    public var deviceName: String {
        let cleaned = PlainWords.clean(device ?? "", limit: 80)
        return cleaned.isEmpty ? "A device" : cleaned
    }
}

/// A profile a device may be signed in as: the person's own, or a Kids or Guest one they look after.
/// The server sends usernames only here.
public struct PairChoice: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let kind: String?
}

/// POST /pair/invite: a code for a device to type.
public struct PairInvite: Decodable, Equatable {
    public let code: String
    public let expiresInSec: Int?
}

struct ProfileChange: Encodable {
    let displayName: String?
    let username: String?
    let showUsername: Bool?
}
