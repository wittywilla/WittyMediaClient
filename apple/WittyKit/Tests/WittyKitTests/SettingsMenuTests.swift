// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// The settings menu every client draws (shared/data/settingsmenu.json, the server's own): the You page on iPhone,
/// iPad and Apple TV is drawn from it, as Android's is.
final class SettingsMenuTests: XCTestCase {
    private func shared(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("shared/data/" + name))
    }

    private func menu() throws -> SettingsMenu { try XCTUnwrap(SettingsMenu.bundled(try shared("settingsmenu.json"))) }

    private let admin: Set<String> = ["admin", "adult", "twoStep", "games", "app", "servers", "fromAway", "looks", "layoutEditor", "moduleSettings", "remote", "parties"]

    func testTheGroupsAreTheAndroidAppsInItsOrder() throws {
        let groups = try menu().visible(facts: admin)
        XCTAssertEqual(groups.map(\.key), ["groupAccount", "groupHousehold", "groupYours", "groupModules", "groupDevice", "groupServer", "groupMaintenance", "groupHelp"])
        XCTAssertEqual(groups[0].rows.map(\.key), ["rowNames", "rowPassword", "rowTwoStep", "rowDevices"])
        XCTAssertEqual(groups.first { $0.id == "device" }?.rows.map(\.key), ["rowLayout", "rowEditLayout", "rowTheme", "rowServers", "rowAway", "rowPlayingHere"])
        XCTAssertEqual(groups.last?.rows.last?.key, "rowAppLog")
        XCTAssertEqual(groups.first { $0.id == "modules" }?.rows.map(\.key), ["rowModuleSettings", "rowModuleStore"], "module settings and the store side by side")
    }

    func testEveryRowHasAnSFSymbolAndWords() throws {
        let words = try JSONDecoder().decode([String: String].self, from: try shared("strings.en.json"))
        for g in try menu().groups {
            XCTAssertNotNil(words[g.key], g.key)
            for r in g.rows {
                XCTAssertFalse(r.icon.apple.isEmpty, r.id)
                XCTAssertNotNil(words[r.key], r.key)
            }
        }
    }

    func testKidsAndATv() throws {
        let kid = try menu().visible(facts: ["app", "servers"], off: ["sharing", "activity"])
        XCTAssertEqual(kid.map(\.id), ["account", "yours", "device", "help"])
        XCTAssertEqual(kid[0].rows.map(\.id), ["names", "devices"])
        let tv = try menu().visible(facts: admin.union(["tv"])).flatMap(\.rows).map(\.id)
        XCTAssertFalse(tv.contains("signInTv"))
        XCTAssertTrue(tv.contains("topMenu"))
        XCTAssertFalse(SettingsMenu.holds("someday", facts: admin, off: []))
    }

    func testWhatATvMayChange() throws {
        let table = TvLevelTable(screens: [
            TvScreenLevel(id: "settings.remote", path: "/settings/remote", level: TvLevel.desktopOnly, title: "Remote Access", summary: "remote"),
            TvScreenLevel(id: "settings.playback", path: "/settings/playback", level: TvLevel.view, title: "Playback"),
        ], parts: [TvPartLevel(id: "app.brand-editor", level: TvLevel.desktopOnly)])
        let rows = Dictionary(uniqueKeysWithValues: try menu().groups.flatMap(\.rows).map { ($0.id, $0) })
        XCTAssertEqual(SettingsMenu.level(of: rows["remote"]!, in: table), TvLevel.desktopOnly)
        XCTAssertEqual(SettingsMenu.level(of: rows["nameAndLogo"]!, in: table), TvLevel.desktopOnly)
        XCTAssertEqual(SettingsMenu.level(of: rows["playback"]!, in: table), TvLevel.view)
        XCTAssertEqual(SettingsMenu.level(of: rows["quality"]!, in: table), TvLevel.full)
        XCTAssertEqual(SettingsMenu.level(of: rows["servers"]!, in: table), TvLevel.full)
        XCTAssertEqual(SettingsMenu.summary(of: rows["remote"]!, in: table), "remote")
        XCTAssertEqual(SettingsMenu.level(of: rows["quality"]!, in: nil), TvLevel.desktopOnly, "an older server: every page is the card")
    }

    func testTheCatalogueCarriesIt() throws {
        let json = #"{"cardStyles":[],"routes":[],"commands":[],"settingsMenu":"# + String(decoding: try shared("settingsmenu.json"), as: UTF8.self) + "}"
        let catalog = try JSONDecoder().decode(SDUICatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.settingsMenu?.groups.count, 8)
    }
}
