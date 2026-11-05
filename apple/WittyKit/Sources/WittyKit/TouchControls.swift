import Foundation

// The account's touch controls, drawn over a game on a phone or tablet with no controller, as
// the website's WittyPlay player draws them. The layout is the server's data
// (`GET /consoles/{console}/controls?device=`: `controls`, `defaults.touch`, `saved.touch`); the
// rules for where each control sits, what a finger presses and how the stick reads are the
// website player's (WittyPlay 0.3.4), so a layout arranged on the website looks and plays the same.

/// Where one control sits: its centre as fractions of the play area from the top left, its size
/// as a fraction of the area's shorter side.
public struct TouchPlacement: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var size: Double
    public var opacity: Double
    public var hidden: Bool?

    public init(x: Double, y: Double, size: Double, opacity: Double, hidden: Bool? = nil) {
        self.x = x
        self.y = y
        self.size = size
        self.opacity = opacity
        self.hidden = hidden
    }
}

/// One control a console's touch layout can have: `dpad`, `lstick`, or `b<id>` for a button.
public struct TouchControl: Decodable, Equatable {
    public let key: String
    /// The RetroPad button, or -1 for the D-pad and -2 for the stick.
    public let id: Int
    public let label: String
    /// `dpad`, `stick`, `face`, `shoulder` or `meta`.
    public let kind: String
    /// A D-pad that is the analog stick, as on the Nintendo 64.
    public let stick: Bool?

    public init(key: String, id: Int, label: String, kind: String, stick: Bool? = nil) {
        self.key = key
        self.id = id
        self.label = label
        self.kind = kind
        self.stick = stick
    }

    public var isStick: Bool { kind == "stick" || (kind == "dpad" && stick == true) }
    public var isDpad: Bool { kind == "dpad" && stick != true }
}

public enum TouchOrientation: String, Equatable {
    case portrait, landscape

    /// Portrait when the area is at least as tall as it is wide.
    public init(width: Double, height: Double) { self = height >= width ? .portrait : .landscape }
}

/// A layout for each way the screen can be held. The server's defaults have every control; what
/// a device saved has only what it changed.
public struct TouchLayouts: Codable, Equatable {
    public var landscape: [String: TouchPlacement]?
    public var portrait: [String: TouchPlacement]?

    public init(landscape: [String: TouchPlacement]? = nil, portrait: [String: TouchPlacement]? = nil) {
        self.landscape = landscape
        self.portrait = portrait
    }

    public subscript(_ orientation: TouchOrientation) -> [String: TouchPlacement]? {
        orientation == .portrait ? portrait : landscape
    }
}

/// A control placed on an area of a given size, in that area's points.
public struct PlacedTouchControl: Equatable {
    public let control: TouchControl
    public let placement: TouchPlacement
    public let centerX: Double
    public let centerY: Double
    /// Half the control's size: what its hit circle and the D-pad and stick are measured by.
    public let half: Double
    /// The box it's drawn in. Shoulder and meta buttons are shorter, and keep the same top.
    public let left: Double
    public let top: Double
    public let width: Double
    public let height: Double
}

public struct TouchScreenLayout: Equatable {
    public let width: Double
    public let height: Double
    public let orientation: TouchOrientation
    /// The visible controls, in the server's order.
    public let controls: [PlacedTouchControl]

    /// Each control's placement from what this device saved, else the server's default for it.
    public init(controls: [TouchControl], defaults: TouchLayouts?, saved: TouchLayouts?, width: Double, height: Double) {
        self.width = width
        self.height = height
        let orientation = TouchOrientation(width: width, height: height)
        self.orientation = orientation
        let merged = (defaults?[orientation] ?? [:]).merging(saved?[orientation] ?? [:]) { _, mine in mine }
        let shorter = min(width, height)
        self.controls = controls.compactMap { control in
            guard let p = merged[control.key], p.hidden != true, p.size > 0 else { return nil }
            let k = p.size * shorter
            let tall: Double
            switch control.kind {
            case "shoulder": tall = 0.62 * k
            case "meta": tall = 0.55 * k
            default: tall = k
            }
            return PlacedTouchControl(control: control, placement: p, centerX: p.x * width, centerY: p.y * height, half: k / 2,
                                      left: p.x * width - k / 2, top: p.y * height - k / 2, width: k, height: tall)
        }
    }

