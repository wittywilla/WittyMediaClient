import SwiftUI
import WittyKit
#if os(iOS) || os(visionOS)
import UniformTypeIdentifiers
#endif

// Home, a library, a show and an item on a phone and a tablet, as the server's website has them at phone size
// (docs/APP-DESIGN.md, One mobile design with the website). Apple TV keeps its own, in BrowseViews.swift.

// MARK: - Rows

extension View {
    /// A row stops with a card at its start, 16 from the left edge, where the system can do that.
    @ViewBuilder func rowSnapping(side: CGFloat) -> some View {
        if #available(iOS 17.0, tvOS 17.0, visionOS 1.0, *) {
            self.contentMargins(.horizontal, side, for: .scrollContent).scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }

    @ViewBuilder func rowSnapTargets(side: CGFloat) -> some View {
        if #available(iOS 17.0, tvOS 17.0, visionOS 1.0, *) {
            self.scrollTargetLayout()
        } else {
            self.padding(.horizontal, side)
        }
    }
}

/// A section title with "See all ›", over a row of poster cards that scrolls sideways. In Customize home, the row
/// alone, from the edge of its box.
struct PageRow<Cards: View>: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.homePreview) private var preview
    let title: String
    var seeAll: Route?
    @ViewBuilder var cards: Cards

    var body: some View {
        let side = preview ? 0 : metrics.gutter
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if !preview {
                SectionHead(title: title, route: seeAll).padding(.horizontal, metrics.gutter)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s4) { cards }
                    .rowSnapTargets(side: side)
                    .padding(.top, Tokens.Space.s3)
                    .padding(.bottom, Tokens.Space.s4)
            }
            .rowSnapping(side: side)
        }
    }
}

/// One of Home's rows, its cards as the website draws them: wide for pictures and creator videos. A saved view's
/// See all keeps its choices, on the server's library page, which reads them from its address.
private struct HubPageRow: View {
    @EnvironmentObject private var model: AppModel
    let hub: Hub
    let focus: FocusState<String?>.Binding

    private var library: Library? { hub.libraryId.flatMap { id in model.libraries.first { $0.id == id } } }

    private var seeAll: Route? {
        guard let id = hub.libraryId else { return nil }
        if let query = hub.query, !query.isEmpty { return .page("/library/\(id)?\(query)") }
        return library.map(libraryRoute) ?? .page("/library/\(id)")
    }

    var body: some View {
        let wide = ["photos", "channels", "musicvideos"].contains(library?.type ?? "")
        PageRow(title: hub.title, seeAll: seeAll) {
            ForEach(ServerPages.albumsOnce(uniqued(hub.items ?? []))) { ItemTile(item: $0, wide: wide, focus: focus) }
            ForEach(uniqued(hub.shows ?? [])) { ShowTile(show: $0, focus: focus) }
        }
    }
}

