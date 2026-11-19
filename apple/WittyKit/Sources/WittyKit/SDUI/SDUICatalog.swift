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
    /// The values beyond the item a command takes (`name`, `type` of `string` or `int`, `required`): the action's own
    /// `params` give them by name, and each goes in place of `{name}` in the path and the body.
    public var params: [Param]?

    public struct Param: Codable, Equatable, Sendable {
        public var name: String
        public var type: String
        public var required: Bool

        public init(_ name: String, type: String = "string", required: Bool = false) {
            self.name = name
            self.type = type
            self.required = required
        }

        enum CodingKeys: String, CodingKey { case name, type, required }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "string"
            required = (try? c.decodeIfPresent(Bool.self, forKey: .required)) ?? false
        }
    }

    public init(_ op: String, method: String? = nil, path: String? = nil, body: String? = nil, params: [Param]? = nil) {
        self.op = op
        self.method = method
        self.path = path
        self.body = body
        self.params = params
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
    /// How much of each screen a TV offers (WittyMediaServer 0.8.1, TvLevels.swift). Nil from an older server.
    public var tvLevels: TvLevelTable?

    enum CodingKeys: String, CodingKey { case revision, cardStyles, routes, commands, icons, components, theme, tvLevels }

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
        try box.encodeIfPresent(tvLevels, forKey: .tvLevels)
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        revision = try? box.decodeIfPresent(Int.self, forKey: .revision)
        let styles = ((try? box.decodeIfPresent([Loose<SDUICardStyle>].self, forKey: .cardStyles)) ?? []).compactMap(\.value)
        let rules = ((try? box.decodeIfPresent([Loose<SDUIRouteRule>].self, forKey: .routes)) ?? []).compactMap(\.value)
        let ops = ((try? box.decodeIfPresent([Loose<SDUICommand>].self, forKey: .commands)) ?? []).compactMap(\.value)
        // The server's tables as they are: a row this app can't read is left out.
        cardStyles = styles
        routes = rules
        commands = ops
        icons = try? box.decodeIfPresent([String].self, forKey: .icons)
        let parts = ((try? box.decodeIfPresent([Loose<Component>].self, forKey: .components)) ?? []).compactMap(\.value)
        componentTokens = Dictionary(parts.compactMap { part in part.tokens.map { (part.type, $0) } }, uniquingKeysWith: { first, _ in first })
        typeRoles = (try? box.decodeIfPresent(ThemeVocabulary.self, forKey: .theme))?.typeRoles ?? [:]
        tvLevels = try? box.decodeIfPresent(TvLevelTable.self, forKey: .tvLevels)
    }

    public init(cardStyles: [SDUICardStyle], routes: [SDUIRouteRule], commands: [SDUICommand]) {
        revision = SDUI.catalog
        self.cardStyles = cardStyles
        self.routes = routes
        self.commands = commands
    }

    public func cardStyle(_ name: String) -> SDUICardStyle? { cardStyles.first { $0.style == name } }
    public func command(_ op: String) -> SDUICommand? { commands.first { $0.op == op } }

    /// The server's own catalogue as this app was built against it: what's drawn with until the server's own has been
    /// read. It is WittyKit's bundled copy of what the server prints (Resources/sdui-catalog.json, written by
    /// apple/scripts/sync-sdui-catalog.sh), so its card styles, routes and commands are the server's, never a
    /// table kept by hand. A copy that is missing or can't be read is a broken build, and stops here, loudly.
    public static let builtIn: SDUICatalog = {
        guard let url = Bundle.module.url(forResource: "sdui-catalog", withExtension: "json"), let data = try? Data(contentsOf: url) else {
            fatalError("WittyKit has no bundled SDUI catalogue: run apple/scripts/sync-sdui-catalog.sh")
        }
        do {
            let catalog = try JSONDecoder().decode(SDUICatalog.self, from: data)
            precondition(!catalog.cardStyles.isEmpty && !catalog.routes.isEmpty && !catalog.commands.isEmpty,
                         "WittyKit's bundled SDUI catalogue has an empty table: run apple/scripts/sync-sdui-catalog.sh")
            return catalog
        } catch {
            fatalError("WittyKit's bundled SDUI catalogue can't be read (\(error)): run apple/scripts/sync-sdui-catalog.sh")
        }
    }()
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
