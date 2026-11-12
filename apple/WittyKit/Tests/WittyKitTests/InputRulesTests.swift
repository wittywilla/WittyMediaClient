// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class InputRulesTests: XCTestCase {
    func testTheKeyMapHasEveryActionOnEveryDevice() {
        for device in InputDevice.allCases {
            for action in InputAction.allCases {
                XCTAssertFalse(KeyMap.keys(device, action).isEmpty, "\(device) has no key for \(action)")
            }
        }
    }

    func testTheContractsKeys() {
        XCTAssertTrue(KeyMap.keys(.keyboard, .back).contains("Escape"))
        XCTAssertTrue(KeyMap.keys(.keyboard, .search).contains("Ctrl+K"))
        XCTAssertEqual(KeyMap.keys(.gamepad, .select), ["A"])
        XCTAssertEqual(KeyMap.keys(.gamepad, .back), ["B"])
        XCTAssertTrue(KeyMap.keys(.gamepad, .options).contains("X"))
        XCTAssertEqual(KeyMap.keys(.gamepad, .search), ["Y"])
        XCTAssertTrue(KeyMap.keys(.remote, .options).contains("LongOK"))
        XCTAssertTrue(KeyMap.keys(.remote, .dock).contains("Menu"))
        XCTAssertEqual(KeyMap.keys(.gamepad, .dock), ["Start"])
    }

    func testAKeyMeansTheActionOfTheScreen() {
        // Space is both Select and Play/Pause: a player prefers the second.
        XCTAssertEqual(KeyMap.action(for: "Space", on: .keyboard, preferring: [.playPause, .select]), .playPause)
        XCTAssertEqual(KeyMap.action(for: "Space", on: .keyboard, preferring: [.select]), .select)
        XCTAssertEqual(KeyMap.action(for: "Escape", on: .keyboard, preferring: []), .back)
        XCTAssertNil(KeyMap.action(for: "F13", on: .keyboard, preferring: [.select]))
    }

    func testGlyphsAreWhatIsPrinted() {
        XCTAssertEqual(KeyMap.glyph("Period"), ".")
        XCTAssertEqual(KeyMap.glyph("Ctrl+BracketLeft"), "Ctrl+[")
        XCTAssertEqual(KeyMap.glyph("KeyK"), "K")
        XCTAssertEqual(KeyMap.glyph("Escape"), "Esc")
        XCTAssertEqual(KeyMap.glyph(.gamepad, .select), "A")
    }

    func testTheLegendIsInTheSameOrderEverywhereAndHiddenForTouch() {
        let pad = KeyLegend.hints(.grid, device: .gamepad)
        XCTAssertEqual(pad.first?.label, "Open")
        XCTAssertTrue(pad.contains { $0.action == .options })
        XCTAssertEqual(KeyLegend.hints(.shelves, device: .remote).last?.glyph, "Back")
        XCTAssertTrue(KeyLegend.visible(device: .remote, touchInUse: false, askedFor: false))
        XCTAssertTrue(KeyLegend.visible(device: .gamepad, touchInUse: false, askedFor: false))
        XCTAssertFalse(KeyLegend.visible(device: .remote, touchInUse: true, askedFor: false))
        XCTAssertFalse(KeyLegend.visible(device: .keyboard, touchInUse: false, askedFor: false))
        XCTAssertTrue(KeyLegend.visible(device: .keyboard, touchInUse: false, askedFor: true))
        XCTAssertFalse(KeyLegend.visible(device: nil, touchInUse: false, askedFor: true))
    }

    func testBackUnwindsLayerThenDockThenStageThenBarThenLeaves() {
        XCTAssertEqual(BackLadder.next(ZoneState(zone: .stage, layerOpen: true, hasDock: true)), .closeLayer)
        XCTAssertEqual(BackLadder.next(ZoneState(zone: .layer)), .closeLayer)
        XCTAssertEqual(BackLadder.next(ZoneState(zone: .dock, hasDock: true)), .closeDock)
        XCTAssertEqual(BackLadder.next(ZoneState(zone: .stage)), .focusBar)
        XCTAssertEqual(BackLadder.next(ZoneState(zone: .bar, barOnHome: false)), .goHome)
        XCTAssertEqual(BackLadder.next(ZoneState(zone: .bar, barOnHome: true)), .exit)
        // The ladder in the tokens is the order the cases above come in.
        XCTAssertEqual(DesignTokens.Nav.backLadder, ["layer", "dock", "stage", "bar", "home", "exit"])
    }

    func testZonesMoveByOnePressAndNeverWrap() {
        let stage = ZoneState(zone: .stage, hasDock: true)
        XCTAssertEqual(ZoneRules.leave(stage, .up, atEdge: true), .bar)
        XCTAssertNil(ZoneRules.leave(stage, .up, atEdge: false))
        XCTAssertEqual(ZoneRules.leave(stage, .down, atEdge: true), .dock)
        XCTAssertNil(ZoneRules.leave(ZoneState(zone: .stage, hasDock: false), .down, atEdge: true))
        XCTAssertEqual(ZoneRules.leave(ZoneState(zone: .bar), .down, atEdge: true), .stage)
        XCTAssertEqual(ZoneRules.leave(ZoneState(zone: .dock, hasDock: true), .up, atEdge: true), .stage)
        XCTAssertNil(ZoneRules.leave(ZoneState(zone: .bar), .up, atEdge: true))
        XCTAssertNil(ZoneRules.leave(ZoneState(zone: .stage, layerOpen: true, hasDock: true), .up, atEdge: true), "a layer keeps focus")
        XCTAssertFalse(DesignTokens.Nav.wrap)
        XCTAssertTrue(ZoneRules.opensDock(stage))
        XCTAssertFalse(ZoneRules.opensDock(ZoneState(zone: .dock, hasDock: true)))
        XCTAssertFalse(ZoneRules.opensDock(ZoneState(zone: .stage, hasDock: false)))
    }

    func testFocusMemoryReturnsWhereThePersonWas() {
        var memory = FocusMemory<String>()
        memory.focused("b3", group: "shelf-2", zone: .stage)
        XCTAssertEqual(memory.enter(group: "shelf-2", among: ["b1", "b2", "b3"]), "b3")
        XCTAssertEqual(memory.enter(group: "shelf-1", among: ["a1", "a2"]), "a1", "a group never visited starts at its first")
        XCTAssertEqual(memory.enter(group: "shelf-2", among: ["b1", "b2"]), "b1", "what was remembered is gone")
        XCTAssertEqual(memory.returnTo(zone: .stage, among: ["b3", "x"]), "b3")
        XCTAssertEqual(memory.returnTo(zone: .dock, among: ["d1", "d2"]), "d1")
        XCTAssertEqual(memory.returnTo(zone: .dock, among: ["d1", "d2"], fallback: "d2"), "d2")
        memory.forget(group: "shelf-2")
        XCTAssertEqual(memory.enter(group: "shelf-2", among: ["b1", "b3"]), "b1")
        memory.reset()
        XCTAssertNil(memory.returnTo(zone: .stage, among: []))
    }

    func testFocusMemoryCanBeSwitchedOffPerGroup() {
        var memory = FocusMemory<Int>(perGroup: false)
        memory.focused(2, group: "g", zone: .stage)
        XCTAssertEqual(memory.enter(group: "g", among: [1, 2, 3]), 1)
    }

    // The same cases as the web's spatial.test.mjs, so the two cannot drift.
    private func box(_ x: Double, _ y: Double, _ w: Double = 100, _ h: Double = 150) -> FocusBox { FocusBox(x: x, y: y, width: w, height: h) }
    private func best(_ from: FocusBox, _ all: [FocusBox], _ dir: Direction) -> FocusBox? {
        Spatial.ranked(from: from, all, box: { $0 }, dir).first
    }
    private var grid: [FocusBox] { (0..<3).flatMap { y in (0..<6).map { x in box(Double(x) * 120, Double(y) * 180) } } }
    private func at(_ x: Int, _ y: Int) -> FocusBox { grid[y * 6 + x] }

    func testAlongARowItStaysOnTheRow() {
        XCTAssertEqual(best(at(2, 1), grid, .right), at(3, 1))
        XCTAssertEqual(best(at(2, 1), grid, .left), at(1, 1))
        XCTAssertEqual(best(at(4, 1), grid, .down), at(4, 2))
        XCTAssertEqual(best(at(4, 1), grid, .up), at(4, 0))
    }

    func testNothingThatWayMeansNowhereToGo() {
        XCTAssertNil(best(at(0, 0), grid, .left))
        XCTAssertNil(best(at(5, 2), grid, .down))
        XCTAssertNil(Spatial.score(at(2, 1), at(2, 0), .down))
    }

    func testAFarCardOnThisRowBeatsANearOneOnTheNext() {
        let here = box(0, 0), sameLine = box(600, 0), nextLine = box(120, 180)
        XCTAssertEqual(best(here, [nextLine, sameLine], .right), sameLine)
    }

    func testFromANarrowButtonDownToAWideBarAndAWideProgramme() {
        let button = box(500, 0, 40, 40), bar = box(0, 60, 1000, 40), corner = box(0, 300, 40, 40)
        XCTAssertEqual(best(button, [corner, bar], .down), bar)
        let chip = box(437, 410, 52, 50), programme = box(662, 500, 1195, 95), footer = box(372, 980, 90, 40)
        XCTAssertEqual(best(chip, [footer, programme], .down), programme)
    }

    func testNearestWhenTheFocusHasGone() {
        let b = { (x: Double, y: Double) in FocusBox(x: x, y: y, width: 100, height: 40) }
        let items = [b(0, 0), b(300, 410), b(0, 900)]
        XCTAssertEqual(Spatial.nearest(from: b(300, 400), items, box: { $0 }), items[1])
        XCTAssertNil(Spatial.nearest(from: b(0, 0), [FocusBox](), box: { $0 }))
    }

    func testPagingStopsAtTheEnds() {
        XCTAssertEqual(Paging.row(from: 3, count: 100, page: 25, forward: true), 28)
        XCTAssertEqual(Paging.row(from: 90, count: 100, page: 25, forward: true), 99)
        XCTAssertEqual(Paging.row(from: 10, count: 100, page: 25, forward: false), 0)
        XCTAssertEqual(Paging.row(from: 0, count: 0, page: 25, forward: true), 0)
        XCTAssertEqual(Paging.timeShift(window: 7200), 3600)
        XCTAssertEqual(Paging.channelPageSizes, [25, 50, 75, 100, 0])
    }

    func testDensity() {
        XCTAssertEqual(Density.from(nil, tv: true), .comfortable)
        XCTAssertEqual(Density.from("compact", tv: true), .compact)
        XCTAssertEqual(Density.from("nonsense", tv: false), .comfortable)
        XCTAssertLessThan(Density.compact.space, Density.comfortable.space)
        XCTAssertGreaterThan(Density.spacious.control, Density.comfortable.control)
    }
}

