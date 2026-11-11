// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// Signing a device in from another: this app as the device that shows the code, and as the phone that approves
/// it. The other end is played by the test with requests to the test server (see FamilySupport.swift), which
/// has to offer secure pairing, and the account the tests are given has to be its administrator.
final class PairUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A session that can't exist, from a server that isn't the test server.
    private let strangersCode = "wms://pair?v=1&s=not-this-server&u=http%3A%2F%2Fexample.invalid%3A9797&c=0123456789abcdef0123456789abcdef&k=AAAAAAAAAAAAAAAA"

    @MainActor
    func testADeviceShowsItsCodeAndPinAndIsSignedInFromAnother() async throws {
        let phone = try await ServerHand.admin()
        let app = try launchApp(signedIn: false)
        #if !os(tvOS)
        // A TV starts here; a phone has it under the profiles.
        app.buttons["Sign in with a code"].firstMatch.shown(30).tap()
        #endif
        let code = app.staticTexts["pair-code"].firstMatch.shown(30)
        let pin = app.staticTexts["pair-pin"].firstMatch.shown()
        XCTAssertTrue(app.images["Scan this with your phone"].firstMatch.exists, "The QR code isn't there")
        snap("pair-device")
        let letters = code.label.filter(\.isLetter)
        XCTAssertEqual(letters.count, 8)
        XCTAssertEqual(pin.label.filter(\.isNumber).count, 6)

        // The phone asks what is waiting, and is told it takes a PIN.
        let asked = try await phone.send("POST", "/pair/info", ["code": letters])
        XCTAssertEqual(asked["needsPin"] as? Bool, true)
        // The code alone doesn't sign it in, and a wrong PIN doesn't either.
        do {
            try await phone.send("POST", "/pair/approve", ["code": letters, "pin": "000000", "password": TestServer.password])
            XCTFail("A wrong PIN was accepted")
        } catch let refused as ServerHand.Refused {
            XCTAssertEqual(refused.body["reason"] as? String, "wrong-pin")
        }
        XCTAssertTrue(app.staticTexts["pair-pin"].firstMatch.exists, "The device stopped waiting after one wrong PIN")
        try await phone.send("POST", "/pair/approve", ["code": letters, "pin": pin.label.filter(\.isNumber), "password": TestServer.password])
        app.buttons["Home"].firstMatch.shown(30)
    }

    @MainActor
    func testARefusedDeviceSaysSoAndOffersANewCode() async throws {
        let phone = try await ServerHand.admin()
        let app = try launchApp(signedIn: false)
        #if !os(tvOS)
        app.buttons["Sign in with a code"].firstMatch.shown(30).tap()
        #endif
        let letters = app.staticTexts["pair-code"].firstMatch.shown(30).label.filter(\.isLetter)
        try await phone.send("POST", "/pair/deny", ["code": letters])
        app.buttons["Get a new code"].firstMatch.shown(30)
        snap("pair-refused")
        choose(app.buttons["Get a new code"].firstMatch, in: app)
        let again = app.staticTexts["pair-code"].firstMatch.shown(30).label.filter(\.isLetter)
        XCTAssertNotEqual(again, letters)
    }

    #if !os(tvOS)
    @MainActor
    func testAScannedCodeIsApprovedWithThePinAndThePassword() async throws {
        let admin = try await ServerHand.admin()
        let tv = ServerHand(base: admin.base)
        let started = try await tv.send("POST", "/auth/pair", ["device": "UI test TV", "platform": "tvOS"])
        let session = try XCTUnwrap(started["sessionId"] as? String)
        let secret = ["X-WMS-Pair-Secret": try XCTUnwrap(started["deviceSecret"] as? String)]
        // What the camera would have read off the TV's screen.
        let app = try launchApp(extra: ["-WMCOpen", "signInTv", "-WMCScan", try XCTUnwrap(started["qr"] as? String)])
        let device = app.descendants(matching: .any)["pair-device"].firstMatch.shown(30)
        XCTAssertTrue(device.label.contains("UI test TV"), device.label)
        snap("pair-approve")

        // A wrong PIN first: the server's words, and how many tries are left.
        app.typeText("000000")
        let password = app.secureTextFields.firstMatch.shown()
        password.tap()
        password.typeText(TestServer.password)
        app.buttons["Sign in the TV"].firstMatch.tap()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tries left'")).firstMatch.shown()
        snap("pair-wrong-pin")

        // Then the one the TV shows now.
        let now = try await tv.send("GET", "/auth/pair/\(session)/pin", headers: secret)
        app.descendants(matching: .any)["The PIN on its screen"].firstMatch.tap()
        app.typeText(try XCTUnwrap(now["pin"] as? String))
        app.buttons["Sign in the TV"].firstMatch.tap()
        app.staticTexts["The TV is signing in now."].firstMatch.shown()
        let answer = try await tv.send("GET", "/auth/pair/\(session)", headers: secret)
        XCTAssertEqual(answer["status"] as? String, "approved")
        XCTAssertFalse((answer["token"] as? String ?? "").isEmpty)
    }

    @MainActor
    func testACodeForAnotherServerIsRefusedAndNothingIsSent() throws {
        let app = try launchApp(extra: ["-WMCOpen", "signInTv", "-WMCScan", strangersCode])
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'another server'")).firstMatch.shown(30)
        XCTAssertFalse(app.descendants(matching: .any)["pair-device"].firstMatch.exists)
        snap("pair-other-server")
    }

    @MainActor
    func testATypedCodeStillSignsADeviceIn() async throws {
        let admin = try await ServerHand.admin()
        let tv = ServerHand(base: admin.base)
        // The older way: a code and no PIN. A server that allows only PINs refuses this, and there is nothing to test.
        let started: [String: Any]
        do {
            started = try await tv.send("POST", "/pair/start", ["device": "UI test old TV", "platform": "tvOS"])
        } catch let refused as ServerHand.Refused where refused.status == 426 {
            throw XCTSkip("This server signs devices in with a PIN only.")
        }
        let letters = try XCTUnwrap(started["code"] as? String).filter(\.isLetter)
        let app = try launchApp(extra: ["-WMCOpen", "signInTv"])
        app.staticTexts["Sign in a TV"].firstMatch.shown(30)
        app.typeText(letters)
        let device = app.descendants(matching: .any)["pair-device"].firstMatch.shown()
        XCTAssertTrue(device.label.contains("UI test old TV"), device.label)
        // An administrator signing it in as themselves gives their password again.
        let password = app.secureTextFields.firstMatch.shown()
        password.tap()
        password.typeText(TestServer.password)
        app.buttons["Sign in the TV"].firstMatch.tap()
        app.staticTexts["The TV is signing in now."].firstMatch.shown()
        let answer = try await tv.send("POST", "/pair/poll", ["deviceSecret": try XCTUnwrap(started["deviceSecret"] as? String)])
        XCTAssertEqual(answer["status"] as? String, "approved")
    }
    #endif
}
