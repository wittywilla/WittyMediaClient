import Foundation

// WittyTV's themes on Apple TV, which can't show the server's guide page. The choice follows the
// account, as it does in the page: what someone chose, or what the app's theme suggests, or else what
// the server's owner set. This is web/src/pages/tv/tvThemes.ts and look.ts in the server's repository:
// every colour token, each theme's shape (its proportions, which the app draws natively to match
// tvthemes.css), and the viewer's other choices. TvLookTests holds this to what that code works out.

/// What's saved in an account, under `tvLook` in GET /me/ui. A look saved before there were themes
/// held a layout and colours instead.
public struct TvSaved: Decodable, Equatable {
    public struct Custom: Decodable, Equatable {
        public var shape: String
        public var font: String?

        public init(shape: String, font: String? = nil) {
            self.shape = shape
            self.font = font
        }
    }

    public var theme: String?
    public var custom: Custom?
    public var themeColours: [String: [String: String]]?
    public var layout: String?
    public var colours: String?
    public var customBg: String?
    public var customAccent: String?
    public var density: String?
    public var hours: Double?
    public var nowLine: Bool?
    public var progress: Bool?
    public var subtitles: Bool?
    public var logos: Bool?
    public var art: Bool?
    public var preview: String?
    public var previewSide: String?
    public var previewW: Double?
    public var previewSound: Bool?
    /// From before there was a side and a width.
    public var previewPos: String?
    public var previewSize: String?

    public init(theme: String? = nil, custom: Custom? = nil, themeColours: [String: [String: String]]? = nil, layout: String? = nil, colours: String? = nil,
                customBg: String? = nil, customAccent: String? = nil, density: String? = nil, hours: Double? = nil, nowLine: Bool? = nil,
                progress: Bool? = nil, subtitles: Bool? = nil, logos: Bool? = nil, art: Bool? = nil, preview: String? = nil,
                previewSide: String? = nil, previewW: Double? = nil, previewSound: Bool? = nil) {
        self.theme = theme
        self.custom = custom
        self.themeColours = themeColours
        self.layout = layout
        self.colours = colours
        self.customBg = customBg
        self.customAccent = customAccent
        self.density = density
        self.hours = hours
        self.nowLine = nowLine
        self.progress = progress
        self.subtitles = subtitles
        self.logos = logos
        self.art = art
        self.preview = preview
        self.previewSide = previewSide
        self.previewW = previewW
        self.previewSound = previewSound
    }

    enum CodingKeys: String, CodingKey {
        case theme, custom, themeColours, layout, colours, customBg, customAccent, density, hours, nowLine, progress, subtitles, logos, art
        case preview, previewSide, previewW, previewSound, previewPos, previewSize
    }

    /// Anything of the wrong kind counts as not chosen, as the page reads it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        func flag(_ key: CodingKeys) -> Bool? { try? c.decodeIfPresent(Bool.self, forKey: key) }
        func number(_ key: CodingKeys) -> Double? { try? c.decodeIfPresent(Double.self, forKey: key) }
        theme = text(.theme)
        custom = try? c.decodeIfPresent(Custom.self, forKey: .custom)
        themeColours = try? c.decodeIfPresent([String: [String: String]].self, forKey: .themeColours)
        layout = text(.layout)
        colours = text(.colours)
        customBg = text(.customBg)
        customAccent = text(.customAccent)
        density = text(.density)
        hours = number(.hours)
        nowLine = flag(.nowLine)
        progress = flag(.progress)
        subtitles = flag(.subtitles)
        logos = flag(.logos)
        art = flag(.art)
        preview = text(.preview)
        previewSide = text(.previewSide)
        previewW = number(.previewW)
        previewSound = flag(.previewSound)
        previewPos = text(.previewPos)
        previewSize = text(.previewSize)
    }
}

