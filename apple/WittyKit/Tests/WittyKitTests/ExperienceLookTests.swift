// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class ExperienceLookTests: XCTestCase {
    private let aero = """
    {"id":"aeroday","tokens":{"bg":"#cfeeff"},"look":{"experience":"aero","theme":"aeroday",
     "effects":{"glass":"full","gloss":"full","glow":"subtle","texture":"none","bevel":"full"},
     "shape":{"radiusMultiple":2,"cardSet":"poster"},"type":"rounded","density":"comfortable","motion":{"focus":"glow","screen":"fade","overshoot":true},
     "finish":{"glass":{"hi":"rgba(255,255,255,.9)","lo":"rgba(255,255,255,.5)","edge":"#ffffff","shadow":"rgba(20,120,200,.25)"},"gloss":["#7fd8ff","#1e9be0","#0c7fc4","#39b5f0","#0a6aa8"]},
     "scene":{"layers":[{"type":"gradient","angle":180,"stops":[{"at":0,"color":"#6fcfff"},{"at":100,"color":"#e1f8d6"}]},{"type":"shape","kind":"circle","x":12,"y":22,"size":9,"color":"rgba(255,255,255,0.3)"},{"type":"shape","kind":"hill","x":50,"y":100,"size":70,"stops":[{"at":0,"color":"#8fdc7a"},{"at":100,"color":"#3aa84a"}]}]}}}
    """

    func testTheLookIsReadFromTheTheme() throws {
        let look = try XCTUnwrap(JSONDecoder().decode(ResolvedTheme.self, from: Data(aero.utf8)).experienceLook)
        XCTAssertEqual(look.experience, "aero")
        XCTAssertEqual(look.effects.gloss, .full)
        XCTAssertEqual(look.effects.glow, .subtle)
        XCTAssertEqual(look.effects.texture, .none)
        XCTAssertEqual(look.radiusMultiple, 2)
        XCTAssertEqual(look.type, .rounded)
        XCTAssertTrue(look.overshoot)
        XCTAssertEqual(look.finish.gloss.count, 5)
        XCTAssertEqual(look.finish.glass?.edge, "#ffffff")
        XCTAssertEqual(look.scene.map(\.type), ["gradient", "shape", "shape"])
        XCTAssertEqual(look.scene[2].kind, "hill")
        XCTAssertEqual(look.scene[2].stops.count, 2)
    }

    func testAModestDeviceDropsEveryEffectAStepAndKeepsOneSceneLayer() throws {
        let look = try XCTUnwrap(JSONDecoder().decode(ResolvedTheme.self, from: Data(aero.utf8)).experienceLook)
        let modest = look.adjusted(modest: true)
        XCTAssertEqual(modest.effects.gloss, .subtle)
        XCTAssertEqual(modest.effects.glow, .none)
        XCTAssertEqual(modest.scene.count, 1)
        XCTAssertFalse(modest.overshoot)
        XCTAssertEqual(look.adjusted(modest: false), look)
    }

    func testAMissingOrOddLookIsPlain() throws {
        let theme = try JSONDecoder().decode(ResolvedTheme.self, from: Data(#"{"id":"x","tokens":{},"look":{"effects":{"glass":"loud"},"type":"comic"}}"#.utf8))
        let look = try XCTUnwrap(theme.experienceLook)
        XCTAssertEqual(look.effects, LookEffects())
        XCTAssertEqual(look.type, .system)
        XCTAssertNil(try JSONDecoder().decode(ResolvedTheme.self, from: Data(#"{"id":"x","tokens":{}}"#.utf8)).experienceLook)
    }

    func testCSSColours() {
        XCTAssertEqual(ThemeColour(css: "rgba(255,255,255,.9)")?.alpha ?? 0, 0.9, accuracy: 0.001)
        XCTAssertEqual(ThemeColour(css: "rgb(10, 20, 30)")?.hex, "#0a141e")
        XCTAssertEqual(ThemeColour(css: "#fff")?.hex, "#ffffff")
        XCTAssertNil(ThemeColour(css: "url(evil)"))
    }
}

extension ExperienceLookTests {
    func testTheGlossBodiesStayReadableUnderTheWords() throws {
        let look = try XCTUnwrap(JSONDecoder().decode(ResolvedTheme.self, from: Data(aero.utf8)).experienceLook)
        let accent = ThemeColour(hex: "#166fa1")!
        let stops = look.finish.glossStops(accent: accent, ink: .white)
        XCTAssertEqual(stops.count, 5)
        XCTAssertGreaterThanOrEqual(stops[1].contrast(with: .white), 4.5)
        XCTAssertGreaterThanOrEqual(stops[2].contrast(with: .white), 4.5)
        // A theme with no recipe still gets five stops from its accent.
        XCTAssertEqual(LookFinish().glossStops(accent: accent, ink: .white).count, 5)
    }

    func testGlassFallsBackToALightOrDarkPane() {
        XCTAssertGreaterThan(LookFinish().glassColours(light: true).hi.alpha, LookFinish().glassColours(light: false).hi.alpha)
    }
}
