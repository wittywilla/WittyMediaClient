// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// A server-driven page and what it was opened with: `GET /sdui/pages/{page}` with these parameters.
struct SDUIPlace: Hashable {
    var page: String
    var params: [String: String] = [:]
    /// The place in the app it is, when it was opened by one: what marks it in the menus.
    var route: String?

    static let home = SDUIPlace(page: "home", route: "/")
}

/// Server-driven pages for the person signed in to this server: whether the server has them, the main menu,
/// the catalogue's routes, the device as the server is told about it, and the cache on disk. One for each
/// server and person; made by the shell, which is made again when either changes.
@MainActor
final class SDUICenter: ObservableObject {
    enum Mode: Equatable {
        /// The server hasn't said yet what it can do, and this app has never seen it say.
        case unknown
        case on
        /// A server without the features: the app's own hand-built screens.
        case off
    }

    @Published private(set) var mode: Mode = .unknown
    @Published private(set) var navigation: SDUINavigation?
    @Published private(set) var catalog = SDUICatalog.builtIn
    @Published private(set) var device: SDUIDevice
    /// Goes up when something a page shows has changed underneath it: a command was carried out, a page was
    /// rearranged. Pages that are showing ask again.
    @Published private(set) var changes = 0
    /// Goes up when a tab's first page has its first look: Apple TV's bar then hands focus to it.
    @Published private(set) var settles = 0
    /// Goes up when the window crosses a breakpoint: pages that are showing ask again with the new window.
    @Published private(set) var epoch = 0
    private(set) var client = WittyClient(base: "")
    private(set) var cache: SDUICache?
    private(set) var features: Set<String> = []
    private var owner = ""

    init() {
        device = SDUICenter.deviceNow(window: nil)
    }

    var enabled: Bool { mode == .on }
    var router: SDUIRouter { SDUIRouter(rules: catalog.routes) }
    var loader: SDUIPageLoader { SDUIPageLoader(client: client, cache: cache, diffs: features.contains("sdui-diff")) }

    /// The app's own views a page's `NativeView` may name. Both kinds of device have the guide; neither has a
    /// photo timeline, a photo map or a cover flow of its own, so those arrive as the sections inside them.
    static let nativeViews = ["guide"]

    static func deviceNow(window: CGSize?) -> SDUIDevice {
        var device = deviceKind(window: window)
        device.appId = appId
        return device
    }

