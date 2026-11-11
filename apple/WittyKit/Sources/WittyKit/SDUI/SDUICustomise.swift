// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// "Customise" for one page, as a person edits it: the page's sections in their order with what may be done
/// to each, the density, each row's card size and each strip of tabs' first tab. Made from what the page says
/// (`document.personal`), what the profile stored before, and the page itself; what it sends back is `personal`.
/// The server's docs/SDUI.md, "Personalisation".
public struct SDUICustomise: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var hidden: Bool
        public var pinned: Bool
        /// Never hidden and never moves.
        public var locked: Bool
        /// Nothing in it now, so it isn't on the page; it can still be placed.
        public var empty: Bool
        /// `s`, `m` or `l` for a row or grid of cards that's on the page; nil for a section that has no cards.
        public var cardSize: String?
    }

    public struct TabChoice: Equatable, Identifiable, Sendable {
        /// The `Tabs` section's ID.
        public var id: String
        public var title: String
        public var tabs: [SDUIOption]
        /// The tab that opens first.
        public var chosen: String
    }

    public static let densities = ["compact", "comfortable", "spacious"]
    public static let cardSizes = ["s", "m", "l"]

    public var rows: [Row]
    public var density: String
    public var tabs: [TabChoice]
    public let allow: Set<String>
    /// False when the profile's `editLayout` switch is off or the server has personalisation off: nothing is offered.
    public let editable: Bool
    public let url: String
    private let before: SDUIPersonal
    /// What would be sent with nothing changed, to tell whether anything has been.
    private var untouched = SDUIPersonal()

    public init(document: SDUIDocument, stored: SDUIPersonal) {
        let info = document.personal ?? SDUIPersonalInfo()
        editable = info.editable == true
        allow = editable ? Set(info.allow ?? []) : []
        url = info.url ?? ""
        before = stored
        density = SDUICustomise.densities.contains(info.density ?? "") ? info.density ?? "comfortable" : (stored.density ?? "comfortable")
        var sizes: [String: String] = [:]
        var found: [TabChoice] = []
        func look(_ node: SDUINode, top: Bool) {
            if top, ["Shelf", "Grid"].contains(node.type), SDUICustomise.cardSizes.contains(node.properties.text("cardSize")) {
                sizes[node.id] = node.properties.text("cardSize")
            }
            if node.type == "Tabs" {
                let options = node.kids.filter { $0.type == "Tab" }.map { SDUIOption(value: $0.id, label: $0.properties.text("label")) }
                let open = stored.defaultTab?[node.id] ?? node.properties.text("default")
                let chosen = options.contains { $0.value == open } ? open : (options.first?.value ?? "")
                if options.count > 1 { found.append(TabChoice(id: node.id, title: options.map(\.label).joined(separator: ", "), tabs: options, chosen: chosen)) }
            }
            for child in node.kids { look(child, top: false) }
        }
        for section in document.root.kids { look(section, top: true) }
        tabs = found
        rows = (info.sections ?? []).map { section in
            Row(id: section.id, title: (section.title ?? "").isEmpty ? section.id : section.title ?? "", hidden: section.hidden == true,
                pinned: section.pinned == true, locked: section.locked == true, empty: section.empty == true,
                cardSize: stored.cardSize?[section.id].flatMap { SDUICustomise.cardSizes.contains($0) ? $0 : nil } ?? sizes[section.id])
        }
        untouched = personal
    }

    public var canReorder: Bool { allow.contains("reorder") }
    public var canHide: Bool { allow.contains("hide") }
    public var canPin: Bool { allow.contains("pin") }
    public var canDensity: Bool { allow.contains("density") }
    public var canCardSize: Bool { allow.contains("cardSize") }
    public var canDefaultTab: Bool { allow.contains("defaultTab") && !tabs.isEmpty }
    /// Whether there's anything to offer at all.
    public var offersAnything: Bool { editable && !allow.isEmpty && !(rows.isEmpty && tabs.isEmpty && !canDensity) }

    public func canMove(_ id: String) -> Bool { canReorder && rows.contains { $0.id == id && !$0.locked } }

    /// Whether a row can go one place up (`-1`) or down (`1`): it never passes out of its own part of the list
    /// (pinned rows stay together at the top) and never changes places with a locked row.
    public func canMove(_ id: String, by step: Int) -> Bool {
        guard canMove(id), let at = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(at + step) else { return false }
        let other = rows[at + step]
        return !other.locked && other.pinned == rows[at].pinned
    }

    /// One place up or down, for a remote.
    public mutating func move(_ id: String, by step: Int) {
        guard canMove(id, by: step), let at = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.swapAt(at, at + step)
    }

    /// A drag: the row at `from` lands before what was at `to` (SwiftUI's `onMove` numbering). A locked row
    /// doesn't move, and a row lands in its own part of the list: pinned among the pinned.
    public mutating func move(from: Int, to: Int) {
        guard canReorder, rows.indices.contains(from), !rows[from].locked, (0...rows.count).contains(to) else { return }
        let row = rows.remove(at: from)
        rows.insert(row, at: min(to > from ? to - 1 : to, rows.count))
        settle()
    }

    public mutating func setHidden(_ id: String, _ hidden: Bool) {
        guard canHide, let at = rows.firstIndex(where: { $0.id == id }), !rows[at].locked else { return }
        rows[at].hidden = hidden
        // Something hidden isn't pinned to the top.
        if hidden { rows[at].pinned = false }
        settle()
    }

    public mutating func setPinned(_ id: String, _ pinned: Bool) {
        guard canPin, let at = rows.firstIndex(where: { $0.id == id }), !rows[at].locked, !rows[at].hidden || !pinned else { return }
        var row = rows.remove(at: at)
        row.pinned = pinned
        // Pinned ones come first, in the order they were pinned; an unpinned one goes to the top of the rest.
        let end = rows.lastIndex(where: \.pinned).map { $0 + 1 } ?? 0
        rows.insert(row, at: end)
    }

    public mutating func setCardSize(_ id: String, _ size: String) {
        guard canCardSize, SDUICustomise.cardSizes.contains(size), let at = rows.firstIndex(where: { $0.id == id }), rows[at].cardSize != nil else { return }
        rows[at].cardSize = size
    }

    public mutating func setDensity(_ value: String) {
        guard canDensity, SDUICustomise.densities.contains(value) else { return }
        density = value
    }

    public mutating func setDefaultTab(_ tabsID: String, _ tab: String) {
        guard canDefaultTab, let at = tabs.firstIndex(where: { $0.id == tabsID }), tabs[at].tabs.contains(where: { $0.value == tab }) else { return }
        tabs[at].chosen = tab
    }

    /// Pinned rows stay together at the top, in their order.
    private mutating func settle() {
        rows = rows.filter(\.pinned) + rows.filter { !$0.pinned }
    }

    /// What to PUT: only what the page allows to be changed is in it, and what was stored before that this page
    /// doesn't show (a row of another variant, a size for a row that's hidden) is kept.
    public var personal: SDUIPersonal {
        var out = before
        let known = Set(rows.map(\.id))
        if canReorder {
            let kept = (before.order ?? []).filter { !known.contains($0) }
            out.order = rows.filter { !$0.pinned }.map(\.id) + kept
        }
        if canHide { out.hidden = rows.filter(\.hidden).map(\.id) + (before.hidden ?? []).filter { !known.contains($0) } }
        if canPin { out.pinned = rows.filter(\.pinned).map(\.id) + (before.pinned ?? []).filter { !known.contains($0) } }
        if canDensity { out.density = density == "comfortable" ? nil : density }
        if canCardSize {
            var sizes = before.cardSize ?? [:]
            for row in rows {
                // A size is stored only once it differs from the page's own, or was stored before.
                if let size = row.cardSize, size != "m" || sizes[row.id] != nil { sizes[row.id] = size }
            }
            out.cardSize = sizes.isEmpty ? nil : sizes
        }
        if canDefaultTab {
            var chosen = before.defaultTab ?? [:]
            for choice in tabs where !choice.chosen.isEmpty { chosen[choice.id] = choice.chosen }
            out.defaultTab = chosen.isEmpty ? nil : chosen
        }
        for list in [\SDUIPersonal.order, \SDUIPersonal.hidden, \SDUIPersonal.pinned] where out[keyPath: list]?.isEmpty == true {
            out[keyPath: list] = nil
        }
        return out
    }

    /// Whether anything differs from what was stored.
    public var changed: Bool { SDUICustomise.settled(personal) != SDUICustomise.settled(untouched) }

    private static func settled(_ personal: SDUIPersonal) -> SDUIPersonal {
        var out = personal
        if out.order?.isEmpty == true { out.order = nil }
        if out.hidden?.isEmpty == true { out.hidden = nil }
        if out.pinned?.isEmpty == true { out.pinned = nil }
        if out.cardSize?.isEmpty == true { out.cardSize = nil }
        if out.defaultTab?.isEmpty == true { out.defaultTab = nil }
        if out.density == "comfortable" || out.density == "" { out.density = nil }
        return out
    }
}

