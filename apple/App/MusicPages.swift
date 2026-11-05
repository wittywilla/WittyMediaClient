#if os(iOS) || os(visionOS)
import SwiftUI
import WittyKit

// The website's music, audiobook and podcast pages at phone size (web/src/pages/AudioLibrary.tsx, music/parts.tsx,
// music/CoverFlow.tsx, music/ArtistPage.tsx, music.css, audio.css): a library's Home with its cover flow and rows, and
// its Albums, Artists, Songs and Playlists; an album or a book; an artist or an author. Apple TV keeps its own
// (ListeningViews.swift).

// MARK: - Small parts

/// The website's `.seg`: choices side by side on `raised`, the chosen one filled with the text colour.
struct SegmentRow<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    let choices: [(Value, String)]
    let chosen: Value
    let label: String
    let choose: (Value) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    let on = choice.0 == chosen
                    Button { choose(choice.0) } label: {
                        Text(choice.1).pageFont(.secondary).fontWeight(.semibold)
                            .foregroundStyle(on ? palette.background : palette.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, Tokens.Space.s3)
                            .frame(minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md - 3, style: .continuous).fill(on ? palette.text : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The colour behind a music page, from its artwork: radial, 34% at the top fading to nothing (music.css `.mh-bg`).
private struct ArtGlow: View {
    @Environment(\.client) private var client
    let url: URL?
    @State private var colour = Color(red: 120 / 255, green: 120 / 255, blue: 135 / 255)

    var body: some View {
        GeometryReader { geo in
            let h = min(720, geo.size.height * 0.9)
            EllipticalGradient(stops: [.init(color: colour.opacity(0.34), location: 0), .init(color: colour.opacity(0.08), location: 0.6),
                                       .init(color: colour.opacity(0), location: 0.8)],
                               center: .top, startRadiusFraction: 0, endRadiusFraction: 0.7)
                .frame(width: geo.size.width, height: h + 120)
                .offset(y: -120)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url, let data = try? await client.imageData(url) else { return }
            let found = await Task.detached(priority: .utility) { () -> (Double, Double, Double)? in
                guard let small = decodeArt(data, maxPixels: 64) else { return nil }
                var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
                let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
                    guard let context = CGContext(data: raw.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(small, in: CGRect(x: 0, y: 0, width: 16, height: 16))
                    return true
                }
                guard drawn else { return nil }
                let c = ArtColour.pick(rgba: pixels)
                return (c.red, c.green, c.blue)
            }.value
            if let found { withAnimation(.easeOut(duration: 0.4)) { colour = Color(red: found.0 / 255, green: found.1 / 255, blue: found.2 / 255) } }
        }
    }
}

/// A shelf's head: its name in Section with an optional count, and "See all ›".
private struct MusicShelfHead: View {
    @Environment(\.palette) private var palette
    let title: String
    var count: Int?
    var seeAll: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text)
                if let count { Text(count.formatted()).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.textSecondary) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 2) {
                        Text("See all").font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(palette.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all, \(title)")
            }
        }
        .padding(.bottom, Tokens.Space.s3 - 12)
    }
}

