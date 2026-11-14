// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// The app's frame on a phone, a tablet and Vision Pro as the server's navigation says it (`navigation.shell`, the
// server's docs/SDUI.md, Layout options): the floating bar at the bottom (`bottomTabs`, as always), a row of tabs
// across the top (`topTabs`), or a menu down the side (`sidebar`, or `rail`: its icons only). The app never picks a
// style of its own; against a server without layout options it is the floating bar, as before. Apple TV's top menu
// and side menu are in TvTabs.swift and TvSideMenu.swift.

/// The menu's style for the frame here, from the catalogue's `navStyles` the server's shell names (docs/SDUI.md, Experiences). The frame
/// is drawn from the style, never from which experience is chosen: bars across the top share one layout and differ in finish.
enum FrameNav: String {
    case bottomTabs, topTabs, sidebar, rail, railDrawer, ornament
    /// How a bar across the top is finished, for the styles that are one.
    enum Finish { case plain, glass, cable, bevel, teleKeys, crossbar }

    static func of(_ shell: SDUIShell?) -> FrameNav {
        switch shell?.nav {
        case "topTabs", "floatingGlassBar", "cableBar", "bevelBar", "teleKeys", "crossbar": return .topTabs
        case "sidebar": return .sidebar
        case "rail": return .rail
        case "railDrawer": return .railDrawer
        case "ornamentTabs": return .ornament
        default: return .bottomTabs
        }
    }

    static func finish(_ shell: SDUIShell?) -> Finish {
        switch shell?.nav {
        case "floatingGlassBar": return .glass
        case "cableBar": return .cable
        case "bevelBar": return .bevel
        case "teleKeys": return .teleKeys
        case "crossbar": return .crossbar
        default: return .plain
        }
    }

    /// Whether the frame itself lists every place, so the strip above a page has nothing to add.
    var listsEverything: Bool { self != .bottomTabs }
}

private struct FrameNavKey: EnvironmentKey { static let defaultValue = FrameNav.bottomTabs }

extension EnvironmentValues {
    var frameNav: FrameNav {
        get { self[FrameNavKey.self] }
        set { self[FrameNavKey.self] = newValue }
    }
}

#if !os(tvOS)
/// What the side menu and the top tabs list: every entry of the server's menu that this app opens, in its order,
/// with You last; each chooses its tab, or opens its page on Home's stack as the drawer does.
@MainActor
struct FrameEntries {
    let center: SDUICenter
    let model: AppModel

    var entries: [SDUINavItem] {
        let you = center.youEntry
        // Settings is You here: one entry for both, at the end.
        // A region the placements hide isn't drawn: Search where the shell has hidden it (Settings and You are never hideable).
        let searchShown = center.shell?.shows("search") != false
        let rest = center.items.filter {
            !$0.isSettings && $0.id != you?.id && model.household.shown([center.tab(for: $0)]).count == 1
                && (searchShown || ($0.route != "/search" && $0.id != "search"))
        }
        return rest + (you.map { [$0] } ?? [])
    }

    func isCurrent(_ entry: SDUINavItem) -> Bool {
        let tab = center.tab(for: entry)
        if center.phoneTabs.contains(tab), tab != .home {
            return model.tab == tab && (model.paths[tab] ?? []).isEmpty
        }
        guard model.tab == .home else { return false }
        if case .sdui(let place)? = model.paths[.home]?.last { return place.route == entry.route }
        return tab == .home && (model.paths[.home] ?? []).isEmpty
    }

    func open(_ entry: SDUINavItem) {
        if let address = model.wittyPlayAddress(.page(entry.address)) { model.wittyPlay = address; return }
        let tab = center.tab(for: entry)
        if center.phoneTabs.contains(tab), tab != .home {
            if model.tab == tab { model.paths[tab] = [] } else { model.tab = tab }
            return
        }
        if let place = center.navPlaces([entry]).first { center.open(place, model: model) }
    }

    func symbol(_ entry: SDUINavItem) -> String { SDUIIcon.symbol(entry.icon, or: "square") }
    func label(_ entry: SDUINavItem) -> String { PlainWords.clean(entry.label, limit: 40) }
}

