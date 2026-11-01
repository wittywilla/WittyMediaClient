import Foundation
import TVServices
import WittyKit

/// What the Apple TV shows at the top of its Home screen when this app is in the top row. It never
/// goes to the network and has no sign-in: it reads the small file the app wrote to their shared App
/// Group, and pictures saved beside it. Choosing something opens the app with a link holding a
/// number, and the app takes it from there, signing in first if it has to.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shelf.groupId) else {
            completionHandler(nil)
            return
        }
        let posters = folder.appendingPathComponent(Shelf.posterFolder, isDirectory: true)
        let sections = Shelf.read(from: folder).sections.compactMap { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? in
            let items = section.entries.compactMap { entry -> TVTopShelfSectionedItem? in
                guard let link = URL(string: entry.link) else { return nil }
                let item = TVTopShelfSectionedItem(identifier: entry.id)
                item.title = entry.subtitle.isEmpty ? entry.title : "\(entry.title) · \(entry.subtitle)"
                item.imageShape = .poster
                item.displayAction = TVTopShelfAction(url: link)
                if let poster = entry.poster {
                    let file = posters.appendingPathComponent(poster)
                    if FileManager.default.fileExists(atPath: file.path) { item.setImageURL(file, for: [.screenScale1x, .screenScale2x]) }
                }
                return item
            }
            guard !items.isEmpty else { return nil }
            let collection = TVTopShelfItemCollection(items: items)
            collection.title = section.title
            return collection
        }
        completionHandler(sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections))
    }
}
