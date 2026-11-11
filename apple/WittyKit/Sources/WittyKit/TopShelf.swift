// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// What the Apple TV's Top Shelf shows. The app writes it to the App Group folder it shares with
// its extension. Pictures need a sign-in, and a sign-in never goes in that folder, so the app
// saves small copies of the posters beside this file and the shelf names those files.

public struct ShelfEntry: Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// A file name in the shared folder, or nil for no picture.
    public let poster: String?
    public let link: String
    /// From a server-driven shelf: `poster`, `wide` or `square`, the link that plays it, and how far through it is.
    public var shape: String?
    public var play: String?
    public var progress: Double?

    public init(id: String, title: String, subtitle: String, poster: String?, link: String, shape: String? = nil,
                play: String? = nil, progress: Double? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.poster = poster
        self.link = link
        self.shape = shape
        self.play = play
        self.progress = progress
    }
}

public struct ShelfSection: Codable, Equatable {
    public let title: String
    public let entries: [ShelfEntry]

    public init(title: String, entries: [ShelfEntry]) {
        self.title = title
        self.entries = entries
    }
}

public struct Shelf: Codable, Equatable {
    public static let groupId = "group.com.wittywilla.wittymediaclient"
    public static let fileName = "top-shelf.json"
    public static let posterFolder = "shelf-posters"
    public static let maxEntries = 12
    /// A server-driven shelf has at most 4 sections of 10.
    public static let maxSections = 4
    private static let maxFileBytes = 256 * 1024

    public var sections: [ShelfSection]

    public init(sections: [ShelfSection] = []) {
        self.sections = sections
    }

    public var entries: [ShelfEntry] { sections.flatMap(\.entries) }

    /// Continue watching and recently added, from the home page. Rows are named by stable keys.
    public static func from(home: Home) -> Shelf {
        let hubs = home.hubs ?? []
        func entries(_ row: [Hub]) -> [ShelfEntry] {
            var out: [ShelfEntry] = []
            for hub in row {
                out += (hub.items ?? []).map { item in
                    let title = item.showTitle?.isEmpty == false ? item.showTitle ?? item.title : item.title
                    return ShelfEntry(id: "i\(item.id)", title: PlainWords.clean(title, limit: 120), subtitle: PlainWords.clean(item.episodeLabel, limit: 60),
                                      poster: "i\(item.id).jpg", link: DeepLink.item(item.id).address)
                }
                out += (hub.shows ?? []).map { show in
                    ShelfEntry(id: "s\(show.id)", title: PlainWords.clean(show.title, limit: 120), subtitle: "",
                               poster: "s\(show.id).jpg", link: DeepLink.show(show.id).address)
                }
            }
            return Array(uniqued(out).prefix(maxEntries))
        }
        let going = entries(hubs.filter { $0.key == "continue" || $0.key == "nextup" })
        let recent = entries(hubs.filter { $0.key.hasPrefix("recent-") })
        var sections: [ShelfSection] = []
        if !going.isEmpty { sections.append(ShelfSection(title: "Continue watching", entries: going)) }
        if !recent.isEmpty { sections.append(ShelfSection(title: "Recently added", entries: recent)) }
        return Shelf(sections: sections)
    }

    public func write(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// Everything read here is checked again as if it came from outside, because anything else
    /// in the group could have written the folder. Nothing unusable reaches the shelf.
    public static func read(from folder: URL) -> Shelf {
        let file = folder.appendingPathComponent(fileName)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber,
              size.intValue <= maxFileBytes,
              let data = try? Data(contentsOf: file),
              let shelf = try? JSONDecoder().decode(Shelf.self, from: data) else { return Shelf() }
        let sections = shelf.sections.prefix(maxSections).compactMap { section -> ShelfSection? in
            let entries = section.entries.prefix(maxEntries).compactMap { entry -> ShelfEntry? in
                guard let url = URL(string: entry.link), DeepLink.parse(url) != nil, !entry.title.isEmpty else { return nil }
                let poster = entry.poster.flatMap { isPosterName($0) ? $0 : nil }
                let play = entry.play.flatMap { text in URL(string: text).flatMap(DeepLink.parse) == nil ? nil : text }
                let shape = entry.shape.flatMap { ["poster", "wide", "square"].contains($0) ? $0 : nil }
                let progress = entry.progress.flatMap { $0.isFinite && $0 > 0 && $0 <= 1 ? $0 : nil }
                return ShelfEntry(id: String(entry.id.prefix(64)), title: PlainWords.clean(entry.title, limit: 120), subtitle: PlainWords.clean(entry.subtitle, limit: 60),
                                  poster: poster, link: entry.link, shape: shape, play: play, progress: progress)
            }
            return entries.isEmpty ? nil : ShelfSection(title: PlainWords.clean(section.title, limit: 60), entries: entries)
        }
        return Shelf(sections: sections)
    }

    /// A plain name in one folder: no path can be made from it.
    public static func isPosterName(_ name: String) -> Bool {
        name.range(of: "^[ist][0-9]{1,20}\\.jpg\\z", options: .regularExpression) != nil
    }

    /// Signing out takes the titles and pictures with it.
    public static func clear(in folder: URL) {
        let files = FileManager.default
        try? files.removeItem(at: folder.appendingPathComponent(fileName))
        try? files.removeItem(at: folder.appendingPathComponent(posterFolder, isDirectory: true))
    }
}
