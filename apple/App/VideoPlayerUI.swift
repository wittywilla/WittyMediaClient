#if os(iOS) || os(visionOS)
import AVKit
import SwiftUI
import WittyKit

// The website's video player on a phone and a tablet, control for control (web/src/player/VideoPlayer.tsx,
// Controls.tsx, TrackPicker.tsx, ViewSettings.tsx, PlayInfoPanel.tsx and player.css), over AVPlayer, which keeps
// picture in picture, AirPlay and the lock screen. The player is always dark, whatever the theme; the accent marks
// the progress and the main buttons. docs/APP-DESIGN.md, Playback and the media player.

private enum PlayerInk {
    static let text = Color.white
    static let quiet = Color(red: 0xA9 / 255, green: 0xAF / 255, blue: 0xBD / 255)
    static let hint = Color(red: 0x84 / 255, green: 0x8B / 255, blue: 0x99 / 255)
    /// Panels over the picture: the website's rgb(20 22 28 / .98).
    static let panel = Color(red: 20 / 255, green: 22 / 255, blue: 28 / 255).opacity(0.98)
    static let line = Color.white.opacity(0.1)
}

// MARK: - The screen

/// Starts the video, or shows the one already playing in the dock.
struct PhonePlayerScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    let id: Int64
    let startOver: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let playback = model.video, playback.id == id {
                VideoPlayerView(playback: playback, clock: playback.clockface)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: id) {
            // A film stops the music, whether or not the system has said so yet.
            model.listening.pauseForVideo()
            if let current = model.video, current.id == id, current.isRunning { return }
            model.video?.stop()
            let playback = PlaybackModel()
            let shown = id
            playback.onFinished = { [weak model] next in model?.videoFinished(next: next, from: shown) }
            model.video = playback
            await playback.start(id: id, client: client, startOver: startOver)
        }
    }
}

/// The picture: the system's player view with its own controls off, so picture in picture and AirPlay still work.
private struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    let fill: Bool
    let playback: PlaybackModel

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let playback: PlaybackModel
        init(_ playback: PlaybackModel) { self.playback = playback }

        func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
            Task { @MainActor [playback] in playback.inPictureInPicture = true }
        }

        func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
            Task { @MainActor [playback] in playback.inPictureInPicture = false }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(playback) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        #if os(iOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

/// What opens over the player.
private enum PlayerPanel: Equatable {
    case speed, scenes, settings, info
    case picker(audio: Bool)
}

