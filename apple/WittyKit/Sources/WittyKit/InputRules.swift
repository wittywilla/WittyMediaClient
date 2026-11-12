// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The input model of docs/plans/DESIGN-2.md section 3, as pure rules the screens call: which key does what on a
// keyboard, a game pad and a TV remote (the table is the server's `input` tokens, so every client agrees), the zones
// a screen is made of, where Back goes, what a screen remembers when focus leaves it, and how the next thing to
// focus is chosen. Nothing here draws or reads a device; the tests are in InputRulesTests.

public enum InputDevice: String, CaseIterable, Sendable {
    case keyboard, gamepad, remote
}

/// What a press means, whichever key made it.
public enum InputAction: String, CaseIterable, Sendable {
    case move, select, back, options, search, tabPrev, tabNext, pageUp, pageDown, top, playPause, seek, dock, help
}

public enum KeyMap {
    /// The keys that make this action on this device, as the tokens spell them ("ArrowUp", "Ctrl+K", "LongOK", "A").
    public static func keys(_ device: InputDevice, _ action: InputAction) -> [String] {
        let table: [String: [String]]
        switch device {
        case .keyboard: table = DesignTokens.Input.keyboard
        case .gamepad: table = DesignTokens.Input.gamepad
        case .remote: table = DesignTokens.Input.remote
        }
        return table[action.rawValue] ?? []
    }

    /// Every action a key can mean on a device. Space is Select and Play/Pause, so a screen takes the one that fits
    /// (a player takes Play/Pause), and an unknown key is none.
    public static func actions(for key: String, on device: InputDevice) -> [InputAction] {
        InputAction.allCases.filter { keys(device, $0).contains(key) }
    }

    /// The action for a key on a screen that has the actions in `context`, in the order the screen prefers them.
    public static func action(for key: String, on device: InputDevice, preferring context: [InputAction]) -> InputAction? {
        let all = actions(for: key, on: device)
        return context.first(where: all.contains) ?? all.first
    }

    /// What to print for a key: "Period" is ".", "Ctrl+BracketLeft" is "Ctrl+[", "KeyK" is "K".
    public static func glyph(_ key: String) -> String {
        let table = ["Period": ".", "Slash": "/", "BracketLeft": "[", "BracketRight": "]", "Escape": "Esc", "ArrowUp": "\u{2191}",
                     "ArrowDown": "\u{2193}", "ArrowLeft": "\u{2190}", "ArrowRight": "\u{2192}", "PageUp": "Page Up", "PageDown": "Page Down",
                     "ContextMenu": "Menu key", "LongOK": "Hold OK", "HoldA": "Hold A", "HoldMenu": "Hold Menu", "DoubleUp": "Up twice",
                     "RightStickClick": "R3", "DPad": "D-pad", "LeftStick": "Left stick", "MediaRewind": "Rewind",
                     "MediaFastForward": "Fast forward", "PlayPause": "Play/Pause", "ChannelUp": "Ch +", "ChannelDown": "Ch -"]
        return key.split(separator: "+", omittingEmptySubsequences: false).map { part -> String in
            let p = String(part)
            if let g = table[p] { return g }
            if p.hasPrefix("Key"), p.count == 4 { return String(p.dropFirst(3)) }
            return p
        }.joined(separator: "+")
    }

    /// The first key of an action, printed: what the legend shows.
    public static func glyph(_ device: InputDevice, _ action: InputAction) -> String? {
        keys(device, action).first.map(glyph)
    }
}

// MARK: - Key legend

/// One entry of the legend in a Dock: a key and what it does here.
public struct LegendHint: Equatable, Identifiable, Sendable {
    public let action: InputAction
    public let glyph: String
    public let label: String
    public var id: String { action.rawValue }
}

public enum KeyLegend {
    /// What the legend shows for a screen kind. The same words everywhere, in the same order; options is always
    /// there, because a screen's options are always on one key (section 3).
    public enum Screen: Sendable { case shelves, grid, detail, guide, player }

