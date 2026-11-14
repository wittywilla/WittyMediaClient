// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// MARK: - Tabs

/// A strip of tabs with the chosen tab's sections under it. Only the chosen tab's content is on the page;
/// choosing another asks for the page again with `tab=`. On Apple TV: pills in the middle, the content changing
/// as focus rests on one. On a touch screen: a segmented control, or text tabs with an underline.
struct SDUITabsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let tabs: SDUIElement
    @FocusState private var resting: String?

    private var chosen: SDUIElement? { tabs.children.first { $0.props.flag("selected") == true } ?? tabs.children.first }
    private func choose(_ tab: SDUIElement) {
        guard tab.id != chosen?.id else { return }
        SDUIActor(model: model, center: center, store: store).perform(tab.action)
    }

    private func name(_ tab: SDUIElement) -> some View {
        HStack(spacing: 6) {
            if !tab.props.text("icon").isEmpty { Image(systemName: SDUIIcon.symbol(tab.props.text("icon"))).accessibilityHidden(true) }
            Text(tab.shown("title")).sduiLines(tab.lineLimit("title"))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(layout.sectionGap)) {
            strip
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sdui.section." + tabs.id)
            if let chosen {
                SDUIColumn(children: chosen.children)
                    .opacity(store.refreshing ? 0.6 : 1)
            }
        }
    }

    @ViewBuilder private var strip: some View {
        #if os(tvOS)
        HStack(spacing: layout.sp("s")) {
            ForEach(tabs.children) { tab in
                Button { choose(tab) } label: { name(tab) }
                    .action(selected: tab.id == chosen?.id, pill: true)
                    .focused($resting, equals: tab.id)
                    .sduiFocusable(tab.isFocusable ? focus : nil, tab.id)
                    .accessibilityLabel(tab.props.text("label"))
                    .accessibilityAddTraits(tab.id == chosen?.id ? [.isSelected] : [])
                    .accessibilityIdentifier("sdui.tab." + tab.id)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, layout.sp("xs"))
        .remoteSection()
        // The content changes as focus moves, once it has rested on a tab for a moment.
        .task(id: resting) {
            guard let resting, resting != chosen?.id, let tab = tabs.children.first(where: { $0.id == resting }) else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            if !Task.isCancelled { choose(tab) }
        }
        #else
        if tabs.props.text("style") == "segments" {
            Picker("", selection: Binding(get: { chosen?.id ?? "" }, set: { id in
                if let tab = tabs.children.first(where: { $0.id == id }) { choose(tab) }
            })) {
                ForEach(tabs.children) { tab in Text(tab.shown("title")).tag(tab.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, layout.margin)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.sp("m")) {
                    ForEach(tabs.children) { tab in
                        let here = tab.id == chosen?.id
                        Button { choose(tab) } label: {
                            name(tab)
                                .sduiFont("body", weight: here ? .semibold : .medium)
                                .foregroundStyle(here ? palette.text : palette.textSecondary)
                                .frame(minHeight: 44)
                                .overlay(alignment: .bottom) { if here { Rectangle().fill(palette.accent).frame(height: 2) } }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.props.text("label"))
                        .accessibilityAddTraits(here ? [.isSelected] : [])
                        .accessibilityIdentifier("sdui.tab." + tab.id)
                    }
                }
                .padding(.horizontal, layout.margin)
            }
        }
        #endif
    }
}

// MARK: - Filter and sort

/// The controls that filter and sort a grid on the same page: Sort first, then each filter with what's chosen.
/// A change asks for the page again with the choice as a parameter. On Apple TV a pill opens a list down the
/// right of the screen; on a touch screen a chip opens a sheet from the bottom.
struct SDUIFilterBarView: View {
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let bar: SDUIElement
    @State private var open: SDUIFilterField?
    @State private var picking = false

    private var anyChosen: Bool { bar.filters.contains { $0.id != "sort" && !$0.value.isEmpty } }