/// Every colour the guide draws with, each as `#rrggbb`, or `#rrggbbaa` for the two washes
/// (`lite` over a cell's progress, `shade`). Every pairing that's drawn can be read.
public struct TvColours: Equatable {
    public let bg, panel, panel2, head, ch, dim, line, text, soft: String
    public let cell, cell2, cellText, cellSoft, live, live2, liveText, liveSoft: String
    public let hi, hiText, accent, accentText, keyA, keyB, keyC, keyText, err, lite, shade: String
}

/// The colours of the app's theme, for the themes that follow it.
public struct TvAppColours: Equatable {
    public let bg, bg2, bg3, bg4, fg, fg2, accent, accentText, accentFg, border, danger: String

    public init(bg: String, bg2: String, bg3: String, bg4: String, fg: String, fg2: String, accent: String, accentText: String, accentFg: String, border: String, danger: String = "#ff5c6c") {
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
        self.danger = danger
    }

    public static let fallback = TvAppColours(bg: "#0f1115", bg2: "#16181d", bg3: "#23262d", bg4: "#30343c", fg: "#ffffff", fg2: "#c9ccd3", accent: "#7955ff", accentText: "#b39dff", accentFg: "#ffffff", border: "#4a4f5a")
}

/// How the guide is built: its proportions, corners, rules and type. A theme is a shape with colours
/// and a name; Custom is a shape and colours someone chose.
public enum TvShape: String, CaseIterable {
    case box, modern, receiver, teletext, listings, cinema, outline, compact

    /// Row heights on a phone, a desktop and a TV, before the viewer's row size.
    public var rows: (phone: Double, desktop: Double, tv: Double) {
        switch self {
        case .box: return (56, 64, 72)
        case .modern: return (64, 76, 80)
        case .receiver: return (56, 58, 70)
        case .teletext: return (52, 50, 64)
        case .listings: return (60, 62, 72)
        case .cinema: return (56, 54, 64)
        case .outline: return (60, 66, 76)
        case .compact: return (44, 40, 56)
        }
    }

    /// How much of the page's width the preview starts at.
    public var previewShare: Double {
        switch self {
        case .modern: return 0.38
        case .cinema: return 0.48
        case .outline: return 0.36
        case .compact: return 0.22
        default: return 0.34
        }
    }

    /// The side the preview starts on.
    public var side: String { self == .cinema ? "left" : "right" }
    /// The programme's picture and title art at the top.
    public var art: Bool { self == .modern || self == .outline }
    /// Cells say time, year and genre, rather than the episode.
    public var details: Bool { [.modern, .cinema, .outline, .compact].contains(self) }
    /// The highlighted row's channel takes the highlight's colour.
    public var rowHighlight: Bool { self == .modern || self == .cinema }
    public var name: String {
        switch self {
        case .box: return "Cable box"
        case .modern: return "Modern"
        case .receiver: return "Receiver"
        case .teletext: return "Teletext"
        case .listings: return "Newspaper"
        case .cinema: return "Big picture"
        case .outline: return "Outline"
        case .compact: return "Compact"
        }
    }
}

/// One of WittyTV's themes. `follows`: its colours come from the app's theme until someone changes them.
public struct TvTheme: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let blurb: String
    public let shape: TvShape
    public let follows: Bool

    public static let all: [TvTheme] = [
        TvTheme(id: "modern", name: "Modern", blurb: "Clean and calm, with the programme's picture up top and a big preview.", shape: .modern, follows: true),
        TvTheme(id: "classic", name: "Classic", blurb: "The chunky blue box of the early 2000s, bevelled and square.", shape: .box, follows: false),
        TvTheme(id: "satellite", name: "Satellite", blurb: "A receiver's display: black and amber, thin rules, digits like an LED.", shape: .receiver, follows: false),
        TvTheme(id: "teletext", name: "Teletext", blurb: "Blocky letters and eight flat colours on black, page number and all.", shape: .teletext, follows: false),
        TvTheme(id: "listings", name: "Newspaper", blurb: "The listings page: ink on paper, serif type and hairline rules.", shape: .listings, follows: false),
        TvTheme(id: "bigpicture", name: "Big picture", blurb: "The preview comes first and takes half the width, over a short grid.", shape: .cinema, follows: true),
        TvTheme(id: "outline", name: "Outline", blurb: "Light and open: cells are outlines, and only the highlight is filled.", shape: .outline, follows: true),
        TvTheme(id: "compact", name: "Compact", blurb: "Small type and tight rows, for seeing the most channels at once.", shape: .compact, follows: true),
        TvTheme(id: "custom", name: "Custom", blurb: "Your own: choose the layout, type and colours, and it stays yours.", shape: .modern, follows: true),
    ]

    public static func byId(_ id: String?) -> TvTheme? { all.first { $0.id == id } }
}

