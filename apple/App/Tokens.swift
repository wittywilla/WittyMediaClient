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

    /// Corners follow the theme in use (its `radius`): docs/APP-DESIGN.md, Themes. Set by the model as the
    /// theme changes; everything that draws with them also reads the palette, so it's drawn again.
    enum Radius {
        static var theme: CGFloat = 10
        static var xs: CGFloat { max(2, theme - 6) }
        static var sm: CGFloat { max(2, theme - 4) }
        static var md: CGFloat { theme }
        static var lg: CGFloat { theme + 4 }
        static var xl: CGFloat { theme + 10 }
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
    /// How wide the hero's words may be: up to half the screen.
    static let heroTextWidth: CGFloat = 900
    #elseif os(macOS)
    static let gutter: CGFloat = 24
    static let edge: CGFloat = 16
    static let cardWidth: CGFloat = 148
    static let wideCardWidth: CGFloat = 260
    static let minTarget: CGFloat = 24
    static let focusRoom: CGFloat = 8
    static let heroHeight: CGFloat = 420
    static let heroTextWidth: CGFloat = 560
    #else
    static let gutter: CGFloat = 16
    static let edge: CGFloat = 8
    static let cardWidth: CGFloat = 132
    static let wideCardWidth: CGFloat = 260
    static let minTarget: CGFloat = 44
    static let focusRoom: CGFloat = 4
    static let heroHeight: CGFloat = 420
    static let heroTextWidth: CGFloat = 560
    #endif

    /// The width of a poster on the phone-sized hero.
    static let heroPosterWidth: CGFloat = 240
}

/// The Android app's type scale (ui/Theme.kt), as the nearest text styles, so it still follows the
/// person's own text size.
extension Font {
    /// The title over a wide picture (Android's displaySmall).
    static let wmDisplay = Font.title.weight(.bold)
    /// The title under the posters at the top of Home on a phone (headlineSmall).
    static let wmHero = Font.title3.weight(.semibold)
    /// The one heading of a page (headlineMedium).
    static let wmPage = Font.title2.weight(.semibold)
    /// Above a row of cards (titleMedium).
    static let wmSection = Font.headline
    /// A poster's title (titleSmall), and what's under it (bodySmall).
    static let wmCard = Font.subheadline.weight(.medium)
    static let wmCardSub = Font.caption
    /// Explanations and facts (bodyMedium).
    static let wmSecondary = Font.footnote
    /// The words on a button (labelLarge).
    static let wmLabel = Font.subheadline.weight(.medium)
}

/// The theme in use, translated from the server's tokens (WittyKit's `ThemeTranslator`), as colours to draw with.
struct Palette {
    var background, panel, card, raised, border, control, text, textSecondary, textHint: Color
    var accent, accentPressed, onAccent, accentText, danger, ok, warn, scrim: Color
    var isLight: Bool

    init(_ theme: AppTheme) {
        func colour(_ c: ThemeColour) -> Color { Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha) }
        background = colour(theme.background)
        panel = colour(theme.panel)
        card = colour(theme.card)
        raised = colour(theme.raised)
        border = colour(theme.border)
        control = colour(theme.control)
        self.text = colour(theme.text)
        textSecondary = colour(theme.textSecondary)
        textHint = colour(theme.textHint)
        accent = colour(theme.accent)
        accentPressed = colour(theme.accentPressed)
        onAccent = colour(theme.onAccent)
        accentText = colour(theme.accentText)
        danger = colour(theme.danger)
        ok = colour(theme.ok)
        warn = colour(theme.warn)
        scrim = colour(theme.scrim)
        isLight = theme.isLight
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette(SharedData.appTheme("default"))
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