    private func set(_ field: SDUIFilterField, _ value: String) {
        open = nil
        guard value != field.value else { return }
        Task { await store.set([field.id: value], center: center) }
    }

    private func clear() {
        var none: [String: String] = [:]
        for field in bar.filters where field.id != "sort" { none[field.id] = "" }
        Task { await store.set(none, center: center) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            if !bar.shown("count").isEmpty, bar.props.flag("showCount") != false {
                Text(bar.shown("count")).sduiFont("caption").foregroundStyle(palette.textSecondary).padding(.horizontal, layout.margin)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.sp("s")) {
                    ForEach(Array(bar.filters.enumerated()), id: \.element.id) { index, field in
                        Button { open = field } label: {
                            HStack(spacing: 6) {
                                Text(field.summary)
                                Image(systemName: "chevron.down").font(.wm(size: 11, weight: .semibold)).accessibilityHidden(true)
                            }
                        }
                        #if os(tvOS)
                        .action(selected: field.id != "sort" && !field.value.isEmpty, pill: true)
                        #else
                        .chip(chosen: field.id != "sort" && !field.value.isEmpty)
                        #endif
                        .sduiFocusable(index == 0 && bar.isFocusable ? focus : nil, bar.id)
                        .accessibilityLabel(field.summary)
                        .accessibilityHint("Opens the choices")
                    }
                    if anyChosen {
                        Button("Clear", action: clear)
                        #if os(tvOS)
                            .action(pill: true)
                        #else
                            .chip()
                        #endif
                    }
                }
                .padding(.horizontal, layout.margin)
                .padding(.vertical, layout.isTV ? layout.sp("xs") : 0)
            }
            .remoteSection()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(bar.label)
        .accessibilityIdentifier("sdui.section." + bar.id)
        .sheet(item: $open) { field in
            SDUIChoiceList(field: field, layout: layout) { set(field, $0) }
        }
        // A Dock's Sort opens the sort's choices; its Filter, which filter to change, then that one's.
        .sheet(isPresented: $picking) {
            SDUIFilterPicker(fields: bar.filters.filter { $0.id != "sort" }) { field in
                picking = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open = field }
            }
        }
        .onReceive(store.$control) { request in
            guard let request, request.target == bar.props.text("target") || bar.props.text("target").isEmpty else { return }
            switch request.control {
            case "sort":
                store.control = nil
                open = bar.filters.first { $0.id == "sort" }
            case "filter":
                store.control = nil
                let filters = bar.filters.filter { $0.id != "sort" }
                if filters.count == 1 { open = filters[0] } else if !filters.isEmpty { picking = true }
            default:
                break
            }
        }
    }
}

/// Which filter to change, from a Dock's Filter: each with what it's set to.
private struct SDUIFilterPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let fields: [SDUIFilterField]
    let choose: (SDUIFilterField) -> Void

    var body: some View {
        NavigationStack {
            List(fields) { field in
                Button { choose(field) } label: {
                    HStack {
                        Text(field.label).foregroundStyle(palette.text)
                        Spacer()
                        Text(field.summary.replacingOccurrences(of: field.label + ": ", with: "")).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .navigationTitle("Filter")
            #if !os(tvOS)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            #endif
        }
        .presentationDetents([.medium, .large])
    }
}

/// A filter's or the sort's choices. "Any" takes a filter away.
private struct SDUIChoiceList: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let field: SDUIFilterField
    let layout: SDUILayout
    let choose: (String) -> Void

    private var choices: [SDUIOption] {
        (field.id == "sort" ? [] : [SDUIOption(value: "", label: "Any")]) + field.options
    }

    private func row(_ option: SDUIOption) -> some View {
        Button { choose(option.value) } label: {
            HStack {
                Text(option.label).foregroundStyle(palette.text)
                Spacer()
                if option.value == field.value { Image(systemName: "checkmark").foregroundStyle(palette.accentText) }
            }
            .padding(.horizontal, layout.sp("m"))
            .frame(minHeight: layout.isTV ? 66 : 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfaceStyle())
        .accessibilityAddTraits(option.value == field.value ? [.isSelected] : [])
    }

    var body: some View {
        #if os(tvOS)
        // A full-height list from the right edge.
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: layout.sp("xs")) {
                Text(field.label).font(.title3.weight(.semibold)).foregroundStyle(palette.text).padding(.horizontal, layout.sp("m"))
                ScrollView {
                    LazyVStack(spacing: 4) { ForEach(choices) { row($0) } }
                }
            }
            .padding(.vertical, 60)
            .frame(width: 640)
            .frame(maxHeight: .infinity)
            .background(palette.panel.ignoresSafeArea())
        }
        .onExitCommand { dismiss() }
        #else
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(choices) { row($0) } }
            }
            .background(palette.panel)
            .navigationTitle(field.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        #endif
    }
}

