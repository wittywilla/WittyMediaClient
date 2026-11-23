// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class PeerInviteTests: XCTestCase {
    func testTheServersAnswerReadsAndSaysItsMinutes() throws {
        let answer = #"{"link":"wittymedia://p2p/abc","expiresInSec":900,"user":{"id":1}}"#
        let invite = try JSONDecoder().decode(PeerInviteLink.self, from: Data(answer.utf8))
        XCTAssertEqual(invite.link, "wittymedia://p2p/abc")
        XCTAssertEqual(invite.minutes, 15)
        XCTAssertEqual(PeerInviteLink(link: "x", expiresInSec: 20).minutes, 1)
    }

    func testANameThatCameInAnInviteIsShownAsPlainText() {
        XCTAssertEqual(PeerConnect.shownName("Home\u{202E}gnp.exe", limit: 80), "Homegnp.exe")
        XCTAssertEqual(PeerConnect.shownName(" \u{2066}Bank\u{2069}\u{1B} ", limit: 80), "Bank")
        XCTAssertEqual(PeerConnect.shownName("\u{FEFF}TV\u{200F}", limit: 80), "TV")
        XCTAssertEqual(PeerConnect.shownName(String(repeating: "\u{1F3E0}", count: 90), limit: 80), String(repeating: "\u{1F3E0}", count: 80))
    }
}
