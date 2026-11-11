// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The pictures a profile can choose. The server keeps only the choice, as "name:colour", and every app
// draws it: one filled shape on a 24 by 24 grid, on one of the avatar colours. The shapes are the web
// client's own (`web/src/ui/avatars.tsx`), read here from the same path data, so a profile looks the same
// in the browser, on a phone and on a TV.

/// A profile's chosen picture, taken apart. Nil for none, and for one this app doesn't know: both show the initial.
public struct ProfilePicture: Equatable {
    public let name: String
    public let colourName: String
    /// The background, as "#rrggbb".
    public let colour: String

    /// Which of the shared avatar colours each colour name is.
    static let colourIndex: [String: Int] = ["red": 0, "orange": 1, "yellow": 2, "green": 3, "teal": 4, "blue": 5, "purple": 7, "pink": 8]

    /// In the order the server lists them, for a chooser shown before the server has answered.
    public static let names = ["star", "heart", "moon", "sun", "bolt", "diamond", "crown", "flower", "music", "planet", "paw", "tree",
                               "rocket", "gamepad", "book"]
    public static let colourNames = ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink"]

    public static func parse(_ avatar: String?) -> ProfilePicture? {
        guard let avatar, !avatar.isEmpty else { return nil }
        let parts = avatar.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, shapes[parts[0]] != nil, let hex = colour(named: parts[1]) else { return nil }
        return ProfilePicture(name: parts[0], colourName: parts[1], colour: hex)
    }

    public static func colour(named name: String) -> String? {
        colourIndex[name].map { AvatarLook.colours[$0] }
    }

    /// What the server keeps: "star:blue".
    public var value: String { "\(name):\(colourName)" }

    /// What a screen reader calls a picture or a colour being chosen: "Star", "Blue".
    public static func label(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }

    /// The shape, as steps to draw on the 24 grid, filled the way a browser fills an icon (non-zero winding), so the
    /// cut-outs in the gamepad and the book stay cut out.
    public var steps: [PathStep] { ProfilePicture.steps(for: name) }

    public static func steps(for name: String) -> [PathStep] {
        shapes[name].map(PathData.parse) ?? []
    }

    static let shapes: [String: String] = [
        "star": "M12 2.5l2.9 6.2 6.6.8-4.9 4.6 1.3 6.6L12 17.4l-5.9 3.3 1.3-6.6L2.5 9.5l6.6-.8z",
        "heart": "M12 20.5C6.5 16.3 3 13 3 9.2 3 6.6 5 4.6 7.5 4.6c1.7 0 3.4.9 4.5 2.4 1.1-1.5 2.8-2.4 4.5-2.4C19 4.6 21 6.6 21 9.2c0 3.8-3.5 7.1-9 11.3z",
        "moon": "M20 14.5A8.5 8.5 0 019.5 4a8.5 8.5 0 1010.5 10.5z",
        "sun": "M12 7a5 5 0 100 10 5 5 0 000-10zM11 1h2v4h-2zM11 19h2v4h-2zM1 11h4v2H1zM19 11h4v2h-4zM4.2 5.6l1.4-1.4 2.8 2.8L7 8.4zM15.6 17l1.4-1.4 2.8 2.8-1.4 1.4zM4.2 18.4L7 15.6 8.4 17l-2.8 2.8zM15.6 7l2.8-2.8 1.4 1.4L17 8.4z",
        "bolt": "M13.5 2L5 13.5h5.5L9.5 22 19 10h-5.5z",
        "diamond": "M12 2.5l8.5 9.5-8.5 9.5L3.5 12z",
        "crown": "M4 18.5h16v2H4zM3 7.5l4.8 3.8L12 4.5l4.2 6.8L21 7.5l-1.6 9H4.6z",
        "flower": "M12 9.2a2.8 2.8 0 100 5.6 2.8 2.8 0 000-5.6zM12 2a3 3 0 100 6 3 3 0 000-6zM12 16a3 3 0 100 6 3 3 0 000-6zM5 9a3 3 0 100 6 3 3 0 000-6zM19 9a3 3 0 100 6 3 3 0 000-6z",
        "music": "M10 3.5v10.2a3.5 3.5 0 102 3.1V7.5h5v-4z",
        "planet": "M12 6a6 6 0 100 12 6 6 0 000-12zM2.6 15.6l.9 1.7 17.9-8.9-.9-1.7z",
        "paw": "M12 12c-3 0-5.5 2.5-5.5 5 0 1.7 1.4 2.5 2.8 2.5 1 0 1.8-.5 2.7-.5s1.7.5 2.7.5c1.4 0 2.8-.8 2.8-2.5 0-2.5-2.5-5-5.5-5zM6.5 7.7a1.8 1.8 0 100 3.6 1.8 1.8 0 000-3.6zM10 4.2a1.8 1.8 0 100 3.6 1.8 1.8 0 000-3.6zM14 4.2a1.8 1.8 0 100 3.6 1.8 1.8 0 000-3.6zM17.5 7.7a1.8 1.8 0 100 3.6 1.8 1.8 0 000-3.6z",
        "tree": "M12 2l7 10h-4l4 6h-6v4h-2v-4H5l4-6H5z",
        "rocket": "M12 2c3 2.5 4.5 6 4.5 10v5h-9v-5C7.5 8 9 4.5 12 2zM7.5 13L4 17v3l3.5-2zM16.5 13l3.5 4v3l-3.5-2zM10.5 18h3L12 22z",
        "gamepad": "M7 7h10a5 5 0 015 5v3.5a3.5 3.5 0 01-6.3 2.1L14.5 16h-5l-1.2 1.6A3.5 3.5 0 012 15.5V12a5 5 0 015-5zM7 10v1.5H5.5v2H7V15h2v-1.5h1.5v-2H9V10zM16 10a1.25 1.25 0 100 2.5 1.25 1.25 0 000-2.5zM18.5 12.5a1.25 1.25 0 100 2.5 1.25 1.25 0 000-2.5z",
        "book": "M5 3h12a2 2 0 012 2v16H7a2 2 0 01-2-2zM7 17v2h10v-2zM8 6v2h8V6z",
    ]
}

