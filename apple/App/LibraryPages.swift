import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// A film, TV, disc or video library's page on a phone and a tablet, as the server's website draws it at phone size
// (web/src/pages/library/VideoLibrary.tsx, Filters.tsx and web/src/components/LibraryHeader.tsx): the strip, the
// library's bar with its name, count, Filters and "⋯", the sorts as plain words, then its shelves; a grid once
// anything is asked for. What's chosen is held as the website holds it in its address (WittyKit's `LibraryState`),
// so a saved view is the same thing on every client. Selecting titles to edit together and arranging categories
// are the server's own page's, which "⋯" opens. docs/APP-DESIGN.md, Library pages.

struct LibraryPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @ScaledMetric(relativeTo: .subheadline) private var countSize: CGFloat = 14
    let library: Library
    @State private var state = LibraryState()
    @State private var shelves: Shelves?
    @State private var listing: ListingStatus?
    @State private var views: [SavedView] = []
    @State private var logos: [String: LogoInfo] = [:]
    @State private var allCount: Int?
    @State private var gridCount: Int?
    /// Titles waiting for an administrator to check their match.
    @State private var waiting = 0
    @State private var scanning: ScanState.Progress?
    /// Scans that have finished while the page was open: each asks for everything again.
    @State private var scans = 0
    @State private var solid = 0.0
    @State private var filtersOpen = false
    @State private var toolsOpen = false
    @State private var saving = false
    /// Save this view from the Filters sheet opens once that sheet has gone.
    @State private var saveAfterFilters = false
    @State private var said = ""

    /// Films, shows, discs and videos have the website's shelves; anything else here is a grid of its own.
    private var browses: Bool { ["movies", "shows", "anime", "videos", "discs"].contains(library.type) }
    private var bare: Bool { shelves?.bare ?? false }
    private var grid: Bool { state.grid(bare: bare) }
    private var isAdmin: Bool { model.user?.isAdmin == true }

    private var allName: String {
        switch library.type {
        case "shows", "anime": return "All shows"
        case "discs": return "All discs"
        case "videos": return "All videos"
        default: return "All films"
        }
    }

    /// The grid's own count once it's in, else the whole library's.
    private var count: Int? { grid ? (gridCount ?? allCount) : allCount }

    /// The website's card sizes, set in `vw` (library.css): a phone keeps them at their least.
    private var categoryWidth: CGFloat { min(max(220, screenSize.width * 0.26), 340) }
    private var logoSize: CGSize { CGSize(width: min(max(180, screenSize.width * 0.2), 280), height: min(max(96, screenSize.width * 0.1), 136)) }

    /// The logos the page shows: a service only while listings are on, as only then is its shelf there.
    private var wantedLogos: [LogoRef] {
        (shelves?.logos ?? []).filter { $0.kind != "platform" || listing?.enabled == true }
    }

    private func load() async {
        guard browses else { return }
        async let shelf = try? client.shelves(library: library.id)
        async let counted = try? client.browse(BrowseQuery(library: library.id), limit: 1)
        let (fresh, total) = await (shelf, counted)
        shelves = fresh ?? Shelves(categories: [], collections: [], studios: [], networks: [], platforms: [])
        if let all = total?.total { allCount = all }
        if isAdmin, let count = try? await client.matchesWaiting(library: library.id) { waiting = count }
    }

    private func loadOnce() async {
        guard browses else { return }
        async let saved = try? client.savedViews()
        async let status = try? client.listingStatus()
        let (all, listed) = await (saved, status)
        if let all { views = all.filter { $0.libraryId == library.id } }
        listing = listed
    }

    private func loadViews() async {
        if let all = try? await client.savedViews() { views = all.filter { $0.libraryId == library.id } }
    }

    /// Asks how a scan is going: every 1.5 seconds during one, every 10 otherwise. When one ends, the page asks for
    /// everything again. A failure stops asking until the page is opened again, as on the website.
    private func watchScans() async {
        var was = false
        while !Task.isCancelled {
            guard let answer = try? await client.scanState(library: library.id) else { return }
            let going = answer.scanning == true && answer.progress != nil
            scanning = going ? answer.progress : nil
            if was && !going { scans += 1 }
            was = going
            try? await Task.sleep(nanoseconds: going ? 1_500_000_000 : 10_000_000_000)
        }
    }

    private func startScan() {
        Task {
            do {
                try await client.scan(library: library.id)
                said = "Scanning \(library.name)"
                scanning = ScanState.Progress()
            } catch {
                said = model.handle(error)
            }
            announce(said)
        }
    }

    private func choose(_ sort: LibrarySort) {
        state.choose(sort, seed: Int.random(in: 1...90000))
    }

    private func open(_ route: Route) {
        model.path.append(route)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                bar
                    .padding(.horizontal, metrics.gutter)
                    // The website's page starts 8 under its bar, and the library's own bar has 12 above and below.
                    .padding(.top, LibraryStrip.height + Tokens.Space.s2 + Tokens.Space.s3)
                    .padding(.bottom, Tokens.Space.s3)
                if browses {
                    underBar
                    content
                } else {
                    LibraryContent(library: library)
                        .padding(.horizontal, metrics.gutter)
                        .padding(.top, Tokens.Space.s2)
                }
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .stripSolidity($solid)
        .overlay(alignment: .top) { LibraryStrip(current: library.id, solid: solid) }
        .pageBackground(palette)
        .task(id: "\(library.id)#\(scans)") { await load() }
        .task(id: library.id) { await loadOnce() }
        .task(id: library.id) { await watchScans() }
        .task(id: wantedLogos) {
            guard let found = try? await client.logos(wantedLogos) else { return }
            logos = Dictionary(found.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        }
        .sheet(isPresented: $filtersOpen, onDismiss: {
            if saveAfterFilters {
                saveAfterFilters = false
                saving = true
            }
        }) {
            FiltersSheet(library: library, state: $state) {
                saveAfterFilters = true
                filtersOpen = false
            }
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $toolsOpen) {
            LibrarySheet(title: library.name) { LibraryRows(rows: tools) }
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $saving) {
            SaveViewSheet(library: library, state: state) {
                said = "View saved"
                announce(said)
                Task { await loadViews() }
            }
            .environment(\.palette, palette)
        }
    }

    // MARK: The bar

    /// The website's `.lh-bar`: the name and count, with Filters and "⋯" at the end (on a line of their own below
    /// the name when there isn't room beside it), and the sorts on the next line, 8 below.
    private var bar: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Tokens.Space.s5) {
                    name.fixedSize()
                    Spacer(minLength: 0)
                    barEnd
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    name
                    barEnd.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if browses { sortRow }
        }
    }

    /// The name as the page's title, and 12 after it how many there are in 14 `textHint`.
    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            Text(library.name)
                .pageFont(.title)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if browses, let count {
                Text(LibraryWords.titles(count, type: library.type))
                    .font(.system(size: countSize))
                    .foregroundStyle(palette.textHint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder private var barEnd: some View {
        HStack(spacing: Tokens.Space.s2) {
            if browses {
                let chosen = state.chosen.count
                Button { filtersOpen = true } label: {
                    Label(chosen > 0 ? "Filters (\(chosen))" : "Filters", systemImage: "slider.horizontal.3")
                }
                .pageButton(.ghost)
                .fixedSize()
            }
            // The website always offers it on a film or TV library; anything else only when it holds something.
            if browses || !tools.isEmpty {
                Button { toolsOpen = true } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                }
                .squareButton()
                .accessibilityLabel("More for \(library.name)")
            }
        }
    }

    /// `SORT` in 11 bold `textHint`, the sorts 4 apart (scrolling sideways when they don't fit), and the button that
    /// turns the chosen one round where it has a direction.
    private var sortRow: some View {
        let current = state.shownSort(grid: grid)
        let words = HStack(spacing: Tokens.Space.s1) {
            ForEach(LibrarySort.all) { sort in
                Button(sort.label) { choose(sort) }
                    .buttonStyle(SortWordStyle(chosen: current == sort.key))
            }
        }
        .padding(2)
        return HStack(spacing: Tokens.Space.s2) {
            Text("SORT")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.77)
                .foregroundStyle(palette.textHint)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                words
                ScrollView(.horizontal, showsIndicators: false) { words }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sort")
            if state.turns, let sort = LibrarySort.all.first(where: { $0.key == state.sort }) {
                Button { state.descending.toggle() } label: {
                    Image(systemName: state.descending ? "arrow.down" : "arrow.up").font(.system(size: 16, weight: .semibold))
                }
                .squareButton()
                .accessibilityLabel(state.descending ? "\(sort.label): last to first. Switch to first to last"
                                                     : "\(sort.label): first to last. Switch to last to first")
            }
        }
    }

    /// What's under the bar: the filters that are on, as tags to take off, with Save this view; or, with none on,
    /// the saved views of this library as chips. 16 below them.
    @ViewBuilder private var underBar: some View {
        if !state.chosen.isEmpty {
            WrapRow {
                ForEach(state.chosen, id: \.key) { filter in
                    FilterTag(label: BrowseFilter.title(of: filter.key), value: shownValue(filter.key, filter.value)) {
                        state.set(filter.key, "")
                    }
                }
                Button("Save this view") { saving = true }.buttonStyle(SmallGhostStyle())
                if state.chosen.count > 1 {
                    Button("Clear all") { state = LibraryState() }.buttonStyle(SmallGhostStyle())
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, Tokens.Space.s4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filters")
        } else if !views.isEmpty {
            WrapRow {
                ForEach(views) { view in
                    Button(view.name) { state = view.state }.chip()
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, Tokens.Space.s4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Saved views")
        }
        if !said.isEmpty {
            Text(said).pageFont(.secondary).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, metrics.gutter)
                .padding(.bottom, Tokens.Space.s3)
        }
    }

    /// A service is filtered by its key, and shown by its name.
    private func shownValue(_ key: String, _ value: String) -> String {
        if key == "platform", let name = shelves?.platforms?.first(where: { $0.key == value })?.name { return name }
        return BrowseFilter.words(key, value)
    }

    // MARK: What's in it

    @ViewBuilder private var content: some View {
        if grid {
            BrowseGrid(query: state.query(library: library.id), filtered: !state.chosen.isEmpty, scanning: scanning != nil,
                       isAdmin: isAdmin, reload: scans, total: $gridCount, library: library)
                .padding(.horizontal, metrics.gutter)
            if state.filters["platform"] != nil, let listing {
                ListingNote(status: listing)
                    .padding(.horizontal, metrics.gutter)
                    .padding(.top, Tokens.Space.s3)
            }
        } else if let shelves {
            shelvesBody(shelves)
        } else {
            SkeletonGrid().padding(.horizontal, metrics.gutter)
        }
    }

    private func brandRoute(_ kind: String, _ name: String) -> Route {
        .page("/brand/\(kind)/\(WittyClient.queryValue(name))?library=\(library.id)")
    }

    /// The website's shelves, each 28 above the next: categories, collections, studios, networks, the streaming
    /// services while listings are on, then rows of titles that load as they come near.
    private func shelvesBody(_ shelves: Shelves) -> some View {
        let gap: CGFloat = 28
        let collections = shelves.collections ?? []
        let platforms = listing?.enabled == true ? (shelves.platforms ?? []) : []
        return LazyVStack(alignment: .leading, spacing: 0) {
            if !shelves.shown.isEmpty {
                PageRow(title: "Categories") {
                    ForEach(shelves.shown) { category in
                        Button { state = LibraryState(filters: ["genre": category.name]) } label: {
                            CategoryCard(name: category.name, count: category.count, art: category.art?.first, width: categoryWidth)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.bottom, gap)
            }
            if !collections.isEmpty {
                // See all is the server's Collections page, when some of these are collections rather than series.
                PageRow(title: "Collections", seeAll: collections.contains { ($0.key ?? "").isEmpty } ? .page(ServerPages.collections) : nil) {
                    ForEach(collections, id: \.self) { collection in
                        if let key = collection.key, !key.isEmpty {
                            Button { state = LibraryState(filters: ["series": collection.name]) } label: {
                                CategoryCard(name: collection.name, count: collection.count, art: collection.art?.first, width: categoryWidth)
                            }
                            .buttonStyle(PressStyle())
                        } else if let id = collection.id {
                            NavigationLink(value: Route.page("/collections/\(id)")) {
                                CategoryCard(name: collection.name, count: collection.count, art: collection.art?.first, width: categoryWidth)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                .padding(.bottom, gap)
            }
            ForEach([("Studios", "studio", shelves.studios ?? []), ("Networks", "network", shelves.networks ?? [])], id: \.0) { title, kind, brands in
                if !brands.isEmpty {
                    PageRow(title: title) {
                        ForEach(brands.prefix(40)) { brand in
                            NavigationLink(value: brandRoute(kind, brand.name)) {
                                LogoCard(name: brand.name, logo: logos[LogoLook.key(kind: kind, name: brand.name)], size: logoSize)
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("\(brand.name), \(brand.count ?? 0) \(brand.count == 1 ? "title" : "titles")")
                        }
                    }
                    .padding(.bottom, gap)
                }
            }
            if !platforms.isEmpty, let listing {
                PageRow(title: "Also listed on") {
                    ForEach(platforms) { platform in
                        Button { state = LibraryState(filters: ["platform": platform.key]) } label: {
                            LogoCard(name: platform.name, logo: logos[LogoLook.key(kind: "platform", name: platform.name)], size: logoSize)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("\(platform.name), \(platform.count ?? 0) \(platform.count == 1 ? "title" : "titles")")
                    }
                }
                ListingNote(status: listing)
                    .padding(.horizontal, metrics.gutter)
                    .padding(.top, Tokens.Space.s3)
                    .padding(.bottom, gap)
            }
            ShelfRow(title: "Recently added", query: BrowseQuery(library: library.id, sort: "added", descending: true)) {
                state = LibraryState(sort: "added", descending: true)
            }
            ShelfRow(title: "Highest rated", query: BrowseQuery(library: library.id, sort: "rating", descending: true, filters: ["minRating": "6"])) {
                state = LibraryState(sort: "rating", descending: true)
            }
            ForEach(shelves.shown.prefix(12)) { category in
                ShelfRow(title: category.name, query: BrowseQuery(library: library.id, sort: "rating", descending: true, filters: ["genre": category.name]),
                         action: LibraryWords.seeAll(category.count)) {
                    state = LibraryState(filters: ["genre": category.name])
                }
            }
            if isAdmin, shelves.shown.isEmpty { categoriesNote }
        }
    }

    /// For an administrator whose library has no categories yet: where they come from, and a way to fill them in.
    private var categoriesNote: some View {
        var words = AttributedString("Categories come from genres, which come from matching titles. ")
        var link = AttributedString("Fix matches")
        link.link = URL(string: "wittymedia-page:/fix-matches?library=\(library.id)")
        words += link + AttributedString(" to fill them in.")
        return HStack(alignment: .top, spacing: Tokens.Space.s2) {
            Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).frame(width: 16, height: 20)
            Text(words).pageFont(.body).fixedSize(horizontal: false, vertical: true)
        }
        // The website's link is in the words' own colour.
        .foregroundStyle(palette.textHint)
        .tint(palette.textHint)
        .environment(\.openURL, OpenURLAction { _ in
            open(.page("/fix-matches?library=\(library.id)"))
            return .handled
        })
        .padding(.horizontal, metrics.gutter)
    }

    // MARK: "⋯"

    /// The website's library tools on a phone, as a sheet of rows (LibraryHeader.tsx): the whole library or back to
    /// the shelves, then an administrator's Fix matches (only with titles waiting), Select or Categories, and Scan
    /// with how far it has got. Select and Categories are the server's own page's.
    private var tools: [SheetRowItem] {
        var rows: [SheetRowItem] = []
        if browses {
            if grid && !bare {
                rows.append(SheetRowItem(id: "shelves", title: "Back to shelves") { state = LibraryState() })
            }
            if !grid {
                rows.append(SheetRowItem(id: "all", title: allName) { state = LibraryState(all: true) })
            }
            if isAdmin && waiting > 0 {
                rows.append(SheetRowItem(id: "fix", title: "Fix matches", badge: waiting) { open(.page("/fix-matches?library=\(library.id)")) })
            }
            if isAdmin && grid {
                let address = state.address
                rows.append(SheetRowItem(id: "select", icon: "checkmark", title: "Select") {
                    open(.page(ServerPages.path(library) + (address.isEmpty ? "" : "?" + address)))
                })
            }
            if isAdmin && !grid {
                rows.append(SheetRowItem(id: "categories", icon: "pencil", title: "Categories") { open(.page(ServerPages.path(library))) })
            }
        }
        if let scanning {
            rows.append(SheetRowItem(id: "scan", icon: "arrow.triangle.2.circlepath", title: ScanState.words(scanning), enabled: false) {})
        } else if isAdmin {
            rows.append(SheetRowItem(id: "scan", icon: "arrow.triangle.2.circlepath", title: "Scan") { startScan() })
        }
        return rows
    }
}

// MARK: - A row of a library's

/// A titled row that asks for its titles when it comes near the screen, as the website's `LazyShelf`: room for it
/// while it waits, and nothing at all when it has none.
private struct ShelfRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let title: String
    let query: BrowseQuery
    var action = "See all"
    let seeAll: () -> Void
    @State private var rows: [BrowseRow]?
    @FocusState private var focused: String?

    var body: some View {
        Group {
            if let rows {
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        SectionHead(title: title, action: action, tap: seeAll).padding(.horizontal, metrics.gutter)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: Tokens.Space.s4) {
                                ForEach(rows) { row in
                                    if let item = row.item { ItemTile(item: item, focus: $focused) }
                                    else if let show = row.show { ShowTile(show: show, focus: $focused) }
                                }
                            }
                            .rowSnapTargets(side: metrics.gutter)
                            .padding(.top, Tokens.Space.s3)
                            .padding(.bottom, Tokens.Space.s4)
                        }
                        .rowSnapping(side: metrics.gutter)
                    }
                    .padding(.bottom, 28)
                }
            } else {
                Color.clear.frame(height: 240)
            }
        }
        .task(id: query) {
            do {
                rows = try await client.browse(query, limit: 20).results ?? []
            } catch {
                _ = model.handle(error)
                if rows == nil { rows = [] }
            }
        }
    }
}

// MARK: - The grid

/// Every title the query finds, three across a phone, a page at a time as it's scrolled.
private struct BrowseGrid: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let query: BrowseQuery
    let filtered: Bool
    let scanning: Bool
    let isAdmin: Bool
    /// Changes when a scan finishes, so what's shown is asked for again.
    let reload: Int
    @Binding var total: Int?
    let library: Library
    @State private var rows: [BrowseRow]?
    @State private var asked: BrowseQuery?
    @State private var all = 0
    @State private var error = ""
    @State private var loading = false
    @FocusState private var focused: String?
    private let pageSize = 120

    private struct Ask: Hashable {
        let query: BrowseQuery
        let reload: Int
    }

    private func first() async {
        // Another question starts empty; the same one asked again after a scan keeps what's shown until the answer.
        if asked != query {
            rows = nil
            total = nil
            asked = query
        }
        error = ""
        do {
            let page = try await client.browse(query, limit: pageSize)
            rows = page.results ?? []
            all = page.total ?? rows?.count ?? 0
            total = all
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    private func more() async {
        guard let have = rows, have.count < all, !loading else { return }
        loading = true
        defer { loading = false }
        if let page = try? await client.browse(query, offset: have.count, limit: pageSize) {
            let fresh = page.results ?? []
            // A server that sends nothing new can't keep this asking for ever.
            if fresh.isEmpty { all = have.count } else { rows = have + fresh.filter { row in !have.contains { $0.id == row.id } } }
        }
    }

    var body: some View {
        Group {
            if let rows {
                if rows.isEmpty {
                    empty
                } else {
                    LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
                        ForEach(rows) { row in
                            Group {
                                if let item = row.item { ItemTile(item: item, inRow: false, focus: $focused) }
                                else if let show = row.show { ShowTile(show: show, inRow: false, focus: $focused) }
                            }
                            .task { if row.id == rows.last?.id { await more() } }
                        }
                    }
                    if loading { SkeletonGrid(count: 3).padding(.top, Tokens.Space.s6) }
                }
            } else if !error.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    ProblemLine(error)
                    Button("Try again") { Task { await first() } }.pageButton(.primary)
                }
            } else {
                SkeletonGrid()
            }
        }
        .task(id: Ask(query: query, reload: reload)) { await first() }
    }

    /// The website's empty grid: still scanning, nothing matching, or nothing yet, when an administrator can check
    /// where the library looks. The button is 16 under the words, inside the empty state's 64.
    private var empty: some View {
        let detail = scanning ? "Titles appear as they are found."
            : filtered ? "Try taking away a filter."
            : library.isShows ? "Organize episodes as Show/Season 1/Show - S01E01 - Title.mkv and scan again."
            : "No videos were found in this library’s folders."
        return VStack(spacing: 0) {
            EmptyState(icon: "film", title: scanning ? "Scanning…" : filtered ? "Nothing matches" : "Nothing here yet", detail: detail)
            if !scanning && !filtered && isAdmin {
                NavigationLink(value: Route.page("/settings/libraries")) { Text("Check its folders") }
                    .pageButton(.secondary)
                    .padding(.top, Tokens.Space.s4 - 64)
                    .padding(.bottom, 64)
            }
        }
    }
}

// MARK: - Filters

/// The website's Filters sheet: words in the title, then each kind of choice as chips with how many each has, in
/// its order. Choosing applies at once. At its foot, Clear all, Save this view and Done.
private struct FiltersSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let library: Library
    @Binding var state: LibraryState
    let save: () -> Void
    @State private var facets: Facets?
    @State private var error = ""
    @State private var words = ""
    @State private var more: Set<String> = []

    private func toggle(_ key: String, _ value: String) {
        state.set(key, state.filters[key]?.lowercased() == value.lowercased() ? "" : value)
    }

    private func find() {
        state.set("search", words.trimmingCharacters(in: .whitespaces))
    }

    /// A group's name in 13 semibold `textSecondary`, 8 over its chips, which wrap 8 apart.
    private func group<Choices: View>(_ title: String, @ViewBuilder choices: () -> Choices) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(title).pageFont(.secondary).fontWeight(.semibold).foregroundStyle(palette.textSecondary).accessibilityAddTraits(.isHeader)
            WrapRow { choices() }
        }
        .padding(.top, Tokens.Space.s5)
    }

    @ViewBuilder private func section(_ section: FilterSection, in facets: Facets) -> some View {
        switch section {
        case .facets(let filter):
            let list = filter.choices(in: facets)
            if !list.isEmpty {
                let shown = more.contains(filter.key) ? list : Array(list.prefix(filter.limit))
                group(filter.title) {
                    ForEach(shown) { facet in
                        Button { toggle(filter.key, facet.value) } label: {
                            HStack(spacing: Tokens.Space.s2) {
                                Text(facet.label ?? BrowseFilter.words(filter.key, facet.value))
                                if let count = facet.count {
                                    Text("\(count)").font(.system(size: 12, weight: .medium)).opacity(0.7)
                                        .accessibilityLabel(", \(count) \(count == 1 ? "title" : "titles")")
                                }
                            }
                        }
                        .chip(chosen: state.filters[filter.key]?.lowercased() == facet.value.lowercased())
                    }
                    if list.count > shown.count {
                        Button("\(list.count - filter.limit) more") { more.insert(filter.key) }.chip()
                    }
                }
            }
        case .score:
            group(section.title) {
                ForEach(BrowseFilter.scores, id: \.self) { score in
                    Button(BrowseFilter.words("minRating", score)) { state.set("minRating", state.filters["minRating"] == score ? "" : score) }
                        .chip(chosen: state.filters["minRating"] == score)
                }
            }
        case .watched:
            group(section.title) {
                ForEach(BrowseFilter.watched, id: \.0) { choice in
                    Button(choice.1) { state.set("watched", state.filters["watched"] == choice.0 ? "" : choice.0) }
                        .chip(chosen: state.filters["watched"] == choice.0)
                }
            }
        }
    }

    var body: some View {
        LibrarySheet(title: "Filters") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Tokens.Space.s2) {
                    WebField(prompt: "Words in the title", text: $words, submit: find)
                    Button("Find", action: find).pageButton(.secondary)
                }
                if !error.isEmpty { ProblemLine(error).padding(.top, Tokens.Space.s3) }
                if let facets {
                    ForEach(FilterSection.all) { part in section(part, in: facets) }
                } else if error.isEmpty {
                    ProgressView().tint(palette.accent).frame(maxWidth: .infinity).padding(64)
                }
            }
            .padding(.horizontal, Tokens.Space.s1)
            .padding(.bottom, Tokens.Space.s2)
        } footer: {
            WrapRow(trailing: true) {
                Button("Clear all") { state = LibraryState() }.pageButton(.ghost)
                Button("Save this view", action: save).pageButton(.ghost).disabled(state.chosen.isEmpty)
                Button("Done") { dismiss() }.pageButton(.primary)
            }
        }
        .task {
            words = state.filters["search"] ?? ""
            do {
                facets = try await client.facets(library: library.id)
            } catch {
                let said = model.handle(error)
                if !said.isEmpty { self.error = said }
            }
        }
    }
}

