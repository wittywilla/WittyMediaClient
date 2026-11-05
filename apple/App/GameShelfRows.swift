import SwiftUI
import WittyKit

// The rows of WittyPlay's games home and a console's collection (docs/WITTYPLAY-EXPERIENCE.md, On a
// phone: Home: Shelves, A collection; On a TV: Shelves on a TV), as the website's GameShelves.tsx: a shelf
// with its heading and ledge, the game pulled out of it, Where you left off, On the go, a collection's
// band, and on a TV the preview of the focused game and the prompt bar.

/// What every shelf on a page shares: the consoles, what's in progress and what's a favourite, and how
/// games stand.
struct ShelfContext {
    let consoles: [String: GameConsole]
    let progress: [Int64: GameContinue]
    let favourites: Set<Int64>
    let view: ShelfView

    func console(_ item: GameItem) -> GameConsole? { consoles[item.console ?? ""] }
    func inProgress(_ item: GameItem) -> Bool { progress[item.id]?.save != nil }

    /// Where pressing Play goes: the game, from where it was left when it was; its page when it can't play.
    func play(_ item: GameItem) -> Route {
        guard console(item)?.ready ?? true else { return .game(item.id) }
        return .playGame(item.id, inProgress(item) ? .resume : .fresh)
    }

    /// "Thwaite, NES, in progress, a favourite", as the design's spoken labels.
    func spoken(_ item: GameItem, chosen: Bool = false) -> String {
        [item.title, console(item)?.shortName, inProgress(item) ? "in progress" : nil,
         favourites.contains(item.id) ? "a favourite" : nil, chosen ? "chosen" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// "console · maker · genre · players", the facts under a game's name.
func gameFacts(_ item: GameItem, _ console: GameConsole?, players: Int? = nil) -> String {
    [console?.shortName, item.studio, item.genres?.first, players.flatMap { $0 > 1 ? "1–\($0) players" : nil }]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}

/// Saying a WittyPlay word with its blank filled: "Yours on {console}".
func say(_ key: String, _ blank: String, with value: String) -> String {
    say(key).replacingOccurrences(of: "{\(blank)}", with: value)
}

// MARK: - A shelf

/// One shelf: its heading (a console's name in its era's type, its era and its count, All ›), its
/// games on the ledge as the chosen view draws them, and under the ledge the one pulled out.
struct GameShelfRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let id: String
    let title: String
    let items: [GameItem]
    var console: GameConsole?
    var count: Int?
    /// Its first game faces out on a shelf of spines, as a shop's best one does.
    var faceFirst = false
    /// Long shelves of spines get a divider at each new letter.
    var letters = false
    var all: Route?
    let context: ShelfContext
    @Binding var pulled: String?
    let focus: FocusState<String?>.Binding
    let toggleFavourite: (GameItem) -> Void

    var body: some View {
        let s = metrics.shelf
        let list = uniqued(items)
        let chosen = list.first { pulled == "\(id):\($0.id)" }
        let dividers = letters && context.view == .spines ? GameShelves.dividers(list.map(\.title)) : [:]
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: metrics.tv ? Tokens.Space.s3 : Tokens.Space.s2) {
                heading
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .bottom, spacing: context.view == .spines ? 3 * s.scale : 12 * s.scale) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                            if let letter = dividers[i] { ShelfDivider(letter: letter) }
                            ShelfGame(item: item, shelf: id, faceOut: faceFirst && i == 0, context: context, pulled: $pulled,
                                      focus: focus, toggleFavourite: toggleFavourite)
                        }
                    }
                    .padding(.horizontal, metrics.gutter)
                    .padding(.top, s.headroom)
                    .padding(.bottom, 3)
                }
                .overlay(alignment: .bottom) { ShelfLedge() }
                .remoteSection()
                if let chosen { PulledInfo(item: chosen, context: context).padding(.horizontal, metrics.gutter) }
            }
            .task(id: context.view) {
                if context.view == .spines { CoverTints.shared.ask(list, client: client) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
    }

    private var heading: some View {
        let tv = metrics.tv
        return HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
            if let console {
                EraName(name: title, era: GameShelves.era(console), size: tv ? 28 : 20, colour: palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let era = GameShelves.era(console), let name = GameShelves.eraNames[era] {
                    Text(name).font(.system(size: tv ? 20 : 12, weight: .medium)).foregroundStyle(palette.textHint)
                }
            } else {
                Text(title).font(.system(size: tv ? 28 : 20, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            if let count {
                Text(count.formatted()).font(.system(size: tv ? 22 : 13)).foregroundStyle(palette.textHint)
            }
            if let console, console.ready == false {
                Text(console.unavailable != nil ? "Not on this server" : "Needs setting up")
                    .font(.system(size: tv ? 20 : 12, weight: .semibold)).foregroundStyle(palette.warn)
            }
            Spacer(minLength: Tokens.Space.s2)
            if let all {
                NavigationLink(value: all) {
                    HStack(spacing: 2) {
                        Text("All")
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                }
                .action(.quiet)
                .accessibilityLabel("All of \(title)")
            }
        }
        .padding(.horizontal, metrics.gutter)
    }
}

/// One game on a shelf. Pressed, it's pulled out; pressed again, it plays (or opens its page, when it
/// can't play here). Held, it offers the rest.
private struct ShelfGame: View {
    @EnvironmentObject private var model: AppModel
    let item: GameItem
    let shelf: String
    let faceOut: Bool
    let context: ShelfContext
    @Binding var pulled: String?
    let focus: FocusState<String?>.Binding
    let toggleFavourite: (GameItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let key = "\(shelf):\(item.id)"
        let on = pulled == key
        let c = context.console(item)
        let ribbon = context.inProgress(item)
        let fav = context.favourites.contains(item.id)
        Button {
            if on {
                model.path.append(context.play(item))
            } else {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { pulled = key }
            }
        } label: {
            switch context.view {
            case .cases: GameCaseView(item: item, console: c, ribbon: ribbon, favourite: fav, pulled: on)
            case .carts: GameCartView(item: item, console: c, ribbon: ribbon, favourite: fav, pulled: on)
            case .spines:
                if on || faceOut {
                    GameFaceOutView(item: item, console: c, ribbon: ribbon, pulled: on)
                } else {
                    GameSpineView(item: item, console: c, ribbon: ribbon, favourite: fav)
                }
            }
        }
        .buttonStyle(ShelfPress())
        .focused(focus, equals: key)
        .contextMenu {
            Button { model.path.append(context.play(item)) } label: {
                Label(context.console(item)?.ready == false ? say("wpCantPlayYet") : (ribbon ? "Resume" : "Play"), systemImage: "play.fill")
            }
            Button { model.path.append(.game(item.id)) } label: { Label("About this game", systemImage: "info.circle") }
            Button { toggleFavourite(item) } label: {
                Label(fav ? "Remove from favourites" : "Add to favourites", systemImage: fav ? "star.slash" : "star")
            }
        }
        #if os(tvOS)
        // Play/Pause plays the focused game straight away.
        .onPlayPauseCommand { model.path.append(context.play(item)) }
        #endif
        .accessibilityLabel(context.spoken(item, chosen: on))
        .accessibilityHint(on ? (ribbon ? "Resumes it" : "Plays it") : "Pulls it out")
    }
}

/// Under the ledge, the game that's pulled out: its name and facts, where it was left off, and
/// Resume or Play beside About.
struct PulledInfo: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let item: GameItem
    let context: ShelfContext

    var body: some View {
        let tv = metrics.tv
        let c = context.console(item)
        let entry = context.progress[item.id]
        VStack(alignment: .leading, spacing: tv ? Tokens.Space.s2 : Tokens.Space.s1) {
            Text(item.title).font(.system(size: tv ? 30 : 17, weight: .semibold)).foregroundStyle(palette.text).lineLimit(2)
            let facts = gameFacts(item, c)
            if !facts.isEmpty { Text(facts).font(.system(size: tv ? 22 : 13)).foregroundStyle(palette.textSecondary).lineLimit(1) }
            if let entry, entry.save != nil, let when = entry.lastPlayed {
                HStack(spacing: Tokens.Space.s1) {
                    Circle().fill(palette.accent).frame(width: tv ? 10 : 6, height: tv ? 10 : 6)
                    Text("\(say("wpWhereYouLeftOff")): \(GameWords.ago(when))")
                }
                .font(.system(size: tv ? 22 : 13)).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: Tokens.Space.s2) {
                if c?.ready ?? true {
                    NavigationLink(value: context.play(item)) {
                        Label(context.inProgress(item) ? "Resume" : "Play", systemImage: "play.fill")
                    }
                    .mainAction()
                } else {
                    NavigationLink(value: Route.game(item.id)) { Label(say("wpCantPlayYet"), systemImage: "slider.horizontal.3") }
                        .action(pill: true)
                }
                NavigationLink("About", value: Route.game(item.id)).action(.quiet, pill: true)
            }
            .padding(.top, Tokens.Space.s1)
            .remoteSection()
        }
        .padding(tv ? Tokens.Space.s6 : Tokens.Space.s4)
        .frame(maxWidth: tv ? 900 : .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
    }
}

/// Above the shelves: Cases, Cartridges or Shelf, which this device remembers.
struct ShelfViewSwitch: View {
    @Environment(\.metrics) private var metrics
    @Binding var view: ShelfView
    var changed: () -> Void = {}

    private func words(_ v: ShelfView) -> String {
        switch v {
        case .cases: return say("wpViewCases")
        case .carts: return say("wpViewCartridges")
        case .spines: return say("wpViewShelf")
        }
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            ForEach(ShelfView.allCases) { v in
                Button {
                    guard view != v else { return }
                    view = v
                    v.save()
                    changed()
                } label: { ChipLabel(title: words(v), selected: view == v) }
                .buttonStyle(SurfaceStyle(radius: 999))
                .accessibilityAddTraits(view == v ? .isSelected : [])
            }
        }
        .padding(.horizontal, metrics.gutter)
        .remoteSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How games stand")
    }
}

// MARK: - Where you left off

/// The one obvious next step: the last moment's picture, large and drifting, with the game, its time
/// played and when, and Resume. The whole card resumes.
struct ResumeCard: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let entry: GameContinue
    let context: ShelfContext

    var body: some View {
        let item = entry.item
        let c = context.console(item)
        let tablet = metrics.gutter > Tokens.Space.s4
        let played = item.playedSeconds
        let facts = [c?.shortName, played > 60 ? GameWords.played(played) : nil, entry.lastPlayed.map { GameWords.ago($0) }]
            .compactMap { $0 }.joined(separator: " · ")
        NavigationLink(value: context.play(item)) {
            ZStack(alignment: .bottomLeading) {
                Drifting { picture(item, c) }
                LinearGradient(stops: [.init(color: .black.opacity(0.86), location: 0), .init(color: .black.opacity(0), location: 0.7)],
                               startPoint: .bottom, endPoint: .top)
                HStack(alignment: .bottom, spacing: Tokens.Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(say("wpWhereYouLeftOff")).font(.caption).foregroundStyle(.white.opacity(0.8))
                        Text(item.title).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                        Text(facts).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Label(entry.save != nil ? "Resume" : "Play", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, Tokens.Space.s4)
                        .frame(height: 32)
                        .background(Capsule().fill(palette.accent))
                }
                .padding(14)
            }
            .frame(maxWidth: tablet ? 560 : .infinity)
            .frame(height: tablet ? 315 : 214)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
            .overlay(alignment: .topTrailing) { if entry.save != nil { ShelfRibbon().padding(.trailing, 22).offset(y: -4) } }
        }
        .buttonStyle(ShelfPress(radius: Tokens.Radius.lg))
        .accessibilityLabel("\(entry.save != nil ? "Resume" : "Play") \(item.title)\(c.map { ", " + $0.shortName } ?? "")\(entry.lastPlayed.map { ", last played " + GameWords.ago($0) } ?? "")")
    }

    @ViewBuilder private func picture(_ item: GameItem, _ c: GameConsole?) -> some View {
        if let save = entry.save, save.hasThumb == true {
            ArtImage(url: client.gameSaveThumbURL(item.id, slot: save.slot, version: save.updatedAt), width: 560, placeholder: item.title)
        } else if item.hasBackdrop {
            ArtImage(url: client.gameBackdropURL(item), width: 560, placeholder: item.title)
        } else {
            ShelfCover(item: item, console: c, width: 560)
        }
    }
}

/// The other games in progress, smaller, each with its ribbon.
struct OnTheGoRow: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    var title: String?
    let entries: [GameContinue]
    let context: ShelfContext
    /// Off where the row sits beside Where you left off, which has the page's margin already.
    var inset = true

    var body: some View {
        let tv = metrics.tv, tablet = metrics.gutter > Tokens.Space.s4
        let gutter = inset ? metrics.gutter : 0
        let size = tv ? CGSize(width: 360, height: 270) : tablet ? CGSize(width: 200, height: 150) : CGSize(width: 152, height: 114)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                if let title {
                    Text(title).font(.system(size: tv ? 28 : 20, weight: .semibold)).foregroundStyle(palette.text)
                        .accessibilityAddTraits(.isHeader).padding(.horizontal, gutter)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: tv ? Tokens.Space.s8 : Tokens.Space.s3) {
                        ForEach(entries) { card($0, size: size) }
                    }
                    .padding(.horizontal, gutter)
                    .padding(.top, tv ? metrics.shelf.headroom : 10)
                    .padding(.bottom, tv ? Tokens.Space.s4 : 0)
                }
                .remoteSection()
            }
        }
    }

    private func card(_ entry: GameContinue, size: CGSize) -> some View {
        let item = entry.item
        let c = context.console(item)
        let tv = metrics.tv
        let played = item.playedSeconds
        return NavigationLink(value: context.play(item)) {
            VStack(alignment: .leading, spacing: 2) {
                ZStack {
                    palette.card
                    if let save = entry.save, save.hasThumb == true {
                        ArtImage(url: client.gameSaveThumbURL(item.id, slot: save.slot, version: save.updatedAt), width: size.width, placeholder: item.title)
                    } else {
                        ShelfCover(item: item, console: c, width: size.width)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                .overlay(alignment: .topTrailing) { if entry.save != nil { ShelfRibbon().padding(.trailing, Tokens.Space.s3).offset(y: -4) } }
                .padding(.bottom, Tokens.Space.s1)
                Text(item.title).font(.system(size: tv ? 24 : 14, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                Text([played > 60 ? GameWords.played(played) : nil, entry.lastPlayed.map { GameWords.ago($0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: tv ? 20 : 12)).foregroundStyle(palette.textHint).lineLimit(1)
            }
            .frame(width: size.width, alignment: .leading)
        }
        .buttonStyle(ShelfPress(radius: Tokens.Radius.md))
        .accessibilityLabel("\(entry.save != nil ? "Resume" : "Play") \(item.title)\(entry.lastPlayed.map { ", last played " + GameWords.ago($0) } ?? "")")
    }
}

// MARK: - A console's collection

/// The top of a console's page: a band in its covers' colour with its era's grain fading down, the
/// console's name large in its era's type. Deep on a dark theme with white words; pale on a light one.
struct CollectionBand: View {
    @ObservedObject private var tints = CoverTints.shared
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let console: GameConsole
    let count: Int?
    let first: GameItem?

    var body: some View {
        let tv = metrics.tv
        let era = GameShelves.era(console)
        let grain = CGFloat(GameShelves.eraGrain[era ?? ""] ?? 10)
        let ink: Color = palette.isLight ? palette.text : .white
        let fill: Color = palette.isLight ? (tints.glow(first, light: true) ?? palette.panel)
                                          : (first.map { tints.deep($0) } ?? palette.panel)
        ZStack(alignment: .bottomLeading) {
            fill
            EraGrain(cell: grain * (tv ? 1.7 : 1), dot: palette.isLight ? 0.35 : 0.22).opacity(palette.isLight ? 0.5 : 1)
            VStack(alignment: .leading, spacing: tv ? Tokens.Space.s2 : Tokens.Space.s1) {
                Text([era.flatMap { GameShelves.eraNames[$0] }, say("wpCollection")].compactMap { $0 }.joined(separator: " · "))
                    .font(tv ? .system(size: 22, weight: .semibold) : .caption.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.8))
                EraName(name: console.shortName, era: era, size: tv ? 76 : 48, colour: ink)
                    .accessibilityAddTraits(.isHeader)
                let facts = [console.name != console.shortName ? console.name : nil,
                             count.map { "\($0.formatted()) \($0 == 1 ? "game" : "games")" }].compactMap { $0 }.joined(separator: " · ")
                if !facts.isEmpty { Text(facts).font(.system(size: tv ? 24 : 15)).foregroundStyle(ink.opacity(0.85)) }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.bottom, tv ? Tokens.Space.s8 : Tokens.Space.s6)
        }
        .frame(height: tv ? 380 : 260)
        .frame(maxWidth: .infinity)
        .task { if let first { tints.ask([first], client: client) } }
        .accessibilityElement(children: .combine)
    }
}

/// What's yours for one console, where people look for it: its Look and settings, and its controls,
/// on the server's pages.
struct YoursOn: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let console: GameConsole

    var body: some View {
        let id = ServerPagesQuery.value(console.id)
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            SectionTitle(say("wpYoursOn", "console", with: console.shortName))
            VStack(spacing: 0) {
                row("slider.horizontal.3", say("wpLookFor", "console", with: console.shortName), "/settings/games?console=\(id)")
                Divider().overlay(palette.border)
                row("gamecontroller", say("wpControlsFor", "console", with: console.shortName), "/controllers?console=\(id)")
            }
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
            .remoteSection()
        }
        .padding(.horizontal, metrics.gutter)
    }

    private func row(_ icon: String, _ words: String, _ path: String) -> some View {
        NavigationLink(value: Route.page(path)) {
            HStack(spacing: Tokens.Space.s3) {
                Image(systemName: icon).foregroundStyle(palette.textSecondary).frame(width: 24)
                Text(words).foregroundStyle(palette.text)
                Spacer()
                Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(palette.textHint)
            }
            .padding(.horizontal, Tokens.Space.s4)
            .frame(minHeight: metrics.tv ? 72 : 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfaceStyle())
    }
}

/// A console id in an address's query.
enum ServerPagesQuery {
    static func value(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }
}

// MARK: - Every game

/// A game in the list of every game: its case, its name, and its console and year.
struct GameGridCell: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let item: GameItem
    let context: ShelfContext
    let width: CGFloat

    var body: some View {
        let s = metrics.shelf
        let c = context.console(item)
        let tv = metrics.tv
        NavigationLink(value: Route.game(item.id)) {
            VStack(alignment: .leading, spacing: 2) {
                GameCaseView(item: item, console: c, ribbon: context.inProgress(item), favourite: context.favourites.contains(item.id), fit: width)
                    .frame(width: width, height: min(176 * s.scale, width * 1.45), alignment: .bottom)
                    .padding(.bottom, Tokens.Space.s2)
                Text(item.title).font(.system(size: tv ? 22 : 14, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                Text([c?.shortName, item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: tv ? 18 : 12)).foregroundStyle(palette.textHint).lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(ShelfPress())
        .accessibilityLabel(context.spoken(item))
    }
}

/// A grid of every game's covers while the page loads: grey strips on a ledge, as the design's state.
struct ShelfLoading: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    var body: some View {
        let s = metrics.shelf.scale
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            ForEach(0..<3, id: \.self) { row in
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    RoundedRectangle(cornerRadius: 4).fill(palette.card).frame(width: 120 * s, height: 18 * s)
                    HStack(alignment: .bottom, spacing: 3 * s) {
                        ForEach(0..<14, id: \.self) { i in
                            UnevenRect(top: 4 * s, bottom: 1).fill(palette.card)
                                .frame(width: CGFloat(34 + (i * 7 + row * 3) % 14) * s, height: 176 * s)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .overlay(alignment: .bottom) { ShelfLedge() }
                }
            }
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.top, Tokens.Space.s6)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

#if os(tvOS)
// MARK: - On a TV

/// The top of the TV's games home: the focused game rises here, its picture drifting on the right;
/// on the left its console and era, its name large, its facts, where it was left off, and Resume (or
/// Play) and More. It follows focus after a moment, so flicking along a shelf doesn't flicker it.
struct TvGamePreview: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let item: GameItem
    let context: ShelfContext
    let scope: Namespace.ID

    var body: some View {
        let c = context.console(item)
        let entry = context.progress[item.id]
        HStack(alignment: .center, spacing: Tokens.Space.s12) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text([c?.shortName, GameShelves.era(c).flatMap { GameShelves.eraNames[$0] }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(palette.textSecondary)
                Text(item.title).font(.system(size: 64, weight: .bold)).tracking(-1.4).foregroundStyle(palette.text)
                    .lineLimit(2).minimumScaleFactor(0.6)
                let facts = [item.year.map(String.init), item.studio, item.genres?.first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !facts.isEmpty { Text(facts).font(.system(size: 24)).foregroundStyle(palette.textSecondary).lineLimit(1) }
                if let entry, entry.save != nil, let when = entry.lastPlayed {
                    HStack(spacing: Tokens.Space.s2) {
                        Circle().fill(palette.accent).frame(width: 12, height: 12)
                        Text("\(say("wpWhereYouLeftOff")): \(GameWords.ago(when))\(item.playedSeconds > 60 ? " · " + GameWords.played(item.playedSeconds) + " played" : "")")
                    }
                    .font(.system(size: 22)).foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: Tokens.Space.s4) {
                    if c?.ready ?? true {
                        NavigationLink(value: context.play(item)) {
                            Label(context.inProgress(item) ? "Resume" : "Play", systemImage: "play.fill")
                        }
                        .mainAction()
                        .prefersDefaultFocus(in: scope)
                    } else {
                        NavigationLink(value: Route.game(item.id)) { Label(say("wpCantPlayYet"), systemImage: "slider.horizontal.3") }
                            .action(pill: true)
                            .prefersDefaultFocus(in: scope)
                    }
                    NavigationLink("More", value: Route.game(item.id)).action(pill: true)
                }
                .padding(.top, Tokens.Space.s2)
                .focusSection()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                palette.card
                Drifting {
                    if item.hasBackdrop {
                        ArtImage(url: client.gameBackdropURL(item), width: 560, placeholder: item.title)
                    } else if let save = entry?.save, save.hasThumb == true {
                        ArtImage(url: client.gameSaveThumbURL(item.id, slot: save.slot, version: save.updatedAt), width: 560, placeholder: item.title)
                    } else {
                        ShelfCover(item: item, console: c, width: 560)
                    }
                }
            }
            .frame(width: 560, height: 420)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
            .overlay(alignment: .topTrailing) { if entry?.save != nil { ShelfRibbon().padding(.trailing, 40).offset(y: -6) } }
            .id(item.id)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
        .frame(height: 420)
        .padding(.horizontal, Tokens.gutter)
        .animation(.easeInOut(duration: 0.25), value: item.id)
    }
}

/// Along the bottom of the TV's games home, what the remote's buttons do here, each in our own round key.
struct TvPromptBar: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 36) {
            hint(Text("OK"), "Open")
            hint(Text(Image(systemName: "chevron.left")), "Back")
            hint(Text(Image(systemName: "playpause.fill")), "Play now")
            hint(Text("Hold OK"), "More")
            Spacer()
        }
        .padding(.horizontal, Tokens.gutter)
        .frame(height: 72)
        .background(LinearGradient(colors: [palette.background.opacity(0), palette.background], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }

    private func hint(_ key: Text, _ words: String) -> some View {
        HStack(spacing: Tokens.Space.s2) {
            key.font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.text)
                .padding(.horizontal, Tokens.Space.s3)
                .frame(minWidth: 40, minHeight: 40)
                .overlay(Capsule().strokeBorder(palette.text.opacity(0.6), lineWidth: 2))
            Text(words).font(.system(size: 22)).foregroundStyle(palette.textSecondary)
        }
    }
}
#endif
