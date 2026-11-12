// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
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

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground(palette)
            .modifier(SDUIChrome(chrome: chrome, top: center.isTop(place), route: place.route, overPicture: overPicture))
            .environmentObject(store)
            // Corners and type from the theme, by the catalogue's tokens for each component.
            .environment(\.sduiDraw, SDUIDraw(catalog: center.catalog, style: model.themeStyle))
            .task { await store.appear(center) }
            .sduiOnChange(of: center.epoch) { _ in Task { await store.load(center) } }
            .sduiOnChange(of: store.phase) { phase in
                if phase == .ready, chrome == .tabRoot { center.settled() }
            }
            .sduiOnChange(of: center.changes) { _ in Task { await store.refresh(center) } }
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
    private var sections: [SDUIElement] { screen.sections }

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
                if let over = screen.document.screenTime { SDUIScreenTimeNote(over: over) }
                if offline { SDUIOfflineNote() }
                if !model.notice.isEmpty { ProblemLine(model.notice).padding(.horizontal, layout.margin) }
                ForEach(sections) { SDUINodeView(element: $0) }
                if sections.isEmpty {
                    EmptyMessage(title: "Nothing here yet", detail: "Add a library on the server, or ask whoever runs it.")
                }
                if let customise {
                    Button(action: customise) { Label("Customise", systemImage: "slider.horizontal.3") }
                        .action(pill: true)
                        .padding(.horizontal, layout.margin)
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
        .scrollDismissesKeyboard(.immediately)
        #endif
    }
}

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
