// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// A profile's own arrangement of a page or of the main menu, as it's stored and as it's sent:
/// the server's docs/SDUI.md, "Personalisation".
public struct SDUIPersonal: Codable, Equatable, Sendable {
    public var order: [String]?
    public var hidden: [String]?
    public var pinned: [String]?
    public var density: String?
    public var cardSize: [String: String]?
    public var defaultTab: [String: String]?

    public init(order: [String]? = nil, hidden: [String]? = nil, pinned: [String]? = nil, density: String? = nil,
                cardSize: [String: String]? = nil, defaultTab: [String: String]? = nil) {
        self.order = order
        self.hidden = hidden
        self.pinned = pinned
        self.density = density
        self.cardSize = cardSize
        self.defaultTab = defaultTab
    }

    public var isEmpty: Bool {
        (order ?? []).isEmpty && (hidden ?? []).isEmpty && (pinned ?? []).isEmpty && (density ?? "").isEmpty
            && (cardSize ?? [:]).isEmpty && (defaultTab ?? [:]).isEmpty
    }
}

/// What the Top Shelf shows: `GET /sdui/topshelf`.
public struct SDUITopShelf: Codable, Equatable, Sendable {
    public struct Picture: Codable, Equatable, Sendable {
        public var url: String?
        public var width: Int?
        public var height: Int?
        public var aspect: String?
    }

    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        public var title: String?
        public var shape: String?
        public var progress: Double?
        public var image: Picture?
        public var displayRoute: String?
        public var playRoute: String?
    }

    public struct Section: Codable, Equatable, Sendable {
        public var title: String?
        public var items: [Item]?
    }

    public var version: Int?
    public var style: String?
    public var expiresInSec: Int?
    public var sections: [Section]?
}

/// An answer that may be "what you have is current".
public enum SDUIFresh<T: Sendable>: Sendable {
    case same
    case new(T, etag: String, body: Data)
}

public extension WittyClient {
    private func sduiGet(_ path: String, etag: String?) async throws -> Answer {
        var headers: [String: String] = [:]
        if let etag, !etag.isEmpty { headers["If-None-Match"] = etag }
        return try await send("GET", path, headers: headers)
    }

    private func fresh<T: Decodable & Sendable>(_ answer: Answer, _ type: T.Type, etag: (T) -> String?) throws -> SDUIFresh<T> {
        if answer.status == 304 { return .same }
        let value = try JSONDecoder().decode(T.self, from: answer.data)
        return .new(value, etag: answer.header("ETag") ?? etag(value) ?? "", body: answer.data)
    }

    /// A page, rendered for this profile and device. `page` is a kind or one page's ID.
    func sduiPage(_ page: String, params: [String: String], device: SDUIDevice, etag: String? = nil) async throws -> SDUIFresh<SDUIDocument> {
        guard SDUIRouter.isPageName(page) else { throw APIError(status: 404, message: "This isn't available.") }
        let answer = try await sduiGet("/sdui/pages/\(page)?" + SDUIQuery.page(params, device), etag: etag)
        return try fresh(answer, SDUIDocument.self) { $0.meta?.etag }
    }

    /// Patches from the render this app has, or the whole page; `.same` when what it has is current.
    func sduiDiff(_ page: String, params: [String: String], device: SDUIDevice, since: String) async throws -> SDUIFresh<SDUIDiffAnswer> {
        guard SDUIRouter.isPageName(page) else { throw APIError(status: 404, message: "This isn't available.") }
        var all = params
        all["since"] = since
        let answer = try await send("GET", "/sdui/pages/\(page)/diff?" + SDUIQuery.page(all, device), headers: ["If-None-Match": since])
        return try fresh(answer, SDUIDiffAnswer.self) { $0.etag }
    }

    /// A page of a section's items, from an address a page gave (`props.more.url`, a season's own).
    func sduiItems(url: String, device: SDUIDevice) async throws -> SDUISectionItems {
        guard let path = SDUIQuery.path(fromServer: url, device: device) else { throw APIError(status: 0, message: "That can't be asked for.") }
        return try JSONDecoder().decode(SDUISectionItems.self, from: try await call("GET", path))
    }

