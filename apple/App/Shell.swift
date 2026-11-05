import SwiftUI
import WittyKit

/// The app's top level. A phone, a tablet and Apple Vision Pro have Home, Search and You in a floating
/// pill at the bottom, within reach of a thumb. Apple TV has six pills along the top, where up from a
/// tab's first row gets to them: Home, Libraries, Games, Live TV, Search and You (docs/APP-DESIGN.md,
/// On a TV, and TvTabs.swift).
enum AppTab: Identifiable, Hashable {
    case home, libraries, games, guide, search, profile
    /// A library this person added to Apple TV's top menu, as a tab of its own.
    case library(Int64)

    var id: String {
        switch self {
        case .home: return "home"
        case .libraries: return "libraries"
        case .games: return "games"
        case .guide: return "guide"
        case .search: return "search"
        case .profile: return "profile"
        case .library(let id): return "library\(id)"
        }
    }

    /// The tabs a phone, a tablet and Vision Pro keep a stack for.
    static let phoneTabs: [AppTab] = [.home, .search, .profile]
    /// Apple TV's bar, in its order, before any libraries added to it and You.
    static let tvTabs: [AppTab] = [.home, .libraries, .games, .guide, .search]

    /// A library's tab is named after the library, which the bar knows.
    var title: String {
        switch self {
        case .home: return say("homeTab")
        case .libraries: return say("librariesTab")
        case .games: return say("gamesTab")
        case .guide: return say("liveTvTab")
        case .search: return say("searchTab")
        case .profile: return say("youTab")
        case .library: return ""
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .libraries: return "books.vertical"
        case .games: return "gamecontroller"
        case .guide: return "tv"
        case .search: return "magnifyingglass"
        case .profile: return "person"
        case .library: return "books.vertical"
        }
    }

    /// Not every one of these has a filled form. A symbol that doesn't exist draws nothing.
    var openIcon: String {
        switch self {
        case .home: return "house.fill"
        case .libraries: return "books.vertical.fill"
        case .games: return "gamecontroller.fill"
        case .guide: return "tv.fill"
        case .profile: return "person.fill"
        case .search, .library: return icon
        }
    }
}

struct BrowseShell: View {
    var body: some View {
        #if os(tvOS)
        TopTabs().nowPlayingCover()
        #else
        PillShell().nowPlayingCover()
        #endif
    }
}

/// One tab's stack of screens. Every route opens from here, whichever tab it's in.
private struct TabRoot: View {
    @EnvironmentObject private var model: AppModel
    let tab: AppTab
    /// Apple TV: Back on a tab's first screen goes up to the bar.
    var toBar: (() -> Void)?

    @ViewBuilder private var first: some View {
        switch tab {
        case .home: HomeView()
        case .search: SearchView()
        case .profile: YouView()
        #if os(tvOS)
        case .libraries: LibrariesPage()
        case .games: GamesTab()
        case .guide: LiveTvTab()
        case .library(let id):
            if let library = model.libraries.first(where: { $0.id == id }) {
                LibraryScreen(library: library)
            } else {
                LoadingView()
            }
        #else
        // Apple TV's tabs alone: these devices never show them.
        case .libraries, .games, .guide, .library: EmptyView()
        #endif
        }
    }

