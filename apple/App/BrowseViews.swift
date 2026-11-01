import SwiftUI
import WittyKit

private func runtimeText(_ seconds: Double?) -> String? {
    guard let seconds, seconds > 0 else { return nil }
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
}

/// One line of facts about something, with the dots only between what's there.
private func factLine(_ item: Item) -> String {
    var facts: [String] = []
    if let year = item.year { facts.append(String(year)) }
    if let runtime = runtimeText(item.runtimeSec) { facts.append(runtime) }
    if let rating = item.contentRating, !rating.isEmpty { facts.append(rating) }
    return facts.joined(separator: " · ")
}

private func displayTitle(_ item: Item) -> String {
    (item.showTitle?.isEmpty == false ? item.showTitle : nil) ?? item.title
}

/// A poster with its words, all one thing to a screen reader, which also hears how far through it is.
struct Tile: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let subtitle: String
    let url: URL?
    let route: Route
    var progress: Double?
    let focus: FocusState<String?>.Binding
    let focusKey: String

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                ArtImage(url: url, width: Tokens.cardWidth)
                    .frame(width: Tokens.cardWidth, height: Tokens.cardWidth * 1.5)
                    .overlay(alignment: .bottom) {
                        if let progress {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .padding(Tokens.Space.s1)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                Text(title).font(.wmCard).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.wmCardSub).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                }
            }
            .frame(width: Tokens.cardWidth, alignment: .leading)
        }
        .tileStyle()
        .focused(focus, equals: focusKey)
        .accessibilityLabel(subtitle.isEmpty ? title : "\(title), \(subtitle)")
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent watched" } ?? "")
    }
}

private struct ItemTile: View {
    @Environment(\.client) private var client
    let item: Item
    let focus: FocusState<String?>.Binding

    var body: some View {
        let subtitle = item.episodeLabel.isEmpty ? (item.year.map(String.init) ?? "") : item.episodeLabel
        Tile(title: displayTitle(item), subtitle: subtitle, url: client.posterURL(item), route: .item(item.id),
             progress: item.progressFraction, focus: focus, focusKey: "item\(item.id)")
    }
}

private struct ShowTile: View {
    @Environment(\.client) private var client
    let show: Show
    let focus: FocusState<String?>.Binding

    private var subtitle: String {
        if let unwatched = show.unwatched, unwatched > 0 { return "\(unwatched) unwatched" }
        return show.year.map(String.init) ?? ""
    }

    var body: some View {
        Tile(title: show.title, subtitle: subtitle, url: client.posterURL(show), route: .show(show.id),
             focus: focus, focusKey: "show\(show.id)")
    }
}

/// A grid of cards that fits the width. What it's given has already had repeats removed.
struct CardGrid: View {
    let items: [Item]
    let shows: [Show]
    let focus: FocusState<String?>.Binding
    var onLast: (() async -> Void)?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Tokens.cardWidth), spacing: Tokens.Space.s4, alignment: .top)], spacing: Tokens.Space.s6) {
            ForEach(shows) { ShowTile(show: $0, focus: focus) }
            ForEach(items) { item in
                ItemTile(item: item, focus: focus).task {
                    if item.id == items.last?.id { await onLast?() }
                }
            }
        }
        .remoteSection()
    }
}

/// A row of cards. On Apple TV a focus section, so moving up and down from anywhere along it finds the
/// next row, however its cards line up.
private struct HubRow: View {
    let hub: Hub
    let focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(hub.title).font(.wmSection).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Tokens.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s4) {
                    ForEach(uniqued(hub.items ?? [])) { ItemTile(item: $0, focus: focus) }
                    ForEach(uniqued(hub.shows ?? [])) { ShowTile(show: $0, focus: focus) }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.vertical, Tokens.focusRoom)
            }
            .remoteSection()
        }
    }
}

/// The libraries along the top. Choosing one changes the page under them, with Back returning to Home.
private struct LibraryTabs: View {
    let libraries: [Library]
    @Binding var selected: Library?
    var gamePCs = false

