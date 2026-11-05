import SwiftUI
import WittyKit

// Music, audiobooks and podcasts: a library, an artist or author, an album or book, and its tracks,
// as Android's ui/ListeningScreens.kt. Choosing a track starts a queue in `Listening`, which carries
// on whatever happens to these screens. What isn't here, such as playlists, lyrics and following a
// podcast, is one button away on the server's own page, behind More.

extension AppModel {
    /// Which kind of library, for what lists of tracks don't say. Asked for once.
    func libraryType(_ id: Int64) async -> String {
        if let known = libraries.first(where: { $0.id == id })?.type { return known }
        if let known = listening.libraryTypes[id] { return known }
        for library in (try? await client.libraries()) ?? [] { listening.libraryTypes[library.id] = library.type }
        return listening.libraryTypes[id] ?? ""
    }

    /// A queue starts. Apple TV goes to the player, as there's little else to look at from across a
    /// room. A phone or a tablet stays where it is, with the mini player showing.
    func startListening(_ tracks: [Item], start: ListeningStart, keepsPlace: Bool) {
        listening.play(tracks, start: start, keepsPlace: keepsPlace, client: client)
        #if os(tvOS)
        listening.screenShown = true
        #endif
    }

    /// Play on a track shown on its own, on Home: its album or book, from that track.
    func playTrack(_ track: Item) {
        guard let library = track.libraryId else { return }
        let client = client
        Task {
            let books = ListeningRules.keepsPlace(libraryType: await libraryType(library))
            do {
                let tracks = uniqued(try await client.tracks(library: library, album: track.album ?? "", artist: track.albumArtistName))
                guard !tracks.isEmpty else { return }
                let index = tracks.firstIndex { $0.id == track.id } ?? 0
                startListening(tracks, start: ListeningStart(index, atSec: ListeningRules.placeOn(tracks[index], keepsPlace: books)), keepsPlace: books)
            } catch {
                let words = handle(error)
                if !words.isEmpty { notice = words }
            }
        }
    }
}

/// Play on Home: a song or a chapter plays from its album straight away, as on Android. Anything else
/// opens where it's played.
struct PlayOrOpen<Label: View>: View {
    @EnvironmentObject private var model: AppModel
    let item: Item
    let route: Route
    @ViewBuilder let label: Label

    var body: some View {
        if item.isAudio {
            Button { model.playTrack(item) } label: { label }
        } else {
            NavigationLink(value: route) { label }
        }
    }
}

// MARK: - Pieces

/// A round button with a picture and no words, except for those who can't see it: Android's RoundButton.
struct RoundButton: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let symbol: String
    let label: String
    var primary = false
    var selected = false
    var size: CGFloat?
    let action: () -> Void

    var body: some View {
        let side = size ?? metrics.minTarget
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: side * 0.4, weight: .semibold))
                .foregroundStyle(primary ? palette.onAccent : (selected ? palette.accentText : palette.text))
                .frame(width: side, height: side)
                .contentShape(Circle())
        }
        .buttonStyle(SurfaceStyle(fill: primary ? palette.accent : (selected ? palette.border : nil), radius: 999))
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "On" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// One of a set of choices, which says it's chosen with a tick as well as a colour.
private struct Choice: View {
    let words: String
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            if chosen { Label(words, systemImage: "checkmark") } else { Text(words) }
        }
        .action(selected: chosen, pill: true)
    }
}

/// A row of choices that runs to the screen's edge, so that one too long for it shows there's more.
private struct ChoiceRow<Content: View>: View {
    @Environment(\.metrics) private var metrics
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) { content }
                .padding(.horizontal, metrics.gutter)
                .padding(.vertical, metrics.tv ? Tokens.focusRoom : Tokens.Space.s1)
        }
        .remoteSection()
    }
}

private extension Metrics {
    /// Square covers to fill the width, as many as fit: three across a phone.
    var coverColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardWidth - Tokens.Space.s3), spacing: Tokens.Space.s2, alignment: .top)]
    }
}

/// A list that couldn't load, a list loading, or the list.
private struct Loaded<Value, Content: View>: View {
    let value: Value?
    let error: String
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        if let value {
            content(value)
        } else if !error.isEmpty {
            ProblemView(words: error, retry: retry)
        } else {
            LoadingView()
        }
    }
}

// MARK: - A library

private enum Part: Hashable { case albums, artists, songs }