// MARK: - Text

/// A heading or a block of text, plain or in the small Markdown subset. Links are routes in the app, or web
/// pages for the browser where the device has one. Raw HTML is the characters it is.
struct SDUITextView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let element: SDUIElement

    private var role: String { element.props.text("role").isEmpty ? "body" : element.props.text("role") }
    private var colour: Color { role == "caption" ? palette.textSecondary : palette.text }
    private var alignment: (TextAlignment, Alignment) {
        switch element.props.text("align") {
        case "center": return (.center, .center)
        case "end": return (.trailing, .trailing)
        default: return (.leading, .leading)
        }
    }

    private func attributed(_ spans: [SDUIMarkdown.Span]) -> AttributedString {
        var out = AttributedString()
        for span in spans {
            var piece = AttributedString(span.words)
            switch span {
            case .plain: break
            case .bold: piece.inlinePresentationIntent = .stronglyEmphasized
            case .italic: piece.inlinePresentationIntent = .emphasized
            case .code: piece.inlinePresentationIntent = .code
            case .link(_, let to):
                // A route in the app goes through the page's own router; a web address to the browser, where there is one.
                if to.hasPrefix("/") {
                    var link = URLComponents()
                    link.scheme = "wittymedia-route"
                    link.host = "open"
                    link.path = "/"
                    link.queryItems = [URLQueryItem(name: "to", value: to)]
                    piece.link = link.url
                } else if layout.externalLinks != false {
                    piece.link = URL(string: to)
                }
                if piece.link != nil { piece.foregroundColor = palette.accentText }
            }
            out += piece
        }
        return out
    }

    @ViewBuilder private func block(_ block: SDUIMarkdown.Block) -> some View {
        switch block {
        case .heading(let level, let spans):
            Text(attributed(spans)).sduiFont(level == 1 ? "pageTitle" : (level == 2 ? "heading" : "title")).accessibilityAddTraits(.isHeader)
        case .paragraph(let spans):
            Text(attributed(spans)).sduiFont(role)
        case .item(let number, let spans):
            HStack(alignment: .firstTextBaseline, spacing: layout.sp("xs")) {
                Text(number.map { "\($0)." } ?? "•").sduiFont(role).foregroundStyle(palette.textSecondary)
                Text(attributed(spans)).sduiFont(role)
            }
        }
    }

    private var heading: AccessibilityHeadingLevel? {
        switch element.role {
        case "heading 1": return .h1
        case "heading 2": return .h2
        case "heading 3": return .h3
        default: return nil
        }
    }

    var body: some View {
        let (textAlignment, frameAlignment) = alignment
        Group {
            if element.props.text("format") == "markdown" {
                VStack(alignment: frameAlignment.horizontal, spacing: layout.sp("xs")) {
                    ForEach(Array(SDUIMarkdown.blocks(element.shown("text")).enumerated()), id: \.offset) { _, part in block(part) }
                }
            } else {
                Text(element.shown("text")).sduiFont(role)
            }
        }
        .foregroundStyle(colour)
        .multilineTextAlignment(textAlignment)
        .sduiLines(element.lineLimit("text"))
        // Body text is at most about 70 characters wide.
        .frame(maxWidth: role == "body" ? CGFloat(layout.textSize("body")) * 36 : .infinity, alignment: frameAlignment)
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(element.label)
        .accessibilityAddTraits(heading == nil ? [] : .isHeader)
        .accessibilityHeading(heading ?? .unspecified)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "wittymedia-route", let to = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "to" })?.value {
                SDUIActor(model: model, center: center, store: store).open(route: to)
                return .handled
            }
            #if os(tvOS)
            return .discarded
            #else
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            #endif
        })
    }
}

