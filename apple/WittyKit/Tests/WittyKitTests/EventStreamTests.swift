// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class EventStreamTests: XCTestCase {
    private func events(_ lines: [String]) -> [ServerEvent] {
        var parser = EventParser()
        return lines.compactMap { parser.feed($0) }
    }

    func testAnEventIsItsNameAndItsData() {
        let found = events(["event: hello", "data: {\"v\":1}", "", "event: command", "data: {\"id\":\"c1\"}", ""])
        XCTAssertEqual(found.map(\.name), ["hello", "command"])
        XCTAssertEqual(String(data: found[1].data, encoding: .utf8), "{\"id\":\"c1\"}")
    }

    func testTheBlankLinesMayBeMissing() {
        // The system's line reader leaves them out.
        let found = events(["event: room", "data: {}", "event: closed", "data: {\"reason\":\"removed\"}"])
        XCTAssertEqual(found.map(\.name), ["room", "closed"])
    }

    func testTheKeepAliveIsNothing() {
        XCTAssertTrue(events([": still here", ": still here"]).isEmpty)
    }

    func testDataWithNoNameIsAMessageAndANameDoesNotOutliveItsEvent() {
        let found = events(["event: device", "data: 1", "", "data: 2"])
        XCTAssertEqual(found.map(\.name), ["device", "message"])
    }

    func testAFieldNobodyKnowsIsSkipped() {
        let found = events(["id: 7", "retry: 3000", "event: gone", "data:{\"id\":\"x\"}"])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(String(data: found[0].data, encoding: .utf8), "{\"id\":\"x\"}")
    }

    func testALineTooLongIsDroppedWithItsEvent() {
        let long = "data: " + String(repeating: "x", count: EventParser.maxLine)
        XCTAssertEqual(events(["event: device", long, "data: 1"]).map(\.name), ["message"])
    }

    func testAnEventIsReadAsWhatItHolds() {
        struct Bye: Decodable { let reason: String }
        let found = events(["event: bye", "data: {\"reason\":\"idle\"}"])
        XCTAssertEqual(found.first?.decoded(Bye.self)?.reason, "idle")
    }

    func testWaitsGrowToHalfAMinuteAndStartAgain() {
        var backoff = Backoff()
        XCTAssertEqual((0..<7).map { _ in backoff.next() }, [1, 2, 4, 8, 16, 30, 30])
        backoff.reset()
        XCTAssertEqual(backoff.next(), 1)
    }

    func testARefusalKeepsItsCodeAndItsBody() {
        struct More: Decodable { let triesLeft: Int }
        let error = APIError(status: 400, message: "Wrong PIN.", code: "wrong-pin", body: Data("{\"triesLeft\":3}".utf8))
        XCTAssertEqual(error.code, "wrong-pin")
        XCTAssertEqual(error.decoded(More.self)?.triesLeft, 3)
    }
}
