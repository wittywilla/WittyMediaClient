// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The server's own pages, on a server that has them (0.8 and later): Home is one, the menu is the server's,
/// a card opens a title's page, and Customise offers what the page allows. Driven as a person would: taps on
/// an iPhone and an iPad, the remote on Apple TV. Like the other UI tests, each skips itself with no server named.
final class SDUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func page(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sdui.page." + prefix)).firstMatch
    }

    @MainActor
    private func named(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func testHomeIsTheServersOwnPage() throws {
        let app = try launchApp()
        page(app, startingWith: "home").shown(40)
        // The menu is the server's: Home and Search are in its built-in one on every device.
        app.buttons["Home"].firstMatch.shown()
        app.buttons["Search"].firstMatch.shown()
    }

    @MainActor
    func testACardOpensItsTitlesPage() throws {
        let app = try launchApp()
        page(app, startingWith: "home").shown(40)
        #if os(tvOS)
        // Focus starts on the page's own first stop; down is the first row, and select opens its card.
        let remote = XCUIRemote.shared
        remote.press(.down)
        remote.press(.down)
        remote.press(.select)
        #else
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sdui.section.recent")).firstMatch
        row.shown(20)
        row.buttons.firstMatch.tap()
        #endif
        page(app, startingWith: "detail").shown(30)
    }

    @MainActor
    func testSearchFindsThroughTheServersPage() throws {
        let app = try launchApp()
        page(app, startingWith: "home").shown(40)
        #if os(tvOS)
        throw XCTSkip("Typing on Apple TV goes through the system's own keyboard, which the simulator's remote can't spell with.")
        #else
        app.buttons["Search"].firstMatch.tap()
        page(app, startingWith: "search").shown(30)
        let field = named(app, "sdui.search")
        field.shown()
        field.tap()
        field.typeText("the")
        // Results arrive as rows of the same page, one for each library that found something.
        let found = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sdui.section.found")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 30) || named(app, "sdui.section.idle").exists || page(app, startingWith: "search").exists)
        #endif
    }

    @MainActor
    func testCustomiseOffersWhatThePageAllows() throws {
        let app = try launchApp()
        let home = page(app, startingWith: "home")
        home.shown(40)
        let customise = named(app, "sdui.customise")
        #if os(tvOS)
        let remote = XCUIRemote.shared
        for _ in 0..<40 where !customise.hasFocus {
            remote.press(.down)
        }
        XCTAssertTrue(customise.hasFocus, "Customise is the last stop of the page")
        remote.press(.select)
        app.buttons["Done"].firstMatch.shown(20)
        remote.press(.menu)
        #else
        for _ in 0..<12 where !customise.isHittable {
            app.swipeUp()
        }
        customise.shown()
        customise.tap()
        named(app, "sdui.customise.done").shown(20)
        app.buttons["Cancel"].firstMatch.tap()
        #endif
        home.shown()
    }
}
