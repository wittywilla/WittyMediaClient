// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// The device profile a page was fitted to: the numbers a renderer lays out with. Sizes are points;
/// `scale` is pixels per point and only chooses pictures. The server's docs/SDUI.md, "Units, sizes and breakpoints".
public struct SDUILayout: Codable, Equatable, Sendable {
    public struct Size: Codable, Equatable, Hashable, Sendable {
        public var width: Int
        public var height: Int
        public init(width: Int = 0, height: Int = 0) {
            self.width = width
            self.height = height
        }
    }

    public struct Insets: Codable, Equatable, Sendable {
        public var top: Int
        public var right: Int
        public var bottom: Int
        public var left: Int
        public init(top: Int = 0, right: Int = 0, bottom: Int = 0, left: Int = 0) {
            self.top = top
            self.right = right
            self.bottom = bottom
            self.left = left
        }
        public var isZero: Bool { top == 0 && right == 0 && bottom == 0 && left == 0 }
    }

    public struct CardMetrics: Codable, Equatable, Sendable {
        public var shape: String?
        public var aspect: String?
        public var width: [String: Int]?
        /// How many medium cards a television's grid has; absent elsewhere.
        public var columns: Int?
    }

    public struct Budget: Codable, Equatable, Sendable {
        public var maxSections: Int?
        public var eagerSections: Int?
        public var shelfItems: Int?
        public var gridItems: Int?
        public var listItems: Int?
        public var pageSize: Int?
        public var heroItems: Int?
        public var repeats: Int?
    }

    public struct TextLimits: Codable, Equatable, Sendable {
        public var title: Int?
        public var subtitle: Int?
        public var synopsis: Int?
        public var overview: Int?
    }

    public var formFactor: String
    public var deviceClass: String?
    public var canvas: Size?
    public var scale: Int
    public var breakpoint: String
    public var safeArea: Insets
    public var focusEngine: Bool
    public var density: String
    public var spacing: [String: Int]
    public var text: [String: Int]
    public var cards: [String: CardMetrics]
    public var hero: Size?
    public var imageWidths: [Int]
    public var budget: Budget?
    public var textLimits: TextLimits?
    public var externalLinks: Bool?
    public var reducedMotion: Bool?
    public var truncated: Bool?
    /// The frame the app draws around the page: the layout option chosen and its menu (docs/SDUI.md, Layout options).
    public var shell: SDUIShell?
    /// How much of the next card or slide shows at a scrolling row's trailing edge (catalogue revision 3).
    public var peek: Double = 0
    /// Where a page's Dock goes and how tall it is (catalogue revision 3).
    public var dock: SDUIDockMetrics?

    enum CodingKeys: String, CodingKey {
        case formFactor, canvas, scale, breakpoint, safeArea, focusEngine, density, spacing, text, cards, hero
        case imageWidths, budget, textLimits, externalLinks, reducedMotion, truncated, shell, peek, dock
        case deviceClass = "class"
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        formFactor = (try? box.decodeIfPresent(String.self, forKey: .formFactor)) ?? "phone"
        deviceClass = try? box.decodeIfPresent(String.self, forKey: .deviceClass)
        canvas = try? box.decodeIfPresent(Size.self, forKey: .canvas)
        scale = (try? box.decodeIfPresent(Int.self, forKey: .scale)) ?? 2
        breakpoint = (try? box.decodeIfPresent(String.self, forKey: .breakpoint)) ?? "compact"
        safeArea = (try? box.decodeIfPresent(Insets.self, forKey: .safeArea)) ?? Insets()
        focusEngine = (try? box.decodeIfPresent(Bool.self, forKey: .focusEngine)) ?? false
        density = (try? box.decodeIfPresent(String.self, forKey: .density)) ?? "comfortable"
        spacing = (try? box.decodeIfPresent([String: Int].self, forKey: .spacing)) ?? SDUILayout.fallback.spacing
        text = (try? box.decodeIfPresent([String: Int].self, forKey: .text)) ?? SDUILayout.fallback.text
        cards = (try? box.decodeIfPresent([String: CardMetrics].self, forKey: .cards)) ?? [:]
        hero = try? box.decodeIfPresent(Size.self, forKey: .hero)
        imageWidths = (try? box.decodeIfPresent([Int].self, forKey: .imageWidths)) ?? SDUILayout.fallback.imageWidths
        budget = try? box.decodeIfPresent(Budget.self, forKey: .budget)
        textLimits = try? box.decodeIfPresent(TextLimits.self, forKey: .textLimits)
        externalLinks = try? box.decodeIfPresent(Bool.self, forKey: .externalLinks)
        reducedMotion = try? box.decodeIfPresent(Bool.self, forKey: .reducedMotion)
        truncated = try? box.decodeIfPresent(Bool.self, forKey: .truncated)
        shell = try? box.decodeIfPresent(SDUIShell.self, forKey: .shell)
        peek = (try? box.decodeIfPresent(Double.self, forKey: .peek)) ?? 0
        dock = try? box.decodeIfPresent(SDUIDockMetrics.self, forKey: .dock)
    }

