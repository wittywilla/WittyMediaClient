// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// A look's layout as a small wireframe (the canvas's wire thumbnails): the menu where it is and how it is drawn, how Home
// starts, what the cards are, where the server's name sits and the finish, in the previewed theme's colours. It draws the
// server's own `wire` of the experience (`LayoutWire`), shapes only. Where a person chooses a look (Settings > Appearance,
// the first-connect chooser, Who must use what), this is what a card shows.

struct LayoutThumb: View {
    let wire: LayoutWire
    /// Background, second background and accent, as `#rrggbb`.
    let swatches: [String]
    /// A phone's layout: drawn upright, the shape of a phone's screen, never taller than a phone in the hand.
    var portrait = false

    private func colour(_ index: Int, fallback: String) -> Color {
        let hex = swatches.indices.contains(index) ? swatches[index] : fallback
        guard let c = ThemeColour(hex: hex) else { return .gray }
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    private var isLight: Bool {
        swatches.first.flatMap(ThemeColour.init(hex:)).map { 0.299 * $0.red + 0.587 * $0.green + 0.114 * $0.blue > 0.6 } ?? false
    }

    var body: some View {
        let corner: CGFloat = portrait ? 14 : 6
        Canvas { ctx, size in
            draw(&ctx, size)
        }
        .aspectRatio(portrait ? 0.56 : 16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(Color.gray.opacity(0.4), lineWidth: portrait ? 2 : 1))
        .frame(maxHeight: portrait ? 420 : nil)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let bg = colour(0, fallback: "#0f1115"), surface = colour(1, fallback: "#1f232c"), accent = colour(2, fallback: "#7955ff")
        let ink: Color = isLight ? .black : .white
        let w = size.width, h = size.height
        let square = wire.style == "cable" || wire.style == "tele" || wire.style == "bevel"
        let r: CGFloat = square ? 0 : max(2, h * 0.03)
        func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ fill: Color, radius: CGFloat? = nil) {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: max(0, rw), height: max(0, rh)), cornerRadius: radius ?? r), with: .color(fill))
        }
        func entries(_ x: CGFloat, _ y: CGFloat, _ ew: CGFloat, _ eh: CGFloat, _ gap: CGFloat, _ n: Int, vertical: Bool = false) {
            for i in 0..<n {
                let on = i == 0
                let fill: Color = on ? accent : ink.opacity(0.3)
                let (ex, ey) = vertical ? (x, y + CGFloat(i) * (eh + gap)) : (x + CGFloat(i) * (ew + gap), y)
                switch wire.style {
                case "under":
                    rect(ex, ey, ew, eh * 0.35, ink.opacity(0.35), radius: 1)
                    if on { rect(ex, ey + eh * 0.55, ew, eh * 0.14, accent, radius: 0) }
                case "tele": rect(ex, ey, ew, eh, [Color.red, .green, .yellow, .blue, .white][i % 5].opacity(0.85), radius: 0)
                case "cable": rect(ex, ey, ew, eh, on ? .white.opacity(0.95) : .white.opacity(0.4), radius: 0)
                case "bevel":
                    rect(ex, ey, ew, eh, on ? accent : ink.opacity(0.22), radius: 1)
                    rect(ex, ey, ew, 1, .white.opacity(0.45), radius: 0)
                default: rect(ex, ey, ew, eh, fill, radius: wire.style == "pill" || wire.style == "gloss" ? eh * 0.5 : 2)
                }
            }
        }
        rect(0, 0, w, h, bg, radius: 0)

        // The menu: what it takes from the page.
        var left: CGFloat = 0, top: CGFloat = 0, bottom: CGFloat = 0
        let barH = h * (portrait ? 0.065 : 0.12)
        let barFill: Color = wire.style == "cable" ? accent.opacity(0.9) : surface
        func brandMark(_ x: CGFloat, _ y: CGFloat, _ bw: CGFloat, _ bh: CGFloat) {
            rect(x, y, bw, bh, wire.style == "cable" ? .white : accent, radius: 2)
        }
        switch wire.nav {
        case "top":
            if wire.style == "gloss" {
                rect(w * 0.18, h * 0.03, w * 0.64, barH * 0.9, surface.opacity(0.85), radius: barH * 0.5)
                rect(w * 0.2, h * 0.03 + 1, w * 0.6, barH * 0.35, .white.opacity(0.22), radius: barH * 0.3)
                brandMark(w * 0.22, h * 0.03 + barH * 0.25, w * 0.08, barH * 0.4)
                entries(w * 0.36, h * 0.03 + barH * 0.28, w * 0.08, barH * 0.35, w * 0.03, 4)
                top = barH * 1.1
            } else {
                rect(0, 0, w, barH * (wire.style == "cable" ? 1.2 : 1), barFill, radius: 0)
                if wire.style == "bevel" { rect(0, 0, w, 1.5, .white.opacity(0.4), radius: 0); rect(0, barH - 1.5, w, 1.5, .black.opacity(0.35), radius: 0) }
                if wire.finish == "gloss" { rect(0, 0, w, barH * 0.45, .white.opacity(0.14), radius: 0) }
                brandMark(w * 0.03, barH * 0.28, w * 0.1, barH * 0.44)
                entries(w * 0.28, barH * 0.28, w * 0.09, barH * 0.44, w * 0.025, 5)
                top = barH * (wire.style == "cable" ? 1.2 : 1)
            }
        case "side":
            let sw = wire.open ? w * 0.22 : w * 0.12
            rect(0, 0, sw, h, surface, radius: 0)
            brandMark(w * 0.02, h * 0.05, sw * 0.5, h * 0.05)
            entries(w * 0.02, h * 0.2, sw - w * 0.04, h * 0.05, h * 0.04, 5, vertical: true)
            left = sw
        case "rail":
            rect(0, 0, w * 0.075, h, surface, radius: 0)
            brandMark(w * 0.02, h * 0.05, w * 0.035, w * 0.035)
            entries(w * 0.022, h * 0.2, w * 0.032, w * 0.032, h * 0.05, 5, vertical: true)
            left = w * 0.075
        case "bottom":
            rect(w * 0.1, h - barH * 1.3, w * 0.8, barH, surface, radius: barH * 0.5)
            entries(w * 0.2, h - barH * 1.05, w * 0.06, barH * 0.5, w * 0.11, 4)
            bottom = barH * 1.4
        default:
            // None: the categories are part of the page (a crossbar).
            rect(0, 0, w, barH * 1.3, surface, radius: 0)
            for i in 0..<6 { rect(w * (0.12 + CGFloat(i) * 0.13), barH * 0.3, w * (i == 2 ? 0.1 : 0.06), barH * 0.7, i == 2 ? accent : ink.opacity(0.3), radius: 2) }
            top = barH * 1.3
        }
        if wire.brand == "centre" { rect(w * 0.44, h * 0.0, w * 0.12, barH * 0.35, accent, radius: 2) }
        if wire.dock {
            // A dock of keys at the foot of the screen (television, headset).
            for i in 0..<4 { rect(w * (0.3 + CGFloat(i) * 0.1), h - h * 0.06, w * 0.07, h * 0.03, ink.opacity(0.35), radius: 1) }
            bottom = max(bottom, h * 0.08)
        }

        // The page, in what is left.
        let x0 = left + w * 0.035, x1 = w - w * 0.035
        let pw = x1 - x0
        var y = top + h * 0.035
        let yEnd = h - bottom - h * 0.03
        let gap = h * 0.035

        switch wire.home {
        case "hero":
            let hh = (yEnd - y) * (portrait ? 0.3 : 0.46)
            rect(x0, y, pw, hh, surface, radius: r)
            rect(x0, y, pw, hh * 0.5, accent.opacity(0.18), radius: r)
            for i in 0..<3 { rect(x0 + pw * 0.04, y + hh * (0.3 + CGFloat(i) * 0.16), pw * (i == 0 ? 0.34 : 0.24), hh * 0.08, ink.opacity(0.5), radius: 1) }
            rect(x0 + pw * 0.04, y + hh * 0.8, pw * 0.12, hh * 0.12, accent, radius: square ? 0 : 2)
            y += hh + gap
        case "banner":
            let hh = (yEnd - y) * (portrait ? 0.2 : 0.3)
            rect(x0, y, pw, hh, surface, radius: r)
            rect(x0, y, pw * 0.5, hh, accent.opacity(0.18), radius: r)
            for i in 0..<2 { rect(x0 + pw * 0.04, y + hh * (0.25 + CGFloat(i) * 0.25), pw * 0.28, hh * 0.12, ink.opacity(0.5), radius: 1) }
            y += hh + gap
        case "carousel":
            let hh = (yEnd - y) * (portrait ? 0.32 : 0.55)
            for (i, scale) in [0.62, 1.0, 0.62].enumerated() {
                let cw = hh * 0.62 * scale, chh = hh * scale
                let cx = x0 + pw / 2 + (CGFloat(i) - 1) * hh * 0.7 - cw / 2
                rect(cx, y + (hh - chh) / 2, cw, chh, i == 1 ? accent.opacity(0.35) : surface, radius: r)
            }
            y += hh + gap
        case "list":
            let hh = (yEnd - y) * 0.2
            for i in 0..<3 { rect(x0 + CGFloat(i) * pw * 0.33, y, pw * 0.3, hh, i == 0 ? accent.opacity(0.3) : surface, radius: r) }
            y += hh + gap
        default: break
        }

        let avail = yEnd - y
        func title(_ yy: CGFloat) {
            if wire.style == "cable" { rect(x0, yy, pw, h * 0.04, accent.opacity(0.7), radius: 0) }
            else { rect(x0, yy, pw * 0.18, h * 0.022, ink.opacity(0.5), radius: 1) }
        }
        switch wire.home {
        case "widgets":
            let cells: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, 0, 0.45, 1), (0.47, 0, 0.25, 0.48), (0.74, 0, 0.26, 0.48), (0.47, 0.52, 0.53, 0.48)]
            for (i, c) in cells.enumerated() { rect(x0 + pw * c.0, y + c.1 * avail, pw * c.2, c.3 * avail, i == 0 ? accent.opacity(0.25) : surface, radius: r) }
        case "cross":
            for i in 0..<4 { rect(x0 + pw * 0.3, y + CGFloat(i) * h * 0.1, pw * 0.5, h * 0.07, i == 0 ? accent.opacity(0.5) : surface, radius: 3) }
        case "list":
            title(y)
            let n = max(2, Int((avail - h * 0.05) / (h * 0.085)))
            for i in 0..<n {
                let yy = y + h * 0.05 + CGFloat(i) * h * 0.085
                if wire.cards != "block" { rect(x0, yy, h * 0.06, h * 0.06, surface, radius: square ? 0 : 2) }
                rect(x0 + (wire.cards != "block" ? h * 0.08 : 0), yy + h * 0.008, pw * (i % 2 == 0 ? 0.45 : 0.35), h * 0.025, ink.opacity(0.4), radius: 1)
                rect(x0 + pw * 0.8, yy + h * 0.015, pw * 0.15, h * 0.02, accent.opacity(0.5), radius: 1)
            }
        default:
            title(y)
            let tiles = wire.home == "tiles"
            switch wire.cards {
            case "landscape", "logo":
                let n = portrait ? 2 : (tiles ? 3 : 4)
                let cw = (pw - CGFloat(n - 1) * w * 0.015) / CGFloat(n)
                let ch = min(avail - h * 0.06, cw * (tiles ? 0.8 : 0.56))
                let rows = portrait ? max(1, Int((avail - h * 0.02) / (ch + h * 0.06))) : 1
                for row in 0..<rows {
                    let yy = y + h * 0.05 + CGFloat(row) * (ch + h * 0.06)
                    for i in 0..<n { rect(x0 + CGFloat(i) * (cw + w * 0.015), yy, cw, ch, surface, radius: wire.cards == "logo" ? 2 : r) }
                }
            case "block":
                let rowsN = max(1, Int((avail - h * 0.05) / (h * 0.11)))
                let cw = (pw - 5 * w * 0.01) / 6
                for rr in 0..<rowsN { for cc in 0..<6 { rect(x0 + CGFloat(cc) * (cw + w * 0.01), y + h * 0.05 + CGFloat(rr) * h * 0.11, cw, h * 0.095, (cc + rr) % 3 == 0 ? accent.opacity(0.45) : surface, radius: 0) } }
            default:
                // Rows of posters: one row on a wide screen, as many as fit on a phone's.
                let rowH = portrait ? min(max(0, avail - h * 0.06), h * 0.17) : max(0, avail - h * 0.06)
                let rows = portrait ? max(1, Int((avail - h * 0.02) / (rowH + h * 0.06))) : 1
                let ph = rowH
                let cw = ph * 0.62
                let count = max(1, Int(pw / (cw + w * 0.015)))
                for row in 0..<rows {
                    let yy = y + h * 0.05 + CGFloat(row) * (ph + h * 0.06)
                    if row > 0 { rect(x0, yy - h * 0.04, pw * 0.3, h * 0.016, ink.opacity(0.4), radius: 1) }
                    for i in 0..<count {
                        let cx = x0 + CGFloat(i) * (cw + w * 0.015)
                        rect(cx, yy, cw, ph, surface, radius: r)
                        if wire.cards == "plate" { rect(cx, yy + ph * 0.72, cw, ph * 0.28, accent.opacity(0.35), radius: r) }
                    }
                }
            }
        }
        if wire.finish == "crt" {
            var yy: CGFloat = 0
            while yy < h { rect(0, yy, w, 0.7, .black.opacity(0.18), radius: 0); yy += 3 }
        }
    }
}
