// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The list of servers a device has used ("Used before"), and the rules that keep it honest: one entry
// for one server whatever address it is at, when each was last reached, which have not been reached
// for a while, and where the remote's focus goes when one is removed. Removing itself is in
// ForgetServer.swift. The desktop and Android apps keep the same rules.

/// A server's settings were kept under one address and belong under another: it moved, or was listed twice.
public struct ServerMove: Equatable {
    public let from: SavedServer
    public let to: SavedServer
}

/// When a remembered server was last reached, for the line under its name.
public enum LastReached: Equatable {
    /// Remembered before the app kept this.
    case unknown
    case today
    case yesterday
    case days(Int)
}

public enum ServerBook {
    /// How many servers are remembered. The oldest gives way to a new one past this.
    public static let limit = 8
    /// A remembered server is marked "Not reached lately" after this long.
    public static let staleDays = 90
    /// What "Remove servers not reached for…" offers, in days.
    public static let periods = [30, 90, 180, 365]
    static let day: Int64 = 86_400_000

    public static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: One entry for one server

    /// Both proved a key, and not the same one: two different servers, whatever else they share.
    static func conflict(_ a: SavedServer, _ b: SavedServer) -> Bool {
        !a.publicKey.isEmpty && !b.publicKey.isEmpty && a.publicKey != b.publicKey
    }

    /// The same server by what it proved: the same ID, or the same key. The address doesn't come into it.
    public static func sameServer(_ a: SavedServer, _ b: SavedServer) -> Bool {
        if !a.publicKey.isEmpty && a.publicKey == b.publicKey { return true }
        return !a.serverId.isEmpty && a.serverId == b.serverId && !conflict(a, b)
    }

    /// Whether two take one place in the list: the same server, or the same address (an address is only
    /// ever listed once, and a server with neither an ID nor a key is known by nothing else).
    public static func sameEntry(_ a: SavedServer, _ b: SavedServer) -> Bool {
        a.url == b.url || sameServer(a, b) || (!a.serverId.isEmpty && a.serverId == b.serverId)
    }

    /// The newer of two entries for one server, with what it lacks taken from the older. Two different
    /// servers that met at one address share nothing: the newer stands as it is.
    static func fill(_ newer: SavedServer, from older: SavedServer) -> SavedServer {
        guard !conflict(newer, older) else { return newer }
        // The fingerprint is the key's, so it comes from whichever the key came from.
        let keyed = newer.publicKey.isEmpty || newer.fingerprint.isEmpty ? older : newer
        var merged = SavedServer(url: newer.url,
                                 name: newer.name.trimmingCharacters(in: .whitespaces).isEmpty ? older.name : newer.name,
                                 serverId: newer.serverId.isEmpty ? older.serverId : newer.serverId,
                                 publicKey: newer.publicKey.isEmpty ? older.publicKey : newer.publicKey,
                                 fingerprint: keyed.fingerprint.isEmpty ? newer.fingerprint : keyed.fingerprint,
                                 brandLogo: newer.brandLogo.isEmpty ? older.brandLogo : newer.brandLogo)
        merged.lastSeen = max(newer.lastSeen, older.lastSeen)
        return merged
    }

    public struct Remembered: Equatable {
        public let list: [SavedServer]
        /// Entries the server took the place of at another address: what was kept for it there goes with it.
        public let moves: [ServerMove]
        /// Other servers this one took the place of, at its address or under its ID with another key: what
        /// was kept for them isn't this one's.
        public let replaced: [SavedServer]
        /// Pushed out of the end of the list by the newest.
        public let dropped: [SavedServer]
    }

    /// A server that has just proved who it is and been opened goes first, stamped with now. It takes the
    /// place of every entry that is the same server (by ID or key, whatever the address) or at its address.
    public static func remember(_ server: SavedServer, in list: [SavedServer], now: Int64) -> Remembered {
        var fresh = server
        fresh.lastSeen = max(now, 0)
        var others: [SavedServer] = []
        var movedFrom: [SavedServer] = []
        var replaced: [SavedServer] = []
        for old in list {
            guard sameEntry(old, server) else { others.append(old); continue }
            if conflict(old, server) {
                replaced.append(old)
            } else {
                fresh = fill(fresh, from: old)
                fresh.lastSeen = max(now, 0)
                if old.url != server.url { movedFrom.append(old) }
            }
        }
        let all = [fresh] + others
        return Remembered(list: Array(all.prefix(limit)), moves: movedFrom.map { ServerMove(from: $0, to: fresh) }, replaced: replaced,
                          dropped: Array(all.dropFirst(limit)))
    }