    var body: some View {
        NavigationStack(path: model.pathBinding(tab)) {
            first
                .noNavigationBar()
                .onRemoteBack(toBar)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .library(let library):
                        LibraryScreen(library: library).plainNavigation()
                    case .listeningAlbum(let library, let album, let artist):
                        AlbumScreen(library: library, album: album, artist: artist).plainNavigation()
                    case .artist(let library, let name): ArtistScreen(library: library, name: name).plainNavigation()
                    case .show(let id): ShowView(id: id).plainNavigation()
                    case .item(let id): ItemView(id: id).plainNavigation()
                    #if os(tvOS)
                    case .gameLibrary(let library, let console): GamesLibraryView(library: library, console: console).plainNavigation()
                    case .game(let id): GameDetailView(id: id).plainNavigation()
                    // A new identity for each game, so a second one gets a new player.
                    case .playGame(let id, let start): GamePlayerScreen(id: id, start: start).id("\(id)\(start)")
                    #else
                    case .gameLibrary(let library, _): LibraryView(library: library).plainNavigation()
                    case .game(let id): ItemView(id: id).plainNavigation()
                    // The same player as Apple TV's, with the account's touch controls.
                    case .playGame(let id, let start): GamePlayerView(gameId: id, start: start).id("\(id)\(start)")
                    #endif
                    // A new identity for each thing played, so the next episode gets a new player
                    // and not the last one's state.
                    case .player(let id, let startOver): PlayerScreen(id: id, startOver: startOver).id(id)
                    case .notices: NoticesView().plainNavigation()
                    case .logs: LogsView().plainNavigation()
                    case .names: NamesView().plainNavigation()
                    case .password: PasswordView().plainNavigation()
                    case .twoStep: TwoStepView().plainNavigation()
                    case .devices: DevicesView().plainNavigation()
                    case .signInTv: SignInTvView().plainNavigation()
                    case .theme: ThemeView().plainNavigation()
                    #if os(tvOS)
                    case .topMenu: TopMenuView().plainNavigation()
                    #else
                    case .topMenu: EmptyView()
                    #endif
                    case .web(let path):
                        #if os(iOS) || os(visionOS)
                        WebPlayerView(path: path, keptToGames: true)
                        #else
                        // Nothing on these devices opens this: see WittyKit's Rigs.swift.
                        ProblemView(words: "That can only be played on an iPhone or iPad.")
                        #endif
                    case .page(let path):
                        #if os(iOS) || os(visionOS)
                        WebPlayerView(path: path, keptToGames: false)
                        #else
                        ElsewhereNote(path: path)
                        #endif
                    #if os(tvOS)
                    case .album(let library, let name):
                        AlbumView(library: library, name: name)
                    case .photo(let library, let id):
                        PhotoView(library: library, id: id)
                    case .guide:
                        GuideView()
                    case .channel(let key):
                        ChannelPlayer(start: key)
                    case .recordings:
                        RecordingsView()
                    #else
                    // Apple TV's own screens. These devices show the server's page for all of them.
                    case .album, .photo, .guide, .channel:
                        #if os(iOS) || os(visionOS)
                        WebPlayerView(path: ServerPages.guide, keptToGames: false)
                        #else
                        ElsewhereNote(path: ServerPages.guide)
                        #endif
                    case .recordings:
                        #if os(iOS) || os(visionOS)
                        WebPlayerView(path: ServerPages.guide + "/recordings", keptToGames: false)
                        #else
                        ElsewhereNote(path: ServerPages.guide + "/recordings")
                        #endif
                    #endif
                    }
                }
        }
    }
}

/// A library's own screen: games, music, audiobooks and podcasts have theirs, everything else its posters.
struct LibraryScreen: View {
    let library: Library

    var body: some View {
        if library.hasGameScreens {
            #if os(tvOS)
            GamesLibraryView(library: library, console: nil)
            #else
            LibraryView(library: library)
            #endif
        } else if library.hasListeningScreens {
            ListeningLibraryView(library: library)
        } else {
            LibraryView(library: library)
        }
    }
}

