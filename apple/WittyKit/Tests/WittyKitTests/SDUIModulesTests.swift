// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// Layout options and modules' settings, as the server's docs/SDUI.md and docs/SDUI-MODULES.md describe them.
final class SDUIModulesTests: XCTestCase {
    func testTheNavigationCarriesItsFrameAndTheLayoutsOnOffer() throws {
        let json = #"""
        {"version":1,"formFactor":"tablet","items":[],
         "shell":{"experience":"classic","nav":"sidebar","size":220},
         "layouts":{"current":"sidebar","options":[{"value":"sidebar","label":"Sidebar"},{"value":"topTabs","label":"Top tabs"},{"nope":1}],
                    "url":"/api/v1/sdui/layout"}}
        """#
        let navigation = try JSONDecoder().decode(SDUINavigation.self, from: Data(json.utf8))
        XCTAssertEqual(navigation.shell, SDUIShell(experience: "classic", nav: "sidebar", size: 220))
        XCTAssertEqual(navigation.layouts?.options.map(\.value), ["sidebar", "topTabs"], "an option that can't be read is passed over")
        XCTAssertNil(navigation.layouts?.chosen)
        XCTAssertEqual(navigation.layouts?.currentLabel, "Sidebar")
        let tv = try JSONDecoder().decode(SDUIShell.self, from: Data(#"{"experience":"compact","nav":"tvSideMenu","size":120,"open":400}"#.utf8))
        XCTAssertEqual(tv.open, 400)
        XCTAssertTrue(SDUIShell.navs.contains(tv.nav))
    }

    func testTheDeviceNamesItselfWithAStableNameOfItsOwn() {
        let made = SDUIDevice.newAppId(platform: "phone")
        XCTAssertTrue(SDUIDevice.isAppId(made))
        XCTAssertTrue(made.hasPrefix("apple-phone-"))
        XCTAssertNotEqual(made, SDUIDevice.newAppId(platform: "phone"))
        XCTAssertFalse(SDUIDevice.isAppId("has space"))
        XCTAssertFalse(SDUIDevice.isAppId(""))
        XCTAssertFalse(SDUIDevice.isAppId("é"))
        var device = SDUIDevice.touch(pad: false, width: 402, height: 874, reducedMotion: false, views: [])
        XCTAssertFalse(device.query.contains { $0.0 == "device" })
        device.appId = "apple-phone-abc123"
        XCTAssertEqual(device.query.last?.0, "device")
        XCTAssertEqual(device.query.last?.1, "apple-phone-abc123")
        device.appId = "bad name"
        XCTAssertFalse(device.query.contains { $0.0 == "device" }, "a name the server would refuse isn't sent")
    }

    private let settingsJSON = #"""
    { "module": "wittyboardgames", "label": "Board games",
      "pages": [ { "id": "wittyboardgames", "title": "Board games", "icon": "game", "groups": [
        { "title": "Game night", "footer": "Used for Tonight's row.", "rows": [
          { "key": "household", "kind": "int", "label": "Players at home", "min": 1, "max": 12, "default": 4 },
          { "key": "ages", "kind": "enum", "label": "Ages", "options": [{"value":"all","label":"Everyone"},{"value":"kids","label":"Kids"}] },
          { "key": "sound", "kind": "bool", "label": "Sound", "scope": "profile" },
          { "key": "apiKey", "kind": "secret", "label": "API key" },
          { "key": "listUrl", "kind": "string", "label": "List address", "maxLength": 20 },
          { "kind": "info", "label": "Made by the board games module." },
          { "key": "future", "kind": "colour", "label": "Something newer" } ] } ] } ],
      "values": { "household": 4, "ages": "kids", "sound": true, "listUrl": "" },
      "secretsSet": [ "apiKey" ],
      "editable": false }
    """#

    func testAModulesSettingsAreReadAndWordedAsTheAppShowsThem() throws {
        let settings = try JSONDecoder().decode(ModuleSettings.self, from: Data(settingsJSON.utf8))
        let rows = try XCTUnwrap(settings.pages.first?.groups.first?.rows)
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(settings.shown(rows[0]), "4")
        XCTAssertEqual(settings.shown(rows[1]), "Kids")
        XCTAssertEqual(settings.shown(rows[2]), "On")
        XCTAssertEqual(settings.shown(rows[3]), "Set", "a secret is never sent, only whether it's set")
        // Not an administrator: only the profile's own row can be changed.
        XCTAssertFalse(settings.canChange(rows[0]))
        XCTAssertTrue(settings.canChange(rows[2]))
        XCTAssertFalse(settings.canChange(rows[5]), "an info row has no value")
        XCTAssertFalse(settings.canChange(rows[6]), "a kind this app doesn't draw is read only")
        var admin = settings
        admin.editable = true
        XCTAssertTrue(admin.canChange(rows[0]))
        XCTAssertFalse(admin.canChange(rows[6]))
    }

    func testAValueIsCheckedAsTheServerChecksIt() throws {
        let settings = try JSONDecoder().decode(ModuleSettings.self, from: Data(settingsJSON.utf8))
        let rows = try XCTUnwrap(settings.pages.first?.groups.first?.rows)
        XCTAssertNil(ModuleSettings.problem(.number(12), for: rows[0]))
        XCTAssertEqual(ModuleSettings.problem(.number(13), for: rows[0]), "Players at home is at most 12")
        XCTAssertEqual(ModuleSettings.problem(.number(0), for: rows[0]), "Players at home is at least 1")
        XCTAssertEqual(ModuleSettings.problem(.number(2.5), for: rows[0]), "Players at home is a whole number")
        XCTAssertNil(ModuleSettings.problem(.string("all"), for: rows[1]))
        XCTAssertEqual(ModuleSettings.problem(.string("teens"), for: rows[1]), "Ages is one of Everyone, Kids")
        XCTAssertNil(ModuleSettings.problem(.bool(false), for: rows[2]))
        XCTAssertEqual(ModuleSettings.problem(.string("a\nb"), for: rows[4]), "List address is one line of plain text")
        XCTAssertEqual(ModuleSettings.problem(.string(String(repeating: "x", count: 21)), for: rows[4]), "List address is at most 20 characters")
    }

    func testOnlyAModulesOwnNameGoesIntoAPath() throws {
        XCTAssertTrue(SDUIRouter.isModuleName("wittyboardgames"))
        XCTAssertFalse(SDUIRouter.isModuleName("../etc"))
        XCTAssertFalse(SDUIRouter.isModuleName("Witty"))
        XCTAssertFalse(SDUIRouter.isModuleName("1witty"))
        XCTAssertFalse(SDUIRouter.isModuleName("w"))
        let list = try JSONDecoder().decode(ModuleSettingsList.self, from: Data(#"{"modules":[{"module":"wittyplay","label":"WittyPlay"},{"module":"../x","label":"x"},{"label":"no id"}]}"#.utf8))
        XCTAssertEqual(list.modules.map(\.module), ["wittyplay"])
    }

    func testTheThemeCarriesEachModulesPalette() throws {
        let json = ##"{"id":"witty","modules":{"wittyplay":{"tokens":{"accent":"#ff8800"},"overrides":{}},"wittytv":{"tokens":{}}}}"##
        let modules = try JSONDecoder().decode(ThemeModules.self, from: Data(json.utf8))
        XCTAssertEqual(modules.tokens, ["wittyplay": ["accent": "#ff8800"]])
        XCTAssertEqual(try JSONDecoder().decode(ThemeModules.self, from: Data(#"{"id":"witty"}"#.utf8)).tokens, [:])
    }
}