/// How WittyTV looks for this viewer: the theme and where it came from, its shape, type and colours,
/// and the rest of what they chose. What they haven't chosen has the page's defaults.
public struct TvLookChoice: Equatable {
    public enum Source: String { case you, app, owner }

    public var theme: String
    public var shape: TvShape
    /// A Custom theme's type: "", "system", "narrow", "mono" or "serif". "" is the layout's own.
    public var font: String
    public var source: Source
    public var colours: TvColours
    /// The colours this theme was changed to, if any.
    public var overrides: [String: String]
    public var density: String
    /// 0 is what fits the screen.
    public var hours: Double
    public var nowLine: Bool
    public var progress: Bool
    public var subtitles: Bool
    public var logos: Bool
    public var art: Bool
    /// "highlight", "last" or "off".
    public var preview: String
    public var previewSide: String
    public var previewW: Double?
    public var previewSound: Bool

    /// The highlight and the background, as dark or light, for logos that come in both.
    public var bgIsDark: Bool { TvLook.readableOn(TvLook.solid(colours.bg)) == "#ffffff" }
    public var hiIsDark: Bool { TvLook.readableOn(TvLook.solid(colours.hi)) == "#ffffff" }
}

public enum TvLook {
    private typealias Tokens = [String: String]
    private static let themes: Set<String> = Set(TvTheme.all.map(\.id))
    private static let aa = 4.5

    private static let own: [String: Tokens] = [
        "classic": ["bg": "#06164a", "panel": "#0a2270", "panel-2": "#123391", "head": "#16389e", "cell": "#1a43b8", "cell-2": "#143594", "live": "#0f6a7f", "live-2": "#0b5466", "ch": "#0c2a84", "dim": "#0d2a7c", "line": "#6f94f2",
                    "text": "#ffffff", "soft": "#d6e2ff", "hi": "#ffd60a", "accent": "#ffd60a", "key-a": "#ffd60a", "key-b": "#4ce06a", "key-c": "#7fc7ff", "err": "#ffe08a", "lite": "#ffffff29"],
        "satellite": ["bg": "#07090d", "panel": "#10131a", "panel-2": "#22262f", "head": "#14171e", "cell": "#14171e", "cell-2": "#14171e", "live": "#2e2300", "live-2": "#2e2300", "ch": "#10131a", "dim": "#0c0e13", "line": "#6a7181",
                      "text": "#ffffff", "soft": "#dcdfe6", "hi": "#ffb300", "accent": "#ffb300", "key-a": "#ffb300", "key-b": "#5fd47d", "key-c": "#8cc6ff", "err": "#ffd27a", "lite": "#ffb3002e"],
        "teletext": ["bg": "#000000", "panel": "#000000", "panel-2": "#0000d0", "head": "#0000d0", "cell": "#000000", "cell-2": "#000000", "live": "#003c00", "live-2": "#003c00", "ch": "#000000", "dim": "#000000", "line": "#00d8d8",
                     "text": "#ffffff", "soft": "#00ffff", "hi": "#00ffff", "accent": "#ffff00", "key-a": "#ff5a5a", "key-b": "#00ff00", "key-c": "#ffff00", "err": "#ff9d9d", "lite": "#00ff0038"],
        "listings": ["bg": "#f5f0e4", "panel": "#f5f0e4", "panel-2": "#eae3d2", "head": "#f5f0e4", "cell": "#f5f0e4", "cell-2": "#f5f0e4", "live": "#ebdfb8", "live-2": "#ebdfb8", "ch": "#f5f0e4", "dim": "#efe9db", "line": "#6b6252",
                     "text": "#1b1813", "soft": "#4d463a", "hi": "#1b1813", "accent": "#9c1c12", "key-a": "#1b1813", "key-b": "#1b1813", "key-c": "#1b1813", "err": "#9c1c12", "lite": "#9c1c121f"],
    ]

