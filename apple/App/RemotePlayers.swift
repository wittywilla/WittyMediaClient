// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import AVFoundation
import SwiftUI
import WittyKit

// What another device's commands do to this app's own players, and what this app says it is playing:
// docs/REMOTE-PROTOCOL.md, Commands and State. Video is the `PlaybackModel` of PlayerScreen.swift; music,
// audiobooks and podcasts are `Listening`. Whichever is playing is the one a command reaches: a film first,
// since a film stops the music.

extension RemoteHub: RemoteDevicePlayers {
    private var listening: Listening? { model?.listening }

    /// Where the device is in its own interface, in a word, for a remote that shows it.
    private var screen: String {
        guard let model else { return "home" }
        if model.showsPlayer || model.listening.screenShown { return "player" }
        if !model.path.isEmpty { return "browse" }
        switch model.tab {
        case .home: return "home"
        case .search: return "search"
        case .guide: return "guide"
        case .profile: return "settings"
        default: return "browse"
        }
    }

    func remoteState(_ abilities: RemoteCapabilities) -> RemoteState {
        if let playback = runningPlayback, playback.error.isEmpty, playback.item != nil {
            return videoState(playback, abilities)
        }
        if let listening, let now = listening.now, listening.problem.isEmpty {
            var state = RemoteState(status: listening.isLoading ? "buffering" : listening.isPlaying ? "playing" : "paused")
            state.itemId = now.item.id
            state.positionSec = listening.positionSec()
            state.durationSec = listening.durationSec()
            state.rate = Double(listening.speed)
            if abilities.has("volume") {
                state.volume = listening.sound.volume
                state.muted = listening.sound.muted
            }
            let queue = Array(listening.rows.map(\.track.item.id).prefix(200))
            if queue.count > 1, queue.indices.contains(listening.nowIndex) {
                state.queue = queue
                state.queueIndex = listening.nowIndex
            }
            state.screen = screen
            return state
        }
        return RemoteState(screen: screen)
    }

    private func videoState(_ playback: PlaybackModel, _ abilities: RemoteCapabilities) -> RemoteState {
        let player = playback.player
        let stream = playback.stream
        let status: String
        if stream == nil || player.currentItem == nil {
            status = "buffering"
        } else {
            switch player.timeControlStatus {
            case .playing: status = "playing"
            case .waitingToPlayAtSpecifiedRate: status = "buffering"
            default: status = "paused"
            }
        }
        var state = RemoteState(status: status)
        state.itemId = playback.id
        let at = player.currentTime().seconds
        state.positionSec = at.isFinite ? max(0, at + (stream?.offset ?? 0)) : 0
        state.durationSec = stream?.durationSec ?? playback.item?.runtimeSec
        let speed = player.timeControlStatus == .paused ? player.defaultRate : player.rate
        state.rate = speed > 0 ? (Double(speed) * 100).rounded() / 100 : 1
        if abilities.has("volume") {
            state.volume = Double(player.volume)
            state.muted = player.isMuted
        }
        if let stream {
            state.audio = stream.audioIndex.map(String.init)
            state.subtitle = RemoteTrack.subtitleId(stream.subtitleIndex)
            let sound = RemoteTrack.list(stream.audio), text = RemoteTrack.list(stream.subtitles)
            if !sound.isEmpty { state.audioTracks = sound }
            if !text.isEmpty { state.subtitleTracks = text }
        }
        if let list = model?.playingList, list.count > 1, let place = RemoteQueue.place(of: playback.id, in: list) {
            state.queue = Array(list.prefix(200))
            state.queueIndex = place
        }
        state.screen = screen
        return state
    }