/// The website's Save this view dialog: a name (what's chosen, in words, to start with) and whether it goes on Home.
private struct SaveViewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let library: Library
    let state: LibraryState
    let saved: () -> Void
    @State private var name: String
    @State private var pinned = true
    @State private var error = ""
    @State private var busy = false
    @FocusState private var typing: Bool

    init(library: Library, state: LibraryState, saved: @escaping () -> Void) {
        self.library = library
        self.state = state
        self.saved = saved
        _name = State(initialValue: state.suggestedName)
    }

    private var ready: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !busy }

    private func save() {
        guard ready else { return }
        busy = true
        error = ""
        Task {
            defer { busy = false }
            do {
                try await client.saveView(library: library.id, name: name, query: state.savedQuery, pinned: pinned)
                saved()
                dismiss()
            } catch {
                let words = model.handle(error)
                if !words.isEmpty { self.error = words }
            }
        }
    }

    var body: some View {
        LibrarySheet(title: "Save this view", headGap: Tokens.Space.s2, footerGap: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("It's yours alone, and it keeps itself up to date as your library changes.")
                    .pageFont(.button)
                    .fontWeight(.regular)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text("Name").pageFont(.secondary).fontWeight(.medium).foregroundStyle(palette.textSecondary)
                    WebField(prompt: "", text: $name, submit: save)
                        .focused($typing)
                        .accessibilityLabel("Name")
                        .onChange(of: name) { if $0.count > 60 { name = String($0.prefix(60)) } }
                }
                CheckRow(title: "Pin it to Home", on: $pinned)
                if !error.isEmpty { ProblemLine(error) }
            }
        } footer: {
            WrapRow(trailing: true) {
                Button("Cancel") { dismiss() }.pageButton(.ghost)
                Button("Save", action: save).pageButton(.primary).disabled(!ready)
            }
        }
        .onAppear { typing = true }
    }
}

