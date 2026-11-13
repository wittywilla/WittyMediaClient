// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// Drives the app as a person would (the Siri Remote on Apple TV, taps elsewhere) and saves a picture after each step, for
/// comparing with the design canvas (docs/design-2/images). Like the other UI tests it needs a server (see Support.swift) and
/// says where to put the pictures:
///
///   TEST_RUNNER_WMC_SERVER=http://localhost:19900 TEST_RUNNER_WMC_USER=name TEST_RUNNER_WMC_PASSWORD=word \
///   TEST_RUNNER_WMC_SHOTS=/some/folder xcodebuild test -project WittyMedia.xcodeproj -scheme WittyMedia-tvOS \
///     -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -only-testing:WittyMedia-tvOS-UITests/ScreenshotTests
///
/// Without `WMC_SHOTS` the pictures are only attached to the test result.
final class ScreenshotTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// One picture: attached to the result, and written as `<folder>/<name>.png` when a folder is named.
    @MainActor
    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["WMC_SHOTS"], !folder.isEmpty {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
    }

    /// A look, as the server has it for this installation: `WMC_DEVICE_ID` names the installation (the app takes it as its own name
    /// with the server, `-sdui.deviceId`), and the script that runs this sets that name's experience first
    /// (`PUT /sdui/experience?device=<name>`). The pictures are named after `WMC_LOOK`.
    @MainActor
    func testLook() throws {
        let env = ProcessInfo.processInfo.environment
        guard let device = env["WMC_DEVICE_ID"], !device.isEmpty else { throw XCTSkip("No installation name: set TEST_RUNNER_WMC_DEVICE_ID.") }
        let look = env["WMC_LOOK"] ?? "look"
        // The first-connect chooser is skipped (its "seen" mark is set for this server and person, as choosing would): the look under
        // test is the one the script put on the server for this installation.
        let server = env["WMC_SERVER"] ?? ""
        let app = try launchApp(extra: ["-sdui.deviceId", device, "-lookSeen|\(server)|1", "YES"])
        _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sdui.page.home")).firstMatch.waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 3)
        shoot("\(look)-1-home")
        #if os(tvOS)
        XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.6)
        XCUIRemote.shared.press(.down); Thread.sleep(forTimeInterval: 0.8)
        shoot("\(look)-2-shelf")
        // Back to the menu: along it, to its second place.
        XCUIRemote.shared.press(.menu); Thread.sleep(forTimeInterval: 0.8)
        XCUIRemote.shared.press(.left); Thread.sleep(forTimeInterval: 0.8)
        shoot("\(look)-3-menu")
        #else
        // A library's entry in the menu (a rail opens its drawer), where there is one.
        let library = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "frame.entry.lib")).firstMatch
        if library.waitForExistence(timeout: 3) { library.tap(); Thread.sleep(forTimeInterval: 1.5); shoot("\(look)-2-library-entry") }
        #endif
    }

    #if os(tvOS)
    /// Presses, one after another, with a moment between for focus to settle and the lift to finish.
    @MainActor
    private func press(_ buttons: XCUIRemote.Button...) {
        for button in buttons {
            XCUIRemote.shared.press(button)
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    @MainActor
    func testAppleTvTour() throws {
        let app = try launchApp()
        _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sdui.page.home")).firstMatch.waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 2)
        shoot("01-home")
        // Down into the first shelf: the card's ring and lift.
        press(.down, .down)
        shoot("02-home-shelf-focus")
        // Along the shelf, to see the peek of the next card and the See all card.
        press(.right, .right, .right)
        shoot("03-home-shelf-right")
        // Up to the bar and along it.
        press(.up, .up, .up, .up)
        shoot("04-bar-focus")
        press(.right, .right, .right)
        shoot("05-bar-libraries")
        // Open Libraries, then a library: the grid with its filter bar and the Dock.
        press(.select)
        shoot("06-libraries")
        press(.down, .select)
        Thread.sleep(forTimeInterval: 3)
        shoot("07-library-grid")
        press(.down, .down, .down)
        shoot("08-library-dock-or-row")
        press(.menu)
        shoot("09-back")
        // The server's name stays in the frame: the You page.
        press(.menu, .menu)
        shoot("10-after-back")
    }
    #else
    @MainActor
    func testTouchTour() throws {
        let app = try launchApp()
        _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sdui.page.home")).firstMatch.waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 2)
        shoot("01-home")
        app.swipeUp()
        shoot("02-home-scrolled")
        let search = app.buttons["Search"].firstMatch
        if search.waitForExistence(timeout: 5) { search.tap(); Thread.sleep(forTimeInterval: 2); shoot("03-search") }
    }
    #endif
}
