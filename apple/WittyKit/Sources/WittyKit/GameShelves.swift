import Foundation

// Shelves: the games home (docs/WITTYPLAY-EXPERIENCE.md). Each console is a shelf, and its games
// stand on it as cases, cartridges or spines. What a console's case and cartridge are, its era and
// its years come from the server (`/games/consoles`: `era`, `launched`, `ended`, `media`, `shelf`);
// for a server that doesn't send them yet, the same tables as WittyPlay's (`game_traits.go`) are here.
// The rules for drawing them are the website's (`web/src/pages/games/GameShelves.tsx`), so both draw the
// same shelves. Nothing here is a console maker's: plain shapes in each console's proportions.

/// One kind of thing a game stands on a shelf as: its case (`box`, `clamshell`, `jewel`, `keep`)
/// or its cartridge (`cart`, `card`, `disc`). `aspect` is the front's width over its height;
/// `height` how tall it stands beside others of its kind (a full-size box is 1).
public struct ShelfShape: Codable, Equatable, Hashable {
    public let kind: String
    public let aspect: Double
    public let height: Double

    public init(kind: String, aspect: Double, height: Double) {
        self.kind = kind
        self.aspect = aspect
        self.height = height
    }
}

/// A console's case and cartridge.
public struct ShelfLook: Codable, Equatable, Hashable {
    public let caseShape: ShelfShape
    public let cart: ShelfShape

    enum CodingKeys: String, CodingKey {
        case caseShape = "case"
        case cart
    }

    public init(caseShape: ShelfShape, cart: ShelfShape) {
        self.caseShape = caseShape
        self.cart = cart
    }
}

/// How games stand on the shelves, this device's choice.
public enum ShelfView: String, CaseIterable, Identifiable {
    case cases, carts, spines

    public var id: String { rawValue }
    /// `wpViewCases`, `wpViewCartridges`, `wpViewShelf`.
    public var label: String {
        switch self {
        case .cases: return "Cases"
        case .carts: return "Cartridges"
        case .spines: return "Shelf"
        }
    }

    public static let storageKey = "wittyplay.shelfView"

    /// The remembered choice, Cases unless another was chosen.
    public static func saved(_ defaults: UserDefaults = .standard) -> ShelfView {
        ShelfView(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .cases
    }

    public func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.storageKey) }
}

/// A console's era, years and media, as WittyPlay's console table has them.
public struct ConsoleTraits: Equatable {
    public let era: String
    public let launched: Int
    public let ended: Int
    /// `cart`, `pocket` or `disc`.
    public let media: String
}

public enum GameShelves {
    // MARK: Eras

    /// Eras oldest first, with their names (`wpEras`).
    public static let eras = ["first", "8-bit", "16-bit", "early-3d", "disc", "pocket"]
    public static let eraNames: [String: String] = [
        "first": "The first consoles", "8-bit": "8-bit", "16-bit": "16-bit", "early-3d": "Early 3D", "disc": "Disc era", "pocket": "Pocket",
    ]
    /// The grain behind a console's spines and band: the size of its era's pixel, in points.
    public static let eraGrain: [String: Double] = ["first": 14, "8-bit": 12, "16-bit": 10, "early-3d": 6, "disc": 5, "pocket": 7]

