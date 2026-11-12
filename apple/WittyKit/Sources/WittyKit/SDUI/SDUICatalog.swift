// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// How a card style is drawn: what it shows of what a card carries, in reading order (which is also the order
/// of its accessibility label), and how many lines its title and subtitle may take.
public struct SDUICardStyle: Codable, Equatable, Sendable {
    public var style: String
    public var shape: String?
    public var aspect: String?
    public var shows: [String]?
    public var titleLines: Int?
    public var subtitleLines: Int?
    /// Which theme tokens draw it: colours, text roles and corners (the server's docs/THEMES.md, SDUI tokens).
    public var tokens: SDUIStyleTokens?

    public init(_ style: String, shape: String, aspect: String, shows: [String], titleLines: Int, subtitleLines: Int) {
        self.style = style
        self.shape = shape
        self.aspect = aspect
        self.shows = shows
        self.titleLines = titleLines
        self.subtitleLines = subtitleLines
    }

    /// What a style this app doesn't know is drawn as: its shape, with the title and subtitle under the picture.
    public static let unknown = SDUICardStyle("", shape: "", aspect: "", shows: ["title", "subtitle"], titleLines: 1, subtitleLines: 1)
}

/// One row of the catalogue's routes table: which page, or which of the app's own screens, shows a place in the app.
public struct SDUIRouteRule: Codable, Equatable, Sendable {
    public var pattern: String
    public var page: String?
    public var native: String?
    /// `{name}` is a part of the route, `?name` a query parameter, anything else is itself.
    public var params: [String: String]?

    public init(_ pattern: String, page: String? = nil, native: String? = nil, params: [String: String]? = nil) {
        self.pattern = pattern
        self.page = page
        self.native = native
        self.params = params
    }
}

/// One of the catalogue's commands: a request the app makes for the profile, then asks for the page again.
public struct SDUICommand: Codable, Equatable, Sendable {
    public var op: String
    public var label: String?
    public var method: String?
    /// With `{item}` where the item's ID goes.
    public var path: String?
    public var body: String?

    public init(_ op: String, method: String? = nil, path: String? = nil, body: String? = nil) {
        self.op = op
        self.method = method
        self.path = path
        self.body = body
    }
}

/// The parts of `GET /sdui/catalog` an app that draws pages needs. Everything else in it is for editors.
public struct SDUICatalog: Codable, Equatable, Sendable {
    public var revision: Int?
    public var cardStyles: [SDUICardStyle]
    public var routes: [SDUIRouteRule]
    public var commands: [SDUICommand]
    public var icons: [String]?
    /// Each component's theme tokens, by its type.
    public var componentTokens: [String: SDUIStyleTokens] = [:]
    /// Each text role's typeface and weight, by name in the resolved theme's `type`.
    public var typeRoles: [String: SDUITypeRole] = [:]

    enum CodingKeys: String, CodingKey { case revision, cardStyles, routes, commands, icons, components, theme }

