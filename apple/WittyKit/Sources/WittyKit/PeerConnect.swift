// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Reaching a server from away, peer to peer: no port opened on anyone's router. The
/// connecting is done by a Go library, Wittyconnect, built from the server's own source
/// (WittyMediaServer, `scripts/build-wittyconnect-mobile.sh apple`, under the AGPL). It gives
/// back an address on this device, and loading the server from there is loading it from home.
/// `docs/P2P.md` in the server's repository is the design.
///
/// What is here needs no library: reading an invite, the configuration the library takes and the
/// state it reports. PeerRoute.swift is the address requests then go to, and PeerManager.swift
/// chooses between home and away. The library itself is only known to the app (PeerLibrary.swift
/// there), so this package still builds and is tested anywhere.
public enum PeerConnect {
    /// What every request to the local address must carry: this header, or a cookie of this name.
    public static let secretHeader = "X-Witty-Connect"
    public static let secretCookie = "wittyconnect"
    /// On an answer from the local address itself, not the server: the way from away couldn't get through.
    public static let errorHeader = "X-Witty-Connect-Error"

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
        let name = shownName(items.first { $0.name == "n" }?.value ?? "", limit: 80)
        return Invite(serverID: id, secret: secret, name: name, hints: hints(items.filter { $0.name == "a" }.compactMap(\.value)))
    }

    /// A name that came in a link, fit to show: no control characters, and none of the invisible
    /// ones that turn text around, so a name can't be made to read as something else beside it.
    public static func shownName(_ text: String, limit: Int) -> String {
        let invisible: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF]
        var kept = String.UnicodeScalarView()
        for u in text.unicodeScalars where !(u.properties.generalCategory == .control) && !invisible.contains(u.value) {
            kept.append(u)
        }
        return String(String(kept).trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// A code as a device with no keyboard shows it, for someone signed in to type into the
    /// server: eight letters and digits, none that reads as another across a room.
    public static func isJoinCode(_ text: String) -> Bool {
        let symbols = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { $0.count == 4 && $0.allSatisfy(symbols.contains) }
    }

    /// What the library takes to look for the server that is told this device's code.
    public static func joinConfiguration(key: String, code: String, name: String, platform: String) -> String {
        let body: [String: Any] = ["key": key, "code": code, "name": String(name.prefix(60)), "platform": String(platform.prefix(24))]
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
        /// What the relay said it allows: kbit/s per connection and the picture height streams keep
        /// to, and the same in a sentence. Only from a relay that carries whole connections.
        public var relayKbps: Int?
        public var relayMaxHeight: Int?
        public var relayAllows: String?

        public init(json: String) {
            if let s = try? JSONDecoder().decode(State.self, from: Data(json.utf8)) { self = s }
        }

        private enum CodingKeys: String, CodingKey { case path, transport, community, error, relayKbps, relayMaxHeight, relayAllows }

        /// Field by field, so that one odd value (from a newer or older library) loses only itself.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(Path.self, forKey: .path)
            transport = try? c.decodeIfPresent(String.self, forKey: .transport)
            community = try? c.decodeIfPresent(Bool.self, forKey: .community)
            error = try? c.decodeIfPresent(String.self, forKey: .error)
            guard path == .relayed, community == true else { return }
            func int(_ k: CodingKeys, _ range: ClosedRange<Int>) -> Int? {
                guard let v = try? c.decodeIfPresent(Int.self, forKey: k), range.contains(v) else { return nil }
                return v
            }
            relayKbps = int(.relayKbps, 100...10_000_000)
            relayMaxHeight = int(.relayMaxHeight, 144...4320)
            if let s = try? c.decodeIfPresent(String.self, forKey: .relayAllows) {
                relayAllows = String(String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).prefix(300))
            }
        }

        /// Requests can be sent.
        public var connected: Bool { path == .local || path == .direct || path == .relayed }

        /// A relay's limits, short: "4 Mbit/s, 720p".
        public var relayLimits: String {
            var parts: [String] = []
            if let k = relayKbps {
                if k >= 1000 {
                    let m = (Double(k) / 100).rounded() / 10
                    parts.append(m == m.rounded() ? "\(Int(m)) Mbit/s" : "\(m) Mbit/s")
                } else {
                    parts.append("\(k) kbit/s")
                }
            }
            if let h = relayMaxHeight { parts.append("\(h)p") }
            return parts.joined(separator: ", ")
        }

        /// In words, to show wherever the app says which server it is on. A relay is always said,
        /// with what it allows, so a smaller picture has its reason in sight.
        public var words: String {
            switch path {
            case .local: return "Peer to peer · same network"
            case .direct: return "Peer to peer · direct"
            case .relayed:
                guard community == true else { return "Peer to peer · connecting directly…" }
                return relayLimits.isEmpty ? "Peer to peer · through a relay" : "Peer to peer · through a relay · \(relayLimits)"
            case .offline: return "Peer to peer · reconnecting…"
            case .connecting: return "Peer to peer · connecting…"
            }
        }
    }

    /// The server's answer to an invite. `code` is an ordinary sign-in code, to redeem over the
    /// new connection like one typed on a TV; the words are the server's own.
    public struct Enrolment: Equatable, Sendable, Decodable {
        public var ok = false
        public var code = ""
        public var reason = ""
        public var error = ""
        public var serverName = ""
        /// Only in the answer to a code this device showed (`joinConfiguration`): which server
        /// took it, and where it is. An invite names its server itself.
        public var serverID = ""
        public var addresses: [String] = []

        private enum CodingKeys: String, CodingKey { case ok, code, reason, error, serverName, serverID = "serverId", addresses = "addrs" }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            ok = (try? values.decodeIfPresent(Bool.self, forKey: .ok)) ?? false
            let digits = (try? values.decodeIfPresent(String.self, forKey: .code)) ?? ""
            code = digits.count == 6 && digits.allSatisfy(\.isNumber) ? digits : ""
            reason = String(((try? values.decodeIfPresent(String.self, forKey: .reason)) ?? "").prefix(40))
            error = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .error)) ?? "", limit: 300)
            serverName = PlainWords.clean((try? values.decodeIfPresent(String.self, forKey: .serverName)) ?? "", limit: 80)
            let id = (try? values.decodeIfPresent(String.self, forKey: .serverID)) ?? ""
            serverID = PeerConnect.isID(id) ? id : ""
            addresses = PeerConnect.hints((try? values.decodeIfPresent([String].self, forKey: .addresses)) ?? [])
        }

        public init(json: String) {
            if let read = try? JSONDecoder().decode(Enrolment.self, from: Data(json.utf8)) { self = read }
        }
    }
}
