// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// One server-driven page as a screen shows it: the page asked for with what it was opened with, the screen
/// built from the answer, and everything fetched for it since (rows that arrive later, further pages, another
/// season). All the deciding is WittyKit's; this only asks, keeps and publishes.
@MainActor
final class SDUIPageStore: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
        /// 404: the page, library or title isn't there, or isn't this profile's to see.
        case missing
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var screen: SDUIScreen?
    /// The server couldn't be reached and this is the page from before.
    @Published private(set) var offline = false
    /// Sections with a request in flight: they show placeholders.
    @Published private(set) var busy: Set<String> = []
    /// Asking again for a page that's already showing.
    @Published private(set) var refreshing = false

    let page: String
    private(set) var params: [String: String]
    /// The document as the server last sent it, for the diff route.
    private var served: SDUILoaded?
    private var working: SDUIDocument?
    private var loadedAt = Date.distantPast
    private var generation = 0
    private var window: Int?
    private var catalog = SDUICatalog.builtIn

    init(place: SDUIPlace) {
        page = place.page
        params = place.params
    }

    var document: SDUIDocument? { working }
    var layout: SDUILayout { working?.layout ?? .fallback }

    private func show(_ document: SDUIDocument) {
        working = document
        screen = SDUIScreen(document: document, catalog: catalog, window: window)
    }

    /// The window's width, which placeholders and a grid's columns follow between breakpoints.
    func setWindow(_ width: CGFloat) {
        let next = width >= 1 ? Int(width) : nil
        guard next != window else { return }
        window = next
        if let working, working.layout.formFactor != "tv" { show(working) }
    }

    /// The screen has come up, or come back: the first time the page is asked for, drawn at once from what was
    /// kept; after that it is asked again once it is older than the server said it stays good for.
    func appear(_ center: SDUICenter) async {
        catalog = center.catalog
        guard screen != nil, case .ready = phase else {
            await load(center)
            return
        }
        let ttl = TimeInterval(working?.meta?.ttlSeconds ?? 60)
        // A page that only changes "when something happens" is still asked on coming back to it: something may have.
        if Date().timeIntervalSince(loadedAt) >= min(max(ttl, 0), 300) || offline { await refresh(center) }
    }

    func load(_ center: SDUICenter) async {
        generation += 1
        let mine = generation
        let loader = center.loader, device = center.device
        if screen == nil, let kept = loader.kept(page, params: params, device: device) {
            // Something to look at while the real answer comes.
            show(kept.document)
            phase = .ready
        } else if screen == nil {
            phase = .loading
        }
        refreshing = screen != nil
        defer { if mine == generation { refreshing = false } }
        do {
            let loaded = try await loader.load(page, params: params, device: device)
            guard mine == generation else { return }
            accept(loaded)
        } catch {
            guard mine == generation, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            fail(error, center: center)
        }
    }

    private func accept(_ loaded: SDUILoaded) {
        let fresh = working.map { loaded.document.keepingLoaded(from: $0) } ?? loaded.document
        served = loaded
        offline = loaded.offline
        loadedAt = Date()
        if fresh != working || screen == nil { show(fresh) }
        phase = .ready
    }

    private func fail(_ error: Error, center: SDUICenter) {
        if let refusal = error as? APIError, refusal.status == 404 {
            working = nil
            screen = nil
            phase = .missing
            return
        }
        // A page already showing stays up: a failed refresh is no reason to lose it.
        if screen != nil {
            offline = true
            return
        }
        phase = .failed((error as? APIError)?.message ?? say("errLost"))
    }

    /// Asks again for the page that's showing: patches where the server still has the render this app has.
    func refresh(_ center: SDUICenter) async {
        guard let current = served, screen != nil else {
            await load(center)
            return
        }
        generation += 1
        let mine = generation
        refreshing = true
        defer { if mine == generation { refreshing = false } }
        do {
            let loaded = try await center.loader.refresh(page, params: params, device: center.device, current: current)
            guard mine == generation else { return }
            accept(loaded)
        } catch {
            guard mine == generation, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            fail(error, center: center)
        }
    }

    /// The page again with a parameter changed: a tab chosen, a filter, a sort, what's searched for. An empty
    /// value takes the parameter away. The page showing stays up until the new one arrives.
    func set(_ changes: [String: String], center: SDUICenter) async {
        var next = params
        for (name, value) in changes {
            if value.isEmpty { next[name] = nil } else { next[name] = value }
        }
        guard next != params else { return }
        params = next
        served = nil
        // Another page of results is another page: nothing fetched for the one before belongs to it.
        let before = working
        working = nil
        await load(center)
        if working == nil, let before, case .ready = phase { show(before) }
    }

    // MARK: A section's own items

    private func fetch(section: String, url: String, center: SDUICenter) async {
        guard !url.isEmpty, !busy.contains(section) else { return }
        // Never the same cursor twice at once: one request a section.
        busy.insert(section)
        defer { busy.remove(section) }
        let mine = generation
        do {
            let answer = try await center.client.sduiItems(url: url, device: center.device)
            guard mine == generation, let working else { return }
            show(working.applying(answer, to: section))
        } catch {
            guard mine == generation, let working, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            show(working.failing(section: section))
        }
    }

    /// A section that arrived waiting for its items has come within a screen of being seen.
    func fill(_ section: SDUIElement, center: SDUICenter) async {
        guard section.state == .deferred else { return }
        await fetch(section: section.id, url: section.moreURL, center: center)
    }

    /// The person has scrolled near the end of a section that has more.
    func more(_ section: SDUIElement, center: SDUICenter) async {
        guard section.hasMore else { return }
        await fetch(section: section.id, url: section.moreURL, center: center)
    }

    /// Retry on a section that couldn't be loaded.
    func retry(_ section: SDUIElement, center: SDUICenter) async {
        await fetch(section: section.id, url: section.moreURL, center: center)
    }

    /// Another season: its episodes take the place of the ones there.
    func choose(_ season: SDUISeason, in section: SDUIElement, center: SDUICenter) async {
        guard !season.selected else { return }
        await fetch(section: section.id, url: season.url, center: center)
    }
}
