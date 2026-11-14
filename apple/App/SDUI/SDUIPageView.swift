// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Combine
import SwiftUI
import WittyKit

/// A server-driven page as a screen: it asks for the page, shows it loading, failed, gone or ready, asks again
/// when it comes back into view or the window crosses a breakpoint, and offers "Customise" where the page does.
struct SDUIPageScreen: View {
    enum Chrome {
        /// A tab's first screen: the menu's strip above it on a phone and a tablet.
        case tabRoot
        /// Opened from somewhere: Back at the top, unless it's one of the menu's own places.
        case pushed
        /// Inside another screen that has its own chrome.
        case bare
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let place: SDUIPlace
    var chrome = Chrome.pushed
    @StateObject private var store: SDUIPageStore
    @State private var customising = false

    init(place: SDUIPlace, chrome: Chrome = .pushed) {
        self.place = place
        self.chrome = chrome
        _store = StateObject(wrappedValue: SDUIPageStore(place: place))
    }

    /// Whether the page starts with a picture the top bar can float over.
    private var overPicture: Bool {
        guard let first = store.screen?.sections.first else { return false }
        return first.type == "DetailHeader" && first.props.text("layout") != "compact" && (first.picture != nil || first.poster != nil)
    }

    /// The page's regions, when it asks for WittyPlay's frame (Apple TV draws it: TvPlayFrame.swift).
    private var regions: SDUIRegions? {
        guard let found = store.screen?.document.regions, !found.isEmpty, chrome != .bare else { return nil }
        return found
    }

    @ViewBuilder private var framed: some View {
        #if os(tvOS)
        if let regions {
            TvPlayFrame(regions: regions, place: place) { content.frame(maxWidth: .infinity, maxHeight: .infinity) }
                .moduleScope(WittyPlayPlace.isPlayPage(place.page) ? "wittyplay" : "")
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pageBackground(palette)
                .modifier(SDUIChrome(chrome: chrome, top: center.isTop(place), route: place.route, overPicture: overPicture))
        }
        #else
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground(palette)
            .modifier(SDUIChrome(chrome: chrome, top: center.isTop(place), route: place.route, overPicture: overPicture))
        #endif
    }

