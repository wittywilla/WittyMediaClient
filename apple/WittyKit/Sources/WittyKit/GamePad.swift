import Foundation

// Controllers into the server's controller states, the way the website's player does it: a pad
// read in the W3C standard layout, the console's default mapping with the person's profile over
// it, their dead zone, press point, stick-as-D-pad and turbo, then the shortcuts held with Select.

/// The buttons of libretro's RetroPad, by bit. Numbers 16 to 23 are one direction of a stick.
public enum RetroPad {
    public static let b = 0, y = 1, select = 2, start = 3, up = 4, down = 5, left = 6, right = 7
    public static let a = 8, x = 9, l = 10, r = 11, l2 = 12, r2 = 13, l3 = 14, r3 = 15
    public static let leftStickLeft = 16, leftStickRight = 17, leftStickUp = 18, leftStickDown = 19
    public static let rightStickLeft = 20, rightStickRight = 21, rightStickUp = 22, rightStickDown = 23

    /// The names the server's settings use for them.
    public static let names: [String: Int] = [
        "b": b, "y": y, "select": select, "start": start, "up": up, "down": down, "left": left, "right": right,
        "a": a, "x": x, "l": l, "r": r, "l2": l2, "r2": r2, "l3": l3, "r3": r3,
    ]

    public static func bit(_ id: Int) -> UInt16 { (0...15).contains(id) ? UInt16(1) << UInt16(id) : 0 }
    public static let dpad: UInt16 = bit(up) | bit(down) | bit(left) | bit(right)
}

/// A gamepad as the W3C standard gamepad has it, which is laid out by position: the bottom face
/// button is 0 whatever it's called. Buttons go from 0 to 1, axes from -1 to 1 with down positive.
public struct StandardPadReading: Equatable {
    public static let south = 0, east = 1, west = 2, north = 3, l1 = 4, r1 = 5, l2 = 6, r2 = 7
    public static let select = 8, start = 9, l3 = 10, r3 = 11, up = 12, down = 13, left = 14, right = 15, home = 16

    public var buttons: [Double]
    public var axes: [Double]

    public init(buttons: [Double] = Array(repeating: 0, count: 17), axes: [Double] = [0, 0, 0, 0]) {
        self.buttons = buttons + Array(repeating: 0, count: max(0, 17 - buttons.count))
        self.axes = axes + Array(repeating: 0, count: max(0, 4 - axes.count))
    }

    public subscript(button n: Int) -> Double {
        get { buttons.indices.contains(n) ? buttons[n] : 0 }
        set { if buttons.indices.contains(n) { buttons[n] = newValue } }
    }
}

/// One player's controller state, as the server takes it: 13 bytes, little-endian, or 17 with a tag.
public struct PadState: Equatable {
    public var port: UInt8
    public var buttons: UInt16
    public var lx: Int16, ly: Int16, rx: Int16, ry: Int16
    public var l2: UInt8, r2: UInt8

    public init(port: UInt8 = 0, buttons: UInt16 = 0, lx: Int16 = 0, ly: Int16 = 0, rx: Int16 = 0, ry: Int16 = 0, l2: UInt8 = 0, r2: UInt8 = 0) {
        self.port = port
        self.buttons = buttons
        self.lx = lx
        self.ly = ly
        self.rx = rx
        self.ry = ry
        self.l2 = l2
        self.r2 = r2
    }

    public func pressed(_ id: Int) -> Bool { buttons & RetroPad.bit(id) != 0 }

    /// Nothing held, which is what's sent when the app leaves or a menu opens.
    public var isReleased: Bool { buttons == 0 && lx == 0 && ly == 0 && rx == 0 && ry == 0 && l2 == 0 && r2 == 0 }

    public func encoded(tag: UInt32? = nil) -> Data {
        var out = Data(capacity: 17)
        out.append(port)
        func put16(_ v: UInt16) { out.append(UInt8(v & 0xff)); out.append(UInt8(v >> 8)) }
        put16(buttons)
        for v in [lx, ly, rx, ry] { put16(UInt16(bitPattern: v)) }
        out.append(l2)
        out.append(r2)
        if let tag { for shift in stride(from: 0, to: 32, by: 8) { out.append(UInt8((tag >> UInt32(shift)) & 0xff)) } }
        return out
    }

