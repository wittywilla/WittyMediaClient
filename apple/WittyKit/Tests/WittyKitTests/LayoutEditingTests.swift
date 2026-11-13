// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class LayoutEditingTests: XCTestCase {
    private let regions = [
        LayoutRegion(id: "brand", label: "Server name", positions: ["start", "center", "top"]),
        LayoutRegion(id: "nav", label: "Menu", positions: ["start", "end", "top", "bottom"], locked: true),
        LayoutRegion(id: "search", label: "Search", positions: ["nav", "top", "floating"]),
        LayoutRegion(id: "dock", label: "Dock", positions: ["top", "bottom", "side"]),
        LayoutRegion(id: "legend", label: "Key legend"),
        LayoutRegion(id: "hero", label: "Spotlight", styles: ["billboard", "banner", "carousel", "row"]),
    ]
    private func draft(layer: [String: SDUIShell.Placement] = [:]) -> LayoutDraft {
        LayoutDraft(regions: regions, placements: ["nav": .init(position: "top", visible: true, style: nil), "hero": .init(position: nil, visible: true, style: "billboard")], layer: layer)
    }

    func testEveryRegionHasAPlaceAndIsShownToStartWith() {
        let d = draft()
        XCTAssertEqual(d.position("brand"), "start")
        XCTAssertEqual(d.position("nav"), "top")
        XCTAssertTrue(d.shown("legend"))
        XCTAssertEqual(d.style("hero"), "billboard")
        XCTAssertFalse(d.changed)
    }

    func testArrowsMoveTheMenuTheWayTheyPointAndStepThroughTheOthers() {
        let d = draft()
        XCTAssertEqual(d.target(of: "nav", .left), "start")
        XCTAssertEqual(d.target(of: "nav", .right), "end")
        XCTAssertEqual(d.target(of: "nav", .up), nil, "already at the top")
        XCTAssertEqual(d.target(of: "nav", .down), "bottom")
        XCTAssertEqual(d.target(of: "search", .right), "top")
        XCTAssertEqual(d.target(of: "search", .left), nil)
        XCTAssertEqual(d.target(of: "dock", .down), "bottom")
    }

    func testMovesUndoRedoAndRevert() {
        var d = draft()
        d.move("nav", to: "start")
        XCTAssertEqual(d.position("nav"), "start")
        XCTAssertTrue(d.changed)
        d.move("nav", to: "nowhere")
        XCTAssertEqual(d.position("nav"), "start", "a place the region doesn't have is refused")
        d.undoLast()
        XCTAssertEqual(d.position("nav"), "top")
        XCTAssertFalse(d.canUndo)
        d.redoLast()
        XCTAssertEqual(d.position("nav"), "start")
        d.move("dock", to: "side")
        d.revert()
        XCTAssertFalse(d.changed)
        d.undoLast()
        XCTAssertEqual(d.position("dock"), "side")
    }

    func testTheWayToSettingsCannotBeHidden() {
        var d = draft()
        XCTAssertFalse(d.canHide("nav"))
        d.setShown("nav", false)
        XCTAssertTrue(d.shown("nav"))
        d.setShown("legend", false)
        XCTAssertFalse(d.shown("legend"))
        XCTAssertEqual(d.announcement("legend"), "Key legend hidden.")
        d.move("nav", to: "end")
        XCTAssertEqual(d.announcement("nav"), "Menu moved to the right side.")
    }

    func testOnlyWhatChangedIsKept() {
        var d = draft(layer: ["search": .init(position: "top", visible: nil, style: nil)])
        d.move("nav", to: "start")
        d.setStyle("hero", "carousel")
        d.setStyle("hero", "wide")
        let layer = d.layerToSave
        XCTAssertEqual(Set(layer.keys), ["nav", "hero", "search"])
        XCTAssertEqual(layer["nav"]?.position, "start")
        XCTAssertEqual(layer["hero"]?.style, "carousel")
        XCTAssertNil(layer["hero"]?.position, "a region with no places sends none")
        XCTAssertEqual(layer["search"]?.position, "top", "an earlier choice is kept")
        XCTAssertTrue(draft().layerToSave.isEmpty)
    }

    func testPresetsRoundTripAndRefuseWhatTheShellCannotDo() throws {
        let preset = LayoutPreset(name: "Left menu", placements: ["nav": .init(position: "start", visible: true, style: nil)])
        let text = try preset.exported()
        XCTAssertEqual(try LayoutPreset.imported(text, regions: regions), preset)
        XCTAssertThrowsError(try LayoutPreset.imported(#"{"name":"x","placements":{"moon":{}}}"#, regions: regions))
        XCTAssertThrowsError(try LayoutPreset.imported(#"{"name":"x","placements":{"nav":{"position":"middle"}}}"#, regions: regions))
        XCTAssertThrowsError(try LayoutPreset.imported(#"{"name":"x","placements":{"nav":{"visible":false}}}"#, regions: regions))
        XCTAssertThrowsError(try LayoutPreset.imported("nope", regions: regions))
    }

    func testTheServersAnswerIsRead() throws {
        let json = #"{"experience":"lumen","regions":[{"id":"nav","label":"Menu","positions":["start","top"],"locked":true}],"placements":{"nav":{"position":"top","visible":true}},"own":{},"editable":true}"#
        let answer = try JSONDecoder().decode(LayoutPlacementsAnswer.self, from: Data(json.utf8))
        XCTAssertEqual(answer.regions.first?.locked, true)
        XCTAssertEqual(answer.placements["nav"]?.position, "top")
        XCTAssertTrue(answer.editable)
    }
}