    var body: some View {
        framed
            .environmentObject(store)
            // Corners and type from the theme, by the catalogue's tokens for each component.
            .environment(\.sduiDraw, SDUIDraw(catalog: center.catalog, style: model.themeStyle))
            .task { await store.appear(center) }
            .sduiOnChange(of: center.epoch) { _ in Task { await store.load(center) } }
            .sduiOnChange(of: store.phase) { phase in
                if phase == .ready, chrome == .tabRoot { center.settled() }
            }
            .sduiOnChange(of: center.changes) { _ in Task { await store.refresh(center) } }
            // Screen time that runs out, or more of it given, changes what the page says about it: ask again.
            .onReceive(model.household.$time.map { $0?.allowed }.removeDuplicates().dropFirst()) { _ in
                Task { await store.refresh(center) }
            }
            .sheet(isPresented: $customising) {
                if let document = store.document {
                    SDUICustomiseView(document: document, page: store.page) { changed in
                        customising = false
                        if changed { Task { await store.load(center) } }
                    }
                    .environmentObject(center)
                    .environmentObject(model)
                    .environment(\.palette, palette)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading:
            // A whole page loading for the first time: three rows of placeholders.
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                ForEach(0..<3, id: \.self) { _ in SkeletonRow(count: 8) }
                Spacer(minLength: 0)
            }
            .padding(.top, Tokens.Space.s6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
        case .otherRevision:
            SDUIRevisionMismatch(server: center.otherRevision)
        case .failed(let words):
            ProblemView(words: words, retry: { Task { await store.load(center) } })
        case .missing:
            VStack(spacing: Tokens.Space.s4) {
                EmptyMessage(title: "This isn't available", detail: "It may have been removed, or it isn't yours to see.")
                Button(say("homeTab")) {
                    model.paths[model.tab] = []
                    model.tab = .home
                }
                .action(primary: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if let screen = store.screen {
                SDUIPageBody(screen: screen, offline: store.offline, customise: canCustomise(screen) ? { customising = true } : nil)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(screen.root.label)
                    .accessibilityIdentifier("sdui.page." + screen.document.page.id)
            }
        }
    }

    private func canCustomise(_ screen: SDUIScreen) -> Bool {
        center.features.contains("sdui-personal") && SDUICustomise(document: screen.document, stored: SDUIPersonal()).offersAnything
    }
}

/// What's around a page on a phone and a tablet: the menu's strip, or Back. Apple TV's pages have the whole screen.
private struct SDUIChrome: ViewModifier {
    let chrome: SDUIPageScreen.Chrome
    let top: Bool
    let route: String?
    let overPicture: Bool

    func body(content: Content) -> some View {
        switch chrome {
        case .tabRoot:
            content.underStrip(path: route).noNavigationBar()
        case .pushed:
            if top {
                content.underStrip(path: route).noNavigationBar()
            } else {
                content.plainNavigation(overPicture: overPicture)
            }
        case .bare:
            content
        }
    }
}

/// The page itself: its sections one under another, the device's distance apart, inside the safe area. It scrolls
/// down and nothing inside it does. On Apple TV focus starts where the page says, each row remembers its card,
/// and coming back puts focus where it was.
struct SDUIPageBody: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiTheme) private var theme
    let screen: SDUIScreen
    let offline: Bool
    let customise: (() -> Void)?
    @FocusState private var focused: String?
    @State private var memory = SDUIFocusMemory()
    @State private var lastFocused: String?
    @Namespace private var scope

    private var layout: SDUILayout { screen.layout }
    /// The page's sections, its Dock aside: the Dock is drawn in its own zone (docs/SDUI.md, Zones and the Dock).
    /// A region the shell's placements hide (the hero, the dock) is left out.
    private var sections: [SDUIElement] {
        screen.sections.filter { $0.type != "Dock" && !($0.type == "Hero" && center.shell?.shows("hero") == false) }
    }
    private var dock: SDUIElement? { center.shell?.shows("dock") == false ? nil : screen.sections.first { $0.type == "Dock" && !$0.children.filter { $0.type == "Button" }.isEmpty } }
    /// A phone's Dock is an Options button that opens its controls as a sheet; elsewhere a bar at the foot.
    private var dockIsSheet: Bool { (layout.dock?.placement ?? (layout.formFactor == "phone" ? "sheet" : "bottom")) == "sheet" }
    @State private var showingDock = false
    @State private var jumpTarget: String?

    /// The app's own view fills the rest of the page; nothing follows it.
    private var nativeAt: Int? {
        sections.firstIndex { $0.type == "NativeView" && SDUINativeView.has($0.props.text("view")) }
    }

    /// The page's heading is drawn on a touch screen, unless what the page starts with is its own heading.
    private var showsTitle: Bool {
        guard !layout.isTV, !screen.title.isEmpty else { return false }
        return !["Hero", "DetailHeader"].contains(sections.first?.type ?? "")
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let nativeAt {
                    VStack(alignment: .leading, spacing: CGFloat(layout.sectionGap)) {
                        ForEach(sections.prefix(nativeAt)) { SDUINodeView(element: $0) }
                        SDUINodeView(element: sections[nativeAt]).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    scrolling
                }
            }
            .environment(\.sduiLayout, layout)
            .environment(\.sduiWidth, geo.size.width)
            .environment(\.sduiFocus, layout.focusEngine ? $focused : nil)
            .onAppear { store.setWindow(geo.size.width) }
            .sduiOnChange(of: geo.size.width) { store.setWindow($0) }
        }
        .sduiScope(screen.document.theme?.tokens ?? [:])
        #if os(tvOS)
        .focusScope(scope)
        .defaultFocus($focused, screen.focus.start)
        .sduiOnChange(of: focused) { now in
            if let now { lastFocused = now }
            // The focus engine picked the nearest card by geometry; the row remembers the one that had focus.
            if let instead = memory.moved(to: now, in: screen.focus) {
                DispatchQueue.main.async { focused = instead }
            }
        }
        .sduiOnChange(of: screen.focus) { memory.prune(to: $0) }
        .onAppear {
            // Coming back from a screen pushed on top of this one.
            if let lastFocused, screen.focus.order.contains(lastFocused) { DispatchQueue.main.async { focused = lastFocused } }
        }
        #endif
    }

