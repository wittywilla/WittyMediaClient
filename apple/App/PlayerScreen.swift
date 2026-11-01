import AVKit
import Network
import SwiftUI
import VideoToolbox
import WittyKit

// The system's player does the seek bar, the remote, AirPlay, HDR and the screen reader. This drives
// it: asks the server what to play, saves progress, gets over failures and moves on to the next
// episode. The rules are in docs/CLIENT-API.md.
//
// Lock-screen and Control Center controls come from the system's player too. It keeps the now-playing
// information up to date itself (`updatesNowPlayingInfoCenter`, on by default) from `externalMetadata`,
// and answers the remote commands, so writing to MPNowPlayingInfoCenter here would only fight it.
@MainActor
final class PlaybackModel: ObservableObject {
    let player = AVPlayer()
    @Published var item: Item?
    @Published var stream: Playback?
    @Published var error = ""
    /// Inside the intro: where to skip to.
    @Published var introEnd: Double?
    /// The last thirty seconds, with something to go on to.
    @Published var offerNext = false
    /// Seconds left before the next episode starts, while counting down.
    @Published var countdown: Int?
    /// While the video floats over other apps, going to the background isn't a reason to pause.
    var inPictureInPicture = false
    var onFinished: (@MainActor (Int64?) -> Void)?

    private var clock = PlaybackClock()
    private var retry = RetryBudget()
    /// Goes up every time what's playing is replaced or stopped. Anything still running from
    /// before can tell it has been left behind, however long the network took to answer.
    private var generation = 0
    private var active = false
    private var everStarted = false
    private var playWhenReady = true
    private var waitingForNetwork = false

    private var client: WittyClient?
    private var id: Int64 = 0
    private var audio: Int?
    private var subtitle: Int?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var waitingObserver: NSKeyValueObservation?
    private var monitor: NWPathMonitor?
    private var failedItem: ObjectIdentifier?
    private var readyItem: ObjectIdentifier?
    private var countdownTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?

    /// What this device can do, asked each time as a TV's output or a phone's network can change.
    private var facts: DeviceFacts {
        let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        let av1 = VTIsHardwareDecodeSupported(CMVideoCodecType(0x6176_3031)) // 'av01'
        var hdr: [String] = []
        #if os(tvOS)
        let modes = AVPlayer.availableHDRModes
        if modes.contains(.hdr10) { hdr.append("hdr10") }
        if modes.contains(.hlg) { hdr.append("hlg") }
        if modes.contains(.dolbyVision) { hdr.append("dv5") }
        let kind = DeviceFacts.Kind.tv
        #elseif os(macOS)
        if AVPlayer.eligibleForHDRPlayback { hdr = ["hdr10", "hlg"] }
        let kind = DeviceFacts.Kind.computer
        #else
        if AVPlayer.eligibleForHDRPlayback { hdr = ["hdr10", "hlg"] }
        let kind: DeviceFacts.Kind = UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone
        #endif
        #if os(macOS)
        let channels: Int? = nil
        #else
        let channels: Int? = AVAudioSession.sharedInstance().maximumOutputNumberOfChannels
        #endif
        let path = monitor?.currentPath
        return DeviceFacts(kind: kind, hevc: hevc, av1: av1, hdr: hdr, audioChannels: channels,
                           costlyNetwork: path?.isExpensive == true || path?.isConstrained == true)
    }

    /// Safe to call again: coming back to a screen runs its task again, and it was either
    /// left running, or stopped and has to start from where it got to.
    func start(id: Int64, client: WittyClient, startOver: Bool) async {
        guard !active else { return }
        active = true
        generation += 1
        let run = generation
        self.id = id
        self.client = client
        error = ""
        clock = PlaybackClock()
        retry.reset()
        failedItem = nil
        readyItem = nil
        let beginning = startOver && !everStarted
        everStarted = true
        activateAudio()
        watchNetwork()
        watchPlayer()
        do {
            let fetched = try await client.item(id)
            guard run == generation else { return }
            item = fetched
        } catch {
            guard run == generation else { return }
            show(error)
            return
        }
        // Left out, startSec lets the server resume where the viewer stopped.
        await open(startSec: beginning ? 0 : nil)
    }

