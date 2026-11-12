// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import AVFoundation
import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// Where the server's Remote Protocol and its watch parties meet this app: one object the model owns, which
// keeps this app announced as a device (RemoteDevice.swift), knows which player is the app's own at the
// moment (RemotePlayers.swift), and holds the watch party this device is in (WatchParty.swift). The wire
// format and every rule that needs no screen are in WittyKit (RemoteProtocol.swift, SyncPlay.swift), from the
// server's docs/REMOTE-PROTOCOL.md and docs/SYNCPLAY.md.
//
// The players know nothing of any of it. A `PlaybackModel` has a `steering` it asks before it plays, pauses,
// seeks or moves on, and a `preset` for where to start; that is all that was added to it.

/// Where to start a video and which tracks, when another device or a watch party decides.
struct PlaybackPreset: Equatable {
    var startSec: Double?
    var audio: Int?
    var subtitle: Int?
}

/// Something that steers a video player in the viewer's place: a watch party, whose room decides when
/// everyone's picture moves. Each answers true when it has taken the press, and the player then does nothing
/// itself.
@MainActor
protocol PlaybackSteering: AnyObject {
    func steerToggle(_ playback: PlaybackModel) -> Bool
    func steerSeek(_ playback: PlaybackModel, to film: Double) -> Bool
    func steerSpeed(_ playback: PlaybackModel, _ rate: Float) -> Bool
    func steerEnded(_ playback: PlaybackModel) -> Bool
    /// Apple TV's own scrubbing: where the player may go, in its own time.
    func steerScrub(_ playback: PlaybackModel, from old: CMTime, to target: CMTime) -> CMTime
}

/// What the player's own bar opens, on Apple TV, where the system's player has the screen.
enum TogetherSheet: Identifiable, Equatable {
    case playOn(PlayOnSource)
    case party

    var id: String {
        switch self {
        case .playOn: return "playOn"
        case .party: return "party"
        }
    }
}

@MainActor
final class RemoteHub: ObservableObject {
    static let switchKey = "remote.letOthersControl"

    /// This app as a device others can play on.
    let device = RemoteDeviceHost()
    /// The watch party this device is in, if any.
    let party = PartySession()
    /// The owner has remote control on, and this profile may use it. Until asked, nothing is offered.
    @Published private(set) var remoteOn = false
    /// What the server said of watch parties when last asked.
    @Published private(set) var partyInfo: SyncInfo?
    /// A line for the person that isn't a failure of the screen in front of them: "Now playing on Den".
    @Published var notice = ""
    /// Opened from the system player's bar on Apple TV.
    @Published var playerSheet: TogetherSheet?
    /// Opened from the music player's More, on a phone or tablet.
    @Published var musicSheet: TogetherSheet?
    /// "Let other devices control this one", on this device. On until turned off.
    @Published private(set) var letOthers = UserDefaults.standard.object(forKey: RemoteHub.switchKey) as? Bool ?? true

    private(set) weak var model: AppModel?
    private(set) var client: WittyClient?
    private var features: Set<String> = []
    private var inFront = true
    private var info: RemoteInfo?
    /// Where a video opened for a command or a party is to start: taken by the player as it's made.
    private var presets: [Int64: PlaybackPreset] = [:]
    /// The video player the app has now. A phone keeps it in the model; Apple TV's belongs to its screen.
    private(set) weak var playback: PlaybackModel?
    private var follower: PartyFollower?
    private var leaving: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var sceneObservers: [NSObjectProtocol] = []

    init() {
        watchScene()
        device.players = self
        party.onRoom = { [weak self] room in self?.partyChanged(room) }
        party.onOver = { [weak self] words in self?.partyOver(words) }
    }

    var hasRemote: Bool { features.contains(RemoteProtocol.feature) && remoteOn }
    var hasParties: Bool { features.contains(SyncPlay.feature) }
    /// This device's id as a device, while it is one and connected.
    var deviceId: String { device.online ? device.deviceId : "" }

