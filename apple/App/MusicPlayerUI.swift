#if os(iOS) || os(visionOS)
import SwiftUI
import WittyKit

// The website's music, audiobook and podcast player on a phone or a tablet: the bar above the floating bar
// (web/src/audio/MiniPlayer.tsx, audio.css) and Now Playing over everything (NowPlaying.tsx, QueuePanel.tsx,
// LyricsPanel.tsx, controls.tsx, nowplaying.css). docs/APP-DESIGN.md, Playback and the media player. AVPlayer stays
// underneath, in Listening. Apple TV keeps its own (NowPlaying.swift).

/// Now Playing's own colours: always on black, whatever the theme, as the website's (`--np-*`).
enum NPInk {
    static let fg = Color.white
    static let fg2 = Color.white.opacity(0.72)
    static let fg3 = Color.white.opacity(0.62)
    static let chip = Color.white.opacity(0.1)
    static let chip2 = Color.white.opacity(0.18)
    static let line = Color.white.opacity(0.14)
    static let panel = Color(red: 16 / 255, green: 16 / 255, blue: 20 / 255).opacity(0.94)
    static let pop = Color(red: 0x15 / 255, green: 0x15 / 255, blue: 0x1A / 255)
    static let well = Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x2C / 255)
    static let loved = Color(red: 1, green: 0x6B / 255, blue: 0x81 / 255)
    static let past = Color.white.opacity(0.42)
    static let rule = Color.white.opacity(0.08)
    static let plate = Color.black.opacity(0.35)
}

private func clamp(_ low: CGFloat, _ value: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), high) }

// MARK: - The range

/// The website's range: a 4 high track filled to the place, and a white 14 thumb, in a taller target.
struct RangeBar: View {
    let place: Double
    let duration: Double
    var height: CGFloat = 20
    let fill: Color
    let track: Color
    let seek: (Double) -> Void
    @State private var dragging: Double?

    private func at(_ x: CGFloat, _ width: CGFloat) -> Double { duration * Double(min(max(x / max(width, 1), 0), 1)) }

    var body: some View {
        let shown = min(max(dragging ?? place, 0), max(duration, 0))
        let part = duration > 0 ? CGFloat(shown / duration) : 0
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: 4)
                Capsule().fill(fill).frame(width: width * part, height: 4)
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
                    .offset(x: part * max(width - 14, 0))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragging = at($0.location.x, width) }
                    .onEnded { value in
                        seek(at(value.location.x, width))
                        dragging = nil
                    }
            )
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(PlayerTime.format(shown)) of \(PlayerTime.format(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seek(min(shown + 10, duration))
            case .decrement: seek(max(shown - 10, 0))
            @unknown default: break
            }
        }
    }
}

// MARK: - The bar

/// A round 44 button of the bar's: clear, or the accent for Play.
private struct BarButton: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let label: String
    var big = false
    var on = false
    /// A liked song's heart: the accent's words colour, with no fill.
    var liked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(big ? palette.onAccent : on || liked ? palette.accentText : palette.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(big ? palette.accent : on ? palette.accent.opacity(0.16) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(BarPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on || liked ? [.isSelected] : [])
    }
}

