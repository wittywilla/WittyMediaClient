import SwiftUI
import WittyKit

// An item and a show on a phone and a tablet, as docs/APP-DESIGN.md's "An item" has them: Back over the
// backdrop, which fades into the page with no line under it; the poster overlapping it at the left; the
// library's name, the title, the tagline and the facts; then one row of actions: Play, Save and "⋯".

/// The picture across the top, `top` plus 220 high, fading into `background` with no hard line.
private struct DetailBackdrop: View {
    @Environment(\.palette) private var palette
    let url: URL?
    let height: CGFloat

    var body: some View {
        ArtImage(url: url, width: 800, blank: true)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay(
                LinearGradient(stops: [
                    .init(color: palette.background, location: 0),
                    .init(color: palette.background.opacity(0.9), location: 0.24),
                    .init(color: palette.background.opacity(0.5), location: 0.62),
                    .init(color: palette.background.opacity(0.2), location: 1),
                ], startPoint: .bottom, endPoint: .top)
            )
            .accessibilityHidden(true)
    }
}

/// The poster, 120 wide on a phone, overlapping the backdrop by 60.
private struct DetailPoster: View {
    @Environment(\.metrics) private var metrics
    let url: URL?
    let title: String

    var body: some View {
        let width: CGFloat = metrics.cardWidth <= 104 ? 120 : 160
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        PosterArt(url: url, title: title, width: width)
            .frame(width: width, height: width * 1.5)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(shape)
            .padding(.top, -width / 2)
            .accessibilityHidden(true)
    }
}

/// Grey shapes where an item or a show is coming.
private struct DetailSkeleton: View {
    @Environment(\.metrics) private var metrics
    let top: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonShape(radius: 0).frame(height: top + 220).opacity(0.6)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                SkeletonShape().frame(width: 120, height: 180).padding(.top, -60)
                SkeletonShape(radius: Tokens.Radius.xs).frame(width: 90, height: 12).padding(.top, Tokens.Space.s2)
                SkeletonShape(radius: Tokens.Radius.sm).frame(width: 240, height: 30)
                SkeletonShape(radius: Tokens.Radius.xs).frame(width: 180, height: 14)
                HStack(spacing: Tokens.Space.s2) {
                    SkeletonShape().frame(height: 44)
                    SkeletonShape().frame(height: 44)
                    SkeletonShape().frame(width: 44, height: 44)
                }
                .padding(.top, Tokens.Space.s3)
            }
            .padding(.horizontal, metrics.gutter)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// MARK: - An item

struct ItemPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let id: Int64
    @State private var item: Item?
    @State private var error = ""
    @State private var saving = false
    @State private var more = false

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

    /// The library's name, or the show and the episode's number.
    private func caption(_ item: Item) -> String {
        if let show = item.showTitle, !show.isEmpty {
            return [show, item.episodeLabel].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return item.libraryId.flatMap { id in model.libraries.first { $0.id == id }?.name } ?? ""
    }

    private func facts(_ item: Item) -> String {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if let runtime = runtimeText(item.runtimeSec) { parts.append(runtime) }
        if let rating = item.contentRating, !rating.isEmpty { parts.append(rating) }
        parts += (item.genres ?? []).prefix(3)
        return parts.joined(separator: " · ")
    }

    /// Kids save to their lists too; a Guest doesn't keep any.
    private var canSave: Bool { model.user.map { $0.kind != "guest" } ?? false }

    private func go(_ route: Route) { model.path.append(route) }

    @ViewBuilder private func actions(_ item: Item) -> some View {
        HStack(spacing: Tokens.Space.s2) {
            if item.isPlayable {
                // The server decides where Resume goes; nothing to resume means start at the beginning.
                NavigationLink(value: Route.player(item.id, startOver: item.resumeSeconds == nil)) {
                    Label(item.resumeSeconds == nil ? "Play" : "Resume", systemImage: "play.fill")
                }
                .pageButton(.primary, wide: true)
                .accessibilityLabel(item.resumeSeconds.map { "Resume from \(runtimeText($0) ?? "where you stopped")" } ?? "Play")
            } else if !item.isRigGame {
                NavigationLink(value: Route.page(ServerPages.path(item))) {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .pageButton(.primary, wide: true)
            }
            if canSave {
                Button { saving = true } label: { Label("Save", systemImage: "plus") }
                    .pageButton(.secondary, wide: true)
            }
            Button { more = true } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)) }
                .squareButton()
                .accessibilityLabel("More")
        }
    }

    @ViewBuilder private func page(_ item: Item, top: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailBackdrop(url: client.backdropURL(item), height: top + 220)
                VStack(alignment: .leading, spacing: 0) {
                    DetailPoster(url: client.posterURL(item), title: item.title)
                    let place = caption(item)
                    if !place.isEmpty { CaptionLabel(place).padding(.top, Tokens.Space.s4) }
                    Text(item.title)
                        .pageFont(.display)
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tokens.Space.s1)
                        .accessibilityAddTraits(.isHeader)
                    if let tagline = item.tagline, !tagline.isEmpty, !item.isRigGame {
                        Text(tagline).pageFont(.body, italic: true).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, Tokens.Space.s1)
                    }
                    let facts = facts(item)
                    if !facts.isEmpty {
                        Text(facts).pageFont(.body).foregroundStyle(palette.textSecondary).padding(.top, Tokens.Space.s2)
                    }
                    if !error.isEmpty { ProblemLine(error).padding(.top, Tokens.Space.s3) }
                    if item.isRigGame {
                        RigPlayPanel(item: item).padding(.top, Tokens.Space.s5)
                    }
                    actions(item).padding(.top, Tokens.Space.s5)
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .pageFont(.body)
                            .foregroundStyle(palette.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Tokens.Space.s5)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, metrics.gutter)
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .refreshable { await load() }
    }

    var body: some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            ZStack(alignment: .top) {
                if let item {
                    page(item, top: top)
                } else if !error.isEmpty {
                    ProblemView(words: error, retry: { error = ""; Task { await load() } }).padding(.top, top + 48)
                } else {
                    DetailSkeleton(top: top)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .pageBackground(palette)
        .task(id: id) { await load() }
        .sheet(isPresented: $saving) {
            if let item { SaveSheet(item: item) }
        }
        .confirmationDialog(item.map(displayTitle) ?? "", isPresented: $more, titleVisibility: .visible) {
            if let item {
                if item.isPlayable, item.resumeSeconds != nil {
                    Button("Play from the start") { go(.player(item.id, startOver: true)) }
                }
                if let next = item.nextId { Button("Next episode") { go(.item(next)) } }
                if let show = item.showId, let name = item.showTitle, !name.isEmpty {
                    Button("Go to \(name)") { go(.show(show)) }
                }
                // Artwork, editing the details and the rest of the website's tools for this title.
                Button(model.user?.isAdmin == true ? "Edit, artwork and more" : "More on the server's page") {
                    go(.page(ServerPages.path(item)))
                }
            }
        }
    }
}

