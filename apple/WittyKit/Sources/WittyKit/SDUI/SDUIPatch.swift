// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// One step of the server's ID-keyed tree diff: its docs/SDUI.md, "Patch protocol".
public struct SDUIPatch: Codable, Equatable, Sendable {
    public var op: String
    public var path: String
    public var node: SDUINode?
    public var value: JSONValue?
    public var from: String?

    public init(op: String, path: String, node: SDUINode? = nil, value: JSONValue? = nil, from: String? = nil) {
        self.op = op
        self.path = path
        self.node = node
        self.value = value
        self.from = from
    }
}

/// The answer to `GET /sdui/pages/{page}/diff?since=`: patches from the render the app has, or the whole page.
public struct SDUIDiffAnswer: Decodable, Sendable {
    public var etag: String?
    public var since: String?
    public var patches: [SDUIPatch]?
    public var document: SDUIDocument?
}

/// A patch that can't be applied. The app then drops its tree and asks for the page.
public struct SDUIPatchError: Error, Equatable {
    public let reason: String
}

public extension SDUINode {
    /// The path of child indices from this node down to the one with this ID. Empty for this node itself.
    func path(to id: String) -> [Int]? {
        if self.id == id { return [] }
        for (index, child) in kids.enumerated() {
            if let rest = child.path(to: id) { return [index] + rest }
        }
        return nil
    }

    func node(at path: [Int]) -> SDUINode? {
        var node = self
        for index in path {
            guard node.kids.indices.contains(index) else { return nil }
            node = node.kids[index]
        }
        return node
    }

    func find(_ id: String) -> SDUINode? { path(to: id).flatMap { node(at: $0) } }

    /// Changes the node at a path in place. False when there's no such node.
    @discardableResult
    mutating func change(at path: [Int], _ change: (inout SDUINode) throws -> Void) rethrows -> Bool {
        guard let first = path.first else {
            try change(&self)
            return true
        }
        guard var list = children, list.indices.contains(first) else { return false }
        let done = try list[first].change(at: Array(path.dropFirst()), change)
        children = list
        return done
    }
}

public extension SDUIDocument {
    /// The document with the patches applied in order. Indices refer to the children as they stand after the
    /// patches before. Throws when any step can't be done: nothing half-applied is ever drawn.
    func applying(_ patches: [SDUIPatch]) throws -> SDUIDocument {
        var out = self
        for patch in patches { try out.apply(patch) }
        return out
    }

    private mutating func apply(_ patch: SDUIPatch) throws {
        if patch.path.hasPrefix("/") {
            guard patch.op == "replace" else { throw SDUIPatchError(reason: "document-level paths only support replace") }
            try applyField(patch)
            return
        }
        guard patch.path.hasPrefix("#") else { throw SDUIPatchError(reason: "a path starts with # or /") }
        let (id, index) = try SDUIDocument.parse(patch.path)
        switch patch.op {
        case "add":
            guard let index, let node = patch.node else { throw SDUIPatchError(reason: "add needs a #parent/children/<n> path and a node") }
            guard let at = root.path(to: id) else { throw SDUIPatchError(reason: "unknown parent \(id)") }
            try root.change(at: at) { parent in
                var list = parent.kids
                guard index <= list.count else { throw SDUIPatchError(reason: "index \(index) out of range") }
                list.insert(node, at: index)
                parent.children = list
            }
        case "remove":
            guard index == nil else { throw SDUIPatchError(reason: "remove takes a #id path") }
            guard let at = root.path(to: id), let last = at.last else { throw SDUIPatchError(reason: "unknown node \(id), or the root") }
            root.change(at: Array(at.dropLast())) { parent in
                parent.children?.remove(at: last)
                if parent.children?.isEmpty == true { parent.children = nil }
            }
        case "replace":
            guard index == nil, let node = patch.node else { throw SDUIPatchError(reason: "replace takes a #id path and a node") }
            guard let at = root.path(to: id) else { throw SDUIPatchError(reason: "unknown node \(id)") }
            // Every field of the node but its children.
            root.change(at: at) { target in
                let kept = target.children
                target = node
                target.children = kept
            }
        case "move":
            guard let index, let from = patch.from, from.hasPrefix("#"), !from.contains("/") else {
                throw SDUIPatchError(reason: "move needs a #parent/children/<n> path and a #id from")
            }
            let moving = String(from.dropFirst())
            guard let at = root.path(to: id) else { throw SDUIPatchError(reason: "unknown parent \(id)") }
            guard let source = root.path(to: moving), let position = source.last, Array(source.dropLast()) == at else {
                throw SDUIPatchError(reason: "move must stay within one parent")
            }
            try root.change(at: at) { parent in
                var list = parent.kids
                let node = list.remove(at: position)
                guard index <= list.count else { throw SDUIPatchError(reason: "index \(index) out of range") }
                list.insert(node, at: index)
                parent.children = list
            }
        default:
            throw SDUIPatchError(reason: "unknown op \(patch.op)")
        }
    }

