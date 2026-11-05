import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// The phone's and tablet's shell, as the server's website has it on a phone: a floating bar of five icons at the
// bottom, the libraries along the top, a round Back on every page below a tab's first, and the libraries in a
// drawer from the left. docs/APP-DESIGN.md, One mobile design with the website, The shell. Apple TV has its own.

// MARK: - Scrolling under the top

/// How far a page has scrolled, measured where its content starts.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Put first in a page's scrolling content; the page reads `ScrollOffsetKey`.
struct ScrollTop: View {
    static let space = "pageScroll"

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ScrollOffsetKey.self, value: -geo.frame(in: .named(Self.space)).minY)
        }
        .frame(height: 0)
    }
}

extension View {
    /// How solid the strip over a page is, from 0 at rest to 1 once 64 points have gone under it. Only
    /// a change that shows is passed on, so scrolling doesn't redraw the page on every frame.
    func stripSolidity(_ solid: Binding<Double>) -> some View {
        modifier(StripSolidity(solid: solid))
    }
}

/// Where the page's scroll view is, read from the scroll view itself where the system says (iOS 18 on): the
/// offset a `ScrollTop` reports through a preference no longer arrives while scrolling there, so the strip stayed
/// clear over whatever went under it. Earlier systems still read `ScrollTop`.
private struct StripSolidity: ViewModifier {
    @Binding var solid: Double

    private func scrolled(_ offset: CGFloat) {
        let next = (min(max((offset - 8) / 56, 0), 1) * 10).rounded() / 10
        if next != solid { solid = next }
    }

    func body(content: Content) -> some View {
        if #available(iOS 18, tvOS 18, visionOS 2, *) {
            content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, offset in
                scrolled(offset)
            }
        } else {
            content
                .coordinateSpace(name: ScrollTop.space)
                .onPreferenceChange(ScrollOffsetKey.self) { scrolled($0) }
        }
    }
}

// MARK: - The library strip

/// The website's bar on a phone's top pages (shell.css, TopBar.tsx SectionRow): 52 high, the menu's places but Home
/// and TV guide in 15 bold `textSecondary`, 20 apart, 44 high and 4 from the bar's top and foot, scrolling sideways
/// and fading out over the last 20 before the activity button; the current one in `text` over a 2-high `accentText`
/// line. The server's lockup when there's nothing to list. Once the page scrolls under it, it gains `background` at
/// 85% with a blur (the regular material, nearest the website's 20 px: a thinner one left a title under it readable), and a hairline. Over a picture, a soft scrim of `background` behind it keeps the names readable.
struct LibraryStrip: View {
    static let height: CGFloat = 52
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    /// The library whose page this is, if any.
    var current: Int64?
    /// Or the server page's address, for Collections, Game PCs and modules' pages.
    var currentPath: String?
    /// 0 over a picture or at rest, 1 once something has scrolled under it.
    var solid: Double = 0
    /// Whether it starts over a picture, as on Home's hero.
    var overPicture = false

    private func isCurrent(_ place: NavPlace) -> Bool {
        if let current { return place.libraryId == current }
        if let currentPath { return place.path == currentPath }
        return false
    }

    var body: some View {
        let places = model.stripPlaces
        HStack(spacing: Tokens.Space.s2) {
            if places.isEmpty {
                BrandLockup().padding(.leading, metrics.gutter)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Tokens.Space.s5) {
                            ForEach(places) { place in
                                let here = isCurrent(place)
                                Button { model.open(place) } label: {
                                    Text(place.label)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(here ? palette.text : palette.textSecondary)
                                        .lineLimit(1)
                                        .frame(height: 44)
                                        .overlay(alignment: .bottom) {
                                            if here { Rectangle().fill(palette.accentText).frame(height: 2) }
                                        }
                                        // Just enough of an edge to part a word from a busy picture, without softening it.
                                        .shadow(color: palette.background.opacity(overPicture && solid < 1 ? 0.5 : 0), radius: 0, y: 1)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(place.id)
                                .accessibilityAddTraits(here ? [.isSelected] : [])
                            }
                        }
                        .padding(.leading, metrics.gutter)
                        .padding(.trailing, Tokens.Space.s5)
                    }
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                                 .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
                        .frame(maxWidth: .infinity))
                    .onAppear {
                        if let here = places.first(where: isCurrent) { proxy.scrollTo(here.id, anchor: .center) }
                    }
                }
            }
            #if !os(tvOS)
            ActivityButton().padding(.trailing, metrics.gutter - 2)
            #endif
        }
        .frame(height: Self.height)
        .background(alignment: .bottom) {
            ZStack {
                Rectangle().fill(.regularMaterial)
                palette.background.opacity(0.85)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
            .ignoresSafeArea(edges: .top)
            .opacity(solid)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }
}

