// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The desktop Settings pages a TV draws itself (docs/TV-SETTINGS-PARITY.md): shared/data/tv-settings.json, the twin of
// Android's net/TvSettings.kt. Each page is in the shape of a module's settings (SDUIModules.swift), so Apple TV draws it
// with the same rows, with where each value is kept on the server: `server` (GET and PUT /settings, the
// administrator's), `ui` (/me/ui, the profile's own choices), `streaming` (/me/streaming) and `about` (/about, to read).
// These are the endpoints the server's own Settings pages use, so a change made on a TV is the same setting everywhere.
// A page's level is the server's TV level (docs/TV-MODE.md): full rows change here, view rows are read, desktopOnly rows
// open the card for a computer.

public struct TvSettingsFile: Decodable, Equatable, Sendable {
    public var stores: [String: TvSettingsStore]
    public var pages: [TvSettingsPage]

    public init(stores: [String: TvSettingsStore] = [:], pages: [TvSettingsPage] = []) {
        self.stores = stores
        self.pages = pages
    }

    public func page(_ id: String) -> TvSettingsPage? { pages.first { $0.id == id } }
}

public struct TvSettingsStore: Decodable, Equatable, Sendable {
    public var get: String
    public var put: String?
    public var write: String?
    public var root: String?
    public var admin: Bool?
}

public struct TvSettingsPage: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var title: String
    public var lead: String?
    public var icon: String?
    public var level: String
    public var admin: Bool?
    public var groups: [TvSettingsGroup]
}

public struct TvSettingsGroup: Decodable, Equatable, Sendable {
    public var title: String?
    public var footer: String?
    public var admin: Bool?
    public var rows: [TvSettingsRow]
}

public struct TvSettingsRow: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable {
        public var label: String
        public var value: String
    }

    public var id: String?
    public var store: String?
    public var key: String?
    /// bool, enum, int, info, list (one row for each thing in a list), link (another screen), desktopOnly (its card).
    public var kind: String
    public var label: String
    public var help: String?
    public var level: String?
    public var admin: Bool?
    public var `default`: JSONValue?
    /// How the value is kept: "flag" ("1" or "0"), "string" (a number as text), "number"; or as it is.
    public var encode: String?
    /// A switch that says the opposite of what is kept (Show the activity button, kept as activityHidden).
    public var invert: Bool?
    public var options: [ModuleSettings.Option]?
    /// What a value none of the options has is called.
    public var other: String?
    public var min: Int?
    public var max: Int?
    public var step: Int?
    public var unit: String?
    /// Kept with the same value as well, when it isn't empty (Disc menus and sound tracks: menuLanguage).
    public var also: [String]?
    /// A link's screen ("app:theme", "tv:skipping"), or a desktopOnly row's address on the server.
    public var to: String?
    public var format: String?
    public var item: Item?

    public init(kind: String, label: String = "", store: String? = nil, key: String? = nil, to: String? = nil) {
        self.kind = kind
        self.label = label
        self.store = store
        self.key = key
        self.to = to
    }

    /// Unique on its page: what the module rows know it by.
    public var rowKey: String {
        if let store, let key, !store.isEmpty, !key.isEmpty { return store + ":" + key }
        return "row:" + (id ?? label)
    }
}

public enum TvSettingsRules {
    static let drawn: Set<String> = ["bool", "enum", "int", "info", "list", "link", "desktopOnly"]

    public static func pageVisible(_ page: TvSettingsPage, admin: Bool) -> Bool { admin || page.admin != true }

    /// What this profile sees of a page: what's for administrators only to them, rows of a kind this app doesn't know left out.
    public static func visible(_ file: TvSettingsFile, _ page: TvSettingsPage, admin: Bool) -> [TvSettingsGroup] {
        page.groups.filter { admin || $0.admin != true }.map { group in
            var g = group
            g.rows = group.rows.filter { r in
                drawn.contains(r.kind) && (admin || (r.admin != true && file.stores[r.store ?? ""]?.admin != true))
            }
            return g
        }.filter { !$0.rows.isEmpty }
    }

    /// The stores a page reads.
    public static func stores(_ groups: [TvSettingsGroup]) -> Set<String> {
        Set(groups.flatMap { $0.rows.compactMap { $0.store } }.filter { !$0.isEmpty })
    }

    public static func level(_ page: TvSettingsPage, _ row: TvSettingsRow) -> String { row.level ?? page.level }

