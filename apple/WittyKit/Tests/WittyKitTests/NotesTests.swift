// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

// The bell's answers as the server sends them, and where a notification may lead.
final class NotesTests: XCTestCase {
    func testTheServersListDecodes() throws {
        let json = #"{"notes":[{"id":9,"kind":"episodes","title":"New episode of A","body":"S1 E2","link":"/show/4","at":1795000000,"read":false},{"id":7,"kind":"server","title":"Out","at":1794000000,"read":true}],"unread":1,"latest":9}"#
        let list = try JSONDecoder().decode(NoteList.self, from: Data(json.utf8))
        XCTAssertEqual(list.notes?.count, 2)
        XCTAssertEqual(list.notes?.first?.link, "/show/4")
        XCTAssertNil(list.notes?.last?.body)
        XCTAssertEqual(list.unread, 1)
        XCTAssertEqual(list.latest, 9)
        let none = try JSONDecoder().decode(NoteList.self, from: Data(#"{"notes":null,"unread":0,"latest":0}"#.utf8))
        XCTAssertTrue((none.notes ?? []).isEmpty)
    }

    func testLinksStayInsideTheApp() {
        XCTAssertEqual(NoteKinds.show("/show/12"), 12)
        XCTAssertNil(NoteKinds.show("/tv/recordings"))
        XCTAssertEqual(NoteKinds.safeLink("/settings/about#updates"), "/settings/about#updates")
        XCTAssertNil(NoteKinds.safeLink("https://elsewhere.example/x"))
        XCTAssertNil(NoteKinds.safeLink("//elsewhere.example/x"))
        XCTAssertNil(NoteKinds.safeLink(nil))
        for kind in ["episodes", "recordings", "scans", "modules", "server"] { XCTAssertNotNil(NoteKinds.names[kind], kind) }
    }
}
