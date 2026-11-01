import Foundation

// WittyTV's themes on Apple TV, which can't show the server's guide page. The choice follows the
// account, as it does in the page: what someone chose, or else what the server's owner set. This is
// web/src/pages/tv/tvThemes.ts in the server's repository, for the colours only. Its layouts are CSS
// and don't come across. TvLookTests holds this to what that code works out.

/// What's saved in an account, under `tvLook` in GET /me/ui. A look saved before there were themes
/// held a layout and colours instead.
public struct TvSaved: Decodable, Equatable {
    public var theme: String?
    public var themeColours: [String: [String: String]]?
    public var layout: String?
    public var colours: String?
    public var customBg: String?
    public var customAccent: String?
    public var logos: Bool?

    public init(theme: String? = nil, themeColours: [String: [String: String]]? = nil, layout: String? = nil, colours: String? = nil, customBg: String? = nil, customAccent: String? = nil, logos: Bool? = nil) {
        self.theme = theme
        self.themeColours = themeColours
        self.layout = layout
        self.colours = colours
        self.customBg = customBg
        self.customAccent = customAccent
        self.logos = logos
    }
}

/// The theme's colours, each as `#rrggbb`. Every pairing that's drawn can be read.
public struct TvColours: Equatable {
    public let bg, panel, cell, cellText, live, liveText, hi, hiText, accent, text, soft, line: String
}

/// The colours of the app's theme, for the themes that follow it.
public struct TvAppColours: Equatable {
    public let bg, bg2, bg3, bg4, fg, fg2, accent, accentText, accentFg, border: String

    public init(bg: String, bg2: String, bg3: String, bg4: String, fg: String, fg2: String, accent: String, accentText: String, accentFg: String, border: String) {
        self.bg = bg
        self.bg2 = bg2
        self.bg3 = bg3
        self.bg4 = bg4
        self.fg = fg
        self.fg2 = fg2
        self.accent = accent
        self.accentText = accentText
        self.accentFg = accentFg
        self.border = border
    }

    public static let fallback = TvAppColours(bg: "#0f1115", bg2: "#16181d", bg3: "#23262d", bg4: "#30343c", fg: "#ffffff", fg2: "#c9ccd3", accent: "#7955ff", accentText: "#b39dff", accentFg: "#ffffff", border: "#4a4f5a")
}

public enum TvLook {
    private typealias Tokens = [String: String]
    private static let themes: Set<String> = ["modern", "classic", "satellite", "teletext", "listings", "bigpicture", "outline", "compact", "custom"]
    private static let aa = 4.5

    private static let own: [String: Tokens] = [
        "classic": ["bg": "#06164a", "panel": "#0a2270", "panel-2": "#123391", "head": "#16389e", "cell": "#1a43b8", "cell-2": "#143594", "live": "#0f6a7f", "live-2": "#0b5466", "ch": "#0c2a84", "dim": "#0d2a7c", "line": "#6f94f2", "text": "#ffffff", "soft": "#d6e2ff", "hi": "#ffd60a", "accent": "#ffd60a"],
        "satellite": ["bg": "#07090d", "panel": "#10131a", "panel-2": "#22262f", "head": "#14171e", "cell": "#14171e", "cell-2": "#14171e", "live": "#2e2300", "live-2": "#2e2300", "ch": "#10131a", "dim": "#0c0e13", "line": "#6a7181", "text": "#ffffff", "soft": "#dcdfe6", "hi": "#ffb300", "accent": "#ffb300"],
        "teletext": ["bg": "#000000", "panel": "#000000", "panel-2": "#0000d0", "head": "#0000d0", "cell": "#000000", "cell-2": "#000000", "live": "#003c00", "live-2": "#003c00", "ch": "#000000", "dim": "#000000", "line": "#00d8d8", "text": "#ffffff", "soft": "#00ffff", "hi": "#00ffff", "accent": "#ffff00"],
        "listings": ["bg": "#f5f0e4", "panel": "#f5f0e4", "panel-2": "#eae3d2", "head": "#f5f0e4", "cell": "#f5f0e4", "cell-2": "#f5f0e4", "live": "#ebdfb8", "live-2": "#ebdfb8", "ch": "#f5f0e4", "dim": "#efe9db", "line": "#6b6252", "text": "#1b1813", "soft": "#4d463a", "hi": "#1b1813", "accent": "#9c1c12"],
    ]

