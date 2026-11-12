// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class SDUIPresenceTests: XCTestCase {
    func testTheDotFollowsTheBadgeByTheStylesTones() {
        XCTAssertEqual(SDUIPresence.tone(badges: ["Playing"]), .ok)
        XCTAssertEqual(SDUIPresence.tone(badges: ["Online"]), .ok)
        XCTAssertEqual(SDUIPresence.tone(badges: ["Away"]), .warn)
        XCTAssertEqual(SDUIPresence.tone(badges: ["Offline"]), .muted)
        XCTAssertNil(SDUIPresence.tone(badges: ["P1"]), "a badge that isn't a presence has no dot")
        XCTAssertNil(SDUIPresence.tone(badges: []))
        XCTAssertEqual(SDUIPresence.tone(badges: ["Busy"], tones: ["busy": "warn"]), .warn)
        XCTAssertEqual(SDUIPresence.tone(badges: ["Online"], tones: ["Online": "muted"]), .muted, "the catalogue's word wins")
    }
}