/// The main menu as a profile arranges it: order and hidden entries, Settings never hidden.
public struct SDUINavCustomise: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var icon: String
        public var hidden: Bool
        /// Settings: it can be moved, never hidden.
        public var fixed: Bool
    }

    public var rows: [Row]
    private let before: SDUIPersonal

    /// `shown` is the menu as the server sends it now; what the profile hid isn't in it and is listed after, by ID.
    public init(shown: [SDUINavItem], stored: SDUIPersonal, names: [String: String] = [:]) {
        before = stored
        var rows = shown.map { Row(id: $0.id, label: $0.label, icon: $0.icon ?? "", hidden: false, fixed: $0.isSettings) }
        for id in stored.hidden ?? [] where !rows.contains(where: { $0.id == id }) {
            rows.append(Row(id: id, label: names[id] ?? id, icon: "", hidden: true, fixed: false))
        }
        self.rows = rows
    }

    public mutating func move(from: Int, to: Int) {
        guard rows.indices.contains(from), (0...rows.count).contains(to) else { return }
        let row = rows.remove(at: from)
        rows.insert(row, at: min(to > from ? to - 1 : to, rows.count))
    }

    public mutating func move(_ id: String, by step: Int) {
        guard let at = rows.firstIndex(where: { $0.id == id }), rows.indices.contains(at + step) else { return }
        rows.swapAt(at, at + step)
    }

    public mutating func setHidden(_ id: String, _ hidden: Bool) {
        guard let at = rows.firstIndex(where: { $0.id == id }), !rows[at].fixed else { return }
        rows[at].hidden = hidden
    }

    public var personal: SDUIPersonal {
        var out = before
        out.order = rows.map(\.id)
        let hidden = rows.filter(\.hidden).map(\.id)
        out.hidden = hidden.isEmpty ? nil : hidden
        return out
    }

    public var changed: Bool { personal != before }
}
