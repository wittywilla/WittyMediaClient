// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The server's name and mark, edited (the server's docs/THEMES.md, The server's name; docs/plans/DESIGN-2.md 7.6): which
// letters are in which colour (the theme's text or accent, any theme token, a fixed colour or a gradient), bold, presets,
// the mark for small spaces, and a contrast check against the surfaces the name is drawn on. The rules here are the server's
// (internal/brandname): the same words, the same limits, the same settings it saves, so what is previewed is what is drawn.

/// Where one word of a name starts and ends, as the server finds words (internal/brandname.Words): split at spaces, and inside
/// joined words before a capital that follows a small letter (MyHome), before the last capital of a run that starts a word
/// (TVRoom), between small letters and digits (Movies4K), and after a dash, underscore, slash or the like.
public enum BrandWords {
    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }
    private static func isMark(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }
    private static func isDigit(_ c: Unicode.Scalar) -> Bool { c.properties.generalCategory == .decimalNumber }
    private static func isUpper(_ c: Unicode.Scalar) -> Bool { c.properties.generalCategory == .uppercaseLetter }
    private static func isLower(_ c: Unicode.Scalar) -> Bool { c.properties.generalCategory == .lowercaseLetter }
    private static func joiner(_ c: Unicode.Scalar) -> Bool {
        c.properties.generalCategory == .dashPunctuation || "_/&+|·:".unicodeScalars.contains(c)
    }

    /// The words of a name as [start, end) code point offsets.
    public static func ranges(_ name: String) -> [Range<Int>] {
        let r = Array(name.unicodeScalars)
        var out: [Range<Int>] = []
        var start = -1
        for (i, c) in r.enumerated() {
            if c.properties.isWhitespace {
                if start >= 0 { out.append(start..<i); start = -1 }
                continue
            }
            if start < 0 { start = i; continue }
            if breaksBefore(r, start, i) { out.append(start..<i); start = i }
        }
        if start >= 0 { out.append(start..<r.count) }
        return out
    }

    private static func breaksBefore(_ r: [Unicode.Scalar], _ start: Int, _ i: Int) -> Bool {
        let c = r[i]
        var p = -1
        var j = i - 1
        while j >= start {
            if !isMark(r[j]) { p = j; break }
            j -= 1
        }
        if p < 0 || isMark(c) { return false }
        let prev = r[p]
        if isUpper(c) {
            if isLower(prev) { return true }
            if isUpper(prev) || isDigit(prev) { return i + 2 < r.count && isLower(r[i + 1]) && isLower(r[i + 2]) }
            if joiner(prev) {
                for k in start..<p where isLetter(r[k]) || isDigit(r[k]) { return true }
            }
        } else if isDigit(c) {
            return isLower(prev)
        }
        return false
    }
}

/// How one letter is drawn.
public struct BrandStyle: Equatable, Sendable {
    public var colour: ResolvedTheme.BrandColour
    public var bold: Bool

    public static let plain = BrandStyle(colour: .init(kind: "fg"), bold: false)
    public init(colour: ResolvedTheme.BrandColour, bold: Bool = false) {
        self.colour = colour
        self.bold = bold
    }
}

/// What the rail's badge holds (the server's `brandMark` setting).
public struct BrandMarkChoice: Codable, Equatable, Sendable {
    /// letter, initials, text or image.
    public var kind: String
    public var text: String?

    public static let letter = BrandMarkChoice(kind: "letter")
    public init(kind: String, text: String? = nil) {
        self.kind = kind
        self.text = text
    }

    /// The server's limits: your own mark is one or two characters.
    public static func custom(_ text: String) -> BrandMarkChoice? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let n = trimmed.unicodeScalars.count
        return n >= 1 && n <= 2 ? BrandMarkChoice(kind: "text", text: trimmed) : nil
    }

    /// The characters the badge draws for a name (letter, initials or the owner's own); a logo draws a picture.
    public func shown(name: String) -> String {
        switch kind {
        case "text": return text ?? ""
        case "initials":
            let scalars = Array(name.unicodeScalars)
            return String(String.UnicodeScalarView(BrandWords.ranges(name).prefix(3).map { scalars[$0.lowerBound] }))
        default:
            return name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
        }
    }
}

/// One colouring of a range of the name, as the server saves it (`brandSpans`).
public struct BrandSpan: Codable, Equatable, Sendable {
    public var from: Int
    public var to: Int
    public var color: ResolvedTheme.BrandColour
    public var bold: Bool?
}

/// The name as being edited: a style for each letter.
public struct BrandDraft: Equatable, Sendable {
    /// The server's limits (internal/brandname): at most 80 characters and 40 colour changes.
    public static let maxRunes = 80
    public static let maxSpans = 40
    public static let defaultName = "WittyMediaServer"

    public private(set) var name: String
    public private(set) var styles: [BrandStyle]
    public var mark: BrandMarkChoice

    /// The name drawn: the owner's, or the default.
    public var shown: String { name.isEmpty ? Self.defaultName : name }
    public var letters: [Character] { Array(shown) }

