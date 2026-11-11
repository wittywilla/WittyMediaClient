// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// One card of a row or a grid. What it draws is exactly what its style shows of what it carries (the element's
/// `shows`, worked out in WittyKit from the catalogue's card styles), at the size the row gave it. On Apple TV
/// it's the system's card: it lifts and tilts with the remote. On a touch screen a long press opens its menu.
/// A style this app doesn't know is drawn as its shape: the picture, with the title and subtitle under it.
struct SDUICardView: View {
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
                Button { actor.perform(card.action) } label: { content }
                    .tileStyle()
                    .disabled(card.action == nil)
            }
        }
        .sduiFocusable(card.isFocusable ? focus : nil, card.id)
        .sduiScope(card.tokens)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.label)
        .accessibilityAddTraits(.isButton)
        #if os(iOS) || os(visionOS)
        .contextMenu { menu }
        #endif
    }

    /// The card's own menu on a touch screen: what a press does, and playing it where it can be played.
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
            Text(card.shown("title").isEmpty ? card.title : card.shown("title"))
                .sduiFont("body", weight: .medium)
                .lineLimit(1)
                .foregroundStyle(palette.text)
                .padding(.horizontal, layout.sp("m"))
                .frame(minHeight: layout.isTV ? 66 : 44)
                .background(Capsule().fill(palette.card))
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder private var content: some View {
        if style == "channel" {
            channel
        } else if style == "tile" {
            tile
        } else {
            VStack(alignment: isCircle ? .center : .leading, spacing: layout.sp("xs")) {
                HStack(alignment: .bottom, spacing: layout.sp("xs")) {
                    if shows("rank") {
                        // A top ten's number beside its card.
                        Text(card.shown("rank"))
                            .font(.system(size: height * 0.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(palette.textHint)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                    picture
                }
                words
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
        let clip = isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
        return Color.clear
            .aspectRatio(width / max(height, 1), contentMode: .fit)
            .frame(width: fills ? nil : width)
            .overlay { SDUIPicture(picture: card.picture, symbol: pictureSymbol, shownWidth: width) }
            .overlay(alignment: .topLeading) {
                if shows("badges") {
                    HStack(spacing: 4) { ForEach(card.badges.prefix(3), id: \.self) { plate($0) } }.padding(layout.sp("xs"))
                }
            }
            .overlay(alignment: .topTrailing) {
                if shows("watched") {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: layout.isTV ? 28 : 18, weight: .semibold))
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
            .clipShape(clip)
    }

    private func plate(_ words: String) -> some View {
        Text(words)
            .font(.system(size: CGFloat(layout.text["badge"] ?? layout.textSize("caption")), weight: .semibold))
            .foregroundStyle(onImage)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.scrim))
            .accessibilityHidden(true)
    }

    /// The title and what's under it. On a television the words are a size down, as its own cards have them.
    @ViewBuilder private var words: some View {
        let titleRole = layout.isTV ? "body" : "title"
        if shows("title") {
            Text(card.shown("title"))
                .sduiFont(titleRole, weight: .medium)
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
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
            HStack(spacing: layout.sp("xs")) {
                if shows("number") { Text(card.shown("number")).foregroundStyle(palette.textSecondary) }
                if shows("title") { Text(card.shown("title")).foregroundStyle(palette.text) }
            }
            .sduiFont(layout.isTV ? "body" : "title", weight: .medium)
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
                            .sduiFont(layout.isTV ? "body" : "title", weight: .semibold)
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
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// The last card of a television's row: "See all", in the row's shape.
struct SDUISeeAllCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let width: CGFloat
    let height: CGFloat
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(palette.card)
                .frame(width: width, height: height)
                .overlay {
                    VStack(spacing: layout.sp("xs")) {
                        Image(systemName: "chevron.right.circle").font(.system(size: 44, weight: .medium))
                        Text("See all").sduiFont("body", weight: .medium)
                    }
                    .foregroundStyle(palette.textSecondary)
                }
        }
        .tileStyle()
        .accessibilityLabel("See all, \(title)")
    }
}