    /// Two states merged: buttons held on either, and the stick pushed furthest.
    public func merged(_ other: PadState) -> PadState {
        func far(_ a: Int16, _ b: Int16) -> Int16 { abs(Int(a)) >= abs(Int(b)) ? a : b }
        return PadState(port: port, buttons: buttons | other.buttons, lx: far(lx, other.lx), ly: far(ly, other.ly),
                        rx: far(rx, other.rx), ry: far(ry, other.ry), l2: max(l2, other.l2), r2: max(r2, other.r2))
    }
}

/// A mapping made from the console's defaults and the layers over it, applied to readings.
public struct PadMapper: Equatable {
    /// RetroPad target to what presses it.
    public let map: [Int: PadSource]
    public let options: PadOptions

    public var deadzone: Double { min(0.6, max(0, options.deadzone ?? 0.15)) }
    public var threshold: Double { min(0.9, max(0.1, options.threshold ?? 0.5)) }
    public var turboHz: Double { min(30, max(2, options.turboHz ?? 12)) }

    /// Each layer's targets replace what's below, and a nil source takes a target away.
    public init(defaults: PadMap?, layers: [PadMap?] = [], options: PadOptions? = nil, defaultOptions: PadOptions? = nil) {
        var merged: [Int: PadSource] = [:]
        for layer in [defaults] + layers {
            for (key, source) in layer ?? [:] {
                guard let target = Int(key), (0...23).contains(target) else { continue }
                if let source { merged[target] = source } else { merged.removeValue(forKey: target) }
            }
        }
        map = merged
        self.options = (options ?? PadOptions()).over(defaultOptions)
    }

    /// The sticks after the dead zone, which is a circle: inside it is rest, and the rest of the
    /// way is spread over the whole range.
    func sticks(_ reading: StandardPadReading) -> [Double] {
        var axes = reading.axes
        for pair in [(0, 1), (2, 3)] {
            let x = axes[pair.0], y = axes[pair.1]
            let m = (x * x + y * y).squareRoot()
            if m <= deadzone || m == 0 {
                axes[pair.0] = 0
                axes[pair.1] = 0
            } else {
                let scaled = (m - deadzone) / (1 - deadzone) / m
                axes[pair.0] = x * scaled
                axes[pair.1] = y * scaled
            }
        }
        return axes
    }

    /// How far a source is pressed, from 0 to 1.
    func value(_ source: PadSource, _ reading: StandardPadReading, sticks: [Double]) -> Double {
        if let b = source.b { return min(1, max(0, reading[button: b])) }
        if let a = source.a {
            let raw = a < 4 ? sticks[a] : (reading.axes.indices.contains(a) ? reading.axes[a] : 0)
            if let rest = source.r, rest != 0 {
                // A trigger that rests at one end counts from there.
                return min(1, max(0, (raw - Double(rest)) / Double(-2 * rest)))
            }
            return min(1, max(0, raw * Double(source.d ?? 1)))
        }
        // A D-pad as one axis only comes from browsers that can't put a pad in order.
        return 0
    }