    func choose(audio: Int? = nil, subtitle: Int? = nil) {
        if let audio { self.audio = audio }
        if let subtitle { self.subtitle = subtitle }
        playWhenReady = player.timeControlStatus != .paused
        let at = clock.saveable ?? clock.filmSeconds
        Task { await open(startSec: at) }
    }

    /// After a failure: from the last good place, or wherever the server says if there wasn't one.
    func tryAgain() {
        error = ""
        waitingForNetwork = false
        retry.reset()
        failedItem = nil
        playWhenReady = true
        if item == nil, let client {
            active = false
            Task { await start(id: id, client: client, startOver: false) }
        } else {
            let at = clock.saveable
            Task { await open(startSec: at, replace: true) }
        }
    }

    private func open(startSec: Double?, replace: Bool = false) async {
        guard active, let client else { return }
        let run = generation
        clock.switching()
        let device = facts
        let request = PlaybackRequest(profile: device.profile, capabilities: device.capabilities, audio: audio, subtitle: subtitle, startSec: startSec)
        do {
            let answer = try await client.playback(id, request)
            guard run == generation else {
                // Left while it was being asked for. Don't leave the conversion running.
                endOnServer(answer.streamId)
                return
            }
            let before = stream
            stream = answer
            ClientLog.shared.session = answer.streamId ?? ""
            error = ""
            if replace || answer.url != before?.url {
                // The address already carries a short-lived stream token.
                guard let url = client.mediaURL(answer.url) else {
                    error = "The server sent an address that can't be used."
                    return
                }
                load(url, startAt: answer.startAtSec)
                if let old = before?.streamId, old != answer.streamId { endOnServer(old) }
            } else {
                // The same stream: the player can do this by itself.
                clock.ready()
                if let startSec, abs(startSec - clock.filmSeconds) > 2 {
                    _ = await player.seek(to: CMTime(seconds: max(0, startSec - answer.offset), preferredTimescale: 600))
                }
                await pickTracks(answer)
            }
        } catch {
            guard run == generation else { return }
            show(error)
        }
    }