/// One step of a drawn shape, in the shape's own units.
public enum PathStep: Equatable {
    case move(x: Double, y: Double)
    case line(x: Double, y: Double)
    case curve(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
    case close
}

/// Reads the path data of an SVG icon: the commands M L H V C S A Z in either case, with numbers run together
/// the way icon files write them ("019.5 4" is two flags and two numbers). Arcs become curves, which is all a
/// drawing surface needs. Anything it can't read ends the shape there rather than drawing something wrong.
public enum PathData {
    public static func parse(_ data: String) -> [PathStep] {
        var reader = Reader(Array(data.unicodeScalars))
        var steps: [PathStep] = []
        var x = 0.0, y = 0.0          // where the pen is
        var startX = 0.0, startY = 0.0 // where this outline began
        var lastC2: (Double, Double)?  // the last curve's second handle, for S
        var command: UnicodeScalar = " "
        while true {
            reader.skipSpace()
            guard let next = reader.peek else { break }
            if isLetter(next) {
                command = next
                reader.advance()
                if command == "Z" || command == "z" {
                    steps.append(.close)
                    x = startX; y = startY
                    lastC2 = nil
                    continue
                }
            } else if command == " " {
                break
            }
            let relative = command.properties.isLowercase
            let dx = relative ? x : 0, dy = relative ? y : 0
            switch command {
            case "M", "m":
                guard let px = reader.number(), let py = reader.number() else { return steps }
                x = px + dx; y = py + dy
                startX = x; startY = y
                steps.append(.move(x: x, y: y))
                // More pairs after a move are lines.
                command = relative ? "l" : "L"
                lastC2 = nil
            case "L", "l":
                guard let px = reader.number(), let py = reader.number() else { return steps }
                x = px + dx; y = py + dy
                steps.append(.line(x: x, y: y))
                lastC2 = nil
            case "H", "h":
                guard let px = reader.number() else { return steps }
                x = px + dx
                steps.append(.line(x: x, y: y))
                lastC2 = nil
            case "V", "v":
                guard let py = reader.number() else { return steps }
                y = py + dy
                steps.append(.line(x: x, y: y))
                lastC2 = nil
            case "C", "c":
                guard let x1 = reader.number(), let y1 = reader.number(), let x2 = reader.number(), let y2 = reader.number(),
                      let px = reader.number(), let py = reader.number() else { return steps }
                steps.append(.curve(x1: x1 + dx, y1: y1 + dy, x2: x2 + dx, y2: y2 + dy, x: px + dx, y: py + dy))
                lastC2 = (x2 + dx, y2 + dy)
                x = px + dx; y = py + dy
            case "S", "s":
                guard let x2 = reader.number(), let y2 = reader.number(), let px = reader.number(), let py = reader.number() else { return steps }
                // The first handle mirrors the last curve's second one.
                let first = lastC2.map { (2 * x - $0.0, 2 * y - $0.1) } ?? (x, y)
                steps.append(.curve(x1: first.0, y1: first.1, x2: x2 + dx, y2: y2 + dy, x: px + dx, y: py + dy))
                lastC2 = (x2 + dx, y2 + dy)
                x = px + dx; y = py + dy
            case "A", "a":
                guard let rx = reader.number(), let ry = reader.number(), let turn = reader.number(),
                      let large = reader.flag(), let sweep = reader.flag(),
                      let px = reader.number(), let py = reader.number() else { return steps }
                steps.append(contentsOf: arc(fromX: x, fromY: y, rx: rx, ry: ry, turn: turn, large: large, sweep: sweep, toX: px + dx, toY: py + dy))
                x = px + dx; y = py + dy
                lastC2 = nil
            default:
                return steps
            }
        }
        return steps
    }

