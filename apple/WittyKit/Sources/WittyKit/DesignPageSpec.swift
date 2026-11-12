// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// A Design 2 page as data (the design canvas's `gp` pages, docs/design-2/canvas/Exp.dc.html: `mk`, `secR`, `secP`,
/// `secN`, `secC`, `R`, `Cc`, `A1`, `A2`): a small eyebrow, a big title, a lead line, sections of rows, chips, a note or
/// cards, the actions and a foot line. The app draws it with `DesignSpecPage`; the same spec reads the same on a TV, a
/// tablet and a phone (one column there). The builders below are named after the canvas's, so a page is copied across
/// as it is drawn: `DesignPageSpec.mk("Welcome", "Choose your server", "…", [.secR("Saved", [.R("Home", "Last used", true)])])`.
///
/// Every row, chip, card and action has an `id` (its title in lower case with dashes, unless given) that a press
/// reports, and that a UI test finds as `design.<id>`. Focus goes through them top to bottom, starting at `start`.
public struct DesignPageSpec: Codable, Equatable, Sendable {
    public var eyebrow: String
    public var title: String
    public var lead: String
    public var sections: [Section]
    public var actions: [Action]
    public var foot: String
    /// Shown over another screen (a sheet, a dialog): Back closes it, as the Back ladder says for a layer. Otherwise
    /// it is the Stage, and Back goes on to the Bar.
    public var layer: Bool
    /// Where focus starts: an item's `id`. Empty is the first thing that can take focus, top to bottom.
    public var start: String

    public init(eyebrow: String = "", title: String, lead: String = "", sections: [Section] = [], actions: [Action] = [],
                foot: String = "", layer: Bool = false, start: String = "") {
        self.eyebrow = eyebrow
        self.title = title
        self.lead = lead
        self.sections = sections
        self.actions = actions
        self.foot = foot
        self.layer = layer
        self.start = start
    }

    // MARK: Parts

    public enum Kind: String, Codable, Sendable { case rows, chips, note, cards }

    public struct Section: Codable, Equatable, Sendable {
        public var heading: String
        public var kind: Kind
        public var rows: [Row]
        public var chips: [Chip]
        public var cards: [Card]
        /// A note's words, and whether it sits on an accent wash (`secN`'s `tone`).
        public var note: String
        public var tone: Bool
        /// Cards across; nil is the device's own (two on a phone, three on a tablet, four on a TV). Never more than
        /// two on a phone.
        public var columns: Int?

        public init(heading: String = "", kind: Kind, rows: [Row] = [], chips: [Chip] = [], cards: [Card] = [],
                    note: String = "", tone: Bool = false, columns: Int? = nil) {
            self.heading = heading
            self.kind = kind
            self.rows = rows
            self.chips = chips
            self.cards = cards
            self.note = note
            self.tone = tone
            self.columns = columns
        }
    }

    /// `R(title, value, on, sub)`: a title in bold, a detail line under it, a value on the right (the accent when on).
    public struct Row: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var value: String
        public var on: Bool
        public var detail: String
        /// Whether pressing it does something; a row that only says something isn't a stop for focus.
        public var pressable: Bool

