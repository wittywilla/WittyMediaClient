import SwiftUI
import WittyKit

// Home, libraries, shows and items, laid out as the Android app's BrowseScreens.kt: posters to swipe
// through at the top of Home with a Play pill, the libraries as pills, rows of poster cards, and item
// and show pages over their picture, dimmed and fading into the page.

func runtimeText(_ seconds: Double?) -> String? {
    guard let seconds, seconds > 0 else { return nil }
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600 + 30) / 60
    return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
}

/// One line of facts about something, with the dots only between what's there.
func factLine(_ item: Item) -> String {
    var facts: [String] = []
    if let year = item.year { facts.append(String(year)) }
    if let runtime = runtimeText(item.runtimeSec) { facts.append(runtime) }
    if let rating = item.contentRating, !rating.isEmpty { facts.append(rating) }
    return facts.joined(separator: " · ")
}

func displayTitle(_ item: Item) -> String {
    (item.showTitle?.isEmpty == false ? item.showTitle : nil) ?? item.title
}

/// Where choosing something goes: this app's own screen where it has one, and otherwise the server's
/// page, or on Apple TV what it can do.
func route(for item: Item) -> Route {
    // A disc has this app's own page, with Play and its menus, as the website's item page has.
    if item.isPlayable || item.isRigGame || item.isDisc { return .item(item.id) }
    // A song or a chapter opens its album or book, as on Android.
    if item.isAudio, let library = item.libraryId { return .listeningAlbum(library: library, album: item.album ?? "", artist: item.albumArtistName) }
    #if os(tvOS)
    if item.isServerGame { return .game(item.id) }
    if item.isPhoto, let library = item.libraryId { return .photo(library: library, id: item.id) }
    return .item(item.id)
    #else
    return .page(ServerPages.path(item))
    #endif
}

/// What Play does from Home: plays a film or an episode, and opens anything else where it's played.
func playRoute(for item: Item) -> Route {
    if item.isPlayable { return .player(item.id, startOver: item.resumeSeconds == nil) }
    return route(for: item)
}

/// A library's own page in this app, or the server's page for the kinds this app doesn't show itself.
func libraryRoute(_ library: Library) -> Route {
    #if os(tvOS)
    return .library(library)
    #else
    return library.opensHere || library.hasListeningScreens ? .library(library) : .page(ServerPages.path(library))
    #endif
}

private func route(for library: Library) -> Route { libraryRoute(library) }

// MARK: - Cards

/// Android's PosterCard: the picture with its corners rounded and how far through it is, then the
/// title and what's under it. All one thing to a screen reader. In a grid it takes the column's width.
struct Tile: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let subtitle: String
    let url: URL?
    let route: Route
    var progress: Double?
    /// Width over height: 2:3 for a poster, square for music.
    var aspect: CGFloat = 2.0 / 3.0
    /// The row's card width, or nil to fill a grid's column.
    var width: CGFloat?
    /// The plates on its picture, on a phone or a tablet.
    var badges: [CardBadge] = []
    var titleLines = 2
    let focus: FocusState<String?>.Binding
    let focusKey: String

    private var spokenValue: String {
        let watched = progress.map { ["\(Int($0 * 100)) percent watched"] } ?? []
        return (badges.map(\.spoken) + watched).joined(separator: ", ")
    }

    var body: some View {
        NavigationLink(value: route) {
            if metrics.tv {
                tvCard
            } else {
                PosterCard(title: title, subtitle: subtitle, url: url, progress: progress, aspect: aspect, width: width,
                           badges: badges, titleLines: titleLines)
            }
        }
        .tileStyle()
        .focused(focus, equals: focusKey)
        .accessibilityLabel(subtitle.isEmpty ? title : "\(title), \(subtitle)")
        .accessibilityValue(spokenValue)
    }

    /// Apple TV's card, as it was.
    private var tvCard: some View {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                ArtImage(url: url, width: width ?? metrics.cardWidth, placeholder: title)
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        if let progress { ProgressStrip(fraction: progress).padding(Tokens.Space.s1) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                Text(title)
                    .font(.wmCard)
                    .foregroundStyle(palette.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, Tokens.Space.s1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.wmCardSub)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .padding(.horizontal, Tokens.Space.s1)
                }
            }
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// The website's `--card-wide-w`: 232 on a phone, 260 wider.
func wideCardWidth(_ metrics: Metrics) -> CGFloat { metrics.cardWidth <= 104 ? 232 : 260 }

