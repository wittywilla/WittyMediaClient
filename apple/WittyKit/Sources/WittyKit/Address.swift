import Foundation

/// Turns what someone typed into a server address, or says why it can't be one.
/// Every client follows the same rules: see shared/data/connection-cases.json.
public enum Address {
    public static let defaultPort = 9797

    public enum Result: Equatable {
        case ok(String)
        case bad(String)
    }

    private static func matches(_ text: String, _ pattern: String, caseInsensitive: Bool = false) -> Bool {
        var options: String.CompareOptions = [.regularExpression]
        if caseInsensitive { options.insert(.caseInsensitive) }
        return text.range(of: pattern, options: options) != nil
    }

    public static func normalize(_ input: String) -> Result {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .bad("empty") }
        // Newer Foundation quietly encodes spaces instead of refusing them.
        if text.contains(where: \.isWhitespace) { return .bad("invalid") }
        let hasScheme = matches(text, "^[a-zA-Z][a-zA-Z0-9+.-]*://")
        var addPort = false
        if hasScheme {
            if !matches(text, "^https?://", caseInsensitive: true) { return .bad("scheme") }
        } else if matches(text, "^(javascript|file|data|mailto):", caseInsensitive: true) {
            return .bad("scheme")
        } else {
            // A bare IPv6 address needs its brackets before it can be parsed.
            if text.filter({ $0 == ":" }).count >= 2 && !text.hasPrefix("[") { text = "[\(text)]" }
            addPort = !matches(text, "(\\]|^[^\\[\\]:]+):[0-9]*$")
            text = "http://" + text
        }
        guard let parts = URLComponents(string: text), let rawHost = parts.host, !rawHost.isEmpty else {
            return .bad("invalid")
        }
        if parts.user != nil || parts.password != nil { return .bad("credentials") }
        // Foundation may or may not keep an IPv6 address's brackets.
        let bare = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let host = bare.contains(":") ? "[\(bare)]" : bare
        let secure = parts.scheme?.lowercased() == "https"
        let port = addPort ? defaultPort : parts.port
        if let port, port > 65535 || port < 0 { return .bad("invalid") }
        if !secure && !isPrivateHost(host) { return .bad("public-http") }
        let standard = secure ? 443 : 80
        var suffix = ""
        if let port, port != standard { suffix = ":\(port)" }
        return .ok("\(secure ? "https" : "http")://\(host)\(suffix)")
    }

    /// A plain http address that redirected to https on the same host: the address to try instead.
    /// Anything else, including another host, gets nil and is never followed.
    public static func upgrade(from address: String, location: String?) -> String? {
        guard let location, let to = URLComponents(string: location), to.scheme?.lowercased() == "https",
              to.user == nil, to.password == nil,
              let from = URLComponents(string: address), from.scheme?.lowercased() == "http",
              let toHost = to.host?.lowercased(), toHost == from.host?.lowercased() else { return nil }
        let host = toHost.contains(":") && !toHost.hasPrefix("[") ? "[\(toHost)]" : toHost
        guard case .ok(let url) = normalize("https://\(host)\(to.port.map { ":\($0)" } ?? "")") else { return nil }
        return url
    }

    /// Is this address on the local network? A name with no dots or ending in
    /// .local can only be resolved locally; anything else may be public. A bare number
    /// isn't a name: 134744072 is how to write 8.8.8.8, and resolves to it.
    public static func isPrivateHost(_ host: String) -> Bool {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        if pieces.count == 4, pieces.allSatisfy({ !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isNumber) }) {
            let a = Int(pieces[0]) ?? 0
            let b = Int(pieces[1]) ?? 0
            return a == 127 || a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
                || (a == 169 && b == 254) || (a == 100 && (64...127).contains(b))
        }
        if host.hasPrefix("[") {
            let h = host.dropFirst().dropLast()
            return h == "::1" || ["fc", "fd", "fe8", "fe9", "fea", "feb"].contains { h.hasPrefix($0) }
        }
        if host.allSatisfy(\.isNumber) || host.lowercased().hasPrefix("0x") { return false }
        return host == "localhost" || !host.contains(".") || host.hasSuffix(".local")
    }

    /// Does everything this name resolved to stay on the local network? Addresses as the system
    /// writes them: `192.168.1.5`, `fe80::1%en0`, `::ffff:192.168.1.5`.
    public static func staysLocal(resolved addresses: [String]) -> Bool {
        addresses.allSatisfy { address in
            let bare = address.split(separator: "%").first.map(String.init)?.lowercased() ?? ""
            if bare.hasPrefix("::ffff:"), bare.contains(".") { return isPrivateHost(String(bare.dropFirst(7))) }
            return isPrivateHost(bare.contains(":") ? "[\(bare)]" : bare)
        }
    }

    /// A name only looks local: a search domain or a local resolver can send `mediabox` or
    /// `mediabox.local` to the internet, where a plain http sign-in could be read. HTTPS and written-out
    /// addresses have nothing to find out. No answer in a few seconds lets it through, as the
    /// connection that follows will then fail by itself; mDNS can be slow.
    public static func plainHTTPStaysLocal(_ address: String) async -> Bool {
        guard let parts = URLComponents(string: address), parts.scheme?.lowercased() == "http", let host = parts.host?.lowercased(),
              !host.isEmpty, !host.contains(":"), !host.hasPrefix("["), !isWrittenOutIPv4(host) else { return true }
        return await withCheckedContinuation { (waiting: CheckedContinuation<Bool, Never>) in
            let once = Once(waiting)
            DispatchQueue.global(qos: .userInitiated).async { once.finish(staysLocal(resolved: resolve(host))) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { once.finish(true) }
        }
    }

    private static func isWrittenOutIPv4(_ host: String) -> Bool {
        host.range(of: "^[0-9]{1,3}(\\.[0-9]{1,3}){3}\\z", options: .regularExpression) != nil
    }

    /// Every address the system has for a name, as text. Blocks, so never on the main thread.
    static func resolve(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0 else { return [] }
        defer { freeaddrinfo(found) }
        var out: [String] = []
        var next = found
        while let current = next, out.count < 32 {
            var text = [CChar](repeating: 0, count: 256)
            if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen, &text, socklen_t(text.count), nil, 0, NI_NUMERICHOST) == 0 {
                out.append(String(cString: text))
            }
            next = current.pointee.ai_next
        }
        return out
    }

    /// Answers once, whichever comes first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: CheckedContinuation<Bool, Never>?

        init(_ waiting: CheckedContinuation<Bool, Never>) { self.waiting = waiting }

        func finish(_ answer: Bool) {
            lock.lock()
            let ready = waiting
            waiting = nil
            lock.unlock()
            ready?.resume(returning: answer)
        }
    }
}

/// One server, as far as a browser would count it: scheme, host and port.
public enum Origin {
    private static func port(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    public static func same(_ a: URL, _ b: URL) -> Bool {
        guard let scheme = a.scheme?.lowercased(), let host = a.host?.lowercased(), !host.isEmpty, let portA = port(a) else { return false }
        return scheme == b.scheme?.lowercased() && host == b.host?.lowercased() && portA == port(b) && a.user == nil && a.password == nil
    }

    /// The server's address and a path from one of its answers. `@other.example/x` or `//other.example/x`
    /// after an address means somewhere else entirely, so the result has to be checked.
    public static func join(base: String, path: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\"), let server = URL(string: base),
              let url = URL(string: base + path), same(url, server) else { return nil }
        return url
    }
}