    private static let legacy: [String: [String: String]] = [
        "midnight": ["bg": "#000000", "cell": "#2a2a2a", "live": "#3a3a3a", "hi": "#ffffff", "accent": "#c9a2ff"],
        "cable": ["bg": "#06164a", "cell": "#1a43b8", "live": "#0f6a7f", "hi": "#ffd60a", "accent": "#ffd60a"],
        "satellite": ["bg": "#07090d", "cell": "#2b3039", "live": "#4d3700", "hi": "#ffb300", "accent": "#ffb300"],
    ]

    // MARK: Which theme

    /// What a theme came to before there were themes: a layout and a set of colours.
    struct Legacy { var theme: String; var custom: TvSaved.Custom?; var colours: [String: String] }

    /// Which theme this account has, and what it changed in it. The app's theme can suggest one, and
    /// the owner's look comes with the guide.
    public static func choice(saved: TvSaved?, suggestion: String? = nil, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?) -> (theme: String, colours: [String: String]) {
        let full = choose(saved: saved, suggestion: suggestion, ownerTheme: ownerTheme, ownerLayout: ownerLayout, ownerSkin: ownerSkin)
        return (full.theme, full.colours)
    }

    private static func choose(saved: TvSaved?, suggestion: String?, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?) -> (theme: String, source: TvLookChoice.Source, custom: TvSaved.Custom?, colours: [String: String]) {
        let mine = upgrade(saved ?? TvSaved(), ownerLayout: ownerLayout, ownerSkin: ownerSkin)
        func yours(_ theme: String) -> [String: String] { mine.themeColours?[theme] ?? [:] }
        if let theme = mine.theme, isTheme(theme) {
            return (theme, .you, mine.custom, yours(theme))
        }
        if let theme = suggestion, isTheme(theme), theme != "custom" {
            return (theme, .app, mine.custom, yours(theme))
        }
        if let theme = ownerTheme, isTheme(theme), theme != "custom" {
            return (theme, .owner, mine.custom, yours(theme))
        }
        if ownerLayout != nil || ownerSkin != nil {
            let was = fromLegacy(ownerLayout, ownerSkin, nil, nil)
            return (was.theme, .owner, mine.custom ?? was.custom, mine.themeColours?[was.theme] ?? was.colours)
        }
        return ("classic", .owner, mine.custom, yours("classic"))
    }

    /// Reads a look saved in any earlier form, as the page's upgradeSaved does.
    static func upgrade(_ raw: TvSaved, ownerLayout: String?, ownerSkin: String?) -> TvSaved {
        var out = raw
        if out.previewSide == nil, let pos = raw.previewPos { out.previewSide = pos == "tl" || pos == "bl" ? "left" : "right" }
        if out.previewW == nil, let size = raw.previewSize, let w = ["s": 220.0, "m": 320, "l": 460][size] { out.previewW = w }
        if !isTheme(raw.theme), raw.layout != nil || raw.colours != nil {
            let was = fromLegacy(raw.layout ?? ownerLayout, raw.colours ?? ownerSkin, raw.customBg, raw.customAccent)
            out.theme = was.theme
            if let custom = was.custom { out.custom = custom }
            if !was.colours.isEmpty { out.themeColours = [was.theme: was.colours] }
        }
        if !isTheme(out.theme) { out.theme = nil }
        if let shape = out.custom?.shape, TvShape(rawValue: shape) == nil { out.custom = nil }
        return out
    }

