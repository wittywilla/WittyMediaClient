// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// WittyPlay's frame on Apple TV: a page whose document has regions (docs/SDUI.md, document.regions; WittyPlay Online's) is
// drawn over the whole screen with a slim status bar along the top (who you are, the page's line, the server's name, the time,
// Return To Server) and a row along the bottom: the round dock of its destinations, as the website's PlayChrome
// draws it, with the page's own Dock (Sort, Filter, the remote's keys) at its sides. The owner's
// choice: WittyPlay works the same on a television. The top menu is already gone (this is a page opened from it); the
// remote's Back leaves, as Esc does on the website, and the dock is one focus section the remote moves along.

#if os(tvOS)
struct TvPlayFrame<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    let regions: SDUIRegions
    let place: SDUIPlace
    @ViewBuilder let content: Content

    private var current: Int? {
        regions.current(path: "/page/" + place.page, query: place.params)
    }

    /// The page's own Dock (its Sort and Filter, and the remote's keys), drawn in the round dock's row.
    private var pageDock: SDUIElement? {
        store.screen?.sections.first { $0.type == "Dock" && $0.children.contains { $0.type == "Button" } }
    }

    /// Return To Server: the app's Home, WittyPlay closed.
    private func exit() {
        model.paths[model.tab] = []
        model.tab = .home
    }

    private func go(_ entry: SDUIRegions.Dock) {
        if entry.route == "/search" {
            model.paths[.search] = []
            model.tab = .search
            return
        }
        if WittyPlayPlace.isPlayPath(entry.route) {
            let route = AppModel.wittyPlayRoute(entry.route)
            if entry.as == "layer" {
                model.path.append(route)
            } else {
                // A place of the dock's takes this one's place, as the website's dock does.
                var path = model.path
                if path.isEmpty { path = [route] } else { path[path.count - 1] = route }
                model.path = path
            }
            return
        }
        if let place = center.place(route: entry.route) { model.path.append(.sdui(place)) }
    }

    var body: some View {
        // The screen's own safe area is the margin: the bars add none of their own, so the page has the most room.
        VStack(spacing: 0) {
            if !regions.statusBar.isEmpty {
                TvPlayStatus(parts: regions.statusBar, exit: exit)
            }
            // The page and the bottom row are sections of their own, so Down from anywhere on the page's last row
            // reaches the row, wherever across the screen the focus is.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
            if !regions.dock.isEmpty || pageDock != nil {
                ZStack {
                    if !regions.dock.isEmpty {
                        TvPlayDock(entries: regions.dock, current: current, go: go)
                    }
                    if let pageDock, let layout = store.screen?.layout {
                        TvPlayPageControls(dock: pageDock).environment(\.sduiLayout, layout)
                    }
                }
                .padding(.top, Tokens.Space.s3)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The status bar, one slim row: the profile's initial and name with the page's line, the server's name as its
/// brand, the time, and Return To Server.
private struct TvPlayStatus: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let parts: [SDUIRegions.Status]
    let exit: () -> Void

    private var name: String { model.user?.shownName ?? "" }
    private var line: String {
        parts.first { $0.kind == "profile" }?.text ?? parts.first { $0.kind == "text" }?.text ?? ""
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s5) {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 48, height: 48)
                .background(Circle().fill(palette.accent))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
                Text(name).font(.system(size: 26, weight: .bold)).foregroundStyle(palette.text)
                if !line.isEmpty { Text(line).font(.system(size: 22)).foregroundStyle(palette.text.opacity(0.7)) }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: Tokens.Space.s6)
            // The server's own name, in its own colours, at the size of the bar.
            if parts.contains(where: { $0.kind == "server" }) {
                HStack(spacing: Tokens.Space.s2) {
                    BrandMark(size: 36, logo: model.client.brandLogoURL(version: model.brandLogo))
                    Wordmark(name: model.brandName, brand: model.themeStyle?.brand, colors: model.themeStyle?.colors ?? [:], size: 26)
                }
                .accessibilityElement(children: .combine)
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(context.date, style: .time).font(.system(size: 26, weight: .semibold)).foregroundStyle(palette.text.opacity(0.85))
            }
            Button(action: exit) {
                Label("Return To Server", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 22, weight: .semibold))
            }
            .accessibilityHint("Leaves WittyPlay for the server's Home")
        }
        .frame(height: 64)
        .padding(.bottom, Tokens.Space.s2)
        .focusSection()
    }
}

/// The page's own Dock beside the round dock: its buttons (Sort, Filter) on the left, the remote's keys on the right.
private struct TvPlayPageControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    let dock: SDUIElement

    private var buttons: [SDUIElement] { dock.children.filter { $0.type == "Button" } }
    private var legend: SDUIElement? { dock.children.first { $0.type == "KeyLegend" } }

    var body: some View {
        HStack(spacing: Tokens.Space.s3) {
            ForEach(buttons) { button in
                Button { SDUIActor(model: model, center: center, store: store).perform(button.action) } label: {
                    Label(button.props.text("label"), systemImage: SDUIIcon.symbol(button.icon, or: "slider.horizontal.3"))
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                }
                .action(pill: true)
                .accessibilityIdentifier("sdui.dock." + button.id)
            }
            Spacer(minLength: 0)
            if let legend { SDUIKeyLegend(legend: legend) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dock.label)
    }
}

/// The round dock: a circle for each destination, the current one filled and named, the focused one lifted and named.
private struct TvPlayDock: View {
    @Environment(\.palette) private var palette
    let entries: [SDUIRegions.Dock]
    let current: Int?
    let go: (SDUIRegions.Dock) -> Void
    @FocusState private var focused: String?

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let on = index == current
                let lit = focused == entry.id
                Button { go(entry) } label: {
                    Image(systemName: SDUIIcon.symbol(entry.icon, or: "circle"))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(on ? palette.onAccent : palette.text)
                        .frame(width: 80, height: 80)
                        .background(Circle().fill(on ? palette.accent : palette.card))
                        .overlay(Circle().strokeBorder(palette.text.opacity(lit ? 1 : (on ? 0.9 : 0)), lineWidth: 4).padding(-8))
                }
                .buttonStyle(TvDockPress())
                .focused($focused, equals: entry.id)
                .accessibilityLabel(entry.label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
                // The name floats under the circle, in the screen's margin, so it takes no room from the page.
                .overlay(alignment: .bottom) {
                    Text(entry.label)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .fixedSize()
                        .offset(y: 34)
                        .opacity(on || lit ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }
}

/// A dock circle lifts while it has focus, as the system's own do.
private struct TvDockPress: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : (focused ? 1.12 : 1))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
#endif
