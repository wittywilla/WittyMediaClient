// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// What the server sends for a server-driven page: the server's docs/SDUI.md, "The rendered document".
// Every type here reads what it knows and ignores the rest, so a newer server's additions do no harm.

/// The catalogue revision this app was built against. Sent with every request (`catalog=6`), so a newer
/// server sends nothing this app can't draw.
public enum SDUI {
    public static let catalog = 8
    public static let version = 1
    /// The features in `/capabilities` that the app's server-driven pages need, all of them.
    public static let neededFeatures: Set<String> = ["sdui-pages", "sdui-catalog", "sdui-navigation", "sdui-personal"]
    public static let topShelfFeature = "sdui-topshelf"

    /// Whether a server with these features has server-driven pages for this app.
    public static func available(_ features: Set<String>) -> Bool { neededFeatures.isSubset(of: features) }

    /// A document this app can draw: written for its own catalogue revision (docs/SDUI.md: a client built for another
    /// revision refuses it). A document that names none is from before revisions were checked.
    public static func accepts(_ document: SDUIDocument) -> Bool { document.catalog == nil || document.catalog == catalog }
}

/// A page rendered for one profile on one device.
public struct SDUIDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var catalog: Int?
    public var page: SDUIPageInfo
    public var layout: SDUILayout
    public var theme: SDUIThemeScope?
    public var root: SDUINode
    public var screenTime: SDUIScreenTime?
    public var personal: SDUIPersonalInfo?
    public var meta: SDUIMeta?
    /// What the page puts in the shell's own regions: a status bar and a round system dock (WittyPlay's frame).
    public var regions: SDUIRegions?

    enum CodingKeys: String, CodingKey { case version, catalog, page, layout, theme, root, screenTime, personal, meta, regions }

    public init(version: Int = SDUI.version, catalog: Int? = SDUI.catalog, page: SDUIPageInfo, layout: SDUILayout,
                theme: SDUIThemeScope? = nil, root: SDUINode, screenTime: SDUIScreenTime? = nil,
                personal: SDUIPersonalInfo? = nil, meta: SDUIMeta? = nil, regions: SDUIRegions? = nil) {
        self.version = version
        self.catalog = catalog
        self.page = page
        self.layout = layout
        self.theme = theme
        self.root = root
        self.screenTime = screenTime
        self.personal = personal
        self.meta = meta
        self.regions = regions
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        version = try box.decodeIfPresent(Int.self, forKey: .version) ?? 0
        // A version this app doesn't know is refused: the one thing a client must not try to draw.
        guard version == SDUI.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: box, debugDescription: "This page needs a newer app.")
        }
        catalog = try? box.decodeIfPresent(Int.self, forKey: .catalog)
        page = (try? box.decodeIfPresent(SDUIPageInfo.self, forKey: .page)) ?? SDUIPageInfo()
        layout = (try? box.decodeIfPresent(SDUILayout.self, forKey: .layout)) ?? SDUILayout.fallback
        theme = try? box.decodeIfPresent(SDUIThemeScope.self, forKey: .theme)
        root = try box.decode(SDUINode.self, forKey: .root)
        screenTime = try? box.decodeIfPresent(SDUIScreenTime.self, forKey: .screenTime)
        personal = try? box.decodeIfPresent(SDUIPersonalInfo.self, forKey: .personal)
        meta = try? box.decodeIfPresent(SDUIMeta.self, forKey: .meta)
        regions = try? box.decodeIfPresent(SDUIRegions.self, forKey: .regions)
    }
}

/// A page's content for the shell's optional regions (docs/SDUI.md, document.regions, catalogue revision 7): a status
/// bar's profile, server and text, and a round system dock of the screen's destinations. A page with either is drawn in
/// that frame, over the whole screen: WittyPlay Online's, as the website's PlayChrome draws it.
public struct SDUIRegions: Codable, Equatable, Sendable {
    public struct Status: Codable, Equatable, Sendable {
        public var id: String
        /// `profile` (the profile's name, `text` under it), `server` (the server's name, as its brand) or `text`.
        public var kind: String
        public var text: String?
        public init(id: String, kind: String, text: String? = nil) { self.id = id; self.kind = kind; self.text = text }
    }