    func sduiNavigation(device: SDUIDevice, etag: String? = nil) async throws -> SDUIFresh<SDUINavigation> {
        try fresh(try await sduiGet("/sdui/navigation?" + SDUIQuery.encode(device.query), etag: etag), SDUINavigation.self) { $0.etag }
    }

    func sduiCatalog(etag: String? = nil) async throws -> SDUIFresh<SDUICatalog> {
        try fresh(try await sduiGet("/sdui/catalog", etag: etag), SDUICatalog.self) { _ in nil }
    }

    /// The profile's own arrangement of a page (`page` nil: of the main menu), as stored.
    func sduiPersonal(page: String?) async throws -> SDUIPersonal {
        try JSONDecoder().decode(SDUIPersonal.self, from: try await call("GET", try personalPath(page)))
    }

    /// Stores it. A 403 means the profile may not rearrange: the `editLayout` switch is off.
    func setSDUIPersonal(_ personal: SDUIPersonal, page: String?) async throws {
        _ = try await call("PUT", try personalPath(page), body: try JSONEncoder().encode(personal))
    }

    /// Back to the page as everyone has it.
    func resetSDUIPersonal(page: String?) async throws {
        _ = try await call("DELETE", try personalPath(page))
    }

    private func personalPath(_ page: String?) throws -> String {
        guard let page else { return "/sdui/navigation/personal" }
        guard SDUIRouter.isPageName(page) else { throw APIError(status: 404, message: "This isn't available.") }
        return "/sdui/pages/\(page)/personal"
    }

    func sduiTopShelf(deviceClass: String, etag: String? = nil) async throws -> SDUIFresh<SDUITopShelf> {
        let query = SDUIQuery.encode([("catalog", String(SDUI.catalog)), ("platform", "tvos"), ("deviceClass", deviceClass)])
        return try fresh(try await sduiGet("/sdui/topshelf?" + query, etag: etag), SDUITopShelf.self) { _ in nil }
    }

    /// Carries out one of the catalogue's commands that is a request (`watchLater.add`, `watched.set`, `watched.clear`).
    /// False for the ones that only ask for the page again, and for one the catalogue doesn't have.
    @discardableResult
    func sduiCommand(_ command: SDUICommand?, item: String, params: [String: String] = [:]) async throws -> Bool {
        guard let request = SDUIRouter.request(for: command, item: item, params: params) else { return false }
        // The catalogue writes the path from the server's root; this app's requests start under its API.
        let path: String
        if request.path.hasPrefix("/api/v1/") {
            path = String(request.path.dropFirst("/api/v1".count))
        } else {
            path = String(request.path.dropFirst("/api".count))
        }
        guard !path.contains(".."), !path.contains("?"), !path.contains("#") else { return false }
        _ = try await call(request.method, path, body: request.body)
        return true
    }
}

/// A page as the app got it: from the server just now, or the last good one kept on disk.
public struct SDUILoaded: Equatable, Sendable {
    public var document: SDUIDocument
    public var etag: String
    /// The server couldn't be reached and this is the page from before.
    public var offline: Bool
}

/// Gets pages through the cache: `If-None-Match` with what's kept, the kept page when the network is down,
/// and the diff route for asking again.
public struct SDUIPageLoader: Sendable {
    public let client: WittyClient
    public let cache: SDUICache?
    /// The server has `sdui-diff`.
    public var diffs: Bool

    public init(client: WittyClient, cache: SDUICache?, diffs: Bool = true) {
        self.client = client
        self.cache = cache
        self.diffs = diffs
    }

    public static func key(_ page: String, _ params: [String: String], _ device: SDUIDevice) -> String {
        "page|\(page)|" + params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&") + "|" + device.cacheName
    }

