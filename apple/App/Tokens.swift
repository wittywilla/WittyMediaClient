import SwiftUI
import WittyKit

/// The server's design tokens (themes/tokens.json, explained in its docs/DESIGN.md) as this app uses
/// them. Sizes that are pixels there are points here. Text isn't sized from here: text styles follow
/// Dynamic Type, and on Apple TV they're already sized for the sofa.
enum Tokens {
    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s10: CGFloat = 40
        static let s12: CGFloat = 48
        static let s16: CGFloat = 64
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }

    enum Motion {
        static let press = 0.09
        static let focus = 0.15
        static let appear = 0.24
    }

    #if os(tvOS)
    /// Apple's safe area for a TV that may crop its picture. Rows run under it so that a lifted
    /// card isn't cut off, and everything in them starts inside it.
    static let gutter: CGFloat = 90
    static let edge: CGFloat = 60
    static let cardWidth: CGFloat = 200
    static let wideCardWidth: CGFloat = 340
    static let minTarget: CGFloat = 48
    /// The room a focused card needs to lift without being clipped.
    static let focusRoom: CGFloat = 32
    static let heroHeight: CGFloat = 620
    #elseif os(macOS)
    static let gutter: CGFloat = 24
    static let edge: CGFloat = 16
    static let cardWidth: CGFloat = 148
    static let wideCardWidth: CGFloat = 260
    static let minTarget: CGFloat = 24
    static let focusRoom: CGFloat = 8
    static let heroHeight: CGFloat = 420
    #else
    static let gutter: CGFloat = 16
    static let edge: CGFloat = 8
    static let cardWidth: CGFloat = 132
    static let wideCardWidth: CGFloat = 260
    static let minTarget: CGFloat = 44
    static let focusRoom: CGFloat = 4
    static let heroHeight: CGFloat = 420
    #endif

    /// The width of a poster on the phone-sized hero.
    static let heroPosterWidth: CGFloat = 240
}

extension Font {
    /// The title over a picture.
    static let wmDisplay = Font.largeTitle.weight(.bold)
    /// The one heading of a page.
    static let wmPage = Font.title2.weight(.semibold)
    /// Above a row of cards.
    static let wmSection = Font.headline
    static let wmCard = Font.footnote
    static let wmCardSub = Font.caption
}

/// The theme's colours, ready to use. Plain data until now, in shared/data/themes.json.
struct Palette {
    var background, panel, card, border, text, textSecondary, textHint, accent, onAccent, accentText, danger, ok: Color

    init(_ colours: SharedData.ThemeColours?) {
        func colour(_ text: String?, _ fallback: String) -> Color { Color(hex: text ?? fallback) }
        background = colour(colours?.background, "#101114")
        panel = colour(colours?.panel, "#17191e")
        card = colour(colours?.card, "#20232a")
        border = colour(colours?.border, "#2b2f38")
        self.text = colour(colours?.text, "#ececf1")
        textSecondary = colour(colours?.textSecondary, "#a8adb9")
        textHint = colour(colours?.textHint, "#858a99")
        accent = colour(colours?.accent, "#e4e6eb")
        onAccent = colour(colours?.onAccent, "#111214")
        accentText = colour(colours?.accentText, "#e4e6eb")
        danger = colour(colours?.danger, "#ff5c6c")
        ok = colour(colours?.ok, "#3ad29f")
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(nil)
}

private struct ClientKey: EnvironmentKey {
    static let defaultValue = WittyClient(base: "")
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    /// The connection in use. Screens that only draw pictures read this rather than the whole
    /// model, so they aren't redrawn every time something else in the app changes.
    var client: WittyClient {
        get { self[ClientKey.self] }
        set { self[ClientKey.self] = newValue }
    }
}

extension Color {
    /// `#rgb`, `#rrggbb` or `#rrggbbaa`. Anything else is mid grey, so a bad value can't hide text.
    init(hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        let value = digits.count == 6 || digits.count == 8 ? UInt64(digits, radix: 16) : nil
        let full = value.map { digits.count == 8 ? $0 : $0 << 8 | 0xff } ?? 0x808080ff
        self.init(.sRGB,
                  red: Double((full >> 24) & 0xff) / 255,
                  green: Double((full >> 16) & 0xff) / 255,
                  blue: Double((full >> 8) & 0xff) / 255,
                  opacity: Double(full & 0xff) / 255)
    }
}
