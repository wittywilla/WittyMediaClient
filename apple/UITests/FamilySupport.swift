// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The other end of a flow that takes two devices, played from the test itself with plain requests to the test
/// server: the TV a phone approves, the phone that approves a TV, the parent who sets a profile up.
struct ServerHand {
    let base: String
    var token = ""

    struct Refused: Error { let status: Int; let body: [String: Any] }

    @discardableResult
    func send(_ method: String, _ path: String, _ body: [String: Any]? = nil, headers: [String: String] = [:]) async throws -> [String: Any] {
        let (data, status) = try await raw(method, path, body, headers: headers)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else { throw Refused(status: status, body: object) }
        return object
    }

    func list(_ path: String) async throws -> [[String: Any]] {
        let (data, _) = try await raw("GET", path, nil, headers: [:])
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    private func raw(_ method: String, _ path: String, _ body: [String: Any]?, headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + "/api/v1" + path)))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Signed in as the account the tests were given, which has to be an administrator.
    static func admin() async throws -> ServerHand {
        guard let address = TestServer.address else { throw XCTSkip("No test server: set TEST_RUNNER_WMC_SERVER.") }
        var hand = ServerHand(base: address)
        let answer = try await hand.send("POST", "/login", ["name": TestServer.user, "password": TestServer.password, "device": "UI tests"])
        hand.token = try XCTUnwrap(answer["token"] as? String)
        return hand
    }

    /// A Kids profile of the test's own, with no password, so each run starts with a day's time unused.
    func makeKid(_ access: [String: Any]) async throws -> (id: Int64, name: String) {
        let name = "kid" + String(UInt32.random(in: 100_000...999_999))
        let made = try await send("POST", "/users", ["name": name, "password": "", "kind": "kids", "displayName": "Test kid", "access": access])
        return (try XCTUnwrap((made["id"] as? NSNumber)?.int64Value), name)
    }

    func remove(user id: Int64) async { _ = try? await send("DELETE", "/users/\(id)", [:]) }
}

extension XCTestCase {
    /// A picture of the screen, kept where `TEST_RUNNER_WMC_SHOTS` says, for whoever runs the tests to look at.
    @MainActor
    func snap(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["WMC_SHOTS"] else { return }
        #if os(tvOS)
        let kind = "tv"
        #else
        let kind = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(kind)-\(name).png"))
    }

    /// Presses or taps something, whichever the device does.
    @MainActor
    func choose(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        element.shown(file: file, line: line)
        #if os(tvOS)
        // The remote moves the focus towards it, by where it is on the screen, and then presses it.
        for _ in 0..<40 where !element.hasFocus {
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard focused.exists else { XCUIRemote.shared.press(.down); continue }
            let from = focused.frame, to = element.frame
            if abs(to.midY - from.midY) > max(from.height, to.height) / 2 {
                XCUIRemote.shared.press(to.midY > from.midY ? .down : .up)
            } else {
                XCUIRemote.shared.press(to.midX > from.midX ? .right : .left)
            }
        }
        XCTAssertTrue(element.hasFocus, "The remote never reached \(element)", file: file, line: line)
        XCUIRemote.shared.press(.select)
        #else
        if !element.isHittable { app.swipeUp() }
        element.tap()
        #endif
    }
}