// MARK: - Sorting

// The page's smaller parts, each measured from the website at phone size: web/src/components/libraryheader.css,
// web/src/pages/library/library.css, web/src/ui/ui.css and styles.css. Kept to this file, so they're this page's.

/// One sort, as a plain word (`.lh-sort-btn`): 44 high, 12 inside, 14 semibold `textSecondary` with no outline; the
/// chosen one inverted.
private struct SortWordStyle: ButtonStyle {
    var chosen = false

    func makeBody(configuration: Configuration) -> some View {
        SortWordBody(label: configuration.label, pressed: configuration.isPressed, chosen: chosen)
    }
}

private struct SortWordBody<Label: View>: View {
    @Environment(\.palette) private var palette
    let label: Label
    let pressed: Bool
    let chosen: Bool

    var body: some View {
        label
            .pageFont(.button)
            .lineLimit(1)
            .foregroundStyle(chosen ? palette.background : pressed ? palette.text : palette.textSecondary)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 44)
            .background(Capsule().fill(chosen ? palette.text : pressed ? palette.text.opacity(0.07) : Color.clear))
            .contentShape(Capsule())
            .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

// MARK: - Filters on show

/// A filter that's on (`.chip.tag`): 28 high, `card`, its name in `textHint` and its value in `text`, 13 medium,
/// with a 24 round × that takes it off.
private struct FilterTag: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s1) {
            (Text("\(label):").foregroundColor(palette.textHint) + Text("\u{00A0}\(value)").foregroundColor(palette.text))
                .pageFont(.action)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take off \(label) \(value)")
        }
        .padding(.leading, Tokens.Space.s3)
        .padding(.trailing, Tokens.Space.s1)
        .frame(minHeight: 28)
        .background(Capsule().fill(palette.card))
    }
}

