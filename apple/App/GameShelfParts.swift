import SwiftUI
import WittyKit

// The things games stand on a shelf as (docs/WITTYPLAY-EXPERIENCE.md, The games home: Shelves), drawn
// as the website draws them (WittyMediaServer `web/src/pages/games/shelves.css`): a game in its
// console's kind of case, as its cartridge, card or disc, or as a spine, with its ribbon when it's
// in progress. All of them are plain shapes in each console's proportions around the game's own
// cover: never a console maker's banners, logos, colours, label designs or outlines. Drawn objects
// keep their own plastic and light in every theme, as a picture does.

/// How big shelves are drawn here: the phone's sizes, scaled for a tablet and a TV (the design's
/// sizes for each), as the website's `--shelf-scale`.
struct ShelfSize {
    let scale: CGFloat
    /// A face-out cover grows more than the rest: 120×160 on a phone, 160×213 on a tablet, 228×300 on a TV.
    let faceScale: CGFloat
    let ribbon: CGSize
    /// How far a focused game lifts, and how much it grows, inside the ring.
    let lift: CGFloat
    let grow: CGFloat
    let tv: Bool

    init(_ metrics: Metrics) {
        tv = metrics.tv
        if metrics.tv {
            scale = 1.7; faceScale = 1.875; ribbon = CGSize(width: 22, height: 52); lift = 28; grow = 1.06
        } else if metrics.gutter > Tokens.Space.s4 {
            scale = 1.25; faceScale = 1.333; ribbon = CGSize(width: 14, height: 40); lift = 10; grow = 1
        } else {
            scale = 1; faceScale = 1; ribbon = CGSize(width: 14, height: 40); lift = 10; grow = 1
        }
    }

    /// The room above a ledge, for ribbons and the lift.
    var headroom: CGFloat { tv ? 48 : 32 * scale }
}

extension Metrics {
    var shelf: ShelfSize { ShelfSize(self) }
}

// MARK: - A cover's colour

/// Each cover's main colour, worked out from an 8-pixel copy of its smallest picture, as the website
/// does, and kept while the app runs. Spines and collection bands are drawn in it, and the page's glow.
@MainActor
final class CoverTints: ObservableObject {
    static let shared = CoverTints()
    @Published private(set) var tints: [Int64: Tint] = [:]
    private var asking: Set<Int64> = []

    struct Tint: Equatable {
        let hue: Double
        let saturation: Double
    }

    /// The deep colour of a game's spine or band, the same in every theme, as the website's `deepColour`.
    func deep(_ item: GameItem) -> Color {
        let t = tints[item.id]
        let c = GameShelves.deepColour(tint: t.map { ($0.hue, $0.saturation) }, title: item.title)
        return Color(hue: c.hue / 360, saturation: c.saturation, lightness: c.lightness)
    }

    /// The glow behind a page from a game's cover: deep on a dark theme, pale on a light one, as the
    /// website's `useCoverTint`. Nothing until its colour is known.
    func glow(_ item: GameItem?, light: Bool) -> Color? {
        guard let item, let t = tints[item.id] else { return nil }
        return light ? Color(hue: t.hue / 360, saturation: min(t.saturation, 0.7), lightness: 0.84)
                     : Color(hue: t.hue / 360, saturation: min(t.saturation, 0.62), lightness: 0.26)
    }

    func ask(_ items: [GameItem], client: WittyClient) {
        for item in items where item.hasPoster && tints[item.id] == nil && !asking.contains(item.id) {
            asking.insert(item.id)
            Task { await load(item, client: client) }
        }
    }

    private func load(_ item: GameItem, client: WittyClient) async {
        defer { asking.remove(item.id) }
        guard let url = client.gamePosterURL(item, width: 64), let data = try? await client.imageData(url) else { return }
        let rgba = await Task.detached(priority: .utility) { Self.pixels(data) }.value
        if let rgba, let t = GameShelves.tint(rgba: rgba) { tints[item.id] = Tint(hue: t.hue, saturation: t.saturation) }
    }

    /// An 8×8 copy of the picture, as RGBA bytes.
    nonisolated static func pixels(_ data: Data) -> [UInt8]? {
        guard let image = decodeArt(data, maxPixels: 64) else { return nil }
        var out = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let drawn: Bool = out.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
            return true
        }
        return drawn ? out : nil
    }
}

