// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// A section's state: the server's docs/SDUI.md, "States". One this app doesn't know is ready.
public enum SDUIState: String, Equatable, Sendable {
    case ready = "", deferred, empty, error

    public init(_ text: String?) { self = SDUIState(rawValue: text ?? "") ?? .ready }
}

/// A button of a hero's slide or a title's header.
public struct SDUIButtonModel: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var icon: String
    public var primary: Bool
    public var action: SDUIAction?
}

/// One choice of a filter, a sort or a season.
public struct SDUIOption: Equatable, Identifiable, Sendable {
    public var value: String
    public var label: String
    public var id: String { value }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

/// One control of a `FilterBar`: the sort, or a filter with what's chosen now ("" for any).
public struct SDUIFilterField: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var value: String
    public var options: [SDUIOption]
    /// What the control says: "Genre: Any", "Sort: Title".
    public var summary: String
}

public struct SDUISeason: Equatable, Identifiable, Sendable {
    public var number: Int
    public var title: String
    public var selected: Bool
    public var url: String
    public var count: Int?
    public var unwatched: Int?
    public var id: Int { number }
}

/// What is on a channel now or next.
public struct SDUIProgramme: Equatable, Sendable {
    public var title: String
    public var start: Int64?
    public var end: Int64?
}

/// One component as this app draws it: everything a view needs, already worked out from the node and the
/// page's layout. The views are thin: they draw exactly what is here, and the conformance tests describe a
/// page from these same values, so what is tested is what is drawn.
public struct SDUIElement: Equatable, Identifiable, Sendable {
    public var id: String
    /// The component it is drawn as. A type this app doesn't know is drawn as a `Stack`: a plain column of its children.
    public var type: String
    public var depth: Int
    public var props: SDUIProps
    public var action: SDUIAction?
    public var focus: SDUIFocus?
    public var state: SDUIState
    /// The state as the server wrote it, for the description.
    public var stateName: String
    public var scope: String
    public var tokens: [String: String]
    public var children: [SDUIElement]
    /// The type the server sent when this app doesn't know it (and draws it as a `Stack`); empty otherwise.
    public var unknownType = ""

    // What assistive technology is told.
    public var role = "none"
    public var label = ""

    // What is drawn.
    /// The text shown, by part. Only parts that are drawn.
    public var text: [String: String] = [:]
    /// The most lines a part may take before it's cut with an ellipsis.
    public var lines: [String: Int] = [:]
    /// The size in points of the element's main text at the default text size.
    public var textSize = 0
    public var cards: Int?
    public var placeholders = 0
    public var cardStyle = ""
    public var cardWidth = 0
    public var cardHeight = 0
    public var columns = 0
    public var hasMore = false
    public var seeAll = ""
    /// The picture asked for, and the icon drawn when there is none.
    public var picture: SDUIImageRef?
    public var poster: SDUIImageRef?
    public var icon = ""
    /// A card's drawn parts, in reading order.
    public var shows: [String] = []
    /// A progress bar's fill, in whole percent.
    public var progress: Int?
    public var buttons: [SDUIButtonModel] = []
    public var filters: [SDUIFilterField] = []
    public var seasons: [SDUISeason] = []
    public var facts: [String] = []

    public func shown(_ part: String) -> String { text[part] ?? "" }
    public func lineLimit(_ part: String) -> Int? { lines[part] }
    public var title: String { props.text("title") }
    public var moreURL: String { props.fields("more")?.text("url") ?? "" }
    public var shape: String { props.text("shape") }
    public var now: SDUIProgramme? { SDUIElement.programme(props["now"]) }
    public var next: SDUIProgramme? { SDUIElement.programme(props["next"]) }
    public var badges: [String] { props.items("badges").compactMap(\.string) }
    public var isFocusable: Bool { focus != nil }

    static func programme(_ value: JSONValue?) -> SDUIProgramme? {
        guard let fields = value?.object else { return nil }
        return SDUIProgramme(title: fields.text("title"), start: fields["start"]?.double.map { Int64($0) }, end: fields["end"]?.double.map { Int64($0) })
    }