    func remoteDo(_ action: RemoteAction) async throws {
        guard let model, let client else { throw RemoteRefusal(RemoteAction.cantDoThat) }
        if case .play(let queue, let index, let positionSec, let audio, let subtitle) = action {
            try await play(queue: queue, index: index, positionSec: positionSec, audio: audio, subtitle: subtitle, model: model, client: client)
            return
        }
        if case .navigate(let key) = action {
            try RemoteKeys.press(key, model: model, hub: self)
            return
        }
        if let playback = runningPlayback {
            try video(action, playback, model: model)
        } else if let listening, listening.now != nil {
            try music(action, listening)
        } else if action == .stop {
            // Nothing to stop is already stopped.
            return
        } else {
            throw RemoteRefusal(RemoteAction.nothingPlaying)
        }
    }

    // MARK: Play

    private func play(queue: [Int64], index: Int, positionSec: Double?, audio: Int?, subtitle: Int?, model: AppModel, client: WittyClient) async throws {
        let id = queue[index]
        let item: Item
        do {
            item = try await client.item(id)
        } catch {
            throw RemoteRefusal("That can't be opened on this device.")
        }
        if item.kind == "audio" {
            // The one asked for starts at once; the rest of its queue follows as each is looked up.
            let keeps = ["audiobooks", "podcasts"].contains(model.libraries.first { $0.id == item.libraryId }?.type ?? "")
            if runningPlayback != nil { closeVideo() }
            let start = positionSec ?? (keeps ? (item.resumeSeconds ?? 0) : 0)
            model.listening.play([item], start: ListeningStart(0, atSec: start), keepsPlace: keeps, client: client)
            if queue.count > 1 {
                Task { [weak self] in await self?.fillQueue(queue, index: index, first: item, keeps: keeps, client: client) }
            }
            return
        }
        guard item.isPlayable else { throw RemoteRefusal("This device can't play that kind of thing.") }
        model.playingList = queue.count > 1 ? queue : []
        openVideo(id, preset: PlaybackPreset(startSec: positionSec, audio: audio, subtitle: subtitle))
    }

    /// The rest of a music queue, looked up a few at a time. If the one that's playing has changed meanwhile,
    /// the person has moved on and the queue is left as they have it.
    private func fillQueue(_ queue: [Int64], index: Int, first: Item, keeps: Bool, client: WittyClient) async {
        var found: [Int64: Item] = [first.id: first]
        let wanted = queue.filter { $0 != first.id && $0 > 0 }
        for chunk in stride(from: 0, to: wanted.count, by: 8).map({ Array(wanted[$0..<min($0 + 8, wanted.count)]) }) {
            await withTaskGroup(of: Item?.self) { group in
                for id in chunk { group.addTask { try? await client.item(id) } }
                for await item in group { if let item { found[item.id] = item } }
            }
        }
        guard let listening, listening.now?.item.id == first.id, listening.rows.count == 1 else { return }
        let items = queue.compactMap { found[$0] }.filter { $0.kind == "audio" }
        guard items.count > 1, let at = items.firstIndex(where: { $0.id == first.id }) else { return }
        let playing = listening.isPlaying
        listening.play(items, start: ListeningStart(at, atSec: listening.positionSec()), keepsPlace: keeps, client: client)
        if !playing { listening.pause() }
    }

    // MARK: Video

    private func video(_ action: RemoteAction, _ playback: PlaybackModel, model: AppModel) throws {
        let player = playback.player
        let paused = player.timeControlStatus == .paused
        switch action {
        case .pause:
            if !paused { playback.togglePlay() }
        case .resume:
            if paused { playback.togglePlay() }
        case .stop:
            closeVideo()
        case .seekTo(let at):
            playback.seek(toFilm: at)
        case .seekBy(let by):
            let now = player.currentTime().seconds
            playback.seek(toFilm: max(0, (now.isFinite ? now : 0) + (playback.stream?.offset ?? 0) + by))
        case .next, .previous:
            let list = model.playingList
            let step = action == .next ? 1 : -1
            if let place = RemoteQueue.place(of: playback.id, in: list), let to = RemoteQueue.step(list, from: place, by: step) {
                openVideo(list[to], preset: PlaybackPreset(startSec: 0))
            } else if action == .next, let next = playback.stream?.nextId {
                openVideo(next, preset: nil)
            } else {
                throw RemoteRefusal("There's nothing more that way.")
            }
        case .volume(let level):
            player.volume = Float(level)
            if level > 0 { player.isMuted = false }
        case .mute(let muted):
            player.isMuted = muted
        case .audio(let index):
            guard playback.stream?.audio?.contains(where: { $0.index == index }) == true else { throw RemoteRefusal("That sound track isn't there.") }
            playback.choose(audio: index)
        case .subtitle(let index):
            guard index == -1 || playback.stream?.subtitles?.contains(where: { $0.index == index }) == true else {
                throw RemoteRefusal("Those subtitles aren't there.")
            }
            playback.choose(subtitle: index)
        case .rate(let rate):
            playback.setSpeed(Float(rate))
        case .play, .navigate, .refuse:
            throw RemoteRefusal(RemoteAction.cantDoThat)
        }
    }