    private func tab(_ title: String, _ library: Library?) -> some View {
        Button {
            selected = library
        } label: {
            ChipLabel(title: title, selected: selected == library)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == library ? [.isSelected] : [])
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                tab("Home", nil)
                ForEach(libraries) { tab($0.name, $0) }
                #if os(iOS)
                if gamePCs {
                    NavigationLink(value: Route.web(WebPlayer.gamePCsPath)) {
                        ChipLabel(title: "Game PCs", selected: false)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.focusRoom)
        }
        .remoteSection()
    }
}

/// The big picture at the top with its one main action. A wide picture where there's room, and a
/// tall poster on a phone. It doesn't turn by itself: nothing moves that nobody asked to move.
private struct HeroView: View {
    @Environment(\.client) private var client
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let item: Item
    let scope: Namespace.ID

    private var wide: Bool {
        #if os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    private var actions: some View {
        HStack(spacing: Tokens.Space.s3) {
            NavigationLink(value: Route.player(item.id, startOver: item.resumeSeconds == nil)) {
                Label(item.resumeSeconds == nil ? "Play" : "Resume", systemImage: "play.fill")
            }
            .mainAction()
            .firstFocus(in: scope)
            .accessibilityLabel("\(item.resumeSeconds == nil ? "Play" : "Resume") \(displayTitle(item))")
            NavigationLink(value: Route.item(item.id)) { Text("More") }
                .buttonStyle(.bordered)
                .accessibilityLabel("More about \(displayTitle(item))")
        }
    }