// MARK: - Notice

/// A message that stands out: a rounded block in `bg2` with a bar at its leading edge in the tone's colour,
/// the icon, the title, the text, and one button at the end (below on a phone).
struct SDUINoticeView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let notice: SDUIElement

    private var tone: Color {
        switch notice.props.text("tone") {
        case "success": return palette.ok
        case "warning": return palette.warn
        case "danger": return palette.danger
        default: return palette.accent
        }
    }

    private var symbol: String {
        if !notice.icon.isEmpty { return SDUIIcon.symbol(notice.icon, or: "info.circle") }
        switch notice.props.text("tone") {
        case "success": return "checkmark.circle"
        case "warning", "danger": return "exclamationmark.triangle"
        default: return "info.circle"
        }
    }

    @ViewBuilder private var button: some View {
        if !notice.shown("button").isEmpty, notice.action != nil, SDUIActor(model: model, center: center, store: store).canPerform(notice.action) {
            Button(notice.shown("button")) { SDUIActor(model: model, center: center, store: store).perform(notice.action) }
                .action()
                .sduiFocusable(notice.isFocusable ? focus : nil, notice.id)
        }
    }

    private var words: some View {
        HStack(alignment: .top, spacing: layout.sp("s")) {
            Image(systemName: symbol).sduiFont("title").foregroundStyle(tone).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if !notice.shown("title").isEmpty {
                    Text(notice.shown("title")).sduiFont("title").foregroundStyle(palette.text)
                }
                Text(notice.shown("text")).sduiFont("body").foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notice.label)
        }
    }

    var body: some View {
        Group {
            if layout.phone {
                VStack(alignment: .leading, spacing: layout.sp("s")) { words; button }
            } else {
                HStack(alignment: .center, spacing: layout.sp("m")) { words; Spacer(minLength: 0); button }
            }
        }
        .padding(layout.sp("m"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel)
        .overlay(alignment: .leading) { Rectangle().fill(tone).frame(width: 4) }
        .clipShape(RoundedRectangle(cornerRadius: draw.radius("Notice"), style: .continuous))
        .padding(.horizontal, layout.margin)
        #if os(tvOS)
        // The whole width is the notice's, so Up or Down from anywhere across the screen lands on its button,
        // rather than skipping a button at the far end of it.
        .focusSection()
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sdui.section." + notice.id)
    }
}

// MARK: - Layout components

/// A hairline between sections, in token `border`.
struct SDUIDividerView: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let divider: SDUIElement

    var body: some View {
        Rectangle().fill(palette.border).frame(height: 1)
            .padding(.horizontal, divider.props.flag("inset") == true ? layout.margin : 0)
            .accessibilityHidden(true)
    }
}

/// Empty space: a spacing step of the device's, in the direction of its container.
struct SDUISpacerView: View {
    @Environment(\.sduiLayout) private var layout
    let spacer: SDUIElement