    public init(formFactor: String, deviceClass: String? = nil, canvas: Size? = nil, scale: Int, breakpoint: String,
                safeArea: Insets = Insets(), focusEngine: Bool = false, density: String = "comfortable",
                spacing: [String: Int], text: [String: Int], cards: [String: CardMetrics] = [:], hero: Size? = nil,
                imageWidths: [Int] = [120, 160, 240, 320, 480, 640, 960, 1280, 1920, 2560, 3840], budget: Budget? = nil) {
        self.formFactor = formFactor
        self.deviceClass = deviceClass
        self.canvas = canvas
        self.scale = scale
        self.breakpoint = breakpoint
        self.safeArea = safeArea
        self.focusEngine = focusEngine
        self.density = density
        self.spacing = spacing
        self.text = text
        self.cards = cards
        self.hero = hero
        self.imageWidths = imageWidths
        self.budget = budget
    }

    /// What a page without a layout is laid out with: a phone's. A real page always carries its own.
    public static let fallback = SDUILayout(formFactor: "phone", scale: 3, breakpoint: "compact",
                                            spacing: ["none": 0, "xs": 4, "s": 8, "m": 16, "l": 24, "xl": 40],
                                            text: ["pageTitle": 28, "heading": 22, "title": 17, "body": 16, "caption": 13])

    public var isTV: Bool { formFactor == "tv" }

    /// A spacing step in points. A step this app doesn't know is the middle one.
    public func space(_ step: String) -> Int { spacing[step] ?? spacing["m"] ?? 16 }

    /// A text role's size in points at the default text size.
    public func textSize(_ role: String) -> Int { text[role] ?? text["body"] ?? 16 }

    /// The distance between a page's sections: `l`, or `m` on a compact window.
    public var sectionGap: Int { breakpoint == "compact" ? space("m") : space("l") }

    /// The distance between cards in a row or a grid: `m`, or `s` + `xs` on a compact window.
    public var cardGap: Int { breakpoint == "compact" ? space("s") + space("xs") : space("m") }

    /// The side margin sections keep: the safe area on a television, `m` elsewhere.
    public var sideMargin: Int { safeArea.left + safeArea.right > 0 ? safeArea.left : space("m") }

    /// The width sections have to themselves. `window` is the real window's width where the app knows it;
    /// without it, the canvas the page was rendered for, or the breakpoint's usual window.
    public func contentWidth(window: Int? = nil) -> Int {
        var width = window ?? canvas?.width ?? 0
        if width <= 0 { width = ["compact": 390, "medium": 720, "expanded": 1024, "large": 1440][breakpoint] ?? 390 }
        if safeArea.left + safeArea.right > 0 { return width - safeArea.left - safeArea.right }
        return width - 2 * space("m")
    }

    /// How many grey placeholder cards a loading row of cards this wide shows: as many as are at least partly
    /// on screen, and no more than the row's first page.
    public func placeholders(cardWidth: Int, window: Int? = nil) -> Int {
        guard cardWidth > 0 else { return 0 }
        let gap = cardGap
        let count = (contentWidth(window: window) + gap) / (cardWidth + gap) + 1
        return max(1, min(count, budget?.shelfItems ?? count))
    }

