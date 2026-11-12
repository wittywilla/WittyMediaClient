// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// The components the experiences add (the server's docs/SDUI.md: Carousel, CrossBar, WidgetGrid, Widget, NumberedRow). Drawn from
// the document and the theme's tokens, never from which look is chosen.

// MARK: - Carousel

/// A centred row of posters, the focused or chosen one large (1.25 times) and its neighbours smaller, with its title under it.
struct SDUICarouselView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let carousel: SDUIElement
    @State private var chosen = 0

    private var cards: [SDUIElement] { carousel.children }
    private var cardWidth: CGFloat { CGFloat(carousel.cardWidth > 0 ? carousel.cardWidth : 160) }
    private var cardHeight: CGFloat { CGFloat(carousel.cardHeight > 0 ? carousel.cardHeight : 240) }
    private var loading: Bool { carousel.state == .deferred || (store.busy.contains(carousel.id) && cards.isEmpty) }

    /// The card with focus, else the one chosen by touch.
    private var current: Int {
        if let id = focus?.wrappedValue, let at = cards.firstIndex(where: { $0.id == id }) { return at }
        return min(chosen, max(cards.count - 1, 0))
    }

    var body: some View {
        VStack(alignment: .center, spacing: layout.sp("s")) {
            SDUISectionHeading(element: carousel)
            if carousel.state == .error {
                SDUISectionError(id: carousel.id) { Task { await store.retry(carousel, center: center) } }
            } else if loading {
                SDUIPlaceholderRow(count: 5, width: cardWidth, height: cardHeight, circle: false)
            } else if cards.isEmpty {
                Text(carousel.shown("empty")).sduiFont("caption").foregroundStyle(palette.textSecondary).padding(.horizontal, layout.margin)
            } else {
                row
                if carousel.props.flag("showTitles") != false, cards.indices.contains(current) {
                    VStack(spacing: 2) {
                        Text(cards[current].shown("title")).sduiFont("heading").foregroundStyle(palette.text).lineLimit(1)
                        if !cards[current].shown("subtitle").isEmpty {
                            Text(cards[current].shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(1)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(carousel.label)
        .accessibilityIdentifier("sdui.section." + carousel.id)
        .task(id: carousel.stateName) { await store.fill(carousel, center: center) }
    }

    private var row: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: layout.gap) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { at, card in
                        let big = at == current
                        SDUICardView(card: card, width: cardWidth * (big ? 1.25 : 1), height: cardHeight * (big ? 1.25 : 1))
                            .id(card.id)
                            .simultaneousGesture(TapGesture().onEnded { chosen = at })
                            .onAppear {
                                if carousel.hasMore, at >= cards.count - 3 { Task { await store.more(carousel, center: center) } }
                            }
                    }
                }
                // Room each side so the first and last card can sit in the middle.
                .padding(.horizontal, max(layout.margin, (CGFloat(layout.canvas?.width ?? 0) - cardWidth * 1.25) / 2))
                .padding(.vertical, layout.isTV ? Tokens.focusRoom : 2)
            }
            .sduiOnChange(of: current) { at in
                guard cards.indices.contains(at) else { return }
                if reduceMotion { scroller.scrollTo(cards[at].id, anchor: .center) } else { withAnimation(.easeOut(duration: 0.24)) { scroller.scrollTo(cards[at].id, anchor: .center) } }
            }
            .remoteSection()
        }
    }
}

// MARK: - Widgets

/// A widget's cell in the grid: its column and row, and how many it spans.
private struct WidgetCell: LayoutValueKey {
    static let defaultValue = (x: 0, y: 0, w: 1, h: 1)
}

/// Cells by column and row on a grid of equal columns; a row is as tall as `rowHeight`, cells `spacing` apart. Narrow windows use
/// fewer columns and a widget wider than that takes the full width.
private struct WidgetLayout: Layout {
    let columns: Int
    let rowHeight: CGFloat
    let spacing: CGFloat

    private func columnsFor(_ width: CGFloat) -> Int { width < 520 ? min(columns, 2) : width < 900 ? min(columns, 4) : columns }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let rows = subviews.map { s -> Int in let c = s[WidgetCell.self]; return c.y + c.h }.max() ?? 0
        return CGSize(width: width, height: CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = columnsFor(bounds.width)
        let cell = (bounds.width - CGFloat(n - 1) * spacing) / CGFloat(n)
        for s in subviews {
            let c = s[WidgetCell.self]
            let w = min(c.w, n), x = min(c.x, n - w)
            let frame = CGRect(x: bounds.minX + CGFloat(x) * (cell + spacing), y: bounds.minY + CGFloat(c.y) * (rowHeight + spacing),
                               width: CGFloat(w) * cell + CGFloat(w - 1) * spacing, height: CGFloat(c.h) * rowHeight + CGFloat(c.h - 1) * spacing)
            s.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
    }
}

/// A grid of widgets, each in its own cell.
struct SDUIWidgetGridView: View {
    @Environment(\.sduiLayout) private var layout
    let grid: SDUIElement

