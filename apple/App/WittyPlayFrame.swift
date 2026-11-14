// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// WittyPlay over the whole app, as the website and the desktop app have it: the owner's choice for every app ("On mobile,
// I want the games button to launch WittyPlay"). It is the server's own WittyPlay, in its own frame and colours (a status
// bar, a round dock, Return To Server; WittyMediaServer web/src/shell/PlayChrome.tsx), so it is the same everywhere. A
// game's Play plays in this app's own player, with the touch controls. Leaving WittyPlay's pages (Return To Server, or the
// dock's Search) closes it and goes there in the app. iPhone and iPad: Apple TV has its own games screens.

#if os(iOS) || os(visionOS)
extension View {
    /// WittyPlay's frame over everything, while `AppModel.wittyPlay` names a place in it.
    func wittyPlayCover() -> some View { modifier(WittyPlayCover()) }
}

private struct WittyPlayCover: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.palette) private var palette
    @Environment(\.client) private var client
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(get: { model.wittyPlay != nil }, set: { if !$0 { model.wittyPlay = nil } })) {
            WittyPlayFrame(start: model.wittyPlay ?? WittyPlayPlace.home)
                .environmentObject(model)
                .environmentObject(listening)
                .environment(\.palette, palette)
                .environment(\.client, client)
                .environment(\.metrics, metrics)
                .preferredColorScheme(model.scheme)
        }
    }
}

struct WittyPlayFrame: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    /// Where it opened: WittyPlay's home, or one games library as WittyPlay draws it.
    let start: String
    @State private var failed = false
    @State private var game: (id: Int64, start: GameStart)?
    @State private var attempt = 0

    /// The page went somewhere that isn't WittyPlay's: WittyPlay closes, and the app goes there.
    private func went(_ path: String) {
        guard !WittyPlayPlace.isPlayPath(path), !WebPlayer.isPlayer(path: path) else { return }
        model.wittyPlay = nil
        switch path {
        case WittyPlayPlace.exit: model.tab = .home
        case "/search": model.tab = .search
        default: model.path.append(.page(path))
        }
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if failed || client.token.isEmpty {
                ProblemView(words: "WittyPlay couldn't open. Check the server is on, then try again.",
                            retry: { failed = false; attempt += 1 }, back: { model.wittyPlay = nil })
            } else if let url = client.mediaURL(start) {
                WebPlayerPage(base: client.root, token: client.token, url: url, keptToGames: false,
                              theme: model.themeChoice == "custom" ? "" : model.themeChoice, backdrop: UIColor(palette.background),
                              onLeave: {}, onFail: { failed = true }, onSaved: { _ in }, onPath: went,
                              onGame: { address, _ in
                                  // A game's Play: this app's player, over WittyPlay, which is there again after.
                                  if let found = WebPlayer.serverGame(address) {
                                      listening.pauseForVideo()
                                      game = found
                                  }
                              })
                    .id("\(model.routeStamp)-\(attempt)")
                    .ignoresSafeArea(.container, edges: .bottom)
            } else {
                ProblemView(words: "The server sent an address that can't be used.", back: { model.wittyPlay = nil })
            }
        }
        .fullScreenCover(isPresented: Binding(get: { game != nil }, set: { if !$0 { game = nil } })) {
            if let game {
                GamePlayerView(gameId: game.id, start: game.start) { self.game = nil }
                    .environmentObject(model)
                    .environmentObject(listening)
                    .environment(\.palette, palette)
                    .environment(\.client, client)
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .accessibilityIdentifier("wittyplay")
    }
}
#endif