/// The website's small Ghost button (`.btn.sm.ghost`), 44 high on a touch screen: 12 inside, 13 semibold.
private struct SmallGhostStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SmallGhostBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct SmallGhostBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var enabled
    let label: Label
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        label
            .pageFont(.action)
            .fontWeight(.semibold)
            .lineLimit(1)
            .foregroundStyle(palette.text)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 44)
            .background(shape.fill(pressed ? palette.text.opacity(0.07) : Color.clear))
            .overlay(shape.strokeBorder(palette.text.opacity(0.2), lineWidth: 1))
            .contentShape(shape)
            .opacity(enabled ? 1 : 0.55)
    }
}

/// Things in rows that wrap, as the website's flex rows do: each row's things centred on each other, and the rows
/// at the start, or at the end for a sheet's buttons.
private struct WrapRow: Layout {
    var spacing: CGFloat = Tokens.Space.s2
    var trailing = false

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var used: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            if size.width > width { size = view.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if used > 0, used + spacing + size.width > width {
                rows.append([])
                used = 0
            }
            used += (used > 0 ? spacing : 0) + size.width
            rows[rows.count - 1].append((index, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (number, row) in rows(subviews, width: width).enumerated() where !row.isEmpty {
            let rowWidth = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(row.count - 1)
            height += (row.map(\.1.height).max() ?? 0) + (number > 0 ? spacing : 0)
            widest = max(widest, rowWidth)
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) where !row.isEmpty {
            let used = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(row.count - 1)
            let height = row.map(\.1.height).max() ?? 0
            var x = trailing ? bounds.maxX - used : bounds.minX
            for (index, size) in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing
        }
    }
}

// MARK: - Sheets

/// The website's sheet on a phone (`Sheet` and `Dialog` in web/src/ui/Overlay.tsx): up from the bottom in `panel`,
/// as tall as what's in it up to 92% of the screen, 20 above and below and 16 at the sides. Its title in 20
/// semibold with a Ghost × beside it, 16 above what's in it; its buttons, if any, at the foot, 24 below it.
private struct LibrarySheet<Content: View, Footer: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// The space under the title: 16, or 8 over a dialog's line about itself.
    var headGap: CGFloat = Tokens.Space.s4
    /// The space between what's in it and its buttons: 24 for a sheet, 16 for a small dialog.
    var footerGap: CGFloat = Tokens.Space.s6
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @State private var headHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    private var hasFooter: Bool { Footer.self != EmptyView.self }

    private var height: CGFloat {
        let natural = Tokens.Space.s5 + headHeight + headGap + contentHeight + (hasFooter ? footerGap + footerHeight : 0) + Tokens.Space.s5
        return min(natural, screenSize.height * 0.92)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Tokens.Space.s3) {
                Text(title)
                    .pageFont(.section)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                }
                .squareButton()
                .accessibilityLabel("Close")
            }
            .measured($headHeight)
            .padding(.bottom, headGap)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .measured($contentHeight)
            }
            if hasFooter {
                footer
                    .measured($footerHeight)
                    .padding(.top, footerGap)
            }
        }
        .padding(.horizontal, Tokens.Space.s4)
        .padding(.vertical, Tokens.Space.s5)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.panel.ignoresSafeArea())
        .presentationDetents(headHeight > 0 ? [.height(height)] : [.medium])
        .sheetCorners(Tokens.Radius.xl)
    }
}