/// An album's, book's or podcast's card: the square cover (2:3 for a book), the name and who and when.
struct AlbumCard: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let library: Int64
    let album: Album
    var book = false
    var noArtist = false

    var body: some View {
        NavigationLink(value: Route.listeningAlbum(library: library, album: album.title ?? "", artist: album.artist ?? "")) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let cover = album.coverItem, cover > 0 {
                        PosterArt(url: client.posterURL(id: cover), title: album.title ?? "Unknown", width: 160)
                    } else {
                        PlaceholderArt(title: album.title ?? "Unknown")
                    }
                }
                .aspectRatio(book ? 2.0 / 3.0 : 1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                Text(album.title ?? "Unknown album").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                    .lineLimit(2).multilineTextAlignment(.leading).padding(.top, Tokens.Space.s2)
                let sub = [noArtist ? nil : album.artist, album.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                Text(sub.isEmpty ? " " : sub).font(.system(size: 12)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// An artist's or author's round picture, with their initial behind it while it comes or when there's none.
private struct ArtistPhoto: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let library: Int64
    let name: String
    var big = false
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.card
                Text(String((name.isEmpty ? "?" : name).prefix(1)))
                    .font(.system(size: big ? min(80, geo.size.width * 0.4) : min(48, geo.size.width * 0.36), weight: .bold))
                    .foregroundStyle(palette.textHint)
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .shadow(color: .black.opacity(big ? 0.35 : 0.2), radius: big ? 14 : 4, y: big ? 8 : 2)
        .accessibilityHidden(true)
        .task(id: name) {
            guard let url = client.artistPhotoURL(library: library, name: name), let data = try? await client.imageData(url) else { return }
            image = await Task.detached(priority: .utility) { decodeArt(data, maxPixels: big ? 600 : 240) }.value
        }
    }
}

private struct ArtistCard: View {
    @Environment(\.palette) private var palette
    let library: Int64
    let artist: Artist
    let noun: (String, String)
    /// On a phone's Home row the count is left off, as the website's.
    var showCount = true

    var body: some View {
        NavigationLink(value: Route.artist(library: library, name: artist.name ?? "")) {
            VStack(spacing: 2) {
                ArtistPhoto(library: library, name: artist.name ?? "")
                Text(artist.name?.isEmpty == false ? artist.name! : "Unknown").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                    .lineLimit(1).padding(.top, 4)
                if showCount {
                    Text(MusicWords.count(artist.albums ?? 0, noun)).font(.system(size: 12)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// "See all" as a card at the end of a row: square, or round for artists.
private struct SeeAllCard: View {
    @Environment(\.palette) private var palette
    var round = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("See all").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(round ? AnyShape(Circle()).fill(palette.card) : AnyShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)).fill(palette.card))
        }
        .buttonStyle(PressStyle())
    }
}

/// A song in a row of them: the art, title, artist and album, length, and its menu.
private struct SongCard: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let song: Item
    let play: () -> Void

    var body: some View {
        let on = listening.now?.item.id == song.id
        HStack(spacing: 0) {
            Button(action: play) {
                HStack(spacing: Tokens.Space.s3) {
                    ZStack {
                        palette.card
                        ArtImage(url: client.posterURL(song), width: 48, blank: true)
                        if on && listening.isPlaying {
                            Image(systemName: "waveform").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                .padding(4).background(RoundedRectangle(cornerRadius: Tokens.Radius.sm).fill(palette.scrim))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                        Text([song.artist ?? song.albumArtist, song.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(song.runtimeSec.map { PlayerTime.format($0) } ?? "").font(.system(size: 13).monospacedDigit()).foregroundStyle(palette.textSecondary)
                }
                .padding(.leading, 8).padding(.trailing, 4).padding(.vertical, 6)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(song.title)")
            TrackMenu(track: song)
        }
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(on ? palette.accent.opacity(0.16) : palette.text.opacity(0.07)))
    }
}

/// A track's "⋯": play next, add to the queue, like, a station, a playlist, the artist, the album.
struct TrackMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let track: Item
    @State private var adding = false

    var body: some View {
        let liked = listening.likes.contains(track.id)
        Menu {
            Button { listening.playNext([track], client: client) } label: { Label("Play next", systemImage: "play.fill") }
            Button { listening.addToQueue([track], keepsPlace: false, client: client) } label: { Label("Add to the queue", systemImage: "plus") }
            Button { Task { _ = await listening.toggleLike(track.id) } } label: { Label(liked ? "Liked" : "Like", systemImage: liked ? "heart.fill" : "heart") }
            Button {
                Task {
                    if let songs = try? await client.radio(from: track.id), songs.count >= 2 {
                        listening.play(songs, start: ListeningStart(0), keepsPlace: false, client: client)
                    }
                }
            } label: { Label("Start a station from this", systemImage: "dot.radiowaves.left.and.right") }
            Button { adding = true } label: { Label("Add to a playlist…", systemImage: "text.badge.plus") }
            if let library = track.libraryId {
                if !(track.artist ?? "").isEmpty {
                    Button("Go to artist") { model.path.append(.artist(library: library, name: track.albumArtistName)) }
                }
                if !(track.album ?? "").isEmpty {
                    Button("Go to album") { model.path.append(.listeningAlbum(library: library, album: track.album ?? "", artist: track.albumArtistName)) }
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(palette.textSecondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("More for \(track.title)")
        .sheet(isPresented: $adding) { PlaylistSheet(items: [track]) }
        .task(id: track.libraryId) { await listening.loadLikes() }
    }
}

/// Add to a playlist, as a sheet from a list: New playlist, then this person's own.
struct PlaylistSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let items: [Item]
    @State private var lists: [TitleCollection]?
    @State private var making = false
    @State private var name = ""
    @State private var problem = ""

    private func add(_ id: Int64) async {
        do {
            try await client.addToCollection(id, items: items.map(\.id))
            dismiss()
        } catch { problem = model.handle(error) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !problem.isEmpty { Text(problem).foregroundStyle(palette.danger) }
                if making {
                    HStack {
                        TextField("Name", text: $name).submitLabel(.done)
                        Button("Make it") {
                            Task {
                                do {
                                    let made = try await client.makePlaylist(named: name.trimmingCharacters(in: .whitespaces))
                                    await add(made.id)
                                } catch { problem = model.handle(error) }
                            }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    Button { making = true } label: { Label("New playlist", systemImage: "plus") }
                }
                if let lists {
                    ForEach(lists) { list in Button(list.name) { Task { await add(list.id) } } }
                } else {
                    Text("Loading…").foregroundStyle(palette.textSecondary)
                }
            }
            .navigationTitle("Add to a playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { lists = ((try? await client.collections()) ?? []).filter(\.isPlaylist) }
    }
}

/// The website's track list: number (or the playing bars), title with artist and album, length, a heart and "⋯".
struct TrackListView: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.palette) private var palette
    let items: [Item]
    var showAlbum = false
    var episodes = false
    var discs = false
    var hearts = true
    let play: (Int) -> Void

    var body: some View {
        let manyDiscs = discs && Set(items.map { $0.discNo ?? 1 }).count > 1
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { at, track in
                if manyDiscs, at == 0 || (items[at - 1].discNo ?? 1) != (track.discNo ?? 1) {
                    Text("DISC \(track.discNo ?? 1)").font(.system(size: 13, weight: .bold)).tracking(0.9).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Space.s2).padding(.top, Tokens.Space.s4).padding(.bottom, Tokens.Space.s1)
                        .accessibilityAddTraits(.isHeader)
                }
                row(track, at: at)
                    .overlay(alignment: .top) { if at > 0 { palette.border.frame(height: 1) } }
            }
        }
    }

    private func row(_ track: Item, at: Int) -> some View {
        let on = listening.now?.item.id == track.id
        let liked = listening.likes.contains(track.id)
        let fraction = track.progressFraction ?? 0
        return HStack(spacing: 6) {
            Button { play(at) } label: {
                HStack(spacing: Tokens.Space.s3) {
                    Group {
                        if on && listening.isPlaying {
                            Image(systemName: "waveform").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.accentText)
                        } else {
                            Text(episodes ? "" : "\(track.track ?? at + 1)").font(.system(size: 13).monospacedDigit()).foregroundStyle(palette.textHint)
                        }
                    }
                    .frame(width: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title).font(.system(size: 14, weight: .medium)).foregroundStyle(on ? palette.accentText : palette.text)
                        if showAlbum {
                            Text([track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                        }
                        if episodes {
                            Text([track.aired, track.overview].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").prefix(160))
                                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottomLeading) {
                        if fraction > 0 {
                            GeometryReader { geo in Capsule().fill(palette.accent).frame(width: geo.size.width * fraction, height: 2) }
                                .frame(height: 2).offset(y: 4)
                        }
                    }
                    HStack(spacing: 4) {
                        if track.progress?.watched == true { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                        Text(track.runtimeSec.map { PlayerTime.format($0) } ?? "")
                    }
                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(palette.textSecondary)
                }
                .padding(Tokens.Space.s2)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(track.title)")
            .accessibilityValue(on ? "Playing" : "")
            if hearts && !episodes {
                Button { Task { _ = await listening.toggleLike(track.id) } } label: {
                    Image(systemName: liked ? "heart.fill" : "heart").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(liked ? palette.accentText : palette.textHint)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(liked ? "Remove \(track.title) from liked songs" : "Like \(track.title)")
                TrackMenu(track: track)
            }
        }
    }
}

/// The library's own tabs, sorts and tools: under the strip, the name kept for screen readers only on a phone.
private struct MusicHeader: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    let tab: MusicTab
    let sorts: [MusicSort]
    let sort: String
    let desc: Bool
    let admin: Bool
    let chooseTab: (MusicTab) -> Void
    let chooseSort: (String, Bool) -> Void
    let tools: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack {
                Text(library.name).accessibilityAddTraits(.isHeader).frame(width: 1, height: 1).opacity(0.01)
                Spacer(minLength: 0)
                if admin {
                    Button(action: tools) { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)) }
                        .squareButton()
                        .accessibilityLabel("More for \(library.name)")
                }
            }
            if !sorts.isEmpty {
                HStack(spacing: Tokens.Space.s2) {
                    CaptionLabel("Sort")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Tokens.Space.s1) {
                            ForEach(sorts, id: \.key) { option in
                                Button(option.label) { chooseSort(option.key, option.desc) }.chip(chosen: sort == option.key)
                            }
                        }
                    }
                    if let current = sorts.first(where: { $0.key == sort }) {
                        Button { chooseSort(current.key, !desc) } label: {
                            Image(systemName: desc ? "arrow.down" : "arrow.up").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.textSecondary).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(desc ? "\(current.label): last to first. Switch to first to last" : "\(current.label): first to last. Switch to last to first")
                    }
                }
            }
            SegmentRow(choices: MusicTab.tabs(libraryType: library.type), chosen: tab, label: "Parts of \(library.name)", choose: chooseTab)
                .padding(.top, Tokens.Space.s1)
        }
    }
}

// MARK: - A library

struct MusicLibraryPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    @State private var tab = MusicTab.home
    @State private var sort: String
    @State private var desc = false
    @State private var songView = ""
    @State private var artistFilter: String?
    @State private var solid = 0.0
    @State private var toolsOpen = false
    @State private var said = ""

    init(library: Library) {
        self.library = library
        _sort = State(initialValue: MusicSort.start(tab: .home, libraryType: library.type))
    }

    private var books: Bool { library.type == "audiobooks" }
    private var pods: Bool { library.type == "podcasts" }

    private func choose(_ next: MusicTab) {
        tab = next
        sort = MusicSort.start(tab: next, libraryType: library.type)
        desc = false
        if next != .songs { songView = "" }
        if next != .albums { artistFilter = nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                MusicHeader(library: library, tab: tab, sorts: MusicSort.options(tab: tab, libraryType: library.type, songView: songView),
                            sort: sort, desc: desc, admin: model.user?.isAdmin == true,
                            chooseTab: choose, chooseSort: { sort = $0; desc = $1 }, tools: { toolsOpen = true })
                    .padding(.horizontal, metrics.gutter)
                    .padding(.top, LibraryStrip.height + Tokens.Space.s3)
                if !said.isEmpty {
                    Text(said).pageFont(.secondary).foregroundStyle(palette.textSecondary).padding(.horizontal, metrics.gutter).padding(.top, Tokens.Space.s2)
                }
                Group {
                    switch tab {
                    case .home: MusicHomeTab(library: library, seeAll: choose)
                    case .albums: AlbumsTab(library: library, sort: sort, desc: desc, artist: $artistFilter)
                    case .artists: ArtistsTab(library: library, sort: sort, desc: desc)
                    case .songs: SongsTab(library: library, view: $songView, sort: sort, desc: desc)
                    case .playlists: PlaylistsTab(library: library, openSongs: { view in choose(.songs); songView = view })
                    }
                }
                .padding(.top, Tokens.Space.s4)
                PageFoot(notice: library.type == "podcasts" ? "webMedia" : "general")
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .stripSolidity($solid)
        .overlay(alignment: .top) { LibraryStrip(current: library.id, solid: solid) }
        .pageBackground(palette)
        .confirmationDialog(library.name, isPresented: $toolsOpen, titleVisibility: .visible) {
            Button("Scan for new files") {
                Task {
                    do { try await client.scan(library: library.id); said = "Looking for new files…" } catch { said = model.handle(error) }
                }
            }
            if pods { Button("Follow a podcast") { model.path.append(.page(ServerPages.path(library))) } }
        }
    }
}

/// Home: the cover flow and what's under it.
private struct MusicHomeTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    let seeAll: (MusicTab) -> Void
    @State private var home: MusicHome?
    @State private var failed = false
    @State private var hero = 0

    private var books: Bool { library.type == "audiobooks" }
    private var pods: Bool { library.type == "podcasts" }

    private func playAlbum(_ album: Album, at track: Int64? = nil) async {
        await playAlbum(title: album.title ?? "", artist: album.artist ?? "", at: track)
    }

    private func playAlbum(title: String, artist: String, at track: Int64? = nil) async {
        guard let tracks = try? await client.tracks(library: library.id, album: title, artist: artist), !tracks.isEmpty else { return }
        let chosen = track.flatMap { id in tracks.firstIndex { $0.id == id } }
        let from = chosen ?? (books ? MusicWords.resumeIndex(tracks) : 0)
        listening.play(tracks, start: ListeningStart(from, atSec: chosen != nil ? (tracks[from].resumeSeconds ?? 0) : 0), keepsPlace: books || pods, client: client)
    }

    var body: some View {
        Group {
            if failed {
                EmptyState(icon: "music.note", title: "This library wouldn't load", detail: "The server didn't answer. Try again in a moment.")
            } else if let home {
                if home.hero.isEmpty {
                    if pods {
                        EmptyState(icon: "mic", title: "Your podcasts will live here",
                                   detail: model.user?.isAdmin == true ? "Follow a podcast from this library's ⋯." : "Ask whoever runs this server to follow some shows.")
                    } else {
                        EmptyState(icon: "music.note", title: "Nothing here yet", detail: "Add audio files to this library's folders and scan it.")
                    }
                } else {
                    content(home)
                }
            } else {
                SkeletonGrid().padding(.horizontal, metrics.gutter)
            }
        }
        .task(id: library.id) {
            do { home = try await client.musicHome(library: library.id) } catch { failed = true }
        }
    }

    private func content(_ home: MusicHome) -> some View {
        let current = home.hero.indices.contains(hero) ? home.hero[hero] : home.hero[0]
        let noun = MusicWords.nouns(libraryType: library.type)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Tokens.Space.s2) {
                CoverFlow(covers: home.hero, library: library.id, tall: books, at: $hero)
                VStack(spacing: 2) {
                    NavigationLink(value: Route.listeningAlbum(library: library.id, album: current.title ?? "", artist: current.artist ?? "")) {
                        Text(current.title ?? "Unknown album").font(.system(size: 22.4, weight: .heavy)).tracking(-0.5)
                            .foregroundStyle(palette.text).multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 0) {
                        if let artist = current.artist, !artist.isEmpty, !pods {
                            NavigationLink(value: Route.artist(library: library.id, name: artist)) {
                                Text(artist).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text)
                            }
                            .buttonStyle(.plain)
                        }
                        let rest = [current.year.map(String.init), current.genre].compactMap { $0 }.filter { !$0.isEmpty }
                        if !rest.isEmpty {
                            Text(((current.artist ?? "").isEmpty || pods ? "" : " · ") + rest.joined(separator: " · "))
                                .font(.system(size: 15)).foregroundStyle(palette.textSecondary)
                        }
                    }
                    .lineLimit(1)
                }
                .padding(.horizontal, Tokens.Space.s3)
                HStack(spacing: Tokens.Space.s2) {
                    if !books && !pods {
                        Button {
                            Task {
                                if let all = try? await client.shuffledSongs(library: library.id), !all.isEmpty {
                                    listening.play(all, start: ListeningStart(0), keepsPlace: false, client: client)
                                }
                            }
                        } label: { Label("Play my music", systemImage: "play.fill") }
                        .buttonStyle(PillButtonStyle(strong: true))
                    }
                    Button { Task { await playAlbum(current) } } label: {
                        Label(books ? "Play this book" : pods ? "Play this show" : "Play this album", systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(strong: books || pods))
                }
                .padding(.top, Tokens.Space.s2)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, Tokens.Space.s4)
            .background(alignment: .top) { ArtGlow(url: current.coverItem.map { client.posterURL(id: $0) } ?? nil).frame(height: 720) }
            if !home.continue.isEmpty {
                shelf("Continue listening") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Tokens.Space.s4) {
                            ForEach(home.continue) { track in resume(track) }
                        }
                        .padding(.horizontal, metrics.gutter).padding(.vertical, 6)
                    }
                }
            }
            if !pods, !home.artists.isEmpty {
                shelf(books ? "Authors" : "Artists", seeAll: { seeAll(.artists) }) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Tokens.Space.s3) {
                            ForEach(home.artists, id: \.self) { artist in
                                ArtistCard(library: library.id, artist: artist, noun: noun, showCount: false).frame(width: 88)
                            }
                            if (home.counts?.artists ?? 0) > home.artists.count || home.artists.count > 4 {
                                SeeAllCard(round: true) { seeAll(.artists) }.frame(width: 88)
                            }
                        }
                        .padding(.horizontal, metrics.gutter).padding(.vertical, 6)
                    }
                }
            }
            shelf(books ? "Books" : pods ? "Shows" : "Albums", count: home.counts?.albums, seeAll: { seeAll(.albums) }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Tokens.Space.s4) {
                        ForEach(home.albums, id: \.key) { album in
                            AlbumCard(library: library.id, album: album, book: books).frame(width: 130)
                        }
                        if (home.counts?.albums ?? 0) > home.albums.count {
                            SeeAllCard { seeAll(.albums) }.frame(width: 110)
                        }
                    }
                    .padding(.horizontal, metrics.gutter).padding(.vertical, 6)
                }
            }
            if !books && !pods {
                shelf("Songs", count: home.counts?.songs, seeAll: { seeAll(.songs) }) { songGrid(home.songs) }
                if !home.recent.isEmpty {
                    shelf("Played lately", seeAll: { seeAll(.songs) }) { songGrid(home.recent) }
                }
            }
        }
    }

    private func shelf<Content: View>(_ title: String, count: Int? = nil, seeAll: (() -> Void)? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            MusicShelfHead(title: title, count: count, seeAll: seeAll).padding(.horizontal, metrics.gutter)
            content()
        }
        .padding(.bottom, 28)
    }

    /// Three songs to a column, the columns 84% of the width, scrolling sideways.
    private func songGrid(_ songs: [Item]) -> some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(60), spacing: 6), count: 3), spacing: Tokens.Space.s3) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { at, song in
                        SongCard(song: song) { listening.play(songs, start: ListeningStart(at), keepsPlace: false, client: client) }
                            .frame(width: geo.size.width * 0.84)
                    }
                }
                .padding(.horizontal, metrics.gutter).padding(.vertical, 2)
            }
        }
        .frame(height: 60 * 3 + 12 + 4)
    }

    private func resume(_ track: Item) -> some View {
        let fraction = track.progress.flatMap { p in track.runtimeSec.map { min(1, (p.positionSec ?? 0) / max($0, 1)) } } ?? 0
        return HStack(alignment: .top, spacing: Tokens.Space.s3) {
            ZStack {
                palette.card
                ArtImage(url: client.posterURL(track), width: 110, blank: true)
            }
            .frame(width: 110, height: 110 * 4 / 3)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.album ?? track.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text).lineLimit(2)
                Text(track.artist ?? track.albumArtist ?? "").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                Text("\(Int((fraction * 100).rounded()))% listened").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.border)
                        Capsule().fill(palette.accent).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3).padding(.vertical, 4)
                Spacer(minLength: 0)
                Button {
                    Task { await playAlbum(title: track.album ?? "", artist: track.albumArtist ?? track.artist ?? "", at: track.id) }
                } label: { Label("Resume", systemImage: "play.fill") }
                .pageButton(.secondary)
            }
        }
        .padding(Tokens.Space.s2)
        .frame(width: min(340, screenSize.width * 0.84), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.text.opacity(0.07)))
    }
}

