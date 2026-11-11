// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(iOS) || os(visionOS)
import AVFoundation
import Combine
import MediaToolbox
import SwiftUI
import WittyKit

// Karaoke with a song's real parts ("stems"): the voice on a slider over the music, instead of a guess at where the
// voice sits in the mix (docs/LYRICS-KARAOKE.md, "Stems"). The rules are WittyKit's MediaStems.swift.
//
// How it stays in time, and why it is built this way:
//
// - Every part goes into ONE player item, an AVComposition with a track per part and a volume per track. Tracks of
//   one composition are rendered by one audio pipeline against one timeline, so the parts are sample-exact with each
//   other through seeks, stalls and speed changes, by construction. That is the property that matters to the ear: a
//   voice 5 ms off its own backing is a different sound. An AVPlayer per part started with
//   `setRate(_:time:atHostTime:)` only promises "close", and each drifts on its own after a stall. AVAudioEngine
//   with player nodes is exact too, but wants whole files on the device first (or a decoder of our own) and would
//   mean a second audio path beside AVPlayer for everything else the app does: the lock screen, AirPlay, speed.
//   The composition streams each part over HTTP with byte ranges, as the song itself is.
// - The song's own player stays exactly what it was: it owns play and pause, seeks, speed, the queue, gapless
//   hand-over, Now Playing and the remote commands. While the parts play it is turned all the way down and is only
//   the clock. The parts' player is slaved to it: started at the song's time on the host clock with
//   `setRate(_:time:atHostTime:)`, and locked again whenever the two are more than 40 ms apart or the song stops,
//   seeks or changes speed (WittyKit's StemFollow). Song-to-parts only has to be good enough for the words on
//   screen, because the song is silent while the parts are heard.
// - Where the song itself has to be heard in the mix (there is music without the voice, but no voice alone, so the
//   voice is faded in by fading the song against its instrumental), the song's file goes into the composition as
//   one more track, for the same sample-exact reason, and the song's own player stays silent.
// - If the parts fall behind (a slow network), the song's own sound comes back until they are locked again, so
//   there is never silence: karaoke must not be the reason the music stops.
//
// The equaliser, the key and the volume leveling reach the parts through the same audio taps as any song.

@MainActor
final class StemMixer: ObservableObject {
    enum Stage: Equatable {
        /// Karaoke isn't open, or this isn't a song.
        case off
        /// Asking the server what the song has.
        case looking
        /// The parts are being opened.
        case loading
        /// The parts are what's heard.
        case playing
        /// The parts fell behind: the song's own sound is heard until they're back.
        case catchingUp
        /// The song has nothing to mix (it may be offered one), or what it has can't be used here.
        case none
    }

    @Published private(set) var stage: Stage = .off
    @Published private(set) var plan: StemPlan?
    @Published private(set) var offer: StemOffer = .none
    /// The owner's separator, for an administrator: whether it can be run on this song, and why not.
    @Published private(set) var separator: StemList.Way?
    /// Something is being made: its progress in words.
    @Published private(set) var making = ""
    @Published private(set) var problem = ""
    @Published private(set) var said = ""
    /// 0 is karaoke, 1 is the recording.
    @Published var voice = 1.0 {
        didSet { if voice != oldValue { applyLevels() } }
    }
    /// How far the parts are from the song, in thousandths of a second, when last looked at.
    @Published private(set) var apartMs = 0
    /// The song is being converted for this device, so it can't join the mix: the voice is on or off, not between.
    @Published private(set) var twoPositions = false

    /// The parts are playing or about to: the slider takes the place of "Voice lower" and "Voice lowest".
    var replacesVoiceChoice: Bool { plan != nil && stage != .off && stage != .none }

    private enum Role { case vocals, backing, song }
    private struct Input {
        let track: AVCompositionTrack
        let role: Role
        let tap: MTAudioProcessingTap?
    }

    private weak var listening: Listening?
    private var client: WittyClient?
    private var features: Set<String> = []
    private var isOpen = false
    private var trackId: Int?
    private var itemId: Int64 = 0
    private var parts: AVPlayer?
    private var inputs: [Input] = []
    private var songInMix = false
    private var locked = false
    private var lastLock = Date.distantPast
    private var goodLooks = 0
    private var badSince: Date?
    private var timer: Timer?
    private var loading: Task<Void, Never>?
    private var job: Task<Void, Never>?
    private var nowWatch: AnyCancellable?