/// On a phone or a tablet, the website's ItemCard (web/src/components/common.tsx): episodes as wide stills with their
/// show's name, songs and CDs square, and the plates for a disc and for watched.
struct ItemTile: View {
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let item: Item
    var inRow = true
    /// Pictures and creator videos are wide; a poster's shape would crop them (on a phone or tablet).
    var wide = false
    let focus: FocusState<String?>.Binding

    var body: some View {
        if metrics.tv {
            Tile(title: item.cardTitle, subtitle: item.cardSubtitle, url: client.posterURL(item), route: route(for: item),
                 progress: item.progressFraction, aspect: item.isAudio ? 1 : 2.0 / 3.0,
                 width: inRow ? metrics.cardWidth : nil, focus: focus, focusKey: "item\(item.id)")
        } else {
            let look = CardLook.item(item, wide: wide || item.showId != nil)
            Tile(title: look.title, subtitle: look.subtitle, url: client.posterURL(item), route: route(for: item),
                 progress: look.progress, aspect: look.shape.aspect,
                 width: inRow ? (look.shape == .wide ? wideCardWidth(metrics) : metrics.cardWidth) : nil,
                 badges: look.badges, titleLines: look.shape == .wide ? 1 : 2, focus: focus, focusKey: "item\(item.id)")
        }
    }
}

/// On a phone or a tablet, the website's ShowCard: "2019 · 3 seasons", with how many episodes are left or a tick.
struct ShowTile: View {
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics
    let show: Show
    var inRow = true
    let focus: FocusState<String?>.Binding

    private var tvSubtitle: String {
        if let unwatched = show.unwatched, unwatched > 0 { return "\(unwatched) unwatched" }
        return show.year.map(String.init) ?? ""
    }

    var body: some View {
        if metrics.tv {
            Tile(title: show.title, subtitle: tvSubtitle, url: client.posterURL(show), route: .show(show.id),
                 width: inRow ? metrics.cardWidth : nil, focus: focus, focusKey: "show\(show.id)")
        } else {
            let look = CardLook.show(show)
            Tile(title: look.title, subtitle: look.subtitle, url: client.posterURL(show), route: .show(show.id),
                 width: inRow ? metrics.cardWidth : nil, badges: look.badges, focus: focus, focusKey: "show\(show.id)")
        }
    }
}

extension CardShape {
    /// Width over height.
    var aspect: CGFloat {
        switch self {
        case .poster: return 2.0 / 3.0
        case .wide: return 16.0 / 9.0
        case .square: return 1
        }
    }
}

/// Posters to fill the width. A card can be a little narrower than in a row: three fit across a phone.
/// What it's given has already had repeats removed.
struct CardGrid: View {
    @Environment(\.metrics) private var metrics
    let items: [Item]
    let shows: [Show]
    let focus: FocusState<String?>.Binding
    var onLast: (() async -> Void)?

    var body: some View {
        LazyVGrid(columns: metrics.tv ? [GridItem(.adaptive(minimum: metrics.cardWidth - Tokens.Space.s3), spacing: Tokens.Space.s2, alignment: .top)]
                                      : posterColumns(metrics),
                  alignment: .leading, spacing: metrics.tv ? Tokens.Space.s4 : Tokens.Space.s6) {
            ForEach(shows) { ShowTile(show: $0, inRow: false, focus: focus) }
            ForEach(ServerPages.albumsOnce(items)) { item in
                ItemTile(item: item, inRow: false, focus: focus).task {
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
    @Environment(\.metrics) private var metrics
    let hub: Hub
    let focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            SectionTitle(hub.title).padding(.horizontal, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s3) {
                    ForEach(ServerPages.albumsOnce(uniqued(hub.items ?? []))) { ItemTile(item: $0, focus: focus) }
                    ForEach(uniqued(hub.shows ?? [])) { ShowTile(show: $0, focus: focus) }
                }
                .padding(.horizontal, metrics.gutter)
                .padding(.vertical, metrics.tv ? Tokens.focusRoom : Tokens.Space.s1)
            }
            .remoteSection()
        }
    }
}

/// The libraries as pills along the top, each opening its own screen, then the guide, collections and
/// game PCs where there are any, as on Android.
private struct LibraryPills: View {
    @Environment(\.metrics) private var metrics
    let libraries: [Library]
    var guide = false
    var gamePCs = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(libraries) { library in
                    NavigationLink(library.name, value: route(for: library)).action(pill: true)
                }
                #if os(tvOS)
                if guide { NavigationLink("TV guide", value: Route.guide).action(pill: true) }
                #else
                if guide { NavigationLink("TV guide", value: Route.page(ServerPages.guide)).action(pill: true) }
                NavigationLink("Collections", value: Route.page(ServerPages.collections)).action(pill: true)
                if gamePCs { NavigationLink("Game PCs", value: Route.web(WebPlayer.gamePCsPath)).action(pill: true) }
                #endif
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, metrics.tv ? Tokens.focusRoom : Tokens.Space.s1)
        }
        .remoteSection()
    }
}

