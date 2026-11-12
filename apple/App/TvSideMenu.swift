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
    /// Which entry had focus last, nil while it's out on the page.
    @State private var inside: AppTab?

    private var isOpen: Bool { focus.wrappedValue != nil }

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
        let places = TvTopBar.entries(model: model, center: center)
        VStack(spacing: Tokens.Space.s2) {
            BrandMark(size: 56).padding(.vertical, Tokens.Space.s6)
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
