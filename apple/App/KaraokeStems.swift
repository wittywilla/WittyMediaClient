// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import AVFoundation
import SwiftUI
import WittyKit

// Karaoke from a song's separate parts, on a server that makes them (`karaoke-auto`): asks the server, waits while
// it prepares, fetches the parts, and plays them in place of the song with a slider for the voice. The rules are
// WittyKit's KaraokeStems.swift; the sound is StemPlayer.swift. The usual player goes on playing, silenced, so the
// place, the words, the lock screen and the remote all carry on as they were.

@MainActor
final class KaraokeStems: ObservableObject {
    @Published private(set) var machine = KaraokeMachine()
    @Published private(set) var levels = StemLevels()
    /// Karaoke is open on a song.
    @Published private(set) var isOpen = false
    /// What the parts being played are. Nil until they're fetched.
    @Published private(set) var loaded: KaraokeStatus?

    weak var listening: Listening?
    private var client: WittyClient?
    private var store: StemLevelsStore?
    private var player: StemPlayer?
    private var folder: URL?
    private var asking: Task<Void, Never>?
    private var fetching: Task<Void, Never>?
    /// The parts were out of step at the last look: twice running and they're started again.
    private var adrift = false

    private static let home = FileManager.default.temporaryDirectory.appendingPathComponent("karaoke-stems", isDirectory: true)

    init() {
        // Anything left from a time the app was closed mid-song.
        try? FileManager.default.removeItem(at: Self.home)
    }

    // MARK: What the screens ask for

    /// Karaoke opened on this song. Asked of the server once for each song.
    func open(song: Int64, client: WittyClient, profile: String) {
        self.client = client
        let store = StemLevelsStore(server: client.base, profile: profile)
        self.store = store
        if !isOpen { levels = store.load() }
        isOpen = true
        run(machine.open(song: song))
    }

    func close() {
        guard isOpen || machine.phase != .idle else { return }
        isOpen = false
        asking?.cancel()
        asking = nil
        run(machine.reset())
        stopParts()
    }

    /// The queue moved on: the same again for the next song, or nothing for a book or an empty queue.
    func songChanged(_ now: QueuedTrack?) {
        guard isOpen else { return }
        guard let now, !now.keepsPlace, client != nil else { close(); return }
        guard machine.song != now.item.id else { return }
        asking?.cancel()
        asking = nil
        stopParts()
        run(machine.open(song: now.item.id))
    }

    func setVocals(_ level: Double) { change { $0.setVocals(level) } }
    func setStem(_ id: String, _ level: Double) {
        change { id == StemMix.vocalsId ? $0.setVocals(level) : $0.setStem(id, level) }
    }
    func toggleSing() { change { $0.toggleSing() } }
    func reset() { change { $0.reset() } }

    private func change(_ how: (inout StemLevels) -> Void) {
        var next = levels
        how(&next)
        guard next != levels else { return }
        levels = next
        store?.save(next)
        if let loaded { player?.set(gains: StemMix.gains(loaded, next)) }
    }

    // MARK: Asking the server

    private func run(_ effects: [KaraokeMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .prepare(let after): ask(after: after, first: true)
            case .poll(let after): ask(after: after, first: false)
            case .load, .swap: fetch()
            case .stop: stopParts()
            }
        }
    }

    private func ask(after: Double, first: Bool) {
        asking?.cancel()
        guard let client, let song = machine.song else { return }
        asking = Task { [weak self] in
            if after > 0 { try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            do {
                let answer = try await (first ? client.prepareKaraoke(item: song) : client.karaoke(item: song))
                guard !Task.isCancelled, let self, self.machine.song == song else { return }
                self.run(self.machine.answered(answer))
            } catch {
                guard !Task.isCancelled, let self, self.machine.song == song else { return }
                // The server's own no is an answer; anything else is worth another try later.
                if let refusal = error as? APIError, (400..<500).contains(refusal.status), refusal.status != 408, refusal.status != 429 {
                    self.run(self.machine.answered(KaraokeStatus(state: "unavailable", message: refusal.message)))
                } else {
                    self.run(self.machine.networkFailed())
                }
            }
        }
    }

    // MARK: The parts

    /// Fetches the parts the machine now wants. What's playing carries on until the new ones are ready, then they
    /// take over from where the song is.
    private func fetch() {
        fetching?.cancel()
        guard let client, let status = machine.status, let song = machine.song else { return }
        let into = Self.home.appendingPathComponent(UUID().uuidString, isDirectory: true)
        fetching = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: into, withIntermediateDirectories: true)
                let files = try await StemFetcher.fetch(StemMix.played(status), client: client, into: into)
                try Task.checkCancellation()
                guard let self, self.machine.song == song, self.machine.wanted == status.version else {
                    try? FileManager.default.removeItem(at: into)
                    return
                }
                let next = try StemPlayer(files: files)
                let old = self.folder
                self.player?.shutdown()
                self.player = next
                self.folder = into
                self.loaded = status
                self.adrift = false
                if let old { try? FileManager.default.removeItem(at: old) }
                self.sync()
            } catch {
                try? FileManager.default.removeItem(at: into)
                guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled,
                      let self, self.machine.song == song else { return }
                ClientLog.shared.warn("karaoke", "the parts couldn't be played: \(error.localizedDescription)")
                self.run(self.machine.stemsFailed((error as? StemTrouble)?.words ?? ""))
            }
        }
    }

    /// Silence from the parts, their files gone, and the song itself heard again.
    private func stopParts() {
        fetching?.cancel()
        fetching = nil
        player?.shutdown()
        player = nil
        if loaded != nil { loaded = nil }
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        adrift = false
        listening?.stemsHeard = false
    }

    /// Keeps the parts with the song: called when it plays, pauses, moves, changes speed or volume, and once a
    /// second while it plays.
    func sync() {
        guard let listening, let player, let loaded else { return }
        // The parts follow the song's speed and its equaliser and levelling (StemPlayer.swift).
        player.set(gains: StemMix.gains(loaded, levels))
        player.set(output: listening.outputLevel, key: listening.sound.keyShift, speed: Double(listening.speed))
        if listening.trulyPlaying {
            let at = listening.positionSec()
            let off = player.position().map { abs($0 - at) }
            // A little out, seen twice running, or far out (the place was moved): start again from where the song is.
            let restart: Bool
            if let off {
                restart = off > 0.3 || (off > 0.08 && adrift)
                adrift = off > 0.08 && !restart
            } else {
                restart = true
                adrift = false
            }
            if restart {
                do {
                    try player.play(from: at)
                } catch {
                    ClientLog.shared.warnSeldom("karaoke", "the parts couldn't start: \(error.localizedDescription)", key: "start")
                    run(machine.stemsFailed())
                    return
                }
            }
        } else {
            player.halt()
            adrift = false
        }
        listening.stemsHeard = true
    }
}