    /// Where the picture goes while the controls show: the top 52% in portrait, so the controls
    /// sit below it, and the whole area in landscape, with the controls over it.
    public var pictureArea: (x: Double, y: Double, width: Double, height: Double) {
        orientation == .portrait ? (0, 0, width, height * 0.52) : (0, 0, width, height)
    }

    /// The first visible stick, the only one a finger can take.
    public var stick: PlacedTouchControl? { controls.first { $0.control.isStick } }

    /// Every control a point is on: buttons by a circle 1.18 times their half, the D-pad by 1.35.
    public func controls(at x: Double, _ y: Double) -> [PlacedTouchControl] {
        controls.filter { c in
            guard !c.control.isStick else { return false }
            let reach = c.half * (c.control.isDpad ? 1.35 : 1.18)
            return hypot(x - c.centerX, y - c.centerY) <= reach
        }
    }

    /// The D-pad's directions for a point: nothing within 0.18 of its half from the middle, else
    /// one of eight 45° sectors.
    public static func dpad(dx: Double, dy: Double, half: Double) -> UInt16 {
        guard half > 0, hypot(dx, dy) / half >= 0.18 else { return 0 }
        let up = RetroPad.bit(RetroPad.up), down = RetroPad.bit(RetroPad.down)
        let left = RetroPad.bit(RetroPad.left), right = RetroPad.bit(RetroPad.right)
        // Screen y points down, so a positive angle is towards the bottom.
        switch Int((atan2(dy, dx) / (.pi / 4)).rounded()) {
        case 0: return right
        case 1: return right | down
        case 2: return down
        case 3: return down | left
        case 4, -4: return left
        case -3: return left | up
        case -2: return up
        default: return up | right
        }
    }

    /// The stick for a finger's offset: full at the edge, with a radial dead zone of 0.12 rescaled
    /// so it still reaches 1. Down is positive, as the protocol has it.
    public static func stick(dx: Double, dy: Double, half: Double) -> (x: Double, y: Double) {
        guard half > 0 else { return (0, 0) }
        let vx = dx / half, vy = dy / half
        let c = hypot(vx, vy)
        guard c >= 0.12 else { return (0, 0) }
        let scale = (min(1, c) - 0.12) / 0.88 / c
        return (vx * scale, vy * scale)
    }
}

/// What the fingers on the screen hold: buttons, the sticks, and the stylus on a touch-screen console.
public struct TouchOutput: Equatable {
    public var buttons: UInt16 = 0
    public var leftX = 0.0, leftY = 0.0, rightX = 0.0, rightY = 0.0
    /// Where the stylus is, in the area's points, while one is down.
    public var stylus: (x: Double, y: Double)?

    public init() {}

    public static func == (a: TouchOutput, b: TouchOutput) -> Bool {
        a.buttons == b.buttons && a.leftX == b.leftX && a.leftY == b.leftY && a.rightX == b.rightX && a.rightY == b.rightY
            && a.stylus?.x == b.stylus?.x && a.stylus?.y == b.stylus?.y
    }

    /// As a controller state for a port. Triggers held go out at full as well as by their bits.
    public func padState(port: UInt8) -> PadState {
        func axis(_ v: Double) -> Int16 { Int16((max(-1, min(1, v)) * 32767).rounded()) }
        return PadState(port: port, buttons: buttons, lx: axis(leftX), ly: axis(leftY), rx: axis(rightX), ry: axis(rightY),
                        l2: buttons & RetroPad.bit(RetroPad.l2) != 0 ? 255 : 0,
                        r2: buttons & RetroPad.bit(RetroPad.r2) != 0 ? 255 : 0)
    }
}