    /// Every element under this one, itself first, depth first in display order.
    public var flattened: [SDUIElement] { [self] + children.flatMap(\.flattened) }

    public func find(_ id: String) -> SDUIElement? {
        if self.id == id { return self }
        for child in children { if let found = child.find(id) { return found } }
        return nil
    }
}

/// A page as this app draws it: the document's tree as elements, the frame they're laid out in, and the focus plan.
public struct SDUIScreen: Equatable, Sendable {
    public let document: SDUIDocument
    public let root: SDUIElement
    public let focus: SDUIFocusPlan
    public var layout: SDUILayout { document.layout }
    public var title: String { document.page.title }
    /// The page's top-level sections.
    public var sections: [SDUIElement] { root.children }
    /// The node types on this page that this app doesn't know, and draws as plain columns.
    public var unknownTypes: Set<String> { Set(root.flattened.map(\.unknownType).filter { !$0.isEmpty }) }

    /// `window` is the window's real width in points, where the app knows it: placeholders and columns follow it.
    public init(document: SDUIDocument, catalog: SDUICatalog = .builtIn, window: Int? = nil) {
        self.document = document
        let builder = Builder(layout: document.layout, catalog: catalog, page: document.page.title, window: window)
        root = builder.element(document.root, depth: 0, parent: nil)
        focus = SDUIFocusPlan(root: document.root)
    }

    struct Builder {
        let layout: SDUILayout
        let catalog: SDUICatalog
        let page: String
        let window: Int?

