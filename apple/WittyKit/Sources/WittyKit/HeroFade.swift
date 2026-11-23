// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// How a backdrop fades into the page (WittyMediaServer #545, `--hero-fade` in styles.css): by its own alpha, a mask,
/// never by painting the page's colour over it, so it melts into a gradient, a scene or a picture behind the page as
/// well as into a flat colour. Solid down to `from`, then eased out (slow at the end) to nothing at the bottom. With
/// `topIn`, the top edge fades in too, for a picture that doesn't start under the bar.
public enum HeroFade {
    public struct Stop: Equatable, Sendable {
        public let location: Double
        public let alpha: Double
    }

    /// Where the fade starts: Home's billboard 48% down, a title's header 46%, a title's header on a phone 34%.
    public static let billboard = 0.48
    public static let title = 0.46
    public static let titleOnPhone = 0.34

    private static let ease: [(at: Double, alpha: Double)] = [(0.23, 0.86), (0.44, 0.62), (0.63, 0.36), (0.81, 0.15), (0.92, 0.04)]
    private static let top: [(at: Double, alpha: Double)] = [(0, 0), (0.04, 0.08), (0.09, 0.3), (0.14, 0.6), (0.19, 0.85), (0.25, 1)]

    public static func stops(from: Double, topIn: Bool = false) -> [Stop] {
        let start = min(max(from.isFinite ? from : billboard, 0), 0.95)
        var out = topIn ? top.map { Stop(location: $0.at, alpha: $0.alpha) } : [Stop(location: 0, alpha: 1)]
        out.append(Stop(location: max(start, out.last?.location ?? 0), alpha: 1))
        out += ease.map { Stop(location: start + (1 - start) * $0.at, alpha: $0.alpha) }
        out.append(Stop(location: 1, alpha: 0))
        return out
    }

    /// The sides of a backdrop wider than the page's column (an iPad on its side, a Mac window): solid in the middle,
    /// fading out over `edge` of the width at each side, so the picture has no hard sides.
    public static func sides(edge: Double = 0.08) -> [Stop] {
        let e = min(max(edge.isFinite ? edge : 0.08, 0), 0.5)
        return [Stop(location: 0, alpha: 0), Stop(location: e * 0.5, alpha: 0.6), Stop(location: e, alpha: 1),
                Stop(location: 1 - e, alpha: 1), Stop(location: 1 - e * 0.5, alpha: 0.6), Stop(location: 1, alpha: 0)]
    }
}
