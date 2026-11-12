// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import AVFoundation
import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// A watch party, from this device's side: the room as the server last described it, the server's clock, and
// keeping the app's video player in step with both. The server's docs/SYNCPLAY.md has the rules, and
// WittyKit's SyncPlay.swift has them as arithmetic; this file is the connection and the player.
//
// The server's state is the only truth. This device never says where its picture is: it asks for changes
// (play, seek) and says whether it has caught up (ready, buffering). What the person presses becomes a
// command, and the answer moves this player like everyone else's.

@MainActor
final class PartySession: ObservableObject {
    @Published private(set) var room: SyncRoom?
    private(set) var drift = SyncDrift()
    private(set) var limits = SyncLimits()
    /// What tells this app's seat from another of the same sign-in: kept on the device, so the app killed and
    /// opened again within the two minutes a seat is kept sits back down in it.
    let device: String
    var onRoom: ((SyncRoom) -> Void)?
    var onOver: ((String) -> Void)?

    private static let deviceKey = "party.device"
    private static let roomKey = "party.room"
    private var client: WittyClient?
    private var time = SyncTime()
    private var listening: Task<Void, Never>?
    private var pinging: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        if let kept = defaults.string(forKey: Self.deviceKey), !kept.isEmpty {
            device = kept
        } else {
            device = "apple-" + UUID().uuidString.prefix(8).lowercased()
            defaults.set(device, forKey: Self.deviceKey)
        }
    }

    /// A clock that doesn't jump, in milliseconds: the wall clock would spoil a ping when it's corrected.
    static func steadyMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    /// The server's time now, as near as the pings have it.
    func serverNow() -> Double { time.serverNow(localMs: Self.steadyMs()) }

    var bestRttMs: Double { time.rttMs }

    /// A watch party in the logs, the same id as the server's: "party-" and the room's id.
    static func logSession(_ roomID: String) -> String {
        let id = roomID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.:".contains($0)) }
        return id.isEmpty ? "" : "party-" + id.prefix(58)
    }

    var logSession: String { Self.logSession(room?.id ?? "") }

    func use(_ client: WittyClient, info: SyncInfo?) {
        self.client = client
        if let info {
            drift = info.drift
            limits = info.limits
        }
    }

    // MARK: Coming and going

    func create(_ start: SyncStart) async throws {
        guard let client else { return }
        enter(try await client.syncCreate(start))
    }

    func join(code: String) async throws {
        guard let client else { return }
        enter(try await client.syncJoin(code: code, device: device))
    }

    func join(room id: String) async throws {
        guard let client else { return }
        enter(try await client.syncJoin(room: id, device: device))
    }

    /// The app was closed with a seat in a party: if the server still keeps it, sit back down.
    func comeBack(among rooms: [SyncListing]) async {
        guard let kept = defaults.string(forKey: Self.roomKey), !kept.isEmpty else { return }
        guard rooms.contains(where: { $0.id == kept && $0.seated }) else {
            defaults.removeObject(forKey: Self.roomKey)
            return
        }
        do {
            try await join(room: kept)
        } catch {
            ClientLog.shared.warn("party", "Sitting back down in the watch party failed: \((error as? APIError)?.status ?? 0)", session: Self.logSession(kept))
            defaults.removeObject(forKey: Self.roomKey)
        }
    }

    private func enter(_ entered: SyncRoom) {
        stopTasks()
        time = SyncTime()
        time.guess(serverTimeMs: entered.serverTimeMs, localMs: Self.steadyMs())
        room = entered
        defaults.set(entered.id, forKey: Self.roomKey)
        ClientLog.shared.info("party", "In watch party \(entered.id.prefix(6)) as \(entered.isHost ? "host" : "guest").")
        pinging = Task { [weak self] in await self?.pings() }
        listening = Task { [weak self] in await self?.listen() }
        onRoom?(entered)
    }

    private func stopTasks() {
        listening?.cancel()
        listening = nil
        pinging?.cancel()
        pinging = nil
    }

    private func gone(_ words: String) {
        stopTasks()
        room = nil
        defaults.removeObject(forKey: Self.roomKey)
        onOver?(words)
    }

    /// The person chose to go: the seat is given up at once.
    func leave() {
        guard let room, let client else { return }
        Task { try? await client.syncLeave(room) }
        gone("")
    }

    /// Signing out: the stream stops, and the server gives the seat up when it notices.
    func drop() {
        guard room != nil else { return }
        stopTasks()
        room = nil
        defaults.removeObject(forKey: Self.roomKey)
    }

    /// Ends the party for everyone: the host's.
    func end() async throws {
        guard let room, let client else { return }
        try await client.syncEnd(room)
        gone("")
    }

    // MARK: The room

    private func take(_ incoming: SyncRoom) {
        guard let current = room else { return }
        let next = current.taking(incoming)
        guard next != current else { return }
        room = next
        onRoom?(next)
    }

    /// A command to the room. The answer is the room after it, which everyone's player then follows.
    func command(_ type: String, positionSec: Double? = nil, index: Int? = nil, rate: Double? = nil, items: [Int64]? = nil, ifSeq: Int? = nil) async throws {
        guard let room, let client else { return }
        take(try await client.syncCommand(room, type, positionSec: positionSec, index: index, rate: rate, items: items, ifSeq: ifSeq))
    }

    func report(_ state: String, rev: Int) {
        guard let room, let client else { return }
        Task { try? await client.syncReport(room, state: state, rev: rev) }
    }

    func set(everyone: Bool? = nil, waitForAll: Bool? = nil) async throws {
        guard let room, let client else { return }
        try await client.syncSet(room, everyone: everyone, waitForAll: waitForAll)
    }

    func makeHost(_ member: String) async throws {
        guard let room, let client else { return }
        try await client.syncMakeHost(room, member: member)
    }

    func remove(_ member: String) async throws {
        guard let room, let client else { return }
        try await client.syncRemove(room, member: member)
    }

    func invite(_ users: [Int64]) async throws {
        guard let room, let client else { return }
        try await client.syncInvite(room, users: users)
    }

    // MARK: The clock, and the stream

    /// A few quickly, to have a good offset before anything plays; then a steady heartbeat.
    private func pings() async {
        var count = 0
        while !Task.isCancelled {
            let wait = SyncTime.wait(beforePing: count, everySec: limits.pingEverySec)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled, let room, let client else { return }
            count += 1
            let sent = Self.steadyMs()
            guard let answer = try? await client.syncPing(room, t0: sent, rttMs: time.rttMs) else { continue }
            time.add(SyncSample(t0: sent, t1: answer.t1, t2: answer.t2, t3: Self.steadyMs()))
        }
    }

    private func listen() async {
        var backoff = Backoff()
        while !Task.isCancelled, let current = room, let client {
            var closed: String?
            var refusal: APIError?
            do {
                for try await event in client.events(client.syncEventsPath(current)) {
                    switch event.name {
                    case "room":
                        backoff.reset()
                        if let fresh = event.decoded(SyncRoom.self) { take(fresh) }
                    case "closed":
                        struct Closed: Decodable { let reason: String? }
                        closed = event.decoded(Closed.self)?.reason ?? "closed"
                    default:
                        break
                    }
                }
            } catch let refused as APIError {
                refusal = refused
                if !Task.isCancelled {
                    ClientLog.shared.warnSeldom("party", "The watch party's events were refused: \(refused.status) \(refused.code)", session: Self.logSession(current.id))
                }
            } catch {
                // The connection dropped, or said nothing for a minute.
                if !Task.isCancelled, !(error is CancellationError) {
                    ClientLog.shared.warnSeldom("party", "The watch party's events stopped: \((error as? URLError)?.code.rawValue ?? 0)", session: Self.logSession(current.id))
                }
            }
            guard !Task.isCancelled else { return }
            switch SyncLife.after(closed: closed, refusal: refusal, backoff: &backoff) {
            case .over(let words):
                gone(words)
                return
            case .rejoin(let wait):
                // The seat is kept for two minutes: take it again, with the same `device`.
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, room != nil else { return }
                do {
                    let again = try await client.syncJoin(room: current.id, device: device)
                    guard !Task.isCancelled else { return }
                    room = again
                    onRoom?(again)
                } catch let refused as APIError {
                    ClientLog.shared.warnSeldom("party", "Rejoining the watch party was refused: \(refused.status) \(refused.code)", session: Self.logSession(current.id))
                    if case .over(let words) = SyncLife.after(closed: nil, refusal: refused, backoff: &backoff) {
                        gone(words)
                        return
                    }
                } catch {
                    // Still no network: round again.
                    if !Task.isCancelled, !(error is CancellationError) {
                        ClientLog.shared.warnSeldom("party", "Rejoining the watch party failed: \((error as? URLError)?.code.rawValue ?? 0)", session: Self.logSession(current.id))
                    }
                }
            }
        }
    }
}

