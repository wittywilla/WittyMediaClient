// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// The last good answer to each server-driven request, on disk, with its ETag: asked again with
/// `If-None-Match` it costs the server nothing, and with no network the page before is still there.
/// A small, bounded folder: so many entries of so many bytes, the oldest going first.
public final class SDUICache: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public let etag: String
        public let body: Data
        public let saved: Date
    }

    private let folder: URL
    private let maxEntries: Int
    private let maxBytes: Int
    private let lock = NSLock()

    /// `folder` is this cache's own: everything in it may be deleted.
    public init(folder: URL, maxEntries: Int = 80, maxBytes: Int = 1_048_576) {
        self.folder = folder
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = maxBytes
    }

    /// The app's cache for one person on one server, under the system's caches folder, which the system may empty.
    public static func standard(server: String, user: Int64) -> SDUICache {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return SDUICache(folder: base.appendingPathComponent("sdui", isDirectory: true)
            .appendingPathComponent(fileName("\(server)|\(user)"), isDirectory: true))
    }

    /// A file name that says nothing of the key and can't leave the folder: FNV-1a over its bytes, twice seeded.
    static func fileName(_ key: String) -> String {
        func hash(_ seed: UInt64) -> UInt64 {
            var h = seed
            for byte in key.utf8 {
                h ^= UInt64(byte)
                h = h &* 0x100000001b3
            }
            return h
        }
        func hex(_ value: UInt64) -> String {
            let text = String(value, radix: 16)
            return String(repeating: "0", count: 16 - text.count) + text
        }
        return hex(hash(0xcbf29ce484222325)) + hex(hash(0x84222325cbf29ce4))
    }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(SDUICache.fileName(key) + ".json") }

    private struct Stored: Codable {
        let key: String
        let etag: String
        let body: Data
    }

    public func read(_ key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        let url = file(key)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.intValue <= maxBytes * 2,
              let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.key == key else { return nil }
        let saved = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        return Entry(etag: stored.etag, body: stored.body, saved: saved)
    }

    public func write(_ key: String, etag: String, body: Data) {
        guard body.count <= maxBytes else { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(Stored(key: key, etag: etag, body: body)).write(to: file(key), options: .atomic)
            prune()
        } catch {
            // A cache that can't be written is only slower.
        }
    }

    public func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file(key))
    }

    /// Signing out, or a change of who's watching, takes it all.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: folder)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }.count
    }

    private func prune() {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path), names.count > maxEntries else { return }
        let dated = names.map { name -> (URL, Date) in
            let url = folder.appendingPathComponent(name)
            return (url, ((try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0))
        }.sorted { $0.1 < $1.1 }
        for (url, _) in dated.prefix(names.count - maxEntries) { try? files.removeItem(at: url) }
    }
}
