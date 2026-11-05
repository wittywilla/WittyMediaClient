#if os(tvOS)
import AVKit
import SwiftUI
import WittyKit

// Apple TV's own screens for what iPhone and iPad leave to the server's page, as tvOS offers apps no
// web view. Live TV, its guide and recordings are in TvGuide.swift, TvChannel.swift and TvRecordings.swift.

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
                                // The listening player, as everywhere else: the lock screen, and on after leaving.
                                Task {
                                    let books = ListeningRules.keepsPlace(libraryType: await model.libraryType(library))
                                    model.startListening(tracks, start: ListeningStart(index, atSec: ListeningRules.placeOn(track, keepsPlace: books)), keepsPlace: books)
                                }
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
#endif
