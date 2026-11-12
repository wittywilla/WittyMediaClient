// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The finished look an app draws (the server's docs/THEMES.md, `look` in `GET /theme`): the experience's effects (glass,
// gloss, glow, texture and bevel, each none, subtle or full), its corners, type set and motion, and the theme's own
// finish recipes and background scene. It is data. Nothing here knows an experience by its id; every part is drawn from
// the values (docs/plans/DESIGN-2.md sections 7.1 and 7.7).

extension ThemeColour {
    /// A CSS colour as the server's theme files write it: `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb(r,g,b)` or `rgba(r,g,b,a)`.
    public init?(css text: String) {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            guard let c = ThemeColour(hex: value) else { return nil }
            self = c
            return
        }
        guard value.hasPrefix("rgb"), let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), open < close else { return nil }
        let numbers = value[value.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        guard numbers.count == 3 || numbers.count == 4 else { return nil }
        let alpha = numbers.count == 4 ? max(0, min(1, numbers[3])) : 1
        self.init(red: max(0, min(1, numbers[0] / 255)), green: max(0, min(1, numbers[1] / 255)), blue: max(0, min(1, numbers[2] / 255)), alpha: alpha)
    }
}

/// How much of an effect is drawn.
public enum EffectLevel: String, Decodable, Equatable, Comparable, Sendable {
    case none, subtle, full

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "none"
        self = EffectLevel(rawValue: raw) ?? .none
    }

    private var rank: Int { self == .none ? 0 : self == .subtle ? 1 : 2 }
    public static func < (a: EffectLevel, b: EffectLevel) -> Bool { a.rank < b.rank }

    /// 0, a half or 1: what to multiply an effect's strength by.
    public var amount: Double { self == .none ? 0 : self == .subtle ? 0.5 : 1 }
    public var on: Bool { self != .none }

    /// One step lower: full to subtle, subtle to none.
    public var lowered: EffectLevel { self == .full ? .subtle : .none }
}

/// The experience's effects.
public struct LookEffects: Decodable, Equatable, Sendable {
    public var glass = EffectLevel.none
    public var gloss = EffectLevel.none
    public var glow = EffectLevel.none
    public var texture = EffectLevel.none
    public var bevel = EffectLevel.none

    public init(glass: EffectLevel = .none, gloss: EffectLevel = .none, glow: EffectLevel = .none, texture: EffectLevel = .none, bevel: EffectLevel = .none) {
        self.glass = glass
        self.gloss = gloss
        self.glow = glow
        self.texture = texture
        self.bevel = bevel
    }

    enum CodingKeys: String, CodingKey { case glass, gloss, glow, texture, bevel }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        glass = (try? box.decodeIfPresent(EffectLevel.self, forKey: .glass)) ?? .none
        gloss = (try? box.decodeIfPresent(EffectLevel.self, forKey: .gloss)) ?? .none
        glow = (try? box.decodeIfPresent(EffectLevel.self, forKey: .glow)) ?? .none
        texture = (try? box.decodeIfPresent(EffectLevel.self, forKey: .texture)) ?? .none
        bevel = (try? box.decodeIfPresent(EffectLevel.self, forKey: .bevel)) ?? .none
    }

    /// Every level one step lower, for a modest device or when the person asks for less transparency.
    public var lowered: LookEffects {
        LookEffects(glass: glass.lowered, gloss: gloss.lowered, glow: glow.lowered, texture: texture.lowered, bevel: bevel.lowered)
    }

    public var any: Bool { glass.on || gloss.on || glow.on || texture.on || bevel.on }
}

/// One layer of the theme's scene, drawn bottom to top, positions in percent of the window.
public struct SceneLayer: Decodable, Equatable, Sendable {
    public struct Stop: Decodable, Equatable, Sendable {
        public var at: Double
        public var color: String
        public init(at: Double, color: String) {
            self.at = at
            self.color = color
        }
    }

