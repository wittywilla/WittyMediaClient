import Foundation

/// The one thing that can come from outside the app: `wittymedia://item/123`, from the Top Shelf.
/// It holds a number and nothing else, so no query, no token and no other address can
/// arrive this way. It only ever chooses a screen, and that screen still needs a sign-in.
public enum DeepLink: Equatable, Hashable {
    case item(Int64)
    case show(Int64)

    public static let scheme = "wittymedia"

    public static func parse(_ url: URL) -> DeepLink? {
        let text = url.absoluteString
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
        }
    }
}
