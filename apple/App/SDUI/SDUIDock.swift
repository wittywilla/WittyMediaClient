// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// The Dock and the key legend (the server's docs/SDUI.md, Dock and KeyLegend; docs/plans/DESIGN-2.md section 4). The page's
// Dock is its last section: on a TV, a tablet and a computer a bar `layout.dock.height` tall across the foot of the screen,
// outside the page's scroll, with its buttons at the start and the legend at the end; on a phone no bar, but an Options
// button that opens the same controls as a sheet. Its buttons are ordinary Buttons whose `control.open` command the page
// answers (SDUIControls.swift).

/// The key legend: each hint's glyph for the input in use, and what it does. Not drawn for touch alone.
struct SDUIKeyLegendView: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @ObservedObject private var input = InputInUse.shared
    let legend: SDUIElement

    private static let actions: [String: InputAction] = ["select": .select, "back": .back, "options": .options, "search": .search,
                                                          "tabs": .tabNext, "page": .pageDown, "top": .top, "dock": .dock, "help": .help]

    var body: some View {
        let shown = KeyLegend.visible(device: input.device, touchInUse: input.device == nil, askedFor: !layout.phone)
        if shown, let device = input.device {
            HStack(spacing: layout.sp("l")) {
                ForEach(Array(legend.keys.enumerated()), id: \.offset) { _, key in
                    if let action = Self.actions[key.action], let glyph = KeyMap.glyph(device, action) {
                        HStack(spacing: layout.sp("xs")) {
                            Text(glyph)
                                .font(.system(size: CGFloat(layout.dock.hintSize) * 0.84, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.text)
                                .padding(.horizontal, 8)
                                .frame(minWidth: CGFloat(layout.dock.hintSize) * 1.5, minHeight: CGFloat(layout.dock.hintSize) * 1.4)
                                .overlay { RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).strokeBorder(palette.control, lineWidth: 1.5) }
                            Text(key.label).font(.system(size: CGFloat(layout.dock.hintSize))).foregroundStyle(palette.textSecondary).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            // Its keys are in every control's hint, so it is hidden from assistive technology.
            .accessibilityHidden(true)
            .accessibilityIdentifier("sdui.legend")
        }
    }
}

/// The Dock as a bar: elevation 1 (the panel colour and a hairline) with its buttons in one row and the legend after them.
struct SDUIDockView: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let dock: SDUIElement

    var body: some View {
        HStack(spacing: layout.sp("m")) {
            ForEach(dock.children.filter { $0.type == "Button" }) { SDUIButtonView(button: $0).sduiInRow() }
            Spacer(minLength: layout.sp("m"))
            ForEach(dock.children.filter { $0.type == "KeyLegend" }) { SDUIKeyLegendView(legend: $0) }
        }
        .padding(.horizontal, layout.margin)
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(layout.dock.height))
        .background(palette.panel)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        #if os(tvOS)
        .focusSection()
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dock.label)
        .accessibilityIdentifier("sdui.dock")
    }
}

/// The phone's Dock: an Options button at the end of the page's header that opens the controls as a sheet.
struct SDUIDockOptions: View {
    @Environment(\.sduiLayout) private var layout
    let dock: SDUIElement
    @State private var open = false

    var body: some View {
        HStack {
            Spacer()
            Button { open = true } label: { Label(dock.label, systemImage: "slider.horizontal.3") }
                .action(pill: true)
                .accessibilityIdentifier("sdui.dock.options")
        }
        .padding(.horizontal, layout.margin)
        .sheet(isPresented: $open) {
            DockSheet(dock: dock) { open = false }
        }
    }
}

private struct DockSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @EnvironmentObject private var store: SDUIPageStore
    let dock: SDUIElement
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("s")) {
            Text(dock.label).sduiFont("heading").foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
            ForEach(dock.children.filter { $0.type == "Button" }) { button in
                SDUIButtonView(button: button).sduiInRow()
            }
            Spacer(minLength: 0)
        }
        .padding(layout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.panel.ignoresSafeArea())
        // Choosing a control closes the sheet, and the page opens what was chosen.
        .sduiOnChange(of: store.control) { if $0 != nil { close() } }
        #if os(iOS) || os(visionOS)
        .presentationDetents([.medium])
        #endif
    }
}