/// The website's round pill buttons on music Home: Play my music in the text colour, the album's in `raised`.
private struct PillButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    var strong = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: strong ? .bold : .semibold))
            .foregroundStyle(strong ? palette.background : palette.text)
            .padding(.horizontal, Tokens.Space.s4)
            .frame(minHeight: 44)
            .background(Capsule().fill(strong ? palette.text : palette.card))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
    }
}

/// Covers in a row with the front one facing out and its neighbours turned away; a swipe or a tap on one moves to
/// it, a tap on the front opens it (music/CoverFlow.tsx at phone size).
private struct CoverFlow: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var calm
    let covers: [Album]
    let library: Int64
    let tall: Bool
    @Binding var at: Int
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width * 0.58, screenSize.height * 0.42)
            ZStack {
                ForEach(Array(covers.enumerated()), id: \.offset) { i, album in
                    let d = i - at
                    if abs(d) <= 3 {
                        let sign = Double(max(-1, min(1, d)))
                        cover(album, size: size)
                            .rotation3DEffect(.degrees(d == 0 ? 0 : sign * -24), axis: (x: 0, y: 1, z: 0), perspective: 1 / 1.2)
                            .scaleEffect(d == 0 ? 1 : 1 - Double(abs(d)) * 0.04)
                            .offset(x: d == 0 ? 0 : CGFloat(d) * size * 0.72 + CGFloat(sign) * size * 0.28)
                            .opacity(d == 0 ? 1 : 1.15 - Double(abs(d)) * 0.28)
                            .zIndex(Double(5 - abs(d)))
                            .onTapGesture {
                                if d == 0 { model.path.append(.listeningAlbum(library: library, album: album.title ?? "", artist: album.artist ?? "")) } else { move(to: i) }
                            }
                            .accessibilityHidden(d != 0)
                            .accessibilityLabel(d == 0 ? "Open \(album.title ?? "")\((album.artist ?? "").isEmpty ? "" : " by \(album.artist!)")" : "")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(width: geo.size.width, height: size * 1.2, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
                guard abs(drag.translation.width) > 36, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                move(to: at + (drag.translation.width < 0 ? 1 : -1))
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Covers")
            .accessibilityAdjustableAction { direction in
                move(to: at + (direction == .increment ? 1 : -1))
            }
        }
        .frame(height: min(screenSize.width * 0.58, screenSize.height * 0.42) * 1.2)
    }

    private func move(to index: Int) {
        let next = max(0, min(covers.count - 1, index))
        withAnimation(calm ? nil : .easeOut(duration: 0.35)) { at = next }
    }

    private func cover(_ album: Album, size: CGFloat) -> some View {
        let url = album.coverItem.flatMap { $0 > 0 ? client.posterURL(id: $0) : nil }
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        return VStack(spacing: 6) {
            Group {
                if let url { PosterArt(url: url, title: album.title ?? "Unknown", width: size) } else { PlaceholderArt(title: album.title ?? "Unknown") }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            if let url {
                PosterArt(url: url, title: "", width: size)
                    .frame(width: size, height: size)
                    .scaleEffect(x: 1, y: -1)
                    .frame(width: size, height: size * 0.18, alignment: .top)
                    .clipShape(shape)
                    .mask(LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, alignment: .top)
    }
}

/// Albums, books or podcasts, with how many, a genre to narrow it, and the grid.
private struct AlbumsTab: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    let sort: String
    let desc: Bool
    @Binding var artist: String?
    @State private var albums: [Album]?
    @State private var genres: [String] = []
    @State private var genre = ""

    private var books: Bool { library.type == "audiobooks" }
    private var pods: Bool { library.type == "podcasts" }

    var body: some View {
        let noun = pods ? ("podcast", "podcasts") : books ? ("book", "books") : ("album", "albums")
        let shown = albums.map { MusicSort.reversed(sort: sort, desc: desc) ? $0.reversed() : $0 }
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            FilterBar {
                if let albums { Text(MusicWords.count(albums.count, noun)).pageFont(.secondary).foregroundStyle(palette.textHint) }
                if let artist {
                    Button { self.artist = nil } label: { Text("\(artist.isEmpty ? "Unknown" : artist) ✕") }.pageButton(.ghost)
                }
            } trailing: {
                if !genres.isEmpty { GenrePicker(genres: genres, genre: $genre) }
            }
            .padding(.horizontal, metrics.gutter)
            if let shown {
                if shown.isEmpty {
                    EmptyState(icon: "music.note", title: "Nothing here", detail: genre.isEmpty ? "Add audio files to this library's folders and scan it." : "Nothing in this genre.")
                } else {
                    LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
                        ForEach(shown, id: \.key) { album in AlbumCard(library: library.id, album: album, book: books) }
                    }
                    .padding(.horizontal, metrics.gutter)
                }
            } else {
                SkeletonGrid().padding(.horizontal, metrics.gutter)
            }
        }
        .task(id: "\(sort)|\(genre)|\(artist ?? "∅")") {
            albums = nil
            if let artist {
                albums = (try? await client.albums(library: library.id, sort: sort, artist: artist)) ?? []
            } else {
                albums = (try? await client.albums(library: library.id, sort: sort, genre: genre)) ?? []
            }
        }
        .task(id: library.id) { if !pods { genres = (try? await client.genres(library: library.id)) ?? [] } }
    }
}

/// The count and buttons on the left, a search or a genre on the right, wrapping on a phone.
private struct FilterBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        FlowRow(spacing: Tokens.Space.s2, lineSpacing: Tokens.Space.s2, centred: false) {
            leading
            trailing
        }
    }
}