    /// WittyPlay's console table, for a server that doesn't send it yet.
    public static let traits: [String: ConsoleTraits] = [
        "a2600": .init(era: "first", launched: 1977, ended: 1992, media: "cart"),
        "a7800": .init(era: "8-bit", launched: 1986, ended: 1992, media: "cart"),
        "nes": .init(era: "8-bit", launched: 1983, ended: 1995, media: "cart"),
        "sms": .init(era: "8-bit", launched: 1985, ended: 1992, media: "cart"),
        "snes": .init(era: "16-bit", launched: 1990, ended: 2003, media: "cart"),
        "md": .init(era: "16-bit", launched: 1988, ended: 1997, media: "cart"),
        "pce": .init(era: "16-bit", launched: 1987, ended: 1994, media: "cart"),
        "gb": .init(era: "pocket", launched: 1989, ended: 2003, media: "pocket"),
        "gba": .init(era: "pocket", launched: 2001, ended: 2010, media: "pocket"),
        "gg": .init(era: "pocket", launched: 1990, ended: 1997, media: "pocket"),
        "lynx": .init(era: "pocket", launched: 1989, ended: 1995, media: "pocket"),
        "ws": .init(era: "pocket", launched: 1999, ended: 2003, media: "pocket"),
        "ngp": .init(era: "pocket", launched: 1998, ended: 2001, media: "pocket"),
        "vb": .init(era: "pocket", launched: 1995, ended: 1996, media: "pocket"),
        "n64": .init(era: "early-3d", launched: 1996, ended: 2002, media: "cart"),
        "ps1": .init(era: "early-3d", launched: 1994, ended: 2006, media: "disc"),
        "dc": .init(era: "disc", launched: 1998, ended: 2001, media: "disc"),
        "ps2": .init(era: "disc", launched: 2000, ended: 2013, media: "disc"),
        "psp": .init(era: "pocket", launched: 2004, ended: 2014, media: "pocket"),
        "nds": .init(era: "pocket", launched: 2004, ended: 2014, media: "pocket"),
        "3ds": .init(era: "pocket", launched: 2011, ended: 2020, media: "pocket"),
    ]

    /// WittyPlay's cases and cartridges, for a server that doesn't send `shelf` yet.
    public static let looks: [String: ShelfLook] = {
        func l(_ ck: String, _ ca: Double, _ ch: Double, _ tk: String, _ ta: Double, _ th: Double) -> ShelfLook {
            ShelfLook(caseShape: ShelfShape(kind: ck, aspect: ca, height: ch), cart: ShelfShape(kind: tk, aspect: ta, height: th))
        }
        return [
            "a2600": l("box", 0.72, 1, "cart", 0.85, 0.75), "a7800": l("box", 0.72, 1, "cart", 0.85, 0.75),
            "nes": l("box", 0.71, 1, "cart", 0.89, 1), "sms": l("clamshell", 0.71, 1, "cart", 0.8, 0.85),
            "snes": l("box", 1.39, 0.68, "cart", 1.18, 0.82), "md": l("clamshell", 0.71, 1, "cart", 0.83, 0.88),
            "pce": l("jewel", 1, 0.66, "card", 1.58, 0.45), "gb": l("box", 0.96, 0.6, "cart", 0.88, 0.5),
            "gba": l("box", 0.96, 0.6, "cart", 1.6, 0.45), "gg": l("clamshell", 0.75, 0.75, "cart", 1.28, 0.5),
            "lynx": l("box", 0.96, 0.6, "card", 1.4, 0.45), "ws": l("box", 0.96, 0.6, "cart", 1.4, 0.45),
            "ngp": l("box", 0.96, 0.6, "cart", 1.3, 0.45), "vb": l("box", 1.39, 0.68, "cart", 0.9, 0.7),
            "n64": l("box", 1.39, 0.68, "cart", 1.12, 0.78), "ps1": l("jewel", 1, 0.66, "disc", 1, 0.66),
            "dc": l("jewel", 1, 0.66, "disc", 1, 0.66), "ps2": l("keep", 0.71, 1, "disc", 1, 0.66),
            "psp": l("keep", 0.58, 0.95, "disc", 1, 0.45), "nds": l("keep", 0.91, 0.72, "card", 0.94, 0.45),
            "3ds": l("keep", 0.91, 0.72, "card", 0.94, 0.45),
        ]
    }()

    public static func era(_ console: GameConsole?) -> String? {
        guard let console else { return nil }
        return console.era ?? traits[console.id]?.era
    }

    public static func media(_ console: GameConsole?) -> String {
        guard let console else { return "cart" }
        return console.media ?? traits[console.id]?.media ?? "cart"
    }

    /// Its case: the server's, else WittyPlay's table, else a box, or a keep case for a disc console.
    public static func caseShape(_ console: GameConsole?) -> ShelfShape {
        if let s = console?.shelf?.caseShape { return s }
        if let id = console?.id, let s = looks[id]?.caseShape { return s }
        return media(console) == "disc" ? ShelfShape(kind: "keep", aspect: 0.71, height: 1) : ShelfShape(kind: "box", aspect: 0.72, height: 1)
    }

