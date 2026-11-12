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
}