    // MARK: Music, audiobooks and podcasts

    private func music(_ action: RemoteAction, _ listening: Listening) throws {
        switch action {
        case .pause: listening.pause()
        case .resume: listening.resume()
        case .stop:
            listening.screenShown = false
            listening.stop()
        case .seekTo(let at): listening.seek(to: at)
        case .seekBy(let by): listening.seek(by: by)
        case .next:
            guard listening.canGoNext else { throw RemoteRefusal("There's nothing more that way.") }
            listening.next()
        case .previous: listening.previous()
        case .volume(let level): listening.setSound { $0.volume = level; if level > 0 { $0.muted = false } }
        case .mute(let muted): listening.setSound { $0.muted = muted }
        case .rate(let rate): listening.choose(speed: Float(rate))
        case .audio: throw RemoteRefusal("This has only the one sound track.")
        case .subtitle: throw RemoteRefusal("This has no subtitles.")
        case .play, .navigate, .refuse: throw RemoteRefusal(RemoteAction.cantDoThat)
        }
    }
}

// MARK: - The remote's keys

/// The keys of a TV remote, pressed from another device: REMOTE-PROTOCOL.md, `navigate`. Only Apple TV
/// announces them. Back, Menu, Home and Play/Pause do what the remote's own do in this app. The arrows and
/// Select go to whatever has the highlight: see RemoteFocus.swift for how far that reaches.
@MainActor
enum RemoteKeys {
    static func press(_ key: String, model: AppModel, hub: RemoteHub) throws {
        switch key {
        case "back", "menu":
            if hub.playerSheet != nil {
                hub.playerSheet = nil
            } else if model.listening.screenShown {
                model.listening.screenShown = false
            } else if !model.path.isEmpty {
                model.path.removeLast()
            } else if model.tab != .home {
                model.tab = .home
            } else {
                throw RemoteRefusal("It's already at the top of Home.")
            }
        case "home":
            hub.playerSheet = nil
            model.listening.screenShown = false
            model.paths[model.tab] = []
            model.tab = .home
        case "playpause":
            if let playback = hub.runningPlayback {
                playback.togglePlay()
            } else if model.listening.now != nil {
                model.listening.toggle()
            } else {
                throw RemoteRefusal(RemoteAction.nothingPlaying)
            }
        case "left", "right", "up", "down", "select":
            if let playback = hub.runningPlayback, model.showsPlayer, hub.playerSheet == nil {
                // In the player the arrows are the remote's own: back and on ten seconds, and Select plays or pauses.
                let now = playback.player.currentTime().seconds + (playback.stream?.offset ?? 0)
                switch key {
                case "left": playback.seek(toFilm: max(0, now - 10))
                case "right": playback.seek(toFilm: now + 10)
                case "select": playback.togglePlay()
                default: throw RemoteRefusal("That key does nothing while a video plays.")
                }
                return
            }
            #if os(tvOS)
            try RemoteFocus.press(key)
            #else
            throw RemoteRefusal(RemoteAction.cantDoThat)
            #endif
        default:
            throw RemoteRefusal("This device doesn't have that key.")
        }
    }
}