        public init(id: String = "", title: String, value: String = "", on: Bool = false, detail: String = "", pressable: Bool = true) {
            self.id = id.isEmpty ? DesignPageSpec.slug(title) : id
            self.title = title
            self.value = value
            self.on = on
            self.detail = detail
            self.pressable = pressable
        }
    }

    /// `Cc(title, on)`: a chip, filled when on.
    public struct Chip: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var on: Bool

        public init(id: String = "", title: String, on: Bool = false) {
            self.id = id.isEmpty ? DesignPageSpec.slug(title) : id
            self.title = title
            self.on = on
        }
    }

    /// A card in `secC`: a title, a line under it, and optionally three swatches (a look's or a theme's colours, as
    /// `#rrggbb`), ringed when chosen.
    public struct Card: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var subtitle: String
        public var on: Bool
        /// Background, second background and accent; empty for none.
        public var swatches: [String]
        /// A symbol over the title (an SF Symbol name on Apple), for a card that is a way to do something; empty for none.
        public var symbol: String
        /// A look's layout id ("lumen", "rail", "classic", …): the card shows a preview of that layout in its swatches'
        /// colours (W6's `LayoutThumb`), where it would show the swatch strip. Empty for none.
        public var layout: String

        public init(id: String = "", title: String, subtitle: String = "", on: Bool = false, swatches: [String] = [], symbol: String = "",
                    layout: String = "") {
            self.id = id.isEmpty ? DesignPageSpec.slug(title) : id
            self.title = title
            self.subtitle = subtitle
            self.on = on
            self.swatches = swatches
            self.symbol = symbol
            self.layout = layout
        }
    }

    /// `A1` (the primary action) or `A2` (a secondary one).
    public struct Action: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var primary: Bool

        public init(id: String = "", title: String, primary: Bool = false) {
            self.id = id.isEmpty ? DesignPageSpec.slug(title) : id
            self.title = title
            self.primary = primary
        }
    }

    // MARK: The canvas's builders

    public static func mk(_ eyebrow: String, _ title: String, _ lead: String, _ sections: [Section],
                          _ actions: [Action] = [], _ foot: String = "") -> DesignPageSpec {
        DesignPageSpec(eyebrow: eyebrow, title: title, lead: lead, sections: sections, actions: actions, foot: foot)
    }

    public static func R(_ title: String, _ value: String = "", _ on: Bool = false, _ detail: String = "") -> Row {
        Row(title: title, value: value, on: on, detail: detail)
    }

    public static func Cc(_ title: String, _ on: Bool = false) -> Chip { Chip(title: title, on: on) }
    public static func A1(_ title: String) -> Action { Action(title: title, primary: true) }
    public static func A2(_ title: String) -> Action { Action(title: title) }

    // MARK: Focus

    /// Everything that can take focus, top to bottom: each section's rows (those that do something), chips or cards
    /// in order, then the actions.
    public var focusOrder: [String] {
        var out: [String] = []
        for section in sections {
            switch section.kind {
            case .rows: out += section.rows.filter(\.pressable).map(\.id)
            case .chips: out += section.chips.map(\.id)
            case .cards: out += section.cards.map(\.id)
            case .note: break
            }
        }
        return out + actions.map(\.id)
    }

    /// Where focus starts: `start` when it names something that can take focus, else the first such thing.
    public var startFocus: String? {
        let order = focusOrder
        return order.contains(start) ? start : order.first
    }

    /// What Back does on this page, by the Back ladder: a layer closes; the Stage hands focus to the Bar.
    public var back: BackStep { BackLadder.next(ZoneState(zone: layer ? .layer : .stage)) }

    /// Cards across on this device: the section's own, at most two on a phone; else two, three or four.
    public static func columns(_ section: Section, phone: Bool, tablet: Bool) -> Int {
        let device = phone ? 2 : (tablet ? 3 : 4)
        guard let asked = section.columns, asked > 0 else { return device }
        return phone ? min(asked, 2) : asked
    }

    /// A title as an id: lower case, letters and digits, dashes between words.
    public static func slug(_ title: String) -> String {
        var out = ""
        var dash = false
        for c in title.lowercased() {
            if c.isLetter || c.isNumber, c.isASCII {
                if dash, !out.isEmpty { out.append("-") }
                out.append(c)
                dash = false
            } else {
                dash = true
            }
        }
        return out.isEmpty ? "item" : out
    }
}

public extension DesignPageSpec.Section {
    /// Kept in the canvas's spelling so a `gp` row reads the same here.
    static func secR(_ heading: String, _ rows: [DesignPageSpec.Row]) -> Self { .init(heading: heading, kind: .rows, rows: rows) }
    static func secP(_ heading: String, _ chips: [DesignPageSpec.Chip]) -> Self { .init(heading: heading, kind: .chips, chips: chips) }
    static func secN(_ heading: String, _ text: String, _ tone: Bool = false) -> Self { .init(heading: heading, kind: .note, note: text, tone: tone) }
    static func secC(_ heading: String, _ cards: [DesignPageSpec.Card], _ columns: Int? = nil) -> Self {
        .init(heading: heading, kind: .cards, cards: cards, columns: columns)
    }
}

