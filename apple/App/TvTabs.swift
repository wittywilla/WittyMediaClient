#if os(tvOS)
import SwiftUI
import WittyKit

// Apple TV's bar along the top and the three tabs only a TV has: Libraries, Games and Live TV
// (docs/APP-DESIGN.md, On a TV). Android TV has the same bar and the same tabs, drawn alike.

// MARK: - The bar

/// Pills the gutter in from the sides and 24 down. From the left: Home, Libraries, Games, Live TV, Search and any
/// libraries added to the top menu, which scroll sideways with focus when they don't all fit. On its own at the right
/// edge, never moving: You. Focus goes along the whole row, You last. Choosing one shows that tab and keeps focus on
/// its pill, one press from what's below. Back from here goes to Home's pill, and from Home's out of the app, as the
/// system does.
struct TvTopBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var focus: FocusState<AppTab?>.Binding
    /// Which pill had focus last, nil while it's below the bar.
    @State private var inside: AppTab?

    private func choose(_ tab: AppTab) {
        if model.tab == tab {
            model.paths[tab] = []
        } else {
            model.tab = tab
        }
    }

    private var back: (() -> Void)? {
        guard model.tab != .home else { return nil }
        return {
            if !(model.paths[.home] ?? []).isEmpty { model.paths[.home] = [] }
            model.tab = .home
            focus.wrappedValue = .home
        }
    }

    /// The libraries added to the top menu, in the server's order.
    private var added: [Library] { model.libraries.filter { model.topMenu.contains($0.id) } }

    private func pill(_ tab: AppTab, _ name: String, _ symbol: String) -> some View {
        TvTabPill(name: name, symbol: symbol, user: tab == .profile ? model.user : nil, chosen: model.tab == tab) { choose(tab) }
            .focused(focus, equals: tab)
    }

    var body: some View {
        // Each pill keeps room for its ring and its growth around it, so the pills themselves start at the gutter,
        // sit 24 from the top and are 16 apart.
        let ring = metrics.focusRing
        HStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.Space.s4 - ring * 2) {
                        ForEach(AppTab.tvTabs) { pill($0, $0.title, $0.icon).id($0) }
                        ForEach(added) { pill(.library($0.id), $0.name, $0.barSymbol).id(AppTab.library($0.id)) }
                    }
                    .padding(.leading, metrics.gutter - ring)
                    // Room for the last pill to come clear of the fade.
                    .padding(.trailing, TvTopBar.fade + ring)
                    .padding(.vertical, ring)
                }
                // Pills that don't fit fade out towards You, rather than stop short against the edge.
                .mask(HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: TvTopBar.fade)
                })
                // The focused pill comes to the middle, so it's never in the fade.
                .onChange(of: focus.wrappedValue) { next in
                    guard let next, next != .profile else { return }
                    if reduceMotion {
                        scroller.scrollTo(next, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: Tokens.Motion.focus)) { scroller.scrollTo(next, anchor: .center) }
                    }
                }
            }
            // Space, not a line, keeps You apart from the rest: 32 from the edge of the pills on the left.
            pill(.profile, AppTab.profile.title, AppTab.profile.icon)
                .padding(.vertical, ring)
                .padding(.leading, Tokens.Space.s8 - ring)
                .padding(.trailing, metrics.gutter - ring)
        }
        .padding(.top, Tokens.Space.s6 - ring * 2)
        .padding(.bottom, Tokens.Space.s4 - ring * 2)
        .focusSection()
        .onExitCommand(perform: back)
        // Up from a tab lands on that tab's pill, whichever pill happens to be above.
        .onChange(of: focus.wrappedValue) { next in
            if let next, inside == nil, next != model.tab {
                focus.wrappedValue = model.tab
                inside = model.tab
            } else {
                inside = next
            }
        }
    }

    /// How far the pills that don't fit fade out, before the space before You.
    static let fade: CGFloat = 48
}

