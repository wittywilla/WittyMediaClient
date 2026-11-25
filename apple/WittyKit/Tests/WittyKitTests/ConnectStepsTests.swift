// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation
import XCTest
@testable import WittyKit

/// The steps of connecting from away (shared/data/connect-steps.json, the server's own), and its
/// cases, which the server and every app answer the same way.
final class ConnectStepsTests: XCTestCase {
    private struct Cases: Decodable {
        struct Case: Decodable { let reason, text, step, code, at: String }
        let cases: [Case]
    }

    private func data() throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("shared/data/connect-steps.json"))
    }

    func testEveryCaseInTheSharedFile() throws {
        let raw = try data()
        let steps = try ConnectSteps(json: raw)
        XCTAssertEqual(steps.steps.map(\.id), ConnectSteps.order)
        let cases = try JSONDecoder().decode(Cases.self, from: raw).cases
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        for c in cases {
            let f = steps.classify(reason: c.reason, text: c.text, step: c.step)
            XCTAssertEqual(f.code, c.code, "\(c)")
            XCTAssertEqual(f.step, c.at, "\(c)")
            XCTAssertFalse(f.say.isEmpty || f.next.isEmpty)
        }
    }

    func testARunTicksUpToTheFailedStepAndNothingAfter() throws {
        let steps = try ConnectSteps(json: try data())
        let run = ConnectRun(kind: "invite", server: "12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz")
        run.pass("read")
        run.pass("found")
        run.fail(steps.classify(reason: "", text: "the server was found, but a direct connection through both routers couldn't be made", step: "secure"))
        XCTAssertEqual(run.states(steps.steps).map(\.state), [.ok, .ok, .fail, .skip])

        let late = ConnectRun(kind: "invite")
        ["read", "found", "secure"].forEach(late.pass)
        XCTAssertEqual(late.fail(steps.classify(reason: "", text: "the server didn't answer in time", step: "signin")).step, "signin")
        let slow = ConnectRun(kind: "invite")
        ["read", "found", "secure"].forEach(slow.pass)
        XCTAssertEqual(slow.fail(steps.of("slow-path", step: "secure")).step, "secure")
    }

    func testDetailsHoldNoSecrets() throws {
        let steps = try ConnectSteps(json: try data())
        let run = ConnectRun(kind: "invite", server: "12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz")
        run.note("opening wittymedia://p2p/12D3KooWAbCd?s=SuperSecretInvite123&n=Home")
        run.note("Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789")
        run.fail(steps.classify(reason: "", text: "token=abcdef123456 the server wasn't found", step: "found"))
        let out = run.details(steps.steps, app: "WittyMediaClient 0.6.3", device: "iPhone")
        for gone in ["SuperSecretInvite123", "abcdefghijklmnopqrstuvwxyz0123456789", "abcdef123456", "12D3KooWAbCdEfGhIjKlMnOpQrStUvWxYz"] {
            XCTAssertFalse(out.contains(gone), "\(gone) in \(out)")
        }
        XCTAssertTrue(out.contains("[!] Server found"))
    }

    func testWhileConnectingTheStepBeingTriedIsNowWithItsWordsAndTheSlowHintComesLater() throws {
        let steps = try ConnectSteps(json: try data())
        let run = ConnectRun(kind: "invite", server: "server")
        XCTAssertEqual(run.progress(steps).items.map(\.state), [.now, .wait, .wait, .wait])
        run.pass("read")
        run.pass("found")
        run.named("Living room")
        var p = run.progress(steps)
        XCTAssertEqual(p.items.map(\.state), [.ok, .ok, .now, .wait])
        XCTAssertEqual(p.step, "secure")
        XCTAssertEqual(p.doing, "Looking for a way to reach your server…")
        XCTAssertEqual(run.name, "Living room")
        XCTAssertEqual(p.slow, "")
        p = run.progress(steps, now: Date().addingTimeInterval(11))
        XCTAssertEqual(p.slow, steps.slow.say)
        XCTAssertEqual(p.clock, "0:11")
        run.stop("That code isn't one any server here made.")
        p = run.progress(steps, now: Date().addingTimeInterval(11))
        XCTAssertEqual(p.items.map(\.state), [.ok, .ok, .fail, .skip])
        XCTAssertEqual(p.failure?.say, "That code isn't one any server here made.")
        XCTAssertEqual(p.doing, "")
        XCTAssertEqual(p.slow, "")
    }

    func testEveryStepSaysWhatItIsDoing() throws {
        let steps = try ConnectSteps(json: try data())
        for s in steps.steps { XCTAssertTrue(s.doing.hasSuffix("…"), s.id) }
        XCTAssertTrue(steps.slow.after > 0 && steps.slow.say.hasSuffix("."))
    }
}