private struct GenrePicker: View {
    @Environment(\.palette) private var palette
    let genres: [String]
    @Binding var genre: String

    var body: some View {
        Menu {
            Button { genre = "" } label: { if genre.isEmpty { Label("All genres", systemImage: "checkmark") } else { Text("All genres") } }
            ForEach(genres, id: \.self) { name in
                Button { genre = name } label: { if genre == name { Label(name, systemImage: "checkmark") } else { Text(name) } }
            }
        } label: {
            HStack(spacing: 6) {
                Text(genre.isEmpty ? "All genres" : genre).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .pageFont(.button)
            .foregroundStyle(palette.text)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(palette.control, lineWidth: 1))
        }
        .accessibilityLabel("Genre")
        .accessibilityValue(genre.isEmpty ? "All genres" : genre)
    }
}

private struct FindField: View {
    @Environment(\.palette) private var palette
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(palette.textHint)
            TextField(placeholder, text: $text).pageFont(.body).foregroundStyle(palette.text).submitLabel(.search).autocorrectionDisabled()
        }
        .padding(.horizontal, Tokens.Space.s3)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(palette.control, lineWidth: 1))
        .accessibilityLabel(placeholder)
    }
}

private struct ArtistsTab: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    let sort: String
    let desc: Bool
    @State private var artists: [Artist]?
    @State private var query = ""

    var body: some View {
        let books = library.type == "audiobooks"
        var shown = (artists ?? []).filter { query.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(query) }
        if sort == "albums" { shown.sort { ($0.albums ?? 0, $1.name ?? "") < ($1.albums ?? 0, $0.name ?? "") } }
        if desc { shown.reverse() }
        return VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                if let artists {
                    Text(MusicWords.count(artists.count, books ? ("author", "authors") : ("artist", "artists"))).pageFont(.secondary).foregroundStyle(palette.textHint)
                }
                FindField(placeholder: books ? "Find an author…" : "Find an artist…", text: $query)
            }
            .padding(.horizontal, metrics.gutter)
            if artists == nil {
                SkeletonGrid().padding(.horizontal, metrics.gutter)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: Tokens.Space.s4, alignment: .top)], spacing: Tokens.Space.s6) {
                    ForEach(shown, id: \.self) { artist in
                        ArtistCard(library: library.id, artist: artist, noun: books ? ("book", "books") : ("album", "albums"))
                    }
                }
                .padding(.horizontal, metrics.gutter)
            }
        }
        .task(id: library.id) { artists = (try? await client.artists(library: library.id)) ?? [] }
    }
}

