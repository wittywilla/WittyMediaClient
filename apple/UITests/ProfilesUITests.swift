// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// Profiles on a shared screen and parental controls: switching, what a Kids profile is shown, its screen time
/// running out, and the pages a parent sets it all on. Each test makes a Kids profile of its own on the test
/// server and removes it, so a day's screen time is never left used up for the next run.
final class ProfilesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func kid(_ admin: ServerHand, _ access: [String: Any]) async throws -> (id: Int64, name: String) {
        let made = try await admin.makeKid(access)
        addTeardownBlock { await admin.remove(user: made.id) }
        return made
    }

    @MainActor
    func testSwitchingProfileSignsThisDeviceInAsTheOther() async throws {
        let admin = try await ServerHand.admin()
        let made = try await kid(admin, ["maxAge": 7, "allowUnrated": true])
        let app = try launchApp(extra: ["-WMCOpen", "switch"])
        let tile = app.buttons["switch-\(made.name)"].firstMatch.shown(30)
        snap("switch-who")
        // No password, on the home network: a press is enough.
        choose(tile, in: app)
        // The whole app is drawn again for the new profile, at Home.
        app.buttons["Home"].firstMatch.shown(30)
        choose(app.buttons["You"].firstMatch, in: app)
        app.staticTexts["Test kid"].firstMatch.shown()
        snap("switch-done")
        // A Kids profile doesn't sign TVs in, and has no profiles to manage.
        XCTAssertFalse(app.buttons["Profiles and parental limits"].firstMatch.exists)
        #if !os(tvOS)
        // Going back takes the first profile's password, so a child handed the device can't.
        app.buttons["Switch profile"].firstMatch.tap()
        app.buttons["switch-\(TestServer.user)"].firstMatch.shown().tap()
        let password = app.secureTextFields.firstMatch.shown()
        password.tap()
        password.typeText("not-the-password")
        app.buttons["Switch"].firstMatch.tap()
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Problem:'")).firstMatch.shown()
        snap("switch-wrong-password")
        password.tap()
        password.typeText(TestServer.password)
        app.buttons["Switch"].firstMatch.tap()
        app.buttons["Home"].firstMatch.shown(30)
        app.buttons["You"].firstMatch.tap()
        app.buttons["Profiles and parental limits"].firstMatch.shown()
        #endif
    }

    @MainActor
    func testAKidsProfileIsNotOfferedWhatIsTurnedOff() async throws {
        let admin = try await ServerHand.admin()
        let made = try await kid(admin, ["maxAge": 7, "allowUnrated": true, "liveTv": false, "off": ["games", "sharing", "editProfile"]])
        let app = try launchApp(user: made.name, password: "")
        app.buttons["Home"].firstMatch.shown(30)
        // The limits arrive a moment after the first screen.
        #if os(tvOS)
        let gone = [app.buttons["Games"].firstMatch, app.buttons["Live TV"].firstMatch]
        #else
        let gone = [app.buttons["TV guide"].firstMatch]
        #endif
        for tab in gone {
            XCTAssertTrue(tab.waitForNonExistence(timeout: 15), "\(tab) is still offered")
        }
        snap("kids-home")
        choose(app.buttons["You"].firstMatch, in: app)
        app.staticTexts["Test kid"].firstMatch.shown()
        XCTAssertFalse(app.buttons["Your picture"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Share links"].firstMatch.exists)
        snap("kids-you")
    }

    @MainActor
    func testWhenScreenTimeRunsOutPlayingStopsAndAParentCanGiveMore() async throws {
        let admin = try await ServerHand.admin()
        // A minute a day, so the time really runs out while the test watches.
        let made = try await kid(admin, ["maxAge": 16, "allowUnrated": true, "time": ["schoolDayMinutes": 1, "weekendMinutes": 1]])
        try await admin.send("PUT", "/parental/pin", ["pin": "4321", "current": TestServer.password])
        var child = ServerHand(base: admin.base)
        let signedIn = try await child.send("POST", "/login", ["name": made.name, "password": "", "device": "UI tests"])
        child.token = try XCTUnwrap(signedIn["token"] as? String)
        let home = try await child.send("GET", "/items?limit=50")
        let films = (home["items"] as? [[String: Any]] ?? []).filter { ($0["kind"] as? String) == "video" }
        // The longest there is: it has to outlast the minute.
        let film = try XCTUnwrap(films.max { (($0["durationSec"] as? Double) ?? 0) < (($1["durationSec"] as? Double) ?? 0) }, "The test server has no video this profile can see")
        let id = try XCTUnwrap((film["id"] as? NSNumber)?.int64Value)

        let app = try launchApp(user: made.name, password: "", extra: ["-WMCOpen", "player:\(id)"])
        // With a minute left it is told so straight away.
        app.staticTexts["screen-time-left"].firstMatch.shown(30)
        snap("time-left")
        let title = app.staticTexts["time-up-title"].firstMatch.shown(150)
        XCTAssertEqual(title.label, "Screen time is up")
        snap("time-up")
        // The player has gone: its place was kept, and the profile is back among the pages.
        let state = try await child.send("GET", "/me/screen-time")
        XCTAssertEqual(state["allowed"] as? Bool, false)

        #if os(tvOS)
        // From the parent's own device: the screen goes by itself once the server says there is time again.
        try await admin.send("POST", "/users/\(made.id)/screen-time/extra", ["minutes": 15])
        XCTAssertTrue(title.waitForNonExistence(timeout: 90), "The time-up screen stayed after a parent gave more time")
        #else
        app.buttons["Ask a parent"].firstMatch.tap()
        let pin = app.secureTextFields.firstMatch.shown()
        pin.tap()
        pin.typeText("0000")
        app.buttons["Give more time"].firstMatch.tap()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'parents'")).firstMatch.shown()
        snap("time-wrong-pin")
        pin.tap()
        pin.typeText("4321")
        app.buttons["Give more time"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 20), "The time-up screen stayed after the right PIN")
        #endif
        let after = try await child.send("GET", "/me/screen-time")
        XCTAssertEqual(after["allowed"] as? Bool, true)
        snap("time-given")
    }

    @MainActor
    func testAParentChangesOneLimitAndTheRestStays() async throws {
        let admin = try await ServerHand.admin()
        let made = try await kid(admin, ["maxAge": 10, "allowUnrated": false, "blockGenres": ["Horror"], "kinds": ["game": ["maxAge": 7, "allowUnrated": false]],
                                         "off": ["editProfile"], "time": ["schoolDayMinutes": 45, "weekendMinutes": 120, "schoolNightUntil": "20:00"]])
        let app = try launchApp(extra: ["-WMCOpen", "limits:\(made.id):allowed"])
        let games = app.buttons["switch-games"].firstMatch.shown(30)
        XCTAssertEqual(games.value as? String, "On")
        snap("limits-do")
        choose(games, in: app)
        XCTAssertEqual(games.value as? String, "Off")
        choose(app.buttons["limits-save"].firstMatch, in: app)
        app.staticTexts["Limits saved."].firstMatch.shown()
        let users = try await admin.list("/users")
        let access = try XCTUnwrap(users.first { ($0["id"] as? NSNumber)?.int64Value == made.id }?["access"] as? [String: Any])
        XCTAssertEqual(Set(access["off"] as? [String] ?? []), ["editProfile", "games"])
        XCTAssertEqual(access["maxAge"] as? Int, 10)
        XCTAssertEqual(access["blockGenres"] as? [String], ["Horror"])
        XCTAssertEqual((access["time"] as? [String: Any])?["schoolDayMinutes"] as? Int, 45)
        XCTAssertEqual((access["time"] as? [String: Any])?["schoolNightUntil"] as? String, "20:00")
        XCTAssertEqual(((access["kinds"] as? [String: Any])?["game"] as? [String: Any])?["maxAge"] as? Int, 7)
    }

    @MainActor
    func testTheProfilesPageListsWhoIsManagedAndTheReportGivesTime() async throws {
        let admin = try await ServerHand.admin()
        let made = try await kid(admin, ["maxAge": 7, "allowUnrated": true, "time": ["schoolDayMinutes": 60, "weekendMinutes": 60]])
        let app = try launchApp(extra: ["-WMCOpen", "profiles"])
        let row = app.buttons["profile-\(made.name)"].firstMatch.shown(30)
        XCTAssertTrue(app.buttons["parents-pin"].firstMatch.exists)
        XCTAssertTrue(app.buttons["profile-add"].firstMatch.exists)
        snap("profiles")
        choose(row, in: app)
        app.buttons["Screen time"].firstMatch.shown()
        snap("profile")
        choose(app.buttons["Screen time"].firstMatch, in: app)
        app.staticTexts["School days"].firstMatch.shown()
        snap("limits-time")
        #if os(tvOS)
        XCUIRemote.shared.press(.menu)
        #else
        app.buttons["Back"].firstMatch.tap()
        #endif
        choose(app.buttons["Report"].firstMatch, in: app)
        app.staticTexts["report-today"].firstMatch.shown()
        choose(app.buttons["give-15"].firstMatch, in: app)
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'more today'")).firstMatch.shown()
        snap("report")
        let report = try await admin.send("GET", "/users/\(made.id)/activity")
        let events = report["events"] as? [[String: Any]] ?? []
        XCTAssertTrue(events.contains { ($0["kind"] as? String) == "extra" && ($0["detail"] as? String) == "15" }, "\(events)")
    }
}
