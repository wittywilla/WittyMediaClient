import SwiftUI
import WittyKit

// A library's page on a phone and a tablet, as the website's (web/src/pages/library/VideoLibrary.tsx): the strip,
// its name and count with Filters, the sorts, then its categories and rows; a grid once a sort or a filter is
// chosen. An administrator's tools are behind "⋯". docs/APP-DESIGN.md, Library pages.

struct LibraryPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    @State private var shelves: Shelves?
    @State private var allCount: Int?
    @State private var gridCount: Int?
    @State private var query: BrowseQuery
    /// A sort chosen: the grid. Nothing chosen: the shelves, as the website starts.
    @State private var sorted = false
    @State private var solid = 0.0
    @State private var filtersOpen = false
    @State private var toolsOpen = false
    @State private var said = ""

    init(library: Library) {
        self.library = library
        _query = State(initialValue: BrowseQuery(library: library.id))
    }

    /// Films, shows, discs and videos have the website's shelves; anything else here is a grid of its own.
    private var browses: Bool { ["movies", "shows", "anime", "videos", "discs"].contains(library.type) }
    private var isShows: Bool { library.isShows }
    /// A library too small or too bare for shelves is a grid from the start.
    private var bare: Bool { shelves.map { $0.shown.isEmpty } ?? false }
    private var grid: Bool { sorted || !query.chosen.isEmpty || bare }
    private var isAdmin: Bool { model.user?.isAdmin == true }

    private var allName: String {
        switch library.type {
        case "shows", "anime": return "All shows"
        case "discs": return "All discs"
        case "videos": return "All videos"
        default: return "All films"
        }
    }

    private func load() async {
        guard browses else { return }
        async let shelf = try? client.shelves(library: library.id)
        async let count = try? client.browse(BrowseQuery(library: library.id), limit: 1)
        let (fresh, counted) = await (shelf, count)
        shelves = fresh ?? Shelves(categories: [], collections: [])
        if let total = counted?.total { allCount = total }
    }

    private func choose(_ sort: LibrarySort) {
        query.sort = sort.key
        query.descending = sort.descending
        query.seed = sort.key == "shuffle" ? Int.random(in: 1...90000) : nil
        sorted = true
    }

    private func showGenre(_ name: String) {
        query = BrowseQuery(library: library.id, filters: ["genre": name])
        sorted = true
    }

    private func backToShelves() {
        query = BrowseQuery(library: library.id)
        sorted = false
    }

    private func open(_ route: Route) {
        toolsOpen = false
        model.path.append(route)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                header
                    .padding(.horizontal, metrics.gutter)
                    .padding(.top, 44 + Tokens.Space.s3)
                if !said.isEmpty {
                    Text(said).pageFont(.secondary).foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, metrics.gutter).padding(.top, Tokens.Space.s2)
                }
                if browses {
                    sortRow.padding(.top, Tokens.Space.s2)
                    if !query.chosen.isEmpty { chosenFilters.padding(.top, Tokens.Space.s1) }
                    content.padding(.top, Tokens.Space.s5)
                } else {
                    LibraryContent(library: library)
                        .padding(.horizontal, metrics.gutter)
                        .padding(.top, Tokens.Space.s5)
                }
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .stripSolidity($solid)
        .overlay(alignment: .top) { LibraryStrip(current: library.id, solid: solid) }
        .pageBackground(palette)
        .task(id: library.id) { await load() }
        .sheet(isPresented: $filtersOpen) { FiltersSheet(library: library, query: $query) }
        .sheet(isPresented: $toolsOpen) { tools }
    }

    // MARK: The top

    /// The name in Title with its count in 15 `textHint` beside it, and on the right a Ghost Filters and "⋯".
    private var header: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
                Text(library.name)
                    .pageFont(.title)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                if let count = grid && !query.chosen.isEmpty ? gridCount : allCount {
                    Text(LibraryWords.titles(count, type: library.type))
                        .pageFont(.body)
                        .foregroundStyle(palette.textHint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Spacer(minLength: Tokens.Space.s2)
            if browses {
                let chosen = query.chosen.count
                Button { filtersOpen = true } label: {
                    Label(chosen > 0 ? "Filters (\(chosen))" : "Filters", systemImage: "slider.horizontal.3")
                }
                .pageButton(.ghost)
                .fixedSize()
            }
            Button { toolsOpen = true } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
            }
            .squareButton()
            .accessibilityLabel("More for \(library.name)")
        }
    }

    /// `SORT` as a Caption, then the sorts in one sideways row.
    private var sortRow: some View {
        HStack(spacing: Tokens.Space.s2) {
            CaptionLabel("Sort").padding(.leading, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s1) {
                    ForEach(LibrarySort.all) { sort in
                        Button(sort.label) { choose(sort) }
                            .chip(chosen: grid && query.sort == sort.key)
                    }
                }
                .padding(.trailing, metrics.gutter)
            }
        }
    }

    /// Each filter that's on, as a chip that takes it off.
    private var chosenFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(query.chosen, id: \.key) { filter in
                    Button {
                        query.filters[filter.key] = nil
                    } label: {
                        HStack(spacing: Tokens.Space.s1) {
                            Text("\(BrowseFilter.title(of: filter.key)): \(BrowseFilter.words(filter.key, filter.value))")
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .chip(chosen: true)
                    .accessibilityLabel("Take off \(BrowseFilter.title(of: filter.key)) \(BrowseFilter.words(filter.key, filter.value))")
                }
                if query.chosen.count > 1 {
                    Button("Clear all") { query.filters = [:] }.chip()
                }
            }
            .padding(.horizontal, metrics.gutter)
        }
    }

    // MARK: What's in it

    @ViewBuilder private var content: some View {
        if grid {
            BrowseGrid(query: query, filtered: !query.chosen.isEmpty, total: $gridCount, library: library)
                .padding(.horizontal, metrics.gutter)
        } else if let shelves {
            shelvesBody(shelves)
        } else {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: Tokens.Space.s4) {
                    ForEach(0..<2, id: \.self) { _ in SkeletonShape(radius: Tokens.Radius.lg).frame(width: 220, height: 124) }
                }
                .padding(.leading, metrics.gutter)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                SkeletonRow()
            }
        }
    }

    private func shelvesBody(_ shelves: Shelves) -> some View {
        let cardWidth: CGFloat = metrics.cardWidth <= 104 ? 220 : 280
        return LazyVStack(alignment: .leading, spacing: 28) {
            if !shelves.shown.isEmpty {
                PageRow(title: "Categories") {
                    ForEach(shelves.shown) { category in
                        Button { showGenre(category.name) } label: {
                            CategoryCard(name: category.name, count: category.count, art: category.art?.first, width: cardWidth)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            let collections = shelves.collections ?? []
            if !collections.isEmpty {
                PageRow(title: "Collections") {
                    ForEach(collections, id: \.self) { collection in
                        if let key = collection.key, !key.isEmpty {
                            Button {
                                query = BrowseQuery(library: library.id, filters: ["series": collection.name])
                                sorted = true
                            } label: {
                                CategoryCard(name: collection.name, count: collection.count, art: collection.art?.first, width: cardWidth)
                            }
                            .buttonStyle(PressStyle())
                        } else if let id = collection.id {
                            NavigationLink(value: Route.page("/collections/\(id)")) {
                                CategoryCard(name: collection.name, count: collection.count, art: collection.art?.first, width: cardWidth)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
            ShelfRow(title: "Recently added", query: BrowseQuery(library: library.id, sort: "added", descending: true)) {
                query = BrowseQuery(library: library.id, sort: "added", descending: true)
                sorted = true
            }
            ShelfRow(title: "Highest rated", query: BrowseQuery(library: library.id, sort: "rating", descending: true, filters: ["minRating": "6"])) {
                query = BrowseQuery(library: library.id, sort: "rating", descending: true)
                sorted = true
            }
            ForEach(shelves.shown.prefix(12)) { category in
                ShelfRow(title: category.name, query: BrowseQuery(library: library.id, sort: "rating", descending: true, filters: ["genre": category.name])) {
                    showGenre(category.name)
                }
            }
            if isAdmin, shelves.shown.isEmpty {
                Text("Categories come from genres, which come from matching titles. Fix matches to fill them in.")
                    .pageFont(.secondary).foregroundStyle(palette.textHint).padding(.horizontal, metrics.gutter)
            }
        }
    }

    // MARK: "⋯"

    private func toolRow(_ title: String, icon: String, tint: String = "#5d6474", detail: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RowLabel(icon: icon, tint: tint, title: title, detail: detail)
        }
        .rowStyle()
    }

    /// A sheet of rows: the whole library, and an administrator's tools, which take two rows of the website today.
    private var tools: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                    ListGroup(title: library.name) {
                        if grid, !bare {
                            toolRow("Back to shelves", icon: "rectangle.grid.1x2", tint: "#0a6fb8") { toolsOpen = false; backToShelves() }
                        } else if !grid, browses {
                            toolRow(allName, icon: "square.grid.3x3", tint: "#0a6fb8") {
                                toolsOpen = false
                                query = BrowseQuery(library: library.id)
                                sorted = true
                            }
                        }
                        toolRow("The server's page", icon: "globe", tint: "#0e7c6f", detail: "Saved views, choosing titles to edit together, and more") {
                            open(.page(ServerPages.path(library)))
                        }
                    }
                    if isAdmin {
                        ListGroup(title: "Manage") {
                            toolRow("Fix matches", icon: "wand.and.stars") { open(.page("/fix-matches?library=\(library.id)")) }
                            toolRow("Categories", icon: "square.stack.3d.up", detail: "Name, order and hide this library's categories") {
                                open(.page(ServerPages.path(library)))
                            }
                            toolRow("Scan", icon: "arrow.clockwise", detail: "Look through this library's folders again") {
                                toolsOpen = false
                                Task {
                                    do {
                                        try await client.scan(library: library.id)
                                        said = "Scanning \(library.name)…"
                                    } catch {
                                        said = model.handle(error)
                                    }
                                    announce(said)
                                }
                            }
                        }
                    }
                }
                .padding(Tokens.Space.s4)
            }
            .pageBackground(palette)
            .navigationTitle(library.name)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { toolsOpen = false }.tint(palette.accentText) }
            }
        }
        .presentationDetents([.medium, .large])
        .environment(\.palette, palette)
    }
}

// MARK: - A row of a library's

/// A titled row that asks for its titles when it comes near the screen, and isn't there at all when it has none.
private struct ShelfRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let title: String
    let query: BrowseQuery
    let seeAll: () -> Void
    @State private var rows: [BrowseRow]?
    @FocusState private var focused: String?

    var body: some View {
        Group {
            if let rows {
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        SectionHead(title: title, tap: seeAll).padding(.horizontal, metrics.gutter)
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
                }
            } else {
                SkeletonRow()
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
    @Binding var total: Int?
    let library: Library
    @State private var rows: [BrowseRow]?
    @State private var all = 0
    @State private var error = ""
    @State private var loading = false
    @FocusState private var focused: String?
    private let pageSize = 120

    private func first() async {
        rows = nil
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
                    EmptyState(icon: "film", title: filtered ? "Nothing matches" : "Nothing here yet",
                               detail: filtered ? "Try taking away a filter."
                                   : (library.isShows ? "Organize episodes as Show/Season 1/Show - S01E01 - Title.mkv and scan again."
                                                      : "No videos were found in this library’s folders."))
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
        .task(id: query) { await first() }
    }
}

// MARK: - Filters

/// The website's Filters as a sheet: words in the title, then each kind of choice as chips with how many each has.
/// Choosing applies at once; Done closes it.
private struct FiltersSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let library: Library
    @Binding var query: BrowseQuery
    @State private var facets: Facets?
    @State private var error = ""
    @State private var words = ""
    @State private var more: Set<String> = []

    private func set(_ key: String, _ value: String) {
        query.filters[key] = query.filters[key]?.lowercased() == value.lowercased() ? nil : value
    }

    private func group<Choices: View>(_ title: String, @ViewBuilder choices: () -> Choices) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text(title).pageFont(.secondary).fontWeight(.semibold).foregroundStyle(palette.textSecondary).accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: Tokens.Space.s1, rowSpacing: 0) { choices() }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                    HStack(spacing: Tokens.Space.s2) {
                        TextField("", text: $words, prompt: Text("Words in the title").foregroundColor(palette.textHint))
                            .pageFont(.body)
                            .foregroundStyle(palette.text)
                            .submitLabel(.search)
                            .onSubmit { query.filters["search"] = words.trimmingCharacters(in: .whitespaces).isEmpty ? nil : words.trimmingCharacters(in: .whitespaces) }
                            .padding(.horizontal, Tokens.Space.s3)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
                            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(palette.control, lineWidth: 1))
                        Button("Find") {
                            let trimmed = words.trimmingCharacters(in: .whitespaces)
                            query.filters["search"] = trimmed.isEmpty ? nil : trimmed
                        }
                        .pageButton(.secondary)
                    }
                    if !error.isEmpty { ProblemLine(error) }
                    if let facets {
                        ForEach(BrowseFilter.groups) { filter in
                            let list = facets[filter.facets]
                            if !list.isEmpty {
                                let shown = more.contains(filter.key) ? list : Array(list.prefix(filter.limit))
                                group(filter.title) {
                                    ForEach(shown) { facet in
                                        let on = query.filters[filter.key]?.lowercased() == facet.value.lowercased()
                                        Button { set(filter.key, facet.value) } label: {
                                            HStack(spacing: 6) {
                                                Text(facet.label ?? BrowseFilter.words(filter.key, facet.value))
                                                if let count = facet.count { Text("\(count)").opacity(0.7) }
                                            }
                                        }
                                        .chip(chosen: on)
                                    }
                                    if list.count > shown.count {
                                        Button("\(list.count - shown.count) more") { more.insert(filter.key) }.chip()
                                    }
                                }
                            }
                        }
                        group("Score") {
                            ForEach(BrowseFilter.scores, id: \.self) { score in
                                Button(BrowseFilter.words("minRating", score)) { set("minRating", score) }
                                    .chip(chosen: query.filters["minRating"] == score)
                            }
                        }
                        group("Watched") {
                            ForEach(BrowseFilter.watched, id: \.0) { choice in
                                Button(choice.1) { set("watched", choice.0) }.chip(chosen: query.filters["watched"] == choice.0)
                            }
                        }
                    } else if error.isEmpty {
                        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            ForEach(0..<3, id: \.self) { _ in SkeletonShape(radius: Tokens.Radius.sm).frame(height: 32) }
                        }
                    }
                }
                .padding(Tokens.Space.s4)
            }
            .pageBackground(palette)
            .navigationTitle("Filters")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear all") { query.filters = [:]; words = "" }.tint(palette.accentText).disabled(query.chosen.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(palette.accentText) }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            words = query.filters["search"] ?? ""
            do {
                facets = try await client.facets(library: library.id)
            } catch {
                let said = model.handle(error)
                if !said.isEmpty { self.error = said }
            }
        }
    }
}
