// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// Any node, drawn as the component it is. A type this app doesn't know arrives here as a `Stack`: a plain
/// column of its children (WittyKit's `SDUIScreen` says so, and the conformance kit checks it).
struct SDUINodeView: View {
    let element: SDUIElement

    var body: some View {
        content.sduiScope(element.tokens)
    }

    @ViewBuilder private var content: some View {
        switch element.type {
        case "Hero": SDUIHeroView(hero: element)
        case "Shelf": SDUIShelfView(shelf: element)
        case "Grid": SDUIGridView(grid: element)
        case "Card": SDUILooseCard(card: element)
        case "Tabs": SDUITabsView(tabs: element)
        case "Tab": SDUIColumn(children: element.children)
        case "FilterBar": SDUIFilterBarView(bar: element)
        case "DetailHeader": SDUIDetailHeaderView(header: element)
        case "SeasonList": SDUISeasonListView(list: element)
        case "TrackList": SDUITrackListView(list: element)
        case "Track": SDUITrackRow(track: element, list: nil)
        case "Banner": SDUIBannerView(banner: element)
        case "Text": SDUITextView(element: element)
        case "Notice": SDUINoticeView(notice: element)
        case "Divider": SDUIDividerView(divider: element)
        case "Spacer": SDUISpacerView(spacer: element)
        case "Split": SDUISplitView(split: element)
        case "Button": SDUIButtonView(button: element)
        case "Image": SDUIImageView(element: element)
        case "SearchBox": SDUISearchBoxView(box: element)
        case "List": SDUIListView(list: element)
        case "ListItem": SDUIListRow(row: element, dense: false)
        case "Dock": EmptyView()
        // A key legend outside a Dock: a TV's remote is always in use; touch alone never shows one.
        case "KeyLegend":
            #if os(tvOS)
            SDUIKeyLegend(legend: element).padding(.horizontal, element.depth > 0 ? 0 : 60)
            #else
            EmptyView()
            #endif
        case "NativeView": SDUINativeView(native: element)
        case "Page": SDUIColumn(children: element.children)
        default: SDUIStackView(stack: element)
        }
    }
}

/// Sections one under another, the page's distance apart.
struct SDUIColumn: View {
    @Environment(\.sduiLayout) private var layout
    let children: [SDUIElement]

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(layout.sectionGap)) {
            ForEach(children) { SDUINodeView(element: $0) }
        }
    }
}

/// A card that isn't in a row or a grid: drawn at its style's medium size.
struct SDUILooseCard: View {
    @Environment(\.sduiLayout) private var layout
    let card: SDUIElement

    var body: some View {
        let metrics = layout.cards[card.props.text("style")]
        let width = CGFloat(metrics?.width?["m"] ?? 160)
        let ratio = SDUILayout.ratio(metrics?.aspect ?? "") ?? card.picture?.ratio ?? 1
        SDUICardView(card: card, width: width, height: width / CGFloat(ratio)).padding(.horizontal, layout.margin)
    }
}

// MARK: - Shelf

