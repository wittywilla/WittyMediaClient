import Foundation

/// A small real server on 127.0.0.1, for testing what the client does with real connections:
/// redirects it must not follow, answers it must not finish reading. One request at a time,
/// and every connection closes after its answer.
final class StandInServer: @unchecked Sendable {
    struct Request {
        let line: String
        let head: String
        var path: String { line.split(separator: " ").dropFirst().first.map(String.init) ?? "" }
        var hasToken: Bool { head.lowercased().contains("authorization:") }
    }

    private let lock = NSLock()
    private var seen: [Request] = []
    private let listener: Int32
    let port: Int

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    var address: String { "http://127.0.0.1:\(port)" }

    /// `respond` answers one request with the bytes to send.
    init(respond: @escaping @Sendable (Request) -> Data) throws {
        #if canImport(Glibc)
        let kind = Int32(SOCK_STREAM.rawValue)
        #else
        let kind = SOCK_STREAM
        #endif
        let fd = socket(AF_INET, kind, 0)
        guard fd >= 0 else { throw URLError(.cannotConnectToHost) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        #if !canImport(Glibc)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1") // only ever this machine
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw URLError(.cannotConnectToHost)
        }
        var actual = sockaddr_in()
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        listener = fd
        port = Int(UInt16(bigEndian: actual.sin_port))
        let thread = Thread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                self?.serve(client, respond)
            }
        }
        thread.start()
    }

    private func serve(_ client: Int32, _ respond: (Request) -> Data) {
        defer { close(client) }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while !received.contains(ending: "\r\n\r\n") {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            received.append(contentsOf: buffer[0..<count])
        }
        let head = String(decoding: received, as: UTF8.self)
        let line = head.components(separatedBy: "\r\n").first ?? ""
        let request = Request(line: line, head: head)
        lock.lock()
        seen.append(request)
        lock.unlock()
        let answer = respond(request)
        answer.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                #if canImport(Glibc)
                let wrote = send(client, bytes.baseAddress! + sent, bytes.count - sent, Int32(MSG_NOSIGNAL))
                #else
                var quiet: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &quiet, socklen_t(MemoryLayout<Int32>.size))
                let wrote = send(client, bytes.baseAddress! + sent, bytes.count - sent, 0)
                #endif
                if wrote <= 0 { return }
                sent += wrote
            }
        }
    }

    func stop() {
        // Waking accept() by closing the socket that's being waited on.
        shutdown(listener, Int32(SHUT_RDWR))
        close(listener)
    }

    static func answer(status: String = "200 OK", headers: [String] = [], body: String = "", announceLength: Bool = true) -> Data {
        var lines = ["HTTP/1.1 \(status)", "Connection: close", "Content-Type: application/json"] + headers
        if announceLength { lines.append("Content-Length: \(body.utf8.count)") }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }
}

private extension Data {
    func contains(ending text: String) -> Bool {
        range(of: Data(text.utf8)) != nil
    }
}
