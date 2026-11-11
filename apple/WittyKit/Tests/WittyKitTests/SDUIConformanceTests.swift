// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// The server's SDUI conformance kit (its pkg/sdui/conformance): for every fixture, the document the server
/// sends is read with the app's own decoder, built into the screen the views draw from, described in the kit's
/// normalised shape and compared with what the kit expects. The fixtures are the server's and aren't copied
/// into this repository: they're read from a checkout beside this one, from `WMS_SDUI_FIXTURES`, or from the
/// copy `apple/scripts/sync-sdui-fixtures.sh` makes.
final class SDUIConformanceTests: XCTestCase {
    struct Fixture: Decodable {
        struct Expected: Decodable {
            struct More: Decodable {
                let section: String
                let answer: JSONValue
            }
            let document: JSONValue?
            let layout: JSONValue?
            let more: [More]?
            let notFound: Bool?
        }
        let id: String
        let kit: Int
        let expected: Expected
    }

    static func fixtureFolder() -> URL? {
        let files = FileManager.default
        func usable(_ url: URL) -> Bool { files.fileExists(atPath: url.appendingPathComponent("index.json").path) }
        if let named = ProcessInfo.processInfo.environment["WMS_SDUI_FIXTURES"], !named.isEmpty {
            let url = URL(fileURLWithPath: named)
            return usable(url) ? url : nil
        }
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let copied = here.appendingPathComponent("Fixtures/sdui")
        if usable(copied) { return copied }
        // The server's repository beside this one, however deep this checkout is (a worktree is two deeper).
        var folder = here
        for _ in 0..<8 {
            folder = folder.deletingLastPathComponent()
            let beside = folder.appendingPathComponent("WittyMediaServer/pkg/sdui/conformance/fixtures")
            if usable(beside) { return beside }
        }
        return nil
    }