    init(listening: Listening) {
        self.listening = listening
        // A new song must never start silent because the last one's parts were playing.
        nowWatch = listening.$now.map { $0?.id }.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.songChanged() }
        }
    }

    // MARK: What karaoke asks for

    /// Karaoke opened. `features` are the server's names for what it can do.
    func open(client: WittyClient, features: Set<String>) {
        self.client = client
        self.features = features
        guard features.contains(MediaFeature.stems) else { return }
        isOpen = true
        voice = 1
        trackId = nil
        timer?.invalidate()
        let ticking = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.look() }
        }
        RunLoop.main.add(ticking, forMode: .common)
        timer = ticking
        look()
    }

    /// Karaoke closed: the song sounds as it did.
    func close() {
        isOpen = false
        timer?.invalidate()
        timer = nil
        job?.cancel()
        job = nil
        dropParts()
        trackId = nil
        plan = nil
        offer = .none
        separator = nil
        making = ""
        problem = ""
        said = ""
        stage = .off
        voice = 1
    }

    /// "Make a karaoke version": the approximate instrumental, which anyone who can play the song may ask for.
    func makeKaraokeVersion() {
        guard let client else { return }
        let id = itemId
        run("Making a karaoke version") { try await client.makeApproximateStems(item: id) }
    }

    /// An administrator's: the owner's separator, for real parts.
    func separate() {
        guard let client else { return }
        let id = itemId
        run("Separating the song into stems") { try await client.separateStems(item: id) }
    }

    // MARK: Following the song

    private func songChanged() {
        guard isOpen else { return }
        dropParts()
        look()
    }

    private func dropParts() {
        loading?.cancel()
        loading = nil
        parts?.pause()
        parts?.replaceCurrentItem(with: nil)
        parts = nil
        inputs = []
        songInMix = false
        locked = false
        goodLooks = 0
        badSince = nil
        twoPositions = false
        if apartMs != 0 { apartMs = 0 }
        listening?.stemGain = 1
    }

    /// Ten times a second while karaoke is open: is this still the song, and are the parts with it?
    private func look() {
        guard isOpen, let listening else { return }
        let now = listening.now
        if now?.id != trackId {
            dropParts()
            trackId = now?.id
            job?.cancel()
            job = nil
            making = ""
            problem = ""
            said = ""
            guard let now, !now.keepsPlace else {
                plan = nil
                offer = .none
                stage = .off
                return
            }
            itemId = now.item.id
            find(item: now.item.id, track: now.id)
            return
        }
        guard let parts, let item = parts.currentItem, plan != nil else { return }
        let deck = listening.stemsDeck
        let offset = deck.stream?.offset ?? 0
        let songPlaying = deck.player.timeControlStatus == .playing
        let song = StemFollow.Clock(time: deck.player.currentTime().seconds + offset, rate: songPlaying ? Double(deck.player.rate) : 0)
        let mine = StemFollow.Clock(time: parts.currentTime().seconds, rate: Double(parts.rate))
        let ready = item.status == .readyToPlay && deck.player.currentItem?.status == .readyToPlay
        if item.status == .failed {
            // A part the server no longer has, or a token that ran out: ask again, as a new stream does.
            trackId = nil
            return
        }
        let apart = Int(((mine.time - song.time) * 1000).rounded())
        if ready, apart != apartMs, abs(apart) < 600_000 { apartMs = apart }
        switch StemFollow.order(song: song, parts: mine, partsReady: ready) {
        case .nothing:
            if ready, song.rate != 0 { goodLooks += 1 }
            badSince = nil
        case .hold(let at):
            parts.pause()
            if abs(mine.time - at) > StemFollow.pausedTolerance, Date().timeIntervalSince(lastLock) > 0.6 {
                lastLock = Date()
                parts.seek(to: CMTime(seconds: max(0, at), preferredTimescale: 48_000), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        case .lock(_, let rate):
            goodLooks = 0
            if badSince == nil { badSince = Date() }
            // A lock takes a moment to be heard. Asking again before it has is how two players chase each other.
            if Date().timeIntervalSince(lastLock) > 0.6 {
                lastLock = Date()
                lock(parts, to: deck.player, offset: offset, rate: rate)
            }
        }
        let wasLocked = locked
        if !locked, goodLooks >= 2 { locked = true }
        if locked, let badSince, Date().timeIntervalSince(badSince) > 1.2 { locked = false }
        if song.rate != 0 { stage = locked ? .playing : (wasLocked || stage == .catchingUp ? .catchingUp : .loading) }
        if locked != wasLocked, locked {
            // The parts replace the guess at where the voice is.
            listening.setSound { $0.vocalCut = 0 }
        }
        applyLevels()
    }

    /// The parts are set to be at the song's place at one moment of the host clock, a little ahead so the order
    /// arrives before the moment does. The two times are read one after the other on the same thread.
    private func lock(_ parts: AVPlayer, to song: AVPlayer, offset: Double, rate: Double) {
        let lead = 0.08
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let place = song.currentTime().seconds + offset
        guard place.isFinite else { return }
        let at = CMTime(seconds: max(0, place + lead * rate), preferredTimescale: 48_000)
        parts.setRate(Float(rate), time: at, atHostTime: CMTimeAdd(host, CMTime(seconds: lead, preferredTimescale: 1_000_000_000)))
    }

    /// How loud everything is right now: the parts by the slider when they're locked to the song, and the song's
    /// own sound when they aren't.
    private func applyLevels() {
        guard let listening else { return }
        guard let parts, let item = parts.currentItem, let plan, locked else {
            parts?.volume = 0
            listening.stemGain = 1
            return
        }
        let sound = listening.sound
        parts.volume = Float(sound.muted ? 0 : sound.volume)
        var level = voice
        if plan.mode == .blend, !songInMix { level = voice < 0.5 ? 0 : 1 }
        var levels = StemMix.levels(plan.mode, voice: level)
        if plan.mode == .blend, !songInMix {
            // The song can't be in the mix: its own player is the voice's "on", and the instrumental its "off".
            listening.stemGain = level >= 1 ? 1 : 0
            levels = StemMix.Levels(vocals: 0, backing: level >= 1 ? 0 : 1, song: 0)
        } else {
            listening.stemGain = 0
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = inputs.map { input in
            let parameters = AVMutableAudioMixInputParameters(track: input.track)
            parameters.audioTimePitchAlgorithm = .timeDomain
            parameters.audioTapProcessor = input.tap
            let volume: Float
            switch input.role {
            case .vocals: volume = levels.vocals
            case .backing: volume = levels.backing
            case .song: volume = levels.song
            }
            parameters.setVolume(volume, at: .zero)
            return parameters
        }
        if !sameVolumes(item.audioMix, mix) { item.audioMix = mix }
    }

    private var lastVolumes: [Float] = []
    /// A mix is only handed over when a volume changed: the player rebuilds its pipeline's volumes each time.
    private func sameVolumes(_ old: AVAudioMix?, _ new: AVMutableAudioMix) -> Bool {
        let volumes = new.inputParameters.map { parameters -> Float in
            var start: Float = 0, end: Float = 0
            var range = CMTimeRange()
            return parameters.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: &range) ? start : -1
        }
        defer { lastVolumes = volumes }
        return old != nil && volumes == lastVolumes
    }

    // MARK: Opening a song's parts

    private func find(item: Int64, track: Int) {
        guard let client else { return }
        stage = .looking
        plan = nil
        offer = .none
        loading?.cancel()
        loading = Task { [weak self] in
            let list = try? await client.stems(item: item)
            guard let self, !Task.isCancelled, self.trackId == track, self.isOpen else { return }
            let plan = StemPlan.plan(list?.stems ?? [])
            self.plan = plan
            self.separator = list?.separation?.external
            self.offer = StemOffer.of(list, plan: plan, featured: self.features.contains(MediaFeature.stemsApproximate))
            if case .making(let task) = self.offer { self.follow(task: task, doing: "Making a karaoke version") }
            guard let plan else {
                self.stage = .none
                return
            }
            self.stage = .loading
            do {
                try await self.build(plan, item: item, client: client, track: track)
            } catch {
                guard !Task.isCancelled, self.trackId == track else { return }
                self.dropParts()
                self.plan = nil
                self.stage = .none
                self.problem = plan.mode == .multitrack
                    ? "This song's stems file isn't one this device can take apart, so karaoke uses the song as it is."
                    : "This song's stems couldn't be opened, so karaoke uses the song as it is."
            }
        }
    }

    /// One player item holding every part, each with its own volume and sound tap.
    private func build(_ plan: StemPlan, item: Int64, client: WittyClient, track: Int) async throws {
        let token = try await client.streamToken(item: item).token
        let mix = AVMutableComposition()
        var made: [Input] = []
        // Exact times matter more here than a quick start: every part has to land on the same sample.
        let exact: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: true]

        func add(_ source: AVAssetTrack, role: Role) async throws {
            let range = try await source.load(.timeRange)
            guard let into = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw URLError(.cannotDecodeContentData) }
            try into.insertTimeRange(CMTimeRange(start: .zero, duration: range.duration), of: source, at: .zero)
            made.append(Input(track: into, role: role, tap: SoundEngine.shared.makeTap()?.tap))
        }

        func tracks(_ path: String, tokened: Bool) async throws -> [AVAssetTrack] {
            guard let url = tokened ? client.mediaURL(path) : client.tokenURL(path: path, token: token) else { throw URLError(.badURL) }
            return try await AVURLAsset(url: url, options: exact).loadTracks(withMediaType: .audio)
        }

        var songJoins = false
        switch plan.mode {
        case .parts:
            guard let vocals = plan.vocals, let voice = try await tracks(vocals.url, tokened: false).first else { throw URLError(.cannotDecodeContentData) }
            try await add(voice, role: .vocals)
            for part in plan.backing {
                guard let music = try await tracks(part.url, tokened: false).first else { throw URLError(.cannotDecodeContentData) }
                try await add(music, role: .backing)
            }
        case .blend:
            guard let backing = plan.backing.first, let music = try await tracks(backing.url, tokened: false).first else { throw URLError(.cannotDecodeContentData) }
            try await add(music, role: .backing)
            // The song as the server sends it untouched: the same samples the instrumental was made from.
            if let stream = listening?.stemsDeck.stream, stream.decision == "audio-direct", stream.offset == 0,
               let song = try? await tracks(stream.url, tokened: true).first {
                try await add(song, role: .song)
                songJoins = true
            }
        case .multitrack:
            // A Native Instruments stems file: the whole mix first, then four parts, the voice last by its
            // convention (drums, bass, the rest, vocals). A file of another shape isn't guessed at.
            guard let file = plan.file else { throw URLError(.cannotDecodeContentData) }
            let all = try await tracks(file.url, tokened: false)
            guard all.count == 5 else { throw URLError(.cannotDecodeContentData) }
            for (index, part) in all.dropFirst().enumerated() { try await add(part, role: index == 3 ? .vocals : .backing) }
        }
        guard !Task.isCancelled, trackId == track, isOpen else { return }
        let ready = AVPlayerItem(asset: mix)
        ready.audioTimePitchAlgorithm = .timeDomain
        let player = AVPlayer(playerItem: ready)
        // Its starts are given to it on the host clock, which is only allowed with this off.
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
        player.volume = 0
        inputs = made
        songInMix = songJoins
        twoPositions = plan.mode == .blend && !songJoins
        lastVolumes = []
        parts = player
    }

    // MARK: Things the server makes

    private func run(_ doing: String, start: @escaping () async throws -> MediaJobStart) {
        guard job == nil else { return }
        problem = ""
        said = ""
        making = "\(doing)…"
        job = Task { [weak self] in
            do {
                let started = try await start()
                guard let self, !Task.isCancelled else { return }
                if let task = started.task, !task.isEmpty {
                    self.job = nil
                    self.follow(task: task, doing: doing)
                } else {
                    // It was there already.
                    self.finished(words: "")
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.job = nil
                self.making = ""
                self.problem = plainWords(Problem.of(error))
            }
        }
    }

    /// The task to its end, then the song's parts are asked for again.
    private func follow(task: String, doing: String) {
        guard job == nil, let client else { return }
        let item = itemId
        making = "\(doing)…"
        job = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                var state = MediaJobState.of(task: task, in: try? await client.activity())
                if state == .unknown {
                    // This account can't see tasks. The song itself says whether it's still being made.
                    guard let list = try? await client.stems(item: item) else { continue }
                    let ways = [list.separation?.approximate?.task, list.separation?.external?.task]
                    if !ways.contains(task) {
                        state = StemPlan.plan(list.stems ?? []) != nil ? .done(result: "")
                            : .failed(words: "It couldn't be made. A song recorded in mono has no two channels to take from each other.")
                    }
                }
                guard let self, !Task.isCancelled, self.itemId == item else { return }
                switch state {
                case .done(let result): self.finished(words: result); return
                case .failed(let words): self.job = nil; self.making = ""; self.problem = words; return
                case .stopped: self.job = nil; self.making = ""; self.said = "It was stopped."; return
                case .waiting, .running, .unknown: self.making = state.progressWords(doing)
                }
            }
        }
    }

    private func finished(words: String) {
        job = nil
        making = ""
        said = words
        // Ask the song for its parts again: there are some now.
        dropParts()
        trackId = nil
        look()
    }
}

