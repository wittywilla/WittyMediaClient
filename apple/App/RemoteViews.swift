// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// This app as a controller of the server's Remote Protocol: the list of devices to play on, and a remote for
// one of them. docs/REMOTE-PROTOCOL.md, "Being a controller". The website's is web/src/remote/PlayOn.tsx; the
// words are its words. A device is only ever offered what its own `capabilities` list.

/// What is to be played on another device: something from a page, or what this device is playing now.
struct PlayOnSource: Equatable {
    enum Playing: Equatable { case video, music }

    let itemId: Int64
    let title: String
    /// The item's kind in the library: `video`, `audio`.
    let kind: String
    var queue: [Int64] = []
    var queueIndex = 0
    /// Set when it is playing here, and is to be handed over at the same place.
    var playing: Playing?

    init(itemId: Int64, title: String, kind: String, queue: [Int64] = [], queueIndex: Int = 0, playing: Playing? = nil) {
        self.itemId = itemId
        self.title = title
        self.kind = kind
        self.queue = queue
        self.queueIndex = queueIndex
        self.playing = playing
    }

    init(_ item: Item) {
        self.init(itemId: item.id, title: item.title, kind: item.kind ?? "video")
    }
}

// MARK: - Presenting

extension View {
    /// A sheet on a phone or tablet; the whole screen on Apple TV, where the remote's Back closes it.
    @ViewBuilder func togetherSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        #if os(tvOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }
}

/// What every sheet here stands in: the app's own colours and connection, a stack to go deeper in, and Done.
struct TogetherFrame<Content: View>: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                #if os(iOS) || os(visionOS)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", action: close).accessibilityIdentifier("together-done") }
                }
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .environmentObject(model)
        .environmentObject(model.listening)
        .environment(\.palette, model.palette)
        .environment(\.client, model.client)
        #if os(tvOS)
        .environment(\.metrics, Metrics.television)
        #endif
        .preferredColorScheme(model.scheme)
        .tint(model.palette.accentText)
    }
}

// MARK: - Watching the devices

/// The devices this account may control, kept up to date while a list or a remote is on screen and no longer.
@MainActor
final class RemoteWatcher: ObservableObject {
    @Published private(set) var devices: [RemoteDevice]?
    @Published private(set) var problem = ""
    /// The owner has turned remote control off.
    @Published private(set) var off = false
    private var clock = RemoteClock()

    private static func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    /// The server's time now, near enough for a progress bar.
    var serverNowMs: Double { clock.serverNow(localMs: Self.nowMs()) }

    func device(_ id: String) -> RemoteDevice? { devices?.first { $0.id == id } }

    /// Runs until the screen that asked goes away.
    func watch(_ client: WittyClient) async {
        var backoff = Backoff(first: 1.5, longest: 15)
        while !Task.isCancelled {
            do {
                for try await event in client.events(WittyClient.remoteEventsPath) {
                    switch event.name {
                    case "snapshot":
                        // Everything, whole: replace what there was.
                        guard let list = event.decoded(RemoteDeviceList.self) else { continue }
                        clock.learn(serverTimeMs: list.serverTimeMs, localMs: Self.nowMs())
                        devices = list.devices
                        problem = ""
                        backoff.reset()
                    case "device":
                        if let device = event.decoded(RemoteDevice.self) { devices = RemoteLook.merged(device, into: devices ?? []) }
                    case "gone":
                        struct Gone: Decodable { let id: String }
                        if let gone = event.decoded(Gone.self) { devices = devices?.filter { $0.id != gone.id } }
                    default:
                        break
                    }
                }
            } catch let refusal as APIError {
                if refusal.code == "disabled" {
                    off = true
                    return
                }
                if !Task.isCancelled { problem = RemoteLook.words(refusal) }
            } catch {
                if !Task.isCancelled, devices == nil { problem = plainWords(Problem.of(error)) }
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: UInt64(backoff.next() * 1_000_000_000))
        }
    }
}

// MARK: - The list