/// What's on the channels now (pages/tv/OnNowRow.tsx, onnow.css): favourites first, each a card 230 wide of the
/// programme's picture on `card`, the channel's number on a plate and a 4-high bar of how far in along the bottom,
/// then what's on in 14 semibold and the channel with the time left in 13 `textSecondary`. Guide opens the TV guide.
private struct OnNowPageRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.homePreview) private var preview
    let channels: [GuideChannel]
    private let width: CGFloat = 230

    var body: some View {
        let now = Date().timeIntervalSince1970
        let side = preview ? 0 : metrics.gutter
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if !preview {
                SectionHead(title: "On TV now", action: "Guide", tap: { model.tab = .guide })
                    .padding(.horizontal, metrics.gutter)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s4) {
                    ForEach(channels) { card($0, now: now) }
                }
                .rowSnapTargets(side: side)
                .padding(.top, Tokens.Space.s3)
                .padding(.bottom, Tokens.Space.s4)
            }
            .rowSnapping(side: side)
        }
    }

    private func card(_ channel: GuideChannel, now: Double) -> some View {
        let picture = OnNowLook.programme(channel, at: now)?.itemId.flatMap { client.mediaURL("/api/items/\($0)/backdrop") }
        let fraction = OnNowLook.fraction(channel, at: now)
        return NavigationLink(value: Route.page("/tv/watch/\(WittyClient.pathPart(channel.key))")) {
            VStack(alignment: .leading, spacing: 3) {
                Color.clear
                    .frame(width: width, height: width * 9 / 16)
                    .background(palette.card)
                    // A picture that doesn't come leaves the card plain.
                    .overlay { if let picture { ArtImage(url: picture, width: width, blank: true) } }
                    .overlay(alignment: .topLeading) {
                        if let number = channel.number, !number.isEmpty {
                            Text(number)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous).fill(palette.scrim))
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(palette.scrim)
                                Rectangle().fill(palette.accent).frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                Text(OnNowLook.title(channel, at: now))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .frame(minHeight: 22)
                Text(OnNowLook.detail(channel, at: now))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .frame(minHeight: 20)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(OnNowLook.spoken(channel, at: now))
    }
}

/// Your libraries (HomePage.tsx LibraryTiles): a tile for each, two across a phone, then Add a library for
/// administrators. Manage opens the libraries' settings.
private struct LibrariesSection: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.homePreview) private var preview
    let libraries: [Library]
    let admin: Bool
    let compact: Bool

    var body: some View {
        let columns = compact ? Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s2), count: 2)
                              : [GridItem(.adaptive(minimum: 200), spacing: Tokens.Space.s3)]
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if !preview {
                SectionHead(title: "Your libraries", action: "Manage", route: admin ? .page("/settings/libraries") : nil)
            }
            LazyVGrid(columns: columns, spacing: compact ? Tokens.Space.s2 : Tokens.Space.s3) {
                ForEach(libraries) { library in
                    NavigationLink(value: libraryRoute(library)) { LibraryTile(library: library, compact: compact) }
                        .buttonStyle(PressStyle())
                }
                if admin {
                    NavigationLink(value: Route.page("/settings/libraries")) { LibraryTile(addingCompact: compact) }
                        .buttonStyle(PressStyle())
                }
            }
        }
        .padding(.horizontal, preview ? 0 : metrics.gutter)
    }
}

/// Can't decide? (HomePage.tsx Shuffle, shell.css `.shuffle`): a film or a disc at random on `panel`, over its own
/// backdrop at 16%, with its poster, title, facts, the main button, Details and Another.
private struct ShuffleSection: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.homePreview) private var preview
    let item: Item
    let compact: Bool
    let another: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if !preview { SectionHead(title: "Can’t decide?") }
            box
        }
        .padding(.horizontal, preview ? 0 : metrics.gutter)
    }

    private var poster: some View {
        let width: CGFloat = compact ? 90 : 104
        return PosterArt(url: client.posterURL(item), title: item.title, width: width)
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 10)
    }

    private var info: some View {
        let facts = ShuffleLook.facts(item)
        return VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .pageFont(.section)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if !facts.isEmpty {
                Text(facts).pageFont(.body).foregroundStyle(palette.textHint)
            }
            FlowLayout(spacing: Tokens.Space.s2) {
                OpenItemButton(item: item).pageButton(.primary)
                NavigationLink(value: route(for: item)) { Label("Details", systemImage: "info.circle.fill") }
                    .pageButton(.secondary)
                Button(action: another) { Label("Another", systemImage: "arrow.triangle.2.circlepath") }
                    .pageButton(.ghost)
            }
            .padding(.top, 6)
        }
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        return Group {
            if compact {
                VStack(alignment: .leading, spacing: Tokens.Space.s5) { poster; info }
            } else {
                HStack(alignment: .center, spacing: Tokens.Space.s5) { poster; info }
            }
        }
        .padding(Tokens.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                palette.panel
                ArtImage(url: client.backdropURL(item), width: 400, blank: true).opacity(0.16)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.border, lineWidth: 1))
    }
}

// MARK: - The top of Home