final class DesignTokensTests: XCTestCase {
    func testTheTvNumbersAreTheContracts() {
        XCTAssertEqual(DesignTokens.Tv.safe.x, 90)
        XCTAssertEqual(DesignTokens.Tv.safe.y, 60)
        XCTAssertEqual(DesignTokens.Tv.Focus.ring, 4)
        XCTAssertEqual(DesignTokens.Tv.Focus.scale, 1.06)
        XCTAssertEqual(DesignTokens.Tv.Target.min, 66)
        XCTAssertEqual(DesignTokens.Tv.Shelf.peek, 0.18)
        XCTAssertEqual(DesignTokens.Tv.Dock.height, 112)
        XCTAssertEqual(DesignTokens.Tv.TopBar.pill, 56)
        XCTAssertEqual(DesignTokens.Tv.Card.Poster.w, 250)
        XCTAssertEqual(DesignTokens.Tv.Card.Wide.h, 236)
    }

    func testTheFocusLanguage() {
        XCTAssertEqual(DesignTokens.Focus.Input.tv.scale, 1.06)
        XCTAssertEqual(DesignTokens.Focus.Input.keys.width, 3)
        XCTAssertEqual(DesignTokens.Focus.Style.media, "ring-lift")
        XCTAssertEqual(DesignTokens.Focus.Style.control, "fill")
    }