/// "Play on another device": every device signed in as this account (and those an administrator lets it
/// control), what each is doing, and a remote for each.
struct PlayOnView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let source: PlayOnSource?
    let close: () -> Void
    @StateObject private var watcher = RemoteWatcher()
    @State private var busy = ""
    @State private var problem = ""
    @State private var remote: String?

    private var hub: RemoteHub { model.remote }

    private var detail: String {
        guard let source else { return "Choose a device to see what it's playing and to control it." }
        return source.playing == nil ? "Start “\(source.title)” on another device." : "Move “\(source.title)” to another device, at the same place."
    }

    private func send(_ command: RemoteCommand, to device: RemoteDevice) async -> RemoteCommandAnswer? {
        busy = device.id
        problem = ""
        defer { busy = "" }
        do {
            return try await client.remoteSend(command, to: device.id)
        } catch {
            problem = RemoteLook.words(error)
            return nil
        }
    }

    /// Starts the source there, or hands over what's playing here.
    private func play(on device: RemoteDevice) async {
        guard let source else { return }
        let withQueue = source.queue.count > 1 && device.capabilities.has("queue")
        var command = withQueue ? RemoteCommand("play", queue: source.queue, queueIndex: source.queueIndex) : RemoteCommand("play", itemId: source.itemId)
        guard let playing = source.playing else {
            if await send(command, to: device) != nil {
                hub.say("Playing on \(device.name)")
                close()
            }
            return
        }
        // Handing over what's playing here. As a device, the server takes it from this one's own report and
        // stops it here; otherwise it's a play at this place, stopped by hand.
        let me = hub.deviceId
        var stopHere = true
        if !me.isEmpty {
            guard let answer = await send(RemoteCommand("cast", from: me), to: device) else { return }
            stopHere = answer.sourceStopped == false
        } else {
            switch playing {
            case .video:
                guard let playback = hub.runningPlayback else { return }
                let at = playback.player.currentTime().seconds
                command.positionSec = max(0, (at.isFinite ? at : 0) + (playback.stream?.offset ?? 0))
                command.audio = playback.stream?.audioIndex.map(String.init)
                command.subtitle = RemoteTrack.subtitleId(playback.stream?.subtitleIndex)
            case .music:
                command.positionSec = model.listening.positionSec()
            }
            guard await send(command, to: device) != nil else { return }
        }
        if stopHere {
            switch playing {
            case .video: hub.closeVideo()
            case .music:
                model.listening.screenShown = false
                model.listening.stop()
            }
        }
        hub.say("Now playing on \(device.name)")
        close()
    }

    @ViewBuilder private func row(_ device: RemoteDevice) -> some View {
        let canPlay = source.map { RemoteLook.canPlay(kind: $0.kind, on: device) } ?? false
        HStack(spacing: Tokens.Space.s3) {
            NavigationLink(value: device.id) {
                HStack(spacing: Tokens.Space.s3) {
                    IconTile(symbol: RemoteLook.symbol(device.kind), hex: "#7f46b8")
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Tokens.Space.s2) {
                            Text(device.name).font(metrics.tv ? .body : .subheadline).foregroundStyle(palette.text).lineLimit(1)
                            if !device.mine, !device.userName.isEmpty {
                                Text(device.userName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(palette.text)
                                    .padding(.horizontal, Tokens.Space.s2)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(palette.border))
                            }
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(RemoteLook.line(device, serverNowMs: watcher.serverNowMs))
                                .font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: Tokens.Space.s2)
                    if !canPlay {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(palette.textHint).accessibilityHidden(true)
                    }
                }
                .padding(.leading, Tokens.Space.s4)
                .padding(.trailing, canPlay ? 0 : Tokens.Space.s4)
                .frame(minHeight: metrics.tv ? 84 : 64)
                .contentShape(Rectangle())
            }
            .rowStyle()
            .disabled(!device.online)
            .accessibilityLabel("\(device.name), \(RemoteLook.line(device, serverNowMs: watcher.serverNowMs))")
            .accessibilityHint(device.online ? "Opens its remote" : "")
            .accessibilityIdentifier("device-\(device.name)")
            if canPlay {
                Button { Task { await play(on: device) } } label: {
                    BusyText(source?.playing == nil ? "Play here" : "Move here", busy: busy == device.id)
                }
                .action(primary: true)
                .disabled(!busy.isEmpty)
                .padding(.trailing, Tokens.Space.s4)
                .accessibilityLabel("\(source?.playing == nil ? "Play" : "Move it") on \(device.name)")
                .accessibilityIdentifier("play-on-\(device.name)")
            }
        }
        // Offline: listed, greyed, for the half minute the server keeps it.
        .opacity(device.online ? 1 : 0.5)
    }

    var body: some View {
        SettingsScreen(title: "Play on another device", detail: detail) {
            if watcher.off {
                EmptyState(icon: "tv.slash", title: "Playing on other devices is turned off",
                           detail: "An administrator can turn it on under Settings, Sharing & photos.")
            } else if let devices = watcher.devices {
                let listed = RemoteLook.listed(devices)
                if listed.isEmpty {
                    EmptyState(icon: "ipad.and.iphone", title: "No other devices right now",
                               detail: "Open the app on another device signed in as you, and it shows here.")
                } else {
                    if !problem.isEmpty { ProblemLine(problem) }
                    ListGroup(title: "Devices") {
                        ForEach(listed) { device in row(device) }
                    }
                }
            } else if !watcher.problem.isEmpty {
                ProblemLine(watcher.problem)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .navigationDestination(for: String.self) { id in
            RemoteView(deviceId: id, watcher: watcher, close: close)
        }
        .task { await watcher.watch(client) }
    }
}

// MARK: - The remote

/// A remote for one device: what it's playing, where it has got to, and every control it says it has.
struct RemoteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let deviceId: String
    @ObservedObject var watcher: RemoteWatcher
    let close: () -> Void
    @State private var problem = ""
    @State private var busy = false
    /// While the person drags the bar: where they have it, which wins over the device's own report.
    @State private var dragging: Double?
    @State private var titles: [Int64: String] = [:]
    @Namespace private var scope

    private var device: RemoteDevice? { watcher.device(deviceId) }
    private var hub: RemoteHub { model.remote }

    private func send(_ command: RemoteCommand) {
        guard let device else { return }
        problem = ""
        Task {
            do {
                try await client.remoteSend(command, to: device.id)
            } catch {
                problem = RemoteLook.words(error)
            }
        }
    }

    /// Brings what that device is playing to this one, at the same place, and stops it there.
    private func bringHere(_ device: RemoteDevice) async {
        guard let id = device.state.itemId else { return }
        busy = true
        problem = ""
        defer { busy = false }
        do {
            let me = hub.deviceId
            if !me.isEmpty {
                // As a device itself, this one is cast to like any other: the server works out the place.
                let answer = try await client.remoteSend(RemoteCommand("cast", from: device.id), to: me)
                if answer.sourceStopped == false { _ = try? await client.remoteSend(RemoteCommand("stop"), to: device.id) }
            } else {
                let at = RemoteLook.position(device.state, stateAt: device.stateAt, serverNowMs: watcher.serverNowMs)
                let queue = (device.state.queue ?? []).filter { $0 > 0 }
                let place = queue.firstIndex(of: id)
                try await hub.remoteDo(.play(queue: place == nil ? [id] : queue, index: place ?? 0, positionSec: at,
                                             audio: RemoteAction.trackIndex(device.state.audio).flatMap { $0 >= 0 ? $0 : nil },
                                             subtitle: RemoteAction.trackIndex(device.state.subtitle)))
                _ = try? await client.remoteSend(RemoteCommand("stop"), to: device.id)
            }
            close()
        } catch let refusal as RemoteRefusal {
            problem = refusal.words
        } catch {
            problem = RemoteLook.words(error)
        }
    }

    // MARK: Parts

    @ViewBuilder private func heading(_ device: RemoteDevice) -> some View {
        let state = device.state
        HStack(alignment: .top, spacing: Tokens.Space.s4) {
            if let id = state.itemId, !device.hidden, !state.isIdle {
                ArtImage(url: client.posterURL(id: id), width: metrics.tv ? 200 : 96, placeholder: device.title)
                    .frame(width: metrics.tv ? 200 : 96, height: metrics.tv ? 300 : 144)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(state.isIdle ? "Nothing playing" : device.hidden ? "Playing something" : (device.title.isEmpty ? "Playing" : device.title))
                    .font(.wmSection).foregroundStyle(palette.text).lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("remote-title")
                Secondary(statusLine(device))
                if device.hidden {
                    Secondary("It's playing something this account can't see, so only what's shown here can be controlled.")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statusLine(_ device: RemoteDevice) -> String {
        var parts = [device.name]
        if !device.mine, !device.userName.isEmpty { parts.append(device.userName) }
        if !device.online { parts.append("Not connected") } else {
            switch device.state.status {
            case "playing": parts.append("Playing")
            case "paused": parts.append("Paused")
            case "buffering": parts.append("Buffering")
            default: break
            }
        }
        return parts.factsLine()
    }

    @ViewBuilder private func scrubber(_ device: RemoteDevice) -> some View {
        let state = device.state
        let length = state.durationSec ?? 0
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let at = dragging ?? RemoteLook.position(state, stateAt: device.stateAt, serverNowMs: watcher.serverNowMs)
            VStack(spacing: Tokens.Space.s1) {
                #if os(tvOS)
                ProgressStrip(fraction: length > 0 ? at / length : 0, track: palette.border)
                #else
                if device.capabilities.has("seek"), length > 0 {
                    Slider(value: Binding(get: { min(at, length) }, set: { dragging = $0 }), in: 0...length) { editing in
                        if !editing, let to = dragging {
                            send(RemoteCommand("seek", positionSec: to))
                            // The device's next report takes over from where the finger left it.
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                dragging = nil
                            }
                        }
                    }
                    .tint(palette.accent)
                    .accessibilityLabel("Position")
                    .accessibilityValue("\(PlayerTime.format(at)) of \(PlayerTime.format(length))")
                    .accessibilityIdentifier("remote-scrubber")
                } else {
                    ProgressStrip(fraction: length > 0 ? at / length : 0, track: palette.border)
                }
                #endif
                HStack {
                    Text(PlayerTime.format(at)).accessibilityIdentifier("remote-position")
                    Spacer()
                    if length > 0 { Text(PlayerTime.format(length)) }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func key(_ symbol: String, _ label: String, primary: Bool = false, id: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.tv ? 30 : 20, weight: .semibold))
                .frame(minWidth: metrics.tv ? 72 : 36, minHeight: metrics.tv ? 44 : 28)
        }
        .action(primary: primary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id.isEmpty ? "remote-\(label)" : id)
    }

    @ViewBuilder private func transport(_ device: RemoteDevice) -> some View {
        let has = device.capabilities.has
        let state = device.state
        HStack(spacing: Tokens.Space.s2) {
            if has("queue"), (state.queue?.count ?? 0) > 1 { key("backward.end.fill", "Previous") { send(RemoteCommand("previous")) } }
            if has("seek") { key("gobackward.10", "Back 10 seconds") { send(RemoteCommand("seek", bySec: -10)) } }
            if state.status == "paused" {
                key("play.fill", "Play", primary: true) { send(RemoteCommand("resume")) }.firstFocus(in: scope)
            } else {
                key("pause.fill", "Pause", primary: true) { send(RemoteCommand("pause")) }.firstFocus(in: scope)
            }
            if has("seek") { key("goforward.10", "Forward 10 seconds") { send(RemoteCommand("seek", bySec: 10)) } }
            if has("queue"), (state.queue?.count ?? 0) > 1 { key("forward.end.fill", "Next") { send(RemoteCommand("next")) } }
            key("stop.fill", "Stop") { send(RemoteCommand("stop")) }
        }
        .frame(maxWidth: .infinity)
        .remoteSection()
    }

    @ViewBuilder private func volume(_ device: RemoteDevice, level: Double) -> some View {
        let muted = device.state.muted == true
        HStack(spacing: Tokens.Space.s3) {
            key(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", muted ? "Unmute" : "Mute") { send(RemoteCommand("mute", muted: !muted)) }
            #if os(tvOS)
            key("minus", "Quieter") { send(RemoteCommand("volume", level: max(0, level - 0.1))) }
            Text("\(Int((level * 100).rounded()))%").font(.body.monospacedDigit()).foregroundStyle(palette.text).frame(minWidth: 90)
            key("plus", "Louder") { send(RemoteCommand("volume", level: min(1, level + 0.1))) }
            #else
            VolumeSlider(level: level) { send(RemoteCommand("volume", level: $0)) }
            #endif
        }
        .remoteSection()
    }

    private func choice(_ title: String, _ symbol: String, _ tracks: [RemoteTrack], chosen: String?, off: Bool, pick: @escaping (String) -> Void) -> some View {
        Menu {
            if off {
                Button { pick("off") } label: { if chosen == "off" { Label("Off", systemImage: "checkmark") } else { Text("Off") } }
            }
            ForEach(tracks) { track in
                Button { pick(track.id) } label: {
                    if track.id == chosen { Label(track.shownName, systemImage: "checkmark") } else { Text(track.shownName) }
                }
            }
        } label: {
            Label(title, systemImage: symbol)
        }
        .action()
        .accessibilityIdentifier("remote-\(title)")
    }

    @ViewBuilder private func choices(_ device: RemoteDevice) -> some View {
        let has = device.capabilities.has
        let state = device.state
        let sound = state.audioTracks ?? [], text = state.subtitleTracks ?? []
        if (has("audio") && sound.count > 1) || (has("subtitles") && !text.isEmpty) || has("rate") {
            FlowLayout(spacing: Tokens.Space.s2) {
                if has("audio"), sound.count > 1 {
                    choice("Audio", "music.note", sound, chosen: state.audio, off: false) { send(RemoteCommand("audio", audio: $0)) }
                }
                if has("subtitles"), !text.isEmpty {
                    choice("Subtitles", "captions.bubble", text, chosen: state.subtitle, off: true) { send(RemoteCommand("subtitle", subtitle: $0)) }
                }
                if has("rate") {
                    Menu {
                        ForEach(RemoteLook.rates, id: \.self) { rate in
                            Button { send(RemoteCommand("rate", rate: rate)) } label: {
                                if abs((state.rate ?? 1) - rate) < 0.01 { Label(PlayerSpeeds.words(rate), systemImage: "checkmark") } else { Text(PlayerSpeeds.words(rate)) }
                            }
                        }
                    } label: {
                        Label("Speed \(PlayerSpeeds.button(state.rate ?? 1))", systemImage: "speedometer")
                    }
                    .action()
                    .accessibilityIdentifier("remote-Speed")
                }
            }
            .remoteSection()
        }
    }

    @ViewBuilder private func queue(_ device: RemoteDevice, _ list: [Int64]) -> some View {
        ListGroup(title: "Queue") {
            ForEach(Array(list.enumerated()), id: \.offset) { place, id in
                let now = place == device.state.queueIndex
                Button {
                    if id > 0, !now { send(RemoteCommand("play", queue: list, queueIndex: place)) }
                } label: {
                    HStack(spacing: Tokens.Space.s3) {
                        Text("\(place + 1)").font(.caption.monospacedDigit()).foregroundStyle(palette.textHint).frame(width: 28, alignment: .trailing)
                        // An entry this account may not see is sent as 0: it has a place and no name.
                        Text(id > 0 ? (titles[id] ?? "…") : "Something you can't see")
                            .font(metrics.tv ? .body : .subheadline)
                            .foregroundStyle(now ? palette.accentText : palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if now { Image(systemName: "speaker.wave.2.fill").font(.footnote).foregroundStyle(palette.accentText).accessibilityLabel("Playing now") }
                    }
                    .padding(.horizontal, Tokens.Space.s4)
                    .frame(minHeight: metrics.tv ? 64 : 48)
                    .contentShape(Rectangle())
                }
                .rowStyle()
                .disabled(id <= 0 || list.contains(0))
                .task(id: id) {
                    guard id > 0, titles[id] == nil, let item = try? await client.item(id) else { return }
                    titles[id] = item.title
                }
            }
        }
    }

    var body: some View {
        SettingsScreen(title: device?.name ?? "Remote") {
            if let device {
                heading(device)
                if !problem.isEmpty { ProblemLine(problem) }
                if !device.online {
                    Secondary("This device isn't connected. It comes back by itself when its app is open again.")
                } else {
                    if !device.state.isIdle {
                        if !device.hidden { scrubber(device) }
                        transport(device)
                    }
                    if device.capabilities.has("volume"), let level = device.state.volume { volume(device, level: level) }
                    if !device.state.isIdle, !device.hidden { choices(device) }
                    if device.capabilities.has("navigate") { RemotePad { send(RemoteCommand("navigate", key: $0)) } }
                    if let id = device.state.itemId, id > 0, !device.hidden, !device.state.isIdle,
                       RemoteAbility.capabilities(hub.platform).plays(device.itemKind.isEmpty ? "video" : device.itemKind) {
                        Button { Task { await bringHere(device) } } label: {
                            Label { BusyText("Move it to this device", busy: busy) } icon: { Image(systemName: "arrow.down.to.line") }
                        }
                        .action(.secondary, wide: true)
                        .disabled(busy)
                        .accessibilityIdentifier("remote-bring-here")
                    }
                    if let list = device.state.queue, list.count > 1, !device.hidden { queue(device, list) }
                }
            } else if watcher.devices != nil {
                EmptyState(icon: "tv.slash", title: "That device has gone", detail: "It shows in the list again when its app is open.")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .focusRoot(scope)
    }
}

#if !os(tvOS)
/// The volume, sent as the finger moves but no faster than the device can take it.
private struct VolumeSlider: View {
    @Environment(\.palette) private var palette
    let level: Double
    let set: (Double) -> Void
    @State private var dragging: Double?
    @State private var lastSent = Date.distantPast

    var body: some View {
        Slider(value: Binding(get: { dragging ?? level }, set: { value in
            dragging = value
            if Date().timeIntervalSince(lastSent) > 0.3 {
                lastSent = Date()
                set(value)
            }
        }), in: 0...1) { editing in
            if !editing, let value = dragging {
                set(value)
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    dragging = nil
                }
            }
        }
        .tint(palette.accent)
        .accessibilityLabel("Volume")
        .accessibilityIdentifier("remote-volume")
    }
}
#endif

/// The keys of a TV remote, for a device that says it has them: the four arrows around Select, and Back, Home
/// and Menu. On a phone or tablet the middle is also a surface to swipe on: a swipe is an arrow, a tap Select.
private struct RemotePad: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let press: (String) -> Void

    private func key(_ symbol: String, _ label: String, _ name: String) -> some View {
        Button { press(name) } label: {
            Image(systemName: symbol)
                .font(.system(size: metrics.tv ? 28 : 20, weight: .semibold))
                .frame(width: metrics.tv ? 72 : 44, height: metrics.tv ? 48 : 36)
        }
        .action()
        .accessibilityLabel(label)
        .accessibilityIdentifier("pad-\(name)")
    }

    private func worded(_ words: String, _ symbol: String, _ name: String) -> some View {
        Button { press(name) } label: { Label(words, systemImage: symbol) }
            .action()
            .accessibilityIdentifier("pad-\(name)")
    }

    var body: some View {
        VStack(spacing: Tokens.Space.s3) {
            Text("REMOTE")
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Tokens.Space.s4)
                .accessibilityAddTraits(.isHeader)
            #if !os(tvOS)
            Text("Swipe here to move, tap to select")
                .font(.wmSecondary)
                .foregroundStyle(palette.textHint)
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 24).onEnded { drag in
                    let across = drag.translation.width, down = drag.translation.height
                    press(abs(across) > abs(down) ? (across > 0 ? "right" : "left") : (down > 0 ? "down" : "up"))
                })
                .onTapGesture { press("select") }
                .accessibilityHidden(true)
                .accessibilityIdentifier("pad-surface")
            #endif
            VStack(spacing: Tokens.Space.s2) {
                key("chevron.up", "Up", "up")
                HStack(spacing: Tokens.Space.s2) {
                    key("chevron.left", "Left", "left")
                    key("circle.fill", "Select", "select")
                    key("chevron.right", "Right", "right")
                }
                key("chevron.down", "Down", "down")
            }
            HStack(spacing: Tokens.Space.s2) {
                worded("Back", "arrow.uturn.backward", "back")
                worded("Home", "house", "home")
                worded("Menu", "line.3.horizontal", "menu")
                key("playpause.fill", "Play or pause", "playpause")
            }
        }
        .frame(maxWidth: .infinity)
        .remoteSection()
    }
}

// MARK: - Where it's offered

/// "Play on another device" wherever something can be played: a button that opens the list for it.
struct PlayOnButton<Label: View>: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var hub: RemoteHub
    /// Asked when pressed, so it is what's playing at that moment.
    let source: () -> PlayOnSource?
    @ViewBuilder var label: Label
    @State private var shown: Shown?

    private struct Shown: Identifiable {
        let id = UUID()
        let source: PlayOnSource?
    }

    var body: some View {
        if hub.hasRemote {
            Button { shown = Shown(source: source()) } label: { label }
                .accessibilityIdentifier("play-on")
                .togetherSheet(item: $shown) { showing in
                    TogetherFrame(model: model, close: { shown = nil }) {
                        PlayOnView(source: showing.source, close: { shown = nil })
                    }
                }
        }
    }
}

/// Beside the queue of Apple TV's music player: hand the music over to another device.
struct MusicPlayOnButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PlayOnButton(hub: model.remote, source: { model.remote.sourcePlayingMusic() }) { Text("Play on…") }.action()
    }
}

