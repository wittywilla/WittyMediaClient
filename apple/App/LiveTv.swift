// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
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
    /// The programme being watched from its start, from the channel's archive (`tv-catchup`); nil when it's live.
    @Published private(set) var fromStart: GuideProgramme?
    /// On a library channel started over (server #648): the moment of the schedule this viewer's own stream started
    /// from, the programme and breaks it is in, the moment the picture is at, and the break it is in, if any.
    @Published private(set) var shiftFrom: Int64?
    @Published private(set) var timeline: Timeline?
    @Published private(set) var sched: Double?
    @Published private(set) var inBreak: Span?
    private var heardAt = Date()
    private var askedEnd: Int64 = 0
    private var pausedAt: (when: Date, sched: Double?)?

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
        guard shiftFrom != nil else { inBreak = nil; return }
        let s = schedNow()
        sched = s
        if let s { behind = max(0, liveNow() - s) }
        inBreak = TimeShiftRules.breakAt(timeline?.breaks, s)
        // Past the programme the timeline told of: what's on from there, and its breaks.
        if let s, let t = timeline, s >= Double(t.programme.end), askedEnd != t.programme.end {
            askedEnd = t.programme.end
            let channel = key, using = client
            Task {
                if let next = try? await using.timeline(channel, at: Int64(s)), channel == self.key, self.shiftFrom != nil { self.timeline = next }
            }
        }
    }

    /// The moment of the schedule the picture is at, from the stream's program date-times.
    func schedNow() -> Double? { player.currentItem?.currentDate()?.timeIntervalSince1970 }

    /// Where live is now, by the server's clock.
    private func liveNow() -> Double {
        guard let t = info?.serverTime, t > 0 else { return Date().timeIntervalSince1970 }
        return t + Date().timeIntervalSince(heardAt)
    }

    /// A library channel can go further back than its window, by starting over from there.
    private var canShift: Bool { TimeShiftRules.isLibrary(key) && (shiftFrom != nil || info?.startOver == true) }

    /// Whether Start over is offered now.
    var canStartOver: Bool { fromStart == nil && TimeShiftRules.canStartOver(info, now: liveNow()) }

    /// A moment of the schedule: within what's loaded, a seek; further back, this viewer's stream from there; at live,
    /// the channel everyone shares.
    /// False when there's nothing to do but stay within the window: live, on the channel everyone shares.
    @discardableResult
    func goTo(_ target: Double) -> Bool {
        guard let s = schedNow(), let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return false }
        let cur = CMTimeGetSeconds(player.currentTime())
        let live = liveNow()
        switch TimeShiftRules.plan(target, sched: s, cur: cur, low: CMTimeGetSeconds(range.start), high: CMTimeGetSeconds(CMTimeRangeGetEnd(range)),
                                   live: live, earliest: Double(timeline?.earliest ?? Int64(live - 6 * 3600))) {
        case .live:
            if shiftFrom == nil { return false }
            backToLive()
        case .within(let to): player.seek(to: CMTime(seconds: to, preferredTimescale: 600))
        case .restart(let at): restart(at: at)
        }
        return true
    }

    private func restart(at: Int64) {
        guard !key.isEmpty, let programme = fromStart ?? info?.now else { return }
        watchFromStart(key, programme, client: client, from: at)
    }

    /// The programme on now from its beginning: this viewer's own stream on a library channel, the archive on a tuner.
    func startOver() {
        guard canStartOver, let p = info?.now else { return }
        watchFromStart(key, p, client: client)
    }

    /// Past the whole break the picture is in, in one press. Only on a start-over stream: live keeps its breaks.
    func skipBreak() {
        guard let b = inBreak else { return }
        goTo(Double(b.end) + 0.5)
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
        fromStart = nil
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
        if let programme = fromStart {
            watchFromStart(was, programme, client: client)
            return
        }
        key = ""
        state = .idle
        watch(was, client: client)
    }

    /// A programme from its start, from what the channel's source keeps. The same viewer as live, so the live
    /// stream of the same channel is left first, and leaving this stops it as leaving live does.
    /// On a library channel it is this viewer's own stream of the channel from `from` (the programme's start if nil).
    func watchFromStart(_ key: String, _ programme: GuideProgramme, client: WittyClient, from: Int64? = nil) {
        self.client = client
        let was = self.key, wasShift = shiftFrom != nil
        let shift = TimeShiftRules.isLibrary(key) ? (from ?? programme.start) : nil
        self.key = key
        fromStart = programme
        shiftFrom = shift
        timeline = nil
        inBreak = nil
        sched = nil
        pausedAt = nil
        info = nil
        state = .tuning
        tuning?.cancel()
        player.replaceCurrentItem(with: nil)
        tuning = Task {
            // A start-over stream replaced by one from a new moment is replaced by the server itself.
            if !was.isEmpty, !(wasShift && shift != nil && was == key) { try? await client.leaveChannel(was, viewer: viewer, shift: wasShift) }
            await tune(key, from: programme)
        }
    }

    /// From watching from the start back to the channel as it is now.
    func backToLive() {
        guard fromStart != nil else { return }
        let channel = key, wasShift = shiftFrom != nil
        fromStart = nil
        shiftFrom = nil
        timeline = nil
        inBreak = nil
        info = nil
        state = .tuning
        tuning?.cancel()
        player.replaceCurrentItem(with: nil)
        tuning = Task {
            try? await client.leaveChannel(channel, viewer: viewer, shift: wasShift)
            await tune(channel)
        }
    }

    /// Nothing to show: the stream is left, and the server can stop it.
    func stop() {
        tuning?.cancel()
        tuning = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if !key.isEmpty { leave(key, shift: shiftFrom != nil) }
        key = ""
        fromStart = nil
        shiftFrom = nil
        timeline = nil
        inBreak = nil
        info = nil
        state = .idle
    }

    func pause() {
        if canShift, playing { pausedAt = (Date(), schedNow()) }
        player.pause()
    }

    func resume() {
        // Back after longer than the server keeps: from where it paused, not whatever is left.
        if let p = pausedAt, let at = p.sched, TimeShiftRules.restartAfterPause(pausedAt: p.when, now: Date(), bufferSec: info?.bufferSec ?? 300) {
            pausedAt = nil
            restart(at: Int64(at))
            return
        }
        pausedAt = nil
        if !key.isEmpty, player.currentItem != nil { player.play() }
    }

    /// Back within what the server keeps of the channel; on a library channel, further back by starting over.
    /// Never on: live TV doesn't skip ahead (#688), whatever asks (a key, a phone steering this TV).
    func seek(by seconds: Double) {
        guard seconds <= 0 else { return }
        if canShift, let s = schedNow() {
            let low = player.currentItem?.seekableTimeRanges.last.map { CMTimeGetSeconds($0.timeRangeValue.start) } ?? 0
            if shiftFrom != nil || CMTimeGetSeconds(player.currentTime()) + seconds < low, goTo(s + seconds) { return }
        }
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

    private func leave(_ key: String, shift: Bool = false) {
        let leaving = client, name = viewer
        Task { try? await leaving.leaveChannel(key, viewer: name, shift: shift) }
    }

    private func tune(_ key: String, from programme: GuideProgramme? = nil) async {
        for _ in 0..<20 {
            do {
                let tuned: Tuned
                let shift = shiftFrom
                if let programme, let shift {
                    tuned = try await client.startOver(key, from: shift, viewer: viewer)
                } else if let programme {
                    tuned = try await client.catchup(key, start: programme.start, end: programme.end, viewer: viewer)
                } else {
                    tuned = try await client.tune(key, viewer: viewer)
                }
                if Task.isCancelled || key != self.key || programme != fromStart || shift != shiftFrom { return }
                guard let address = tuned.streamUrl ?? tuned.url, let url = client.mediaURL(address) else {
                    state = .failed("The server sent an address that can't be used.")
                    return
                }
                info = tuned
                heardAt = Date()
                timeline = tuned.timeline
                player.replaceCurrentItem(with: AwayCookie.playerItem(url))
                player.play()
                return
            } catch let problem as APIError where problem.status == 503 {
                // Still starting: the server says to wait and ask again.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || key != self.key { return }
            } catch let problem as APIError where problem.status == 409 && shiftFrom != nil {
                // That moment is live now: the channel everyone shares.
                if !Task.isCancelled, key == self.key { backToLive() }
                return
            } catch {
                if Task.isCancelled || key != self.key { return }
                // Screen time is up: with the channel on the whole screen, the time-up screen says so.
                if Household.caught(error, needsScreen: true) { return }
                let status = (error as? APIError)?.status ?? 0
                if programme != nil, status == 404 {
                    state = .failed("This programme is no longer kept, so it can't be watched from the start.")
                } else {
                    // A tuner's own reason ("the stream answered 404 …") is said after what it means.
                    let reason = (error as? APIError)?.message ?? ""
                    state = .failed(reason.isEmpty ? "This channel can't be played right now."
                                    : reason.first?.isLowercase == true ? "This channel can't be played right now: \(reason)." : reason)
                }
                return
            }
        }
        state = .failed("This channel didn't start in time. Try it again in a moment.")
    }

    /// Asks again what's on, when the programme on the banner has ended.
    func refreshInfo() async {
        // From the start, what's on is the programme chosen: asking would start the live stream instead.
        guard fromStart == nil, !key.isEmpty, let fresh = try? await client.tune(key, viewer: viewer) else { return }
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
