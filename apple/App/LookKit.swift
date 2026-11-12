// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import CoreText
import WittyKit

// What a look (an experience wearing a theme) brings to every surface: the finish (glass, gloss, bevel, glow, texture), the
// theme's scene behind the page, and the type set. It is all data from the theme engine's `look` (WittyKit's ExperienceLook):
// nothing here names an experience, so a look that asks for glass gets glass (docs/plans/DESIGN-2.md 7.1 and 7.7, the server's
// docs/DESIGN.md). Glass is gradients, a highlight edge and a soft shadow, never a blur over what scrolls; on a modest device, or
// when the person asks for less transparency or motion, every effect drops a step and the scene is its first layer.

// MARK: - Type sets

/// The type sets (system, humanist, rounded, mono, serif). The system's is the platform's; the others are bundled open fonts
/// (Nunito, Source Sans 3, Source Serif 4, JetBrains Mono: SIL OFL, apple/App/Fonts) registered once at launch.
enum TypeSet {
    /// The set in use, set by the model as the look changes; everything that draws type also reads the palette, so it is drawn again.
    static var current: TypeSetID = .system

    private static var faces: [TypeSetID: [Int: String]] = [:]
    private static var registered = false

    private static let files: [(set: TypeSetID, file: String)] = [
        (.rounded, "Nunito-Variable"), (.humanist, "SourceSans3-Variable"), (.serif, "SourceSerif4-Variable"), (.mono, "JetBrainsMono-Variable"),
    ]
    private static let weights: [(word: String, weight: Int)] = [
        ("extralight", 200), ("extrabold", 800), ("semibold", 600), ("light", 300), ("medium", 500), ("regular", 400), ("bold", 700),
        ("black", 900), ("thin", 100),
    ]

    /// Registers the bundled fonts and learns each one's weights. Safe to call again.
    static func register() {
        guard !registered else { return }
        registered = true
        for (set, file) in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") ?? Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            var found: [Int: String] = [:]
            for descriptor in (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? [] {
                guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { continue }
                let tail = name.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).last.map(String.init) ?? ""
                if let weight = weights.first(where: { $0.word == tail })?.weight { found[weight] = name }
            }
            faces[set] = found
        }
    }

    private static func css(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight, .thin: return 200
        case .light: return 300
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    /// Text at a size and weight in the set in use. Numbers set in a monospaced design stay the system's, so columns line up.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        guard current != .system, design == .default || design == .rounded || design == .serif, let available = faces[current], !available.isEmpty else {
            return .system(size: size, weight: weight, design: design)
        }
        let want = css(weight)
        guard let key = available.keys.min(by: { abs($0 - want) < abs($1 - want) }), let name = available[key] else {
            return .system(size: size, weight: weight, design: design)
        }
        return .custom(name, fixedSize: size)
    }

    /// The bundled face's name for a weight, for the places that need a font by name (SDUI's roles).
    static func faceName(weight: Font.Weight) -> String? {
        guard current != .system, let available = faces[current], !available.isEmpty else { return nil }
        let want = css(weight)
        return available.keys.min(by: { abs($0 - want) < abs($1 - want) }).flatMap { available[$0] }
    }
}

extension Font {
    /// `.system(size:weight:design:)` in the look's type set.
    static func wm(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        TypeSet.font(size, weight, design: design)
    }
}

// MARK: - The finish

/// A surface's part in a look: what it is decides which effects draw on it.
enum FinishRole {
    /// A panel, a card, a group of rows, a widget.
    case card
    /// A row in a list.
    case row
    /// A bar, the Dock, a menu or a dialog.
    case bar
    /// A button that isn't the main one.
    case button
    /// The main button: filled with the accent.
    case accent
    /// A chip, off and on.
    case chip(on: Bool)

    var isGlass: Bool {
        switch self {
        case .card, .row, .bar: return true
        default: return false
        }
    }
}