/// A menu down the leading side: the brand at the top, then every place with its icon and name; as a rail, the icons
/// alone in a narrow column, each named for VoiceOver and in a tooltip with a pointer.
struct SideMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    let width: CGFloat
    let iconsOnly: Bool
    /// A rail that can be kept open: this is its pin (shown while it is open).
    var pinned: Binding<Bool>?
    /// A rail with a library drawer: choosing an entry that has one opens it (the entry is passed here) instead of the page.
    var drawerEntry: Binding<SDUINavItem?>?

    var body: some View {
        let list = FrameEntries(center: center, model: model)
        VStack(alignment: iconsOnly ? .center : .leading, spacing: 2) {
            if center.shell?.shows("brand") != false {
                if iconsOnly {
                    // The mark in a square badge, centred: never a bare letter.
                    BrandBadge(size: 48).padding(.vertical, Tokens.Space.s3)
                } else {
                    BrandLockup().padding(.horizontal, Tokens.Space.s3).padding(.vertical, Tokens.Space.s3)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: iconsOnly ? .center : .leading, spacing: 2) {
                    ForEach(list.entries) { entry in
                        let here = list.isCurrent(entry)
                        Button { if let drawerEntry, entry.drawer != nil { drawerEntry.wrappedValue = entry } else { list.open(entry) } } label: {
                            HStack(spacing: Tokens.Space.s3) {
                                Image(systemName: list.symbol(entry))
                                    .font(.system(size: iconsOnly ? 20 : 16, weight: .medium))
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(here ? palette.accentText : palette.textSecondary)
                                if !iconsOnly {
                                    Text(list.label(entry))
                                        .font(.system(size: 15, weight: here ? .semibold : .medium))
                                        .foregroundStyle(here ? palette.text : palette.textSecondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(.horizontal, iconsOnly ? 0 : Tokens.Space.s3)
                            .frame(maxWidth: iconsOnly ? 48 : .infinity, minHeight: iconsOnly ? 48 : 40)
                            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                                .fill(here ? palette.accent.opacity(0.14) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FramePressStyle())
                        .help(list.label(entry))
                        .accessibilityLabel(list.label(entry))
                        .accessibilityAddTraits(here ? [.isSelected] : [])
                        .accessibilityIdentifier("frame.entry." + entry.id)
                    }
                }
                .padding(.horizontal, iconsOnly ? 0 : Tokens.Space.s2)
            }
            if let pinned, !iconsOnly {
                Toggle(isOn: pinned) { Label("Keep menu open", systemImage: pinned.wrappedValue ? "pin.fill" : "pin") }
                    .toggleStyle(.button)
                    .padding(Tokens.Space.s3)
                    .accessibilityIdentifier("frame.pin")
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.panel.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(palette.border).frame(width: 1).ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu")
    }
}

/// The rail: icons and the mark's badge while closed, the full menu (names, the brand lockup, Keep menu open) when it has the
/// pointer, focus or a pin. The widths are the shell's (`size` closed, `open` open).
struct RailMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    let closed: CGFloat
    let open: CGFloat
    /// The width of a library's drawer beside the menu; 0 for a rail without one.
    var drawerWidth: CGFloat = 0
    @AppStorage("frame.railPinned") private var pinned = false
    @State private var hovering = false
    @State private var drawer: SDUINavItem?

    var body: some View {
        let isOpen = pinned || hovering || drawer != nil
        HStack(spacing: 0) {
            SideMenu(width: isOpen ? open : closed, iconsOnly: !isOpen, pinned: $pinned, drawerEntry: drawerWidth > 0 ? $drawer : nil)
            if let entry = drawer, let content = entry.drawer, drawerWidth > 0 {
                RailDrawer(entry: entry, content: content, width: drawerWidth) { drawer = nil }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: DesignTokens.Motion.screen / 1000), value: isOpen)
        .animation(.easeOut(duration: DesignTokens.Motion.screen / 1000), value: drawer?.id)
        .onHover { hovering = $0 }
        // The options key opens it for a keyboard; Escape (Back) closes the drawer, then the rail.
        .background {
            Group {
                Button("") { hovering.toggle() }.keyboardShortcut(".", modifiers: [])
                Button("") { if drawer != nil { drawer = nil } else { hovering = false; pinned = false } }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A library's drawer: its name large with its icon and item count, then its views (Recently added, Genres, Collections, All ...).
struct RailDrawer: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    let entry: SDUINavItem
    let content: SDUINavDrawer
    let width: CGFloat
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack(spacing: Tokens.Space.s3) {
                Image(systemName: SDUIIcon.symbol(content.icon, or: "folder")).font(.system(size: 22, weight: .semibold)).foregroundStyle(palette.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(PlainWords.clean(content.title, limit: 40)).font(.system(size: 22, weight: .bold)).foregroundStyle(palette.text).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if let count = content.count, count > 0 {
                        Text(count == 1 ? "1 title" : "\(count) titles").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(palette.textSecondary)
                    .accessibilityLabel("Close \(content.title)")
            }
            .padding(.top, Tokens.Space.s3)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(content.views) { view in
                        Button {
                            if let route = view.route { model.tab = .home; SDUIActor(model: model, center: center, store: nil).open(route: route) }
                            close()
                        } label: {
                            HStack(spacing: Tokens.Space.s3) {
                                Image(systemName: SDUIIcon.symbol(view.icon, or: "square")).frame(width: 24).accessibilityHidden(true)
                                Text(view.label).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, Tokens.Space.s3)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("frame.drawer." + view.id)
                    }
                }
            }
        }
        .padding(.horizontal, Tokens.Space.s3)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.card.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(palette.border).frame(width: 1).ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.title)
    }
}

/// A row of tabs across the top: every place by name, scrolling sideways when they don't fit, You at the end. Laid
/// over the page (`overlay`) it is clear with a scrim behind its words until the page scrolls under it, then turns
/// solid as the library strip does, by `solid` (0 at the top of the page, 1 once it has scrolled under).
struct TopTabsBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    let height: CGFloat
    let overlay: Bool
    var solid = 1.0
    var finish = FrameNav.Finish.plain

    /// How the chosen tab is marked, by the bar's finish: a tinted pill; a gloss pill; a flat accent band (cable); a bevelled key;
    /// a colour-coded key (teletext); or a large icon over its name (crossbar).
    @ViewBuilder private func chosenBackground(_ here: Bool, index: Int) -> some View {
        let keys = [Color.red, Color.green, Color.yellow, Color.cyan]
        switch finish {
        case .plain:
            Capsule().fill(here ? palette.accent.opacity(0.16) : .clear)
        case .glass:
            Capsule().fill(here ? AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.45), palette.accent.opacity(0.35)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.clear))
                .overlay(Capsule().strokeBorder(here ? .white.opacity(0.6) : .clear, lineWidth: 1))
        case .cable:
            Rectangle().fill(here ? palette.accent : palette.card)
        case .bevel:
            RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
                .fill(LinearGradient(colors: here ? [palette.accent.opacity(0.9), palette.accent] : [palette.raised, palette.card], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        case .teleKeys:
            Rectangle().fill(keys[index % keys.count].opacity(here ? 1 : 0.55))
        case .crossbar:
            Capsule().fill(here ? palette.accent.opacity(0.2) : .clear)
        }
    }

    private func chosenText(_ here: Bool) -> Color {
        switch finish {
        case .cable: return here ? palette.onAccent : palette.text
        case .teleKeys: return .black
        default: return here ? palette.text : palette.textSecondary
        }
    }

    var body: some View {
        let list = FrameEntries(center: center, model: model)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s1) {
                ForEach(Array(list.entries.enumerated()), id: \.element.id) { index, entry in
                    let here = list.isCurrent(entry)
                    Button { list.open(entry) } label: {
                        Group {
                            if finish == .crossbar {
                                VStack(spacing: 2) {
                                    Image(systemName: list.symbol(entry)).font(.system(size: 20, weight: .medium)).accessibilityHidden(true)
                                    Text(list.label(entry)).font(.system(size: 11, weight: here ? .semibold : .medium)).lineLimit(1)
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Image(systemName: list.symbol(entry)).font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
                                    Text(list.label(entry)).font(.system(size: 15, weight: here ? .semibold : .medium)).lineLimit(1)
                                }
                            }
                        }
                        .foregroundStyle(chosenText(here))
                        .padding(.horizontal, Tokens.Space.s3)
                        .frame(minHeight: max(height - 12, 32))
                        .background(chosenBackground(here, index: index))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FramePressStyle())
                    .accessibilityAddTraits(here ? [.isSelected] : [])
                    .accessibilityIdentifier("frame.entry." + entry.id)
                }
            }
            .padding(.horizontal, Tokens.Space.s3)
        }
        .frame(height: height)
        .background {
            ZStack {
                if overlay {
                    LinearGradient(colors: [palette.background.opacity(0.85), palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .opacity(1 - solid)
                }
                ZStack {
                    switch finish {
                    case .glass:
                        Rectangle().fill(.regularMaterial)
                        LinearGradient(colors: [.white.opacity(0.35), palette.accent.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    case .cable:
                        palette.panel
                    case .bevel:
                        LinearGradient(colors: [palette.raised, palette.panel], startPoint: .top, endPoint: .bottom)
                    case .teleKeys:
                        Color.black
                    default:
                        Rectangle().fill(.regularMaterial)
                        palette.background.opacity(0.85)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(finish == .bevel ? Color.white.opacity(0.35) : palette.border).frame(height: 1) }
                .opacity(overlay ? solid : 1)
            }
            .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu")
    }
}
/// The top tabs on one tab's stack, so the screens pushed onto it lay out below them; over the page when `overlay`,
/// solid once the page under them scrolls (see `stripSolidity`).
struct TopTabsSlot: ViewModifier {
    let nav: FrameNav
    let height: CGFloat
    let overlay: Bool
    let shown: Bool
    var finish = FrameNav.Finish.plain
    @State private var solid = 0.0

    func body(content: Content) -> some View {
        if nav != .topTabs {
            content
        } else if overlay {
            content
                .stripSolidity($solid)
                .overlay(alignment: .top) { if shown { TopTabsBar(height: height, overlay: true, solid: solid, finish: finish) } }
        } else {
            // Above the stack, not an inset of it: a page pushed onto it lays out below the tabs, its Back with it.
            VStack(spacing: 0) {
                if shown { TopTabsBar(height: height, overlay: false, finish: finish) }
                // The clock's room is the tabs' now: the pages start right under them.
                content.ignoresSafeArea(.container, edges: shown ? .top : [])
            }
        }
    }
}

/// A press shows as a faint wash, as the floating bar's does.
private struct FramePressStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(configuration.isPressed ? palette.text.opacity(0.07) : Color.clear))
    }
}
#endif
