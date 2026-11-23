// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Two things a server with module SDUI asks of an app besides drawing pages (the server's docs/SDUI-MODULES.md and
// docs/SDUI.md, Layout options): a Layout row in the app's own Settings, and Settings → Modules, where each module's
// settings are drawn with the app's own rows. Neither is ever a server-driven page.

/// `GET /sdui/modules/settings`: the modules whose settings this profile may see.
public struct ModuleSettingsList: Decodable, Equatable, Sendable {
    public struct Entry: Decodable, Equatable, Identifiable, Sendable {
        public var module: String
        public var label: String
        public var icon: String?
        public var id: String { module }
    }

    public var modules: [Entry]

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        modules = ((try? box.decodeIfPresent([Loose<Entry>].self, forKey: .modules)) ?? []).compactMap(\.value)
            .filter { SDUIRouter.isModuleName($0.module) }
    }

    enum CodingKeys: String, CodingKey { case modules }
}

/// One module's settings for this profile: its pages of groups of rows, every value with its default, and which secrets
/// have a value. Secrets themselves are never sent.
public struct ModuleSettings: Decodable, Equatable, Sendable {
    public struct Option: Decodable, Equatable, Sendable {
        public var value: String
        public var label: String
    }

    public struct Row: Decodable, Equatable, Identifiable, Sendable {
        public var key: String?
        public var kind: String
        public var label: String
        public var help: String?
        public var scope: String?
        public var options: [Option]?
        public var min: Int?
        public var max: Int?
        public var unit: String?
        public var maxLength: Int?
        /// How far − and + go: 1 for a module's rows; the TV's own Settings pages (TvSettings.swift) give larger ones.
        public var step: Int?
        public var id: String { key ?? "info:" + label }

        public var isProfile: Bool { scope == "profile" }
        /// Kinds this app draws. A kind it doesn't know is shown as its label, to read.
        public static let kinds: Set<String> = ["bool", "enum", "int", "string", "secret", "info"]
    }

    public struct Group: Decodable, Equatable, Sendable {
        public var title: String?
        public var footer: String?
        public var rows: [Row]
    }

    public struct Page: Decodable, Equatable, Identifiable, Sendable {
        public var id: String
        public var title: String
        public var icon: String?
        public var admin: Bool?
        public var groups: [Group]
    }

    public var module: String
    public var label: String
    public var pages: [Page]
    public var values: [String: JSONValue]
    public var secretsSet: [String]
    public var editable: Bool

    enum CodingKeys: String, CodingKey { case module, label, pages, values, secretsSet, editable }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        module = try box.decode(String.self, forKey: .module)
        label = (try? box.decodeIfPresent(String.self, forKey: .label)) ?? module
        pages = ((try? box.decodeIfPresent([Loose<Page>].self, forKey: .pages)) ?? []).compactMap(\.value)
        values = (try? box.decodeIfPresent([String: JSONValue].self, forKey: .values)) ?? [:]
        secretsSet = (try? box.decodeIfPresent([String].self, forKey: .secretsSet)) ?? []
        editable = (try? box.decodeIfPresent(Bool.self, forKey: .editable)) ?? false
    }

    /// Whether this profile may change a row: its own `profile` rows always, `server` rows only as an administrator.
    public func canChange(_ row: Row) -> Bool {
        guard row.key != nil, row.kind != "info", Row.kinds.contains(row.kind) else { return false }
        return row.isProfile || editable
    }

    public func isSet(_ row: Row) -> Bool { row.key.map(secretsSet.contains) ?? false }

    /// A row's value as words: what a read-only row shows and what a screen reader says.
    public func shown(_ row: Row) -> String {
        guard let key = row.key else { return "" }
        let value = values[key]
        switch row.kind {
        case "bool": return value?.bool == true ? "On" : "Off"
        case "enum":
            let picked = value?.string ?? ""
            return row.options?.first { $0.value == picked }?.label ?? picked
        case "int":
            guard let number = value?.int else { return "" }
            return row.unit.map { "\(number) \($0)" } ?? "\(number)"
        case "secret": return isSet(row) ? "Set" : "Not set"
        default: return value?.string ?? ""
        }
    }

    /// Checks a value as the server will, so a wrong one is said before it's sent. Nil when it's good.
    public static func problem(_ value: JSONValue, for row: Row) -> String? {
        switch row.kind {
        case "bool":
            return value.bool == nil ? "\(row.label) is on or off" : nil
        case "enum":
            guard let picked = value.string, (row.options ?? []).contains(where: { $0.value == picked }) else {
                return "\(row.label) is one of " + (row.options ?? []).map(\.label).joined(separator: ", ")
            }
            return nil
        case "int":
            guard let number = value.int, value.double.map({ $0.rounded() == $0 }) == true else { return "\(row.label) is a whole number" }
            if let min = row.min, number < min { return "\(row.label) is at least \(min)" }
            if let max = row.max, number > max { return "\(row.label) is at most \(max)" }
            return nil
        case "string", "secret":
            guard let text = value.string else { return "\(row.label) is text" }
            let limit = (row.maxLength ?? 0) > 0 ? row.maxLength ?? 1000 : 1000
            if text.count > limit { return "\(row.label) is at most \(limit) characters" }
            if text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) { return "\(row.label) is one line of plain text" }
            return nil
        default:
            return "\(row.label) can't be changed"
        }
    }
}

public extension WittyClient {
    func moduleSettingsList() async throws -> ModuleSettingsList { try await get("/sdui/modules/settings") }

    func moduleSettings(_ module: String) async throws -> ModuleSettings {
        guard SDUIRouter.isModuleName(module) else { throw APIError(status: 404, message: "This isn't available.") }
        return try await get("/sdui/modules/\(module)/settings")
    }

    /// Saves values: `server` rows to the server's route (an administrator's), `profile` rows to the profile's own.
    /// `null` takes a saved value away, so the default applies. Answers the settings as they now are.
    func setModuleSettings(_ module: String, values: [String: JSONValue], personal: Bool) async throws -> ModuleSettings {
        guard SDUIRouter.isModuleName(module) else { throw APIError(status: 404, message: "This isn't available.") }
        let body = try JSONEncoder().encode(["values": values])
        let data = try await call("PUT", "/sdui/modules/\(module)/settings" + (personal ? "/personal" : ""), body: body)
        return try JSONDecoder().decode(ModuleSettings.self, from: data)
    }
}

public extension SDUIRouter {
    /// A module's ID (docs/SDUI-MODULES.md, Names): a lower-case letter, then 1 to 63 lower-case letters and digits.
    static func isModuleName(_ name: String) -> Bool {
        guard (2...64).contains(name.count), let first = name.first, first.isASCII, first.isLowercase else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }
}
