// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import SwiftUI
import WittyKit

/// Apple TV's menu down the side, for a layout whose navigation says `tvSideMenu` (the server's docs/SDUI.md, Layout
/// options): a column of icons `closed` points wide at the leading edge, which opens to `open` points with the
/// places' names while it has focus, over the page rather than pushing it. The same places as the top bar, in its
/// order, You at the foot. Left from a page's first card reaches it; choosing a place shows it and keeps focus on it;
/// Back goes to Home's, then out of the app, as the top bar does.
struct TvSideMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var focus: FocusState<AppTab?>.Binding
    let closed: CGFloat
    let open: CGFloat
    /// The width of a library's drawer beside the open menu (`shell.drawer`); 0 for a menu without one.
    var drawerWidth: CGFloat = 0
    /// Which entry had focus last, nil while it's out on the page.
    @State private var inside: AppTab?
    /// The entry the drawer is for: the last library entry that had focus, while the menu is open.
    @State private var drawerTab: AppTab?
    @FocusState private var drawerFocus: String?

    private var isOpen: Bool { focus.wrappedValue != nil || drawerFocus != nil }

    /// The drawer data of the menu entry for a tab, where the server gave one.
    private func drawer(for tab: AppTab?) -> SDUINavDrawer? {
        guard drawerWidth > 0, let tab else { return nil }
        return center.items.first { center.tab(for: $0) == tab && $0.drawer != nil }?.drawer
    }

    private func choose(_ tab: AppTab) {
        if model.tab == tab {
            model.paths[tab] = []
        } else {
            model.tab = tab
        }
    }

    private var back: (() -> Void)? {
        guard model.tab != .home else { return nil }
        return {
            if !(model.paths[.home] ?? []).isEmpty { model.paths[.home] = [] }
            model.tab = .home
            focus.wrappedValue = .home
        }
    }

    private func entry(_ tab: AppTab, _ name: String, _ symbol: String) -> some View {
        let chosen = model.tab == tab
        return Button { choose(tab) } label: {
            HStack(spacing: Tokens.Space.s4) {
                Group {
                    if tab == .profile, let user = model.user {
                        AvatarTile(name: user.shownName, size: 40, picture: user.avatar)
                    } else {
                        Image(systemName: symbol).font(.system(size: 30, weight: .medium))
                    }
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
                if isOpen {
                    Text(tab == .profile ? (model.user?.shownName ?? name) : name)
                        .font(.wmLabel)
                        .lineLimit(1)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(chosen ? palette.accentText : palette.textSecondary)
            .padding(.horizontal, Tokens.Space.s4)
            .frame(width: (isOpen ? open : closed) - Tokens.Space.s6, height: 76, alignment: isOpen ? .leading : .center)
        }
        .buttonStyle(SurfaceStyle(fill: chosen ? palette.accent.opacity(0.14) : nil, radius: Tokens.Radius.lg))
        .focused(focus, equals: tab)
        .accessibilityLabel(tab == .profile ? say("youTab") : name)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .accessibilityIdentifier("frame.entry." + tab.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            menu
            if isOpen, let content = drawer(for: drawerTab) { drawerColumn(content) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // The drawer is for the library entry that had focus last.
        .onChange(of: focus.wrappedValue) { next in
            if let next, drawer(for: next) != nil { drawerTab = next } else if let next, drawerFocus == nil { drawerTab = next }
        }
        .onExitCommand(perform: drawerFocus != nil ? { drawerFocus = nil; focus.wrappedValue = drawerTab } : nil)
    }

    /// A library's drawer: its name large with the icon and count, then its views; Back returns to the menu.
    private func drawerColumn(_ content: SDUINavDrawer) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack(spacing: Tokens.Space.s4) {
                Image(systemName: SDUIIcon.symbol(content.icon, or: "folder")).font(.system(size: 34, weight: .semibold)).foregroundStyle(palette.accentText)
                VStack(alignment: .leading, spacing: 0) {
                    Text(PlainWords.clean(content.title, limit: 40)).font(.system(size: 44, weight: .bold)).foregroundStyle(palette.text).lineLimit(1)
                    if let count = content.count, count > 0 {
                        Text(count == 1 ? "1 title" : "\(count) titles").font(.system(size: 25)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(.vertical, Tokens.Space.s6)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(content.views) { view in
                        Button {
                            if let route = view.route {
                                model.tab = .home
                                SDUIActor(model: model, center: center, store: nil).open(route: route)
                            }
                        } label: {
                            HStack(spacing: Tokens.Space.s4) {
                                Image(systemName: SDUIIcon.symbol(view.icon, or: "square")).font(.system(size: 28)).frame(width: 40)
                                Text(view.label).font(.wmLabel).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, Tokens.Space.s4)
                            .frame(width: drawerWidth - Tokens.Space.s8, height: 76, alignment: .leading)
                        }
                        .buttonStyle(SurfaceStyle(fill: nil, radius: Tokens.Radius.lg))
                        .focused($drawerFocus, equals: view.id)
                        .accessibilityIdentifier("frame.drawer." + view.id)
                    }
                }
            }
            .unclippedScroll()
        }
        .padding(.horizontal, Tokens.Space.s4)
        .frame(width: drawerWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.card.opacity(0.97).ignoresSafeArea().shadow(color: .black.opacity(0.5), radius: 30, x: 10))
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.title)
    }

    private var menu: some View {
        let places = TvTopBar.entries(model: model, center: center)
        return VStack(spacing: Tokens.Space.s2) {
            if center.shell?.shows("brand") != false {
                // The mark in a centred badge while closed, the name in its colours once open.
                if isOpen {
                    BrandLockup().padding(.horizontal, Tokens.Space.s4).padding(.vertical, Tokens.Space.s6).frame(width: open, alignment: .leading)
                } else {
                    BrandBadge(size: 72).padding(.vertical, Tokens.Space.s6)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Tokens.Space.s2) {
                    ForEach(places, id: \.tab) { entry($0.tab, $0.name, $0.symbol) }
                }
                .padding(.vertical, Tokens.Space.s2)
            }
            .unclippedScroll()
            Spacer(minLength: Tokens.Space.s4)
            entry(.profile, AppTab.profile.title, AppTab.profile.icon).padding(.bottom, Tokens.Space.s8)
        }
        .frame(width: isOpen ? open : closed)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // Open, it lies over the page with the page dimmed beside it.
            palette.panel.opacity(isOpen ? 0.97 : 0.9).ignoresSafeArea()
                .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 30, x: 10)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: isOpen)
        .focusSection()
        .onExitCommand(perform: back)
        // Coming in from a page lands on the tab that is showing, whichever entry happens to be beside.
        .onChange(of: focus.wrappedValue) { next in
            if let next, inside == nil, next != model.tab {
                focus.wrappedValue = model.tab
                inside = model.tab
            } else {
                inside = next
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Menu")
    }
}
#endif
