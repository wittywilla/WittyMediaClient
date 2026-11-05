import SwiftUI
import WittyKit

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

/// A section title with "See all ›", over a row of poster cards that scrolls sideways.
struct PageRow<Cards: View>: View {
    @Environment(\.metrics) private var metrics
    let title: String
    var seeAll: Route?
    @ViewBuilder var cards: Cards

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            SectionHead(title: title, route: seeAll).padding(.horizontal, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s4) { cards }
                    .rowSnapTargets(side: metrics.gutter)
                    .padding(.top, Tokens.Space.s3)
                    .padding(.bottom, Tokens.Space.s4)
            }
            .rowSnapping(side: metrics.gutter)
        }
    }
}

/// One of Home's rows, its cards as the website draws them: wide for pictures and creator videos.
private struct HubPageRow: View {
    @EnvironmentObject private var model: AppModel
    let hub: Hub
    let focus: FocusState<String?>.Binding

    var body: some View {
        let library = hub.libraryId.flatMap { id in model.libraries.first { $0.id == id } }
        let wide = ["photos", "channels", "musicvideos"].contains(library?.type ?? "")
        PageRow(title: hub.title, seeAll: library.map(libraryRoute)) {
            ForEach(ServerPages.albumsOnce(uniqued(hub.items ?? []))) { ItemTile(item: $0, wide: wide, focus: focus) }
            ForEach(uniqued(hub.shows ?? [])) { ShowTile(show: $0, focus: focus) }
        }
    }
}

/// What's on the channels now, as wide cards, with "See all" opening the guide.
private struct OnNowPageRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let channels: [GuideChannel]

    var body: some View {
        let now = Int64(Date().timeIntervalSince1970)
        let width = metrics.cardWidth * 2.5
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack {
                Text("On TV now").pageFont(.section).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    model.tab = .guide
                } label: {
                    HStack(spacing: 2) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .pageFont(.action)
                    .foregroundStyle(palette.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all, TV guide")
            }
            .padding(.horizontal, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s4) {
                    ForEach(channels) { channel in
                        let on = channel.on(at: now)
                        let words = on?.title ?? "Nothing listed"
                        NavigationLink(value: Route.page("/tv/watch/\(WittyClient.pathPart(channel.key))")) {
                            VStack(alignment: .leading, spacing: 0) {
                                RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                                    .fill(palette.card)
                                    .frame(width: width, height: width * 9 / 16)
                                    .overlay {
                                        Image(systemName: channel.radio == true ? "radio" : "tv")
                                            .font(.system(size: 24, weight: .medium))
                                            .foregroundStyle(palette.textHint)
                                    }
                                    .overlay(alignment: .topLeading) {
                                        if let number = channel.number, !number.isEmpty {
                                            Text(number)
                                                .pageFont(.caption)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .frame(minHeight: 20)
                                                .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs).fill(palette.scrim))
                                                .padding(Tokens.Space.s2)
                                        }
                                    }
                                    .overlay(alignment: .bottom) {
                                        if let on {
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Rectangle().fill(Color.white.opacity(0.28))
                                                    Rectangle().fill(palette.accent).frame(width: geo.size.width * on.fraction(at: now))
                                                }
                                            }
                                            .frame(height: 3)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                                Text(words).pageFont(.button).foregroundStyle(palette.text).lineLimit(1).padding(.top, Tokens.Space.s2)
                                Text(channel.name + (on.map { " · \($0.minutesLeft(at: now)) min left" } ?? ""))
                                    .pageFont(.small).foregroundStyle(palette.textHint).lineLimit(1).padding(.top, 2)
                            }
                            .frame(width: width, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Channel \(channel.label): \(words)")
                    }
                }
                .rowSnapTargets(side: metrics.gutter)
                .padding(.top, Tokens.Space.s3)
                .padding(.bottom, Tokens.Space.s4)
            }
            .rowSnapping(side: metrics.gutter)
        }
    }
}

// MARK: - Home