    public struct Tidied: Equatable {
        public let list: [SavedServer]
        public let moves: [ServerMove]
    }

    /// A stored list made clean, when the app starts: entries for one server become one. The one reached
    /// most recently wins (of two not known, the one nearer the top, which is the newer), and takes what
    /// it lacks from the other. Tidying a tidy list changes nothing.
    public static func tidy(_ list: [SavedServer]) -> Tidied {
        var out = list
        var moves: [ServerMove] = []
        while true {
            var next: [SavedServer] = []
            for entry in out {
                guard let at = next.firstIndex(where: { sameEntry($0, entry) }) else { next.append(entry); continue }
                let kept = next[at]
                let (newer, older) = entry.lastSeen > kept.lastSeen ? (entry, kept) : (kept, entry)
                next[at] = fill(newer, from: older)
                if older.url != newer.url, !conflict(newer, older) { moves.append(ServerMove(from: older, to: newer)) }
            }
            if next.count == out.count { out = next; break }
            out = next
        }
        // A move's end is the entry as it finished.
        let settled = moves.compactMap { move in out.first { sameEntry($0, move.to) }.map { ServerMove(from: move.from, to: $0) } }
        return Tidied(list: out, moves: settled.filter { $0.from.url != $0.to.url })
    }

    // MARK: Found on the network

    /// Where to connect for a remembered server: where it is found now, if the network shows it at another
    /// address than the one remembered. Who answers there is still checked before anything is updated.
    public static func address(of server: SavedServer, found: [FoundServer]) -> String {
        guard !server.serverId.isEmpty, let there = found.first(where: { $0.id == server.serverId }) else { return server.url }
        return there.url
    }

    /// The remembered entries a server showing another key clashes with: the ones at its address or with its ID.
    public static func clashes(with shown: SavedServer, in list: [SavedServer]) -> [SavedServer] {
        list.filter { old in
            !old.publicKey.isEmpty && old.publicKey != shown.publicKey
                && (old.url == shown.url || (!old.serverId.isEmpty && old.serverId == shown.serverId))
        }
    }

    // MARK: When it was last reached

    public static func lastReached(_ lastSeen: Int64, now: Int64, calendar: Calendar = .current) -> LastReached {
        guard lastSeen > 0 else { return .unknown }
        let then = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(lastSeen) / 1000))
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(now) / 1000))
        let days = calendar.dateComponents([.day], from: then, to: today).day ?? 0
        // A clock put back makes the future: that is today too.
        if days <= 0 { return .today }
        return days == 1 ? .yesterday : .days(days)
    }

    /// "Not reached lately": only said of a server whose last time is known.
    public static func isStale(_ server: SavedServer, now: Int64) -> Bool {
        server.lastSeen > 0 && now - server.lastSeen >= Int64(staleDays) * day
    }

    /// The servers not reached for `days` or more. One whose last time isn't known (remembered before the
    /// app kept times, or never reached since) is never chosen: nothing says how long it has been, and the
    /// desktop and Android apps leave it out the same way. It can still be removed by itself or with Remove all.
    public static func notReached(for days: Int, in list: [SavedServer], now: Int64) -> [SavedServer] {
        list.filter { $0.lastSeen > 0 && now - $0.lastSeen >= Int64(days) * day }
    }

    // MARK: Focus

    /// Where focus goes when a card is removed: the next one, else the one before, else nil, which is
    /// "Enter an address". Never nowhere.
    public static func focusAfter(removing id: String, in ids: [String]) -> String? {
        guard let at = ids.firstIndex(of: id) else { return ids.first }
        if at + 1 < ids.count { return ids[at + 1] }
        return at > 0 ? ids[at - 1] : nil
    }
}