private struct SongsTab: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    @Binding var view: String
    let sort: String
    let desc: Bool
    @State private var songs: [Item]?
    @State private var genres: [String] = []
    @State private var genre = ""
    @State private var query = ""
    @State private var search = ""

    var body: some View {
        let total = (songs ?? []).reduce(0) { $0 + ($1.runtimeSec ?? 0) }
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            SegmentRow(choices: SongViews.all, chosen: view, label: "Which songs") { view = $0 }
                .padding(.horizontal, metrics.gutter)
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                FlowRow(spacing: Tokens.Space.s2, lineSpacing: Tokens.Space.s2, centred: false) {
                    if let songs {
                        Text("\(songs.count.formatted()) \(songs.count == 1 ? "song" : "songs")\(total > 0 ? " · \(MusicWords.runtime(total))" : "")")
                            .pageFont(.secondary).foregroundStyle(palette.textHint)
                    }
                    Button { if let songs { listening.play(songs, start: ListeningStart(0), keepsPlace: false, client: client) } } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .pageButton(.primary)
                    .disabled(songs?.isEmpty ?? true)
                    Button("Shuffle") { if let songs { listening.play(songs.shuffled(), start: ListeningStart(0), keepsPlace: false, client: client) } }
                        .pageButton(.secondary)
                        .disabled(songs?.isEmpty ?? true)
                }
                FindField(placeholder: "Find a song…", text: $query)
                if !genres.isEmpty { GenrePicker(genres: genres, genre: $genre) }
            }
            .padding(.horizontal, metrics.gutter)
            if let songs {
                if songs.isEmpty {
                    let words = SongViews.empty(view: view, filtered: !search.isEmpty || !genre.isEmpty)
                    EmptyState(icon: "music.note", title: words.title, detail: words.text)
                } else {
                    TrackListView(items: songs, showAlbum: true) { at in listening.play(songs, start: ListeningStart(at), keepsPlace: false, client: client) }
                        .padding(.horizontal, metrics.gutter - Tokens.Space.s2)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.s8)
            }
        }
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            search = query.trimmingCharacters(in: .whitespaces)
        }
        .task(id: "\(view)|\(sort)|\(desc)|\(genre)|\(search)") {
            songs = nil
            songs = (try? await client.songs(library: library.id, view: view, sort: sort, desc: desc, genre: genre, search: search, limit: 2000)) ?? []
        }
        .task(id: library.id) { genres = (try? await client.genres(library: library.id)) ?? [] }
    }
}