    var body: some View {
        WidgetLayout(columns: max(grid.columns, 1), rowHeight: layout.isTV ? 220 : 160, spacing: layout.sp("m")) {
            ForEach(grid.children) { widget in
                SDUIWidgetView(widget: widget)
                    .layoutValue(key: WidgetCell.self, value: (widget.props.whole("x") ?? 0, widget.props.whole("y") ?? 0,
                                                              max(widget.props.whole("w") ?? 1, 1), max(widget.props.whole("h") ?? 1, 1)))
            }
        }
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(grid.label)
        .accessibilityIdentifier("sdui.section." + grid.id)
        .remoteSection()
    }
}

/// One cell: a panel at elevation 1 with its title, and what its kind shows.
struct SDUIWidgetView: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiDraw) private var draw
    let widget: SDUIElement

    private var kind: String { widget.props.text("kind") }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("s")) {
            if !widget.shown("title").isEmpty {
                Text(widget.shown("title")).sduiFont("heading").foregroundStyle(palette.text).lineLimit(1).accessibilityAddTraits(.isHeader)
            }
            if kind == "clock" {
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(time.date, style: .time).sduiFont("display").foregroundStyle(palette.text)
                        Text(time.date, format: .dateTime.weekday(.wide).day().month(.wide)).sduiFont("caption").foregroundStyle(palette.textSecondary)
                    }
                }
            } else if widget.children.isEmpty {
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: layout.gap) { ForEach(widget.children) { SDUINodeView(element: $0).sduiInRow() } }
                }
            }
        }
        .padding(layout.sp("m"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.panel)
        .overlay { RoundedRectangle(cornerRadius: draw.radius("Card"), style: .continuous).strokeBorder(palette.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: draw.radius("Card"), style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(widget.label)
        .accessibilityIdentifier("sdui.widget." + widget.id)
    }
}

// MARK: - Numbered rows

/// Listing rows with a number column: a channel's number, or the place in the list.
struct SDUINumberedRowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiDraw) private var draw
    @Environment(\.sduiFocus) private var focus
    let list: SDUIElement

    private var numberWidth: CGFloat {
        let longest = list.children.map { $0.props.text("number").count }.max() ?? 2
        return CGFloat(max(longest, 2)) * (layout.isTV ? 26 : 12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("s")) {
            SDUISectionHeading(element: list)
            if list.children.isEmpty {
                Text(list.shown("empty")).sduiFont("caption").foregroundStyle(palette.textSecondary).padding(.horizontal, layout.margin)
            } else {
                LazyVStack(alignment: .leading, spacing: layout.sp("xs")) {
                    ForEach(Array(list.children.enumerated()), id: \.element.id) { at, card in
                        row(card)
                            .onAppear {
                                if list.hasMore, at >= list.children.count - 10 { Task { await store.more(list, center: center) } }
                            }
                    }
                }
                .padding(.horizontal, layout.margin)
                .remoteSection()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(list.label)
        .accessibilityIdentifier("sdui.section." + list.id)
        .task(id: list.stateName) { await store.fill(list, center: center) }
    }

    private func row(_ card: SDUIElement) -> some View {
        let height: CGFloat = layout.isTV ? 90 : 56
        return Button { SDUIActor(model: model, center: center, store: store).perform(card.action) } label: {
            HStack(spacing: layout.sp("m")) {
                Text(card.props.text("number")).sduiFont("title", weight: .semibold).foregroundStyle(palette.textSecondary)
                    .monospacedDigit().frame(width: numberWidth, alignment: .trailing)
                Color.clear.frame(width: height * 1.4, height: height * 0.8)
                    .overlay { SDUIPicture(picture: card.picture, symbol: "tv", contain: true, shownWidth: height * 1.4) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.shown("title")).sduiFont("title", weight: .medium).foregroundStyle(palette.text).lineLimit(1)
                    if !card.shown("subtitle").isEmpty {
                        Text(card.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.sp("s"))
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .tileStyle(ring: true, radius: draw.radius("Card"))
        .disabled(card.action == nil)
        .sduiFocusable(card.isFocusable ? focus : nil, card.id)
        .accessibilityLabel(card.label)
        .accessibilityIdentifier("sdui.card." + card.id)
    }
}