extension Color {
    /// A colour from hue, saturation and lightness (each 0 to 1), as CSS's `hsl()`.
    init(hue: Double, saturation: Double, lightness: Double) {
        let v = lightness + saturation * min(lightness, 1 - lightness)
        let s = v == 0 ? 0 : 2 * (1 - lightness / v)
        self.init(hue: hue, saturation: s, brightness: v)
    }
}

// MARK: - Era type

/// A console's name in its era's type, in the system's own faces: 8-bit in monospaced capitals,
/// Pocket monospaced, 16-bit extra-bold and tight, Early 3D bold italic, Disc era light, wide capitals.
struct EraName: View {
    let name: String
    let era: String?
    let size: CGFloat
    var colour: Color

    var body: some View {
        styled.foregroundStyle(colour).lineLimit(1).minimumScaleFactor(0.6)
    }

    private var styled: Text {
        switch era {
        case "first", "8-bit":
            return Text(name.uppercased()).font(.system(size: size, weight: .bold, design: .monospaced)).tracking(size * 0.06)
        case "pocket":
            return Text(name).font(.system(size: size, weight: .semibold, design: .monospaced))
        case "16-bit":
            return Text(name).font(.system(size: size, weight: .heavy)).tracking(-size * 0.02)
        case "early-3d":
            return Text(name).font(.system(size: size, weight: .bold)).italic()
        case "disc":
            return Text(name.uppercased()).font(.system(size: size, weight: .light)).tracking(size * 0.14)
        default:
            return Text(name).font(.system(size: size, weight: .bold))
        }
    }
}

// MARK: - The ribbon

/// A game in progress has a notched accent ribbon standing out of its top.
struct ShelfRibbon: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    var height: CGFloat?

    var body: some View {
        let size = metrics.shelf.ribbon
        RibbonShape()
            .fill(palette.accent)
            .frame(width: size.width, height: height ?? size.height)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .accessibilityHidden(true)
    }
}

private struct RibbonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.8))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A favourite's small star, on a scrim.
private struct ShelfStar: View {
    @Environment(\.palette) private var palette
    let scale: CGFloat
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 10 * scale, weight: .bold))
            .foregroundStyle(palette.warn)
            .padding(3 * scale)
            .background(Circle().fill(palette.scrim))
            .accessibilityHidden(true)
    }
}

// MARK: - The cover

/// The game's own cover, or its title on a plain card when it has none.
struct ShelfCover: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let item: GameItem
    let console: GameConsole?
    let width: CGFloat

    var body: some View {
        if item.hasPoster {
            ArtImage(url: client.gamePosterURL(item, width: Int(width * 2)), width: width, placeholder: item.title)
        } else {
            ZStack {
                LinearGradient(colors: [palette.card, palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 2) {
                    Text(item.title).font(.system(size: max(9, width * 0.1), weight: .semibold)).foregroundStyle(palette.text)
                        .multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.7)
                    if let c = console {
                        Text(c.shortName).font(.system(size: max(8, width * 0.075), weight: .bold, design: .monospaced)).foregroundStyle(palette.textHint)
                    }
                }
                .padding(4)
            }
        }
    }
}

// MARK: - Shared drawing

/// Plastic: the theme's text over its raised surface, so it's grey on a dark theme and pale on a light one.
private struct Plastic: View {
    @Environment(\.palette) private var palette
    var edge = false
    var body: some View {
        ZStack { palette.raised; palette.text.opacity(edge ? 0.22 : 0.12) }
    }
}

/// The insets of a shape, as fractions of its size (top, right, bottom, left), as the website's `inset`.
private struct Inset {
    let top, right, bottom, left: CGFloat
    func rect(in size: CGSize) -> CGRect {
        CGRect(x: size.width * left, y: size.height * top,
               width: size.width * (1 - left - right), height: size.height * (1 - top - bottom))
    }
}

