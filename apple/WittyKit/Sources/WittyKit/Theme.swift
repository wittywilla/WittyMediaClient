import Foundation

// Every theme the server has, in the apps: docs/APP-DESIGN.md, Themes. A theme comes as data, the CSS
// variables of the server's theme (`GET /themes/{id}/tokens.json`), and is translated here into the roles the
// apps draw with. Nothing here is platform-specific: the apps turn `ThemeColour` into their own colours.

/// One colour, red, green, blue and alpha from 0 to 1.
public struct ThemeColour: Equatable, Codable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`; anything else is nil, so a fallback is used.
    public init?(hex text: String) {
        var digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
        } else {
            self.init(red: Double((value >> 24) & 0xff) / 255, green: Double((value >> 16) & 0xff) / 255,
                      blue: Double((value >> 8) & 0xff) / 255, alpha: Double(value & 0xff) / 255)
        }
    }

    public var hex: String {
        let parts = [red, green, blue].map { String(format: "%02x", Int((max(0, min(1, $0)) * 255).rounded())) }.joined()
        return alpha >= 1 ? "#\(parts)" : "#\(parts)\(String(format: "%02x", Int((max(0, min(1, alpha)) * 255).rounded())))"
    }

    public var description: String { hex }

    /// This colour moved `amount` of the way towards another, alpha included.
    public func mixed(with other: ThemeColour, _ amount: Double) -> ThemeColour {
        ThemeColour(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount,
                    blue: blue + (other.blue - blue) * amount, alpha: alpha + (other.alpha - alpha) * amount)
    }

    public func opacity(_ value: Double) -> ThemeColour { ThemeColour(red: red, green: green, blue: blue, alpha: value) }

    /// Drawn over an opaque colour: what the eye sees.
    public func over(_ base: ThemeColour) -> ThemeColour {
        ThemeColour(red: red * alpha + base.red * (1 - alpha), green: green * alpha + base.green * (1 - alpha),
                    blue: blue * alpha + base.blue * (1 - alpha))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public func contrast(with other: ThemeColour) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public static let white = ThemeColour(red: 1, green: 1, blue: 1)
    public static let black = ThemeColour(red: 0, green: 0, blue: 0)
    static let ink = ThemeColour(hex: "#0e1013")!
}

/// What the apps draw with, translated from a theme.
public struct AppTheme: Equatable {
    public var id: String
    public var name: String
    public var isLight: Bool
    public var background, panel, card, raised, border, control: ThemeColour
    public var text, textSecondary, textHint: ThemeColour
    public var accent, accentPressed, onAccent, accentText: ThemeColour
    public var danger, ok, warn, scrim: ThemeColour
    /// The medium radius: buttons, fields, posters. See `radii`.
    public var radius: Double

    /// Small, medium, large and extra radii, from the theme's one.
    public var radii: (small: Double, medium: Double, large: Double, extra: Double) {
        (max(2, radius - 4), radius, radius + 4, radius + 10)
    }

    public static func == (a: AppTheme, b: AppTheme) -> Bool {
        a.id == b.id && a.name == b.name && a.isLight == b.isLight && a.background == b.background && a.panel == b.panel
            && a.card == b.card && a.raised == b.raised && a.border == b.border && a.control == b.control && a.text == b.text
            && a.textSecondary == b.textSecondary && a.textHint == b.textHint && a.accent == b.accent
            && a.accentPressed == b.accentPressed && a.onAccent == b.onAccent && a.accentText == b.accentText
            && a.danger == b.danger && a.ok == b.ok && a.warn == b.warn && a.scrim == b.scrim && a.radius == b.radius
    }
}

/// `GET /themes/{id}/tokens.json`.
public struct ThemeTokens: Codable, Equatable {
    public var id: String
    public var name: String?
    public var scheme: String?
    public var colors: [String: String]?
    public var lengths: [String: Double]?
    public var webOnly: Bool?

    public init(id: String, name: String? = nil, scheme: String? = nil, colors: [String: String]? = nil,
                lengths: [String: Double]? = nil, webOnly: Bool? = nil) {
        self.id = id
        self.name = name
        self.scheme = scheme
        self.colors = colors
        self.lengths = lengths
        self.webOnly = webOnly
    }

    enum CodingKeys: String, CodingKey { case id, name, scheme, colors, lengths, webOnly }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(scheme, forKey: .scheme)
        try c.encodeIfPresent(colors, forKey: .colors)
        try c.encodeIfPresent(lengths, forKey: .lengths)
        try c.encodeIfPresent(webOnly, forKey: .webOnly)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        scheme = try c.decodeIfPresent(String.self, forKey: .scheme)
        colors = try c.decodeIfPresent([String: String].self, forKey: .colors)
        // A length an uploaded theme wrote oddly is left out, not the whole theme.
        if let raw = try? c.decodeIfPresent([String: LooseNumber].self, forKey: .lengths) {
            lengths = raw.compactMapValues(\.value)
        } else {
            lengths = nil
        }
        webOnly = try c.decodeIfPresent(Bool.self, forKey: .webOnly)
    }
}

private struct LooseNumber: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = (try? c.decode(Double.self)) ?? (try? c.decode(String.self)).flatMap(Double.init)
    }
}

/// `GET /themes`: what's on offer, with four colours each to draw a swatch before its tokens are read.
public struct ThemeList: Decodable, Equatable {
    public var themes: [ThemeSummary]
    public var `default`: String?

    public struct ThemeSummary: Decodable, Equatable, Identifiable {
        public var id: String
        public var name: String?
        public var scheme: String?
        public var webOnly: Bool?
        public var builtin: Bool?
        public var modTime: Int64?
        public var preview: Preview?

        public struct Preview: Decodable, Equatable {
            public var bg, surface, text, accent: String?
        }

        public var shownName: String {
            let cleaned = PlainWords.clean(name ?? "", limit: 40)
            return cleaned.isEmpty ? id : cleaned
        }
    }
}

/// The person's own look from the theme maker, kept in their account under `customTheme` in `GET /me/ui`.
public struct ThemeMakerInput: Codable, Equatable {
    public var name: String
    public var scheme: String
    public var accent: String
    public var tint: String
    public var corners: String

    public init(name: String, scheme: String, accent: String, tint: String, corners: String) {
        self.name = name
        self.scheme = scheme
        self.accent = accent
        self.tint = tint
        self.corners = corners
    }
}

public enum ThemeTranslator {
    /// The default theme's colours: the last fallback for anything a theme lacks.
    public static let witty: [String: String] = [
        "bg": "#0f1115", "bg-2": "#171a21", "bg-3": "#1f232c", "bg-4": "#2a2f3a", "border": "#e8eaf01a",
        "control-line": "#e8eaf033", "fg": "#e8eaf0", "fg-2": "#a9afbd", "fg-3": "#848b99", "accent": "#7955ff",
        "accent-2": "#6a45f0", "accent-fg": "#ffffff", "accent-text": "#9174ff", "danger": "#ff5c6c", "ok": "#3ad29f",
        "warn": "#e0a030", "overlay": "#00000099",
    ]

    /// A theme from its tokens, with its list entry's `preview` for anything the tokens lack: docs/APP-DESIGN.md,
    /// Themes, Translation.
    public static func translate(_ tokens: ThemeTokens, preview: ThemeList.ThemeSummary.Preview? = nil) -> AppTheme {
        let colors = tokens.colors ?? [:]
        func token(_ key: String) -> ThemeColour? {
            colors[key].flatMap(ThemeColour.init(hex:)) ?? colors[key.lowercased()].flatMap(ThemeColour.init(hex:))
        }
        func base(_ key: String) -> ThemeColour { ThemeColour(hex: witty[key]!)! }

        let background = token("bg") ?? preview?.bg.flatMap(ThemeColour.init(hex:)) ?? base("bg")
        let text = token("fg") ?? preview?.text.flatMap(ThemeColour.init(hex:)) ?? base("fg")
        let accent = token("accent") ?? preview?.accent.flatMap(ThemeColour.init(hex:)) ?? base("accent")
        let panel = token("bg-2") ?? background.mixed(with: text, 0.04)
        let card = token("bg-3") ?? preview?.surface.flatMap(ThemeColour.init(hex:)) ?? background.mixed(with: text, 0.09)
        let raised = token("bg-4") ?? card.mixed(with: text, 0.06)
        let onAccent = token("accent-fg")
            ?? (ThemeColour.white.contrast(with: accent) >= ThemeColour.ink.contrast(with: accent) ? .white : .ink)
        let isLight: Bool = {
            switch tokens.scheme {
            case "light": return true
            case "dark": return false
            default: return background.luminance > 0.4
            }
        }()
        let radius = tokens.lengths?["radius"].flatMap { $0 >= 0 && $0 <= 40 ? $0 : nil } ?? 10
        return AppTheme(
            id: tokens.id,
            name: PlainWords.clean(tokens.name ?? "", limit: 40).isEmpty ? tokens.id : PlainWords.clean(tokens.name ?? "", limit: 40),
            isLight: isLight,
            background: background,
            panel: panel,
            card: card,
            raised: raised,
            border: token("border") ?? text.opacity(0.10),
            control: token("control-line") ?? text.opacity(0.20),
            text: text,
            textSecondary: token("fg-2") ?? text.opacity(0.72).over(background),
            textHint: token("fg-3") ?? text.opacity(0.55).over(background),
            accent: accent,
            accentPressed: token("accent-2") ?? accent.mixed(with: .black, 0.10),
            onAccent: onAccent,
            accentText: token("accent-text") ?? accent,
            danger: token("danger") ?? base("danger"),
            ok: token("ok") ?? base("ok"),
            warn: token("warn") ?? base("warn"),
            scrim: token("overlay") ?? ThemeColour.black.opacity(0.6),
            radius: radius)
    }

    /// The person's own look, made exactly as the website's theme maker makes it.
    public static func translate(made input: ThemeMakerInput) -> AppTheme {
        let made = ThemeMaker.make(input)
        let tokens = ThemeTokens(id: "custom", name: input.name, scheme: input.scheme == "light" ? "light" : "dark",
                                 colors: made.vars, lengths: ["radius": Double(made.radius)])
        return translate(tokens)
    }
}

/// The server's theme maker (`web/src/ui/themeMaker.ts`, `makeTheme`), step for step: a whole theme from a few
/// choices, every colour checked as it's made so anything picked is readable. Tested against
/// `shared/data/theme-maker-examples.json`, worked out by running the website's own code.
public enum ThemeMaker {
    public struct Made: Equatable {
        public var vars: [String: String]
        public var radius: Int
        public var adjusted: Bool
    }

    private typealias RGB = (Double, Double, Double)

    static func isHex(_ s: String) -> Bool {
        s.count == 7 && s.hasPrefix("#") && s.dropFirst().allSatisfy(\.isHexDigit)
    }

    private static func toRgb(_ h: String) -> RGB {
        let chars = Array(h)
        func part(_ i: Int) -> Double { Double(Int(String(chars[i...i + 1]), radix: 16) ?? 0) / 255 }
        return (part(1), part(3), part(5))
    }

    private static func toHex(_ c: RGB) -> String {
        func byte(_ v: Double) -> String {
            // JavaScript's Math.round rounds halves up, which Swift's .rounded() doesn't for negatives; these are 0...255.
            let n = Int((max(0, min(1, v)) * 255 + 0.5).rounded(.down))
            return String(format: "%02x", n)
        }
        return "#" + byte(c.0) + byte(c.1) + byte(c.2)
    }

    private static func luminance(_ c: RGB) -> Double {
        func f(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c.0) + 0.7152 * f(c.1) + 0.0722 * f(c.2)
    }

    static func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(toRgb(a)), lb = luminance(toRgb(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func toHsl(_ c: RGB) -> RGB {
        let (r, g, b) = c
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        if d == 0 { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if mx == r {
            h = ((g - b) / d + 6).truncatingRemainder(dividingBy: 6)
        } else if mx == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    private static func fromHsl(_ hsl: RGB) -> RGB {
        let (h, s, l) = hsl
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        // JavaScript's % keeps the sign of the dividend; Math.floor(h * 6) % 6 for h in 0..<1 is 0...5.
        let i = Int((h * 6).rounded(.down)) % 6
        let table: [RGB] = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)]
        let (r, g, b) = table[(i + 6) % 6]
        return (r + m, g + m, b + m)
    }

    private static func shade(_ hue: Double, _ sat: Double, _ l: Double) -> String { toHex(fromHsl((hue, sat, l))) }

    /// The colour, moved in lightness only as far as it takes to reach `need` against all of `on`.
    private static func reach(_ color: String, _ on: [String], _ need: Double, _ lighter: Bool) -> String {
        let (h, s, start) = toHsl(toRgb(color))
        var l = start
        for _ in 0..<220 {
            let c = toHex(fromHsl((h, s, l)))
            if on.allSatisfy({ contrast(c, $0) >= need }) { return c }
            l = max(0, min(1, l + (lighter ? 0.005 : -0.005)))
        }
        return lighter ? "#ffffff" : "#000000"
    }

    private static let corners = ["square": 2, "soft": 10, "round": 18]
    private static let ink = "#0e1013"

    public static func make(_ i: ThemeMakerInput) -> Made {
        let dark = i.scheme == "dark"
        let accent0 = isHex(i.accent) ? i.accent : "#7955ff"
        let tintHsl = toHsl(toRgb(isHex(i.tint) ? i.tint : accent0))
        let hue = tintHsl.0, tintSat = tintHsl.1
        // Surfaces take the tint's hue, held back so the page stays calm.
        let sat = min(tintSat, dark ? 0.32 : 0.28)
        func surface(_ dk: Double, _ lt: Double) -> String { shade(hue, sat, dark ? dk : lt) }
        let bg = surface(0.07, 0.96), bg2 = surface(0.1, 0.995), bg3 = surface(0.14, 0.92), bg4 = surface(0.19, 0.86)
        let surfaces = [bg, bg2, bg3]
        func text(_ dk: Double, _ lt: Double, _ s: Double = 0.12) -> String {
            reach(shade(hue, min(sat, s), dark ? dk : lt), surfaces, 4.5, dark)
        }
        let label = contrast("#ffffff", accent0) >= contrast(ink, accent0) ? "#ffffff" : ink
        let accent = reach(accent0, [label], 4.5, label == ink)
        let a = toHsl(toRgb(accent))
        let hover = toHex(fromHsl((a.0, a.1, max(0, min(1, a.2 + (label == ink ? 0.06 : -0.06))))))
        func status(_ c: String) -> String { reach(c, surfaces, 4.5, dark) }
        return Made(
            vars: [
                "bg": bg, "bg-2": bg2, "bg-3": bg3, "bg-4": bg4,
                "fg": text(0.93, 0.1), "fg-2": text(0.72, 0.3), "fg-3": text(0.6, 0.38),
                "accent": accent, "accent-2": reach(hover, [label], 4.5, label == ink), "accent-fg": label,
                "accent-text": reach(accent, surfaces, 4.5, dark),
                "control-line": reach(bg4, surfaces, 3, dark),
                "danger": status(dark ? "#ff5c6c" : "#cf2537"), "ok": status(dark ? "#3ad29f" : "#117b50"),
                "warn": status(dark ? "#e0a030" : "#9b5d00"),
            ],
            radius: corners[i.corners] ?? 10,
            adjusted: accent.lowercased() != accent0.lowercased())
    }
}
