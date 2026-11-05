import SwiftUI
import WittyKit

// What's playing: the mini player over the app's own screens, and the whole-screen player with the
// queue, as Android's ui/NowPlaying.kt. The place on the track is looked at once a second while one
// of these is showing, and isn't published by the player: nothing else needs redrawing for it.

/// How far through, as a thin line along the top of the mini player.
private struct PlaceLine: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let duration = listening.durationSec()
            let part = duration > 0 ? min(max(listening.positionSec() / duration, 0), 1) : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.border)
                    Rectangle().fill(palette.accent).frame(width: geo.size.width * part)
                }
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// Over the app's own screens, with what most people want from it: what's on, Play or Pause, and Next.
/// Paused, Next gives way to a way of stopping altogether.
struct MiniPlayer: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    var body: some View {
        if let now = listening.now {
            VStack(spacing: 0) {
                PlaceLine()
                HStack(spacing: Tokens.Space.s1) {
                    Button { listening.screenShown = true } label: {
                        HStack(spacing: Tokens.Space.s3) {
                            ArtImage(url: client.posterURL(now.item), width: 44)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(now.title).foregroundStyle(palette.text).lineLimit(1)
                                Group {
                                    if !listening.problem.isEmpty {
                                        Text(listening.problem)
                                    } else if listening.isLoading {
                                        Text("Loading…")
                                    } else if !now.artist.isEmpty {
                                        Text(now.artist)
                                    }
                                }
                                .font(.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(Tokens.Space.s1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SurfaceStyle())
                    .accessibilityLabel("Now playing: \(now.title), \(now.artist)")
                    .accessibilityValue(listening.isPlaying ? "Playing" : "Paused")
                    .accessibilityHint("Opens the player")
                    RoundButton(symbol: listening.isPlaying ? "pause.fill" : "play.fill", label: listening.isPlaying ? "Pause" : "Play") {
                        listening.toggle()
                    }
                    if listening.isPlaying {
                        RoundButton(symbol: "forward.end.fill", label: "Next") { listening.next() }
                            .disabled(!listening.canGoNext)
                    } else {
                        RoundButton(symbol: "xmark", label: "Stop and clear the queue") { listening.stop() }
                    }
                }
                // A TV may crop the edge of its picture.
                .padding(.horizontal, metrics.tv ? metrics.gutter : Tokens.Space.s2)
                .padding(.vertical, metrics.tv ? Tokens.Space.s3 : Tokens.Space.s1)
                .remoteSection()
            }
            .background(palette.panel)
        }
    }
}

/// Where the mini player goes: above the pill on a phone or a tablet, along the bottom on a TV. Not over
/// a film, a game or the server's own page, which has its own player.
struct MiniPlayerSlot: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let tab: AppTab

    private var shows: Bool {
        guard listening.now != nil else { return false }
        switch model.paths[tab]?.last {
        case .player?, .web?, .page?: return false
        default: return true
        }
    }

    var body: some View {
        if shows {
            if metrics.tv {
                MiniPlayer()
            } else {
                MiniPlayer()
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).stroke(palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .padding(.horizontal, Tokens.Space.s3)
            }
        }
    }
}

/// The whole-screen player over everything, opened from the mini player.
struct NowPlayingCover: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.palette) private var palette
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics

    private var screen: some View {
        NowPlayingView()
            .environmentObject(model)
            .environmentObject(listening)
            .environment(\.palette, palette)
            .environment(\.client, client)
            .environment(\.metrics, metrics)
            .preferredColorScheme(model.scheme)
            .tint(palette.accentText)
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(isPresented: $listening.screenShown) { screen.frame(minWidth: 720, minHeight: 560) }
        #elseif os(tvOS)
        // The remote's Play/Pause works on every screen of the app's own, as on Android TV. A film's
        // player takes it first.
        content
            .fullScreenCover(isPresented: $listening.screenShown) { screen }
            .onPlayPauseCommand { if listening.now != nil { listening.toggle() } }
        #else
        content.fullScreenCover(isPresented: $listening.screenShown) { screen }
        #endif
    }
}

extension View {
    func nowPlayingCover() -> some View { modifier(NowPlayingCover()) }
}

// MARK: - The bar

