// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Cast and crew under a title's header (catalogue revision 5; the server's docs/SDUI.md, Cast and crew, Credits):
// the cast as a row of round portraits with the part each played, the guest stars the same way, then the crew as
// one row of "Job · Name" chips by department; Show all cast and Show all credits ask for everyone. Each person opens their own page (`/person/<id>`).

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

    private var crew: [Part] { parts.filter { !$0.isPeople } }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sp("m")) {
            heading
            switch credits.state {
            case .error:
                SDUISectionError(id: credits.id) { Task { await store.retry(credits, center: center) } }
            case .deferred:
                SDUIPlaceholderRow(count: 6, width: portrait, height: portrait, circle: true)
            default:
                ForEach(parts.filter(\.isPeople)) { part in peopleRow(part) }
                if !crew.isEmpty { crewRow }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(credits.label)
        .accessibilityIdentifier("sdui.section." + credits.id)
        .task(id: credits.stateName) { await store.fill(credits, center: center) }
    }

    private func askForAll() { Task { await store.retry(credits, center: center) } }

    private var heading: some View {
        Text(credits.shown("title"))
            .sduiFont("heading")
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, layout.margin)
    }

    // MARK: The cast and the guest stars

    /// Round portraits with the part played under each; the first row ends with Show all cast, where the eye and the
    /// remote go.
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
                    if credits.hasMore, part.id == parts.first(where: \.isPeople)?.id {
                        Button(action: askForAll) {
                            VStack(spacing: layout.sp("xs")) {
                                Circle().fill(palette.card).frame(width: portrait, height: portrait)
                                    .overlay(Image(systemName: "arrow.right")
                                        .font(.system(size: portrait * 0.25, weight: .semibold))
                                        .foregroundStyle(palette.text))
                                Text("Show all cast").sduiFont("body", weight: .medium).foregroundStyle(palette.text)
                                    .lineLimit(2).multilineTextAlignment(.center)
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

    /// One Crew row of chips, "Job · Name", department by department in the server's order, ending with Show all
    /// credits. A row that scrolls sideways on a TV; chips that wrap elsewhere.
    private var crewRow: some View {
        VStack(alignment: .leading, spacing: layout.sp("xs")) {
            Text("Crew").sduiFont("title").foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, layout.margin)
            #if os(tvOS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.sp("s")) { crewChips }
                    .padding(.horizontal, layout.margin)
                    .padding(.vertical, Tokens.focusRoom)
            }
            .unclippedScroll()
            .remoteSection()
            #else
            FlowLayout(spacing: layout.sp("s"), rowSpacing: layout.sp("s")) { crewChips }
                .padding(.horizontal, layout.margin)
            #endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crew")
    }

    @ViewBuilder private var crewChips: some View {
        ForEach(crew) { part in
            ForEach(part.cards) { card in
                let job = card.shown("subtitle").isEmpty ? part.label : card.shown("subtitle")
                Button { actor.perform(card.action) } label: {
                    (Text(job.isEmpty ? "" : job + " · ").foregroundColor(palette.textSecondary)
                        + Text(card.shown("title")).foregroundColor(palette.text))
                        .sduiFont("body")
                        .lineLimit(1)
                }
                .action(pill: true)
                .sduiFocusable(card.isFocusable ? focus : nil, card.id)
                .accessibilityLabel(card.label)
                .accessibilityIdentifier("sdui.card." + card.id)
            }
        }
        if credits.hasMore {
            Button(action: askForAll) { Text("Show all credits").sduiFont("body", weight: .semibold).lineLimit(1) }
                .action(pill: true)
                .accessibilityIdentifier("sdui.credits.showAllCrew")
        }
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
