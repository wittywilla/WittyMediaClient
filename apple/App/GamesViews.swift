import SwiftUI
import WittyKit

// WittyPlay's games home on every Apple device: Shelves (docs/WITTYPLAY-EXPERIENCE.md, The games home:
// Shelves), as the website's (WittyMediaServer `web/src/pages/games/Library.tsx`). Where you left off,
// the other games in progress, then a shelf for each console and the shelves the server picks, with
// every game at the foot; a console's own page is its collection. On a TV the focused game rises into
// the preview at the top and the remote's buttons are along the bottom. Colours come from the theme,
// so every theme works here as anywhere else; spines and bands keep their covers' deep colours.

/// A game's card where a row of games is wanted outside the shelves (the TV's list of games
/// libraries): its case, its name, and its console and year.
struct GameCard: View {
    @Environment(\.metrics) private var metrics
    let game: GameItem
    let console: GameConsole?
    var favourite = false
    var width: CGFloat?

    var body: some View {
        let context = ShelfContext(consoles: console.map { [$0.id: $0] } ?? [:], progress: [:],
                                   favourites: favourite ? [game.id] : [], view: .cases)
        GameGridCell(item: game, context: context, width: width ?? metrics.cardWidth)
    }
}

private enum GameSort: String, CaseIterable, Identifiable {
    case title, popular, newest, oldest, rating, added
    var id: String { rawValue }
    var label: String {
        switch self {
        case .popular: return "Most popular"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .title: return "A to Z"
        case .rating: return "Highest rated"
        case .added: return "Recently added"
        }
    }
}

