import Foundation
import ImageIO
import WittyKit
#if os(tvOS)
import TVServices
import UniformTypeIdentifiers
#endif

/// Keeps the Top Shelf's small file up to date, on Apple TV. Everywhere else this does nothing.
/// The sign-in stays in this app's own Keychain: the extension gets titles, numbers and pictures, in a
/// folder only this app and its extension can reach. See apple/TopShelf/ContentProvider.swift.
enum TopShelfWriter {
    #if os(tvOS)
    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shelf.groupId)
    }

    /// One run at a time, as the home page can be loaded again while one is going.
    private static var running: Task<Void, Never>?

    @MainActor
    static func update(home: Home, client: WittyClient) {
        // No App Group means a build signed without one, and just an empty shelf.
        guard let folder = folder else { return }
        let shelf = Shelf.from(home: home)
        var pictures: [(name: String, url: URL)] = []
        for hub in home.hubs ?? [] {
            for item in hub.items ?? [] { if let url = client.posterURL(item) { pictures.append(("i\(item.id).jpg", url)) } }
            for show in hub.shows ?? [] { if let url = client.posterURL(show) { pictures.append(("s\(show.id).jpg", url)) } }
        }
        let wanted = Set(shelf.entries.compactMap(\.poster))
        running?.cancel()
        running = Task.detached(priority: .utility) {
            let posters = folder.appendingPathComponent(Shelf.posterFolder, isDirectory: true)
            let files = FileManager.default
            try? files.createDirectory(at: posters, withIntermediateDirectories: true)
            // What's no longer on the shelf goes, so this folder can't grow.
            for old in (try? files.contentsOfDirectory(atPath: posters.path)) ?? [] where !wanted.contains(old) {
                try? files.removeItem(at: posters.appendingPathComponent(old))
            }
            var done = Set<String>()
            for picture in pictures where wanted.contains(picture.name) && done.insert(picture.name).inserted {
                if Task.isCancelled { return }
                let file = posters.appendingPathComponent(picture.name)
                if files.fileExists(atPath: file.path) { continue }
                guard let data = try? await client.imageData(picture.url), let image = decodeArt(data, maxPixels: 600) else { continue }
                TopShelfWriter.write(image, to: file)
            }
            if Task.isCancelled { return }
            try? shelf.write(to: folder)
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    private static func write(_ image: CGImage, to file: URL) {
        guard let out = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(out)
    }

    @MainActor
    static func clear() {
        running?.cancel()
        guard let folder = folder else { return }
        Shelf.clear(in: folder)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
    #else
    @MainActor static func update(home: Home, client: WittyClient) {}
    @MainActor static func clear() {}
    #endif
}
