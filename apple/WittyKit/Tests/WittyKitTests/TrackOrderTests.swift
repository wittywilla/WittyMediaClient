// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class TrackOrderTests: XCTestCase {
    private struct T { let id: Int; let title: String; let lang: String }

    func testCodesOfOneLanguageAreOne() {
        XCTAssertEqual(TrackOrder.base("eng"), "en")
        XCTAssertEqual(TrackOrder.base("ger"), "de")
        XCTAssertEqual(TrackOrder.base("en-GB"), "en")
        XCTAssertEqual(TrackOrder.base("pt_BR"), "pt")
        XCTAssertEqual(TrackOrder.base("und"), "")
        XCTAssertEqual(TrackOrder.base(nil), "")
    }

    func testDeviceThenRecentThenTheRestByName() {
        let tracks = [T(id: 1, title: "Spanish", lang: "spa"), T(id: 2, title: "Greek", lang: "gre"), T(id: 3, title: "English", lang: "eng"),
                      T(id: 4, title: "English SDH", lang: "eng"), T(id: 5, title: "Danish", lang: "dan"), T(id: 6, title: "Arabic", lang: "ara")]
        let got = TrackOrder.order(tracks, language: { $0.lang }, title: { $0.title }, device: ["en-GB", "en"], recent: ["es"])
        XCTAssertEqual(got.map(\.id), [3, 4, 1, 6, 5, 2])
    }

    func testPicksAreRememberedNewestFirstFiveAtMost() {
        var saved: [String] = []
        for c in ["eng", "spa", "fra", "deu", "ita", "jpn", "spa"] { saved = TrackOrder.remember(saved, c) }
        XCTAssertEqual(saved, ["es", "ja", "it", "de", "fr"])
        XCTAssertEqual(TrackOrder.remember(saved, "und"), saved)
    }
}
