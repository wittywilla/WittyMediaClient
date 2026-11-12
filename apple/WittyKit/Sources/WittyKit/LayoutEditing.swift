// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The layout editor's rules (docs/plans/DESIGN-2.md 7.3 and 7.5; the server's docs/SDUI.md, Placements): the shell is made of
// regions (the server's name, the menu, search, You, the clock, the Dock, the key legend, the spotlight), each with a position and
// whether it is shown; a person changes them for their own device and an administrator for everyone. The page's own sections
// (their order, hidden, pinned, card size) are SDUICustomise's. Moving is by pick up, step and drop, so a remote, a pad, a keyboard
// and a finger all do the same; Back cancels; undo, redo and reset are always there.

/// A region of the shell, as `GET /sdui/placements` lists them.
public struct LayoutRegion: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    /// Where it may be; empty: it has none to choose, only to show or hide.
    public let positions: [String]
    /// Can't be hidden: the way to Settings, to You and out of a screen.
    public let locked: Bool
    /// The choices of a region with a style (the spotlight's).
    public let styles: [String]

    enum CodingKeys: String, CodingKey { case id, label, positions, locked, styles }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(String.self, forKey: .id)
        label = (try? box.decode(String.self, forKey: .label)) ?? id
        positions = (try? box.decodeIfPresent([String].self, forKey: .positions)) ?? []
        locked = (try? box.decodeIfPresent(Bool.self, forKey: .locked)) ?? false
        styles = (try? box.decodeIfPresent([String].self, forKey: .styles)) ?? []
    }

    public init(id: String, label: String, positions: [String] = [], locked: Bool = false, styles: [String] = []) {
        self.id = id
        self.label = label
        self.positions = positions
        self.locked = locked
        self.styles = styles
    }
}

/// `GET /sdui/placements`.
public struct LayoutPlacementsAnswer: Decodable, Equatable, Sendable {
    public let experience: String
    public let regions: [LayoutRegion]
    /// In force on this device: the experience's own, the administrator's and the profile's, merged.
    public let placements: [String: SDUIShell.Placement]
    /// The profile's own for this device.
    public let own: [String: SDUIShell.Placement]
    /// False when the profile's `editLayout` switch is off or the server has personalisation off.
    public let editable: Bool

    enum CodingKeys: String, CodingKey { case experience, regions, placements, own, editable }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        experience = (try? box.decode(String.self, forKey: .experience)) ?? ""
        regions = (try? box.decode([LayoutRegion].self, forKey: .regions)) ?? []
        placements = (try? box.decodeIfPresent([String: SDUIShell.Placement].self, forKey: .placements)) ?? [:]
        own = (try? box.decodeIfPresent([String: SDUIShell.Placement].self, forKey: .own)) ?? [:]
        editable = (try? box.decode(Bool.self, forKey: .editable)) ?? false
    }
}

/// A way to say where something goes with the four arrows.
public enum LayoutStep: String, Sendable { case left, right, up, down }

/// What an edit is on: the shell's regions and, when the page has them, its sections.
public struct LayoutDraft: Equatable, Sendable {
    public struct Snapshot: Equatable, Sendable {
        public var placements: [String: SDUIShell.Placement]
        public var page: SDUICustomise?
    }

    public let regions: [LayoutRegion]
    public private(set) var now: Snapshot
    /// What it was when editing began: the finished layout the server sent.
    public let first: Snapshot
    /// The profile's own placements when editing began (for "For me") or the administrator's layer (for "For everyone").
    public let layer: [String: SDUIShell.Placement]
    private var undo: [Snapshot] = []
    private var redo: [Snapshot] = []

    /// `inferred`: where the shell puts a region when the placements don't say (the menu from its style, for one).
    public init(regions: [LayoutRegion], placements: [String: SDUIShell.Placement], layer: [String: SDUIShell.Placement], page: SDUICustomise? = nil,
                inferred: [String: String] = [:]) {
        self.regions = regions
        let start = Snapshot(placements: LayoutDraft.complete(regions, placements, inferred: inferred), page: page)
        now = start
        first = start
        self.layer = layer
    }