/// The same builders where a list of rows, chips or actions is being written: `[.R("Now", "77be", true)]`.
public extension DesignPageSpec.Row {
    static func R(_ title: String, _ value: String = "", _ on: Bool = false, _ detail: String = "") -> Self {
        .init(title: title, value: value, on: on, detail: detail)
    }
}

public extension DesignPageSpec.Chip {
    static func Cc(_ title: String, _ on: Bool = false) -> Self { .init(title: title, on: on) }
}

public extension DesignPageSpec.Action {
    static func A1(_ title: String) -> Self { .init(title: title, primary: true) }
    static func A2(_ title: String) -> Self { .init(title: title) }
}

// MARK: - Reading a spec sent as JSON

extension DesignPageSpec {
    private enum Keys: String, CodingKey { case eyebrow, title, lead, sections, actions, foot, layer, start }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(eyebrow: try c.decodeIfPresent(String.self, forKey: .eyebrow) ?? "",
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  lead: try c.decodeIfPresent(String.self, forKey: .lead) ?? "",
                  sections: try c.decodeIfPresent([Section].self, forKey: .sections) ?? [],
                  actions: try c.decodeIfPresent([Action].self, forKey: .actions) ?? [],
                  foot: try c.decodeIfPresent(String.self, forKey: .foot) ?? "",
                  layer: try c.decodeIfPresent(Bool.self, forKey: .layer) ?? false,
                  start: try c.decodeIfPresent(String.self, forKey: .start) ?? "")
    }
}

extension DesignPageSpec.Section {
    private enum Keys: String, CodingKey { case heading, kind, rows, chips, cards, note, tone, columns }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(heading: try c.decodeIfPresent(String.self, forKey: .heading) ?? "",
                  kind: try c.decode(DesignPageSpec.Kind.self, forKey: .kind),
                  rows: try c.decodeIfPresent([DesignPageSpec.Row].self, forKey: .rows) ?? [],
                  chips: try c.decodeIfPresent([DesignPageSpec.Chip].self, forKey: .chips) ?? [],
                  cards: try c.decodeIfPresent([DesignPageSpec.Card].self, forKey: .cards) ?? [],
                  note: try c.decodeIfPresent(String.self, forKey: .note) ?? "",
                  tone: try c.decodeIfPresent(Bool.self, forKey: .tone) ?? false,
                  columns: try c.decodeIfPresent(Int.self, forKey: .columns))
    }
}

extension DesignPageSpec.Row {
    private enum Keys: String, CodingKey { case id, title, value, on, detail, pressable }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? "", title: try c.decode(String.self, forKey: .title),
                  value: try c.decodeIfPresent(String.self, forKey: .value) ?? "", on: try c.decodeIfPresent(Bool.self, forKey: .on) ?? false,
                  detail: try c.decodeIfPresent(String.self, forKey: .detail) ?? "",
                  pressable: try c.decodeIfPresent(Bool.self, forKey: .pressable) ?? true)
    }
}

extension DesignPageSpec.Chip {
    private enum Keys: String, CodingKey { case id, title, on }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? "", title: try c.decode(String.self, forKey: .title),
                  on: try c.decodeIfPresent(Bool.self, forKey: .on) ?? false)
    }
}

extension DesignPageSpec.Card {
    private enum Keys: String, CodingKey { case id, title, subtitle, on, swatches, symbol, layout }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? "", title: try c.decode(String.self, forKey: .title),
                  subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle) ?? "",
                  on: try c.decodeIfPresent(Bool.self, forKey: .on) ?? false,
                  swatches: try c.decodeIfPresent([String].self, forKey: .swatches) ?? [],
                  symbol: try c.decodeIfPresent(String.self, forKey: .symbol) ?? "",
                  layout: try c.decodeIfPresent(String.self, forKey: .layout) ?? "")
    }
}

extension DesignPageSpec.Action {
    private enum Keys: String, CodingKey { case id, title, primary }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? "", title: try c.decode(String.self, forKey: .title),
                  primary: try c.decodeIfPresent(Bool.self, forKey: .primary) ?? false)
    }
}
