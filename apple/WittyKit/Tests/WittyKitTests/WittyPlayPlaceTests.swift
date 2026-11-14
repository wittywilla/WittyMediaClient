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

    func testAnAddressAsAPageForApplesTv() {
        XCTAssertEqual(WittyPlayPlace.page(for: "/page/wittyplay-online").page, "wittyplay-online")
        XCTAssertEqual(WittyPlayPlace.page(for: "/page/wittyplay-online?tab=together").params, ["tab": "together"])
        XCTAssertEqual(WittyPlayPlace.page(for: "/page/wittyplay-controllers").page, "wittyplay-controllers")
        XCTAssertEqual(WittyPlayPlace.page(for: "/wittyplay/library/3").page, "wittyplay-online", "no page for a library's own view")
    }
}

final class SDUIRegionsTests: XCTestCase {
    private let json = #"""
    {"statusBar":[{"id":"me","kind":"profile","text":"WittyPlay Online"},{"id":"server","kind":"server"}],
     "systemDock":[{"id":"search","label":"Search","icon":"search","route":"/search"},
                   {"id":"together","label":"Together","icon":"users","route":"/page/wittyplay-online?tab=together"},
                   {"id":"controllers","label":"Controllers","icon":"devices","route":"/page/wittyplay-controllers","as":"layer"}]}
    """#

    func testReadsWittyPlaysRegionsAndPutsHomeFirst() throws {
        let r = try JSONDecoder().decode(SDUIRegions.self, from: Data(json.utf8))
        XCTAssertEqual(r.statusBar.map(\.kind), ["profile", "server"])
        XCTAssertEqual(r.dock.map(\.id), ["home", "search", "together", "controllers"])
        XCTAssertEqual(r.dock[3].as, "layer")
        XCTAssertFalse(r.isEmpty)
        XCTAssertTrue(SDUIRegions().isEmpty)
    }

    func testTheCurrentEntryIsTheWebsites() throws {
        let r = try JSONDecoder().decode(SDUIRegions.self, from: Data(json.utf8))
        XCTAssertEqual(r.current(path: "/page/wittyplay-online"), 0, "the page with no tab is Home")
        XCTAssertEqual(r.current(path: "/page/wittyplay-online", query: ["tab": "together"]), 2)
        XCTAssertEqual(r.current(path: "/page/wittyplay-controllers"), 3)
        XCTAssertNil(r.current(path: "/library/2"))
    }
}