private struct PlaylistsTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    let openSongs: (String) -> Void
    @State private var lists: [TitleCollection]?
    @State private var said = ""

    private func play(_ view: String) async {
        guard let items = try? await client.songs(library: library.id, view: view, sort: "title", desc: false, genre: "", search: "", limit: 500) else { return }
        if items.isEmpty { said = "Nothing there yet"; return }
        listening.play(items, start: ListeningStart(0), keepsPlace: false, client: client)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Tokens.Space.s2) { content() }
            .padding(Tokens.Space.s2)
            .frame(minHeight: 68)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.text.opacity(0.07)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if !said.isEmpty { Text(said).pageFont(.secondary).foregroundStyle(palette.textSecondary) }
            ForEach(SongViews.built, id: \.view) { built in
                card {
                    Button { openSongs(built.view) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(built.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                            Text(built.about).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { Task { await play(built.view) } } label: {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(palette.onAccent)
                            .frame(width: 44, height: 44).background(Circle().fill(palette.accent))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Play \(built.name)")
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Your playlists").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                NavigationLink(value: Route.page(ServerPages.collections)) {
                    Text("Make one, or a smart one").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textSecondary).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Tokens.Space.s6)
            if let lists {
                let mine = lists.filter { ($0.system ?? "").isEmpty }
                if mine.isEmpty {
                    Text("None yet. Add any song to a playlist from its menu, or make a smart one in Collections that keeps itself up to date.")
                        .pageFont(.body).foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(mine) { list in
                        NavigationLink(value: Route.page("/collections/\(list.id)")) {
                            card {
                                ZStack {
                                    palette.card
                                    if let cover = list.coverId, cover > 0 { ArtImage(url: client.posterURL(id: cover), width: 52, blank: true) }
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(list.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                                    Text(list.kind == "smart" ? "Smart playlist" : "\(list.count ?? 0) \((list.count ?? 0) == 1 ? "item" : "items")")
                                        .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Tokens.Space.s4)
            }
        }
        .padding(.horizontal, metrics.gutter)
        .task { lists = (try? await client.collections()) ?? [] }
    }
}

// MARK: - An album, a book or a podcast

struct MusicAlbumPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Int64
    let album: String
    let artist: String
    @State private var tracks: [Item]?
    @State private var others: [Album] = []
    @State private var kind = "music"
    @State private var said = ""

    private var books: Bool { kind != "music" }
    private var pods: Bool { kind == "podcasts" }

    private func say(_ words: String) {
        said = words
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if said == words { said = "" } }
    }

    private func play(_ tracks: [Item], at: Int) {
        let track = tracks[at]
        if let disc = track.cdDisc {
            model.path.append(.page("/cd/\(disc)?play=1&track=\(track.track ?? 1)"))
        } else {
            listening.play(tracks, start: ListeningStart(at, atSec: books ? (track.resumeSeconds ?? 0) : 0), keepsPlace: books, client: client)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                if let tracks {
                    content(tracks)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
                }
            }
            .padding(.top, LibraryStrip.height)
            .padding(.bottom, Tokens.Space.s6)
        }
        .background(alignment: .top) { ArtGlow(url: tracks?.first { $0.libraryId != nil }.flatMap { client.posterURL($0) }).frame(height: 720) }
        .pageBackground(palette)
        .task(id: "\(library)|\(album)|\(artist)") {
            if let type = listening.libraryTypes[library] { kind = type } else if let found = try? await client.libraries().first(where: { $0.id == library }) {
                listening.libraryTypes[library] = found.type
                kind = found.type
            }
            tracks = (try? await client.tracks(library: library, album: album, artist: artist)) ?? []
            if !artist.isEmpty {
                others = ((try? await client.albums(library: library, sort: "year", artist: artist)) ?? []).filter { $0.title != album }
            }
            await listening.loadLikes()
        }
    }

    private func content(_ tracks: [Item]) -> some View {
        let started = books && tracks.contains { ($0.progress?.positionSec ?? 0) > 5 }
        let discs = Array(Set(tracks.compactMap(\.cdDisc))).sorted()
        let allLiked = !tracks.isEmpty && tracks.allSatisfy { listening.likes.contains($0.id) }
        let versions = others.filter { MusicWords.baseTitle($0.title ?? "") == MusicWords.baseTitle(album) }
        let more = others.filter { MusicWords.baseTitle($0.title ?? "") != MusicWords.baseTitle(album) }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Group {
                    if let cover = tracks.first {
                        PosterArt(url: client.posterURL(cover), title: album.isEmpty ? "Unknown" : album, width: 240)
                    } else {
                        PlaceholderArt(title: album.isEmpty ? "Unknown" : album)
                    }
                }
                .aspectRatio(books && !pods ? 2.0 / 3.0 : 1, contentMode: .fit)
                .frame(width: min(screenSize.width * 0.6, 240))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .padding(.bottom, Tokens.Space.s5)
                Text(pods ? "PODCAST" : books ? "AUDIOBOOK" : "ALBUM").font(.system(size: 11, weight: .semibold)).tracking(0.77).foregroundStyle(palette.textSecondary)
                Text(album.isEmpty ? "Unknown album" : album).pageFont(.display).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Tokens.Space.s1)
                if pods {
                    Text(artist).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.accentText)
                } else {
                    NavigationLink(value: Route.artist(library: library, name: artist)) {
                        Text(artist.isEmpty ? "Unknown" : artist).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.accentText)
                    }
                    .buttonStyle(.plain)
                }
                Text(MusicWords.albumFacts(tracks: tracks, kind: kind)).pageFont(.body).foregroundStyle(palette.textSecondary)
                FlowRow(spacing: Tokens.Space.s2, lineSpacing: Tokens.Space.s2, centred: false) {
                    Button { play(tracks, at: books && !pods ? MusicWords.resumeIndex(tracks) : 0) } label: {
                        Label(pods ? "Play newest" : started ? "Continue" : "Play", systemImage: "play.fill")
                    }
                    .pageButton(.primary)
                    .disabled(tracks.isEmpty)
                    ForEach(Array(discs.enumerated()), id: \.offset) { at, disc in
                        NavigationLink(value: Route.page("/cd/\(disc)?play=1")) {
                            Label(discs.count > 1 ? "Disc \(at + 1)" : "Insert disc", systemImage: "opticaldisc")
                        }
                        .pageButton(.secondary)
                    }
                    if !books {
                        Button("Shuffle") { listening.play(tracks.shuffled(), start: ListeningStart(0), keepsPlace: false, client: client) }.pageButton(.secondary)
                        if let first = tracks.first {
                            Button {
                                Task {
                                    if let songs = try? await client.radio(from: first.id), songs.count >= 2 {
                                        listening.play(songs, start: ListeningStart(0), keepsPlace: false, client: client)
                                    } else { say("There isn't enough here yet to make a station from this song") }
                                }
                            } label: { Label("Station", systemImage: "dot.radiowaves.left.and.right") }
                            .pageButton(.ghost)
                        }
                    }
                    Button("Play next") { listening.playNext(tracks, client: client); say("Plays next") }.pageButton(.ghost)
                    Button("Add to queue") { listening.addToQueue(tracks, keepsPlace: books, client: client); say("Added to the queue") }.pageButton(.ghost)
                    if !books {
                        Button {
                            Task { for track in tracks where listening.likes.contains(track.id) == allLiked { _ = await listening.toggleLike(track.id) } }
                        } label: { Label(allLiked ? "Liked" : "Like all", systemImage: allLiked ? "heart.fill" : "heart") }
                        .pageButton(.ghost)
                    }
                }
                .padding(.top, Tokens.Space.s3)
                if !said.isEmpty { Text(said).pageFont(.secondary).foregroundStyle(palette.textSecondary).padding(.top, Tokens.Space.s2) }
                if let about = tracks.first?.overview, !about.isEmpty, !pods {
                    Text(about).font(.system(size: 14)).foregroundStyle(palette.textSecondary).lineLimit(4).padding(.top, Tokens.Space.s3)
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, Tokens.Space.s2)
            .padding(.bottom, Tokens.Space.s6)
            TrackListView(items: tracks, episodes: pods, discs: !books, hearts: !books) { at in play(tracks, at: at) }
                .padding(.horizontal, metrics.gutter - Tokens.Space.s2)
            if !versions.isEmpty { albumRow("Other versions", versions, seeAll: nil) }
            if !more.isEmpty, !books { albumRow("More by \(artist)", more, seeAll: .artist(library: library, name: artist)) }
            PageFoot(notice: pods ? "webMedia" : "metadata")
        }
    }

    private func albumRow(_ title: String, _ albums: [Album], seeAll: Route?) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        HStack(spacing: 2) { Text("See all"); Image(systemName: "chevron.right") }
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textSecondary).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Tokens.Space.s4) {
                    ForEach(albums, id: \.key) { other in AlbumCard(library: library, album: other, noArtist: true).frame(width: 130) }
                }
                .padding(.horizontal, metrics.gutter).padding(.vertical, 6)
            }
        }
        .padding(.top, 28)
    }
}

