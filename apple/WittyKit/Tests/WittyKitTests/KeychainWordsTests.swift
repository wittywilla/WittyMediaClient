// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class KeychainWordsTests: XCTestCase {
    func testEachFailureSaysWhatWouldFixIt() {
        XCTAssertTrue(KeychainWords.notice(status: -34018).contains("isn't signed"))
        XCTAssertTrue(KeychainWords.notice(status: -34018).contains("AltStore or SideStore"))
        XCTAssertTrue(KeychainWords.notice(status: -25308).contains("Unlock it"))
        XCTAssertTrue(KeychainWords.notice(status: -50).contains("keychain error -50"))
    }
}