    /// gradient, radial, shape or image.
    public var type: String
    /// For a shape: circle or hill.
    public var kind: String?
    public var angle: Double?
    public var stops: [Stop]
    public var x, y, w, h, size, fade: Double?
    public var color: String?

    public init(type: String, kind: String? = nil, angle: Double? = nil, stops: [Stop] = [], x: Double? = nil, y: Double? = nil,
                w: Double? = nil, h: Double? = nil, size: Double? = nil, fade: Double? = nil, color: String? = nil) {
        self.type = type
        self.kind = kind
        self.angle = angle
        self.stops = stops
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.size = size
        self.fade = fade
        self.color = color
    }

    enum CodingKeys: String, CodingKey { case type, kind, angle, stops, x, y, w, h, size, fade, color }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? box.decode(String.self, forKey: .type)) ?? ""
        kind = try? box.decodeIfPresent(String.self, forKey: .kind)
        angle = try? box.decodeIfPresent(Double.self, forKey: .angle)
        stops = (try? box.decodeIfPresent([Stop].self, forKey: .stops)) ?? []
        x = try? box.decodeIfPresent(Double.self, forKey: .x)
        y = try? box.decodeIfPresent(Double.self, forKey: .y)
        w = try? box.decodeIfPresent(Double.self, forKey: .w)
        h = try? box.decodeIfPresent(Double.self, forKey: .h)
        size = try? box.decodeIfPresent(Double.self, forKey: .size)
        fade = try? box.decodeIfPresent(Double.self, forKey: .fade)
        color = try? box.decodeIfPresent(String.self, forKey: .color)
    }
}

/// The theme's glass and gloss recipes: a top and a bottom fill, an edge and a shadow for glass; five stops for a glossy
/// button (highlight, upper body, lower body, glow, edge).
public struct LookFinish: Decodable, Equatable, Sendable {
    public struct Glass: Decodable, Equatable, Sendable {
        public var hi, lo, edge, shadow: String
    }
    public var glass: Glass?
    public var gloss: [String]

    public init(glass: Glass? = nil, gloss: [String] = []) {
        self.glass = glass
        self.gloss = gloss
    }

    enum CodingKeys: String, CodingKey { case glass, gloss }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        glass = try? box.decodeIfPresent(Glass.self, forKey: .glass)
        gloss = (try? box.decodeIfPresent([String].self, forKey: .gloss)) ?? []
    }
}

/// The type sets of an experience.
public enum TypeSetID: String, Equatable, Sendable, CaseIterable {
    case system, humanist, rounded, mono, serif
}

/// `look` in `GET /theme`.
public struct ExperienceLook: Decodable, Equatable, Sendable {
    public var experience: String
    public var theme: String
    public var effects: LookEffects
    /// The corner multiple: the theme's radius times this (0 is square).
    public var radiusMultiple: Double
    public var cardSet: String
    public var type: TypeSetID
    public var density: String
    public var focusStyle: String
    public var overshoot: Bool
    public var finish: LookFinish
    public var scene: [SceneLayer]

    public static let plain = ExperienceLook(experience: "", theme: "", effects: LookEffects(), radiusMultiple: 1, cardSet: "poster", type: .system,
                                             density: "comfortable", focusStyle: "ring", overshoot: false, finish: LookFinish(), scene: [])

    public init(experience: String, theme: String, effects: LookEffects, radiusMultiple: Double, cardSet: String, type: TypeSetID, density: String,
                focusStyle: String, overshoot: Bool, finish: LookFinish, scene: [SceneLayer]) {
        self.experience = experience
        self.theme = theme
        self.effects = effects
        self.radiusMultiple = radiusMultiple
        self.cardSet = cardSet
        self.type = type
        self.density = density
        self.focusStyle = focusStyle
        self.overshoot = overshoot
        self.finish = finish
        self.scene = scene
    }

    private struct Shape: Decodable { var radiusMultiple: Double?; var cardSet: String? }
    private struct Motion: Decodable { var focus: String?; var overshoot: Bool? }
    private struct Scene: Decodable { var layers: [SceneLayer]? }