    private var scrolling: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CGFloat(layout.sectionGap)) {
                #if !os(tvOS)
                ScrollTop()
                #endif
                if showsTitle {
                    Text(screen.title)
                        .sduiFont("pageTitle")
                        .foregroundStyle(palette.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHeading(.h1)
                        .padding(.horizontal, layout.margin)
                }
                if let dock, dockIsSheet {
                    // A phone's Dock: one Options button that opens its controls.
                    Button { showingDock = true } label: { Label(dock.label, systemImage: "slider.horizontal.3") }
                        .action(pill: true)
                        .padding(.horizontal, layout.margin)
                        .accessibilityIdentifier("sdui.dock.options")
                }
                if let over = screen.document.screenTime { SDUIScreenTimeNote(over: over) }
                if offline { SDUIOfflineNote() }
                AppNoticeLine().padding(.horizontal, layout.margin)
                ForEach(sections) { SDUINodeView(element: $0) }
                // A disc's own sections (its titles, why this title is the film, versions, episodes) are the app's,
                // under the server's title page, as the website keeps them.
                if screen.document.page.kind == "detail", let id = store.params["item"].flatMap({ Int64($0) }) {
                    SDUIDiscExtras(id: id)
                }
                if sections.isEmpty {
                    EmptyMessage(title: "Nothing here yet", detail: "Add a library on the server, or ask whoever runs it.")
                }
                if let customise {
                    Button(action: customise) { Label("Customise", systemImage: "slider.horizontal.3") }
                        .action(pill: true)
                        .padding(.horizontal, layout.margin)
                        // On a TV the button's ring and lift need room, and the Dock under the page must not crowd it.
                        .padding(.vertical, layout.isTV ? layout.sp("xl") : 0)
                        .accessibilityIdentifier("sdui.customise")
                        .remoteSection()
                }
                #if !os(tvOS)
                PageFoot().padding(.horizontal, layout.margin)
                #endif
            }
            .padding(.top, layout.isTV ? 0 : layout.sp("s"))
            .padding(.bottom, layout.isTV ? CGFloat(layout.safeArea.bottom) : layout.sp("xl"))
        }
        #if os(tvOS)
        // The page keeps inside its own safe area, which the rows run under so that a lifted card isn't cut off.
        .ignoresSafeArea(.container, edges: .horizontal)
        #else
        .refreshable { await store.refresh(center) }
        #if os(iOS)
        // Not on visionOS, which has no on-screen keyboard to put away.
        .scrollDismissesKeyboard(.immediately)
        #endif
        #endif
        // A jump to a letter brings its first title into view.
        .sduiOnChange(of: store.scrollTo) { target in
            guard let target else { return }
            withAnimation(.easeOut(duration: Tokens.Motion.focus)) { proxy.scrollTo(target, anchor: .top) }
            #if os(tvOS)
            focused = target
            #endif
            store.scrollTo = nil
        }
        }
        // A bar at the foot that never moves: outside the page's scroll.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let dock, !dockIsSheet { SDUIDockBar(dock: dock, height: CGFloat(layout.dock?.height ?? 64), focus: layout.focusEngine ? $focused : nil) }
        }
        .sheet(isPresented: $showingDock) {
            if let dock { SDUIDockSheet(dock: dock) { showingDock = false } }
        }
        .onReceive(store.$control) { request in
            guard let request, request.control == "jump" else { return }
            store.control = nil
            jumpTarget = request.target
        }
        .sheet(item: Binding(get: { jumpTarget.map { SDUIJumpTarget(grid: $0) } }, set: { jumpTarget = $0?.grid })) { target in
            SDUILetterPicker { letter in
                jumpTarget = nil
                Task { await store.jump(to: letter, in: target.grid, center: center) }
            }
        }
        .onAppear { store.loadViews(profile: String(model.user?.id ?? 0)) }
    }
}