struct VideoPlayerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var playback: PlaybackModel
    @ObservedObject var clock: VideoClock
    @State private var shown = true
    @State private var lastTouch = Date()
    @State private var panel: PlayerPanel?
    @State private var view = ViewPrefs()
    @State private var scope = ViewPrefsStore.Scope.global
    @State private var speeds = PlayerSpeeds.offered(max: nil)
    @State private var next: (item: Item, show: Show?, recommended: Bool)?
    @State private var dismissedNext = false
    @State private var landscape = false

    private var stream: Playback? { playback.stream }
    private var item: Item? { playback.item }
    private var duration: Double { stream?.durationSec ?? item?.runtimeSec ?? 0 }
    private var chapters: [Chapter] { stream?.chapters ?? [] }
    private var nearEnd: Bool { duration > 0 && clock.time >= duration - 30 }

    /// Shown again by any touch; hidden after the chosen time while playing, never while paused or a panel is open.
    private func touched() {
        lastTouch = Date()
        if !shown { withAnimation(.easeOut(duration: Tokens.Motion.appear)) { shown = true } }
    }

    private func togglePlay() {
        guard playback.error.isEmpty else { return }
        playback.togglePlay()
    }

    private func toggleLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        landscape.toggle()
        #if os(iOS)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait)) { _ in }
        #endif
    }

    private var subtitle: String {
        guard let item else { return "" }
        let show = [item.showTitle, item.episodeLabel.isEmpty ? nil : item.episodeLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let mode: String? = switch stream?.decision {
        case "direct": "Direct play"
        case "remux": "Rewrapped"
        case "transcode": "Transcoding"
        default: nil
        }
        return [show.isEmpty ? item.year.map(String.init) : show, mode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                VideoSurface(player: playback.player, fill: view.picture == "fill", playback: playback)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                // A tap shows the controls and plays or pauses, as a click on the website's player does. (Its double
                // click for full screen is left to the button: waiting for a second tap would slow every first one.)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { touched(); if panel == nil { togglePlay() } else { panel = nil } }
                    .accessibilityHidden(true)
                if clock.waiting && playback.error.isEmpty { PlayerSpinner() }
                if !playback.error.isEmpty { failure }
                if let end = playback.introEnd, playback.error.isEmpty {
                    Button("Skip intro ›") { touched(); playback.seek(toFilm: end) }
                        .buttonStyle(SkipIntroStyle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, Tokens.Space.s6)
                        .padding(.bottom, 110)
                }
                if let next, (nearEnd || playback.ended || playback.countdown != nil), !dismissedNext, panel == nil {
                    WatchNextCard(next: next, countdown: playback.countdown, currentTitle: item?.showTitle ?? item?.title ?? "",
                                  play: { play(next.item) }, dismiss: { dismissedNext = true; playback.stopCountdown() })
                        .frame(maxWidth: min(320, geo.size.width - 32))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, Tokens.Space.s6)
                        .padding(.bottom, 110)
                }
                VStack(spacing: 0) {
                    top
                    Spacer(minLength: 0)
                    bottom(width: geo.size.width)
                }
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(shown)
                panels(geo.size)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!shown)
        .persistentSystemOverlays(shown ? .automatic : .hidden)
        .task(id: playback.id) {
            let stored = ViewPrefsStore().load(item: playback.id)
            view = stored.prefs
            scope = stored.scope
            if let prefs = try? await client.prefs() { speeds = PlayerSpeeds.offered(max: prefs.maxSpeed) }
        }
        .task(id: "\(shown)|\(lastTouch.timeIntervalSince1970)|\(clock.playing)|\(panel == nil)|\(view.hideAfter)") {
            // The website hides them after the chosen time while playing, and not while paused.
            guard shown, clock.playing, panel == nil, view.hideAfter > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(view.hideAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.appear)) { shown = false }
        }
        .task(id: "\(nearEnd || playback.ended)|\(playback.id)") { await findNext() }
        .onDisappear {
            if landscape { toggleLandscape() }
        }
    }

    /// The next episode, or something like it when there isn't one, fetched in the last 30 seconds.
    private func findNext() async {
        guard nearEnd || playback.ended, next == nil, let item else { return }
        if let id = stream?.nextId ?? item.nextId {
            if let found = try? await client.item(id) { next = (found, nil, false) }
        } else if let found = try? await client.recommend(after: item.id), let picked = found.item {
            next = (picked, found.show, true)
        }
    }

    private func play(_ item: Item) {
        if case .player? = model.path.last { model.path.removeLast() }
        model.path.append(.player(item.id, startOver: false))
    }

    // MARK: The bars

    /// Back (to the dock), the title and what's playing, How this is playing, Next episode and the mini player.
    private var top: some View {
        HStack(spacing: 6) {
            PlayerIconButton(symbol: "arrow.left", label: "Back, keeps playing in the mini player") { model.minimizeVideo() }
            VStack(alignment: .leading, spacing: 0) {
                Text(item?.title ?? "").font(.system(size: PageType.section.size - 3, weight: .semibold)).foregroundStyle(PlayerInk.text).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(PlayerInk.quiet).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if stream != nil {
                PlayerIconButton(symbol: "info.circle.fill", label: "How this is playing") { touched(); panel = .info }
            }
            if stream?.nextId != nil {
                Button { playback.playNext() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(PlayerSmallButtonStyle())
                .accessibilityLabel("Next episode")
            }
            PlayerIconButton(symbol: "pip", label: "Mini player") { model.minimizeVideo() }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [Color.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    private func bottom(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            ZStack(alignment: .topLeading) {
                if view.seekBar {
                    VideoSeekBar(clock: clock, duration: duration, chapters: view.chapterMarks ? chapters.map(\.start) : [], accent: palette.accent) { to in
                        touched()
                        playback.seek(toFilm: to)
                    }
                    .padding(.top, 14)
                }
                // On a phone the time sits over the seek bar, as on the website.
                Text(view.seekBar ? "\(PlayerTime.format(clock.time)) / \(PlayerTime.format(duration))" : timeAndScene)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(PlayerInk.text)
                    .padding(.leading, 4)
                    .accessibilityLabel("\(PlayerTime.format(clock.time)) of \(PlayerTime.format(duration))")
            }
            HStack(spacing: 0) {
                PlayerIconButton(symbol: clock.playing ? "pause.fill" : "play.fill", label: clock.playing ? "Pause" : "Play", big: true) { touched(); togglePlay() }
                Spacer(minLength: 0)
                Button { touched(); panel = panel == .speed ? nil : .speed } label: {
                    Text(PlayerSpeeds.button(Double(clock.rate))).font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .buttonStyle(PlayerSpeedButtonStyle())
                .accessibilityLabel("Playback speed \(PlayerSpeeds.button(Double(clock.rate)))")
                if chapters.count > 1 {
                    PlayerIconButton(symbol: "rectangle.grid.1x2.fill", label: "Scenes", on: panel == .scenes) { touched(); panel = panel == .scenes ? nil : .scenes }
                }
                if (stream?.audio?.count ?? 0) > 1 {
                    PlayerIconButton(symbol: "music.note", label: "Audio & language") { touched(); panel = .picker(audio: true) }
                }
                if !(stream?.subtitles ?? []).isEmpty {
                    PlayerIconButton(symbol: "captions.bubble.fill", label: "Subtitles") { touched(); panel = .picker(audio: false) }
                }
                PlayerIconButton(symbol: "gearshape.fill", label: "Viewing settings", on: panel == .settings) { touched(); panel = panel == .settings ? nil : .settings }
                #if os(iOS)
                PlayerIconButton(symbol: landscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", label: "Fullscreen") { touched(); toggleLandscape() }
                #endif
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Color.black.opacity(0.82), location: 0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var timeAndScene: String {
        let now = PlayerTime.format(clock.time)
        guard chapters.count > 1 else { return now }
        return "\(now) · \(Scenes.name(chapters, Scenes.current(chapters.map(\.start), at: clock.time)))"
    }

    private var failure: some View {
        VStack(spacing: Tokens.Space.s3) {
            Text("Playback failed: \(playback.error)").font(.system(size: 15)).foregroundStyle(PlayerInk.quiet).multilineTextAlignment(.center)
            HStack(spacing: Tokens.Space.s2) {
                Button("Try again") { playback.tryAgain() }.pageButton(.primary)
                Button(say("back")) { model.closeVideo() }.pageButton(.secondary)
            }
        }
        .padding(.vertical, Tokens.Space.s4)
        .padding(.horizontal, Tokens.Space.s6)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(Color.black.opacity(0.68)))
        .padding(Tokens.Space.s5)
    }

    // MARK: What opens over it

    @ViewBuilder private func panels(_ size: CGSize) -> some View {
        switch panel {
        case .speed?:
            PlayerPopover(title: "Playback speed") {
                ForEach(speeds, id: \.self) { speed in
                    PopoverRow(words: PlayerSpeeds.words(speed), active: Float(speed) == clock.rate, note: speed > 4 ? "may be muted" : "") {
                        playback.setSpeed(Float(speed))
                        panel = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, Tokens.Space.s5)
            .padding(.bottom, 64)
        case .picker(let audio)?:
            if let stream {
                TrackPickerView(heading: audio ? "Audio & language" : "Subtitles",
                                tiles: audio ? TrackTile.audio(stream.audio ?? [], chosen: stream.audioIndex)
                                             : TrackTile.subtitles(stream.subtitles ?? [], chosen: stream.subtitleIndex),
                                pick: { id in audio ? playback.choose(audio: id) : playback.choose(subtitle: id) },
                                close: { panel = nil })
            }
        case .scenes?:
            ScenePanel(chapters: chapters, current: Scenes.current(chapters.map(\.start), at: clock.time),
                       pick: { start in playback.seek(toFilm: start); panel = nil }, close: { panel = nil })
        case .settings?:
            ViewSettingsPanel(prefs: $view, scope: $scope, item: playback.id, close: { panel = nil })
                .frame(maxWidth: min(380, size.width - 32))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, Tokens.Space.s4)
                .padding(.bottom, 78)
        case .info?:
            if let stream { PlayInfoDialog(stream: stream, close: { panel = nil }) }
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Parts

/// The website's `.ibtn`: a 44 round button with a white icon (36 in a phone's row, 44 for Play).
private struct PlayerIconButton: View {
    let symbol: String
    let label: String
    var big = false
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: big ? 26 : 19, weight: .semibold))
                .foregroundStyle(PlayerInk.text)
                .frame(width: big ? 44 : 36, height: big ? 44 : 36)
                .background(Circle().fill(on ? Color.white.opacity(0.14) : .clear))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PlayerPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

private struct PlayerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? Color.white.opacity(0.14) : .clear))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// `.btn.sm` on the player: `card`, the theme's medium radius, 32 high.
private struct PlayerSmallButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.text)
            .padding(.horizontal, 8)
            .frame(minWidth: 32, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// The speed button: "1×" on white at 10%.
private struct PlayerSpeedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(PlayerInk.text)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .frame(minHeight: 44)
            .padding(.horizontal, 2)
    }
}

/// White, with dark words: the website's Skip intro.
private struct SkipIntroStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255))
            .padding(.horizontal, Tokens.Space.s5)
            .frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(configuration.isPressed ? Color(white: 0.91) : .white))
            .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
    }
}

/// The website's spinner: a ring with its top in the accent.
private struct PlayerSpinner: View {
    @Environment(\.palette) private var palette
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
            Circle().trim(from: 0, to: 0.25).stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: 28, height: 28)
        .onAppear { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { turning = true } }
        .allowsHitTesting(false)
        .accessibilityLabel("Loading")
    }
}