/// The website's Home on a phone: the hero under the library strip, "Your libraries", then the rows.
struct PhoneHome: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var home: Home?
    @State private var recommended: Recommended?
    @State private var onNow: [GuideChannel] = []
    @State private var error = ""
    @State private var solid = 0.0
    @FocusState private var focused: String?

    private func heroes(_ home: Home) -> [Item] {
        let pool = (home.featured ?? []).isEmpty ? ((home.hubs ?? []).first { !$0.isEmpty }?.items ?? []) : (home.featured ?? [])
        return Array(ServerPages.albumsOnce(uniqued(pool)).prefix(8))
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
        async let picked = try? client.recommended()
        async let couch = try? client.couchStatus()
        async let guide = try? client.guide()
        let (fresh, pcs, listing) = await (picked, couch, guide)
        if fresh != recommended { recommended = fresh }
        model.gamePCs = pcs?.allowed == true
        let channels = uniqued(listing?.channels ?? [])
        model.channels = channels
        onNow = channels.filter(\.canTune)
    }

    private var isAdmin: Bool { model.user?.isAdmin == true }

    private var libraryColumns: [GridItem] {
        if metrics.cardWidth <= 104 {
            return Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s2), count: 2)
        }
        return [GridItem(.adaptive(minimum: 200), spacing: Tokens.Space.s3)]
    }

    private var libraries: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            SectionHead(title: "Your libraries", action: "Manage", route: isAdmin ? .page("/settings/libraries") : nil)
            LazyVGrid(columns: libraryColumns, spacing: metrics.cardWidth <= 104 ? Tokens.Space.s2 : Tokens.Space.s3) {
                ForEach(model.libraries) { library in
                    NavigationLink(value: libraryRoute(library)) { LibraryTile(library: library) }
                        .buttonStyle(PressStyle())
                }
            }
        }
        .padding(.horizontal, metrics.gutter)
    }

    @ViewBuilder private func page(_ home: Home, top: CGFloat, height: CGFloat) -> some View {
        let heroes = heroes(home)
        let rows = HomeRows.rows(home, recommended: recommended)
        let jump = rows.first { $0.key == HomeRows.jumpBackIn }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollTop()
                if heroes.isEmpty {
                    Color.clear.frame(height: top + 44 + Tokens.Space.s4)
                } else {
                    HomeHero(items: heroes, top: top, height: height)
                        .padding(.bottom, 28)
                }
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !model.notice.isEmpty {
                        ProblemLine(model.notice).padding(.horizontal, metrics.gutter)
                    }
                    if !model.libraries.isEmpty { libraries }
                    if let jump { HubPageRow(hub: jump, focus: $focused) }
                    if !onNow.isEmpty { OnNowPageRow(channels: onNow) }
                    ForEach(rows.filter { $0.key != HomeRows.jumpBackIn }) { HubPageRow(hub: $0, focus: $focused) }
                    if heroes.isEmpty, rows.isEmpty, model.libraries.isEmpty {
                        EmptyState(icon: "film", title: "Nothing here yet", detail: "Add a library on the server, or ask whoever runs it.")
                    }
                }
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .stripSolidity($solid)
        .refreshable { await load() }
    }

    var body: some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            let height = HomeHero.height(for: outer.size, top: top, compact: metrics.cardWidth <= 104)
            ZStack(alignment: .top) {
                if let home {
                    page(home, top: top, height: height)
                } else if !error.isEmpty {
                    ProblemView(words: error, retry: { Task { await load() } })
                        .padding(.top, top + 44)
                } else {
                    HomeSkeleton(top: top, height: height)
                }
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                if let home, !heroes(home).isEmpty { StripScrim(top: top).opacity(1 - solid).ignoresSafeArea(edges: .top) }
            }
        }
        // On the reader, which keeps to the safe area, so the strip sits under the clock and not behind it.
        .overlay(alignment: .top) { LibraryStrip(current: nil, solid: solid, overPicture: home.map { !heroes($0).isEmpty } ?? false) }
        .pageBackground(palette)
        // Again on every return, as what's "Jump back in" has probably just changed.
        .task { await load() }
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

