#if os(tvOS)
import SwiftUI
import UIKit
import WittyKit

// WittyPlay's games on Apple TV, laid out as the website's couch mode (/big): covers at the top,
// one at the front and the others turned away on a shiny floor, tinted by the cover's colour;
// then what's being played, the consoles, the shelves and every game. A game's page has its box,
// a big Play, where you left off, and how it plays. Colours come from the theme, so every theme
// and every WittyTV look works here as anywhere else.

// MARK: - Covers and their colour

/// A cover's main colour, from a very small copy of it: the colourful parts count for more, so a
/// white box with a red logo reads as red. Deep on a dark theme, pale on a light one.
@MainActor
final class CoverTints {
    static let shared = CoverTints()
    private var known: [URL: (h: Double, s: Double)?] = [:]

    func tint(_ url: URL?, client: WittyClient, dark: Bool) async -> Color? {
        guard let url else { return nil }
        let hs: (h: Double, s: Double)?
        if let cached = known[url] {
            hs = cached
        } else {
            guard let data = try? await client.imageData(url) else { return nil }
            hs = await Task.detached(priority: .utility) { Self.average(data) }.value
            known[url] = hs
        }
        guard let hs else { return nil }
        return dark ? Color(hue: hs.h, saturation: min(hs.s, 0.62), brightness: 0.42).opacity(1)
                    : Color(hue: hs.h, saturation: min(hs.s, 0.5), brightness: 0.95)
    }

    nonisolated static func average(_ data: Data) -> (h: Double, s: Double)? {
        guard let image = decodeArt(data, maxPixels: 32) else { return nil }
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        var r = 0.0, g = 0.0, b = 0.0, w = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let R = Double(pixels[i]), G = Double(pixels[i + 1]), B = Double(pixels[i + 2])
            let weight = 1 + ((max(R, G, B) - min(R, G, B)) / 255) * 6
            r += R * weight
            g += G * weight
            b += B * weight
            w += weight
        }
        guard w > 0 else { return nil }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: r / w / 255, green: g / w / 255, blue: b / w / 255, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (Double(hue), Double(saturation))
    }
}

extension Palette {
    /// Whether the page is dark, which decides how a cover's colour is used behind it.
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(background).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5
    }
}

/// The colour behind the top of the page, faded from one cover's colour to the next.
private struct Ambient: View {
    @Environment(\.palette) private var palette
    let colour: Color?
    var height: CGFloat = 900

    var body: some View {
        LinearGradient(colors: [colour ?? palette.panel, palette.background], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.4), value: colour)
            .accessibilityHidden(true)
    }
}

