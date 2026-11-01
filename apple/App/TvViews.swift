#if os(tvOS)
import AVKit
import SwiftUI
import WittyKit

// Apple TV's own screens for what iPhone and iPad leave to the server's page, as tvOS offers apps no
// web view. Written without a Mac: see docs/PLATFORMS.md for how far that's been checked.

/// An album or a book's chapters. Choosing one plays from there to the end of the list.
struct AlbumView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let library: Int64
    let name: String
    @State private var tracks: [Item]?
    @State private var error = ""
    @Namespace private var scope

    private func load() async {
        do {
            // A page big enough for any album a shelf would hold; the server has no list by album name.
            let page = try await client.items(library: library, offset: 0, limit: 500)
            tracks = ServerPages.tracks(of: name, in: uniqued(page.items ?? []))
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    var body: some View {
        ZStack {
            if let tracks {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        Text(name).font(.wmPage).accessibilityAddTraits(.isHeader)
                        if let artist = tracks.first?.cardSubtitle, !artist.isEmpty {
                            Text(artist).foregroundStyle(palette.textSecondary)
                        }
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                model.play(tracks, from: track)
                            } label: {
                                Text(track.title).frame(maxWidth: .infinity, minHeight: Tokens.minTarget, alignment: .leading)
                            }
                            .firstFocus(in: scope, when: index == 0)
                        }
                    }
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.vertical, Tokens.edge)
                }
                .focusRoot(scope)
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .pageBackground(palette)
        .task { await load() }
    }
}

/// A photo as big as the screen. Left and right go through the library.
struct PhotoView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let library: Int64
    let id: Int64
    @State private var photos: [Item] = []
    @State private var shown: Int64?
    @State private var error = ""
    @FocusState private var focused: Bool

    private func load() async {
        do {
            let page = try await client.items(library: library, offset: 0, limit: 500)
            photos = uniqued(page.items ?? []).filter(\.isPhoto)
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    private func move(_ by: Int) {
        guard let at = photos.firstIndex(where: { $0.id == (shown ?? id) }) else { return }
        let next = at + by
        if photos.indices.contains(next) { shown = photos[next].id }
    }

    var body: some View {
        let current = shown ?? id
        ZStack {
            Color.black.ignoresSafeArea()
            if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                ArtImage(url: client.originalURL(current), width: 1920, fit: true)
                    .id(current)
                    .accessibilityLabel(photos.first { $0.id == current }?.title ?? "Photo")
            }
        }
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            if direction == .left { move(-1) }
            if direction == .right { move(1) }
        }
        .onAppear { focused = true }
        .task { await load() }
    }
}

/// A row of the guide in the account's WittyTV theme. Focus takes the theme's highlight.
private struct GuideRowStyle: ButtonStyle {
    let look: TvColours
    let on: Bool

    private struct Row: View {
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let label: Configuration.Label
        let look: TvColours
        let on: Bool

        var body: some View {
            label
                .foregroundStyle(Color(hex: focused ? look.hiText : on ? look.liveText : look.cellText))
                .padding(.horizontal, Tokens.Space.s6)
                .padding(.vertical, Tokens.Space.s3)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.sm).fill(Color(hex: focused ? look.hi : on ? look.live : look.cell)))
                .scaleEffect(focused && !reduceMotion ? 1.02 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: focused)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label, look: look, on: on)
    }
}