/// What's on the channels right now, as on the server's own Home. Choosing one watches it.
struct OnNowRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let channels: [GuideChannel]

    private func route(_ channel: GuideChannel) -> Route {
        #if os(tvOS)
        return .channel(key: channel.key)
        #else
        return .page("/tv/watch/\(WittyClient.pathPart(channel.key))")
        #endif
    }

    var body: some View {
        let now = Int64(Date().timeIntervalSince1970)
        let width = metrics.cardWidth * 1.5
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            SectionTitle("On TV now").padding(.horizontal, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s3) {
                    ForEach(channels) { channel in
                        let on = channel.on(at: now)
                        let words = on?.title ?? "Nothing listed"
                        NavigationLink(value: route(channel)) {
                            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                                RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                                    .fill(palette.card)
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                    .overlay(alignment: .topLeading) {
                                        if let number = channel.number, !number.isEmpty {
                                            Text(number)
                                                .font(.wmLabel)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, Tokens.Space.s1)
                                                .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs).fill(.black.opacity(0.6)))
                                                .padding(Tokens.Space.s2)
                                        }
                                    }
                                    .overlay(alignment: .center) {
                                        Image(systemName: channel.radio == true ? "radio" : "tv")
                                            .font(.title2)
                                            .foregroundStyle(palette.textHint)
                                    }
                                    .overlay(alignment: .bottom) {
                                        if let on { ProgressStrip(fraction: on.fraction(at: now)).padding(Tokens.Space.s1) }
                                    }
                                Text(words).font(.wmCard).foregroundStyle(palette.text).lineLimit(2).padding(.horizontal, Tokens.Space.s1)
                                Text(channel.name + (on.map { " · \($0.minutesLeft(at: now)) min left" } ?? ""))
                                    .font(.wmCardSub).foregroundStyle(palette.textSecondary).lineLimit(1)
                                    .padding(.horizontal, Tokens.Space.s1)
                            }
                            .frame(width: width, alignment: .leading)
                        }
                        .tileStyle()
                        .accessibilityLabel("Channel \(channel.label): \(words)")
                    }
                }
                .padding(.horizontal, metrics.gutter)
                .padding(.vertical, metrics.tv ? Tokens.focusRoom : Tokens.Space.s1)
            }
            .remoteSection()
        }
    }
}

// MARK: - The top of Home