/// A box as it is, whatever its shape, standing on the bottom of its space.
private struct BoxArt: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let game: GameItem
    let console: GameConsole?
    let width: CGFloat

    var body: some View {
        Group {
            if game.hasPoster {
                ArtImage(url: client.gamePosterURL(game, width: Int(width * 2)), width: width, fit: true, blank: true)
            } else {
                // A game with no picture gets one made from its title and console, as on the website.
                ZStack {
                    LinearGradient(colors: [palette.card, palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: Tokens.Space.s2) {
                        Text(game.title).font(.headline).multilineTextAlignment(.center).lineLimit(4)
                        if let short = console?.shortName { Text(short).font(.caption).foregroundStyle(palette.textSecondary) }
                    }
                    .foregroundStyle(palette.text)
                    .padding(Tokens.Space.s3)
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
            }
        }
        .frame(width: width, height: width * 4 / 3, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private func gameSubtitle(_ game: GameItem, _ console: GameConsole?) -> String {
    [console?.shortName, game.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
}

/// A game's card: its box, its name, its console and year.
struct GameCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let game: GameItem
    let console: GameConsole?
    var favourite = false
    var width: CGFloat?

    var body: some View {
        let w = width ?? metrics.cardWidth
        NavigationLink(value: Route.game(game.id)) {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                BoxArt(game: game, console: console, width: w)
                    .overlay(alignment: .topTrailing) {
                        if favourite {
                            Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                                .padding(Tokens.Space.s1).background(Circle().fill(.black.opacity(0.5))).padding(Tokens.Space.s1)
                        }
                    }
                Text(game.title).font(.wmCard).foregroundStyle(palette.text).lineLimit(1)
                HStack(spacing: Tokens.Space.s1) {
                    if let rating = game.rating {
                        Image(systemName: "star.fill").font(.caption2)
                        Text(String(format: "%.1f", rating))
                    }
                    Text(gameSubtitle(game, console))
                }
                .font(.wmCardSub)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            }
            .frame(width: w, alignment: .leading)
        }
        .buttonStyle(.card)
        .accessibilityLabel([game.title, console?.shortName, game.year.map(String.init), favourite ? "Favourite" : nil].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - The covers at the top

/// One cover at the front, the others turned away on either side, standing on a shiny floor. It's
/// one stop for the focus: left and right go along it, up and down leave it, select opens the game.
private struct CoverFlow: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let games: [GameItem]
    let consoles: [String: GameConsole]
    @Binding var index: Int
    let open: (GameItem) -> Void
    @FocusState private var focused: Bool
    private let height: CGFloat = 420
    private let near = 4

    private func place(_ d: Int) -> (x: CGFloat, turn: Double, back: CGFloat, dim: Double) {
        let a = abs(d), side = d == 0 ? 0 : (d > 0 ? 1.0 : -1.0)
        return (x: CGFloat(side * (0.74 + Double(max(0, a - 1)) * 0.3)), turn: -side * (a == 0 ? 0 : 58),
                back: a == 0 ? 0 : 0.5 + CGFloat(a) * 0.08, dim: a == 0 ? 0 : min(0.62, 0.3 + Double(a) * 0.08))
    }

    var body: some View {
        let first = max(0, index - near), last = min(games.count - 1, index + near)
        Button {
            if games.indices.contains(index) { open(games[index]) }
        } label: {
            ZStack(alignment: .bottom) {
                if first <= last {
                    ForEach(first...last, id: \.self) { i in
                        let d = i - index, p = place(d), a = abs(d)
                        let game = games[i]
                        VStack(spacing: 2) {
                            BoxArt(game: game, console: consoles[game.console ?? ""], width: height * 0.75)
                                .overlay(palette.background.opacity(p.dim))
                                .overlay {
                                    if d == 0 && focused {
                                        RoundedRectangle(cornerRadius: Tokens.Radius.sm + 6).strokeBorder(palette.text, lineWidth: 5).padding(-8)
                                    }
                                }
                                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                            if a <= 2 {
                                // The floor's reflection.
                                BoxArt(game: game, console: consoles[game.console ?? ""], width: height * 0.75)
                                    .scaleEffect(x: 1, y: -1)
                                    .frame(height: height * 0.3, alignment: .top)
                                    .clipped()
                                    .mask(LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
                                    .opacity(1 - p.dim)
                            }
                        }
                        .frame(height: height * 1.3, alignment: .top)
                        .rotation3DEffect(.degrees(p.turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .scaleEffect(1 - p.back * 0.42)
                        .offset(x: p.x * height)
                        .zIndex(Double(9 - a))
                        .opacity(a > near - 1 ? 0 : 1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height * 1.3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: index)
        }
        .buttonStyle(FlowButton())
        .focused($focused)
        .onMoveCommand { direction in
            switch direction {
            case .left: if index > 0 { index -= 1 }
            case .right: if index < games.count - 1 { index += 1 }
            default: break
            }
        }
        .accessibilityLabel(games.indices.contains(index) ? "\(games[index].title), \(index + 1) of \(games.count). Open" : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if index < games.count - 1 { index += 1 }
            case .decrement: if index > 0 { index -= 1 }
            @unknown default: break
            }
        }
    }
}

/// The covers draw their own ring around the front one, and don't lift as a card does.
private struct FlowButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Rows

private struct ContinueCard: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let entry: GameContinue
    let console: GameConsole?

    var body: some View {
        let game = entry.item
        let ready = console?.ready ?? true
        let route: Route = ready ? .playGame(game.id, entry.save != nil ? .resume : .fresh) : .game(game.id)
        let facts = [console?.shortName, game.playedSeconds > 60 ? GameWords.played(game.playedSeconds) : nil, entry.lastPlayed.map { GameWords.ago($0) }]
            .compactMap { $0 }.joined(separator: " · ")
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ZStack(alignment: .bottomTrailing) {
                    Rectangle().fill(palette.card)
                    if let save = entry.save, save.hasThumb == true {
                        ArtImage(url: client.gameSaveThumbURL(game.id, slot: save.slot, version: save.updatedAt), width: 340, fit: true, blank: true)
                    } else if game.hasPoster {
                        ArtImage(url: client.gamePosterURL(game, width: 320), width: 340, fit: true, blank: true).opacity(0.8)
                    } else {
                        Text(game.title).font(.headline).foregroundStyle(palette.text).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Image(systemName: "play.fill")
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(palette.accent))
                        .padding(Tokens.Space.s2)
                }
                .frame(width: 340, height: 212)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                Text(game.title).font(.wmCard).foregroundStyle(palette.text).lineLimit(1)
                Text(facts).font(.wmCardSub).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            .frame(width: 340, alignment: .leading)
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(entry.save != nil ? "Resume" : "Play") \(game.title)\(console.map { ", " + $0.shortName } ?? "")\(entry.lastPlayed.map { ", last played " + GameWords.ago($0) } ?? "")")
    }
}

private struct ConsoleTile: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let console: GameConsole
    let library: Library

    var body: some View {
        let n = console.count ?? 0
        NavigationLink(value: Route.gameLibrary(library, console: console.id)) {
            VStack(spacing: Tokens.Space.s2) {
                Text(console.shortName).font(.title3.weight(.bold)).foregroundStyle(palette.text).lineLimit(2).multilineTextAlignment(.center)
                Text("\(n) \(n == 1 ? "game" : "games")\(console.ready == false && model.user?.isAdmin == true ? " · set up" : "")")
                    .font(.wmCardSub).foregroundStyle(palette.textSecondary)
            }
            .padding(Tokens.Space.s4)
            .frame(width: 260, height: 150)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        }
        .buttonStyle(.card)
        .accessibilityLabel("\(console.name): \(n) \(n == 1 ? "game" : "games")\(console.ready == false ? ", not set up yet" : "")")
    }
}

/// A row of anything, with its heading, as a focus section of its own.
private struct GameRow<Content: View>: View {
    @Environment(\.metrics) private var metrics
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            SectionTitle(title).padding(.horizontal, metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.s6) { content() }
                    .padding(.horizontal, metrics.gutter)
                    .padding(.vertical, Tokens.focusRoom)
            }
            .focusSection()
        }
    }
}

// MARK: - The library

private enum GameSort: String, CaseIterable, Identifiable {
    case popular, newest, oldest, title, rating, added
    var id: String { rawValue }
    var label: String {
        switch self {
        case .popular: return "Most popular"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .title: return "A to Z"
        case .rating: return "Highest rated"
        case .added: return "Recently added"
        }
    }
}

/// A games library, or one console's games in it.
struct GamesLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let library: Library
    let console: String?

    @State private var home: GamesHome?
    @State private var consoles: [GameConsole] = []
    @State private var hero: [GameItem] = []
    @State private var heroAt = 0
    @State private var tint: Color?
    @State private var games: [GameItem] = []
    @State private var total: Int?
    @State private var sort: GameSort = .popular
    @State private var error = ""
    @State private var loadingMore = false
    @State private var clock = Date()
    @Namespace private var scope

    private var byId: [String: GameConsole] { Dictionary(consoles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var current: GameConsole? { console.flatMap { byId[$0] } }
    private var favourites: Set<Int64> { Set(home?.favouriteIds ?? []) }
    private var present: [GameConsole] { consoles.filter { ($0.count ?? 0) > 0 }.sorted { ($0.count ?? 0) > ($1.count ?? 0) } }

    /// The most interesting in the middle, the rest spreading out on either side.
    private static func centreOut(_ list: [GameItem]) -> [GameItem] {
        var out: [GameItem] = []
        for (i, g) in list.enumerated() { if i % 2 == 1 { out.append(g) } else { out.insert(g, at: 0) } }
        return out
    }

    private func load() async {
        do {
            async let c = client.gameConsoles(library: library.id)
            if let console {
                async let page = client.games(library: library.id, console: console, sort: "popular", limit: 40)
                consoles = try await c
                let found = try await page.items ?? []
                if hero.isEmpty {
                    hero = Self.centreOut(Array(found.filter(\.hasPoster).prefix(15)))
                    heroAt = (hero.count - 1) / 2
                }
            } else {
                async let h = client.gamesHome(library: library.id)
                consoles = try await c
                let fresh = try await h
                if fresh != home { home = fresh }
                if hero.isEmpty {
                    hero = Self.centreOut(fresh.hero ?? [])
                    heroAt = (hero.count - 1) / 2
                }
            }
            if total == nil { await loadGames(reset: true) }
            error = ""
        } catch {
            let words = model.handle(error)
            if home == nil, consoles.isEmpty, !words.isEmpty { self.error = words }
        }
    }

    private func loadGames(reset: Bool) async {
        guard !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await client.games(library: library.id, console: console, sort: sort.rawValue, offset: reset ? 0 : games.count, limit: 60)
            let fresh = page.items ?? []
            let all = uniqued((reset ? [] : games) + fresh)
            let finished = !reset && all.count == games.count
            games = all
            total = finished ? games.count : (page.total ?? games.count)
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    private func updateTint() async {
        guard hero.indices.contains(heroAt) else { return }
        let game = hero[heroAt]
        guard game.hasPoster else { tint = nil; return }
        tint = await CoverTints.shared.tint(client.gamePosterURL(game, width: 64), client: client, dark: palette.isDark)
    }

    private var title: String { current?.name ?? library.name }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                if current != nil { Secondary(library.name) }
                Heading(title)
            }
            if let total { Secondary("\(total) \(total == 1 ? "game" : "games")") }
            Spacer()
            if let user = model.user { Secondary((user.displayName ?? "").isEmpty ? user.name : user.displayName!) }
            Text(clock, style: .time).font(.headline.monospacedDigit()).foregroundStyle(palette.text)
        }
        .padding(.horizontal, metrics.gutter)
    }

    @ViewBuilder private func heroInfo(_ game: GameItem) -> some View {
        let c = byId[game.console ?? ""]
        let ready = c?.ready ?? true
        let resumable = (home?.continue ?? []).contains { $0.item.id == game.id && $0.save != nil }
        VStack(spacing: Tokens.Space.s2) {
            Text(game.title).font(.wmDisplay).foregroundStyle(palette.text).multilineTextAlignment(.center).lineLimit(2)
            Secondary([c?.name, game.year.map(String.init), game.studio].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            HStack(spacing: Tokens.Space.s3) {
                if ready {
                    NavigationLink(value: Route.playGame(game.id, resumable ? .resume : .fresh)) {
                        Label(resumable ? "Resume" : "Play", systemImage: "play.fill")
                    }
                    .mainAction()
                } else {
                    NavigationLink(value: Route.game(game.id)) { Label("Needs setting up", systemImage: "gearshape") }.action(pill: true)
                }
                NavigationLink("About this game", value: Route.game(game.id)).action(pill: true)
            }
            .focusSection()
        }
        .padding(.horizontal, metrics.gutter)
        .frame(maxWidth: .infinity)
    }

    private var sortChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(GameSort.allCases) { s in
                    Button {
                        guard sort != s else { return }
                        sort = s
                        total = nil
                        Task { await loadGames(reset: true) }
                    } label: { ChipLabel(title: s.label, selected: sort == s) }
                    .buttonStyle(SurfaceStyle(radius: 999))
                }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, Tokens.Space.s2)
        }
        .focusSection()
    }

    var body: some View {
        ZStack(alignment: .top) {
            if !error.isEmpty, home == nil, consoles.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else if home == nil && console == nil || consoles.isEmpty {
                LoadingView()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s8) {
                        header
                        if let current, current.ready == false {
                            Secondary(current.unavailable ?? "This server has no core for the \(current.name) yet, so these games can't start. \(model.user?.isAdmin == true ? "Install one in Settings, Consoles & cores, on the website." : "Ask whoever runs this server to install one.")")
                                .padding(.horizontal, metrics.gutter)
                        }
                        if !hero.isEmpty {
                            VStack(spacing: Tokens.Space.s4) {
                                CoverFlow(games: hero, consoles: byId, index: $heroAt) { model.path.append(.game($0.id)) }
                                    .prefersDefaultFocus(in: scope)
                                if hero.indices.contains(heroAt) { heroInfo(hero[heroAt]) }
                            }
                        }
                        if console == nil, let home {
                            if let entries = home.continue, !entries.isEmpty {
                                GameRow(title: "Continue playing") {
                                    ForEach(entries) { ContinueCard(entry: $0, console: byId[$0.item.console ?? ""]) }
                                }
                            }
                            if !present.isEmpty {
                                GameRow(title: "Consoles") {
                                    ForEach(present) { ConsoleTile(console: $0, library: library) }
                                }
                            }
                            shelf("Recently added", home.recent)
                            shelf("Favourites", home.favourites)
                            shelf("Most played", home.mostPlayed)
                            ForEach((home.shelves ?? []).filter { $0.kind == "series" }) { shelf($0.name, $0.items) }
                            ForEach((home.shelves ?? []).filter { $0.kind == "genre" }) { shelf($0.name, $0.items) }
                        }
                        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            SectionTitle("Games").padding(.horizontal, metrics.gutter)
                            sortChips
                            if total == 0 {
                                EmptyMessage(title: "No games here yet", detail: "Put your own game files in this library's folder and scan it. Zipped games and multi-disc sets work too.")
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.cardWidth + 10), spacing: Tokens.Space.s6, alignment: .top)],
                                      alignment: .leading, spacing: Tokens.Space.s6) {
                                ForEach(games) { game in
                                    GameCard(game: game, console: byId[game.console ?? ""], favourite: favourites.contains(game.id), width: metrics.cardWidth)
                                        .task { if game.id == games.last?.id, games.count < (total ?? 0) { await loadGames(reset: false) } }
                                }
                            }
                            .padding(.horizontal, metrics.gutter)
                            .padding(.vertical, Tokens.focusRoom)
                            .focusSection()
                        }
                        Secondary("Games run on your server and stream to this Apple TV. Only play games you own.")
                            .padding(.horizontal, metrics.gutter)
                    }
                    .padding(.vertical, Tokens.Space.s6)
                    .background(alignment: .top) { Ambient(colour: tint) }
                }
                .focusScope(scope)
            }
        }
        .pageBackground(palette)
        .task { await load() }
        .task(id: heroAt) { await updateTint() }
        .task {
            // The clock ticks on the minute, as the website's couch mode does.
            while !Task.isCancelled {
                clock = Date()
                let wait = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    @ViewBuilder private func shelf(_ title: String, _ items: [GameItem]?) -> some View {
        if let items, !items.isEmpty {
            GameRow(title: title) {
                ForEach(uniqued(items)) { GameCard(game: $0, console: byId[$0.console ?? ""], favourite: favourites.contains($0.id)) }
            }
        }
    }
}

// MARK: - A game's page

struct GameDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let id: Int64

    @State private var game: GameItem?
    @State private var check: GameCheck?
    @State private var saves: [GameSave] = []
    @State private var mine: GamePersonal?
    @State private var details: GameDetails?
    @State private var consoles: [GameConsole] = []
    @State private var resume = ResumeChoice.offer
    @State private var tint: Color?
    @State private var error = ""
    @State private var deleting: GameSave?
    @State private var showMore = false
    @Namespace private var scope

    private var console: GameConsole? { consoles.first { $0.id == game?.console } }
    private var auto: GameSave? { saves.first { $0.slot == 0 } }
    private var ready: Bool { check?.ready ?? console?.ready ?? false }

    private func load() async {
        do {
            async let g = client.gameItem(id)
            async let c = client.gameCheck(id)
            async let s = client.gameSaves(id)
            async let l = client.gameConsoles()
            let fresh = try await g
            if fresh != game { game = fresh }
            check = try? await c
            saves = ((try? await s) ?? []).sorted { $0.slot < $1.slot }
            if consoles.isEmpty { consoles = (try? await l) ?? [] }
            error = ""
        } catch {
            let words = model.handle(error)
            if game == nil, !words.isEmpty { self.error = words }
            return
        }
        async let m = client.gamePersonal(id)
        async let d = client.gameDetails(id)
        async let st = client.gameSettings(item: id)
        mine = try? await m
        details = try? await d
        if let settings = try? await st { resume = ResumeChoice(setting: settings.text("states.resume", "ask")) }
        if let game, game.hasPoster {
            tint = await CoverTints.shared.tint(client.gamePosterURL(game, width: 64), client: client, dark: palette.isDark)
        }
    }

    private func toggleFavourite() {
        guard let mine else { return }
        Task {
            if let fresh = try? await client.setGameFavourite(id, !mine.favourite) { self.mine = fresh }
        }
    }

    private func delete(_ save: GameSave) {
        Task {
            do {
                try await client.deleteGameSave(id, slot: save.slot)
                saves.removeAll { $0.slot == save.slot }
            } catch {
                self.error = (error as? APIError)?.message ?? "That save couldn't be deleted."
            }
        }
    }

    private var resumes: Bool { resume.resumes(hasAutoSave: auto != nil) }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Tokens.Space.s3) {
            if ready {
                NavigationLink(value: Route.playGame(id, resumes ? .resume : .fresh)) {
                    Label(resumes ? "Resume" : "Play", systemImage: "play.fill")
                }
                .mainAction()
                .prefersDefaultFocus(in: scope)
                if auto != nil, resumes {
                    NavigationLink("Start over", value: Route.playGame(id, .fresh)).action(pill: true)
                } else if auto != nil {
                    NavigationLink("Resume", value: Route.playGame(id, .resume)).action(pill: true)
                }
            }
            if let mine {
                Button(action: toggleFavourite) {
                    Image(systemName: mine.favourite ? "star.fill" : "star").foregroundStyle(mine.favourite ? Color.yellow : palette.text)
                }
                .action(pill: true)
                .accessibilityLabel(mine.favourite ? "Favourite" : "Add to favourites")
            }
            if ready {
                Button { showMore = true } label: { Image(systemName: "ellipsis") }
                    .action(pill: true)
                    .accessibilityLabel("More")
            }
        }
        .focusSection()
        .confirmationDialog("More for this game", isPresented: $showMore) {
            Button("Start with default settings") { model.path.append(.playGame(id, .safe(resume: auto != nil))) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Defaults only: no cheats and no patches, for a game that won't start the usual way.")
        }
    }

    @ViewBuilder private func head(_ game: GameItem) -> some View {
        let c = console
        HStack(alignment: .bottom, spacing: Tokens.Space.s10) {
            BoxArt(game: game, console: c, width: 320)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Secondary([model.libraries.first { $0.id == game.libraryId }?.name, c?.shortName].compactMap { $0 }.joined(separator: " / "))
                Text(game.title).font(.wmDisplay).foregroundStyle(palette.text).lineLimit(3).accessibilityAddTraits(.isHeader)
                if let tagline = game.tagline, !tagline.isEmpty { Text(tagline).font(.title3).foregroundStyle(palette.textSecondary) }
                let facts: [String] = [c?.name, game.year.map(String.init), details?.players.flatMap { $0 > 0 ? GameWords.players($0) : nil },
                                       game.rating.map { "★ " + String(format: "%.1f", $0) }, (game.genres ?? []).prefix(3).joined(separator: ", ")]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                Secondary(facts.joined(separator: " · "))
                let plays = mine?.plays ?? 0
                if game.playedSeconds > 60 || plays > 0 {
                    Secondary([game.playedSeconds > 60 ? "\(GameWords.played(game.playedSeconds)) played" : nil,
                               plays > 0 ? "\(plays) \(plays == 1 ? "session" : "sessions")" : nil].compactMap { $0 }.joined(separator: " · "))
                }
                actions.padding(.top, Tokens.Space.s2)
                if let auto, ready {
                    NavigationLink(value: Route.playGame(id, .resume)) {
                        HStack(spacing: Tokens.Space.s3) {
                            saveThumb(auto, width: 128)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pick up where you left off").font(.headline).foregroundStyle(palette.text)
                                Text(GameWords.ago(auto.updatedAt)).font(.caption).foregroundStyle(palette.textSecondary)
                            }
                        }
                        .padding(Tokens.Space.s2)
                        .padding(.trailing, Tokens.Space.s4)
                    }
                    .buttonStyle(SurfaceStyle(fill: palette.panel))
                    .accessibilityLabel("Resume from \(GameWords.ago(auto.updatedAt))")
                }
                if let check, !check.ready { blocked(check) }
            }
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .padding(.horizontal, metrics.gutter)
    }

    private func blocked(_ check: GameCheck) -> some View {
        let heading = check.reason == "core" ? "This game needs a core first" : check.reason == "bios" ? "This game needs a BIOS file" : "This console can't play here yet"
        let admin = model.user?.isAdmin == true
        let extra = check.reason == "core" ? (admin ? " A core is the free program that plays these games: install one on the website, in Settings, Consoles & cores." : " Ask whoever runs this server to install one.") : ""
        return HStack(alignment: .top, spacing: Tokens.Space.s3) {
            Image(systemName: "info.circle").foregroundStyle(palette.danger)
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(heading).font(.headline).foregroundStyle(palette.text)
                Secondary((check.message ?? "") + extra)
            }
        }
        .padding(Tokens.Space.s4)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md).strokeBorder(palette.danger, lineWidth: 2))
        .focusable(true)
        .accessibilityElement(children: .combine)
    }

    private func saveThumb(_ save: GameSave, width: CGFloat) -> some View {
        Group {
            if save.hasThumb == true {
                ArtImage(url: client.gameSaveThumbURL(id, slot: save.slot, version: save.updatedAt), width: width, fit: true)
            } else {
                Rectangle().fill(palette.card)
            }
        }
        .frame(width: width, height: width * 0.75)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous))
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(title).font(.wmSection).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(Tokens.Space.s6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .focusable(true)
        .accessibilityElement(children: .combine)
    }

    private func check(_ ok: Bool, _ words: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s2) {
            Image(systemName: ok ? "checkmark.circle.fill" : "info.circle").foregroundStyle(ok ? palette.ok : palette.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(words).font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
                Text(detail).font(.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func factRows(_ game: GameItem) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let released = details?.released, !released.isEmpty {
            rows.append(("Released", GameWords.released(released)))
        } else if let year = game.year {
            rows.append(("Year", String(year)))
        }
        if let studio = game.studio, !studio.isEmpty { rows.append(("Developer", studio)) }
        if let publisher = details?.publisher, !publisher.isEmpty { rows.append(("Publisher", publisher)) }
        if let players = details?.players, players > 0 { rows.append(("Players", players == 1 ? "1" : "Up to \(players)")) }
        if let series = details?.franchise, !series.isEmpty { rows.append(("Series", series)) }
        let genres = game.genres ?? []
        if !genres.isEmpty { rows.append(("Genres", genres.joined(separator: ", "))) }
        return rows
    }

    @ViewBuilder private func facts(_ game: GameItem) -> some View {
        let rows = factRows(game)
        if !rows.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .topLeading)], alignment: .leading, spacing: Tokens.Space.s4) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(palette.textHint)
                        Text(row.1).foregroundStyle(palette.text)
                    }
                }
            }
            .focusable(true)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func body(_ game: GameItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s10) {
                head(game)
                if !error.isEmpty { ProblemLine(error).padding(.horizontal, metrics.gutter) }
                HStack(alignment: .top, spacing: Tokens.Space.s10) {
                    if let overview = game.overview, !overview.isEmpty {
                        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            SectionTitle("About this game")
                            Text(overview).foregroundStyle(palette.textSecondary).lineLimit(8).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: 900, alignment: .leading)
                        .focusable(true)
                        .accessibilityElement(children: .combine)
                    }
                    facts(game).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, metrics.gutter)
                if !saves.isEmpty {
                    GameRow(title: "Save states") {
                        ForEach(saves) { save in
                            NavigationLink(value: Route.playGame(id, save.slot == 0 ? .resume : .slot(save.slot))) {
                                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                                    saveThumb(save, width: 300)
                                    Text(GameWords.slotName(save.slot)).font(.wmCard).foregroundStyle(palette.text)
                                    Text(GameWords.ago(save.updatedAt)).font(.wmCardSub).foregroundStyle(palette.textSecondary)
                                }
                                .frame(width: 300, alignment: .leading)
                            }
                            .buttonStyle(.card)
                            .disabled(!ready)
                            .contextMenu {
                                Button("Delete \(GameWords.slotName(save.slot).lowercased())", role: .destructive) { deleting = save }
                            }
                            .accessibilityLabel("Play from \(GameWords.slotName(save.slot)), saved \(GameWords.ago(save.updatedAt))")
                            .accessibilityHint("Press and hold to delete it")
                        }
                    }
                }
                HStack(alignment: .top, spacing: Tokens.Space.s6) {
                    panel("How it plays") {
                        check(true, "Runs on your server", "and streams to this Apple TV, so it needs no emulator and nothing downloads. Saves stay on the server and follow you to every device: start here, carry on in a browser, and back.")
                        if let core = check?.core {
                            check(true, core.name ?? core.id, "The core that plays this game, on the server. Licence: \(core.license ?? "not known").")
                        }
                        if check?.reason == "core" { check(false, "No core installed", model.user?.isAdmin == true ? "Install one on the website, in Settings, Consoles & cores." : "Ask whoever runs this server.") }
                        if check?.needsGpu == true { check(true, "Uses the server's graphics card", "This console is drawn with one, so it needs a server that has one.") }
                        ForEach((check?.bios ?? []).filter { $0.required == true || $0.found == true }, id: \.file) { b in
                            check(b.found == true, "BIOS: \(b.file)", b.found == true ? "Found. \(b.for ?? "")." : "Not found yet. \(b.for ?? ""). Put your own copy in a folder named \(check?.biosFolder ?? "BIOS") beside these games.")
                        }
                    }
                    panel("Controls") {
                        if let pad = console?.pad {
                            FlowLayout(spacing: Tokens.Space.s2) {
                                ForEach(["D-pad"] + (pad.sticks == true ? ["Stick"] : []) + pad.buttons.map(\.label), id: \.self) { label in
                                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(palette.text)
                                        .padding(.horizontal, Tokens.Space.s3).padding(.vertical, Tokens.Space.s1)
                                        .background(Capsule().fill(palette.card))
                                }
                            }
                        }
                        Secondary("MFi, Xbox and PlayStation controllers work, and so does the Siri Remote for games that need few buttons. Start and Select together, or the remote's Back button, open the game menu. Your controller profiles from the website apply here too.")
                        if console?.pad?.pointer == true {
                            Secondary("This console has a touch screen, which Apple TV can't reach. Games that need it are best played in a browser.")
                        }
                    }
                }
                .padding(.horizontal, metrics.gutter)
                .focusSection()
                if let credits = details?.credits, !credits.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        ForEach(credits, id: \.self) { credit in
                            Secondary([credit.text ?? credit.name, credit.site, credit.license].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        }
                    }
                    .padding(.horizontal, metrics.gutter)
                    .focusable(true)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, Tokens.Space.s12)
            .padding(.bottom, Tokens.Space.s10)
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Ambient(colour: tint, height: 760)
                    if game.hasBackdrop { PageBackdrop(url: client.gameBackdropURL(game), height: 620, dim: 0.24) }
                }
            }
        }
        .focusScope(scope)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let game {
                body(game)
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .pageBackground(palette)
        // Again on every return: a game just played has a new save and time played.
        .task { await load() }
        .alert("Delete this save?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { delete(deleting) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(deleting.map { GameWords.slotName($0.slot) } ?? "This save") can't be brought back, here or on any other device.")
        }
    }
}
#endif
