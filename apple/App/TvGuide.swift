#if os(tvOS)
import SwiftUI
import WittyKit

// The programme guide on Apple TV, as the server's page draws it (web/src/pages/tv/GuidePage.tsx,
// Hero.tsx and Preview.tsx) under each of WittyTV's themes: at the top, the highlighted channel, its
// programme, what can be done with it and a live preview; below, the filters and times; then the
// grid, half an hour to a column. The remote moves the highlight cell by cell; past either edge of
// the grid it moves the time. Select watches what's on, or says more about what's later; holding
// Select offers everything else, and Play/Pause watches the channel.

/// Where focus can be in the grid: a cell, or one of the two edges that move the time.
enum GuideFocus: Hashable {
    case cell(Int, Int64)
    case earlier, later
}

/// The highlighted row and the moment in it, as the page keeps them.
struct GuideSpot: Equatable {
    var row: Int
    var at: Int64
}

/// What the details sheet is about.
struct GuideAsk: Identifiable {
    let channel: GuideChannel
    let programme: GuideProgramme?
    let cell: GuideCell
    var day = false
    var id: String { channel.key + "|\(cell.start)|\(day)" }
}

/// Which channel to come back to when the guide shows again after watching one.
enum GuideReturn {
    static var key = ""
}

struct GuideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = GuideStore()
    @ObservedObject private var looks = TvLookStore.shared
    @ObservedObject private var live = LiveTv.shared
    @ObservedObject private var reminders = TvReminders.shared
    @ObservedObject private var logos = TvLogos.shared
    @State private var from = GuideRules.floorSlot(Int64(Date().timeIntervalSince1970))
    @State private var spot = GuideSpot(row: 0, at: Int64(Date().timeIntervalSince1970))
    @State private var now = Int64(Date().timeIntervalSince1970)
    @State private var ask: GuideAsk?
    @State private var lookOpen = false
    @State private var searchOpen = false
    @State private var dayOpen = false
    @State private var toast = ""
    @State private var notices: [String: String] = [:]
    @State private var placed = false
    @State private var visible = Set<Int>()
    @FocusState private var focused: GuideFocus?

    private var dress: TvDress { looks.dress }
    private var slots: Int { GuideRules.slots(hours: dress.look.hours, width: 1920) }
    private var to: Int64 { from + Int64(slots) * GuideRules.slot }
    /// The grid's own width: the page less its edges and the channels.
    private var trackWidth: CGFloat { 1920 - dress.edge * 2 - dress.channelWidth }
    private var perSecond: Double { Double(trackWidth) / Double(to - from) }

    private var current: GuideChannel? { store.rows[spot.row] }
    private var cells: [GuideCell] { GuideRules.cells(current, from: from, to: to, pointsPerSecond: perSecond) }
    private var currentCell: GuideCell? { GuideRules.cell(at: spot.at, in: cells) }

    var body: some View {
        let p = dress.paint
        ZStack {
            p.bg.ignoresSafeArea()
            if store.total == 0, store.filter.isAll {
                EmptyMessage(title: "No channels yet",
                             detail: model.user?.isAdmin == true ? "Make channels out of your library in one click, or add a tuner or an IPTV playlist, in the server's TV settings." : "Ask whoever runs this server to set some up.")
            } else if store.total == nil, !store.error.isEmpty {
                ProblemView(words: store.error, retry: { store.error = ""; Task { await store.ensure(0) } })
            } else if store.total == nil {
                LoadingView()
            } else {
                // Exactly the screen, edge to edge: the grid takes what the rest leaves.
                GeometryReader { screen in
                    page.frame(width: screen.size.width, height: screen.size.height, alignment: .top)
                }
                .ignoresSafeArea()
            }
            if !toast.isEmpty { toastView }
        }
        .environment(\.colorScheme, dress.look.bgIsDark ? .dark : .light)
        // WittyTV has the whole screen, as the page does: the tabs are a Back away.
        .toolbar(.hidden, for: .tabBar)
        .task { await start() }
        .task(id: previewWanted) { await settlePreview() }
        .task { await tick() }
        .onChange(of: focused) { next in arrive(next) }
        .onChange(of: store.filter) { _ in spot = GuideSpot(row: 0, at: spot.at); placed = false }
        .onAppear { comeBack() }
        // A look changed on another device shows when this one is picked up again.
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await looks.load(client: client, themeId: model.effectiveThemeId, app: model.tvAppColours) } }
        }
        .onDisappear { leaveIfDone() }
        .sheet(item: $ask) { a in
            GuideDetails(ask: a, now: now, onWatch: { key in ask = nil; watch(key) }, onSaid: say)
        }
        .sheet(isPresented: $lookOpen) { TvLookPanel() }
        .sheet(isPresented: $searchOpen) { GuideSearch { hit in searchOpen = false; go(to: hit) } }
        .confirmationDialog("Day", isPresented: $dayOpen) {
            ForEach(0..<15, id: \.self) { n in
                Button(n == 0 ? "Today" : n == 1 ? "Tomorrow" : GuideRules.dayName(today + Int64(n) * 86400 + 3600)) { goDay(n) }
            }
        }
    }

    private var today: Int64 { Int64(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now))).timeIntervalSince1970) }

    // MARK: The page

    private var page: some View {
        VStack(spacing: 0) {
            GuideHero(dress: dress, channel: current, cell: currentCell, programme: currentCell?.programme(at: spot.at),
                      next: GuideRules.next(after: currentCell?.programme(at: spot.at), cell: currentCell, on: current), now: now,
                      preview: previewKey, onWatch: watch, onDetails: { details(day: false) }, onDay: { details(day: true) },
                      onFavourite: favourite, onStep: { moveRow(spot.row + $0) }, onRecord: record, onSaid: say)
            bar
            if !store.error.isEmpty {
                Text(store.error).font(dress.font(25, .bold)).foregroundStyle(dress.paint.err)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, dress.edge).padding(.vertical, 8).background(dress.paint.panel)
            }
            grid
            if [.box, .receiver, .teletext, .listings].contains(dress.shape) { footer }
            legal
        }
        .padding(.bottom, dress.foot / 2)
    }

    // MARK: The strip between the top and the grid

    private var bar: some View {
        let p = dress.paint
        let all = store.filter.isAll
        let hasBoth = store.lineup.contains { $0.kind == "tuner" } && store.lineup.contains { $0.kind == "library" }
        let anyFavourite = store.lineup.contains { $0.favourite == true }
        return HStack(spacing: 16) {
            dress.words("Guide", barTitle.size, barTitle.weight, smallCaps: true).foregroundColor(barTitleColour)
                .tvCase(dress.capitals, tracking: dress.shape == .receiver ? 2.4 : 0)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    chip("All", on: all) { store.setFilter(.init()) }
                    if anyFavourite || store.filter.favourites {
                        chip("★ Favourites", on: store.filter.favourites) { store.setFilter(.init(favourites: !store.filter.favourites)) }
                    }
                    ForEach(store.groups, id: \.self) { g in
                        chip(g, on: store.filter.group == g) { store.setFilter(.init(group: store.filter.group == g ? "" : g)) }
                    }
                    if hasBoth {
                        chip("My library", on: store.filter.kind == "library") { store.setFilter(.init(kind: store.filter.kind == "library" ? "" : "library")) }
                        chip("Live TV", on: store.filter.kind == "tuner") { store.setFilter(.init(kind: store.filter.kind == "tuner" ? "" : "tuner")) }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                Button { shift(-GuideRules.slot) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(TvButtonStyle(dress: dress, kind: .icon, onBar: true)).accessibilityLabel("Half an hour earlier")
                Button("Now") { goNow() }.buttonStyle(TvButtonStyle(dress: dress, on: GuideRules.floorSlot(now) == from, onBar: true))
                Button { shift(GuideRules.slot) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(TvButtonStyle(dress: dress, kind: .icon, onBar: true)).accessibilityLabel("Half an hour later")
                ForEach(GuideRules.jumps(now: now), id: \.label) { j in
                    Button(j.label) { goAt(j.at) }.buttonStyle(TvButtonStyle(dress: dress, kind: .link, onBar: true))
                }
                Button { dayOpen = true } label: { Text(dayLabel + " ▾") }.buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                Button { searchOpen = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(TvButtonStyle(dress: dress, kind: .icon, onBar: true)).accessibilityLabel("Search the schedule")
                Button("Look") { lookOpen = true }.buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                NavigationLink(value: Route.recordings) { Text("Recordings") }.buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                if model.user?.isAdmin == true {
                    NavigationLink(value: Route.page("/tv/channels")) { Label("Edit channels", systemImage: "gearshape") }
                        .buttonStyle(TvButtonStyle(dress: dress, onBar: true))
                }
            }
            .padding(.vertical, 10)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, dress.edge - 8)
        .frame(maxWidth: .infinity)
        .background(barFill)
        .overlay { barRules }
        .focusSection()
    }

    private var dayLabel: String {
        let n = Int((Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(from))).timeIntervalSince1970 - Double(today)) / 86400)
        return n < 0 ? "Yesterday" : n == 0 ? "Today" : n == 1 ? "Tomorrow" : GuideRules.dayName(from)
    }

    private var barTitle: (size: CGFloat, weight: Font.Weight) {
        switch dress.shape {
        case .modern: return (25, .bold)
        case .receiver: return (17.5, .medium)
        case .teletext: return (18.75, .bold)
        case .listings: return (30, .bold)
        case .outline: return (25, .light)
        case .compact: return (17.5, .bold)
        default: return (21.25, .bold)
        }
    }

    private var barTitleColour: Color {
        [.modern, .listings, .cinema, .outline, .compact].contains(dress.shape) ? dress.paint.text : dress.paint.accent
    }

    @ViewBuilder private var barFill: some View {
        switch dress.shape {
        case .modern, .receiver, .listings, .cinema, .outline: dress.paint.bg
        case .teletext: dress.paint.panel2
        default: dress.paint.panel
        }
    }

    @ViewBuilder private var barRules: some View {
        switch dress.shape {
        case .receiver: Rule(edge: .bottom, colour: dress.paint.panel2)
        case .listings: Rule(edge: .bottom, colour: dress.paint.text)
        case .cinema: Rule(edge: .top, colour: dress.paint.panel2)
        default: EmptyView()
        }
    }

    private func chip(_ words: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(words) }
            .buttonStyle(TvButtonStyle(dress: dress, kind: .chip, on: on, onBar: true))
            .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: The grid

    private var grid: some View {
        let p = dress.paint
        let total = store.total ?? 0
        return VStack(spacing: 0) {
            GuideTimes(dress: dress, from: from, now: now, slots: slots)
            ZStack(alignment: .topLeading) {
                ScrollViewReader { scroller in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<total, id: \.self) { r in
                                row(r).id(r)
                                    .onAppear { visible.insert(r); Task { await store.ensure(r) } }
                                    .onDisappear { visible.remove(r) }
                            }
                        }
                    }
                    .onChange(of: spot.row) { r in
                        if case .cell = focused {} else { withAnimation(nil) { scroller.scrollTo(r, anchor: .center) } }
                    }
                }
                edges
            }
            .frame(maxHeight: .infinity)
            // A TV's scroll view draws past its edges, for lifted cards; the grid's rows stop at its own.
            .clipped()
            if total == 0 {
                Text(store.filter.favourites ? "No favourites yet: hold Select on a channel to make it one." : "No channels match that.")
                    .font(dress.font(25, .bold)).foregroundStyle(p.err).padding(.vertical, 12)
            }
        }
        .overlay(alignment: .topLeading) {
            if dress.look.nowLine, now >= from, now < to {
                GuideNowLine(dress: dress, x: dress.channelWidth + trackWidth * CGFloat(now - from) / CGFloat(to - from), now: now)
            }
        }
        .padding(.horizontal, dress.edge)
        .frame(minHeight: 260)
        .focusSection()
    }

    /// The grid's two edges: moving onto one is moving the time.
    private var edges: some View {
        HStack(spacing: 0) {
            Button {} label: { Color.clear.frame(width: 6).frame(maxHeight: .infinity) }
                .buttonStyle(TvEdgeStyle()).focused($focused, equals: .earlier)
                .padding(.leading, dress.channelWidth - 10)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Button {} label: { Color.clear.frame(width: 6).frame(maxHeight: .infinity) }
                .buttonStyle(TvEdgeStyle()).focused($focused, equals: .later)
                .accessibilityHidden(true)
        }
        // Just outside the cells on both sides: the focus engine only goes to what's wholly beside it.
        .padding(.trailing, -10)
    }

    @ViewBuilder private func row(_ r: Int) -> some View {
        let channel = store.rows[r]
        GuideRow(dress: dress, index: r, channel: channel, from: from, to: to, perSecond: perSecond, now: now,
                 current: r == spot.row, focusAt: r == spot.row ? spot.at : nil, logo: logos.info(channel?.brand),
                 reminded: { channel.map { c in { reminders.has(c.key, $0) } } ?? { _ in false } }(),
                 focused: $focused,
                 activate: activate, more: { cell, day in if let channel { ask = GuideAsk(channel: channel, programme: cell.programme(at: spot.at), cell: cell, day: day) } },
                 record: { cell in if let channel, let p = cell.programme { record(channel, p) } },
                 series: { cell in if let channel, let p = cell.programme { series(channel, p) } },
                 remind: { cell in if let channel, let p = cell.programme { remind(channel, p) } },
                 favourite: { if let channel { favourite(channel) } },
                 watch: { if let channel { watch(channel.key) } })
            .frame(height: dress.rowHeight)
    }

    // MARK: Underneath

    private var footer: some View {
        let p = dress.paint
        let kind = store.filter.kind
        return HStack(spacing: 16) {
            key("A", "Day −", p.keyA) { shift(-86400) }
            key("B", "Day +", p.keyB) { shift(86400) }
            key("C", kind.isEmpty ? "All" : kind == "library" ? "Library" : "Live TV", p.keyC) { cycleKind() }
            Spacer(minLength: 16)
            Text("▲▼ Channel · ◄► Time · Select Watch · Hold Select for more · Play/Pause Watch the channel")
                .font(dress.font(17.5)).foregroundStyle(p.soft).lineLimit(1).truncationMode(.tail)
                .italic(dress.shape == .listings)
        }
        .padding(.horizontal, dress.edge)
        .padding(.vertical, 6)
        .background {
            switch dress.shape {
            case .box: LinearGradient(colors: [p.panel, p.bg], startPoint: .top, endPoint: .bottom)
            default: p.bg
            }
        }
        .overlay {
            switch dress.shape {
            case .box: Rule(edge: .top, colour: p.line, width: 3)
            case .receiver: Rule(edge: .top, colour: p.line)
            case .listings: Rule(edge: .top, colour: p.text)
            default: EmptyView()
            }
        }
        .focusSection()
    }

    private func key(_ letter: String, _ words: String, _ colour: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(letter).font(dress.font(15, .bold)).foregroundStyle(dress.paint.keyText)
                    .frame(width: 26, height: 26)
                    .background(dress.shape == .receiver || dress.shape == .teletext ? AnyView(Rectangle().fill(colour)) : AnyView(Circle().fill(colour)))
                Text(words)
            }
        }
        .buttonStyle(TvButtonStyle(dress: dress, kind: .link))
    }

    private var legal: some View {
        let shown = [notices["tv"], dress.look.logos && store.lineup.contains { $0.logo?.hasPrefix("/") == true || logos.info($0.brand)?.has == true } ? notices["logos"] : nil].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(shown, id: \.self) { Text($0).font(.system(size: 13.75)).foregroundStyle(dress.paint.soft).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, dress.edge)
        .padding(.vertical, shown.isEmpty ? 0 : 8)
        .accessibilityElement(children: .combine)
    }

    private var toastView: some View {
        VStack {
            Spacer()
            Text(toast).font(.wmLabel).foregroundStyle(dress.paint.hiText)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(Capsule().fill(dress.paint.hi))
                .padding(.bottom, 60)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: What happens

    private func start() async {
        store.use(client)
        async let lookLoaded: Void = looks.load(client: client, themeId: model.effectiveThemeId, app: model.tvAppColours)
        async let remindersLoaded: Void = reminders.load(client: client)
        store.setFrom(from)
        await store.ensure(0)
        await store.loadLineup()
        _ = await (lookLoaded, remindersLoaded)
        model.channels = store.lineup
        await logos.ask(store.lineup.compactMap(\.brand), client: client)
        if notices.isEmpty, let all = try? await client.legalNoticeWords() { notices = all }
        placeFirstFocus()
    }

    /// The channel just watched, in the middle of the rows, at now, with the highlight on it.
    private func placeFirstFocus() {
        guard !placed, store.total != nil else { return }
        placed = true
        var r = 0
        if !GuideReturn.key.isEmpty, let i = store.index(of: GuideReturn.key) { r = i }
        GuideReturn.key = ""
        let at = Int64(Date().timeIntervalSince1970)
        from = GuideRules.floorSlot(at)
        store.setFrom(from)
        spot = GuideSpot(row: r, at: at)
        Task {
            await store.ensure(r)
            focusCell(row: r, at: at)
        }
    }

    private func comeBack() {
        guard placed, !GuideReturn.key.isEmpty, let r = store.index(of: GuideReturn.key) else { return }
        GuideReturn.key = ""
        let at = Int64(Date().timeIntervalSince1970)
        if at >= to || at < from { from = GuideRules.floorSlot(at); store.setFrom(from) }
        spot = GuideSpot(row: r, at: at)
        Task { await store.ensure(r); focusCell(row: r, at: at) }
    }

    /// Focus on the cell of a row at a moment, once it's drawn.
    private func focusCell(row: Int, at: Int64) {
        let rowCells = GuideRules.cells(store.rows[row], from: from, to: to, pointsPerSecond: perSecond)
        guard let cell = GuideRules.cell(at: at, in: rowCells) else { return }
        DispatchQueue.main.async { focused = .cell(row, cell.start) }
    }

    /// Focus has moved: onto a cell, which the top of the page follows, or onto an edge, which moves the time.
    private func arrive(_ next: GuideFocus?) {
        switch next {
        case .cell(let r, let start)?:
            spot = GuideSpot(row: r, at: max(start, from))
        case .later?:
            let end = currentCell?.end ?? to
            shift(GuideRules.slot, at: max(end, to))
        case .earlier?:
            if from <= GuideRules.floorSlot(now) - GuideRules.earliest {
                focusCell(row: spot.row, at: spot.at)
            } else {
                shift(-GuideRules.slot, at: from - GuideRules.slot)
            }
        case nil:
            break
        }
    }

    private func shift(_ seconds: Int64, at: Int64? = nil) {
        let next = GuideRules.shifted(from, by: seconds, now: now)
        let span = Int64(slots) * GuideRules.slot
        let target = at ?? max(next, min(next + span - 1, spot.at + seconds))
        from = next
        store.setFrom(next)
        spot.at = min(max(target, next), next + span - 1)
        reload()
        focusCell(row: spot.row, at: spot.at)
    }

    private func goAt(_ at: Int64, row: Int? = nil) {
        from = GuideRules.floorSlot(at)
        store.setFrom(from)
        spot = GuideSpot(row: row ?? spot.row, at: at)
        reload()
        focusCell(row: spot.row, at: at)
    }

    private func goNow() { goAt(Int64(Date().timeIntervalSince1970)) }

    private func goDay(_ n: Int) {
        if n == 0 { goNow(); return }
        shift(today + Int64(n) * 86400 - (Int64(Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(from))).timeIntervalSince1970)))
    }

    private func moveRow(_ r: Int) {
        let row = max(0, min((store.total ?? 1) - 1, r))
        spot.row = row
        Task { await store.ensure(row); focusCell(row: row, at: spot.at) }
    }

    private func reload() {
        let rows = visible.isEmpty ? [spot.row] : Array(visible)
        Task { for r in Set(rows.map { $0 / GuideRules.page * GuideRules.page }) { await store.ensure(r) } }
    }

    private func cycleKind() {
        let k = store.filter.kind
        store.setFilter(.init(kind: k.isEmpty ? "library" : k == "library" ? "tuner" : ""))
    }

    /// The clock, a little at a time, and the guide kept current while it's open.
    private func tick() async {
        var minutes = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            now = Int64(Date().timeIntervalSince1970)
            minutes += 1
            if minutes % 10 == 0 { store.refresh(); reload() }
        }
    }

    private func activate(_ channel: GuideChannel, _ cell: GuideCell) {
        if !channel.canTune || cell.kind == .group {
            ask = GuideAsk(channel: channel, programme: cell.programme(at: spot.at), cell: cell)
            return
        }
        let live = cell.kind == .none ? cell.start <= now + 60 : cell.isOn(at: now)
        if live { watch(channel.key) } else { ask = GuideAsk(channel: channel, programme: cell.programme, cell: cell) }
    }

    private func details(day: Bool) {
        guard let current, let cell = currentCell else { return }
        ask = GuideAsk(channel: current, programme: cell.programme(at: spot.at), cell: cell, day: day)
    }

    private func watch(_ key: String) {
        GuideReturn.key = key
        model.path.append(.channel(key: key))
    }

    private func record() {
        guard let current, let p = currentCell?.programme(at: spot.at) else { return }
        record(current, p)
    }

    private func record(_ channel: GuideChannel, _ p: GuideProgramme) {
        Task {
            do {
                try await client.record(channel: channel.key, title: p.title, sub: p.sub, start: p.start, stop: p.end)
                say("Recording \(p.title)")
            } catch { say((error as? APIError)?.message ?? "That couldn't be recorded.") }
        }
    }

    private func series(_ channel: GuideChannel, _ p: GuideProgramme) {
        Task {
            do {
                try await client.recordSeries(channel: channel.key, title: p.title)
                say("Every airing of \(p.title) will be recorded")
            } catch { say((error as? APIError)?.message ?? "That couldn't be recorded.") }
        }
    }

    private func remind(_ channel: GuideChannel, _ p: GuideProgramme) {
        Task { say(await reminders.toggle(channel.key, p)) }
    }

    private func favourite() { if let current { favourite(current) } }

    private func favourite(_ channel: GuideChannel) {
        let on = channel.favourite != true
        Task {
            do {
                try await store.setFavourite(channel, on)
                say(on ? "\(channel.name) added to favourites" : "\(channel.name) removed from favourites")
            } catch { say((error as? APIError)?.message ?? "That didn't work. Try again.") }
        }
    }

    private func go(to hit: GuideHit) {
        if let i = store.index(of: hit.channel) {
            goAt(hit.start, row: i)
            Task { await store.ensure(i) }
        } else {
            store.setFilter(.init())
            let i = store.lineup.firstIndex { $0.key == hit.channel } ?? 0
            goAt(hit.start, row: i)
            Task { await store.ensure(i); focusCell(row: i, at: hit.start) }
        }
    }

    private func say(_ words: String) {
        announce(words)
        withAnimation { toast = words }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast == words { withAnimation { toast = "" } }
        }
    }

    // MARK: The preview

    /// What the preview would show: the highlighted channel, the last one watched, or nothing.
    private var previewWanted: String {
        switch dress.look.preview {
        case "off": return ""
        case "last": return LastChannel.current.isEmpty ? (current?.canTune == true ? current!.key : "") : LastChannel.current
        default: return current.map { $0.canTune ? $0.key : "" } ?? ""
        }
    }

    /// The channel the preview shows once the highlight has settled on it.
    private var previewKey: String { previewWanted }

    /// Each channel the preview shows runs a stream, so it waits for the highlight to settle, and one
    /// that was only flicked past isn't tuned at all.
    private func settlePreview() async {
        let want = previewWanted
        live.muted = !dress.look.previewSound
        if want.isEmpty { live.stop(); return }
        if want == live.key, !live.isFailed { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if Task.isCancelled { return }
        live.watch(want, client: client)
    }

    /// Back out of the guide to Home: nothing is watched any more. Into a channel: it carries on there.
    private func leaveIfDone() {
        DispatchQueue.main.async {
            if !model.path.contains(where: { if case .channel = $0 { return true }; return $0 == .guide }) { live.stop() }
        }
    }
}

