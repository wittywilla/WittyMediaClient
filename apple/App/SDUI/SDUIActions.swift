// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// What activating something on a server-driven page does in this app. Where it leads is the catalogue's
/// to say (WittyKit's `SDUIRouter`); this turns that into the app's own navigation, player and screens.
@MainActor
struct SDUIActor {
    let model: AppModel
    let center: SDUICenter
    let store: SDUIPageStore?

    /// The app's own screens this device has. A button for one it lacks isn't drawn: Apple TV has no browser,
    /// no downloads, no reader and no share sheet, and nothing pretends otherwise.
    static func has(native screen: String) -> Bool {
        switch screen {
        case "settings", "profiles", "guide", "player", "livePlayer", "game", "nowPlaying", "pair", "collections":
            return true
        case "downloads", "remote", "reader", "download", "share", "playOn", "watchParty":
            #if os(iOS) || os(visionOS)
            return true
            #else
            return false
            #endif
        default:
            return false
        }
    }

    func destination(_ action: SDUIAction?) -> SDUIDestination { center.router.resolve(action) }

    /// Whether this app can do what an action asks. What it can't, it doesn't offer.
    func canPerform(_ action: SDUIAction?) -> Bool {
        switch destination(action) {
        case .none: return false
        case .native(let screen, _): return SDUIActor.has(native: screen)
        case .external:
            #if os(tvOS)
            return false
            #else
            return true
            #endif
        case .play(let item, _): return Int64(item) != nil
        case .command(let op, _, _): return center.catalog.command(op) != nil
        default: return true
        }
    }

    func perform(_ action: SDUIAction?) {
        go(destination(action))
    }

    func open(route: String) {
        go(center.router.resolve(route: route), route: route)
    }

    func open(_ entry: SDUINavItem) {
        go(center.router.resolve(entry), route: entry.route)
    }

    private func push(_ route: Route) { model.path.append(route) }

    private func webPage(_ path: String) {
        #if os(iOS) || os(visionOS)
        push(.page(path))
        #endif
    }

    func go(_ destination: SDUIDestination, route: String? = nil) {
        switch destination {
        case .page(let page, let params):
            if page == "home", params.isEmpty {
                model.paths[.home] = []
                model.tab = .home
            } else {
                push(.sdui(SDUIPlace(page: page, params: params, route: route)))
            }
        case .native(let screen, let params):
            native(screen, params)
        case .external(let url):
            #if os(iOS) || os(visionOS)
            UIApplication.shared.open(url)
            #endif
        case .play(let item, let resume):
            play(item, resume: resume)
        case .command(let op, let item, let params):
            command(op, item: item, params: params)
        case .back:
            if !model.path.isEmpty { model.path.removeLast() }
        case .none:
            break
        }
    }

    private func native(_ screen: String, _ params: [String: String]) {
        let item = params["item"].flatMap { Int64($0) }
        switch screen {
        case "settings", "profiles":
            // This app's Settings are its You screen, as they always were.
            model.paths[.profile] = []
            model.tab = .profile
        case "guide":
            #if os(tvOS)
            push((params["route"] ?? "").hasSuffix("/recordings") ? .recordings : .guide)
            #else
            push((params["route"] ?? "").hasSuffix("/recordings") ? .recordings : .page(ServerPages.guide))
            #endif
        case "player":
            if let item { push(.player(item, startOver: false)) }
        case "livePlayer":
            guard let key = params["key"], !key.isEmpty else { return }
            #if os(tvOS)
            push(.channel(key: key))
            #else
            webPage(params["route"] ?? ServerPages.guide)
            #endif
        case "game":
            if let item { push(.game(item)) }
        case "reader":
            if let item { webPage("/read/\(item)") }
        case "nowPlaying":
            if model.listening.now != nil { model.listening.screenShown = true }
        case "pair":
            push(.signInTv)
        case "collections":
            push(.sdui(SDUIPlace(page: "collections", route: ServerPages.collections)))
        case "downloads":
            webPage("/downloads")
        case "remote":
            webPage("/remote")
        case "share":
            share()
        case "download", "playOn", "watchParty":
            // The server's own page for the title has these, as it has for every title this app shows.
            if let route = store?.document?.page.route { webPage(route) }
        default:
            break
        }
    }

    /// The system's share sheet with the page's address on the server.
    private func share() {
        #if os(iOS)
        guard let route = store?.document?.page.route, let url = model.client.mediaURL(route),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let over = top.presentedViewController { top = over }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // An iPad shows it as a popover, which needs somewhere to point.
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        top.present(sheet, animated: true)
        #endif
    }

    /// Plays an item with the app's own player: a film or an episode on the player's screen, a song or a chapter
    /// from its album, and anything else where the app opens that kind of thing.
    private func play(_ text: String, resume: Bool) {
        guard let id = Int64(text) else { return }
        let model = model, center = center
        Task {
            do {
                let item = try await center.client.item(id)
                switch OpenLook.action(item) {
                case .listen:
                    model.playTrack(item)
                case .player(let startOver):
                    model.path.append(.player(id, startOver: startOver || !resume))
                case .item:
                    model.path.append(.sdui(SDUIPlace(page: "detail", params: ["item": String(id)], route: "/item/\(id)")))
                case .page(let path):
                    if case .native("game", _) = center.router.resolve(route: path) {
                        model.path.append(.game(id))
                    } else {
                        model.path.append(.page(path))
                    }
                }
            } catch {
                let words = model.handle(error)
                if !words.isEmpty { model.notice = words }
            }
        }
    }

    private func command(_ op: String, item: String, params: [String: String]) {
        let center = center, store = store, model = model
        Task {
            switch op {
            case "selectTab":
                if let tab = params["tab"], !tab.isEmpty { await store?.set(["tab": tab], center: center) }
            case "refresh":
                await store?.refresh(center)
            case "control.open":
                // The page opens the control itself (SDUIControls.swift).
                if let control = params["control"], !control.isEmpty { store?.control = SDUIControlRequest(control: control, target: params["target"] ?? "") }
            default:
                do {
                    guard try await center.client.sduiCommand(center.catalog.command(op), item: item) else { return }
                    // Then the page is asked for again, and any other page showing the same thing.
                    await store?.refresh(center)
                    center.changed()
                } catch {
                    let words = model.handle(error)
                    if !words.isEmpty { model.notice = words }
                }
            }
        }
    }
}

extension AppModel {
    /// A route from outside the app (the Top Shelf): the page or the player it names, on Home's stack.
    func openFromOutside(route: String) {
        switch SDUIRouter().resolve(route: route) {
        case .page(let page, let params):
            paths[.home] = page == "home" ? [] : [.sdui(SDUIPlace(page: page, params: params, route: route))]
        case .native("player", let params):
            if let item = params["item"].flatMap({ Int64($0) }) { paths[.home] = [.player(item, startOver: false)] }
        default:
            break
        }
    }
}