    private struct Component: Codable { let type: String; let tokens: SDUIStyleTokens? }
    private struct ThemeVocabulary: Codable { let typeRoles: [String: SDUITypeRole]? }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encodeIfPresent(revision, forKey: .revision)
        try box.encode(cardStyles, forKey: .cardStyles)
        try box.encode(routes, forKey: .routes)
        try box.encode(commands, forKey: .commands)
        try box.encodeIfPresent(icons, forKey: .icons)
        try box.encode(componentTokens.map { Component(type: $0.key, tokens: $0.value) }.sorted { $0.type < $1.type }, forKey: .components)
        try box.encode(ThemeVocabulary(typeRoles: typeRoles), forKey: .theme)
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        revision = try? box.decodeIfPresent(Int.self, forKey: .revision)
        let styles = ((try? box.decodeIfPresent([Loose<SDUICardStyle>].self, forKey: .cardStyles)) ?? []).compactMap(\.value)
        let rules = ((try? box.decodeIfPresent([Loose<SDUIRouteRule>].self, forKey: .routes)) ?? []).compactMap(\.value)
        let ops = ((try? box.decodeIfPresent([Loose<SDUICommand>].self, forKey: .commands)) ?? []).compactMap(\.value)
        // A catalogue without a table keeps the one this app was built with.
        cardStyles = styles.isEmpty ? SDUICatalog.builtIn.cardStyles : styles
        routes = rules.isEmpty ? SDUICatalog.builtIn.routes : rules
        commands = ops.isEmpty ? SDUICatalog.builtIn.commands : ops
        icons = try? box.decodeIfPresent([String].self, forKey: .icons)
        let parts = ((try? box.decodeIfPresent([Loose<Component>].self, forKey: .components)) ?? []).compactMap(\.value)
        componentTokens = Dictionary(parts.compactMap { part in part.tokens.map { (part.type, $0) } }, uniquingKeysWith: { first, _ in first })
        typeRoles = (try? box.decodeIfPresent(ThemeVocabulary.self, forKey: .theme))?.typeRoles ?? [:]
    }

    public init(cardStyles: [SDUICardStyle], routes: [SDUIRouteRule], commands: [SDUICommand]) {
        revision = SDUI.catalog
        self.cardStyles = cardStyles
        self.routes = routes
        self.commands = commands
    }

    public func cardStyle(_ name: String) -> SDUICardStyle? { cardStyles.first { $0.style == name } }
    public func command(_ op: String) -> SDUICommand? { commands.first { $0.op == op } }

    /// Catalogue revision 2 as this app was built against it: what's used until the server's own has been
    /// read, and when it can't be. The same tables as the server's docs/SDUI.md, "Card styles", "Routes", "Commands".
    public static let builtIn = SDUICatalog(
        cardStyles: [
            SDUICardStyle("poster", shape: "poster", aspect: "2/3", shows: ["title", "subtitle", "progress", "watched", "unwatched", "badges"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("landscape", shape: "landscape", aspect: "16/9", shows: ["title", "subtitle", "badges"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("progress", shape: "landscape", aspect: "16/9", shows: ["title", "subtitle", "progress", "remaining"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("episode", shape: "landscape", aspect: "16/9", shows: ["title", "subtitle", "synopsis", "progress", "watched"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("square", shape: "square", aspect: "1/1", shows: ["title", "subtitle"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("album", shape: "square", aspect: "1/1", shows: ["title", "subtitle"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("circle", shape: "circle", aspect: "1/1", shows: ["title"], titleLines: 2, subtitleLines: 0),
            SDUICardStyle("person", shape: "circle", aspect: "1/1", shows: ["title", "subtitle"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("book", shape: "poster", aspect: "2/3", shows: ["title", "subtitle", "progress"], titleLines: 2, subtitleLines: 1),
            SDUICardStyle("person", shape: "circle", aspect: "1/1", shows: ["title", "subtitle"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("game", shape: "poster", aspect: "3/4", shows: ["title", "subtitle", "badges"], titleLines: 1, subtitleLines: 1),
            SDUICardStyle("photo", shape: "square", aspect: "1/1", shows: [], titleLines: 0, subtitleLines: 0),
            SDUICardStyle("channel", shape: "landscape", aspect: "16/9", shows: ["number", "title", "now", "next", "progress"], titleLines: 1, subtitleLines: 2),
            SDUICardStyle("tile", shape: "landscape", aspect: "16/9", shows: ["title", "count"], titleLines: 1, subtitleLines: 0),
            SDUICardStyle("plate", shape: "poster", aspect: "2/3", shows: ["title", "subtitle", "badges"], titleLines: 2, subtitleLines: 1),
            SDUICardStyle("block", shape: "landscape", aspect: "16/9", shows: ["title", "subtitle"], titleLines: 2, subtitleLines: 1),
            SDUICardStyle("logo", shape: "landscape", aspect: "16/9", shows: ["number", "title"], titleLines: 1, subtitleLines: 0),
            SDUICardStyle("chip", shape: "chip", aspect: "", shows: ["title"], titleLines: 1, subtitleLines: 0),
        ],
        routes: [
            SDUIRouteRule("/", page: "home"),
            SDUIRouteRule("/libraries", page: "libraries"),
            SDUIRouteRule("/library/{library}", page: "library", params: ["library": "{library}"]),
            SDUIRouteRule("/item/{item}", page: "detail", params: ["item": "{item}"]),
            SDUIRouteRule("/person/{person}", page: "detail", params: ["person": "{person}"]),
            SDUIRouteRule("/show/{show}", page: "detail", params: ["show": "{show}"]),
            SDUIRouteRule("/album/{library}", page: "detail", params: ["album": "?album", "artist": "?artist", "library": "{library}"]),
            SDUIRouteRule("/collections/{collection}", page: "detail", params: ["collection": "{collection}"]),
            SDUIRouteRule("/collections", page: "collections"),
            SDUIRouteRule("/search", page: "search", params: ["q": "?q"]),
            SDUIRouteRule("/tv", page: "livetv"),
            SDUIRouteRule("/music", page: "music"),
            SDUIRouteRule("/photos", page: "photos"),
            SDUIRouteRule("/books", page: "books"),
            SDUIRouteRule("/games", page: "games"),
            SDUIRouteRule("/page/{id}", page: "{id}"),
            SDUIRouteRule("/settings", native: "settings"),
            SDUIRouteRule("/settings/{section}", native: "settings"),
            SDUIRouteRule("/tv/guide", native: "guide"),
            SDUIRouteRule("/tv/recordings", native: "guide"),
            SDUIRouteRule("/tv/watch/{key}", native: "livePlayer"),
            SDUIRouteRule("/watch/{item}", native: "player"),
            SDUIRouteRule("/play/{item}", native: "player"),
            SDUIRouteRule("/read/{item}", native: "reader"),
            SDUIRouteRule("/game/{item}", native: "game"),
            SDUIRouteRule("/you", native: "profiles"),
            SDUIRouteRule("/pair", native: "pair"),
        ],
        commands: [
            SDUICommand("watchLater.add", method: "POST", path: "/api/v1/collections/watch-later/items", body: "{\"items\":[{item}]}"),
            SDUICommand("watched.set", method: "POST", path: "/api/v1/items/{item}/progress", body: "{\"watched\":true}"),
            SDUICommand("watched.clear", method: "DELETE", path: "/api/v1/items/{item}/progress"),
            SDUICommand("selectTab"),
            SDUICommand("refresh"),
        ])
}

/// A component's or card style's theme tokens: each coloured part's colour token, each text's role, each rounded
/// part's shape token.
public struct SDUIStyleTokens: Codable, Equatable, Sendable {
    public var colors: [String: String]?
    public var type: [String: String]?
    public var shape: [String: String]?

    public init(colors: [String: String]? = nil, type: [String: String]? = nil, shape: [String: String]? = nil) {
        self.colors = colors
        self.type = type
        self.shape = shape
    }
}

/// A text role's typeface (`display`, `body` or `mono`) and weight (`body`, `medium`, `strong`, `heading`).
public struct SDUITypeRole: Codable, Equatable, Sendable {
    public var family: String
    public var weight: String

    public init(family: String, weight: String) {
        self.family = family
        self.weight = weight
    }
}