/// The fingers on the controls. What a finger does is settled when it lands: on the stick it
/// steers until lifted; on a console with a touch screen, one that lands on no control is the
/// stylus until lifted; any other presses whatever it's over, and sliding off one button onto
/// another lets go of the first.
public struct TouchFingers {
    public enum Role: Equatable { case buttons, stick, stylus }

    private var fingers: [Int: (x: Double, y: Double, role: Role)] = [:]

    public init() {}

    public var isEmpty: Bool { fingers.isEmpty }

    public mutating func down(_ id: Int, x: Double, y: Double, layout: TouchScreenLayout, stylus: Bool) {
        var role = Role.buttons
        if let s = layout.stick, !fingers.values.contains(where: { $0.role == .stick }),
           hypot(x - s.centerX, y - s.centerY) <= 1.1 * s.half {
            role = .stick
        } else if stylus, layout.controls(at: x, y).isEmpty, !fingers.values.contains(where: { $0.role == .stylus }) {
            role = .stylus
        }
        fingers[id] = (x, y, role)
    }

    public mutating func move(_ id: Int, x: Double, y: Double) {
        guard let f = fingers[id] else { return }
        fingers[id] = (x, y, f.role)
    }

    public mutating func up(_ id: Int) { fingers[id] = nil }

    public mutating func clear() { fingers = [:] }

    public func output(_ layout: TouchScreenLayout) -> TouchOutput {
        var out = TouchOutput()
        var axes = [0.0, 0.0, 0.0, 0.0]
        for f in fingers.values {
            switch f.role {
            case .stylus:
                out.stylus = (f.x, f.y)
            case .stick:
                if let s = layout.stick {
                    let v = TouchScreenLayout.stick(dx: f.x - s.centerX, dy: f.y - s.centerY, half: s.half)
                    out.leftX = v.x
                    out.leftY = v.y
                }
            case .buttons:
                for c in layout.controls(at: f.x, f.y) {
                    if c.control.isDpad {
                        out.buttons |= TouchScreenLayout.dpad(dx: f.x - c.centerX, dy: f.y - c.centerY, half: c.half)
                    } else if (16...23).contains(c.control.id) {
                        // A button that pushes a stick: 16 + k is axis k / 2, the low way for even k.
                        let k = c.control.id - 16
                        axes[k >> 1] = k % 2 == 0 ? -1 : 1
                    } else if c.control.id >= 0 {
                        out.buttons |= RetroPad.bit(c.control.id)
                    }
                }
            }
        }
        // A stick finger outweighs a stick button.
        if out.leftX == 0, out.leftY == 0 {
            out.leftX = axes[0]
            out.leftY = axes[1]
        }
        out.rightX = axes[2]
        out.rightY = axes[3]
        return out
    }
}

/// Where a point on the picture is on the game's own screen, for the pointer message: from the
/// picture's box on the screen, with the picture's quarter turns undone. Outside the picture it
/// stays at the edge.
public func touchPointer(x: Double, y: Double, picture: (x: Double, y: Double, width: Double, height: Double),
                         turns: Int, pressed: Bool) -> PointerState {
    guard picture.width > 0, picture.height > 0 else { return PointerState(pressed: pressed) }
    var u = min(1, max(0, (x - picture.x) / picture.width))
    var v = min(1, max(0, (y - picture.y) / picture.height))
    switch ((turns % 4) + 4) % 4 {
    case 1: (u, v) = (v, 1 - u)
    case 2: (u, v) = (1 - u, 1 - v)
    case 3: (u, v) = (1 - v, u)
    default: break
    }
    return PointerState(pressed: pressed, x: u * 2 - 1, y: v * 2 - 1)
}