    var platform: RemotePlatform {
        #if os(tvOS)
        return .tv
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone
        #else
        return .tablet
        #endif
    }

    // MARK: The session

    /// Called whenever who is signed in to what changes, and when the server's features are known.
    func session(model: AppModel, client: WittyClient, signedIn: Bool, features: Set<String>) {
        self.model = model
        let same = self.client?.base == client.base && self.client?.token == client.token
        var bye: Task<Void, Never>?
        if !same {
            if self.client != nil { bye = Task { await goodbye() } }
            self.client = signedIn ? client : nil
            remoteOn = false
            partyInfo = nil
            info = nil
        } else if !signedIn, self.client != nil {
            bye = Task { await goodbye() }
            self.client = nil
        } else if signedIn, self.client == nil {
            self.client = client
        }
        self.features = features
        guard signedIn, self.client != nil else { return }
        Task {
            // The last sign-in's goodbye first, or it would take this one's device with it.
            await bye?.value
            await learn()
        }
    }

    /// Asks the server what's on, and starts being a device if it is.
    private func learn() async {
        guard let client else { return }
        if features.contains(RemoteProtocol.feature), info == nil {
            async let asked = try? client.remoteInfo()
            async let allowed = client.remoteAllowed()
            let (found, may) = await (asked, allowed)
            guard self.client === client else { return }
            info = found
            remoteOn = (found?.enabled ?? false) && may
        }
        syncDevice()
        if features.contains(SyncPlay.feature), partyInfo == nil {
            let found = try? await client.syncInfo(device: party.device)
            guard self.client === client else { return }
            partyInfo = found
            party.use(client, info: found)
            if party.room == nil, found?.enabled == true { await party.comeBack(among: found?.rooms ?? []) }
        }
    }

    /// The server's word on watch parties, asked again as a sheet opens: the rooms change.
    func refreshParties() async -> SyncInfo? {
        guard let client, hasParties else { return nil }
        if let found = try? await client.syncInfo(device: party.device) {
            partyInfo = found
            party.use(client, info: found)
        }
        return partyInfo
    }

    func setLetOthers(_ on: Bool) {
        letOthers = on
        UserDefaults.standard.set(on, forKey: Self.switchKey)
        if on {
            syncDevice()
        } else {
            Task { await device.stop(forget: true) }
        }
    }

    /// iOS stops an app that's behind others unless it is playing, so the channel is only held there while
    /// something plays (music, or a picture floating over other apps). Otherwise it is closed, and the device
    /// shows as not connected for the half minute the server keeps it; coming back in front opens it again
    /// as the same device.
    private func scene(inFront front: Bool) {
        inFront = front
        syncDevice()
        // Back in front, a party's stream that the system closed is opened again by its own loop; the device's too.
    }

