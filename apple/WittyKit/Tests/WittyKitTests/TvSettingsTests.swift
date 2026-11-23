// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// shared/data/tv-settings.json, the desktop Settings pages a TV draws itself, read and kept as Android's TvSettingsTest does.
final class TvSettingsTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // WittyKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // WittyKit
            .deletingLastPathComponent() // apple
            .deletingLastPathComponent() // wittymediaclient
    }

    private func load() throws -> (TvSettingsFile, [String: String]) {
        let file = try JSONDecoder().decode(TvSettingsFile.self, from: Data(contentsOf: root.appendingPathComponent("shared/data/tv-settings.json")))
        let strings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("shared/data/strings.en.json")))
        return (file, strings)
    }

    private func row(_ file: TvSettingsFile, _ page: String, _ key: String) -> TvSettingsRow {
        file.page(page)!.groups.flatMap(\.rows).first { $0.key == key || $0.id == key }!
    }

    private func json(_ text: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    private func text(_ value: JSONValue) -> String { String(decoding: try! { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return try e.encode(value) }(), as: UTF8.self) }

    func testEveryWordIsTranslatedAndEveryRowIsKeptSomewhere() throws {
        let (file, strings) = try load()
        XCTAssertGreaterThanOrEqual(file.pages.count, 7)
        for page in file.pages {
            XCTAssertNotNil(strings[page.title], page.id)
            for group in page.groups {
                if let title = group.title, !title.isEmpty { XCTAssertNotNil(strings[title], title) }
                for r in group.rows {
                    XCTAssertNotNil(strings[r.label], r.label)
                    if ["bool", "enum", "int"].contains(r.kind) { XCTAssertNotNil(file.stores[r.store ?? ""], r.rowKey) }
                    XCTAssertTrue(["bool", "enum", "int", "info", "list", "link", "desktopOnly"].contains(r.kind), r.kind)
                }
            }
        }
    }

    func testASwitchReadsFlagsBooleansDefaultsAndItsOpposite() throws {
        let (file, _) = try load()
        let uploads = row(file, "sharing", "uploads")
        XCTAssertTrue(TvSettingsRules.bool(uploads, .string("1")))
        XCTAssertFalse(TvSettingsRules.bool(uploads, .string("0")))
        XCTAssertTrue(TvSettingsRules.bool(uploads, .string("")))
        XCTAssertEqual(TvSettingsRules.encode(uploads, .bool(false)), .string("0"))
        let shown = row(file, "activity", "activityHidden")
        XCTAssertTrue(TvSettingsRules.bool(shown, nil))
        XCTAssertFalse(TvSettingsRules.bool(shown, .bool(true)))
        XCTAssertEqual(TvSettingsRules.encode(shown, .bool(false)), .bool(true))
        let severity = row(file, "skipping", "contentFilters.minSeverity")
        XCTAssertEqual(TvSettingsRules.choice(severity, nil), "0")
        XCTAssertEqual(TvSettingsRules.choice(severity, .number(2)), "2")
        XCTAssertEqual(TvSettingsRules.encode(severity, .string("3")), .number(3))
    }

    func testAChangeIsSentAsTheWebSendsIt() throws {
        let (file, _) = try load()
        let server = file.stores["server"]!, ui = file.stores["ui"]!, streaming = file.stores["streaming"]!
        let audio = row(file, "appearance", "audioLanguage")
        XCTAssertEqual(text(TvSettingsRules.body(server, fresh: nil, row: audio, value: .string("fr"))), #"{"audioLanguage":"fr","menuLanguage":"fr"}"#)
        XCTAssertEqual(text(TvSettingsRules.body(server, fresh: nil, row: audio, value: .string(""))), #"{"audioLanguage":""}"#)
        let keep = row(file, "activity", "activityKeepCount")
        XCTAssertEqual(text(TvSettingsRules.body(server, fresh: nil, row: keep, value: .number(550))), #"{"activityKeepCount":"550"}"#)
        XCTAssertEqual(TvSettingsRules.stepped(keep, 950, by: 1), 1000)
        XCTAssertEqual(TvSettingsRules.stepped(keep, 5000, by: 1), 5000)
        XCTAssertEqual(TvSettingsRules.stepped(keep, 40, by: -1), 10)
        let credits = row(file, "skipping", "autoSkip.credits")
        XCTAssertEqual(text(TvSettingsRules.body(ui, fresh: json(#"{"posterTilt":false,"autoSkip":{"intro":true}}"#), row: credits, value: .bool(true))),
                       #"{"autoSkip":{"credits":true,"intro":true},"posterTilt":false}"#)
        let home = row(file, "quality", "prefs.home")
        XCTAssertEqual(text(TvSettingsRules.body(streaming, fresh: json(#"{"prefs":{"home":"","away":"h720-b4000"},"remote":{}}"#), row: home, value: .string("h1080-b8000"))),
                       #"{"away":"h720-b4000","home":"h1080-b8000"}"#)
    }

    func testValuesAreShownInTheirOwnWords() throws {
        let (file, strings) = try load()
        let page = file.page("quality")!
        let groups = TvSettingsRules.visible(file, page, admin: false)
        let stores = ["streaming": json(#"{"prefs":{"home":"h1080-b6000","away":""},"profile":{},"remote":{"maxHeight":1080,"maxKbps":8000}}"#)]
        let module = TvSettingsRules.asModule(file, page, groups, stores) { strings[$0] ?? $0 }
        let rows = module.pages[0].groups.flatMap(\.rows)
        let home = rows.first { $0.key == "streaming:prefs.home" }!
        XCTAssertEqual(home.options?.last?.label, "Your own, set in the player")
        XCTAssertTrue(module.canChange(home))
        XCTAssertEqual(module.values["streaming:profile"], .string("No limit"))
        XCTAssertEqual(module.values["streaming:remote"], .string("up to 1080p, 8 Mb/s at most"))
    }

    func testAdministratorsSeeTheServersRowsAndViewPagesAreRead() throws {
        let (file, _) = try load()
        let activity = file.page("activity")!
        XCTAssertEqual(TvSettingsRules.visible(file, activity, admin: false).flatMap(\.rows).compactMap(\.key), ["activityHidden"])
        XCTAssertTrue(TvSettingsRules.visible(file, activity, admin: true).flatMap(\.rows).contains { $0.key == "activityKeepDays" })
        let playback = file.page("playback")!
        XCTAssertFalse(TvSettingsRules.pageVisible(playback, admin: false))
        XCTAssertFalse(TvSettingsRules.editable(file, playback, row(file, "playback", "maxSpeed")))
        let about = ["about": json(#"{"version":"0.8.1-alpha","modules":[{"name":"WittyDVD","version":"0.4.0"}]}"#)]
        let items = TvSettingsRules.items(row(file, "about", "modules"), about)
        XCTAssertEqual(items.map(\.0), ["WittyDVD"])
        XCTAssertEqual(items.map(\.1), ["0.4.0"])
    }
}
