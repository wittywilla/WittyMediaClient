// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import GameController
import SwiftUI
import WittyKit

// The Dock of a TV screen (docs/plans/DESIGN-2.md sections 1 and 4): one row under the Stage that never moves, holding that
// screen's controls (sort, filters, jump, and on the guide look, day, channels ...), with the key legend at its end.
// Reached with Down from the Stage's last row, or with the options key; Up, or Back, returns to where focus was.

/// Which kind of input the person is using, for the key legend: a game controller when one is connected, otherwise
/// the Siri Remote. (Touch doesn't exist on a TV, so the legend always shows here.)
@MainActor
final class InputInUse: ObservableObject {
    static let shared = InputInUse()
    @Published private(set) var device: InputDevice = .remote

    private init() {
        refresh()
        let centre = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    private func refresh() {
        device = GCController.controllers().contains { $0.extendedGamepad != nil } ? .gamepad : .remote
    }
}

/// The key legend: a glyph and what it does, from WittyKit's `KeyLegend` for the connected input.
struct TvLegend: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var input = InputInUse.shared
    let screen: KeyLegend.Screen

    var body: some View {
        let hints = KeyLegend.hints(screen, device: input.device)
        if KeyLegend.visible(device: input.device, touchInUse: false, askedFor: true), !hints.isEmpty {
            HStack(spacing: Tokens.Space.s6) {
                ForEach(hints) { hint in
                    HStack(spacing: Tokens.Space.s2) {
                        Text(hint.glyph)
                            .font(.system(size: CGFloat(DesignTokens.Tv.Dock.hintSize) * 0.84, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 40, minHeight: 36)
                            .background(Capsule().strokeBorder(palette.textSecondary, lineWidth: 2))
                        Text(hint.label)
                            .font(.system(size: CGFloat(DesignTokens.Tv.Dock.hintSize)))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Keys")
            .accessibilityIdentifier("tv.legend")
        }
    }
}

struct TvDockItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var chosen = false
    let action: () -> Void
}

/// The Dock: its buttons in one row, the legend at the end, on the elevation 1 surface under a hairline. Focus moves along
/// the buttons without wrapping; Back returns to the Stage.
struct TvDock: View {
    @Environment(\.palette) private var palette
    let items: [TvDockItem]
    let legend: KeyLegend.Screen
    var focus: FocusState<String?>.Binding?
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            ForEach(items) { item in
                Button(action: item.action) {
                    Label(item.title, systemImage: item.symbol).lineLimit(1)
                }
                .action(selected: item.chosen, pill: true)
                .tvDockFocus(focus, item.id)
                .accessibilityIdentifier("tv.dock." + item.id)
            }
            Spacer(minLength: Tokens.Space.s4)
            TvLegend(screen: legend)
        }
        .padding(.horizontal, Tokens.gutter - CGFloat(DesignTokens.Tv.Focus.ring + DesignTokens.Tv.Focus.gap))
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(DesignTokens.Tv.Dock.height))
        .background(palette.panel)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        .focusSection()
        .onExitCommand(perform: onBack)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Controls for this screen")
        .accessibilityIdentifier("tv.dock")
    }
}

private extension View {
    @ViewBuilder func tvDockFocus(_ focus: FocusState<String?>.Binding?, _ id: String) -> some View {
        if let focus { self.focused(focus, equals: "dock." + id) } else { self }
    }
}

/// A grid of letters: "#" then A to Z. The ones with nothing under them are dimmed but still choosable (they go to the next).
struct TvJumpSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let present: Set<String>?
    let choose: (String) -> Void

    var body: some View {
        VStack(spacing: Tokens.Space.s6) {
            Text("Jump to").font(.title3.weight(.semibold)).foregroundStyle(palette.text)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s3), count: 9), spacing: Tokens.Space.s3) {
                ForEach(LetterJump.letters, id: \.self) { letter in
                    Button { choose(letter) } label: {
                        Text(letter).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
                            .opacity(present == nil || present!.contains(letter) ? 1 : 0.5)
                    }
                    .action()
                    .accessibilityLabel(letter == "#" ? "Numbers and symbols" : letter)
                }
            }
        }
        .padding(Tokens.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.panel.ignoresSafeArea())
        .onExitCommand { dismiss() }
    }
}
#endif