/// What Apple TV's player opens from its own bar, and nothing on the others: there the buttons are on the
/// player itself (see `PlayerTogetherButtons`).
struct PlayerTogether: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let playback: PlaybackModel

    func body(content: Content) -> some View {
        content.modifier(Sheets(hub: model.remote, model: model, playback: playback))
    }

    private struct Sheets: ViewModifier {
        @ObservedObject var hub: RemoteHub
        let model: AppModel
        let playback: PlaybackModel

        func body(content: Content) -> some View {
            content.togetherSheet(item: $hub.playerSheet) { sheet in
                TogetherFrame(model: model, close: { hub.playerSheet = nil }) {
                    switch sheet {
                    case .playOn(let source): PlayOnView(source: source, close: { hub.playerSheet = nil })
                    case .party: PartyView(item: playback.item, close: { hub.playerSheet = nil })
                    }
                }
            }
        }
    }
}

/// What the phone's and tablet's music player opens from its More.
struct MusicTogether: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content.modifier(Sheets(hub: model.remote, model: model))
    }

    private struct Sheets: ViewModifier {
        @ObservedObject var hub: RemoteHub
        let model: AppModel

        func body(content: Content) -> some View {
            content.togetherSheet(item: $hub.musicSheet) { sheet in
                TogetherFrame(model: model, close: { hub.musicSheet = nil }) {
                    switch sheet {
                    case .playOn(let source): PlayOnView(source: source, close: { hub.musicSheet = nil })
                    case .party: PartyView(item: nil, close: { hub.musicSheet = nil })
                    }
                }
            }
        }
    }
}