/// The soft scrim behind the strip over a picture: `background` from 80% at the top of the screen to 70% behind
/// the names (so even `textSecondary` reads at 4.5:1 on a bright sky), gone 32 below them. Drawn from the screen's top edge, so give it the clock's room.
struct StripScrim: View {
    @Environment(\.palette) private var palette
    let top: CGFloat

    var body: some View {
        LinearGradient(stops: [
            .init(color: palette.background.opacity(0.8), location: 0),
            .init(color: palette.background.opacity(0.7), location: (top + LibraryStrip.height / 2) / (top + LibraryStrip.height + Tokens.Space.s8)),
            .init(color: palette.background.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: top + LibraryStrip.height + Tokens.Space.s8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Back

/// A 40 round Back at the top left: `background` at 70% with a chevron, over the picture where there is one.
struct PageBackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(palette.background.opacity(0.7)))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(say("back"))
    }
}

private struct BackBar: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let overPicture: Bool
    var hidden = false
    @State private var solid = 0.0

    /// The website's bar below a tab's first page: 52 high with the round Back 16 from the side. Clear at the top of
    /// the page; once the page scrolls under it (a page that starts with ScrollTop says so), `background` at 85% with
    /// a blur and a hairline. Over a picture, a scrim of `background` behind it, fading as that surface comes in.
    private func bar(top: CGFloat) -> some View {
        HStack {
            PageBackButton()
            Spacer(minLength: 0)
            #if !os(tvOS)
            ActivityButton()
            #endif
        }
            .padding(.horizontal, metrics.gutter - 2)
            .frame(height: LibraryStrip.height)
            .background(alignment: .bottom) {
                ZStack {
                    if overPicture {
                        StripScrim(top: top).opacity(1 - solid)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    ZStack {
                        Rectangle().fill(.regularMaterial)
                        palette.background.opacity(0.85)
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
                    .opacity(solid)
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
    }

    func body(content: Content) -> some View {
        // Hidden, it leaves the page where it is: a server's page underneath mustn't be made again, which would reload it.
        if overPicture {
            content
                .stripSolidity($solid)
                .overlay(alignment: .top) {
                    if !hidden {
                        GeometryReader { geo in bar(top: geo.safeAreaInsets.top) }.frame(height: LibraryStrip.height)
                    }
                }
        } else {
            content
                .stripSolidity($solid)
                .safeAreaInset(edge: .top, spacing: 0) { if !hidden { bar(top: 0) } }
        }
    }
}

/// A top page of the website's other than Home and a library's: the strip above it, its own solid once the page
/// scrolls under it (if the page starts with ScrollTop).
private struct UnderStrip: ViewModifier {
    var path: String?
    var hidden = false
    @State private var solid = 0.0

    func body(content: Content) -> some View {
        content
            .stripSolidity($solid)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !hidden { LibraryStrip(currentPath: path, solid: solid) }
            }
    }
}

extension View {
    /// The strip over a top page: Search, You, the TV guide, and the strip's own sections.
    @ViewBuilder func underStrip(path: String? = nil, hidden: Bool = false) -> some View {
        #if os(iOS) || os(visionOS)
        self.toolbar(.hidden, for: .navigationBar).modifier(UnderStrip(path: path, hidden: hidden))
        #else
        self
        #endif
    }

    /// A screen pushed onto a tab: no system bar, and the round Back at the top left. Over a picture it floats
    /// on it; otherwise the page starts below it.
    @ViewBuilder func plainNavigation(overPicture: Bool = false, hidden: Bool = false) -> some View {
        #if os(iOS) || os(visionOS)
        self.toolbar(.hidden, for: .navigationBar).modifier(BackBar(overPicture: overPicture, hidden: hidden))
        #else
        self
        #endif
    }

    /// A tab's first screen or a library's page, which has its own top and no Back.
    @ViewBuilder func noNavigationBar() -> some View {
        #if os(iOS) || os(visionOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

#if os(iOS)
/// The edge swipe back still works with the system's bar hidden, except on the player and a game, where a
/// thumb at the edge is playing, not leaving.
enum BackSwipe {
    static var paused = false
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && !BackSwipe.paused
    }
}
#endif

// MARK: - The floating bar

#if !os(tvOS)
/// A pill 60 high, 16 from the sides and the bottom: `card` with a `control` outline and the website's shadow,
/// 4 inside. Five buttons share it, icons only: Home, TV guide, Search, Menu and You (the person's face). The
/// chosen one has `accent` at 14% behind it and its icon in `accentText`; the others are `textSecondary`.
struct FloatingBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    private func press(_ tab: AppTab) {
        if model.tab == tab {
            // Choosing the open one again goes back to its first page, as tab bars do.
            model.paths[tab] = []
        } else {
            model.tab = tab
        }
    }

    /// A tab is marked only on its own page, as the website's: none on a library's, a title's or a section's.
    private func marked(_ tab: AppTab) -> Bool { model.tab == tab && (model.paths[tab] ?? []).isEmpty }

    private func slot<Icon: View>(_ name: String, chosen: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .foregroundStyle(chosen ? palette.accentText : palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(Capsule().fill(chosen ? palette.accent.opacity(0.14) : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(BarPressStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    var body: some View {
        HStack(spacing: 0) {
            // Home and TV guide go when the person hid them from their menu, as the website's bar.
            ForEach([AppTab.home, .guide, .search].filter { !(model.navPrefs.hidden ?? []).contains($0 == .home ? "home" : $0 == .guide ? "tv" : "") }, id: \.self) { tab in
                slot(tab.title, chosen: marked(tab), action: { press(tab) }) {
                    Image(systemName: tab.barIcon).font(.system(size: 20, weight: .medium)).frame(width: 24, height: 24)
                }
            }
            slot("Menu", chosen: false, action: { model.menuOpen = true }) {
                Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .medium)).frame(width: 24, height: 24)
            }
            let name = model.user?.shownName ?? ""
            slot(name.isEmpty ? AppTab.profile.title : "\(AppTab.profile.title), \(name)", chosen: marked(.profile), action: { press(.profile) }) {
                if model.user != nil {
                    AvatarTile(name: name, size: 32)
                        .overlay(alignment: .topTrailing) {
                            // An update to install, for whoever can: the website's dot.
                            if model.user?.isAdmin == true, !model.serverUpdate.isEmpty {
                                Circle().fill(palette.accent).frame(width: 8, height: 8)
                                    .background(Circle().fill(palette.accent.opacity(0.25)).frame(width: 14, height: 14))
                                    .offset(x: 2, y: -6)
                                    .accessibilityLabel("Version \(model.serverUpdate) is available")
                            }
                        }
                } else {
                    Image(systemName: "person.crop.circle").font(.system(size: 22, weight: .medium))
                }
            }
        }
        .padding(Tokens.Space.s1)
        .frame(height: 60)
        .background(Capsule().fill(palette.card))
        .overlay(Capsule().strokeBorder(palette.text.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .frame(maxWidth: 416)
        .padding(.horizontal, Tokens.Space.s4)
        .frame(maxWidth: .infinity)
    }
}

private struct BarPressStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(configuration.isPressed ? palette.text.opacity(0.07) : Color.clear))
    }
}

// MARK: - The menu

/// The website's drawer on a phone (shell/Sidebar.tsx, styles.css): 240 wide in `panel`, the server's lockup, then
/// the menu's places but Home and TV guide (which are on the bar), the libraries under `LIBRARIES` (or in the
/// person's groups), as rows 40 high in 14 medium `textSecondary` with an 18 icon in `textHint`; the page you're on
/// in `accent` at 14% with its words semibold and its icon in `accentText`. The version at its foot. A `scrim` covers
/// the rest; tapping it closes the drawer, at once, as the website's does.
struct MenuDrawer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func close() { model.menuOpen = false }

    /// The place whose page is on top of Home's stack, if it's one of the menu's.
    private var currentId: String? {
        switch model.paths[.home]?.last {
        case .library(let library)?: return "lib:\(library.id)"
        case .page(let path)?: return model.navPlaces.first { $0.path == path }?.id
        case .web(let path)? where path == WebPlayer.gamePCsPath: return "couch"
        default: return nil
        }
    }

    private func row(_ place: NavPlace) -> some View {
        let here = place.id == currentId && model.tab == .home
        return Button {
            close()
            model.open(place)
        } label: {
            HStack(spacing: Tokens.Space.s3) {
                Image(systemName: symbol(place))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(here ? palette.accentText : palette.textHint)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(place.label).font(.system(size: 14, weight: here ? .semibold : .medium))
                    .foregroundStyle(here ? palette.text : palette.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(here ? palette.accent.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(DrawerRowStyle())
        .accessibilityAddTraits(here ? [.isSelected] : [])
    }

    private func symbol(_ place: NavPlace) -> String {
        switch place.id {
        case "collections": return "books.vertical"
        case "couch": return "gamecontroller"
        default:
            if let kind = place.kind, kind.hasPrefix("module:") { return kind == "module:chart" ? "chart.bar" : "puzzlepiece" }
            if let id = place.libraryId, let library = model.libraries.first(where: { $0.id == id }) { return library.symbol }
            return "folder"
        }
    }

    private func caption(_ words: String) -> some View {
        Text(words.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.77).foregroundStyle(palette.textHint)
            .padding(.horizontal, Tokens.Space.s3).padding(.top, Tokens.Space.s5).padding(.bottom, Tokens.Space.s2)
            .accessibilityAddTraits(.isHeader)
    }

    private var panel: some View {
        let places = model.navPlaces.filter { $0.id != "home" && $0.id != "tv" }
        let grouped = model.navPrefs.grouped == true
        let firstLibrary = places.firstIndex { $0.libraryId != nil }
        let version = VersionTag.parts(model.serverVersion)
        return VStack(alignment: .leading, spacing: 0) {
            BrandLockup()
                .padding(.horizontal, Tokens.Space.s3)
                .padding(.top, Tokens.Space.s3)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(places.enumerated()), id: \.element.id) { at, place in
                        if grouped, let group = NavPlaces.group(place, model.navPrefs), at == places.firstIndex(where: { NavPlaces.group($0, model.navPrefs) == group }) {
                            caption(group)
                        } else if !grouped, at == firstLibrary {
                            caption("Libraries")
                        }
                        row(place)
                    }
                    if model.libraries.isEmpty {
                        Text("No libraries yet").font(.system(size: 13)).foregroundStyle(palette.textHint)
                            .padding(.horizontal, Tokens.Space.s3).padding(.vertical, Tokens.Space.s1)
                    }
                }
                .padding(.bottom, Tokens.Space.s4)
            }
            HStack(spacing: 6) {
                Text("WittyMediaServer \(version.number)")
                if !version.stage.isEmpty {
                    Text(version.stage).font(.system(size: 11, weight: .bold)).tracking(0.55)
                        .foregroundStyle(palette.accentText)
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.accent.opacity(0.16)))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(palette.textHint)
            .padding(.horizontal, Tokens.Space.s3).padding(.top, Tokens.Space.s4).padding(.bottom, Tokens.Space.s2)
        }
        .padding(.horizontal, Tokens.Space.s3)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.panel.ignoresSafeArea())
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if model.menuOpen {
                palette.scrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .transition(.opacity)
                    .accessibilityLabel("Close the menu")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { close() }
                panel
                    .frame(width: 240)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { close() }
            }
        }
        // Opening slides in; closing is at once, as the website's drawer hides.
        .animation(model.menuOpen ? (reduceMotion ? .easeOut(duration: Tokens.Motion.focus) : .easeOut(duration: Tokens.Motion.appear)) : nil, value: model.menuOpen)
    }
}

private struct DrawerRowStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(configuration.isPressed ? palette.accent.opacity(0.14) : Color.clear))
    }
}
#endif
