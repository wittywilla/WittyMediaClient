// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Reaching a server from away, peer to peer: no port opened on anyone's router. The
/// connecting is done by a Go library, Wittyconnect, built from the server's own source
/// (WittyMediaServer, `scripts/build-wittyconnect-mobile.sh apple`, under the AGPL). It gives
/// back an address on this device, and loading the server from there is loading it from home.
/// `docs/P2P.md` in the server's repository is the design.
///
/// What is here without the library: reading an invite, the configuration the library takes,
/// and the state it reports. `PeerConnector`, further down, is only compiled where the
/// framework has been added to the app.
public enum PeerConnect {
    /// What every request to the local address must carry: this header, or a cookie of this name.
    public static let secretHeader = "X-Witty-Connect"
    public static let secretCookie = "wittyconnect"

    /// A server's or a device's connection ID: an Ed25519 key, in the text form libp2p gives it.
    public static func isID(_ text: String) -> Bool {
        guard text.count == 52, text.hasPrefix("12D3KooW") else { return false }
        let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return text.allSatisfy { base58.contains($0) }
    }

    /// An invite link: `wittymedia://p2p/<server ID>?s=<secret>&n=<name>&a=<address>…`.
    /// Nothing in it is believed further than this: the ID is what gets dialled and proved.
    public struct Invite: Equatable, Sendable {
        public let serverID: String
        public let secret: String
        public let name: String
        public let hints: [String]
    }

    public static func invite(from text: String) -> Invite? {
        guard text.count <= 4096, let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == DeepLink.scheme, parts.host == "p2p" else { return nil }
        let id = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let items = parts.queryItems ?? []
        let secret = items.first { $0.name == "s" }?.value ?? ""
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard isID(id), (16...64).contains(secret.count), secret.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let name = String((items.first { $0.name == "n" }?.value ?? "").prefix(80))
        return Invite(serverID: id, secret: secret, name: name, hints: hints(items.filter { $0.name == "a" }.compactMap(\.value)))
    }

    /// Addresses worth handing to the library: multiaddrs, and nothing that could hide in one.
    public static func hints(_ list: [String]) -> [String] {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/.:%-")
        return Array(list.filter { a in
            a.count <= 400 && a.unicodeScalars.allSatisfy(allowed.contains)
                && ["/ip4/", "/ip6/", "/dns/", "/dns4/", "/dns6/"].contains { a.hasPrefix($0) }
        }.prefix(12))
    }

    /// The configuration the library is started with, as the JSON it takes.
    public static func configuration(key: String, serverID: String, hints: [String], port: Int = 0) -> String {
        let body: [String: Any] = ["key": key, "serverId": serverID, "hints": PeerConnect.hints(hints), "port": port]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// How the server is being reached right now, as the library reports it.
    public struct State: Equatable, Sendable, Decodable {
        public enum Path: String, Sendable, Decodable { case connecting, offline, local, direct, relayed }
        public var path: Path = .connecting
        public var transport: String?
        public var community: Bool?
        public var error: String?

        public init(json: String) {
            if let s = try? JSONDecoder().decode(State.self, from: Data(json.utf8)) { self = s }
        }

        /// Requests can be sent.
        public var connected: Bool { path == .local || path == .direct || path == .relayed }

        /// In words, to show wherever the app says which server it is on. A relay is always said.
        public var words: String {
            switch path {
            case .local: return "Peer to peer · same network"
            case .direct: return "Peer to peer · direct"
            case .relayed: return community == true ? "Peer to peer · through a relay" : "Peer to peer · connecting directly…"
            case .offline: return "Peer to peer · reconnecting…"
            case .connecting: return "Peer to peer · connecting…"
            }
        }
    }
}

#if canImport(Wittyconnect)
import Wittyconnect

/// One connection to one server. Start it, then send requests to `baseURL` with
/// `PeerConnect.secretHeader: secret` (URLSession), or the cookie (AVPlayer, a web view).
/// Not yet used by AppModel: see docs/PLATFORMS.md, "From away, peer to peer".
public final class PeerConnector: NSObject, WittyMobileListenerProtocol, @unchecked Sendable {
    private let session: WittyMobileSession
    private let onState: @Sendable (PeerConnect.State) -> Void

    /// A new key for this device. Keep it in the Keychain: the server knows the device by it.
    public static func newKey() throws -> String {
        var error: NSError?
        let key = WittyMobileNewKey(&error)
        if let error { throw error }
        return key
    }

    /// The public name of a key: what is sent to `POST /api/v1/p2p/devices`.
    public static func deviceID(of key: String) throws -> String {
        var error: NSError?
        let id = WittyMobileDeviceID(key, &error)
        if let error { throw error }
        return id
    }

    public init(key: String, serverID: String, hints: [String], onState: @escaping @Sendable (PeerConnect.State) -> Void) throws {
        self.onState = onState
        let relay = Relay()
        var error: NSError?
        guard let session = WittyMobileStart(PeerConnect.configuration(key: key, serverID: serverID, hints: hints), relay, &error) else {
            throw error ?? NSError(domain: "PeerConnect", code: 1)
        }
        self.session = session
        super.init()
        relay.to = self
    }

    // The library holds its listener strongly; this keeps the connector free to go away.
    private final class Relay: NSObject, WittyMobileListenerProtocol {
        weak var to: PeerConnector?
        func onState(_ state: String?) { to?.onState(state) }
    }

    public func onState(_ state: String?) { onState(PeerConnect.State(json: state ?? "")) }

    public var baseURL: URL { URL(string: "http://127.0.0.1:\(session.port())")! }
    public var secret: String { session.secret() }
    public var state: PeerConnect.State { PeerConnect.State(json: session.state()) }
    /// The server's addresses as last learnt, to keep as hints for next time.
    public var knownAddresses: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(session.knownAddrs().utf8))) ?? []
    }

    /// Call from NWPathMonitor when the network changes.
    public func networkChanged() { session.networkChanged() }

    /// Shows the server an invite's secret. Blocks for up to a minute: call it off the main actor.
    public func enrol(secret: String, deviceName: String, platform: String) throws -> String {
        var error: NSError?
        let answer = session.enrol(secret, name: deviceName, platform: platform, error: &error)
        if let error { throw error }
        return answer
    }

    public func close() { session.close() }
    deinit { session.close() }
}
#endif
