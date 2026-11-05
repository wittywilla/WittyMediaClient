#if os(tvOS)
import SwiftUI
import UIKit
import WittyKit

// How each WittyTV theme is dressed on Apple TV. The server's page draws its themes with CSS
// (web/src/pages/tv/tv.css for what they share, tvthemes.css for each shape); this is the same, as
// the page works it out on a 1920 by 1080 TV in big screen mode, where a rem is 20 points. Colours
// come from WittyKit's TvLook, which works them out as tvThemes.ts does.

/// The look's colours, ready to draw with.
struct TvPaint {
    let bg, panel, panel2, head, ch, dim, line, text, soft: Color
    let cell, cell2, cellText, cellSoft, live, live2, liveText, liveSoft: Color
    let hi, hiText, accent, accentText, keyA, keyB, keyC, keyText, err, lite, shade: Color

    init(_ c: TvColours) {
        func k(_ hex: String) -> Color { Color(hex: hex) }
        bg = k(c.bg); panel = k(c.panel); panel2 = k(c.panel2); head = k(c.head); ch = k(c.ch); dim = k(c.dim); line = k(c.line); text = k(c.text); soft = k(c.soft)
        cell = k(c.cell); cell2 = k(c.cell2); cellText = k(c.cellText); cellSoft = k(c.cellSoft); live = k(c.live); live2 = k(c.live2); liveText = k(c.liveText); liveSoft = k(c.liveSoft)
        hi = k(c.hi); hiText = k(c.hiText); accent = k(c.accent); accentText = k(c.accentText); keyA = k(c.keyA); keyB = k(c.keyB); keyC = k(c.keyC); keyText = k(c.keyText)
        err = k(c.err); lite = k(c.lite); shade = k(c.shade)
    }
}

/// Everything a screen needs to draw a look: the choice, its colours and its shape's measures.
struct TvDress {
    let look: TvLookChoice
    let paint: TvPaint
    var shape: TvShape { look.shape }

    init(_ look: TvLookChoice) {
        self.look = look
        paint = TvPaint(look.colours)
    }

    // MARK: Type

    /// Which family the words are in: the shape's own, or what Custom chose.
    enum Family { case plain, narrow, din, mono, serif }

    var family: Family {
        switch look.font {
        case "system": return .plain
        case "narrow": return .narrow
        case "mono": return .mono
        case "serif": return .serif
        default:
            switch shape {
            case .box: return .narrow
            case .receiver: return .din
            case .teletext: return .mono
            case .listings: return .serif
            default: return .plain
            }
        }
    }

    private static let georgia = UIFont(name: "Georgia", size: 20) != nil
    private static let din = UIFont(name: "DINAlternate-Bold", size: 20) != nil

    /// Type at a size from the page, in its family. `digits` is the page's monospaced numbers.
    func font(_ size: CGFloat, _ weight: Font.Weight = .regular, digits: Bool = false) -> Font {
        if digits { return .system(size: size, weight: weight, design: .monospaced) }
        switch family {
        case .plain: return .system(size: size, weight: weight)
        case .narrow: return .system(size: size, weight: weight).width(.condensed)
        case .din: return Self.din ? .custom("DINAlternate-Bold", size: size) : .system(size: size, weight: weight).width(.compressed)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .serif: return Self.georgia ? .custom("Georgia", size: size).weight(weight) : .system(size: size, weight: weight, design: .serif)
        }
    }