    private func watchScene() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        sceneObservers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scene(inFront: true) }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scene(inFront: false) }
            },
        ]
        #endif
    }

    private var playingBehind: Bool {
        guard let model else { return false }
        if model.listening.isPlaying { return true }
        if let playback, playback.isRunning, playback.inPictureInPicture { return true }
        return false
    }

    /// Starts or stops being a device, by everything that decides it.
    func syncDevice() {
        guard let client, let model, hasRemote, letOthers, let info else {
            if device.running { Task { await device.stop(forget: false) } }
            return
        }
        if DeviceLife.holdsChannel(inFront: inFront, playingBehind: playingBehind) {
            device.start(client: client, name: model.deviceName, platform: platform, limits: info.limits)
        } else if device.running {
            Task { await device.stop(forget: false) }
        }
    }

    /// Signing out or leaving the server: the device says goodbye and the party's seat is let go, before the
    /// sign-in ends.
    func goodbye() async {
        if let leaving {
            await leaving.value
            return
        }
        let task = Task { @MainActor in
            detachFollower()
            party.drop()
            await device.stop(forget: true)
        }
        leaving = task
        await task.value
        leaving = nil
    }

    // MARK: Words for the person

    func say(_ words: String) {
        guard !words.isEmpty else { return }
        notice = words
        announce(words)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = ""
        }
    }

    // MARK: The app's own video player

    /// Every video player the app makes passes through here before it starts: it takes the place a command or
    /// a party chose for it, and a party that is playing this very item starts steering it.
    func adopt(_ playback: PlaybackModel, id: Int64) {
        self.playback = playback
        if let preset = presets.removeValue(forKey: id) { playback.preset = preset }
        presets.removeAll()
        #if os(tvOS)
        playback.extraMenus = playerMenus(for: playback)
        #endif
        detachFollower()
        if let room = party.room, room.state.itemId == id, !room.blocked {
            if playback.preset == nil {
                playback.preset = PlaybackPreset(startSec: room.state.position(atServerMs: party.serverNow()))
            }
            let following = PartyFollower(playback: playback, party: party, hub: self)
            follower = following
            following.start()
        }
        device.reportSoon()
    }

    /// The video that is really playing or paused now, if any.
    var runningPlayback: PlaybackModel? {
        #if os(iOS) || os(visionOS)
        if let video = model?.video, video.isRunning { return video }
        return nil
        #else
        guard let playback, playback.isRunning else { return nil }
        return playback
        #endif
    }

    private func detachFollower() {
        follower?.stop()
        follower = nil
    }

    /// Opens a video in the app's own player, in place of whatever video is on.
    func openVideo(_ id: Int64, preset: PlaybackPreset?) {
        guard let model else { return }
        if let preset { presets[id] = preset }
        model.listening.screenShown = false
        if let running = runningPlayback, running.id == id {
            // The same thing again: the player that has it goes to the place asked for.
            presets[id] = nil
            if let at = preset?.startSec { running.seek(toFilm: at) }
            if preset?.audio != nil || preset?.subtitle != nil { running.choose(audio: preset?.audio, subtitle: preset?.subtitle) }
            #if os(iOS) || os(visionOS)
            model.expandVideo()
            #endif
            return
        }
        if model.showsPlayer { model.path.removeLast() }
        model.path.append(.player(id, startOver: false))
    }

    /// Stops the video and leaves its screen.
    func closeVideo() {
        guard let model else { return }
        #if os(iOS) || os(visionOS)
        model.closeVideo()
        #else
        if model.showsPlayer { model.path.removeLast() }
        #endif
    }

    #if os(tvOS)
    private func playerMenus(for playback: PlaybackModel) -> [UIMenuElement] {
        var menus: [UIMenuElement] = []
        if hasRemote {
            menus.append(UIAction(title: "Play on another device", image: UIImage(systemName: "tv.and.mediabox")) { [weak self, weak playback] _ in
                guard let self, let playback, let source = self.source(playing: playback) else { return }
                self.playerSheet = .playOn(source)
            })
        }
        if hasParties {
            menus.append(UIAction(title: "Watch party", image: UIImage(systemName: "person.2")) { [weak self] _ in
                self?.playerSheet = .party
            })
        }
        return menus
    }
    #endif

    // MARK: The watch party and the player

    private func partyChanged(_ room: SyncRoom) {
        if room.blocked {
            // Something this account may not see: the seat is kept, and nothing of it plays here.
            if let follower {
                follower.playback?.player.pause()
                detachFollower()
                say(SyncWords.blocked)
            }
            return
        }
        guard room.state.itemId > 0 else { return }
        if let follower, let following = follower.playback, following.isRunning, following.id == room.state.itemId {
            follower.roomChanged()
            return
        }
        // The party is on something this device hasn't open: open it where the party has got to.
        openVideo(room.state.itemId, preset: PlaybackPreset(startSec: room.state.position(atServerMs: party.serverNow())))
    }

    private func partyOver(_ words: String) {
        detachFollower()
        if let playback = runningPlayback {
            playback.player.rate = playback.player.timeControlStatus == .paused ? 0 : 1
            playback.player.defaultRate = 1
            playback.clockface.rate = 1
        }
        say(words)
    }

    /// The player a party was steering has closed. If nothing takes its place in a moment, that was leaving.
    func followerEnded(_ ended: PartyFollower) {
        guard follower === ended else { return }
        let room = party.room
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.follower === ended, let room, self.party.room?.id == room.id else { return }
            self.follower = nil
            self.party.leave()
            self.say("You left the watch party.")
        }
    }

    /// Whether the party is steering this player.
    func isFollowing(_ playback: PlaybackModel) -> Bool { follower?.playback === playback && party.room != nil }

    /// How far this player is from the room, for the room's panel.
    var driftSeconds: Double? { follower?.lastBehind }

    // MARK: What this device is playing, as something to hand over

    func source(playing playback: PlaybackModel) -> PlayOnSource? {
        guard let item = playback.item else { return nil }
        let list = model?.playingList ?? []
        let queue = list.contains(item.id) && list.count > 1 ? list : [item.id]
        return PlayOnSource(itemId: item.id, title: item.title, kind: item.kind ?? "video", queue: queue,
                            queueIndex: queue.firstIndex(of: item.id) ?? 0, playing: .video)
    }

    func sourcePlayingMusic() -> PlayOnSource? {
        guard let listening = model?.listening, let now = listening.now else { return nil }
        let queue = Array(listening.rows.map(\.track.item.id).prefix(200))
        let at = min(listening.nowIndex, max(0, queue.count - 1))
        let fits = queue.indices.contains(at) && queue[at] == now.item.id
        return PlayOnSource(itemId: now.item.id, title: now.title, kind: now.item.kind ?? "audio", queue: fits ? queue : [now.item.id],
                            queueIndex: fits ? at : 0, playing: .music)
    }
}