    /// Every region has a position and a shown/hidden; one the server left out is where its first position is, shown.
    static func complete(_ regions: [LayoutRegion], _ given: [String: SDUIShell.Placement], inferred: [String: String] = [:]) -> [String: SDUIShell.Placement] {
        var out: [String: SDUIShell.Placement] = [:]
        for r in regions {
            var p = given[r.id] ?? .init(position: nil, visible: nil, style: nil)
            if p.position == nil || !(r.positions.contains(p.position ?? "")) {
                p.position = inferred[r.id].flatMap { r.positions.contains($0) ? $0 : nil } ?? r.positions.first
            }
            if p.visible == nil { p.visible = true }
            if p.style == nil || !(r.styles.contains(p.style ?? "")) { p.style = r.styles.first }
            out[r.id] = p
        }
        return out
    }

    public func region(_ id: String) -> LayoutRegion? { regions.first { $0.id == id } }
    public func position(_ id: String) -> String? { now.placements[id]?.position }
    public func shown(_ id: String) -> Bool { now.placements[id]?.visible != false }
    public func style(_ id: String) -> String? { now.placements[id]?.style }

    public var changed: Bool { now != first }
    public var canUndo: Bool { !undo.isEmpty }
    public var canRedo: Bool { !redo.isEmpty }

    private mutating func commit(_ next: Snapshot) {
        guard next != now else { return }
        undo.append(now)
        redo.removeAll()
        now = next
    }

    public mutating func undoLast() {
        guard let previous = undo.popLast() else { return }
        redo.append(now)
        now = previous
    }

    public mutating func redoLast() {
        guard let next = redo.popLast() else { return }
        undo.append(now)
        now = next
    }

    /// Back to how it was when editing began.
    public mutating func revert() { commit(first) }

    // MARK: Regions

    /// Where an arrow takes a region from where it is, nil when it can't go that way. The menu goes the way the arrow points
    /// (start is left, end is right, top is up, bottom is down); the others step through their places, left and up to the one
    /// before, right and down to the one after.
    public func target(of id: String, _ step: LayoutStep) -> String? {
        guard let region = region(id), let at = position(id), let index = region.positions.firstIndex(of: at) else { return nil }
        let direct: [LayoutStep: String] = [.left: "start", .right: "end", .up: "top", .down: "bottom"]
        if let want = direct[step], region.positions.contains(want), region.positions.contains("start") || region.positions.contains("bottom") {
            return want == at ? nil : want
        }
        let delta = (step == .left || step == .up) ? -1 : 1
        let next = index + delta
        return region.positions.indices.contains(next) ? region.positions[next] : nil
    }

    public mutating func move(_ id: String, to position: String) {
        guard let region = region(id), region.positions.contains(position), var p = now.placements[id] else { return }
        p.position = position
        var next = now
        next.placements[id] = p
        commit(next)
    }

    /// Whether a region may be hidden: the way to Settings, to You and out of a screen may not be.
    public func canHide(_ id: String) -> Bool { region(id).map { !$0.locked } ?? false }

    public mutating func setShown(_ id: String, _ shown: Bool) {
        guard canHide(id) || shown, var p = now.placements[id] else { return }
        p.visible = shown
        var next = now
        next.placements[id] = p
        commit(next)
    }

    public mutating func setStyle(_ id: String, _ style: String) {
        guard let region = region(id), region.styles.contains(style), var p = now.placements[id] else { return }
        p.style = style
        var next = now
        next.placements[id] = p
        commit(next)
    }

    // MARK: Sections

    public mutating func editPage(_ edit: (inout SDUICustomise) -> Void) {
        guard var page = now.page else { return }
        edit(&page)
        var next = now
        next.page = page
        commit(next)
    }

