// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// The one thing that can come from outside the app: `wittymedia://item/123`, from the Top Shelf.
/// It holds a number and nothing else, so no query, no token and no other address can
/// arrive this way. It only ever chooses a screen, and that screen still needs a sign-in.
public enum DeepLink: Equatable, Hashable {
    case item(Int64)
    case show(Int64)
    /// A place in the app by its route, from a server-driven Top Shelf: `/album/5?artist=…`, `/watch/12`. Only a
    /// route the catalogue's table knows is one: a server-driven page, or the player for one item.
    case route(String)

    public static let scheme = "wittymedia"

    public static func parse(_ url: URL) -> DeepLink? {
        let text = url.absoluteString
        if let route = routeLink(text) { return route }
        guard text.count <= 64, text.lowercased().hasPrefix(scheme + "://") else { return nil }
        let parts = text.dropFirst(scheme.count + 3).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...18).contains(parts[1].count),
              parts[1].allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int64(parts[1]), id > 0 else { return nil }
        switch parts[0] {
        case "item": return .item(id)
        case "show": return .show(id)
        default: return nil
        }
    }

    public var address: String {
        switch self {
        case .item(let id): return "\(Self.scheme)://item/\(id)"
        case .show(let id): return "\(Self.scheme)://show/\(id)"
        case .route(let route): return "\(Self.scheme)://route/" + (route.addingPercentEncoding(withAllowedCharacters: DeepLink.routeSafe) ?? "")
        }
    }
}

extension DeepLink {
    static let routeSafe: CharacterSet = {
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-._~")
        return safe
    }()

    /// `wittymedia://route/<the route, percent-encoded>`. The route must be one the routes table shows with a
    /// server-driven page or the player: a link still only chooses a screen.
    private static func routeLink(_ text: String) -> DeepLink? {
        let prefix = scheme + "://route/"
        guard text.count <= 1024, text.lowercased().hasPrefix(prefix),
              let route = String(text.dropFirst(prefix.count)).removingPercentEncoding, isOpenable(route) else { return nil }
        return .route(route)
    }

    /// Whether a route may be opened from outside the app.
    public static func isOpenable(_ route: String) -> Bool {
        guard route.count <= 512, route.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f }) else { return false }
        switch SDUIRouter().resolve(route: route) {
        case .page: return true
        case .native(let screen, let params): return screen == "player" && Int64(params["item"] ?? "") != nil
        default: return false
        }
    }
}
