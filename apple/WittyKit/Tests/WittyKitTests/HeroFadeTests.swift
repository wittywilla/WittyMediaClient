// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class HeroFadeTests: XCTestCase {
    func testSolidThenEasedOutToNothing() {
        let stops = HeroFade.stops(from: HeroFade.billboard)
        XCTAssertEqual(stops.first, HeroFade.Stop(location: 0, alpha: 1))
        XCTAssertEqual(stops[1], HeroFade.Stop(location: 0.48, alpha: 1))
        XCTAssertEqual(stops.last, HeroFade.Stop(location: 1, alpha: 0))
        XCTAssertEqual(stops[2].location, 0.48 + 0.52 * 0.23, accuracy: 1e-9)
        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThanOrEqual(a.location, b.location, "in order")
            XCTAssertGreaterThanOrEqual(a.alpha, b.alpha, "never comes back")
        }
    }

    func testTopFadesInWhenAsked() {
        let stops = HeroFade.stops(from: HeroFade.title, topIn: true)
        XCTAssertEqual(stops.first?.alpha, 0)
        XCTAssertEqual(stops.first(where: { $0.alpha == 1 })?.location, 0.25)
        XCTAssertEqual(stops.last?.alpha, 0)
        for (a, b) in zip(stops, stops.dropFirst()) { XCTAssertLessThanOrEqual(a.location, b.location) }
    }

    func testBrokenStartFallsBack() {
        XCTAssertEqual(HeroFade.stops(from: .nan)[1].location, HeroFade.billboard)
        XCTAssertLessThan(HeroFade.stops(from: 4)[1].location, 1)
    }

    func testSidesFadeOut() {
        let sides = HeroFade.sides()
        XCTAssertEqual(sides.first?.alpha, 0)
        XCTAssertEqual(sides.last?.alpha, 0)
        XCTAssertTrue(sides.contains { $0.location == 0.5 || ($0.location < 0.5 && $0.alpha == 1) })
    }
}