    static func fixtures() throws -> [Fixture] {
        guard let folder = fixtureFolder() else {
            if ProcessInfo.processInfo.environment["WMS_SDUI_FIXTURES_REQUIRED"] == "1" {
                XCTFail("The SDUI conformance fixtures are required and weren't found.")
            }
            throw XCTSkip("No SDUI conformance fixtures: put the server's repository beside this one, set WMS_SDUI_FIXTURES, or run apple/scripts/sync-sdui-fixtures.sh.")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") && $0 != "index.json" }.sorted()
        return try names.map { try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: folder.appendingPathComponent($0))) }
    }

    /// The first place two values differ, in words: fixtures are large.
    static func difference(_ got: JSONValue, _ want: JSONValue, at path: String = "") -> String? {
        switch (got, want) {
        case (.object(let a), .object(let b)):
            for key in Set(a.keys).union(b.keys).sorted() {
                guard let x = a[key] else { return "\(path)/\(key): missing, wanted \(describe(b[key]))" }
                guard let y = b[key] else { return "\(path)/\(key): \(describe(x)) wasn't expected" }
                if let found = difference(x, y, at: path + "/" + key) { return found }
            }
            return nil
        case (.array(let a), .array(let b)):
            for (index, pair) in zip(a, b).enumerated() {
                let name = pair.1["id"]?.string.map { "[\($0)]" } ?? "[\(index)]"
                if let found = difference(pair.0, pair.1, at: path + name) { return found }
            }
            return a.count == b.count ? nil : "\(path): \(a.count) entries, wanted \(b.count)"
        default:
            return got == want ? nil : "\(path): got \(describe(got)), wanted \(describe(want))"
        }
    }

    static func describe(_ value: JSONValue?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value) else { return "nothing" }
        return String(String(decoding: data, as: UTF8.self).prefix(200))
    }

    func testEveryFixtureIsLaidOutAsTheKitExpects() throws {
        let fixtures = try Self.fixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 57, "the kit has 57 cases")
        var passed = 0, pages = 0
        for fixture in fixtures {
            XCTAssertEqual(fixture.kit, 1, fixture.id)
            if fixture.expected.notFound == true {
                // The server's half: there is no page to lay out.
                XCTAssertNil(fixture.expected.document, fixture.id)
                passed += 1
                continue
            }
            pages += 1
            guard let sent = fixture.expected.document, let want = fixture.expected.layout else {
                XCTFail("\(fixture.id): no document or layout")
                continue
            }
            guard let document = sent.decoded(SDUIDocument.self) else {
                XCTFail("\(fixture.id): the app's decoder can't read the document")
                continue
            }
            let screen = SDUIScreen(document: document)
            let got = try JSONValue(encoding: screen.normalised())
            if let found = Self.difference(got.withoutZeroValues, want.withoutZeroValues) {
                XCTFail("\(fixture.id): \(found)")
            } else {
                passed += 1
            }
        }
        print("SDUI conformance: \(passed)/\(fixtures.count) fixtures pass (\(pages) pages laid out)")
        XCTAssertEqual(passed, fixtures.count)
    }

    /// The same document read, written and read again is the same document: nothing the app keeps on disk
    /// or patches loses what the server sent that the app draws.
    func testEveryDocumentSurvivesBeingKept() throws {
        for fixture in try Self.fixtures() {
            guard let sent = fixture.expected.document, let document = sent.decoded(SDUIDocument.self) else { continue }
            let again = try JSONDecoder().decode(SDUIDocument.self, from: JSONEncoder().encode(document))
            XCTAssertEqual(again, document, fixture.id)
            XCTAssertEqual(SDUIScreen(document: again).normalised(), SDUIScreen(document: document).normalised(), fixture.id)
        }
    }

    /// Numbering focus again in reading order gives every fixture the numbers the server gave it, which is what
    /// lets cards that arrive later be numbered in place.
    func testNumberingFocusAgainChangesNothing() throws {
        for fixture in try Self.fixtures() {
            guard let document = fixture.expected.document?.decoded(SDUIDocument.self) else { continue }
            var renumbered = document
            renumbered.renumberFocus()
            XCTAssertEqual(SDUIFocusPlan(root: renumbered.root), SDUIFocusPlan(root: document.root), fixture.id)
            XCTAssertEqual(renumbered, document, fixture.id)
        }
    }

    /// Every `expected.more`: the answer goes through the code that handles a real `more.url` response, and the
    /// section then holds its old cards followed by the new ones, or only the new ones with `replace`.
    func testEveryPageOfItemsLandsInItsSection() throws {
        var checked = 0
        for fixture in try Self.fixtures() {
            guard let document = fixture.expected.document?.decoded(SDUIDocument.self) else { continue }
            var current = document
            for more in fixture.expected.more ?? [] {
                guard let answer = more.answer.decoded(SDUISectionItems.self) else {
                    XCTFail("\(fixture.id): a page of \(more.section) can't be read")
                    continue
                }
                guard let before = current.root.find(more.section) else {
                    XCTFail("\(fixture.id): no section \(more.section)")
                    continue
                }
                let arrived = (answer.items ?? []).map(\.id)
                let waiting = before.state == "deferred"
                current = current.applying(answer, to: more.section)
                let after = current.root.find(more.section)
                let want = answer.replace == true || waiting ? arrived : before.kids.map(\.id) + arrived
                XCTAssertEqual(after?.kids.map(\.id), want, "\(fixture.id) \(more.section)")
                XCTAssertNil(after?.state, "\(fixture.id) \(more.section) is ready")
                XCTAssertEqual(after?.properties.fields("more")?.text("url") ?? "", answer.next ?? "", "\(fixture.id) \(more.section) continues from next")
                // Its cards are in its focus group, at the end, in the order sent; numbers still run from 1 without gaps.
                let plan = SDUIFocusPlan(root: current.root)
                if !arrived.isEmpty { XCTAssertEqual(Array((plan.groups[more.section] ?? []).suffix(arrived.count)), arrived, fixture.id) }
                let screen = SDUIScreen(document: current)
                XCTAssertEqual(screen.root.find(more.section)?.cards, want.count, fixture.id)
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 6)
    }
}
