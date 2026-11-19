// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// The server's TV levels (WittyMediaServer 0.8.1, docs/TV-MODE.md), as Android's TvLevelsTest checks them.
final class TvLevelsTests: XCTestCase {
    /// A piece of the server's own table (pkg/sdui/data/tvlevels.json), as the catalogue carries it.
    private let catalogue = #"""
    {"revision":8,"cardStyles":[],"routes":[],"commands":[],
     "tvLevels":{"levels":["full","view","desktopOnly"],"default":"full",
      "note":"To change this, use the WittyMediaClient app on a Windows or Mac computer, or a web browser.",
      "noteDesktop":"Leave TV mode to change this.",
      "screens":[{"id":"settings.libraries","path":"/settings/libraries","level":"desktopOnly","title":"Libraries","summary":"libraries"},
       {"id":"settings.pages","path":"/settings/pages/*","level":"desktopOnly","title":"Pages and menu"},
       {"id":"settings.playback","path":"/settings/playback","level":"view","title":"Playback"},
       {"id":"item.edit","path":"/item/:id/edit","level":"desktopOnly","title":"Edit details"},
       "not a row"],
      "parts":[{"id":"layout.editor","level":"desktopOnly"},{"id":"games.controllers","level":"full"}]}}
    """#

    private func table() throws -> TvLevelTable {
        try XCTUnwrap(JSONDecoder().decode(SDUICatalog.self, from: Data(catalogue.utf8)).tvLevels)
    }

    func testTheCatalogueCarriesTheTable() throws {
        let levels = try table()
        XCTAssertEqual(levels.note, "To change this, use the WittyMediaClient app on a Windows or Mac computer, or a web browser.")
        XCTAssertEqual(levels.screens.count, 4, "a row that can't be read is left out")
        XCTAssertNil(try JSONDecoder().decode(SDUICatalog.self, from: Data(#"{"cardStyles":[],"routes":[],"commands":[]}"#.utf8)).tvLevels,
                     "an older server has no table")
    }

    func testAddressesMatchAsOnTheServer() {
        XCTAssertTrue(TvLevels.matches("/settings/libraries", "/settings/libraries"))
        XCTAssertTrue(TvLevels.matches("/settings/libraries", "/settings/libraries/?tab=2"))
        XCTAssertFalse(TvLevels.matches("/settings/libraries", "/settings/libraries/3"))
        XCTAssertTrue(TvLevels.matches("/settings/pages/*", "/settings/pages"))
        XCTAssertTrue(TvLevels.matches("/settings/pages/*", "/settings/pages/home/rows"))
        XCTAssertTrue(TvLevels.matches("/item/:id/edit", "/item/42/edit#cast"))
        XCTAssertFalse(TvLevels.matches("/item/:id/edit", "/item/42"))
    }

    func testEditorsAreForAComputerAndTheRestOpens() throws {
        let levels = try table()
        XCTAssertTrue(TvLevels.isDesktopOnly(levels, "/settings/libraries"))
        XCTAssertEqual(levels.screen(for: "/settings/libraries")?.summary, "libraries")
        XCTAssertFalse(TvLevels.isDesktopOnly(levels, "/settings/playback"), "a page a TV can look at")
        XCTAssertFalse(TvLevels.isDesktopOnly(levels, "/settings/controllers"), "not in the table: full")
        XCTAssertFalse(TvLevels.isDesktopOnly(nil, "/settings/libraries"), "an older server says nothing")
        XCTAssertFalse(TvLevels.partOpens(levels, "layout.editor"))
        XCTAssertTrue(TvLevels.partOpens(levels, "games.controllers"))
        XCTAssertTrue(TvLevels.partOpens(levels, "brand.editor"))
        XCTAssertTrue(TvLevels.partOpens(nil, "layout.editor"))
    }

    func testTheCardsAddressIsOneAPhoneCanOpen() {
        XCTAssertEqual(TvLevels.cardAddress(base: "http://192.168.1.5:9797", path: "/settings/libraries", home: ["http://10.0.0.2:9797"]),
                       "http://192.168.1.5:9797/settings/libraries")
        XCTAssertEqual(TvLevels.cardAddress(base: "http://127.0.0.1:9797/", path: "settings/libraries", home: ["http://192.168.1.5:9797/"]),
                       "http://192.168.1.5:9797/settings/libraries")
        XCTAssertEqual(TvLevels.cardAddress(base: "http://[::1]:9797", path: "/x", home: ["http://192.168.1.5:9797"]), "http://192.168.1.5:9797/x")
        XCTAssertEqual(TvLevels.cardAddress(base: "http://tv.localhost:9797", path: "/x", home: []), "http://tv.localhost:9797/x")
    }

    func testASummaryReadsWithItsNulls() throws {
        let read = try JSONDecoder().decode(TvSummary.self, from: Data(#"{"id":"libraries","lines":["Movies · 2 folders"],"addresses":null}"#.utf8))
        XCTAssertEqual(read.lines, ["Movies · 2 folders"])
        XCTAssertEqual(read.addresses, [])
    }
}
