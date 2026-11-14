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

    /// The server page a WittyPlay address is, drawn natively (Apple TV, which has no web pages): `/page/x?tab=y` is page
    /// `x` with `tab=y`; WittyPlay's website views are its pages for the apps: a library's (`/wittyplay/library/3` is
    /// `wittyplay-library` with `library=3`), Settings, and Cores & emulators. Anything else is WittyPlay Online's home.
    public static func page(for address: String) -> (page: String, params: [String: String]) {
        let parts = address.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        var params: [String: String] = [:]
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
        }
        let path = parts[0]
        if path.hasPrefix("/page/"), isPlayPath(path) { return (String(path.dropFirst("/page/".count)), params) }
        if path.hasPrefix("/wittyplay/library/"), let id = Int64(path.dropFirst("/wittyplay/library/".count)) {
            params["library"] = String(id)
            return ("wittyplay-library", params)
        }
        if path == "/wittyplay/settings/store" || path.hasPrefix("/wittyplay/settings/store/") { return ("wittyplay-store", params) }
        if path == "/wittyplay/settings" || path.hasPrefix("/wittyplay/settings/") { return ("wittyplay-settings", params) }
        return ("wittyplay-online", [:])
    }

    /// One games library, as WittyPlay draws it, with the website's query (a tab): `/wittyplay/library/3?tab=consoles`.
    public static func library(_ id: Int64, query: [String: String]) -> String {
        let rest = query.filter { $0.key != "library" }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
        return library(id) + (rest.isEmpty ? "" : "?" + rest.joined(separator: "&"))
    }

    /// WittyPlay is on this server: its menu entry is in the server's navigation.
    public static func installed(routes: [String]) -> Bool { routes.contains { isPlayPath($0) } }
}

public extension SDUINavItem {
    /// Where the entry goes on the website: its route, else its page's address.
    var address: String { route ?? page.map { "/page/" + $0 } ?? "" }
}