/// When nothing is featured: "Good morning, Willow" in 24 semibold over "Here's what's on your server."
private struct Greeting: View {
    @Environment(\.palette) private var palette
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text(HomeGreeting.line(hour: Calendar.current.component(.hour, from: Date()), name: name))
                .pageFont(.title)
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            Text("Here’s what’s on your server.").pageFont(.body).foregroundStyle(palette.textHint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A newer server, for administrators (components/UpdateBanner.tsx, ui `Notice`): on `card` with an outline of `text`
/// at 20%, the version in 14 semibold, its first change, then Update, What's new and Later. Update and What's new open
/// Settings, About on the server's page.
private struct UpdateNotice: View {
    @Environment(\.palette) private var palette
    let version: String
    let status: UpdateStatus?
    let later: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        let about = Route.page("/settings/about#updates")
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(UpdateNews.title(version)).font(.system(size: 14, weight: .semibold))
                if let status { Text(UpdateNews.sentence(status)).font(.system(size: 14)) }
            }
            .foregroundStyle(palette.text)
            .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: Tokens.Space.s2) {
                NavigationLink(UpdateNews.action(status), value: about).smallButton(.primary)
                NavigationLink("What’s new", value: about).smallButton(.secondary)
                Button("Later", action: later).smallButton(.ghost)
            }
        }
        .padding(.vertical, Tokens.Space.s3)
        .padding(.horizontal, Tokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(palette.card))
        .overlay(shape.strokeBorder(palette.text.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// The first visit, before there's any library (HomePage.tsx Welcome): a welcome, what to do, and for administrators the
/// way to add one, which is the server's Libraries settings.
private struct Welcome: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let admin: Bool
    let name: String
    let compact: Bool

    private var words: AttributedString {
        var said = AttributedString((admin
            ? "Choose what kind of media you have, then point to the folder it’s in. Your files stay where they are; nothing is moved or changed. You can add more libraries any time."
            : "There’s nothing to watch, read or listen to yet. Whoever runs this server can add libraries in Settings, and they’ll appear here.") + " ")
        var link = AttributedString("Getting started")
        link.link = URL(string: "wittymedia-help:getting-started")
        link.swiftUI.underlineStyle = .single
        said += link
        return said
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(systemName: "film.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(palette.accentText)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(palette.accent.opacity(0.14)))
                    .accessibilityHidden(true)
                Text("Welcome\(name.isEmpty ? "" : ", \(name)")! Let’s fill your server.")
                    .pageFont(.display)
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                Text(words)
                    .pageFont(.body)
                    .lineSpacing(5)
                    .foregroundStyle(palette.textHint)
                    .tint(palette.accentText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 580)
                    .environment(\.openURL, OpenURLAction { _ in
                        model.path.append(.page("/help/getting-started"))
                        return .handled
                    })
            }
            if admin {
                NavigationLink(value: Route.page("/settings/libraries")) { LibraryTile(addingCompact: compact) }
                    .buttonStyle(PressStyle())
                    .frame(maxWidth: compact ? .infinity : 280)
            }
        }
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Customize home

/// What Customize home says, with Reset and Done (shell.css `.home-tools`): on `panel` with a hairline and a small
/// shadow, under the strip.
private struct HomeTools: View {
    @Environment(\.palette) private var palette
    let reset: () -> Void
    let done: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        VStack(alignment: .trailing, spacing: 10) {
            Text("Drag sections, or use the arrows. Hidden sections stay here until you show them again.")
                .font(.system(size: 13))
                .foregroundStyle(palette.textHint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Reset", action: reset).smallButton(.ghost)
                Button("Done", action: done).smallButton(.primary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            shape.fill(palette.panel)
                .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        )
        .overlay(shape.strokeBorder(palette.border, lineWidth: 1))
    }
}

/// One section in Customize home (`.widget.edit`): `panel` in a dashed outline, its name with Up, Down and Hide or
/// Show, and a small look at it, fading out at the foot. A hidden one is faded and shows only its bar.
private struct WidgetEditor<Preview: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    let hidden: Bool
    let first: Bool
    let last: Bool
    let up: () -> Void
    let down: () -> Void
    let toggle: () -> Void
    @ViewBuilder var preview: Preview

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Tokens.Space.s2) {
                Image(systemName: "circle.grid.2x3.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textHint)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: up) { Image(systemName: "chevron.up") }
                    .smallButton(.ghost, square: true)
                    .disabled(first)
                    .accessibilityLabel("Move \(title) up")
                Button(action: down) { Image(systemName: "chevron.down") }
                    .smallButton(.ghost, square: true)
                    .disabled(last)
                    .accessibilityLabel("Move \(title) down")
                Button(hidden ? "Show" : "Hide", action: toggle).smallButton()
            }
            .padding(.vertical, Tokens.Space.s2)
            .padding(.horizontal, Tokens.Space.s3)
            if !hidden {
                preview
                    .environment(\.homePreview, true)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: 280, alignment: .top)
                    .clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .padding(.horizontal, Tokens.Space.s3)
                    .padding(.bottom, Tokens.Space.s3)
            }
        }
        .background(shape.fill(palette.panel))
        .overlay(shape.strokeBorder(palette.text.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .opacity(hidden ? 0.55 : 1)
    }
}

#if os(iOS) || os(visionOS)
/// Dropping a section on another puts it in that one's place.
private struct WidgetDrop: DropDelegate {
    let place: Int
    @Binding var dragging: String?
    let move: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = dragging else { return false }
        dragging = nil
        move(id, place)
        return true
    }
}
#endif