/// A tab's icon and name, or You's avatar and the person's name. The chosen one has the accent behind it.
private struct TvTabPill: View {
    @Environment(\.palette) private var palette
    let name: String
    let symbol: String
    let user: User?
    let chosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s3) {
                if let user {
                    AvatarTile(name: user.shownName, size: 28)
                    Text(user.shownName)
                } else {
                    Image(systemName: symbol).accessibilityHidden(true)
                    Text(name)
                }
            }
            .font(.wmLabel)
            .lineLimit(1)
            .foregroundStyle(chosen ? palette.accentText : palette.textSecondary)
            .padding(.horizontal, Tokens.Space.s6)
            .frame(height: TvTabPill.height)
        }
        .buttonStyle(SurfaceStyle(fill: chosen ? palette.accent.opacity(0.14) : nil, radius: 999))
        .accessibilityLabel(user == nil ? name : say("youTab"))
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    /// You's avatar with 12 above and below it, the same for every pill.
    static let height: CGFloat = 52
}

// MARK: - Libraries

/// Every library this profile can see, as tiles: the phone's Menu list as a page. Each opens as it
/// does from Home's row of libraries.
struct LibrariesPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var libraries: [Library]?
    @State private var error = ""
    @FocusState private var focused: Int64?
    /// What had focus when this screen was left. Coming back puts it there.
    @State private var lastFocused: Int64?

    private func load() async {
        do {
            let fresh = uniqued(try await client.libraries())
            error = ""
            if fresh != libraries { libraries = fresh }
        } catch {
            // A page already showing stays up. A failed refresh is no reason to lose it.
            let words = model.handle(error)
            if libraries == nil, !words.isEmpty { self.error = words }
        }
    }

    private func grid(_ libraries: [Library]) -> some View {
        // The tiles keep their rings' room inside them: 32 between tiles, the first at the gutter.
        let ring = metrics.focusRing
        let gap = Tokens.Space.s8 - ring * 2
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 4), spacing: gap) {
                ForEach(libraries) { library in
                    NavigationLink(value: Route.library(library)) { LibraryTile(library: library) }
                        .buttonStyle(SurfaceStyle(fill: palette.panel, radius: Tokens.Radius.lg))
                        .focused($focused, equals: library.id)
                        .accessibilityLabel(library.name)
                }
            }
            .padding(.horizontal, metrics.gutter - ring)
            .padding(.top, Tokens.Space.s6 - ring)
            .padding(.bottom, Tokens.Space.s8)
        }
    }

    var body: some View {
        ZStack {
            if let libraries {
                if libraries.isEmpty {
                    EmptyMessage(title: say("librariesNone"), detail: say("librariesNoneDetail"))
                } else {
                    grid(libraries)
                }
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground(palette)
        .onChange(of: focused) { new in
            if let new { lastFocused = new }
        }
        .onAppear {
            // Runs again on coming back from a library.
            if let lastFocused { DispatchQueue.main.async { focused = lastFocused } }
        }
        .task { await load() }
    }
}

/// The website's library tile at a TV's size: the library's icon on the accent, then its name.
private struct LibraryTile: View {
    @Environment(\.palette) private var palette
    let library: Library

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            Image(systemName: library.tileSymbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.accent.opacity(0.14)))
                .accessibilityHidden(true)
            Text(library.name)
                .font(.wmLabel)
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s4)
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
    }
}

extension Library {
    /// A library's icon in the top menu: its tile's icon in outline, as the bar's others are.
    var barSymbol: String { tileSymbol.replacingOccurrences(of: ".fill", with: "") }