    /// This installation's own name with the server, made up once: a profile's layout is kept for it.
    static var appId: String {
        let key = "sdui.deviceId"
        if let kept = UserDefaults.standard.string(forKey: key), SDUIDevice.isAppId(kept) { return kept }
        #if os(tvOS)
        let made = SDUIDevice.newAppId(platform: "tv")
        #else
        let made = SDUIDevice.newAppId(platform: UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone")
        #endif
        UserDefaults.standard.set(made, forKey: key)
        return made
    }

    private static func deviceKind(window: CGSize?) -> SDUIDevice {
        let locale = Locale.preferredLanguages.first
        #if os(tvOS)
        // The screen's own pixels: 3840 across on an Apple TV 4K showing 4K, 1920 on an Apple TV HD or a 4K set to 1080p.
        return .appleTV(pixelsWide: Int(UIScreen.main.nativeBounds.width), reducedMotion: UIAccessibility.isReduceMotionEnabled,
                        locale: locale, views: nativeViews)
        #elseif os(iOS)
        let size = window ?? UIScreen.main.bounds.size
        return .touch(pad: UIDevice.current.userInterfaceIdiom == .pad, width: size.width, height: size.height,
                      reducedMotion: UIAccessibility.isReduceMotionEnabled, locale: locale, views: nativeViews)
        #else
        let size = window ?? CGSize(width: 1280, height: 720)
        return .touch(pad: true, width: size.width, height: size.height, reducedMotion: UIAccessibility.isReduceMotionEnabled,
                      locale: locale, views: nativeViews)
        #endif
    }

    /// The window changed size, or the person's motion setting did: what the server is told follows.
    func windowChanged(_ size: CGSize) {
        guard size.width >= 1, size.height >= 1 else { return }
        let next = SDUICenter.deviceNow(window: size)
        guard next != device else { return }
        let reload = next.needsNewPage(after: device)
        device = next
        guard reload else { return }
        // A breakpoint was crossed: pages and the menu are asked for again with the new window.
        epoch += 1
        if enabled { Task { await loadMenu() } }
    }

    private static func rememberedKey(_ base: String) -> String { "sdui.available|\(base)" }

    /// Called whenever the connection, the person or what the server can do changes.
    func configure(client: WittyClient, user: Int64, features: Set<String>, known: Bool) {
        let who = "\(client.base)|\(user)|\(client.token.hashValue)"
        if who != owner {
            owner = who
            self.client = client
            cache = client.base.isEmpty ? nil : SDUICache.standard(server: client.base, user: user)
            navigation = nil
            catalog = .builtIn
        }
        self.features = features
        let defaults = UserDefaults.standard
        let next: Mode
        if known {
            next = SDUI.available(features) ? .on : .off
            defaults.set(next == .on, forKey: SDUICenter.rememberedKey(client.base))
        } else if let before = defaults.object(forKey: SDUICenter.rememberedKey(client.base)) as? Bool {
            // What this server could do last time, until it says again: the first screen is drawn at once.
            next = before ? .on : .off
        } else {
            next = .unknown
        }
        guard next != mode || navigation == nil else { return }
        mode = next
        if next == .on {
            restoreMenu()
            Task { await loadMenu() }
        }
    }

    private var menuKey: String { "navigation|" + device.cacheName }

    /// The menu and the catalogue kept from before, so the bar is there before the server answers and without it.
    private func restoreMenu() {
        if navigation == nil, let kept = cache?.read(menuKey), let menu = try? JSONDecoder().decode(SDUINavigation.self, from: kept.body) {
            navigation = menu
        }
        if let kept = cache?.read("catalog"), let known = try? JSONDecoder().decode(SDUICatalog.self, from: kept.body) {
            catalog = known
        }
    }

    /// The layout option this profile chose for this device, or nil to follow the server's. The menu and every page
    /// showing are asked for again, so the whole app takes the new layout.
    func chooseLayout(_ layout: String?) async throws {
        try await client.setSDUILayout(layout, device: device)
        await loadMenu()
        epoch += 1
    }

    /// The app's frame as the server's navigation says it, where it says one.
    var shell: SDUIShell? { enabled ? navigation?.shell : nil }

    func loadMenu() async {
        let asking = client, key = menuKey, device = device
        async let menu = try? asking.sduiNavigation(device: device, etag: navigation == nil ? nil : cache?.read(key)?.etag)
        async let known = try? asking.sduiCatalog(etag: cache?.read("catalog")?.etag)
        let (freshMenu, freshCatalog) = await (menu, known)
        guard asking === client else { return }
        if case .new(let value, let etag, let body)? = freshMenu {
            cache?.write(key, etag: etag, body: body)
            if value != navigation { navigation = value }
        }
        if case .new(let value, let etag, let body)? = freshCatalog {
            cache?.write("catalog", etag: etag, body: body)
            if value != catalog { catalog = value }
        }
    }

    /// Something a page shows has changed underneath it.
    func changed() { changes += 1 }

    func settled() { settles += 1 }

    /// The menu's entries this app can open: a page, or one of the app's own screens that this device has.
    var items: [SDUINavItem] {
        (navigation?.items ?? []).filter { entry in
            switch router.resolve(entry) {
            case .page: return true
            case .native(let screen, _): return SDUIActor.has(native: screen) && !["player", "livePlayer", "game", "reader", "share", "download", "playOn", "watchParty"].contains(screen)
            default: return false
            }
        }
    }

    /// Signing out takes what was kept.
    func forget() {
        cache?.clear()
        navigation = nil
    }

    // MARK: The menu

    private func isYou(_ entry: SDUINavItem) -> Bool {
        if case .native(let screen, _) = router.resolve(entry) { return screen == "profiles" || screen == "settings" }
        return false
    }

    /// This app's Settings are its You screen, so the menu's You and Settings are one place here. The entry that
    /// stands for it in a bar: You where the menu has it, else Settings, which is always there.
    var youEntry: SDUINavItem? {
        let all = items
        return all.first { $0.kind == "native" && $0.screen == "profiles" } ?? all.first(where: \.isSettings)
    }

    private func entries(_ placements: [String], withYou: Bool) -> [SDUINavItem] {
        items.filter { placements.contains($0.placement ?? "primary") && (withYou || !isYou($0)) }
    }

    /// A phone's and a tablet's bar: the primary entries, but You, which has its own place at the bar's end.
    var barEntries: [SDUINavItem] { entries(["primary"], withYou: false) }
    /// Behind Menu: everything else. Settings is among them, wherever the server put it.
    var moreEntries: [SDUINavItem] {
        items.filter { entry in
            let placement = entry.placement ?? "primary"
            if placement == "primary" { return false }
            // You is in the bar already; Settings is listed, and opens the same screen.
            return entry.id != youEntry?.id || placement == "more"
        }
    }
    /// Apple TV's top menu: every entry but You and Settings in the row that scrolls, in the server's order.
    var topMenuEntries: [SDUINavItem] { entries(["primary", "more", "end"], withYou: false) }

    func entry(_ id: String) -> SDUINavItem? { items.first { $0.id == id } }

    /// The tab an entry is: Home, Search and You keep the tabs they always had; any other entry is a tab of its own.
    func tab(for entry: SDUINavItem) -> AppTab {
        switch router.resolve(entry) {
        case .page("home", let params) where params.isEmpty: return .home
        case .page("search", _): return .search
        case .native("profiles", _), .native("settings", _): return .profile
        default: return .sdui(entry.id)
        }
    }

    /// The tabs a phone or a tablet keeps a stack for. Home's is always there: pages opened from the menu go on it.
    var phoneTabs: [AppTab] {
        var tabs: [AppTab] = [.home]
        for entry in barEntries {
            let tab = tab(for: entry)
            if !tabs.contains(tab) { tabs.append(tab) }
        }
        if !tabs.contains(.profile) { tabs.append(.profile) }
        return tabs
    }

    /// The server-driven page a place in the menus is, if it is one.
    func place(for entry: SDUINavItem) -> SDUIPlace? {
        if case .page(let page, let params) = router.resolve(entry) { return SDUIPlace(page: page, params: params, route: entry.route) }
        return nil
    }

    /// The place a route is, when a server-driven page shows it.
    func place(route: String) -> SDUIPlace? {
        if case .page(let page, let params) = router.resolve(route: route) { return SDUIPlace(page: page, params: params, route: route) }
        return nil
    }

    /// Whether a page is one of the menu's own places: it then has the menu's strip above it and no Back.
    func isTop(_ place: SDUIPlace) -> Bool {
        guard let route = place.route else { return false }
        return items.contains { $0.route == route }
    }

    /// The menu's entries as the strip and the drawer on a phone and a tablet list their places.
    func navPlaces(_ entries: [SDUINavItem]) -> [NavPlace] {
        entries.map { NavPlace(id: $0.id, label: PlainWords.clean($0.label, limit: 60), path: $0.route ?? "", kind: "sdui:" + ($0.icon ?? "")) }
    }

    /// A place in the strip or the drawer was chosen: its page on Home's stack, in place of what was there, as the
    /// strip changes the page in place; or the app's own screen it names.
    func open(_ place: NavPlace, model: AppModel) {
        guard let entry = entry(place.id) else { return }
        switch router.resolve(entry) {
        case .page("home", let params) where params.isEmpty:
            model.paths[.home] = []
            model.tab = .home
        case .page(let page, let params):
            var transaction = Transaction()
            transaction.disablesAnimations = model.tab == .home && (model.paths[.home]?.count ?? 0) == 1
            withTransaction(transaction) {
                model.tab = .home
                model.paths[.home] = [.sdui(SDUIPlace(page: page, params: params, route: entry.route))]
            }
        default:
            model.tab = .home
            SDUIActor(model: model, center: self, store: nil).open(entry)
        }
    }

    /// The strip along the top of a phone's and a tablet's pages: the pages behind Menu.
    var stripPlaces: [NavPlace] { navPlaces(moreEntries.filter { $0.kind != "native" }) }
}

/// The catalogue's icon names as the system's symbols. A name this app doesn't know is a plain square.
enum SDUIIcon {
    static let symbols: [String: String] = [
        "home": "house", "library": "books.vertical", "movie": "film", "show": "tv", "tv": "tv", "live": "dot.radiowaves.left.and.right",
        "guide": "calendar.day.timeline.left", "record": "record.circle", "music": "music.note", "album": "square.stack", "artist": "music.mic",
        "mic": "mic", "radio": "radio", "podcast": "antenna.radiowaves.left.and.right", "book": "book.closed", "audiobook": "headphones",
        "comic": "book", "photo": "photo", "video": "play.rectangle", "disc": "opticaldisc", "game": "gamecontroller",
        "collection": "rectangle.stack", "list": "list.bullet", "folder": "folder", "search": "magnifyingglass", "settings": "gearshape",
        "user": "person", "users": "person.2", "kids": "figure.and.child.holdinghands", "star": "star", "heart": "heart", "clock": "clock",
        "history": "clock.arrow.circlepath", "calendar": "calendar", "sparkles": "sparkles", "fire": "flame", "shuffle": "shuffle",
        "play": "play.fill", "download": "arrow.down.circle", "share": "square.and.arrow.up", "globe": "globe", "info": "info.circle",
        "warning": "exclamationmark.triangle", "check": "checkmark", "plus": "plus", "grid": "square.grid.2x2",
        "filter": "line.3.horizontal.decrease", "sort": "arrow.up.arrow.down", "plug": "powerplug", "chart": "chart.bar",
        "devices": "tv.and.mediabox", "more": "ellipsis", "restart": "arrow.counterclockwise", "watched": "checkmark.circle",
        "watchLater": "clock.badge.checkmark", "playOn": "tv.and.mediabox", "watchParty": "person.2",
    ]

    static func symbol(_ name: String?, or fallback: String = "square") -> String {
        guard let name, !name.isEmpty else { return fallback }
        return symbols[name] ?? fallback
    }

    /// The icon that stands for a kind of item where it has no picture.
    static func symbol(kind: String) -> String {
        switch kind {
        case "movie", "video": return "film"
        case "show", "episode", "season": return "tv"
        case "album", "track", "audio": return "music.note"
        case "artist", "person": return "person"
        case "book", "comic": return "book.closed"
        case "audiobook": return "headphones"
        case "podcast": return "antenna.radiowaves.left.and.right"
        case "game": return "gamecontroller"
        case "photo": return "photo"
        case "channel", "recording": return "tv"
        case "collection": return "rectangle.stack"
        case "library": return "books.vertical"
        case "genre": return "tag"
        default: return "square"
        }
    }
}