    var body: some View {
        let size = layout.sp(spacer.props.text("size").isEmpty ? "m" : spacer.props.text("size"))
        Color.clear.frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Sections one after another, down or across. A row that doesn't fit continues on the next line.
/// What a type this app doesn't know is drawn as, too: a plain column of its children.
struct SDUIStackView: View {
    @Environment(\.sduiLayout) private var layout
    let stack: SDUIElement

    private var gap: CGFloat { layout.sp(stack.props.text("gap").isEmpty ? "m" : stack.props.text("gap")) }

    var body: some View {
        if stack.props.text("direction") == "row" {
            let align: VerticalAlignment = ["start": .top, "end": .bottom][stack.props.text("align")] ?? .center
            Group {
                if stack.props.flag("wrap") != false {
                    FlowLayout(spacing: gap) { ForEach(stack.children) { SDUINodeView(element: $0).sduiInRow() } }
                } else {
                    HStack(alignment: align, spacing: gap) { ForEach(stack.children) { SDUINodeView(element: $0).sduiInRow() } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.margin)
            // A row of buttons is one focus group.
            .remoteSection()
        } else {
            let align: HorizontalAlignment = ["center": .center, "end": .trailing][stack.props.text("align")] ?? .leading
            VStack(alignment: align, spacing: gap) { ForEach(stack.children) { SDUINodeView(element: $0) } }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: align, vertical: .top))
        }
    }
}

private struct SDUIInRowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Inside a row: things take their own width and the row keeps the page's margin.
    var sduiInRow: Bool {
        get { self[SDUIInRowKey.self] }
        set { self[SDUIInRowKey.self] = newValue }
    }
}

extension View {
    func sduiInRow() -> some View { environment(\.sduiInRow, true) }
}

/// Two sections side by side on a wide screen, one above the other on a narrow one.
struct SDUISplitView: View {
    @Environment(\.sduiLayout) private var layout
    let split: SDUIElement

    private var sideBySide: Bool {
        if layout.isTV { return true }
        if layout.phone { return false }
        let order = ["compact", "medium", "expanded", "large"]
        let below = split.props.text("stackBelow").isEmpty ? "medium" : split.props.text("stackBelow")
        return (order.firstIndex(of: layout.breakpoint) ?? 0) >= (order.firstIndex(of: below) ?? 1)
    }

    var body: some View {
        let gap = layout.sp(split.props.text("gap").isEmpty ? "m" : split.props.text("gap"))
        if sideBySide, split.children.count >= 2 {
            let parts = split.props.text("ratio").split(separator: ":").compactMap { Double($0) }
            let left = parts.count == 2 ? parts[0] : 1, right = parts.count == 2 ? parts[1] : 1
            GeometryReader { geo in
                let room = max(geo.size.width - gap, 0)
                HStack(alignment: .top, spacing: gap) {
                    SDUINodeView(element: split.children[0]).frame(width: room * left / (left + right), alignment: .leading)
                    VStack(alignment: .leading, spacing: gap) {
                        ForEach(split.children.dropFirst()) { SDUINodeView(element: $0) }
                    }
                    .frame(width: room * right / (left + right), alignment: .leading)
                }
            }
            .frame(minHeight: layout.isTV ? 300 : 200)
        } else {
            VStack(alignment: .leading, spacing: gap) { ForEach(split.children) { SDUINodeView(element: $0) } }
        }
    }
}

/// A button that opens a place in the app, one of the app's own screens, or a web page: filled in the accent
/// (primary), in the card colour (secondary) or words alone (ghost).
struct SDUIButtonView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    @Environment(\.sduiInRow) private var inRow
    let button: SDUIElement

    var body: some View {
        let actor = SDUIActor(model: model, center: center, store: store)
        // One this device can't carry out isn't offered.
        if button.action == nil || actor.canPerform(button.action) {
            let kind: ActionKind = ["primary": .primary, "ghost": .quiet][button.props.text("variant")] ?? .secondary
            Button { actor.perform(button.action) } label: {
                if button.icon.isEmpty {
                    Text(button.shown("title")).sduiLines(button.lineLimit("title"))
                } else {
                    Label(button.shown("title"), systemImage: SDUIIcon.symbol(button.icon))
                }
            }
            .action(kind)
            .disabled(button.action == nil)
            .sduiFocusable(button.isFocusable ? focus : nil, button.id)
            .padding(.horizontal, inRow ? 0 : layout.margin)
            .accessibilityLabel(button.label)
            .accessibilityIdentifier("sdui.button." + button.id)
        }
    }
}

