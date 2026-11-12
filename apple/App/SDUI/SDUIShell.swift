// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// Keeps the server's own pages and menu in step with who is signed in to what, with the window, and with the
/// app coming back to the front. Put on the shell, which is made again for each server and person.
struct SDUIShellSync: ViewModifier {
    @ObservedObject var center: SDUICenter
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var who: String {
        "\(model.client.base)|\(model.user?.id ?? 0)|\(model.featuresKnown)|\(model.features.sorted().joined(separator: ","))"
    }

    private func configure() {
        center.configure(client: model.client, user: model.user?.id ?? 0, features: model.features, known: model.featuresKnown)
    }

    /// What the rest of the app needs that the hand-built Home used to bring: the libraries, and Apple TV's Top Shelf.
    private func supply() async {
        guard center.enabled else { return }
        let client = model.client
        if let all = try? await client.libraries(), client === model.client {
            let fresh = uniqued(all)
            if fresh != model.libraries { model.libraries = fresh }
        }
        if model.features.contains(SDUI.topShelfFeature) {
            TopShelfWriter.update(fromServer: client, deviceClass: center.device.deviceClass ?? "hd")
        }
    }

    func body(content: Content) -> some View {
        content
            #if !os(tvOS)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { center.windowChanged(geo.size) }
                        .sduiOnChange(of: geo.size) { center.windowChanged($0) }
                }
                .ignoresSafeArea()
            }
            #endif
            .onAppear(perform: configure)
            .sduiOnChange(of: who) { _ in configure() }
            .sduiOnChange(of: reduceMotion) { _ in center.windowChanged(screenSize) }
            .task(id: "\(who)|\(center.mode == .on)") { await supply() }
            .sduiOnChange(of: scenePhase) { phase in
                guard phase == .active, center.enabled else { return }
                Task {
                    await center.loadMenu()
                    await supply()
                }
            }
    }
}

/// The first screen of a tab that is one of the server's menu entries: its page, or the app's own screen it names.
struct SDUIEntryRoot: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    let id: String

    var body: some View {
        if let entry = center.entry(id) {
            switch center.router.resolve(entry) {
            case .page(let page, let params):
                SDUIPageScreen(place: SDUIPlace(page: page, params: params, route: entry.route), chrome: .tabRoot).id(entry.id)
            case .native("guide", _):
                #if os(iOS) || os(visionOS)
                SDUIGuide().underStrip(path: entry.route, hidden: model.pagePlaying && (model.paths[.sdui(id)] ?? []).isEmpty)
                #else
                SDUIGuide()
                #endif
            case .native("collections", _):
                SDUIPageScreen(place: SDUIPlace(page: "collections", route: entry.route), chrome: .tabRoot)
            case .native("pair", _):
                SignInTvView().underStrip(path: entry.route)
            case .native(let screen, _):
                SDUIWebScreen(screen: screen).underStrip(path: entry.route)
            default:
                LoadingView()
            }
        } else {
            // The menu has changed under this tab: back to Home.
            LoadingView().onAppear { model.tab = .home }
        }
    }
}

/// One of the app's own screens that a phone and a tablet show as the server's page: downloads, the remote.
private struct SDUIWebScreen: View {
    let screen: String

    var body: some View {
        #if os(iOS) || os(visionOS)
        WebPlayerView(path: ["downloads": "/downloads", "remote": "/remote"][screen] ?? "/", keptToGames: false)
        #else
        YouView()
        #endif
    }
}