    public struct Dock: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var icon: String?
        /// Where it goes, as a website address; `/page/x?tab=y` opens a tab of a page.
        public var route: String
        /// `layer`: it opens over the page rather than in place of it.
        public var `as`: String?
        /// The page says this is where it is, on a page none of the dock's buttons opens (WittyPlay's store, under Settings).
        public var current: Bool?
        public init(id: String, label: String, icon: String? = nil, route: String, as: String? = nil, current: Bool? = nil) {
            self.id = id; self.label = label; self.icon = icon; self.route = route; self.as = `as`; self.current = current
        }
    }

    public var statusBar: [Status]
    public var systemDock: [Dock]

    public init(statusBar: [Status] = [], systemDock: [Dock] = []) { self.statusBar = statusBar; self.systemDock = systemDock }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        statusBar = (try? box.decodeIfPresent([Status].self, forKey: .statusBar)) ?? []
        systemDock = (try? box.decodeIfPresent([Dock].self, forKey: .systemDock)) ?? []
    }

    /// Nothing in either region: no frame.
    public var isEmpty: Bool { statusBar.isEmpty && systemDock.isEmpty }

    /// The dock with Home first, as the website's (playPaths.ts dockFor): a dock without one gets WittyPlay's home.
    public var dock: [Dock] {
        guard !systemDock.isEmpty, !systemDock.contains(where: { $0.id == "home" || $0.route == WittyPlayPlace.home }) else { return systemDock }
        return [Dock(id: "home", label: "Home", icon: "home", route: WittyPlayPlace.home)] + systemDock
    }

    /// Which dock entry is where the page is (regions.ts dockCurrent): one asking for a query wins on its own page with
    /// that query; else one whose route is the page or a parent of it.
    public func current(path: String, query: [String: String] = [:]) -> Int? {
        let entries = dock
        if let marked = entries.firstIndex(where: { $0.current == true }) { return marked }
        if let exact = entries.firstIndex(where: { entry in
            let parts = entry.route.split(separator: "?", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == path else { return false }
            return parts[1].split(separator: "&").allSatisfy { pair in
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 && query[kv[0]] == kv[1]
            }
        }) { return exact }
        return entries.firstIndex { !$0.route.contains("?") && (path == $0.route || path.hasPrefix($0.route + "/")) }
    }
}

public struct SDUIPageInfo: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var icon: String?
    public var route: String?
    public var variant: String?
    /// What the page was opened with, to send again with a refresh.
    public var params: [String: String]?

    public init(id: String = "", kind: String = "", title: String = "", icon: String? = nil, route: String? = nil,
                variant: String? = nil, params: [String: String]? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.icon = icon
        self.route = route
        self.variant = variant
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case id, kind, title, icon, route, variant, params }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? box.decodeIfPresent(String.self, forKey: .id)) ?? ""
        kind = (try? box.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        title = (try? box.decodeIfPresent(String.self, forKey: .title)) ?? ""
        icon = try? box.decodeIfPresent(String.self, forKey: .icon)
        route = try? box.decodeIfPresent(String.self, forKey: .route)
        variant = try? box.decodeIfPresent(String.self, forKey: .variant)
        // Parameters are text, but a number would do no harm.
        if let loose = try? box.decodeIfPresent([String: JSONValue].self, forKey: .params) {
            var out: [String: String] = [:]
            for (key, value) in loose {
                if let text = value.string { out[key] = text } else if let n = value.int { out[key] = String(n) }
            }
            params = out
        }
    }
}

public struct SDUIThemeScope: Codable, Equatable, Sendable {
    public var scope: String?
    public var tokens: [String: String]?
    public init(scope: String? = nil, tokens: [String: String]? = nil) {
        self.scope = scope
        self.tokens = tokens
    }
}

/// Present when the profile's screen time is over: pages still draw, nothing in them plays.
public struct SDUIScreenTime: Codable, Equatable, Sendable {
    public var reason: String?
    public var message: String?
    /// When there is time again, in Unix seconds.
    public var nextAt: Int64?
}

public struct SDUIMeta: Codable, Equatable, Sendable {
    public var etag: String?
    public var generatedAt: String?
    public var source: String?
    public var configRevision: Int?
    public var ttlSeconds: Int?
    /// Something on the page is in progress (a library scanning): ask for it again this many seconds after the last
    /// answer, while it's open and showing. Absent or 0: don't.
    public var refreshSec: Int?

    /// `refreshSec` as the app follows it: 0 for none, at most 300.
    public var refreshAfter: Int { min(max(refreshSec ?? 0, 0), 300) }
}

/// What the profile may change about a page, and what it has changed.
public struct SDUIPersonalInfo: Codable, Equatable, Sendable {
    public struct Section: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String?
        public var hidden: Bool?
        public var pinned: Bool?
        public var locked: Bool?
        /// Nothing in it now, so it isn't on the page.
        public var empty: Bool?

