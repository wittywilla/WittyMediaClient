import AVKit
import SwiftUI
import WittyKit

// Apple TV's own screens for what iPhone and iPad leave to the server's page, as tvOS offers apps no
// web view. They're compiled for every device, as the routes they answer to are, and only Apple TV
// goes to them. Written without a Mac: see docs/PLATFORMS.md for how far that's been checked.

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
        #if os(tvOS)
        .onMoveCommand { direction in
            if direction == .left { move(-1) }
            if direction == .right { move(1) }
        }
        #endif
        .onAppear { focused = true }
        .task { await load() }
    }
}

/// Live channels, from the server's guide. Encrypted broadcasts are listed and say so: this server
/// never decrypts one.
struct GuideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @State private var channels: [GuideChannel]?
    @State private var error = ""
    @Namespace private var scope

    private func load() async {
        do {
            channels = uniqued(try await client.guide().channels ?? [])
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    var body: some View {
        ZStack {
            if let channels {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        Text("TV guide").font(.wmPage).accessibilityAddTraits(.isHeader)
                        if channels.isEmpty {
                            EmptyMessage(title: "No channels yet", detail: "Channels are made on the server, under Settings, Channels and tuners.")
                        }
                        ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                            if channel.canTune {
                                NavigationLink(value: Route.channel(key: channel.key, name: channel.name)) {
                                    Text(channel.label).frame(maxWidth: .infinity, minHeight: Tokens.minTarget, alignment: .leading)
                                }
                                .firstFocus(in: scope, when: index == 0)
                            } else {
                                VStack(alignment: .leading) {
                                    Text(channel.label)
                                    Text(channel.encrypted ?? "").foregroundStyle(palette.textSecondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
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

/// One channel, in the system's player. It says when it's still starting, and leaves the channel on the way out.
struct ChannelPlayer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    let key: String
    let name: String
    @State private var player: AVPlayer?
    @State private var error = ""
    // The same name for as long as this is on screen, however often the view is redrawn.
    @State private var viewer = UUID().uuidString

    private func tune() async {
        for _ in 0..<20 {
            do {
                let tuned = try await client.tune(key, viewer: viewer)
                guard let address = tuned.streamUrl ?? tuned.url, let url = client.mediaURL(address) else {
                    error = "The server sent an address that can't be used."
                    return
                }
                let starting = AVPlayer(url: url)
                player = starting
                starting.play()
                return
            } catch let problem as APIError where problem.status == 503 {
                // Still starting: the server says to wait and ask again.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            } catch {
                let words = model.handle(error)
                if !words.isEmpty { self.error = words }
                return
            }
        }
        error = "\(name) didn't start in time. Try it again in a moment."
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await tune() } })
            } else {
                LoadingView()
            }
        }
        .task { await tune() }
        .onDisappear {
            player?.pause()
            let leaving = client
            let channel = key, name = viewer
            Task { try? await leaving.leaveChannel(channel, viewer: name) }
        }
    }
}