    private mutating func applyField(_ patch: SDUIPatch) throws {
        if patch.path == "/root" {
            guard let node = patch.node else { throw SDUIPatchError(reason: "replace /root needs a node") }
            root = node
            return
        }
        let value = patch.value ?? .null
        func read<T: Decodable>(_ type: T.Type) throws -> T? {
            if value.isNull { return nil }
            guard let read = value.decoded(T.self) else { throw SDUIPatchError(reason: "\(patch.path) can't be read") }
            return read
        }
        switch patch.path {
        case "/page":
            guard let page = try read(SDUIPageInfo.self) else { throw SDUIPatchError(reason: "a page has to be something") }
            self.page = page
        case "/layout":
            guard let layout = try read(SDUILayout.self) else { throw SDUIPatchError(reason: "a layout has to be something") }
            self.layout = layout
        case "/theme": theme = try read(SDUIThemeScope.self)
        case "/personal": personal = try read(SDUIPersonalInfo.self)
        case "/screenTime": screenTime = try read(SDUIScreenTime.self)
        case "/catalog": catalog = try read(Int.self)
        case "/meta":
            // The time it was made and its ETag are never in a patch: the new ETag is the answer's.
            var next = try read(SDUIMeta.self)
            next?.etag = meta?.etag
            next?.generatedAt = meta?.generatedAt
            meta = next
        default:
            throw SDUIPatchError(reason: "unknown document path \(patch.path)")
        }
    }

    /// `#id` or `#id/children/<n>`.
    private static func parse(_ path: String) throws -> (id: String, index: Int?) {
        let body = path.dropFirst()
        guard let mark = body.range(of: "/children/", options: .backwards) else {
            guard !body.isEmpty else { throw SDUIPatchError(reason: "a path names a node") }
            return (String(body), nil)
        }
        guard let index = Int(body[mark.upperBound...]), index >= 0, mark.lowerBound > body.startIndex else {
            throw SDUIPatchError(reason: "bad index in \(path)")
        }
        return (String(body[..<mark.lowerBound]), index)
    }

    // MARK: A section's own pages of items