// MARK: - In karaoke

/// Karaoke's row for the song's parts: the voice on a slider when it has some, "Make a karaoke version" when it
/// has none and the server can make one, and what is going on in words.
struct KaraokeStemsBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @ObservedObject var stems: StemMixer

    private var isAdmin: Bool { model.user?.isAdmin == true }

    private var note: String {
        if !stems.problem.isEmpty { return stems.problem }
        if !stems.making.isEmpty { return stems.making }
        guard let plan = stems.plan, stems.replacesVoiceChoice else { return stems.said }
        if stems.stage == .catchingUp { return "The karaoke tracks are catching up; this is the song as it is." }
        if stems.twoPositions { return plan.approximate ? "\(plan.note) This song is being converted for this device, so the voice is on or off." : "This song is being converted for this device, so the voice is on or off." }
        return plan.note
    }

    private var canSeparate: Bool {
        isAdmin && model.has(MediaFeature.stemsSeparate) && stems.making.isEmpty && stems.stage != .off && stems.stage != .looking
            && (stems.plan == nil || stems.plan?.approximate == true)
    }

    var body: some View {
        VStack(spacing: 6) {
            if stems.replacesVoiceChoice {
                HStack(spacing: 10) {
                    Image(systemName: stems.voice <= 0.005 ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.white).frame(width: 24)
                        .accessibilityHidden(true)
                    Slider(value: $stems.voice, in: 0...1)
                        .tint(.white)
                        .accessibilityLabel("Singer's voice")
                        .accessibilityValue(StemMix.words(stems.voice))
                        .accessibilityIdentifier("stems-voice")
                    Text(StemMix.words(stems.twoPositions ? (stems.voice < 0.5 ? 0 : 1) : stems.voice))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white)
                        .frame(minWidth: 118, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Capsule().fill(NPInk.chip))
                .frame(maxWidth: 460)
            }
            HStack(spacing: 8) {
                if stems.offer == .make, stems.making.isEmpty {
                    Button("Make a karaoke version") { stems.makeKaraokeVersion() }
                        .buttonStyle(StemsChipStyle())
                        .accessibilityIdentifier("stems-make")
                }
                if canSeparate {
                    if stems.separator?.available == true {
                        Button("Separate into stems") { stems.separate() }
                            .buttonStyle(StemsChipStyle())
                            .accessibilityIdentifier("stems-separate")
                    }
                }
            }
            if !note.isEmpty {
                Text(note).font(.system(size: 13)).foregroundStyle(stems.problem.isEmpty ? NPInk.fg2 : Color(red: 1, green: 0.62, blue: 0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stems-note")
            }
            if canSeparate, stems.separator?.available != true, stems.plan == nil || stems.plan?.approximate == true {
                let why = StemOffer.separatorWords(stems.separator)
                if !why.isEmpty {
                    Text(why).font(.system(size: 12)).foregroundStyle(NPInk.fg3).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("stems-separator-note")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(syncProbe)
        .onAppear { stems.open(client: client, features: model.features) }
        .onDisappear { stems.close() }
    }

    /// For the UI tests in a debug build: where the mixer is, and how far the parts are from the song.
    @ViewBuilder private var syncProbe: some View {
        #if DEBUG
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel("Stems")
            .accessibilityValue(Text(verbatim: "\(String(describing: stems.stage)) \(stems.apartMs) ms"))
            .accessibilityIdentifier("stems-sync")
        #endif
    }
}

/// Hides the "Voice on, lower, lowest" choice while the song's real voice track is on its slider.
struct KaraokeVoiceChoice<Content: View>: View {
    @ObservedObject var stems: StemMixer
    @ViewBuilder var content: Content

    var body: some View {
        if !stems.replacesVoiceChoice { content }
    }
}

private struct StemsChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .background(Capsule().fill(configuration.isPressed ? NPInk.chip2 : NPInk.chip))
            .contentShape(Capsule())
    }
}
#endif