#if os(tvOS)
/// The bar along the top over the chosen tab. A tab's first screen has the bar above it; a screen opened
/// from there has the whole screen, and Back from it comes back to the tab. Only the chosen tab is drawn:
/// the bar can only be reached from a tab's first screen, and where each stack had got to is kept in the
/// model. (The system's tab view keeps room for its own bar above every tab, even with the bar hidden.)
private struct TopTabs: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.resetFocus) private var resetFocus
    @FocusState private var bar: AppTab?
    @Namespace private var root
    /// Whether Home's first look has arrived.
    @State private var settled = false

    var body: some View {
        VStack(spacing: 0) {
            if model.path.isEmpty {
                TvTopBar(focus: $bar).ignoresSafeArea(.container, edges: .horizontal)
            }
            TabRoot(tab: model.tab, toBar: { bar = model.tab })
                .id(model.tab)
                .safeAreaInset(edge: .bottom) { MiniPlayerSlot(tab: model.tab) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Focus starts on the tab's own main action, not on the bar above it.
                .prefersDefaultFocus(in: root)
        }
        .focusScope(root)
        .background(palette.background.ignoresSafeArea())
        // Home's first look comes after the bar, which has focus meanwhile as the only thing there. Once,
        // if nobody has moved it, it goes on to Home's main action.
        .onChange(of: model.libraries) { _ in
            guard !settled else { return }
            settled = true
            // A moment for Home's first look to be drawn, so its main action is there to take focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if bar == .home { resetFocus(in: root) }
            }
        }
        // A WittyTV reminder comes up on whatever's showing.
        .modifier(TvReminderAlert())
    }
}
#else
/// The system's tab view holds the three stacks, with its own bar hidden and the pill in its place.
private struct PillShell: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        TabView(selection: $model.tab) {
            ForEach(AppTab.phoneTabs) { tab in
                TabRoot(tab: tab)
                    .safeAreaInset(edge: .bottom) {
                        // The mini player sits above the pill, as on Android.
                        VStack(spacing: Tokens.Space.s2) {
                            MiniPlayerSlot(tab: tab)
                            if !model.hidesBars { PillBar() }
                        }
                    }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        // What scrolls under the clock and the battery fades out, so they can still be read.
        .overlay {
            if !model.hidesBars {
                // Measured from the very top of the screen, so the inset it reports is the clock's.
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        LinearGradient(colors: [palette.background.opacity(0.92), palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: geo.safeAreaInsets.top)
                        Spacer(minLength: 0)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

/// Android's floating bar: the open section filled in the accent colour with its name, the others
/// as their icons. Real buttons, each saying which section it is and whether it's the one open.
private struct PillBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    private func press(_ tab: AppTab) {
        if model.tab == tab {
            // Choosing the open section again goes back to its top, as tab bars do.
            model.paths[tab] = []
        } else {
            model.tab = tab
        }
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s1) {
            ForEach(AppTab.phoneTabs) { tab in
                let open = model.tab == tab
                Button {
                    press(tab)
                } label: {
                    HStack(spacing: Tokens.Space.s2) {
                        if tab == .profile, let user = model.user {
                            // The person's own face: who's signed in, at a glance.
                            AvatarTile(name: user.shownName, size: 24)
                                .overlay(Circle().strokeBorder(open ? palette.onAccent.opacity(0.9) : palette.border, lineWidth: 1.5))
                        } else {
                            Image(systemName: open ? tab.openIcon : tab.icon).font(.body.weight(.semibold))
                        }
                        if open { Text(tab.title).font(.wmLabel) }
                    }
                    .foregroundStyle(open ? palette.onAccent : palette.text)
                    .padding(.horizontal, open ? Tokens.Space.s5 : Tokens.Space.s4)
                    .padding(.vertical, Tokens.Space.s3)
                }
                .buttonStyle(SurfaceStyle(fill: open ? palette.accent : nil, radius: 999))
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(open ? [.isSelected] : [])
            }
        }
        .padding(Tokens.Space.s1)
        .background(Capsule().fill(palette.panel))
        .overlay(Capsule().stroke(palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(.bottom, Tokens.Space.s3)
        .frame(maxWidth: .infinity)
    }
}
#endif

#if !os(iOS) && !os(visionOS)
/// One of the server's pages, on a device that can't show it inside this app.
struct ElsewhereNote: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let path: String

    var body: some View {
        #if os(tvOS)
        // The same card Android TV shows: the page's code for a phone's camera, and its address.
        if let url = model.client.mediaURL(path) {
            OpenOnPhone(url: url)
        } else {
            Secondary("Open \(model.client.base) on a phone, tablet or computer.").padding(Tokens.gutter)
        }
        #else
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if let url = model.client.mediaURL(path), WebPlayer.isWebLink(url) {
                Link("Open in your browser", destination: url).action(primary: true)
            }
        }
        .padding(Tokens.gutter)
        .pageBackground(palette)
        #endif
    }
}
#endif

/// A library Apple TV can't show, and where it can be seen. Never pretends otherwise.
struct BrowserOnlyNote: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            SectionTitle(library.name)
            #if os(tvOS)
            // No browser on Apple TV, so this can only say where to go.
            Secondary("Apple TV can't show this, as it has no way to open your server's own pages. Open \(model.client.base) on a phone, tablet or computer.")
            #else
            Secondary("This opens in your web browser.")
            if let url = URL(string: model.client.base), WebPlayer.isWebLink(url) {
                Link("Open in your browser", destination: url).action()
            }
            #endif
        }
        .padding(Tokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg).fill(palette.panel))
        .accessibilityElement(children: .contain)
    }
}