// MARK: - Home

/// The website's Home on a phone (pages/HomePage.tsx): its sections in the order this person saved, with the hero
/// under the library strip; a greeting when nothing is featured; the notice of a newer server for administrators; a
/// card while the libraries are empty or still being looked through; and Customize home at the foot.
struct PhoneHome: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var home: Home?
    @State private var recommended: Recommended?
    @State private var channels: [GuideChannel] = []
    @State private var pick: Item?
    @State private var layout = HomeLayout()
    /// The newer version an administrator put off.
    @State private var putOff: String?
    /// The newer version the server found, for administrators.
    @State private var update = ""
    @State private var updateStatus: UpdateStatus?
    @State private var trouble: Trouble?
    @State private var editing = false
    @State private var dragging: String?
    /// What couldn't be saved, for a few seconds.
    @State private var said = ""
    @State private var solid = 0.0
    @FocusState private var focused: String?

    private struct Trouble: Equatable {
        let offline: Bool
        let words: String
    }

    private var isAdmin: Bool { model.user?.isAdmin == true }
    private var name: String { model.user?.shownName ?? "" }
    private var mainLibraries: [Library] { model.libraries.filter(\.inMainMenus) }
    private var showsUpdate: Bool { UpdateNews.shows(update: update, isAdmin: isAdmin, later: putOff) }

    private func load() async {
        do {
            let fresh = try await client.home()
            trouble = nil
            if fresh != home { home = fresh }
            model.homeLoaded(fresh)
        } catch {
            // A page already showing stays up. A failed refresh is no reason to lose it.
            let words = model.handle(error)
            if home == nil, !words.isEmpty { trouble = Trouble(offline: error is URLError, words: words) }
        }
        async let picked = try? client.recommended()
        async let couch = try? client.couchStatus()
        async let guide = try? client.onNow()
        async let choices = try? client.homeChoices()
        async let random = try? client.shuffle()
        async let newer = newerVersion()
        let (fresh, pcs, listing, saved, chosen, version) = await (picked, couch, guide, choices, random, newer)
        if fresh != recommended { recommended = fresh }
        model.gamePCs = pcs?.allowed == true
        let ordered = OnNowLook.ordered(uniqued(listing?.channels ?? []))
        if ordered != channels { channels = ordered }
        if let saved {
            if !editing { layout = HomeLayout.saved(saved.home) }
            putOff = saved.updateLater
        }
        if let chosen { pick = chosen }
        update = version
        if showsUpdate {
            // A build that can't update itself has no /update: the notice still shows, without its first change.
            updateStatus = try? await client.updateStatus()
        } else {
            updateStatus = nil
        }
    }

    /// The server says what's newer in its status, and only to administrators.
    private func newerVersion() async -> String {
        guard isAdmin else { return "" }
        return (try? await client.status())?.update ?? ""
    }

    private func save(_ next: HomeLayout) {
        layout = next
        let client = client
        Task {
            do { try await client.saveHomeLayout(next) } catch { tell("Could not save the layout") }
        }
    }

    private func putOffUpdate() {
        let version = update
        putOff = version
        let client = client
        Task {
            do { try await client.putOffUpdate(version) } catch { tell("Could not save that") }
        }
    }

    private func another() {
        let client = client
        Task {
            if let fresh = try? await client.shuffle() { pick = fresh }
        }
    }

    private func tell(_ words: String) {
        said = words
        announce(words)
    }

    // MARK: Sections

    private func widgets(_ home: Home) -> [HomeWidget] {
        layout.ordered(HomeWidgets.list(home, recommended: recommended))
    }

    /// Whether a section has anything to show. One that hasn't is left out, as the website leaves it out.
    private func renders(_ widget: HomeWidget, _ home: Home) -> Bool {
        switch widget.id {
        case HomeWidgets.hero: return !(home.featured ?? []).isEmpty
        case HomeWidgets.libraries: return !mainLibraries.isEmpty
        case HomeWidgets.onNow: return !channels.isEmpty
        case HomeWidgets.shuffle: return pick != nil
        default: return widget.hub.map { !$0.isEmpty } ?? false
        }
    }

    private func shown(_ home: Home) -> [HomeWidget] {
        widgets(home).filter { !layout.hidden.contains($0.id) && renders($0, home) }
    }

    /// The hero runs up under the strip when it's the first thing on the page.
    private func heroFirst(_ home: Home) -> Bool {
        !editing && !(home.libraries ?? []).isEmpty && !showsUpdate && shown(home).first?.id == HomeWidgets.hero
    }

    private var heroOnTop: Bool {
        if let home { return heroFirst(home) }
        return trouble == nil
    }

    @ViewBuilder private func section(_ widget: HomeWidget, _ home: Home, top: CGFloat, heroHeight: CGFloat, width: CGFloat) -> some View {
        switch widget.id {
        case HomeWidgets.hero:
            HomeHero(items: uniqued(home.featured ?? []), top: top, height: heroHeight, narrow: width <= 700)
        case HomeWidgets.libraries:
            LibrariesSection(libraries: mainLibraries, admin: isAdmin, compact: width <= 600)
        case HomeWidgets.onNow:
            OnNowPageRow(channels: channels)
        case HomeWidgets.shuffle:
            if let pick { ShuffleSection(item: pick, compact: width <= 600, another: another) }
        default:
            if let hub = widget.hub { HubPageRow(hub: hub, focus: $focused) }
        }
    }

    @ViewBuilder private var notices: some View {
        let words = [model.notice, said].filter { !$0.isEmpty }
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ForEach(words, id: \.self) { ProblemLine($0) }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, Tokens.Space.s4)
        }
    }

    private var emptyCard: some View {
        let scanning = model.libraries.contains { $0.scanning == true }
        return HomeCard(icon: "arrow.triangle.2.circlepath",
                        title: scanning ? "Your libraries are being scanned" : "Your libraries are empty",
                        words: scanning
                            ? "Movies, shows, music and books appear here as they’re found. The first scan can take a few minutes."
                            : "Nothing was found in their folders yet. Check the folders in Settings, Libraries, then scan again.") {
            if isAdmin && !scanning {
                NavigationLink("Open library settings", value: Route.page("/settings/libraries")).pageButton(.secondary)
            }
        }
    }

    // MARK: Pages

    @ViewBuilder private func page(_ home: Home, top: CGFloat, width: CGFloat, heroHeight: CGFloat) -> some View {
        let sections = shown(home)
        let onTop = heroFirst(home)
        let featured = home.featured ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                if !onTop {
                    Color.clear.frame(height: top + LibraryStrip.height + Tokens.Space.s2)
                }
                if showsUpdate {
                    // The website sets the notice in by a gutter of its own, inside the page's.
                    UpdateNotice(version: update, status: updateStatus, later: putOffUpdate)
                        .padding(.horizontal, metrics.gutter * 2)
                        .padding(.top, Tokens.Space.s3)
                }
                if featured.isEmpty || layout.hidden.contains(HomeWidgets.hero) {
                    Greeting(name: name)
                        .padding(.horizontal, metrics.gutter)
                        .padding(.top, Tokens.Space.s2)
                        .padding(.bottom, Tokens.Space.s6)
                }
                if !onTop { notices }
                if HomeWidgets.isEmpty(home) {
                    emptyCard
                        .padding(.horizontal, metrics.gutter)
                        .padding(.bottom, 30)
                }
                ForEach(sections) { widget in
                    section(widget, home, top: onTop ? top : 0, heroHeight: heroHeight, width: width)
                        .padding(.bottom, 28)
                    if onTop, widget.id == HomeWidgets.hero { notices }
                }
                // Customize home starts at the top of the page, as the website scrolls there.
                Button("Customize home") {
                    solid = 0
                    editing = true
                }
                    .smallButton(.ghost)
                    .accessibilityHint("Rearrange or hide sections of the home page")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                    .padding(.bottom, Tokens.Space.s1)
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .stripSolidity($solid)
        .refreshable { await load() }
    }

    @ViewBuilder private func editPage(_ home: Home, top: CGFloat, width: CGFloat, heroHeight: CGFloat) -> some View {
        let ordered = widgets(home)
        let ids = ordered.map(\.id)
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { place, widget in
                    let editor = WidgetEditor(title: widget.title, hidden: layout.hidden.contains(widget.id),
                                              first: place == 0, last: place == ordered.count - 1,
                                              up: { save(layout.moving(widget.id, to: place - 1, among: ids)) },
                                              down: { save(layout.moving(widget.id, to: place + 1, among: ids)) },
                                              toggle: { save(layout.toggling(widget.id)) }) {
                        if renders(widget, home) {
                            section(widget, home, top: 0, heroHeight: heroHeight, width: width - 2 * metrics.gutter - 26)
                        } else {
                            Text("Nothing to show here right now.").pageFont(.body).foregroundStyle(palette.textHint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    #if os(iOS) || os(visionOS)
                    editor
                        .onDrag {
                            dragging = widget.id
                            return NSItemProvider(object: widget.id as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: WidgetDrop(place: place, dragging: $dragging) { id, at in
                            save(layout.moving(id, to: at, among: ids))
                        })
                    #else
                    editor
                    #endif
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, 14)
            .padding(.bottom, Tokens.Space.s6)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeTools(reset: { save(HomeLayout()) }, done: { editing = false })
                .padding(.horizontal, metrics.gutter)
                .padding(.top, top + LibraryStrip.height + Tokens.Space.s1)
        }
    }

    private func welcomePage(top: CGFloat, viewport: CGFloat, width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if showsUpdate {
                    UpdateNotice(version: update, status: updateStatus, later: putOffUpdate)
                        .padding(.bottom, Tokens.Space.s4)
                }
                Welcome(admin: isAdmin, name: name, compact: width <= 600)
                    .padding(.top, viewport * 0.04)
                    .padding(.bottom, Tokens.Space.s10)
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, top + LibraryStrip.height + Tokens.Space.s2)
        }
        .refreshable { await load() }
    }

    private func troublePage(_ trouble: Trouble, top: CGFloat, viewport: CGFloat) -> some View {
        ScrollView {
            HomeCard(icon: "info.circle.fill",
                     title: trouble.offline ? "Can’t reach your server" : "Home didn’t load",
                     words: trouble.offline
                        ? "Check that WittyMediaServer is running on its computer and that this device is on the same network. This page tries again by itself every few seconds."
                        : trouble.words) {
                Button { Task { await load() } } label: { Label("Try again", systemImage: "arrow.triangle.2.circlepath") }
                    .pageButton(.primary)
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, top + LibraryStrip.height + Tokens.Space.s2 + viewport * 0.08)
            .padding(.bottom, Tokens.Space.s6)
        }
        .refreshable { await load() }
        .onAppear { announce(trouble.offline ? "Can’t reach your server" : "Home didn’t load") }
    }

    var body: some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            let width = outer.size.width
            // The website's vh: the screen below the clock.
            let viewport = max(screenSize.height - top, 1)
            let heroHeight = HomeHero.height(viewport: viewport, narrow: width <= 700)
            ZStack(alignment: .top) {
                if let home {
                    if (home.libraries ?? []).isEmpty {
                        welcomePage(top: top, viewport: viewport, width: width)
                    } else if editing {
                        editPage(home, top: top, width: width, heroHeight: heroHeight)
                    } else {
                        page(home, top: top, width: width, heroHeight: heroHeight)
                    }
                } else if let trouble {
                    troublePage(trouble, top: top, viewport: viewport)
                } else {
                    HomeSkeleton(top: top, height: heroHeight, width: width)
                }
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                if heroOnTop { StripScrim(top: top).opacity(1 - solid).ignoresSafeArea(edges: .top) }
            }
        }
        // On the reader, which keeps to the safe area, so the strip sits under the clock and not behind it.
        .overlay(alignment: .top) { LibraryStrip(current: nil, solid: editing ? 1 : solid, overPicture: heroOnTop) }
        .pageBackground(palette)
        // Again on every return, as what's "Jump back in" has probably just changed.
        .task { await load() }
        // Offline, it tries again every few seconds, so Home comes back by itself when the server does.
        .task(id: trouble) {
            guard trouble?.offline == true else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { await load() }
        }
        .task(id: said) {
            guard !said.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { said = "" }
        }
    }
}