    public static func colours(saved: TvSaved?, suggestion: String? = nil, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?, app: TvAppColours = .fallback) -> TvColours {
        resolve(saved: saved, suggestion: suggestion, ownerTheme: ownerTheme, ownerLayout: ownerLayout, ownerSkin: ownerSkin, app: app).colours
    }

    /// The whole look, as the page's `useLook` works it out.
    public static func resolve(saved: TvSaved?, suggestion: String? = nil, ownerTheme: String?, ownerLayout: String?, ownerSkin: String?, app: TvAppColours = .fallback) -> TvLookChoice {
        let mine = upgrade(saved ?? TvSaved(), ownerLayout: ownerLayout, ownerSkin: ownerSkin)
        let chosen = choose(saved: saved, suggestion: suggestion, ownerTheme: ownerTheme, ownerLayout: ownerLayout, ownerSkin: ownerSkin)
        let custom = chosen.custom ?? TvSaved.Custom(shape: "modern", font: "")
        let shape = chosen.theme == "custom" ? TvShape(rawValue: custom.shape) ?? .modern : TvTheme.byId(chosen.theme)?.shape ?? .box
        let hours = [0, 1.5, 2, 3, 4].contains(mine.hours ?? 0) ? mine.hours ?? 0 : 0
        return TvLookChoice(
            theme: chosen.theme, shape: shape, font: chosen.theme == "custom" ? custom.font ?? "" : "", source: chosen.source,
            colours: colours(theme: chosen.theme, overrides: chosen.colours, app: app), overrides: chosen.colours.filter { isHex($0.value) },
            density: ["compact", "normal", "large"].contains(mine.density ?? "") ? mine.density! : "normal", hours: hours,
            nowLine: mine.nowLine ?? true, progress: mine.progress ?? true, subtitles: mine.subtitles ?? true, logos: mine.logos ?? true, art: mine.art ?? true,
            preview: ["highlight", "last", "off"].contains(mine.preview ?? "") ? mine.preview! : "highlight",
            previewSide: mine.previewSide == "left" || mine.previewSide == "right" ? mine.previewSide! : shape.side,
            previewW: mine.previewW, previewSound: mine.previewSound ?? false)
    }

    private static func isTheme(_ id: String?) -> Bool { id.map(themes.contains) ?? false }

    static func fromLegacy(_ layout: String?, _ colours: String?, _ customBg: String?, _ customAccent: String?) -> Legacy {
        var mine: [String: String] = [:]
        if let customBg, let customAccent, isHex(customBg), isHex(customAccent) { mine = ["bg": customBg, "accent": customAccent, "hi": customAccent] }
        if layout == "streaming" {
            if colours == "theme" { return Legacy(theme: "modern", custom: nil, colours: [:]) }
            return Legacy(theme: "modern", custom: nil, colours: colours == "custom" ? mine : legacy[colours ?? "midnight"] ?? legacy["midnight"]!)
        }
        switch colours {
        case "satellite": return Legacy(theme: "satellite", custom: nil, colours: [:])
        case "midnight": return Legacy(theme: "custom", custom: .init(shape: "box", font: ""), colours: legacy["midnight"]!)
        case "theme": return Legacy(theme: "custom", custom: .init(shape: "box", font: "system"), colours: [:])
        case "custom": return Legacy(theme: "custom", custom: .init(shape: "box", font: ""), colours: mine)
        default: return Legacy(theme: "classic", custom: nil, colours: [:])
        }
    }

    /// What a theme says for clients that only know the two earlier looks, kept beside it.
    public static func legacyOf(_ id: String, shape: TvShape) -> (layout: String, colours: String) {
        if id == "satellite" { return ("classic", "satellite") }
        if id == "classic" || id == "teletext" { return ("classic", "cable") }
        if shape == .box { return ("classic", "theme") }
        return ("streaming", "theme")
    }

