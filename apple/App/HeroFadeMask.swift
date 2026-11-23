// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// A backdrop fades into the page by its own alpha, never by painting the page's colour over it (WittyMediaServer #545):
// then it melts into a theme's gradient, scene or picture as well as into a flat colour, with no line where it ends.
// The curve is WittyKit's HeroFade.

extension View {
    /// Solid down to `from`, eased out to nothing at the bottom; with `topIn` the top fades in too, and with `sides`
    /// the left and right edges fade out, for a backdrop wider than the page's column.
    func heroFade(from: Double, topIn: Bool = false, sides: Bool = false) -> some View {
        mask(LinearGradient(stops: HeroFade.stops(from: from, topIn: topIn).map { Gradient.Stop(color: .black.opacity($0.alpha), location: $0.location) },
                            startPoint: .top, endPoint: .bottom))
            .mask {
                if sides {
                    LinearGradient(stops: HeroFade.sides().map { Gradient.Stop(color: .black.opacity($0.alpha), location: $0.location) },
                                   startPoint: .leading, endPoint: .trailing)
                } else {
                    Color.black
                }
            }
    }
}