/// The timeline: a 4-high track, what's loaded, the accent up to now, chapter marks, and a knob while dragging.
private struct VideoSeekBar: View {
    @ObservedObject var clock: VideoClock
    let duration: Double
    let chapters: [Double]
    let accent: Color
    let seek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let shown = dragging ?? clock.time
            let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0
            let loaded = duration > 0 ? min(max(clock.buffered / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.26)).frame(height: dragging == nil ? 4 : 6)
                Capsule().fill(Color.white.opacity(0.34)).frame(width: width * loaded, height: dragging == nil ? 4 : 6)
                Capsule().fill(accent).frame(width: width * fraction, height: dragging == nil ? 4 : 6)
                if duration > 0 {
                    ForEach(Array(chapters.dropFirst().enumerated()), id: \.offset) { _, start in
                        Rectangle().fill(Color.black.opacity(0.65)).frame(width: 2, height: 6)
                            .offset(x: width * min(start / duration, 1) - 1)
                    }
                }
                if dragging != nil {
                    Circle().fill(.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .offset(x: width * fraction - 7)
                }
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragging = duration * min(max(value.location.x / width, 0), 1) }
                    .onEnded { value in
                        seek(duration * min(max(value.location.x / width, 0), 1))
                        dragging = nil
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(PlayerTime.format(clock.time)) of \(PlayerTime.format(duration))")
        .accessibilityAdjustableAction { direction in
            seek(clock.time + (direction == .increment ? 10 : -10))
        }
    }
}