    // MARK: Sizes

    /// A row's height, from the shape, the width of the page and the viewer's row size.
    public static func rowHeight(_ shape: TvShape, width: Double, density: String) -> Double {
        let rows = shape.rows
        let base = width < 560 ? rows.phone : width >= 1800 ? rows.tv : rows.desktop
        let times: Double = density == "compact" ? 0.8 : density == "large" ? 1.25 : 1
        return (base * times).rounded()
    }

    public static let previewMin = 180.0
    /// The preview's named sizes. Any width between works too.
    public static let previewSizes: [(width: Double, name: String)] = [(220, "Small"), (320, "Medium"), (460, "Large"), (640, "Extra large"), (880, "Huge")]

    /// What the page can spare for the preview, so the words beside it and the guide below keep room.
    public static func previewLimit(pageWidth: Double, pageHeight: Double) -> Double {
        let byWidth = pageWidth * 0.6
        let byHeight = (pageHeight * 0.46 - 44) * (16.0 / 9)
        return max(previewMin, min(byWidth, byHeight)).rounded()
    }

    /// How wide the preview starts: a share of the page that suits the shape, held to what fits.
    public static func previewAuto(_ shape: TvShape, pageWidth: Double, pageHeight: Double) -> Double {
        let most = previewLimit(pageWidth: pageWidth, pageHeight: pageHeight)
        return min(most, max(previewMin, pageWidth * shape.previewShare)).rounded()
    }

    // MARK: Its colours

    static func colours(theme id: String, overrides: [String: String], app: TvAppColours) -> TvColours {
        let set = overrides.filter { isHex($0.value) }
        let hiFollowsText = id == "modern" || id == "bigpicture"
        if set.isEmpty {
            if let base = own[id] {
                return derive(["bg": base["bg"]!, "cell": base["cell"]!, "live": base["live"]!, "hi": base["hi"]!, "accent": base["accent"]!, "text": base["text"]!], base: base)
            }
            // Following the app's theme: only its own colours.
            let hi = hiFollowsText ? app.fg : app.accent, hiText = hiFollowsText ? app.bg : app.accentFg
            return TvColours(bg: app.bg, panel: app.bg2, panel2: app.bg3, head: app.bg2, ch: app.bg2, dim: app.bg2, line: app.border, text: app.fg, soft: app.fg2,
                             cell: app.bg3, cell2: app.bg3, cellText: app.fg, cellSoft: app.fg2, live: app.bg4, live2: app.bg4, liveText: app.fg, liveSoft: app.fg2,
                             hi: hi, hiText: hiText, accent: app.accentText, accentText: app.bg, keyA: hi, keyB: hi, keyC: hi, keyText: hiText, err: app.danger,
                             lite: alpha(app.accent, 0.24), shade: alpha(app.bg, 0.12))
        }
        let base = own[id] ?? ["bg": app.bg, "panel": app.bg2, "panel-2": app.bg3, "head": app.bg2, "cell": app.bg3, "cell-2": app.bg3, "live": app.bg4, "live-2": app.bg4, "ch": app.bg2, "dim": app.bg2, "line": app.border,
                               "text": app.fg, "soft": app.fg2, "hi": hiFollowsText ? app.fg : app.accent, "accent": app.accentText]
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
        let panel = fromBase("panel", 0.06), panel2 = fromBase("panel-2", 0.12), head = fromBase("head", 0.14), ch = fromBase("ch", 0.06), dim = fromBase("dim", 0.06)
        let page = [bg, panel, panel2, head, ch, dim]
        let accent = legible(c["accent"]!, page)
        let hi = legible(c["hi"]!, [bg], need: 3)
        let cell = c["cell"]!, live = c["live"]!
        let onCell = onCells(text, cell, base["cell"] == cell ? base["cell-2"]! : mix(cell, bg, 0.18))
        let onLive = onCells(text, live, base["live"] == live ? base["live-2"]! : mix(live, bg, 0.18))
        func key(_ k: String) -> String { base["accent"] == accent ? base[k] ?? accent : accent }
        let err = legible(base["err"] != nil && base["bg"] == bg ? base["err"]! : accent, page)
        let lite = base["lite"] != nil && base["bg"] == bg ? base["lite"]! : readableOn(bg) == "#ffffff" ? alpha("#ffffff", 0.16) : alpha("#000000", 0.1)
        let shade = readableOn(hi) == "#ffffff" ? alpha("#ffffff", 0.2) : alpha("#000000", 0.14)
        return TvColours(bg: bg, panel: panel, panel2: panel2, head: head, ch: ch, dim: dim,
                         line: legible(fromBase("line", 0.34), [bg], need: 3), text: text, soft: softOn(text, page),
                         cell: cell, cell2: onCell.second, cellText: onCell.text, cellSoft: onCell.soft,
                         live: live, live2: onLive.second, liveText: onLive.text, liveSoft: onLive.soft,
                         hi: hi, hiText: readableOn(hi), accent: accent, accentText: readableOn(accent),
                         keyA: key("key-a"), keyB: key("key-b"), keyC: key("key-c"), keyText: readableOn(key("key-a")),
                         err: err, lite: lite, shade: shade)
    }