// MARK: - The top of the page

struct GuideHero: View {
    @Environment(\.client) private var client
    @ObservedObject private var reminders = TvReminders.shared
    @ObservedObject private var looks = TvLookStore.shared
    @ObservedObject private var live = LiveTv.shared
    @ObservedObject private var logos = TvLogos.shared
    @EnvironmentObject private var model: AppModel
    let dress: TvDress
    let channel: GuideChannel?
    let cell: GuideCell?
    let programme: GuideProgramme?
    let next: GuideProgramme?
    let now: Int64
    let preview: String
    let onWatch: (String) -> Void
    let onDetails: () -> Void
    let onDay: () -> Void
    let onFavourite: () -> Void
    let onStep: (Int) -> Void
    let onRecord: () -> Void
    let onSaid: (String) -> Void
    @State private var art: Int64?

    private var shape: TvShape { dress.shape }
    private var showsClock: Bool { [.box, .receiver, .teletext, .listings].contains(shape) }
    private var showsArt: Bool { dress.look.art && shape.art }

    var body: some View {
        let p = dress.paint
        HStack(alignment: shape == .cinema ? .center : .top, spacing: shape == .cinema ? 24 : 16) {
            // Each column is a section, so left and right go between them wherever their buttons are.
            if dress.look.previewSide == "left", dress.look.preview != "off" { previewBox.focusSection() }
            main.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: shape == .cinema ? .leading : .topLeading).focusSection()
            if dress.look.previewSide == "right", dress.look.preview != "off" { previewBox.focusSection() }
            if showsClock { clock }
        }
        // As tall as the taller column, which the other then fills, so the remote finds it beside it.
        .fixedSize(horizontal: false, vertical: true)
        // The page's --ctv-top, measured from what the screen really shows.
        .padding(.top, dress.top + 16 + (shape == .teletext ? 44 : 0))
        .padding(.horizontal, dress.edge)
        .padding(.bottom, shape == .compact ? 8 : 16)
        .background { background }
        .overlay(alignment: .topLeading) {
            if shape == .teletext {
                Text("P100  WITTYTV  GUIDE").font(dress.font(17.5)).tracking(1.75).foregroundStyle(p.soft)
                    .padding(.top, dress.top + 16).padding(.leading, dress.edge).accessibilityHidden(true)
            }
        }
        .overlay { rules }
        .clipped()
        .focusSection()
        .task(id: "\(programme?.itemId ?? 0)|\(showsArt)") {
            art = nil
            guard showsArt, let id = programme?.itemId else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled { art = id }
        }
    }

    @ViewBuilder private var background: some View {
        let p = dress.paint
        ZStack {
            switch shape {
            case .modern: LinearGradient(colors: [p.panel, p.bg], startPoint: .top, endPoint: .bottom)
            case .receiver: p.panel
            case .teletext, .listings, .cinema, .outline, .compact: p.bg
            case .box: LinearGradient(colors: [p.panel2, p.panel], startPoint: .top, endPoint: .bottom)
            }
            if let art, let url = client.mediaURL("/api/items/\(art)/backdrop") {
                ArtImage(url: url, width: 1920, blank: true)
                    .opacity(shape == .outline ? 0.12 : 0.22)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing))
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var rules: some View {
        let p = dress.paint
        switch shape {
        case .box: Rule(edge: .bottom, colour: p.line, width: 4)
        case .receiver: Rule(edge: .bottom, colour: p.accent)
        case .listings:
            VStack(spacing: 2) { Spacer(); p.text.frame(height: 1); p.text.frame(height: 1) }
        case .compact: Rule(edge: .bottom, colour: p.line)
        default: EmptyView()
        }
    }

    private var main: some View {
        let p = dress.paint
        let real = programme != nil && cell?.kind == .programme
        return VStack(alignment: .leading, spacing: 0) {
            channelLine
            title
            meta
            if real, let programme { when(programme) }
            if let next {
                (Text("Next ") + Text(tvClock(next.start)).bold().foregroundColor(p.text) + Text(" " + next.title))
                    .font(dress.font(dress.heroFacts)).foregroundStyle(p.soft).lineLimit(1)
                    .padding(.top, shape == .modern ? 6 : shape == .cinema || shape == .outline ? 8 : 3)
            }
            if shape != .compact, let desc = programme?.desc, !desc.isEmpty {
                Text(desc).font(dress.font(dress.heroFacts)).foregroundStyle(p.soft).lineLimit(2).padding(.top, 4)
            }
            if channel?.security?.state == "encrypted", let s = channel?.security {
                (Text(s.label + ". ").bold() + Text(s.detail)).font(dress.font(dress.heroFacts)).foregroundStyle(p.soft).lineLimit(2).padding(.top, 4)
            }
            ForEach(channel?.notices ?? [], id: \.self) { n in
                Text(n).font(dress.font(dress.heroFacts)).foregroundStyle(p.soft).lineLimit(2).padding(.top, 4)
            }
            actions
        }
        .shadow(color: shape == .modern || shape == .outline ? p.bg : .clear, radius: 3, y: 1)
    }

    private var channelLine: some View {
        let p = dress.paint
        let n = dress.heroNumber
        return HStack(spacing: 10) {
            if let channel {
                Text(channel.number ?? "")
                    .font(dress.font(n.size, n.weight, digits: shape == .receiver))
                    .italic(shape == .listings)
                    .tracking(shape == .receiver ? 2 : 0)
                    .monospacedDigit()
                    .foregroundStyle(shape == .modern ? p.text : p.accent)
                    .padding(.horizontal, shape == .receiver ? 8 : 0)
                    .overlay { if shape == .receiver { Rectangle().strokeBorder(p.accent, lineWidth: 1) } }
                ChannelLogo(dress: dress, channel: channel, size: dress.heroLogo, highlighted: false)
                VStack(alignment: .leading, spacing: 0) {
                    dress.words(channel.name, dress.heroChannel, .bold, smallCaps: true)
                        .foregroundColor(shape == .teletext ? p.soft : p.text)
                        .tvCase(shape == .receiver || shape == .teletext, tracking: shape == .receiver ? 2 : 0)
                    if shape != .compact, let d = channel.description, !d.isEmpty {
                        Text(d).font(dress.font(dress.heroChannel)).italic(shape == .listings)
                            .foregroundStyle(shape == .teletext ? p.text : p.soft)
                    }
                }
                .lineLimit(1)
            } else {
                Image(systemName: "tv").font(.system(size: 22)).foregroundStyle(p.soft)
            }
        }
        .frame(minHeight: 26)
    }

    private var title: some View {
        let p = dress.paint
        let t = dress.heroTitle
        let words = programme?.title ?? channel?.name ?? " "
        return Group {
            if shape == .teletext {
                Text(words).font(dress.font(t.size, t.weight)).textCase(.uppercase).foregroundStyle(p.accent).lineLimit(1)
                    .scaleEffect(x: 1, y: 1.7, anchor: .topLeading)
                    .padding(.bottom, t.size * 0.75)
                    .padding(.top, 12)
            } else {
                Text(words)
                    .font(dress.font(t.size, t.weight))
                    .tracking(shape == .modern || shape == .cinema || shape == .outline ? -t.size * 0.022 : shape == .receiver ? t.size * 0.03 : 0)
                    .textCase(shape == .receiver ? .uppercase : nil)
                    .foregroundStyle(p.text)
                    .lineLimit(shape == .compact ? 1 : 2)
                    .padding(.top, shape == .modern ? 6 : shape == .cinema ? 12 : shape == .receiver || shape == .listings || shape == .outline ? 8 : shape == .compact ? 2 : 4)
                    .shadow(color: shape == .box ? .black.opacity(0.6) : .clear, radius: 0, x: 1, y: 1)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var meta: some View {
        let p = dress.paint
        var bits: [AnyView] = []
        if let sub = programme?.sub, !sub.isEmpty {
            let colour: Color = [.modern, .cinema, .outline, .compact].contains(shape) || shape == .teletext ? p.soft : shape == .listings ? p.text : p.accent
            let weight: Font.Weight = shape == .box ? .bold : shape == .teletext || shape == .listings || shape == .outline ? .regular : .medium
            bits.append(AnyView(Text(sub).font(dress.font(dress.heroFacts, weight)).italic(shape == .listings).foregroundStyle(colour).lineLimit(1)))
        }
        if let year = programme?.year { bits.append(AnyView(Text(String(year)))) }
        if let genre = programme?.genre, !genre.isEmpty { bits.append(AnyView(Text(genre))) }
        for tag in [programme?.rating, channel?.hd == true ? "HD" : nil, channel?.atsc3 == true ? "ATSC 3.0" : nil,
                    channel?.security?.state == "clear" ? "Clear" : channel?.security?.state == "unknown" ? channel?.security?.label : nil].compactMap({ $0 }) {
            bits.append(AnyView(Text(tag).font(dress.font(15, .bold)).padding(.horizontal, 5)
                .overlay(RoundedRectangle(cornerRadius: dress.radius).strokeBorder(p.soft, lineWidth: 1))))
        }
        return HStack(spacing: 10) { ForEach(bits.indices, id: \.self) { bits[$0] } }
            .font(dress.font(dress.heroFacts)).foregroundStyle(p.soft)
            .padding(.top, shape == .modern ? 6 : shape == .cinema || shape == .outline ? 8 : 3)
    }

    private func when(_ programme: GuideProgramme) -> some View {
        let p = dress.paint
        let later = programme.start > now
        let on = programme.isOn(at: now)
        let barHeight: CGFloat = shape == .receiver || shape == .compact ? 4 : shape == .teletext ? 8 : shape == .listings || shape == .outline ? 2 : 6
        return HStack(spacing: 10) {
            Text((later ? GuideRules.dayName(programme.start) + ", " : "") + GuideRules.span(programme.start, programme.end))
                .font(dress.font(dress.heroFacts, shape == .listings || shape == .outline ? .regular : .bold))
                .foregroundStyle(p.text)
            if on {
                GeometryReader { box in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(shape == .teletext ? p.panel2 : shape == .listings ? p.line : p.lite)
                        Rectangle().fill(p.accent).frame(width: box.size.width * programme.fraction(at: now))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: shape == .receiver || shape == .teletext ? 0 : dress.radius))
                }
                .frame(minWidth: 80, maxWidth: 320).frame(height: barHeight)
                .accessibilityLabel("How far through").accessibilityValue("\(Int(programme.fraction(at: now) * 100)) percent")
                Text(GuideRules.left(programme.end - max(now, programme.start)) + " left").font(dress.font(dress.heroFacts)).foregroundStyle(p.soft)
            }
        }
        .padding(.top, shape == .modern ? 8 : shape == .cinema || shape == .outline ? 8 : 5)
    }

    private var actions: some View {
        let later = (programme?.start ?? 0) > now
        let reminded = channel.map { c in programme.map { reminders.has(c.key, $0.start) } ?? false } ?? false
        let isTitle = cell?.kind == .programme && programme?.itemId != nil
        let isFilm = isTitle && programme?.showId == nil
        return FlowLayout(spacing: 16, rowSpacing: 12) {
            if let channel, let alt = channel.alternative {
                Button("Watch \(alt.number) \(alt.name) instead") { onWatch(alt.key) }.buttonStyle(TvButtonStyle(dress: dress, on: true))
            }
            if let channel, channel.canTune {
                if later, let programme {
                    Button(reminded ? "✓ Reminder set" : "Remind me") { Task { onSaid(await reminders.toggle(channel.key, programme)) } }
                        .buttonStyle(TvButtonStyle(dress: dress, on: !reminded))
                    Button { onWatch(channel.key) } label: { Label("Watch channel", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(TvButtonStyle(dress: dress))
                } else {
                    Button { onWatch(channel.key) } label: { Label("Watch full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(TvButtonStyle(dress: dress, on: true))
                }
            }
            if isTitle, let id = programme?.itemId {
                NavigationLink(value: Route.player(id, startOver: true)) { Label("Start over", systemImage: "backward.end") }
                    .buttonStyle(TvButtonStyle(dress: dress))
                NavigationLink(value: programme?.showId.map { Route.show($0) } ?? Route.item(id)) {
                    Label(isFilm ? "Open the film" : "Open the show", systemImage: "film")
                }
                .buttonStyle(TvButtonStyle(dress: dress))
            }
            if channel?.canRecord == true, cell?.isBroadcast == true, (programme?.end ?? 0) > now {
                Button("● Record", action: onRecord).buttonStyle(TvButtonStyle(dress: dress))
            }
            if let channel {
                Button(action: onFavourite) { Image(systemName: channel.favourite == true ? "star.fill" : "star") }
                    .buttonStyle(TvButtonStyle(dress: dress, kind: .icon))
                    .foregroundStyle(channel.favourite == true ? dress.paint.accent : dress.paint.text)
                    .accessibilityLabel("Favourite channel").accessibilityAddTraits(channel.favourite == true ? [.isSelected] : [])
            }
            Button { onStep(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).accessibilityLabel("Channel down")
            Button { onStep(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).accessibilityLabel("Channel up")
            Button(action: onDetails) { Image(systemName: "info.circle") }.buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).accessibilityLabel("More about this programme")
            Button("Day", action: onDay).buttonStyle(TvButtonStyle(dress: dress))
            if dress.look.preview == "off" {
                Button("Show preview") { looks.change(["preview": "highlight"], client: client) }.buttonStyle(TvButtonStyle(dress: dress))
            }
        }
        .padding(.top, shape == .modern || shape == .outline ? 12 : shape == .cinema ? 16 : 8)
    }

    private var clock: some View {
        let p = dress.paint
        let big: CGFloat = shape == .teletext || shape == .listings ? 25 : 47.5
        return VStack(alignment: .trailing, spacing: 0) {
            Text(tvClock(now)).font(dress.font(big, shape == .box ? .bold : .regular, digits: shape == .receiver))
                .italic(shape == .listings).monospacedDigit().foregroundStyle(p.accent).lineLimit(1)
            Text(GuideRules.dayName(now)).font(dress.font(shape == .receiver ? 16.25 : 25)).tvCase(shape == .receiver, tracking: 1.3)
                .foregroundStyle(p.soft).lineLimit(1)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    // The little TV: a column of the top of the page, not a layer over it, so it covers nothing.
    private var previewBox: some View {
        GuidePreview(dress: dress, channel: preview, name: previewName, onWatch: onWatch)
    }

    private var previewName: String {
        if let channel, channel.key == preview { return "\(channel.number ?? "") \(channel.name)" }
        return model.channels.first { $0.key == preview }.map { "\($0.number ?? "") \($0.name)" } ?? ""
    }
}

/// The little TV on the guide, with its own bar: smaller, larger, sound, full screen and hide.
struct GuidePreview: View {
    @Environment(\.client) private var client
    @ObservedObject private var live = LiveTv.shared
    @ObservedObject private var looks = TvLookStore.shared
    let dress: TvDress
    let channel: String
    let name: String
    let onWatch: (String) -> Void

    private var most: Double { TvLook.previewLimit(pageWidth: 1920, pageHeight: 1080) }
    private var least: Double { min(TvLook.previewMin, most) }
    private var width: Double { max(least, min(most, dress.look.previewW ?? TvLook.previewAuto(dress.shape, pageWidth: 1920, pageHeight: 1080))) }

    var body: some View {
        let p = dress.paint
        let shape = dress.shape
        let radius: CGFloat = shape == .modern || shape == .outline ? 14 : shape == .cinema ? 10 : shape == .compact ? 6 : 0
        let pictureBar = shape == .modern || shape == .cinema
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if live.key == channel, !channel.isEmpty { LivePicture(player: live.player) }
                if live.key == channel, live.playing, live.info?.now?.kind == "slate" {
                    SlateCard(name: live.info?.name ?? name, next: live.info?.next, scale: width / 1920)
                }
                message
            }
            .frame(width: width, height: width * 9 / 16)
            HStack(spacing: 16) {
                Text(name).font(.system(size: 18.75)).foregroundStyle(pictureBar ? Color.white : p.text).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
                Button { size(-1) } label: { Text("−") }.buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).disabled(width <= least).accessibilityLabel("Smaller preview")
                Button { size(1) } label: { Text("+") }.buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).disabled(width >= most).accessibilityLabel("Larger preview")
                Button { looks.change(["previewSound": !dress.look.previewSound], client: client); live.muted = dress.look.previewSound } label: {
                    Image(systemName: dress.look.previewSound ? "speaker.wave.2" : "speaker.slash")
                }
                .buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).accessibilityLabel("Preview sound")
                Button { if !channel.isEmpty { onWatch(channel) } } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).disabled(channel.isEmpty).accessibilityLabel("Watch \(name) full screen")
                Button { looks.change(["preview": "off"], client: client) } label: { Image(systemName: "xmark") }
                    .buttonStyle(TvButtonStyle(dress: dress, kind: .icon)).accessibilityLabel("Hide the preview")
            }
            .padding(.horizontal, 2)
            .frame(width: width)
            .frame(minHeight: 56)
            .background(pictureBar ? Color.black : shape == .teletext ? p.panel2 : [.listings, .outline].contains(shape) ? p.bg : p.panel)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(border, lineWidth: borderWidth)
                .allowsHitTesting(false)
        }
        .padding(shape == .receiver ? 4 : 0)
        .overlay { if shape == .receiver { Rectangle().strokeBorder(p.line, lineWidth: 1).allowsHitTesting(false) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview: \(name.isEmpty ? "no channel" : name)")
    }

    private var border: Color {
        let p = dress.paint
        switch dress.shape {
        case .modern, .cinema: return .clear
        case .receiver: return p.accent
        case .teletext: return p.panel2
        case .listings: return p.text
        default: return p.line
        }
    }

    private var borderWidth: CGFloat {
        switch dress.shape {
        case .box: return 3
        case .receiver, .listings, .outline, .compact: return 1
        case .modern, .cinema: return 0
        default: return 2
        }
    }

    @ViewBuilder private var message: some View {
        let words: String? = {
            if channel.isEmpty { return "No preview for this channel" }
            if live.key != channel { return name }
            switch live.state {
            case .failed(let why): return why.count > 90 ? "Not available" : why
            case .tuning, .playing, .idle: return live.playing ? nil : "Tuning…"
            }
        }()
        if let words {
            Text(words).font(.system(size: 15)).foregroundStyle(.white).multilineTextAlignment(.center).padding(8)
        }
    }

    /// Between the named sizes, and down to the least that can be used or up to what the page can spare.
    private func size(_ way: Int) {
        let named = TvLook.previewSizes.map(\.width).filter { $0 <= most }
        let next = way > 0 ? named.first { $0 > width + 1 } ?? most : named.last { $0 < width - 1 } ?? least
        looks.change(["previewW": next.rounded()], client: client)
    }
}

// MARK: - The grid's parts

/// The row of times over the grid, with the day and time in its corner.
struct GuideTimes: View {
    let dress: TvDress
    let from: Int64
    let now: Int64
    let slots: Int

    var body: some View {
        let p = dress.paint
        let shape = dress.shape
        let size = dress.timeSize
        let weight: Font.Weight = [.receiver, .teletext, .listings, .outline].contains(shape) ? .regular : [.modern, .cinema, .compact].contains(shape) ? .semibold : .bold
        let padding: CGFloat = shape == .compact ? 3 : 8
        let height = size * 1.4 + padding * 2
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                dress.words(GuideRules.dayWord(from, now: now), size, .bold, smallCaps: true)
                Text(tvClock(from)).italic(shape == .listings)
            }
            .font(dress.font(size, shape == .modern ? .semibold : .regular))
            .tvCase(shape == .box || shape == .receiver || shape == .teletext, tracking: shape == .receiver ? 1.5 : 0)
            .foregroundStyle([.modern, .listings, .cinema, .outline].contains(shape) ? p.text : shape == .teletext ? p.soft : p.accent)
            .lineLimit(1)
            .padding(.horizontal, shape == .compact ? 8 : 10)
            .frame(width: dress.channelWidth, height: height, alignment: .leading)
            .overlay(alignment: .trailing) { cornerRule }
            GeometryReader { box in
                ZStack(alignment: .topLeading) {
                    ForEach(0..<slots, id: \.self) { i in
                        Text(tvClock(from + Int64(i) * GuideRules.slot))
                            .font(dress.font(size, weight, digits: shape == .receiver))
                            .italic(shape == .listings)
                            .textCase(shape == .box ? .uppercase : nil)
                            .foregroundStyle([.modern, .cinema, .outline].contains(shape) || shape == .teletext ? p.soft : shape == .receiver ? p.accent : p.text)
                            .lineLimit(1)
                            .padding(.leading, shape == .modern ? 10 : shape == .outline ? 12 : shape == .compact ? 6 : 10)
                            .frame(width: box.size.width / CGFloat(slots), height: height, alignment: .leading)
                            .overlay(alignment: .leading) { tick }
                            .padding(.leading, box.size.width * CGFloat(i) / CGFloat(slots))
                    }
                }
            }
            .frame(height: height)
            .clipped()
        }
        .background { fill }
        .overlay { bottomRule }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var fill: some View {
        let p = dress.paint
        switch dress.shape {
        case .box: LinearGradient(colors: [p.head, p.panel], startPoint: .top, endPoint: .bottom)
        case .compact: p.panel
        default: p.bg
        }
    }

    @ViewBuilder private var cornerRule: some View {
        let p = dress.paint
        switch dress.shape {
        case .box: p.line.frame(width: 3)
        case .receiver, .compact: p.line.frame(width: 1)
        case .listings: p.text.frame(width: 1)
        default: EmptyView()
        }
    }

    @ViewBuilder private var tick: some View {
        let p = dress.paint
        switch dress.shape {
        case .box, .compact: p.line.frame(width: 1)
        case .modern, .receiver, .cinema: p.panel2.frame(width: 1)
        case .listings: p.line.frame(width: 1)
        default: EmptyView()
        }
    }

    @ViewBuilder private var bottomRule: some View {
        let p = dress.paint
        switch dress.shape {
        case .box: Rule(edge: .bottom, colour: p.line, width: 3)
        case .receiver, .compact: Rule(edge: .bottom, colour: p.line)
        case .listings: Rule(edge: .bottom, colour: p.text)
        case .cinema: Rule(edge: .bottom, colour: p.panel2)
        default: EmptyView()
        }
    }
}

/// The line at the current time, over the times and the rows.
struct GuideNowLine: View {
    let dress: TvDress
    let x: CGFloat
    let now: Int64

    var body: some View {
        let p = dress.paint
        let thin = dress.shape == .listings || dress.shape == .outline
        let pill = dress.shape == .modern || dress.shape == .outline
        ZStack(alignment: .top) {
            p.accent.frame(width: thin ? 1 : 2).shadow(color: thin ? .clear : .black.opacity(0.5), radius: 2)
            Text(tvClock(now))
                .font(dress.font(dress.shape == .compact ? 13.75 : 15, .bold)).italic(dress.shape == .listings)
                .foregroundStyle(p.accentText)
                .padding(.horizontal, pill ? 8 : dress.shape == .compact ? 4 : 6).padding(.vertical, pill ? 2 : 1)
                .background(RoundedRectangle(cornerRadius: pill ? 20 : dress.radius).fill(p.accent))
                .fixedSize()
                .padding(.top, dress.shape == .compact ? 2 : 4)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .offset(x: x - 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A channel's picture: the owner's own upload first, then the logo service's. Without either, nothing.
struct ChannelLogo: View {
    @Environment(\.client) private var client
    @ObservedObject private var logos = TvLogos.shared
    let dress: TvDress
    let channel: GuideChannel
    let size: CGSize
    let highlighted: Bool

    private var url: URL? {
        guard dress.look.logos else { return nil }
        if let own = channel.logo, own.hasPrefix("/") { return client.mediaURL(own) }
        guard let info = logos.info(channel.brand), info.has == true else { return nil }
        let dark = highlighted && dress.rowHighlight ? dress.look.hiIsDark : dress.look.bgIsDark
        return client.logoImageURL(info, variant: info.opaque == true ? "original" : dark ? "white" : "dark")
    }

    var body: some View {
        if let url {
            ArtImage(url: url, width: size.width, fit: true, blank: true)
                .frame(width: size.width, height: size.height)
                .accessibilityLabel(channel.name)
        }
    }

    var shown: Bool { url != nil }
}

/// One channel's row: who it is, then its programmes.
struct GuideRow: View {
    @Environment(\.client) private var client
    @ObservedObject private var logos = TvLogos.shared
    let dress: TvDress
    let index: Int
    let channel: GuideChannel?
    let from: Int64
    let to: Int64
    let perSecond: Double
    let now: Int64
    let current: Bool
    let focusAt: Int64?
    let logo: LogoInfo?
    let reminded: (Int64) -> Bool
    var focused: FocusState<GuideFocus?>.Binding
    let activate: (GuideChannel, GuideCell) -> Void
    let more: (GuideCell, Bool) -> Void
    let record: (GuideCell) -> Void
    let series: (GuideCell) -> Void
    let remind: (GuideCell) -> Void
    let favourite: () -> Void
    let watch: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            header.frame(width: dress.channelWidth)
            track
        }
    }

    private var hasLogo: Bool {
        guard dress.look.logos, let channel else { return false }
        return channel.logo?.hasPrefix("/") == true || logos.info(channel.brand)?.has == true
    }

    private var header: some View {
        let p = dress.paint
        let shape = dress.shape
        let lit = current && dress.rowHighlight
        let ink = lit ? p.hiText : p.text
        let n = dress.number
        let name = dress.name
        let inset: CGFloat = shape == .modern || shape == .outline ? 3 : 0
        return HStack(spacing: shape == .modern ? 10 : shape == .compact ? 4 : 7) {
            if let channel {
                Text(channel.number ?? "")
                    .font(dress.font(n.size, n.weight, digits: shape == .receiver))
                    .italic(shape == .listings).monospacedDigit()
                    .foregroundStyle(lit ? p.hiText : shape == .modern ? p.soft : p.accent)
                    .frame(minWidth: shape == .compact ? 28 : 56, alignment: .trailing)
                    .lineLimit(1)
                if hasLogo {
                    ChannelLogo(dress: dress, channel: channel, size: dress.logo, highlighted: current)
                } else {
                    dress.words(channel.name, name.size, name.weight, smallCaps: true)
                        .tvCase(shape == .modern || shape == .receiver || shape == .teletext, tracking: shape == .modern ? 0.4 : shape == .receiver ? 0.8 : 0)
                        .foregroundStyle(shape == .teletext && !current ? p.soft : ink)
                        .lineLimit(shape == .compact ? 1 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                if channel.favourite == true {
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(lit ? p.hiText : p.accent).accessibilityLabel("Favourite")
                }
                if !channel.canTune { Text("🔒").font(.system(size: 15)).accessibilityHidden(true) }
            } else {
                Text("…").font(dress.font(name.size, .bold)).foregroundStyle(p.soft)
            }
        }
        .padding(.horizontal, shape == .modern ? 12 : 8)
        .frame(maxHeight: .infinity)
        .background { headerFill(lit: lit) }
        .overlay { headerRules }
        .overlay(alignment: .leading) {
            if let a = TvLook.channelAccent(channel?.accent, on: dress.look.colours.bg) {
                Color(hex: a).frame(width: 4).clipShape(RoundedRectangle(cornerRadius: shape == .modern ? 10 : 0))
            } else if shape == .receiver, current { p.accent.frame(width: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: shape == .modern || shape == .outline ? 10 : 0, style: .continuous))
        .overlay {
            if shape == .outline {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(current ? p.accent : p.line, lineWidth: current ? 2 : 1)
            }
        }
        .padding(.vertical, inset)
        .padding(.trailing, inset * 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func headerFill(lit: Bool) -> some View {
        let p = dress.paint
        switch dress.shape {
        case .box: ZStack { p.ch; Bevel() }
        case .modern: lit ? p.hi : p.ch
        case .cinema: lit ? p.hi : p.bg
        case .teletext, .listings: current ? p.panel2 : p.bg
        case .outline: Color.clear
        case .compact: index % 2 == 1 ? p.panel : p.bg
        case .receiver: p.bg
        }
    }

    @ViewBuilder private var headerRules: some View {
        let p = dress.paint
        switch dress.shape {
        case .box:
            ZStack { Rule(edge: .trailing, colour: p.line, width: 3); Rectangle().strokeBorder(p.bg, lineWidth: 1) }
        case .receiver: ZStack { Rule(edge: .bottom, colour: p.panel2); Rule(edge: .trailing, colour: p.line) }
        case .listings: ZStack { Rule(edge: .bottom, colour: p.line); Rule(edge: .trailing, colour: p.text) }
        case .cinema: Rule(edge: .bottom, colour: p.panel)
        case .compact: ZStack { Rule(edge: .bottom, colour: p.panel2); Rule(edge: .trailing, colour: p.line) }
        default: EmptyView()
        }
    }

    private var track: some View {
        let cells = GuideRules.cells(channel, from: from, to: to, pointsPerSecond: perSecond)
        let focusedCell = focusAt.flatMap { GuideRules.cell(at: $0, in: cells) }
        return ZStack(alignment: .topLeading) {
            if dress.shape == .modern || dress.shape == .outline { dress.paint.bg }
            if let channel {
                ForEach(Array(cells.enumerated()), id: \.element.start) { i, cell in
                    let start = max(cell.start, from), end = min(cell.end, to)
                    let x = CGFloat(Double(start - from) * perSecond), w = CGFloat(Double(end - start) * perSecond)
                    Button { activate(channel, cell) } label: { EmptyView() }
                        .buttonStyle(GuideCellStyle(dress: dress, channel: channel, cell: cell, from: from, to: to, now: now, width: w,
                                                    highlighted: cell == focusedCell, evenRow: index % 2 == 1, reminded: reminded(cell.start)))
                        .frame(width: max(1, w))
                        .padding(.leading, x)
                        .focused(focused, equals: .cell(index, cell.start))
                        .onPlayPauseCommand { watch() }
                        .contextMenu { menu(channel, cell) }
                        .accessibilityLabel(label(channel, cell))
                        .accessibilityAddTraits(i == 0 ? [] : [])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func menu(_ channel: GuideChannel, _ cell: GuideCell) -> some View {
        let later = cell.start > now && cell.kind == .programme
        Button("More about this") { more(cell, false) }
        Button("The whole day on \(channel.name)") { more(cell, true) }
        if channel.canTune { Button("Watch \(channel.name) now") { watch() } }
        if later, channel.canTune, cell.programme?.kind != "slate" {
            Button(reminded(cell.start) ? "Remove the reminder" : "Remind me") { remind(cell) }
        }
        if channel.canRecord == true, cell.isBroadcast, cell.end > now {
            Button("Record this") { record(cell) }
            Button("Record every airing") { series(cell) }
        }
        Button(channel.favourite == true ? "Remove from favourites" : "Add to favourites") { favourite() }
    }

    private func label(_ channel: GuideChannel, _ cell: GuideCell) -> String {
        let p = cell.programme
        let when = cell.kind == .none ? "" : GuideRules.span(cell.start, cell.end)
        let on = cell.isOn(at: now) ? ", on now" : ""
        let lock = channel.security?.state == "encrypted" ? ", \(channel.security!.label)" : ""
        return "Channel \(channel.number ?? ""), \(channel.name): " + [cell.title, p?.sub ?? "", when].filter { !$0.isEmpty }.joined(separator: ", ") + on + lock
    }
}

/// A cell of the grid, in its shape: a programme, a gap, or a run of short ones. Highlighted, it
/// takes the theme's highlight, as on the page.
struct GuideCellStyle: ButtonStyle {
    let dress: TvDress
    let channel: GuideChannel
    let cell: GuideCell
    let from: Int64
    let to: Int64
    let now: Int64
    let width: CGFloat
    let highlighted: Bool
    let evenRow: Bool
    let reminded: Bool

    func makeBody(configuration: Configuration) -> some View {
        GuideCellBody(style: self, pressed: configuration.isPressed)
    }
}

private struct GuideCellBody: View {
    @Environment(\.isFocused) private var focused
    let style: GuideCellStyle
    let pressed: Bool

    var body: some View {
        let d = style.dress
        let p = d.paint
        let shape = d.shape
        let cell = style.cell
        // The highlight stays where it was while focus is above the grid, as on the page.
        let lit = focused || style.highlighted
        let live = cell.isOn(at: style.now)
        let past = cell.end <= style.now
        let dim = cell.isDim
        let tiny = style.width < 34
        let small = style.width < 96
        let inset: CGFloat = shape == .modern || shape == .outline ? 3 : shape == .cinema ? 2 : 0
        let radius: CGFloat = shape == .modern || shape == .outline ? 10 : shape == .cinema ? 4 : 0
        let box = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let ink: Color = lit ? p.hiText : dim || (past && shape != .outline && shape != .compact) ? p.soft : shape == .outline || (shape == .compact && !live) ? p.text : live ? p.liveText : p.cellText
        let soft: Color = lit ? p.hiText : dim || past ? p.soft : shape == .outline || (shape == .compact && !live) ? p.soft : live ? p.liveSoft : p.cellSoft
        let t = d.cellTitle
        ZStack(alignment: .leading) {
            fill(lit: lit, live: live, past: past, dim: dim).clipShape(box)
            if d.look.progress, live, cell.kind != .none {
                let start = max(cell.start, style.from), end = min(cell.end, style.to)
                let share = CGFloat(Double(style.now - start) / Double(max(1, end - start)))
                if shape == .outline {
                    VStack { Spacer(); (lit ? p.hiText : p.accent).frame(width: style.width * share, height: 2) }.clipShape(box)
                } else {
                    (lit ? p.hiText.opacity(0.14) : p.lite).frame(width: max(0, style.width - inset * 0) * share).clipShape(box)
                }
            }
            if tiny {
                if cell.kind == .group {
                    Text("\(cell.group.count)").font(.system(size: 13.75, weight: .bold)).foregroundStyle(ink).frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 3) {
                    if cell.start < style.from { Text("◄").font(.system(size: 13.75)).foregroundStyle(ink) }
                    words(ink: ink, soft: soft, small: small, title: t)
                    if cell.end > style.to { Text("►").font(.system(size: 13.75)).foregroundStyle(ink) }
                }
                .padding(.horizontal, padding)
            }
        }
        .overlay { border(lit: lit, live: live, past: past, dim: dim, box: box) }
        .padding(.vertical, inset)
        .padding(.trailing, inset)
        .opacity(pressed ? 0.85 : 1)
    }

    private var padding: CGFloat {
        switch style.dress.shape {
        case .modern: return 14
        case .receiver, .listings: return 10
        case .teletext: return 8
        case .cinema, .outline: return 12
        case .compact: return 6
        case .box: return 6
        }
    }

    @ViewBuilder private func words(ink: Color, soft: Color, small: Bool, title t: (size: CGFloat, weight: Font.Weight)) -> some View {
        let d = style.dress
        let cell = style.cell
        let p = cell.programme
        let details = [cell.kind == .none || small ? "" : tvClock(cell.start), p?.year.map(String.init) ?? "", p?.genre ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let under = d.look.subtitles ? (d.shape.details ? details : p?.sub ?? "") : ""
        let lock = style.channel.canTune ? "" : "🔒 "
        let reminder = style.reminded ? " ⏰" : ""
        let titleText = Text(lock + cell.title + reminder)
            .font(d.font(t.size, cell.isDim ? .regular : t.weight))
        let underText = Text(under).font(d.font(d.cellSmall)).italic(d.shape == .listings)
        if d.shape == .compact {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText.foregroundStyle(ink).lineLimit(1).layoutPriority(1)
                if !under.isEmpty { underText.foregroundStyle(soft).lineLimit(1) }
            }
        } else {
            VStack(alignment: .leading, spacing: d.shape == .modern ? 3 : 0) {
                titleText.foregroundStyle(ink).lineLimit(1)
                    .textCase(d.shape == .teletext ? .uppercase : nil)
                    .tracking(d.shape == .box ? t.size * 0.01 : 0)
                if !under.isEmpty { underText.foregroundStyle(soft).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func fill(lit: Bool, live: Bool, past: Bool, dim: Bool) -> some View {
        let d = style.dress
        let p = d.paint
        if lit {
            p.hi
        } else if d.shape == .outline {
            Color.clear
        } else if dim || past {
            p.dim
        } else if style.cell.kind == .group {
            HStack(spacing: 0) {
                ForEach(0..<Int(style.width / 6) + 1, id: \.self) { _ in
                    p.cell.frame(width: 3)
                    (d.shape == .modern ? p.bg : p.cell2).frame(width: d.shape == .modern ? 2 : 3)
                }
            }
        } else if d.shape == .box {
            ZStack {
                LinearGradient(colors: live ? [p.live, p.live2] : [p.cell, p.cell2], startPoint: .top, endPoint: .bottom)
                Bevel()
            }
        } else if d.shape == .compact {
            live ? p.live : style.evenRow ? p.panel : p.bg
        } else {
            live ? p.live : p.cell
        }
    }

    @ViewBuilder private func border(lit: Bool, live: Bool, past: Bool, dim: Bool, box: RoundedRectangle) -> some View {
        let d = style.dress
        let p = d.paint
        switch d.shape {
        case .box:
            ZStack {
                Rectangle().strokeBorder(p.bg, lineWidth: 2)
                if lit { Rectangle().strokeBorder(p.text, lineWidth: 2).padding(2) }
            }
        case .modern:
            if lit { box.strokeBorder(p.accent, lineWidth: 2).padding(-3) }
        case .receiver, .compact:
            ZStack { Rule(edge: .bottom, colour: p.panel2); Rule(edge: .trailing, colour: p.panel2) }
        case .listings:
            ZStack { Rule(edge: .bottom, colour: p.line); Rule(edge: .trailing, colour: p.line) }
        case .outline:
            if lit {
                box.strokeBorder(p.hi, lineWidth: 1)
            } else if dim || past {
                box.strokeBorder(p.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            } else {
                box.strokeBorder(live ? p.accent : p.line, lineWidth: 1)
            }
        default:
            EmptyView()
        }
    }
}
#endif

#if os(tvOS)
/// "We'll be right back": the card over a channel's slate, when nothing is scheduled, so neither the
/// preview nor the channel looks broken while it's on. Always over the picture, in the picture's colours.
struct SlateCard: View {
    let name: String
    let next: GuideProgramme?
    /// The preview draws it in proportion to its own width.
    var scale: CGFloat = 1

    var body: some View {
        let s = max(scale * 1.6, 0.3)
        VStack(spacing: 6 * s) {
            Text(name).font(.system(size: max(10, 25 * s), weight: .bold)).opacity(0.85)
            Text("We'll be right back").font(.system(size: max(14, 47.5 * s), weight: .bold)).shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 2)
            if let next {
                Text("Coming up at \(tvClock(next.start)): \(next.title)").font(.system(size: max(9, 21.25 * s))).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 34 * s).padding(.vertical, 22 * s)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
#endif
