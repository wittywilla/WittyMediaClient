// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import AVFoundation
import CryptoKit
import Network
import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// A canvas: the short silent video the server has for a song, an album or a title, looped behind the music player,
// on an album's cover and behind a title's page (docs/MUSIC.md, "Canvas"). It is decoration and behaves like it:
//
// - Whether it plays at all is WittyKit's CanvasRules: not with Low Power Mode or Reduce Motion on, not on mobile or
//   Low Data networks, not away from the server's own network, not when switched off in You. Then the still
//   artwork that is already there is simply left showing.
// - It is fetched once into the caches folder and looped from there, so a loop costs no network and no stream
//   token to keep alive, and the join is seamless.
// - Its player has no sound at all (its sound tracks are turned off, and it is muted), is never the app's Now
//   Playing, never keeps the screen awake, and stops with the screen it is on. It doesn't touch the audio session,
//   so it can't pause the music or take the audio route.
// - One plays at a time: a page's canvas rests while the music player covers the page.

/// What the device and its network are like now, watched while any canvas is on screen and not otherwise.
@MainActor
final class CanvasWatch: ObservableObject {
    static let shared = CanvasWatch()
    static let wantedKey = "wms.canvas.off"

    @Published private(set) var conditions = CanvasConditions()
    /// Goes up when a canvas was made or removed here, so the pages showing one ask again.
    @Published var changes = 0

    private var monitor: NWPathMonitor?
    private var watchers = 0
    private var observers: [NSObjectProtocol] = []

    /// The person's own switch, kept on this device. On until turned off.
    var wanted: Bool {
        get { !UserDefaults.standard.bool(forKey: Self.wantedKey) }
        set {
            UserDefaults.standard.set(!newValue, forKey: Self.wantedKey)
            read()
        }
    }

    private init() { read() }

    private static var smallDevice: Bool {
        #if os(tvOS)
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        return CanvasRules.isSmallTV(model: model)
        #else
        return false
        #endif
    }

    /// The state that needs no watching to read.
    private func read(path: NWPath? = nil) {
        var next = conditions
        next.wanted = wanted
        next.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        #if canImport(UIKit)
        next.reduceMotion = UIAccessibility.isReduceMotionEnabled
        #endif
        next.smallDevice = Self.smallDevice
        if let path {
            next.expensiveNetwork = path.isExpensive
            next.constrainedNetwork = path.isConstrained
        }
        if next != conditions { conditions = next }
    }

    func watch() {
        watchers += 1
        guard watchers == 1 else { return }
        read()
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.read() }
        })
        #if canImport(UIKit)
        observers.append(centre.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.read() }
        })
        #endif
        let watching = NWPathMonitor()
        watching.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in self?.read(path: path) }
        }
        watching.start(queue: DispatchQueue.global(qos: .utility))
        monitor = watching
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        monitor?.cancel()
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    /// The conditions for a canvas of this server: one reached at a public address is "away".
    func conditions(server: String) -> CanvasConditions {
        var now = conditions
        if let host = URL(string: server)?.host {
            now.awayFromHome = !Address.isPrivateHost(host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host)
        }
        return now
    }
}

