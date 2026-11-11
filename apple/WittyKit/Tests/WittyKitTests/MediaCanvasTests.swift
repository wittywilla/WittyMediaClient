// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class MediaCanvasTests: XCTestCase {
    private let canvas = CanvasInfo(available: true, url: "/api/media/9/canvas/file?v=xabc", mime: "video/mp4", width: 540, height: 960)

    func testTheServersAnswerIsRead() throws {
        let read = try JSONDecoder().decode(CanvasInfo.self, from: Data(#"""
        {"available":true,"url":"/api/media/2/canvas/file?v=x1","mime":"video/mp4","width":1280,"height":720,"durationMs":8000,
         "loop":true,"source":"generated","canGenerate":true}
        """#.utf8))
        XCTAssertEqual(read.url, "/api/media/2/canvas/file?v=x1")
        XCTAssertEqual(read.durationMs, 8000)
        XCTAssertTrue(read.removable)
        XCTAssertEqual(read.sourceWords, "Cut from the video by the server")
        let none = try JSONDecoder().decode(CanvasInfo.self, from: Data(#"{"available":false,"loop":true,"canGenerate":false,"reason":"too-long"}"#.utf8))
        XCTAssertFalse(none.removable)
        XCTAssertTrue(none.refusalWords.contains("longer than a minute"))
        XCTAssertFalse(CanvasInfo(available: true, source: "sidecar").removable, "one beside the media is the folder's own")
    }

    func testItPlaysWhenNothingStandsInItsWay() {
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions()), .play(path: "/api/media/9/canvas/file?v=xabc"))
    }

    func testAnythingThatCostsThePersonKeepsItStill() {
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(wanted: false)), .still(why: .switchedOff))
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(reduceMotion: true)), .still(why: .reduceMotion))
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(lowPower: true)), .still(why: .lowPower))
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(constrainedNetwork: true)), .still(why: .lowData))
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(expensiveNetwork: true)), .still(why: .mobileData))
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(awayFromHome: true)), .still(why: .away))
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(wanted: false, lowPower: true, reduceMotion: true)), .still(why: .switchedOff),
                       "the person's own switch is said first")
    }

    func testNoCanvasOrOneThisDeviceCantShowIsTheStillPicture() {
        XCTAssertEqual(CanvasRules.decide(nil, CanvasConditions()), .still(why: .none))
        XCTAssertEqual(CanvasRules.decide(CanvasInfo(available: false), CanvasConditions()), .still(why: .none))
        XCTAssertEqual(CanvasRules.decide(CanvasInfo(available: true, url: "", mime: "video/mp4"), CanvasConditions()), .still(why: .none))
        XCTAssertEqual(CanvasRules.decide(CanvasInfo(available: true, url: "/c", mime: "video/webm"), CanvasConditions()), .still(why: .cannotPlay))
        XCTAssertTrue(CanvasRules.playable(mime: "video/mp4; codecs=avc1"))
        XCTAssertFalse(CanvasRules.playable(mime: nil))
    }

    func testASmallAppleTVPlaysOnlySmallOnes() {
        let big = CanvasInfo(available: true, url: "/c", mime: "video/mp4", width: 1920, height: 1080)
        XCTAssertEqual(CanvasRules.decide(big, CanvasConditions()), .play(path: "/c"))
        XCTAssertEqual(CanvasRules.decide(big, CanvasConditions(smallDevice: true)), .still(why: .tooLarge))
        XCTAssertEqual(CanvasRules.decide(canvas, CanvasConditions(smallDevice: true)), .play(path: "/api/media/9/canvas/file?v=xabc"))
        XCTAssertEqual(CanvasRules.decide(CanvasInfo(available: true, url: "/c", mime: "video/mp4", width: 3840, height: 2160), CanvasConditions()),
                       .still(why: .tooLarge), "nothing over 1080p is decoded for decoration")
        XCTAssertEqual(CanvasRules.decide(CanvasInfo(available: true, url: "/c", mime: "video/mp4"), CanvasConditions(smallDevice: true)), .play(path: "/c"),
                       "a server without FFprobe doesn't say the size: the upload limit keeps it small")
        XCTAssertTrue(CanvasRules.isSmallTV(model: "AppleTV5,3"))
        XCTAssertFalse(CanvasRules.isSmallTV(model: "AppleTV14,1"))
    }

    func testTheSettingsScreenSaysWhatKeepsThemStill() {
        XCTAssertEqual(CanvasRules.standing(CanvasConditions()), .none)
        XCTAssertEqual(CanvasRules.standing(CanvasConditions(lowPower: true)), .lowPower)
        XCTAssertEqual(CanvasRules.words(.lowPower), "Low Power Mode is on, so pictures stay still.")
        XCTAssertEqual(CanvasRules.words(.switchedOff), "", "the switch speaks for itself")
    }

    func testTheStreamTokenGoesOnTheAddress() {
        XCTAssertEqual(CanvasRules.address(path: "/api/media/9/canvas/file?v=x1", token: "st_ab12"), "/api/media/9/canvas/file?v=x1&st=st_ab12")
        XCTAssertEqual(CanvasRules.address(path: "/api/media/9/stems/vocals", token: "st_ab12"), "/api/media/9/stems/vocals?st=st_ab12")
        XCTAssertEqual(CanvasRules.address(path: "/a", token: "a b&c"), "/a?st=a%20b%26c")
        XCTAssertEqual(CanvasRules.address(path: "/a", token: ""), "/a")
    }
}