/// A titled row of cards that scrolls sideways. On Apple TV the row is one focus section, its cards the
/// system's own, the page's safe area's width from the edge; on a touch screen it bleeds off both edges.
/// It asks for its items when it arrives waiting for them, and for more as its end comes near.
struct SDUIShelfView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiWidth) private var pageWidth
    let shelf: SDUIElement

    private var cardWidth: CGFloat { CGFloat(shelf.cardWidth > 0 ? shelf.cardWidth : 160) }
    private var cardHeight: CGFloat { CGFloat(shelf.cardHeight > 0 ? shelf.cardHeight : 240) }
    private var actor: SDUIActor { SDUIActor(model: model, center: center, store: store) }
    private var loading: Bool { shelf.state == .deferred || (store.busy.contains(shelf.id) && shelf.children.isEmpty) }
    private var isChips: Bool { shelf.cardStyle == "chip" }

    /// How many cards are a screen's worth: the next page is asked for once the end is that near.
    private var perScreen: Int { max(layout.placeholders(cardWidth: Int(cardWidth)), 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("s")) {
            SDUISectionHeading(element: shelf, seeAll: shelf.seeAll.isEmpty || shelf.seeAllCard ? nil : { actor.open(route: shelf.seeAll) })
            if shelf.state == .error {
                SDUISectionError(id: shelf.id) { Task { await store.retry(shelf, center: center) } }
            } else if loading {
                SDUIPlaceholderRow(count: max(shelf.placeholders, perScreen), width: cardWidth, height: isChips ? 44 : cardHeight,
                                   circle: ["circle", "person"].contains(shelf.cardStyle))
            } else if shelf.state == .empty || shelf.children.isEmpty {
                Text(shelf.shown("empty")).sduiFont("caption").foregroundStyle(palette.textSecondary).padding(.horizontal, layout.margin)
            } else {
                row
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(shelf.label)
        .accessibilityIdentifier("sdui.section." + shelf.id)
        // Within a screen of being seen: a lazy column makes it just before it shows.
        .task(id: shelf.stateName) { await store.fill(shelf, center: center) }
    }

    /// The width a card is drawn at. A row that scrolls shows whole cards and a slice of the next (`peek`, a fraction of a
    /// card's width, from the page's layout), so the person can see there is more: the cards are the page's own size, nudged to
    /// the nearest that makes that fit.
    private var shownWidth: CGFloat {
        guard shelf.peek > 0, !isChips, pageWidth > 0 else { return cardWidth }
        let available = Double(pageWidth - layout.margin)
        let items = shelf.children.count + (!shelf.seeAll.isEmpty && (shelf.seeAllCard || layout.isTV) ? 1 : 0)
        let whole = TvGeometry.wholeCards(available: available, width: Double(cardWidth), gap: Double(layout.gap))
        return CGFloat(TvGeometry.peekWidth(available: available, nominal: Double(cardWidth), gap: Double(layout.gap), peek: shelf.peek, hasMore: items > whole))
    }

    private var shownHeight: CGFloat { cardHeight * shownWidth / max(cardWidth, 1) }

    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: layout.gap) {
                ForEach(Array(shelf.children.enumerated()), id: \.element.id) { index, card in
                    SDUICardView(card: card, width: shownWidth, height: shownHeight)
                        .onAppear {
                            if shelf.hasMore, index >= shelf.children.count - perScreen { Task { await store.more(shelf, center: center) } }
                        }
                }
                if store.busy.contains(shelf.id) {
                    SkeletonShape().frame(width: shownWidth, height: shownHeight)
                }
                // See all as the row's last card where the row says so (always on a TV, where it's how the remote gets there).
                if !shelf.seeAll.isEmpty, !isChips, shelf.seeAllCard || layout.isTV {
                    SDUISeeAllCard(width: shownWidth, height: shownHeight, title: shelf.shown("title")) { actor.open(route: shelf.seeAll) }
                }
            }
            .padding(.horizontal, layout.margin)
            // The room a focused card needs to lift without being cut off.
            .padding(.vertical, layout.isTV ? Tokens.focusRoom : 2)
        }
        .remoteSection()
    }
}

// MARK: - Grid

/// Cards in rows and columns: the count the page gives for a television and for the window it was asked with,
/// worked out again as the window changes between breakpoints. Cards stretch to fill the row. It pages as its
/// last two rows come near.
struct SDUIGridView: View {
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let grid: SDUIElement