/// How far through a programme, in whatever colour the words beside it are.
private struct ProgrammeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { room in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary).opacity(0.4)
                Capsule().fill(.primary).frame(width: room.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Live channels, from the server's guide: what's on each now and what's next, in the server's order,
/// in the theme this account chose for WittyTV. It isn't the grid: its colours are the theme's, not its layout.
/// Encrypted broadcasts are listed and say so: this server never decrypts one.
struct GuideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @State private var channels: [GuideChannel]?
    @State private var look: TvColours?
    @State private var error = ""
    @Namespace private var scope

    private func load() async {
        do {
            let guide = try await client.guide()
            await model.learnTvLook(from: guide, client: client)
            look = model.tvColours
            let fresh = uniqued(guide.channels ?? [])
            channels = fresh
            model.channels = fresh
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    /// The owner's logo for a channel if it has one and this account wants them, else its name.
    @ViewBuilder private func channelMark(_ channel: GuideChannel) -> some View {
        if model.tvLogos, let logo = channel.logo, logo.hasPrefix("/"), let url = client.mediaURL(logo) {
            HStack(spacing: Tokens.Space.s3) {
                Text(channel.number ?? "").font(.wmSection)
                ArtImage(url: url, width: 160, fit: true).frame(width: 160, height: 64)
            }
        } else {
            Text(channel.label).font(.wmSection).lineLimit(2)
        }
    }

    private func row(_ channel: GuideChannel, at now: Int64) -> some View {
        let on = channel.on(at: now)
        let next = channel.next(after: now)
        return HStack(alignment: .center, spacing: Tokens.Space.s6) {
            channelMark(channel).frame(width: 340, alignment: .leading)
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(on?.title ?? "Nothing on").lineLimit(1)
                if let on { ProgrammeBar(fraction: on.fraction(at: now)) }
                if let next {
                    Text("Next: \(next.title)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let on {
                Text("\(on.minutesLeft(at: now)) min left").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Tokens.minTarget, alignment: .leading)
    }

    var body: some View {
        let look = self.look ?? model.tvColours ?? TvLook.colours(saved: nil, ownerTheme: nil, ownerLayout: nil, ownerSkin: nil, app: model.tvAppColours)
        ZStack {
            Color(hex: look.bg).ignoresSafeArea()
            if let channels {
                // The times move by themselves, and nothing else on the page has to be drawn again for it.
                TimelineView(.periodic(from: .now, by: 30)) { time in
                    let now = Int64(time.date.timeIntervalSince1970)
                    ScrollView {
                        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            Text("TV guide").font(.wmPage).foregroundStyle(Color(hex: look.accent)).accessibilityAddTraits(.isHeader)
                            if channels.isEmpty {
                                EmptyMessage(title: "No channels yet", detail: "Channels are made on the server, under Settings, Channels and tuners.")
                            }
                            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                                if channel.canTune {
                                    NavigationLink(value: Route.channel(key: channel.key)) { row(channel, at: now) }
                                        .buttonStyle(GuideRowStyle(look: look, on: channel.on(at: now) != nil))
                                        .firstFocus(in: scope, when: index == 0)
                                        .accessibilityLabel("\(channel.label). \(channel.on(at: now)?.title ?? "Nothing on")")
                                } else {
                                    VStack(alignment: .leading) {
                                        Text(channel.label).font(.wmSection).foregroundStyle(Color(hex: look.text))
                                        Text(channel.encrypted ?? "").foregroundStyle(Color(hex: look.soft))
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        .padding(.horizontal, Tokens.gutter)
                        .padding(.vertical, Tokens.edge)
                    }
                    .focusRoot(scope)
                }
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .task { await load() }
    }
}

/// The picture alone: a live channel has nothing to scrub, so the arrows are free to change channel.
private struct LivePicture: UIViewRepresentable {
    let player: AVPlayer

    final class Picture: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Picture {
        let view = Picture()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: Picture, context: Context) {}
}

/// One channel, as a TV does it: up and down change channel and bring up what's on, Select brings it
/// up on its own, and Back leaves. It says when it's still starting, and leaves the channel on the way out.
struct ChannelPlayer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.scenePhase) private var scenePhase
    @State private var key: String
    @State private var player = AVPlayer()
    @State private var starting = true
    @State private var banner = true
    @State private var error = ""
    /// One name for as long as this is on screen, however often the view is redrawn.
    @State private var viewer = UUID().uuidString
    @FocusState private var focused: Bool

    init(start: String) { _key = State(initialValue: start) }

    private var channel: GuideChannel? { model.channels.first { $0.key == key } }

    private func tune() async {
        starting = true
        error = ""
        for _ in 0..<20 {
            do {
                let tuned = try await client.tune(key, viewer: viewer)
                guard let address = tuned.streamUrl ?? tuned.url, let url = client.mediaURL(address) else {
                    error = "The server sent an address that can't be used."
                    return
                }
                if Task.isCancelled { return }
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.play()
                starting = false
                return
            } catch let problem as APIError where problem.status == 503 {
                // Still starting: the server says to wait and ask again.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            } catch {
                if Task.isCancelled { return }
                let words = model.handle(error)
                if !words.isEmpty { self.error = words }
                return
            }
        }
        error = "\(channel?.name ?? "This channel") didn't start in time. Try it again in a moment."
    }

    private func leave(_ old: String) {
        let leaving = client, name = viewer
        Task { try? await leaving.leaveChannel(old, viewer: name) }
    }

    private func step(_ by: Int) {
        guard let next = ServerPages.channel(from: key, by: by, in: model.channels), next.key != key else { return }
        leave(key)
        key = next.key
        banner = true
    }

    private func bannerView(at now: Int64) -> some View {
        let look = model.tvColours ?? TvLook.colours(saved: nil, ownerTheme: nil, ownerLayout: nil, ownerSkin: nil, app: model.tvAppColours)
        return VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text(channel?.label ?? "").font(.wmSection).foregroundStyle(Color(hex: look.accent))
            if let on = channel?.on(at: now) {
                Text(on.title).font(.wmDisplay).lineLimit(2)
                if let sub = on.sub, !sub.isEmpty { Text(sub).lineLimit(1) }
                ProgrammeBar(fraction: on.fraction(at: now))
                Text("\(on.minutesLeft(at: now)) min left").font(.footnote)
            }
            if let next = channel?.next(after: now) {
                Text("Next: \(next.title)").font(.footnote).lineLimit(1)
            }
        }
        .foregroundStyle(Color(hex: look.text))
        .padding(Tokens.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).fill(Color(hex: look.panel).opacity(0.94)))
        .padding(Tokens.gutter)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LivePicture(player: player).ignoresSafeArea()
            if !error.isEmpty {
                ProblemView(words: error, retry: { Task { await tune() } })
            } else if starting {
                LoadingView()
            }
            if banner, error.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { time in
                    bannerView(at: Int64(time.date.timeIntervalSince1970))
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            if direction == .up { step(1) }
            if direction == .down { step(-1) }
        }
        .onPlayPauseCommand {
            if player.timeControlStatus == .paused { player.play() } else { player.pause() }
        }
        .onTapGesture { banner.toggle() }
        .onAppear { focused = true }
        .task(id: key) { await tune() }
        // What's on says itself for a moment on every change, then gets out of the way.
        .task(id: banner) {
            guard banner else { return }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { banner = false }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { player.play() } else { player.pause() }
        }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
            leave(key)
        }
    }
}
#endif