// MARK: - An artist or an author

struct MusicArtistPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Int64
    let name: String
    @State private var info: ArtistPageInfo?
    @State private var failed = false
    @State private var newestFirst = true
    @State private var kind = "music"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                if failed {
                    EmptyState(icon: "music.note", title: "Nobody by that name here", detail: "They may have been moved or renamed.")
                } else if let info {
                    content(info)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
                }
            }
            .padding(.top, LibraryStrip.height)
            .padding(.bottom, Tokens.Space.s6)
        }
        .background(alignment: .top) { ArtGlow(url: client.artistPhotoURL(library: library, name: name)).frame(height: 720) }
        .pageBackground(palette)
        .task(id: "\(library)|\(name)") {
            if let type = listening.libraryTypes[library] { kind = type } else if let found = try? await client.libraries().first(where: { $0.id == library }) {
                listening.libraryTypes[library] = found.type
                kind = found.type
            }
            do { info = try await client.artistPage(library: library, name: name) } catch { failed = true }
            await listening.loadLikes()
        }
    }

    private func content(_ info: ArtistPageInfo) -> some View {
        let books = kind == "audiobooks"
        let total = info.tracks.reduce(0) { $0 + ($1.runtimeSec ?? 0) }
        let top = info.top.isEmpty ? Array(info.tracks.prefix(5)) : info.top
        let split = info.discography(newestFirst: newestFirst, books: books)
        let facts = [MusicWords.count(info.albums.count, books ? ("book", "books") : ("album", "albums")),
                     MusicWords.count(info.tracks.count, ("song", "songs")), MusicWords.runtime(total), info.genres.prefix(3).joined(separator: ", ")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Tokens.Space.s1) {
                ArtistPhoto(library: library, name: name, big: true)
                    .frame(width: min(screenSize.width * 0.52, 200))
                    .padding(.bottom, Tokens.Space.s5)
                Text(books ? "AUTHOR" : "ARTIST").font(.system(size: 11, weight: .semibold)).tracking(0.77).foregroundStyle(palette.textSecondary)
                Text(name.isEmpty ? "Unknown" : name).pageFont(.display).foregroundStyle(palette.text).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(facts).pageFont(.body).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                FlowRow(spacing: Tokens.Space.s2, lineSpacing: Tokens.Space.s2) {
                    Button { listening.play(info.tracks, start: ListeningStart(0), keepsPlace: books, client: client) } label: { Label("Play", systemImage: "play.fill") }
                        .pageButton(.primary)
                    if !books {
                        Button("Shuffle") { listening.play(info.tracks.shuffled(), start: ListeningStart(0), keepsPlace: false, client: client) }.pageButton(.secondary)
                        if let first = info.tracks.first {
                            Button {
                                Task {
                                    if let songs = try? await client.radio(from: first.id), songs.count >= 2 {
                                        listening.play(songs, start: ListeningStart(0), keepsPlace: false, client: client)
                                    }
                                }
                            } label: { Label("Station", systemImage: "dot.radiowaves.left.and.right") }
                            .pageButton(.ghost)
                        }
                    }
                }
                .padding(.top, Tokens.Space.s3)
                if let bio = info.bio, !bio.isEmpty {
                    Text(bio).pageFont(.body).foregroundStyle(palette.text).lineSpacing(4).padding(.top, Tokens.Space.s3)
                    if let link = info.bioUrl.flatMap(URL.init(string:)) {
                        (Text("From ") + Text(.init("[Wikipedia](\(link.absoluteString))")) + Text(", available under CC BY-SA 4.0. It's the article with this name, which may not always be the right person."))
                            .font(.system(size: 12)).foregroundStyle(palette.textSecondary).tint(palette.textSecondary).padding(.top, Tokens.Space.s2)
                    }
                } else if info.online != true, model.user?.isAdmin == true {
                    Text("Biographies and photos can come from Wikipedia, if you turn on online music information in Settings. An artist.jpg in their folder is used first.")
                        .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, Tokens.Space.s2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.gutter)
            .padding(.top, Tokens.Space.s2)
            .padding(.bottom, Tokens.Space.s6)
            if !top.isEmpty, !books {
                Text(info.top.isEmpty ? "Songs" : "Your most played").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, metrics.gutter).padding(.bottom, Tokens.Space.s3)
                TrackListView(items: top, showAlbum: true) { at in listening.play(top, start: ListeningStart(at), keepsPlace: false, client: client) }
                    .padding(.horizontal, metrics.gutter - Tokens.Space.s2)
                    .padding(.bottom, 28)
            }
            HStack {
                Text(books ? "Books" : "Discography").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Menu {
                    Button { newestFirst = true } label: { if newestFirst { Label("Newest first", systemImage: "checkmark") } else { Text("Newest first") } }
                    Button { newestFirst = false } label: { if !newestFirst { Label("By title", systemImage: "checkmark") } else { Text("By title") } }
                } label: {
                    HStack(spacing: 6) {
                        Text(newestFirst ? "Newest first" : "By title")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .pageFont(.button).foregroundStyle(palette.text)
                    .padding(.horizontal, Tokens.Space.s3).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(palette.control, lineWidth: 1))
                }
                .accessibilityLabel("Sort albums")
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, Tokens.Space.s3)
            LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
                ForEach(split.full, id: \.key) { album in AlbumCard(library: library, album: album, book: books, noArtist: true) }
            }
            .padding(.horizontal, metrics.gutter)
            if !split.small.isEmpty {
                Text("Singles and EPs").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, metrics.gutter).padding(.top, 28).padding(.bottom, Tokens.Space.s3)
                LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
                    ForEach(split.small, id: \.key) { album in AlbumCard(library: library, album: album, noArtist: true) }
                }
                .padding(.horizontal, metrics.gutter)
            }
            PageFoot()
        }
    }
}
#endif