/// A list over the player: the speeds.
private struct PlayerPopover<Rows: View>: View {
    let title: String
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                .foregroundStyle(PlayerInk.hint)
                .padding(.horizontal, Tokens.Space.s2).padding(.top, Tokens.Space.s1).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ScrollView { VStack(spacing: 0) { rows } }
                .frame(maxHeight: 360)
        }
        .padding(Tokens.Space.s2)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(PlayerInk.panel))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(PlayerInk.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PopoverRow: View {
    @Environment(\.palette) private var palette
    let words: String
    let active: Bool
    var note = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(words).font(.system(size: 14, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? palette.accentText : PlayerInk.quiet)
                Spacer(minLength: 0)
                if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(PlayerInk.hint) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// The website's track picker: large square tiles over the darkened picture, two across a phone.
private struct TrackPickerView: View {
    @Environment(\.palette) private var palette
    let heading: String
    let tiles: [TrackTile]
    let pick: (Int) -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.84).ignoresSafeArea().onTapGesture(perform: close)
            ScrollView {
                VStack(spacing: 0) {
                    Text(heading).pageFont(.title).foregroundStyle(PlayerInk.text).accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                        ForEach(tiles) { tile in
                            Button { pick(tile.id); close() } label: { tileBody(tile) }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(tile.active ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 18)
                    Button("Close", action: close).pageButton(.ghost).frame(minWidth: 140)
                }
                .padding(Tokens.Space.s6)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .transition(.opacity)
    }

    private func tileBody(_ tile: TrackTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        return VStack(spacing: 6) {
            Text(tile.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(PlayerInk.text).multilineTextAlignment(.center)
            if !tile.sub.isEmpty { Text(tile.sub).font(.system(size: 13)).foregroundStyle(PlayerInk.quiet).multilineTextAlignment(.center) }
            if !tile.detail.isEmpty { Text(tile.detail).font(.system(size: 12)).foregroundStyle(PlayerInk.hint) }
        }
        .padding(Tokens.Space.s3)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(shape.fill(tile.active ? palette.accent.opacity(0.22) : Color.white.opacity(0.07)))
        .overlay(shape.strokeBorder(tile.active ? palette.accent : Color.white.opacity(0.1), lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if tile.active {
                Text("✓").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.accentText).padding(.top, 10).padding(.trailing, Tokens.Space.s3)
            }
        }
    }
}

/// Every scene with its start time and name, the one playing now marked.
private struct ScenePanel: View {
    @Environment(\.palette) private var palette
    let chapters: [Chapter]
    let current: Int
    let pick: (Double) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(spacing: Tokens.Space.s3) {
                    Text("Scenes").font(.system(size: 17, weight: .semibold)).foregroundStyle(PlayerInk.text).accessibilityAddTraits(.isHeader)
                    Text("\(chapters.count) scenes").font(.system(size: 13)).foregroundStyle(PlayerInk.hint)
                    Spacer(minLength: 0)
                    PlayerIconButton(symbol: "xmark", label: "Close scenes", action: close)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s3), count: 2), spacing: Tokens.Space.s3) {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                                Button { pick(chapter.start) } label: { scene(index, chapter) }
                                    .buttonStyle(.plain)
                                    .id(index)
                                    .accessibilityLabel("Play \(Scenes.name(chapters, index)), from \(PlayerTime.format(chapter.start))")
                                    .accessibilityAddTraits(index == current ? [.isSelected] : [])
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                    .onAppear { proxy.scrollTo(current, anchor: .center) }
                }
            }
            .padding(Tokens.Space.s4)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).fill(PlayerInk.panel).ignoresSafeArea(edges: .bottom))
        }
    }

    private func scene(_ index: Int, _ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { Text("\(index + 1)").font(.system(size: 24, weight: .semibold)).foregroundStyle(PlayerInk.quiet) }
                .overlay(alignment: .bottomTrailing) {
                    Text(PlayerTime.format(chapter.start)).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minHeight: 20)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs).fill(Color.black.opacity(0.68))).padding(6)
                }
                .overlay(alignment: .topLeading) {
                    if index == current {
                        Text("Now playing").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.onAccent)
                            .padding(.horizontal, 6).frame(minHeight: 20)
                            .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs).fill(palette.accent)).padding(6)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(index == current ? palette.accent : .clear, lineWidth: 2))
            (Text("\(index + 1). ").foregroundColor(PlayerInk.hint) + Text(Scenes.name(chapters, index)).foregroundColor(PlayerInk.text))
                .font(.system(size: 13)).lineLimit(2)
        }
    }
}

