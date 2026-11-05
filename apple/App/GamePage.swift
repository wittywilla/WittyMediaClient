import SwiftUI
import WittyKit

// A game's page on every Apple device (docs/WITTYPLAY-EXPERIENCE.md, A game; On a TV: A game on a
// TV), as APP-DESIGN's item page for a game: its picture drifting behind, its box, its name and facts,
// Resume (or Play) with Favourite and More, Where you left off with its ribbon, its moments, About this
// game and How you play it. A game that can't play here shows why in a state card, and never Play.

struct GameDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @ObservedObject private var tints = CoverTints.shared
    let id: Int64

    @State private var game: GameItem?
    @State private var check: GameCheck?
    @State private var saves: [GameSave] = []
    @State private var mine: GamePersonal?
    @State private var details: GameDetails?
    @State private var consoles: [GameConsole] = []
    @State private var resume = ResumeChoice.offer
    @State private var error = ""
    @State private var deleting: GameSave?
    @State private var showMore = false
    @State private var wholeAbout = false
    @Namespace private var scope

    private var console: GameConsole? { consoles.first { $0.id == game?.console } }
    private var auto: GameSave? { saves.first { $0.slot == 0 } }
    private var ready: Bool { check?.ready ?? console?.ready ?? false }
    private var resumes: Bool { resume.resumes(hasAutoSave: auto != nil) }
    private var players: Int? { details?.players.flatMap { $0 > 0 ? $0 : nil } }

    /// Moments newest first, then the server's two for undoing: Before you loaded, Before starting over.
    private var moments: [GameSave] {
        let mine = saves.filter { GameWords.canSave(to: $0.slot) }.sorted { $0.updatedAt > $1.updatedAt }
        return mine + saves.filter { $0.slot == 100 } + saves.filter { $0.slot == 101 }
    }

    // MARK: Loading

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
        if let game { tints.ask([game], client: client) }
        async let m = client.gamePersonal(id)
        async let d = client.gameDetails(id)
        async let st = client.gameSettings(item: id)
        mine = try? await m
        details = try? await d
        if let settings = try? await st { resume = ResumeChoice(setting: settings.text("states.resume", "ask")) }
    }

    private func toggleFavourite() {
        guard let mine else { return }
        Task {
            if let fresh = try? await client.setGameFavourite(id, !mine.favourite) {
                self.mine = fresh
                announce(fresh.favourite ? "Added to favourites" : "Removed from favourites")
            }
        }
    }

    private func delete(_ save: GameSave) {
        Task {
            do {
                try await client.deleteGameSave(id, slot: save.slot)
                saves.removeAll { $0.slot == save.slot }
            } catch {
                self.error = (error as? APIError)?.message ?? "That moment couldn't be deleted."
            }
        }
    }

    private func momentName(_ slot: Int) -> String {
        switch slot {
        case 0: return say("wpWhereYouLeftOff")
        case 100: return say("wpBeforeYouLoaded")
        case 101: return say("wpBeforeStartingOver")
        default: return "\(say("wpMoment")) \(slot)"
        }
    }

    // MARK: Pieces

    /// "{console} · {era}".
    private var kicker: String {
        [console?.shortName, GameShelves.era(console).flatMap { GameShelves.eraNames[$0] }].compactMap { $0 }.joined(separator: " · ")
    }

    /// maker · genre · 1–n players.
    private func facts(_ game: GameItem) -> String {
        [game.studio, (game.genres ?? []).first, players.map { $0 > 1 ? "1–\($0) players" : "1 player" }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private func backdrop(_ game: GameItem) -> some View {
        Drifting {
            if game.hasBackdrop {
                ArtImage(url: client.gameBackdropURL(game), width: metrics.tv ? 1920 : 900, blank: true)
            } else if let auto, auto.hasThumb == true {
                ArtImage(url: client.gameSaveThumbURL(id, slot: 0, version: auto.updatedAt), width: 900, blank: true)
            } else {
                // The cover's colour, as the page's glow.
                (tints.glow(game, light: palette.isLight) ?? palette.panel)
            }
        }
        .accessibilityHidden(true)
    }

    private func saveThumb(_ save: GameSave, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            palette.card
            if save.hasThumb == true {
                ArtImage(url: client.gameSaveThumbURL(id, slot: save.slot, version: save.updatedAt), width: width)
            } else {
                Image(systemName: "photo").foregroundStyle(palette.textHint)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
    }

    /// Resume (or Play), Favourite and More, in one row.
    @ViewBuilder private var actions: some View {
        let tv = metrics.tv
        HStack(spacing: Tokens.Space.s2) {
            NavigationLink(value: Route.playGame(id, resumes ? .resume : .fresh)) {
                Label(resumes ? "Resume" : "Play", systemImage: "play.fill")
                    .frame(maxWidth: tv ? nil : .infinity)
            }
            .mainAction()
            .firstFocus(in: scope)
            .accessibilityLabel(resumes ? "Resume \(game?.title ?? "")" : "Play \(game?.title ?? "")")
            if let mine {
                Button(action: toggleFavourite) {
                    Image(systemName: mine.favourite ? "star.fill" : "star")
                        .foregroundStyle(mine.favourite ? palette.warn : palette.text)
                        .frame(width: tv ? nil : 20)
                }
                .action(pill: true)
                .accessibilityLabel(mine.favourite ? "Favourite" : "Add to favourites")
                .accessibilityAddTraits(mine.favourite ? .isSelected : [])
            }
            more
        }
        .remoteSection()
    }

    /// "⋯": Start over (or Resume), Start with default settings, and Controls for this console.
    @ViewBuilder private var more: some View {
        #if os(tvOS)
        Button { showMore = true } label: { Image(systemName: "ellipsis") }
            .action(pill: true)
            .accessibilityLabel("More")
            .confirmationDialog("More for this game", isPresented: $showMore) {
                if auto != nil {
                    if resumes {
                        Button(say("wpStartOver")) { model.path.append(.playGame(id, .fresh)) }
                    } else {
                        Button("Resume") { model.path.append(.playGame(id, .resume)) }
                    }
                }
                Button(say("wpStartDefault")) { model.path.append(.playGame(id, .safe(resume: auto != nil))) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Defaults only: no cheats and no patches, for a game that won't start the usual way.")
            }
        #else
        Menu {
            if auto != nil {
                if resumes {
                    Button { model.path.append(.playGame(id, .fresh)) } label: { Label(say("wpStartOver"), systemImage: "arrow.counterclockwise") }
                } else {
                    Button { model.path.append(.playGame(id, .resume)) } label: { Label("Resume", systemImage: "play") }
                }
            }
            Button { model.path.append(.playGame(id, .safe(resume: auto != nil))) } label: {
                Label(say("wpStartDefault"), systemImage: "shield")
            }
            if let console {
                Button { model.path.append(.page("/controllers?console=\(ServerPagesQuery.value(console.id))")) } label: {
                    Label(say("wpControlsFor", "console", with: console.shortName), systemImage: "gamecontroller")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.wmLabel)
                .foregroundStyle(palette.text)
                .frame(width: 60, height: metrics.minTarget)
                .background(Capsule().fill(palette.card))
                .contentShape(Capsule())
        }
        .accessibilityLabel("More")
        #endif
    }

    /// Where you left off: the last moment's picture with its ribbon, when, and time played.
    @ViewBuilder private var leftOff: some View {
        if let auto {
            let tv = metrics.tv
            NavigationLink(value: Route.playGame(id, .resume)) {
                HStack(spacing: Tokens.Space.s3) {
                    saveThumb(auto, width: tv ? 160 : 96, height: tv ? 120 : 72)
                        .overlay(alignment: .topTrailing) { ShelfRibbon(height: tv ? 40 : 28).padding(.trailing, Tokens.Space.s2).offset(y: -4) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(say("wpWhereYouLeftOff")).font(.system(size: tv ? 24 : 15, weight: .semibold)).foregroundStyle(palette.text)
                        Text(GameWords.ago(auto.updatedAt)).font(.system(size: tv ? 20 : 13)).foregroundStyle(palette.textSecondary)
                        if let played = game?.playedSeconds, played > 60 {
                            Text("\(GameWords.played(played)) played").font(.system(size: tv ? 20 : 13)).foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Tokens.Space.s3)
            }
            .buttonStyle(SurfaceStyle(fill: palette.panel, radius: Tokens.Radius.lg))
            .accessibilityLabel("Resume from \(GameWords.ago(auto.updatedAt))")
        }
    }

    /// Why this game can't play here, in place of Play.
    @ViewBuilder private var stateCard: some View {
        if let check, !check.ready {
            let name = console?.shortName ?? "These"
            let admin = model.user?.isAdmin == true
            switch check.reason ?? "" {
            case "core":
                GameStateCard(icon: "puzzlepiece.extension", headline: "This server can't play \(name) games yet",
                              detail: "It needs a core for this console." + (admin ? " Install one on the website, in Settings, Consoles & cores." : " Ask whoever runs the server."),
                              action: admin ? ("Install a core", Route.page("/settings/gaming")) : nil)
            case "bios":
                GameStateCard(icon: "cpu", headline: "\(name) games need a BIOS file",
                              detail: "From a console you own. Put it in a folder named \(check.biosFolder ?? "BIOS") inside your \(name) games folder.",
                              files: (check.bios ?? []).filter { $0.required == true || $0.found == true }, retry: { Task { await load() } })
            case "gpu":
                GameStateCard(icon: "display", headline: "Not on this server", detail: check.message ?? "This console needs a graphics card this server doesn't have.")
            default:
                GameStateCard(icon: "info.circle", headline: say("wpCantPlayYet"), detail: console?.unavailable ?? check.message ?? "This console can't play here yet.")
            }
        }
    }

    /// The moments row: each one's picture, name and when; pressed, the game plays from it.
    @ViewBuilder private var momentsRow: some View {
        let list = moments
        if !list.isEmpty {
            let tv = metrics.tv
            let w: CGFloat = tv ? 304 : 200, h: CGFloat = tv ? 228 : 150
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                    SectionTitle(say("wpMoments"))
                    Text("\(list.count)").font(.system(size: tv ? 22 : 13)).foregroundStyle(palette.textHint)
                }
                .padding(.horizontal, sideGutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: tv ? Tokens.Space.s8 : Tokens.Space.s3) {
                        ForEach(list) { save in
                            NavigationLink(value: Route.playGame(id, .slot(save.slot))) {
                                VStack(alignment: .leading, spacing: 2) {
                                    saveThumb(save, width: w, height: h).padding(.bottom, Tokens.Space.s1)
                                    Text(momentName(save.slot)).font(.system(size: tv ? 22 : 14, weight: .semibold)).foregroundStyle(palette.text).lineLimit(1)
                                    Text(GameWords.ago(save.updatedAt)).font(.system(size: tv ? 18 : 12)).foregroundStyle(palette.textHint)
                                }
                                .frame(width: w, alignment: .leading)
                            }
                            .buttonStyle(ShelfPress(radius: Tokens.Radius.sm))
                            .disabled(!ready)
                            .contextMenu {
                                if ready {
                                    Button { model.path.append(.playGame(id, .slot(save.slot))) } label: { Label(say("wpPlayFromHere"), systemImage: "play.fill") }
                                }
                                Button(role: .destructive) { deleting = save } label: { Label("Delete", systemImage: "trash") }
                            }
                            .accessibilityLabel("\(say("wpPlayFromHere")): \(momentName(save.slot)), saved \(GameWords.ago(save.updatedAt))")
                            .accessibilityHint("Press and hold to delete it")
                        }
                    }
                    .padding(.horizontal, sideGutter)
                    .padding(.top, tv ? metrics.shelf.headroom : Tokens.Space.s1)
                    .padding(.bottom, Tokens.Space.s2)
                }
                .remoteSection()
            }
        }
    }

    /// Two columns on a tablet hold the moments in the right one, which has no margin of its own.
    @State private var twoColumns = false
    private var sideGutter: CGFloat { twoColumns ? 0 : metrics.gutter }

    private func factRows(_ game: GameItem) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let released = details?.released, !released.isEmpty {
            rows.append(("Released", GameWords.released(released)))
        } else if let year = game.year {
            rows.append(("Year", String(year)))
        }
        if let studio = game.studio, !studio.isEmpty { rows.append(("Developer", studio)) }
        if let publisher = details?.publisher, !publisher.isEmpty { rows.append(("Publisher", publisher)) }
        if let players { rows.append(("Players", players == 1 ? "1" : "Up to \(players)")) }
        if let series = details?.franchise, !series.isEmpty { rows.append(("Series", series)) }
        let genres = game.genres ?? []
        if !genres.isEmpty { rows.append(("Genres", genres.joined(separator: ", "))) }
        return rows
    }

    @ViewBuilder private func about(_ game: GameItem) -> some View {
        let rows = factRows(game)
        let overview = game.overview ?? ""
        if !overview.isEmpty || !rows.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                SectionTitle("About this game")
                if !overview.isEmpty {
                    Text(overview).foregroundStyle(palette.textSecondary)
                        .lineLimit(wholeAbout ? nil : (metrics.tv ? 6 : 5))
                        .fixedSize(horizontal: false, vertical: true)
                    #if !os(tvOS)
                    if !wholeAbout, overview.count > 260 {
                        Button("More") { wholeAbout = true }.action(.quiet)
                    }
                    #endif
                }
                if !rows.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.tv ? 260 : 140), alignment: .topLeading)], alignment: .leading,
                              spacing: Tokens.Space.s3) {
                        ForEach(rows, id: \.0) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.0.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(palette.textHint)
                                Text(row.1).foregroundStyle(palette.text)
                            }
                        }
                    }
                }
            }
            .readableOnTv()
            .accessibilityElement(children: .combine)
        }
    }

    private func check(_ ok: Bool, _ words: String, _ detail: String, greyed: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s2) {
            Image(systemName: greyed ? "person.2" : ok ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(greyed ? palette.textHint : ok ? palette.ok : palette.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(words).font(.subheadline.weight(.semibold)).foregroundStyle(greyed ? palette.textHint : palette.text)
                Text(detail).font(.caption).foregroundStyle(greyed ? palette.textHint : palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(greyed ? 0.7 : 1)
    }

    /// How you play it: ready on your server or why not, the controls, and what's reserved for later.
    @ViewBuilder private var howYouPlay: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            SectionTitle(say("wpHowYouPlay"))
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                if ready {
                    check(true, "Ready on your server", "It runs there and streams to this device, so nothing downloads. Moments stay on the server and follow you to every device.")
                } else {
                    check(false, say("wpCantPlayYet"), check?.message ?? console?.unavailable ?? "This console can't play here yet.")
                }
                if let core = check?.core {
                    check(true, core.name ?? core.id, "The core that plays this game, on the server. Licence: \(core.license ?? "not known").")
                }
                if check?.needsGpu == true { check(true, "Uses the server's graphics card", "This console is drawn with one, so it needs a server that has one.") }
                if let pad = console?.pad {
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        Text("Controls").font(.subheadline.weight(.semibold)).foregroundStyle(palette.text)
                        FlowLayout(spacing: Tokens.Space.s2) {
                            ForEach(["D-pad"] + (pad.sticks == true ? ["Stick"] : []) + pad.buttons.map(\.label), id: \.self) { label in
                                Text(label).font(.caption.weight(.semibold)).foregroundStyle(palette.text)
                                    .padding(.horizontal, Tokens.Space.s3).padding(.vertical, Tokens.Space.s1)
                                    .background(Capsule().fill(palette.card))
                            }
                        }
                        Text(controllerNote(pad)).font(.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                check(false, say("wpMultiplayer"), say("wpMultiplayerLater"), greyed: true)
            }
            .padding(metrics.tv ? Tokens.Space.s6 : Tokens.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        }
        .readableOnTv()
        .accessibilityElement(children: .combine)
    }

    private func controllerNote(_ pad: GamePadShape) -> String {
        #if os(tvOS)
        let base = "Game controllers work, and so does the Siri Remote for games that need few buttons. Start and Select together, or the remote's Back button, open the game menu."
        return pad.pointer == true ? base + " This console has a touch screen, which Apple TV can't reach: games that need it are best played on a phone or tablet." : base
        #else
        return "Touch controls are drawn over the game, and game controllers and keyboards work too. Start and Select together, or the menu button, open the game menu."
        #endif
    }

    @ViewBuilder private var notesAndCredits: some View {
        if let note = mine?.note, !note.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                SectionTitle(say("wpYourNotes"))
                Text(note).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .readableOnTv()
            .accessibilityElement(children: .combine)
        }
        if let credits = details?.credits, !credits.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                ForEach(credits, id: \.self) { credit in
                    Secondary([credit.text ?? credit.name, credit.site, credit.license].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                }
            }
            .readableOnTv()
            .accessibilityElement(children: .combine)
        }
    }

    /// The box, and beside it the console and era, and for two or more players "Made for two".
    @ViewBuilder private func boxRow(_ game: GameItem) -> some View {
        let tablet = metrics.gutter > Tokens.Space.s4
        let w: CGFloat = tablet ? 160 : 120, h: CGFloat = tablet ? 213 : 160
        HStack(alignment: .bottom, spacing: Tokens.Space.s4) {
            ShelfCover(item: game, console: console, width: w)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .overlay(alignment: .topTrailing) { if auto != nil { ShelfRibbon().padding(.trailing, Tokens.Space.s3).offset(y: -6) } }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                if !kicker.isEmpty { Text(kicker).font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary) }
                if let players, players > 1 {
                    HStack(spacing: 3) {
                        ForEach(0..<min(players, 4), id: \.self) { _ in Circle().fill(palette.textSecondary).frame(width: 6, height: 6) }
                        Text(say("wpMadeForTwo")).font(.caption).foregroundStyle(palette.textSecondary).padding(.leading, 3)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(say("wpMadeForTwo")): up to \(players) players")
                }
            }
            .padding(.bottom, Tokens.Space.s1)
        }
    }

    /// The name, its facts, and what to do: Resume and Where you left off, or why it can't play.
    @ViewBuilder private func titleAndActions(_ game: GameItem) -> some View {
        let tv = metrics.tv
        VStack(alignment: .leading, spacing: tv ? Tokens.Space.s3 : Tokens.Space.s2) {
            Text(game.title)
                .font(.system(size: tv ? 48 : 30, weight: tv ? .bold : .semibold))
                .tracking(tv ? -1 : -0.66)
                .foregroundStyle(palette.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            let line = facts(game)
            if !line.isEmpty { Text(line).font(.system(size: tv ? 24 : 15)).foregroundStyle(palette.textSecondary) }
            if !error.isEmpty { ProblemLine(error) }
            if check?.ready == false {
                stateCard.padding(.top, Tokens.Space.s2)
            } else if check != nil || console?.ready == true {
                actions.padding(.top, Tokens.Space.s2)
                leftOff
            }
        }
    }

    // MARK: The page

    @ViewBuilder private func phonePage(_ game: GameItem) -> some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            let split = metrics.gutter > Tokens.Space.s4 && outer.size.width >= 700
            ScrollView {
                ScrollTop()
                VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                    if split {
                        HStack(alignment: .top, spacing: Tokens.Space.s8) {
                            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                                boxRow(game)
                                titleAndActions(game)
                                howYouPlay
                            }
                            .frame(width: 360)
                            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                                momentsRow
                                about(game)
                                notesAndCredits
                            }
                            .padding(.top, 60 + Tokens.Space.s4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, metrics.gutter)
                    } else {
                        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                            boxRow(game)
                            titleAndActions(game)
                        }
                        .padding(.horizontal, metrics.gutter)
                        momentsRow
                        about(game).padding(.horizontal, metrics.gutter)
                        howYouPlay.padding(.horizontal, metrics.gutter)
                        notesAndCredits.padding(.horizontal, metrics.gutter)
                    }
                }
                .padding(.top, top + 220 - 60)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .top) {
                    backdrop(game)
                        .frame(height: 220 + top)
                        .frame(maxWidth: .infinity)
                        .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: palette.background, location: 1)],
                                                startPoint: .top, endPoint: .bottom))
                        .clipped()
                }
            }
            .ignoresSafeArea(edges: .top)
            .onAppear { twoColumns = split }
            .onChange(of: split) { twoColumns = $0 }
        }
    }

    #if os(tvOS)
    @ViewBuilder private func tvPage(_ game: GameItem) -> some View {
        ZStack(alignment: .topLeading) {
            backdrop(game)
                .ignoresSafeArea()
                .overlay(LinearGradient(stops: [.init(color: palette.background.opacity(0.96), location: 0), .init(color: palette.background.opacity(0.7), location: 0.45),
                                                .init(color: palette.background.opacity(0.1), location: 1)], startPoint: .leading, endPoint: .trailing).ignoresSafeArea())
                .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: palette.background, location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s10) {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        if !kicker.isEmpty { Text(kicker).font(.system(size: 22, weight: .semibold)).foregroundStyle(palette.textSecondary) }
                        titleAndActions(game)
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.top, 160)
                    momentsRow
                    HStack(alignment: .top, spacing: Tokens.Space.s10) {
                        about(game).frame(maxWidth: .infinity, alignment: .leading)
                        howYouPlay.frame(maxWidth: 760)
                    }
                    .padding(.horizontal, Tokens.gutter)
                    .focusSection()
                    notesAndCredits.padding(.horizontal, Tokens.gutter)
                }
                .padding(.bottom, Tokens.Space.s12)
            }
        }
        .focusScope(scope)
    }
    #endif

    var body: some View {
        ZStack(alignment: .top) {
            if let game {
                #if os(tvOS)
                tvPage(game)
                #else
                phonePage(game)
                #endif
            } else if !error.isEmpty {
                ProblemView(words: error, retry: { error = ""; Task { await load() } })
            } else {
                LoadingView()
            }
        }
        .pageBackground(palette)
        // Again on every return: a game just played has a new moment and time played.
        .task { await load() }
        .alert("Delete this moment?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { delete(deleting) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(deleting.map { momentName($0.slot) } ?? "This moment") can't be brought back, here or on any other device.")
        }
    }
}