    // MARK: Making a draft

    /// From the name the server draws: the theme's parts, each with its colour (the default is the theme's text with the
    /// middle word in the accent).
    public init(name: String, parts: [ResolvedTheme.Brand.Part], mark: BrandMarkChoice = .letter) {
        self.name = name
        self.mark = mark
        var out: [BrandStyle] = []
        for part in parts {
            let colour = part.color ?? ResolvedTheme.BrandColour(kind: part.accent == true ? "accent" : "fg")
            out += Array(repeating: BrandStyle(colour: colour, bold: part.bold == true), count: part.text.unicodeScalars.count)
        }
        let want = (name.isEmpty ? Self.defaultName : name).unicodeScalars.count
        if out.count != want { out = Array(repeating: .plain, count: want) }
        styles = out
    }

    /// The server's quick colouring for a name nobody has coloured: the odd words (Witty, Media, Server: the middle one) in the
    /// accent.
    public init(name: String) {
        self.name = name
        mark = .letter
        styles = []
        styles = Self.preset(.accentOnMedia, for: shown)
    }

    // MARK: Editing

    /// A name changed: the letters that were already there keep their colours, and what is new takes the colour of the
    /// letter before it.
    public mutating func rename(_ new: String) {
        let trimmed = String(String.UnicodeScalarView(new.unicodeScalars.prefix(Self.maxRunes)))
        let old = styles
        name = trimmed
        let count = shown.unicodeScalars.count
        var next = Array(old.prefix(count))
        while next.count < count { next.append(next.last ?? .plain) }
        styles = next
    }

    /// Draws `range` (letter offsets) in a colour, and bold or not.
    public mutating func apply(_ colour: ResolvedTheme.BrandColour, bold: Bool? = nil, to range: Range<Int>) {
        for i in range where styles.indices.contains(i) {
            styles[i].colour = colour
            if let bold { styles[i].bold = bold }
        }
    }

    public mutating func setBold(_ bold: Bool, in range: Range<Int>) {
        for i in range where styles.indices.contains(i) { styles[i].bold = bold }
    }

    /// Every letter drawn as one of the presets says.
    public mutating func use(_ preset: Preset) { styles = Self.preset(preset, for: shown) }

    public enum Preset: String, CaseIterable, Sendable {
        case accentOnMedia, twoTone, oneColour, plain, rainbow, gradient

        public var title: String {
            switch self {
            case .accentOnMedia: return "Accent on \"Media\""
            case .twoTone: return "Two-tone"
            case .oneColour: return "One colour"
            case .plain: return "Plain"
            case .rainbow: return "Rainbow letters"
            case .gradient: return "Gradient"
            }
        }
    }

    /// The styles a preset gives each letter of a name.
    public static func preset(_ preset: Preset, for name: String) -> [BrandStyle] {
        let count = name.unicodeScalars.count
        func all(_ s: BrandStyle) -> [BrandStyle] { Array(repeating: s, count: count) }
        switch preset {
        case .plain: return all(.plain)
        case .oneColour: return all(BrandStyle(colour: .init(kind: "accent")))
        case .accentOnMedia:
            var out = all(.plain)
            for (n, w) in BrandWords.ranges(name).enumerated() where n % 2 == 1 {
                for i in w { out[i] = BrandStyle(colour: .init(kind: "accent")) }
            }
            return out
        case .twoTone:
            // The first half of the words in the text colour, the rest in the accent.
            var out = all(.plain)
            let words = BrandWords.ranges(name)
            for (n, w) in words.enumerated() where n >= (words.count + 1) / 2 {
                for i in w { out[i] = BrandStyle(colour: .init(kind: "accent")) }
            }
            return out
        case .rainbow:
            var out = all(.plain)
            var n = 0
            let letters = Array(name.unicodeScalars)
            let coloured = letters.filter { !$0.properties.isWhitespace }.count
            for (i, c) in letters.enumerated() where !c.properties.isWhitespace {
                out[i] = BrandStyle(colour: .init(kind: "static", hex: hue(Double(n) / Double(max(1, coloured)))), bold: true)
                n += 1
            }
            return out
        case .gradient:
            return all(BrandStyle(colour: .init(kind: "gradient", stops: ["#1e9be0", "#3aa84a"], angle: 90), bold: true))
        }
    }