    // MARK: What is sent

    /// The placements to keep as a layer: what was in the layer before, brought up to what it is now, and every region whose
    /// position, shown or style differs from what the server sent. A region left as it was and not in the layer isn't sent, so
    /// a later change of the experience still reaches it.
    public var layerToSave: [String: SDUIShell.Placement] {
        var out: [String: SDUIShell.Placement] = [:]
        for r in regions {
            if first.placements[r.id] != now.placements[r.id], var p = now.placements[r.id] {
                if r.positions.isEmpty { p.position = nil }
                if r.styles.isEmpty { p.style = nil }
                out[r.id] = p
            } else if let kept = layer[r.id] {
                out[r.id] = kept
            }
        }
        return out
    }

    /// A preset put on: each region it names takes its place, shown or hidden, and style, as far as the shell allows.
    public mutating func apply(_ preset: LayoutPreset) {
        var next = now
        for r in regions {
            guard let want = preset.placements[r.id], var p = next.placements[r.id] else { continue }
            if let position = want.position, r.positions.contains(position) { p.position = position }
            if let visible = want.visible, visible || !r.locked { p.visible = visible }
            if let style = want.style, r.styles.contains(style) { p.style = style }
            next.placements[r.id] = p
        }
        commit(next)
    }

    /// The placements as a preset, to keep or share.
    public func preset(named name: String) -> LayoutPreset { LayoutPreset(name: name, placements: now.placements) }

    /// Where the menu is for a style of it (the catalogue's `navStyles`), to start from when the placements don't say.
    public static func menuPosition(forStyle nav: String) -> String {
        switch nav {
        case "sidebar", "rail", "railDrawer", "tvSideMenu", "ornamentTabs": return "start"
        case "bottomTabs": return "bottom"
        default: return "top"
        }
    }

    /// Words for a screen reader after a move: "Menu moved to the left side.".
    public func announcement(_ id: String) -> String {
        guard let region = region(id) else { return "" }
        if !shown(id) { return "\(region.label) hidden." }
        guard let position = position(id) else { return "\(region.label) shown." }
        return "\(region.label) moved to \(LayoutWords.position(position, of: id))."
    }
}

/// How the layout editor says things.
public enum LayoutWords {
    public static func position(_ position: String, of region: String) -> String {
        switch (region, position) {
        case ("nav", "start"): return "the left side"
        case ("nav", "end"): return "the right side"
        case (_, "start"): return "the start"
        case (_, "end"): return "the end"
        case (_, "top"): return "the top"
        case (_, "bottom"): return "the bottom"
        case (_, "center"): return "the middle"
        case (_, "nav"): return "the menu"
        case (_, "floating"): return "a floating spot"
        case (_, "dock"): return "the Dock"
        case (_, "side"): return "the side"
        default: return position
        }
    }

    public static func title(_ position: String) -> String {
        switch position {
        case "nav": return "In the menu"
        case "top": return "Top"
        case "start": return "Start"
        case "end": return "End"
        case "bottom": return "Bottom"
        case "center": return "Middle"
        case "floating": return "Floating"
        case "dock": return "In the Dock"
        case "side": return "Side"
        default: return position.prefix(1).uppercased() + position.dropFirst()
        }
    }

    public static func style(_ style: String) -> String { style.prefix(1).uppercased() + style.dropFirst() }
}

