#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit
import WittyKit

// The account's touch controls over a game, on a phone or tablet with no controller: the layout
// is the server's (WittyKit `TouchScreenLayout`), drawn as the website's WittyPlay player draws it.
// On a DS or 3DS a finger on the picture is the stylus, with or without the controls.

/// The fingers on the screen, turned into what they hold.
@MainActor
final class TouchSurface: ObservableObject {
    @Published private(set) var output = TouchOutput()
    private var fingers = TouchFingers()
    @Published private(set) var layout = TouchScreenLayout(controls: [], defaults: nil, saved: nil, width: 0, height: 0)
    private var size = CGSize.zero
    private var stylus = false
    private let tap = UIImpactFeedbackGeneratorIfAny()
    var onChange: ((TouchOutput, CGSize) -> Void)?

    func update(controls: GameControls?, drawn: Bool, stylus: Bool, size: CGSize) {
        self.stylus = stylus
        self.size = size
        layout = TouchScreenLayout(controls: drawn ? (controls?.controls ?? []) : [], defaults: controls?.defaults?.touch,
                                   saved: controls?.saved?.touch, width: size.width, height: size.height)
        recompute()
    }

    func down(_ id: Int, _ p: CGPoint) {
        fingers.down(id, x: p.x, y: p.y, layout: layout, stylus: stylus)
        recompute()
    }

    func move(_ id: Int, _ p: CGPoint) {
        fingers.move(id, x: p.x, y: p.y)
        recompute()
    }

    func up(_ id: Int) {
        fingers.up(id)
        recompute()
    }

    func clear() {
        fingers.clear()
        recompute()
    }

    private func recompute() {
        let next = fingers.output(layout)
        guard next != output else { return }
        // A short tap for each button or direction newly pressed, as the website's player buzzes.
        if next.buttons & ~output.buttons != 0 || (next.rightX != 0 && output.rightX == 0) || (next.rightY != 0 && output.rightY == 0) {
            tap.fire()
        }
        output = next
        onChange?(next, size)
    }
}

/// A light tap where the device has a motor for it.
private struct UIImpactFeedbackGeneratorIfAny {
    #if os(iOS)
    private let generator = UIImpactFeedbackGenerator(style: .light)
    func fire() { generator.impactOccurred(intensity: 0.6) }
    #else
    func fire() {}
    #endif
}

struct TouchControlsOverlay: View {
    @ObservedObject var game: GamePlayerModel
    /// The controls themselves; without them only the stylus works.
    let drawn: Bool
    @StateObject private var surface = TouchSurface()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(surface.layout.controls, id: \.control.key) { c in
                    TouchControlView(control: c, output: surface.output, art: game.controlsData?.pad?.art)
                        .frame(width: c.width, height: c.height)
                        .opacity(c.placement.opacity)
                        .position(x: c.left + c.width / 2, y: c.top + c.height / 2)
                }
                TouchCatcher(surface: surface)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { configure(geo.size) }
            .onChange(of: geo.size) { configure($0) }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear { surface.onChange = { [weak game] out, size in game?.touched(out, size: size) } }
        .onDisappear { surface.clear() }
    }

    private func configure(_ size: CGSize) {
        surface.update(controls: game.controlsData, drawn: drawn, stylus: game.touchScreenConsole, size: size)
    }
}

/// Every finger on the screen, as many at once as there are.
private struct TouchCatcher: UIViewRepresentable {
    let surface: TouchSurface

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.surface = surface
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) { view.surface = surface }

    final class CatcherView: UIView {
        weak var surface: TouchSurface?

        private func id(_ touch: UITouch) -> Int { ObjectIdentifier(touch).hashValue }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { surface?.down(id(t), t.location(in: self)) }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { surface?.move(id(t), t.location(in: self)) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { surface?.up(id(t)) }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches { surface?.up(id(t)) }
        }
    }
}

// MARK: - Drawing

/// The website player's colours: tinted glass by the console's controller, a white edge, and a
/// white face when pressed.
private enum TouchInk {
    static let edge = Color.white.opacity(0.42)
    static let sheen = Color.white.opacity(0.1)
    static let ink = Color.white.opacity(0.95)
    static let hit = Color.white.opacity(0.92)
    static let pressedText = Color(red: 10 / 255, green: 12 / 255, blue: 18 / 255)

    static func glass(_ art: String?) -> Color {
        func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255).opacity(a) }
        switch art {
        case "two": return c(38, 18, 20, 0.52)
        case "one": return c(40, 28, 14, 0.5)
        case "four": return c(26, 20, 44, 0.5)
        case "six": return c(14, 26, 44, 0.52)
        case "handle": return c(14, 32, 30, 0.5)
        case "dual": return c(16, 20, 34, 0.5)
        default: return c(16, 18, 26, 0.5)
        }
    }
}

