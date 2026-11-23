// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The settings menu every client draws (the server's pkg/sdui/data/settingsmenu.json, in its catalogue as
// `settingsMenu`; a copy in shared/data for a server that doesn't send it yet): the Android phone app's You page,
// its groups, rows, order and words, so iPhone, iPad and Apple TV show the same list as Android, the web and its
// TV mode. These are its rules with nothing from SwiftUI, so they can be tested.

public struct SettingsMenu: Codable, Equatable, Sendable {
    public var conditions: [String]
    public var values: [String]
    public var groups: [Group]

    public struct Icon: Codable, Equatable, Sendable {
        public var android: String
        public var apple: String
        public var web: String
    }

    public struct Row: Codable, Equatable, Sendable {
        public var id: String
        public var key: String
        public var title: String
        public var icon: Icon
        public var tint: String
        public var native: String?
        public var path: String?
        public var sdui: Bool?
        public var part: String?
        public var when: [String]?
        public var value: String?
        public var summary: String?
    }

    public struct Group: Codable, Equatable, Sendable {
        public var id: String
        public var key: String
        public var title: String
        public var rows: [Row]
    }

    /// Whether a row's condition holds: `facts` are the conditions true here, `off` what this profile's limits turn
    /// off. A condition this app doesn't know keeps the row out rather than lead nowhere.
    public static func holds(_ cond: String, facts: Set<String>, off: Set<String>) -> Bool {
        if cond.hasPrefix("notOff:") { return !off.contains(String(cond.dropFirst(7))) }
        if cond == "notTv" { return !facts.contains("tv") }
        return facts.contains(cond)
    }

    /// The groups this person sees, in the menu's order; a group left with no rows is left out.
    public func visible(facts: Set<String>, off: Set<String> = [], opens: (Row) -> Bool = { _ in true }) -> [Group] {
        groups.compactMap { g in
            var g = g
            g.rows = g.rows.filter { r in (r.when ?? []).allSatisfy { Self.holds($0, facts: facts, off: off) } && opens(r) }
            return g.rows.isEmpty ? nil : g
        }
    }

    /// What a TV may do with a row: its part's level, else its page's. With no table every server page is the card.
    public static func level(of row: Row, in table: TvLevelTable?) -> String {
        if let part = row.part, !part.isEmpty { return table?.partLevel(part) ?? TvLevel.desktopOnly }
        guard let path = row.path, !path.isEmpty else { return TvLevel.full }
        guard let table else { return TvLevel.desktopOnly }
        let page = String(path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        return table.screen(for: page)?.level ?? TvLevel.full
    }

    /// The TV summary a row shows where a TV can't change it: its own, else its page's.
    public static func summary(of row: Row, in table: TvLevelTable?) -> String {
        if let s = row.summary, !s.isEmpty { return s }
        guard let path = row.path, !path.isEmpty else { return "" }
        let page = String(path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        return table?.screen(for: page)?.summary ?? ""
    }

    /// The menu as this app was built with it, from shared/data.
    public static func bundled(_ data: Data?) -> SettingsMenu? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(SettingsMenu.self, from: data)
    }
}