#if os(iOS) || os(visionOS)
/// On the phone's and tablet's player, beside "How this is playing": the watch party, and playing on another device.
struct PlayerTogetherButtons: View {
    @EnvironmentObject private var model: AppModel
    let playback: PlaybackModel

    var body: some View {
        Buttons(hub: model.remote, party: model.remote.party, playback: playback)
    }

    private struct Buttons: View {
        @ObservedObject var hub: RemoteHub
        @ObservedObject var party: PartySession
        let playback: PlaybackModel

        private func icon(_ symbol: String, on: Bool = false) -> some View {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? Color.white.opacity(0.22) : .clear))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }

        var body: some View {
            if hub.hasParties, playback.item?.isPlayable == true {
                WatchPartyButton(hub: hub, item: playback.item) { icon("person.2.fill", on: party.room != nil) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(party.room == nil ? "Watch party" : "Watch party, \(party.room?.members.count ?? 0) here")
            }
            PlayOnButton(hub: hub, source: { hub.source(playing: playback) }) { icon("tv.and.mediabox") }
                .buttonStyle(.plain)
                .accessibilityLabel("Play on another device")
        }
    }
}
#endif

/// On a film's or an episode's page.
struct TitleTogether: View {
    @EnvironmentObject private var model: AppModel
    let item: Item
    /// A phone's row has room for one small button, which opens the two choices.
    var compact = false

