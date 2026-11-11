// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Where focus starts and goes on a page: the server's docs/SDUI.md, "Focus". Reading order is the page's
/// `focus.order`; a group is one focus section that remembers its member; movement between sections follows
/// the page's order, never geometry.
public struct SDUIFocusPlan: Equatable, Sendable {
    /// Everything that can take focus, in the order Tab or a screen reader's "next" visits it.
    public var order: [String]
    /// Where focus starts.
    public var start: String
    /// Each group's members, in order.
    public var groups: [String: [String]]
    /// The page's stops from top to bottom: a group's ID, or the ID of a node that is a stop by itself.
    public var stops: [String]
    private var groupOf: [String: String]

    public init(root: SDUINode) {
        var byOrder: [(Int, SDUINode)] = []
        func collect(_ node: SDUINode) {
            if let focus = node.focus { byOrder.append((focus.order, node)) }
            for child in node.kids { collect(child) }
        }
        collect(root)
        // Reading order is `order`; the same number twice keeps the tree's order.
        let sorted = byOrder.enumerated().sorted { a, b in
            a.element.0 != b.element.0 ? a.element.0 < b.element.0 : a.offset < b.offset
        }.map(\.element.1)
        var order: [String] = [], groups: [String: [String]] = [:], stops: [String] = [], groupOf: [String: String] = [:]
        var start = ""
        for node in sorted {
            order.append(node.id)
            if node.focus?.isDefault == true, start.isEmpty { start = node.id }
            if let group = node.focus?.group, !group.isEmpty {
                if groups[group] == nil { stops.append(group) }
                groups[group, default: []].append(node.id)
                groupOf[node.id] = group
            } else {
                stops.append(node.id)
            }
        }
        self.order = order
        self.start = start.isEmpty ? (order.first ?? "") : start
        self.groups = groups
        self.stops = stops
        self.groupOf = groupOf
    }

    /// The stop a node belongs to: its group, or itself.
    public func stop(of id: String) -> String? {
        if let group = groupOf[id] { return group }
        return order.contains(id) ? id : nil
    }

    /// The stop above (`-1`) or below (`1`) another in the page's order. Nil at either end.
    public func stop(from stop: String, by step: Int) -> String? {
        guard let at = stops.firstIndex(of: stop), stops.indices.contains(at + step) else { return nil }
        return stops[at + step]
    }

    /// The node after (`1`) or before (`-1`) another in reading order, for Tab and a screen reader. Nil at either end.
    public func neighbour(of id: String, by step: Int) -> String? {
        guard let at = order.firstIndex(of: id), order.indices.contains(at + step) else { return nil }
        return order[at + step]
    }
}

/// Which member of each group had focus last, and where focus should land when it moves into a group.
/// The system's focus engine picks the nearest card by geometry when focus moves between rows; this says
/// which card it should have been, so the view can put it there.
public struct SDUIFocusMemory: Equatable, Sendable {
    public private(set) var remembered: [String: String] = [:]
    public private(set) var current: String?

    public init() {}

    /// Focus has moved to `id` (nil: off the page). Returns the node focus should be on instead, when it has
    /// just come into a group from outside it and that group remembers another member that is still there.
    public mutating func moved(to id: String?, in plan: SDUIFocusPlan) -> String? {
        let before = current.flatMap { plan.stop(of: $0) }
        current = id
        guard let id, let stop = plan.stop(of: id) else { return nil }
        guard let members = plan.groups[stop] else { return nil }
        if before != stop, let last = remembered[stop], last != id, members.contains(last) {
            current = last
            return last
        }
        remembered[stop] = id
        return nil
    }

    /// Where focus lands in a stop: the member that had focus last, else the group's first, else the stop itself.
    public func landing(in stop: String, plan: SDUIFocusPlan) -> String {
        guard let members = plan.groups[stop] else { return stop }
        if let last = remembered[stop], members.contains(last) { return last }
        return members.first ?? stop
    }

    /// Forgets members that are no longer on the page, after it has been drawn again.
    public mutating func prune(to plan: SDUIFocusPlan) {
        remembered = remembered.filter { plan.groups[$0.key]?.contains($0.value) == true }
        if let now = current, !plan.order.contains(now) { current = nil }
    }
}
