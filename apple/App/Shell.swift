import SwiftUI
import WittyKit

/// The app's top level. The same four places on every device, arranged for each: a floating pill along
/// the bottom on iPhone, a sidebar on iPad and Mac, and the system's top tabs on Apple TV.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, music, search, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .music: return "Music"
        case .search: return "Search"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .music: return "music.note"
        case .search: return "magnifyingglass"
        case .profile: return "person"
        }
    }

    /// Not every one of these has a filled form. A symbol that doesn't exist draws nothing.
    var openIcon: String {
        switch self {
        case .home: return "house.fill"
        case .profile: return "person.fill"
        case .music, .search: return icon
        }
    }
}

struct BrowseShell: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(tvOS)
        TopTabs()
        #elseif os(macOS)
        SideShell()
        #else
        if sizeClass == .regular {
            SideShell()
        } else {
            PillShell()
        }
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
        case .music: MusicView()
        case .search: SearchView()
        case .profile: ProfileView()
        }
    }

    var body: some View {
        NavigationStack(path: model.pathBinding(tab)) {
            first
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .library(let library): LibraryView(library: library)
                    case .show(let id): ShowView(id: id)
                    case .item(let id): ItemView(id: id)
                    // A new identity for each thing played, so the next episode gets a new player
                    // and not the last one's state.
                    case .player(let id, let startOver): PlayerScreen(id: id, startOver: startOver).id(id)
                    case .web(let path):
                        #if os(iOS)
                        WebPlayerView(path: path)
                        #else
                        // Nothing on these devices opens this: see WittyKit's Rigs.swift.
                        ProblemView(words: "That can only be played on an iPhone or iPad.")
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
#endif

#if os(iOS)
/// The system's tab view holds the four stacks, with its own bar hidden and the pill in its place.
private struct PillShell: View {
    @EnvironmentObject private var model: AppModel

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
    }
}

/// Real buttons, each saying which section it is and whether it's the one open. Nearly solid, as
/// blur costs a frame on every scroll under it.
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
                    Image(systemName: open ? tab.openIcon : tab.icon)
                        .font(.title3)
                        .foregroundStyle(open ? palette.background : palette.text)
                        .frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
                        .background(Capsule().fill(open ? palette.text : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(open ? [.isSelected] : [])
            }
        }
        .padding(Tokens.Space.s1)
        .background(Capsule().fill(palette.panel.opacity(0.97)))
        .overlay(Capsule().stroke(palette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(.horizontal, Tokens.Space.s6)
        .padding(.bottom, Tokens.Space.s1)
    }
}
#endif

#if !os(tvOS)
/// iPad and Mac have the room to show the libraries all the time.
private struct SideShell: View {
    private enum Choice: Hashable {
        case tab(AppTab)
        case library(Library)
    }

    @EnvironmentObject private var model: AppModel
    @State private var choice: Choice? = .tab(.home)

    private func apply(_ new: Choice?) {
        switch new {
        case .tab(let tab)?:
            model.tab = tab
            model.paths[tab] = []
        case .library(let library)?:
            model.tab = .home
            model.paths[.home] = [.library(library)]
        case nil:
            break
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $choice) {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(Choice.tab(tab))
                }
                let openable = model.libraries.filter(\.opensHere)
                if !openable.isEmpty {
                    Section("Libraries") {
                        ForEach(openable) { library in
                            Text(library.name).tag(Choice.library(library))
                        }
                    }
                }
            }
            .navigationTitle(say("appName"))
        } detail: {
            TabRoot(tab: model.tab).id(model.tab)
        }
        .onChange(of: choice) { apply($0) }
    }
}
#endif

/// Music has no player in this app yet. Rather than hide what's on the server, this lists it and says
/// plainly where it plays for now.
struct MusicView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let listening = model.libraries.filter(\.isListening)
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("Music").font(.wmPage).accessibilityAddTraits(.isHeader)
                if listening.isEmpty {
                    EmptyMessage(title: "No music here yet", detail: "This server has no music, audiobooks or podcasts this account can open.")
                } else {
                    ForEach(listening) { library in
                        BrowserOnlyNote(library: library)
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
        }
        .pageBackground(palette)
    }
}

/// A library this app can't open yet, and where it can be. Never pretends otherwise.
struct BrowserOnlyNote: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let library: Library

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(library.name).font(.wmSection).accessibilityAddTraits(.isHeader)
            Text("This plays in a web browser for now.").foregroundStyle(palette.textSecondary)
            #if os(tvOS)
            // No browser on Apple TV, so this can only say where to go.
            Text("Open \(model.client.base) on a phone or computer.").foregroundStyle(palette.textSecondary)
            #else
            if let url = URL(string: model.client.base), WebPlayer.isWebLink(url) {
                Link("Open in your browser", destination: url)
            }
            #endif
        }
        .padding(Tokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg).fill(palette.panel))
        .accessibilityElement(children: .contain)
    }
}

/// Who's signed in, to what, and the ways out.
struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Namespace private var scope

    private func fact(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(name).font(.caption).foregroundStyle(palette.textSecondary)
            Text(value)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text(model.user?.name ?? "Profile").font(.wmPage).accessibilityAddTraits(.isHeader)
                if !model.notice.isEmpty { ProblemLine(model.notice) }
                if let server = model.current {
                    fact("Server", server.name)
                    fact("Address", server.url)
                    if !server.fingerprint.isEmpty { fact(say("fingerprintLabel"), server.fingerprint) }
                }
                fact("This app", "\(say("appName")) \(WittyClient.appVersion)")
                Text(say("legalConnect")).font(.footnote).foregroundStyle(palette.textSecondary)
                Button("Switch profile") { model.signOut() }.firstFocus(in: scope)
                Button(say("changeServer")) { model.changeServer() }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
        }
        .focusRoot(scope)
        .pageBackground(palette)
    }
}

/// What's asked of the server for this, in `WittyClient.search`. A short pause after typing keeps it
/// from asking on every letter.
struct SearchView: View {
    @Environment(\.client) private var client
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
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
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("Search").font(.wmPage).accessibilityAddTraits(.isHeader)
                // On Apple TV choosing this opens the system's keyboard, which a phone can also type into.
                TextField("Films and shows", text: $query)
                    .plainEntry()
                    .accessibilityLabel("Search films and shows")
                    .focused($focused, equals: "field")
                if !error.isEmpty {
                    ProblemLine(error)
                    Button("Try again") { Task { await run(query) } }
                } else if searching && results == nil {
                    LoadingView()
                } else if let results {
                    if results.isEmpty {
                        EmptyMessage(title: "Nothing found", detail: "Try fewer words, or check the spelling.")
                    } else {
                        CardGrid(items: results.items, shows: results.shows, focus: $focused)
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
        }
        .pageBackground(palette)
        .task(id: query) { await run(query) }
    }
}