    var body: some View {
        Buttons(hub: model.remote, item: item, compact: compact)
    }

    private struct Buttons: View {
        @EnvironmentObject private var model: AppModel
        @ObservedObject var hub: RemoteHub
        let item: Item
        let compact: Bool
        @State private var sheet: TogetherSheet?

        private var playable: Bool { item.isPlayable || item.kind == "audio" }

        @ViewBuilder private var buttons: some View {
            if hub.hasRemote, playable {
                Button { sheet = .playOn(PlayOnSource(item)) } label: { Label("Play on…", systemImage: "tv.and.mediabox") }
                    .accessibilityLabel("Play on another device")
                    .accessibilityIdentifier("play-on")
            }
            if hub.hasParties, item.isPlayable {
                Button { sheet = .party } label: { Label("Watch party", systemImage: "person.2") }
                    .accessibilityIdentifier("watch-party")
            }
        }

        var body: some View {
            Group {
                if (hub.hasRemote && playable) || (hub.hasParties && item.isPlayable) {
                    #if os(tvOS)
                    buttons.action(pill: true)
                    #else
                    if compact {
                        Menu { buttons } label: { Image(systemName: "person.2.wave.2").font(.system(size: 16, weight: .semibold)) }
                            .squareButton()
                            .accessibilityLabel("Watch together or on another device")
                            .accessibilityIdentifier("together")
                    } else {
                        buttons.pageButton(.secondary)
                    }
                    #endif
                }
            }
            .togetherSheet(item: $sheet) { showing in
                TogetherFrame(model: model, close: { sheet = nil }) {
                    switch showing {
                    case .playOn(let source): PlayOnView(source: source, close: { sheet = nil })
                    case .party: PartyView(item: item, close: { sheet = nil })
                    }
                }
            }
        }
    }
}