// MARK: - Following the room with a player

/// Keeps one video player in step with the room, and turns what the viewer does into commands for everyone.
/// The decisions are WittyKit's `SyncFollower`; this reads the player's facts for it and does what it answers.
@MainActor
final class PartyFollower: PlaybackSteering {
    private(set) weak var playback: PlaybackModel?
    private let party: PartySession
    private weak var hub: RemoteHub?
    private var rules: SyncFollower
    private var ticking: Task<Void, Never>?
    private var waking: Task<Void, Never>?
    private var statusObserver: NSKeyValueObservation?
    /// What this does to the player isn't the viewer doing it.
    private var quietUntil = 0.0
    /// While true, the player's own seek goes ahead: it's this asking.
    private var own = false
    private var seeking = false
    private var seenItem: AVPlayerItem?
    private var toldOff = 0.0
    private var logged = 0.0
    private var stopped = false
    /// How far behind the room this player was at the last look (negative: ahead). Nil while the room is held.
    private(set) var lastBehind: Double?

    init(playback: PlaybackModel, party: PartySession, hub: RemoteHub) {
        self.playback = playback
        self.party = party
        self.hub = hub
        rules = SyncFollower(drift: party.drift)
    }

    private static func now() -> Double { PartySession.steadyMs() }

    func start() {
        guard let playback else { return }
        playback.steering = self
        quietUntil = Self.now() + 2000
        statusObserver = playback.player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.statusChanged() }
        }
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        ticking?.cancel()
        waking?.cancel()
        statusObserver = nil
        if let playback, playback.steering === self {
            playback.steering = nil
            // Out of the party, the player is the viewer's own again, at an ordinary speed.
            let speed = playback.clockface.rate
            playback.player.defaultRate = speed
            if playback.player.timeControlStatus != .paused { playback.player.rate = speed }
        }
    }

    /// The room this player is following, while it is: the room's item is this one, and this account may see it.
    private var room: SyncRoom? {
        guard let playback, let room = party.room, !room.blocked, room.state.itemId == playback.id else { return nil }
        return room
    }

    func roomChanged() { tick() }

    private func quiet(_ change: () -> Void) {
        quietUntil = Self.now() + 700
        change()
    }

    private var loaded: Bool {
        guard let playback else { return false }
        return playback.stream != nil && playback.player.currentItem?.status == .readyToPlay
    }

    private func filmTime(_ playback: PlaybackModel) -> Double {
        let at = playback.player.currentTime().seconds
        return (at.isFinite ? at : 0) + (playback.stream?.offset ?? 0)
    }

    private func facts(_ playback: PlaybackModel) -> SyncPlayerFacts {
        let player = playback.player
        let item = player.currentItem
        let position = filmTime(playback)
        let duration = playback.stream?.durationSec ?? playback.item?.runtimeSec ?? 0
        let stalled = player.timeControlStatus == .waitingToPlayAtSpecifiedRate && player.reasonForWaitingToPlay == .toMinimizeStalls
        let canPlay = loaded && !stalled && (item?.isPlaybackLikelyToKeepUp == true || player.timeControlStatus == .playing)
        return SyncPlayerFacts(positionSec: position, paused: player.timeControlStatus == .paused, loaded: loaded, canPlay: canPlay,
                               seeking: seeking, ended: playback.ended || (duration > 0 && position >= duration - 0.25),
                               cheapSeek: playback.stream?.mustReopenToSeekFar != true)
    }

    private func tick() {
        guard !stopped else { return }
        guard let playback, playback.isRunning else {
            // The player has closed. Unless another takes its place, that was leaving the party.
            ticking?.cancel()
            hub?.followerEnded(self)
            return
        }
        guard let room else { return }
        let player = playback.player
        if let item = player.currentItem {
            // Voices keep their pitch while the picture is nudged 3% faster or slower.
            if item.audioTimePitchAlgorithm != .timeDomain { item.audioTimePitchAlgorithm = .timeDomain }
            if item !== seenItem {
                seenItem = item
                seeking = false
                rules.reset()
                quietUntil = max(quietUntil, Self.now() + 1500)
            }
        }
        let state = room.state
        let orders = rules.tick(state: state, me: room.me, serverNowMs: party.serverNow(), localMs: Self.now(), player: facts(playback))
        lastBehind = orders.behind

        let wanted = Float(orders.rate ?? state.rate)
        if playback.clockface.rate != Float(state.rate) { playback.clockface.rate = Float(state.rate) }
        if orders.pause {
            quiet { player.pause() }
        }
        if let to = orders.seekTo { seek(playback, to: to) }
        if orders.play {
            quiet {
                player.defaultRate = Float(state.rate)
                // With enough loaded it starts on the moment; otherwise the player waits for more, and says so.
                if player.currentItem?.isPlaybackLikelyToKeepUp == true {
                    player.playImmediately(atRate: nudge(wanted, on: player.currentItem, room: Float(state.rate)))
                } else {
                    player.play()
                }
            }
        } else if orders.rate != nil, player.timeControlStatus != .paused {
            let rate = nudge(wanted, on: player.currentItem, room: Float(state.rate))
            if abs(player.rate - rate) > 0.001 {
                quiet { player.rate = rate }
            }
            if player.defaultRate != Float(state.rate) { player.defaultRate = Float(state.rate) }
        }
        waking?.cancel()
        if let wait = orders.againInMs {
            waking = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
        if let report = orders.report { party.report(report, rev: orders.rev) }
        log(orders, rate: player.rate)
    }

    /// A stream the player can't play a little faster or slower is left at the room's speed: a gap then waits
    /// for the three seconds that make it a jump.
    private func nudge(_ wanted: Float, on item: AVPlayerItem?, room: Float) -> Float {
        guard let item, wanted != room else { return wanted }
        if wanted > room, wanted > 1, !item.canPlayFastForward { return room }
        if wanted < room, wanted < 1, !item.canPlaySlowForward { return room }
        return wanted
    }

    /// To a place in the film, exactly. A stream the server is converting starts again from there, the way
    /// the player always goes past what it has so far.
    private func seek(_ playback: PlaybackModel, to film: Double) {
        guard let stream = playback.stream else { return }
        let known = playback.player.currentItem?.seekableTimeRanges.last?.timeRangeValue.end.seconds
        switch stream.seekPlan(toFilm: film, seekableEnd: known) {
        case .inPlayer(let at):
            seeking = true
            quietUntil = Self.now() + 700
            let item = playback.player.currentItem
            playback.player.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.playback?.player.currentItem === item else { return }
                    self.seeking = false
                    self.tick()
                }
            }
        case .reopen:
            own = true
            playback.seek(toFilm: film)
            own = false
        }
    }

    /// The gap, a line every five seconds while playing: how well this device keeps up, for anyone who asks.
    private func log(_ orders: SyncOrders, rate: Float) {
        guard let behind = orders.behind, Self.now() - logged >= 5000 else { return }
        logged = Self.now()
        ClientLog.shared.info("party", String(format: "Drift %+.3f s, rate %.2f, round trip %.0f ms.", -behind, rate, party.bestRttMs))
        // Far enough off that it had to jump: worth the server knowing, once a minute at most.
        if abs(behind) >= party.drift.seekSec {
            ClientLog.shared.warnSeldom("party", String(format: "Far out of step with the watch party: %+.0f ms (round trip %.0f ms)", -behind * 1000, party.bestRttMs),
                                        key: "drift", session: party.logSession)
        }
    }

    // MARK: What the viewer does

    private func notYours() {
        if Self.now() - toldOff > 8000 {
            toldOff = Self.now()
            hub?.say(SyncWords.hostOnly)
        }
    }

    private func send(_ type: String, positionSec: Double? = nil, rate: Double? = nil, ifSeq: Int? = nil) {
        Task { [weak self] in
            do {
                try await self?.party.command(type, positionSec: positionSec, rate: rate, ifSeq: ifSeq)
            } catch {
                // The end of the queue, said by every player at once, is nothing to tell anyone.
                if (error as? APIError)?.code != "end-of-queue" {
                    self?.hub?.say(SyncWords.refusal(error))
                    ClientLog.shared.warnSeldom("party", "A watch party command failed: \(type.prefix(40)): \((error as? APIError)?.status ?? 0)", session: self?.party.logSession)
                }
            }
        }
    }

    func steerToggle(_ playback: PlaybackModel) -> Bool {
        guard let room else { return false }
        guard room.canControl else { notYours(); return true }
        send(room.state.paused ? "play" : "pause")
        return true
    }

    func steerSeek(_ playback: PlaybackModel, to film: Double) -> Bool {
        if own { return false }
        guard let room else { return false }
        guard room.canControl else { notYours(); return true }
        send("seek", positionSec: max(0, film))
        return true
    }

    func steerSpeed(_ playback: PlaybackModel, _ rate: Float) -> Bool {
        guard let room else { return false }
        guard room.canControl else { notYours(); return true }
        send("rate", rate: Double(min(2, max(0.5, rate))))
        return true
    }

    func steerEnded(_ playback: PlaybackModel) -> Bool {
        guard let room else { return false }
        // Every player reaches the end together and says "next"; the seq lets one of them count.
        if room.canControl, room.hasNext { send("next", ifSeq: room.state.seq) }
        return true
    }

    func steerScrub(_ playback: PlaybackModel, from old: CMTime, to target: CMTime) -> CMTime {
        guard let room else { return target }
        guard room.canControl else { notYours(); return old }
        send("seek", positionSec: max(0, target.seconds + (playback.stream?.offset ?? 0)))
        return target
    }

    /// Play and pause reach the player from many places (the system's own controls on Apple TV, the lock
    /// screen, headphones), so they are noticed here rather than at each.
    private func statusChanged() {
        guard !stopped, let playback, let room else { return }
        let player = playback.player
        if player.currentItem !== seenItem || !loaded {
            // A stream that has just opened plays by itself: that isn't the viewer.
            quietUntil = max(quietUntil, Self.now() + 1500)
            tick()
            return
        }
        guard Self.now() >= quietUntil, playback.error.isEmpty, inFront || playback.inPictureInPicture else { return }
        let paused = player.timeControlStatus == .paused
        let state = room.state
        if paused, !state.paused, !state.waiting, !facts(playback).ended {
            if room.canControl { send("pause") } else { notYours(); tick() }
        } else if !paused, state.paused {
            if room.canControl { send("play") } else { notYours(); tick() }
        }
    }

    /// Behind other apps the system pauses the picture, which is this device going away, not a pause for everyone.
    private var inFront: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.applicationState == .active
        #else
        return true
        #endif
    }
}