/// On a TV: the picture across the top with the title, its facts and Play beside it.
private struct WideHero: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let item: Item
    let scope: Namespace.ID
    /// The room the clock and battery take at the top, which the picture runs under.
    var clock: CGFloat = 0

    private var height: CGFloat {
        if metrics.tv { return Tokens.heroHeight }
        #if os(iOS) || os(visionOS)
        return sizeClass == .regular ? 340 : 260
        #else
        return 340
        #endif
    }

    var body: some View {
        // On a TV the words may take up to half the screen, and a long title wraps to three lines before it
        // shrinks, to three quarters at most; the hero grows to fit them (docs/APP-DESIGN.md, On a TV).
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(displayTitle(item))
                .font(.wmDisplay)
                .foregroundStyle(palette.text)
                .lineLimit(metrics.tv ? 3 : 2)
                .minimumScaleFactor(metrics.tv ? 0.75 : 1)
                .accessibilityAddTraits(.isHeader)
            Secondary([item.year.map(String.init), item.genres?.first, item.contentRating].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            if let overview = item.overview, !overview.isEmpty { Secondary(overview, lines: 2) }
            HStack(spacing: Tokens.Space.s3) {
                PlayOrOpen(item: item, route: playRoute(for: item)) {
                    Label(item.resumeSeconds == nil ? "Play" : "Resume", systemImage: "play.fill")
                }
                .mainAction()
                .firstFocus(in: scope)
                .accessibilityLabel("\(item.resumeSeconds == nil ? "Play" : "Resume") \(displayTitle(item))")
                NavigationLink("More", value: route(for: item)).action(pill: true)
                    .accessibilityLabel("More about \(displayTitle(item))")
            }
            .padding(.top, Tokens.Space.s1)
            .remoteSection()
        }
        .frame(maxWidth: Tokens.heroTextWidth, alignment: .leading)
        .padding(.horizontal, metrics.gutter)
        .padding(.top, clock)
        .padding(.vertical, metrics.tv ? Tokens.Space.s6 : 0)
        .frame(maxWidth: .infinity, minHeight: height + clock, alignment: .leading)
        .background {
            ArtImage(url: client.backdropURL(item), width: 1280, blank: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.5)
                .clipped()
                .overlay(LinearGradient(stops: [.init(color: palette.background, location: 0), .init(color: .clear, location: 0.75)],
                                        startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.6), .init(color: palette.background, location: 1)],
                                        startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Home

/// Home: the website's on a phone and a tablet, and Apple TV's own, which its sessions look after.
struct HomeView: View {
    @Environment(\.metrics) private var metrics

    var body: some View {
        if metrics.tv { TvHomeView() } else { PhoneHome() }
    }
}

private struct TvHomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var home: Home?
    @State private var error = ""
    @State private var gamePCs = false
    @State private var onNow: [GuideChannel] = []
    #if DEBUG
    /// For checking the hero with a title of one's choosing on a simulator: `-WittyHomeHero <item id>` at launch
    /// puts that item first, whatever the server features.
    @State private var pinnedHero: Item?
    #endif
    @FocusState private var focused: String?
    /// What had focus when this screen was left. Coming back puts it there.
    @State private var lastFocused: String?
    @Namespace private var scope

    /// Featured first, and otherwise whatever someone was in the middle of. Apple TV can only start
    /// what it can play itself.
    private func heroes(_ home: Home) -> [Item] {
        let hubs = (home.hubs ?? []).filter { !$0.isEmpty }
        let pool = (home.featured ?? []).isEmpty ? (hubs.first?.items ?? []) : (home.featured ?? [])
        var list = ServerPages.albumsOnce(uniqued(pool))
        #if os(tvOS)
        list = list.filter(\.isPlayable)
        #endif
        #if DEBUG
        if let pinnedHero { list.insert(pinnedHero, at: 0) }
        #endif
        return Array(list.prefix(8))
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
        #if os(iOS) || os(visionOS)
        gamePCs = (try? await client.couchStatus())?.allowed == true
        #endif
        let guide = try? await client.guide()
        let channels = uniqued(guide?.channels ?? [])
        model.channels = channels
        #if os(tvOS)
        if let guide { await model.learnTvLook(from: guide, client: client) }
        #endif
        onNow = channels.filter(\.canTune)
        #if DEBUG
        let pin = UserDefaults.standard.integer(forKey: "WittyHomeHero")
        if pin > 0, pinnedHero == nil { pinnedHero = try? await client.item(Int64(pin)) }
        #endif
    }

    @ViewBuilder private func page(_ home: Home) -> some View {
        let heroes = heroes(home)
        let hubs = uniqued(home.hubs ?? []).filter { !$0.isEmpty }
        // The picture at the top runs up under the clock, as on Android, so the page itself does too
        // and keeps the clock's room in its own spacing.
        GeometryReader { outer in
        let clock = outer.safeAreaInsets.top
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Space.s5) {
                if let first = heroes.first {
                    WideHero(item: first, scope: scope, clock: clock)
                }
                if !model.notice.isEmpty {
                    ProblemLine(model.notice).padding(.horizontal, metrics.gutter)
                }
                LibraryPills(libraries: model.libraries, guide: !model.channels.isEmpty, gamePCs: gamePCs)
                if !onNow.isEmpty { OnNowRow(channels: onNow) }
                ForEach(hubs) { HubRow(hub: $0, focus: $focused) }
                if heroes.isEmpty, hubs.isEmpty {
                    EmptyMessage(title: "Nothing here yet", detail: "Add a library on the server, or ask whoever runs it.")
                }
            }
            .padding(.top, heroes.isEmpty ? clock + Tokens.Space.s4 : 0)
            .padding(.bottom, Tokens.Space.s6)
        }
        .ignoresSafeArea(edges: .top)
        .focusRoot(scope)
        }
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

// MARK: - Libraries

/// One library's cards. Grows as it's scrolled.
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

    private var opens: Bool {
        #if os(tvOS)
        return library.opensOnAppleTV
        #else
        return library.opensHere
        #endif
    }

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
        ZStack(alignment: .topLeading) {
            if !opens {
                BrowserOnlyNote(library: library)
            } else if !error.isEmpty, total == nil {
                ProblemView(words: error, retry: { error = ""; Task { await loadMore() } })
            } else if total == nil {
                LoadingView()
            } else if total == 0 {
                Secondary("Nothing here yet. Once the server has finished looking through its files, they'll be here.")
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    CardGrid(items: items, shows: shows, focus: $focused, onLast: {
                        if items.count < (total ?? 0) { await loadMore() }
                    })
                    if !error.isEmpty {
                        ProblemLine(error)
                        Button("Try again") { error = ""; Task { await loadMore() } }.action()
                    }
                }
            }
        }
        .task { if opens, total == nil { await loadMore() } }
    }
}