    public func state(_ reading: StandardPadReading, port: UInt8, now: TimeInterval = 0, applyTurbo: Bool = true) -> PadState {
        let sticks = sticks(reading)
        var amounts = [Double](repeating: 0, count: 24)
        for (target, source) in map { amounts[target] = max(amounts[target], value(source, reading, sticks: sticks)) }
        var out = PadState(port: port)
        for id in 0...15 {
            // A button is pressed or not; an analog input, a trigger or a stick, presses it past the press point.
            if amounts[id] > 0, amounts[id] >= threshold { out.buttons |= RetroPad.bit(id) }
        }
        out.l2 = UInt8((amounts[RetroPad.l2] * 255).rounded())
        out.r2 = UInt8((amounts[RetroPad.r2] * 255).rounded())
        func axis(_ minus: Int, _ plus: Int) -> Int16 { Int16((max(-1, min(1, amounts[plus] - amounts[minus])) * 32767).rounded()) }
        out.lx = axis(RetroPad.leftStickLeft, RetroPad.leftStickRight)
        out.ly = axis(RetroPad.leftStickUp, RetroPad.leftStickDown)
        out.rx = axis(RetroPad.rightStickLeft, RetroPad.rightStickRight)
        out.ry = axis(RetroPad.rightStickUp, RetroPad.rightStickDown)
        if options.stickDpad ?? true {
            // The left stick steers the D-pad as well.
            if sticks[0] <= -threshold { out.buttons |= RetroPad.bit(RetroPad.left) }
            if sticks[0] >= threshold { out.buttons |= RetroPad.bit(RetroPad.right) }
            if sticks[1] <= -threshold { out.buttons |= RetroPad.bit(RetroPad.up) }
            if sticks[1] >= threshold { out.buttons |= RetroPad.bit(RetroPad.down) }
        }
        if applyTurbo { out.buttons = Self.turbo(out.buttons, ids: options.turbo ?? [], hz: turboHz, now: now) }
        return out
    }

    /// Buttons that repeat while held: pressed for the first half of each beat.
    public static func turbo(_ buttons: UInt16, ids: [Int], hz: Double, now: TimeInterval) -> UInt16 {
        guard !ids.isEmpty, hz > 0 else { return buttons }
        let on = Int((now * hz * 2).rounded(.down)) % 2 == 0
        if on { return buttons }
        var out = buttons
        for id in ids { out &= ~RetroPad.bit(id) }
        return out
    }
}

/// Keys into states: a TV remote by `KeyboardEvent.key` names, or a keyboard by `KeyboardEvent.code`
/// names, from the console's `defaults.remote` or `defaults.keyboard`.
public struct KeyMapper: Equatable {
    /// Key name to the targets it presses.
    public let targets: [String: [Int]]

    public init(_ map: [String: String]?) {
        var out: [String: [Int]] = [:]
        for (key, name) in map ?? [:] {
            guard let target = Int(key), (0...23).contains(target) else { continue }
            out[name, default: []].append(target)
        }
        targets = out.mapValues { $0.sorted() }
    }

    public func state(held: Set<String>, port: UInt8 = 0) -> PadState {
        var out = PadState(port: port)
        var push = [Int16](repeating: 0, count: 24)
        for name in held {
            for target in targets[name] ?? [] {
                if target < 16 { out.buttons |= RetroPad.bit(target) } else { push[target] = 32767 }
            }
        }
        if out.pressed(RetroPad.l2) { out.l2 = 255 }
        if out.pressed(RetroPad.r2) { out.r2 = 255 }
        func axis(_ minus: Int, _ plus: Int) -> Int16 { push[plus] != 0 ? 32767 : (push[minus] != 0 ? -32767 : 0) }
        out.lx = axis(RetroPad.leftStickLeft, RetroPad.leftStickRight)
        out.ly = axis(RetroPad.leftStickUp, RetroPad.leftStickDown)
        out.rx = axis(RetroPad.rightStickLeft, RetroPad.rightStickRight)
        out.ry = axis(RetroPad.rightStickUp, RetroPad.rightStickDown)
        return out
    }

    /// A key name this mapping knows, for a remote that can only reach a few.
    public func knows(_ name: String) -> Bool { targets[name] != nil }
}

/// What the shortcut button and another can do, by the person's `hotkeys.pad.*` settings.
public enum PadShortcut: String, CaseIterable {
    case menu, fastForward, rewind, quickSave, quickLoad, slow, pause, advance, screenshot

    /// Held for as long as the buttons are, rather than done once.
    public var isHeld: Bool { self == .fastForward || self == .rewind || self == .slow }
}

/// Shortcuts held with a modifier, as the website's player has them. Start and Select together
/// always open the menu. A button used for a shortcut isn't seen by the game until it's let go.
public struct PadShortcuts: Equatable {
    public let modifier: UInt16
    public let combos: Bool
    public let byBit: [UInt16: PadShortcut]
    /// Whether the console has the modifier: if not, the game never sees it.
    public let consoleHasModifier: Bool
    private var last: UInt16 = 0
    private var hidden: UInt16 = 0
    private var running: [UInt16: PadShortcut] = [:]