private struct TouchControlView: View {
    let control: PlacedTouchControl
    let output: TouchOutput
    let art: String?

    private var c: TouchControl { control.control }
    private var size: Double { control.width }

    var body: some View {
        if c.isStick {
            stick
        } else if c.isDpad {
            dpad
        } else {
            button
        }
    }

    // The D-pad: a rounded plus, and an arrow that lights for each direction held.
    private var dpad: some View {
        let held = output.buttons
        return Canvas { ctx, box in
            let s = box.width / 100
            ctx.scaleBy(x: s, y: s)
            let plus = Self.plus
            ctx.fill(plus, with: .color(TouchInk.glass(art)))
            ctx.stroke(plus, with: .color(TouchInk.edge), lineWidth: 1.5 / s)
            ctx.fill(Path(ellipseIn: CGRect(x: 41, y: 41, width: 18, height: 18)), with: .color(TouchInk.sheen))
            let arrows: [(Int, [CGPoint])] = [
                (RetroPad.up, [CGPoint(x: 50, y: 11), CGPoint(x: 59, y: 22), CGPoint(x: 41, y: 22)]),
                (RetroPad.down, [CGPoint(x: 50, y: 89), CGPoint(x: 41, y: 78), CGPoint(x: 59, y: 78)]),
                (RetroPad.left, [CGPoint(x: 11, y: 50), CGPoint(x: 22, y: 41), CGPoint(x: 22, y: 59)]),
                (RetroPad.right, [CGPoint(x: 89, y: 50), CGPoint(x: 78, y: 59), CGPoint(x: 78, y: 41)]),
            ]
            for (id, points) in arrows {
                var p = Path()
                p.addLines(points)
                p.closeSubpath()
                let on = held & RetroPad.bit(id) != 0
                ctx.fill(p, with: .color(on ? TouchInk.hit : TouchInk.ink.opacity(0.75)))
            }
        }
    }

    /// The website's plus: arms 36 wide from 3 to 97, the outer corners rounded by 5.
    private static let plus: Path = {
        let points: [(CGPoint, Bool)] = [
            (CGPoint(x: 32, y: 3), true), (CGPoint(x: 68, y: 3), true), (CGPoint(x: 68, y: 32), false), (CGPoint(x: 97, y: 32), true),
            (CGPoint(x: 97, y: 68), true), (CGPoint(x: 68, y: 68), false), (CGPoint(x: 68, y: 97), true), (CGPoint(x: 32, y: 97), true),
            (CGPoint(x: 32, y: 68), false), (CGPoint(x: 3, y: 68), true), (CGPoint(x: 3, y: 32), true), (CGPoint(x: 32, y: 32), false),
        ]
        var p = Path()
        let last = points[points.count - 1].0, first = points[0].0
        p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for (i, (corner, round)) in points.enumerated() {
            let next = points[(i + 1) % points.count].0
            p.addArc(tangent1End: corner, tangent2End: next, radius: round ? 5 : 0)
        }
        p.closeSubpath()
        return p
    }()

    // The stick: a well, a ring, and a cap that follows the finger.
    private var stick: some View {
        let knob = CGPoint(x: output.leftX * 26, y: output.leftY * 26)
        return Canvas { ctx, box in
            let s = box.width / 100
            ctx.scaleBy(x: s, y: s)
            func circle(_ r: CGFloat, _ at: CGPoint = CGPoint(x: 50, y: 50)) -> Path {
                Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
            }
            ctx.fill(circle(47), with: .color(TouchInk.glass(art)))
            ctx.stroke(circle(47), with: .color(TouchInk.edge), lineWidth: 1.5 / s)
            ctx.stroke(circle(30), with: .color(TouchInk.sheen), lineWidth: 2)
            let cap = CGPoint(x: 50 + knob.x, y: 50 + knob.y)
            ctx.fill(circle(24, cap), with: .color(Color.white.opacity(0x38 / 255)))
            ctx.stroke(circle(24, cap), with: .color(TouchInk.edge), lineWidth: 1.5 / s)
            ctx.fill(circle(14, cap), with: .color(TouchInk.sheen))
        }
    }

    private var pressed: Bool {
        if (16...23).contains(c.id) {
            let k = c.id - 16
            let axis = [output.leftX, output.leftY, output.rightX, output.rightY][k >> 1]
            return axis == (k % 2 == 0 ? -1 : 1)
        }
        return c.id >= 0 && output.buttons & RetroPad.bit(c.id) != 0
    }

