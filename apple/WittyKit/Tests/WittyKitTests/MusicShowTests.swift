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
        XCTAssertEqual(VisualizerEffects.colours.count, 9)
        XCTAssertEqual(VisualizerEffects.changes.map(\.id), ["fade", "dissolve", "iris", "sweep"])
    }

    func testPrefsKeepOldSavedChoicesAndClamp() throws {
        let old = try JSONDecoder().decode(VisualizerPrefs.self, from: Data(#"{"viz":true,"style":"waves"}"#.utf8))
        XCTAssertEqual(old.colour, "theme")
        XCTAssertEqual(old.change, "fade")
        let odd = try JSONDecoder().decode(VisualizerPrefs.self, from: Data(#"{"colour":"x","change":"y","intensity":9,"speed":-1,"calm":true}"#.utf8))
        XCTAssertEqual(odd.colour, "theme")
        XCTAssertEqual(odd.intensity, 1)
        XCTAssertEqual(odd.speed, 0)
        XCTAssertTrue(odd.calm)
        XCTAssertEqual(VisualizerPrefs().effect.id, "bars")
    }
}