/// The place on the track, which a finger drags and a remote's left and right move. A remote's presses
/// add up, and the player goes there once they stop.
struct SeekBar: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let place: Double
    let duration: Double
    let seek: (Double) -> Void
    @State private var dragging: Double?
    @State private var pending: Double?
    @State private var commit: Task<Void, Never>?
    #if os(tvOS)
    @FocusState private var focused: Bool
    private var thick: CGFloat { focused ? 8 : 4 }
    #else
    private let thick: CGFloat = 4
    #endif

    private func clamped(_ seconds: Double) -> Double { min(max(seconds, 0), duration) }

    private func nudge(_ by: Double) {
        pending = clamped((pending ?? place) + by)
        commit?.cancel()
        commit = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let target = pending else { return }
            seek(target)
            pending = nil
        }
    }

    var body: some View {
        let shown = clamped(dragging ?? pending ?? place)
        let fraction = duration > 0 ? shown / duration : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.border).frame(height: thick)
                Capsule().fill(palette.accent).frame(width: geo.size.width * fraction, height: thick)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragging = clamped(duration * $0.location.x / max(geo.size.width, 1)) }
                    .onEnded { value in
                        seek(clamped(duration * value.location.x / max(geo.size.width, 1)))
                        dragging = nil
                    }
            )
            #endif
        }
        .frame(height: metrics.minTarget)
        #if os(tvOS)
        .padding(.horizontal, Tokens.Space.s2)
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.sm).strokeBorder(focused ? palette.text : Color.clear, lineWidth: metrics.focusRing))
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            if direction == .left { nudge(-10) }
            if direction == .right { nudge(10) }
        }
        #endif
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(ListeningRules.spokenClock(shown)) of \(ListeningRules.spokenClock(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seek(clamped(shown + 10))
            case .decrement: seek(clamped(shown - 10))
            @unknown default: break
            }
        }
    }
}

// MARK: - The whole screen

/// The bar, then the buttons, then for a book its speed. A remote walks down through these, and left
/// and right stay within a row; on the bar they move it.
private struct Controls: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.palette) private var palette

    private var repeatWords: String {
        switch listening.repeatMode {
        case .one: return "Repeat this one"
        case .all: return "Repeat the queue"
        case .off: return "Repeat"
        }
    }

    var body: some View {
        let books = listening.keepsPlace
        VStack(spacing: Tokens.Space.s2) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let place = listening.positionSec()
                let duration = listening.durationSec()
                if duration > 0 {
                    VStack(spacing: 0) {
                        SeekBar(place: place, duration: duration) { listening.seek(to: $0) }
                        HStack {
                            Secondary(ListeningRules.clock(place)).accessibilityLabel(ListeningRules.spokenClock(place))
                            Spacer()
                            Secondary(ListeningRules.clock(duration)).accessibilityLabel("\(ListeningRules.spokenClock(duration)) long")
                        }
                    }
                }
            }
            HStack(spacing: Tokens.Space.s2) {
                if books {
                    RoundButton(symbol: "backward.end.fill", label: "Previous part") { listening.previous() }
                    Button("−15") { listening.seek(by: -Listening.backSeconds) }.action(pill: true).accessibilityLabel("Back 15 seconds")
                } else {
                    RoundButton(symbol: "shuffle", label: "Shuffle", selected: listening.shuffle) { listening.toggleShuffle() }
                    RoundButton(symbol: "backward.end.fill", label: "Previous") { listening.previous() }
                }
                RoundButton(symbol: listening.isPlaying ? "pause.fill" : "play.fill", label: listening.isPlaying ? "Pause" : "Play",
                            primary: true, size: 72) { listening.toggle() }
                if books {
                    Button("+30") { listening.seek(by: Listening.forwardSeconds) }.action(pill: true).accessibilityLabel("Forward 30 seconds")
                    RoundButton(symbol: "forward.end.fill", label: "Next part") { listening.next() }.disabled(!listening.canGoNext)
                } else {
                    RoundButton(symbol: "forward.end.fill", label: "Next") { listening.next() }.disabled(!listening.canGoNext)
                    RoundButton(symbol: listening.repeatMode == .one ? "repeat.1" : "repeat", label: repeatWords,
                                selected: listening.repeatMode != .off) { listening.cycleRepeat() }
                }
            }
            .frame(maxWidth: .infinity)
            .remoteSection()
            if books {
                Button("Speed \(ListeningRules.speedWords(listening.speed))") { listening.cycleSpeed() }
                    .action(pill: true)
                    .remoteSection()
            }
        }
    }
}

