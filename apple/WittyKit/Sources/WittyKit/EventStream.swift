// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The server's live channels (a device's commands, a watch party's room, the devices a remote can see) are
// server-sent events: an `event:` line, a `data:` line holding one JSON object, and a blank line. A comment
// line (`: still here`) comes every 25 seconds so that nothing in between closes the stream.
// See the server's docs/REMOTE-PROTOCOL.md, Transport.

/// One event from a stream: its name and its JSON, not yet read as anything.
public struct ServerEvent: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    public func decoded<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(T.self, from: data) }
}

/// Turns the lines of a stream into events. It is fed a line at a time, with or without the blank lines
/// between events (the system's line reader leaves them out), and never keeps more than one event.
public struct EventParser: Sendable {
    /// One event's data is at most this long. A longer line is dropped with its event.
    public static let maxLine = 256 * 1024
    private var name = ""

    public init() {}

    /// An event when this line completes one, otherwise nil. An event with no `event:` line is a "message",
    /// as the standard has it.
    public mutating func feed(_ line: String) -> ServerEvent? {
        if line.isEmpty {
            name = ""
            return nil
        }
        // A comment: the keep-alive.
        if line.hasPrefix(":") { return nil }
        guard line.utf8.count <= Self.maxLine else {
            name = ""
            return nil
        }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[line.startIndex..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event":
            name = String(value)
            return nil
        case "data":
            let event = ServerEvent(name: name.isEmpty ? "message" : name, data: Data(value.utf8))
            name = ""
            return event
        default:
            // `id:`, `retry:` and anything newer: nothing here needs them.
            return nil
        }
    }
}

/// How long to wait before opening a dropped stream again: a second, then twice as long each time, up to
/// half a minute. A stream that stayed open goes back to the start.
public struct Backoff: Equatable, Sendable {
    public let first: Double
    public let longest: Double
    public private(set) var failures = 0

    public init(first: Double = 1, longest: Double = 30) {
        self.first = first
        self.longest = longest
    }

    /// The wait before the next try, in seconds, counting this failure.
    public mutating func next() -> Double {
        let wait = min(longest, first * pow(2, Double(min(failures, 16))))
        failures += 1
        return wait
    }

    public mutating func reset() { failures = 0 }
}

extension WittyClient {
    /// How long a stream may say nothing before it's taken to be dead: the server writes every 25 seconds.
    public static let streamIdleSeconds: TimeInterval = 60

    /// Opens one of the server's event streams and reads it until it ends, fails or the task is cancelled.
    /// A refusal is an `APIError` with the server's `code`. Opening it again is the caller's business,
    /// since what to do first (announce again, join again) differs: see `Backoff`.
    public func events(_ path: String) -> AsyncThrowingStream<ServerEvent, Error> {
        AsyncThrowingStream { continuation in
            #if canImport(FoundationNetworking)
            continuation.finish(throwing: APIError(status: 0, message: "Live channels aren't available here."))
            #else
            guard let url = URL(string: base + apiPath + path) else {
                continuation.finish(throwing: APIError(status: 0, message: "That server address can't be used."))
                return
            }
            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            for (name, value) in authHeaders { request.setValue(value, forHTTPHeaderField: name) }
            // A session of its own: the shared one reads whole answers up to a limit, and this never ends.
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.timeoutIntervalForRequest = Self.streamIdleSeconds
            config.timeoutIntervalForResource = 24 * 60 * 60
            let session = URLSession(configuration: config)
            let reading = Task {
                defer { session.finishTasksAndInvalidate() }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 16 * 1024 { break }
                        }
                        struct Failure: Decodable {
                            let error: String?
                            let code: String?
                        }
                        let failure = try? JSONDecoder().decode(Failure.self, from: body)
                        let words = PlainWords.clean(failure?.error ?? "")
                        throw APIError(status: http.statusCode,
                                       message: words.isEmpty ? "The server answered with an error (\(http.statusCode))." : words,
                                       code: PlainWords.clean(failure?.code ?? "", limit: 40), body: body,
                                       retryAfter: Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0)
                    }
                    var parser = EventParser()
                    for try await line in bytes.lines {
                        if let event = parser.feed(line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
            #endif
        }
    }
}