/// Pressed, a tile dims a little and shrinks a touch, as the website's buttons do.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: Tokens.Motion.press), value: configuration.isPressed)
    }
}

/// Grey shapes where Home is coming, as the website's (ui/Surface.tsx PageSkeleton, `home`): the hero with its title,
/// facts and two buttons, the libraries, and a row of posters.
private struct HomeSkeleton: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let top: CGFloat
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        let inner = max(width - 2 * metrics.gutter, 0)
        let compact = width <= 600
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [palette.card.opacity(0.6), palette.card.opacity(0)], startPoint: .top, endPoint: .bottom)
                HeroShade()
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    SkeletonShape(radius: Tokens.Radius.xs).frame(width: inner * 0.7, height: 32)
                    SkeletonShape(radius: Tokens.Radius.xs).frame(width: inner * 0.45, height: 15)
                    SkeletonShape(radius: Tokens.Radius.xs).frame(width: inner * 0.9, height: 15)
                    HStack(spacing: Tokens.Space.s2) {
                        SkeletonShape().frame(width: 104, height: 44)
                        SkeletonShape().frame(width: 104, height: 44)
                    }
                }
                .padding(.horizontal, metrics.gutter)
                .padding(.bottom, Tokens.Space.s6)
            }
            .frame(height: top + height)
            .padding(.bottom, 28)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                SkeletonShape(radius: Tokens.Radius.xs).frame(width: 144, height: 20)
                LazyVGrid(columns: compact ? Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s2), count: 2)
                                           : [GridItem(.adaptive(minimum: 200), spacing: Tokens.Space.s3)],
                          spacing: compact ? Tokens.Space.s2 : Tokens.Space.s3) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonShape(radius: Tokens.Radius.lg).frame(height: 64) }
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, 28)
            VStack(alignment: .leading, spacing: 0) {
                SkeletonShape(radius: Tokens.Radius.xs).frame(width: 192, height: 20)
                HStack(alignment: .top, spacing: Tokens.Space.s4) {
                    ForEach(0..<6, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                            SkeletonShape().aspectRatio(2.0 / 3.0, contentMode: .fit)
                            SkeletonShape(radius: Tokens.Radius.xs).frame(width: metrics.cardWidth * 0.8, height: 14)
                            SkeletonShape(radius: Tokens.Radius.xs).frame(width: metrics.cardWidth * 0.5, height: 12)
                        }
                        .frame(width: metrics.cardWidth)
                    }
                }
                .padding(.top, Tokens.Space.s3 + Tokens.Space.s3)
                .frame(width: max(width - metrics.gutter, 0), alignment: .leading)
                .clipped()
            }
            .padding(.leading, metrics.gutter)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// The featured titles (HomePage.tsx Hero, styles.css `.hero` under 700): 66% of the screen's height, between 380 and
