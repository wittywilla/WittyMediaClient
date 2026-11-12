// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The other side of the Remote Protocol and of a watch party, played by the test itself: a second sign-in to
/// the same server that lists devices, sends commands, starts rooms and reads how things stand. With it one
/// simulator is enough to see the app obey another device, and follow a party's host.
struct TestAPI {
    let base: String
    var token = ""

    struct Refusal: Error, CustomStringConvertible {
        let status: Int
        let body: [String: Any]
        var code: String { body["code"] as? String ?? "" }
        var description: String { "\(status) \(body["error"] as? String ?? "")" }
    }

    static func signIn(user: String = TestServer.user, password: String = TestServer.password, device: String = "UI test") async throws -> TestAPI {
        guard let address = TestServer.address else { throw XCTSkip("No test server: set TEST_RUNNER_WMC_SERVER.") }
        var api = TestAPI(base: address)
        let answer = try await api.call("POST", "/login", ["name": user, "password": password, "device": device])
        api.token = answer["token"] as? String ?? ""
        return api
    }

    @discardableResult
    func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/api/v1" + path)), timeoutInterval: 20)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let read = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Refusal(status: status, body: read) }
        return read
    }

    // MARK: Devices

    func devices() async throws -> [[String: Any]] {
        try await call("GET", "/remote-control/devices")["devices"] as? [[String: Any]] ?? []
    }

    /// The app under test as a device: the one of that kind that is connected and isn't this sign-in's own.
    func appDevice(kinds: [String], within seconds: TimeInterval = 30) async throws -> [String: Any] {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let found = try await devices().first(where: { kinds.contains($0["kind"] as? String ?? "") && $0["online"] as? Bool == true && $0["thisSession"] as? Bool == false }) {
                return found
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw XCTSkip("The app never showed as a device. Is remote control on, on the test server?")
    }

    func device(_ id: String) async throws -> [String: Any]? {
        try await devices().first { $0["id"] as? String == id }
    }

    @discardableResult
    func send(_ id: String, _ command: [String: Any]) async throws -> [String: Any] {
        var body = command
        body["v"] = 1
        return try await call("POST", "/remote-control/devices/\(id)/commands", body)
    }

    /// Waits until the device's own report says so.
    func waitForState(_ id: String, _ what: String, within seconds: TimeInterval = 25, _ test: @escaping ([String: Any]) -> Bool) async throws -> [String: Any] {
        let end = Date().addingTimeInterval(seconds)
        var last: [String: Any] = [:]
        while Date() < end {
            if let state = try await device(id)?["state"] as? [String: Any] {
                last = state
                if test(state) { return state }
            }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        XCTFail("The device never reported \(what). Its last state: \(last)")
        return last
    }

    /// Where a device is now, from its last report and the server's clock.
    func position(_ id: String) async throws -> Double {
        let list = try await call("GET", "/remote-control/devices")
        let now = list["serverTimeMs"] as? Double ?? 0
        guard let device = (list["devices"] as? [[String: Any]])?.first(where: { $0["id"] as? String == id }),
              let state = device["state"] as? [String: Any] else { return -1 }
        var at = state["positionSec"] as? Double ?? 0
        if state["status"] as? String == "playing" { at += (now - (device["stateAt"] as? Double ?? now)) / 1000 * (state["rate"] as? Double ?? 1) }
        return at
    }

    // MARK: Watch parties

    func room(_ room: [String: Any]) async throws -> [String: Any] {
        try await call("GET", "/syncplay/rooms/\(room["id"] as? String ?? "")?member=\(room["you"] as? String ?? "")")
    }

    @discardableResult
    func command(_ room: [String: Any], _ type: String, _ more: [String: Any] = [:]) async throws -> [String: Any] {
        var body = more
        body["member"] = room["you"]
        body["type"] = type
        return try await call("POST", "/syncplay/rooms/\(room["id"] as? String ?? "")/command", body)
    }

    /// The party's host stays "here" only while it's heard from: a ping, as its player would send.
    func ping(_ room: [String: Any]) async throws {
        try await call("POST", "/syncplay/rooms/\(room["id"] as? String ?? "")/ping", ["member": room["you"] ?? "", "t0": Date().timeIntervalSince1970 * 1000, "rttMs": 20])
    }

    func report(_ room: [String: Any], ready: Bool = true) async throws {
        let now = try await self.room(room)
        let rev = (now["state"] as? [String: Any])?["rev"] ?? 0
        try await call("POST", "/syncplay/rooms/\(room["id"] as? String ?? "")/report", ["member": room["you"] ?? "", "state": ready ? "ready" : "buffering", "rev": rev])
    }

    /// Where the room is now, by the server's own state and clock.
    func roomPosition(_ room: [String: Any]) async throws -> (position: Double, playing: Bool, members: [[String: Any]]) {
        let now = try await self.room(room)
        let state = now["state"] as? [String: Any] ?? [:]
        let serverNow = now["serverTimeMs"] as? Double ?? 0
        let at = state["positionSec"] as? Double ?? 0, atMs = state["atMs"] as? Double ?? 0
        let held = state["paused"] as? Bool == true || state["waiting"] as? Bool == true || serverNow <= atMs
        return (held ? at : at + (serverNow - atMs) / 1000 * (state["rate"] as? Double ?? 1), !held, now["members"] as? [[String: Any]] ?? [])
    }

    /// Waits until some member of the room, other than the caller, is in that state.
    func waitForGuest(_ room: [String: Any], state wanted: String, within seconds: TimeInterval = 40) async throws {
        let end = Date().addingTimeInterval(seconds)
        var seen = ""
        while Date() < end {
            try await ping(room)
            let members = try await self.room(room)["members"] as? [[String: Any]] ?? []
            let guests = members.filter { $0["you"] as? Bool != true }
            seen = guests.map { "\($0["name"] ?? ""): \($0["state"] ?? "")" }.joined(separator: ", ")
            if guests.contains(where: { $0["state"] as? String == wanted }) { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTFail("No guest became \(wanted). The room has: \(seen)")
    }

    /// A film of the test library that is long enough to seek about in: the longest, or the one whose title
    /// holds `WMC_FILM` when the environment names one (to try a file that plays as it is, or one that's converted).
    func aFilm(atLeast seconds: Double = 80) async throws -> (id: Int, title: String, kind: String) {
        let wanted = ProcessInfo.processInfo.environment["WMC_FILM"] ?? ""
        for library in try await callList("/libraries") where library["type"] as? String == "movies" {
            let items = try await call("GET", "/items?library=\(library["id"] ?? 0)&limit=100")["items"] as? [[String: Any]] ?? []
            let long = items.filter { ($0["runtimeSec"] as? Double ?? 0) >= seconds && $0["kind"] as? String == "video" }
                .sorted { ($0["runtimeSec"] as? Double ?? 0, $1["id"] as? Int ?? 0) > ($1["runtimeSec"] as? Double ?? 0, $0["id"] as? Int ?? 0) }
            if let film = long.first(where: { !wanted.isEmpty && ($0["title"] as? String ?? "").contains(wanted) }) ?? long.first {
                return (film["id"] as? Int ?? 0, film["title"] as? String ?? "", "video")
            }
        }
        throw XCTSkip("The test server has no film of \(Int(seconds)) seconds or more.")
    }

    func callList(_ path: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/api/v1" + path)))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }
}

/// A device that isn't an app: it announces itself, holds the channel and answers what it's sent, so the app's
/// list of devices and its remote have something to play on. What it was told is kept for the test to read.
final class StandInDevice: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let api: TestAPI
    private let lock = NSLock()
    private var buffer = ""
    private var received: [[String: Any]] = []
    private var session: URLSession?
    private(set) var id = ""
    /// What it reports after each command, as a real player would.
    private var state: [String: Any] = ["v": 1, "status": "idle", "volume": 0.5, "muted": false, "screen": "home"]

    init(api: TestAPI) { self.api = api }

    var commands: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    func start(name: String, kind: String = "tv", features: [String] = ["seek", "volume", "queue", "audio", "subtitles", "rate", "navigate"]) async throws {
        let agreed = try await api.call("POST", "/remote-control/devices", ["v": 1, "name": name, "kind": kind, "capabilities": ["mediaKinds": ["video", "audio"], "features": features]])
        id = agreed["deviceId"] as? String ?? ""
        var request = URLRequest(url: try XCTUnwrap(URL(string: api.base + "/api/v1/remote-control/devices/\(id)/channel")))
        request.setValue("Bearer \(api.token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        let made = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        session = made
        made.dataTask(with: request).resume()
        try await report()
    }

    func stop() async {
        session?.invalidateAndCancel()
        _ = try? await api.call("DELETE", "/remote-control/devices/\(id)")
    }

    func set(_ change: [String: Any]) async throws {
        lock.lock()
        for (key, value) in change { state[key] = value }
        lock.unlock()
        try await report()
    }

    private func report() async throws {
        lock.lock()
        let now = state
        lock.unlock()
        try await api.call("POST", "/remote-control/devices/\(id)/state", now)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer += String(decoding: data, as: UTF8.self)
        var commands: [[String: Any]] = []
        while let end = buffer.range(of: "\n\n") {
            let frame = String(buffer[buffer.startIndex..<end.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            guard frame.contains("event: command"), let line = frame.split(separator: "\n").first(where: { $0.hasPrefix("data: ") }),
                  let command = (try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8))) as? [String: Any] else { continue }
            received.append(command)
            commands.append(command)
        }
        lock.unlock()
        for command in commands { Task { await self.obey(command) } }
    }

    /// Does what a simple player would, and says so.
    private func obey(_ command: [String: Any]) async {
        lock.lock()
        switch command["type"] as? String {
        case "play":
            let queue = command["queue"] as? [Int] ?? []
            state["status"] = "playing"
            state["itemId"] = command["itemId"] ?? (queue.isEmpty ? 0 : queue[command["queueIndex"] as? Int ?? 0])
            state["positionSec"] = command["positionSec"] ?? 0
            state["durationSec"] = 600
            state["rate"] = 1
            if queue.count > 1 { state["queue"] = queue; state["queueIndex"] = command["queueIndex"] ?? 0 }
        case "pause": state["status"] = "paused"
        case "resume": state["status"] = "playing"
        case "stop": state = ["v": 1, "status": "idle", "volume": state["volume"] ?? 0.5, "muted": false, "screen": "home"]
        case "seek": state["positionSec"] = command["positionSec"] ?? ((state["positionSec"] as? Double ?? 0) + (command["bySec"] as? Double ?? 0))
        case "volume": state["volume"] = command["level"] ?? 0.5
        case "mute": state["muted"] = command["muted"] ?? false
        case "rate": state["rate"] = command["rate"] ?? 1
        default: break
        }
        lock.unlock()
        _ = try? await api.call("POST", "/remote-control/devices/\(id)/ack", ["id": command["id"] ?? "", "ok": true])
        try? await report()
    }

    func waitForCommand(_ type: String, within seconds: TimeInterval = 15) async -> [String: Any]? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let found = commands.last(where: { $0["type"] as? String == type }) { return found }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return nil
    }
}

extension XCTestCase {
    /// Which Apple device the tests are running on, as the protocol names it.
    var deviceKinds: [String] {
        #if os(tvOS)
        return ["tv"]
        #else
        return ["phone", "tablet"]
        #endif
    }
}
