// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// A page's Dock and its key legend (catalogue revision 3; the server's docs/SDUI.md, Zones and the Dock, Dock,
// KeyLegend): the persistent controls of one screen. On Apple TV and an iPad, a bar at the foot that never moves, with
// the remote's keys at its end on a TV; on an iPhone, an Options button that opens them as a sheet.

/// The Dock as a bar at the foot of the page, outside its scroll.
struct SDUIDockBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let dock: SDUIElement
    let height: CGFloat
    let focus: FocusState<String?>.Binding?

    private var buttons: [SDUIElement] { dock.children.filter { $0.type == "Button" } }
    private var legend: SDUIElement? { dock.children.first { $0.type == "KeyLegend" } }

    var body: some View {
        HStack(spacing: layout.sp("s")) {
            ForEach(buttons) { button in
                Button { SDUIActor(model: model, center: center, store: store).perform(button.action) } label: {
                    Label(button.props.text("label"), systemImage: SDUIIcon.symbol(button.icon, or: "slider.horizontal.3"))
                        .lineLimit(1)
                }
                .action(pill: true)
                .sduiFocusable(button.isFocusable ? focus : nil, button.id)
                .accessibilityIdentifier("sdui.dock." + button.id)
                .accessibilityHint(legend.map { SDUIKeyLegend.hint($0) } ?? "")
            }
            Spacer(minLength: layout.sp("s"))
            #if os(tvOS)
            // A remote is always in use on a TV: its keys are always shown.
            if let legend { SDUIKeyLegend(legend: legend) }
            #endif
        }
        .padding(.horizontal, layout.margin)
        .frame(height: max(height, 52))
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                #if !os(tvOS)
                Rectangle().fill(.regularMaterial)
                #endif
                palette.panel.opacity(0.92)
                FinishBackdrop(shape: Rectangle(), fill: nil, role: .bar)
            }
            .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
            .ignoresSafeArea(edges: .bottom)
        }
        .remoteSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dock.label)
        .accessibilityAddTraits(.isHeader)
    }
}

/// An iPhone's Dock: the same controls, in order, as a sheet.
struct SDUIDockSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    let dock: SDUIElement
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List(dock.children.filter { $0.type == "Button" }) { button in
                Button {
                    close()
                    // The sheet goes before the control's own sheet comes.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        SDUIActor(model: model, center: center, store: store).perform(button.action)
                    }
                } label: {
                    Label(button.props.text("label"), systemImage: SDUIIcon.symbol(button.icon, or: "slider.horizontal.3"))
                        .foregroundStyle(palette.text)
                }
                .accessibilityIdentifier("sdui.dock." + button.id)
            }
            .navigationTitle(dock.label)
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) } }
            #endif
        }
        .presentationDetents([.medium])
    }
}

/// The remote's keys and what they do, at the end of a TV's Dock. Hidden from VoiceOver: the keys are each control's hint.
struct SDUIKeyLegend: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let legend: SDUIElement

    private struct Entry: Hashable { let action: String; let label: String }

    private var entries: [Entry] {
        legend.props.items("entries").compactMap { value in
            guard let fields = value.object else { return nil }
            return Entry(action: fields.text("action"), label: PlainWords.clean(fields.text("label"), limit: 30))
        }
    }

    /// The Siri Remote's button for an action.
    static func glyph(_ action: String) -> String {
        switch action {
        case "select": return "circle.circle"
        case "back": return "chevron.backward.circle"
        case "options", "dock": return "playpause.circle"
        case "search": return "mic.circle"
        case "tabs", "top": return "tv.circle"
        case "page": return "arrow.up.arrow.down.circle"
        default: return "questionmark.circle"
        }
    }

    static func hint(_ legend: SDUIElement) -> String {
        legend.props.items("entries").compactMap { $0.object?.text("label") }.joined(separator: ", ")
    }

    var body: some View {
        let size = CGFloat(layout.dock?.hintSize ?? 25)
        HStack(spacing: size) {
            ForEach(entries, id: \.self) { entry in
                HStack(spacing: size * 0.3) {
                    Image(systemName: SDUIKeyLegend.glyph(entry.action))
                    Text(entry.label)
                }
                .font(.wm(size: size))
                .foregroundStyle(palette.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A Dock's Jump to a letter: A to Z and #.
struct SDUILetterPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let choose: (String) -> Void

    private static let letters = (65...90).map { String(UnicodeScalar($0)!) } + ["#"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Tokens.Space.s3)], spacing: Tokens.Space.s3) {
                    ForEach(SDUILetterPicker.letters, id: \.self) { letter in
                        Button { choose(letter) } label: {
                            Text(letter).font(.title3.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                        }
                        .action(pill: true)
                        .accessibilityLabel(letter == "#" ? "Numbers and symbols" : letter)
                    }
                }
                .padding(Tokens.Space.s4)
            }
            .navigationTitle("Jump to a letter")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            #endif
        }
        .presentationDetents([.medium, .large])
    }
}
