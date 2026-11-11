// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Where a route or an action leads: a server-driven page with its parameters, one of the app's own screens,
/// a web page for the system's browser, a command, or nothing.
public enum SDUIDestination: Equatable, Hashable, Sendable {
    /// `GET /sdui/pages/{page}` with these query parameters.
    case page(String, params: [String: String])
    /// One of the app's own screens, by the catalogue's name for it, with what the route or action gave it.
    case native(String, params: [String: String])
    case external(URL)
    /// Play an item with the app's own player; `resume` false starts over.
    case play(item: String, resume: Bool)
    case command(op: String, item: String, params: [String: String])
    case back
    /// An action or a route this app can't follow: it does nothing.
    case none
}

/// The one router a renderer needs: the catalogue's routes table decides what shows each place in the app
/// (the server's docs/SDUI.md, "Routes"). No screen is chosen by anything written here.
public struct SDUIRouter: Equatable, Sendable {
    public var rules: [SDUIRouteRule]

    public init(rules: [SDUIRouteRule] = SDUICatalog.builtIn.routes) {
        self.rules = rules.isEmpty ? SDUICatalog.builtIn.routes : rules
    }

    /// A route in the app, with or without a query: `/library/3?genre=Drama`. The query's own parameters go to a
    /// page as they are (a library page's filters), with the rule's on top.
    public func resolve(route: String) -> SDUIDestination {
        guard route.hasPrefix("/"), !route.hasPrefix("//"), route.utf8.count <= 2048 else { return .none }
        let (path, query) = SDUIRouter.split(route)
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        for rule in rules {
            guard let found = SDUIRouter.match(rule.pattern, parts) else { continue }
            var params: [String: String] = [:]
            if rule.page != nil { params = query }
            for (name, source) in rule.params ?? [:] {
                if source.hasPrefix("{"), source.hasSuffix("}") {
                    params[name] = found[String(source.dropFirst().dropLast())]
                } else if source.hasPrefix("?") {
                    params[name] = query[String(source.dropFirst())]
                } else {
                    params[name] = source
                }
            }
            if var page = rule.page {
                if page.hasPrefix("{"), page.hasSuffix("}") { page = found[String(page.dropFirst().dropLast())] ?? "" }
                guard SDUIRouter.isPageName(page) else { return .none }
                return .page(page, params: params)
            }
            if let native = rule.native {
                // An app's own screen gets everything the route named: the item to play, the channel's key, and
                // the route itself, for a screen that shows more than one place (the guide and its recordings).
                var all = found.merging(params) { _, new in new }
                all["route"] = path
                return .native(native, params: all)
            }
        }
        return .none
    }

    /// What an action does. Types this app doesn't know do nothing.
    public func resolve(_ action: SDUIAction?) -> SDUIDestination {
        guard let action else { return .none }
        switch action.type {
        case "navigate":
            return resolve(route: action.to ?? "")
        case "play":
            guard let item = action.item, !item.isEmpty else { return .none }
            return .play(item: item, resume: action.params?["resume"]?.bool != false)
        case "native":
            guard let screen = action.to, !screen.isEmpty else { return .none }
            return .native(screen, params: SDUIRouter.texts(action.params))
        case "external":
            guard let text = action.url, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .none }
            return .external(url)
        case "back":
            return .back
        case "command":
            guard let op = action.op, !op.isEmpty else { return .none }
            return .command(op: op, item: action.item ?? "", params: SDUIRouter.texts(action.params))
        default:
            return .none
        }
    }

    /// A navigation entry: its page with its parameters, the app's own screen, or its route.
    public func resolve(_ entry: SDUINavItem) -> SDUIDestination {
        switch entry.kind {
        case "page":
            if let page = entry.page, SDUIRouter.isPageName(page) { return .page(page, params: entry.params ?? [:]) }
        case "native":
            if let screen = entry.screen, !screen.isEmpty { return .native(screen, params: entry.params ?? [:]) }
        default:
            break
        }
        return resolve(route: entry.route ?? "")
    }

    /// The request a command makes, from the catalogue: method, path under the server and body, with the item filled in.
    /// Nil for the commands that only ask for the page again (`selectTab`, `refresh`) and for ones this app doesn't know.
    public static func request(for command: SDUICommand?, item: String) -> (method: String, path: String, body: Data?)? {
        guard let command, let method = command.method, let path = command.path, !method.isEmpty, path.hasPrefix("/api/") else { return nil }
        // An item's ID goes into a path and a JSON body: only what an ID is made of may.
        guard !item.isEmpty, item.count <= 128, item.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_.:-~".contains($0)) }) else { return nil }
        let number = Int64(item)
        let inBody = number.map(String.init) ?? "\"\(item)\""
        let body = command.body.map { $0.replacingOccurrences(of: "{item}", with: inBody) }
        return (method.uppercased(), path.replacingOccurrences(of: "{item}", with: item), body.flatMap { $0.data(using: .utf8) })
    }

    static func isPageName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
    }

    static func texts(_ props: SDUIProps?) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in props ?? [:] {
            if let text = value.string { out[key] = text } else if let n = value.int { out[key] = String(n) } else if let b = value.bool { out[key] = b ? "true" : "false" }
        }
        return out
    }

    /// A route's path and its query's parameters. Go's `+` for a space is read as one.
    static func split(_ route: String) -> (path: String, query: [String: String]) {
        guard let mark = route.firstIndex(of: "?") else { return (route, [:]) }
        var query: [String: String] = [:]
        for pair in route[route.index(after: mark)...].split(separator: "&") {
            let sides = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            func plain(_ text: Substring) -> String {
                let spaced = text.replacingOccurrences(of: "+", with: " ")
                return spaced.removingPercentEncoding ?? spaced
            }
            guard let name = sides.first.map(plain), !name.isEmpty else { continue }
            query[name] = sides.count > 1 ? plain(sides[1]) : ""
        }
        return (String(route[..<mark]), query)
    }

    /// The pattern's `{names}` with what they matched, or nil when the path isn't this pattern's.
    static func match(_ pattern: String, _ parts: [String]) -> [String: String]? {
        let wanted = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard wanted.count == parts.count else { return nil }
        var found: [String: String] = [:]
        for (want, part) in zip(wanted, parts) {
            if want.hasPrefix("{"), want.hasSuffix("}") {
                found[String(want.dropFirst().dropLast())] = part
            } else if want != part {
                return nil
            }
        }
        return found
    }
}
