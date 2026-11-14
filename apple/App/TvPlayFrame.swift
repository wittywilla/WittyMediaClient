// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// WittyPlay's frame on Apple TV: a page whose document has regions (docs/SDUI.md, document.regions; WittyPlay Online's) is
// drawn over the whole screen with a status bar along the top (who you are, the page's line, the server's name, the time,
// Return To Server) and a round dock of its destinations along the bottom, as the website's PlayChrome draws it. The owner's
// choice: WittyPlay works the same on a television. The top menu is already gone (this is a page opened from it); the
// remote's Back leaves, as Esc does on the website, and the dock is one focus section the remote moves along.

#if os(tvOS)
struct TvPlayFrame<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    let regions: SDUIRegions
    let place: SDUIPlace
    @ViewBuilder let content: Content

    private var current: Int? {
        regions.current(path: "/page/" + place.page, query: place.params)
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
        VStack(spacing: 0) {
            if !regions.statusBar.isEmpty {
                TvPlayStatus(parts: regions.statusBar, exit: exit)
            }
            // The page and the dock are sections of their own, so Down from anywhere on the page's last row reaches the
            // dock, wherever across the screen the focus is.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
            if !regions.dock.isEmpty {
                TvPlayDock(entries: regions.dock, current: current, go: go)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The status bar: the profile's initial and name with the page's line, the server's name as its brand, the time, and
/// Return To Server.
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
        HStack(spacing: Tokens.Space.s6) {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(palette.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 31, weight: .bold)).foregroundStyle(palette.text)
                if !line.isEmpty { Text(line).font(.system(size: 25)).foregroundStyle(palette.text.opacity(0.75)) }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Tokens.Space.s6)
            // The server's own name, in its own colours.
            if parts.contains(where: { $0.kind == "server" }) { BrandLockup() }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(context.date, style: .time).font(.system(size: 31, weight: .semibold)).foregroundStyle(palette.text)
            }
            Button(action: exit) {
                Label("Return To Server", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 25, weight: .semibold))
            }
            .accessibilityHint("Leaves WittyPlay for the server's Home")
        }
        .padding(.horizontal, 90)
        .padding(.top, 40)
        .padding(.bottom, Tokens.Space.s4)
        .focusSection()
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
        HStack(alignment: .top, spacing: Tokens.Space.s8) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let on = index == current
                let lit = focused == entry.id
                VStack(spacing: Tokens.Space.s3) {
                    Button { go(entry) } label: {
                        Image(systemName: SDUIIcon.symbol(entry.icon, or: "circle"))
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(on ? palette.onAccent : palette.text)
                            .frame(width: 104, height: 104)
                            .background(Circle().fill(on ? palette.accent : palette.card))
                            .overlay(Circle().strokeBorder(palette.text.opacity(lit ? 1 : (on ? 0.9 : 0)), lineWidth: 5).padding(-10))
                    }
                    .buttonStyle(TvDockPress())
                    .focused($focused, equals: entry.id)
                    .accessibilityLabel(entry.label)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                    Text(entry.label)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .opacity(on || lit ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.bottom, 50)
        .padding(.top, Tokens.Space.s4)
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