        public init(id: String, title: String? = nil, hidden: Bool? = nil, pinned: Bool? = nil, locked: Bool? = nil,
                    empty: Bool? = nil) {
            self.id = id
            self.title = title
            self.hidden = hidden
            self.pinned = pinned
            self.locked = locked
            self.empty = empty
        }
    }

    public var editable: Bool?
    public var allow: [String]?
    public var sections: [Section]?
    public var density: String?
    public var url: String?

    public init(editable: Bool? = nil, allow: [String]? = nil, sections: [Section]? = nil, density: String? = nil, url: String? = nil) {
        self.editable = editable
        self.allow = allow
        self.sections = sections
        self.density = density
        self.url = url
    }
}

public struct SDUIFocus: Codable, Equatable, Hashable, Sendable {
    public var order: Int
    public var group: String?
    public var isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case order, group
        case isDefault = "default"
    }

    public init(order: Int, group: String? = nil, isDefault: Bool? = nil) {
        self.order = order
        self.group = group
        self.isDefault = isDefault
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? box.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        group = try? box.decodeIfPresent(String.self, forKey: .group)
        isDefault = try? box.decodeIfPresent(Bool.self, forKey: .isDefault)
    }
}

/// What activating a node does. A type this app doesn't know does nothing.
public struct SDUIAction: Codable, Equatable, Hashable, Sendable {
    public var type: String
    public var to: String?
    public var item: String?
    public var url: String?
    public var op: String?
    public var params: SDUIProps?
    /// A question to ask before a command runs ("Read every file of Movies again?"); nothing runs without a yes.
    public var confirm: String?

    public init(type: String, to: String? = nil, item: String? = nil, url: String? = nil, op: String? = nil, params: SDUIProps? = nil,
                confirm: String? = nil) {
        self.type = type
        self.to = to
        self.item = item
        self.url = url
        self.op = op
        self.params = params
        self.confirm = confirm
    }

    enum CodingKeys: String, CodingKey { case type, to, item, url, op, params, confirm }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? box.decodeIfPresent(String.self, forKey: .type)) ?? ""
        to = try? box.decodeIfPresent(String.self, forKey: .to)
        // An item's ID is text, but a number is read too.
        if let text = try? box.decodeIfPresent(String.self, forKey: .item) {
            item = text
        } else if let n = try? box.decodeIfPresent(Int64.self, forKey: .item) {
            item = String(n)
        }
        url = try? box.decodeIfPresent(String.self, forKey: .url)
        op = try? box.decodeIfPresent(String.self, forKey: .op)
        params = try? box.decodeIfPresent(SDUIProps.self, forKey: .params)
        let question = (try? box.decodeIfPresent(String.self, forKey: .confirm))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        confirm = question.isEmpty ? nil : String(question.prefix(240))
    }
}

/// One component of a page. `type` is whatever the server sent: one this app doesn't know is drawn as a
/// plain column of its children.
public struct SDUINode: Codable, Equatable, Identifiable, Sendable {
    public var type: String
    public var id: String
    public var props: SDUIProps?
    public var children: [SDUINode]?
    public var action: SDUIAction?
    public var focus: SDUIFocus?
    public var state: String?
    public var scope: String?
    public var tokens: [String: String]?

    public init(type: String, id: String, props: SDUIProps? = nil, children: [SDUINode]? = nil, action: SDUIAction? = nil,
                focus: SDUIFocus? = nil, state: String? = nil, scope: String? = nil, tokens: [String: String]? = nil) {
        self.type = type
        self.id = id
        self.props = props
        self.children = children
        self.action = action
        self.focus = focus
        self.state = state
        self.scope = scope
        self.tokens = tokens
    }

    enum CodingKeys: String, CodingKey { case type, id, props, children, action, focus, state, scope, tokens }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? box.decodeIfPresent(String.self, forKey: .type)) ?? ""
        id = (try? box.decodeIfPresent(String.self, forKey: .id)) ?? ""
        props = try? box.decodeIfPresent(SDUIProps.self, forKey: .props)
        // A child that can't be read at all is left out; the rest of the page still draws.
        if let loose = try? box.decodeIfPresent([Loose<SDUINode>].self, forKey: .children) {
            children = loose.compactMap(\.value)
        }
        action = try? box.decodeIfPresent(SDUIAction.self, forKey: .action)
        focus = try? box.decodeIfPresent(SDUIFocus.self, forKey: .focus)
        state = try? box.decodeIfPresent(String.self, forKey: .state)
        scope = try? box.decodeIfPresent(String.self, forKey: .scope)
        tokens = try? box.decodeIfPresent([String: String].self, forKey: .tokens)
    }

    public var kids: [SDUINode] { children ?? [] }
    public var properties: SDUIProps { props ?? [:] }
}

