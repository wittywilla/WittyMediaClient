// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// The app's frame on a phone, a tablet and Vision Pro as the server's navigation says it (`navigation.shell`, the
// server's docs/SDUI.md, Layout options): the floating bar at the bottom (`bottomTabs`, as always), a row of tabs
// across the top (`topTabs`), or a menu down the side (`sidebar`, or `rail`: its icons only). The app never picks a
// style of its own; against a server without layout options it is the floating bar, as before. Apple TV's top menu
// and side menu are in TvTabs.swift and TvSideMenu.swift.

/// The menu's style for the frame here: the navigation's, where it names one this device draws.
enum FrameNav: String {
    case bottomTabs, topTabs, sidebar, rail

    static func of(_ shell: SDUIShell?) -> FrameNav {
        switch shell?.nav {
        case "topTabs": return .topTabs
        case "sidebar": return .sidebar
        case "rail": return .rail
        default: return .bottomTabs
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
        let rest = center.items.filter { !$0.isSettings && $0.id != you?.id && model.household.shown([center.tab(for: $0)]).count == 1 }
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

    var body: some View {
        let list = FrameEntries(center: center, model: model)
        VStack(alignment: iconsOnly ? .center : .leading, spacing: 2) {
            if iconsOnly {
                BrandMark(size: 32).padding(.vertical, Tokens.Space.s3)
            } else {
                BrandLockup().padding(.horizontal, Tokens.Space.s3).padding(.vertical, Tokens.Space.s3)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: iconsOnly ? .center : .leading, spacing: 2) {
                    ForEach(list.entries) { entry in
                        let here = list.isCurrent(entry)
                        Button { list.open(entry) } label: {
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
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.panel.ignoresSafeArea())
        .overlay(alignment: .trailing) { Rectangle().fill(palette.border).frame(width: 1).ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu")
    }
}

/// A row of tabs across the top: every place by name, scrolling sideways when they don't fit, You at the end. Laid
/// over the page (`overlay`) it is clear with a scrim behind its words until the page scrolls under it.
struct TopTabsBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    let height: CGFloat
    let overlay: Bool

    var body: some View {
        let list = FrameEntries(center: center, model: model)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s1) {
                ForEach(list.entries) { entry in
                    let here = list.isCurrent(entry)
                    Button { list.open(entry) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: list.symbol(entry)).font(.system(size: 14, weight: .medium)).accessibilityHidden(true)
                            Text(list.label(entry)).font(.system(size: 15, weight: here ? .semibold : .medium)).lineLimit(1)
                        }
                        .foregroundStyle(here ? palette.text : palette.textSecondary)
                        .padding(.horizontal, Tokens.Space.s3)
                        .frame(minHeight: max(height - 12, 32))
                        .background(Capsule().fill(here ? palette.accent.opacity(0.16) : .clear))
                        .contentShape(Capsule())
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
            if overlay {
                LinearGradient(colors: [palette.background.opacity(0.85), palette.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
            } else {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    palette.background.opacity(0.85)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu")
    }
}
/// The top tabs on one tab's stack, so the screens pushed onto it lay out below them; over the page when `overlay`.
struct TopTabsSlot: ViewModifier {
    let nav: FrameNav
    let height: CGFloat
    let overlay: Bool
    let shown: Bool

    func body(content: Content) -> some View {
        if nav != .topTabs {
            content
        } else if overlay {
            content.overlay(alignment: .top) { if shown { TopTabsBar(height: height, overlay: true) } }
        } else {
            // Above the stack, not an inset of it: a page pushed onto it lays out below the tabs, its Back with it.
            VStack(spacing: 0) {
                if shown { TopTabsBar(height: height, overlay: false) }
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
