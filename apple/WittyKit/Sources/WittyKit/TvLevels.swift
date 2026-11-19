// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// How much of each screen a TV offers (WittyMediaServer's docs/TV-MODE.md, 0.8.1). The table is the server's, in its
// SDUI catalogue (`tvLevels`), so Apple TV, Android TV and the server's own TV mode make the same choices: browsing,
// playing, games and their controllers stay; editors with many fields, typing or dragging are a card that says to use
// the WittyMediaClient app on a computer, or a web browser, with what is set now. Apple TV has no web engine, so every
// server page is a card there; the table decides what the card says. The same rules as Android's net/TvLevels.kt.

public enum TvLevel {
    public static let full = "full"
    public static let view = "view"
    public static let desktopOnly = "desktopOnly"
}

/// One screen in the table, by its address (`:name` is one part, `*` at the end the rest).
public struct TvScreenLevel: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var level: String
    public var title: String
    /// Which summary of what is set now `GET /sdui/tv-summary/{id}` gives for it, or "".
    public var summary: String

    public init(id: String = "", path: String = "", level: String = TvLevel.full, title: String = "", summary: String = "") {
        self.id = id
        self.path = path
        self.level = level
        self.title = title
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey { case id, path, level, title, summary }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? ""
        level = (try? c.decodeIfPresent(String.self, forKey: .level)) ?? TvLevel.full
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
    }
}

/// One part of a screen in the table (this app's own editors among them: `layout.editor`, `brand.editor`).
public struct TvPartLevel: Codable, Equatable, Sendable {
    public var id: String
    public var level: String

    public init(id: String, level: String) {
        self.id = id
        self.level = level
    }

    private enum CodingKeys: String, CodingKey { case id, level }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        level = (try? c.decodeIfPresent(String.self, forKey: .level)) ?? TvLevel.full
    }
}

/// The catalogue's `tvLevels`. Nil from a server older than 0.8.1.
public struct TvLevelTable: Codable, Equatable, Sendable {
    /// What a TV device says on the card: "To change this, use the WittyMediaClient app on a Windows or Mac computer,
    /// or a web browser."
    public var note: String
    public var screens: [TvScreenLevel]
    public var parts: [TvPartLevel]

    public init(note: String = "", screens: [TvScreenLevel] = [], parts: [TvPartLevel] = []) {
        self.note = note
        self.screens = screens
        self.parts = parts
    }

    private enum CodingKeys: String, CodingKey { case note, screens, parts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        screens = ((try? c.decodeIfPresent([Loose<TvScreenLevel>].self, forKey: .screens)) ?? []).compactMap(\.value)
        parts = ((try? c.decodeIfPresent([Loose<TvPartLevel>].self, forKey: .parts)) ?? []).compactMap(\.value)
    }

    /// The screen an address is, or nil for one a TV offers in full. The first match wins, as on the server.
    public func screen(for path: String) -> TvScreenLevel? { screens.first { TvLevels.matches($0.path, path) } }

    public func partLevel(_ id: String) -> String { parts.first { $0.id == id }?.level ?? TvLevel.full }
}

/// What `GET /sdui/tv-summary/{id}` answers: a few lines of what is set now, and the server's addresses at home.
public struct TvSummary: Codable, Equatable, Sendable {
    public var id: String
    public var lines: [String]
    public var addresses: [String]

    public init(id: String = "", lines: [String] = [], addresses: [String] = []) {
        self.id = id
        self.lines = lines
        self.addresses = addresses
    }

    private enum CodingKeys: String, CodingKey { case id, lines, addresses }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        lines = (try? c.decodeIfPresent([String].self, forKey: .lines)) ?? []
        addresses = (try? c.decodeIfPresent([String].self, forKey: .addresses)) ?? []
    }
}

public enum TvLevels {
    /// `:name` is one part of the address, and `*` at the end is the rest of it, or nothing.
    public static func matches(_ pattern: String, _ path: String) -> Bool {
        let want = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let bare = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let have = (bare.split(separator: "#", maxSplits: 1).first.map(String.init) ?? "")
            .split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for (i, part) in want.enumerated() {
            if part == "*" && i == want.count - 1 { return true }
            if i >= have.count { return false }
            if part.hasPrefix(":") { continue }
            if part != have[i] { return false }
        }
        return have.count == want.count
    }

    /// Whether this address is an editor a TV doesn't offer: the card then says so in the server's words. With no
    /// table (a server older than 0.8.1) nothing is known, and the card says only to open the page elsewhere.
    public static func isDesktopOnly(_ table: TvLevelTable?, _ path: String) -> Bool {
        table?.screen(for: path)?.level == TvLevel.desktopOnly
    }

    /// Whether one of this app's own editors (the layout editor, name and logo) opens on a TV. Without a table they
    /// do, as before.
    public static func partOpens(_ table: TvLevelTable?, _ id: String) -> Bool {
        guard let table else { return true }
        return table.partLevel(id) != TvLevel.desktopOnly
    }

    /// The address to put in the QR code: the server's own, unless that is one only this device can open, then its
    /// first address on the home network.
    public static func cardAddress(base: String, path: String, home: [String]) -> String {
        let afterScheme = base.components(separatedBy: "://").dropFirst().first ?? base
        let hostPort = afterScheme.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        var host = hostPort
        if host.hasPrefix("[") {
            host = String(host.dropFirst().prefix { $0 != "]" })
        } else if let colon = host.lastIndex(of: ":") {
            host = String(host[..<colon])
        }
        let local = host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1"
        let root = (local ? home.first : nil) ?? base
        let trimmed = root.hasSuffix("/") ? String(root.dropLast()) : root
        return trimmed + (path.hasPrefix("/") ? path : "/" + path)
    }
}

extension WittyClient {
    /// What a TV shows in place of an editor it doesn't open: what is set now, and the addresses at home.
    public func tvSummary(_ id: String) async throws -> TvSummary {
        let name = id.isEmpty ? "none" : id
        return try await get("/sdui/tv-summary/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name))
    }
}