/// A games library's home, or one console's collection in it.
struct GamesLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @ObservedObject private var tints = CoverTints.shared
    let library: Library
    let console: String?

    @State private var home: GamesHome?
    @State private var consoles: [GameConsole] = []
    @State private var byConsole: [String: [GameItem]] = [:]
    @State private var forTwo: [GameItem] = []
    @State private var popular: [GameItem] = []
    @State private var games: [GameItem] = []
    @State private var total: Int?
    @State private var sort: GameSort = .title
    @State private var view = ShelfView.saved()
    @State private var pulled: String?
    @State private var favourites: Set<Int64> = []
    @State private var error = ""
    @State private var loadingMore = false
    @State private var width: CGFloat = 0
    @FocusState private var focused: String?
    @State private var shown: GameItem?
    @State private var following: Task<Void, Never>?
    @Namespace private var scope

    private var byId: [String: GameConsole] { Dictionary(consoles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var current: GameConsole? { console.flatMap { byId[$0] } }
    /// Consoles with games here, most games first.
    private var present: [GameConsole] { consoles.filter { ($0.count ?? 0) > 0 }.sorted { ($0.count ?? 0) > ($1.count ?? 0) } }
    private var inProgress: [GameContinue] {
        let all = home?.continue ?? []
        return console.map { c in all.filter { $0.item.console == c } } ?? all
    }
    private var context: ShelfContext {
        ShelfContext(consoles: byId, progress: Dictionary((home?.continue ?? []).map { ($0.item.id, $0) }, uniquingKeysWith: { a, _ in a }),
                     favourites: favourites, view: view)
    }
    private var everything: Int { present.reduce(0) { $0 + ($1.count ?? 0) } }

    // MARK: Loading

    private func load() async {
        do {
            async let c = client.gameConsoles(library: library.id)
            async let h = client.gamesHome(library: library.id)
            let freshConsoles = try await c
            if freshConsoles != consoles { consoles = freshConsoles }
            let freshHome = try await h
            if freshHome != home { home = freshHome }
            favourites = Set(freshHome.favouriteIds ?? [])
            error = ""
        } catch {
            let words = model.handle(error)
            if home == nil, consoles.isEmpty, !words.isEmpty { self.error = words }
            return
        }
        if let console {
            popular = (try? await client.games(library: library.id, console: console, sort: "popular", limit: 24).items) ?? popular
        } else {
            await loadShelves()
        }
        if total == nil { await loadGames(reset: true) }
        if shown == nil { shown = home?.continue?.first?.item ?? present.lazy.compactMap { byConsole[$0.id]?.first }.first ?? games.first }
    }

    /// A shelf for each console with games (the eight with most), and one of games for two or more.
    private func loadShelves() async {
        let lib = library.id, ids = present.prefix(8).map(\.id), client = client
        var found: [String: [GameItem]] = [:]
        await withTaskGroup(of: (String, [GameItem]?).self) { group in
            for id in ids {
                group.addTask { (id, try? await client.games(library: lib, console: id, sort: "popular", limit: 24).items) }
            }
            group.addTask { ("", try? await client.games(library: lib, players: 2, sort: "popular", limit: 24).items) }
            for await (id, items) in group {
                if id.isEmpty { forTwo = items ?? forTwo } else { found[id] = items ?? byConsole[id] ?? [] }
            }
        }
        if found != byConsole { byConsole = found }
    }

    private func loadGames(reset: Bool) async {
        guard !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await client.games(library: library.id, console: console, sort: sort.rawValue, offset: reset ? 0 : games.count, limit: 60)
            let fresh = page.items ?? []
            let all = uniqued((reset ? [] : games) + fresh)
            let finished = !reset && all.count == games.count
            games = all
            total = finished ? games.count : (page.total ?? games.count)
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    private func toggleFavourite(_ item: GameItem) {
        let on = !favourites.contains(item.id)
        if on { favourites.insert(item.id) } else { favourites.remove(item.id) }
        announce(on ? "\(item.title) added to favourites" : "\(item.title) removed from favourites")
        Task {
            do {
                try await client.setGameFavourite(item.id, on)
            } catch {
                if on { favourites.remove(item.id) } else { favourites.insert(item.id) }
                _ = model.handle(error)
            }
        }
    }

    /// On a TV, the preview follows focus a moment later, so flicking along a shelf doesn't flicker it.
    private func follow(_ key: String?) {
        following?.cancel()
        guard let key, let id = key.split(separator: ":").last.flatMap({ Int64($0) }) else { return }
        let known = (home?.continue?.map(\.item) ?? []) + byConsole.values.flatMap { $0 } + forTwo + popular + games
            + (home?.favourites ?? []) + (home?.recent ?? []) + (home?.mostPlayed ?? []) + (home?.shelves ?? []).flatMap { $0.items ?? [] }
        guard let item = known.first(where: { $0.id == id }), item.id != shown?.id else { return }
        following = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            shown = item
            tints.ask([item], client: client)
        }
    }

    // MARK: Rows

    private func shelf(_ id: String, _ title: String, _ items: [GameItem]?, console: GameConsole? = nil, count: Int? = nil,
                       faceFirst: Bool = false, letters: Bool = false, all: Route? = nil) -> some View {
        GameShelfRow(id: id, title: title, items: items ?? [], console: console, count: count, faceFirst: faceFirst, letters: letters,
                     all: all, context: context, pulled: $pulled, focus: $focused, toggleFavourite: toggleFavourite)
    }

    @ViewBuilder private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
            Heading(library.name)
            if everything > 0 {
                Text("\(everything.formatted()) \(everything == 1 ? "game" : "games")").font(.system(size: 15)).foregroundStyle(palette.textHint)
            }
            Spacer()
        }
        .padding(.horizontal, metrics.gutter)
    }

    @ViewBuilder private var homeRows: some View {
        let entries = inProgress
        if !metrics.tv { titleRow }
        if metrics.tv {
            OnTheGoRow(title: say("wpContinuePlaying"), entries: entries, context: context)
        } else if let first = entries.first {
            if metrics.gutter > Tokens.Space.s4 {
                // A tablet: Where you left off beside the rest of what's in progress.
                HStack(alignment: .top, spacing: Tokens.Space.s6) {
                    ResumeCard(entry: first, context: context)
                    if entries.count > 1 {
                        OnTheGoRow(entries: Array(entries.dropFirst()), context: context, inset: false)
                    }
                }
                .padding(.horizontal, metrics.gutter)
            } else {
                ResumeCard(entry: first, context: context).padding(.horizontal, metrics.gutter)
                OnTheGoRow(entries: Array(entries.dropFirst()), context: context)
            }
        }
        if !present.isEmpty { ShelfViewSwitch(view: $view) { pulled = nil } }
        ForEach(present.prefix(8)) { c in
            shelf("c-" + c.id, c.shortName, byConsole[c.id], console: c, count: c.count, faceFirst: true,
                  all: .gameLibrary(library, console: c.id))
        }
        shelf("two", say("wpMadeForTwo"), forTwo)
        if let home {
            shelf("fav", "Favourites", home.favourites)
            shelf("recent", "Recently added", home.recent)
            shelf("most", "Most played", home.mostPlayed)
            ForEach((home.shelves ?? []).filter { $0.kind == "series" }) { s in shelf("s-" + s.name, s.name, s.items, letters: true) }
            ForEach((home.shelves ?? []).filter { $0.kind == "genre" }) { s in shelf("g-" + s.name, s.name, s.items) }
        }
    }

    @ViewBuilder private func collectionRows(_ c: GameConsole) -> some View {
        CollectionBand(console: c, count: c.count, first: popular.first)
        if c.ready == false {
            Secondary(c.unavailable ?? "This server has no core for the \(c.name) yet, so these games can't start. \(model.user?.isAdmin == true ? "Install one on the website, in Settings, Consoles & cores." : "Ask whoever runs this server to install one.")")
                .padding(.horizontal, metrics.gutter)
        }
        OnTheGoRow(title: say("wpContinuePlaying"), entries: inProgress, context: context)
        if !popular.isEmpty {
            ShelfViewSwitch(view: $view) { pulled = nil }
            shelf("popular", "Most popular", popular, faceFirst: true)
        }
        YoursOn(console: c)
    }

    // MARK: Every game

    private struct Letter: Identifiable {
        let id: String
        let items: [GameItem]
    }

    /// Every game in the order chosen; A to Z, in letters.
    private var letters: [Letter] {
        guard sort == .title else { return [Letter(id: "", items: games)] }
        var out: [Letter] = []
        var run: [GameItem] = [], at = ""
        for g in games {
            let l = Shelves.initial(g.title)
            if l != at, !run.isEmpty { out.append(Letter(id: at, items: run)); run = [] }
            at = l
            run.append(g)
        }
        if !run.isEmpty { out.append(Letter(id: at, items: run)) }
        return out
    }

    private var columns: (count: Int, width: CGFloat, spacing: CGFloat) {
        let spacing: CGFloat = metrics.tv ? Tokens.Space.s8 : Tokens.Space.s3
        let room = max(240, width - 2 * metrics.gutter)
        let count = metrics.tv ? 6 : metrics.gutter > Tokens.Space.s4 ? max(4, Int(room / 170)) : 3
        return (count, ((room - CGFloat(count - 1) * spacing) / CGFloat(count)).rounded(.down), spacing)
    }

    @ViewBuilder private var everyGame: some View {
        let cols = columns
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                Text(sort == .title ? say("wpEveryGame") : "Every game")
                    .font(.system(size: metrics.tv ? 28 : 20, weight: .semibold)).foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let total { Text(total.formatted()).font(.system(size: metrics.tv ? 22 : 13)).foregroundStyle(palette.textHint) }
            }
            .padding(.horizontal, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s2) {
                    ForEach(GameSort.allCases) { s in
                        Button {
                            guard sort != s else { return }
                            sort = s
                            total = nil
                            Task { await loadGames(reset: true) }
                        } label: { ChipLabel(title: s.label, selected: sort == s) }
                        .buttonStyle(SurfaceStyle(radius: 999))
                        .accessibilityAddTraits(sort == s ? .isSelected : [])
                    }
                }
                .padding(.horizontal, metrics.gutter)
                .padding(.vertical, Tokens.Space.s1)
            }
            .remoteSection()
            if total == 0 {
                EmptyMessage(title: "No games here yet", detail: "Put your own game files in this library's folder and scan it. Zipped games and multi-disc sets work too.")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cols.width), spacing: cols.spacing, alignment: .top), count: cols.count),
                      alignment: .leading, spacing: metrics.tv ? Tokens.Space.s8 : Tokens.Space.s5) {
                ForEach(letters) { letter in
                    Section {
                        ForEach(letter.items) { game in
                            GameGridCell(item: game, context: context, width: cols.width)
                                .task { if game.id == games.last?.id, games.count < (total ?? 0) { await loadGames(reset: false) } }
                        }
                    } header: {
                        if !letter.id.isEmpty {
                            Text(letter.id)
                                .font(.system(size: metrics.tv ? 24 : 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Tokens.Space.s2)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, metrics.tv ? metrics.shelf.headroom : 0)
            .remoteSection()
        }
    }

    private var legalNote: some View {
        Secondary("Games run on your server and stream to this device. Only play games you own.")
            .padding(.horizontal, metrics.gutter)
    }

    // MARK: The page

    @ViewBuilder private var rows: some View {
        if let console {
            if let current { collectionRows(current) } else { Heading(console).padding(.horizontal, metrics.gutter) }
        } else {
            homeRows
        }
        everyGame
        legalNote
    }

    private var scroller: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.tv ? Tokens.Space.s10 : 26) {
                rows
            }
            .padding(.top, console == nil ? Tokens.Space.s4 : 0)
            .padding(.bottom, metrics.tv ? Tokens.Space.s16 : 120)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { width = $0 }
            })
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if !error.isEmpty, home == nil, consoles.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else if home == nil && consoles.isEmpty {
                ShelfLoading()
            } else {
                page
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground(palette)
        .task { await load() }
        .onChange(of: focused) { follow($0) }
    }

    @ViewBuilder private var page: some View {
        #if os(tvOS)
        if console == nil {
            VStack(spacing: 0) {
                if let shown { TvGamePreview(item: shown, context: context, scope: scope).padding(.top, Tokens.Space.s4) }
                scroller.padding(.top, Tokens.Space.s4)
                TvPromptBar()
            }
            .background(alignment: .top) {
                LinearGradient(colors: [tints.glow(shown, light: palette.isLight) ?? palette.panel, palette.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 700)
                    .animation(.easeInOut(duration: 0.4), value: shown?.id)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            .focusScope(scope)
        } else {
            scroller.focusScope(scope)
        }
        #else
        scroller.refreshable { await load() }
        #endif
    }
}
