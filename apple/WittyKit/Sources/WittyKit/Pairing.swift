// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Signing a device in from one that already is, with a QR code and a PIN that changes every 30 seconds
// (the server's docs/CLIENT-API.md, "With a QR code and a PIN"). Both ends are here: the device that
// shows the code, and the phone that scans it and types the PIN. The rules are here so they can be
// tested; the screens are in the app's PairDevice.swift and PairApprove.swift.

// MARK: - The device asking to be signed in

/// POST /auth/pair: a session to show as a QR code and a PIN.
public struct SecurePairStart: Decodable, Equatable {
    public let sessionId: String
    /// Kept by the device and never shown: it goes back only in the `X-WMS-Pair-Secret` header.
    public let deviceSecret: String
    public let pin: String
    /// Unix seconds.
    public let pinExpiresAt: Int64?
    public let period: Int?
    /// `wms://pair?...`, for an app that scans.
    public let qr: String?
    public let code: String?
    public let approvePath: String?
    public let approveUrl: String?
    public let expiresAt: Int64?
    public let expiresInSec: Int?
    public let intervalSec: Int?
}

/// GET /auth/pair/{session}/pin: the PIN to show now, and when to ask again.
public struct PairPin: Decodable, Equatable {
    public let pin: String
    public let pinExpiresAt: Int64?
    public let expiresAt: Int64?
}

/// What a device waiting to be signed in has on its screen, whichever way the server started it.
public struct PairShown: Equatable {
    /// ABCD-EFGH, for typing on the other device.
    public let code: String
    public let deviceSecret: String
    /// Only secure pairing has a session and a PIN.
    public let sessionId: String?
    public var pin: String
    public var pinExpiresAt: Int64
    /// How long one PIN lasts, for the countdown's bar.
    public let period: Int
    /// When the whole request ends, in Unix seconds.
    public let expiresAt: Int64
    public let intervalSec: Int
    /// What the QR code holds, and what is written beside it.
    public let address: String

    public var isSecure: Bool { sessionId != nil }

    public init(code: String, deviceSecret: String, sessionId: String?, pin: String, pinExpiresAt: Int64, period: Int,
                expiresAt: Int64, intervalSec: Int, address: String) {
        self.code = code
        self.deviceSecret = deviceSecret
        self.sessionId = sessionId
        self.pin = pin
        self.pinExpiresAt = pinExpiresAt
        self.period = period
        self.expiresAt = expiresAt
        self.intervalSec = intervalSec
        self.address = address
    }

    /// A code shown the older way: no PIN, ten minutes.
    public init(_ start: PairStart, base: String, now: Int64) {
        self.init(code: PlainWords.clean(start.code, limit: 16), deviceSecret: start.deviceSecret, sessionId: nil, pin: "", pinExpiresAt: 0,
                  period: 30, expiresAt: now + Int64(max(start.expiresInSec ?? 600, 30)), intervalSec: max(start.intervalSec ?? 3, 1),
                  address: start.approveAddress(base: base) ?? base)
    }

    public init(_ start: SecurePairStart, base: String, now: Int64) {
        let period = min(max(start.period ?? 30, 5), 300)
        self.init(code: PlainWords.clean(start.code ?? "", limit: 16), deviceSecret: start.deviceSecret,
                  sessionId: start.sessionId, pin: PairRules.digits(start.pin), pinExpiresAt: start.pinExpiresAt ?? now + Int64(period),
                  period: period, expiresAt: start.expiresAt ?? now + Int64(max(start.expiresInSec ?? 300, 30)),
                  intervalSec: max(start.intervalSec ?? 3, 1),
                  address: PairRules.qrText(approveUrl: start.approveUrl, qr: start.qr, base: base))
    }
}

/// What the server says when a waiting device asks whether someone answered.
public enum PairPollState: Equatable {
    case pending
    case approved(token: String)
    /// Someone pressed Deny on the other device.
    case denied
    /// Its minutes are up, or it was collected already.
    case expired
    /// Five wrong PINs ended it.
    case locked
    /// Asked too often: wait this many seconds, the code is still good.
    case slowDown(Int)
}

public enum PairRules {
    /// The header the device's secret travels in, so it stays out of addresses and logs.
    public static let secretHeader = "X-WMS-Pair-Secret"