/// The gear: the viewing choices that apply on a phone, for this video or for every video on this device.
private struct ViewSettingsPanel: View {
    @Binding var prefs: ViewPrefs
    @Binding var scope: ViewPrefsStore.Scope
    let item: Int64
    let close: () -> Void

    private func save() { ViewPrefsStore().save(prefs, item: item, scope: scope) }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            Text(label).font(.system(size: 14)).foregroundStyle(PlayerInk.text)
            Spacer(minLength: 0)
            control()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(PlayerInk.line).frame(height: 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Viewing settings").font(.system(size: 15, weight: .semibold)).foregroundStyle(PlayerInk.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                PlayerIconButton(symbol: "xmark", label: "Close viewing settings", action: close)
            }
            row("Apply to") {
                PlayerSegments(choices: [("This video", ViewPrefsStore.Scope.item), ("Everything", .global)], chosen: scope) { scope = $0; save() }
            }
            row("Seek bar") { PlayerSwitch(on: prefs.seekBar, label: "Seek bar") { prefs.seekBar.toggle(); save() } }
            row("Chapter marks") { PlayerSwitch(on: prefs.chapterMarks, label: "Chapter marks") { prefs.chapterMarks.toggle(); save() } }
            row("Hide controls after") {
                PlayerSegments(choices: ViewPrefs.hideChoices.map { ($0.1, $0.0) }, chosen: prefs.hideAfter) { prefs.hideAfter = $0; save() }
            }
            row("Picture") {
                PlayerSegments(choices: [("Fit", "fit"), ("Fill screen", "fill")], chosen: prefs.picture) { prefs.picture = $0; save() }
            }
            Text(scope == .item ? "Saved for this video on this device." : "Saved for all videos on this device.")
                .font(.system(size: 12)).foregroundStyle(PlayerInk.hint).padding(.top, Tokens.Space.s3)
        }
        .padding(.horizontal, Tokens.Space.s4)
        .padding(.vertical, Tokens.Space.s3)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(PlayerInk.panel))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(PlayerInk.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
    }
}

