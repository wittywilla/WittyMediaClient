// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Colour tokens a page or a node overrides, on top of the theme in use: the server's docs/SDUI.md, "Theme
/// scopes". A page never holds a colour of its own; a scope's overrides are theme tokens with colour values,
/// and anything else in them is ignored.
public enum SDUITheme {
    /// The theme with these tokens' colours in place of its own, for a node and everything in it. Tokens are
    /// named as the theme engine names them (`bg2`, `accentFg`) or as its stylesheets do (`bg-2`, `accent-fg`).
    public static func apply(_ tokens: [String: String]?, to theme: AppTheme) -> AppTheme {
        guard let tokens, !tokens.isEmpty else { return theme }
        var given: [String: ThemeColour] = [:]
        for (name, value) in tokens {
            guard let colour = ThemeColour(hex: value) else { continue }
            given[name.replacingOccurrences(of: "-", with: "").lowercased()] = colour
        }
        guard !given.isEmpty else { return theme }
        var out = theme
        if let c = given["bg"] { out.background = c }
        if let c = given["bg2"] { out.panel = c }
        if let c = given["bg3"] { out.card = c }
        if let c = given["bg4"] { out.raised = c }
        if let c = given["fg"] { out.text = c }
        if let c = given["fg2"] { out.textSecondary = c }
        if let c = given["fg3"] { out.textHint = c }
        if let c = given["border"] { out.border = c }
        if let c = given["controlline"] { out.control = c }
        if let c = given["danger"] { out.danger = c }
        if let c = given["ok"] { out.ok = c }
        if let c = given["warn"] { out.warn = c }
        if let c = given["scrim"] ?? given["overlay"] { out.scrim = c }
        if let c = given["focus"] { out.focus = c; out.tvRing = c }
        if let accent = given["accent"] {
            // An accent of a scope's own brings what follows from it, as a theme's does, unless the scope says otherwise.
            out.accent = accent
            out.accentPressed = accent.mixed(with: .black, 0.10)
            out.accentText = accent
            out.onAccent = ThemeColour.white.contrast(with: accent) >= ThemeColour.ink.contrast(with: accent) ? .white : .ink
        }
        if let c = given["accenthover"] ?? given["accent2"] { out.accentPressed = c }
        if let c = given["accentfg"] { out.onAccent = c }
        if let c = given["accenttext"] { out.accentText = c }
        // A background of a scope's own decides light or dark for what's drawn on it.
        if given["bg"] != nil { out.isLight = out.background.luminance > 0.4 }
        return out
    }

    /// The colour of text over a picture: the scope's `onImage` when it has one, else white.
    public static func onImage(_ tokens: [String: String]?) -> ThemeColour {
        tokens?["onImage"].flatMap(ThemeColour.init(hex:)) ?? tokens?["on-image"].flatMap(ThemeColour.init(hex:)) ?? .white
    }
}

public extension Shelf {
    /// The Top Shelf's file from the server's own Top Shelf document: its sections and items, each with the link
    /// that shows it and the one that plays it, wrapped in the app's scheme. `pictures` are the files to fetch.
    static func from(topShelf: SDUITopShelf) -> (shelf: Shelf, pictures: [(name: String, url: String)]) {
        var pictures: [(name: String, url: String)] = []
        var seen = Set<String>()
        let sections = (topShelf.sections ?? []).prefix(maxSections).compactMap { section -> ShelfSection? in
            let entries = (section.items ?? []).prefix(10).compactMap { item -> ShelfEntry? in
                guard let route = item.displayRoute, DeepLink.isOpenable(route), let title = item.title, !title.isEmpty,
                      seen.insert(item.id).inserted else { return nil }
                var poster: String?
                if let url = item.image?.url, url.hasPrefix("/api/") {
                    let name = "t\(pictureNumber(url)).jpg"
                    poster = name
                    pictures.append((name, url))
                }
                let play = item.playRoute.flatMap { DeepLink.isOpenable($0) ? DeepLink.route($0).address : nil }
                return ShelfEntry(id: String(item.id.prefix(64)), title: PlainWords.clean(title, limit: 120), subtitle: "", poster: poster,
                                  link: DeepLink.route(route).address, shape: item.shape, play: play, progress: item.progress)
            }
            return entries.isEmpty ? nil : ShelfSection(title: PlainWords.clean(section.title ?? "", limit: 60), entries: entries)
        }
        return (Shelf(sections: Array(sections)), pictures)
    }

    /// A number that stands for a picture's address in its file name: the same picture keeps its file.
    static func pictureNumber(_ url: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in url.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }
}