/// A picture from this server at the content's width, at most 960 points, in its shape; a link when it has somewhere to go.
struct SDUIImageView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let element: SDUIElement

    private var picture: some View {
        let ratio = CGFloat(SDUILayout.ratio(element.props.text("aspect")) ?? element.picture?.ratio ?? 16.0 / 9.0)
        return Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: 960)
            .overlay { SDUIPicture(picture: element.picture, contain: element.props.text("fit") == "contain") }
            .clipShape(RoundedRectangle(cornerRadius: element.props.flag("rounded") == false ? 0 : draw.radius("Image"), style: .continuous))
    }

    var body: some View {
        Group {
            if element.action != nil {
                Button { SDUIActor(model: model, center: center, store: store).perform(element.action) } label: { picture }
                    .tileStyle()
                    .sduiFocusable(element.isFocusable ? focus : nil, element.id)
            } else {
                picture
            }
        }
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(element.label)
        .accessibilityAddTraits(element.action != nil ? [.isImage, .isButton] : .isImage)
        .accessibilityHidden(element.role == "none")
    }
}

/// The field people type a search into. On the search page it holds the search, and typing asks for the page
/// again 300 ms after the last keystroke; anywhere else it opens the search page with what was typed. On Apple
/// TV choosing it brings up the system's own keyboard.
struct SDUISearchBoxView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let box: SDUIElement
    @State private var words = ""
    @State private var seeded = false

    private var onSearchPage: Bool { store.document?.page.kind == "search" }

    private func submit() {
        guard !onSearchPage else { return }
        let asked = words.trimmingCharacters(in: .whitespacesAndNewlines)
        SDUIActor(model: model, center: center, store: store).open(route: asked.isEmpty ? "/search" : "/search?" + SDUIQuery.encode([("q", asked)]))
    }

    var body: some View {
        HStack(spacing: layout.sp("xs")) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.textSecondary).accessibilityHidden(true)
            TextField(box.shown("placeholder").isEmpty ? "Search" : box.shown("placeholder"), text: $words)
                .sduiFont("body")
                .foregroundStyle(palette.text)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(submit)
                .sduiFocusable(box.isFocusable ? focus : nil, box.id)
                .accessibilityLabel(box.label)
                .accessibilityIdentifier("sdui.search")
            #if !os(tvOS)
            if !words.isEmpty {
                Button { words = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.textHint) }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Clear the search")
            }
            #endif
        }
        #if !os(tvOS)
        .padding(.horizontal, layout.sp("s"))
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: draw.radius("SearchBox"), style: .continuous).fill(palette.card))
        #endif
        .frame(maxWidth: layout.isTV ? 900 : 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, layout.margin)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            words = box.shown("query")
        }
        .task(id: words) {
            guard onSearchPage, seeded, words != (store.params["q"] ?? "") else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await store.set(["q": words.trimmingCharacters(in: .whitespacesAndNewlines)], center: center)
        }
    }
}

// MARK: - The app's own views

/// A place where the app draws one of its own rich views. This app has the guide; a view it doesn't have never
/// arrives as one (the app names the ones it has), and if one did, the sections inside it are drawn instead.
struct SDUINativeView: View {
    let native: SDUIElement

    static func has(_ view: String) -> Bool { SDUICenter.nativeViews.contains(view) }

    var body: some View {
        if SDUINativeView.has(native.props.text("view")) {
            SDUIGuide()
                .accessibilityIdentifier("sdui.native." + native.props.text("view"))
        } else {
            SDUIColumn(children: native.children)
        }
    }
}

/// The app's own guide: Apple TV's grid of channels and times, and on a phone and a tablet the guide those
/// devices have always had, the server's own.
struct SDUIGuide: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        #if os(tvOS)
        LiveTvTab()
        #elseif os(iOS) || os(visionOS)
        WebPlayerView(path: ServerPages.guide, keptToGames: false)
        #else
        ElsewhereNote(path: ServerPages.guide)
        #endif
    }
}