    var body: some View {
        if wide {
            ZStack(alignment: .bottomLeading) {
                ArtImage(url: client.backdropURL(item), width: 1280)
                    .frame(maxWidth: .infinity)
                    .frame(height: Tokens.heroHeight)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text(displayTitle(item)).font(.wmDisplay).foregroundStyle(.white).lineLimit(2).accessibilityAddTraits(.isHeader)
                    Text(factLine(item)).foregroundStyle(.white.opacity(0.85))
                    actions.padding(.top, Tokens.Space.s2).remoteSection()
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, Tokens.Space.s8)
            }
            .frame(height: Tokens.heroHeight)
        } else {
            VStack(spacing: Tokens.Space.s3) {
                ArtImage(url: client.posterURL(item), width: Tokens.heroPosterWidth)
                    .frame(width: Tokens.heroPosterWidth, height: Tokens.heroPosterWidth * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                Text(displayTitle(item)).font(.title2.weight(.bold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                Text(factLine(item)).font(.subheadline).foregroundStyle(.secondary)
                actions
            }
            .padding(.horizontal, Tokens.gutter)
            .frame(maxWidth: .infinity)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var home: Home?
    @State private var error = ""
    @State private var gamePCs = false
    @State private var selected: Library?
    @FocusState private var focused: String?
    /// What had focus when this screen was left. Coming back puts it there.
    @State private var lastFocused: String?
    @Namespace private var scope

    /// Sidebars list them already.
    private var showsTabs: Bool {
        #if os(macOS)
        return false
        #elseif os(iOS)
        return sizeClass != .regular
        #else
        return true
        #endif
    }

    private func load() async {
        do {
            let fresh = try await client.home()
            error = ""
            if fresh != home { home = fresh }
            model.homeLoaded(fresh)
        } catch {
            // A page already showing stays up. A failed refresh is no reason to lose it.
            let words = model.handle(error)
            if home == nil, !words.isEmpty { self.error = words }
        }
        #if os(iOS)
        gamePCs = (try? await client.couchStatus())?.allowed == true
        #endif
    }

    @ViewBuilder private func page(_ home: Home) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Space.s6) {
                if showsTabs {
                    LibraryTabs(libraries: model.libraries, selected: $selected, gamePCs: gamePCs)
                }
                if !model.notice.isEmpty {
                    ProblemLine(model.notice).padding(.horizontal, Tokens.gutter)
                }
                if let selected {
                    LibraryContent(library: selected).id(selected.id)
                } else {
                    if let hero = home.hero { HeroView(item: hero, scope: scope) }
                    ForEach(uniqued(home.hubs ?? []).filter { !$0.isEmpty }) { HubRow(hub: $0, focus: $focused) }
                    if home.hero == nil, (home.hubs ?? []).allSatisfy(\.isEmpty) {
                        EmptyMessage(title: "Nothing here yet", detail: "Add a library on the server, or ask whoever runs it.")
                    }
                }
            }
            .padding(.vertical, Tokens.edge)
        }
        .focusRoot(scope)
    }

    var body: some View {
        ZStack {
            if let home {
                page(home)
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .pageBackground(palette)
        .onRemoteBack(selected == nil ? nil : { selected = nil })
        .onChange(of: focused) { new in
            if let new { lastFocused = new }
        }
        .onAppear {
            // Runs again on coming back from a screen pushed on top of this one.
            if let lastFocused { DispatchQueue.main.async { focused = lastFocused } }
        }
        // Again on every return, as what's "continue watching" has probably just changed.
        .task { await load() }
    }
}

/// One library's cards, however it's framed. Grows as it's scrolled.
struct LibraryContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    let library: Library
    @State private var items: [Item] = []
    @State private var shows: [Show] = []
    @State private var total: Int?
    @State private var error = ""
    @State private var loading = false
    @FocusState private var focused: String?
    private let pageSize = 60

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            if library.isShows {
                let page = try await client.shows(library: library.id)
                shows = uniqued(page.shows ?? [])
                total = page.total ?? shows.count
            } else {
                let page = try await client.items(library: library.id, offset: items.count, limit: pageSize)
                let fresh = uniqued(items + (page.items ?? []))
                // A server that sends nothing new can't keep this asking for ever.
                let finished = fresh.count == items.count
                items = fresh
                total = finished ? items.count : (page.total ?? items.count)
            }
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    var body: some View {
        ZStack {
            if !library.opensHere {
                BrowserOnlyNote(library: library).padding(.horizontal, Tokens.gutter)
            } else if !error.isEmpty, total == nil {
                ProblemView(words: error, retry: { error = ""; Task { await loadMore() } })
            } else if total == nil {
                LoadingView()
            } else if total == 0 {
                EmptyMessage(title: "Nothing in \(library.name) yet", detail: "Once the server has finished looking through its files, they'll be here.")
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    CardGrid(items: items, shows: shows, focus: $focused, onLast: {
                        if items.count < (total ?? 0) { await loadMore() }
                    })
                    if !error.isEmpty {
                        ProblemLine(error)
                        Button("Try again") { error = ""; Task { await loadMore() } }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
            }
        }
        .task { if library.opensHere, total == nil { await loadMore() } }
    }
}

/// A library as a screen of its own, from a sidebar.
struct LibraryView: View {
    @Environment(\.palette) private var palette
    let library: Library

    var body: some View {
        ScrollView {
            LibraryContent(library: library).padding(.vertical, Tokens.edge)
        }
        .navigationTitle(library.name)
        .pageBackground(palette)
    }
}

/// The wide picture at the top of a show or an item, fading into the page.
private struct Backdrop: View {
    @Environment(\.palette) private var palette
    let url: URL?

    var body: some View {
        ArtImage(url: url, width: 1280)
            .frame(maxWidth: .infinity)
            .frame(height: Tokens.heroHeight * 0.6)
            .overlay(LinearGradient(colors: [.clear, palette.background], startPoint: .center, endPoint: .bottom))
    }
}

struct ShowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let id: Int64
    @State private var detail: ShowDetail?
    @State private var season: Int?
    @State private var error = ""
    @Namespace private var scope

    private func load() async {
        do {
            let fresh = try await client.show(id)
            error = ""
            if fresh != detail { detail = fresh }
        } catch {
            let words = model.handle(error)
            if detail == nil, !words.isEmpty { self.error = words }
        }
    }

    private func episodeRow(_ episode: Item) -> some View {
        NavigationLink(value: Route.item(episode.id)) {
            HStack(spacing: Tokens.Space.s3) {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text("\(episode.episodeLabel)  \(episode.title)")
                    if let fraction = episode.progressFraction {
                        ProgressView(value: fraction).progressViewStyle(.linear).accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 0)
                if episode.progress?.watched == true {
                    Label("Watched", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Tokens.minTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .tileStyle()
        .accessibilityLabel("\(episode.episodeLabel), \(episode.title)")
        .accessibilityValue(episode.progress?.watched == true ? "Watched" : (episode.progressFraction.map { "\(Int($0 * 100)) percent watched" } ?? ""))
    }

    var body: some View {
        ZStack {
            if let detail {
                let selected = season ?? detail.seasons?.first?.number
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        Backdrop(url: client.backdropURL(detail.show))
                        Group {
                            Text(detail.show.title).font(.wmPage).accessibilityAddTraits(.isHeader)
                            if let overview = detail.show.overview, !overview.isEmpty {
                                Text(overview).foregroundStyle(palette.textSecondary).lineLimit(4)
                            }
                            if let next = detail.nextUpId {
                                NavigationLink(value: Route.player(next, startOver: false)) {
                                    Label("Play next up", systemImage: "play.fill")
                                }
                                .mainAction()
                                .firstFocus(in: scope)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Tokens.Space.s2) {
                                    ForEach(uniqued(detail.seasons ?? [])) { s in
                                        Button {
                                            season = s.number
                                        } label: {
                                            ChipLabel(title: s.displayTitle, selected: s.number == selected)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityAddTraits(s.number == selected ? [.isSelected] : [])
                                    }
                                }
                                .padding(.vertical, Tokens.focusRoom)
                            }
                            .remoteSection()
                            ForEach(uniqued(detail.episodes ?? []).filter { $0.season == selected }) { episodeRow($0) }
                        }
                        .padding(.horizontal, Tokens.gutter)
                    }
                    .padding(.bottom, Tokens.edge)
                }
                .focusRoot(scope)
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .pageBackground(palette)
        .task(id: id) { await load() }
    }
}

struct ItemView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let id: Int64
    @State private var item: Item?
    @State private var error = ""
    @Namespace private var scope

    private func load() async {
        do {
            let fresh = try await client.item(id)
            error = ""
            if fresh != item { item = fresh }
        } catch {
            let words = model.handle(error)
            if item == nil, !words.isEmpty { self.error = words }
        }
    }

    @ViewBuilder private func actions(_ item: Item) -> some View {
        if item.isRigGame {
            if let tagline = item.tagline, !tagline.isEmpty { Text(tagline).foregroundStyle(palette.textSecondary) }
            RigPlayPanel(item: item)
        } else if item.isPlayable {
            HStack(spacing: Tokens.Space.s3) {
                if let resume = item.resumeSeconds {
                    NavigationLink(value: Route.player(item.id, startOver: false)) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .mainAction()
                    .firstFocus(in: scope)
                    .accessibilityLabel("Resume from \(runtimeText(resume) ?? "where you stopped")")
                    NavigationLink("Start over", value: Route.player(item.id, startOver: true))
                } else {
                    NavigationLink(value: Route.player(item.id, startOver: true)) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .mainAction()
                    .firstFocus(in: scope)
                }
            }
            .remoteSection()
        } else {
            Text("This plays in a web browser for now.").foregroundStyle(palette.textSecondary)
        }
    }

    var body: some View {
        ZStack {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        Backdrop(url: client.backdropURL(item))
                        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            if let show = item.showTitle, !show.isEmpty {
                                Text("\(show) · \(item.episodeLabel)").foregroundStyle(palette.textSecondary)
                            }
                            Text(item.title).font(.wmPage).accessibilityAddTraits(.isHeader)
                            Text(factLine(item)).foregroundStyle(palette.textSecondary)
                            if let genres = item.genres, !genres.isEmpty {
                                Text(genres.joined(separator: ", ")).foregroundStyle(palette.textSecondary)
                            }
                            actions(item)
                            if let overview = item.overview, !overview.isEmpty {
                                Text(overview).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: 900, alignment: .leading)
                        .padding(.horizontal, Tokens.gutter)
                    }
                    .padding(.bottom, Tokens.edge)
                }
                .focusRoot(scope)
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .pageBackground(palette)
        .task(id: id) { await load() }
    }
}
