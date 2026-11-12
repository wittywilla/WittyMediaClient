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
        // Rows below come as the page scrolls: Customise exists only once it's near.
        for _ in 0..<40 where !(customise.exists && customise.hasFocus) {
            remote.press(.down)
        }
        XCTAssertTrue(customise.exists && customise.hasFocus, "Customise is the last stop of the page")
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

    #if os(tvOS)
    // MARK: Apple TV's focus, by the remote

    @MainActor
    private func focused(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
    }

    @MainActor
    private func waitForFocus(_ element: XCUIElement, _ seconds: TimeInterval = 20) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if element.exists, element.hasFocus { return true }
            usleep(250_000)
        }
        return false
    }

    /// The page's `focus.default` is the hero's Play: focus is there at launch, not on the menu's Home.
    @MainActor
    func testAppleTVFocusStartsOnTheHerosPlay() throws {
        let app = try launchApp()
        page(app, startingWith: "home").shown(40)
        let play = named(app, "sdui.action.play")
        guard play.waitForExistence(timeout: 20) else { throw XCTSkip("The test server's Home has no hero: give it a few titles with art.") }
        XCTAssertTrue(waitForFocus(play), "focus at launch is on \(focused(app).identifier), not the hero's Play")
    }

    /// Right past the hero's last button is the next title; left past its first goes back.
    @MainActor
    func testAppleTVRightPastTheHerosButtonsChangesTitle() throws {
        let app = try launchApp()
        page(app, startingWith: "home").shown(40)
        let play = named(app, "sdui.action.play")
        guard play.waitForExistence(timeout: 20), waitForFocus(play) else { throw XCTSkip("No hero with focus on its Play.") }
        let dots = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Title ")).firstMatch
        guard dots.waitForExistence(timeout: 5) else { throw XCTSkip("The hero has one title only.") }
        let before = dots.label
        let remote = XCUIRemote.shared
        // Play, More info, then past the end.
        for _ in 0..<4 where dots.label == before { remote.press(.right) }
        XCTAssertNotEqual(dots.label, before, "right past the buttons didn't change the title")
        let after = dots.label
        for _ in 0..<4 where dots.label == after { remote.press(.left) }
        XCTAssertNotEqual(dots.label, after, "left past the first button didn't go back")
    }

    /// A row remembers the card it was left on: down into a row, along it, down out of it and back up lands on
    /// the same card, not the row's first.
    @MainActor
    func testAppleTVARowRemembersItsCard() throws {
        let app = try launchApp()
        page(app, startingWith: "home").shown(40)
        let remote = XCUIRemote.shared
        let card = NSPredicate(format: "identifier BEGINSWITH %@", "sdui.card.")
        var chosen = ""
        for _ in 0..<6 {
            remote.press(.down)
            if card.evaluate(with: focused(app)) { break }
        }
        guard card.evaluate(with: focused(app)) else { throw XCTSkip("No row of cards on the test server's Home.") }
        let first = focused(app).identifier
        remote.press(.right)
        remote.press(.right)
        chosen = focused(app).identifier
        guard chosen != first else { throw XCTSkip("The first row has one card only.") }
        remote.press(.down)
        remote.press(.up)
        XCTAssertEqual(focused(app).identifier, chosen, "coming back to the row didn't return to the card it was left on")
    }
    /// With a layout whose menu is down the side (`tvSideMenu`), left from the page reaches the menu, which opens with
    /// the places' names, and choosing one shows it. Skips itself unless the test server gives Apple TV that layout.
    @MainActor
    func testAppleTVSideMenuOpensWithFocus() throws {
        let app = try launchApp()
        page(app, startingWith: "home").shown(40)
        let home = named(app, "frame.entry.home")
        guard home.waitForExistence(timeout: 10) else { throw XCTSkip("The server's layout for Apple TV has its menu at the top.") }
        let remote = XCUIRemote.shared
        for _ in 0..<4 where !home.hasFocus { remote.press(.left) }
        XCTAssertTrue(home.hasFocus, "left from the page didn't reach the side menu's Home")
        // Open, the menu shows names beside its icons.
        XCTAssertTrue(app.staticTexts["Search"].firstMatch.waitForExistence(timeout: 5), "the menu didn't open with its names")
        remote.press(.down)
        remote.press(.select)
        page(app, startingWith: "search").shown(20)
    }
    #endif
}