    public static func hints(_ screen: Screen, device: InputDevice) -> [LegendHint] {
        let wanted: [(InputAction, String)]
        switch screen {
        case .shelves: wanted = [(.select, "Open"), (.options, "Options"), (.search, "Search"), (.back, "Back")]
        case .grid: wanted = [(.select, "Open"), (.options, "Sort and filter"), (.pageDown, "Page down"), (.top, "Top"), (.back, "Back")]
        case .detail: wanted = [(.select, "Choose"), (.options, "More"), (.back, "Back")]
        case .guide: wanted = [(.select, "Watch"), (.options, "Dock"), (.pageDown, "Page"), (.back, "Back")]
        case .player: wanted = [(.playPause, "Play or pause"), (.options, "Options"), (.back, "Back")]
        }
        return wanted.compactMap { action, label in
            KeyMap.glyph(device, action).map { LegendHint(action: action, glyph: $0, label: label) }
        }
    }

    /// Whether the legend shows at all: only when a pad or a remote is the thing in use. Touch, a pointer and a keyboard
    /// on a phone show nothing; a keyboard on a TV or a laptop shows it only when the person has asked for it.
    public static func visible(device: InputDevice?, touchInUse: Bool, askedFor: Bool) -> Bool {
        if touchInUse { return false }
        switch device {
        case .gamepad?, .remote?: return true
        case .keyboard?: return askedFor
        case nil: return false
        }
    }
}

// MARK: - Zones and Back

/// The four places focus can be on a screen (section 1.3).
public enum Zone: String, CaseIterable, Sendable {
    case bar, stage, dock, layer
}

public enum Direction: String, Sendable {
    case up, down, left, right
}

/// What Back does next (section 3: "Back unwinds Layer, then Dock, then Stage to Bar, then Bar to Home, then leaves").
public enum BackStep: Equatable, Sendable {
    case closeLayer, closeDock, focusBar, goHome, exit
}

/// Where a screen is, for the rules that move between its zones.
public struct ZoneState: Equatable, Sendable {
    public var zone: Zone
    /// A layer (dialog, menu, sheet, player) is open over it.
    public var layerOpen: Bool
    /// The screen has a Dock and it is showing.
    public var hasDock: Bool
    /// The Bar's current tab is Home.
    public var barOnHome: Bool

    public init(zone: Zone, layerOpen: Bool = false, hasDock: Bool = false, barOnHome: Bool = true) {
        self.zone = zone
        self.layerOpen = layerOpen
        self.hasDock = hasDock
        self.barOnHome = barOnHome
    }
}

public enum BackLadder {
    /// The next thing Back does. A layer closes first, then a Dock that has focus; from Stage, focus goes to the Bar's
    /// current tab; from the Bar a tab other than Home goes to Home; from Home the app is left (to the system).
    public static func next(_ s: ZoneState) -> BackStep {
        if s.layerOpen || s.zone == .layer { return .closeLayer }
        switch s.zone {
        case .dock: return .closeDock
        case .stage: return .focusBar
        case .bar: return s.barOnHome ? .exit : .goHome
        case .layer: return .closeLayer
        }
    }
}

public enum ZoneRules {
    /// Where one press of a direction takes focus when it has run out of room inside its zone (`atEdge`), or nil when it
    /// stays or goes nowhere: Up from the first row of Stage reaches the Bar; Down from the Bar goes back to Stage; Down
    /// from the last row of Stage reaches a Dock that is showing; Up from the Dock returns to Stage. A layer keeps focus
    /// to itself. Nothing wraps, except a Dock's own buttons, which the Dock handles.
    public static func leave(_ s: ZoneState, _ dir: Direction, atEdge: Bool) -> Zone? {
        guard atEdge, !s.layerOpen, s.zone != .layer else { return nil }
        switch (s.zone, dir) {
        case (.stage, .up): return .bar
        case (.bar, .down): return .stage
        case (.stage, .down): return s.hasDock ? .dock : nil
        case (.dock, .up): return .stage
        default: return nil
        }
    }

    /// The key that opens the Dock from anywhere in Stage: only where the screen has one.
    public static func opensDock(_ s: ZoneState) -> Bool { s.hasDock && s.zone != .dock && !s.layerOpen }
}

// MARK: - Focus memory