    /// A grid's columns when the window has changed without crossing a breakpoint:
    /// `max(minimum, floor((content + gap) / (card + gap)))`. A television keeps the count it was sent.
    public func gridColumns(cardWidth: Int, sent: Int?, window: Int?) -> Int {
        if isTV || window == nil, let sent, sent > 0 { return sent }
        guard cardWidth > 0 else { return max(sent ?? 2, 1) }
        let gap = cardGap
        let minimum = cardWidth < 130 ? 3 : 2
        return max(minimum, (contentWidth(window: window) + gap) / (cardWidth + gap))
    }

    /// The width in pixels to ask for a picture drawn this many points wide: the smallest of the list that covers it.
    public func imageWidth(points: Int) -> Int {
        let want = points * max(scale, 1)
        return imageWidths.first { $0 >= want } ?? imageWidths.last ?? want
    }

    /// The breakpoint of a window this wide: compact under 600 points, medium under 840, expanded under 1200, large from there.
    public static func breakpoint(width: Double) -> String {
        if width < 600 { return "compact" }
        if width < 840 { return "medium" }
        if width < 1200 { return "expanded" }
        return "large"
    }

    /// "16/9" as width over height.
    public static func ratio(_ aspect: String) -> Double? {
        let parts = aspect.split(separator: "/")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        return w / h
    }

    /// Text cut to at most `limit` characters, the server's rule: at the last space within 20 characters of the
    /// limit when there is one, trailing spaces and punctuation removed, an ellipsis added.
    public static func truncate(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0 else { return trimmed }
        let scalars = Array(trimmed.unicodeScalars)
        guard scalars.count > limit else { return trimmed }
        var cut = limit - 1
        var i = cut
        while i > cut - 20 && i > 0 {
            if scalars[i] == " " {
                cut = i
                break
            }
            i -= 1
        }
        var kept = String(String.UnicodeScalarView(scalars[..<cut]))
        while let last = kept.last, " ,.;:-–—".contains(last) { kept.removeLast() }
        return kept + "…"
    }
}

/// A layout option's frame: which layout, the menu's style (`sidebar`, `rail`, `bottomTabs`, `topTabs`, `tvTopMenu`,
/// `tvSideMenu`), its breadth in points, whether the bar lies over the page until it scrolls, and how wide a TV's side
/// menu opens while it has focus.
public struct SDUIShell: Codable, Equatable, Sendable {
    public var layout: String
    public var nav: String
    public var overlay: Bool?
    public var size: Int
    public var open: Int?

    public init(layout: String, nav: String, overlay: Bool? = nil, size: Int, open: Int? = nil) {
        self.layout = layout
        self.nav = nav
        self.overlay = overlay
        self.size = size
        self.open = open
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? box.decodeIfPresent(String.self, forKey: .layout)) ?? ""
        nav = (try? box.decodeIfPresent(String.self, forKey: .nav)) ?? ""
        overlay = try? box.decodeIfPresent(Bool.self, forKey: .overlay)
        size = (try? box.decodeIfPresent(Int.self, forKey: .size)) ?? 0
        open = try? box.decodeIfPresent(Int.self, forKey: .open)
    }

    /// The menu styles this app draws. A style it doesn't know is drawn as the device's usual one.
    public static let navs: Set<String> = ["sidebar", "rail", "bottomTabs", "topTabs", "tvTopMenu", "tvSideMenu"]
}

/// `layout.dock`: `bottom`, a bar `height` points tall at the foot of the screen; or `sheet`, a phone's Options button
/// that opens the controls as a sheet. `hintSize` is the key legend's text size.
public struct SDUIDockMetrics: Codable, Equatable, Sendable {
    public var placement: String
    public var height: Int
    public var hintSize: Int

    public init(placement: String, height: Int = 0, hintSize: Int = 0) {
        self.placement = placement
        self.height = height
        self.hintSize = hintSize
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        placement = (try? box.decodeIfPresent(String.self, forKey: .placement)) ?? "bottom"
        height = (try? box.decodeIfPresent(Int.self, forKey: .height)) ?? 0
        hintSize = (try? box.decodeIfPresent(Int.self, forKey: .hintSize)) ?? 0
    }
}