/// Words to read and nothing else: the licences, or this app's log. On Apple TV each paragraph can
/// take the focus, which is how the remote scrolls through it.
private struct TextPage: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let title: String
    let paragraphs: [String]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Heading(title)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, words in
                    Text(words)
                        .font(.wmSecondary)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #if os(tvOS)
                        .focusable()
                        #else
                        .textSelection(.enabled)
                        #endif
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, Tokens.Space.s4)
        }
        .pageBackground(palette)
    }
}

/// Every third-party part this app ships and its licence: the repository's NOTICE, bundled.
struct NoticesView: View {
    private var paragraphs: [String] {
        guard let url = Bundle.main.url(forResource: "NOTICE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ["The licence notes couldn't be read from this copy of the app."]
        }
        return text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        TextPage(title: "Licences", paragraphs: paragraphs)
    }
}

/// What this app has written about itself on this device. It is cleaned as it's written, and nothing
/// leaves the device from here.
struct LogsView: View {
    private static let lines = 200

    private var paragraphs: [String] {
        let file = ClientLog.defaultDirectory.appendingPathComponent("client.log")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let all = text.split(separator: "\n").suffix(Self.lines).map(String.init)
        return all.isEmpty ? ["Nothing has been logged yet."] : all
    }

    var body: some View {
        TextPage(title: "This app's log", paragraphs: paragraphs)
    }
}

/// What's asked of the server for this, in `WittyClient.search`. A short pause after typing keeps it
/// from asking on every letter.
struct SearchView: View {
    @Environment(\.client) private var client
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var query = ""
    @State private var results: SearchResults?
    @State private var error = ""
    @State private var searching = false
    @FocusState private var focused: String?

    private func run(_ words: String) async {
        error = ""
        guard WittyClient.searchQuery(words) != nil else {
            results = nil
            searching = false
            return
        }
        searching = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        do {
            let found = try await client.search(words)
            if Task.isCancelled { return }
            results = found
            announce(found.isEmpty ? "Nothing found" : "\(found.items.count + found.shows.count) found")
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
        searching = false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Heading("Search")
                // On Apple TV choosing this opens the system's keyboard, which a phone can also type into.
                OutlinedField(label: "Titles, shows and songs", text: $query)
                if !error.isEmpty {
                    ProblemLine(error)
                    Button("Try again") { Task { await run(query) } }.action()
                } else if searching && results == nil {
                    LoadingView()
                } else if let results {
                    if results.isEmpty {
                        Secondary("Nothing found for that.")
                    } else {
                        CardGrid(items: results.items, shows: results.shows, focus: $focused)
                    }
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, Tokens.Space.s4)
        }
        .scrollDismissesKeyboardIfAvailable()
        .pageBackground(palette)
        .task(id: query) { await run(query) }
    }
}