private struct BarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// Above the floating bar: art, words, Play, Next and a way up. From 900 across (an iPad on its side), the website's
/// wider bar: the rest of the transport, Like and Add to a playlist, the time, the volume, the queue, the visualizer,
/// full screen, Collapse and Stop. Collapsed, a round button in the corner that keeps Play to hand.
struct AudioBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let width: CGFloat
    @State private var adding = false
    @State private var volume = false
    @State private var said = ""

    private var wide: Bool { width >= 900 }
    /// Between 900 and 1240 across, the time and the visualizer's word are left off, as on the website.
    private var roomy: Bool { width > 1240 }

    private func open(queue: Bool = false, visualizer: Bool = false) {
        listening.screenWithQueue = queue
        listening.screenWithVisualizer = visualizer
        listening.screenShown = true
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let _ = listening.jumps
            RangeBar(place: listening.positionSec(), duration: listening.durationSec(), height: 14,
                     fill: palette.accent, track: palette.text.opacity(0.28)) { listening.seek(to: $0) }
        }
    }

    var body: some View {
        if let now = listening.now {
            if listening.barCollapsed {
                collapsed(now)
            } else {
                bar(now)
            }
        }
    }

    private func collapsed(_ now: QueuedTrack) -> some View {
        HStack(spacing: 6) {
            Button { listening.barCollapsed = false } label: {
                PosterArt(url: client.posterURL(now.item), title: now.title, width: 48)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            }
            .buttonStyle(BarPressStyle())
            .overlay {
                // How far through, as a ring around the artwork.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let _ = listening.jumps
                    let duration = listening.durationSec()
                    Circle()
                        .trim(from: 0, to: duration > 0 ? min(1, listening.positionSec() / duration) : 0)
                        .stroke(palette.accentText, lineWidth: 2.5)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)
                }
                .allowsHitTesting(false)
            }
            .accessibilityLabel("Show the player: \(now.title)")
            BarButton(symbol: listening.isPlaying ? "pause.fill" : "play.fill", label: listening.isPlaying ? "Pause" : "Play", big: true) {
                listening.toggle()
            }
        }
        .padding(.leading, 5).padding(.trailing, 8).padding(.vertical, 5)
        .background(Capsule().fill(palette.panel))
        .overlay(Capsule().strokeBorder(palette.control, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, wide ? 16 : Tokens.Space.s2)
    }

    private func bar(_ now: QueuedTrack) -> some View {
        let books = now.keepsPlace
        let sub = listening.problem.isEmpty ? [now.artist, now.album].filter { !$0.isEmpty }.joined(separator: " · ") : listening.problem
        return HStack(spacing: wide ? 4 : Tokens.Space.s2) {
            Button { open() } label: {
                PosterArt(url: client.posterURL(now.item), title: now.title, width: wide ? 64 : 48)
                    .frame(width: wide ? 64 : 48, height: wide ? 64 : 48)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .buttonStyle(BarPressStyle())
            .padding(.top, wide ? -22 : 0)
            .accessibilityLabel("Show the full player")
            Button { open() } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(now.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                    Text(sub).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(minWidth: wide ? 120 : 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(now.title), \(sub)")
            .accessibilityHint("Shows the full player")
            if wide { likeAndAdd(now) }
            HStack(spacing: 2) {
                if wide {
                    if books {
                        BarButton(symbol: "gobackward.15", label: "Back 15 seconds") { listening.seek(by: -Listening.backSeconds) }
                    } else {
                        BarButton(symbol: "shuffle", label: "Shuffle", on: listening.shuffle) { listening.toggleShuffle() }
                    }
                    BarButton(symbol: "backward.end.fill", label: "Previous") { listening.previous() }
                }
                BarButton(symbol: listening.isPlaying ? "pause.fill" : "play.fill", label: listening.isPlaying ? "Pause" : "Play", big: true) {
                    listening.toggle()
                }
                BarButton(symbol: "forward.end.fill", label: "Next") { listening.next() }
                    .disabled(!listening.canGoNext)
                if wide {
                    if books {
                        BarButton(symbol: "goforward.30", label: "Forward 30 seconds") { listening.seek(by: Listening.forwardSeconds) }
                    } else {
                        BarButton(symbol: listening.repeatMode == .one ? "repeat.1" : "repeat",
                                  label: listening.repeatMode == .one ? "Repeat this song" : listening.repeatMode == .all ? "Repeat all" : "Repeat off",
                                  on: listening.repeatMode != .off) { listening.cycleRepeat() }
                    }
                }
            }
            if wide {
                rightSide(books: books)
            } else {
                BarButton(symbol: "chevron.up", label: "Full screen") { open() }
            }
        }
        .padding(.top, wide ? 12 : 8)
        .padding([.horizontal, .bottom], wide ? 12 : 8)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).strokeBorder(palette.control, lineWidth: 1))
        .overlay(alignment: .top) {
            progress
                .padding(.leading, wide ? 88 : 16)
                .padding(.trailing, wide ? 20 : 16)
                .offset(y: wide ? 2 : -7)
        }
        .overlay(alignment: .top) {
            if !said.isEmpty {
                Text(said).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                    .padding(.horizontal, 16).frame(minHeight: 40)
                    .background(Capsule().fill(palette.raised))
                    .offset(y: -56)
                    .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .frame(maxWidth: wide ? 1320 : .infinity)
        .padding(.horizontal, wide ? 24 : Tokens.Space.s2)
    }

    private func say(_ words: String) {
        withAnimation { said = words }
        UIAccessibility.post(notification: .announcement, argument: words)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { if said == words { said = "" } }
        }
    }

    @ViewBuilder
    private func likeAndAdd(_ now: QueuedTrack) -> some View {
        HStack(spacing: 2) {
            if !now.keepsPlace {
                let liked = listening.likes.contains(now.item.id)
                BarButton(symbol: liked ? "heart.fill" : "heart", label: liked ? "Remove from liked songs" : "Add to liked songs", liked: liked) {
                    Task { if let error = await listening.toggleLike(now.item.id) { say(model.handle(error)) } }
                }
                .task(id: now.item.libraryId) { await listening.loadLikes() }
            }
            BarButton(symbol: "text.badge.plus", label: "Add to a playlist", on: adding) { adding.toggle() }
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    PlaylistPicker(items: [now.item], done: { adding = false }, said: say)
                        .padding(6)
                        .frame(width: 280)
                        .environment(\.onBlack, false)
                        .background(palette.panel.ignoresSafeArea())
                }
        }
    }

    private func rightSide(books: Bool) -> some View {
        HStack(spacing: 2) {
            if roomy {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let _ = listening.jumps
                    Text("\(PlayerTime.format(listening.positionSec())) / \(PlayerTime.format(listening.durationSec()))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8)
                }
            }
            let silent = listening.sound.muted || listening.sound.volume == 0
            BarButton(symbol: silent ? "speaker.slash.fill" : "speaker.wave.2.fill", label: "Volume", on: volume) { volume.toggle() }
                .popover(isPresented: $volume, arrowEdge: .bottom) {
                    VolumeCard()
                        .padding(6)
                        .environment(\.onBlack, false)
                        .background(palette.panel.ignoresSafeArea())
                }
            BarButton(symbol: "list.bullet", label: books ? "Chapters" : "Queue") { open(queue: true) }
            if !books {
                Button { open(visualizer: true) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform").font(.system(size: 17)).foregroundStyle(palette.accentText)
                        if roomy { Text("Visualizer").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.text) }
                    }
                    .padding(.horizontal, roomy ? 12 : 10)
                    .frame(minHeight: 40)
                    .background(Capsule().fill(palette.accent.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(palette.accent.opacity(0.4), lineWidth: 1.5))
                    .padding(.horizontal, 2)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(BarPressStyle())
                .accessibilityLabel("Visualizer")
            }
            BarButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Full screen") { open() }
            BarButton(symbol: "chevron.down", label: "Collapse the player") { listening.barCollapsed = true }
            BarButton(symbol: "xmark", label: "Stop playing and close") { listening.stop() }
        }
    }
}

// MARK: - Now Playing

private enum NPPanel { case queue, lyrics, sound, read }

/// The menus that open under a button, as the website's pop-ups.
private enum NPMenu: Hashable { case addThis, addQueue, sleep, more, volume, shuffle }

private struct MenuAnchors: PreferenceKey {
    static var defaultValue: [NPMenu: Anchor<CGRect>] = [:]
    static func reduce(value: inout [NPMenu: Anchor<CGRect>], nextValue: () -> [NPMenu: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A round button of Now Playing's: white at 10%, or white with black for one that's on.
private struct NPButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 44
    var glyph: CGFloat = 20
    var on = false
    var loved = false
    var plain = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(on ? Color.black : loved ? NPInk.loved : NPInk.fg)
                .frame(width: size, height: size)
                .background(Circle().fill(on ? Color.white : plain ? Color.clear : NPInk.chip))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(BarPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The website's chip: a pill of white at 10%, white with black when it's on.
private struct NPChipStyle: ButtonStyle {
    var on = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 13 : 14, weight: .semibold))
            .foregroundStyle(on ? Color.black : NPInk.fg)
            .padding(.horizontal, small ? 12 : 16)
            .frame(minHeight: small ? 36 : 44)
            .background(Capsule().fill(on ? Color.white : configuration.isPressed ? NPInk.chip2 : NPInk.chip))
    }
}

/// A row of a pop-up menu: 44 high, an optional icon, the words.
/// Whether a part sits on Now Playing's black, or on the theme's own surfaces: the tablet bar's pop-ups.
private struct OnBlackKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var onBlack: Bool {
        get { self[OnBlackKey.self] }
        set { self[OnBlackKey.self] = newValue }
    }
}

private struct NPMenuRow: View {
    @Environment(\.onBlack) private var onBlack
    @Environment(\.palette) private var palette
    let words: String
    var symbol: String?
    var chosen = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if chosen { Text("✓") }
                if let symbol { Image(systemName: symbol).font(.system(size: 16)).frame(width: 18) }
                Text(words).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: chosen ? .bold : .regular))
            .foregroundStyle(onBlack ? NPInk.fg : palette.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(NPRowStyle())
    }
}

private struct NPRowStyle: ButtonStyle {
    @Environment(\.onBlack) private var onBlack
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(configuration.isPressed ? (onBlack ? NPInk.chip : palette.text.opacity(0.1)) : .clear))
    }
}

