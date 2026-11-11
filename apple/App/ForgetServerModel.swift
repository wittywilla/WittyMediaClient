// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation
import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// Remembering servers and removing them: what the app does around WittyKit's rules (ServerBook.swift)
// and its plan for a removal (ForgetServer.swift). Every way of removing a server (a swipe, the menu
// of a card, Manage servers, the warning about a server that changed) ends in `forgetServers` here.
//
// What goes with a server: its entry in the list, the address in use if it was that one, the sign-in
// if it was that server's (the server is told, once the removal can no longer be undone), its theme
// choice and the themes kept for it, the top menu of every profile on it, its logo, its cookies, the
// Top Shelf if it was the server in use, and the way to it from away (the server is asked to take this
// device off its list; the device's own key goes when no server left uses it).
//
// What stays, because it is the device's and not a server's: sound, streaming and remote choices, the
// games' touch layout and device name, the speed of books, the last channel, the app's own log, and
// files the person saved to Files. Web views keep nothing on disk, and the app's own connections keep
// no cache.

/// A removal that can still be taken back: iPhone and iPad show "Removed … Undo" for a few seconds.
@MainActor
final class ServerRemovals: ObservableObject {
    static let shared = ServerRemovals()

    struct Held: Identifiable {
        let id = UUID()
        let name: String
        let undo: () -> Void
        let finish: () -> Void
    }

    @Published private(set) var held: Held?
    private var clock: Task<Void, Never>?

    /// Long enough to read and reach; longer for someone finding the button with a screen reader or a switch.
    private var seconds: Double {
        #if canImport(UIKit) && !os(tvOS)
        if UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning { return 20 }
        #endif
        return 6
    }

    func hold(_ removal: Held) {
        finish()
        held = removal
        let wait = seconds
        clock = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// The time to undo is over: the screen was left, the app went off the screen, or the seconds ran out.
    func finish() {
        clock?.cancel()
        clock = nil
        guard let done = held else { return }
        held = nil
        done.finish()
    }

    func undo() {
        clock?.cancel()
        clock = nil
        guard let back = held else { return }
        held = nil
        back.undo()
    }
}

extension LogoCache {
    private static func files(of server: String) -> [String] {
        guard let folder else { return [] }
        let prefix = ServerKeys.logoName(server) + "-"
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix(prefix) }
    }

    static func remove(server: String) {
        guard let folder else { return }
        for file in files(of: server) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) }
    }

    /// A server's logo follows it to its new address, unless one is already kept there.
    static func move(from old: String, to new: String) {
        guard let folder, old != new else { return }
        let taken = !files(of: new).isEmpty
        for file in files(of: old) {
            let at = folder.appendingPathComponent(file)
            if taken {
                try? FileManager.default.removeItem(at: at)
            } else {
                let name = ServerKeys.logoName(new) + file.dropFirst(ServerKeys.logoName(old).count)
                try? FileManager.default.moveItem(at: at, to: folder.appendingPathComponent(name))
            }
        }
    }

    /// Logos of servers the device no longer remembers.
    static func sweep(keeping addresses: Set<String>) {
        guard let folder else { return }
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
            guard let address = ServerKeys.logoAddress(file: file), !addresses.contains(address) else { continue }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
}

extension AppModel {
    /// When this device began keeping the time each server was last reached.
    private static let sinceKey = "recentSince"

