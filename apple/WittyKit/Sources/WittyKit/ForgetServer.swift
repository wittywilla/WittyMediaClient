// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Removing a server from a device: what exactly goes, worked out here with nothing touched, so that it
// can be tested. Everything the app keeps for that server, and nothing of any other. The app carries
// the plan out (apple/App/ForgetServerModel.swift); every way of removing a server goes through it.

/// The names the app keeps a server's settings under, in its preferences. Most are by the server's
/// address; how to reach it from away is by its ID, so that it follows the server when it moves.
public enum ServerKeys {
    static let theme = "theme."
    static let themeTokens = "themeTokens|"
    static let topMenu = "topMenu."
    static let peer = "peer."

    /// Where the way to a server from away is kept: apple/App/AwayModel.swift.
    public static func peerKey(_ server: SavedServer) -> String {
        peer + (server.serverId.isEmpty ? server.url : server.serverId)
    }

    public enum Owner: Equatable {
        /// Kept by address. An address nobody knows comes back as it was written.
        case address(String)
        /// How to reach a server from away, by the server's ID (or its address, with no ID).
        case peer(String)
    }

    /// Whose a key is, or nil if it isn't a server's at all. A top menu's key ends in a profile's name
    /// after a dot, and addresses have dots of their own (`http://nas` and `http://nas.local`), so it is
    /// the longest known address that fits.
    public static func owner(of key: String, addresses: [String]) -> Owner? {
        if key.hasPrefix(theme) { return .address(String(key.dropFirst(theme.count))) }
        if key.hasPrefix(themeTokens) {
            let rest = key.dropFirst(themeTokens.count)
            guard let bar = rest.lastIndex(of: "|") else { return .address(String(rest)) }
            return .address(String(rest[..<bar]))
        }
        if key.hasPrefix(topMenu) {
            let rest = String(key.dropFirst(topMenu.count))
            let fits = addresses.filter { rest.hasPrefix($0 + ".") }.max { $0.count < $1.count }
            return .address(fits ?? rest)
        }
        if key.hasPrefix(peer) { return .peer(String(key.dropFirst(peer.count))) }
        return nil
    }

    /// The keys kept under a server's address, out of every key the app has.
    public static func byAddress(_ url: String, in keys: [String], addresses: [String]) -> [String] {
        let known = addresses.contains(url) ? addresses : addresses + [url]
        return keys.filter { owner(of: $0, addresses: known) == .address(url) }
    }

    /// What to rename when a server's settings follow it to another address: old name, new name.
    public static func renames(_ move: ServerMove, in keys: [String], addresses: [String]) -> [(from: String, to: String)] {
        let old = move.from.url, new = move.to.url
        var out: [(from: String, to: String)] = []
        for key in byAddress(old, in: keys, addresses: addresses) {
            for prefix in [theme, themeTokens, topMenu] where key.hasPrefix(prefix) {
                out.append((key, prefix + new + key.dropFirst(prefix.count + old.count)))
            }
        }
        let peerOld = peerKey(move.from), peerNew = peerKey(move.to)
        if peerOld != peerNew, keys.contains(peerOld) { out.append((peerOld, peerNew)) }
        return out
    }

    /// Keys by address that belong to no server the device remembers or is using: left by a server that
    /// moved, or one that dropped off the end of the list. Ways from away are never guessed at here.
    public static func orphans(in keys: [String], servers: [SavedServer], current: String) -> [String] {
        let known = servers.map(\.url) + (current.isEmpty ? [] : [current])
        return keys.filter { key in
            guard case .address(let url)? = owner(of: key, addresses: known) else { return false }
            return !known.contains(url)
        }
    }

    /// The name a server's logo is kept under begins with this: apple/App/SignInKit.swift, LogoCache.
    public static func logoName(_ url: String) -> String {
        Data(url.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }

    /// The address a kept logo's file is for, from its name. Nil if the name isn't one of these.
    public static func logoAddress(file: String) -> String? {
        guard let dash = file.lastIndex(of: "-") else { return nil }
        var text = file[..<dash].replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
        while text.count % 4 != 0 { text += "=" }
        guard let data = Data(base64Encoded: text) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public enum ForgetServer {
    /// What the device holds, as far as removing a server is concerned.
    public struct Holding {
        public var recent: [SavedServer]
        /// The address of the server in use, or last in use.
        public var current: String
        /// Whether a sign-in is kept, and the key of the server it was kept with.
        public var signedIn: Bool
        public var pin: String
        /// Every key in the app's preferences.
        public var keys: [String]

        public init(recent: [SavedServer], current: String = "", signedIn: Bool = false, pin: String = "", keys: [String] = []) {
            self.recent = recent
            self.current = current
            self.signedIn = signedIn
            self.pin = pin
            self.keys = keys
        }
    }

    public struct Plan: Equatable {
        public let removed: [SavedServer]
        public let remaining: [SavedServer]
        /// Preferences to delete: the removed servers' settings and their ways from away.
        public let keys: [String]
        /// Addresses whose kept logo goes.
        public let logos: [String]
        /// Hosts whose cookies go: the removed servers', but for one a remaining server is at too.
        public let hosts: [String]
        /// The address of the server in use is forgotten: it was one of them.
        public let clearsCurrent: Bool
        /// The kept sign-in belongs to this one, and goes; the server is told so afterwards.
        public let signIn: SavedServer?
        /// Removed servers this device can reach from away: each is asked to take this device off its
        /// list, and the way to it is dropped.
        public let peers: [SavedServer]
        /// No server left knows this device by its key for connections from away, so the key goes too.
        public let clearsDeviceKey: Bool
    }

    /// The sign-in is the removed server's if that is the server in use, or it was kept with that server's key.
    static func ownsSignIn(_ server: SavedServer, _ holding: Holding) -> Bool {
        holding.signedIn && (server.url == holding.current || (!holding.pin.isEmpty && holding.pin == server.publicKey))
    }

    static func host(_ url: String) -> String { (URLComponents(string: url)?.host ?? "").lowercased() }

    public static func plan(removing: [SavedServer], holding: Holding) -> Plan {
        let removed = holding.recent.filter { old in removing.contains { $0.url == old.url } }
        let remaining = holding.recent.filter { old in !removed.contains { $0.url == old.url } }
        let addresses = holding.recent.map(\.url) + (holding.current.isEmpty ? [] : [holding.current])
        var keys: [String] = []
        for server in removed {
            keys += ServerKeys.byAddress(server.url, in: holding.keys, addresses: addresses)
            let peer = ServerKeys.peerKey(server)
            if holding.keys.contains(peer), !remaining.contains(where: { ServerKeys.peerKey($0) == peer }) { keys.append(peer) }
        }
        let peers = removed.filter { holding.keys.contains(ServerKeys.peerKey($0)) }
        let stillAway = remaining.contains { holding.keys.contains(ServerKeys.peerKey($0)) }
        let kept = Set(remaining.map { host($0.url) })
        var hosts: [String] = []
        for server in removed {
            let name = host(server.url)
            if !name.isEmpty, !kept.contains(name), !hosts.contains(name) { hosts.append(name) }
        }
        return Plan(removed: removed, remaining: remaining, keys: keys, logos: removed.map(\.url), hosts: hosts,
                    clearsCurrent: removed.contains { $0.url == holding.current },
                    signIn: removed.first { ownsSignIn($0, holding) },
                    peers: peers, clearsDeviceKey: !peers.isEmpty && !stillAway)
    }
}
