#if os(tvOS)
import AVKit
import SwiftUI
import WittyKit

// WittyTV's one player, as web/src/pages/tv/live.ts is the page's: the guide's preview and the
// channel on the whole screen are the same picture, so going from one to the other never tunes
// again. Moving on leaves the last channel at once, so the server stops a stream nobody watches.

@MainActor
final class LiveTv: ObservableObject {
    static let shared = LiveTv()

    enum State: Equatable {
        case idle, tuning, playing, failed(String)
    }

    let player = AVPlayer()
    /// The channel asked for, which may still be starting.
    @Published private(set) var key = ""
    @Published private(set) var state: State = .idle
    /// What the server said about it: what's on, what's next, its notices.
    @Published private(set) var info: Tuned?
    @Published private(set) var playing = false
    /// How far behind the live edge, in seconds, and whether there's room to go back.
    @Published private(set) var behind: Double = 0

    private var client = WittyClient(base: "")
    /// One name for this player, so the server can tell when it has gone.
    private let viewer = UUID().uuidString
    private var tuning: Task<Void, Never>?
    private var watchers: [NSKeyValueObservation] = []
    private var clock: Timer?

    private init() {
        player.automaticallyWaitsToMinimizeStalling = true
        watchers.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let on = player.timeControlStatus == .playing
            Task { @MainActor in
                guard let self else { return }
                self.playing = on
                if on, self.state == .tuning { self.state = .playing }
            }
        })
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.measure() }
        }
    }

    private func measure() {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { behind = 0; return }
        let end = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
        let at = CMTimeGetSeconds(player.currentTime())
        behind = end.isFinite && at.isFinite ? max(0, end - at) : 0
    }

    var muted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    /// Plays a channel, or carries on with it if it's the one already on.
    func watch(_ key: String, client: WittyClient) {
        self.client = client
        if key == self.key, state != .idle, !isFailed { return }
        if !self.key.isEmpty, self.key != key { leave(self.key) }
        self.key = key
        info = nil
        state = .tuning
        tuning?.cancel()
        player.replaceCurrentItem(with: nil)
        tuning = Task { await tune(key) }
    }

    var isFailed: Bool { if case .failed = state { return true } else { return false } }

    /// Tries the channel again after it failed.
    func retry() {
        let was = key
        key = ""
        state = .idle
        watch(was, client: client)
    }

    /// Nothing to show: the stream is left, and the server can stop it.
    func stop() {
        tuning?.cancel()
        tuning = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if !key.isEmpty { leave(key) }
        key = ""
        info = nil
        state = .idle
    }

    func pause() { player.pause() }
    func resume() { if !key.isEmpty, player.currentItem != nil { player.play() } }

    /// Back or on within what the server keeps of the channel.
    func seek(by seconds: Double) {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        let target = CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600))
        let low = range.start, high = CMTimeRangeGetEnd(range)
        player.seek(to: CMTimeMaximum(low, CMTimeMinimum(high, target)))
    }

    func goLive() {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        player.seek(to: CMTimeRangeGetEnd(range))
        player.play()
    }

    private func leave(_ key: String) {
        let leaving = client, name = viewer
        Task { try? await leaving.leaveChannel(key, viewer: name) }
    }

    private func tune(_ key: String) async {
        for _ in 0..<20 {
            do {
                let tuned = try await client.tune(key, viewer: viewer)
                if Task.isCancelled || key != self.key { return }
                guard let address = tuned.streamUrl ?? tuned.url, let url = client.mediaURL(address) else {
                    state = .failed("The server sent an address that can't be used.")
                    return
                }
                info = tuned
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
                return
            } catch let problem as APIError where problem.status == 503 {
                // Still starting: the server says to wait and ask again.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || key != self.key { return }
            } catch {
                if Task.isCancelled || key != self.key { return }
                state = .failed((error as? APIError)?.message ?? "This channel can't be played right now.")
                return
            }
        }
        state = .failed("This channel didn't start in time. Try it again in a moment.")
    }

    /// Asks again what's on, when the programme on the banner has ended.
    func refreshInfo() async {
        guard !key.isEmpty, let fresh = try? await client.tune(key, viewer: viewer) else { return }
        if fresh.key == nil || fresh.key == key { info = fresh }
    }
}

/// The picture alone, as big as it's given. A live channel has nothing to scrub, so the remote's
/// arrows are the screen's to use.
struct LivePicture: UIViewRepresentable {
    let player: AVPlayer
    var fill = false

    final class Picture: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Picture {
        let view = Picture()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Picture, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

/// The last channel watched, for the preview that shows it, and for Last.
enum LastChannel {
    private static let key = "wms.tv.last"

    static var current: String { UserDefaults.standard.string(forKey: key) ?? "" }
    static var before: String { UserDefaults.standard.string(forKey: key + ".before") ?? "" }

    static func remember(_ channel: String) {
        let was = current
        if !was.isEmpty, was != channel { UserDefaults.standard.set(was, forKey: key + ".before") }
        UserDefaults.standard.set(channel, forKey: key)
    }
}
#endif