/// The list of a listening library. Its first row chooses which part; for albums the next row says
/// in which order.
struct ListeningLibraryView: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    @State private var part = Part.albums
    @State private var sort: String

    init(library: Library) {
        self.library = library
        _sort = State(initialValue: library.type == "audiobooks" ? "artist" : "title")
    }

    private func sortWords(_ key: String) -> String {
        switch key {
        case "artist": return String(ListeningRules.artistsWord(libraryType: library.type).dropLast())
        case "added": return "Newest"
        default: return "Title"
        }
    }

    var body: some View {
        let type = library.type
        let pods = type == "podcasts"
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if metrics.tv {
                Heading(library.name).padding(.horizontal, metrics.gutter)
            } else {
                // A library's page on a phone or tablet: under the strip, its name in Title, as the website's.
                Text(library.name).pageFont(.title).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, metrics.gutter)
            }
            ChoiceRow {
                Choice(words: ListeningRules.albumsWord(libraryType: type), chosen: part == .albums) { part = .albums }
                if !pods { Choice(words: ListeningRules.artistsWord(libraryType: type), chosen: part == .artists) { part = .artists } }
                if type == "music" { Choice(words: "Songs", chosen: part == .songs) { part = .songs } }
                #if os(iOS) || os(visionOS)
                // Playlists, lyrics, a song's radio and following a podcast.
                NavigationLink("More", value: Route.page(ServerPages.path(library))).action(pill: true)
                #endif
            }
            if part == .albums, !pods {
                ChoiceRow {
                    ForEach(["title", "artist", "added"], id: \.self) { key in
                        Choice(words: sortWords(key), chosen: sort == key) { sort = key }
                    }
                }
            }
            ScrollView {
                Group {
                    switch part {
                    case .albums: AlbumGrid(library: library.id, sort: sort, artist: nil)
                    case .artists: ArtistGrid(library: library)
                    case .songs: SongList(library: library)
                    }
                }
                .padding(.horizontal, metrics.gutter)
                .padding(.top, Tokens.Space.s1)
                .padding(.bottom, Tokens.Space.s6)
            }
        }
        .padding(.top, metrics.tv ? Tokens.Space.s4 : 44 + Tokens.Space.s3)
        .overlay(alignment: .top) {
            if !metrics.tv { LibraryStrip(current: library.id) }
        }
        .pageBackground(palette)
    }
}