    /// Every name in this app's own preferences. Not what the system or the launch arguments add.
    private var ownKeys: [String] {
        Array((defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]).keys)
    }

    var keepingTimesSince: Int64 { (defaults.object(forKey: Self.sinceKey) as? NSNumber)?.int64Value ?? 0 }

    /// The server in use: the one whose screens are showing, signed in or signing in.
    func isInUse(_ server: SavedServer) -> Bool {
        guard current?.url == server.url, !client.base.isEmpty else { return false }
        switch stage {
        case .browsing, .signIn, .code: return true
        default: return false
        }
    }

    // MARK: Remembering

    /// The list as it was stored, made clean, once when the app starts: a server listed twice (it moved,
    /// or was typed by another of its addresses) becomes one entry, and what was kept under the address
    /// that went follows it. See `ServerBook.tidy`.
    func tidyServers() {
        #if DEBUG
        // For apple/scripts/forget-check.sh: `-WittyCheckPicker 1` at launch starts at the list of
        // servers, as "Change server" leaves it, with nobody there to press it.
        if UserDefaults.standard.bool(forKey: "WittyCheckPicker") {
            Keychain.clear()
            defaults.removeObject(forKey: "server")
        }
        // `-WittyCheckServers 1` opens Manage servers once someone is signed in, as You's row does.
        if UserDefaults.standard.bool(forKey: "WittyCheckServers") {
            Task {
                for _ in 0..<240 where stage != .browsing { try? await Task.sleep(nanoseconds: 250_000_000) }
                if stage == .browsing { paths[.home] = [.servers] }
            }
        }
        #endif
        let stored = recent
        let tidy = ServerBook.tidy(stored)
        if tidy.list != stored {
            ClientLog.shared.info("servers", "The list of servers had \(stored.count - tidy.list.count) listed twice: now \(tidy.list.count)")
            recent = tidy.list
        }
        for move in tidy.moves { follow(move) }
        if defaults.object(forKey: Self.sinceKey) == nil { defaults.set(NSNumber(value: ServerBook.now()), forKey: Self.sinceKey) }
        sweep()
    }

    /// A server that has just proved who it is and been opened: it goes first in the list with the time,
    /// as one entry whatever address it was remembered at before.
    func remember(_ server: SavedServer) {
        let done = ServerBook.remember(server, in: recent, now: ServerBook.now())
        recent = done.list
        for old in done.replaced {
            // Another server was remembered here. What was kept for it isn't this one's.
            if old.url == server.url {
                for key in ServerKeys.byAddress(old.url, in: ownKeys, addresses: done.list.map(\.url)) { defaults.removeObject(forKey: key) }
                LogoCache.remove(server: old.url)
            }
            let way = ServerKeys.peerKey(old)
            if defaults.object(forKey: way) != nil {
                defaults.removeObject(forKey: way)
                if !done.list.contains(where: { defaults.object(forKey: ServerKeys.peerKey($0)) != nil }) { Keychain.clearPeerKey() }
            }
        }
        for move in done.moves { follow(move) }
        sweep()
        objectWillChange.send()
    }

    /// What was kept under a server's old address goes to its new one.
    private func follow(_ move: ServerMove) {
        let addresses = recent.map(\.url) + [move.from.url, move.to.url]
        for (old, new) in ServerKeys.renames(move, in: ownKeys, addresses: addresses) {
            if defaults.object(forKey: new) == nil, let value = defaults.object(forKey: old) { defaults.set(value, forKey: new) }
            defaults.removeObject(forKey: old)
        }
        LogoCache.move(from: move.from.url, to: move.to.url)
        if lastUsedURL == move.from.url { defaults.set(move.to.url, forKey: "server") }
        // The theme chosen on this device for it, if it is the server on screen.
        if client.base == move.to.url, let chosen = defaults.string(forKey: "theme." + move.to.url), chosen != themeChoice { chooseTheme(chosen) }
        ClientLog.shared.info("servers", "A remembered server is at a new address: what was kept for it went with it")
    }

    /// Settings and logos left under addresses no remembered server is at.
    private func sweep() {
        for key in ServerKeys.orphans(in: ownKeys, servers: recent, current: lastUsedURL) { defaults.removeObject(forKey: key) }
        LogoCache.sweep(keeping: Set(recent.map(\.url) + [lastUsedURL]))
    }

    // MARK: Removing

    /// What a removal took that can be put back, and what is still to do once it can't.
    private struct Leaving {
        let plan: ForgetServer.Plan
        let before: [SavedServer]
        let current: String
        var values: [String: Any] = [:]
        var token = ""
        var pin = ""
        /// The one that was on screen, which `changeServer` has already said goodbye to.
        var using: SavedServer?
    }

    /// Removes servers from this device: everything it keeps for them, and nothing of any other.
    /// With `undoable`, one server that isn't on screen can be put back for a few seconds, and
    /// nothing is said to it until then. Removing the server on screen signs out and goes back to
    /// the list of servers.
    func forgetServers(_ asked: [SavedServer], undoable: Bool = false) {
        // One at a time: an earlier removal is finished first.
        ServerRemovals.shared.finish()
        let token = Keychain.token
        let pin = Keychain.pin
        let holding = ForgetServer.Holding(recent: recent, current: lastUsedURL, signedIn: !token.isEmpty, pin: pin, keys: ownKeys)
        let plan = ForgetServer.plan(removing: asked, holding: holding)
        guard !plan.removed.isEmpty else { return }
        var leaving = Leaving(plan: plan, before: holding.recent, current: holding.current)
        for key in plan.keys { leaving.values[key] = defaults.object(forKey: key) }
        leaving.using = plan.removed.first { isInUse($0) }

        if leaving.using != nil {
            // As "Change server" does: the last place listened to is sent, this device comes off the
            // server's list for connections from away, the sign-in is ended there and forgotten here.
            changeServer()
        } else if plan.signIn != nil {
            leaving.token = token
            leaving.pin = pin
            Keychain.clear()
            TopShelfWriter.clear()
            ArtCache.shared.removeAllObjects()
        }
        recent = plan.remaining
        if plan.clearsCurrent { defaults.removeObject(forKey: "server") }
        // The way from away to the server that was on screen is `changeServer`'s to drop, after it has told the server.
        let usingWay = leaving.using.map(ServerKeys.peerKey)
        for key in plan.keys where !(key == usingWay && PeerLibrary.available) { defaults.removeObject(forKey: key) }
        objectWillChange.send()
        ClientLog.shared.info("servers", plan.removed.count == 1 ? "A server was removed from this device" : "\(plan.removed.count) servers were removed from this device")

        if undoable, leaving.using == nil, plan.removed.count == 1, let server = plan.removed.first {
            let kept = leaving
            ServerRemovals.shared.hold(ServerRemovals.Held(name: ServerWords.name(server),
                                                           undo: { [weak self] in self?.putBack(kept) },
                                                           finish: { [weak self] in self?.finishForgetting(kept) }))
        } else {
            finishForgetting(leaving)
        }
    }

    /// Undo: the entry in its place, its settings, and the sign-in if it was this server's.
    private func putBack(_ leaving: Leaving) {
        var list = recent
        for server in leaving.plan.removed where !list.contains(where: { ServerBook.sameEntry($0, server) }) {
            let was = leaving.before.firstIndex { $0.url == server.url } ?? list.count
            list.insert(server, at: min(was, list.count))
        }
        recent = list
        for (key, value) in leaving.values { defaults.set(value, forKey: key) }
        if !leaving.token.isEmpty { _ = Keychain.save(token: leaving.token, pin: leaving.pin) }
        if leaving.plan.clearsCurrent, lastUsedURL.isEmpty { defaults.set(leaving.current, forKey: "server") }
        objectWillChange.send()
        if let server = leaving.plan.removed.first { announce(ServerWords.fill("removeUndone", ["name": ServerWords.name(server)])) }
    }

    /// The removal stands. What couldn't be put back goes now, and the servers are told.
    private func finishForgetting(_ leaving: Leaving) {
        let plan = leaving.plan
        for url in plan.logos { LogoCache.remove(server: url) }
        let jar = HTTPCookieStorage.shared
        for cookie in jar.cookies ?? [] where cookie.name != PeerConnect.secretCookie {
            let domain = cookie.domain.lowercased()
            if plan.hosts.contains(domain.hasPrefix(".") ? String(domain.dropFirst()) : domain) { jar.deleteCookie(cookie) }
        }
        sweep()
        let others = plan.removed.filter { $0.url != leaving.using?.url }
        Task {
            for server in others {
                let way = ServerKeys.peerKey(server)
                await sayGoodbye(to: server, token: server.url == plan.signIn?.url ? leaving.token : "", way: leaving.values[way])
                // Whatever came of that, the way to it isn't kept (unless a remaining server shares it).
                if plan.keys.contains(way) { defaults.removeObject(forKey: way) }
            }
            if plan.clearsDeviceKey, !recent.contains(where: { defaults.object(forKey: ServerKeys.peerKey($0)) != nil }) {
                Keychain.clearPeerKey()
            }
        }
    }

    /// Tells a removed server that this device has gone: its sign-in is ended, and the device comes off
    /// its list for connections from away. Only a server that proves it is still the one remembered is
    /// sent the sign-in. Three seconds at most, and nothing here can stop or undo the removal.
    private func sayGoodbye(to server: SavedServer, token: String, way: Any?) async {
        let away = way != nil && PeerLibrary.available
        guard !token.isEmpty || away else { return }
        let work = Task { @MainActor in
            var leavingClient = connection(to: server.url, quick: true)
            if !token.isEmpty {
                let proof = await WittyClient.identify(server.url, saved: [server], route: routeFor(server.url))
                if Identity.fits(pin: server.publicKey, proof: proof) { leavingClient = connection(to: server.url, token: token, quick: true) }
            }
            if away {
                // The one place that knows how a way from away is dropped: AwayModel.swift. It looks the
                // way up where it was kept, so it is put there for it to find.
                defaults.set(way, forKey: ServerKeys.peerKey(server))
                await forgetAway(on: leavingClient, server: server)
            }
            if !leavingClient.token.isEmpty { try? await leavingClient.logout() }
        }
        let clock = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            work.cancel()
        }
        await work.value
        clock.cancel()
    }
}