// MARK: - Saving

/// Watch later and the person's own collections, each with a check when this is in it. Choosing one puts it in
/// or takes it out at once.
struct SaveSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let item: Item
    @State private var lists: [TitleCollection]?
    @State private var holding: Set<Int64> = []
    @State private var busy: Int64?
    @State private var error = ""

    private func load() async {
        do {
            let me = model.user?.id
            async let all = client.collections()
            async let held = client.collectionsHolding(item: item.id)
            let (found, inThem) = try await (all, held)
            lists = found.filter { $0.takesTitles && $0.ownerId == me }
            holding = Set(inThem)
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
            if lists == nil { lists = [] }
        }
    }

    private func toggle(_ list: TitleCollection?) async {
        busy = list?.id ?? -1
        defer { busy = nil }
        do {
            if let list {
                let isIn = holding.contains(list.id)
                try await client.setInCollection(list.id, item: item.id, !isIn)
                if isIn { holding.remove(list.id) } else { holding.insert(list.id) }
                announce(isIn ? "Taken out of \(list.name)" : "Saved to \(list.name)")
            } else {
                let made = try await client.saveForLater(item: item.id)
                holding.insert(made)
                announce("Saved to Watch later")
                await load()
            }
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    private func row(_ name: String, icon: String, tint: String, on: Bool, list: TitleCollection?) -> some View {
        Button {
            Task { await toggle(list) }
        } label: {
            HStack(spacing: 0) {
                RowLabel(icon: icon, tint: tint, title: name, value: list?.count.map { "\($0)" } ?? "", chevron: false)
                Group {
                    if busy == (list?.id ?? -1) {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(palette.accentText).opacity(on ? 1 : 0)
                    }
                }
                .frame(width: 24)
                .padding(.trailing, Tokens.Space.s4)
            }
        }
        .rowStyle()
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    Text(displayTitle(item)).pageFont(.secondary).foregroundStyle(palette.textSecondary)
                    if !error.isEmpty { ProblemLine(error) }
                    if let lists {
                        let later = lists.first { $0.name.caseInsensitiveCompare("Watch later") == .orderedSame }
                        ListGroup(title: "") {
                            row("Watch later", icon: "clock", tint: "#0a6fb8", on: later.map { holding.contains($0.id) } ?? false, list: later)
                            ForEach(lists.filter { $0.id != later?.id }) { list in
                                row(list.name, icon: "square.stack", tint: "#0e7c6f", on: holding.contains(list.id), list: list)
                            }
                        }
                        Text("Your collections are on the server's Collections page, where you can make new ones.")
                            .pageFont(.secondary).foregroundStyle(palette.textHint)
                    } else {
                        SkeletonShape(radius: Tokens.Radius.lg).frame(height: 104)
                    }
                }
                .padding(Tokens.Space.s4)
            }
            .pageBackground(palette)
            .navigationTitle("Save")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(palette.accentText) }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }
}

// MARK: - A show

