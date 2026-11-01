import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What went wrong, in the terms a screen needs. The system's own descriptions are for logs:
/// they read like "The operation couldn't be completed. (NSURLErrorDomain error -1004.)".
public enum Problem: Equatable {
    /// Leaving a screen cancels what it asked for. Nothing to show.
    case cancelled
    /// The server no longer accepts the sign-in.
    case expiredSignIn
    /// This device has no network.
    case offline
    /// The network is there, and the server isn't answering.
    case lost
    case certificate
    /// The server's own words, which are written to be shown.
    case server(String)
    /// An answer that couldn't be read.
    case unreadable

    public static func of(_ error: Error) -> Problem {
        if error is CancellationError { return .cancelled }
        if let api = error as? APIError {
            return api.isExpiredSignIn ? .expiredSignIn : .server(api.message)
        }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled:
                return .cancelled
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .secureConnectionFailed, .clientCertificateRejected, .clientCertificateRequired:
                return .certificate
            default:
                return .lost
            }
        }
        return .unreadable
    }

    /// Whether a working network might put this right by itself.
    public var isConnection: Bool { self == .offline || self == .lost }
}

public enum PlainWords {
    /// Words from a server, kept to something a screen can show: no control characters or
    /// direction overrides, and not a page of text from an address that has proved nothing.
    public static func clean(_ text: String, limit: Int = 300) -> String {
        let shown = String(text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return value >= 0x20 && !(0x7f...0x9f).contains(value) && !(0x202a...0x202e).contains(value) && !(0x2066...0x2069).contains(value)
        })
        return String(shown.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

/// Keeps the first of anything with the same ID: SwiftUI's lists misbehave on repeats.
public func uniqued<T: Identifiable>(_ list: [T]) -> [T] where T.ID: Hashable {
    var seen = Set<T.ID>()
    return list.filter { seen.insert($0.id).inserted }
}
