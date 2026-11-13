// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// Pictures of a look (docs/design-2/images) in the running app, for comparing: Home, Home scrolled, You, the layout editor with a
/// part picked up, and the server's name editor. Like ScreenshotTests it needs a server (see Support.swift) and a folder:
///
///   TEST_RUNNER_WMC_SERVER=http://localhost:19840 TEST_RUNNER_WMC_USER=name TEST_RUNNER_WMC_PASSWORD=word \
///   TEST_RUNNER_WMC_SHOTS=/some/folder TEST_RUNNER_WMC_LOOK=aero xcodebuild test-without-building -project WittyMedia.xcodeproj \
///     -scheme WittyMedia-iOS -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:WittyMedia-iOS-UITests/LookTests
///
/// `WMC_LOOK` is only the picture names' prefix: the server decides which look is drawn.
final class LookTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    @MainActor
    private func shoot(_ name: String) {
        let prefix = ProcessInfo.processInfo.environment["WMC_LOOK"] ?? "look"
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(prefix)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["WMC_SHOTS"], !folder.isEmpty {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(prefix)-\(name).png"))
        }
    }

    private func anything(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    #if os(tvOS)
    @MainActor
    private func press(_ buttons: XCUIRemote.Button...) {
        for button in buttons {
            XCUIRemote.shared.press(button)
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    @MainActor
    func testLookOnTv() throws {
        let app = try launchApp()
        _ = anything(app, "sdui.page.home").waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 3)
        shoot("tv-01-home")
        // Down through the shelves: titles must not run under the bar unreadable.
        press(.down, .down, .down, .down, .down, .down)
        Thread.sleep(forTimeInterval: 1)
        shoot("tv-02-home-scrolled")
    }
    #else
    @MainActor
    func testLookOnTouch() throws {
        let app = try launchApp()
        _ = anything(app, "sdui.page.home").waitForExistence(timeout: 40)
        Thread.sleep(forTimeInterval: 3)
        shoot("01-home")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        shoot("02-home-scrolled")
        app.swipeDown()
        // You, then the layout editor.
        let you = app.buttons["You"].firstMatch
        if you.waitForExistence(timeout: 5) { you.tap() }
        Thread.sleep(forTimeInterval: 2)
        shoot("03-you")
        let layout = anything(app, "row.layoutEditor")
        for _ in 0..<6 where !layout.exists || !layout.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 0.4) }
        if layout.waitForExistence(timeout: 5) {
            layout.tap()
            Thread.sleep(forTimeInterval: 4)
            shoot("04-layout-editor")
            let nav = anything(app, "layout.r:nav")
            if nav.waitForExistence(timeout: 5) {
                nav.tap()
                Thread.sleep(forTimeInterval: 1)
                shoot("05-layout-picked-up")
                nav.tap()
            }
            app.navigationBars.buttons.firstMatch.tap()
        }
        Thread.sleep(forTimeInterval: 1)
        let brand = anything(app, "row.brandEditor")
        for _ in 0..<8 where !brand.exists || !brand.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 0.4) }
        if brand.waitForExistence(timeout: 5) {
            brand.tap()
            Thread.sleep(forTimeInterval: 4)
            shoot("06-brand-editor")
            app.swipeUp()
            shoot("07-brand-editor-2")
            app.swipeUp()
            shoot("08-brand-editor-3")
        }
    }
    #endif
}