struct ShowPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let id: Int64
    @State private var detail: ShowDetail?
    @State private var season: Int?
    @State private var error = ""
    @State private var more = false

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

    private func facts(_ detail: ShowDetail) -> String {
        var parts: [String] = []
        if let year = detail.show.year { parts.append(String(year)) }
        let seasons = detail.seasons?.count ?? detail.show.seasonCount ?? 0
        if seasons > 0 { parts.append("\(seasons) \(seasons == 1 ? "season" : "seasons")") }
        if let episodes = detail.show.episodeCount, episodes > 0 { parts.append("\(episodes) \(episodes == 1 ? "episode" : "episodes")") }
        return parts.joined(separator: " · ")
    }

    /// An episode: its picture, its number and title, how long it is and how far through.
    private func episodeRow(_ episode: Item) -> some View {
        let watched = episode.progress?.watched == true
        let facts = [runtimeText(episode.runtimeSec), watched ? "Watched" : nil].compactMap { $0 }.joined(separator: " · ")
        let width: CGFloat = metrics.cardWidth <= 104 ? 128 : 176
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
        return NavigationLink(value: Route.item(episode.id)) {
            HStack(alignment: .center, spacing: Tokens.Space.s3) {
                PosterArt(url: client.posterURL(episode), title: episode.title, width: width)
                    .frame(width: width, height: width * 9 / 16)
                    .overlay(alignment: .bottom) {
                        if let fraction = episode.progressFraction {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.white.opacity(0.28))
                                    Rectangle().fill(palette.accent).frame(width: geo.size.width * fraction)
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                    .clipShape(shape)
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.episodeLabel).pageFont(.caption).foregroundStyle(palette.textHint)
                    Text(episode.title).pageFont(.button).foregroundStyle(palette.text).lineLimit(2).multilineTextAlignment(.leading)
                    if !facts.isEmpty { Text(facts).pageFont(.small).foregroundStyle(palette.textHint).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(episode.episodeLabel), \(episode.title)")
        .accessibilityValue(watched ? "Watched" : (episode.progressFraction.map { "\(Int($0 * 100)) percent watched" } ?? ""))
    }

    @ViewBuilder private func page(_ detail: ShowDetail, top: CGFloat) -> some View {
        let selected = season ?? detail.seasons?.first?.number
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailBackdrop(url: client.backdropURL(detail.show), height: top + 220)
                VStack(alignment: .leading, spacing: 0) {
                    DetailPoster(url: client.posterURL(detail.show), title: detail.show.title)
                    let library = (detail.episodes ?? []).first?.libraryId.flatMap { id in model.libraries.first { $0.id == id }?.name } ?? ""
                    if !library.isEmpty { CaptionLabel(library).padding(.top, Tokens.Space.s4) }
                    Text(detail.show.title)
                        .pageFont(.display)
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tokens.Space.s1)
                        .accessibilityAddTraits(.isHeader)
                    let facts = facts(detail)
                    if !facts.isEmpty { Text(facts).pageFont(.body).foregroundStyle(palette.textSecondary).padding(.top, Tokens.Space.s2) }
                    if !error.isEmpty { ProblemLine(error).padding(.top, Tokens.Space.s3) }
                    HStack(spacing: Tokens.Space.s2) {
                        if let next = detail.nextUpId {
                            let label = (detail.episodes ?? []).first { $0.id == next }?.episodeLabel ?? ""
                            NavigationLink(value: Route.item(next)) {
                                Label(label.isEmpty ? "Next up" : "Next up: \(label)", systemImage: "play.fill")
                            }
                            .pageButton(.primary, wide: true)
                        }
                        Button { more = true } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)) }
                            .squareButton()
                            .accessibilityLabel("More")
                    }
                    .padding(.top, Tokens.Space.s5)
                    if let overview = detail.show.overview, !overview.isEmpty {
                        Text(overview).pageFont(.body).foregroundStyle(palette.text).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, Tokens.Space.s5)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, metrics.gutter)
                let seasons = uniqued(detail.seasons ?? [])
                if seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Tokens.Space.s1) {
                            ForEach(seasons) { s in
                                Button(s.displayTitle) { season = s.number }.chip(chosen: s.number == selected)
                            }
                        }
                        .padding(.horizontal, metrics.gutter)
                    }
                    .padding(.top, Tokens.Space.s5)
                } else if let only = seasons.first {
                    SectionHead(title: only.displayTitle).padding(.horizontal, metrics.gutter).padding(.top, Tokens.Space.s6)
                }
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    ForEach(uniqued(detail.episodes ?? []).filter { $0.season == selected }) { episodeRow($0) }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, metrics.gutter)
                .padding(.top, Tokens.Space.s3)
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .refreshable { await load() }
    }

    var body: some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            ZStack(alignment: .top) {
                if let detail {
                    page(detail, top: top)
                } else if !error.isEmpty {
                    ProblemView(words: error, retry: { error = ""; Task { await load() } }).padding(.top, top + 48)
                } else {
                    DetailSkeleton(top: top)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .pageBackground(palette)
        .task(id: id) { await load() }
        .confirmationDialog(detail?.show.title ?? "", isPresented: $more, titleVisibility: .visible) {
            Button(model.user?.isAdmin == true ? "Edit, artwork and more" : "More on the server's page") {
                model.path.append(.page("/show/\(id)"))
            }
        }
    }
}