    private static let legacy: [String: [String: String]] = [
        "midnight": ["bg": "#000000", "cell": "#2a2a2a", "live": "#3a3a3a", "hi": "#ffffff", "accent": "#c9a2ff"],
        "cable": ["bg": "#06164a", "cell": "#1a43b8", "live": "#0f6a7f", "hi": "#ffd60a", "accent": "#ffd60a"],
        "satellite": ["bg": "#07090d", "cell": "#2b3039", "live": "#4d3700", "hi": "#ffb300", "accent": "#ffb300"],
    ]

    // MARK: Which theme

    /// Which theme this account has, and what it changed in it. The owner's look comes with the guide.
    public static func choice(saved: TvSaved?, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?) -> (theme: String, colours: [String: String]) {
        var mine = saved ?? TvSaved()
        if !isTheme(mine.theme), mine.layout != nil || mine.colours != nil {
            let was = fromLegacy(mine.layout ?? ownerLayout, mine.colours ?? ownerSkin, mine.customBg, mine.customAccent)
            mine.theme = was.theme
            mine.themeColours = was.colours.isEmpty ? nil : [was.theme: was.colours]
        }
        if let theme = mine.theme, isTheme(theme) {
            return (theme, mine.themeColours?[theme] ?? [:])
        }
        if let theme = ownerTheme, isTheme(theme), theme != "custom" {
            return (theme, mine.themeColours?[theme] ?? [:])
        }
        if ownerLayout != nil || ownerSkin != nil {
            let was = fromLegacy(ownerLayout, ownerSkin, nil, nil)
            return (was.theme, mine.themeColours?[was.theme] ?? was.colours)
        }
        return ("classic", mine.themeColours?["classic"] ?? [:])
    }

    public static func colours(saved: TvSaved?, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?, app: TvAppColours = .fallback) -> TvColours {
        let chosen = choice(saved: saved, ownerTheme: ownerTheme, ownerLayout: ownerLayout, ownerSkin: ownerSkin)
        return colours(theme: chosen.theme, overrides: chosen.colours, app: app)
    }

    private static func isTheme(_ id: String?) -> Bool { id.map(themes.contains) ?? false }

    private static func fromLegacy(_ layout: String?, _ colours: String?, _ customBg: String?, _ customAccent: String?) -> (theme: String, colours: [String: String]) {
        var mine: [String: String] = [:]
        if let customBg, let customAccent, isHex(customBg), isHex(customAccent) { mine = ["bg": customBg, "accent": customAccent, "hi": customAccent] }
        if layout == "streaming" {
            if colours == "theme" { return ("modern", [:]) }
            return ("modern", colours == "custom" ? mine : legacy[colours ?? "midnight"] ?? legacy["midnight"]!)
        }
        switch colours {
        case "satellite": return ("satellite", [:])
        case "midnight": return ("custom", legacy["midnight"]!)
        case "theme": return ("custom", [:])
        case "custom": return ("custom", mine)
        default: return ("classic", [:])
        }
    }

    // MARK: Its colours

    static func colours(theme id: String, overrides: [String: String], app: TvAppColours) -> TvColours {
        let set = overrides.filter { isHex($0.value) }
        let followsWithHi = id == "modern" || id == "bigpicture"
        if set.isEmpty {
            if let base = own[id] {
                return derive(["bg": base["bg"]!, "cell": base["cell"]!, "live": base["live"]!, "hi": base["hi"]!, "accent": base["accent"]!, "text": base["text"]!], base: base)
            }
            return TvColours(bg: app.bg, panel: app.bg2, cell: app.bg3, cellText: app.fg, live: app.bg4, liveText: app.fg,
                             hi: followsWithHi ? app.fg : app.accent, hiText: followsWithHi ? app.bg : app.accentFg,
                             accent: app.accentText, text: app.fg, soft: app.fg2, line: app.border)
        }
        let base = own[id] ?? ["bg": app.bg, "panel": app.bg2, "panel-2": app.bg3, "head": app.bg2, "cell": app.bg3, "cell-2": app.bg3, "live": app.bg4, "live-2": app.bg4, "ch": app.bg2, "dim": app.bg2, "line": app.border, "text": app.fg, "soft": app.fg2, "hi": followsWithHi ? app.fg : app.accent, "accent": app.accentText]
        // A new background with no word on the text: the text goes with it, and so do cells
        // that were worked out for the old one.
        let text = set["text"] ?? (set["bg"] != nil ? readableOn(set["bg"]!) : base["text"]!)
        let bg = set["bg"] ?? base["bg"]!
        let cell = set["cell"] ?? (set["bg"] != nil ? mix(bg, readableOn(bg), 0.14) : base["cell"]!)
        let accent = set["accent"] ?? base["accent"]!
        let live = set["live"] ?? (set["bg"] != nil || set["accent"] != nil || set["cell"] != nil ? mix(cell, accent, 0.22) : base["live"]!)
        return derive(["bg": bg, "cell": cell, "live": live, "hi": set["hi"] ?? base["hi"]!, "accent": accent, "text": text], base: base)
    }