    /// The page's `font-variant: small-caps`: small letters drawn as smaller capitals.
    func smallCaps(_ words: String, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Text {
        var out = Text("")
        var run = ""
        var small = false
        func flush() {
            guard !run.isEmpty else { return }
            out = out + Text(small ? run.uppercased() : run).font(font(small ? size * 0.78 : size, weight))
            run = ""
        }
        for ch in words {
            let lower = ch.isLowercase
            if lower != small { flush(); small = lower }
            run.append(ch)
        }
        flush()
        return out
    }

    /// Words in the shape's case: Newspaper's small capitals where the page has them, else as they are.
    func words(_ text: String, _ size: CGFloat, _ weight: Font.Weight = .regular, smallCaps: Bool) -> Text {
        smallCaps && shape == .listings ? self.smallCaps(text, size, weight) : Text(text).font(font(size, weight))
    }

    // MARK: Measures (CSS pixels at 1920 wide, which are Apple TV points)

    /// --ctv-top, --ctv-edge and --ctv-foot on a TV.
    let top: CGFloat = 59
    let edge: CGFloat = 96
    let foot: CGFloat = 54

    /// --ctv-r: the theme's corners.
    var radius: CGFloat {
        switch shape {
        case .box: return 3
        case .modern, .cinema: return 6
        case .receiver, .teletext, .listings: return 0
        case .outline: return 10
        case .compact: return 4
        }
    }

    /// The channel column.
    var channelWidth: CGFloat { shape == .compact ? 220 : shape == .cinema ? 240 : 300 }

    var rowHeight: CGFloat { CGFloat(TvLook.rowHeight(shape, width: 1920, density: look.density)) }

    /// The words of a cell: its title, then the line under it.
    var cellTitle: (size: CGFloat, weight: Font.Weight) {
        switch shape {
        case .box, .modern, .listings: return (18.75, .bold)
        case .receiver: return (17.5, .medium)
        case .teletext: return (17.5, .regular)
        case .cinema: return (25, .bold)
        case .outline: return (18.75, .medium)
        case .compact: return (17.5, .semibold)
        }
    }

    var cellSmall: CGFloat { [.modern, .listings, .compact].contains(shape) ? 16.25 : 21.25 }

    var number: (size: CGFloat, weight: Font.Weight) {
        switch shape {
        case .box, .modern: return (21.25, .bold)
        case .receiver: return (30, .regular)
        case .teletext, .listings, .outline: return (30, .regular)
        case .cinema: return (17.5, .bold)
        case .compact: return (15, .bold)
        }
    }

    var name: (size: CGFloat, weight: Font.Weight) {
        switch shape {
        case .box: return (25, .bold)
        case .modern: return (18.75, .heavy)
        case .receiver: return (16.25, .medium)
        case .teletext: return (16.25, .regular)
        case .listings: return (25, .bold)
        case .cinema: return (16.25, .bold)
        case .outline: return (25, .medium)
        case .compact: return (17.5, .semibold)
        }
    }

    var logo: CGSize {
        switch shape {
        case .modern: return CGSize(width: 104, height: 46)
        case .cinema: return CGSize(width: 72, height: 32)
        case .compact: return CGSize(width: 40, height: 24)
        default: return CGSize(width: 72, height: 46)
        }
    }

    var heroLogo: CGSize {
        switch shape {
        case .modern: return CGSize(width: 84, height: 40)
        case .compact: return CGSize(width: 40, height: 24)
        default: return CGSize(width: 54, height: 32)
        }
    }

    var timeSize: CGFloat { shape == .compact ? 16.25 : 25 }

    var heroTitle: (size: CGFloat, weight: Font.Weight) {
        switch shape {
        case .box: return (47.5, .bold)
        case .modern: return (54.7, .bold)
        case .receiver: return (47.5, .medium)
        case .teletext: return (37.5, .bold)
        case .listings, .cinema: return (60, .bold)
        case .outline: return (54.7, .light)
        case .compact: return (25, .bold)
        }
    }

    var heroNumber: (size: CGFloat, weight: Font.Weight) {
        switch shape {
        case .modern: return (30, .bold)
        case .receiver, .teletext: return (25, .regular)
        case .listings: return (25, .regular)
        case .outline: return (37.5, .light)
        case .compact: return (17.5, .bold)
        default: return (37.5, .bold)
        }
    }

    /// The facts under the title: the episode, times, what's next and the description.
    var heroFacts: CGFloat {
        switch shape {
        case .modern, .cinema, .outline: return 18.75
        case .compact: return 17.5
        default: return 25
        }
    }

    var heroChannel: CGFloat { shape == .compact ? 16.25 : 25 }

    var buttonText: (size: CGFloat, weight: Font.Weight) {
        switch shape {
        case .modern, .cinema: return (21.25, .semibold)
        case .receiver: return (16.25, .medium)
        case .teletext: return (16.25, .regular)
        case .listings: return (21.25, .regular)
        case .outline: return (21.25, .medium)
        case .compact: return (16.25, .semibold)
        case .box: return (21.25, .bold)
        }
    }

    /// The words the shape writes in capitals.
    var capitals: Bool { shape == .receiver || shape == .teletext }

    /// A raised edge, as a cable box drew everything.
    var bevel: Bool { shape == .box }

    /// The highlighted row's channel takes the highlight's colour.
    var rowHighlight: Bool { shape.rowHighlight }
}

// MARK: - Pieces

/// The cable box's raised edge: light along the top and left, dark along the bottom and right.
struct Bevel: View {
    var width: CGFloat = 2