    /// Where the server lists `pair-totp`, a device starts with the PIN. Older servers have only the code.
    public static func startsSecure(features: Set<String>) -> Bool { features.contains("pair-totp") }

    /// The owner allows only pairing with a PIN: `/pair/start` answered 426 `pin-required`.
    public static func mustBeSecure(_ error: APIError) -> Bool { error.status == 426 || error.code == "pin-required" }

    /// What the QR code holds. The server gives two things: `qr` (`wms://pair?...`), which only an app that
    /// knows it can read, and `approveUrl`, an ordinary web address. This app shows the web address, as the
    /// server's own sign-in page does: any phone's camera opens the approval page from it, with or without
    /// this app, and this app's own scanner reads the code out of it just as well (see `PairScan`). The
    /// `wms://` form is the fallback for a server that doesn't know its own address. Either way the PIN on
    /// the screen is what proves the person is looking at this device, not the QR code.
    public static func qrText(approveUrl: String?, qr: String?, base: String) -> String {
        let web = (approveUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = web.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://"), URL(string: web)?.host != nil { return web }
        if web.hasPrefix("/"), !base.isEmpty, let joined = Origin.join(base: base, path: web) { return joined.absoluteString }
        if let qr, qr.hasPrefix("wms://") { return qr }
        return Origin.join(base: base, path: "/pair")?.absoluteString ?? base
    }

    /// An answer to "has someone answered?", by its HTTP status and what it carried. The words win over the
    /// number: 410 is `expired` and `locked` both.
    public static func pollState(status: Int, word: String?, token: String?, retryAfter: Int = 0, intervalSec: Int? = nil) -> PairPollState {
        switch (word ?? "").lowercased() {
        case "approved":
            if let token, !token.isEmpty { return .approved(token: token) }
            return .expired // an approval with nothing to sign in with is no use to anyone
        case "pending": return .pending
        case "denied": return .denied
        case "locked": return .locked
        case "expired", "answered": return .expired
        case "slow-down": return .slowDown(max(retryAfter, intervalSec ?? 0, 1))
        default: break
        }
        switch status {
        case 200: return .pending
        case 403: return .denied
        case 404, 410: return .expired
        case 429: return .slowDown(max(retryAfter, intervalSec ?? 0, 1))
        default: return .pending
        }
    }

    /// The same, from a refusal.
    public static func pollState(_ error: APIError) -> PairPollState {
        struct Said: Decodable { let status: String?; let intervalSec: Int? }
        let said = error.decoded(Said.self)
        return pollState(status: error.status, word: said?.status, token: nil, retryAfter: error.retryAfter, intervalSec: said?.intervalSec)
    }

    /// How long to wait before asking again, after being told to slow down.
    public static func nextWait(current: Int, slowDown: Int) -> Int { min(max(current, slowDown) + 1, 30) }

    /// Only the digits of what was sent or typed, at most `limit`.
    public static func digits(_ text: String, limit: Int = 6) -> String {
        String(text.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init).prefix(limit))
    }

    /// A PIN as it's easiest to read across a room: "123 456".
    public static func grouped(_ pin: String) -> String {
        guard pin.count > 3 else { return pin }
        let half = pin.count / 2
        return pin.prefix(half) + " " + pin.dropFirst(half)
    }

    /// Whole seconds until a moment, never below zero. What "A new PIN in 12 s" counts.
    public static func secondsLeft(until: Int64, now: TimeInterval) -> Int {
        max(0, Int((Double(until) - now).rounded(.up)))
    }

    /// How much of the PIN's life is left, 0 to 1, for the bar under it.
    public static func share(until: Int64, period: Int, now: TimeInterval) -> Double {
        guard period > 0 else { return 0 }
        return min(max((Double(until) - now) / Double(period), 0), 1)
    }

    /// Time to fetch the next PIN: the one shown has run out.
    public static func pinIsStale(until: Int64, now: TimeInterval) -> Bool { now >= Double(until) }