        func element(_ node: SDUINode, depth: Int, parent: SDUINode?) -> SDUIElement {
            let p = node.properties
            var e = SDUIElement(id: node.id, type: node.type, depth: depth, props: p, action: node.action, focus: node.focus,
                                state: SDUIState(node.state), stateName: node.state ?? "", scope: node.scope ?? "",
                                tokens: node.tokens ?? [:], children: [])
            e.children = node.kids.map { element($0, depth: depth + 1, parent: node) }
            func text(_ part: String, _ value: String) { if !value.isEmpty { e.text[part] = value } }
            func lines(_ part: String, _ count: Int) { if count > 0 { e.lines[part] = count } }
            func collection() {
                e.cards = node.kids.count
                if let card = p.fields("card") {
                    e.cardStyle = p.text("cardStyle")
                    e.cardWidth = card.whole("width") ?? 0
                    e.cardHeight = card.whole("height") ?? 0
                    if e.state == .deferred { e.placeholders = layout.placeholders(cardWidth: e.cardWidth, window: window) }
                }
                if let sent = p.whole("columns") { e.columns = layout.gridColumns(cardWidth: e.cardWidth, sent: sent, window: window) }
                e.hasMore = p.fields("more") != nil && e.state != .deferred && e.state != .error
                e.seeAll = p.fields("seeAll")?.text("route") ?? ""
                text("title", p.text("title"))
                text("subtitle", p.text("subtitle"))
                text("empty", p.text("emptyText"))
                lines("title", 1)
                e.textSize = layout.textSize("title")
            }
            switch node.type {
            case "Page":
                e.role = "main"
                e.label = p.text("title")
            case "Shelf":
                collection()
                e.role = "list"
                e.label = p.text("title")
            case "Grid":
                collection()
                // A grid is a list to a screen reader on touch devices.
                e.role = layout.focusEngine || layout.formFactor == "desktop" || layout.formFactor == "web" ? "grid" : "list"
                e.label = p.text("title").isEmpty ? page : p.text("title")
            case "List":
                e.cards = node.kids.count
                e.role = "list"
                e.label = p.text("title")
                text("title", p.text("title"))
                text("empty", p.text("emptyText"))
                e.hasMore = p.fields("more") != nil
            case "Card":
                card(&e, parent: parent)
            case "Hero":
                e.role = "region"
                e.label = p.text("title").isEmpty ? "Featured" : p.text("title")
                e.cards = node.kids.count
                if let size = p.fields("size") {
                    e.cardWidth = size.whole("width") ?? 0
                    e.cardHeight = size.whole("height") ?? 0
                }
                if let seconds = p.whole("autoAdvanceSec") { text("autoAdvance", "\(seconds) s") }
            case "Tabs":
                e.role = "tablist"
                e.cards = node.kids.count
            case "Tab":
                e.role = "tab"
                e.label = p.text("label") + (p.flag("selected") == true ? ", selected" : "")
                text("title", p.text("label"))
                lines("title", 1)
            case "FilterBar":
                e.role = "toolbar"
                e.label = "Filter and sort"
                if let sort = p.fields("sort") {
                    let options = Builder.options(sort)
                    let value = sort.text("value")
                    let chosen = options.first { $0.value == value }?.label ?? ""
                    e.filters.append(SDUIFilterField(id: "sort", label: "Sort", value: value, options: options, summary: "Sort: " + chosen))
                }
                for field in p.items("fields").compactMap(\.object) {
                    let options = Builder.options(field)
                    let value = field.text("value")
                    let chosen = options.first { $0.value == value }?.label ?? ""
                    e.filters.append(SDUIFilterField(id: field.text("id"), label: field.text("label"), value: value, options: options,
                                                     summary: field.text("label") + ": " + (chosen.isEmpty ? "Any" : chosen)))
                }
                if let count = p.whole("count") { text("count", "\(count) titles") }
            case "DetailHeader":
                e.role = "region"
                e.label = p.text("title")
                text("title", p.text("title"))
                text("tagline", p.text("tagline"))
                e.facts = Builder.facts(p)
                text("facts", e.facts.joined(separator: " · "))
                text("overview", p.text("overview"))
                lines("title", 2)
                lines("overview", 4)
                e.textSize = layout.textSize("pageTitle")
                e.buttons = Builder.buttons(p)
                e.progress = Builder.percent(p)
                if let images = p.fields("images") {
                    e.picture = SDUIImageRef(images["backdrop"])
                    e.poster = SDUIImageRef(images["poster"])
                }
            case "SeasonList":
                e.role = "region"
                e.label = "Episodes"
                e.cards = node.kids.count
                e.seasons = p.items("seasons").compactMap(\.object).map {
                    SDUISeason(number: $0.whole("number") ?? 0, title: $0.text("title"), selected: $0.flag("selected") == true,
                               url: $0.text("url"), count: $0.whole("count"), unwatched: $0.whole("unwatched"))
                }
                e.hasMore = p.fields("more") != nil
                if let card = p.fields("card") {
                    e.cardStyle = "episode"
                    e.cardWidth = card.whole("width") ?? 0
                    e.cardHeight = card.whole("height") ?? 0
                }
            case "TrackList":
                e.role = "list"
                e.label = "Tracks"
                e.cards = node.kids.count
            case "Track":
                e.role = "button"
                let from = parent?.properties ?? [:]
                var parts: [String] = []
                if let number = p.whole("number"), from.flag("showNumbers") != false {
                    parts.append("Track \(number)")
                }
                parts.append(p.text("title"))
                text("title", p.text("title"))
                lines("title", 1)
                if from.flag("showArtist") == true {
                    parts.append(p.text("artist"))
                    text("subtitle", p.text("artist"))
                }
                if let seconds = p.whole("durationSec"), from.flag("showDuration") != false {
                    parts.append(SDUIWords.spokenDuration(seconds))
                    text("duration", SDUIWords.clock(seconds))
                }
                e.label = SDUIWords.join(parts)
                e.progress = Builder.percent(p)
            case "Banner":
                e.role = node.action == nil ? "group" : "button"
                e.label = SDUIWords.join([p.text("title"), p.text("text"), p.text("buttonLabel")])
                text("title", p.text("title"))
                text("text", p.text("text"))
                text("button", p.text("buttonLabel"))
                lines("title", 2)
                lines("text", 2)
                e.picture = SDUIImageRef(p["image"])
                e.icon = p.text("icon")
            case "Text":
                let role = p.text("role").isEmpty ? "body" : p.text("role")
                e.textSize = layout.text[role] ?? 0
                e.role = ["pageTitle": "heading 1", "heading": "heading 2", "title": "heading 3"][role] ?? "text"
                let shown = p.text("text")
                e.label = p.text("format") == "markdown" ? SDUIMarkdown.plainText(shown) : shown
                text("text", shown)
                if let most = p.whole("maxLines") { lines("text", most) }
            case "Notice":
                let tone = p.text("tone")
                e.role = tone == "warning" || tone == "danger" ? "alert" : "status"
                let whole = p.text("title") + ". " + p.text("text")
                e.label = whole.hasPrefix(". ") ? String(whole.dropFirst(2)) : whole
                text("title", p.text("title"))
                text("text", p.text("text"))
                text("button", p.text("buttonLabel"))
                e.icon = p.text("icon")
            case "Button":
                e.role = "button"
                e.label = p.text("label")
                text("title", p.text("label"))
                lines("title", 1)
                e.icon = p.text("icon")
            case "Image":
                e.picture = SDUIImageRef(p["image"])
                if !p.text("alt").isEmpty || node.action != nil {
                    e.role = "img"
                    e.label = p.text("alt")
                }
            case "SearchBox":
                e.role = "searchbox"
                e.label = "Search"
                text("placeholder", p.text("placeholder"))
                text("query", p.text("query"))
            case "ListItem":
                e.role = node.action == nil ? "text" : "button"
                e.label = SDUIWords.join([p.text("title"), p.text("subtitle"), p.text("trailing")])
                text("title", p.text("title"))
                text("subtitle", p.text("subtitle"))
                text("trailing", p.text("trailing"))
                lines("title", 1)
                lines("subtitle", 1)
                e.picture = SDUIImageRef(p["image"])
                e.icon = p.text("icon")
            case "Divider":
                e.role = "separator"
            case "NativeView":
                e.role = "group"
                e.label = p.text("view")
            case "Stack", "Split", "Spacer":
                break
            default:
                // A type this catalogue doesn't have is drawn as a plain column.
                e.unknownType = node.type
                e.type = "Stack"
            }
            return e
        }