    private var columns: Int { max(grid.columns, 1) }
    private var ratio: CGFloat { grid.cardHeight > 0 ? CGFloat(grid.cardWidth) / CGFloat(grid.cardHeight) : 2.0 / 3.0 }
    private var loading: Bool { grid.state == .deferred || (store.busy.contains(grid.id) && grid.children.isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("s")) {
            SDUISectionHeading(element: grid)
            if grid.state == .error {
                SDUISectionError(id: grid.id) { Task { await store.retry(grid, center: center) } }
            } else if loading {
                cells(placeholders: columns * 2)
            } else if grid.state == .empty || grid.children.isEmpty {
                Text(grid.shown("empty")).sduiFont("caption").foregroundStyle(palette.textSecondary).padding(.horizontal, layout.margin)
            } else if store.listed.contains(grid.id) {
                // The Dock's View: the same titles as a list, a line each with its picture.
                LazyVStack(spacing: layout.isTV ? layout.sp("xs") : 0) {
                    ForEach(Array(grid.children.enumerated()), id: \.element.id) { index, card in
                        SDUIListRow(row: card, dense: false)
                            .onAppear {
                                if grid.hasMore, index >= grid.children.count - 6 { Task { await store.more(grid, center: center) } }
                            }
                    }
                }
                .remoteSection()
            } else {
                cells(placeholders: store.busy.contains(grid.id) ? columns : 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(grid.label)
        .accessibilityIdentifier("sdui.section." + grid.id)
        .task(id: grid.stateName) { await store.fill(grid, center: center) }
    }

    private func cells(placeholders: Int) -> some View {
        let isChips = grid.cardStyle == "chip"
        let items = Array(repeating: GridItem(.flexible(), spacing: layout.gap, alignment: .top), count: columns)
        return LazyVGrid(columns: isChips ? [GridItem(.adaptive(minimum: 120), spacing: layout.gap, alignment: .leading)] : items,
                         alignment: .leading, spacing: layout.gap) {
            ForEach(Array(grid.children.enumerated()), id: \.element.id) { index, card in
                SDUICardView(card: card, width: CGFloat(max(grid.cardWidth, 1)), height: CGFloat(max(grid.cardHeight, 1)), fills: true)
                    .onAppear {
                        // Within two rows of the end.
                        if grid.hasMore, index >= grid.children.count - columns * 2 { Task { await store.more(grid, center: center) } }
                    }
            }
            ForEach(0..<placeholders, id: \.self) { _ in
                SkeletonShape().aspectRatio(ratio, contentMode: .fit)
            }
        }
        .padding(.horizontal, layout.margin)
        .padding(.vertical, layout.isTV ? Tokens.focusRoom / 2 : 0)
        .remoteSection()
    }
}

// MARK: - List

/// Rows of text with an icon or a small picture: 56 points tall, 44 when dense, 90 on a television.
struct SDUIListView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let list: SDUIElement

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            SDUISectionHeading(element: list)
            if list.state == .error {
                SDUISectionError(id: list.id) { Task { await store.retry(list, center: center) } }
            } else if list.state == .deferred {
                VStack(spacing: layout.sp("xs")) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonShape(radius: draw.radius("ListItem")).frame(height: layout.isTV ? 90 : 56) }
                }
                .padding(.horizontal, layout.margin)
            } else if list.children.isEmpty {
                Text(list.shown("empty")).sduiFont("caption").foregroundStyle(palette.textSecondary).padding(.horizontal, layout.margin)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.children.enumerated()), id: \.element.id) { index, row in
                        SDUIListRow(row: row, dense: list.props.flag("dense") == true)
                            .onAppear {
                                if list.hasMore, index >= list.children.count - 4 { Task { await store.more(list, center: center) } }
                            }
                    }
                }
                .remoteSection()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(list.label)
        .accessibilityIdentifier("sdui.section." + list.id)
        .task(id: list.stateName) { await store.fill(list, center: center) }
    }
}

struct SDUIListRow: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let row: SDUIElement
    let dense: Bool

    /// With a picture, the row is as tall as a small poster; without, a line of text.
    private var height: CGFloat {
        if row.picture != nil { return layout.isTV ? 150 : (dense ? 64 : 84) }
        return layout.isTV ? 90 : (dense ? 44 : 56)
    }
    private var picHeight: CGFloat { height - (layout.isTV ? 20 : 12) }
    /// How far through it is, 0 to 1, when it has been started.
    private var progress: CGFloat? {
        guard let done = row.props["progress"]?.double, done > 0, done < 1 else { return nil }
        return CGFloat(done)
    }

    private var label: some View {
        HStack(spacing: layout.sp("s")) {
            if let picture = row.picture {
                // In the item's own shape: a poster upright, a still wide, a cover square (docs/SDUI.md, Layout options).
                let tall = picHeight
                let wide = (tall * CGFloat(min(max(picture.ratio, 0.5), 2))).rounded()
                SDUIPicture(picture: picture, symbol: SDUIIcon.symbol(row.icon, or: "square"), shownWidth: wide)
                    .frame(width: wide, height: tall)
                    .clipShape(RoundedRectangle(cornerRadius: draw.radius("ListItem", "art"), style: .continuous))
                    .overlay(alignment: .bottom) {
                        if let done = progress {
                            GeometryReader { geo in
                                Capsule().fill(palette.accent).frame(width: geo.size.width * done, height: 3)
                            }
                            .frame(height: 3)
                            .padding(.horizontal, 3)
                            .padding(.bottom, 3)
                            .accessibilityHidden(true)
                        }
                    }
            } else if !row.icon.isEmpty {
                Image(systemName: SDUIIcon.symbol(row.icon)).foregroundStyle(palette.textSecondary).frame(width: 28).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.shown("title")).sduiFont("body", weight: .medium).foregroundStyle(palette.text).sduiLines(row.lineLimit("title"))
                if !row.shown("subtitle").isEmpty {
                    Text(row.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).sduiLines(row.lineLimit("subtitle"))
                }
                if !row.badges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(row.badges.prefix(2).enumerated()), id: \.offset) { _, badge in
                            Text(PlainWords.clean(badge, limit: 24))
                                .font(.system(size: CGFloat(layout.text["badge"] ?? layout.textSize("caption")), weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: draw.radius("Card", "badge"), style: .continuous).fill(palette.card))
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            Spacer(minLength: layout.sp("s"))
            if !row.shown("trailing").isEmpty {
                Text(row.shown("trailing")).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            if row.action != nil {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textHint).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, layout.isTV ? layout.sp("s") : 0)
        .frame(minHeight: height)
        .contentShape(Rectangle())
    }

    var body: some View {
        Group {
            if row.action != nil {
                Button { SDUIActor(model: model, center: center, store: store).perform(row.action) } label: { label }
                    .buttonStyle(SurfaceStyle())
                    .sduiFocusable(focus, row.id)
                    .accessibilityAddTraits(.isButton)
            } else {
                label
            }
        }
        .padding(.horizontal, layout.margin - (layout.isTV ? layout.sp("s") : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([row.label] + row.badges.prefix(2).map { $0 } + (progress.map { ["\(Int(($0 * 100).rounded())) percent watched"] } ?? []))
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

// MARK: - Tracks

/// An album's songs, a book's chapters: numbered, with their lengths. On a television the list keeps to the
/// right two thirds of the screen.
struct SDUITrackListView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiWidth) private var width
    let list: SDUIElement

    var body: some View {
        Group {
            if list.state == .error {
                SDUISectionError(id: list.id) { Task { await store.retry(list, center: center) } }
            } else if list.state == .deferred {
                VStack(spacing: layout.sp("xs")) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonShape(radius: draw.radius("TrackList", "row")).frame(height: layout.isTV ? 66 : 56) }
                }
                .padding(.horizontal, layout.margin)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(list.children) { SDUITrackRow(track: $0, list: list) }
                }
                .remoteSection()
            }
        }
        .frame(maxWidth: layout.isTV ? max(width * 2 / 3, 600) : .infinity)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(list.label)
        .accessibilityIdentifier("sdui.section." + list.id)
        .task(id: list.stateName) { await store.fill(list, center: center) }
    }
}