/// The finish in force: the experience's effects at the level the device allows, and the theme's recipes as colours.
struct Finish: Equatable {
    var effects = LookEffects()
    var glassHi = Color.white.opacity(0.2), glassLo = Color.white.opacity(0.06), glassEdge = Color.white.opacity(0.3), glassShadow = Color.black.opacity(0.3)
    /// Highlight, upper body, lower body, glow and edge of a glossy button.
    var gloss: [Color] = []
    var accentGlow = Color.clear
    var focusStyle = "ring"
    var overshoot = false
    var scene: [SceneLayer] = []

    static let plain = Finish()

    var active: Bool { effects.any }

    init() {}

    /// `modest`: a device that is slow, in low power mode, or whose person asked for less transparency or motion.
    init(look: ExperienceLook, palette: Palette, theme: AppTheme, modest: Bool) {
        let adjusted = look.adjusted(modest: modest)
        effects = adjusted.effects
        focusStyle = adjusted.focusStyle
        overshoot = adjusted.overshoot
        scene = adjusted.scene
        func colour(_ c: ThemeColour) -> Color { Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha) }
        let glass = adjusted.finish.glassColours(light: theme.isLight)
        glassHi = colour(glass.hi)
        glassLo = colour(glass.lo)
        glassEdge = colour(glass.edge)
        glassShadow = colour(glass.shadow)
        let stops = adjusted.finish.glossStops(accent: theme.accent, ink: theme.onAccent)
        gloss = stops.map(colour)
        accentGlow = colour(theme.accent)
    }
}

private struct FinishKey: EnvironmentKey { static let defaultValue = Finish.plain }

extension EnvironmentValues {
    var finish: Finish {
        get { self[FinishKey.self] }
        set { self[FinishKey.self] = newValue }
    }
}

/// What a surface is painted with: its own fill, then the look's layers over it (glass, gloss, bevel, texture), under the
/// surface's words. Drawn as the `.background` of the thing.
struct FinishBackdrop<S: InsettableShape>: View {
    @Environment(\.finish) private var finish
    let shape: S
    var fill: Color?
    let role: FinishRole

    var body: some View {
        let e = finish.effects
        ZStack {
            if let fill { shape.fill(fill) }
            if finish.active { layers(e) }
        }
        .shadow(color: shadowColour(e), radius: shadowRadius(e), y: shadowRadius(e) > 0 ? 2 : 0)
        .allowsHitTesting(false)
    }

