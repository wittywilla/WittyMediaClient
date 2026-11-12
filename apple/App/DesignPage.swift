// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Design 2's page for the app's own screens (the design canvas, "App screens": connect, profiles, remote, states):
// a small eyebrow, a big title, a lead line, then sections of rows, chips, notes or cards, the actions and a foot
// line. The same sections and words on a TV, an iPad and an iPhone; one column on a phone. Everything is drawn from
// the theme in use (its palette and corners), never from frames of its own.

/// The sizes of a Design 2 page on this device.
struct DesignSizes {
    let title: CGFloat, body: CGFloat, small: CGFloat, tiny: CGFloat
    let rowHeight: CGFloat, chipHeight: CGFloat, buttonHeight: CGFloat
    let gap: CGFloat, gap2: CGFloat, ring: CGFloat, leadWidth: CGFloat, columns: Int

    static func of(_ metrics: Metrics, width: CGFloat) -> DesignSizes {
        if metrics.tv {
            return DesignSizes(title: 64, body: 29, small: 24, tiny: 20, rowHeight: 88, chipHeight: 60, buttonHeight: 66,
                               gap: 16, gap2: 40, ring: metrics.focusRing, leadWidth: 1100, columns: 4)
        }
        let tablet = width >= 600
        return DesignSizes(title: tablet ? 40 : 30, body: 17, small: 15, tiny: 13, rowHeight: tablet ? 56 : 52,
                           chipHeight: 36, buttonHeight: 48, gap: 10, gap2: tablet ? 28 : 22, ring: 2,
                           leadWidth: 620, columns: tablet ? 3 : 2)
    }
}

private struct DesignSizesKey: EnvironmentKey { static let defaultValue = DesignSizes.of(.phone, width: 390) }

extension EnvironmentValues {
    var designSizes: DesignSizes {
        get { self[DesignSizesKey.self] }
        set { self[DesignSizesKey.self] = newValue }
    }
}

/// The page: eyebrow, title and lead, then `content` (its sections), the actions and the foot line, scrolling.
struct DesignPage<Content: View, Actions: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    var eyebrow: String = ""
    let title: String
    var lead: String = ""
    var foot: String = ""
    var identifier: String = ""
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        GeometryReader { geo in
            let sizes = DesignSizes.of(metrics, width: geo.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !eyebrow.isEmpty {
                        Text(eyebrow.uppercased())
                            .font(.system(size: sizes.small, weight: .bold))
                            .kerning(sizes.small * 0.08)
                            .foregroundStyle(palette.accentText)
                            .padding(.bottom, sizes.gap * 0.6)
                    }
                    Text(title)
                        .font(.system(size: sizes.title, weight: .heavy, design: .rounded))
                        .kerning(-sizes.title * 0.04)
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(identifier.isEmpty ? "" : identifier + "-title")
                    if !lead.isEmpty {
                        Text(lead)
                            .font(.system(size: sizes.body))
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: sizes.leadWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, sizes.gap)
                    }
                    content()
                    DesignActions(content: actions).padding(.top, sizes.gap2)
                    if !foot.isEmpty {
                        Text(foot)
                            .font(.system(size: sizes.small))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, sizes.gap2)
                    }
                }
                .frame(maxWidth: metrics.tv ? .infinity : 760, alignment: .leading)
                .padding(.horizontal, metrics.tv ? Tokens.gutter : metrics.gutter)
                .padding(.vertical, metrics.tv ? Tokens.edge : Tokens.Space.s6)
                .frame(maxWidth: .infinity)
            }
            .environment(\.designSizes, sizes)
        }
        .background(palette.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension DesignPage where Actions == EmptyView {
    init(eyebrow: String = "", title: String, lead: String = "", foot: String = "", identifier: String = "",
         @ViewBuilder content: @escaping () -> Content) {
        self.init(eyebrow: eyebrow, title: title, lead: lead, foot: foot, identifier: identifier, content: content,
                  actions: { EmptyView() })
    }
}

/// The page's actions in a row that wraps (a column on a narrow phone), each a button of the theme.
private struct DesignActions<Content: View>: View {
    @Environment(\.designSizes) private var sizes
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: sizes.gap, rowSpacing: sizes.gap) { content() }
            .remoteSection()
    }
}

/// One section: its heading, then what's in it.
struct DesignSection<Content: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: sizes.gap) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: sizes.body, weight: .heavy))
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .padding(.top, sizes.gap2)
        .accessibilityElement(children: .contain)
    }
}