extension LibrarySheet where Footer == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, footer: { EmptyView() })
    }
}

private extension View {
    /// Keeps the height this is drawn at.
    func measured(_ height: Binding<CGFloat>) -> some View {
        background(GeometryReader { geo in
            Color.clear
                .onAppear { height.wrappedValue = geo.size.height }
                .onChange(of: geo.size.height) { height.wrappedValue = $0 }
        })
    }

    /// The website's sheet has the extra-large radius at its top; older systems keep their own.
    @ViewBuilder func sheetCorners(_ radius: CGFloat) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) { self.presentationCornerRadius(radius) } else { self }
        #else
        self
        #endif
    }
}

/// One row of a sheet of rows (`.ui-rows`): 52 high, a 20 icon in `textSecondary` 16 in, the words in 15 medium
/// 12 after it (or 48 in without one), a badge at the end, and a hairline above it from the words on.
private struct SheetRowItem: Identifiable {
    let id: String
    var icon: String?
    let title: String
    var badge = 0
    var enabled = true
    let run: () -> Void
}

/// A card of rows on `card` with the large radius. Choosing one closes the sheet, then does what it says.
private struct LibraryRows: View {
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    let rows: [SheetRowItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { place, row in
                Button {
                    dismiss()
                    row.run()
                } label: {
                    HStack(spacing: Tokens.Space.s3) {
                        if let icon = row.icon {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                        }
                        Text(row.title).pageFont(.label).foregroundStyle(palette.text).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if row.badge > 0 {
                            // `.lib-badge`: 20 high, the text colour, its number in 11 bold.
                            Text("\(row.badge)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.background)
                                .padding(.horizontal, Tokens.Space.s1)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Capsule().fill(palette.text))
                        }
                    }
                    .padding(.leading, row.icon == nil ? Tokens.Space.s4 + 20 + Tokens.Space.s3 : Tokens.Space.s4)
                    .padding(.trailing, Tokens.Space.s4)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SheetRowStyle())
                .disabled(!row.enabled)
                .overlay(alignment: .top) {
                    if place > 0 {
                        Rectangle()
                            .fill(palette.border)
                            .frame(height: 1 / max(displayScale, 1))
                            .padding(.leading, Tokens.Space.s4 + 20 + Tokens.Space.s3)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityValue(row.badge > 0 ? "\(row.badge)" : "")
            }
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
    }
}

/// Pressed, a row takes the text colour at 12%; one that can't be chosen is at 45%.
private struct SheetRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SheetRowBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct SheetRowBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var enabled
    let label: Label
    let pressed: Bool

    var body: some View {
        label
            .background(pressed ? palette.text.opacity(0.12) : Color.clear)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// The website's checkbox, 22 square: Save this view's "Pin it to Home".
private struct CheckRow: View {
    @Environment(\.palette) private var palette
    let title: String
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            HStack(spacing: Tokens.Space.s2) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? palette.accent : palette.textSecondary)
                    .frame(width: 22, height: 22)
                Text(title).pageFont(.secondary).fontWeight(.medium).foregroundStyle(palette.textSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The website's text box (`.input`): 44 high, `card` with the control line, the theme's radius, 14.
private struct WebField: View {
    @Environment(\.palette) private var palette
    let prompt: String
    @Binding var text: String
    var submit: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        TextField("", text: $text, prompt: Text(prompt).foregroundColor(palette.textHint))
            .pageFont(.button)
            .fontWeight(.regular)
            .foregroundStyle(palette.text)
            .onSubmit(submit)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(height: 44)
            .background(shape.fill(palette.card))
            .overlay(shape.strokeBorder(palette.control, lineWidth: 1))
            .accessibilityLabel(prompt)
    }
}

// MARK: - Logos

/// A studio, network or streaming service (`.lib-logo`): 180 by 96 on a phone, on `card` with the theme's radius,
/// 16 by 20 inside: its logo in the middle, or its name in 17 semibold when the server has no logo for it.
private struct LogoCard: View {
    @Environment(\.palette) private var palette
    let name: String
    let logo: LogoInfo?
    var size = CGSize(width: 180, height: 96)

    var body: some View {
        ZStack {
            if let logo, logo.hasPicture {
                LogoPicture(logo: logo, name: name, size: CGSize(width: size.width - 2 * Tokens.Space.s5, height: size.height - 2 * Tokens.Space.s4))
            } else {
                LogoName(name: name)
            }
        }
        .padding(.horizontal, Tokens.Space.s5)
        .padding(.vertical, Tokens.Space.s4)
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
    }
}

private struct LogoName: View {
    @Environment(\.palette) private var palette
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(palette.text)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
    }
}

/// The logo that reads on this theme; its name if the picture won't come.
private struct LogoPicture: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    let logo: LogoInfo
    let name: String
    let size: CGSize
    @State private var image: CGImage?
    @State private var failed = false

    private var variant: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        UIColor(palette.background).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return LogoLook.variant(opaque: logo.opaque == true, background: Double(red), Double(green), Double(blue))
    }