    /// A vivid colour round the wheel, for rainbow letters.
    static func hue(_ t: Double) -> String {
        let h = t * 360, s = 0.85, v = 0.95
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h / 60) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return ThemeColour(red: r + m, green: g + m, blue: b + m).hex
    }

    // MARK: What is saved

    /// The colour changes as the server wants them: runs of letters in one style, letters in the theme's own text colour left out.
    public var spans: [BrandSpan] {
        var out: [BrandSpan] = []
        var i = 0
        while i < styles.count {
            var j = i + 1
            while j < styles.count, styles[j] == styles[i] { j += 1 }
            if styles[i] != .plain { out.append(BrandSpan(from: i, to: j, color: styles[i].colour, bold: styles[i].bold ? true : nil)) }
            i = j
        }
        return out
    }

    /// What is wrong with it, in words, before it is sent: the server's limits.
    public var problems: [String] {
        var out: [String] = []
        if name.unicodeScalars.count > Self.maxRunes { out.append("The name can be at most \(Self.maxRunes) characters.") }
        if spans.count > Self.maxSpans {
            out.append("The name has \(spans.count) colour changes; the most is \(Self.maxSpans). Colour longer runs, or use a gradient.")
        }
        for span in spans {
            if span.color.kind == "static", ThemeColour(hex: span.color.hex ?? "") == nil || (span.color.hex ?? "").count != 7 {
                out.append("A fixed colour is written #rrggbb.")
                break
            }
            if span.color.kind == "gradient", (span.color.stops ?? []).count < 2 || (span.color.stops ?? []).count > 4 {
                out.append("A gradient has two to four stops.")
                break
            }
        }
        if mark.kind == "text", BrandMarkChoice.custom(mark.text ?? "") == nil { out.append("Your own mark is one or two characters.") }
        return out
    }

    /// The settings to save (`PUT /settings`): the name, the quick colouring left at automatic since the spans win, the spans as
    /// JSON and the mark.
    public func settings() throws -> [String: String] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let spans = try String(decoding: encoder.encode(self.spans), as: UTF8.self)
        let mark = try String(decoding: encoder.encode(self.mark), as: UTF8.self)
        return ["brandName": name, "brandColouring": "auto", "brandSpans": self.spans.isEmpty ? "" : spans, "brandMark": mark]
    }

    /// The parts to draw, as the theme engine hands them out: runs of letters in one style.
    public var parts: [ResolvedTheme.Brand.Part] {
        let letters = Array(shown.unicodeScalars)
        var out: [ResolvedTheme.Brand.Part] = []
        var start = 0
        while start < letters.count {
            var end = start + 1
            while end < letters.count, styles[end] == styles[start] { end += 1 }
            let style = styles[start]
            out.append(.init(text: String(String.UnicodeScalarView(letters[start..<end])), accent: style.colour.kind == "accent", color: style.colour, bold: style.bold ? true : nil))
            start = end
        }
        return out
    }
}

/// Whether the name can be read on the surfaces it is drawn on: the page, the panel and a card, in a theme's colours.
public enum BrandContrast {
    public struct Warning: Equatable, Sendable {
        public let text: String
        public let surface: String
        public let ratio: Double
        public let need: Double

        /// "“Media” is 2.1 to 1 on the page in Aero Day; it needs 4.5."
        public func words(theme: String) -> String {
            "“\(text)” is \(String(format: "%.1f", ratio)) to 1 on \(surface) in \(theme); it needs \(String(format: "%.1f", need))."
        }
    }

    public static let need = 4.5

    /// The colours (or the stops) a letter is drawn in, in a theme's tokens.
    static func colours(_ colour: ResolvedTheme.BrandColour, colors: [String: String]) -> [ThemeColour] {
        func hex(_ key: String, _ fallback: String) -> ThemeColour { colors[key].flatMap(ThemeColour.init(hex:)) ?? ThemeColour(hex: fallback)! }
        switch colour.kind {
        case "accent": return [colors["brandAccent"].flatMap(ThemeColour.init(hex:)) ?? hex("accentText", "#ffffff")]
        case "token": return [colour.token.flatMap { colors[$0] }.flatMap(ThemeColour.init(hex:)) ?? hex("fg", "#ffffff")]
        case "static": return [colour.hex.flatMap(ThemeColour.init(hex:)) ?? hex("fg", "#ffffff")]
        case "gradient": return (colour.stops ?? []).compactMap(ThemeColour.init(hex:))
        default: return [hex("fg", "#ffffff")]
        }
    }

    /// Each run of the name drawn in a colour that reads under 4.5 to 1 on a surface, worst first, for one theme's `colors`.
    /// The surfaces: the page (`bg`), the panel (`bg2`) and cards (`bg3`).
    public static func warnings(_ draft: BrandDraft, colors: [String: String]) -> [Warning] {
        let surfaces: [(String, String)] = [("the page", "bg"), ("a panel", "bg2"), ("a card", "bg3")]
        var out: [Warning] = []
        for part in draft.parts {
            let inks = colours(part.color ?? .init(kind: "fg"), colors: colors)
            guard !part.text.allSatisfy(\.isWhitespace), !inks.isEmpty else { continue }
            for (label, token) in surfaces {
                guard let surface = colors[token].flatMap(ThemeColour.init(hex:)) else { continue }
                let ground = surface.over(.black)
                let worst = inks.map { $0.over(ground).contrast(with: ground) }.min() ?? 21
                if worst < need { out.append(Warning(text: part.text.trimmingCharacters(in: .whitespaces), surface: label, ratio: worst, need: need)) }
            }
        }
        return out.sorted { $0.ratio < $1.ratio }
    }
}