/// A library as a screen of its own: the website's library page on a phone and a tablet, Apple TV's own there.
struct LibraryView: View {
    @Environment(\.metrics) private var metrics
    let library: Library
    var start = LibraryState()

    var body: some View {
        if metrics.tv { TvLibraryView(library: library) } else { LibraryPage(library: library, start: start) }
    }
}

/// Apple TV's: its name, and its posters filling the width.
private struct TvLibraryView: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Heading(library.name)
                LibraryContent(library: library)
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, Tokens.Space.s4)
            .padding(.bottom, Tokens.Space.s6)
        }
        .pageBackground(palette)
    }
}

// MARK: - Shows

struct ShowView: View {
    @Environment(\.metrics) private var metrics
    let id: Int64

    var body: some View {
        if metrics.tv { TvShowView(id: id) } else { ShowPage(id: id) }
    }
}

private struct TvShowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
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

    /// An episode: its picture, its number and title, how long it is and how far through.
    private func episodeRow(_ episode: Item) -> some View {
        let watched = episode.progress?.watched == true
        let facts = [runtimeText(episode.runtimeSec), watched ? "Watched" : nil].compactMap { $0 }.joined(separator: " · ")
        let pictureWidth: CGFloat = metrics.tv ? 240 : 120
        return NavigationLink(value: Route.item(episode.id)) {
            HStack(spacing: Tokens.Space.s3) {
                ArtImage(url: client.posterURL(episode), width: pictureWidth, placeholder: episode.episodeLabel)
                    .frame(width: pictureWidth, height: pictureWidth * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text("\(episode.episodeLabel)  \(episode.title)")
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !facts.isEmpty { Secondary(facts, lines: 1) }
                    if let fraction = episode.progressFraction {
                        ProgressStrip(fraction: fraction, track: palette.border).padding(.top, Tokens.Space.s1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SurfaceStyle(fill: palette.panel))
        .accessibilityLabel("\(episode.episodeLabel), \(episode.title)")
        .accessibilityValue(watched ? "Watched" : (episode.progressFraction.map { "\(Int($0 * 100)) percent watched" } ?? ""))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let detail {
                let selected = season ?? detail.seasons?.first?.number
                // The picture behind, fading into the page, as on an item.
                PageBackdrop(url: client.backdropURL(detail.show)).ignoresSafeArea(edges: .top)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        Heading(detail.show.title)
                        if let overview = detail.show.overview, !overview.isEmpty {
                            Secondary(overview, lines: 4)
                        }
                        if !error.isEmpty { ProblemLine(error) }
                        if let next = detail.nextUpId {
                            let label = (detail.episodes ?? []).first { $0.id == next }?.episodeLabel ?? ""
                            NavigationLink(value: Route.item(next)) {
                                Label(label.isEmpty ? "Next up" : "Next up: \(label)", systemImage: "play.fill")
                            }
                            .mainAction()
                            .firstFocus(in: scope)
                            .padding(.vertical, Tokens.Space.s1)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Tokens.Space.s2) {
                                ForEach(uniqued(detail.seasons ?? [])) { s in
                                    Button(s.displayTitle) { season = s.number }
                                        .action(selected: s.number == selected, pill: true)
                                        .firstFocus(in: scope, when: detail.nextUpId == nil && s.number == selected)
                                }
                            }
                            .padding(.vertical, metrics.tv ? Tokens.focusRoom : Tokens.Space.s1)
                        }
                        .remoteSection()
                        ForEach(uniqued(detail.episodes ?? []).filter { $0.season == selected }) { episodeRow($0) }
                    }
                    .padding(.horizontal, metrics.gutter)
                    .padding(.top, Tokens.Space.s4)
                    .padding(.bottom, Tokens.Space.s6)
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

// MARK: - Items

struct ItemView: View {
    @Environment(\.metrics) private var metrics
    let id: Int64

    var body: some View {
        if metrics.tv { TvItemView(id: id) } else { ItemPage(id: id) }
    }
}

private struct TvItemView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    let id: Int64
    @State private var item: Item?
    @State private var error = ""
    @Namespace private var scope

    /// The poster above the words on a phone held upright, beside them where there's room.
    private var upright: Bool {
        #if os(iOS) || os(visionOS)
        return sizeClass == .compact
        #else
        return false
        #endif
    }

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
            if let tagline = item.tagline, !tagline.isEmpty { Secondary(tagline) }
            RigPlayPanel(item: item)
        } else if item.isPlayable {
            // The server decides where Resume goes; nothing to resume means start at the beginning.
            HStack(spacing: Tokens.Space.s3) {
                if let resume = item.resumeSeconds {
                    NavigationLink(value: Route.player(item.id, startOver: false)) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .mainAction()
                    .firstFocus(in: scope)
                    .accessibilityLabel("Resume from \(runtimeText(resume) ?? "where you stopped")")
                    NavigationLink("Start over", value: Route.player(item.id, startOver: true)).action(pill: true)
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
            #if os(iOS) || os(visionOS)
            NavigationLink(value: Route.page(ServerPages.path(item))) {
                Label("Open", systemImage: "play.fill")
            }
            .mainAction()
            #else
            ElsewhereNote(path: ServerPages.path(item))
            #endif
        }
    }

    @ViewBuilder private func words(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if let show = item.showTitle, !show.isEmpty {
                Secondary("\(show) · \(item.episodeLabel)")
            }
            Heading(item.title)
            let facts = factLine(item)
            if !facts.isEmpty { Secondary(facts) }
            if let genres = item.genres, !genres.isEmpty { Secondary(genres.joined(separator: ", ")) }
            if !error.isEmpty { ProblemLine(error) }
            actions(item)
            if let overview = item.overview, !overview.isEmpty {
                Text(overview).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let item {
                let posterWidth = metrics.cardWidth * 1.4
                let poster = ArtImage(url: client.posterURL(item), width: posterWidth, placeholder: item.title)
                    .frame(width: posterWidth, height: posterWidth * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
                    .accessibilityHidden(true)
                // The page runs up under the bar and the clock, as on Android, so its picture can.
                GeometryReader { outer in
                    let top = outer.safeAreaInsets.top
                    ScrollView {
                        Group {
                            if upright {
                                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                                    poster.frame(maxWidth: .infinity)
                                    words(item)
                                }
                            } else {
                                HStack(alignment: .top, spacing: Tokens.Space.s6) {
                                    poster
                                    words(item).frame(minWidth: 280, maxWidth: 640, alignment: .leading)
                                }
                            }
                        }
                        .padding(.horizontal, metrics.gutter)
                        .padding(.top, top + Tokens.Space.s6)
                        .padding(.bottom, Tokens.Space.s6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The picture behind, fading into the page, as on Home. It scrolls with the page.
                        .background(alignment: .top) { PageBackdrop(url: client.backdropURL(item), height: 340 + top) }
                    }
                    .ignoresSafeArea(edges: .top)
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