/// Albums, books or podcasts, each once, as covers.
private struct AlbumGrid: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let library: Int64
    let sort: String
    let artist: String?
    @State private var albums: [Album]?
    @State private var error = ""
    @FocusState private var focused: String?

    private func load() async {
        do {
            var seen = Set<String>()
            albums = try await client.albums(library: library, sort: sort, artist: artist).filter { seen.insert($0.key).inserted }
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    var body: some View {
        Loaded(value: albums, error: error, retry: { error = ""; Task { await load() } }) { albums in
            if albums.isEmpty {
                Secondary("Nothing here yet.")
            } else {
                LazyVGrid(columns: metrics.coverColumns, alignment: .leading, spacing: Tokens.Space.s4) {
                    ForEach(albums, id: \.key) { album in
                        let title = album.title ?? ""
                        let by = album.artist ?? ""
                        Tile(title: title.isEmpty ? "No album" : title, subtitle: by == title ? "" : by,
                             url: album.coverItem.flatMap { client.coverURL($0) },
                             route: .listeningAlbum(library: library, album: title, artist: by),
                             aspect: 1, focus: $focused, focusKey: "a-\(album.key)")
                    }
                }
                .remoteSection()
            }
        }
        .task(id: "\(library)|\(sort)|\(artist ?? "")") { await load() }
    }
}

/// Artists or authors, each once.
private struct ArtistGrid: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let library: Library
    @State private var artists: [Artist]?
    @State private var error = ""
    @FocusState private var focused: String?

    private func load() async {
        do {
            var seen = Set<String>()
            artists = try await client.artists(library: library.id).filter { seen.insert($0.name ?? "").inserted }
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    private func count(_ artist: Artist) -> String {
        let word = ListeningRules.albumsWord(libraryType: library.type).lowercased()
        let albums = artist.albums ?? 0
        return albums == 1 ? "1 \(word.dropLast())" : "\(albums) \(word)"
    }

    var body: some View {
        Loaded(value: artists, error: error, retry: { error = ""; Task { await load() } }) { artists in
            if artists.isEmpty {
                Secondary("Nothing here yet.")
            } else {
                LazyVGrid(columns: metrics.coverColumns, alignment: .leading, spacing: Tokens.Space.s4) {
                    ForEach(artists, id: \.name) { artist in
                        let name = artist.name ?? ""
                        Tile(title: name.isEmpty ? "Unknown" : name, subtitle: count(artist),
                             url: artist.coverItem.flatMap { client.coverURL($0) },
                             route: .artist(library: library.id, name: name),
                             aspect: 1, focus: $focused, focusKey: "ar-\(name)")
                    }
                }
                .remoteSection()
            }
        }
        .task { await load() }
    }
}

/// Every song, by title, a page at a time as it's scrolled.
private struct SongList: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    let library: Library
    @State private var songs: [Item] = []
    @State private var finished = false
    @State private var loading = false
    @State private var error = ""
    private let page = 100

    private func loadMore() async {
        guard !loading, !finished else { return }
        loading = true
        defer { loading = false }
        do {
            let found = try await client.songs(library: library.id, offset: songs.count, limit: page)
            let seen = Set(songs.map(\.id))
            songs += uniqued(found.filter { !seen.contains($0.id) })
            // A server that sends nothing new can't keep this asking for ever.
            if found.count < page || found.allSatisfy({ seen.contains($0.id) }) { finished = true }
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    var body: some View {
        Group {
            if songs.isEmpty, !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await loadMore() } })
            } else if songs.isEmpty, !finished {
                LoadingView()
            } else if songs.isEmpty {
                Secondary("Nothing here yet.")
            } else {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    if !error.isEmpty { ProblemLine(error) }
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(track: song, number: index + 1, subtitle: [song.artist ?? "", song.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                                 showArt: true, books: false) {
                            model.startListening(songs, start: ListeningStart(index), keepsPlace: false)
                        }
                        .onAppear {
                            if index == songs.count - 1, !finished { Task { await loadMore() } }
                        }
                    }
                }
                .remoteSection()
            }
        }
        .task { if songs.isEmpty { await loadMore() } }
    }
}

// MARK: - An artist

/// One artist or author: everything of theirs in this library, newest last.
struct ArtistScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Int64
    let name: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Heading(name.isEmpty ? "Unknown" : name)
                AlbumGrid(library: library, sort: "year", artist: name)
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, Tokens.Space.s4)
            .padding(.bottom, Tokens.Space.s6)
        }
        .pageBackground(palette)
    }
}

// MARK: - A track

/// One line of a list of tracks. A tap or OK plays from here. Beside it, and one press to the right
/// on a remote, a button adds it to the queue instead.
struct TrackRow: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let track: Item
    let number: Int
    let subtitle: String
    let showArt: Bool
    let books: Bool
    let play: () -> Void
    @State private var added = false

    var body: some View {
        let isNow = listening.now?.item.id == track.id
        let place = ListeningRules.placeOn(track, keepsPlace: books)
        let done = books && track.progress?.watched == true
        let under = [subtitle, done ? "Finished" : "", place > 0 ? "\(ListeningRules.clock(place)) in" : ""].filter { !$0.isEmpty }
        let state = isNow ? "Playing" : (done ? "Finished" : (place > 0 ? "\(ListeningRules.spokenClock(place)) in" : ""))
        HStack(spacing: Tokens.Space.s2) {
            Button(action: play) {
                HStack(spacing: Tokens.Space.s3) {
                    if showArt {
                        ArtImage(url: client.posterURL(track), width: 48)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                    } else {
                        Group {
                            if isNow {
                                Image(systemName: "play.fill").foregroundStyle(palette.accentText)
                            } else {
                                Text("\(track.track ?? number)").font(.wmSecondary).foregroundStyle(palette.textSecondary)
                            }
                        }
                        .frame(width: Tokens.Space.s8, alignment: .trailing)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).foregroundStyle(palette.text).lineLimit(2).multilineTextAlignment(.leading)
                        if !under.isEmpty { Secondary(under.joined(separator: " · "), lines: 1) }
                    }
                    Spacer(minLength: 0)
                    if let length = track.runtimeSec, length > 0 { Secondary(ListeningRules.clock(length)) }
                }
                .padding(.horizontal, Tokens.Space.s3)
                .padding(.vertical, Tokens.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SurfaceStyle(fill: isNow ? palette.card : palette.panel))
            .accessibilityLabel([track.title, subtitle].filter { !$0.isEmpty }.joined(separator: ", "))
            .accessibilityValue(state)
            RoundButton(symbol: added ? "checkmark" : "plus",
                        label: added ? "\(track.title) is in the queue" : "Add \(track.title) to the queue") {
                guard !added else { return }
                listening.addToQueue([track], keepsPlace: books, client: client)
                added = true
            }
        }
        .remoteSection()
    }
}