    /// "4:05", for how long the whole code still lasts.
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + (s % 60 < 10 ? "0" : "") + "\(s % 60)"
    }

    /// What to say when the waiting ends without a sign-in.
    public static func ending(_ state: PairPollState) -> String? {
        switch state {
        case .denied: return "The sign-in was refused on the other device."
        case .expired: return "That took too long, so the code has expired."
        case .locked: return "Too many wrong PINs were typed, so this code was ended."
        case .pending, .approved, .slowDown: return nil
        }
    }
}

// MARK: - The phone that approves

/// What a QR code on a device asking to be signed in says: `wms://pair?v=1&s=&u=&c=&k=`.
public struct PairPayload: Equatable {
    /// The server's ID, as `/capabilities` and `/identity` give it.
    public let serverId: String
    /// Where the device reached the server. Only ever shown; nothing is sent there.
    public let base: String
    public let session: String
    /// The server's own check over the other fields. It goes back as it came.
    public let check: String

    public init(serverId: String, base: String, session: String, check: String) {
        self.serverId = serverId
        self.base = base
        self.session = session
        self.check = check
    }

    /// The same string the server writes (Go's `url.QueryEscape` for each value).
    public var text: String {
        "wms://pair?v=1&s=\(PairScan.escape(serverId))&u=\(PairScan.escape(base))&c=\(PairScan.escape(session))&k=\(PairScan.escape(check))"
    }
}

/// What a scanned code turned out to be.
public enum ScannedPair: Equatable {
    /// The app's own code: a session to look up, with its check.
    case session(PairPayload)
    /// The web address a device shows for any phone's camera. Only the code in it is used.
    case code(String)
}

public enum PairScanProblem: Error, Equatable {
    /// A QR code of something else entirely.
    case notPairing
    /// A pairing code of a newer kind than this app knows.
    case unknownVersion
    /// Parts are missing or unreadable.
    case incomplete
    /// It belongs to another server than the one this app is signed in to.
    case otherServer

    public var words: String {
        switch self {
        case .notPairing: return "That isn't a sign-in code. Scan the code on the screen of the device you want to sign in."
        case .unknownVersion: return "That sign-in code is of a newer kind than this app knows. Update the app, or type the code shown on the device."
        case .incomplete: return "That sign-in code couldn't be read. Try again, or type the code shown on the device."
        case .otherServer: return "That device is asking another server, not the one you're signed in to here. Nothing was sent."
        }
    }
}

public enum PairScan {
    /// Go's `url.QueryEscape`: letters, digits and `-_.~` stay, a space is `+`, the rest is `%XX`.
    public static func escape(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
                out.unicodeScalars.append(UnicodeScalar(byte))
            case UInt8(ascii: " "):
                out += "+"
            default:
                out += "%" + (byte < 16 ? "0" : "") + String(byte, radix: 16, uppercase: true)
            }
        }
        return out
    }

    /// Nil for an escape that isn't one, so a mangled code is refused rather than guessed at.
    static func unescape(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    /// The pairs of a query, each named once. A name given twice makes the whole thing unreadable: which
    /// one the server signed can't be told.
    static func query(_ text: String) -> [String: String]? {
        var out: [String: String] = [:]
        for part in text.split(separator: "&", omittingEmptySubsequences: true) {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = unescape(String(pair[0])), let value = unescape(pair.count > 1 ? String(pair[1]) : "") else { return nil }
            if out[name] != nil { return nil }
            out[name] = value
        }
        return out
    }

    /// A device's eight letters, however they were written: upper case, without the dash. Nil for anything else.
    public static func deviceCode(_ text: String) -> String? {
        let letters = text.uppercased().filter { $0 != "-" && $0 != " " }
        guard letters.count == 8, letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return letters
    }

    /// Reads what the camera saw. Nothing here talks to anything: it only takes the text apart.
    public static func parse(_ scanned: String) -> Result<ScannedPair, PairScanProblem> {
        let text = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 2048 else { return .failure(.notPairing) }
        let lower = text.lowercased()
        if lower.hasPrefix("wms://") {
            guard lower.hasPrefix("wms://pair?") else { return .failure(.notPairing) }
            let rest = String(text.dropFirst("wms://pair?".count)).split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            guard let fields = query(rest) else { return .failure(.incomplete) }
            guard fields["v"] == "1" else { return .failure(fields["v"] == nil ? .incomplete : .unknownVersion) }
            guard let server = fields["s"], let session = fields["c"], let check = fields["k"],
                  !server.isEmpty, !check.isEmpty, check.utf8.count <= 128, server.utf8.count <= 128,
                  // The server's sessions are 32 hex digits; anything else isn't one, and would end up in a path.
                  session.count == 32, session.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return .failure(.incomplete) }
            return .success(.session(PairPayload(serverId: server, base: fields["u"] ?? "", session: session.lowercased(), check: check)))
        }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let parts = URLComponents(string: text), parts.path == "/pair" || parts.path.hasSuffix("/pair") else { return .failure(.notPairing) }
            guard let raw = parts.queryItems?.first(where: { $0.name == "code" })?.value, let code = deviceCode(raw) else { return .failure(.incomplete) }
            return .success(.code(code))
        }
        return .failure(.notPairing)
    }

    /// The same, held against the server this app is signed in to. A code for another server is refused here,
    /// before anything is asked: the app only ever talks to the server it has already proved, never to the
    /// address inside a QR code, which anyone can print.
    public static func judge(_ scanned: String, signedInTo serverId: String) -> Result<ScannedPair, PairScanProblem> {
        switch parse(scanned) {
        case .success(.session(let payload)):
            guard !serverId.isEmpty, payload.serverId == serverId else { return .failure(.otherServer) }
            return .success(.session(payload))
        case let other:
            return other
        }
    }
}

