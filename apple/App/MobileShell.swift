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
        coordinateSpace(name: ScrollTop.space)
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                let next = (min(max((offset - 8) / 56, 0), 1) * 10).rounded() / 10
                if next != solid.wrappedValue { solid.wrappedValue = next }
            }
    }
}

// MARK: - The library strip

/// The libraries' names along the top of Home and the library pages: 15 bold, `textSecondary`, 20 apart, 44 high,
/// scrolling sideways, the current one in `text` over a 2-high `accent` line. Once the page scrolls under it, it
/// gains `background` at 85% with a blur, and a hairline. Over a picture, a soft scrim of `background` fades down
/// behind it, so the names stay sharp and readable on any picture (a glow round each word blurs them).
struct LibraryStrip: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    /// The library whose page this is, if any.
    var current: Int64?
    /// 0 over a picture or at rest, 1 once something has scrolled under it.
    var solid: Double = 0
    /// Whether it starts over a picture, as on Home's hero.
    var overPicture = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s5) {
                    ForEach(model.libraries) { library in
                        let here = library.id == current
                        Button {
                            model.openLibrary(library)
                        } label: {
                            Text(library.name)
                                .font(.system(size: PageType.body.size, weight: .bold))
                                .foregroundStyle(here ? palette.text : palette.textSecondary)
                                .lineLimit(1)
                                .frame(height: 44)
                                .overlay(alignment: .bottom) {
                                    if here { Rectangle().fill(palette.accent).frame(height: 2) }
                                }
                                // Just enough of an edge to part a word from a busy picture, without softening it.
                                .shadow(color: palette.background.opacity(overPicture && solid < 1 ? 0.5 : 0), radius: 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(library.id)
                        .accessibilityAddTraits(here ? [.isSelected] : [])
                    }
                }
                .padding(.leading, metrics.gutter)
                .padding(.trailing, Tokens.Space.s5)
            }
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: .center) }
            }
        }
        .frame(height: 44)
        .background(alignment: .bottom) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                palette.background.opacity(0.85)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
            .ignoresSafeArea(edges: .top)
            .opacity(solid)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Libraries")
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
            .init(color: palette.background.opacity(0.7), location: (top + 22) / (top + 76)),
            .init(color: palette.background.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: top + 44 + Tokens.Space.s8)
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

    func body(content: Content) -> some View {
        // Where the website's has it: in a bar 52 high, the circle 6 from its top and 16 from the side. Hidden, it
        // leaves the page where it is: a server's page underneath mustn't be made again, which would reload it.
        if overPicture {
            content.overlay(alignment: .topLeading) {
                if !hidden {
                    PageBackButton().padding(.leading, metrics.gutter - 2).padding(.top, Tokens.Space.s1)
                }
            }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                if !hidden {
                    HStack { PageBackButton(); Spacer(minLength: 0) }
                        .padding(.horizontal, metrics.gutter - 2)
                        .padding(.vertical, Tokens.Space.s1)
                        .background {
                            ZStack {
                                Rectangle().fill(.ultraThinMaterial)
                                palette.background.opacity(0.85)
                            }
                            .ignoresSafeArea(edges: .top)
                        }
                }
            }
        }
    }
}

extension View {
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
            ForEach([AppTab.home, .guide, .search], id: \.self) { tab in
                slot(tab.title, chosen: model.tab == tab, action: { press(tab) }) {
                    Image(systemName: tab.barIcon).font(.system(size: 20, weight: .medium)).frame(width: 24, height: 24)
                }
            }
            slot("Menu", chosen: false, action: { model.menuOpen = true }) {
                Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .medium)).frame(width: 24, height: 24)
            }
            let name = model.user?.shownName ?? ""
            slot(name.isEmpty ? AppTab.profile.title : "\(AppTab.profile.title), \(name)", chosen: model.tab == .profile, action: { press(.profile) }) {
                if model.user != nil {
                    AvatarTile(name: name, size: 32)
                } else {
                    Image(systemName: "person.crop.circle").font(.system(size: 22, weight: .medium))
                }
            }
        }
        .padding(Tokens.Space.s1)
        .frame(height: 60)
        .background(Capsule().fill(palette.card))
        .overlay(Capsule().strokeBorder(palette.control, lineWidth: 1))
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

/// A drawer from the left, 280 wide (at most 80%), in `panel`: the server's lockup, then `LIBRARIES`, then every
/// library as a row 44 high, and the other places. A `scrim` covers everything else, the bar included.
/// Swiping left or tapping the scrim closes it.
struct MenuDrawer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    private func close() { model.menuOpen = false }

    private func row(_ name: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s3) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(name).pageFont(.label).foregroundStyle(palette.text).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(DrawerRowStyle())
    }

    private func go(_ route: Route) {
        close()
        model.tab = .home
        model.paths[.home] = [route]
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandLockup()
                .padding(.horizontal, Tokens.Space.s3)
                .padding(.top, Tokens.Space.s3)
                .padding(.bottom, Tokens.Space.s5)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    CaptionLabel("Libraries").padding(.horizontal, Tokens.Space.s3).padding(.bottom, Tokens.Space.s2)
                    ForEach(model.libraries) { library in
                        row(library.name, symbol: library.symbol) {
                            close()
                            model.openLibrary(library)
                        }
                    }
                    CaptionLabel("More").padding(.horizontal, Tokens.Space.s3).padding(.top, Tokens.Space.s5).padding(.bottom, Tokens.Space.s2)
                    row("Collections", symbol: "square.stack") { go(.page(ServerPages.collections)) }
                    if model.gamePCs {
                        row("Game PCs", symbol: "desktopcomputer") { go(.web(WebPlayer.gamePCsPath)) }
                    }
                }
                .padding(.bottom, Tokens.Space.s6)
            }
        }
        .padding(.horizontal, Tokens.Space.s3)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.panel.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(palette.border).frame(width: 1).ignoresSafeArea() }
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(280, geo.size.width * 0.8)
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
                        .frame(width: width)
                        .offset(x: min(drag, 0))
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { drag = $0.translation.width }
                                .onEnded { value in
                                    if value.translation.width < -width / 4 || value.predictedEndTranslation.width < -width / 2 { close() }
                                    drag = 0
                                }
                        )
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { close() }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: Tokens.Motion.focus) : .easeOut(duration: Tokens.Motion.appear), value: model.menuOpen)
        }
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