        /// One card: what its style shows of what it was given.
        func card(_ e: inout SDUIElement, parent: SDUINode?) {
            let p = e.props
            e.role = "button"
            e.picture = SDUIImageRef(p["image"])
            e.icon = p.text("icon")
            if parent?.type == "Hero" {
                // A slide of a Hero: a group, not a button; its buttons are its own.
                e.role = "group"
                e.facts = Builder.facts(p)
                e.label = SDUIWords.join([p.text("title")] + (e.facts.isEmpty ? [] : [e.facts.joined(separator: ", ")]))
                e.text = ["title": p.text("title")]
                if !e.facts.isEmpty { e.text["facts"] = e.facts.joined(separator: " · ") }
                if !p.text("synopsis").isEmpty { e.text["synopsis"] = p.text("synopsis") }
                e.lines = ["title": 2, "synopsis": 3]
                e.buttons = Builder.buttons(p)
                e.poster = SDUIImageRef(p["logo"])
                return
            }
            let style = catalog.cardStyle(p.text("style")) ?? .unknown
            let shows = style.shows ?? ["title", "subtitle"]
            e.label = SDUIWords.cardLabel(p, shows: shows)
            let titles = parent?.properties.flag("showTitles") != false
            for part in shows {
                switch part {
                case "title", "subtitle":
                    guard titles, !p.text(part).isEmpty else { continue }
                    e.text[part] = p.text(part)
                    e.shows.append(part)
                    e.lines[part] = part == "title" ? style.titleLines ?? 1 : style.subtitleLines ?? 1
                case "synopsis":
                    guard !p.text(part).isEmpty else { continue }
                    e.text[part] = p.text(part)
                    e.lines[part] = 2
                    e.shows.append(part)
                case "remaining", "number":
                    guard !p.text(part).isEmpty else { continue }
                    e.text[part] = p.text(part)
                    e.shows.append(part)
                case "now", "next":
                    guard let programme = p.fields(part) else { continue }
                    e.text[part] = programme.text("title")
                    e.lines[part] = 1
                    e.shows.append(part)
                case "progress":
                    guard let percent = Builder.percent(p) else { continue }
                    e.progress = percent
                    e.shows.append(part)
                case "watched":
                    if p.flag("watched") == true { e.shows.append(part) }
                case "unwatched", "count":
                    guard let count = p.whole(part) else { continue }
                    e.text[part] = String(count)
                    e.shows.append(part)
                case "badges":
                    let badges = p.items(part).compactMap(\.string)
                    guard !badges.isEmpty else { continue }
                    e.text[part] = badges.joined(separator: " ")
                    e.shows.append(part)
                default:
                    continue
                }
            }
            if let rank = p.whole("rank") {
                e.text["rank"] = String(rank)
                e.shows.insert("rank", at: 0)
            }
            e.lines = e.lines.filter { $0.value > 0 }
        }