/// What a screen remembers so that coming back lands where the person was: per group (a shelf, a grid, the guide, the
/// Dock) the last thing focused, and per zone the place it left from. Entering a group from outside lands on the last
/// thing in it, or the first (`enterFromOutside` "last-or-first"); that a group is remembered at all follows
/// `rememberPerGroup`.
public struct FocusMemory<ID: Hashable>: Sendable where ID: Sendable {
    private var lastInGroup: [String: ID] = [:]
    private var lastInZone: [Zone: ID] = [:]
    public var perGroup: Bool

    public init(perGroup: Bool = DesignTokens.Nav.rememberPerGroup) {
        self.perGroup = perGroup
    }

    public mutating func focused(_ id: ID, group: String, zone: Zone) {
        if perGroup { lastInGroup[group] = id }
        lastInZone[zone] = id
    }

    /// Where focus lands entering a group: the last thing in it if it's still there, else the first.
    public func enter(group: String, among ids: [ID]) -> ID? {
        if perGroup, let last = lastInGroup[group], ids.contains(last) { return last }
        return ids.first
    }

    /// Where focus returns to in a zone: the thing it left from, if it's still there; else `fallback`.
    public func returnTo(zone: Zone, among ids: [ID], fallback: ID? = nil) -> ID? {
        if let last = lastInZone[zone], ids.contains(last) { return last }
        return fallback ?? ids.first
    }

    /// Forget a group (its content changed under it).
    public mutating func forget(group: String) { lastInGroup[group] = nil }

    public mutating func reset() { lastInGroup = [:]; lastInZone = [:] }
}

// MARK: - Spatial scoring

public struct FocusBox: Equatable, Sendable {
    public var left, top, right, bottom: Double
    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(left: x, top: y, right: x + width, bottom: y + height)
    }
    public var centre: (x: Double, y: Double) { ((left + right) / 2, (top + bottom) / 2) }
}

/// Which control is next in a direction: the port of the web's spatial.ts, with its weights from the `nav.weights`
/// tokens so the two cannot drift.
public enum Spatial {
    private static func offLine(_ d: Direction) -> Double {
        switch d {
        case .left: return DesignTokens.Nav.Weights.OffLine.left
        case .right: return DesignTokens.Nav.Weights.OffLine.right
        case .up: return DesignTokens.Nav.Weights.OffLine.up
        case .down: return DesignTokens.Nav.Weights.OffLine.down
        }
    }
    private static func offCentre(_ d: Direction) -> Double {
        switch d {
        case .left: return DesignTokens.Nav.Weights.OffCentre.left
        case .right: return DesignTokens.Nav.Weights.OffCentre.right
        case .up: return DesignTokens.Nav.Weights.OffCentre.up
        case .down: return DesignTokens.Nav.Weights.OffCentre.down
        }
    }
    private static func leavesLine(_ d: Direction) -> Double {
        switch d {
        case .left: return DesignTokens.Nav.Weights.LeavesLine.left
        case .right: return DesignTokens.Nav.Weights.LeavesLine.right
        case .up: return DesignTokens.Nav.Weights.LeavesLine.up
        case .down: return DesignTokens.Nav.Weights.LeavesLine.down
        }
    }

    /// How far `b` is from `a` going `dir`, smaller being better; nil when `b` isn't that way at all.
    public static func score(_ a: FocusBox, _ b: FocusBox, _ dir: Direction) -> Double? {
        let (ax, ay) = a.centre, (bx, by) = b.centre
        func off(_ p: Double, _ lo: Double, _ hi: Double) -> Double { p < lo ? lo - p : (p > hi ? p - hi : 0) }
        let gap, near, far, bNear, bFar, centre: Double
        switch dir {
        case .right:
            guard bx > ax + 1 else { return nil }
            gap = b.left - a.right; near = a.top; far = a.bottom; bNear = b.top; bFar = b.bottom; centre = off(ay, b.top, b.bottom)
        case .left:
            guard bx < ax - 1 else { return nil }
            gap = a.left - b.right; near = a.top; far = a.bottom; bNear = b.top; bFar = b.bottom; centre = off(ay, b.top, b.bottom)
        case .down:
            guard by > ay + 1 else { return nil }
            gap = b.top - a.bottom; near = a.left; far = a.right; bNear = b.left; bFar = b.right; centre = off(ax, b.left, b.right)
        case .up:
            guard by < ay - 1 else { return nil }
            gap = a.top - b.bottom; near = a.left; far = a.right; bNear = b.left; bFar = b.right; centre = off(ax, b.left, b.right)
        }
        let aside = max(0, max(near, bNear) - min(far, bFar))
        return max(0, gap) + aside * offLine(dir) + (aside > 0 ? leavesLine(dir) : 0) + centre * offCentre(dir)
    }

