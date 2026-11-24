// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class BidiTests: XCTestCase {
    func testRightToLeftPartsAreIsolated() {
        XCTAssertEqual(Bidi.isolate("שיר 2"), "\u{2068}שיר 2\u{2069}")
        XCTAssertEqual(["עפרה", "2019"].factsLine(), "\u{2068}עפרה\u{2069} · " + Bidi.isolate("2019"))
        XCTAssertEqual(Bidi.isolate(Bidi.isolate("شمس")), Bidi.isolate("شمس"), "isolated once")
        XCTAssertEqual(Bidi.isolate(""), "")
    }

    func testLeftToRightPartsOnALeftToRightDeviceStayAsTheyAre() throws {
        try XCTSkipIf(Bidi.rightToLeftDevice, "this Mac is set to a right-to-left language")
        XCTAssertEqual(["2018", "2 hr 10 min"].factsLine(), "2018 · 2 hr 10 min")
        XCTAssertEqual(Bidi.isolate("00-aurora-2019"), "00-aurora-2019")
    }
}
