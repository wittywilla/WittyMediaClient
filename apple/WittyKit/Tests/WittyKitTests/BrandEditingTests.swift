// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class BrandEditingTests: XCTestCase {
    /// The server's own cases (internal/brandname/testdata/cases.json): coloured words in [brackets].
    func testWordsAreFoundAsTheServerFindsThem() {
        let cases: [(String, String)] = [
            ("WittyMediaServer", "Witty[Media]Server"), ("MyHomeTheater", "My[Home]Theater"), ("Willow's Movies", "Willow's [Movies]"),
            ("Kim's TV Room", "Kim's [TV] Room"), ("HDTV", "HDTV"), ("MyTVRoom", "My[TV]Room"), ("TVRoom", "TV[Room]"),
            ("Kim's DVDs", "Kim's [DVDs]"), ("Our TVs at Home", "Our [TVs] at [Home]"), ("Movies4K", "Movies[4K]"), ("4KMovies", "4K[Movies]"),
            ("Studio54 Films", "Studio[54] Films"), ("HDTV2Go", "HDTV2Go"), ("iPhone Videos", "i[Phone] Videos"),
            ("Witty-Media-Server", "Witty-[Media-]Server"), ("Home&Away", "Home&[Away]"), ("-Home", "-Home"), ("O'Brien Family", "O'Brien [Family]"),
            ("J.R. Movies", "J.R. [Movies]"), ("A B C D", "A [B] C [D]"),
        ]
        for (name, want) in cases {
            var draft = BrandDraft(name: name)
            draft.use(.accentOnMedia)
            let got = draft.parts.map { $0.color?.kind == "accent" ? "[\($0.text)]" : $0.text }.joined()
            XCTAssertEqual(got, want, name)
        }
    }

    func testTheDefaultNameHasMediaInTheAccent() {
        let draft = BrandDraft(name: "")
        XCTAssertEqual(draft.shown, "WittyMediaServer")
        XCTAssertEqual(draft.spans, [BrandSpan(from: 5, to: 10, color: .init(kind: "accent"), bold: nil)])
    }

    func testColouringASelectionMakesSpansTheServerAccepts() throws {
        var draft = BrandDraft(name: "")
        draft.use(.plain)
        draft.apply(.init(kind: "static", hex: "#b4491f"), to: 0..<5)
        draft.apply(.init(kind: "gradient", stops: ["#1e9be0", "#3aa84a"], angle: 90), bold: true, to: 5..<16)
        XCTAssertEqual(draft.spans.count, 2)
        XCTAssertEqual(draft.spans[1].bold, true)
        XCTAssertTrue(draft.problems.isEmpty)
        let settings = try draft.settings()
        XCTAssertEqual(settings["brandColouring"], "auto")
        let back = try JSONDecoder().decode([BrandSpan].self, from: Data(try XCTUnwrap(settings["brandSpans"]).utf8))
        XCTAssertEqual(back, draft.spans)
        XCTAssertEqual(settings["brandMark"], #"{"kind":"letter"}"#)
    }

    func testPlainSavesNoSpansAndALongRainbowIsRefused() throws {
        var draft = BrandDraft(name: "")
        draft.use(.plain)
        XCTAssertEqual(try draft.settings()["brandSpans"], "")
        draft.rename(String(repeating: "Ab", count: 40))
        draft.use(.rainbow)
        XCTAssertTrue(draft.problems.contains { $0.contains("colour changes") })
    }

    func testRenamingKeepsTheColoursOfTheLettersThatStay() {
        var draft = BrandDraft(name: "")
        draft.rename("Witty")
        draft.apply(.init(kind: "accent"), to: 0..<2)
        draft.rename("Wit")
        XCTAssertEqual(draft.letters.count, 3)
        XCTAssertEqual(draft.styles[1].colour.kind, "accent")
        draft.rename("Wittiest")
        XCTAssertEqual(draft.styles.count, 8)
    }

    func testTheMark() {
        XCTAssertEqual(BrandMarkChoice(kind: "letter").shown(name: "orchid"), "O")
        XCTAssertEqual(BrandMarkChoice(kind: "initials").shown(name: "WittyMediaServer"), "WMS")
        XCTAssertEqual(BrandMarkChoice.custom("♥")?.shown(name: "x"), "♥")
        XCTAssertNil(BrandMarkChoice.custom("abc"))
        XCTAssertNil(BrandMarkChoice.custom("  "))
    }

    func testAFixedColourThatDoesNotReadIsWarnedWithNumbers() {
        var draft = BrandDraft(name: "")
        draft.use(.plain)
        draft.apply(.init(kind: "static", hex: "#f0f0f0"), to: 5..<10)
        let light = ["bg": "#ffffff", "bg2": "#f4f4f4", "bg3": "#ececec", "fg": "#111111", "brandAccent": "#0a6aa8"]
        let warned = BrandContrast.warnings(draft, colors: light)
        XCTAssertFalse(warned.isEmpty)
        XCTAssertEqual(warned.first?.text, "Media")
        XCTAssertLessThan(warned.first?.ratio ?? 99, 4.5)
        let dark = ["bg": "#0a0a0a", "bg2": "#141414", "bg3": "#1c1c1c", "fg": "#f5f5f5", "brandAccent": "#8ab4ff"]
        XCTAssertTrue(BrandContrast.warnings(draft, colors: dark).isEmpty)
        // A theme token follows the theme, so the same name is fine in both.
        var themed = BrandDraft(name: "")
        themed.use(.accentOnMedia)
        XCTAssertTrue(BrandContrast.warnings(themed, colors: light).isEmpty)
    }
}
