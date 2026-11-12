// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class PairingTests: XCTestCase {
    private let session = "0123456789abcdef0123456789abcdef"

    private func refusal(_ status: Int, _ json: String, retryAfter: Int = 0) -> APIError {
        struct Said: Decodable { let error: String?; let reason: String? }
        let said = try? JSONDecoder().decode(Said.self, from: Data(json.utf8))
        return APIError(status: status, message: said?.error ?? "", code: said?.reason ?? "", body: Data(json.utf8), retryAfter: retryAfter)
    }

    // MARK: What a scanned code says

    func testACodeGoesOutAndComesBackTheSame() throws {
        let sent = PairPayload(serverId: "srv-1 & co", base: "http://192.168.1.20:9797", session: session, check: "aB3_-xZ9Qw12Lm0p")
        // The server writes each value with Go's QueryEscape: a space is a plus, the rest is percent-escaped.
        XCTAssertEqual(sent.text, "wms://pair?v=1&s=srv-1+%26+co&u=http%3A%2F%2F192.168.1.20%3A9797&c=\(session)&k=aB3_-xZ9Qw12Lm0p")
        XCTAssertEqual(try PairScan.parse(sent.text).get(), .session(sent))
        XCTAssertEqual(try PairScan.parse("  " + sent.text + "\n").get(), .session(sent))
    }

    func testTheCheckIsCarriedBackUntouched() throws {
        // Base64url has no padding and uses - and _; nothing about it may be tidied.
        let text = "wms://pair?v=1&s=abc&u=&c=\(session)&k=%2B%2F-_AZaz09"
        guard case .session(let payload) = try PairScan.parse(text).get() else { return XCTFail("not a session") }
        XCTAssertEqual(payload.check, "+/-_AZaz09")
        XCTAssertEqual(payload.base, "")
    }

    func testCodesThisAppCannotReadAreRefusedInWords() {
        XCTAssertEqual(PairScan.parse("https://example.com/"), .failure(.notPairing))
        XCTAssertEqual(PairScan.parse("otpauth://totp/x?secret=abc"), .failure(.notPairing))
        XCTAssertEqual(PairScan.parse("wms://play?v=1"), .failure(.notPairing))
        XCTAssertEqual(PairScan.parse("wms://pair?v=2&s=a&u=b&c=\(session)&k=c"), .failure(.unknownVersion))
        XCTAssertEqual(PairScan.parse("wms://pair?s=a&u=b&c=\(session)&k=c"), .failure(.incomplete))
        XCTAssertEqual(PairScan.parse("wms://pair?v=1&s=a&u=b&c=\(session)"), .failure(.incomplete))
        XCTAssertEqual(PairScan.parse("wms://pair?v=1&s=&u=b&c=\(session)&k=c"), .failure(.incomplete))
        // A session is 32 hex digits: anything else would end up in a path.
        XCTAssertEqual(PairScan.parse("wms://pair?v=1&s=a&u=b&c=../../logout&k=c"), .failure(.incomplete))
        XCTAssertEqual(PairScan.parse("wms://pair?v=1&s=a&u=b&c=abc&k=c"), .failure(.incomplete))
        // A broken escape, or a field given twice, is not guessed at.
        XCTAssertEqual(PairScan.parse("wms://pair?v=1&s=%zz&u=b&c=\(session)&k=c"), .failure(.incomplete))
        XCTAssertEqual(PairScan.parse("wms://pair?v=1&s=a&s=b&u=b&c=\(session)&k=c"), .failure(.incomplete))
        XCTAssertEqual(PairScan.parse(String(repeating: "a", count: 5000)), .failure(.notPairing))
        for problem in [PairScanProblem.notPairing, .unknownVersion, .incomplete, .otherServer] { XCTAssertFalse(problem.words.isEmpty) }
    }

    func testACodeForAnotherServerIsRefusedBeforeAnythingIsSent() throws {
        let text = PairPayload(serverId: "server-A", base: "http://evil.example", session: session, check: "k").text
        XCTAssertEqual(PairScan.judge(text, signedInTo: "server-B"), .failure(.otherServer))
        // An app that doesn't know its own server's ID can't tell, so it refuses too.
        XCTAssertEqual(PairScan.judge(text, signedInTo: ""), .failure(.otherServer))
        guard case .session(let payload) = try PairScan.judge(text, signedInTo: "server-A").get() else { return XCTFail("not a session") }
        XCTAssertEqual(payload.session, session)
    }

    func testTheWebAddressADeviceShowsGivesOnlyItsCode() throws {
        XCTAssertEqual(try PairScan.parse("http://192.168.1.20:9797/pair?code=BCDF-GHJK").get(), .code("BCDFGHJK"))
        XCTAssertEqual(try PairScan.parse("https://media.example/pair?code=bcdfghjk").get(), .code("BCDFGHJK"))
        // Whatever host it names, the same code comes out: the app asks its own server about it.
        XCTAssertEqual(try PairScan.judge("https://evil.example/pair?code=BCDF-GHJK", signedInTo: "server-A").get(), .code("BCDFGHJK"))
        XCTAssertEqual(PairScan.parse("https://media.example/pair"), .failure(.incomplete))
        XCTAssertEqual(PairScan.parse("https://media.example/pair?code=123"), .failure(.incomplete))
        XCTAssertEqual(PairScan.parse("https://media.example/login?code=BCDF-GHJK"), .failure(.notPairing))
        XCTAssertEqual(PairScan.deviceCode("bcdf ghjk"), "BCDFGHJK")
        XCTAssertNil(PairScan.deviceCode("BCDF-GHJ1"))
    }

    // MARK: What the device shows

    func testTheQRCodeHoldsTheWebAddressAnyPhoneCanOpen() {
        XCTAssertEqual(PairRules.qrText(approveUrl: "http://192.168.1.20:9797/pair?code=BCDF-GHJK", qr: "wms://pair?v=1", base: "http://tv.local:9797"),
                       "http://192.168.1.20:9797/pair?code=BCDF-GHJK")
        // A server that doesn't know its own address gives a path: this device knows where it reached it.
        XCTAssertEqual(PairRules.qrText(approveUrl: "/pair?code=BCDF-GHJK", qr: "wms://pair?v=1", base: "http://tv.local:9797"),
                       "http://tv.local:9797/pair?code=BCDF-GHJK")
        XCTAssertEqual(PairRules.qrText(approveUrl: "javascript:alert(1)", qr: "wms://pair?v=1&s=a", base: ""), "wms://pair?v=1&s=a")
        XCTAssertEqual(PairRules.qrText(approveUrl: nil, qr: nil, base: "http://tv.local:9797"), "http://tv.local:9797/pair")
    }

    func testSecurePairingIsStartedOnlyWhereTheServerOffersIt() {
        XCTAssertTrue(PairRules.startsSecure(features: ["pair-totp", "pair-qr"]))
        XCTAssertFalse(PairRules.startsSecure(features: ["themes"]))
        XCTAssertTrue(PairRules.mustBeSecure(refusal(426, #"{"error":"This server signs devices in with a PIN.","reason":"pin-required","use":"/api/v1/auth/pair"}"#)))
        XCTAssertFalse(PairRules.mustBeSecure(refusal(429, #"{"error":"busy"}"#)))
    }

    func testWhatIsShownIsReadFromEitherStart() throws {
        let old = try JSONDecoder().decode(PairStart.self, from: Data(#"{"code":"BCDF-GHJK","deviceSecret":"s","expiresInSec":600,"intervalSec":3,"approvePath":"/pair","approveUrl":"/pair?code=BCDF-GHJK"}"#.utf8))
        let plain = PairShown(old, base: "http://tv.local:9797", now: 1000)
        XCTAssertFalse(plain.isSecure)
        XCTAssertEqual(plain.expiresAt, 1600)
        XCTAssertEqual(plain.address, "http://tv.local:9797/pair?code=BCDF-GHJK")

        let json = #"{"sessionId":"\#(session)","deviceSecret":"s","pin":"123456","pinExpiresAt":1030,"period":30,"digits":6,"qr":"wms://pair?v=1","code":"BCDF-GHJK","approvePath":"/pair","approveUrl":"http://192.168.1.20:9797/pair?code=BCDF-GHJK","expiresAt":1300,"expiresInSec":300,"intervalSec":3}"#
        let secure = PairShown(try JSONDecoder().decode(SecurePairStart.self, from: Data(json.utf8)), base: "http://tv.local:9797", now: 1000)
        XCTAssertTrue(secure.isSecure)
        XCTAssertEqual(secure.pin, "123456")
        XCTAssertEqual(secure.pinExpiresAt, 1030)
        XCTAssertEqual(secure.expiresAt, 1300)
        XCTAssertEqual(secure.address, "http://192.168.1.20:9797/pair?code=BCDF-GHJK")
    }

    func testThePinCountsDownAndIsAskedForAgainWhenItRunsOut() {
        XCTAssertEqual(PairRules.secondsLeft(until: 1030, now: 1000), 30)
        XCTAssertEqual(PairRules.secondsLeft(until: 1030, now: 1029.2), 1)
        XCTAssertEqual(PairRules.secondsLeft(until: 1030, now: 1030), 0)
        XCTAssertEqual(PairRules.secondsLeft(until: 1030, now: 1100), 0)
        XCTAssertEqual(PairRules.share(until: 1030, period: 30, now: 1015), 0.5, accuracy: 0.001)
        XCTAssertEqual(PairRules.share(until: 1030, period: 30, now: 900), 1)
        XCTAssertEqual(PairRules.share(until: 1030, period: 0, now: 900), 0)
        XCTAssertFalse(PairRules.pinIsStale(until: 1030, now: 1029.9))
        XCTAssertTrue(PairRules.pinIsStale(until: 1030, now: 1030))
        XCTAssertEqual(PairRules.grouped("123456"), "123 456")
        XCTAssertEqual(PairRules.grouped("12"), "12")
        XCTAssertEqual(PairRules.digits("12 34-56x789"), "123456")
        XCTAssertEqual(PairRules.clock(245), "4:05")
        XCTAssertEqual(PairRules.clock(-3), "0:00")
    }

    func testEveryAnswerToTheWaitingDeviceIsUnderstood() {
        XCTAssertEqual(PairRules.pollState(status: 200, word: "pending", token: nil), .pending)
        XCTAssertEqual(PairRules.pollState(status: 200, word: "approved", token: "tok"), .approved(token: "tok"))
        // An approval with no sign-in in it is no use: ask for a new code.
        XCTAssertEqual(PairRules.pollState(status: 200, word: "approved", token: ""), .expired)
        XCTAssertEqual(PairRules.pollState(refusal(403, #"{"status":"denied","error":"the sign-in was refused"}"#)), .denied)
        XCTAssertEqual(PairRules.pollState(refusal(410, #"{"status":"expired","error":"gone"}"#)), .expired)
        // 410 is two things: the word says which.
        XCTAssertEqual(PairRules.pollState(refusal(410, #"{"status":"locked","error":"too many wrong PINs were typed; start again"}"#)), .locked)
        XCTAssertEqual(PairRules.pollState(refusal(429, #"{"status":"slow-down","error":"polling too fast","intervalSec":3}"#, retryAfter: 3)), .slowDown(3))
        XCTAssertEqual(PairRules.pollState(refusal(404, #"{"status":"expired"}"#)), .expired)
        // An answer with no word in it is read by its number.
        XCTAssertEqual(PairRules.pollState(refusal(403, "{}")), .denied)
        XCTAssertEqual(PairRules.pollState(refusal(429, "nonsense")), .slowDown(1))
        XCTAssertEqual(PairRules.nextWait(current: 3, slowDown: 3), 4)
        XCTAssertEqual(PairRules.nextWait(current: 40, slowDown: 3), 30)
        XCTAssertNil(PairRules.ending(.pending))
        XCTAssertNotNil(PairRules.ending(.locked))
        XCTAssertNotNil(PairRules.ending(.denied))
    }

    // MARK: Approving

    func testWhatIsAskingIsReadWithItsProfiles() throws {
        let json = #"{"code":"BCDF-GHJK","device":"Living room\u0007 Apple TV","platform":"tvOS","ip":"192.168.1.30","createdAt":1,"expiresAt":2,"profiles":[{"id":1,"name":"willa","kind":"adult","needsPassword":true},{"id":2,"name":"mia","kind":"kids"}],"needsPin":true,"twoFactor":false,"sessionId":"\#(session)"}"#
        let asked = try JSONDecoder().decode(PairRequest.self, from: Data(json.utf8))
        XCTAssertEqual(asked.deviceName, "Living room Apple TV")
        XCTAssertEqual(asked.facts, "tvOS · 192.168.1.30")
        XCTAssertEqual(asked.needsPin, true)
        XCTAssertEqual(asked.profiles?.first?.needsPassword, true)
        XCTAssertNil(asked.profiles?.last?.needsPassword)
        XCTAssertEqual(try JSONDecoder().decode(PairRequest.self, from: Data("{}".utf8)).deviceName, "A device")
    }

    func testEachRefusalLeadsSomewhere() {
        XCTAssertEqual(PairRefusal.of(refusal(400, #"{"error":"That PIN isn't right.","reason":"wrong-pin","triesLeft":3}"#), sentPassword: false), .wrongPin(triesLeft: 3))
        XCTAssertEqual(PairRefusal.of(refusal(403, #"{"error":"needs your password","reason":"password-required","twoFactor":true}"#), sentPassword: false), .passwordRequired(twoFactor: true))
        XCTAssertEqual(PairRefusal.of(refusal(403, #"{"error":"needs your password","reason":"password-required","twoFactor":false}"#), sentPassword: false), .passwordRequired(twoFactor: false))
        XCTAssertEqual(PairRefusal.of(refusal(403, #"{"error":"wrong password"}"#), sentPassword: true), .wrongPassword)
        XCTAssertEqual(PairRefusal.of(refusal(403, #"{"error":"you can't sign a device in as that profile"}"#), sentPassword: false), .other)
        for reason in ["bad-check", "not-found", "expired", "used", "locked"] {
            XCTAssertEqual(PairRefusal.of(refusal(410, #"{"error":"x","reason":"\#(reason)"}"#), sentPassword: false), .ended, reason)
        }
        XCTAssertEqual(PairRefusal.of(refusal(404, #"{"error":"That code isn't valid."}"#), sentPassword: false), .ended)
        XCTAssertEqual(PairRefusal.of(refusal(429, #"{"error":"Too many wrong codes."}"#, retryAfter: 45), sentPassword: false), .wait(seconds: 45))
        XCTAssertEqual(PairRefusal.triesWords(1), "1 try left.")
        XCTAssertEqual(PairRefusal.triesWords(4), "4 tries left.")
        XCTAssertEqual(PairRefusal.triesWords(nil), "")
        XCTAssertEqual(PairRefusal.triesWords(0), "")
    }
}
