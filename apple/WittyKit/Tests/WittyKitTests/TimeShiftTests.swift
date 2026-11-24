// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// Start over, rewinding past the buffer and skipping breaks, as server #648 and the web player have them.
final class TimeShiftTests: XCTestCase {
    private let breaks = [Span(start: 600, end: 660), Span(start: 1200, end: 1290)]

    func testTheBreakThePictureIsIn() {
        XCTAssertEqual(TimeShiftRules.breakAt(breaks, 600), breaks[0])
        XCTAssertEqual(TimeShiftRules.breakAt(breaks, 1289.9), breaks[1])
        XCTAssertNil(TimeShiftRules.breakAt(breaks, 660))
        XCTAssertNil(TimeShiftRules.breakAt(breaks, nil))
    }

    func testSeeks() {
        XCTAssertEqual(TimeShiftRules.plan(970, sched: 1000, cur: 100, low: 40, high: 130, live: 5000), .within(70))
        XCTAssertEqual(TimeShiftRules.plan(500.7, sched: 1000, cur: 100, low: 40, high: 130, live: 5000), .restart(500))
        XCTAssertEqual(TimeShiftRules.plan(100, sched: 1000, cur: 100, low: 40, high: 130, live: 5000, earliest: 300), .restart(300))
        // Skipping a break that ends past what's loaded.
        XCTAssertEqual(TimeShiftRules.plan(660.5, sched: 610, cur: 100, low: 40, high: 110, live: 5000), .restart(660))
        XCTAssertEqual(TimeShiftRules.plan(4980, sched: 1000, cur: 100, low: 40, high: 130, live: 5000), .live)
    }

    func testALongPauseStartsAgainWhereItPaused() {
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(TimeShiftRules.restartAfterPause(pausedAt: t0, now: t0.addingTimeInterval(60), bufferSec: 300))
        XCTAssertTrue(TimeShiftRules.restartAfterPause(pausedAt: t0, now: t0.addingTimeInterval(280), bufferSec: 300))
        XCTAssertFalse(TimeShiftRules.restartAfterPause(pausedAt: t0, now: t0.addingTimeInterval(25), bufferSec: 10))
    }

    func testTheServersAnswerAndStartOver() throws {
        let json = #"""
        {"url":"/api/tv/lib-4/shift/v1/playlist.m3u8","startOver":true,"serverTime":5000,"bufferSec":300,
         "now":{"start":1000,"end":2800,"kind":"show","title":"Film"},
         "timeline":{"programme":{"start":1000,"end":2800,"kind":"show","title":"Film"},"breaks":[{"start":1600,"end":1660}],"from":1000,"live":5000,"earliest":0}}
        """#
        let t = try JSONDecoder().decode(Tuned.self, from: Data(json.utf8))
        XCTAssertEqual(t.timeline?.breaks, [Span(start: 1600, end: 1660)])
        XCTAssertEqual(t.timeline?.from, 1000)
        XCTAssertEqual(t.bufferSec, 300)
        XCTAssertTrue(TimeShiftRules.canStartOver(t, now: 1100))
        XCTAssertFalse(TimeShiftRules.canStartOver(t, now: 1010))
    }

    func testAddresses() {
        XCTAssertEqual(TimeShiftRules.query(key: "lib-4", from: 1000, viewer: "v1"), "/tv/lib-4/startover?viewer=v1&streamToken=1&from=1000")
        XCTAssertEqual(TimeShiftRules.query(key: "lib-4", from: nil, viewer: "v1"), "/tv/lib-4/startover?viewer=v1&streamToken=1")
        XCTAssertEqual(TimeShiftRules.leaveQuery(key: "lib-4", viewer: "v1", shift: true), "/tv/lib-4/leave?viewer=v1&shift=1")
        XCTAssertTrue(TimeShiftRules.isLibrary("lib-4"))
        XCTAssertFalse(TimeShiftRules.isLibrary("tun-4"))
    }
}