    private func load(_ url: URL, startAt: Double?) {
        let next = AVPlayerItem(url: url)
        #if !os(macOS)
        addMetadata(to: next)
        #endif
        let itemId = ObjectIdentifier(next)
        failedItem = nil
        readyItem = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: next, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finished() }
        }
        failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: next, queue: .main) { [weak self] note in
            let problem = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in self?.failed(problem, item: itemId) }
        }
        // A stream that never starts only shows up here, not in the notification above.
        statusObserver = next.observe(\.status) { [weak self] observed, _ in
            let status = observed.status
            let problem = observed.error
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay: await self?.becameReady(itemId, startAt: startAt)
                case .failed: self?.failed(problem, item: itemId)
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: next)
    }

    /// A seek before this is ignored or lost, and a play before it plays from the wrong place.
    private func becameReady(_ itemId: ObjectIdentifier, startAt: Double?) async {
        guard active, readyItem != itemId, let current = player.currentItem, ObjectIdentifier(current) == itemId else { return }
        readyItem = itemId
        let run = generation
        if let startAt, startAt > 0 {
            _ = await player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        guard run == generation else { return }
        clock.ready()
        if playWhenReady { player.play() }
        playWhenReady = true
        if let stream { await pickTracks(stream) }
    }

    /// Sound and text tracks inside a stream are switched in the player, and nothing else knows
    /// which one the server chose. Picture subtitles and "off" are nothing to choose here.
    private func pickTracks(_ answer: Playback) async {
        guard let current = player.currentItem else { return }
        if let tracks = answer.audio, tracks.count > 1, let wanted = tracks.first(where: { $0.index == answer.audioIndex }),
           let group = try? await current.asset.loadMediaSelectionGroup(for: .audible) {
            select(wanted, among: tracks, in: group, on: current)
        }
        guard let group = try? await current.asset.loadMediaSelectionGroup(for: .legible) else { return }
        let inPlayer = answer.subtitleDelivery == "hls" || answer.subtitleDelivery == "embedded"
        if inPlayer, let tracks = answer.subtitles, let wanted = tracks.first(where: { $0.index == answer.subtitleIndex }) {
            select(wanted, among: tracks, in: group, on: current)
        } else if player.currentItem === current {
            current.select(nil, in: group)
        }
    }

    private func select(_ wanted: Track, among tracks: [Track], in group: AVMediaSelectionGroup, on current: AVPlayerItem) {
        guard player.currentItem === current else { return }
        let options = group.options.map { TrackOption(language: $0.extendedLanguageTag ?? $0.locale?.identifier, name: $0.displayName) }
        if let at = TrackMatch.pick(wanted: wanted, among: tracks, options: options) {
            current.select(group.options[at], in: group)
        }
    }

    /// An expired token or a stream that went away: ask again from the same place. One item can say
    /// it failed in both of the ways above, which counts as one. The detail is for the log only.
    private func failed(_ problem: Error?, item: ObjectIdentifier) {
        guard active, failedItem != item else { return }
        failedItem = item
        let detail = problem.map { problem -> String in
            let found = problem as NSError
            return "\(found.domain) \(found.code): \(found.localizedDescription)"
        } ?? "no details"
        guard let wait = retry.next() else {
            ClientLog.shared.report("error", "player", "Playback failed: \(detail)", session: stream?.streamId ?? "")
            noteConnection(problem)
            player.pause()
            error = "This stopped playing, and starting it again didn't work."
            return
        }
        ClientLog.shared.report("warn", "player", "Playback failed: \(detail)", session: stream?.streamId ?? "")
        let at = clock.saveable
        let run = generation
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self, run == self.generation else { return }
            await self.open(startSec: at, replace: true)
        }
    }

    /// Words for the screen, and a note to try again by itself when it's the network.
    private func show(_ problem: Error) {
        let trouble = Problem.of(problem)
        if trouble == .cancelled { return }
        // The screen says there's a problem, so nothing should carry on playing behind it.
        player.pause()
        waitingForNetwork = trouble.isConnection
        let words = plainWords(trouble)
        error = words.isEmpty ? "The server no longer accepts this sign-in." : words
    }

    private func noteConnection(_ problem: Error?) {
        if let problem, Problem.of(problem).isConnection { waitingForNetwork = true }
    }

    private func finished() {
        guard active, countdown == nil else { return }
        saveFinished()
        guard stream?.nextId != nil else { onFinished?(nil); return }
        startCountdown()
    }

    private func startCountdown() {
        countdown = 8
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while let left = self?.countdown, left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self?.countdown = left - 1
            }
            self?.onFinished?(self?.stream?.nextId)
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdown = nil
        onFinished?(nil)
    }

    /// Straight on to the next one, from the button or the end of the countdown.
    func playNext() {
        countdownTask?.cancel()
        countdown = nil
        onFinished?(stream?.nextId)
    }

    private func tick(_ inPlayer: Double) {
        guard active else { return }
        let playing = player.timeControlStatus == .playing
        if playing { retry.played(seconds: 1) }
        if clock.tick(playerSeconds: inPlayer, offset: stream?.offset ?? 0, playing: playing) { save() }
        // Only published when they change: these redraw the whole screen, once a second otherwise.
        let intro = stream?.intro
        let skip = intro.flatMap { clock.filmSeconds >= $0.startSec && clock.filmSeconds < $0.endSec - 1 ? $0.endSec : nil }
        if skip != introEnd { introEnd = skip }
        let near = stream?.nextId != nil && clock.nearEnd(duration: stream?.durationSec)
        if near != offerNext { offerNext = near }
    }

    /// Goes past what a growing stream has so far by opening a new one.
    func seek(toFilm target: Double) {
        guard let current = stream else { return }
        let known = player.currentItem?.seekableTimeRanges.last?.timeRangeValue.end.seconds
        switch current.seekPlan(toFilm: target, seekableEnd: known) {
        case .inPlayer(let at):
            player.seek(to: CMTime(seconds: at, preferredTimescale: 600))
        case .reopen(let at):
            Task { await open(startSec: at) }
        }
    }

    func skipIntro() {
        if let end = introEnd { seek(toFilm: end) }
    }

    /// In its own task: the last save happens as the screen is leaving.
    private func save() {
        guard let client, let at = clock.saveable, let duration = stream?.durationSec ?? item?.runtimeSec else { return }
        let id = id
        Task.detached { try? await client.saveProgress(id, positionSec: at, durationSec: duration) }
    }

    /// Past the end, which is what makes it count as watched.
    private func saveFinished() {
        guard let client, let duration = stream?.durationSec ?? item?.runtimeSec else { return }
        let id = id
        Task.detached { try? await client.saveProgress(id, positionSec: duration, durationSec: duration) }
    }

    private func endOnServer(_ streamId: String?) {
        guard let client, let streamId, !streamId.isEmpty else { return }
        Task.detached { try? await client.stopStream(streamId) }
    }

    /// Going to the background on a TV or a phone: keep the place, and stop, unless it's floating.
    func sceneChanged(_ phase: ScenePhase) {
        guard active, phase != .active else { return }
        clock.tick(playerSeconds: player.currentTime().seconds, offset: stream?.offset ?? 0, playing: false)
        save()
        #if !os(macOS)
        if phase == .background, !inPictureInPicture { player.pause() }
        #endif
    }

    func stop() {
        guard active else { return }
        clock.tick(playerSeconds: player.currentTime().seconds, offset: stream?.offset ?? 0, playing: false)
        save()
        generation += 1
        active = false
        player.pause()
        countdownTask?.cancel()
        retryTask?.cancel()
        stallTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        for observer in [endObserver, failObserver, interruptionObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        failObserver = nil
        interruptionObserver = nil
        statusObserver = nil
        waitingObserver = nil
        monitor?.cancel()
        monitor = nil
        ClientLog.shared.session = ""
        player.replaceCurrentItem(with: nil)
        deactivateAudio()
        // Stops the conversion straight away instead of letting it run on.
        endOnServer(stream?.streamId)
        stream = nil
        introEnd = nil
        offerNext = false
        countdown = nil
    }

    private func watchPlayer() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in self?.tick(seconds) }
        }
        // Stuck waiting for far longer than a slow network explains. The player would wait for ever.
        waitingObserver = player.observe(\.timeControlStatus) { [weak self] observed, _ in
            let waiting = observed.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor [weak self] in self?.waitingChanged(waiting) }
        }
    }

    private func waitingChanged(_ waiting: Bool) {
        stallTask?.cancel()
        stallTask = nil
        guard waiting, active, let current = player.currentItem else { return }
        let itemId = ObjectIdentifier(current)
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self?.failed(nil, item: itemId)
        }
    }

    /// Nothing is polled. When the network comes back after it was the reason for stopping, carry on.
    private func watchNetwork() {
        monitor?.cancel()
        let watching = NWPathMonitor()
        watching.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in self?.networkChanged(online: online) }
        }
        watching.start(queue: DispatchQueue.global(qos: .utility))
        monitor = watching
    }

    private func networkChanged(online: Bool) {
        guard online, waitingForNetwork, active else { return }
        tryAgain()
    }

    // MARK: Sound

    /// Without `.playback` nothing is heard with the silent switch on. A failure here is no reason
    /// not to try playing, so it goes in the log and carries on.
    private func activateAudio() {
        #if !os(macOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            ClientLog.shared.warn("player", "The audio session couldn't start: \((error as NSError).code)")
        }
        // The player pauses itself for a phone call. Only the system knows if it should carry on after.
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: raw) == .ended,
                  let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) else { return }
            Task { @MainActor [weak self] in self?.player.play() }
        }
        #endif
    }

    private func deactivateAudio() {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: What the system shows

    #if !os(macOS)
    /// For the info panel on Apple TV, the lock screen and Control Center.
    private func addMetadata(to next: AVPlayerItem) {
        guard let item else { return }
        func entry(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let made = AVMutableMetadataItem()
            made.identifier = identifier
            made.value = value as NSString
            made.extendedLanguageTag = "und"
            return made
        }
        var entries = [entry(.commonIdentifierTitle, item.showTitle?.isEmpty == false ? "\(item.showTitle ?? "") · \(item.episodeLabel)" : item.title)]
        if item.showTitle?.isEmpty == false { entries.append(entry(.iTunesMetadataTrackSubTitle, item.title)) }
        if let overview = item.overview, !overview.isEmpty { entries.append(entry(.commonIdentifierDescription, overview)) }
        next.externalMetadata = entries
        guard let client, let poster = client.posterURL(item) else { return }
        Task { [weak next] in
            // A picture is a nice extra, and has to be small enough to hand around.
            guard let data = try? await client.imageData(poster), data.count <= 2 * 1024 * 1024, let next else { return }
            let art = AVMutableMetadataItem()
            art.identifier = .commonIdentifierArtwork
            art.value = data as NSData
            art.dataType = (data.first == 0x89 ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String
            art.extendedLanguageTag = "und"
            next.externalMetadata.append(art)
        }
    }
    #endif
}

#if os(macOS)
private struct PlayerHost: NSViewRepresentable {
    @ObservedObject var playback: PlaybackModel
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = playback.player
        view.controlsStyle = .floating
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {}
}
#else
private struct PlayerHost: UIViewControllerRepresentable {
    @ObservedObject var playback: PlaybackModel

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let playback: PlaybackModel
        /// What the bar was last built from, so a menu that's open isn't rebuilt from under the person.
        var builtFrom = ""

        init(_ playback: PlaybackModel) { self.playback = playback }

        #if os(iOS)
        func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
            Task { @MainActor [playback] in playback.inPictureInPicture = true }
        }

        func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
            Task { @MainActor [playback] in playback.inPictureInPicture = false }
        }
        #endif
    }

    func makeCoordinator() -> Coordinator { Coordinator(playback) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = playback.player
        controller.delegate = context.coordinator
        #if os(tvOS)
        // Lets the TV switch to the film's frame rate and dynamic range. It may go dark for a moment.
        controller.appliesPreferredDisplayCriteriaAutomatically = true
        #else
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        #if os(tvOS)
        // On Apple TV the choices belong in the system player's own bar, where the remote reaches them.
        let stream = playback.stream
        let shape = "\(stream?.url ?? "")|\(stream?.audioIndex ?? -2)|\(stream?.subtitleIndex ?? -2)|\(playback.introEnd != nil)|\(playback.offerNext)"
        guard shape != context.coordinator.builtFrom else { return }
        context.coordinator.builtFrom = shape
        var menus: [UIMenuElement] = []
        if let audio = stream?.audio, audio.count > 1 {
            menus.append(UIMenu(title: "Audio", image: UIImage(systemName: "speaker.wave.2"), children: audio.map { track in
                UIAction(title: track.label, state: track.index == stream?.audioIndex ? .on : .off) { _ in playback.choose(audio: track.index) }
            }))
        }
        if let subtitles = stream?.subtitles, !subtitles.isEmpty {
            let off = UIAction(title: "Off", state: stream?.subtitleIndex == -1 ? .on : .off) { _ in playback.choose(subtitle: -1) }
            menus.append(UIMenu(title: "Subtitles", image: UIImage(systemName: "captions.bubble"), children: [off] + subtitles.map { track in
                UIAction(title: track.label, state: track.index == stream?.subtitleIndex ? .on : .off) { _ in playback.choose(subtitle: track.index) }
            }))
        }
        controller.transportBarCustomMenuItems = menus
        var actions: [UIAction] = []
        if playback.introEnd != nil { actions.append(UIAction(title: "Skip intro") { _ in playback.skipIntro() }) }
        if playback.offerNext { actions.append(UIAction(title: "Next episode") { _ in playback.playNext() }) }
        controller.contextualActions = actions
        #endif
    }
}
#endif