/// Grey shapes where Home is coming: the hero, the libraries and a row.
private struct HomeSkeleton: View {
    @Environment(\.metrics) private var metrics
    let top: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SkeletonShape(radius: 0).frame(height: height)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                SkeletonShape(radius: Tokens.Radius.sm).frame(width: 150, height: 22)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s2), count: 2), spacing: Tokens.Space.s2) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonShape(radius: Tokens.Radius.lg).frame(height: 64) }
                }
            }
            .padding(.horizontal, metrics.gutter)
            SkeletonRow()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// The featured titles: the backdrop the full width under the strip, darkened from the bottom, with the title,
/// its facts, two lines of what it's about, and Play and Details. It moves on every 8 s, and not at all with
/// Reduce Motion or once paused.
struct HomeHero: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [Item]
    /// The room the clock takes, which the picture runs under.
    let top: CGFloat
    let height: CGFloat
    @State private var index = 0
    @State private var paused = false

    /// 536 on a phone, about two-thirds of it; 62% of a bigger screen's height, between 400 and 660.
    static func height(for size: CGSize, top: CGFloat, compact: Bool) -> CGFloat {
        let screen = size.height + top
        if compact { return min(536, max(screen * 0.95, 380)) }
        return min(max(screen * 0.62, 400), 660)
    }

    private var current: Item { items[min(index, items.count - 1)] }

    private func show(_ next: Int) {
        let wrapped = (next + items.count) % items.count
        if reduceMotion { index = wrapped } else { withAnimation(.easeInOut(duration: 0.42)) { index = wrapped } }
    }

    private var facts: String {
        var parts: [String] = []
        if let year = current.year { parts.append(String(year)) }
        if let runtime = runtimeText(current.runtimeSec) { parts.append(runtime) }
        parts += (current.genres ?? []).prefix(3)
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let item = current
        ZStack(alignment: .bottomLeading) {
            ArtImage(url: client.backdropURL(item), width: 800, blank: true)
                .id(item.id)
                .transition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
            HeroShade()
            VStack(alignment: .leading, spacing: 0) {
                Text(displayTitle(item))
                    .pageFont(.display)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !facts.isEmpty {
                    Text(facts).pageFont(.body).foregroundStyle(palette.textSecondary).lineLimit(2).padding(.top, Tokens.Space.s2)
                }
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview).pageFont(.body).foregroundStyle(palette.textSecondary).lineLimit(2).padding(.top, Tokens.Space.s3)
                }
                HStack(spacing: Tokens.Space.s2) {
                    PlayOrOpen(item: item, route: playRoute(for: item)) {
                        Label(item.resumeSeconds == nil ? "Play" : "Resume", systemImage: "play.fill")
                    }
                    .pageButton(.primary)
                    .accessibilityLabel("\(item.resumeSeconds == nil ? "Play" : "Resume") \(displayTitle(item))")
                    NavigationLink(value: route(for: item)) {
                        Label("Details", systemImage: "info.circle")
                    }
                    .pageButton(.ghost)
                    .accessibilityLabel("Details of \(displayTitle(item))")
                }
                .padding(.top, Tokens.Space.s5)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, Tokens.Space.s6)
        }
        .frame(height: height)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if items.count > 1 { dots.padding(.top, top + 44 + Tokens.Space.s2).padding(.trailing, metrics.gutter - 4) }
        }
        .contentShape(Rectangle())
        #if !os(tvOS)
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard items.count > 1, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                show(index + (value.translation.width < 0 ? 1 : -1))
            }
        )
        #endif
        .task(id: "\(index)|\(paused)|\(reduceMotion)") {
            guard items.count > 1, !paused, !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { show(index + 1) }
        }
    }

    /// Pause, then a dot for each title, the current one longer. Each is a 24 target.
    private var dots: some View {
        HStack(spacing: 2) {
            if !reduceMotion {
                Button {
                    paused.toggle()
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, Tokens.Space.s1)
                .accessibilityLabel(paused ? "Start turning the featured titles" : "Stop turning the featured titles")
            }
            ForEach(items.indices, id: \.self) { place in
                let here = place == index
                Button {
                    show(place)
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
        .shadow(color: palette.background.opacity(0.6), radius: 4)
    }
}
