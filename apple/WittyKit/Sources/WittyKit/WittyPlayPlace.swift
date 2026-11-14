// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Where WittyPlay lives on the server's website, as its own frame knows it (WittyMediaServer web/src/shell/playPaths.ts).
/// With WittyPlay installed, the owner's choice for every app: games open WittyPlay, which takes the whole screen in its
/// own frame (a status bar, a round dock, Return To Server), as the website and the desktop app do.
public enum WittyPlayPlace {
    /// WittyPlay Online's home: where Games goes.
    public static let home = "/page/wittyplay-online"
    /// Return To Server: the website's address for leaving WittyPlay.
    public static let exit = "/"

    /// One games library, as WittyPlay draws it.
    public static func library(_ id: Int64) -> String { "/wittyplay/library/\(id)" }

    /// The address is one of WittyPlay's: its pages, its settings and its own views of the games libraries.
    public static func isPlayPath(_ path: String) -> Bool {
        let bare = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        return bare == home || bare == "/page/wittyplay" || bare.hasPrefix("/page/wittyplay-") || bare == "/design/play"
            || bare == "/wittyplay" || bare.hasPrefix("/wittyplay/")
    }

    /// A server page (an SDUI page's id) that is WittyPlay's.
    public static func isPlayPage(_ page: String) -> Bool { page == "wittyplay" || page.hasPrefix("wittyplay-") }

    /// WittyPlay is on this server: its menu entry is in the server's navigation.
    public static func installed(routes: [String]) -> Bool { routes.contains { isPlayPath($0) } }
}

public extension SDUINavItem {
    /// Where the entry goes on the website: its route, else its page's address.
    var address: String { route ?? page.map { "/page/" + $0 } ?? "" }
}