    private static func isLetter(_ c: UnicodeScalar) -> Bool {
        (c >= "a" && c <= "z" && c != "e") || (c >= "A" && c <= "Z" && c != "E")
    }

    /// An elliptical arc as curves, by the SVG standard's own conversion (F.6.5), in pieces of a quarter turn at most.
    static func arc(fromX x0: Double, fromY y0: Double, rx rawRx: Double, ry rawRy: Double, turn: Double, large: Bool, sweep: Bool,
                    toX x: Double, toY y: Double) -> [PathStep] {
        var rx = abs(rawRx), ry = abs(rawRy)
        if (x0 == x && y0 == y) { return [] }
        if rx == 0 || ry == 0 { return [.line(x: x, y: y)] }
        let phi = turn * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let hx = (x0 - x) / 2, hy = (y0 - y) / 2
        let x1 = cosPhi * hx + sinPhi * hy
        let y1 = -sinPhi * hx + cosPhi * hy
        // Radii too small to reach are grown until they do.
        let reach = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if reach > 1 {
            rx *= reach.squareRoot()
            ry *= reach.squareRoot()
        }
        let top = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let bottom = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = bottom == 0 ? 0 : max(0, top / bottom).squareRoot()
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let cx = cosPhi * cx1 - sinPhi * cy1 + (x0 + x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (y0 + y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let start = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var sweepAngle = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }
        let pieces = max(1, Int((abs(sweepAngle) / (.pi / 2)).rounded(.up)))
        let step = sweepAngle / Double(pieces)
        let handle = 4.0 / 3.0 * tan(step / 4)
        var out: [PathStep] = []
        func point(_ a: Double) -> (Double, Double) {
            (cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi, cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func slope(_ a: Double) -> (Double, Double) {
            (-rx * sin(a) * cosPhi - ry * cos(a) * sinPhi, -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        for piece in 0..<pieces {
            let a = start + Double(piece) * step, b = a + step
            let from = point(a), to = point(b)
            let leaving = slope(a), arriving = slope(b)
            // The last piece ends exactly where the path said, not where the arithmetic landed.
            let end = piece == pieces - 1 ? (x, y) : to
            out.append(.curve(x1: from.0 + handle * leaving.0, y1: from.1 + handle * leaving.1,
                              x2: to.0 - handle * arriving.0, y2: to.1 - handle * arriving.1, x: end.0, y: end.1))
        }
        return out
    }

    private struct Reader {
        let text: [UnicodeScalar]
        var at = 0
        init(_ text: [UnicodeScalar]) { self.text = text }

        var peek: UnicodeScalar? { at < text.count ? text[at] : nil }
        mutating func advance() { at += 1 }

        mutating func skipSpace() {
            while let c = peek, c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { at += 1 }
        }

        /// One number: a sign, digits, one point, more digits. A second point or a sign starts the next number.
        mutating func number() -> Double? {
            skipSpace()
            var seen = ""
            if let c = peek, c == "-" || c == "+" { seen.unicodeScalars.append(c); at += 1 }
            var point = false, digits = false
            while let c = peek {
                if c >= "0" && c <= "9" {
                    digits = true
                } else if c == ".", !point {
                    point = true
                } else {
                    break
                }
                seen.unicodeScalars.append(c)
                at += 1
            }
            return digits ? Double(seen) : nil
        }

        /// An arc's flag: a single 0 or 1, which may have the next number right after it.
        mutating func flag() -> Bool? {
            skipSpace()
            guard let c = peek, c == "0" || c == "1" else { return nil }
            at += 1
            return c == "1"
        }
    }
}
