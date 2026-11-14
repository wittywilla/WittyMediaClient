// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class SDUIRowControlTests: XCTestCase {
    private func control(_ json: String) throws -> SDUIRowControl? {
        SDUIRowControl(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    func testASelectSendsTheChoiceAsValue() throws {
        let c = try XCTUnwrap(control(#"{"type":"select","name":"core","value":"","options":[{"value":"","label":"Automatically"},{"value":"snes9x","label":"Snes9x"}]}"#))
        XCTAssertEqual(c.shown, "Automatically")
        let action = SDUIAction(type: "command", item: "snes", op: "wittyplay.console.core")
        XCTAssertEqual(c.action(action, choosing: "snes9x")?.params?["value"], .string("snes9x"))
        XCTAssertEqual(c.action(action, choosing: "snes9x")?.op, "wittyplay.console.core")
    }

    func testADisabledControlRunsNothingAndSaysWhy() throws {
        let c = try XCTUnwrap(control(#"{"type":"select","options":[{"value":"","label":"Automatically"}],"disabled":true,"why":"Install one of its cores first."}"#))
        XCTAssertTrue(c.disabled)
        XCTAssertEqual(c.why, "Install one of its cores first.")
        XCTAssertNil(c.action(SDUIAction(type: "command", op: "x"), choosing: ""))
    }

    func testASwitchRunsItsActionAsItIs() throws {
        let c = try XCTUnwrap(control(#"{"type":"switch","value":true}"#))
        XCTAssertEqual(c.shown, "On")
        let action = SDUIAction(type: "command", op: "x", params: ["on": .bool(false)])
        XCTAssertEqual(c.action(action, choosing: "")?.params, ["on": .bool(false)])
        XCTAssertNil(SDUIRowControl(nil))
    }
}