/// Something in a list that may not be readable: the list keeps the ones that are.
struct Loose<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// A page of a section's items: the answer to `props.more.url`, a season's own address, or a deferred section's.
public struct SDUISectionItems: Codable, Equatable, Sendable {
    public var version: Int?
    public var section: String?
    public var items: [SDUINode]?
    public var next: String?
    /// The items take the place of the ones there (another season).
    public var replace: Bool?
    /// On a first page: the section's own props as they are now.
    public var props: SDUIProps?
    public var state: String?
}

/// One entry of the main menu.
public struct SDUINavItem: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var icon: String?
    /// `page` or `native`. Anything else is opened by its route.
    public var kind: String
    public var page: String?
    public var params: [String: String]?
    public var screen: String?
    public var route: String?
    /// `primary`, `more` or `end`.
    public var placement: String?
    /// The second column a library opens beside a rail that has a drawer: its name, icon and count, and the views it offers.
    public var drawer: SDUINavDrawer?

    public init(id: String, label: String, icon: String? = nil, kind: String, page: String? = nil, params: [String: String]? = nil,
                screen: String? = nil, route: String? = nil, placement: String? = nil, drawer: SDUINavDrawer? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.kind = kind
        self.page = page
        self.params = params
        self.screen = screen
        self.route = route
        self.placement = placement
        self.drawer = drawer
    }

    public var isSettings: Bool { kind == "native" && screen == "settings" }
}

/// A library's drawer beside the rail: headed by its name, icon and item count, listing its views (each opens as the library's page
/// with its parameters).
public struct SDUINavDrawer: Codable, Equatable, Hashable, Sendable {
    public struct View: Codable, Equatable, Hashable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var icon: String?
        public var params: [String: String]?
        public var route: String?
    }

    public var title: String
    public var icon: String?
    public var count: Int?
    public var views: [View]
}

public struct SDUINavigation: Codable, Equatable, Sendable {
    public var version: Int?
    public var formFactor: String?
    public var etag: String?
    public var items: [SDUINavItem]
    /// For a profile that may rearrange the menu: every entry it could have, in its order, hidden ones included.
    public var personal: SDUIPersonalInfo?
    /// The frame the app draws around its pages: the layout option in force and its menu.
    public var shell: SDUIShell?

    public init(items: [SDUINavItem], formFactor: String? = nil, etag: String? = nil, personal: SDUIPersonalInfo? = nil,
                shell: SDUIShell? = nil) {
        self.version = SDUI.version
        self.items = items
        self.formFactor = formFactor
        self.etag = etag
        self.personal = personal
        self.shell = shell
    }

    enum CodingKeys: String, CodingKey { case version, formFactor, etag, items, personal, shell }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        version = try? box.decodeIfPresent(Int.self, forKey: .version)
        formFactor = try? box.decodeIfPresent(String.self, forKey: .formFactor)
        etag = try? box.decodeIfPresent(String.self, forKey: .etag)
        items = ((try? box.decodeIfPresent([Loose<SDUINavItem>].self, forKey: .items)) ?? []).compactMap(\.value)
        personal = try? box.decodeIfPresent(SDUIPersonalInfo.self, forKey: .personal)
        shell = try? box.decodeIfPresent(SDUIShell.self, forKey: .shell)
    }

    public func placed(_ placement: String) -> [SDUINavItem] { items.filter { ($0.placement ?? "primary") == placement } }
}

/// A picture as a page names it: the address already carries the width to ask for.
public struct SDUIImageRef: Equatable, Hashable, Sendable {
    public var url: String
    public var width: Int
    public var height: Int
    public var aspect: String
    public var kind: String

    public init?(_ value: JSONValue?) {
        guard let fields = value?.object, let url = fields["url"]?.string, !url.isEmpty else { return nil }
        self.url = url
        width = fields.whole("width") ?? 0
        height = fields.whole("height") ?? 0
        aspect = fields.text("aspect")
        kind = fields.text("kind")
    }

    /// Width over height, from `aspect` ("16/9") or the two sizes. 1 when neither says.
    public var ratio: Double { SDUILayout.ratio(aspect) ?? (width > 0 && height > 0 ? Double(width) / Double(height) : 1) }
}