    func testTheStepsOfSpaceAndDepth() {
        XCTAssertEqual(DesignTokens.Space.xl, 40)
        XCTAssertEqual(DesignTokens.Space.n4, 16)
        XCTAssertEqual(DesignTokens.Elevation.N1.fill, "bg2")
        XCTAssertEqual(DesignTokens.Elevation.N0.line, "none")
        XCTAssertEqual(DesignTokens.Motion.focusMove, 120)
        XCTAssertEqual(DesignTokens.Layout.Breakpoints.Medium.min, 600)
    }
}

final class TvGeometryTests: XCTestCase {
    func testCardsFollowTheirStyle() {
        XCTAssertEqual(TvGeometry.card("poster").width, 250)
        XCTAssertEqual(TvGeometry.card("wide").height, 236)
        XCTAssertEqual(TvGeometry.card("circle").width, 200)
        XCTAssertEqual(TvGeometry.card("whatever").height, 375)
    }

    func testAShelfShowsASliceOfTheNextCard() {
        let available = 1920.0 - 90
        let w = TvGeometry.peekWidth(available: available, nominal: 250)
        let n = Double(TvGeometry.wholeCards(available: available, width: w))
        let slice = available - n * (w + DesignTokens.Tv.Shelf.cardGap)
        XCTAssertEqual(slice, w * DesignTokens.Tv.Shelf.peek, accuracy: 0.5)
        XCTAssertEqual(w, 250, accuracy: 250 * 0.15)
    }

    func testNothingMoreNothingPeeks() {
        XCTAssertEqual(TvGeometry.peekWidth(available: 1830, nominal: 250, hasMore: false), 250)
    }

    func testTheRingIsConcentric() {
        XCTAssertEqual(TvGeometry.ringRadius(inner: 12), 12 + 4 + 4)
        XCTAssertGreaterThan(TvGeometry.focusRoom(cardWidth: 250), 8)
    }
}