    public init(settings: GameSettings?, consoleButtons: Set<Int>) {
        let modifierName = settings?.text("hotkeys.padModifier", "select") ?? "select"
        let modifierId = RetroPad.names[modifierName] ?? RetroPad.select
        modifier = RetroPad.bit(modifierId)
        combos = settings?.flag("hotkeys.padCombos", true) ?? true
        consoleHasModifier = consoleButtons.isEmpty || consoleButtons.contains(modifierId)
        let fallback: [PadShortcut: String] = [.fastForward: "r", .rewind: "l", .quickSave: "r2", .quickLoad: "l2", .slow: "x",
                                               .pause: "y", .advance: "right", .screenshot: "a", .menu: "b"]
        var table: [UInt16: PadShortcut] = [:]
        for shortcut in PadShortcut.allCases {
            let name = settings?.text("hotkeys.pad.\(shortcut.rawValue)", fallback[shortcut] ?? "none") ?? fallback[shortcut] ?? "none"
            guard let id = RetroPad.names[name] else { continue }
            let bit = RetroPad.bit(id)
            if bit != modifier, table[bit] == nil { table[bit] = shortcut }
        }
        byBit = table
    }

    public struct Result: Equatable {
        public var buttons: UInt16
        public var started: [PadShortcut]
        public var ended: [PadShortcut]
    }

    /// Ends every shortcut in progress, for a controller that went away or a menu that opened.
    /// Returns the held ones, which have to be told to stop.
    public mutating func endAll() -> [PadShortcut] {
        let held = running.values.filter(\.isHeld).sorted { $0.rawValue < $1.rawValue }
        running = [:]
        hidden = 0
        last = 0
        return held
    }

    /// What the game should see of these buttons, and which shortcuts began or ended.
    public mutating func filter(_ buttons: UInt16) -> Result {
        let down = buttons & ~last
        var started: [PadShortcut] = []
        var ended: [PadShortcut] = []
        let menuPair = RetroPad.bit(RetroPad.start) | RetroPad.bit(RetroPad.select)
        if buttons & menuPair == menuPair, down & menuPair != 0 {
            started.append(.menu)
            hidden |= menuPair
        } else if combos, buttons & modifier != 0 {
            for (bit, shortcut) in byBit where down & bit != 0 {
                started.append(shortcut)
                hidden |= bit
                running[bit] = shortcut
            }
        }
        // Let go: the button counts again, and a held shortcut stops.
        for (bit, shortcut) in running where buttons & bit == 0 {
            if shortcut.isHeld { ended.append(shortcut) }
            running.removeValue(forKey: bit)
        }
        hidden &= buttons
        last = buttons
        var seen = buttons & ~hidden
        if !consoleHasModifier { seen &= ~modifier }
        return Result(buttons: seen, started: started.sorted { $0.rawValue < $1.rawValue }, ended: ended.sorted { $0.rawValue < $1.rawValue })
    }
}

/// Which profiles apply to a controller: the server keys them by `vendor:product` in lowercase hex.
/// tvOS doesn't give an app those numbers, so the common controllers are known by their kind, and
/// anything else goes by its name.
public enum PadIdentity {
    static let known: [String: String] = [
        "DualSense": "054c:0ce6",
        "DualSense Edge": "054c:0df2",
        "DualShock 4": "054c:09cc",
        "Xbox One": "045e:0b13",
        "Xbox Series": "045e:0b13",
        "Xbox Elite": "045e:0b05",
        "Xbox Adaptive": "045e:0b0a",
        "Switch Pro Controller": "057e:2009",
        "Nintendo Switch Pro Controller": "057e:2009",
        "Joy-Con (L/R)": "057e:200e",
    ]

    /// The key a profile names this controller by.
    public static func key(productCategory: String, vendorName: String?) -> String {
        if let numbers = known[productCategory] { return numbers }
        let name = (vendorName ?? "").isEmpty ? productCategory : vendorName!
        return "id:" + String(name.prefix(60))
    }
}