    private static func derive(_ c: [String: String], base: Tokens) -> TvColours {
        let bg = c["bg"]!
        let text = legible(c["text"]!, [bg])
        func lift(_ t: Double) -> String { underText(mix(bg, text, t), text, bg) }
        func fromBase(_ key: String, _ t: Double) -> String { base["bg"] == bg ? underText(base[key]!, text, bg) : lift(t) }
        let panel = fromBase("panel", 0.06)
        let page = [bg, panel, fromBase("panel-2", 0.12), fromBase("head", 0.14), fromBase("ch", 0.06), fromBase("dim", 0.06)]
        let accent = legible(c["accent"]!, page)
        let hi = legible(c["hi"]!, [bg], need: 3)
        let cell = c["cell"]!, live = c["live"]!
        return TvColours(bg: bg, panel: panel,
                         cell: cell, cellText: onCells(text, cell),
                         live: live, liveText: onCells(text, live),
                         hi: hi, hiText: readableOn(hi), accent: accent, text: text, soft: softOn(text, page),
                         line: legible(fromBase("line", 0.34), [bg], need: 3))
    }

    private static func onCells(_ text: String, _ cell: String) -> String {
        contrast(text, cell) >= aa ? text : readableOn(cell)
    }

    private static func legible(_ colour: String, _ surfaces: [String], need: Double = aa) -> String {
        func ok(_ c: String) -> Bool { surfaces.allSatisfy { contrast(c, $0) >= need } }
        for towards in [readableOn(surfaces[0]), readableOn(colour)] {
            var c = colour
            var tries = 0
            while tries < 12, !ok(c) {
                c = mix(c, towards, 0.15)
                tries += 1
            }
            if ok(c) { return c }
            if ok(towards) { return towards }
        }
        return readableOn(surfaces[0])
    }

    private static func underText(_ surface: String, _ text: String, _ readsOn: String) -> String {
        var s = surface
        var tries = 0
        while tries < 12, contrast(text, s) < aa {
            s = mix(s, readsOn, 0.2)
            tries += 1
        }
        return contrast(text, s) >= aa ? s : readsOn
    }

    private static func softOn(_ text: String, _ surfaces: [String]) -> String {
        for t in [0.24, 0.16, 0.08] {
            let c = mix(text, surfaces[0], t)
            if surfaces.allSatisfy({ contrast(c, $0) >= aa }) { return c }
        }
        return text
    }

    private static func isHex(_ value: String) -> Bool {
        value.count == 7 && value.hasPrefix("#") && value.dropFirst().allSatisfy(\.isHexDigit)
    }

    private static func channels(_ hex: String) -> [Double] {
        let digits = Array(hex.dropFirst())
        return [0, 2, 4].map { Double(Int(String(digits[$0...($0 + 1)]), radix: 16) ?? 0) }
    }

    private static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        let x = channels(a), y = channels(b)
        return "#" + zip(x, y).map { pair -> String in
            let v = Int(max(0, min(255, pair.0 + (pair.1 - pair.0) * t)).rounded())
            return (v < 16 ? "0" : "") + String(v, radix: 16)
        }.joined()
    }

    private static func luminance(_ hex: String) -> Double {
        let c = channels(hex).map { (v: Double) -> Double in
            let s = v / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    private static func contrast(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func readableOn(_ bg: String) -> String {
        contrast(bg, "#ffffff") >= contrast(bg, "#000000") ? "#ffffff" : "#000000"
    }
}

/// GET /me/ui. It holds other choices too, which this leaves alone.
struct AccountChoices: Decodable {
    let tvLook: TvSaved?
}
