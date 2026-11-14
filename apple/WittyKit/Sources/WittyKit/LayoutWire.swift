// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The wireframe of a look (Design 2, the canvas's wire thumbnails): where the menu is and how it is drawn, how Home starts,
// what the cards are, where the server's name sits and the finish, so a person choosing a look sees its LAYOUT and not only
// its colours. It is the server's own `wire` of each experience in `GET /sdui/experiences` (docs/SDUI.md, Experiences:
// "wire: the layout a chooser draws"), a map from form factor to `{nav, open, style, home, cards, dock, brand, finish}`:
// nothing here knows a look by its name, so a look the server adds draws itself. The app draws it with `LayoutThumb`, in the
// previewed theme's colours.

public struct LayoutWire: Codable, Equatable, Sendable {
    /// `top`, `side`, `rail`, `bottom` or `none` (a crossbar: the categories are part of the page).
    public var nav: String
    /// The menu is open all the time (a sidebar).
    public var open: Bool
    /// `pill`, `gloss`, `cable`, `bevel`, `tele`, `crossbar` or `under`.
    public var style: String
    /// `hero`, `banner`, `carousel`, `cross`, `tiles`, `widgets` or `list`.
    public var home: String
    /// `poster`, `landscape`, `plate`, `block` or `logo`.
    public var cards: String
    /// A dock of keys: on a television and in a headset.
    public var dock: Bool
    /// `left` of a top bar, `top` of a side menu, rail or tab bar, `centre` for a crossbar.
    public var brand: String
    /// `flat`, `gloss`, `bevel`, `glass` or `crt`.
    public var finish: String

    public init(nav: String = "top", open: Bool = false, style: String = "pill", home: String = "hero", cards: String = "poster",
                dock: Bool = false, brand: String = "left", finish: String = "flat") {
        self.nav = nav
        self.open = open
        self.style = style
        self.home = home
        self.cards = cards
        self.dock = dock
        self.brand = brand
        self.finish = finish
    }

    enum CodingKeys: String, CodingKey { case nav, open, style, home, cards, dock, brand, finish }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys, _ d: String) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? d }
        nav = s(.nav, "top")
        open = (try? c.decodeIfPresent(Bool.self, forKey: .open)) ?? false
        style = s(.style, "pill")
        home = s(.home, "hero")
        cards = s(.cards, "poster")
        dock = (try? c.decodeIfPresent(Bool.self, forKey: .dock)) ?? false
        brand = s(.brand, "left")
        finish = s(.finish, "flat")
    }

    /// The wireframe to draw for a look on this device's form factor (`phone`, `tablet`, `tv` or `desktop`): the server works
    /// one out for each. A server that sends no `wire` gets the default.
    public static func of(_ look: ExperienceCatalogue.Info, form: String) -> LayoutWire {
        look.wire[form] ?? look.wire["web"] ?? LayoutWire()
    }
}
