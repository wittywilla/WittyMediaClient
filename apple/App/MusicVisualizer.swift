// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// MARK: - The visualizer

/// Bars, Waves and Drift, drawn from the sound as the website's backdrop does: 30 a second, or 20 when slow.
final class VisualizerDrawer {
    struct Mote { var x: Double, y: Double, r: Double, vx: Double, vy: Double, band: Int }
    var levels = [Double](repeating: 0, count: VisualizerLevels.count)
    var motes: [Mote] = (0..<14).map { i in
        Mote(x: .random(in: 0...1), y: .random(in: 0...1), r: 0.12 + .random(in: 0...0.2),
             vx: (.random(in: 0...1) - 0.5) * 0.02, vy: (.random(in: 0...1) - 0.5) * 0.02, band: i % 6)
    }
    var bins = [UInt8](repeating: 0, count: 1024)
    var last: Date?
    var t = 0.0

    func step(at now: Date, active: Bool, slow: Bool) -> Double {
        let dt = min(0.2, last.map { now.timeIntervalSince($0) } ?? 0.033)
        last = now
        let heard = active && SoundEngine.shared.spectrum(into: &bins)
        let rise = slow ? 2.5 : 14.0, fall = slow ? 1.0 : 3.2
        let ms = now.timeIntervalSinceReferenceDate * 1000
        for i in 0..<levels.count {
            var v = 0.0
            if heard {
                let range = VisualizerLevels.bins(i)
                var peak: UInt8 = 0
                for k in range where k < bins.count { peak = max(peak, bins[k]) }
                v = VisualizerLevels.level(peak: peak, at: i)
            } else if active {
                v = 0.18 + 0.1 * sin(ms / 1400 + Double(i) * 0.5) + 0.05 * sin(ms / 700 + Double(i))
            }
            let old = levels[i]
            levels[i] = v > old ? old + (v - old) * min(1, dt * rise) : old + (v - old) * min(1, dt * fall)
        }
        t += dt * (slow ? 0.35 : 1)
        return dt
    }

    func band(_ a: Int, _ b: Int) -> Double { levels[a..<min(b, levels.count)].reduce(0, +) / Double(max(1, b - a)) }
}

struct VisualizerBackground: View {
    let style: String
    let slow: Bool
    let colour: Color
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var drawer = VisualizerDrawer()