/// 660, under the strip, the backdrop darkened from the bottom, with the title, its facts, two lines of what it's
/// about in `text` at 86%, and the main button, Disc menu for a disc with menus, and Details. It turns every 9 s
/// until paused, starting paused with Reduce Motion; pause and a dot for each title sit at the top right.
struct HomeHero: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homePreview) private var preview
    let items: [Item]
    /// The room above it that its picture runs under: the clock's, when it's at the top of the page.
    let top: CGFloat
    let height: CGFloat
    /// A phone's hero, words over the picture; a wider one has its dots at the foot.
    var narrow = true
    @State private var index = 0
    /// Nil until someone chooses, which leaves it as Reduce Motion has it.
    @State private var paused: Bool?

    /// 66% of a phone's screen, between 380 and 660; 62% of a bigger one, between 400 and 660.
    static func height(viewport: CGFloat, narrow: Bool) -> CGFloat {
        narrow ? min(max(viewport * 0.66, 380), 660) : min(max(viewport * 0.62, 400), 660)
    }

    private var isPaused: Bool { paused ?? reduceMotion }
    private var current: Item { items[min(index, items.count - 1)] }

    /// The title showing, the one before and the one after: the rest wait to be shown.
    private func near(_ place: Int) -> Bool {
        let count = items.count
        return place == index || place == (index + 1) % count || place == (index + count - 1) % count
    }

    var body: some View {
        let item = current
        let total = preview ? 240 : top + height
        ZStack(alignment: .bottomLeading) {
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { place, each in
                    if near(place) {
                        ArtImage(url: client.backdropURL(each), width: 800, blank: true)
                            .opacity(place == index ? 1 : 0)
                    }
                }
            }
            .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.42), value: index)
            .frame(maxWidth: .infinity)
            .frame(height: total)
            .clipped()
            .accessibilityHidden(true)
            HeroShade()
            info(item)
        }
        .frame(height: total)
        .clipShape(RoundedRectangle(cornerRadius: preview ? Tokens.Radius.md : 0, style: .continuous))
        .overlay(alignment: narrow ? .topTrailing : .bottomTrailing) {
            if items.count > 1, !preview { dots }
        }
        .task(id: "\(index)|\(isPaused)|\(items.count)") {
            guard items.count > 1, !isPaused, !preview else { return }
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            if !Task.isCancelled { index = (index + 1) % items.count }
        }
    }

    private func info(_ item: Item) -> some View {
        let facts = HeroLook.facts(item)
        return VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .pageFont(.display)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Tokens.Space.s3)
                .accessibilityAddTraits(.isHeader)
            if !facts.isEmpty {
                HeroFactsRow(facts: facts).padding(.bottom, Tokens.Space.s3)
            }
            if !preview, let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .pageFont(.body)
                    .lineSpacing(5)
                    .foregroundStyle(palette.text)
                    .opacity(0.86)
                    .lineLimit(narrow ? 2 : 3)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.bottom, Tokens.Space.s5)
            }
            FlowLayout(spacing: Tokens.Space.s2) {
                OpenItemButton(item: item)
                    .pageButton(.primary)
                    .accessibilityLabel("\(OpenLook.label(item)) \(item.title)")
                if item.hasDiscMenus {
                    NavigationLink("Disc menu", value: Route.page(OpenLook.discMenu(item))).pageButton(.secondary)
                }
                NavigationLink(value: route(for: item)) { Label("Details", systemImage: "info.circle.fill") }
                    .pageButton(.ghost)
                    .accessibilityLabel("Details of \(item.title)")
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(.horizontal, metrics.gutter)
        .padding(.bottom, preview ? Tokens.Space.s3 : (narrow ? Tokens.Space.s6 : Tokens.Space.s10))
    }

    /// Pause, then a dot for each title, the current one longer. Each is a 24 target.
    private var dots: some View {
        HStack(spacing: 2) {
            Button {
                paused = !isPaused
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, Tokens.Space.s1)
            .accessibilityLabel(isPaused ? "Start turning the featured titles" : "Stop turning the featured titles")
            ForEach(items.indices, id: \.self) { place in
                let here = place == index
                Button {
                    index = place
                } label: {
                    Capsule()
                        .fill(here ? palette.text : palette.text.opacity(0.45))
                        .frame(width: here ? 18 : 8, height: 8)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show featured title \(place + 1)")
                .accessibilityAddTraits(here ? [.isSelected] : [])
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: index)
        .padding(.top, narrow ? top + LibraryStrip.height + Tokens.Space.s2 : 0)
        .padding(.bottom, narrow ? 0 : Tokens.Space.s10)
        .padding(.trailing, metrics.gutter)
    }
}