/// Lines across or down, as the website's `repeating-linear-gradient`: `line` thick, `period` apart.
private struct Stripes: View {
    let colour: Color
    let line: CGFloat
    let period: CGFloat
    var vertical = false
    var body: some View {
        Canvas { ctx, size in
            var at: CGFloat = 0
            while at < (vertical ? size.width : size.height) {
                let r = vertical ? CGRect(x: at, y: 0, width: line, height: size.height) : CGRect(x: 0, y: at, width: size.width, height: line)
                ctx.fill(Path(r), with: .color(colour))
                at += max(1, period)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The era's grain: dots on a grid the size of its pixel, fading down.
struct EraGrain: View {
    let cell: CGFloat
    var dot: Double = 0.22
    var fade: Double = 0.7
    var body: some View {
        Canvas { ctx, size in
            let r = cell * 0.17
            var y: CGFloat = cell / 2
            while y < size.height {
                var x: CGFloat = cell / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(dot)))
                    x += cell
                }
                y += cell
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: fade)], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A rectangle with one radius at the top and another at the bottom, as a cartridge's or a spine's.
struct UnevenRect: InsettableShape {
    let top: CGFloat
    let bottom: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> UnevenRect { UnevenRect(top: top, bottom: bottom, inset: inset + amount) }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let t = max(0, min(top - inset, r.width / 2, r.height / 2)), b = max(0, min(bottom - inset, r.width / 2, r.height / 2))
        var p = Path()
        p.move(to: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + t), radius: t)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - b))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - b, y: r.maxY), radius: b)
        p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - b), radius: b)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + t))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + t, y: r.minY), radius: t)
        p.closeSubpath()
        return p
    }
}

/// Pulled out, a game takes a 2-wide accent ring, 2 out.
private struct PulledRing<S: InsettableShape>: View {
    @Environment(\.palette) private var palette
    let shape: S
    let on: Bool
    var body: some View {
        if on { shape.inset(by: -4).strokeBorder(palette.accent, lineWidth: 2) }
    }
}

// MARK: - A case

/// A game in its console's kind of case, cover showing: a cardboard box, a plastic clamshell, a CD
/// jewel case or a DVD-style keep case. `fit` makes it no wider than that, for a grid.
struct GameCaseView: View {
    @Environment(\.metrics) private var metrics
    let item: GameItem
    let console: GameConsole?
    var ribbon = false
    var favourite = false
    var pulled = false
    var fit: CGFloat?

    static func size(_ console: GameConsole?, scale: CGFloat, fit: CGFloat? = nil) -> CGSize {
        let shape = GameShelves.caseShape(console)
        var h = 176 * CGFloat(shape.height) * scale
        if let fit, h * CGFloat(shape.aspect) > fit { h = fit / CGFloat(shape.aspect) }
        return CGSize(width: (h * CGFloat(shape.aspect)).rounded(), height: h.rounded())
    }

    var body: some View {
        let s = metrics.shelf
        let size = Self.size(console, scale: s.scale, fit: fit)
        drawn(kind: GameShelves.caseShape(console).kind, size: size)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topTrailing) { if ribbon { ShelfRibbon().padding(.trailing, size.width * 0.12).offset(y: -8) } }
            .overlay(alignment: .topLeading) { if favourite { ShelfStar(scale: s.scale).padding(Tokens.Space.s2 * s.scale) } }
            .offset(y: pulled ? -10 * s.scale : 0)
    }

    @ViewBuilder private func drawn(kind: String, size: CGSize) -> some View {
        let cover = ShelfCover(item: item, console: console, width: size.width)
        switch kind {
        case "clamshell":
            PlasticCase(size: size, radius: 4, inset: Inset(top: 0.04, right: 0.05, bottom: 0.04, left: 0.07), coverRadius: 1, pulled: pulled, cover: cover) { Plastic() }
        case "jewel":
            PlasticCase(size: size, radius: 3, inset: Inset(top: 0.03, right: 0.03, bottom: 0.03, left: 0.11), coverRadius: 1, pulled: pulled, cover: cover) {
                // The hinge down the left, under clear plastic.
                HStack(spacing: 0) {
                    ZStack {
                        Plastic(edge: true)
                        Stripes(colour: .white.opacity(0.18), line: 2, period: 6).padding(.vertical, size.height * 0.04).padding(.horizontal, size.width * 0.02)
                    }
                    .frame(width: size.width * 0.09)
                    Color.white.opacity(0.06)
                }
            }
        case "keep":
            PlasticCase(size: size, radius: 6, inset: Inset(top: 0.05, right: 0.05, bottom: 0.05, left: 0.08), coverRadius: 2, pulled: pulled, cover: cover) { Plastic() }
        default:
            // A cardboard box: the cover is the box, its top catching the light and its side in shade.
            let shape = RoundedRectangle(cornerRadius: 2)
            cover
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) { Color.white.opacity(0.25).frame(height: 1) }
                .overlay(alignment: .trailing) { LinearGradient(colors: [.clear, .black.opacity(0.22)], startPoint: .leading, endPoint: .trailing).frame(width: 4) }
                .clipShape(shape)
                .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
                .overlay(PulledRing(shape: shape, on: pulled))
        }
    }
}