// MARK: - An album or a book

/// An album, a book or a podcast. Beside its cover on a TV or a wide screen, under it on a phone held
/// upright. Nothing shows until the kind of library is known: Play means something else in a book.
struct AlbumScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let library: Int64
    let album: String
    let artist: String
    @State private var tracks: [Item]?
    @State private var libraryType = ""
    @State private var error = ""
    @Namespace private var scope
    private let cover: CGFloat = 220

    private var upright: Bool {
        #if os(iOS) || os(visionOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

    private func load() async {
        let type = await model.libraryType(library)
        do {
            let found = uniqued(try await client.tracks(library: library, album: album, artist: artist))
            libraryType = type
            tracks = found
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    @ViewBuilder private func words(_ tracks: [Item], books: Bool) -> some View {
        let start = ListeningRules.whereToStart(tracks, keepsPlace: books)
        let resume = ListeningRules.hasPlaceToResume(tracks, keepsPlace: books)
        let year = books ? nil : tracks.lazy.compactMap(\.year).first
        let facts = [year.map(String.init), ListeningRules.tracksWords(libraryType: libraryType, count: tracks.count),
                     ListeningRules.lengthWords(tracks.reduce(0) { $0 + ($1.runtimeSec ?? 0) })].compactMap { $0 }
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Heading(album.isEmpty ? "No album" : album)
            if !artist.isEmpty, artist != album { Secondary(artist) }
            Secondary(facts.joined(separator: " · "))
            if !error.isEmpty { ProblemLine(error) }
            // The buttons wrap on a narrow phone.
            FlowLayout(spacing: Tokens.Space.s2) {
                Button {
                    model.startListening(tracks, start: start, keepsPlace: books)
                } label: {
                    Label(resume ? "Resume" : "Play", systemImage: "play.fill")
                }
                .mainAction()
                .firstFocus(in: scope)
                if resume {
                    Button("Start over") { model.startListening(tracks, start: ListeningStart(0), keepsPlace: books) }.action(pill: true)
                }
                if !books {
                    Button {
                        model.startListening(tracks.shuffled(), start: ListeningStart(0), keepsPlace: books)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .action(pill: true)
                }
                Button("Add to queue") { listening.addToQueue(tracks, keepsPlace: books, client: client) }.action(pill: true)
            }
            .remoteSection()
        }
    }

    @ViewBuilder private func head(_ tracks: [Item], books: Bool) -> some View {
        let picture = ArtImage(url: tracks.first.flatMap { client.posterURL($0) }, width: cover, placeholder: album)
            .frame(width: cover, height: cover)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
            .accessibilityHidden(true)
        if upright {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                picture.frame(maxWidth: .infinity)
                words(tracks, books: books)
            }
        } else {
            HStack(alignment: .top, spacing: Tokens.Space.s6) {
                picture
                words(tracks, books: books).frame(minWidth: 280, maxWidth: 640, alignment: .leading)
            }
        }
    }

    var body: some View {
        ZStack {
            Loaded(value: tracks, error: error, retry: { error = ""; Task { await load() } }) { tracks in
                let books = ListeningRules.keepsPlace(libraryType: libraryType)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        head(tracks, books: books).padding(.bottom, Tokens.Space.s3)
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(track: track, number: index + 1, subtitle: track.artist.map { $0 == artist ? "" : $0 } ?? "",
                                     showArt: false, books: books) {
                                let start = ListeningStart(index, atSec: ListeningRules.placeOn(track, keepsPlace: books))
                                model.startListening(tracks, start: start, keepsPlace: books)
                            }
                        }
                    }
                    .padding(.horizontal, metrics.gutter)
                    .padding(.vertical, metrics.tv ? metrics.edge : Tokens.Space.s4)
                }
                .focusRoot(scope)
            }
        }
        .pageBackground(palette)
        .task(id: "\(library)|\(artist)|\(album)") { await load() }
    }
}
