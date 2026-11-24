// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The bell's routes (the server's docs/NOTIFICATIONS.md): each profile's notifications, how many are unread, and the
// kinds it gets. The same calls the website and the Android app make.

/// One notification, as its profile sees it. `link` is a path in the website.
public struct Note: Codable, Equatable, Identifiable {
    public let id: Int64
    public let kind: String
    public let title: String
    public let body: String?
    public let link: String?
    public let at: Double
    public var read: Bool

    public init(id: Int64, kind: String = "", title: String = "", body: String? = nil, link: String? = nil, at: Double = 0, read: Bool = false) {
        self.id = id; self.kind = kind; self.title = title; self.body = body; self.link = link; self.at = at; self.read = read
    }
}

public struct NoteList: Decodable, Equatable {
    public let notes: [Note]?
    public let unread: Int
    public let latest: Int64
}

public struct NoteCount: Decodable, Equatable {
    public let unread: Int
    public let latest: Int64
}

public struct NoteChoice: Codable, Equatable {
    public let kind: String
    public var on: Bool
    public init(kind: String, on: Bool) { self.kind = kind; self.on = on }
}

private struct NoteChoices: Codable { let choices: [NoteChoice]? }
private struct NoteIds: Encodable { let ids: [Int64] }

public enum NoteKinds {
    /// What each kind is called and what it's about, as the website's Settings → Notifications says.
    public static let names: [String: (name: String, about: String)] = [
        "episodes": ("New episodes", "When a scan finds new episodes of a show you can watch."),
        "recordings": ("Recordings", "When a recording you set up finishes, or fails."),
        "scans": ("Failed scans", "When a library scan stops on an error."),
        "modules": ("Module updates", "When modules you have get new versions."),
        "server": ("Server updates", "When a new version of WittyMediaServer is out."),
    ]

    /// A link is followed only when it is a path in the website.
    public static func safeLink(_ link: String?) -> String? {
        guard let link, link.hasPrefix("/"), !link.hasPrefix("//"), !link.contains("\\") else { return nil }
        return link
    }

    /// The show a link opens, when it is a show's page.
    public static func show(_ link: String?) -> Int64? {
        guard let path = safeLink(link), path.hasPrefix("/show/") else { return nil }
        return Int64(path.dropFirst("/show/".count))
    }
}

extension WittyClient {
    public func noteCount() async throws -> NoteCount { try await get("/me/notifications/count") }

    public func notes(before: Int64 = 0, limit: Int = 30) async throws -> NoteList {
        try await get("/me/notifications?limit=\(limit)" + (before > 0 ? "&before=\(before)" : ""))
    }

    /// None named: every one.
    @discardableResult
    public func markNotesRead(_ ids: [Int64] = []) async throws -> NoteCount {
        let body = ids.isEmpty ? Data("{}".utf8) : try JSONEncoder().encode(NoteIds(ids: ids))
        return try JSONDecoder().decode(NoteCount.self, from: try await call("POST", "/me/notifications/read", body: body))
    }

    /// 0: every one.
    @discardableResult
    public func clearNotes(_ id: Int64 = 0) async throws -> NoteCount {
        try JSONDecoder().decode(NoteCount.self, from: try await call("DELETE", "/me/notifications" + (id > 0 ? "/\(id)" : "")))
    }

    public func noteChoices() async throws -> [NoteChoice] {
        let got: NoteChoices = try await get("/me/notifications/choices")
        return got.choices ?? []
    }

    @discardableResult
    public func setNoteChoices(_ list: [NoteChoice]) async throws -> [NoteChoice] {
        let body = try JSONEncoder().encode(NoteChoices(choices: list))
        return try JSONDecoder().decode(NoteChoices.self, from: try await call("PUT", "/me/notifications/choices", body: body)).choices ?? []
    }
}