/// A row: its title in bold with an optional detail line under it, and a value on the right (in the accent when
/// `on`). Pressing it does `action`; without one it is only read.
struct DesignRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    let title: String
    var value: String = ""
    var on = false
    var detail: String = ""
    var selected = false
    var symbol: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { face }
                .buttonStyle(DesignRowStyle(selected: selected))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
        } else {
            face.designRowBackground(selected: selected, pressed: false, focused: false)
                .accessibilityElement(children: .combine)
        }
    }

    private var face: some View {
        HStack(spacing: sizes.gap) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: sizes.body, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: sizes.body * 1.6)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: sizes.body, weight: .bold)).foregroundStyle(palette.text)
                if !detail.isEmpty {
                    Text(detail).font(.system(size: sizes.tiny)).foregroundStyle(palette.text.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: sizes.gap)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: sizes.small, weight: .bold))
                    .foregroundStyle(on ? palette.accentText : palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, sizes.gap * 1.6)
        .padding(.vertical, sizes.gap * 0.6)
        .frame(maxWidth: .infinity, minHeight: sizes.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A column of rows, a small gap between each.
struct DesignRows<Content: View>: View {
    @Environment(\.designSizes) private var sizes
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: sizes.gap * 0.6) { content() }.remoteSection()
    }
}

/// A Design 2 row's press, focus and ring, for a row drawn by its own view.
struct DesignRowButton: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        DesignRowStyle(selected: selected).makeBody(configuration: configuration)
    }
}

private struct DesignRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, selected: selected)
    }

    private struct Inner: View {
        let configuration: Configuration
        let selected: Bool
        #if os(tvOS)
        @Environment(\.isFocused) private var focused
        #else
        private let focused = false
        #endif

        var body: some View {
            configuration.label
                .designRowBackground(selected: selected, pressed: configuration.isPressed, focused: focused)
                .scaleEffect(focused ? 1.02 : 1)
                .animation(.easeOut(duration: Tokens.Motion.focus), value: focused)
        }
    }
}

private extension View {
    /// `bg2` at the theme's corner; a ring of the text colour when chosen or focused.
    func designRowBackground(selected: Bool, pressed: Bool, focused: Bool) -> some View {
        modifier(DesignRowBackground(selected: selected, pressed: pressed, focused: focused))
    }
}

private struct DesignRowBackground: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    let selected: Bool, pressed: Bool, focused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        content
            .background(shape.fill(pressed ? palette.raised : palette.card))
            .overlay(shape.strokeBorder(focused ? palette.tvRing : palette.text, lineWidth: sizes.ring)
                .opacity(selected || focused ? 1 : 0))
            .clipShape(shape)
    }
}

/// Chips in a row that wraps.
struct DesignChips<Content: View>: View {
    @Environment(\.designSizes) private var sizes
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) { content() }.remoteSection()
    }
}

/// A chip: filled with the text colour when `on`, a quiet grey otherwise.
struct DesignChip: View {
    let title: String
    var on = false
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title).lineLimit(1)
            }
        }
        .buttonStyle(DesignChipStyle(on: on))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

private struct DesignChipStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View { Inner(configuration: configuration, on: on) }

    private struct Inner: View {
        @Environment(\.palette) private var palette
        @Environment(\.designSizes) private var sizes
        let configuration: Configuration
        let on: Bool
        #if os(tvOS)
        @Environment(\.isFocused) private var focused
        #else
        private let focused = false
        #endif

        var body: some View {
            configuration.label
                .font(.system(size: sizes.small, weight: .semibold))
                .foregroundStyle(on ? palette.background : palette.text)
                .padding(.horizontal, sizes.chipHeight * 0.45)
                .frame(minHeight: sizes.chipHeight)
                .background(Capsule().fill(on ? palette.text : Color(white: 0.5).opacity(configuration.isPressed ? 0.34 : 0.22)))
                .overlay(Capsule().strokeBorder(palette.tvRing, lineWidth: sizes.ring).opacity(focused ? 1 : 0))
                .contentShape(Capsule())
                .scaleEffect(focused ? 1.05 : 1)
                .animation(.easeOut(duration: Tokens.Motion.focus), value: focused)
        }
    }
}

/// A short note; `tone` sets it on an accent wash.
struct DesignNote: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    let text: String
    var tone = false

    var body: some View {
        Text(text)
            .font(.system(size: sizes.small))
            .foregroundStyle(tone ? palette.text : palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(tone ? sizes.gap * 1.2 : sizes.gap * 0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md * 0.7, style: .continuous)
                .fill(tone ? palette.accent.opacity(0.12) : .clear))
    }
}

/// Cards in a grid: two across on a phone, three on a tablet, four on a TV.
struct DesignCards<Content: View>: View {
    @Environment(\.designSizes) private var sizes
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: sizes.gap), count: sizes.columns),
                  alignment: .leading, spacing: sizes.gap) { content() }
            .remoteSection()
    }
}

// MARK: - A page from data

