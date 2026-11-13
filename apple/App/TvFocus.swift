// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// One focus language on Apple TV (docs/plans/DESIGN-2.md sections 1 and 2): a ring in the theme's ring colour, concentric
// with the thing's own corner and a gap off it, and a lift (a scale of 1.06 and a soft shadow) on media. Controls take a
// fill instead (ActionStyle). The system's parallax and tilt are not used, so nothing moves but the lift, in 120 ms
// (and not at all with Reduce Motion, where the ring stays). The numbers are `DesignTokens.Tv.Focus`.

/// A ring around whatever has focus, `radius` being that thing's own corner: it grows outwards by the gap and the ring's
/// width so it stays concentric.
struct TvFocusRing: ViewModifier {
    @Environment(\.isFocused) private var focused
    @Environment(\.palette) private var palette
    let radius: CGFloat

    func body(content: Content) -> some View {
        let ring = CGFloat(DesignTokens.Tv.Focus.ring), gap = CGFloat(DesignTokens.Tv.Focus.gap)
        content.overlay {
            if focused {
                RoundedRectangle(cornerRadius: CGFloat(TvGeometry.ringRadius(inner: Double(radius))), style: .continuous)
                    .strokeBorder(palette.tvRing, lineWidth: ring)
                    .padding(-(gap + ring))
                    .finishGlow(true, colour: palette.tvRing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// The focus ring of Apple TV; nothing elsewhere, where a pointer, keys or touch have their own.
    @ViewBuilder func tvFocusRing(radius: CGFloat) -> some View {
        #if os(tvOS)
        self.modifier(TvFocusRing(radius: radius))
        #else
        self
        #endif
    }
}

#if os(tvOS)
/// A card, a tile or a picture on a TV: it lifts a little when focused, and (when `ring` is on) the ring surrounds all of it.
/// A label that draws the ring around its own picture turns `ring` off.
struct TvTileStyle: ButtonStyle {
    var ring = true
    var radius: CGFloat = Tokens.Radius.lg

    func makeBody(configuration: Configuration) -> some View {
        TvTileBody(label: configuration.label, pressed: configuration.isPressed, ring: ring, radius: radius)
    }
}

private struct TvTileBody<Label: View>: View {
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool
    let ring: Bool
    let radius: CGFloat

    var body: some View {
        let lift = focused && !reduceMotion
        label
            .modifier(OptionalRing(on: ring, radius: radius))
            .scaleEffect(pressed ? 0.98 : (lift ? CGFloat(DesignTokens.Tv.Focus.scale) : 1))
            .shadow(color: .black.opacity(lift ? 0.4 : 0), radius: lift ? 22 : 0, y: lift ? CGFloat(DesignTokens.Tv.Focus.lift) * 2 : 0)
            .opacity(enabled ? 1 : 0.55)
            .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.focusMove / 1000), value: focused)
            .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.focusMove / 1000), value: pressed)
    }
}

private struct OptionalRing: ViewModifier {
    let on: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if on { content.modifier(TvFocusRing(radius: radius)) } else { content }
    }
}
#endif
