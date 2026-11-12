// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The TV numbers of DESIGN-2.md (the `tv` tokens) as the rules that use them: how wide the cards of a shelf are so
// that a slice of the next one shows, where the focus ring goes, how big the ring grows. Pure; Apple TV draws with it.

public enum TvGeometry {
    /// A card's size by style, from the `tv.card` tokens. Unknown styles are a poster.
    public static func card(_ style: String) -> (width: Double, height: Double) {
        switch style {
        case "wide", "landscape", "episode": return (DesignTokens.Tv.Card.Wide.w, DesignTokens.Tv.Card.Wide.h)
        case "square", "album": return (DesignTokens.Tv.Card.Square.w, DesignTokens.Tv.Card.Square.h)
        case "circle", "person": return (DesignTokens.Tv.Card.circle, DesignTokens.Tv.Card.circle)
        case "channel": return (DesignTokens.Tv.Card.Channel.w, DesignTokens.Tv.Card.Channel.h)
        default: return (DesignTokens.Tv.Card.Poster.w, DesignTokens.Tv.Card.Poster.h)
        }
    }

    /// The width a card of a shelf is drawn at so that whole cards fill the row and a slice (`peek`, a fraction of a card)
    /// of the next shows at the edge, telling the person there is more. `nominal` is the style's own width; the result
    /// is the nearest to it that fits, never under 85% of it. With nothing more to show (`hasMore` false), the cards keep
    /// their own width.
    public static func peekWidth(available: Double, nominal: Double, gap: Double = DesignTokens.Tv.Shelf.cardGap,
                                 peek: Double = DesignTokens.Tv.Shelf.peek, hasMore: Bool = true) -> Double {
        guard hasMore, available > 0, nominal > 0 else { return nominal }
        var best = nominal, bestOff = Double.infinity
        for n in 1...max(1, Int(available / nominal) + 1) {
            let w = (available - Double(n) * gap) / (Double(n) + peek)
            guard w >= nominal * 0.85, w <= nominal * 1.15 else { continue }
            let off = abs(w - nominal)
            if off < bestOff { best = w; bestOff = off }
        }
        return best
    }

    /// How many cards of a row show whole.
    public static func wholeCards(available: Double, width: Double, gap: Double = DesignTokens.Tv.Shelf.cardGap) -> Int {
        guard width > 0 else { return 0 }
        return max(1, Int((available + gap) / (width + gap)))
    }

    /// The room a focused card needs around it so the ring and the lift are not clipped: the ring, its gap, and what
    /// the scale adds to each side of a card of this width.
    public static func focusRoom(cardWidth: Double) -> Double {
        let grow = cardWidth * (DesignTokens.Tv.Focus.scale - 1) / 2
        return DesignTokens.Tv.Focus.ring + DesignTokens.Tv.Focus.gap + grow + DesignTokens.Tv.Focus.lift
    }

    /// A ring's corner radius: concentric with the thing it surrounds, so its outer edge is the thing's corner plus the gap
    /// plus the ring's own width.
    public static func ringRadius(inner: Double) -> Double {
        DesignTokens.Tv.Focus.concentric ? inner + DesignTokens.Tv.Focus.gap + DesignTokens.Tv.Focus.ring : inner
    }

    /// The width a shelf's row has from the gutter to the screen's edge.
    public static func shelfWidth(screen: Double) -> Double { max(0, screen - DesignTokens.Tv.gutter) }

    /// The size of a type role on a TV, from `tv.type`; unknown roles are body.
    public static func type(_ role: String) -> Double {
        switch role {
        case "display": return DesignTokens.Tv.Typography.display
        case "pageTitle": return DesignTokens.Tv.Typography.pageTitle
        case "heading": return DesignTokens.Tv.Typography.heading
        case "title": return DesignTokens.Tv.Typography.title
        case "caption": return DesignTokens.Tv.Typography.caption
        case "label": return DesignTokens.Tv.Typography.label
        default: return DesignTokens.Tv.Typography.body
        }
    }
}