/// A `DesignPageSpec` drawn through `DesignPage`: the canvas's `gp` pages as data, not views written by hand. A press of
/// any row, chip, card or action reports its `id`. Focus starts at the spec's `startFocus` and runs top to bottom; Back
/// follows the Back ladder: a layer closes (`onBack`), and on the Stage the press is left to the frame, which takes
/// focus to the Bar. Each part is found by UI tests as `design.<id>`.
struct DesignSpecPage: View {
    let spec: DesignPageSpec
    /// Something on the page was pressed: its `id`.
    var onPress: (String) -> Void = { _ in }
    /// The page is a layer and Back closes it.
    var onBack: (() -> Void)? = nil
    @FocusState private var focus: String?
    @Environment(\.metrics) private var metrics

    var body: some View {
        DesignPage(eyebrow: spec.eyebrow, title: spec.title, lead: spec.lead, foot: spec.foot, identifier: "design.page") {
            ForEach(Array(spec.sections.enumerated()), id: \.offset) { _, section in
                DesignSpecSection(section: section, focus: $focus, onPress: onPress)
            }
        } actions: {
            ForEach(spec.actions, id: \.id) { action in
                Button(action.title) { onPress(action.id) }
                    .action(primary: action.primary)
                    .focused($focus, equals: action.id)
                    .accessibilityIdentifier("design." + action.id)
            }
        }
        .onRemoteBack(spec.back == .closeLayer ? onBack : nil)
        .onAppear {
            // A TV starts where the spec says; a touch screen leaves focus alone until a keyboard moves it.
            guard metrics.tv, let start = spec.startFocus else { return }
            DispatchQueue.main.async { focus = start }
        }
    }
}

private struct DesignSpecSection: View {
    @Environment(\.designSizes) private var sizes
    @Environment(\.metrics) private var metrics
    let section: DesignPageSpec.Section
    let focus: FocusState<String?>.Binding
    let onPress: (String) -> Void

    var body: some View {
        DesignSection(title: section.heading) {
            switch section.kind {
            case .rows:
                DesignRows {
                    ForEach(section.rows, id: \.id) { row in
                        DesignRow(title: row.title, value: row.value, on: row.on, detail: row.detail,
                                  action: row.pressable ? { onPress(row.id) } : nil)
                            .focused(focus, equals: row.id)
                            .accessibilityIdentifier("design." + row.id)
                    }
                }
            case .chips:
                DesignChips {
                    ForEach(section.chips, id: \.id) { chip in
                        DesignChip(title: chip.title, on: chip.on) { onPress(chip.id) }
                            .focused(focus, equals: chip.id)
                            .accessibilityIdentifier("design." + chip.id)
                    }
                }
            case .note:
                DesignNote(text: section.note, tone: section.tone)
            case .cards:
                let columns = DesignPageSpec.columns(section, phone: !metrics.tv && sizes.columns == 2,
                                                     tablet: !metrics.tv && sizes.columns == 3)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: sizes.gap), count: columns),
                          alignment: .leading, spacing: sizes.gap) {
                    ForEach(section.cards, id: \.id) { card in
                        DesignCard(card: card) { onPress(card.id) }
                            .focused(focus, equals: card.id)
                            .accessibilityIdentifier("design." + card.id)
                    }
                }
                .remoteSection()
            }
        }
    }
}

/// A card of `secC`: three swatches when it has them (a look's or a theme's colours), its title and a line under it,
/// on `bg2` at the theme's corner, ringed when chosen.
struct DesignCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.designSizes) private var sizes
    let card: DesignPageSpec.Card
    let action: () -> Void

    private func colour(_ hex: String) -> Color {
        guard let c = ThemeColour(hex: hex) else { return .clear }
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                if card.swatches.count >= 3 {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 5).fill(colour(card.swatches[0])).frame(maxWidth: .infinity)
                        RoundedRectangle(cornerRadius: 5).fill(colour(card.swatches[1])).frame(maxWidth: .infinity)
                            .layoutPriority(-1)
                        RoundedRectangle(cornerRadius: 5).fill(colour(card.swatches[2])).frame(width: sizes.chipHeight * 0.8)
                    }
                    .frame(height: sizes.chipHeight * 0.8)
                    .accessibilityHidden(true)
                    .padding(.bottom, 4)
                }
                Text(card.title).font(.system(size: sizes.small, weight: .heavy)).foregroundStyle(palette.text)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if !card.subtitle.isEmpty {
                    Text(card.subtitle).font(.system(size: sizes.tiny)).foregroundStyle(palette.text.opacity(0.75))
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .padding(sizes.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DesignRowButton(selected: card.on))
        .accessibilityLabel([card.title, card.subtitle].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(card.on ? [.isSelected] : [])
    }
}
