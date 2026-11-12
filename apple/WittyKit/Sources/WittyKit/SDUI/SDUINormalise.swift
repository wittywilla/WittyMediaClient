// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// A page as this app lays it out, described without pixels, in the conformance kit's shape (the server's
/// pkg/sdui/conformance/README.md). It is written from the elements the views draw, not from the JSON, so two
/// renderers that agree on it for every fixture draw the same page.
public struct SDUINormalised: Encodable, Equatable, Sendable {
    public struct Page: Encodable, Equatable, Sendable {
        public var title: String
        public var formFactor: String
        public var breakpoint: String
        public var density: String
        public var contentWidth: Int
        public var sectionGap: Int
        public var scope: String?
        public var shell: SDUIShell?
    }

    public struct Element: Encodable, Equatable, Sendable {
        public var id: String
        public var type: String
        public var depth: Int
        public var role: String
        public var label: String
        public var state: String?
        public var text: [String: String]?
        public var lines: [String: Int]?
        public var textSize: Int?
        public var cards: Int?
        public var placeholders: Int?
        public var cardStyle: String?
        public var cardWidth: Int?
        public var cardHeight: Int?
        public var columns: Int?
        public var hasMore: Bool?
        public var seeAll: String?
        public var image: String?
        public var shows: [String]?
        public var progress: Int?
        public var buttons: [String]?
        public var action: String?
        public var scope: String?
    }

    public struct Focus: Encodable, Equatable, Sendable {
        public var order: [String]
        public var `default`: String
        public var groups: [String: [String]]?
    }

    public var kit = 1
    public var page: Page
    public var visible: [Element]
    public var focus: Focus
}

public extension SDUIScreen {
    /// What this screen draws, in the conformance kit's words.
    func normalised() -> SDUINormalised {
        let layout = document.layout
        return SDUINormalised(
            page: .init(title: document.page.title, formFactor: layout.formFactor, breakpoint: layout.breakpoint,
                        density: layout.density, contentWidth: layout.contentWidth(), sectionGap: layout.sectionGap,
                        scope: document.theme?.scope, shell: layout.shell),
            visible: root.flattened.map(\.normalised),
            focus: .init(order: focus.order, default: focus.start, groups: focus.groups.isEmpty ? nil : focus.groups))
    }
}

public extension SDUIElement {
    /// The picture this element asks for, in the kit's words: "poster 320"; "icon movie" where a card draws an icon instead.
    var pictureWords: String {
        func words(_ ref: SDUIImageRef?) -> String { ref.map { "\($0.kind) \($0.width)" } ?? "" }
        if type == "DetailHeader" { return SDUIWords.join([words(picture), words(poster)]) }
        if let picture { return words(picture) }
        return type == "Card" && role == "button" && !icon.isEmpty ? "icon " + icon : ""
    }

    /// The labels of its buttons in order, the primary one starred; a filter bar's controls; a show's seasons.
    var buttonWords: [String] {
        if !filters.isEmpty { return filters.map(\.summary) }
        if !seasons.isEmpty { return seasons.map { ($0.selected ? "*" : "") + $0.title } }
        return buttons.map { ($0.primary ? "*" : "") + $0.label }
    }

    var normalised: SDUINormalised.Element {
        // A hero's slide is a group whose buttons act; it has no action of its own.
        let isSlide = type == "Card" && role == "group"
        return SDUINormalised.Element(
            id: id, type: type, depth: depth, role: role, label: label, state: stateName.isEmpty ? nil : stateName,
            text: text.isEmpty ? nil : text, lines: lines.isEmpty ? nil : lines, textSize: textSize, cards: cards,
            placeholders: placeholders, cardStyle: cardStyle, cardWidth: cardWidth, cardHeight: cardHeight, columns: columns,
            hasMore: hasMore, seeAll: seeAll, image: pictureWords, shows: shows.isEmpty ? nil : shows, progress: progress,
            buttons: buttonWords.isEmpty ? nil : buttonWords, action: isSlide ? nil : SDUIWords.action(action),
            scope: scope.isEmpty ? nil : scope)
    }
}