    // Face, shoulder and meta buttons.
    private var button: some View {
        let font = size * (c.kind == "meta" ? 0.26 : 0.38)
        let on = pressed
        return ZStack {
            shape(font: font).fill(on ? TouchInk.hit : TouchInk.glass(art))
            if !on {
                shape(font: font).fill(RadialGradient(colors: [Color.white.opacity(0.16), .clear], center: UnitPoint(x: 0.35, y: 0.3),
                                                      startRadius: 0, endRadius: size * 0.6))
            }
            shape(font: font).strokeBorder(TouchInk.edge, lineWidth: art == "handle" ? 2 : 1.5)
            label(font: font, on: on)
        }
    }

    private func shape(font: Double) -> AnyInsettableShape {
        switch c.kind {
        case "meta": return AnyInsettableShape(Capsule())
        case "shoulder":
            return art == "six" ? AnyInsettableShape(RoundedRectangle(cornerRadius: size * 0.36 * 0.62, style: .continuous))
                : AnyInsettableShape(ShoulderShape(top: font * 0.55, bottom: font))
        default:
            return art == "six" ? AnyInsettableShape(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)) : AnyInsettableShape(Circle())
        }
    }

    @ViewBuilder private func label(font: Double, on: Bool) -> some View {
        let colour = on ? TouchInk.pressedText : TouchInk.ink
        let symbols = ["□", "△", "✕", "○"]
        if symbols.contains(c.label) {
            PlayStationMark(mark: c.label).stroke(colour, style: StrokeStyle(lineWidth: size * 0.07 * 0.68, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.68, height: size * 0.68)
        } else if let direction = c.label.range(of: #"^C (up|down|left|right)$"#, options: .regularExpression).map({ _ in String(c.label.dropFirst(2)) }) {
            CArrow(direction: direction).fill(colour).frame(width: size * 0.52, height: size * 0.52)
        } else {
            Text(c.label)
                .font(.system(size: c.label.count > 2 ? font * 0.72 : font, weight: c.kind == "meta" ? .semibold : .bold))
                .foregroundStyle(colour)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, c.kind == "meta" ? font * 0.5 : 0)
        }
    }
}

/// A shoulder button: rounder at the bottom than the top.
private struct ShoulderShape: InsettableShape {
    var top: CGFloat
    var bottom: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let t = min(top, r.height / 2, r.width / 2), b = min(bottom, r.height / 2, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + t, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: t)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: b)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: b)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: t)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> ShoulderShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// The PlayStation's marks, drawn as the website draws them, in a 100-unit square.
private struct PlayStationMark: Shape {
    let mark: String

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 100
        var p = Path()
        switch mark {
        case "□": p.addRoundedRect(in: CGRect(x: 33, y: 33, width: 34, height: 34), cornerSize: CGSize(width: 2, height: 2))
        case "△": p.addLines([CGPoint(x: 50, y: 28), CGPoint(x: 73, y: 68), CGPoint(x: 27, y: 68)]); p.closeSubpath()
        case "○": p.addEllipse(in: CGRect(x: 29, y: 29, width: 42, height: 42))
        default:
            p.move(to: CGPoint(x: 32, y: 32)); p.addLine(to: CGPoint(x: 68, y: 68))
            p.move(to: CGPoint(x: 68, y: 32)); p.addLine(to: CGPoint(x: 32, y: 68))
        }
        return p.applying(CGAffineTransform(scaleX: s, y: s).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

/// A Nintendo 64 C button's arrow.
private struct CArrow: Shape {
    let direction: String

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addLines([CGPoint(x: 50, y: 26), CGPoint(x: 74, y: 68), CGPoint(x: 26, y: 68)])
        p.closeSubpath()
        let turn: CGFloat
        switch direction {
        case "right": turn = .pi / 2
        case "down": turn = .pi
        case "left": turn = -.pi / 2
        default: turn = 0
        }
        let s = rect.width / 100
        let t = CGAffineTransform(translationX: -50, y: -50).concatenating(CGAffineTransform(rotationAngle: turn))
            .concatenating(CGAffineTransform(translationX: 50, y: 50)).concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return p.applying(t)
    }
}

/// Any insettable shape, so a button can be a circle, a pill or a shoulder.
private struct AnyInsettableShape: InsettableShape {
    private let make: (CGRect) -> Path
    private let insetBy: (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        make = { shape.path(in: $0) }
        insetBy = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { make(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBy(amount) }
}
#endif
