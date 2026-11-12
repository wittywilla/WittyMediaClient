// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// Watch parties: the app joins a party another account hosts and follows it. The host is the test itself,
/// through the API; where the app's own player has got to is read from what it reports as a device.
/// Needs a second account: TEST_RUNNER_WMC_USER_HOST and TEST_RUNNER_WMC_PASSWORD_HOST.
final class WatchPartyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func host() async throws -> TestAPI {
        guard let other = TestServer.account("host") else { throw XCTSkip("No second account: set TEST_RUNNER_WMC_USER_HOST.") }
        return try await TestAPI.signIn(user: other.user, password: other.password, device: "Party host")
    }

    /// How far the app's player is from the room, in seconds, from its device report and the room's state.
    private func gap(_ mine: TestAPI, device: String, _ host: TestAPI, _ room: [String: Any]) async throws -> Double {
        async let here = mine.position(device)
        async let there = host.roomPosition(room)
        return try await abs(here - there.position)
    }

    @MainActor
    func testTheAppJoinsAPartyAndFollowsItsHost() async throws {
        let host = try await host()
        let mine = try await TestAPI.signIn()
        let film = try await host.aFilm(atLeast: 300)
        var room = try await host.call("POST", "/syncplay/rooms", ["itemId": film.id, "name": "Test party", "policy": "host", "waitForAll": true, "device": "test"])
        addTeardownBlock { _ = try? await host.call("DELETE", "/syncplay/rooms/\(room["id"] as? String ?? "")?member=\(room["you"] as? String ?? "")") }
        let code = try XCTUnwrap(room["code"] as? String)
        try await host.report(room)

        let app = try launchApp()
        app.buttons["Home"].firstMatch.shown(30)
        #if os(tvOS)
        // Invited by name, the party is in the list under Watch party: no code to type.
        let me = try await mine.call("GET", "/status")["user"] as? [String: Any]
        try await host.call("POST", "/syncplay/rooms/\(room["id"] as? String ?? "")/invite", ["member": room["you"] ?? "", "userIds": [me?["id"] ?? 0]])
        try openWatchPartyOnTV(app)
        let invited = app.buttons["Test party"].firstMatch
        invited.shown(20)
        let remote = XCUIRemote.shared
        for _ in 0..<12 where !invited.hasFocus { remote.press(.down) }
        XCTAssertTrue(invited.hasFocus, "the invitation should be reachable with the remote")
        remote.press(.select)
        #else
        app.buttons["You"].firstMatch.shown(10).tap()
        let row = app.buttons["row-watch-party"].firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        // Typed as people type it: lower case, with a dash.
        let field = app.textFields["party-code"].firstMatch
        field.shown(20)
        app.otherElements["Code"].firstMatch.tap()
        let typed = code.prefix(3).lowercased() + "-" + code.dropFirst(3).lowercased()
        app.typeText(typed)
        app.buttons["party-join"].firstMatch.shown(5).tap()
        #endif

        // The app's player opens the party's film and says it's ready; the room was paused at the start.
        try await host.waitForGuest(room, state: "ready")
        let found = try await mine.appDevice(kinds: deviceKinds)
        let device = try XCTUnwrap(found["id"] as? String)
        var state = try await mine.waitForState(device, "the party's film, paused") { $0["itemId"] as? Int == film.id && $0["status"] as? String == "paused" }
        XCTAssertLessThan(state["positionSec"] as? Double ?? 99, 2)

        // The host presses play: everyone's picture moves, this one's too.
        room = try await host.command(room, "play")
        state = try await mine.waitForState(device, "playing") { $0["status"] as? String == "playing" }
        for _ in 0..<8 {
            try await host.ping(room)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        var apart = try await gap(mine, device: device, host, room)
        XCTAssertLessThan(apart, 1.5, "playing along with the host (the device's report is only so exact)")

        // The host seeks four minutes in: the app goes there, loads, and says it's ready again.
        room = try await host.command(room, "seek", ["positionSec": 240])
        try await host.report(room)
        try await host.waitForGuest(room, state: "ready")
        state = try await mine.waitForState(device, "four minutes in") { ($0["positionSec"] as? Double ?? 0) >= 238 }
        for _ in 0..<6 {
            try await host.ping(room)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        apart = try await gap(mine, device: device, host, room)
        XCTAssertLessThan(apart, 1.5)

        // The host pauses: the app pauses at the room's place.
        room = try await host.command(room, "pause")
        state = try await mine.waitForState(device, "paused with the host") { $0["status"] as? String == "paused" }
        let held = try await host.roomPosition(room)
        XCTAssertFalse(held.playing)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let stopped = try await mine.position(device)
        XCTAssertEqual(stopped, held.position, accuracy: 0.6, "paused at the room's own place")

        // Only the host controls this party: a pause sent to the app as a device changes nothing in the room.
        room = try await host.command(room, "play")
        state = try await mine.waitForState(device, "playing again") { $0["status"] as? String == "playing" }
        try await mine.send(device, ["type": "pause"])
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let still = try await host.roomPosition(room)
        XCTAssertTrue(still.playing, "a guest can't pause a party whose host alone controls it")
        app.staticTexts["Only the host controls this watch party."].firstMatch.shown(5)
        state = try await mine.waitForState(device, "still playing") { $0["status"] as? String == "playing" }

        // The host ends it: the app is told, and its player is its own again.
        try await host.call("DELETE", "/syncplay/rooms/\(room["id"] as? String ?? "")?member=\(room["you"] as? String ?? "")")
        app.staticTexts["The watch party has ended."].firstMatch.shown(15)
    }

    #if os(tvOS)
    /// From Home to You, down to the device's rows, and into Watch party.
    @MainActor
    private func openWatchPartyOnTV(_ app: XCUIApplication) throws {
        let remote = XCUIRemote.shared
        let you = app.buttons["You"].firstMatch
        you.shown(10)
        for _ in 0..<10 where !you.hasFocus { remote.press(.right) }
        remote.press(.select)
        let row = app.buttons["row-watch-party"].firstMatch
        row.shown(15)
        for _ in 0..<30 where !row.hasFocus { remote.press(.down) }
        XCTAssertTrue(row.hasFocus, "Watch party should be among You's rows")
        remote.press(.select)
    }

    /// The code is typed with the remote, on the app's own pad of letters and numbers.
    @MainActor
    func testACodeIsTypedWithTheRemote() async throws {
        let host = try await host()
        let film = try await host.aFilm(atLeast: 300)
        let room = try await host.call("POST", "/syncplay/rooms", ["itemId": film.id, "name": "Typed in", "device": "test"])
        addTeardownBlock { _ = try? await host.call("DELETE", "/syncplay/rooms/\(room["id"] as? String ?? "")?member=\(room["you"] as? String ?? "")") }
        let code = try XCTUnwrap(room["code"] as? String)
        try await host.report(room)

        let app = try launchApp()
        app.buttons["Home"].firstMatch.shown(30)
        try openWatchPartyOnTV(app)
        let remote = XCUIRemote.shared
        let first = app.buttons["key-A"].firstMatch
        first.shown(20)
        for _ in 0..<12 where !first.hasFocus { remote.press(.down) }
        if !first.hasFocus { for _ in 0..<10 where !first.hasFocus { remote.press(.left) } }
        XCTAssertTrue(first.hasFocus, "the pad's first key should take the highlight")
        // The pad is four rows of nine: walk from key to key.
        let rows = ["ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ0", "123456789"].map(Array.init)
        func place(_ letter: Character) -> (Int, Int) {
            for (r, row) in rows.enumerated() { if let c = row.firstIndex(of: letter) { return (r, c) } }
            return (0, 0)
        }
        var at = (0, 0)
        for letter in code {
            let to = place(letter)
            for _ in 0..<abs(to.0 - at.0) { remote.press(to.0 > at.0 ? .down : .up) }
            for _ in 0..<abs(to.1 - at.1) { remote.press(to.1 > at.1 ? .right : .left) }
            XCTAssertTrue(app.buttons["key-\(letter)"].firstMatch.hasFocus, "the highlight should be on \(letter)")
            remote.press(.select)
            at = to
        }
        XCTAssertEqual(app.otherElements["party-code"].firstMatch.value as? String, code)
        let join = app.buttons["party-join"].firstMatch
        for _ in 0..<8 where !join.hasFocus { remote.press(.down) }
        remote.press(.select)
        try await host.waitForGuest(room, state: "ready")
    }
    #endif
}
