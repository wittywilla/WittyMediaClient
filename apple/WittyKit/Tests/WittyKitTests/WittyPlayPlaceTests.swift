// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class WittyPlayPlaceTests: XCTestCase {
    func testWittyPlaysAddressesAreTheWebsites() {
        for path in ["/page/wittyplay-online", "/page/wittyplay-online?tab=together", "/page/wittyplay", "/page/wittyplay-controllers",
                     "/wittyplay/library/4", "/wittyplay/settings", "/wittyplay/game/12"] {
            XCTAssertTrue(WittyPlayPlace.isPlayPath(path), path)
        }
        for path in ["/", "/library/4", "/game/12", "/page/home", "/page/wittyplayer", "/search"] {
            XCTAssertFalse(WittyPlayPlace.isPlayPath(path), path)
        }
        XCTAssertEqual(WittyPlayPlace.library(4), "/wittyplay/library/4")
    }

    func testInstalledWhenTheMenuHasWittyPlay() {
        XCTAssertTrue(WittyPlayPlace.installed(routes: ["/", "/search", "/page/wittyplay-online"]))
        XCTAssertFalse(WittyPlayPlace.installed(routes: ["/", "/search", "/library/2"]))
        XCTAssertTrue(WittyPlayPlace.isPlayPage("wittyplay-online"))
        XCTAssertFalse(WittyPlayPlace.isPlayPage("library"))
    }
}
