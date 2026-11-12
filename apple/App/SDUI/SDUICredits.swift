// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Cast and crew under a title's header (catalogue revision 5; the server's docs/SDUI.md, Cast and crew, Credits):
// the cast as a row of round portraits with the part each played, the guest stars the same way, then the crew by
// department; Show all asks for everyone. Each person opens their own page (`/person/<id>`).

struct SDUICreditsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @EnvironmentObject private var store: SDUIPageStore
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let credits: SDUIElement

    /// One part of the credits, in the server's order: `cast`, `guests`, or a department.
    struct Part: Identifiable {
        let id: String
        let label: String
        /// `cast` and `guests` are portraits; a department is names and jobs.
        let isPeople: Bool
        let cards: [SDUIElement]
    }

    private var parts: [Part] {
        let groups = credits.props.items("groups").compactMap { $0.object }
        var out: [Part] = groups.map { group in
            let id = group.text("id")
            let role = group.text("role")
            return Part(id: id, label: group.text("label"), isPeople: role == "cast" || role == "guests" || id == "cast" || id == "guests",
                        cards: credits.children.filter { $0.props.text("group") == id })
        }
        // A card in a part the groups don't list still shows, under its own heading.
        let listed = Set(out.map(\.id))
        let others = credits.children.filter { !listed.contains($0.props.text("group")) }
        if !others.isEmpty { out.append(Part(id: "other", label: "", isPeople: false, cards: others)) }
        return out.filter { !$0.cards.isEmpty }
    }

    private var portrait: CGFloat {
        let sent = CGFloat(credits.cardWidth)
        return sent > 0 ? sent : (layout.isTV ? 140 : 96)
    }

    private var actor: SDUIActor { SDUIActor(model: model, center: center, store: store) }
    private var showAll: String? { credits.hasMore ? (credits.buttons.first?.label ?? "Show all") : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("m")) {
            heading
            switch credits.state {
            case .error:
                SDUISectionError(id: credits.id) { Task { await store.retry(credits, center: center) } }
            case .deferred:
                SDUIPlaceholderRow(count: 6, width: portrait, height: portrait, circle: true)
            default:
                ForEach(parts) { part in
                    if part.isPeople { peopleRow(part) } else { department(part) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(credits.label)
        .accessibilityIdentifier("sdui.section." + credits.id)
        .task(id: credits.stateName) { await store.fill(credits, center: center) }
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: layout.sp("s")) {
            Text(credits.shown("title"))
                .sduiFont("heading")
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            // A TV's Show all is the last card of the cast row, where the remote goes.
            if let showAll, !layout.isTV {
                Button { Task { await store.retry(credits, center: center) } } label: {
                    HStack(spacing: 2) {
                        Text(showAll)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .sduiFont("caption", weight: .medium)
                    .foregroundStyle(palette.textSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sdui.credits.showAll")
            }
        }
        .padding(.horizontal, layout.margin)
    }

    // MARK: The cast and the guest stars

    private func peopleRow(_ part: Part) -> some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            if part.id != "cast" || parts.first?.id != "cast" {
                Text(part.label).sduiFont("title").foregroundStyle(palette.text).padding(.horizontal, layout.margin)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: layout.isTV ? 40 : layout.sp("m")) {
                    ForEach(part.cards) { card in
                        Button { actor.perform(card.action) } label: { PersonCard(card: card, side: portrait) }
                            .personButtonStyle()
                            .sduiFocusable(card.isFocusable ? focus : nil, card.id)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(card.label)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("sdui.card." + card.id)
                    }
                    if layout.isTV, let showAll, part.id == parts.first(where: \.isPeople)?.id {
                        Button { Task { await store.retry(credits, center: center) } } label: {
                            VStack(spacing: layout.sp("xs")) {
                                Circle().fill(palette.card).frame(width: portrait, height: portrait)
                                    .overlay(Image(systemName: "arrow.right").font(.system(size: portrait * 0.25, weight: .semibold)))
                                Text(showAll).sduiFont("body").foregroundStyle(palette.text)
                            }
                            .frame(width: portrait)
                        }
                        .personButtonStyle()
                        .accessibilityIdentifier("sdui.credits.showAll")
                    }
                }
                .padding(.horizontal, layout.margin)
                .padding(.vertical, layout.isTV ? Tokens.focusRoom : 2)
            }
            .unclippedScroll()
            .remoteSection()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(part.label.isEmpty ? "Cast" : part.label)
        }
    }

    // MARK: The crew

    @ViewBuilder private func department(_ part: Part) -> some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            if !part.label.isEmpty {
                Text(part.label)
                    .sduiFont(layout.isTV ? "title" : "caption", weight: .semibold)
                    .foregroundStyle(layout.isTV ? palette.text : palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
            }
            #if os(tvOS)
            // Focusable chips in a row, name and job.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.sp("s")) {
                    ForEach(part.cards) { card in
                        Button { actor.perform(card.action) } label: {
                            HStack(spacing: 10) {
                                Text(card.shown("title")).foregroundStyle(palette.text)
                                Text(card.shown("subtitle")).foregroundStyle(palette.textSecondary)
                            }
                            .sduiFont("body")
                            .lineLimit(1)
                        }
                        .action(pill: true)
                        .sduiFocusable(card.isFocusable ? focus : nil, card.id)
                        .accessibilityLabel(card.label)
                        .accessibilityIdentifier("sdui.card." + card.id)
                    }
                }
                .padding(.vertical, Tokens.focusRoom)
            }
            .unclippedScroll()
            .remoteSection()
            #else
            // "<name>, <job>" lines that wrap, each a link to the person.
            FlowLayout(spacing: layout.sp("m"), rowSpacing: layout.sp("xs")) {
                ForEach(part.cards) { card in
                    Button { actor.perform(card.action) } label: {
                        (Text(card.shown("title")).foregroundColor(palette.accentText)
                            + Text(card.shown("subtitle").isEmpty ? "" : ", " + card.shown("subtitle")).foregroundColor(palette.textSecondary))
                            .sduiFont("body")
                            .lineLimit(2)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.label)
                    .accessibilityAddTraits(.isLink)
                    .accessibilityIdentifier("sdui.card." + card.id)
                }
            }
            #endif
        }
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(part.label)
    }
}

/// A round portrait, the name under it and the part played under that. Without a photo, the person's initials on `bg3`.
private struct PersonCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let card: SDUIElement
    let side: CGFloat

    private var initials: String {
        let words = card.shown("title").split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }.map(String.init)
        return letters.joined().uppercased()
    }

    var body: some View {
        VStack(spacing: layout.sp("xs")) {
            ZStack {
                Circle().fill(palette.card)
                if card.picture != nil {
                    SDUIPicture(picture: card.picture, symbol: "person", shownWidth: side).clipShape(Circle())
                } else {
                    Text(initials)
                        .font(.system(size: side * 0.32, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: side, height: side)
            Text(card.shown("title")).sduiFont("body", weight: .medium).foregroundStyle(palette.text)
                .lineLimit(1).multilineTextAlignment(.center)
            if !card.shown("subtitle").isEmpty {
                Text(card.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .frame(width: side)
    }
}

private extension View {
    /// A TV's lifted card; a plain press elsewhere.
    @ViewBuilder func personButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.borderless)
        #else
        buttonStyle(.plain)
        #endif
    }
}