    /// Every candidate that way, best first.
    public static func ranked<T>(from: FocusBox, _ candidates: [T], box: (T) -> FocusBox, _ dir: Direction) -> [T] {
        candidates.compactMap { c in score(from, box(c), dir).map { ($0, c) } }
            .sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The closest candidate to a place in any direction: for when what had focus has gone.
    public static func nearest<T>(from: FocusBox, _ candidates: [T], box: (T) -> FocusBox) -> T? {
        let (ax, ay) = from.centre
        return candidates.min { l, r in
            let (lx, ly) = box(l).centre, (rx, ry) = box(r).centre
            return hypot(lx - ax, ly - ay) < hypot(rx - ax, ry - ay)
        }
    }
}

// MARK: - Paging

public enum Paging {
    /// Where a Page Up or Page Down lands in a list of `count` rows from row `index`, `page` rows at a time. It stops at
    /// the ends: nothing wraps.
    public static func row(from index: Int, count: Int, page: Int, forward: Bool) -> Int {
        guard count > 0 else { return 0 }
        let step = max(1, page)
        return max(0, min(count - 1, forward ? index + step : index - step))
    }

    /// The guide's time window moving past an edge: by half of what it shows (section 4, WittyTV).
    public static func timeShift(window: TimeInterval) -> TimeInterval { window / 2 }

    /// The channel page sizes the Channels button offers; 0 is All.
    public static let channelPageSizes = [25, 50, 75, 100, 0]
}

// MARK: - Density

public enum Density: String, CaseIterable, Sendable {
    case compact, comfortable, spacious

    public var space: Double {
        switch self {
        case .compact: return DesignTokens.Density.Steps.Compact.space
        case .comfortable: return DesignTokens.Density.Steps.Comfortable.space
        case .spacious: return DesignTokens.Density.Steps.Spacious.space
        }
    }

    public var control: Double {
        switch self {
        case .compact: return DesignTokens.Density.Steps.Compact.control
        case .comfortable: return DesignTokens.Density.Steps.Comfortable.control
        case .spacious: return DesignTokens.Density.Steps.Spacious.control
        }
    }

    /// A profile's choice, as the server stores it; anything else is the default for the device.
    public static func from(_ text: String?, tv: Bool) -> Density {
        if let text, let d = Density(rawValue: text) { return d }
        return Density(rawValue: tv ? DesignTokens.Density.tvDefault : DesignTokens.Density.default) ?? .comfortable
    }
}

// MARK: - Jump to a letter

/// The Dock's "Jump": a long list sorted by title, to the first title at or after a letter. "#" stands for every title
/// that doesn't start with a letter (digits, symbols) and comes first. Nothing here loads anything: a screen asks for
/// more pages while `firstIndex` still says nil and there is more to load.
public enum LetterJump {
    public static let letters: [String] = ["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }

    /// The bucket a title sorts under: its first letter or digit, without accents or case; "#" for anything else.
    public static func key(_ title: String) -> String {
        let folded = title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard let first = folded.first(where: { $0.isLetter || $0.isNumber }) else { return "#" }
        let up = String(first).uppercased()
        return up.count == 1 && up >= "A" && up <= "Z" ? up : "#"
    }

    /// The first title (by position) whose bucket is `letter` or later; nil if there is none among these.
    public static func firstIndex(titles: [String], letter: String) -> Int? {
        titles.firstIndex { key($0) >= letter }
    }

    /// Whether a list in this order can be jumped by letter: the sort is by title.
    public static func applies(sort: String, firstSort: String?) -> Bool {
        sort == "title" || (sort.isEmpty && firstSort == "title")
    }
}
