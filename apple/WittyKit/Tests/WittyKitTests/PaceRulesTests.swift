// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// The same sizes and words as the website (web/src/player/pace.ts) and the Android app (PlaybackRules.kt).
final class PaceRulesTests: XCTestCase {
    func testNextSizeDown() {
        XCTAssertEqual(PaceRules.lowerHeight(2160), 1440)
        XCTAssertEqual(PaceRules.lowerHeight(1080), 720)
        XCTAssertEqual(PaceRules.lowerHeight(800), 720)
        XCTAssertEqual(PaceRules.lowerHeight(720), 480)
        XCTAssertEqual(PaceRules.lowerHeight(360), 0)
        XCTAssertEqual(PaceRules.lowerHeight(0), 0)
    }

    func testRealignAfterARealChangeOfSpeed() {
        XCTAssertTrue(PaceRules.realignNeeded(from: 4, to: 1))
        XCTAssertTrue(PaceRules.realignNeeded(from: 1, to: 2))
        XCTAssertFalse(PaceRules.realignNeeded(from: 1, to: 1.25))
        XCTAssertFalse(PaceRules.realignNeeded(from: 0, to: 1))
    }

    func testWords() {
        XCTAssertTrue(PaceRules.steppedDown(speed: 0.7, rate: 2, height: 720).hasSuffix("so it goes on at 720p."))
        XCTAssertTrue(PaceRules.tooSlow(speed: 0.666, rate: 2).contains("0.67×"))
    }

    func testLowerOnceThenSlower() {
        XCTAssertEqual(PaceRules.step(speed: 1.4, rate: 4, height: 1080, viewerChose: false), .lower)
        XCTAssertEqual(PaceRules.step(speed: 1.4, rate: 4, height: 720, viewerChose: false), .slower)
        XCTAssertEqual(PaceRules.step(speed: 1.4, rate: 4, height: 1080, viewerChose: true), .slower)
        XCTAssertEqual(PaceRules.step(speed: 0.8, rate: 1, height: 720, viewerChose: false), .lower)
        XCTAssertEqual(PaceRules.step(speed: 1.05, rate: 1.25, height: 720, viewerChose: false), .tell)
        XCTAssertEqual(PaceRules.sustainableRate(speed: 1.4, rate: 4), 1.25)
        XCTAssertEqual(PaceRules.sustainableRate(speed: 2.3, rate: 4), 2)
        XCTAssertEqual(PaceRules.slower(rate: 4, to: 1.25), "This server can’t keep up at 4× for this video, so it plays at 1.25×.")
    }

    func testPaceDecodes() throws {
        let json = #"{"encoder":"libx264","pace":{"speed":0.8,"rate":2,"leadSec":4,"keepingUp":false,"fastest":true}}"#
        struct Work: Decodable { var pace: StreamPace? }
        let w = try JSONDecoder().decode(Work.self, from: Data(json.utf8))
        XCTAssertEqual(w.pace, StreamPace(speed: 0.8, rate: 2, keepingUp: false, fastest: true))
    }
}
