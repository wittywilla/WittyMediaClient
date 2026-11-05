import SwiftUI
import WittyKit

/// The app's top level. A phone, a tablet and Apple Vision Pro have the website's floating bar at the bottom,
/// within reach of a thumb: Home, TV guide, Search, the Menu (not a tab, a drawer) and You. Apple TV has six pills
/// along the top, where up from a tab's first row gets to them: Home, Libraries, Games, Live TV, Search and You
/// (docs/APP-DESIGN.md, On a TV, and TvTabs.swift).
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

    /// The tabs a phone, a tablet and Vision Pro keep a stack for: the floating bar's, the Menu aside.
    static let phoneTabs: [AppTab] = [.home, .guide, .search, .profile]
    /// Apple TV's bar, in its order, before any libraries added to it and You.
    static let tvTabs: [AppTab] = [.home, .libraries, .games, .guide, .search]

    /// A library's tab is named after the library, which the bar knows.
    var title: String {
        switch self {
        case .home: return say("homeTab")
        case .libraries: return say("librariesTab")
        case .games: return say("gamesTab")
        #if os(tvOS)
        case .guide: return say("liveTvTab")
        #else
        // The website's bar calls it the TV guide.
        case .guide: return "TV guide"
        #endif
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

    /// The website's icons in the floating bar.
    var barIcon: String { self == .home ? "house.fill" : icon }

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
        #if os(iOS) || os(visionOS)
        // The website's other top pages have the strip too.
        case .search: SearchView().underStrip()
        case .profile: YouView().underStrip()
        #else
        case .search: SearchView()
        case .profile: YouView()
        #endif
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
        case .guide:
            // The guide and live channels: the server's page, under the strip.
            #if os(iOS) || os(visionOS)
            WebPlayerView(path: ServerPages.guide, keptToGames: false).underStrip(hidden: model.pagePlaying && (model.paths[.guide] ?? []).isEmpty)
            #else
            ElsewhereNote(path: ServerPages.guide)
            #endif
        // Apple TV's tabs alone: these devices never show them.
        case .libraries, .games, .library: EmptyView()
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
                        #if os(tvOS)
                        LibraryScreen(library: library).plainNavigation()
                        #else
                        // A library's page is a top of its own, with the strip and no Back, as on the website. Going from one
                        // section to another replaces the page in place, so each library is a page of its own (`id`):
                        // otherwise the last one's shelves, count and choices stayed under the new one's name.
                        LibraryScreen(library: library).noNavigationBar().id(library.id)
                        #endif
                    #if os(iOS) || os(visionOS)
                    // The website's album and artist pages, over their artwork's colour.
                    case .listeningAlbum(let library, let album, let artist):
                        MusicAlbumPage(library: library, album: album, artist: artist).plainNavigation(overPicture: true)
                    case .artist(let library, let name): MusicArtistPage(library: library, name: name).plainNavigation(overPicture: true)
                    #else
                    case .listeningAlbum(let library, let album, let artist):
                        AlbumScreen(library: library, album: album, artist: artist).plainNavigation()
                    case .artist(let library, let name): ArtistScreen(library: library, name: name).plainNavigation()
                    #endif
                    case .show(let id): ShowView(id: id).plainNavigation(overPicture: true)
                    case .item(let id): ItemView(id: id).plainNavigation(overPicture: true)
                    // WittyPlay's own screens on every device: the Shelves home, which is a library's page with the
                    // strip and no Back, or a console's collection under its band, and a game's page over its picture.
                    case .gameLibrary(let library, nil): GamesLibraryView(library: library, console: nil).noNavigationBar().id(library.id)
                    case .gameLibrary(let library, let console): GamesLibraryView(library: library, console: console).plainNavigation(overPicture: true)
                    case .game(let id): GameDetailView(id: id).plainNavigation(overPicture: true)
                    #if os(tvOS)
                    // A new identity for each game, so a second one gets a new player.
                    case .playGame(let id, let start): GamePlayerScreen(id: id, start: start).id("\(id)\(start)")
                    #else
                    // The same player as Apple TV's, with the account's touch controls. A website's game page opened
                    // in the app hands its Play over to it too (WebPlayerView hands over the website's /game/ address).
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
                        let playing = model.pagePlaying && model.paths[tab]?.last == .page(path)
                        if let found = model.libraryPage(path) {
                            // A saved view, or a genre, studio or network from an item's page: the app's own library
                            // page with that chosen, as the website opens /library/3?genre=Drama.
                            LibraryView(library: found.library, start: found.state).noNavigationBar().id(path)
                        } else if model.isTopPage(path) {
                            // Collections, Game PCs and modules' pages are sections of their own, under the strip.
                            WebPlayerView(path: path, keptToGames: false).underStrip(path: path, hidden: playing)
                        } else {
                            WebPlayerView(path: path, keptToGames: false).plainNavigation(hidden: playing)
                        }
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
            GamesLibraryView(library: library, console: nil)
        } else if library.hasListeningScreens {
            #if os(iOS) || os(visionOS)
            MusicLibraryPage(library: library)
            #else
            ListeningLibraryView(library: library)
            #endif
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
/// The system's tab view holds the stacks, with its own bar hidden and the website's floating bar in its place.
/// The Menu's drawer is over all of it, the bar included.
private struct PillShell: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    /// The room the clock and the home indicator take.
    @State private var insets = EdgeInsets()
    /// The bar goes behind the keyboard while one is up, as on the website.
    @State private var typing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // 8 above the home indicator's room, as the website's bar (shell.css: bottom 8 + the safe area).
        let lift = typing ? 0 : Tokens.Space.s2
        TabView(selection: $model.tab) {
            ForEach(AppTab.phoneTabs) { tab in
                TabRoot(tab: tab)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        // The mini player sits above the bar.
                        VStack(spacing: Tokens.Space.s2) {
                            MiniPlayerSlot(tab: tab)
                            // A video left for the rest of the app plays on here, as in the website's dock.
                            if let video = model.video, !model.hidesBars { VideoDock(playback: video, clock: video.clockface) }
                            if !model.hidesBars && !typing { FloatingBar() }
                        }
                        .padding(.bottom, model.hidesBars || typing ? 0 : lift)
                    }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { insets = geo.safeAreaInsets }
                    .onChange(of: geo.safeAreaInsets) { insets = $0 }
            }
            .ignoresSafeArea(.keyboard)
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in typing = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in typing = false }
        #endif
        // What scrolls under the clock and the battery fades out, so they can still be read.
        .overlay {
            if !model.hidesBars {
                VStack(spacing: 0) {
                    LinearGradient(colors: [palette.background.opacity(0.92), palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: insets.top)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .overlay { MenuDrawer() }
        // The menus' arrangement, modules' pages and the legal notices, once per server and person.
        .task(id: "\(model.client.base)|\(model.user?.id ?? 0)") { await model.loadNavigation() }
        // A video in the dock keeps its place and stops in the background, as on its own screen.
        .onChange(of: scenePhase) { model.video?.sceneChanged($0) }
        #if os(iOS)
        .onAppear { BackSwipe.paused = model.hidesBars }
        .onChange(of: model.hidesBars) { BackSwipe.paused = $0 }
        #endif
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
    /// What was asked for: on a phone, the box searches when Search is pressed, as the website's does.
    @State private var asked = ""
    @State private var results: SearchResults?
    @State private var error = ""
    @State private var searching = false
    @FocusState private var focused: String?
    @FocusState private var typing: Bool

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
        Group {
            if metrics.tv { tvPage } else { page }
        }
        .task(id: metrics.tv ? query : asked) { await run(metrics.tv ? query : asked) }
    }

    /// Apple TV's, as it was.
    private var tvPage: some View {
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
    }

    /// The website's Search on a phone: "Search" with what was asked in quotes beside it, the box, then shows and
    /// everything else, three posters across, and the notice about results.
    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
                    Text("Search").pageFont(.title).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                    if !asked.isEmpty {
                        Text("“\(asked)”").font(.system(size: 14)).foregroundStyle(palette.textHint).lineLimit(1)
                    }
                }
                .padding(.top, Tokens.Space.s3)
                box.padding(.top, 20)
                results(for: asked).padding(.top, Tokens.Space.s2)
                #if !os(tvOS)
                PageFoot(notice: "")
                #endif
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, Tokens.Space.s6)
        }
        .scrollDismissesKeyboardIfAvailable()
        .pageBackground(palette)
        .onAppear {
            // Arriving with nothing typed, the box is the next step, as on the website.
            if query.isEmpty { DispatchQueue.main.async { typing = true } }
        }
    }

    /// 44 high, the theme's medium radius, `card`, with a search icon.
    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        return HStack(spacing: Tokens.Space.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.textHint)
                .frame(width: 20)
                .accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Search your libraries…").foregroundColor(palette.textHint))
                .pageFont(.body)
                .foregroundStyle(palette.text)
                .tint(palette.accent)
                .focused($typing)
                .submitLabel(.search)
                .onSubmit {
                    let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !words.isEmpty { asked = words }
                }
                .autocorrectionDisabled()
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityLabel("Search")
            if !query.isEmpty {
                Button {
                    query = ""
                    typing = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(palette.textHint).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.leading, Tokens.Space.s3)
        .padding(.trailing, Tokens.Space.s1)
        .frame(height: 44)
        .background(shape.fill(palette.card))
        .overlay(shape.strokeBorder(typing ? palette.accentText : palette.control, lineWidth: typing ? 2 : 1))
        .contentShape(shape)
        .onTapGesture { typing = true }
    }

    private func searchHead(_ title: String) -> some View {
        Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
            .padding(.top, 28).padding(.bottom, Tokens.Space.s3)
    }

    @ViewBuilder private func results(for words: String) -> some View {
        if WittyClient.searchQuery(words) == nil {
            EmptyState(icon: "magnifyingglass", title: "Find anything on this server",
                       detail: "Type a title in the search box: movies, shows, episodes, music, books and games are all included.")
        } else if !error.isEmpty {
            if metrics.tv {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    ProblemLine(error)
                    Button("Try again") { Task { await run(query) } }.pageButton(.primary)
                }
            } else {
                EmptyState(icon: "magnifyingglass", title: "The search didn’t work", detail: error)
            }
        } else if let results, !(searching && results.isEmpty) {
            if results.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "No results",
                           detail: "Nothing on this server matches “\(words)”. Try a shorter or different word.")
            } else if metrics.tv {
                let types = Dictionary(model.libraries.map { ($0.id, $0.type) }, uniquingKeysWith: { first, _ in first })
                VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                    ForEach(SearchGroups.group(items: results.items, shows: results.shows, libraryTypes: types)) { group in
                        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            SectionHead(title: group.title)
                            LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
                                ForEach(group.shows) { ShowTile(show: $0, inRow: false, focus: $focused) }
                                ForEach(ServerPages.albumsOnce(group.items)) { ItemTile(item: $0, inRow: false, focus: $focused) }
                            }
                        }
                    }
                }
                .opacity(searching ? 0.6 : 1)
            } else {
                // The website's two groups: shows, then everything else under its own heading only when there are shows.
                VStack(alignment: .leading, spacing: 0) {
                    if !results.shows.isEmpty {
                        searchHead("Shows")
                        LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
                            ForEach(results.shows) { ShowTile(show: $0, inRow: false, focus: $focused) }
                        }
                    }
                    if !results.items.isEmpty {
                        if !results.shows.isEmpty { searchHead("Everything else") }
                        LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
                            ForEach(results.items) { ItemTile(item: $0, inRow: false, focus: $focused) }
                        }
                        .padding(.top, results.shows.isEmpty ? Tokens.Space.s5 : 0)
                    }
                    if let notice = model.legal?.notice("searchResults") {
                        Text(notice.words).font(.system(size: 12)).foregroundStyle(palette.textHint).lineSpacing(3).padding(.top, Tokens.Space.s4)
                    }
                }
                .opacity(searching ? 0.6 : 1)
            }
        } else {
            SkeletonGrid()
        }
    }
}