/// The colour of a picture, as the website reads it: a 16 × 16 copy, then ArtColour.
private func artColour(_ data: Data) -> Color? {
    guard let small = decodeArt(data, maxPixels: 64) else { return nil }
    var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .medium
        context.draw(small, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        return true
    }
    guard drawn else { return nil }
    let colour = ArtColour.pick(rgba: pixels)
    return Color(red: colour.red / 255, green: colour.green / 255, blue: colour.blue / 255)
}

private let neutralGlow = Color(red: ArtColour.neutral.red / 255, green: ArtColour.neutral.green / 255, blue: ArtColour.neutral.blue / 255)

/// The whole-screen player: on black, lit from the top by the artwork's colour, with the artwork and its
/// reflection, the title, the place, the transport and the tools. A panel (the queue or the words) takes the
/// artwork's place on a phone, and sits beside it on a wide tablet.
struct PhoneNowPlaying: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @State private var panel: NPPanel?
    @State private var menu: NPMenu?
    @State private var art: CGImage?
    @State private var artMissing = false
    @State private var glow = neutralGlow
    @State private var maxSpeed: Double?
    @State private var said = ""
    @State private var saidTask: Task<Void, Never>?
    @StateObject private var words = LyricsModel()
    @State private var extras: [Extra] = []
    @State private var karaoke = false
    @State private var viz = VisualizerPrefs()
    @State private var vizLoaded = false
    @State private var vizHere = true
    /// What shuffle is showing now, if it's on.
    @State private var shownStyle = ""

    private var now: QueuedTrack? { listening.now }
    private var music: Bool { !(now?.keepsPlace ?? false) }
    private var lyricsWanted: Bool { music && (panel == .lyrics || panel == .read || karaoke) }
    private var style: String { shownStyle.isEmpty ? viz.nativeStyle : shownStyle }

    /// Kept for the person on the server, with their other interface choices.
    private func setViz(_ change: (inout VisualizerPrefs) -> Void) {
        change(&viz)
        let saved = viz
        Task { try? await client.setInterfaceChoice("musicPlayer", saved) }
    }

    private func say(_ words: String) {
        said = words
        saidTask?.cancel()
        saidTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { said = "" }
        }
        UIAccessibility.post(notification: .announcement, argument: words)
    }

    private func close() { listening.screenShown = false }

    /// Somewhere else in the app, with the player put away first, as the website's goTowards.
    private func go(_ route: Route) {
        close()
        menu = nil
        model.paths[model.tab, default: []].append(route)
    }

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width, height: geo.size.height + safe.top + safe.bottom)
            let compact = geo.size.width <= 860
            let phone = geo.size.width <= 480
            ZStack(alignment: .top) {
                Color.black
                glowLayer(full)
                if vizHere, vizLoaded, viz.viz {
                    VisualizerBackground(style: style, slow: viz.slow, colour: glow, playing: listening.isPlaying)
                }
                VStack(spacing: 0) {
                    header(phone: phone, compact: compact, width: geo.size.width)
                        .padding(.top, safe.top + max(14 - safe.top, 0))
                    stage(full: full, compact: compact, phone: phone, bottom: safe.bottom)
                }
                if !said.isEmpty {
                    Text(said)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NPInk.fg)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(Capsule().fill(NPInk.pop))
                        .overlay(Capsule().strokeBorder(NPInk.line, lineWidth: 1))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, safe.bottom + 24)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                if karaoke, let item = now?.item {
                    KaraokeView(item: item, lyrics: words.lyrics, loading: words.loading || (words.lyrics == nil && words.failed.isEmpty), glow: glow,
                                offset: words.offset, setOffset: { words.setOffset($0, client: client) }, close: { karaoke = false },
                                insets: EdgeInsets(top: safe.top, leading: 0, bottom: safe.bottom, trailing: 0))
                        .transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea()
            .overlayPreferenceValue(MenuAnchors.self) { anchors in
                GeometryReader { space in
                    if let menu, let anchor = anchors[menu] {
                        menuLayer(menu, at: space[anchor], in: space.size)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(.white)
        .onAppear {
            if listening.screenWithQueue { panel = .queue }
            listening.screenWithQueue = false
        }
        .onChange(of: vizLoaded) { loaded in
            guard loaded, listening.screenWithVisualizer else { return }
            listening.screenWithVisualizer = false
            if !viz.viz { setViz { $0.viz = true } }
        }
        .task(id: now.map { client.posterURL($0.item) } ?? nil) { await loadArt() }
        .task(id: now?.item.libraryId) { await loadLikes() }
        .task {
            let prefs = try? await client.prefs()
            maxSpeed = prefs?.maxSpeed
            vizHere = prefs?.visualizer != false
            if let saved = try? await client.interfaceChoice("musicPlayer", as: VisualizerPrefs.self) { viz = saved }
            vizLoaded = true
        }
        .task(id: music ? now?.item.id : nil) {
            extras = []
            guard music, let id = now?.item.id else { return }
            extras = (try? await client.extras(item: id)) ?? []
        }
        .onChange(of: lyricsWanted) { _ in words.want(now?.item.id, wanted: lyricsWanted, client: client, model: model) }
        .onChange(of: now?.item.id) { _ in words.want(now?.item.id, wanted: lyricsWanted, client: client, model: model) }
        // Shuffle: only ever because someone chose it, among the player's own styles.
        .task(id: "\(viz.viz)-\(viz.shuffleEvery)-\(viz.style)") {
            shownStyle = ""
            guard viz.viz, viz.shuffleEvery > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(viz.shuffleEvery) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                let others = VisualizerPrefs.styles.map(\.id).filter { $0 != style }
                shownStyle = others.randomElement() ?? shownStyle
            }
        }
        // The queue was cleared, from here or from elsewhere.
        .onChange(of: now == nil) { gone in if gone { close() } }
        .onChange(of: music) { isMusic in
            if !isMusic, panel == .lyrics || panel == .read { panel = nil }
            if !isMusic { karaoke = false }
        }
        .animation(.easeOut(duration: 0.25), value: karaoke)
        .accessibilityAction(.escape) {
            if karaoke { karaoke = false } else if menu != nil { menu = nil } else if panel != nil { panel = nil } else { close() }
        }
    }

    // MARK: Loading

    private func loadArt() async {
        art = nil
        artMissing = false
        guard let item = now?.item, let url = client.posterURL(item) else {
            artMissing = true
            withAnimation(.easeOut(duration: 0.4)) { glow = neutralGlow }
            return
        }
        do {
            let data = try await client.imageData(url)
            let (image, colour) = await Task.detached(priority: .userInitiated) { (decodeArt(data, maxPixels: 900), artColour(data)) }.value
            guard !Task.isCancelled else { return }
            art = image
            artMissing = image == nil
            withAnimation(.easeOut(duration: 0.4)) { glow = colour ?? neutralGlow }
        } catch {
            artMissing = true
            withAnimation(.easeOut(duration: 0.4)) { glow = neutralGlow }
        }
    }

    private func loadLikes() async { await listening.loadLikes() }

    private func toggleLike(_ id: Int64) {
        Task { if let error = await listening.toggleLike(id) { say(model.handle(error)) } }
    }

    // MARK: The glow

    /// radial-gradient(90% 60% at 50% 0%, art 34%, art 10% at 55%, nothing at 80%).
    private func glowLayer(_ full: CGSize) -> some View {
        EllipticalGradient(stops: [.init(color: glow.opacity(0.34), location: 0),
                                   .init(color: glow.opacity(0.1), location: 0.55),
                                   .init(color: glow.opacity(0), location: 0.8)],
                           center: .top, startRadiusFraction: 0, endRadiusFraction: 0.9)
            .frame(width: full.width, height: full.height * 0.6 / 0.9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: The top

    private func header(phone: Bool, compact: Bool, width: CGFloat) -> some View {
        let books = !music
        let kind = books ? (listening.libraryTypes[now?.item.libraryId ?? 0] == "podcasts" ? "Podcast" : "Audiobook") : "Now playing"
        let sub = now.map { $0.album.isEmpty ? $0.artist : $0.album } ?? ""
        // What's playing and from where: between the two sides up to 860 across, and in the middle of the bar on a
        // wider screen, as the website's grid has it. A phone leaves it off.
        let place = VStack(spacing: 0) {
            Text(kind).font(.system(size: 13, weight: .semibold)).foregroundStyle(NPInk.fg2)
            Text(sub).font(.system(size: 14, weight: .semibold)).foregroundStyle(NPInk.fg).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        return HStack(spacing: Tokens.Space.s2) {
            NPButton(symbol: "chevron.down", label: "Close the full player") { close() }
            if compact, !phone {
                place.frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: phone ? 2 : compact ? 4 : 6) {
                // Phones have their own volume, as on the website.
                if !phone {
                    let silent = listening.sound.muted || listening.sound.volume == 0
                    NPButton(symbol: silent ? "speaker.slash.fill" : "speaker.wave.2.fill", label: "Volume", on: menu == .volume) { toggle(.volume) }
                        .anchorPreference(key: MenuAnchors.self, value: .bounds) { [.volume: $0] }
                }
                NPButton(symbol: "text.badge.plus", label: "Add to a playlist", on: menu == .addThis) { toggle(.addThis) }
                    .anchorPreference(key: MenuAnchors.self, value: .bounds) { [.addThis: $0] }
                sleepButton
                NPButton(symbol: books ? "list.number" : "list.bullet", label: books ? "Chapters" : "Queue", on: panel == .queue) {
                    panel = panel == .queue ? nil : .queue
                }
                if music, let id = now?.item.id {
                    let liked = listening.likes.contains(id)
                    NPButton(symbol: liked ? "heart.fill" : "heart", label: liked ? "Remove from liked songs" : "Add to liked songs", loved: liked) {
                        toggleLike(id)
                    }
                    .accessibilityAddTraits(liked ? [.isSelected] : [])
                }
                NPButton(symbol: "ellipsis", label: "More", on: menu == .more) { toggle(.more) }
                    .anchorPreference(key: MenuAnchors.self, value: .bounds) { [.more: $0] }
            }
        }
        .overlay { if !compact { place.frame(maxWidth: width * 0.46) } }
        .padding(.horizontal, compact ? 12 : clamp(12, width * 0.02, 24))
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        // A swipe down puts it away, as the player's own Close does.
        .gesture(DragGesture(minimumDistance: 24).onEnded { if $0.translation.height > 80 { close() } })
    }

    private var sleepButton: some View {
        let words: String = {
            switch listening.sleep {
            case .at(let when)?: return "Sleep timer: stops at \(when.formatted(date: .omitted, time: .shortened))"
            case .afterThis?: return "Sleep timer: stops after this one"
            case nil: return "Sleep timer"
            }
        }()
        return NPButton(symbol: "moon", label: words, on: listening.sleep != nil || menu == .sleep) { toggle(.sleep) }
            .anchorPreference(key: MenuAnchors.self, value: .bounds) { [.sleep: $0] }
    }

    private func toggle(_ chosen: NPMenu) { menu = menu == chosen ? nil : chosen }

    // MARK: The stage

    @ViewBuilder
    private func stage(full: CGSize, compact: Bool, phone: Bool, bottom: CGFloat) -> some View {
        if compact, let panel {
            VStack(spacing: Tokens.Space.s2) {
                panelView(panel, height: full.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).fill(NPInk.panel))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).strokeBorder(NPInk.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous))
                transport(play: 56, taller: 48, tall: 44, gap: max(6, full.width * 0.012))
                    .padding(.top, 4)
                    .padding(.bottom, max(10, bottom))
            }
            .padding(.horizontal, 16)
        } else {
            HStack(alignment: .top, spacing: clamp(16, full.width * 0.03, 40)) {
                main(full: full, compact: compact, phone: phone)
                if let panel {
                    panelView(panel, height: full.height, wide: true)
                        .frame(width: max(320, min(480, full.width * 0.42)))
                        .frame(maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).fill(NPInk.panel))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).strokeBorder(NPInk.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous))
                        .padding(.top, 4)
                        .padding(.bottom, max(8, bottom))
                }
            }
            .padding(.horizontal, compact ? 16 : clamp(16, full.width * 0.03, 40))
        }
    }

    private func main(full: CGSize, compact: Bool, phone: Bool) -> some View {
        let height = full.height
        let side = compact ? min(full.width * 0.66, height * 0.32) : clamp(150, height * 0.38, 440)
        let below = compact ? clamp(16, height * 0.04, 36) : clamp(30, height * 0.062, 72)
        let reflection = compact ? clamp(16, height * 0.044, 40) : clamp(26, height * 0.056, 64)
        let gap = clamp(6, height * 0.013, 16)
        let tall: CGFloat = phone ? 46 : 56
        let taller: CGFloat = phone ? 56 : 66
        return GeometryReader { box in
            ScrollView(showsIndicators: false) {
                VStack(spacing: gap) {
                    artBox(side: side, reflection: reflection)
                        .padding(.bottom, below)
                    titleBlock(height: height)
                    seek
                    transport(play: clamp(66, height * 0.1, 96), taller: taller, tall: tall, gap: clamp(6, full.width * 0.012, 16))
                    tools(compact: compact)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: box.size.height)
            }
        }
    }

    private func artBox(side: CGFloat, reflection: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        return ZStack(alignment: .top) {
            Group {
                if let art {
                    Image(decorative: art, scale: 1).resizable().scaledToFill()
                } else if artMissing {
                    PlaceholderArt(title: now?.title ?? "")
                } else {
                    NPInk.well
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
            .accessibilityLabel("Cover of \(now.map { $0.album.isEmpty ? $0.title : $0.album } ?? "")")
            if let art {
                Image(decorative: art, scale: 1).resizable().scaledToFill()
                    .frame(width: side, height: side)
                    .scaleEffect(x: 1, y: -1)
                    .frame(width: side, height: reflection, alignment: .top)
                    .clipShape(shape)
                    .mask(LinearGradient(colors: [.black.opacity(0.34), .clear], startPoint: .top, endPoint: .bottom))
                    .offset(y: side + 8)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side, alignment: .top)
    }

    private func titleBlock(height: CGFloat) -> some View {
        let title = clamp(22.4, height * 0.036, 44.8)
        let artist = now?.artist ?? ""
        return VStack(spacing: 2) {
            Text(now?.title ?? "")
                .font(.system(size: title, weight: .heavy))
                .tracking(-0.022 * title)
                .lineSpacing(title * 0.12 - 4)
                .foregroundStyle(NPInk.fg)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if music, !artist.isEmpty, let library = now?.item.libraryId {
                Button { go(.artist(library: library, name: now?.item.albumArtistName ?? artist)) } label: {
                    Text(artist)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: clamp(16, height * 0.021, 20.8), weight: .semibold))
                .foregroundStyle(NPInk.fg2)
                .accessibilityHint("Goes to the artist")
            } else if !artist.isEmpty {
                Text(artist)
                    .font(.system(size: clamp(16, height * 0.021, 20.8), weight: .semibold))
                    .foregroundStyle(NPInk.fg2)
                    .padding(.horizontal, 8).padding(.vertical, 2)
            }
            if !listening.problem.isEmpty {
                Text(listening.problem).font(.system(size: 13)).foregroundStyle(NPInk.fg2).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: 760)
    }

    private var seek: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let _ = listening.jumps
            let place = listening.positionSec()
            let duration = listening.durationSec()
            VStack(spacing: 2) {
                RangeBar(place: place, duration: duration, fill: .white, track: Color.white.opacity(0.28)) { listening.seek(to: $0) }
                HStack {
                    Text(PlayerTime.format(place))
                    Spacer()
                    Text(PlayerTime.format(duration))
                }
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(NPInk.fg2)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: 820)
    }

    private func transport(play: CGFloat, taller: CGFloat, tall: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            if music {
                NPButton(symbol: "shuffle", label: "Shuffle", size: tall, on: listening.shuffle) { listening.toggleShuffle() }
            } else {
                NPButton(symbol: "gobackward.15", label: "Back 15 seconds", size: tall, glyph: 22) { listening.seek(by: -Listening.backSeconds) }
            }
            NPButton(symbol: "backward.end.fill", label: "Previous", size: taller, glyph: taller >= 56 ? 26 : 22) { listening.previous() }
            Button { listening.toggle() } label: {
                Image(systemName: listening.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: play * 0.4, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: play, height: play)
                    .background(Circle().fill(Color.white))
                    .contentShape(Circle())
            }
            .buttonStyle(BarPressStyle())
            .accessibilityLabel(listening.isPlaying ? "Pause" : "Play")
            NPButton(symbol: "forward.end.fill", label: "Next", size: taller, glyph: taller >= 56 ? 26 : 22) { listening.next() }
                .disabled(!listening.canGoNext)
                .opacity(listening.canGoNext ? 1 : 0.4)
            if music {
                NPButton(symbol: listening.repeatMode == .one ? "repeat.1" : "repeat",
                         label: listening.repeatMode == .one ? "Repeat this song" : listening.repeatMode == .all ? "Repeat all" : "Repeat off",
                         size: tall, on: listening.repeatMode != .off) { listening.cycleRepeat() }
            } else {
                NPButton(symbol: "goforward.30", label: "Forward 30 seconds", size: tall, glyph: 22) { listening.seek(by: Listening.forwardSeconds) }
            }
        }
    }

    /// Lyrics, Karaoke and Read, the visualizer's choices and the speed. On a narrow screen the words come first:
    /// they're what a thumb came here for.
    private func tools(compact: Bool) -> some View {
        FlowRow(spacing: compact ? 6 : 8, lineSpacing: compact ? 6 : 8) {
            if compact { wordsChips }
            if vizHere {
                Button { setViz { $0.viz.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform").font(.system(size: 20))
                        Text("Visualizer")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NPInk.fg)
                    .padding(.horizontal, 18)
                    .frame(minHeight: compact ? 44 : 48)
                    .background(Capsule().fill(viz.viz ? glow.opacity(0.45) : NPInk.plate))
                    .overlay(Capsule().strokeBorder(viz.viz ? Color.white : Color.white.opacity(0.45), lineWidth: 2))
                }
                .buttonStyle(BarPressStyle())
                .accessibilityAddTraits(viz.viz ? [.isSelected] : [])
                if viz.viz {
                    HStack(spacing: 2) {
                        ForEach(VisualizerPrefs.styles, id: \.id) { choice in
                            let on = style == choice.id
                            Button(choice.name) {
                                shownStyle = ""
                                setViz {
                                    $0.style = choice.id
                                    $0.viz = true
                                }
                                UIAccessibility.post(notification: .announcement, argument: "Visualizer: \(choice.name)")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? Color.black : NPInk.fg)
                            .padding(.horizontal, 16).frame(minHeight: 40)
                            .background(Capsule().fill(on ? Color.white : .clear))
                            .accessibilityAddTraits(on ? [.isSelected] : [])
                        }
                    }
                    .padding(3)
                    .background(Capsule().fill(NPInk.chip))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Visualizer style")
                }
            }
            if !compact {
                if vizHere, viz.viz { vizExtras }
                if vizHere { NPInk.line.frame(width: 1, height: 30).padding(.horizontal, 4) }
                wordsChips
            }
            speedChoice
            if compact, vizHere, viz.viz { vizExtras }
        }
        .padding(.top, 2).padding(.bottom, 6)
    }

    @ViewBuilder private var wordsChips: some View {
        if music {
            Button { panel = panel == .lyrics ? nil : .lyrics } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.mic").font(.system(size: 18))
                    Text("Lyrics")
                }
            }
            .buttonStyle(NPChipStyle(on: panel == .lyrics))
            .accessibilityAddTraits(panel == .lyrics ? [.isSelected] : [])
            Button { karaoke = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.microphone").font(.system(size: 18))
                    Text("Karaoke")
                }
            }
            .buttonStyle(NPChipStyle())
            Button { panel = panel == .read ? nil : .read } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book").font(.system(size: 18))
                    Text("Read")
                    if !extras.isEmpty {
                        Text("\(extras.count)").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(panel == .read ? Color.white : Color.black)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(panel == .read ? Color.black : Color.white))
                    }
                }
            }
            .buttonStyle(NPChipStyle(on: panel == .read))
            .accessibilityHint("Read the words, or the album's booklet")
            .accessibilityAddTraits(panel == .read ? [.isSelected] : [])
        }
    }

    /// Slow, and changing style by itself.
    @ViewBuilder private var vizExtras: some View {
        Button { setViz { $0.slow.toggle() } } label: {
            HStack(spacing: 8) {
                Image(systemName: "tortoise").font(.system(size: 18))
                Text("Slow")
            }
        }
        .buttonStyle(NPChipStyle(on: viz.slow))
        .accessibilityHint("A slower, gentler pace")
        .accessibilityAddTraits(viz.slow ? [.isSelected] : [])
        Button { toggle(.shuffle) } label: {
            HStack(spacing: 8) {
                Image(systemName: "shuffle").font(.system(size: 16))
                Text(viz.shuffleEvery > 0 ? VisualizerPrefs.everyWords(viz.shuffleEvery).replacingOccurrences(of: "Every ", with: "") : "Styles")
            }
        }
        .buttonStyle(NPChipStyle(on: viz.shuffleEvery > 0 || menu == .shuffle))
        .anchorPreference(key: MenuAnchors.self, value: .bounds) { [.shuffle: $0] }
        .accessibilityLabel(viz.shuffleEvery > 0 ? "Shuffling visualizers: \(VisualizerPrefs.everyWords(viz.shuffleEvery))" : "Shuffle visualizers")
    }

    private var speedChoice: some View {
        Menu {
            Picker("Playback speed", selection: Binding(get: { listening.speed }, set: { listening.choose(speed: $0) })) {
                ForEach(ListeningSpeeds.offered(max: maxSpeed), id: \.self) { speed in
                    Text(PlayerSpeeds.button(Double(speed))).tag(speed)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(PlayerSpeeds.button(Double(listening.speed)))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NPInk.fg)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Capsule().fill(NPInk.chip))
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(PlayerSpeeds.words(Double(listening.speed)))
    }

    // MARK: The panels

    @ViewBuilder
    private func panelView(_ shown: NPPanel, height: CGFloat, wide: Bool = false) -> some View {
        switch shown {
        case .queue:
            QueuePanelView(glow: glow, close: { panel = nil }, save: { toggle(.addQueue) }, saving: menu == .addQueue, wide: wide)
        case .lyrics:
            if let item = now?.item {
                LyricsPanelView(words: words, item: item, screenHeight: height, close: { panel = nil }, go: go, said: say).id(item.id)
            }
        case .sound:
            SoundPanelView(close: { panel = nil })
        case .read:
            if let item = now?.item {
                ReadPanelView(item: item, extras: extras, lyrics: words.lyrics, loading: words.loading, close: { panel = nil }).id(item.id)
            }
        }
    }

    // MARK: The pop-up menus

    private func menuLayer(_ shown: NPMenu, at rect: CGRect, in size: CGSize) -> some View {
        let width = min(280, size.width - 16)
        let rightSide = rect.midX > size.width / 2
        let x = min(max(rightSide ? rect.maxX - width : rect.minX, 8), size.width - 8 - width)
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { menu = nil }
                .accessibilityHidden(true)
            menuCard(shown, maxHeight: min(size.height * 0.6, 460))
                .frame(width: width)
                .offset(x: x, y: rect.maxY + 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func menuCard(_ shown: NPMenu, maxHeight: CGFloat) -> some View {
        let card = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        Group {
            switch shown {
            case .addThis:
                if let item = now?.item { PlaylistPicker(items: [item], done: { menu = nil }, said: say) }
            case .addQueue:
                PlaylistPicker(items: listening.rows.map(\.track.item), done: { menu = nil }, said: say)
            case .sleep:
                ScrollView { sleepRows }.frame(maxHeight: maxHeight)
            case .more:
                ScrollView { moreRows }.frame(maxHeight: maxHeight)
            case .volume:
                VolumeCard()
            case .shuffle:
                ScrollView { shuffleRows }.frame(maxHeight: maxHeight)
            }
        }
        .padding(6)
        .background(card.fill(NPInk.pop))
        .overlay(card.strokeBorder(NPInk.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sleepRows: some View {
        VStack(spacing: 1) {
            switch listening.sleep {
            case .at(let when)?:
                NPMenuRow(words: "Turn it off (stops at \(when.formatted(date: .omitted, time: .shortened)))") { listening.sleep = nil; menu = nil }
            case .afterThis?:
                NPMenuRow(words: "Turn it off") { listening.sleep = nil; menu = nil }
            case nil:
                EmptyView()
            }
            ForEach(SleepChoices.minutes, id: \.self) { minutes in
                NPMenuRow(words: SleepChoices.words(minutes)) {
                    listening.sleep = .at(Date().addingTimeInterval(Double(minutes) * 60))
                    menu = nil
                }
            }
            NPMenuRow(words: SleepChoices.atTheEnd(books: !music)) { listening.sleep = .afterThis; menu = nil }
        }
    }

    private var shuffleRows: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Change style by itself. It stays still unless you choose this.")
                .font(.system(size: 13)).foregroundStyle(NPInk.fg2).padding(.horizontal, 12).padding(.vertical, 6)
            ForEach(VisualizerPrefs.shuffleChoices, id: \.self) { every in
                NPMenuRow(words: VisualizerPrefs.everyWords(every), chosen: viz.shuffleEvery == every) {
                    setViz { $0.shuffleEvery = every }
                    menu = nil
                }
            }
        }
    }

    private var moreRows: some View {
        VStack(spacing: 1) {
            NPMenuRow(words: "Sound: equaliser and more", symbol: "slider.horizontal.3") {
                menu = nil
                panel = panel == .sound ? nil : .sound
            }
            if let now {
                let library = now.item.libraryId
                if music {
                    NPMenuRow(words: "Start a station from this song", symbol: "dot.radiowaves.left.and.right") {
                        menu = nil
                        startStation(from: now.item)
                    }
                }
                if !now.album.isEmpty, let library {
                    NPMenuRow(words: music ? "Go to album" : "Go to book") {
                        go(.listeningAlbum(library: library, album: now.album, artist: now.item.albumArtistName))
                    }
                }
                if music, !now.item.albumArtistName.isEmpty, let library {
                    NPMenuRow(words: "Go to artist") { go(.artist(library: library, name: now.item.albumArtistName)) }
                }
            }
            NPMenuRow(words: "Stop and close", symbol: "xmark") {
                menu = nil
                listening.stop()
            }
        }
    }

    private func startStation(from item: Item) {
        Task {
            do {
                let songs = try await client.radio(from: item.id)
                guard songs.count >= 2 else {
                    say("There isn't enough here yet to make a station from this song")
                    return
                }
                listening.play(songs, start: ListeningStart(0), keepsPlace: false, client: client)
            } catch {
                say(model.handle(error))
            }
        }
    }
}

// MARK: - Add to a playlist

/// The website's PlaylistPicker: New playlist, then this person's own playlists.
private struct PlaylistPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.onBlack) private var onBlack
    let items: [Item]
    let done: () -> Void
    let said: (String) -> Void
    @State private var lists: [TitleCollection]?
    @State private var making = false
    @State private var name = ""
    @State private var busy = false
    @FocusState private var typing: Bool

    private func add(_ id: Int64, _ called: String) async {
        busy = true
        do {
            try await client.addToCollection(id, items: items.map(\.id))
            said("Added to \(called)")
            done()
        } catch {
            said(model.handle(error))
        }
        busy = false
    }

    private func make() async {
        let chosen = name.trimmingCharacters(in: .whitespaces)
        guard !chosen.isEmpty else { return }
        busy = true
        do {
            let made = try await client.makePlaylist(named: chosen)
            await add(made.id, chosen)
        } catch {
            said(model.handle(error))
            busy = false
        }
    }

    var body: some View {
        Group {
            if making {
                HStack(spacing: 6) {
                    TextField("Name", text: $name)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit { Task { await make() } }
                        .font(.system(size: 14))
                        .foregroundStyle(onBlack ? NPInk.fg : palette.text)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(onBlack ? NPInk.well : palette.card))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(onBlack ? Color.white.opacity(0.4) : palette.control, lineWidth: 1))
                        .accessibilityLabel("Name of the new playlist")
                        .onAppear { typing = true }
                    Button("Make it") { Task { await make() } }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(onBlack ? Color.black : palette.onAccent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(onBlack ? Color.white : palette.accent))
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(4)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        NPMenuRow(words: "New playlist", symbol: "plus") { making = true }
                        if let lists {
                            ForEach(lists, id: \.id) { list in
                                NPMenuRow(words: list.name) { Task { await add(list.id, list.name) } }
                                    .disabled(busy)
                            }
                        } else {
                            Text("Loading…").font(.system(size: 13)).foregroundStyle(onBlack ? NPInk.fg2 : palette.textSecondary)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).padding(.horizontal, 12)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .task { lists = ((try? await client.collections()) ?? []).filter(\.isPlaylist) }
    }
}

// MARK: - The queue

private struct QueuePanelView: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    let glow: Color
    let close: () -> Void
    let save: () -> Void
    let saving: Bool
    /// Over 860 across, the website keeps Up beside each song too.
    var wide = false

    var body: some View {
        let rows = listening.rows
        let books = listening.keepsPlace
        let heading = books ? "Chapters" : "Queue"
        let at = rows.firstIndex { $0.index == listening.nowIndex } ?? 0
        let toCome = rows.count > at + 1 ? Array(rows[(at + 1)...]) : []
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(heading).font(.system(size: 17, weight: .bold)).foregroundStyle(NPInk.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text(QueueWords.toCome(toCome.map(\.track.durationSec)))
                    .font(.system(size: 12)).foregroundStyle(NPInk.fg2)
                NPButton(symbol: "xmark", label: "Close the \(heading.lowercased())", plain: true, action: close)
            }
            .padding(.leading, 18).padding(.trailing, 8).padding(.top, 12).padding(.bottom, 8)
            if !books {
                HStack(spacing: 8) {
                    NPButton(symbol: "text.badge.plus", label: "Save the queue as a playlist", on: saving, action: save)
                        .anchorPreference(key: MenuAnchors.self, value: .bounds) { [.addQueue: $0] }
                    Button("Clear what's to come") { listening.clearUpNext() }
                        .buttonStyle(NPChipStyle(small: true))
                        .disabled(toCome.isEmpty)
                        .opacity(toCome.isEmpty ? 0.45 : 1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                            line(row, position: position, last: rows.count - 1).id(row.id)
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 10)
                }
                .onAppear { if let now = listening.now { proxy.scrollTo(now.id, anchor: .center) } }
            }
        }
    }

    private func line(_ row: QueueRow, position: Int, last: Int) -> some View {
        let track = row.track
        let isNow = row.index == listening.nowIndex
        return HStack(spacing: 0) {
            Button { listening.jump(to: row.index) } label: {
                HStack(spacing: 10) {
                    ZStack {
                        NPInk.well
                        ArtImage(url: client.posterURL(track.item), width: 44, blank: true)
                        if isNow && listening.isPlaying {
                            Image(systemName: "waveform")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: Tokens.Radius.sm).fill(NPInk.plate))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(NPInk.fg)
                        Text(track.artist).font(.system(size: 12)).foregroundStyle(NPInk.fg2)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(PlayerTime.format(track.durationSec))
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(NPInk.fg2)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel([track.title, track.artist].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityValue(isNow ? "Playing" : "")
            // Up is left off on a narrow screen, as the website's; Down and Remove stay.
            if !listening.shuffle, wide {
                NPButton(symbol: "chevron.up", label: "Move \(track.title) up", size: 36, glyph: 15, plain: true) {
                    listening.move(from: row.index, to: row.index - 1)
                }
                .disabled(position == 0)
                .opacity(position == 0 ? 0.4 : 1)
            }
            if !listening.shuffle {
                NPButton(symbol: "chevron.down", label: "Move \(track.title) down", size: 36, glyph: 15, plain: true) {
                    listening.move(from: row.index, to: row.index + 1)
                }
                .disabled(position == last)
                .opacity(position == last ? 0.4 : 1)
            }
            NPButton(symbol: "xmark", label: "Remove \(track.title) from the queue", size: 36, glyph: 15, plain: true) {
                listening.remove(row.index)
            }
        }
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(isNow ? glow.opacity(0.24) : .clear))
    }
}

// MARK: - The words

/// A song's words, shared by Lyrics, Read and karaoke, and asked for only when one of them is open (lyrics.ts).
@MainActor
final class LyricsModel: ObservableObject {
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var loading = false
    @Published private(set) var failed = ""
    @Published private(set) var offset = 0.0
    private var itemId: Int64?
    private var held: [Int64: Lyrics] = [:]
    private var task: Task<Void, Never>?
    private var saving: Task<Void, Never>?

    /// The words of this song, if they're wanted now.
    func want(_ id: Int64?, wanted: Bool, client: WittyClient, model: AppModel) {
        failed = ""
        guard let id, wanted else {
            if id != itemId {
                task?.cancel()
                loading = false
                itemId = id
                lyrics = id.flatMap { held[$0] }
                offset = lyrics?.offsetMs ?? 0
            }
            return
        }
        if itemId == id, lyrics != nil || loading { return }
        itemId = id
        if let have = held[id] {
            lyrics = have
            offset = have.offsetMs ?? 0
            return
        }
        lyrics = nil
        load(id, client: client, model: model)
    }

    /// After someone has corrected them.
    func reload(client: WittyClient, model: AppModel) {
        guard let itemId else { return }
        held[itemId] = nil
        lyrics = nil
        load(itemId, client: client, model: model)
    }

    private func load(_ id: Int64, client: WittyClient, model: AppModel) {
        task?.cancel()
        loading = true
        task = Task { [weak self] in
            // The server was busy with another song: ask again after a while, a few times.
            for attempt in 0..<5 {
                do {
                    let found = try await client.lyrics(item: id)
                    guard let self, !Task.isCancelled, self.itemId == id else { return }
                    if found.retry == true, attempt < 4 {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        continue
                    }
                    if (found.failed ?? "").isEmpty { self.held[id] = found }
                    self.lyrics = found
                    self.offset = found.offsetMs ?? 0
                    self.loading = false
                    return
                } catch {
                    guard let self, !Task.isCancelled, self.itemId == id else { return }
                    self.failed = model.handle(error)
                    self.loading = false
                    return
                }
            }
        }
    }

    /// The listener's own timing, saved a moment after the last change.
    func setOffset(_ ms: Double, client: WittyClient) {
        guard let itemId else { return }
        let clamped = max(-120_000, min(120_000, ms))
        offset = clamped
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            try? await client.setLyricsOffset(item: itemId, ms: clamped)
        }
    }
}

private struct LyricsPanelView: View {
    @EnvironmentObject private var listening: Listening
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @ObservedObject var words: LyricsModel
    let item: Item
    let screenHeight: CGFloat
    let close: () -> Void
    let go: (Route) -> Void
    let said: (String) -> Void
    @State private var index = -1
    @State private var heldUntil = Date.distantPast
    @State private var fixing = false
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let lyrics = words.lyrics
        let loading = words.loading
        let offset = words.offset
        let lines = lyrics?.timed ?? []
        VStack(spacing: 0) {
            NPSideHead(title: "Lyrics", closeLabel: "Close the lyrics", close: close) {
                if let source = lyrics?.sourceName, !source.isEmpty {
                    if let link = lyrics?.creditUrl.flatMap(URL.init(string:)) {
                        Link(source, destination: link).font(.system(size: 12)).foregroundStyle(NPInk.fg2).underline()
                    } else {
                        Text(source).font(.system(size: 12)).foregroundStyle(NPInk.fg2)
                    }
                }
            }
            if loading {
                Text("Looking for the words…").font(.system(size: 13)).foregroundStyle(NPInk.fg2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 6)
            }
            if !words.failed.isEmpty {
                NPNote(words: words.failed).padding(.horizontal, 18).padding(.vertical, 8)
            }
            if let lyrics, !loading {
                if lyrics.instrumental == true {
                    empty(["This one has no words."])
                } else if !lyrics.hasWords {
                    empty(LyricWords.none(lyrics), links: lyrics.online != true && lyrics.tried != true && (lyrics.failed ?? "").isEmpty)
                }
            }
            if !lines.isEmpty {
                lineList(lines, offset: offset)
            } else if let plain = lyrics?.plain, !plain.isEmpty {
                ScrollView {
                    Text(plain).font(.system(size: 17)).foregroundStyle(NPInk.fg)
                        .lineSpacing(17 * 0.55 - 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 16)
                        .textSelection(.enabled)
                }
            } else {
                Spacer(minLength: 0)
            }
            if let lyrics, !(lyrics.plain ?? "").isEmpty || lyrics.canEdit == true {
                HStack(spacing: 6) {
                    if !lines.isEmpty {
                        Button("Sooner") { words.setOffset(LyricWords.nudge(offset, by: -250), client: client) }
                            .buttonStyle(NPChipStyle(small: true))
                            .accessibilityHint("The words come sooner")
                        Text(LyricWords.offset(offset))
                            .font(.system(size: 13).monospacedDigit()).foregroundStyle(NPInk.fg2)
                            .frame(minWidth: 62)
                        Button("Later") { words.setOffset(LyricWords.nudge(offset, by: 250), client: client) }
                            .buttonStyle(NPChipStyle(small: true))
                            .accessibilityHint("The words come later")
                        if offset != 0 {
                            Button("Reset") { words.setOffset(0, client: client) }.buttonStyle(NPChipStyle(small: true))
                        }
                    }
                    Spacer(minLength: 0)
                    if lyrics.canEdit == true {
                        Button { fixing = true } label: { Label("Fix", systemImage: "pencil") }
                            .buttonStyle(NPChipStyle(small: true))
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
                .overlay(alignment: .top) { NPInk.line.frame(height: 1) }
            }
        }
        .overlay {
            if fixing, let lyrics {
                FixLyricsView(item: item, lyrics: lyrics, close: { fixing = false }) { done in
                    fixing = false
                    said(done)
                    words.reload(client: client, model: model)
                }
            }
        }
        .onReceive(tick) { _ in
            guard let lyrics else { return }
            let at = lyrics.lineAt(seconds: listening.positionSec(), offset: offset)
            if at != index { index = at }
        }
    }

    private func empty(_ paragraphs: [String], links: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(paragraphs, id: \.self) { words in
                if links, words.contains("turn on online lyrics") {
                    Text(.init(words.replacingOccurrences(of: "turn on online lyrics", with: "[turn on online lyrics](wms://settings)")))
                } else {
                    Text(.init(words.replacingOccurrences(of: ".lrc", with: "`.lrc`")))
                }
            }
            if links {
                Text(.init("[How lyrics work](wms://help)"))
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(NPInk.fg2)
        .tint(.white)
        .environment(\.openURL, OpenURLAction { url in
            switch url.host {
            case "settings": go(.page("/settings/metadata#lyrics"))
            case "help": go(.page("/help/lyrics-karaoke#if-lyrics-are-missing-or-wrong"))
            default: return .systemAction
            }
            return .handled
        })
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    private func lineList(_ lines: [LyricLine], offset: Double) -> some View {
        GeometryReader { box in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { at, line in
                            let size = clamp(18.4, screenHeight * 0.023, 26.4)
                            Button {
                                heldUntil = .distantPast
                                listening.seek(to: max(0, (line.t + offset) / 1000))
                            } label: {
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: size, weight: .bold))
                                    .lineSpacing(size * 0.3 - 4)
                                    .foregroundStyle(at == index ? Color.white : at < index ? NPInk.past : NPInk.fg3)
                                    .scaleEffect(at == index ? 1.03 : 1, anchor: .leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(PlayerTime.format(line.t / 1000)): \(line.text.isEmpty ? "a break" : line.text)")
                            .accessibilityAddTraits(at == index ? [.isSelected] : [])
                            .id(at)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, box.size.height * 0.3)
                    .animation(.easeOut(duration: 0.2), value: index)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in heldUntil = Date().addingTimeInterval(4) })
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                             .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .onChange(of: index) { at in
                    guard at >= 0, Date() >= heldUntil else { return }
                    withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(at, anchor: .center) }
                }
                .onAppear { if index >= 0 { proxy.scrollTo(index, anchor: .center) } }
            }
        }
    }
}
#endif
