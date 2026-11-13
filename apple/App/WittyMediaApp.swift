// SPDX-License-Identifier: GPL-3.0-or-later
//
// WittyMediaClient - Apps that connect to a WittyMediaServer, for TV boxes, phones, tablets and desktops.
// Copyright (C) 2026 WittyWilla and contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import SwiftUI
import WittyKit

@main
struct WittyMediaApp: App {
    @StateObject private var model = AppModel()

    init() {
        ClientLog.shared.start(app: "WittyMedia Apple", version: WittyClient.appVersion)
        TypeSet.register()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && os(iOS)
            // For checking the touch controls with no game: `-WittyPlayTouchPreview snes` at launch.
            if let console = UserDefaults.standard.string(forKey: "WittyPlayTouchPreview") {
                TouchPreviewScreen(console: console)
            } else {
                rootView
            }
            #else
            rootView
            #endif
        }
    }

    private var rootView: some View {
        Group {
            RootView()
                .environmentObject(model)
                .environmentObject(model.listening)
                .modifier(MetricsForWidth())
                .preferredColorScheme(model.scheme)
                .tint(model.palette.accentText)
                .task {
                    model.tidyServers()
                    await model.start()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// The device's own, while the automatic theme leaves it be; otherwise the theme's.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The finish of the look in use, a step lower on a modest device or when the person asked for less transparency or motion.
    private var finish: Finish {
        #if os(tvOS)
        let lowPower = false
        #else
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        #endif
        return Finish(look: model.look, palette: model.palette, theme: model.appTheme, modest: reduceTransparency || lowPower, calm: reduceMotion)
    }

    var body: some View {
        ZStack {
            SceneBackdrop()
            switch model.stage {
            case .starting:
                LoadingView()
            case .connect(let message):
                ConnectView(initialMessage: message)
            case .code(let server, let fromSignIn):
                CodeView(server: server, fromSignIn: fromSignIn)
            case .mismatch(let server):
                MismatchView(server: server)
            case .signIn(let way):
                SignInView(way: way).id(way)
            case .browsing:
                // A new shell for each server and person, so the first screen after signing in is drawn fresh.
                BrowseShell().id("\(model.client.base)|\(model.user?.id ?? 0)")
            }
        }
        // From here, which redraws with the model, and not from the scene above it, which can draw a
        // moment later: a screen that has just appeared must never ask with the connection before.
        // The profile's limits and screen time, over everything: see Household.swift.
        .modifier(ScreenTimeGuard(household: model.household))
        .modifier(FirstRunLayers())
        .environment(\.palette, model.palette)
        .environment(\.finish, finish)
        .environment(\.client, model.client)
        .animation(.easeInOut(duration: 0.2), value: model.effectiveThemeId)
        .onAppear { model.systemScheme = colorScheme }
        .onChange(of: colorScheme) { scheme in
            if model.themeChoice == "auto" || model.scheme == nil { model.systemScheme = scheme }
        }
        .onChange(of: scenePhase) { phase in
            // Off the screen, a connection from away is ended before the system ends it; back on, it starts again.
            if phase == .active { Task { await model.cameBack() } }
            if phase == .background { model.leftScreen() }
        }
        .modifier(RemoteRoot())
        #if os(tvOS)
        // Only Apple TV has anything that opens this, the Top Shelf, so only it registers the scheme.
        .onOpenURL { model.open(link: $0) }
        #endif
    }
}