    /// Its cartridge, card or disc, the same way.
    public static func cartShape(_ console: GameConsole?) -> ShelfShape {
        if let s = console?.shelf?.cart { return s }
        if let id = console?.id, let s = looks[id]?.cart { return s }
        return media(console) == "disc" ? ShelfShape(kind: "disc", aspect: 1, height: 0.66) : ShelfShape(kind: "cart", aspect: 0.88, height: 0.85)
    }

    // MARK: Spines

    /// A spine's width at phone size: 34, and up to 14 more by the title's length.
    public static func spineWidth(title: String) -> Double { 34 + min(14, (Double(title.utf16.count) * 0.55).rounded()) }

    /// The short name on a spine's foot: the console's own short name when it fits, else its id.
    public static func footName(_ console: GameConsole?) -> String {
        guard let console else { return "" }
        let short = console.shortName
        if short.count <= 5 { return short }
        var id = console.id
        if id.hasPrefix("custom-") { id.removeFirst("custom-".count) }
        return String(id.uppercased().prefix(4))
    }

    /// A title's letter for the dividers: A to Z, or # for anything else.
    public static func initial(_ title: String) -> String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "#" }
        let l = String(first).uppercased()
        return l.count == 1 && ("A"..."Z").contains(l) ? l : "#"
    }

    /// The letters a shelf's dividers go before: the index of each game where a new letter starts.
    public static func dividers(_ titles: [String]) -> [Int: String] {
        var out: [Int: String] = [:]
        var last = ""
        for (i, t) in titles.enumerated() {
            let l = initial(t)
            if l != last { out[i] = l }
            last = l
        }
        return out
    }

    // MARK: A cover's colour

    /// A cover's main colour from a small copy (RGBA bytes), the colourful parts counting more, as
    /// hue (degrees) and saturation (0 to 1). A grey cover has saturation 0; no pixels, nil.
    public static func tint(rgba: [UInt8]) -> (hue: Double, saturation: Double)? {
        var r = 0.0, g = 0.0, b = 0.0, w = 0.0
        var i = 0
        while i + 3 < rgba.count {
            let pr = Double(rgba[i]), pg = Double(rgba[i + 1]), pb = Double(rgba[i + 2])
            let k = 1 + (max(pr, pg, pb) - min(pr, pg, pb)) / 255 * 6
            r += pr * k; g += pg * k; b += pb * k; w += k
            i += 4
        }
        guard w > 0 else { return nil }
        return hueSaturation(r / w, g / w, b / w)
    }

    static func hueSaturation(_ r255: Double, _ g255: Double, _ b255: Double) -> (hue: Double, saturation: Double)? {
        let r = r255 / 255, g = g255 / 255, b = b255 / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        guard d > 0 else { return (0, 0) }
        let s = d / (1 - abs(2 * l - 1))
        let h: Double
        if mx == r { h = ((g - b) / d + 6).truncatingRemainder(dividingBy: 6) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        return ((h * 60).rounded(), s)
    }

    /// A game with no picture still gets a colour of its own, from its title, as the website's.
    public static func titleHue(_ title: String) -> Double {
        // JavaScript's `charCodeAt(0)` of each character: its first UTF-16 unit.
        var h: UInt32 = 0
        for scalar in title.unicodeScalars {
            let v = scalar.value
            let unit = v > 0xFFFF ? 0xD800 + ((v - 0x10000) >> 10) : v
            h = h &* 31 &+ unit
        }
        return Double(h % 360)
    }

    /// The deep colour of a spine or a band, as hue, saturation and lightness: at least 38%
    /// saturation and 30% lightness, whatever the theme, so they read as objects on a shelf.
    public static func deepColour(tint: (hue: Double, saturation: Double)?, title: String) -> (hue: Double, saturation: Double, lightness: Double) {
        guard let tint else { return (titleHue(title), 0.40, 0.30) }
        return (tint.hue, (max(tint.saturation, 0.38) * 100).rounded() / 100, 0.30)
    }
}
