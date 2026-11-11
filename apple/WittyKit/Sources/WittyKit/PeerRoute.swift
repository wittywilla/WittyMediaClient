// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// The way to a server from away: an address on this device that the connecting library answers
/// at, and the secret every request to it must carry. Whatever is sent there comes out at the
/// server. The secret is new each time the library starts, and without it the address answers
/// nobody, so another app on the device that finds the port gets nothing from it.
public struct PeerRoute: Equatable, Sendable {
    /// `http://127.0.0.1:<port>`.
    public let origin: String
    public let secret: String

    public init(port: Int, secret: String) {
        origin = "http://127.0.0.1:\(port)"
        self.secret = secret
    }

    public var port: Int { URL(string: origin)?.port ?? 0 }

    /// An address the library could have answered at: this device, plain http, a port of its own.
    public static func isLocalAddress(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" && url.host == "127.0.0.1" && (url.port ?? 0) >= 1024 && url.user == nil
    }
}

/// The way in use, shared by every `WittyClient` made for one server. Home is no route at all.
/// It can change while screens are up (leaving home, coming back, the app waking), and a
/// connection that asks here each time follows it without being made again.
public final class RouteBox: @unchecked Sendable {
    public enum Trouble: Sendable { case lost, offline }

    private let lock = NSLock()
    private var route: PeerRoute?
    private var hear: (@Sendable (Trouble) -> Void)?

    public init() {}

    public var current: PeerRoute? {
        lock.lock()
        defer { lock.unlock() }
        return route
    }

    public func set(_ new: PeerRoute?) {
        lock.lock()
        route = new
        lock.unlock()
    }

    /// Whoever chooses the way asks to hear when a request couldn't get through.
    public func onTrouble(_ hear: (@Sendable (Trouble) -> Void)?) {
        lock.lock()
        self.hear = hear
        lock.unlock()
    }

    public func trouble(_ kind: Trouble) {
        lock.lock()
        let hear = self.hear
        lock.unlock()
        hear?(kind)
    }
}

/// What the app keeps about reaching one server from away. None of it is secret: the device's
/// key is, and that is kept apart, in the Keychain.
public struct PeerInfo: Codable, Equatable, Sendable {
    /// The server's connection ID, which is what gets dialled and proved.
    public var serverID: String
    /// Addresses it had last time. They save a search; wrong ones cost a failed try.
    public var hints: [String]
    /// The port the local address had last time, asked for again so addresses already handed
    /// out (a video that is playing) still lead somewhere after the app wakes.
    public var port: Int

    public init(serverID: String, hints: [String] = [], port: Int = 0) {
        self.serverID = serverID
        self.hints = PeerConnect.hints(hints)
        self.port = (1024...65535).contains(port) ? port : 0
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(serverID: try values.decode(String.self, forKey: .serverID),
                  hints: try values.decodeIfPresent([String].self, forKey: .hints) ?? [],
                  port: try values.decodeIfPresent(Int.self, forKey: .port) ?? 0)
    }

    public var usable: Bool { PeerConnect.isID(serverID) }

    /// What `GET /api/v1/p2p` says, as something to keep. Addresses on this very device are no
    /// use from anywhere else.
    public static func learnt(_ answer: PeerAnswer, keeping old: PeerInfo?) -> PeerInfo? {
        guard answer.enabled == true, let id = answer.serverId, PeerConnect.isID(id) else { return nil }
        let hints = (answer.addrs ?? []).filter { !$0.hasPrefix("/ip4/127.") && !$0.hasPrefix("/ip6/::1/") }
        return PeerInfo(serverID: id, hints: hints, port: old?.serverID == id ? old?.port ?? 0 : 0)
    }

    /// The address a server only ever reached from away is remembered by. Names under
    /// `.localhost` never leave the device, and nothing listens there, so asking it at home
    /// simply finds nobody: the way from away is all there is until the server is found on
    /// the network by its name.
    public static func placeholderAddress(serverID: String) -> String {
        "http://p2p-\(serverID.suffix(16).lowercased()).localhost"
    }

    public static func isPlaceholder(_ address: String) -> Bool {
        address.hasPrefix("http://p2p-") && address.hasSuffix(".localhost")
    }
}

/// `GET /api/v1/p2p?device=<id>`: whether the server takes connections from away, and where it is.
public struct PeerAnswer: Decodable, Sendable {
    public let enabled: Bool?
    public let serverId: String?
    public let addrs: [String]?
    public let enrolled: Bool?
    public let serverName: String?
}

/// One of this account's devices on the server's list for connections from away.
public struct PeerDevice: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let platform: String?
}

public extension WittyClient {
    /// The server's feature name for connections from away: docs/P2P.md in its repository.
    static let peerFeature = "p2p"

    func peerInfo(device: String) async throws -> PeerAnswer {
        try JSONDecoder().decode(PeerAnswer.self, from: try await call("GET", "/p2p?device=\(Self.queryValue(device))"))
    }

    /// Puts this device's key on the server's list. Being on it signs nobody in.
    func enrolPeer(device: String, name: String, platform: String) async throws {
        _ = try await call("POST", "/p2p/devices", body: try JSONEncoder().encode(["id": device, "name": name, "platform": platform]))
    }

    /// Takes a device off the list, which closes its connections.
    func forgetPeer(device: String) async throws {
        _ = try await call("DELETE", "/p2p/devices/\(Self.queryValue(device))")
    }
}
