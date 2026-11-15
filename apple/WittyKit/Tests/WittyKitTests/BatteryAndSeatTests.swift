// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// Batteries in the same words as the website, said once; a game's invite and join links as seats.
final class BatteryAndSeatTests: XCTestCase {
    func testWords() {
        let p1 = BatteryReading(id: "pad-0", kind: .controller, name: "P1", detail: "DualSense", level: 0.153, charging: false)
        XCTAssertEqual(p1.text, "P1 15%")
        XCTAssertEqual(p1.label, "Controller P1, DualSense: battery 15%, low")
        let charging = BatteryReading(id: "pad-0", kind: .controller, name: "P1", detail: "DualSense", level: 0.153, charging: true)
        XCTAssertEqual(charging.label, "Controller P1, DualSense: battery 15%, charging")
        let device = BatteryReading(id: "device", kind: .device, name: "This device", level: 0.64, charging: false)
        XCTAssertEqual(device.text, "Battery 64%")
        XCTAssertEqual(device.label, "This device: battery 64%")
    }

    func testLowIsAFifthOrUnderNotCharging() {
        func r(_ level: Double, _ charging: Bool = false) -> BatteryReading { BatteryReading(id: "x", kind: .controller, name: "P1", level: level, charging: charging) }
        XCTAssertTrue(r(0.2).isLow)
        XCTAssertFalse(r(0.21).isLow)
        XCTAssertFalse(r(0.05, true).isLow)
    }

    func testDeviceWithNothingToSay() {
        XCTAssertNil(BatteryReading.device(level: -1, charging: false, full: false), "unknown level")
        XCTAssertNil(BatteryReading.device(level: 1, charging: true, full: true), "full on its charger")
        XCTAssertEqual(BatteryReading.device(level: 0.64, charging: false, full: false)?.text, "Battery 64%")
    }

    func testLowIsSaidOnceUntilCharged() {
        let notes = LowBatteryNotes()
        func p(_ level: Double, _ charging: Bool = false) -> BatteryReading { BatteryReading(id: "pad-0", kind: .controller, name: "P1", level: level, charging: charging) }
        func d(_ level: Double) -> BatteryReading { BatteryReading(id: "device", kind: .device, name: "This device", level: level, charging: false) }
        XCTAssertEqual(notes.check([p(0.5), d(0.5)]), [])
        XCTAssertEqual(notes.check([p(0.19), d(0.5)]), ["Controller P1’s battery is low: 19%. Charge it or change its batteries soon."])
        XCTAssertEqual(notes.check([p(0.15), d(0.5)]), [], "lower still")
        XCTAssertEqual(notes.check([p(0.22), d(0.5)]), [], "wobbling over the line")
        XCTAssertEqual(notes.check([p(0.19), d(0.5)]), [], "and back")
        XCTAssertEqual(notes.check([p(0.19, true), d(0.1)]), ["This device’s battery is low: 10%. Plug it in soon."])
        XCTAssertEqual(notes.check([p(0.18), d(0.1)]), ["Controller P1’s battery is low: 18%. Charge it or change its batteries soon."], "charged, then low again")
        XCTAssertEqual(notes.check([d(0.1)]), [], "the pad went")
        XCTAssertEqual(notes.check([p(0.1), d(0.1)]).count, 1, "back low: said again")
    }

    func testGameLinksAsSeats() {
        XCTAssertEqual(GameStart.from(["invite": "ab12", "join": "s1"]), .invite("ab12"), "an invite first")
        XCTAssertEqual(GameStart.from(["join": "3f9e"]), .join("3f9e"))
        XCTAssertEqual(GameStart.from(["resume": "1"]), .resume)
        XCTAssertTrue(GameStart.join("x").isSeat)
        XCTAssertFalse(GameStart.join("x").resumes)
        XCTAssertEqual(WebPlayer.serverGame("/game/7?join=3f9e")?.start, .join("3f9e"))
        XCTAssertEqual(WebPlayer.serverGame("/game/7?invite=ab12")?.start, .invite("ab12"))
    }
}
