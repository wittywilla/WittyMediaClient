#if os(tvOS)
import SwiftUI
import WittyKit

// Apple TV's bar along the top and the three tabs only a TV has: Libraries, Games and Live TV
// (docs/APP-DESIGN.md, On a TV). Android TV has the same bar and the same tabs, drawn alike.

// MARK: - The bar

/// Six pills, the gutter in from the side and 24 down: Home, Libraries, Games, Live TV, Search and You.
/// Choosing one shows that tab and keeps focus on its pill, one press from what's below. Back from
/// here goes to Home's pill, and from Home's out of the app, as the system does.
struct TvTopBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.metrics) private var metrics
    var focus: FocusState<AppTab?>.Binding

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

    var body: some View {
        // Each pill keeps room for its ring around it, so the pills themselves start at the gutter,
        // sit 24 from the top and are 16 apart.
        let ring = metrics.focusRing
        HStack(spacing: Tokens.Space.s4 - ring * 2) {
            ForEach(AppTab.tvTabs) { tab in
                TvTabPill(tab: tab, chosen: model.tab == tab, user: model.user) { choose(tab) }
                    .focused(focus, equals: tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.gutter - ring)
        .padding(.top, Tokens.Space.s6 - ring)
        .padding(.bottom, Tokens.Space.s4 - ring)
        .focusSection()
        .onExitCommand(perform: back)
    }
}

/// A tab's icon and name, or You's avatar and the person's name. The chosen one has the accent behind it.
private struct TvTabPill: View {
    @Environment(\.palette) private var palette
    let tab: AppTab
    let chosen: Bool
    let user: User?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s3) {
                if tab == .profile, let user {
                    AvatarTile(name: user.shownName, size: 28)
                    Text(user.shownName)
                } else {
                    Image(systemName: tab.icon).accessibilityHidden(true)
                    Text(tab.title)
                }
            }
            .font(.wmLabel)
            .lineLimit(1)
            .foregroundStyle(chosen ? palette.accentText : palette.textSecondary)
            .padding(.horizontal, Tokens.Space.s6)
            .frame(height: TvTabPill.height)
        }
        .buttonStyle(SurfaceStyle(fill: chosen ? palette.accent.opacity(0.14) : nil, radius: 999))
        .accessibilityLabel(tab.title)
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

private extension Library {
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

/// WittyPlay's couch library. One games library opens straight in; several are a row each.
struct GamesTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @State private var libraries: [Library]?
    @State private var error = ""

    private func load() async {
        do {
            let fresh = uniqued(try await client.libraries()).filter { $0.type == "games" && !$0.isRigGames }
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
                } else {
                    LibraryView(library: libraries[0])
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
