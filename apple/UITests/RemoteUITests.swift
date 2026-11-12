// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The server's Remote Protocol, with the app as a device and as a controller. The test plays the other side
/// with a second sign-in of the same account: see TogetherSupport.swift.
final class RemoteUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The app announces itself with what it really does, and obeys what another device sends it: play, pause,
    /// seek, volume where it has one, stop.
    @MainActor
    func testTheAppIsADeviceAndObeysAnotherDevice() async throws {
        let app = try launchApp()
        app.buttons["Home"].firstMatch.shown(30)
        let api = try await TestAPI.signIn()
        let film = try await api.aFilm()

        let found = try await api.appDevice(kinds: deviceKinds)
        let id = try XCTUnwrap(found["id"] as? String)
        let features = (found["capabilities"] as? [String: Any])?["features"] as? [String] ?? []
        XCTAssertTrue(features.contains("seek") && features.contains("queue") && features.contains("rate"))
        #if os(tvOS)
        XCTAssertTrue(features.contains("navigate"), "Apple TV has a remote's keys")
        XCTAssertFalse(features.contains("volume"), "Apple TV's volume is the TV's, not the app's")
        #else
        XCTAssertTrue(features.contains("volume"))
        XCTAssertFalse(features.contains("navigate"), "a phone is touched, not steered")
        #endif
        XCTAssertEqual((found["state"] as? [String: Any])?["status"] as? String, "idle")

        // Play it from a minute in: the app opens its player there.
        try await api.send(id, ["type": "play", "itemId": film.id, "positionSec": 60])
        var state = try await api.waitForState(id, "playing") { $0["status"] as? String == "playing" && $0["itemId"] as? Int == film.id }
        XCTAssertGreaterThanOrEqual(state["positionSec"] as? Double ?? 0, 55)
        XCTAssertEqual(state["screen"] as? String, "player")

        try await api.send(id, ["type": "pause"])
        state = try await api.waitForState(id, "paused") { $0["status"] as? String == "paused" }

        try await api.send(id, ["type": "seek", "positionSec": 30])
        state = try await api.waitForState(id, "the seek") { abs(($0["positionSec"] as? Double ?? 0) - 30) < 3 }
        try await api.send(id, ["type": "seek", "bySec": 10])
        state = try await api.waitForState(id, "ten seconds on") { abs(($0["positionSec"] as? Double ?? 0) - 40) < 3 }

        try await api.send(id, ["type": "resume"])
        state = try await api.waitForState(id, "playing again") { $0["status"] as? String == "playing" }

        try await api.send(id, ["type": "rate", "rate": 1.5])
        state = try await api.waitForState(id, "the speed") { abs(($0["rate"] as? Double ?? 0) - 1.5) < 0.01 }
        try await api.send(id, ["type": "rate", "rate": 1])

        #if !os(tvOS)
        try await api.send(id, ["type": "volume", "level": 0.4])
        state = try await api.waitForState(id, "the volume") { abs(($0["volume"] as? Double ?? 0) - 0.4) < 0.01 }
        try await api.send(id, ["type": "mute", "muted": true])
        state = try await api.waitForState(id, "muted") { $0["muted"] as? Bool == true }
        try await api.send(id, ["type": "mute", "muted": false])
        #else
        XCTAssertNil(state["volume"], "no volume is reported where none can be set")
        // What it never announced is refused before it hears of it.
        do {
            try await api.send(id, ["type": "volume", "level": 0.4])
            XCTFail("volume should be unsupported on Apple TV")
        } catch let refusal as TestAPI.Refusal {
            XCTAssertEqual(refusal.code, "unsupported")
        }
        #endif

        // A track that isn't there is refused in the device's own words.
        do {
            try await api.send(id, ["type": "audio", "audio": "42"])
            XCTFail("a sound track that isn't there should be refused")
        } catch let refusal as TestAPI.Refusal {
            XCTAssertEqual(refusal.code, "refused")
            XCTAssertEqual(refusal.body["error"] as? String, "That sound track isn't there.")
        }

        try await api.send(id, ["type": "stop"])
        state = try await api.waitForState(id, "idle") { $0["status"] as? String == "idle" }
        XCTAssertNotEqual(state["screen"] as? String, "player")
    }

    /// Music goes to the app's music player, with its queue, and moves along it.
    @MainActor
    func testMusicIsPlayedWithItsQueue() async throws {
        let app = try launchApp()
        app.buttons["Home"].firstMatch.shown(30)
        let api = try await TestAPI.signIn()
        var songs: [Int] = []
        for library in try await api.callList("/libraries") where library["type"] as? String == "music" {
            let items = try await api.call("GET", "/items?library=\(library["id"] ?? 0)&limit=10")["items"] as? [[String: Any]] ?? []
            songs = items.compactMap { $0["id"] as? Int }.sorted()
        }
        guard songs.count >= 2 else { throw XCTSkip("The test server has no music.") }
        let found = try await api.appDevice(kinds: deviceKinds)
        let id = try XCTUnwrap(found["id"] as? String)

        try await api.send(id, ["type": "play", "queue": songs, "queueIndex": 0])
        var state = try await api.waitForState(id, "the first song with its queue") {
            $0["itemId"] as? Int == songs[0] && ($0["queue"] as? [Int]) == songs && $0["status"] as? String != "idle"
        }
        try await api.send(id, ["type": "next"])
        state = try await api.waitForState(id, "the second song") { $0["itemId"] as? Int == songs[1] && $0["queueIndex"] as? Int == 1 }
        try await api.send(id, ["type": "pause"])
        state = try await api.waitForState(id, "paused") { $0["status"] as? String == "paused" }
        try await api.send(id, ["type": "stop"])
        state = try await api.waitForState(id, "idle") { $0["status"] as? String == "idle" }
        XCTAssertNil(state["itemId"])
    }

    #if os(tvOS)
    /// The keys of a remote, pressed from another device: Home and Back move about the app's own screens.
    @MainActor
    func testTheRemotesKeysMoveAboutAppleTV() async throws {
        let api = try await TestAPI.signIn()
        let film = try await api.aFilm()
        let app = try launchApp(extra: ["-WMCOpenItem", "\(film.id)"])
        app.buttons["Play"].firstMatch.shown(30)
        let found = try await api.appDevice(kinds: ["tv"])
        let id = try XCTUnwrap(found["id"] as? String)
        var state = try await api.waitForState(id, "a page under Home") { $0["screen"] as? String == "browse" }

        try await api.send(id, ["type": "navigate", "key": "back"])
        state = try await api.waitForState(id, "Home") { $0["screen"] as? String == "home" }
        XCTAssertFalse(app.buttons["Play"].exists)

        // With nothing playing, Play/Pause has nothing to do, and says so.
        do {
            try await api.send(id, ["type": "navigate", "key": "playpause"])
            XCTFail("play/pause with nothing playing should be refused")
        } catch let refusal as TestAPI.Refusal {
            XCTAssertEqual(refusal.code, "refused")
            XCTAssertEqual(refusal.body["error"] as? String, "Nothing is playing.")
        }
        try await api.send(id, ["type": "navigate", "key": "home"])
        _ = state
    }
    #endif

    /// The app as a controller: the list shows another device, starts a film on it, and its remote steers it.
    @MainActor
    func testPlayOnStartsAFilmOnAnotherDeviceAndTheRemoteSteersIt() async throws {
        let api = try await TestAPI.signIn()
        let film = try await api.aFilm()
        let den = StandInDevice(api: api)
        try await den.start(name: "Den")
        addTeardownBlock { await den.stop() }

        let app = try launchApp(extra: ["-WMCOpenItem", "\(film.id)"])
        #if os(tvOS)
        app.buttons["Play"].firstMatch.shown(30)
        let remote = XCUIRemote.shared
        // Along the row of actions to "Play on…".
        for _ in 0..<4 where !app.buttons["play-on"].hasFocus { remote.press(.right) }
        XCTAssertTrue(app.buttons["play-on"].hasFocus, "Play on… should be in the row of actions")
        remote.press(.select)
        app.buttons["play-on-Den"].firstMatch.shown(20)
        for _ in 0..<4 where !app.buttons["play-on-Den"].hasFocus { remote.press(.right) }
        remote.press(.select)
        #else
        let together = app.buttons["together"].firstMatch
        if together.waitForExistence(timeout: 30) { together.tap() }
        app.buttons["play-on"].firstMatch.shown(15).tap()
        app.buttons["play-on-Den"].firstMatch.shown(20).tap()
        #endif

        let played = await den.waitForCommand("play")
        XCTAssertEqual(played?["itemId"] as? Int, film.id, "the device is told to play the film")
        XCTAssertNotNil(played?["sender"], "the server says who sent it")
        app.staticTexts["Playing on Den"].firstMatch.shown(10)

        #if !os(tvOS)
        // Its remote: from You, the list again, then the device.
        app.buttons["You"].firstMatch.shown(10).tap()
        let row = app.buttons["row-devices"].firstMatch
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        app.buttons["device-Den"].firstMatch.shown(20).tap()
        app.staticTexts["remote-title"].firstMatch.shown(10)
        app.buttons["remote-Pause"].firstMatch.shown(10).tap()
        let paused = await den.waitForCommand("pause")
        XCTAssertNotNil(paused, "Pause on the remote reaches the device")
        app.buttons["remote-Play"].firstMatch.shown(10)
        app.buttons["remote-Forward 10 seconds"].firstMatch.tap()
        let sought = await den.waitForCommand("seek")
        XCTAssertEqual(sought?["bySec"] as? Double, 10)
        // It says it has a remote's keys, so the pad is offered.
        let select = app.buttons["pad-select"].firstMatch
        for _ in 0..<4 where !select.isHittable { app.swipeUp() }
        select.tap()
        let key = await den.waitForCommand("navigate")
        XCTAssertEqual(key?["key"] as? String, "select")
        #endif
    }
}