/// A named layout a person keeps to put back, or to share as text.
public struct LayoutPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var placements: [String: SDUIShell.Placement]

    public init(name: String, placements: [String: SDUIShell.Placement]) {
        self.name = name
        self.placements = placements
    }

    /// The preset as text, for sharing.
    public func exported() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// A preset read from text, with only what the shell has: unknown regions and positions are refused in words.
    public static func imported(_ text: String, regions: [LayoutRegion]) throws -> LayoutPreset {
        guard let data = text.data(using: .utf8), let preset = try? JSONDecoder().decode(LayoutPreset.self, from: data),
              !preset.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw APIError(status: 400, message: "That isn't a layout preset.")
        }
        for (id, p) in preset.placements {
            guard let region = regions.first(where: { $0.id == id }) else { throw APIError(status: 400, message: "\"\(id)\" isn't a part of the layout.") }
            if let position = p.position, !region.positions.contains(position) {
                throw APIError(status: 400, message: "The \(region.label) can't be at \"\(position)\".")
            }
            if p.visible == false, region.locked { throw APIError(status: 400, message: "The \(region.label) can't be hidden.") }
        }
        return preset
    }
}

public extension WittyClient {
    /// The shell's regions and where each is, on this device.
    func layoutPlacements(device: SDUIDevice) async throws -> LayoutPlacementsAnswer {
        try JSONDecoder().decode(LayoutPlacementsAnswer.self, from: try await call("GET", "/sdui/placements?" + SDUIQuery.encode(device.query)))
    }

    /// Keeps this profile's own placements for this device, replacing its earlier ones.
    func saveLayoutPlacements(_ placements: [String: SDUIShell.Placement], device: SDUIDevice) async throws {
        struct Body: Encodable { let placements: [String: SDUIShell.Placement] }
        _ = try await call("PUT", "/sdui/placements?" + SDUIQuery.encode(device.query), body: try JSONEncoder().encode(Body(placements: placements)))
    }

    /// The name of the look in force on this device, for "Reset to Lumen".
    func layoutExperienceName(device: SDUIDevice) async -> String? {
        struct Answer: Decodable {
            struct Choice: Decodable {
                struct Option: Decodable { let value: String; let label: String }
                let current: String
                let options: [Option]
            }
            let choice: Choice
        }
        guard let data = try? await call("GET", "/sdui/experience?" + SDUIQuery.encode(device.query)),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        return answer.choice.options.first { $0.value == answer.choice.current }?.label
    }

    /// Back to the experience's (and the administrator's).
    func resetLayoutPlacements(device: SDUIDevice) async throws {
        _ = try await call("DELETE", "/sdui/placements?" + SDUIQuery.encode(device.query))
    }

    /// Administrators: the layer of placements the server keeps for an experience, for everyone, and the settings' tag.
    func layoutEveryone(experience: String) async throws -> (layer: [String: SDUIShell.Placement], whole: [String: JSONValue], etag: String) {
        let data = try await call("GET", "/sdui/config/experience")
        guard case .object(let top) = try JSONDecoder().decode(JSONValue.self, from: data),
              case .string(let etag)? = top["etag"] else { throw APIError(status: 0, message: "The server's layouts can't be read.") }
        var whole: [String: JSONValue] = [:]
        if case .object(let policy)? = top["experiences"] { whole = policy }
        var layer: [String: SDUIShell.Placement] = [:]
        if case .object(let byExperience)? = whole["placements"], let mine = byExperience[experience],
           let raw = try? JSONEncoder().encode(mine), let decoded = try? JSONDecoder().decode([String: SDUIShell.Placement].self, from: raw) {
            layer = decoded
        }
        return (layer, whole, etag)
    }

    /// Administrators: sets the placements of an experience for everyone; an empty layer takes them away.
    func saveLayoutEveryone(experience: String, layer: [String: SDUIShell.Placement], whole: [String: JSONValue], etag: String) async throws {
        var policy = whole
        var byExperience: [String: JSONValue] = [:]
        if case .object(let existing)? = policy["placements"] { byExperience = existing }
        if layer.isEmpty {
            byExperience[experience] = nil
        } else {
            byExperience[experience] = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(layer))
        }
        policy["placements"] = byExperience.isEmpty ? nil : .object(byExperience)
        _ = try await send("PUT", "/sdui/config/experience", body: try JSONEncoder().encode(JSONValue.object(policy)), headers: ["If-Match": etag])
    }
}
