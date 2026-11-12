// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// The theme on server-driven pages (the server's docs/THEMES.md, SDUI tokens and A profile's own colours).
final class ThemeTokensSDUITests: XCTestCase {
    func testTheResolvedThemeGivesColoursCornersTypeAndTheName() throws {
        let json = ##"""
        {"id":"auto","scheme":"auto","tokens":{"bg":"#0F1115","fg":"#E8EAF0"},
         "shape":{"radius":10,"card":10,"chip":999,"badge":4},
         "type":{"display":["Inter","system-ui"],"body":["Inter"],"mono":["ui-monospace"],"weights":{"body":400,"heading":650}},
         "brand":{"parts":[{"text":"Witty"},{"text":"Media","accent":true},{"text":"Server"}],"token":"brandAccent","color":"#9174FF"},
         "variants":{"dark":{"id":"default","tokens":{"bg":"#0F1115"}},"light":{"id":"light","tokens":{"bg":"#FFFFFF"},"shape":{"card":8}}}}
        """##
        let theme = try JSONDecoder().decode(ResolvedTheme.self, from: Data(json.utf8))
        XCTAssertEqual(theme.colors(dark: false)["bg"], "#FFFFFF")
        XCTAssertEqual(theme.colors(dark: true)["bg"], "#0F1115")
        XCTAssertEqual(theme.shape(dark: false)["card"], 8, "a look's own corners")
        XCTAssertEqual(theme.shape(dark: true)["card"], 10, "else the theme's")
        XCTAssertEqual(theme.typefaces(dark: true)?.families("display"), ["Inter", "system-ui"])
        XCTAssertEqual(theme.typefaces(dark: true)?.weights["heading"], 650)
        XCTAssertEqual(theme.brand?.parts.map(\.text).joined(), "WittyMediaServer")
        XCTAssertEqual(theme.brand?.parts.filter { $0.accent == true }.map(\.text), ["Media"])
    }

    func testTheCatalogueSaysWhichTokensDrawEachComponent() throws {
        let json = #"""
        {"revision":2,"components":[{"type":"Card","tokens":{"shape":{"corner":"card","badge":"badge"},"type":{"title":"title"}}},{"type":"Nothing"}],
         "cardStyles":[{"style":"chip","shape":"chip","tokens":{"shape":{"corner":"chip"}}}],
         "theme":{"typeRoles":{"heading":{"family":"display","weight":"heading"},"title":{"family":"body","weight":"strong"}}}}
        """#
        let catalog = try JSONDecoder().decode(SDUICatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.componentTokens["Card"]?.shape?["corner"], "card")
        XCTAssertNil(catalog.componentTokens["Nothing"])
        XCTAssertEqual(catalog.cardStyle("chip")?.tokens?.shape?["corner"], "chip")
        XCTAssertEqual(catalog.typeRoles["heading"], SDUITypeRole(family: "display", weight: "heading"))
        // Kept on disk and read back the same.
        let again = try JSONDecoder().decode(SDUICatalog.self, from: JSONEncoder().encode(catalog))
        XCTAssertEqual(again.componentTokens, catalog.componentTokens)
        XCTAssertEqual(again.typeRoles, catalog.typeRoles)
    }

    func testARefusalSaysWhichTextWouldBeHardToRead() throws {
        let json = #"{"contrast":[{"scope":"personal","text":"fg2","surface":"bg3","ratio":1.24,"need":4.5,"variant":"light"}],"error":"Those colours…"}"#
        let refusal = try JSONDecoder().decode(ContrastRefusal.self, from: Data(json.utf8))
        XCTAssertEqual(refusal.contrast.count, 1)
        XCTAssertEqual(ContrastRefusal.words(refusal.contrast[0]), "Secondary text on cards and fields: 1.2 to 1, needs 4.5 (light look)")
        XCTAssertEqual(try JSONDecoder().decode(PersonalColours.self, from: Data(##"{"tokens":{"accent":"#FF8800"},"etag":"x"}"##.utf8)).tokens, ["accent": "#FF8800"])
    }
}