    /// The website's icon for each kind of library (web/src/icons.tsx, `libIcon`), as a symbol.
    var tileSymbol: String {
        switch type {
        case "games": return "gamecontroller.fill"
        case "photos": return "photo.fill"
        case "shorts": return "rectangle.portrait.on.rectangle.portrait.fill"
        case "channels", "musicvideos": return "play.rectangle.fill"
        case "radio": return "radio.fill"
        case "movies": return "film.fill"
        case "shows": return "tv.fill"
        case "anime": return "star.fill"
        case "music": return "music.note"
        case "podcasts": return "mic.fill"
        case "audiobooks": return "headphones"
        case "books": return "book.closed.fill"
        case "videos": return "video.fill"
        default: return "opticaldisc.fill"
        }
    }
}

// MARK: - Games

/// WittyPlay's couch library. One games library opens straight in; several are a row each, as Home's
/// rows are: the library's name and a pill for the whole of it, then its covers.
struct GamesTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var libraries: [Library]?
    @State private var error = ""

    private func load() async {
        do {
            let fresh = uniqued(try await client.libraries()).filter(\.hasGameScreens)
            error = ""
            if fresh != libraries { libraries = fresh }
        } catch {
            let words = model.handle(error)
            if libraries == nil, !words.isEmpty { self.error = words }
        }
    }

    var body: some View {
        ZStack {
            if let libraries {
                if libraries.isEmpty {
                    EmptyMessage(title: say("gamesNone"), detail: say("gamesNoneDetail"))
                } else if libraries.count == 1 {
                    GamesLibraryView(library: libraries[0], console: nil)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Tokens.Space.s5) {
                            ForEach(libraries) { GamesShelf(library: $0) }
                        }
                        .padding(.top, Tokens.Space.s6)
                        .padding(.bottom, Tokens.Space.s6)
                    }
                }
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground(palette)
        .task { await load() }
    }
}

/// One games library's row: its name and a pill that opens it, then its most played covers.
private struct GamesShelf: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let library: Library
    @State private var games: [GameItem]?
    @State private var consoles: [String: GameConsole] = [:]

    private func load() async {
        do {
            async let found = client.games(library: library.id, sort: "popular", limit: GamesShelf.length)
            async let known = client.gameConsoles(library: library.id)
            let fresh = uniqued(try await found.items ?? [])
            consoles = Dictionary((try? await known)?.map { ($0.id, $0) } ?? [], uniquingKeysWith: { a, _ in a })
            if fresh != games { games = fresh }
        } catch {
            _ = model.handle(error)
            if games == nil { games = [] }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack(spacing: Tokens.Space.s4) {
                SectionTitle(library.name)
                NavigationLink(say("gamesAll"), value: Route.gameLibrary(library, console: nil)).action(pill: true)
            }
            .padding(.horizontal, metrics.gutter)
            .focusSection()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s6) {
                    ForEach(games ?? []) { game in
                        GameCard(game: game, console: consoles[game.console ?? ""])
                    }
                }
                .padding(.horizontal, metrics.gutter)
                .padding(.vertical, Tokens.focusRoom)
            }
            .frame(minHeight: games == nil ? metrics.cardWidth * 1.4 : nil)
            .focusSection()
        }
        .task { if games == nil { await load() } }
    }

    /// As many covers as fill a row and a little more.
    static let length = 20
}

// MARK: - Live TV

/// WittyTV's guide, in the account's look, with Recordings at its top. A server with no channels says so.
struct LiveTvTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    /// Whether the server has any channels this profile can see, once asked.
    @State private var hasChannels: Bool?
    @State private var error = ""

    private func load() async {
        do {
            let lineup = try await client.lineup()
            error = ""
            hasChannels = !(lineup.channels ?? []).isEmpty
        } catch let refused as APIError where refused.status == 404 {
            // A server without live TV at all.
            hasChannels = false
        } catch {
            let words = model.handle(error)
            if hasChannels == nil, !words.isEmpty { self.error = words }
        }
    }

    var body: some View {
        ZStack {
            if hasChannels == true {
                GuideView()
            } else if hasChannels == false {
                EmptyMessage(title: say("liveTvNone"), detail: say("liveTvNoneDetail"))
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground(palette)
        .task { await load() }
    }
}
#endif