    /// The page kept from before, if any, without asking: something to draw at once while the real answer comes.
    public func kept(_ page: String, params: [String: String], device: SDUIDevice) -> SDUILoaded? {
        guard let entry = cache?.read(SDUIPageLoader.key(page, params, device)),
              let document = try? JSONDecoder().decode(SDUIDocument.self, from: entry.body) else { return nil }
        return SDUILoaded(document: document, etag: entry.etag, offline: false)
    }

    /// The refusal of a page written for another catalogue revision.
    public static let otherRevision = APIError(status: 426, message: "This server's pages are for another version of this app. Update the app or the server.",
                                               code: "sdui-revision")

    public func load(_ page: String, params: [String: String], device: SDUIDevice) async throws -> SDUILoaded {
        let loaded = try await loadAny(page, params: params, device: device)
        guard SDUI.accepts(loaded.document) else {
            cache?.remove(SDUIPageLoader.key(page, params, device))
            throw SDUIPageLoader.otherRevision
        }
        return loaded
    }

    private func loadAny(_ page: String, params: [String: String], device: SDUIDevice) async throws -> SDUILoaded {
        let key = SDUIPageLoader.key(page, params, device)
        let before = kept(page, params: params, device: device)
        do {
            switch try await client.sduiPage(page, params: params, device: device, etag: before?.etag) {
            case .same:
                if let before { return before }
                // The server said "the same" to an app with nothing: ask plainly.
                guard case .new(let document, let etag, let body) = try await client.sduiPage(page, params: params, device: device) else {
                    throw APIError(status: 0, message: "The server sent an answer that can't be read.")
                }
                cache?.write(key, etag: etag, body: body)
                return SDUILoaded(document: document, etag: etag, offline: false)
            case .new(let document, let etag, let body):
                cache?.write(key, etag: etag, body: body)
                return SDUILoaded(document: document, etag: etag, offline: false)
            }
        } catch let error as APIError where error.status != 0 {
            // The server answered, with a no: what was kept is no longer this profile's to see.
            if [401, 403, 404].contains(error.status) { cache?.remove(key) }
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw error }
            // No answer at all: the last good page, said to be from before.
            if var before {
                before.offline = true
                return before
            }
            throw error
        }
    }

    /// Asks again for a page the app is showing: nothing when it's current, patches applied to it, or the whole page.
    /// Sections the app filled in itself since (pages of items, deferred rows) are kept only by a full reload's
    /// own paging, so `current` must be the document as the server last sent it.
    public func refresh(_ page: String, params: [String: String], device: SDUIDevice, current: SDUILoaded) async throws -> SDUILoaded {
        guard diffs, !current.etag.isEmpty, !current.offline else { return try await load(page, params: params, device: device) }
        let key = SDUIPageLoader.key(page, params, device)
        let answer: SDUIFresh<SDUIDiffAnswer>
        do {
            answer = try await client.sduiDiff(page, params: params, device: device, since: current.etag)
        } catch let error as APIError where error.status == 404 {
            // The page has gone: asking for it again says so in the page's own way.
            return try await load(page, params: params, device: device)
        }
        switch answer {
        case .same:
            return current
        case .new(let diff, let etag, _):
            if let whole = diff.document {
                guard SDUI.accepts(whole) else { throw SDUIPageLoader.otherRevision }
                keep(whole, etag: etag, key: key)
                return SDUILoaded(document: whole, etag: etag, offline: false)
            }
            // If any step fails, drop the tree and ask for the page.
            guard let patches = diff.patches, var patched = try? current.document.applying(patches) else {
                return try await load(page, params: params, device: device)
            }
            if patched.meta == nil { patched.meta = SDUIMeta() }
            patched.meta?.etag = etag
            keep(patched, etag: etag, key: key)
            return SDUILoaded(document: patched, etag: etag, offline: false)
        }
    }

    private func keep(_ document: SDUIDocument, etag: String, key: String) {
        guard let body = try? JSONEncoder().encode(document) else { return }
        cache?.write(key, etag: etag, body: body)
    }
}