/// A plastic case: the cover under clear plastic in a frame, which shines across it.
private struct PlasticCase<Back: View>: View {
    @Environment(\.palette) private var palette
    let size: CGSize
    let radius: CGFloat
    let inset: Inset
    let coverRadius: CGFloat
    let pulled: Bool
    let cover: ShelfCover
    @ViewBuilder let back: () -> Back

    var body: some View {
        let r = inset.rect(in: size)
        let shape = RoundedRectangle(cornerRadius: radius)
        ZStack(alignment: .topLeading) {
            back()
            cover
                .frame(width: r.width, height: r.height)
                .clipShape(RoundedRectangle(cornerRadius: coverRadius))
                .offset(x: r.minX, y: r.minY)
            LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0), location: 0.38),
                                   .init(color: .white.opacity(0), location: 0.7), .init(color: .white.opacity(0.08), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.text.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
        .overlay(PulledRing(shape: shape, on: pulled))
    }
}

// MARK: - A cartridge

/// A game as its cartridge, card or disc, the cover on its label.
struct GameCartView: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let item: GameItem
    let console: GameConsole?
    var ribbon = false
    var favourite = false
    var pulled = false

    static func size(_ console: GameConsole?, scale: CGFloat) -> CGSize {
        let shape = GameShelves.cartShape(console)
        let h = 150 * CGFloat(shape.height) * scale
        return CGSize(width: (h * CGFloat(shape.aspect)).rounded(), height: h.rounded())
    }

    var body: some View {
        let s = metrics.shelf
        let size = Self.size(console, scale: s.scale)
        drawn(kind: GameShelves.cartShape(console).kind, size: size)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topTrailing) { if ribbon { ShelfRibbon().padding(.trailing, size.width * 0.12).offset(y: -8) } }
            .overlay(alignment: .topLeading) { if favourite { ShelfStar(scale: s.scale).padding(Tokens.Space.s2 * s.scale) } }
            .offset(y: pulled ? -10 * s.scale : 0)
    }

    @ViewBuilder private func drawn(kind: String, size: CGSize) -> some View {
        let cover = ShelfCover(item: item, console: console, width: size.width)
        switch kind {
        case "card":
            // Flat, mostly label, contacts along its foot.
            let label = Inset(top: 0.08, right: 0.08, bottom: 0.22, left: 0.08).rect(in: size)
            let shape = RoundedRectangle(cornerRadius: 5)
            ZStack(alignment: .topLeading) {
                Plastic()
                cover.frame(width: label.width, height: label.height).clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: label.minX, y: label.minY)
                Stripes(colour: palette.warn.opacity(0.7), line: max(1, size.width * 0.04), period: size.width * 0.075, vertical: true)
                    .frame(width: size.width * 0.76, height: size.height * 0.09)
                    .offset(x: size.width * 0.12, y: size.height * 0.85)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
            .overlay(shape.strokeBorder(palette.text.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
            .overlay(PulledRing(shape: shape, on: pulled))
        case "disc":
            // Round, the cover printed on it, a clear ring and the hole in the middle.
            let d = min(size.width, size.height)
            ZStack {
                Circle().fill(AngularGradient(colors: [.white.opacity(0.35), Color(red: 0.63, green: 0.78, blue: 1).opacity(0.25),
                                                       Color(red: 1, green: 0.86, blue: 0.63).opacity(0.3), .white.opacity(0.35)],
                                              center: .center, angle: .degrees(30)))
                cover.frame(width: d * 0.94, height: d * 0.94)
                    .clipShape(Circle())
                    .mask(Circle().strokeBorder(.black, lineWidth: d * 0.47 - d * 0.18))
                // The clear ring around the hole, and the hole showing the page behind.
                Circle().fill(.white.opacity(0.1)).frame(width: d * 0.36, height: d * 0.36)
                Circle().strokeBorder(.white.opacity(0.45), lineWidth: d * 0.03).frame(width: d * 0.26, height: d * 0.26)
                Circle().fill(palette.background).frame(width: d * 0.16, height: d * 0.16)
            }
            .frame(width: d, height: d)
            .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
            .overlay(PulledRing(shape: Circle(), on: pulled))
        default:
            // A plastic shell, the cover on a label in its top part, grip lines below.
            let label = Inset(top: 0.08, right: 0.10, bottom: 0.33, left: 0.10).rect(in: size)
            let shape = UnevenRect(top: 7, bottom: 4)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Plastic().frame(height: size.height * 0.70)
                    Plastic(edge: true).frame(height: max(1, size.height * 0.02))
                    Plastic()
                }
                Color.white.opacity(0.12).frame(height: 2)
                cover.frame(width: label.width, height: label.height).clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.25), lineWidth: 1))
                    .offset(x: label.minX, y: label.minY)
                Stripes(colour: .black.opacity(0.22), line: 2, period: 5)
                    .frame(width: size.width * 0.56, height: size.height * 0.16)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .offset(x: size.width * 0.22, y: size.height * 0.76)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
            .overlay(shape.strokeBorder(palette.text.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
            .overlay(PulledRing(shape: shape, on: pulled))
        }
    }
}