struct PlayerScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = PlaybackModel()
    let id: Int64
    let startOver: Bool
    @FocusState private var onCountdown: Bool

    private func leave() {
        if case .player? = model.path.last { model.path.removeLast() }
    }

    /// The film's end, the viewer's Cancel, or the next episode.
    private func moveOn(_ next: Int64?) {
        guard case .player? = model.path.last else { return }
        model.path.removeLast()
        // A list of tracks goes on by itself; the server only knows what follows an episode.
        if let then = next ?? ServerPages.next(after: id, in: model.playingList) { model.path.append(.player(then, startOver: false)) }
    }

    #if !os(tvOS)
    /// The system player has no place for these on iPhone, iPad and Mac.
    private var choices: some View {
        HStack(spacing: Tokens.Space.s3) {
            if playback.introEnd != nil {
                Button("Skip intro") { playback.skipIntro() }
            }
            if playback.offerNext {
                Button("Next episode") { playback.playNext() }
            }
            if let audio = playback.stream?.audio, audio.count > 1 {
                Menu("Audio") {
                    ForEach(uniqued(audio)) { track in
                        Button { playback.choose(audio: track.index) } label: {
                            if track.index == playback.stream?.audioIndex { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                        }
                    }
                }
                .accessibilityLabel("Sound track")
            }
            if let subtitles = playback.stream?.subtitles, !subtitles.isEmpty {
                Menu("Subtitles") {
                    Button { playback.choose(subtitle: -1) } label: {
                        if playback.stream?.subtitleIndex == -1 { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                    }
                    ForEach(uniqued(subtitles)) { track in
                        Button { playback.choose(subtitle: track.index) } label: {
                            if track.index == playback.stream?.subtitleIndex { Label(track.label, systemImage: "checkmark") } else { Text(track.label) }
                        }
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .padding()
    }
    #endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if playback.error.isEmpty {
                // No label of its own: the system's player already speaks for itself and its controls.
                PlayerHost(playback: playback).ignoresSafeArea()
            } else {
                // The player is always dark, whatever the theme. There's a way out here on any
                // device: on a TV there would otherwise be nothing to focus at all.
                ProblemView(words: playback.error, retry: { playback.tryAgain() }, back: leave)
                    .environment(\.colorScheme, .dark)
            }
            if let left = playback.countdown {
                VStack(spacing: Tokens.Space.s4) {
                    Text("\(say("nextEpisodeIn")) \(left)").font(.title2).foregroundStyle(.white)
                        .accessibilityAddTraits(.updatesFrequently)
                    Button("Play now") { playback.playNext() }.focused($onCountdown)
                    Button(say("cancel")) { playback.cancelCountdown() }
                }
                .padding(Tokens.Space.s8)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg).fill(Color.black.opacity(0.8)))
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .remoteSection()
            }
            #if !os(tvOS)
            choices
            #endif
        }
        #if os(tvOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(playback.item?.title ?? "")
        #endif
        .onChange(of: playback.countdown != nil) { counting in
            // Focus has to come out of the player, or the remote can't reach the buttons.
            if counting {
                onCountdown = true
                announce("\(say("nextEpisodeIn")) \(playback.countdown ?? 0)")
            }
        }
        .onChange(of: scenePhase) { playback.sceneChanged($0) }
        .task {
            playback.onFinished = { next in moveOn(next) }
            await playback.start(id: id, client: client, startOver: startOver)
        }
        .onDisappear { playback.stop() }
    }
}