/// One line of the queue. Choosing it plays it. While changing the queue, it can be moved, unless
/// it's shuffled and there's no order to move within, and taken out.
private struct QueueLine: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.palette) private var palette
    let row: QueueRow
    let position: Int
    let last: Int
    let editing: Bool

    var body: some View {
        let track = row.track
        let isNow = row.index == listening.nowIndex
        HStack(spacing: Tokens.Space.s1) {
            Button { listening.jump(to: row.index) } label: {
                HStack(spacing: Tokens.Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).foregroundStyle(palette.text).lineLimit(1)
                        if !track.artist.isEmpty { Secondary(track.artist, lines: 1) }
                    }
                    Spacer(minLength: 0)
                    if track.durationSec > 0 { Secondary(ListeningRules.clock(track.durationSec)) }
                }
                .padding(.horizontal, Tokens.Space.s3)
                .padding(.vertical, Tokens.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(SurfaceStyle(fill: isNow ? palette.card : nil))
            .accessibilityLabel([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityValue(isNow ? "Playing" : "")
            if editing {
                if !listening.shuffle {
                    RoundButton(symbol: "chevron.up", label: "Move \(track.title) up") { listening.move(from: row.index, to: row.index - 1) }
                        .disabled(position == 0)
                    RoundButton(symbol: "chevron.down", label: "Move \(track.title) down") { listening.move(from: row.index, to: row.index + 1) }
                        .disabled(position == last)
                }
                RoundButton(symbol: "xmark", label: "Take \(track.title) out of the queue") { listening.remove(row.index) }
            }
        }
        .remoteSection()
    }
}

/// The whole screen. Upright, everything scrolls in one column. On a TV or sideways, the queue has its
/// own side, and keeps what's playing in view unless someone is rearranging it.
struct NowPlayingView: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var editing = false

    private func art(_ side: CGFloat?) -> some View {
        ArtImage(url: listening.now.flatMap { client.posterURL($0.item) }, width: side ?? 360, placeholder: listening.now?.album ?? "")
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side)
            .frame(maxWidth: 360)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
            .accessibilityHidden(true)
    }

    private func words(centre: Bool) -> some View {
        let now = listening.now
        let under = [now?.artist ?? "", now?.album ?? ""].filter { !$0.isEmpty }
        let line = (under.count == 2 && under[0] == under[1] ? [under[0]] : under).joined(separator: " · ")
        let align: TextAlignment = centre ? .center : .leading
        return VStack(alignment: centre ? .center : .leading, spacing: Tokens.Space.s1) {
            Text(now?.title ?? "").font(.wmHero).foregroundStyle(palette.text).lineLimit(3).multilineTextAlignment(align)
                .accessibilityAddTraits(.isHeader)
            if !line.isEmpty { Text(line).foregroundStyle(palette.textSecondary).multilineTextAlignment(align) }
            if listening.isLoading { Text("Loading…").font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            if !listening.problem.isEmpty { ProblemLine(listening.problem) }
        }
        .frame(maxWidth: .infinity, alignment: centre ? .center : .leading)
    }

    @ViewBuilder private var queueHead: some View {
        HStack(spacing: Tokens.Space.s2) {
            SectionTitle("Queue")
            Spacer()
            Button(editing ? "Done" : "Change") { editing.toggle() }.action()
            Button("Clear") { listening.stop() }.action()
        }
        .padding(.top, Tokens.Space.s2)
        .remoteSection()
    }

    @ViewBuilder private var queueLines: some View {
        let rows = listening.rows
        ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
            QueueLine(row: row, position: position, last: rows.count - 1, editing: editing).id(row.id)
        }
    }

    #if !os(tvOS)
    /// Back to the app. A TV's remote has Back for this.
    private var close: some View {
        HStack {
            RoundButton(symbol: "chevron.down", label: "Close the player") { listening.screenShown = false }
            Spacer()
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 24).onEnded { if $0.translation.height > 80 { listening.screenShown = false } })
    }
    #endif

    private var upright: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Space.s1) {
                VStack(spacing: Tokens.Space.s4) {
                    #if !os(tvOS)
                    close
                    #endif
                    art(nil)
                    words(centre: true)
                    Controls()
                }
                queueHead
                queueLines
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, Tokens.Space.s4)
        }
    }

    private var wide: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s8) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                #if !os(tvOS)
                close
                #endif
                Spacer(minLength: 0)
                HStack(spacing: Tokens.Space.s6) {
                    art(metrics.tv ? 240 : 120)
                    words(centre: false)
                }
                Controls()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        queueHead
                        queueLines
                    }
                    .padding(.vertical, metrics.tv ? Tokens.focusRoom : 0)
                }
                .remoteSection()
                .onAppear { if let now = listening.now { proxy.scrollTo(now.id, anchor: .top) } }
                .onChange(of: listening.now?.id) { id in
                    if !editing, let id { proxy.scrollTo(id, anchor: .top) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.vertical, metrics.tv ? metrics.edge : Tokens.Space.s4)
    }

    var body: some View {
        GeometryReader { geo in
            if metrics.tv || geo.size.width > geo.size.height {
                wide
            } else {
                upright
            }
        }
        .background(palette.background.ignoresSafeArea())
        // The queue was cleared, from here or from elsewhere.
        .onChange(of: listening.now == nil) { gone in
            if gone { listening.screenShown = false }
        }
        #if os(tvOS)
        .onPlayPauseCommand { listening.toggle() }
        #endif
    }
}