/// Canvases already fetched, in the caches folder (which the system may empty whenever it needs the room). A few
/// at most: the newest are kept.
actor CanvasStore {
    static let shared = CanvasStore()
    private static let keep = 6
    /// Uploads are held to 30 MB and files beside the media to 64 MB by the server; nothing bigger is kept.
    private static let largest = 64 * 1024 * 1024
    private var fetching: [String: Task<URL, Error>] = [:]

    private var folder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("wms-canvas", isDirectory: true)
    }

    /// The same canvas of the same server is the same file: its address carries a version that changes with it.
    private func name(server: String, path: String) -> String {
        let digest = SHA256.hash(data: Data("\(server)|\(path)".utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined() + ".mp4"
    }

    /// The canvas as a file on this device, fetched if it isn't here yet. `address` answers the full address
    /// with a fresh stream token, and is only asked when there's something to fetch.
    func file(server: String, path: String, address: @escaping @Sendable () async throws -> URL?) async throws -> URL {
        let local = folder.appendingPathComponent(name(server: server, path: path))
        if FileManager.default.fileExists(atPath: local.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: local.path)
            return local
        }
        let key = local.lastPathComponent
        if let going = fetching[key] { return try await going.value }
        let folder = folder
        let task = Task<URL, Error> {
            guard let remote = try await address() else { throw URLError(.badURL) }
            var request = URLRequest(url: remote, timeoutInterval: 60)
            // Never over mobile data or in Low Data Mode, whatever was decided a moment ago.
            request.allowsExpensiveNetworkAccess = false
            request.allowsConstrainedNetworkAccess = false
            let (fetched, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: fetched) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let size = (try? FileManager.default.attributesOfItem(atPath: fetched.path)[.size] as? Int) ?? 0
            guard size > 0, size <= Self.largest else { throw URLError(.dataLengthExceedsMaximum) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.moveItem(at: fetched, to: local)
            return local
        }
        fetching[key] = task
        defer { fetching[key] = nil }
        let got = try await task.value
        prune()
        return got
    }

    private func prune() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let byAge = files.sorted {
            let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in byAge.dropFirst(Self.keep) { try? FileManager.default.removeItem(at: old) }
    }
}

/// The looping picture itself: a layer with a queue player on a file. Nothing of it outlives the view.
private struct CanvasPlayerView: UIViewRepresentable {
    let file: URL
    let failed: () -> Void

    final class Surface: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var status: NSKeyValueObservation?
        /// The view went away while the file was still being looked at.
        var stopped = false

        func stop() {
            stopped = true
            status = nil
            looper?.disableLooping()
            looper = nil
            player?.pause()
            player?.removeAllItems()
            player = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Surface {
        let surface = Surface()
        surface.isUserInteractionEnabled = false
        surface.backgroundColor = .clear
        surface.playerLayer?.videoGravity = .resizeAspectFill
        let coordinator = context.coordinator
        let failed = failed
        let asset = AVURLAsset(url: file)
        Task { @MainActor [weak surface] in
            // A canvas is silent by definition. Only its picture is ever handed to the player, so a file that
            // has sound anyway has nothing to mix with the music or to send to any speaker.
            guard let picture = try? await asset.loadTracks(withMediaType: .video).first,
                  let range = try? await picture.load(.timeRange), range.duration.seconds > 0.2,
                  let turned = try? await picture.load(.preferredTransform) else { failed(); return }
            let silent = AVMutableComposition()
            guard let track = silent.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  (try? track.insertTimeRange(range, of: picture, at: .zero)) != nil else { failed(); return }
            track.preferredTransform = turned
            guard let surface, !coordinator.stopped else { return }
            let item = AVPlayerItem(asset: silent)
            // Decoration is never worth more than a moment's buffer.
            item.preferredForwardBufferDuration = 1
            let player = AVQueuePlayer()
            player.isMuted = true
            player.volume = 0
            player.allowsExternalPlayback = false
            player.preventsDisplaySleepDuringVideoPlayback = false
            if #available(iOS 15.0, tvOS 15.0, *) { player.audiovisualBackgroundPlaybackPolicy = .pauses }
            coordinator.player = player
            coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
            coordinator.status = coordinator.looper?.observe(\.status) { looper, _ in
                if looper.status == .failed { DispatchQueue.main.async { failed() } }
            }
            surface.playerLayer?.player = player
            player.play()
        }
        return surface
    }

    func updateUIView(_ surface: Surface, context: Context) {}

    static func dismantleUIView(_ surface: Surface, coordinator: Coordinator) {
        surface.playerLayer?.player = nil
        coordinator.stop()
    }
}

/// An item's canvas where there's room for one, or nothing at all: the still artwork under it is the fallback.
/// `active` is false while the place is covered or put away.
struct CanvasLayer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var watch = CanvasWatch.shared
    let item: Int64?
    var active = true
    /// A shade of this colour over the picture, so words on it stay readable.
    var shade: Color = .clear
    @State private var info: CanvasInfo?
    @State private var file: URL?
    @State private var shownFor: String = ""

    private var plays: String? {
        guard model.has(MediaFeature.canvas), active, scenePhase == .active,
              case .play(let path) = CanvasRules.decide(info, watch.conditions(server: client.base)) else { return nil }
        return path
    }

    var body: some View {
        ZStack {
            if let file, plays != nil, shownFor == "\(item ?? 0)" {
                CanvasPlayerView(file: file) { self.file = nil }
                    .id(file)
                    .overlay(shade)
                    .transition(.opacity)
                    .canvasAccessibility()
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.4), value: file)
        .onAppear { watch.watch() }
        .onDisappear { watch.stop() }
        .task(id: "\(item ?? 0)|\(model.has(MediaFeature.canvas))|\(watch.changes)") {
            info = nil
            file = nil
            guard let item, model.has(MediaFeature.canvas) else { return }
            let found = try? await client.canvas(item: item)
            if !Task.isCancelled { info = found }
        }
        .task(id: "\(item ?? 0)|\(plays ?? "")") {
            guard let item, let path = plays, let info else { return }
            let client = client
            let got = try? await CanvasStore.shared.file(server: client.base, path: path) { try await client.canvasURL(info, item: item) }
            guard !Task.isCancelled else { return }
            shownFor = "\(item)"
            file = got
        }
    }
}

private extension View {
    /// Decoration says nothing to a screen reader. A debug build names it, so the UI tests can see it play.
    @ViewBuilder func canvasAccessibility() -> some View {
        #if DEBUG
        accessibilityElement(children: .ignore).accessibilityLabel("Moving picture").accessibilityIdentifier("canvas-playing")
        #else
        accessibilityHidden(true)
        #endif
    }
}
