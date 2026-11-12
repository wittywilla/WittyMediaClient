// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Small parts the remaining hand-built pages (music, items) share.

/// A plate on a card's picture (`.badge`), 20 high in 11 bold: the kind of disc in white on `scrim`; a tick in a round
/// `scrim` once it's watched; how many episodes are left in `onAccent` on `accent`.
struct CardPlate: View {
    @Environment(\.palette) private var palette
    let badge: CardBadge

    var body: some View {
        switch badge {
        case .disc(let name):
            Text(name)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.22)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minHeight: 20)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.scrim))
        case .seen:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(palette.scrim))
        case .unwatched(let count):
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.22)
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.accent))
        }
    }
}

extension CardBadge {
    /// What a screen reader hears for it, as the website labels it.
    var spoken: String {
        switch self {
        case .disc(let name): return name
        case .seen: return "Watched"
        case .unwatched(let count): return "\(count) unwatched"
        }
    }
}

/// Pressed, a tile dims a little and shrinks a touch, as the website's buttons do.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: Tokens.Motion.press), value: configuration.isPressed)
    }
}