/// Why a game can't play, in place of Play: an icon in a tinted circle, the headline and what to do,
/// with the BIOS files needed and found, and a button when there's something to press.
struct GameStateCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let icon: String
    let headline: String
    let detail: String
    var files: [GameBIOS] = []
    var action: (String, Route)?
    var retry: (() -> Void)?

    var body: some View {
        let tv = metrics.tv
        HStack(alignment: .top, spacing: Tokens.Space.s3) {
            Image(systemName: icon)
                .font(.system(size: tv ? 22 : 16, weight: .semibold))
                .foregroundStyle(palette.warn)
                .frame(width: tv ? 48 : 36, height: tv ? 48 : 36)
                .background(Circle().fill(palette.warn.opacity(0.18)))
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(headline).font(.system(size: tv ? 24 : 15, weight: .semibold)).foregroundStyle(palette.text)
                Text(detail).font(.system(size: tv ? 20 : 13)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(files, id: \.file) { b in
                    HStack(spacing: Tokens.Space.s1) {
                        Image(systemName: b.found == true ? "checkmark.circle.fill" : "circle").foregroundStyle(b.found == true ? palette.ok : palette.textHint)
                        Text(b.file).font(.system(size: tv ? 20 : 13, design: .monospaced)).foregroundStyle(palette.text)
                        if let what = b.for, !what.isEmpty { Text(what).font(.system(size: tv ? 18 : 12)).foregroundStyle(palette.textHint) }
                    }
                }
                if action != nil || retry != nil {
                    HStack(spacing: Tokens.Space.s2) {
                        if let action { NavigationLink(action.0, value: action.1).action(pill: true) }
                        if let retry { Button("Try again", action: retry).action(pill: true) }
                    }
                    .padding(.top, Tokens.Space.s1)
                    .remoteSection()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .readableOnTv(action == nil && retry == nil)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// On a TV, words with nothing to press still take focus, so the remote can reach them and the
    /// page scrolls to them. Elsewhere they're simply read.
    @ViewBuilder func readableOnTv(_ wanted: Bool = true) -> some View {
        #if os(tvOS)
        self.focusable(wanted)
        #else
        self
        #endif
    }
}