    /// The document with a page of a section's items in place: appended after the ones there, or in their
    /// place with `replace` or when the section was still waiting for its first. The section's props are
    /// merged, `more` becomes the answer's `next`, and the cards join the section's focus group at the end.
    /// A section whose answer is `empty` leaves the page. Unknown sections change nothing.
    func applying(_ answer: SDUISectionItems, to section: String) -> SDUIDocument {
        var out = self
        guard let at = root.path(to: section) else { return self }
        if answer.state == "empty", let last = at.last {
            out.root.change(at: Array(at.dropLast())) { parent in parent.children?.remove(at: last) }
            out.renumberFocus()
            return out
        }
        out.root.change(at: at) { node in
            let waiting = node.state == "deferred" || node.state == "error"
            var props = node.properties
            for (key, value) in answer.props ?? [:] { props[key] = value }
            if let next = answer.next, !next.isEmpty {
                props["more"] = .object(["url": .string(next)])
            } else {
                props["more"] = nil
            }
            node.props = props
            var arrived = answer.items ?? []
            for index in arrived.indices where arrived[index].focus == nil && arrived[index].action != nil {
                arrived[index].focus = SDUIFocus(order: 0, group: node.id)
            }
            node.children = answer.replace == true || waiting ? arrived : node.kids + arrived
            node.state = answer.state == "error" ? "error" : nil
        }
        out.renumberFocus()
        return out
    }

    /// The section marked as failed: its heading and "Couldn't load this" with Retry.
    func failing(section: String) -> SDUIDocument {
        var out = self
        guard let at = root.path(to: section) else { return self }
        out.root.change(at: at) { $0.state = "error" }
        return out
    }

    /// Focus numbers again in reading order, from 1 without gaps, after cards have arrived or a section has gone.
    /// Reading order is the tree's, except that a strip of tabs is read whole before the chosen tab's content.
    /// Where focus starts doesn't change while that node is still there.
    mutating func renumberFocus() {
        var next = 0
        var hasStart = false
        var first: [Int]?
        func own(_ node: inout SDUINode, _ path: [Int]) {
            guard node.focus != nil else { return }
            next += 1
            node.focus?.order = next
            if node.focus?.isDefault == true { hasStart = true }
            if first == nil { first = path }
        }
        func number(_ node: inout SDUINode, _ path: [Int], skipOwn: Bool = false) {
            if !skipOwn { own(&node, path) }
            guard var list = node.children else { return }
            if node.type == "Tabs" {
                for index in list.indices { own(&list[index], path + [index]) }
                for index in list.indices { number(&list[index], path + [index], skipOwn: true) }
            } else {
                for index in list.indices { number(&list[index], path + [index]) }
            }
            node.children = list
        }
        number(&root, [])
        // The node focus started on has gone: it starts on the first that can take it.
        if !hasStart, let first { root.change(at: first) { $0.focus?.isDefault = true } }
    }

    /// A node's own ETag-free identity for the cache: the page it is and what it was opened with.
    var cacheName: String { page.id + "?" + (page.params ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&") }
}

public extension SDUIDocument {
    /// A page asked for again, with what the app had fetched for the one before kept where it still fits: a
    /// row that arrives waiting for its items keeps the ones it had, and a row or grid that had been paged
    /// further keeps its later pages when it still starts with the same cards. Nothing else is carried over:
    /// what the server sent wins.
    func keepingLoaded(from old: SDUIDocument) -> SDUIDocument {
        guard old.page.id == page.id else { return self }
        var out = self
        func visit(_ node: SDUINode, _ path: [Int]) {
            if ["Shelf", "Grid", "List", "SeasonList", "TrackList"].contains(node.type), let before = old.root.find(node.id), before.type == node.type {
                let had = before.kids.map(\.id), has = node.kids.map(\.id)
                let filledBefore = before.state == nil && !had.isEmpty
                if node.state == "deferred", filledBefore {
                    out.root.change(at: path) { $0 = before }
                } else if node.state == nil, filledBefore, had.count > has.count, !has.isEmpty, Array(had.prefix(has.count)) == has,
                          node.properties["more"] != nil {
                    out.root.change(at: path) { target in
                        // The first page is the server's own, as it is now; the later ones are the ones fetched before.
                        target.children = node.kids + before.kids.dropFirst(has.count)
                        target.props?["more"] = before.properties["more"]
                    }
                }
                return
            }
            for (index, child) in node.kids.enumerated() { visit(child, path + [index]) }
        }
        visit(root, [])
        if out != self { out.renumberFocus() }
        return out
    }
}
