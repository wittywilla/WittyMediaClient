// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// What a Dock's `control.open` opens (the server's docs/SDUI.md, Commands): the sort and the filters (the page's FilterBar
// choices), the view (a grid or a list, kept for the profile on this device) and a letter to jump to.

private struct SDUIListViewKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Whether the page's grid is drawn as a list (the Dock's View).
    var sduiListView: Bool {
        get { self[SDUIListViewKey.self] }
        set { self[SDUIListViewKey.self] = newValue }
    }
}

/// The grid-or-list choice, remembered per page on this device.
enum SDUIViewMode {
    private static func key(_ page: String) -> String { "sdui.view.list." + page }
    static func isList(page: String) -> Bool { UserDefaults.standard.bool(forKey: key(page)) }
    static func set(list: Bool, page: String) { UserDefaults.standard.set(list, forKey: key(page)) }
}

/// Which filter: a page with several lists them, and a choice opens that filter's own list.
struct SDUIFilterPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let fields: [SDUIFilterField]
    let choose: (SDUIFilterField) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("Filter").font(.title3.weight(.semibold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
            ForEach(fields) { field in
                Button { choose(field) } label: {
                    Text(field.summary).frame(maxWidth: .infinity, minHeight: Tokens.minTarget, alignment: .leading)
                }
                .action(wide: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.panel.ignoresSafeArea())
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #else
        .presentationDetents([.medium])
        #endif
    }
}

/// A grid of letters: "#" then A to Z. A letter with nothing under it among the titles already here is dimmed, and still
/// goes to the next title after it.
struct SDUIJumpSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let present: Set<String>?
    let choose: (String) -> Void

    var body: some View {
        VStack(spacing: Tokens.Space.s4) {
            Text("Jump to").font(.title3.weight(.semibold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s2), count: 9), spacing: Tokens.Space.s2) {
                ForEach(LetterJump.letters, id: \.self) { letter in
                    Button { choose(letter) } label: {
                        Text(letter).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
                            .opacity(present == nil || present!.contains(letter) ? 1 : 0.5)
                    }
                    .action()
                    .accessibilityLabel(letter == "#" ? "Numbers and symbols" : letter)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.panel.ignoresSafeArea())
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #else
        .presentationDetents([.medium])
        #endif
    }
}

/// A card as a row of a list: its picture small at the start, its title and what is under it.
struct SDUICardRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiDraw) private var draw
    @Environment(\.sduiFocus) private var focus
    let card: SDUIElement

    var body: some View {
        let height: CGFloat = layout.isTV ? 90 : 56
        Button { SDUIActor(model: model, center: center, store: store).perform(card.action) } label: {
            HStack(spacing: layout.sp("m")) {
                Color.clear
                    .frame(width: height * 0.67, height: height)
                    .overlay { SDUIPicture(picture: card.picture, symbol: "film", shownWidth: height) }
                    .clipShape(RoundedRectangle(cornerRadius: draw.radius("Card", "thumb", style: card.props.text("style")), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.shown("title")).sduiFont("title", weight: .medium).foregroundStyle(palette.text).lineLimit(1)
                    if !card.shown("subtitle").isEmpty {
                        Text(card.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.sp("s"))
            .frame(maxWidth: .infinity, minHeight: Tokens.minTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .tileStyle(ring: true, radius: Tokens.Radius.md)
        .disabled(card.action == nil)
        .sduiFocusable(card.isFocusable ? focus : nil, card.id)
        .accessibilityLabel(card.label)
        .accessibilityIdentifier("sdui.card." + card.id)
    }
}