    var body: some View {
        GeometryReader { box in
            Path { p in
                p.addRect(CGRect(x: 0, y: 0, width: box.size.width, height: width))
                p.addRect(CGRect(x: 0, y: 0, width: width, height: box.size.height))
            }
            .fill(Color.white.opacity(0.28))
            Path { p in
                p.addRect(CGRect(x: 0, y: box.size.height - width, width: box.size.width, height: width))
                p.addRect(CGRect(x: box.size.width - width, y: 0, width: width, height: box.size.height))
            }
            .fill(Color.black.opacity(0.45))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One edge of a box drawn as a rule, as the page's borders are.
struct Rule: View {
    enum Edge { case top, bottom, leading, trailing }
    let edge: Edge
    let colour: Color
    var width: CGFloat = 1

    var body: some View {
        switch edge {
        case .top: VStack(spacing: 0) { colour.frame(height: width); Spacer(minLength: 0) }
        case .bottom: VStack(spacing: 0) { Spacer(minLength: 0); colour.frame(height: width) }
        case .leading: HStack(spacing: 0) { colour.frame(width: width); Spacer(minLength: 0) }
        case .trailing: HStack(spacing: 0) { Spacer(minLength: 0); colour.frame(width: width) }
        }
    }
}

extension View {
    func rule(_ edge: Rule.Edge, _ colour: Color, _ width: CGFloat = 1) -> some View {
        overlay(Rule(edge: edge, colour: colour, width: width).allowsHitTesting(false))
    }

    /// Words as the shape writes them: in capitals with room between the letters, or as they are.
    @ViewBuilder func tvCase(_ on: Bool, tracking: CGFloat = 0) -> some View {
        if on { self.textCase(.uppercase).tracking(tracking) } else { self }
    }
}

/// The ring a focused thing gets on a TV: concentric with it, in the theme's text colour.
private struct FocusRing: ViewModifier {
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let focused: Bool
    let radius: CGFloat
    let colour: Color

    func body(content: Content) -> some View {
        content
            .padding(metrics.focusRing)
            .overlay {
                RoundedRectangle(cornerRadius: radius + metrics.focusRing, style: .continuous)
                    .strokeBorder(focused ? colour : .clear, lineWidth: metrics.focusRing)
            }
            .scaleEffect(focused && !reduceMotion ? metrics.focusScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: focused)
    }
}

extension View {
    func tvRing(_ focused: Bool, radius: CGFloat, colour: Color) -> some View {
        modifier(FocusRing(focused: focused, radius: radius, colour: colour))
    }
}

/// The page's `.ctv-btn`, in each shape's own style. `on` is the one the theme fills with its
/// highlight; focus fills any of them, and adds the TV's ring.
struct TvButtonStyle: ButtonStyle {
    enum Kind { case button, chip, link, icon }
    let dress: TvDress
    var kind: Kind = .button
    var on = false
    /// Teletext's bar is blue, and its buttons are black on it.
    var onBar = false

    func makeBody(configuration: Configuration) -> some View {
        TvButtonBody(label: configuration.label, pressed: configuration.isPressed, dress: dress, kind: kind, on: on, onBar: onBar)
    }
}

private struct TvButtonBody<Label: View>: View {
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    let label: Label
    let pressed: Bool
    let dress: TvDress
    let kind: TvButtonStyle.Kind
    let on: Bool
    let onBar: Bool

    private var round: Bool { (dress.shape == .modern || dress.shape == .outline) && kind != .link }

    private var radius: CGFloat {
        if round { return 24 }
        if dress.shape == .cinema, kind != .link { return 10 }
        return dress.radius
    }

    var body: some View {
        let p = dress.paint
        let lit = on || focused
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let words = dress.buttonText
        let chip = kind == .chip || kind == .link
        label
            .font(dress.font(words.size, chip && dress.shape == .box ? .bold : words.weight))
            .italic(dress.shape == .listings && chip)
            .tvCase(dress.capitals, tracking: dress.shape == .receiver ? words.size * 0.06 : 0)
            .lineLimit(1)
            .foregroundStyle(lit ? p.hiText : ink(p))
            .padding(.horizontal, kind == .icon ? 0 : chip ? 12 : 14)
            .frame(minWidth: kind == .icon ? 48 : nil, minHeight: 48)
            .background { shape.fill(lit ? AnyShapeStyle(p.hi) : fill(p)) }
            .overlay { if let border = border(p), !lit { shape.strokeBorder(border, lineWidth: 1) } }
            .overlay { if dress.bevel, kind == .button || kind == .icon { Bevel().clipShape(shape) } }
            .tvRing(focused, radius: radius, colour: p.text)
            .opacity(enabled ? (pressed ? 0.85 : 1) : 0.45)
    }

    private func ink(_ p: TvPaint) -> Color {
        switch dress.shape {
        case .modern where kind == .chip || kind == .link: return p.soft
        case .teletext where kind == .chip: return p.soft
        default: return p.text
        }
    }

    private func fill(_ p: TvPaint) -> AnyShapeStyle {
        if kind == .chip || kind == .link { return AnyShapeStyle(Color.clear) }
        switch dress.shape {
        case .box: return AnyShapeStyle(LinearGradient(colors: [p.panel2, p.panel], startPoint: .top, endPoint: .bottom))
        case .modern, .cinema, .compact: return AnyShapeStyle(p.panel2)
        case .teletext: return AnyShapeStyle(onBar ? p.bg : p.panel2)
        case .receiver, .listings, .outline: return AnyShapeStyle(Color.clear)
        }
    }

    private func border(_ p: TvPaint) -> Color? {
        if kind == .chip || kind == .link { return nil }
        switch dress.shape {
        case .box, .receiver, .outline: return p.line
        case .listings: return p.text
        default: return nil
        }
    }
}

/// Draws nothing and can still be focused: the edges of the grid, where moving on means another time.
struct TvEdgeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(0.001)
    }
}

/// The time on the TV, as the page's clock says it.
func tvClock(_ time: Int64) -> String { GuideRules.clock(time) }
#endif