    /// Text for a cell and its gradient's other end: a cell can be any colour, and the page another.
    private static func onCells(_ text: String, _ cell: String, _ second: String) -> (text: String, second: String, soft: String) {
        let t = contrast(text, cell) >= aa ? text : readableOn(cell)
        let second = underText(second, t, cell)
        return (t, second, softOn(t, [cell, second]))
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

    // MARK: Colour sums

    public static func isHex(_ value: String) -> Bool {
        value.count == 7 && value.hasPrefix("#") && value.dropFirst().allSatisfy(\.isHexDigit)
    }

    /// `#rrggbb` with an opacity, as `#rrggbbaa`.
    static func alpha(_ hex: String, _ amount: Double) -> String {
        let a = Int((amount * 255).rounded())
        return solid(hex) + (a < 16 ? "0" : "") + String(a, radix: 16)
    }

    /// The colour without its opacity.
    static func solid(_ hex: String) -> String { String(hex.prefix(7)) }

    private static func channels(_ hex: String) -> [Double] {
        let digits = Array(hex.dropFirst())
        guard digits.count >= 6 else { return [0, 0, 0] }
        return [0, 2, 4].map { Double(Int(String(digits[$0...($0 + 1)]), radix: 16) ?? 0) }
    }

    static func mix(_ a: String, _ b: String, _ t: Double) -> String {
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

    public static func contrast(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    public static func readableOn(_ bg: String) -> String {
        contrast(bg, "#ffffff") >= contrast(bg, "#000000") ? "#ffffff" : "#000000"
    }

    /// A channel's own colour, pushed far enough from the background to be seen.
    public static func channelAccent(_ accent: String?, on bg: String) -> String? {
        guard let accent, isHex(accent) else { return nil }
        let away = readableOn(solid(bg))
        var a = accent
        var tries = 0
        while tries < 10, contrast(a, solid(bg)) < aa {
            a = mix(a, away, 0.15)
            tries += 1
        }
        return a
    }
}

/// GET /me/ui. It holds other choices too, which this leaves alone. Each part is read on its own, so one
/// written by an older or newer website can't spoil the rest.
struct AccountChoices: Decodable {
    let tvLook: TvSaved?
    let customTheme: ThemeMakerInput?

    enum CodingKeys: String, CodingKey { case tvLook, customTheme }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tvLook = try? c.decodeIfPresent(TvSaved.self, forKey: .tvLook)
        customTheme = try? c.decodeIfPresent(ThemeMakerInput.self, forKey: .customTheme)
    }
}