    /// Whether a row is changed here: a full one, kept somewhere that can be written.
    public static func editable(_ file: TvSettingsFile, _ page: TvSettingsPage, _ row: TvSettingsRow) -> Bool {
        ["bool", "enum", "int"].contains(row.kind) && level(page, row) == TvLevel.full && !(file.stores[row.store ?? ""]?.put ?? "").isEmpty
    }

    /// "a.b" inside an answer.
    public static func at(_ root: JSONValue?, _ path: String) -> JSONValue? {
        guard !path.isEmpty else { return root }
        var here = root
        for part in path.split(separator: ".") {
            guard let next = here?[String(part)] else { return nil }
            here = next
        }
        return here
    }

    private static func text(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let s)?: return s
        case .number(let n)?: return n.rounded() == n ? String(Int64(n)) : String(n)
        case .bool(let b)?: return b ? "true" : "false"
        default: return nil
        }
    }

    public static func bool(_ row: TvSettingsRow, _ raw: JSONValue?) -> Bool {
        var kept: Bool?
        switch raw {
        case .bool(let b)?: kept = b
        case .number(let n)?: kept = n != 0
        case .string(let s)?: kept = s == "1" || s == "true" ? true : (s == "0" || s == "false" ? false : nil)
        default: kept = nil
        }
        // The default is what is kept when nothing is (activityHidden: false), as the web reads it.
        let stored = kept ?? (row.default?.bool ?? (row.default?.string == "1"))
        return row.invert == true ? !stored : stored
    }

    public static func choice(_ row: TvSettingsRow, _ raw: JSONValue?) -> String {
        let v = text(raw) ?? ""
        if v.isEmpty, !(row.options ?? []).contains(where: { $0.value.isEmpty }) { return text(row.default) ?? "" }
        return v
    }

    public static func number(_ row: TvSettingsRow, _ raw: JSONValue?) -> Int {
        if let t = text(raw), let d = Double(t.trimmingCharacters(in: .whitespaces)) { return Int(d) }
        return row.default?.int ?? row.min ?? 0
    }

    /// One step of a number, by the row's step, inside its bounds.
    public static func stepped(_ row: TvSettingsRow, _ now: Int, by: Int) -> Int {
        var next = now + by * Swift.max(1, row.step ?? 1)
        if let low = row.min { next = Swift.max(low, next) }
        if let high = row.max { next = Swift.min(high, next) }
        return next
    }

    public static func limitWords(_ raw: JSONValue?, words: (String) -> String) -> String {
        let height = raw?["maxHeight"]?.int ?? 0
        let kbps = raw?["maxKbps"]?.int ?? 0
        let size = height >= 2160 ? "4K" : "\(height)p"
        let rate: String
        if kbps >= 1000 {
            rate = (kbps % 1000 == 0 ? "\(kbps / 1000)" : String(format: "%.1f", Double(kbps) / 1000)) + " Mb/s"
        } else {
            rate = "\(kbps) kb/s"
        }
        if height > 0, kbps > 0 { return words("tvsLimitBoth").replacingOccurrences(of: "{size}", with: size).replacingOccurrences(of: "{rate}", with: rate) }
        if height > 0 { return words("tvsLimitSize").replacingOccurrences(of: "{size}", with: size) }
        if kbps > 0 { return words("tvsLimitRate").replacingOccurrences(of: "{rate}", with: rate) }
        return words("tvsNoLimit")
    }

    /// A row's value as the module rows hold it: a switch's true or false, a choice's value, a number, an info row's words.
    public static func value(_ row: TvSettingsRow, _ stores: [String: JSONValue], words: (String) -> String) -> JSONValue? {
        let raw = at(stores[row.store ?? ""], row.key ?? "")
        switch row.kind {
        case "bool": return .bool(bool(row, raw))
        case "enum": return .string(choice(row, raw))
        case "int": return .number(Double(number(row, raw)))
        case "info", "desktopOnly":
            guard let key = row.key, !key.isEmpty else { return nil }
            return .string(row.format == "limit" ? limitWords(raw, words: words) : text(raw) ?? "")
        default: return nil
        }
    }

    /// A list row's things, as a label and a value each.
    public static func items(_ row: TvSettingsRow, _ stores: [String: JSONValue]) -> [(String, String)] {
        guard let list = at(stores[row.store ?? ""], row.key ?? "")?.array else { return [] }
        let item = row.item ?? TvSettingsRow.Item(label: "name", value: "version")
        return list.compactMap { e in text(at(e, item.label)).map { ($0, text(at(e, item.value)) ?? "") } }
    }

    /// How a value chosen here is kept.
    public static func encode(_ row: TvSettingsRow, _ value: JSONValue) -> JSONValue {
        switch row.kind {
        case "bool":
            let on = value.bool == true
            let kept = row.invert == true ? !on : on
            return row.encode == "flag" ? .string(kept ? "1" : "0") : .bool(kept)
        case "enum":
            let s = text(value) ?? ""
            return row.encode == "number" ? .number(Double(Int(Double(s) ?? 0))) : .string(s)
        case "int":
            let n = Int(Double(text(value) ?? "") ?? 0)
            return row.encode == "string" ? .string(String(n)) : .number(Double(n))
        default: return value
        }
    }

    /// What a change sends to the store's `put`: for "patch", the keys alone (the server keeps the rest); for "merge",
    /// everything there now (fresh: other screens write there too) with this change, at the store's root.
    public static func body(_ store: TvSettingsStore, fresh: JSONValue?, row: TvSettingsRow, value: JSONValue) -> JSONValue {
        let kept = encode(row, value)
        var changes: [(String, JSONValue)] = [(row.key ?? "", kept)]
        if let t = text(kept), !t.isEmpty { changes += (row.also ?? []).map { ($0, kept) } }
        if store.write == "patch" { return .object(Dictionary(changes, uniquingKeysWith: { $1 })) }
        let root = store.root ?? ""
        let prefix = root.isEmpty ? "" : root + "."
        var base = at(fresh, root)?.object ?? [:]
        for (k, v) in changes where prefix.isEmpty || k.hasPrefix(prefix) {
            base = put(base, String(k.dropFirst(prefix.count)).split(separator: ".").map(String.init), v)
        }
        return .object(base)
    }

    private static func put(_ obj: [String: JSONValue], _ path: [String], _ value: JSONValue) -> [String: JSONValue] {
        var out = obj
        guard let head = path.first else { return out }
        if path.count == 1 {
            out[head] = value
        } else {
            out[head] = .object(put(obj[head]?.object ?? [:], Array(path.dropFirst()), value))
        }
        return out
    }

    /// The page as a module's settings, for the rows Apple TV draws for a module: words looked up, values filled in.
    public static func asModule(_ file: TvSettingsFile, _ page: TvSettingsPage, _ groups: [TvSettingsGroup], _ stores: [String: JSONValue], words: (String) -> String) -> ModuleSettings {
        var values: [String: JSONValue] = [:]
        let mod = groups.map { g in
            ModuleSettings.Group(title: words(g.title ?? ""), footer: words(g.footer ?? ""), rows: g.rows.map { r in
                if let v = value(r, stores, words: words) { values[r.rowKey] = v }
                var options = (r.options ?? []).map { ModuleSettings.Option(value: $0.value, label: words($0.label)) }
                if r.kind == "enum", let chosen = values[r.rowKey]?.string, !options.contains(where: { $0.value == chosen }), let other = r.other {
                    options.append(ModuleSettings.Option(value: chosen, label: words(other)))
                }
                // Editable rows say "profile", so ModuleSettings.canChange lets them change; the rest are read.
                return ModuleSettings.Row(key: r.rowKey, kind: r.kind, label: words(r.label), help: words(r.help ?? ""),
                                          scope: editable(file, page, r) ? "profile" : "server", options: options,
                                          min: r.min, max: r.max, unit: r.unit.map(words), maxLength: nil, step: r.step)
            })
        }
        return ModuleSettings(module: page.id, label: words(page.title), pages: [ModuleSettings.Page(id: page.id, title: words(page.title), icon: page.icon, admin: page.admin, groups: mod)],
                              values: values, secretsSet: [], editable: false)
    }
}

extension ModuleSettings {
    init(module: String, label: String, pages: [Page], values: [String: JSONValue], secretsSet: [String], editable: Bool) {
        self.module = module
        self.label = label
        self.pages = pages
        self.values = values
        self.secretsSet = secretsSet
        self.editable = editable
    }
}

public extension WittyClient {
    /// One of the places a TV settings page reads (TvSettingsStore.get).
    func tvSettingsStore(_ store: TvSettingsStore) async throws -> JSONValue { try await get(store.get) }

    /// Sends one change to where it is kept (TvSettingsRules.body makes it).
    func saveTvSetting(_ store: TvSettingsStore, _ body: JSONValue) async throws {
        guard let put = store.put, !put.isEmpty else { return }
        _ = try await call("PUT", put, body: try JSONEncoder().encode(body))
    }
}
