// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

#if os(tvOS)
/// Apple TV: a game started from its page, then left with the remote's Menu. It must stop and come back to the game's
/// page with focus where it was, and the remote must still move focus there (not be held by the player). In an app
/// already signed in on this simulator; `TEST_RUNNER_WMC_GAMES` (a games library) and `TEST_RUNNER_WMC_GAME` (a game in
/// its Continue playing row, or its first) name what to play.
final class GameBackOutTests: XCTestCase {
    @MainActor
    func testMenuLeavesTheGame() throws {
        let env = ProcessInfo.processInfo.environment
        guard let games = env["WMC_GAMES"], let title = env["WMC_GAME_TITLE"] else {
            throw XCTSkip("Set TEST_RUNNER_WMC_GAMES and TEST_RUNNER_WMC_GAME_TITLE, in an app already signed in.")
        }
        guard #available(tvOS 17.0, *) else { throw XCTSkip("Needs tvOS 17.") }
        let app = launchWithCode()
        XCUIDevice.shared.system.open(URL(string: "wittymedia://route/%2Fpage%2Fwittyplay-library%3Flibrary%3D\(games)")!)
        Thread.sleep(forTimeInterval: 6)
        snap("games-library")
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND isEnabled == true", title)).firstMatch
        choose(card, in: app)
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume ' OR label BEGINSWITH 'Play '")).firstMatch
        play.shown(20)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(play.hasFocus, "Focus starts on the game page's Play")
        snap("game-page")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 15)
        snap("game-playing")
        XCTAssertFalse(play.isHittable && play.hasFocus, "The game is on screen")

        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 4)
        snap("game-after-menu")
        // The menu may come first: Menu again leaves (or its Quit does).
        if !play.waitForExistence(timeout: 2) || !play.isHittable {
            let quit = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Quit' OR label CONTAINS[c] 'Leave'")).firstMatch
            if quit.exists { choose(quit, in: app) } else { XCUIRemote.shared.press(.menu) }
            Thread.sleep(forTimeInterval: 5)
            snap("game-after-quit")
        }
        XCTAssertTrue(play.waitForExistence(timeout: 15) && play.isHittable, "Back on the game's page")
        XCTAssertTrue(play.hasFocus, "Focus back on Play")
        // The remote moves focus again: it isn't held by the player.
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(play.hasFocus, "Right moved focus off Play")
        XCUIRemote.shared.press(.left)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(play.hasFocus, "Left brought it back")
        snap("game-page-after")
    }
}
#endif