// MARK: - A spine

/// A game as a book stands: a strip in its cover's deep colour, with its title down it, the
/// console's short name at its foot and its era's grain at the top.
struct GameSpineView: View {
    @ObservedObject private var tints = CoverTints.shared
    @Environment(\.metrics) private var metrics
    @Environment(\.dynamicTypeSize) private var typeSize
    let item: GameItem
    let console: GameConsole?
    var ribbon = false
    var favourite = false

    static func size(_ item: GameItem, _ console: GameConsole?, scale: CGFloat) -> CGSize {
        let media = GameShelves.media(console)
        let w = media == "disc" ? 24 : CGFloat(GameShelves.spineWidth(title: item.title))
        return CGSize(width: (w * scale).rounded(), height: (media == "pocket" ? 136 : 176) * scale)
    }

    /// Spine titles scale with the text size, and spines widen to fit them.
    private var words: CGFloat {
        switch typeSize {
        case .xSmall, .small, .medium, .large: return 1
        case .xLarge: return 1.1
        case .xxLarge: return 1.2
        case .xxxLarge: return 1.3
        default: return 1.5
        }
    }

    var body: some View {
        let s = metrics.shelf.scale
        let media = GameShelves.media(console)
        let base = Self.size(item, console, scale: s)
        let size = CGSize(width: (base.width * (media == "disc" ? 1 : words)).rounded(), height: base.height)
        let grain = CGFloat(GameShelves.eraGrain[GameShelves.era(console) ?? ""] ?? 10)
        let shape = UnevenRect(top: 4 * s, bottom: 1)
        let run = size.height - (24 + 30) * s
        ZStack(alignment: .top) {
            tints.deep(item)
            LinearGradient(stops: [.init(color: .white.opacity(media == "disc" ? 0.35 : 0.14), location: 0),
                                   .init(color: .white.opacity(0), location: media == "disc" ? 0.18 : 0.28),
                                   .init(color: .black.opacity(media == "disc" ? 0 : 0.22), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            EraGrain(cell: grain * s).opacity(0.35)
            if media != "disc" {
                Text(item.title)
                    .font(.system(size: 12.5 * s * words, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 1)
                    .frame(width: run, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: size.width, height: run)
                    .padding(.top, 24 * s)
                VStack {
                    Spacer(minLength: 0)
                    Text(GameShelves.footName(console))
                        .font(.system(size: 9 * s, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, minHeight: 18 * s, maxHeight: 18 * s)
                        .background(RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.28)))
                        .padding(.horizontal, 3 * s)
                        .padding(.bottom, 6 * s)
                }
            }
            if favourite {
                Image(systemName: "star.fill").font(.system(size: 10 * s)).foregroundStyle(.white.opacity(0.9)).padding(.top, 5 * s)
                    .offset(y: ribbon ? metrics.shelf.ribbon.height * 0.6 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.stroke(.black.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
        .overlay(alignment: .top) { if ribbon { ShelfRibbon(height: metrics.shelf.ribbon.height * 0.85).offset(y: -16 * s) } }
    }
}

/// A game turned to show its cover: a shelf's first, or one pulled out.
struct GameFaceOutView: View {
    @Environment(\.metrics) private var metrics
    let item: GameItem
    let console: GameConsole?
    var ribbon = false
    var pulled = false

    static func size(_ console: GameConsole?, faceScale: CGFloat) -> CGSize {
        let pocket = GameShelves.media(console) == "pocket"
        return CGSize(width: ((pocket ? 104 : 120) * faceScale).rounded(), height: ((pocket ? 136 : 160) * faceScale).rounded())
    }

    var body: some View {
        let s = metrics.shelf
        let size = Self.size(console, faceScale: s.faceScale)
        let shape = RoundedRectangle(cornerRadius: 6 * s.scale, style: .continuous)
        ShelfCover(item: item, console: console, width: size.width)
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .shadow(color: .black.opacity(0.6), radius: 11, y: 14)
            .overlay(PulledRing(shape: shape, on: pulled))
            .overlay(alignment: .topTrailing) { if ribbon { ShelfRibbon().padding(.trailing, Tokens.Space.s3 * s.scale).offset(y: -6) } }
            .offset(y: -6 * s.scale)
    }
}

/// A letter divider on a long shelf of spines, like a record shop's.
struct ShelfDivider: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let letter: String

    var body: some View {
        let s = metrics.shelf.scale
        let shape = UnevenRect(top: 3 * s, bottom: 0)
        Text(letter)
            .font(.system(size: 11 * s, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.textSecondary)
            .padding(.top, 5 * s)
            .frame(width: 22 * s, height: 64 * s, alignment: .top)
            .background(shape.fill(palette.card))
            .overlay(shape.strokeBorder(palette.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// What a shelf's games stand on: a 3-high line of the theme's text at 13%, with a soft shadow under it.
struct ShelfLedge: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Rectangle()
            .fill(palette.text.opacity(0.13))
            .frame(height: 3)
            .shadow(color: .black.opacity(0.25), radius: 6, y: 5)
            .accessibilityHidden(true)
    }
}

// MARK: - Pressing and focus

/// A game on a shelf takes the focus ring as it lifts and grows a little (on a TV, 28 and 1.06), as
/// the design's "it's in your hand". Pressed, it dims for a moment. Touch shows no ring.
struct ShelfPress: ButtonStyle {
    var radius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        ShelfPressBody(label: configuration.label, pressed: configuration.isPressed, radius: radius)
    }
}

private struct ShelfPressBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool
    let radius: CGFloat

    var body: some View {
        let s = metrics.shelf
        let on = focused && metrics.tv
        label
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: radius + metrics.focusRing, style: .continuous)
                        .strokeBorder(palette.text, lineWidth: metrics.focusRing)
                        .padding(-2 * metrics.focusRing)
                }
            }
            .scaleEffect(on && !reduceMotion ? s.grow : 1, anchor: .bottom)
            .offset(y: on ? -s.lift : 0)
            .opacity(pressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: on)
            .contentShape(Rectangle())
    }
}

/// A picture that drifts very slowly, as the design's attract previews and Where you left off: a
/// 14-second pan between 1.04 and 1.14, still with Reduce Motion.
struct Drifting<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: () -> Content
    @State private var far = false

    var body: some View {
        content()
            .scaleEffect(reduceMotion ? 1.04 : (far ? 1.14 : 1.04), anchor: far ? .topLeading : .bottomTrailing)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { far = true }
            }
            .clipped()
    }
}