    enum CodingKeys: String, CodingKey { case experience, theme, effects, shape, type, density, motion, finish, scene }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        experience = (try? box.decodeIfPresent(String.self, forKey: .experience)) ?? ""
        theme = (try? box.decodeIfPresent(String.self, forKey: .theme)) ?? ""
        effects = (try? box.decodeIfPresent(LookEffects.self, forKey: .effects)) ?? LookEffects()
        let shape = try? box.decodeIfPresent(Shape.self, forKey: .shape)
        radiusMultiple = max(0, min(4, shape?.radiusMultiple ?? 1))
        cardSet = shape?.cardSet ?? "poster"
        type = (try? box.decodeIfPresent(String.self, forKey: .type)).flatMap { TypeSetID(rawValue: $0) } ?? .system
        density = (try? box.decodeIfPresent(String.self, forKey: .density)) ?? "comfortable"
        let motion = try? box.decodeIfPresent(Motion.self, forKey: .motion)
        focusStyle = motion?.focus ?? "ring"
        overshoot = motion?.overshoot ?? false
        finish = (try? box.decodeIfPresent(LookFinish.self, forKey: .finish)) ?? LookFinish()
        scene = ((try? box.decodeIfPresent(Scene.self, forKey: .scene))?.layers) ?? []
    }

    /// The look for a modest device, or a person who asked for less transparency or motion: with `modest` (a slow device, low power,
    /// Reduce Transparency) every effect a step lower; with `modest` or `calm` (Reduce Motion) only the scene's first layer and no
    /// overshoot ("On modest hardware and with reduced transparency or motion a renderer draws only the first layer", the server's
    /// docs/THEMES.md).
    public func adjusted(modest: Bool, calm: Bool = false) -> ExperienceLook {
        guard modest || calm else { return self }
        var out = self
        if modest { out.effects = effects.lowered }
        out.scene = Array(scene.prefix(1))
        out.overshoot = false
        return out
    }
}

extension LookFinish {
    /// The five stops of a glossy button (highlight, upper body, lower body, glow, edge) as colours, with the two bodies moved
    /// towards the accent until `ink` (the words on it) reads on both at 4.5 to 1: the theme's sky-blue gloss would otherwise
    /// put white words on a light blue. A theme with no gloss recipe gets one worked out from the accent.
    public func glossStops(accent: ThemeColour, ink: ThemeColour) -> [ThemeColour] {
        var stops = gloss.compactMap { ThemeColour(css: $0) }
        if stops.count < 5 {
            stops = [accent.mixed(with: .white, 0.5), accent, accent.mixed(with: .black, 0.15), accent.mixed(with: .white, 0.2), accent.mixed(with: .black, 0.3)]
        }
        for index in [1, 2] {
            var amount = 0.0
            while stops[index].mixed(with: accent, amount).contrast(with: ink) < 4.5, amount < 1 { amount += 0.1 }
            stops[index] = stops[index].mixed(with: accent, min(1, amount))
        }
        // The accent itself has to carry the words; if it cannot, the bodies go to the darker of the accent and the ink's opposite.
        return stops
    }

    /// The glass recipe's colours, worked out from the page when the theme has none: a light pane on a dark page and a white one
    /// on a light page.
    public func glassColours(light: Bool) -> (hi: ThemeColour, lo: ThemeColour, edge: ThemeColour, shadow: ThemeColour) {
        if let g = glass, let hi = ThemeColour(css: g.hi), let lo = ThemeColour(css: g.lo), let edge = ThemeColour(css: g.edge), let shadow = ThemeColour(css: g.shadow) {
            return (hi, lo, edge, shadow)
        }
        return light
            ? (ThemeColour.white.opacity(0.9), ThemeColour.white.opacity(0.5), .white, ThemeColour(red: 0.08, green: 0.47, blue: 0.78, alpha: 0.25))
            : (ThemeColour.white.opacity(0.22), ThemeColour.white.opacity(0.08), ThemeColour.white.opacity(0.38), ThemeColour.black.opacity(0.4))
    }
}