    var body: some View {
        let gentle = slow || calm
        TimelineView(.animation(minimumInterval: gentle ? 1.0 / 20 : 1.0 / 30, paused: !playing && drawer.levels.allSatisfy { $0 < 0.004 })) { timeline in
            Canvas { context, size in
                let dt = drawer.step(at: timeline.date, active: playing, slow: gentle)
                switch style {
                case "waves": waves(&context, size)
                case "drift": drift(&context, size, dt: dt, gentle: gentle)
                default: bars(&context, size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bars(_ g: inout GraphicsContext, _ size: CGSize) {
        let n = VisualizerLevels.count
        let gap = size.width / CGFloat(n * 2)
        let width = gap * 0.62
        let base = size.height * 0.62, tall = size.height * 0.46
        let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: [colour.opacity(0.55), colour.opacity(0)]),
                                                             startPoint: CGPoint(x: 0, y: base - tall), endPoint: CGPoint(x: 0, y: base))
        for i in 0..<n {
            let v = 0.12 + drawer.levels[i] * 0.88
            let height = min(tall, CGFloat(v) * tall)
            let off = (CGFloat(i) + 0.5) * gap
            var layer = g
            layer.opacity = 1 - Double(i) / Double(n) * 0.72
            layer.fill(Path(CGRect(x: size.width / 2 + off - width / 2, y: base - height, width: width, height: height)), with: shading)
            layer.fill(Path(CGRect(x: size.width / 2 - off - width / 2, y: base - height, width: width, height: height)), with: shading)
        }
    }

    private func waves(_ g: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let low = drawer.band(0, 4), mid = drawer.band(4, 12), high = drawer.band(12, 23)
        let layers: [(a: Double, f: Double, s: Double, y: Double, o: Double)] = [
            (0.2 + low * 0.3, 1.2, 0.5, 0.62, 0.3), (0.12 + mid * 0.28, 2.1, -0.7, 0.6, 0.22), (0.07 + high * 0.22, 3.4, 1, 0.58, 0.16),
        ]
        for layer in layers {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h))
            var x = 0.0
            while x <= Double(w) {
                let u = x / Double(w)
                let envelope = sin(u * .pi) * 0.8 + 0.2
                let y = Double(h) * layer.y - envelope * Double(h) * 0.42 * layer.a * (0.6 + 0.4 * sin(u * layer.f * 6.283 + drawer.t * layer.s * 1.4))
                    - Double(h) * 0.02 * sin(u * 3 + drawer.t * layer.s)
                path.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
            g.fill(path, with: .linearGradient(Gradient(colors: [colour.opacity(layer.o), colour.opacity(0)]),
                                               startPoint: CGPoint(x: 0, y: h * 0.2), endPoint: CGPoint(x: 0, y: h * 0.8)))
        }
    }

    private func drift(_ g: inout GraphicsContext, _ size: CGSize, dt: Double, gentle: Bool) {
        let w = Double(size.width), h = Double(size.height)
        let push = gentle ? 0.35 : 1
        var layer = g
        layer.blendMode = .plusLighter
        for index in drawer.motes.indices {
            var m = drawer.motes[index]
            let level = drawer.levels[min(drawer.levels.count - 1, m.band * 3)]
            m.x += m.vx * dt * push * (1 + level * 2)
            m.y += m.vy * dt * push * (1 + level * 2)
            if m.x < -0.2 { m.x = 1.2 } else if m.x > 1.2 { m.x = -0.2 }
            if m.y < -0.2 { m.y = 1.2 } else if m.y > 1.2 { m.y = -0.2 }
            drawer.motes[index] = m
            let side = (m.r + level * 0.1) * max(w, h)
            let rect = CGRect(x: m.x * w - side / 2, y: m.y * h - side / 2, width: side, height: side)
            var mote = layer
            mote.opacity = 0.45 + min(0.45, level * 0.5)
            mote.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [.init(color: colour.opacity(0.5), location: 0), .init(color: colour.opacity(0.16), location: 0.5),
                                 .init(color: colour.opacity(0), location: 1)]),
                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: side / 2))
        }
    }
}

/// Things in a row that wrap onto the next line, centred, as the website's flex-wrap rows.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var centred = true

    private func lines(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var all: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if !all[all.count - 1].isEmpty, used + spacing + size.width > width {
                all.append([])
                used = 0
            }
            used += (all[all.count - 1].isEmpty ? 0 : spacing) + size.width
            all[all.count - 1].append(index)
        }
        return all
    }

    /// A row's tallest, and its width with the gaps: spelled out, as CI's type-checker gave up on the one-liners.
    private func rowHeight(_ row: [Int], _ sizes: [CGSize]) -> CGFloat {
        var tallest: CGFloat = 0
        for index in row { tallest = max(tallest, sizes[index].height) }
        return tallest
    }

    private func rowWidth(_ row: [Int], _ sizes: [CGSize]) -> CGFloat {
        var total: CGFloat = 0
        for index in row { total += sizes[index].width }
        return total + CGFloat(max(0, row.count - 1)) * spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width: CGFloat = proposal.width ?? .infinity
        let sizes: [CGSize] = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows: [[Int]] = lines(sizes, width: width)
        var height: CGFloat = CGFloat(max(0, rows.count - 1)) * lineSpacing
        var widest: CGFloat = 0
        for row in rows {
            height += rowHeight(row, sizes)
            widest = max(widest, rowWidth(row, sizes))
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes: [CGSize] = subviews.map { $0.sizeThatFits(.unspecified) }
        var y: CGFloat = bounds.minY
        for row in lines(sizes, width: bounds.width) {
            let rowWidth: CGFloat = rowWidth(row, sizes)
            let rowHeight: CGFloat = rowHeight(row, sizes)
            var x: CGFloat = centred ? bounds.minX + (bounds.width - rowWidth) / 2 : bounds.minX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (rowHeight - sizes[index].height) / 2), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}