/// In You, under this device's own choices: the switch that lets other devices play here, the list of devices
/// to control, and watch parties.
struct TogetherRows: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Rows(hub: model.remote, device: model.remote.device, party: model.remote.party)
    }

    private struct Rows: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.palette) private var palette
        @Environment(\.metrics) private var metrics
        @ObservedObject var hub: RemoteHub
        @ObservedObject var device: RemoteDeviceHost
        @ObservedObject var party: PartySession
        @State private var sheet: TogetherSheet?
        @State private var devices = false

        private struct Shown: Identifiable { let id = 0 }

        var body: some View {
            if hub.hasRemote {
                #if os(tvOS)
                Button { hub.setLetOthers(!hub.letOthers) } label: {
                    RowLabel(icon: "dot.radiowaves.left.and.right", tint: "#0e7c6f", title: "Let other devices control this one",
                             value: say(hub.letOthers ? "on" : "off"), chevron: false)
                }
                .rowStyle()
                .accessibilityIdentifier("let-others-control")
                #else
                Toggle(isOn: Binding(get: { hub.letOthers }, set: { hub.setLetOthers($0) })) {
                    HStack(spacing: Tokens.Space.s3) {
                        IconTile(symbol: "dot.radiowaves.left.and.right", hex: "#0e7c6f")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Let other devices control this one").font(.subheadline).foregroundStyle(palette.text)
                            Text(hub.letOthers ? (device.online ? "It shows in the list on your other devices." : "Connecting…") : "It isn't shown on your other devices.")
                                .font(.wmSecondary).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                .tint(palette.accent)
                .padding(.horizontal, Tokens.Space.s4)
                .frame(minHeight: 64)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.border).frame(height: 0.5).padding(.leading, Tokens.Space.s4 + 28 + Tokens.Space.s3).accessibilityHidden(true)
                }
                .accessibilityIdentifier("let-others-control")
                #endif
                Button { devices = true } label: {
                    RowLabel(icon: "tv.and.mediabox", tint: "#7f46b8", title: "Play on another device")
                }
                .rowStyle()
                .accessibilityIdentifier("row-devices")
                .togetherSheet(item: Binding(get: { devices ? Shown() : nil }, set: { devices = $0 != nil })) { _ in
                    TogetherFrame(model: model, close: { devices = false }) {
                        PlayOnView(source: nil, close: { devices = false })
                    }
                }
            }
            if hub.hasParties {
                Button { sheet = .party } label: {
                    RowLabel(icon: "person.2", tint: "#bd2f85", title: "Watch party", value: party.room?.name ?? "")
                }
                .rowStyle()
                .accessibilityIdentifier("row-watch-party")
                .togetherSheet(item: $sheet) { _ in
                    TogetherFrame(model: model, close: { sheet = nil }) {
                        PartyView(item: nil, close: { sheet = nil })
                    }
                }
            }
        }
    }
}