private struct SDUIJumpTarget: Identifiable { let grid: String; var id: String { grid } }

/// Screen time is over: the page still shows, nothing in it plays, and this says why and when there's time again.
struct SDUIScreenTimeNote: View {
    @Environment(\.sduiDraw) private var draw
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let over: SDUIScreenTime

    private var words: String {
        let said = PlainWords.clean(over.message ?? "", limit: 300)
        return said.isEmpty ? "Screen time is over for now." : said
    }

    private var again: String? {
        guard let at = over.nextAt, at > 0 else { return nil }
        let when = Date(timeIntervalSince1970: TimeInterval(at))
        let format = DateFormatter()
        format.timeStyle = .short
        format.dateStyle = Calendar.current.isDateInToday(when) ? .none : .medium
        format.doesRelativeDateFormatting = true
        return "There's time again at \(format.string(from: when))."
    }

    var body: some View {
        HStack(alignment: .top, spacing: layout.sp("s")) {
            Image(systemName: "hourglass").sduiFont("title").foregroundStyle(palette.warn).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(words).sduiFont("body", weight: .medium).foregroundStyle(palette.text)
                if let again { Text(again).sduiFont("caption").foregroundStyle(palette.textSecondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(layout.sp("m"))
        .background(palette.panel)
        .overlay(alignment: .leading) { Rectangle().fill(palette.warn).frame(width: 4) }
        .clipShape(RoundedRectangle(cornerRadius: draw.radius("Notice"), style: .continuous))
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sdui.screentime")
    }
}

/// The server couldn't be reached, and this is the page as it was.
struct SDUIOfflineNote: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout

    var body: some View {
        Label("The server isn't answering. This is the page as it was.", systemImage: "wifi.slash")
            .sduiFont("caption")
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, layout.margin)
            .accessibilityIdentifier("sdui.offline")
    }
}

/// Under a server-driven title page, the app's own parts the server's page doesn't draw: where to watch it and an
/// administrator's media tools for every title, and a disc's own sections (DiscSections.swift on a phone and a tablet;
/// why this title is the film on Apple TV).
private struct SDUIDiscExtras: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiWidth) private var width
    let id: Int64
    @State private var found: (item: Item, facts: ItemFacts)?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            if let found {
                // Where to watch it, and an administrator's canvas and skip markers (MediaPages.swift).
                MediaItemExtras(item: found.item)
            }
            if let found, TitleLook.isDisc(found.item) {
                let page = width > 0 ? width : 400
                #if os(tvOS)
                DiscWhy(item: found.item.id, playable: false, top: Tokens.Space.s2)
                    .moduleScope(found.item.isBluray ? "wittybluray" : "wittydvd")
                #else
                DiscSections(item: found.item, disc: found.facts.disc, admin: model.user?.isAdmin == true,
                             playable: TitleLook.playable(found.item, found.facts), page: page,
                             column: max(page - layout.margin * 2, 200), say: { model.notice = $0 })
                    .moduleScope(found.item.isBluray ? "wittybluray" : "wittydvd")
                #endif
            }
        }
        .padding(.horizontal, layout.margin)
        .task(id: id) {
            if let pair = try? await client.itemPage(id) { found = (pair.0, pair.1) }
        }
    }
}