    var body: some View {
        Group {
            if failed {
                LogoName(name: name)
            } else if let image {
                if logo.opaque == true {
                    // A picture with its own background can't change colour, so it gets a white plate.
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .padding(Tokens.Space.s1)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(Color.white))
                } else {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: size.width, maxHeight: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .task(id: "\(logo.id ?? 0)/\(logo.version ?? 0)/\(variant)") { await load() }
    }

    private func load() async {
        guard let url = client.logoURL(logo, variant: variant) else { failed = true; return }
        let pixels = Int(max(size.width, size.height) * displayScale)
        let key = "\(url.absoluteString)#\(pixels)" as NSString
        if let cached = ArtCache.shared.object(forKey: key) {
            image = cached
            return
        }
        guard let data = try? await client.imageData(url) else {
            if !Task.isCancelled { failed = true }
            return
        }
        let decoded = await Task.detached(priority: .utility) { decodeArt(data, maxPixels: pixels) }.value
        guard !Task.isCancelled else { return }
        guard let decoded else { failed = true; return }
        ArtCache.shared.setObject(decoded, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        image = decoded
    }
}

// MARK: - Streaming listings

/// What streaming listings are, every time they're shown (`ListingNote`): a warning notice, 12 by 16 inside,
/// `warn` at 13% with a line of it at 50%, in 14.
private struct ListingNote: View {
    @Environment(\.palette) private var palette
    let status: ListingStatus

    private var words: String {
        var asOf = ""
        if let newest = status.newest, newest > 0 {
            asOf = ", as of " + Date(timeIntervalSince1970: TimeInterval(newest)).formatted(date: .numeric, time: .omitted)
        }
        return "This only sorts the media already on your server by which titles they currently list, for region \(status.region ?? "")\(asOf). "
            + "There's no connection with any of them, and you may have no account with them at all."
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Text("Nothing streams from these services.").fontWeight(.semibold)
            (Text(words) + Text(" ") + Text(status.attribution ?? "").foregroundColor(palette.textHint))
                .fixedSize(horizontal: false, vertical: true)
        }
        .pageFont(.button)
        .fontWeight(.regular)
        .foregroundStyle(palette.text)
        .padding(.vertical, Tokens.Space.s3)
        .padding(.horizontal, Tokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(palette.warn.opacity(0.13)))
        .overlay(shape.strokeBorder(palette.warn.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