        static func percent(_ p: SDUIProps) -> Int? { p.number("progress").map { Int($0 * 100 + 0.5) } }

        static func facts(_ p: SDUIProps) -> [String] { p.items("facts").compactMap(\.object).map { $0.text("value") } }

        static func options(_ field: SDUIProps) -> [SDUIOption] {
            field.items("options").compactMap(\.object).map { SDUIOption(value: $0.text("value"), label: $0.text("label")) }
        }

        static func buttons(_ p: SDUIProps) -> [SDUIButtonModel] {
            p.items("actions").enumerated().compactMap { index, value in
                guard let fields = value.object else { return nil }
                let id = fields.text("id").isEmpty ? "action\(index)" : fields.text("id")
                return SDUIButtonModel(id: id, label: fields.text("label"), icon: fields.text("icon"),
                                       primary: fields.flag("primary") == true, action: fields["action"]?.decoded(SDUIAction.self))
            }
        }
    }
}

/// The words the spec fixes: labels and the short forms of what a thing does.
public enum SDUIWords {
    /// Parts joined by ", ", empty ones left out.
    public static func join(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: ", ") }

    /// A card's accessibility label: the parts its style shows, in the style's order.
    public static func cardLabel(_ p: SDUIProps, shows: [String]) -> String {
        var parts: [String] = []
        if let rank = p.whole("rank") { parts.append("Number \(rank)") }
        // A photo's name is read, though it isn't drawn.
        if !shows.contains("title") { parts.append(p.text("title")) }
        for part in shows {
            switch part {
            case "title", "subtitle", "remaining":
                parts.append(p.text(part))
            case "number":
                if !p.text(part).isEmpty { parts.append("Channel " + p.text(part)) }
            case "now", "next":
                if let programme = p.fields(part) { parts.append(part + " " + programme.text("title")) }
            case "progress":
                if let fill = p.number("progress"), p.fields("now") == nil { parts.append("\(Int(fill * 100 + 0.5)) percent watched") }
            case "watched":
                if p.flag("watched") == true { parts.append("Watched") }
            case "unwatched":
                if let count = p.whole(part) { parts.append("\(count) unwatched") }
            case "count":
                if let count = p.whole(part) { parts.append("\(count) items") }
            case "badges":
                parts += p.items(part).compactMap(\.string)
            default:
                break
            }
        }
        return join(parts)
    }

    public static func spokenDuration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if m == 0 { return "\(s) seconds" }
        if s == 0 { return "\(m) minutes" }
        return "\(m) minutes \(s) seconds"
    }

    public static func clock(_ seconds: Int) -> String {
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        if seconds >= 3600 { return "\(seconds / 3600):\(two(seconds % 3600 / 60)):\(two(seconds % 60))" }
        return "\(seconds / 60):\(two(seconds % 60))"
    }

    /// What activating something does, in the conformance kit's words: "navigate /item/3", "play 3 from the start".
    public static func action(_ action: SDUIAction?) -> String {
        guard let action else { return "" }
        switch action.type {
        case "navigate", "native":
            return action.type + " " + (action.to ?? "")
        case "play":
            return "play " + (action.item ?? "") + (action.params?["resume"]?.bool == false ? " from the start" : "")
        case "external":
            return "external " + (action.url ?? "")
        case "command":
            var words = "command " + (action.op ?? "")
            if let item = action.item, !item.isEmpty { words += " " + item }
            if let tab = action.params?["tab"]?.string, !tab.isEmpty { words += " " + tab }
            return words
        default:
            return action.type
        }
    }
}