/// The website's `.seg`: choices side by side, the chosen one filled with the text colour.
private struct PlayerSegments<Value: Equatable>: View {
    let choices: [(String, Value)]
    let chosen: Value
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                let on = choice.1 == chosen
                Button { choose(choice.1) } label: {
                    Text(choice.0).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.black : PlayerInk.quiet)
                        .padding(.horizontal, 9).frame(minHeight: 28)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md - 3, style: .continuous).fill(on ? Color.white : .clear))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(Color.white.opacity(0.08)).frame(height: 34))
    }
}

private struct PlayerSwitch: View {
    @Environment(\.palette) private var palette
    let on: Bool
    let label: String
    let flip: () -> Void

    var body: some View {
        Button(action: flip) {
            Capsule().fill(on ? palette.accent : Color.white.opacity(0.3))
                .frame(width: 44, height: 24)
                .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 18, height: 18).padding(3) }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// "How this is playing": what the file is, what happens to it and why, in the server's words.
private struct PlayInfoDialog: View {
    @Environment(\.palette) private var palette
    let stream: Playback
    let close: () -> Void

    private func fact(_ key: String, _ value: String?) -> some View {
        Group {
            if let value, !value.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(palette.textHint)
                    Text(value).font(.system(size: 14)).foregroundStyle(palette.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var body: some View {
        let ex = stream.explain
        let load: String? = switch ex?.load {
        case "none": "Nothing: your player does the work"
        case "light": "Very little"
        case "heavy": "A lot"
        default: nil
        }
        ZStack {
            palette.scrim.ignoresSafeArea().onTapGesture(perform: close)
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text("How this is playing").pageFont(.section).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                    if let summary = ex?.summary, !summary.isEmpty {
                        Text(summary).pageFont(.body).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    fact("The file", ex?.source)
                    fact("Picture", ex?.picture)
                    fact("Sound", ex?.sound)
                    fact("Subtitles", ex?.subtitles)
                    fact("Work for the server", load)
                    fact("Streaming", ex?.streaming)
                    if let reasons = ex?.reasons, !reasons.isEmpty {
                        Text("Why it isn’t simpler").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text).padding(.top, Tokens.Space.s2)
                        ForEach(reasons, id: \.self) { reason in
                            Text("• \(reason)").font(.system(size: 14)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button("Close", action: close).pageButton(.secondary).padding(.top, Tokens.Space.s2)
                }
                .padding(Tokens.Space.s6)
            }
            .frame(maxWidth: 520, maxHeight: 640)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).fill(palette.panel))
            .padding(Tokens.Space.s4)
        }
    }
}

/// Near the end: the next episode, or something like this when there's none, with Play and Dismiss.
private struct WatchNextCard: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let next: (item: Item, show: Show?, recommended: Bool)
    let countdown: Int?
    let currentTitle: String
    let play: () -> Void
    let dismiss: () -> Void

    private var head: String {
        if next.recommended { return next.show != nil ? "Because you watched \(currentTitle)" : "You might also like" }
        if let countdown { return "Next episode in \(countdown)s" }
        return "Watch next"
    }

    var body: some View {
        let episode = next.item.showId != nil
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(head.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(PlayerInk.hint)
            Button(action: play) {
                HStack(spacing: Tokens.Space.s3) {
                    PosterArt(url: client.posterURL(next.item), title: next.item.title, width: 90)
                        .frame(width: 90, height: episode ? 90 * 9 / 16 : 135)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.show?.title ?? next.item.showTitle ?? next.item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(PlayerInk.text).lineLimit(2)
                        Text(episode ? [next.item.episodeLabel, next.item.title].filter { !$0.isEmpty }.joined(separator: " · ") : (next.item.year.map(String.init) ?? ""))
                            .font(.system(size: 12)).foregroundStyle(PlayerInk.hint).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: Tokens.Space.s2) {
                Button(action: play) { Label("Play", systemImage: "play.fill") }.pageButton(.primary)
                Button("Dismiss", action: dismiss).pageButton(.ghost)
            }
        }
        .padding(Tokens.Space.s3)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(PlayerInk.panel))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(PlayerInk.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

// MARK: - The dock

/// The website's mini player on a phone: a bar 64 high above the floating bar, the picture at the left, the title,
/// and Play, the full player and Stop. Tapping the words opens the full player again.
struct VideoDock: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @ObservedObject var playback: PlaybackModel
    @ObservedObject var clock: VideoClock

    private var sub: String {
        guard let item = playback.item else { return "" }
        if item.showTitle != nil { return [item.episodeLabel, item.title].filter { !$0.isEmpty }.joined(separator: " · ") }
        return item.year.map(String.init) ?? ""
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        HStack(spacing: 0) {
            DockPicture(player: playback.player)
                .frame(width: 114, height: 64)
                .background(Color.black)
                .accessibilityHidden(true)
            Button { model.expandVideo() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(playback.item?.showTitle ?? playback.item?.title ?? "").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.text).lineLimit(1)
                    if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(palette.textSecondary).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Tokens.Space.s2)
            .accessibilityLabel("\(playback.item?.title ?? ""), open the player")
            dockButton(clock.playing ? "pause.fill" : "play.fill", size: 26, label: clock.playing ? "Pause" : "Play") { playback.togglePlay() }
            dockButton("arrow.up.left.and.arrow.down.right", size: 18, label: "Full player") { model.expandVideo() }
            dockButton("xmark", size: 18, label: "Stop") { model.closeVideo() }
        }
        .padding(.trailing, Tokens.Space.s1)
        .frame(height: 64)
        .background(shape.fill(palette.panel))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .padding(.horizontal, Tokens.Space.s2)
    }

    private func dockButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(palette.text)
                .frame(width: 34, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The same player's picture, small.
private struct DockPicture: UIViewRepresentable {
    let player: AVPlayer

    final class Host: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: Host, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
#endif