    private var glossPaint: LinearGradient {
        let g = finish.gloss
        guard g.count >= 5 else { return LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom) }
        // The recipe as paint: highlight to upper body over the top half, lower body to glow under it.
        return LinearGradient(stops: [.init(color: g[0], location: 0), .init(color: g[1], location: 0.48), .init(color: g[2], location: 0.52), .init(color: g[3], location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    private func layers(_ e: LookEffects) -> some View {
        let glass = e.glass.amount, gloss = e.gloss.amount, bevel = e.bevel.amount, texture = e.texture.amount
        // Glass: a pane lit from above, with a highlight edge.
        if glass > 0, role.isGlass {
            shape.fill(LinearGradient(colors: [finish.glassHi.opacity(glass), finish.glassLo.opacity(glass)], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(finish.glassEdge.opacity(glass), lineWidth: 1)
        }
        // Gloss: the main button is a drop of colour in the theme's five stops; the others a sheen over their top half.
        if gloss > 0 {
            switch role {
            case .accent:
                if e.gloss == .full {
                    shape.fill(glossPaint)
                    if finish.gloss.count >= 5 { shape.strokeBorder(finish.gloss[4], lineWidth: 1) }
                } else if finish.gloss.count >= 1 {
                    shape.fill(LinearGradient(stops: [.init(color: finish.gloss[0].opacity(0.4), location: 0), .init(color: .clear, location: 0.52)], startPoint: .top, endPoint: .bottom))
                }
            case .button, .chip(on: false):
                if e.gloss == .full {
                    shape.fill(LinearGradient(colors: [finish.glassHi, finish.glassLo], startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(finish.glassEdge, lineWidth: 1)
                }
            default: EmptyView()
            }
        }
        // Bevel: a lit top edge and a shaded bottom edge on what can be pressed, and on cards and bars.
        if bevel > 0 {
            shape.strokeBorder(LinearGradient(stops: [.init(color: Color.white.opacity(0.32 * bevel), location: 0), .init(color: .clear, location: 0.35),
                                                      .init(color: .clear, location: 0.65), .init(color: Color.black.opacity(0.26 * bevel), location: 1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        if texture > 0, role.isGlass { ScanTexture(level: e.texture).clipShape(shape) }
    }

    private func shadowColour(_ e: LookEffects) -> Color {
        switch role {
        case .accent:
            if e.gloss == .full, finish.gloss.count >= 3 { return finish.gloss[2].opacity(0.45) }
            return e.glow.on ? finish.accentGlow.opacity(0.38 * e.glow.amount * 2) : .clear
        case .card, .bar: return e.glass == .full ? finish.glassShadow : .clear
        case .button, .chip: return e.gloss == .full ? finish.glassShadow : .clear
        case .row: return .clear
        }
    }

    private func shadowRadius(_ e: LookEffects) -> CGFloat {
        switch role {
        case .accent: return (e.gloss == .full || e.glow.on) ? 7 : 0
        case .card, .bar: return e.glass == .full ? 9 : 0
        case .button, .chip: return e.gloss == .full ? 3 : 0
        case .row: return 0
        }
    }
}

/// Fine horizontal lines (a screen's scanlines) or dots (paper's grain), drawn with the finish's texture level.
struct ScanTexture: View {
    @Environment(\.palette) private var palette
    let level: EffectLevel

    var body: some View {
        Canvas { context, size in
            if level == .full {
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.18)))
                    y += 3
                }
            } else {
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = (Int(y / 4) % 2 == 0) ? 0 : 2
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)), with: .color(palette.text.opacity(0.07)))
                        x += 4
                    }
                    y += 4
                }
            }
        }
        .opacity(level == .subtle ? 0.5 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The thing painted as a look says: its fill and the finish's layers behind it.
    func finished<S: InsettableShape>(_ shape: S, fill: Color?, role: FinishRole) -> some View {
        background { FinishBackdrop(shape: shape, fill: fill, role: role) }
    }

    /// Light given off around what has focus, where the look has glow.
    func finishGlow(_ on: Bool, colour: Color) -> some View { modifier(FinishGlow(on: on, colour: colour)) }
}

private struct FinishGlow: ViewModifier {
    @Environment(\.finish) private var finish
    let on: Bool
    let colour: Color

    func body(content: Content) -> some View {
        let level = finish.effects.glow
        content.shadow(color: on && level.on ? colour.opacity(0.6 * level.amount + 0.2) : .clear, radius: on && level.on ? 8 + 6 * level.amount : 0)
    }
}

// MARK: - The scene

/// The theme's scene: ordered layers drawn behind the page and under the menu, positions in percent of the window: a gradient
/// (the sky), a radial light (the light sweep), shapes (bubbles, a hill) and the plain page colour when the theme has none.
/// Gradients and shapes only, no blur. The light drifts and the bubbles rise slowly unless motion is reduced.
struct SceneBackdrop: View {
    @Environment(\.palette) private var palette
    @Environment(\.finish) private var finish
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            palette.background
            if !finish.scene.isEmpty {
                if reduceMotion || finish.scene.count <= 1 {
                    SceneCanvas(layers: finish.scene, phase: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
                        SceneCanvas(layers: finish.scene, phase: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
            if finish.effects.texture.on { FilmTexture(level: finish.effects.texture) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The page's ground: the theme's background colour, or nothing where the look has a scene, which the root draws under the
    /// whole window (a page that is the root's child lets it show).
    func pageGround() -> some View { modifier(PageGround()) }
}

private struct PageGround: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.finish) private var finish

    func body(content: Content) -> some View {
        content.background { (finish.scene.isEmpty ? palette.background : Color.clear).ignoresSafeArea() }
    }
}

/// The texture over the whole page, as a film that takes no tap.
private struct FilmTexture: View {
    let level: EffectLevel
    var body: some View { ScanTexture(level: level).opacity(level == .full ? 0.8 : 1) }
}

private struct SceneCanvas: View {
    let layers: [SceneLayer]
    let phase: Double

    private func colour(_ css: String?) -> Color? {
        css.flatMap(ThemeColour.init(css:)).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) }
    }

    private func gradient(_ layer: SceneLayer) -> Gradient? {
        let stops = layer.stops.compactMap { stop in colour(stop.color).map { Gradient.Stop(color: $0, location: max(0, min(1, stop.at / 100))) } }
        return stops.count >= 2 ? Gradient(stops: stops) : nil
    }

    var body: some View {
        Canvas { context, size in
            for (index, layer) in layers.enumerated() {
                let drift = sin(phase / 13 + Double(index) * 1.7)
                switch layer.type {
                case "gradient":
                    guard let gradient = gradient(layer) else { continue }
                    // CSS angles: 180 runs top to bottom, 90 left to right.
                    let a = (layer.angle ?? 180) * .pi / 180
                    let dx = sin(a), dy = -cos(a)
                    let half = abs(dx * size.width) / 2 + abs(dy * size.height) / 2
                    let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .linearGradient(gradient, startPoint: CGPoint(x: mid.x - dx * half, y: mid.y - dy * half), endPoint: CGPoint(x: mid.x + dx * half, y: mid.y + dy * half)))
                case "radial":
                    guard let c = colour(layer.color) else { continue }
                    let w = size.width * (layer.w ?? 50) / 100, h = size.height * (layer.h ?? 50) / 100
                    let centre = CGPoint(x: size.width * ((layer.x ?? 50) / 100 + drift * 0.012), y: size.height * (layer.y ?? 50) / 100)
                    var inner = context
                    inner.translateBy(x: centre.x, y: centre.y)
                    inner.scaleBy(x: w, y: h)
                    inner.fill(Path(ellipseIn: CGRect(x: -2, y: -2, width: 4, height: 4)),
                               with: .radialGradient(Gradient(stops: [.init(color: c, location: 0), .init(color: c.opacity(0), location: max(0.05, min(1, (layer.fade ?? 100) / 100)))]),
                                                     center: .zero, startRadius: 0, endRadius: 1))
                case "shape":
                    if layer.kind == "hill" {
                        let size2 = (layer.size ?? 60) / 100
                        let width = size.width * size2 * 2, height = size.height * size2 * 0.4
                        let rect = CGRect(x: size.width * (layer.x ?? 50) / 100 - width / 2, y: size.height * (layer.y ?? 100) / 100 - height, width: width, height: height * 2)
                        let paint: GraphicsContext.Shading
                        if let g = gradient(layer) {
                            paint = .linearGradient(g, startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.minY + height))
                        } else if let c = colour(layer.color) {
                            paint = .color(c)
                        } else { continue }
                        context.fill(Path(ellipseIn: rect), with: paint)
                        // The lit rim along the top of the hill.
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.4)), lineWidth: 2)
                    } else if let c = colour(layer.color) {
                        let d = min(size.width, size.height) * (layer.size ?? 8) / 100
                        let lift = CGFloat(drift) * min(size.width, size.height) * 0.008
                        let centre = CGPoint(x: size.width * (layer.x ?? 50) / 100, y: size.height * (layer.y ?? 50) / 100 + lift)
                        let rect = CGRect(x: centre.x - d / 2, y: centre.y - d / 2, width: d, height: d)
                        // A bubble: a soft body, a lit rim and a small highlight.
                        context.fill(Path(ellipseIn: rect), with: .color(c))
                        context.stroke(Path(ellipseIn: rect), with: .color(c), lineWidth: 1)
                        context.fill(Path(ellipseIn: CGRect(x: rect.minX + d * 0.2, y: rect.minY + d * 0.16, width: d * 0.22, height: d * 0.16)),
                                     with: .color(.white.opacity(0.55)))
                    }
                default: continue
                }
            }
        }
    }
}
