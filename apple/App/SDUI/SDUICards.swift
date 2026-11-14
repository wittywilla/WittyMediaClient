// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// One card of a row or a grid. What it draws is exactly what its style shows of what it carries (the element's
/// `shows`, worked out in WittyKit from the catalogue's card styles), at the size the row gave it. On Apple TV
/// it's the system's card: it lifts and tilts with the remote. On a touch screen a long press opens its menu.
/// A style this app doesn't know is drawn as its shape: the picture, with the title and subtitle under it.
struct SDUICardView: View {
    @Environment(\.sduiDraw) private var draw
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    @Environment(\.sduiOnImage) private var onImage
    let card: SDUIElement
    /// The picture's size in points, from the row's `props.card`. In a grid the card fills its column and keeps the shape.
    let width: CGFloat
    let height: CGFloat
    var fills = false

    private var actor: SDUIActor { SDUIActor(model: model, center: center, store: store) }
    private var style: String { card.props.text("style") }
    private var shape: String {
        if !card.shape.isEmpty { return card.shape }
        return center.catalog.cardStyle(style)?.shape ?? "poster"
    }
    private var isCircle: Bool { shape == "circle" }
    private func shows(_ part: String) -> Bool { card.shows.contains(part) }

    var body: some View {
        Group {
            if shape == "chip" {
                chip
            } else {
                // The ring is drawn around the picture itself (`picture`), the lift is the whole card's.
                Button { actor.perform(card.action) } label: { content }
                    .tileStyle(ring: false)
                    .disabled(card.action == nil)
            }
        }
        .sduiFocusable(card.isFocusable && card.action != nil ? focus : nil, card.id)
        .sduiScope(card.tokens)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.label)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sdui.card." + card.id)
        // A long press on a touch screen; on Apple TV, a long press of the remote's centre (the options key).
        #if os(iOS) || os(visionOS) || os(tvOS)
        .contextMenu { menu }
        #endif
    }

    /// The card's own menu on a touch screen and on a long press of a TV remote: what a press does, and playing it where it can be played.
    @ViewBuilder private var menu: some View {
        if card.action != nil {
            Button { actor.perform(card.action) } label: { Label("Open", systemImage: "arrow.up.forward.square") }
        }
        let playId = card.props.text("playId")
        if !playId.isEmpty, Int64(playId) != nil {
            Button { actor.go(.play(item: playId, resume: true)) } label: { Label("Play", systemImage: "play.fill") }
            if card.progress != nil {
                Button { actor.go(.play(item: playId, resume: false)) } label: { Label("Play from the start", systemImage: "arrow.counterclockwise") }
            }
        }
    }

    private var chip: some View {
        Button { actor.perform(card.action) } label: {
            HStack(spacing: layout.sp("xs")) {
                // A library's chip has its kind's icon before its name.
                if !card.icon.isEmpty || !card.props.text("icon").isEmpty {
                    Image(systemName: SDUIIcon.symbol(card.icon.isEmpty ? card.props.text("icon") : card.icon, or: "folder"))
                        .font(.wm(size: layout.isTV ? 26 : 15, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(card.shown("title").isEmpty ? card.title : card.shown("title"))
                    .sduiFont("body", weight: .medium)
                    .lineLimit(1)
                    .foregroundStyle(palette.text)
            }
                .padding(.horizontal, layout.sp("m"))
                .frame(minHeight: layout.isTV ? 66 : 44)
                .background(Capsule().fill(palette.card))
        }
        #if os(tvOS)
        .buttonStyle(TvTileStyle(radius: 33))
        #else
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder private var content: some View {
        if style == "channel" || style == "logo" {
            channel
        } else if style == "tile" {
            tile
        } else if style == "plate" {
            plateCard
        } else if style == "block" {
            blockCard
        } else {
            VStack(alignment: isCircle ? .center : .leading, spacing: layout.sp("xs")) {
                HStack(alignment: .bottom, spacing: layout.sp("xs")) {
                    if shows("rank") {
                        // A top ten's number beside its card.
                        Text(card.shown("rank"))
                            .font(.wm(size: height * 0.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(palette.textHint)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    picture
                }
                // On Apple TV the words sit on the card's own plate, a little in from its edge.
                VStack(alignment: isCircle ? .center : .leading, spacing: layout.sp("xs")) { words }
                    .padding(.horizontal, layout.isTV ? 10 : 0)
                    .padding(.bottom, layout.isTV && !card.text.isEmpty ? 10 : 0)
            }
            .frame(width: fills ? nil : frameWidth, alignment: .leading)
            .frame(maxWidth: fills ? .infinity : nil, alignment: isCircle ? .center : .leading)
            .contentShape(Rectangle())
        }
    }

    /// A numbered card is wider by its number.
    private var frameWidth: CGFloat { shows("rank") ? width + height * 0.35 : width }

    private var pictureSymbol: String {
        card.icon.isEmpty ? SDUIIcon.symbol(kind: card.props.text("kind")) : SDUIIcon.symbol(card.icon)
    }

    private var picture: some View {
        let clip = isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: draw.radius("Card", style: style), style: .continuous))
        return Color.clear
            .aspectRatio(width / max(height, 1), contentMode: .fit)
            .frame(width: fills ? nil : width)
            .overlay { SDUIPicture(picture: card.picture, symbol: pictureSymbol, shownWidth: width) }
            // No picture (a game with no art): its name on the tile, as the website draws a box with the title, so the
            // card is never a blank grey square. Only where the card doesn't print its title under the picture already.
            .overlay(alignment: .bottom) {
                if card.picture == nil, !isCircle, !card.title.isEmpty, !shows("title") {
                    Text(card.title)
                        .sduiFont("title", weight: .semibold)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(layout.sp("s"))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topLeading) {
                if shows("badges") {
                    HStack(spacing: 4) { ForEach(card.badges.prefix(3), id: \.self) { plate($0) } }.padding(layout.sp("xs"))
                }
            }
            .overlay(alignment: .topTrailing) {
                if shows("watched") {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.wm(size: layout.isTV ? 28 : 18, weight: .semibold))
                        .foregroundStyle(palette.onAccent, palette.accent)
                        .padding(layout.sp("xs"))
                } else if shows("unwatched") {
                    plate(card.shown("unwatched")).padding(layout.sp("xs"))
                }
            }
            .overlay(alignment: .bottom) {
                if shows("progress"), let percent = card.progress {
                    ProgressStrip(fraction: Double(percent) / 100).padding(layout.sp("xs"))
                }
            }
            .overlay { FinishCardEdge(shape: clip) }
            .clipShape(clip)
            .tvFocusRing(radius: isCircle ? 999 : draw.radius("Card", style: style))
    }

    private func plate(_ words: String) -> some View {
        Text(words)
            .font(.wm(size: CGFloat(layout.text["badge"] ?? layout.textSize("caption")), weight: .semibold))
            .foregroundStyle(onImage)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: draw.radius("Card", "badge", style: style), style: .continuous).fill(palette.scrim))
            .accessibilityHidden(true)
    }

    /// The title and what's under it, in the title and caption sizes the device was given (docs/SDUI.md, Card).
    @ViewBuilder private var words: some View {
        if shows("title") {
            Text(card.shown("title"))
                .sduiFont("title", weight: .medium)
                .foregroundStyle(palette.text)
                .sduiLines(card.lineLimit("title"))
                .multilineTextAlignment(isCircle ? .center : .leading)
        }
        let under = [shows("subtitle") ? card.shown("subtitle") : "", shows("remaining") ? card.shown("remaining") : ""].filter { !$0.isEmpty }
        if !under.isEmpty {
            Text(under.joined(separator: " · "))
                .sduiFont("caption")
                .foregroundStyle(palette.textSecondary)
                .sduiLines(card.lineLimit("subtitle") ?? 1)
                .multilineTextAlignment(isCircle ? .center : .leading)
        }
        if shows("synopsis") {
            Text(card.shown("synopsis"))
                .sduiFont("caption")
                .foregroundStyle(palette.textSecondary)
                .sduiLines(card.lineLimit("synopsis"))
                .multilineTextAlignment(.leading)
        }
    }

    /// A channel: its logo fitted on a plain tile, its number and name, what's on now with how far through it is, and what's next.
    private var channel: some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            Color.clear
                .aspectRatio(width / max(height, 1), contentMode: .fit)
                .frame(width: fills ? nil : width)
                .overlay { SDUIPicture(picture: card.picture, symbol: "tv", contain: true, shownWidth: width) }
                .overlay(alignment: .bottom) {
                    if shows("progress"), let percent = card.progress { ProgressStrip(fraction: Double(percent) / 100).padding(layout.sp("xs")) }
                }
                .clipShape(RoundedRectangle(cornerRadius: draw.radius("Card", style: style), style: .continuous))
                .tvFocusRing(radius: draw.radius("Card", style: style))
            HStack(spacing: layout.sp("xs")) {
                if shows("number") { Text(card.shown("number")).foregroundStyle(palette.textSecondary) }
                if shows("title") { Text(card.shown("title")).foregroundStyle(palette.text) }
            }
            .sduiFont("title", weight: .medium)
            .lineLimit(1)
            if shows("now") {
                Text(card.shown("now")).sduiFont("caption").foregroundStyle(palette.text).sduiLines(card.lineLimit("now"))
            }
            if shows("next") {
                Text("Next: " + card.shown("next")).sduiFont("caption").foregroundStyle(palette.textSecondary).sduiLines(card.lineLimit("next"))
            }
        }
        .frame(width: fills ? nil : width, alignment: .leading)
        .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Upright art with the title over it on a scrim along its foot (the Rail look's card).
    private var plateCard: some View {
        Color.clear
            .aspectRatio(width / max(height, 1), contentMode: .fit)
            .frame(width: fills ? nil : width)
            .frame(maxWidth: fills ? .infinity : nil)
            .overlay { SDUIPicture(picture: card.picture, symbol: pictureSymbol, shownWidth: width) }
            .overlay { LinearGradient(colors: [.clear, palette.scrim], startPoint: .center, endPoint: .bottom) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if shows("title") {
                        Text(card.shown("title")).sduiFont("title", weight: .semibold).foregroundStyle(onImage).sduiLines(card.lineLimit("title"))
                    }
                    if shows("subtitle"), !card.shown("subtitle").isEmpty {
                        Text(card.shown("subtitle")).sduiFont("caption").foregroundStyle(onImage.opacity(0.85)).sduiLines(card.lineLimit("subtitle") ?? 1)
                    }
                }
                .padding(layout.sp("s"))
            }
            .overlay(alignment: .topLeading) {
                if shows("badges") {
                    HStack(spacing: 4) { ForEach(card.badges.prefix(3), id: \.self) { plate($0) } }.padding(layout.sp("xs"))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: draw.radius("Card", style: style), style: .continuous))
            .tvFocusRing(radius: draw.radius("Card", style: style))
            .contentShape(Rectangle())
    }

    /// A flat block of the theme's card colour with the title in it: teletext's cell.
    private var blockCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.shown("title")).sduiFont("title", weight: .semibold).foregroundStyle(palette.text).sduiLines(card.lineLimit("title"))
            if shows("subtitle"), !card.shown("subtitle").isEmpty {
                Text(card.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).sduiLines(card.lineLimit("subtitle") ?? 1)
            }
            Spacer(minLength: 0)
        }
        .padding(layout.sp("s"))
        .frame(width: fills ? nil : width, height: fills ? nil : height, alignment: .topLeading)
        .frame(maxWidth: fills ? .infinity : nil, alignment: .topLeading)
        .aspectRatio(fills ? width / max(height, 1) : nil, contentMode: .fit)
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: draw.radius("Card", style: style), style: .continuous))
        .tvFocusRing(radius: draw.radius("Card", style: style))
        .contentShape(Rectangle())
    }

    /// A wide tile with its name over the picture, or over a plain tile with an icon: a library, a collection.
    private var tile: some View {
        Color.clear
            .aspectRatio(width / max(height, 1), contentMode: .fit)
            .frame(width: fills ? nil : width)
            .frame(maxWidth: fills ? .infinity : nil)
            .overlay { SDUIPicture(picture: card.picture, symbol: pictureSymbol, shownWidth: width) }
            .overlay {
                if card.picture != nil {
                    LinearGradient(colors: [.clear, palette.scrim], startPoint: .center, endPoint: .bottom)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if shows("title") {
                        Text(card.shown("title"))
                            .sduiFont("title", weight: .semibold)
                            .foregroundStyle(card.picture == nil ? palette.text : onImage)
                            .sduiLines(card.lineLimit("title"))
                    }
                    if shows("count") {
                        Text(card.shown("count") + (card.shown("count") == "1" ? " item" : " items"))
                            .sduiFont("caption")
                            .foregroundStyle(card.picture == nil ? palette.textSecondary : onImage.opacity(0.85))
                    }
                }
                .padding(layout.sp("s"))
            }
            .clipShape(RoundedRectangle(cornerRadius: draw.radius("Card", style: style), style: .continuous))
            .tvFocusRing(radius: draw.radius("Card", style: style))
            .contentShape(Rectangle())
    }
}

/// The last card of a television's row: "See all", in the row's shape.
struct SDUISeeAllCard: View {
    @Environment(\.sduiDraw) private var draw
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let width: CGFloat
    let height: CGFloat
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: draw.radius("Card"), style: .continuous)
                .fill(palette.card)
                .frame(width: width, height: height)
                .overlay {
                    VStack(spacing: layout.sp("xs")) {
                        Image(systemName: "chevron.right.circle").font(.wm(size: 44, weight: .medium))
                        Text("See all").sduiFont("body", weight: .medium)
                    }
                    .foregroundStyle(palette.textSecondary)
                }
        }
        .tileStyle()
        .accessibilityLabel("See all, \(title)")
    }
}