// MARK: - The root

/// Keeps the hub told who is signed in and whether the app is in front, and shows its one line of news over
/// whatever is on screen.
struct RemoteRoot: ViewModifier {
    @EnvironmentObject private var model: AppModel
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) { RemoteNotice(hub: model.remote) }
            .task(id: "\(model.client.base)|\(model.client.token.isEmpty)|\(model.stage == .browsing)|\(model.user?.id ?? 0)|\(model.features.count)") {
                model.remote.session(model: model, client: model.client, signedIn: model.stage == .browsing && !model.client.token.isEmpty,
                                     features: model.features)
                #if DEBUG
                // For the UI tests and for checking a screen on a simulator: `-WMCOpenItem <id>` opens that title's page.
                let open = UserDefaults.standard.integer(forKey: "WMCOpenItem")
                if open > 0, model.stage == .browsing, model.paths[.home]?.isEmpty ?? true { model.paths[.home] = [.item(Int64(open))] }
                #endif
            }
            // Music starting or stopping behind other apps changes whether the channel can be held.
            .onReceive(model.listening.$isPlaying) { _ in
                Task { @MainActor in model.remote.syncDevice() }
            }
    }
}

private struct RemoteNotice: View {
    @ObservedObject var hub: RemoteHub
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !hub.notice.isEmpty {
                Text(hub.notice)
                    .font(metrics.tv ? .body.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Tokens.Space.s5)
                    .padding(.vertical, Tokens.Space.s3)
                    .background(Capsule().fill(palette.card))
                    .overlay(Capsule().strokeBorder(palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    .padding(.horizontal, Tokens.Space.s6)
                    .padding(.top, metrics.tv ? Tokens.Space.s10 : Tokens.Space.s4)
                    .transition(.opacity)
                    .accessibilityIdentifier("remote-notice")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.appear), value: hub.notice)
        .allowsHitTesting(false)
    }
}
