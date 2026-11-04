import SwiftUI
import WittyKit

/// The app's top level, as on Android (ui/Shell.kt): Home, Search and Profile. A phone, a tablet and
/// Apple Vision Pro have them in a floating pill at the bottom, within reach of a thumb; Apple TV has
/// the system's tabs along the top, where up from the first row gets to them. Music and the other
/// libraries are on Home, as they are on Android.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, search, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .profile: return "person"
        }
    }

    /// Not every one of these has a filled form. A symbol that doesn't exist draws nothing.
    var openIcon: String {
        switch self {
        case .home: return "house.fill"
        case .profile: return "person.fill"
        case .search: return icon
        }
    }
}

struct BrowseShell: View {
    var body: some View {
        #if os(tvOS)
        TopTabs()
        #else
        PillShell()
        #endif
    }
}

/// One tab's stack of screens. Every route opens from here, whichever tab it's in.
private struct TabRoot: View {
    @EnvironmentObject private var model: AppModel
    let tab: AppTab

    @ViewBuilder private var first: some View {
        switch tab {
        case .home: HomeView()
        case .search: SearchView()
        case .profile: ProfileView()
        }
    }

    var body: some View {
        NavigationStack(path: model.pathBinding(tab)) {
            first
                .noNavigationBar()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .library(let library): LibraryView(library: library).plainNavigation()
                    case .show(let id): ShowView(id: id).plainNavigation()
                    case .item(let id): ItemView(id: id).plainNavigation()
                    // A new identity for each thing played, so the next episode gets a new player
                    // and not the last one's state.
                    case .player(let id, let startOver): PlayerScreen(id: id, startOver: startOver).id(id)
                    case .notices: NoticesView().plainNavigation()
                    case .logs: LogsView().plainNavigation()
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
                    #else
                    // Apple TV's own screens. These devices show the server's page for all of them.
                    case .album, .photo, .guide, .channel:
                        #if os(iOS) || os(visionOS)
                        WebPlayerView(path: ServerPages.guide, keptToGames: false)
                        #else
                        ElsewhereNote(path: ServerPages.guide)
                        #endif
                    #endif
                    }
                }
        }
    }
}

#if os(tvOS)
/// The Siri Remote moves along these with the focus engine. Back from a tab's content goes to the tab
/// bar, and Back from there leaves the app, which is what the system does and people expect.
private struct TopTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            ForEach(AppTab.allCases) { tab in
                TabRoot(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
    }
}
#else
/// The system's tab view holds the three stacks, with its own bar hidden and the pill in its place.
private struct PillShell: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        TabView(selection: $model.tab) {
            ForEach(AppTab.allCases) { tab in
                TabRoot(tab: tab)
                    .safeAreaInset(edge: .bottom) {
                        if !model.hidesBars { PillBar() }
                    }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        // What scrolls under the clock and the battery fades out, so they can still be read.
        .overlay(alignment: .top) {
            if !model.hidesBars {
                GeometryReader { geo in
                    LinearGradient(colors: [palette.background.opacity(0.92), palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)
                }
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
            ForEach(AppTab.allCases) { tab in
                let open = model.tab == tab
                Button {
                    press(tab)
                } label: {
                    HStack(spacing: Tokens.Space.s2) {
                        Image(systemName: open ? tab.openIcon : tab.icon).font(.body.weight(.semibold))
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
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            #if os(tvOS)
            Secondary("Apple TV can't show this, as it has no way to open your server's own pages. Open \(model.client.base) on a phone, tablet or computer.")
            #else
            if let url = model.client.mediaURL(path), WebPlayer.isWebLink(url) {
                Link("Open in your browser", destination: url).action(primary: true)
            }
            #endif
        }
        .padding(Tokens.gutter)
        .pageBackground(palette)
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

/// Who's signed in and to what, and the ways out of that, as on Android's Profile.
struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Namespace private var scope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Heading("Profile")
                if !model.notice.isEmpty { ProblemLine(model.notice) }
                if let name = model.user?.name, !name.isEmpty { Secondary("Signed in as \(name)") }
                if let server = model.current {
                    SectionTitle(server.name)
                    Secondary(server.url)
                    if !server.fingerprint.isEmpty { Secondary("\(say("fingerprintLabel")): \(server.fingerprint)") }
                }
                #if os(iOS) || os(visionOS)
                NavigationLink("Server settings", value: Route.page(ServerPages.settings)).action(wide: true)
                #endif
                Button("Sign out") { model.signOut() }.action(wide: true).firstFocus(in: scope)
                Button(say("changeServer")) { model.changeServer() }.action(wide: true)
                SectionTitle("About this app").padding(.top, Tokens.Space.s3)
                Secondary("\(say("appName")) \(WittyClient.appVersion)")
                NavigationLink("Licences", value: Route.notices).action(wide: true)
                NavigationLink("This app's log", value: Route.logs).action(wide: true)
                Secondary(say("legalConnect"))
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, Tokens.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusRoot(scope)
        .pageBackground(palette)
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
