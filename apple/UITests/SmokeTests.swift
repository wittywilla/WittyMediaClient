// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The first things anyone does: the app opens the server, signs in and shows Home.
final class SmokeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSignedInItShowsHome() throws {
        let app = try launchApp()
        // The bar's Home on a phone or tablet, the top menu's on Apple TV.
        app.buttons["Home"].firstMatch.shown(30)
    }

    @MainActor
    func testWithNobodySignedInItAsksWhoIsWatching() throws {
        let app = try launchApp(signedIn: false)
        app.staticTexts["Who's watching?"].firstMatch.shown(30)
    }
}
