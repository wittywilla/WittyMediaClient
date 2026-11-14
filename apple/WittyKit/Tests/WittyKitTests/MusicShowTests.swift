// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class MusicShowTests: XCTestCase {
    func testShowIsRememberedPerDevice() {
        let d = UserDefaults(suiteName: "musicshow-\(UUID())")!
        XCTAssertEqual(MusicShow.load(d), .art)
        MusicShow.canvas.save(d)
        XCTAssertEqual(MusicShow.load(d), .canvas)
        d.set("nonsense", forKey: MusicShow.key)
        XCTAssertEqual(MusicShow.load(d), .art)
    }

    func testCanvasFallsBackToArtButIsNeverHidden() {
        XCTAssertEqual(MusicShow.canvas.shown(canvasPlays: false, visualizerAllowed: true), .art)
        XCTAssertEqual(MusicShow.canvas.shown(canvasPlays: true, visualizerAllowed: true), .canvas)
        XCTAssertEqual(MusicShow.viz.shown(canvasPlays: true, visualizerAllowed: false), .art)
        XCTAssertNotNil(MusicShow.canvasNote(info: nil, conditions: CanvasConditions()))
        let info = try! JSONDecoder().decode(CanvasInfo.self, from: Data(#"{"available":true,"url":"/c","mime":"video/mp4","width":640,"height":360}"#.utf8))
        XCTAssertNil(MusicShow.canvasNote(info: info, conditions: CanvasConditions()))
        XCTAssertTrue(MusicShow.canvasNote(info: info, conditions: CanvasConditions(lowPower: true))!.contains("Low Power"))
        XCTAssertTrue(MusicShow.canvasNote(info: info, conditions: CanvasConditions(reduceMotion: true))!.contains("Reduce Motion"))
        XCTAssertTrue(MusicShow.canvasNote(info: info, conditions: CanvasConditions(constrainedNetwork: true))!.contains("Low Data"))
        XCTAssertTrue(MusicShow.canvasNote(info: info, conditions: CanvasConditions(expensiveNetwork: true))!.contains("mobile data"))
    }

    func testFollowAlongNeedsTimes() {
        XCTAssertNotNil(LyricsMode.followNote(timed: false))
        XCTAssertNil(LyricsMode.followNote(timed: true))
        XCTAssertEqual(LyricsMode.follow.effective(timed: false), .read)
        XCTAssertEqual(LyricsMode.follow.effective(timed: true), .follow)
        XCTAssertEqual(LyricsMode.read.effective(timed: true), .read)
    }

    func testEighteenEffectsAndTheAppsOwnThree() {
        XCTAssertEqual(VisualizerEffects.picker.count, 18)
        XCTAssertNotNil(VisualizerEffects.named("auroraRings"))
        XCTAssertEqual(Set(VisualizerEffects.all.map(\.id)).count, VisualizerEffects.all.count)
        XCTAssertEqual(VisualizerChoices.fallback.effects.count, 18)
    }

    func testPrefsReadAndWriteWittyVisualizersValues() {
        let none = VisualizerPrefs(values: [:], shown: true)
        XCTAssertEqual(none, VisualizerPrefs())
        XCTAssertEqual(none.effect.id, "skyline")
        let saved = VisualizerPrefs(values: ["effect": .string("molten"), "cycleSec": .string("30"), "calm": .string("on"),
                                             "intensityPct": .number(150), "speedPct": .number(50), "colour": .string("theme")], shown: false)
        XCTAssertFalse(saved.viz)
        XCTAssertEqual(saved.style, "molten")
        XCTAssertEqual(saved.shuffleEvery, 30)
        XCTAssertEqual(saved.intensity, 1.5)
        XCTAssertEqual(saved.speed, 0.5)
        XCTAssertEqual(saved.colour, "theme")
        XCTAssertTrue(saved.calmNow(reduceMotion: false))
        // The values go back as the module keeps them.
        XCTAssertEqual(saved.values["cycleSec"], .string("30"))
        XCTAssertEqual(saved.values["intensityPct"], .number(150))
        XCTAssertEqual(VisualizerPrefs(values: saved.values, shown: false), saved)
        // Odd values fall back to the defaults.
        let odd = VisualizerPrefs(values: ["calm": .string("loud"), "colour": .string("x")], shown: true)
        XCTAssertEqual(odd.calm, "system")
        XCTAssertEqual(odd.colour, "effect")
        XCTAssertTrue(odd.calmNow(reduceMotion: true))
        XCTAssertFalse(odd.calmNow(reduceMotion: false))
    }

    func testChoicesComeFromTheModulesRows() throws {
        let json = #"{"module":"wittyvisualizer","pages":[{"id":"p","title":"Visualizer","groups":[{"rows":[{"key":"effect","kind":"enum","label":"Effect","options":[{"value":"skyline","label":"Skyline"},{"value":"newone","label":"New One"}]},{"key":"cycleSec","kind":"enum","label":"Change","options":[{"value":"0","label":"Off"},{"value":"10","label":"Every 10 s"}]},{"key":"intensityPct","kind":"int","label":"Intensity","min":30,"max":150}]}]}],"values":{}}"#
        let choices = VisualizerChoices(try JSONDecoder().decode(ModuleSettings.self, from: Data(json.utf8)))
        XCTAssertEqual(choices.effects.map(\.id), ["skyline", "newone"])
        XCTAssertFalse(choices.effects[0].about.isEmpty)
        XCTAssertEqual(choices.every, [0, 10])
        XCTAssertEqual(choices.intensity, 0.3...1.5)
        XCTAssertEqual(choices.speed, VisualizerChoices.fallback.speed)
        XCTAssertEqual(choices.colours.map(\.id), ["effect", "theme"])
    }
}
