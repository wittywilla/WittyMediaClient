// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class DesignPageSpecTests: XCTestCase {
    /// The canvas's `gp.mismatch`, copied across with the builders.
    private let mismatch = DesignPageSpec.mk(
        "Careful", "This isn’t the server you used before",
        "The address is the same, but the server’s identity changed.",
        [.secR("Identity", [.R("Saved", "a4f2 · 91c0", false), .R("Now", "77be · 02d4", true)]),
         .secN("", "Only continue if you reinstalled or restored this server yourself.", true)],
        [.A2("Go back"), .A1("Trust this server")], "")

    func testBuildersReadAsTheCanvas() {
        XCTAssertEqual(mismatch.eyebrow, "Careful")
        XCTAssertEqual(mismatch.sections[0].kind, .rows)
        XCTAssertEqual(mismatch.sections[0].rows[1].value, "77be · 02d4")
        XCTAssertTrue(mismatch.sections[0].rows[1].on)
        XCTAssertEqual(mismatch.sections[1].kind, .note)
        XCTAssertTrue(mismatch.sections[1].tone)
        XCTAssertEqual(mismatch.actions.map(\.primary), [false, true])
        XCTAssertEqual(mismatch.actions.map(\.id), ["go-back", "trust-this-server"])
    }

    func testFocusRunsTopToBottomAndSkipsWhatOnlySays() {
        var spec = mismatch
        spec.sections[0].rows[0].pressable = false
        XCTAssertEqual(spec.focusOrder, ["now", "go-back", "trust-this-server"])
        XCTAssertEqual(spec.startFocus, "now")
        spec.start = "trust-this-server"
        XCTAssertEqual(spec.startFocus, "trust-this-server")
        spec.start = "gone"
        XCTAssertEqual(spec.startFocus, "now")
    }

    func testBackFollowsTheLadder() {
        var spec = mismatch
        XCTAssertEqual(spec.back, .focusBar)
        spec.layer = true
        XCTAssertEqual(spec.back, .closeLayer)
    }

    func testCardsAreNeverMoreThanTwoAcrossOnAPhone() {
        let five = DesignPageSpec.Section.secC("Looks", [], 5)
        XCTAssertEqual(DesignPageSpec.columns(five, phone: true, tablet: false), 2)
        XCTAssertEqual(DesignPageSpec.columns(five, phone: false, tablet: false), 5)
        let own = DesignPageSpec.Section.secC("Looks", [])
        XCTAssertEqual(DesignPageSpec.columns(own, phone: false, tablet: true), 3)
        XCTAssertEqual(DesignPageSpec.columns(own, phone: false, tablet: false), 4)
    }

    func testIdsComeFromTitles() {
        XCTAssertEqual(DesignPageSpec.slug("Show saved servers first"), "show-saved-servers-first")
        XCTAssertEqual(DesignPageSpec.slug("Import a theme…"), "import-a-theme")
        XCTAssertEqual(DesignPageSpec.slug("…"), "item")
    }

    func testJSONReadsWithEverythingOptionalButTitlesAndKinds() throws {
        let json = #"""
        {"eyebrow":"Pip","title":"That’s all for today","layer":true,
         "sections":[{"kind":"chips","chips":[{"title":"Ask a parent","on":true},{"title":"Switch profile"}]},
                     {"kind":"cards","columns":5,"cards":[{"title":"Lumen","subtitle":"Quiet cinema","swatches":["#101014","#1d1d24","#7c5cff"]}]}],
         "actions":[{"title":"OK","primary":true}]}
        """#
        let spec = try JSONDecoder().decode(DesignPageSpec.self, from: Data(json.utf8))
        XCTAssertEqual(spec.sections[0].chips.map(\.id), ["ask-a-parent", "switch-profile"])
        XCTAssertEqual(spec.sections[1].cards[0].swatches.count, 3)
        XCTAssertEqual(spec.sections[1].columns, 5)
        XCTAssertEqual(spec.back, .closeLayer)
        XCTAssertEqual(spec.startFocus, "ask-a-parent")
        // And back out and in again, unchanged.
        let again = try JSONDecoder().decode(DesignPageSpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(again, spec)
    }
}

final class DesignPageSpecControlTests: XCTestCase {
    private let json = #"""
    {"title":"Privacy","form":{"submitLabel":"Save","cancelLabel":"Cancel"},
     "sections":[{"kind":"rows","rows":[
       {"title":"Show what I play","control":{"type":"switch","name":"showPlaying","value":true}},
       {"title":"Who can see me","control":{"type":"select","name":"who","value":"friends",
          "options":[{"value":"everyone","label":"Everyone"},{"value":"friends","label":"Friends"},{"value":"nobody","label":"Nobody"}]}},
       {"title":"Status","control":{"type":"field","name":"status","value":"Hi","maxLength":5,"placeholder":"Say something"}},
       {"title":"Volume","control":{"type":"slider","name":"volume","value":40,"min":0,"max":50,"step":10}},
       {"title":"Read only","pressable":false}]}]}
    """#

    func testControlsReadAsTheServerSendsThem() throws {
        let spec = try JSONDecoder().decode(DesignPageSpec.self, from: Data(json.utf8))
        let rows = spec.sections[0].rows
        XCTAssertEqual(rows[0].control?.kind, .switch)
        XCTAssertEqual(rows[0].control?.shown, "On")
        XCTAssertEqual(rows[0].control?.flipped, "false")
        XCTAssertEqual(rows[1].control?.shown, "Friends")
        XCTAssertEqual(rows[1].control?.option(after: 1), "nobody")
        XCTAssertEqual(rows[1].control?.option(after: 2), "everyone", "round again at the end")
        XCTAssertEqual(rows[1].control?.option(after: -1), "everyone")
        XCTAssertEqual(rows[2].control?.clipped("Hello there"), "Hello")
        XCTAssertEqual(rows[3].control?.shown, "40")
        XCTAssertEqual(rows[3].control?.stepped(1), "50")
        XCTAssertEqual(rows[3].control?.stepped(2), "50", "kept between its ends")
        XCTAssertEqual(rows[3].control?.stepped(-5), "0")
        XCTAssertEqual(spec.form?.cancelLabel, "Cancel")
        XCTAssertEqual(spec.initialValues, ["showPlaying": "true", "who": "friends", "status": "Hi", "volume": "40"])
        XCTAssertEqual(spec.focusOrder, ["show-what-i-play", "who-can-see-me", "status", "volume"])
        let again = try JSONDecoder().decode(DesignPageSpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(again, spec)
    }
}