struct SDUITrackRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var listening: Listening
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let track: SDUIElement
    let list: SDUIElement?

    /// The track that's playing is drawn in the accent colour.
    private var playing: Bool {
        guard let id = Int64(track.props.text("itemId")) else { return false }
        return listening.now?.item.id == id
    }

    var body: some View {
        let showNumbers = list?.props.flag("showNumbers") != false
        Button { SDUIActor(model: model, center: center, store: store).perform(track.action) } label: {
            HStack(spacing: layout.sp("s")) {
                if showNumbers, let number = track.props.whole("number") {
                    Text(String(number)).sduiFont("body").monospacedDigit().foregroundStyle(playing ? palette.accentText : palette.textSecondary)
                        .frame(minWidth: layout.isTV ? 60 : 28, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.shown("title")).sduiFont("body", weight: .medium).foregroundStyle(playing ? palette.accentText : palette.text)
                        .sduiLines(track.lineLimit("title"))
                    if !track.shown("subtitle").isEmpty {
                        Text(track.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(1)
                    }
                    if let percent = track.progress, percent > 0 {
                        ProgressStrip(fraction: Double(percent) / 100, track: palette.border).frame(maxWidth: 160)
                    }
                }
                Spacer(minLength: layout.sp("s"))
                if !track.shown("duration").isEmpty {
                    Text(track.shown("duration")).sduiFont("caption").monospacedDigit().foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, layout.isTV ? layout.sp("s") : 0)
            .frame(minHeight: layout.isTV ? 66 : 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(SurfaceStyle())
        .disabled(track.action == nil)
        .sduiFocusable(track.isFocusable ? focus : nil, track.id)
        .padding(.horizontal, layout.margin - (layout.isTV ? layout.sp("s") : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.label)
        .accessibilityAddTraits(playing ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Seasons and episodes

/// A show's seasons with the chosen season's episodes. On Apple TV: a row of season pills, then the episodes as
/// a row of cards. On a touch screen: a season menu, then the episodes one under another, the still at the left.
struct SDUISeasonListView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let list: SDUIElement

    private var cardWidth: CGFloat { CGFloat(list.cardWidth > 0 ? list.cardWidth : 224) }
    private var cardHeight: CGFloat { CGFloat(list.cardHeight > 0 ? list.cardHeight : 126) }
    private var chosen: SDUISeason? { list.seasons.first(where: \.selected) ?? list.seasons.first }
    private func choose(_ season: SDUISeason) { Task { await store.choose(season, in: list, center: center) } }
    private var asList: Bool { !layout.isTV }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("s")) {
            if !list.title.isEmpty {
                Text(list.title).sduiFont("title").foregroundStyle(palette.text).accessibilityAddTraits(.isHeader).padding(.horizontal, layout.margin)
            }
            if list.seasons.count > 1 || (list.seasons.count == 1 && layout.isTV) { seasons }
            if list.state == .error {
                SDUISectionError(id: list.id) { Task { await store.retry(list, center: center) } }
            } else if list.state == .deferred || (store.busy.contains(list.id) && list.children.isEmpty) {
                SDUIPlaceholderRow(count: layout.placeholders(cardWidth: Int(cardWidth)), width: cardWidth, height: cardHeight)
            } else if asList {
                LazyVStack(alignment: .leading, spacing: layout.sp("s")) {
                    ForEach(Array(list.children.enumerated()), id: \.element.id) { index, card in
                        SDUIEpisodeRow(card: card, stillWidth: min(cardWidth, 160))
                            .onAppear { if list.hasMore, index >= list.children.count - 4 { Task { await store.more(list, center: center) } } }
                    }
                }
                .opacity(store.busy.contains(list.id) ? 0.5 : 1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: layout.gap) {
                        ForEach(Array(list.children.enumerated()), id: \.element.id) { index, card in
                            SDUICardView(card: card, width: cardWidth, height: cardHeight)
                                .onAppear { if list.hasMore, index >= list.children.count - 4 { Task { await store.more(list, center: center) } } }
                        }
                    }
                    .padding(.horizontal, layout.margin)
                    .padding(.vertical, Tokens.focusRoom)
                }
                .remoteSection()
                .opacity(store.busy.contains(list.id) ? 0.5 : 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(list.label)
        .accessibilityIdentifier("sdui.section." + list.id)
        .task(id: list.stateName) { await store.fill(list, center: center) }
    }

    @ViewBuilder private var seasons: some View {
        #if os(tvOS)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: layout.sp("s")) {
                ForEach(list.seasons) { season in
                    Button(season.title) { choose(season) }
                        .action(selected: season.selected, pill: true)
                        .accessibilityLabel(season.title)
                        .accessibilityAddTraits(season.selected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, layout.margin)
            .padding(.vertical, layout.sp("xs"))
        }
        .remoteSection()
        #else
        Menu {
            ForEach(list.seasons) { season in
                Button { choose(season) } label: {
                    if season.selected { Label(season.title, systemImage: "checkmark") } else { Text(season.title) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(chosen?.title ?? "Season")
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
            }
            .sduiFont("body", weight: .semibold)
            .foregroundStyle(palette.text)
            .padding(.horizontal, layout.sp("m"))
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: draw.radius("SeasonList", "season"), style: .continuous).fill(palette.card))
        }
        .padding(.horizontal, layout.margin)
        .accessibilityLabel(chosen?.title ?? "Season")
        #endif
    }
}

/// An episode in a touch screen's list: the still at the left with how far through it is, then the title, the
/// running time and two lines of what happens.
struct SDUIEpisodeRow: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let card: SDUIElement
    let stillWidth: CGFloat

    private var actor: SDUIActor { SDUIActor(model: model, center: center, store: store) }

    var body: some View {
        Button { actor.perform(card.action) } label: {
            HStack(alignment: .top, spacing: layout.sp("s")) {
                SDUIPicture(picture: card.picture, symbol: "tv", shownWidth: stillWidth)
                    .frame(width: stillWidth, height: stillWidth * 9 / 16)
                    .overlay(alignment: .bottom) {
                        if card.shows.contains("progress"), let percent = card.progress { ProgressStrip(fraction: Double(percent) / 100).padding(4) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if card.shows.contains("watched") {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.onAccent, palette.accent).padding(4)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: draw.radius("SeasonList", "still"), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.shown("title")).sduiFont("title", weight: .medium).foregroundStyle(palette.text).sduiLines(card.lineLimit("title"))
                    if !card.shown("subtitle").isEmpty {
                        Text(card.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).sduiLines(card.lineLimit("subtitle"))
                    }
                    if !card.shown("synopsis").isEmpty {
                        Text(card.shown("synopsis")).sduiFont("caption").foregroundStyle(palette.textSecondary).sduiLines(card.lineLimit("synopsis"))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(card.action == nil)
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.label)
        .accessibilityAddTraits(.isButton)
        #if os(iOS) || os(visionOS)
        .contextMenu {
            let playId = card.props.text("playId")
            if card.action != nil { Button { actor.perform(card.action) } label: { Label("Open", systemImage: "arrow.up.forward.square") } }
            if Int64(playId) != nil { Button { actor.go(.play(item: playId, resume: true)) } label: { Label("Play", systemImage: "play.fill") } }
        }
        #endif
    }
}