/// POST /pair/info and GET /auth/pair/{session}/info: the device that is asking, and who it may be signed in as.
public struct PairRequest: Decodable, Equatable {
    public let code: String?
    public let sessionId: String?
    public let device: String?
    public let platform: String?
    public let ip: String?
    public let expiresAt: Int64?
    public let profiles: [PairProfile]?
    /// Started with a PIN: approving takes the six digits the device shows now.
    public let needsPin: Bool?
    /// The person approving has two-step sign-in, so confirming their password takes a code too.
    public let twoFactor: Bool?

    public var deviceName: String {
        let cleaned = PlainWords.clean(device ?? "", limit: 80)
        return cleaned.isEmpty ? "A device" : cleaned
    }

    /// "tvOS · 192.168.1.20", cleaned: the device wrote the first and the network the second.
    public var facts: String {
        [PlainWords.clean(platform ?? "", limit: 40), PlainWords.clean(ip ?? "", limit: 64)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A profile a device may be signed in as. `needsPassword` is an administrator's own account: the server
/// asks for their password again before it hands a device that much.
public struct PairProfile: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let kind: String?
    public let needsPassword: Bool?

    public init(id: Int64, name: String, kind: String? = nil, needsPassword: Bool? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.needsPassword = needsPassword
    }
}

/// Why an approval didn't go through, for deciding what the screen does next. The words shown are the server's own.
public enum PairRefusal: Equatable {
    /// Not the PIN shown now: type it again. `triesLeft` when the server said.
    case wrongPin(triesLeft: Int?)
    /// The device would be signed in as an administrator: their password (and code) first.
    case passwordRequired(twoFactor: Bool)
    /// The password or the authenticator's code given with it was wrong. The PIN's tries aren't used up.
    case wrongPassword
    /// Too many wrong tries: wait this long.
    case wait(seconds: Int)
    /// Over: expired, used, locked, not found, or a QR code that isn't this session's. Start again on the device.
    case ended
    case other

    public static func of(_ error: APIError, sentPassword: Bool) -> PairRefusal {
        struct Said: Decodable { let triesLeft: Int?; let twoFactor: Bool? }
        let said = error.decoded(Said.self)
        switch error.code {
        case "wrong-pin": return .wrongPin(triesLeft: said?.triesLeft)
        case "password-required": return .passwordRequired(twoFactor: said?.twoFactor == true || error.twoFactor)
        case "bad-check", "not-found", "expired", "used", "locked": return .ended
        default: break
        }
        if error.status == 429 { return .wait(seconds: max(error.retryAfter, 1)) }
        if error.status == 410 || error.status == 404 { return .ended }
        if error.status == 403, sentPassword { return .wrongPassword }
        return .other
    }

    /// "2 tries left", under the server's words about a wrong PIN.
    public static func triesWords(_ left: Int?) -> String {
        guard let left, left > 0 else { return "" }
        return left == 1 ? "1 try left." : "\(left) tries left."
    }
}

// MARK: - The calls

extension WittyClient {
    /// Starts secure pairing. No sign-in is needed, or sent.
    public func securePairStart(device: String, platform: String) async throws -> SecurePairStart {
        try await ask("POST", "/auth/pair", ["device": device, "platform": platform])
    }

    /// The PIN to show now. 404 and 410 mean the session is over or answered: the poll says which.
    public func securePairPin(session: String, secret: String) async throws -> PairPin {
        let answer = try await send("GET", "/auth/pair/\(WittyClient.pathPart(session))/pin", headers: [PairRules.secretHeader: secret])
        return try JSONDecoder().decode(PairPin.self, from: answer.data)
    }

    /// Has someone answered? Denied, expired, locked and slow-down are answers here, not errors.
    public func securePairPoll(session: String, secret: String) async throws -> PairPollState {
        struct Said: Decodable { let status: String?; let token: String?; let intervalSec: Int? }
        do {
            let answer = try await send("GET", "/auth/pair/\(WittyClient.pathPart(session))", headers: [PairRules.secretHeader: secret])
            let said = try JSONDecoder().decode(Said.self, from: answer.data)
            return PairRules.pollState(status: answer.status, word: said.status, token: said.token, intervalSec: said.intervalSec)
        } catch let error as APIError where [403, 404, 410, 429].contains(error.status) {
            return PairRules.pollState(error)
        }
    }

    /// The older code's poll, read the same way.
    public func pairPollState(deviceSecret: String) async throws -> PairPollState {
        let poll = try await pairPoll(deviceSecret: deviceSecret)
        return PairRules.pollState(status: 200, word: poll.status, token: poll.token, intervalSec: poll.intervalSec)
    }

    /// What is asking, by the code typed from its screen (or read out of the web address in its QR code).
    public func pairRequest(code: String) async throws -> PairRequest {
        try await ask("POST", "/pair/info", ["code": code])
    }

    /// What is asking, by the session in a scanned `wms://` code. The check goes back as it came; a wrong one is refused.
    public func pairRequest(_ scanned: PairPayload) async throws -> PairRequest {
        try await get("/auth/pair/\(WittyClient.pathPart(scanned.session))/info?k=\(WittyClient.queryValue(scanned.check))")
    }

    private struct Approval: Encodable {
        var code: String?
        var pin: String?
        var userId: Int64
        var check: String?
        var password: String?
        var otp: String?
    }

    /// Signs the device in, by its code. `pin` when the device shows one; `password` (and `otp`) when it will be
    /// signed in as an administrator.
    public func pairApprove(code: String, userId: Int64, pin: String, password: String = "", otp: String = "") async throws {
        try await tell("POST", "/pair/approve", Approval(code: code, pin: pin.isEmpty ? nil : pin, userId: userId,
                                                         password: password.isEmpty ? nil : password, otp: otp.isEmpty ? nil : otp))
    }

    /// Signs the device in, by a scanned session, with the PIN it shows now.
    public func pairApprove(_ scanned: PairPayload, userId: Int64, pin: String, password: String = "", otp: String = "") async throws {
        try await tell("POST", "/auth/pair/\(WittyClient.pathPart(scanned.session))/approve",
                       Approval(pin: pin, userId: userId, check: scanned.check, password: password.isEmpty ? nil : password, otp: otp.isEmpty ? nil : otp))
    }

    public func pairDeny(_ scanned: PairPayload) async throws {
        _ = try await call("POST", "/auth/pair/\(WittyClient.pathPart(scanned.session))/deny", body: Data("{}".utf8))
    }

    /// Six digits for a device to type. An administrator's own needs their password again.
    public func pairInvite(userId: Int64, password: String, otp: String = "") async throws -> PairInvite {
        struct Invite: Encodable { let userId: Int64; let password: String?; let otp: String? }
        return try await ask("POST", "/pair/invite", Invite(userId: userId, password: password.isEmpty ? nil : password, otp: otp.isEmpty ? nil : otp))
    }
}
