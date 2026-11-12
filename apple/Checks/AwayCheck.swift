// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The Apple TV app (or the iPhone one), in a simulator, against a real WittyMediaServer with
/// peer-to-peer connections on. `apple/scripts/p2p-check.sh` starts the server and runs these in order, taking
/// the server's home address away between the first and the second:
///
///   testHome   a code shown on the TV is approved, as from a phone (with the PIN beside it, when the
///              server pairs securely); the app then puts this device on the server's list by itself
///   testInvite a device that never met the server takes an invite link in, and is signed in by it
///   testJoinFromAway   (only with P2P_CHECK_PUBLIC=1) a TV that has never met the server shows a code,
///              which is typed into the server; the two find each other through the public address book
///   testAway   the home address no longer answers: the app has to find the server peer to peer,
///              still signed in, and play a film through the connection; then leave the screen
///              and come back, and carry on
///
/// What the script hands over, as TEST_RUNNER_ variables: CHECK_HOME (the address the app is told,
/// a forwarder the script stops), CHECK_DIRECT (the server's own, which only this check uses),
/// CHECK_TOKEN and CHECK_PASSWORD (the owner's sign-in, and the password an administrator's approval
/// takes) and CHECK_ITEM (a film to play).
@MainActor
final class AwayCheck: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.wittywilla.wittymediaclient")

    /// What the app calls its system when it puts itself on the server's list.
    #if os(tvOS)
    private static let platform = "tvOS"
    #else
    private static let platform = "iOS"
    #endif

    private func given(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("\(name) isn't set: run apple/scripts/p2p-check.sh, which sets it")
        }
        return value
    }

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Asking the server

    private func ask(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> (Int, Any?) {
        let base = try given("CHECK_DIRECT")
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + path)), timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("Bearer \(try given("CHECK_TOKEN"))", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: data))
    }

    private func list(_ path: String) async throws -> [[String: Any]] {
        (try await ask("GET", path).1 as? [[String: Any]]) ?? []
    }

    /// Asks again until `found` answers, or fails with what was last seen.
    private func until<T>(_ what: String, seconds: Double = 60, _ found: () async throws -> T?) async throws -> T {
        let end = Date().addingTimeInterval(seconds)
        var last = ""
        while Date() < end {
            do {
                if let got = try await found() { return got }
            } catch {
                last = "\(error)"
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTFail("Waited \(Int(seconds)) seconds for \(what). \(last)")
        throw XCTSkip("gave up")
    }

    /// The Apple TV's own sign-in, as the server lists it.
    private func tvSession() async throws -> [String: Any]? {
        try await list("/api/v1/sessions").first { ($0["current"] as? Bool) != true && ($0["device"] as? String) != "check" }
    }

    private func tvDevice() async throws -> [String: Any]? {
        try await list("/api/v1/p2p/devices").first { ($0["platform"] as? String) == Self.platform }
    }

    private func picture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: The two runs

    func testHome() async throws {
        let home = try given("CHECK_HOME")
        app.launchArguments = ["-WittyCheckServer", home]
        app.launch()

        // The TV shows a code; someone signed in approves it.
        let shown = app.staticTexts["pairCode"]
        XCTAssertTrue(shown.waitForExistence(timeout: 60), "the code to approve never showed")
        // The code without its dash; a server that pairs securely also wants the PIN shown now.
        let code = shown.label.filter { $0.isLetter || $0.isNumber }
        picture("home-code")
        let me = try await ask("GET", "/api/v1/status").1 as? [String: Any]
        let owner = try XCTUnwrap((me?["user"] as? [String: Any])?["id"] as? Int, "the check's own sign-in isn't one")
        var approval: [String: Any] = ["code": code, "userId": owner, "password": try given("CHECK_PASSWORD")]
        let pin = app.staticTexts["pairPin"]
        if pin.exists { approval["pin"] = pin.label.filter(\.isNumber) } // read last: it changes every 30 s
        let approved = try await ask("POST", "/api/v1/pair/approve", body: approval)
        XCTAssertEqual(approved.0, 200, "the server didn't take the approval: \(String(describing: approved.1))")

        // Signed in at home, the app puts this device on the server's list by itself.
        let device = try await until("this Apple TV on the server's list for connections from away") { try await self.tvDevice() }
        XCTAssertEqual(device["how"] as? String, "signed-in")
        let session = try await until("the Apple TV's sign-in") { try await self.tvSession() }
        XCTAssertNotEqual(session["where"] as? String, "internet", "at home it counts as at home")
        // Long enough for what it learnt to be written down.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        picture("home-signed-in")
        app.terminate()
    }

    func testAway() async throws {
        let home = try given("CHECK_HOME")
        let item = try given("CHECK_ITEM")
        // The test needs the home address to be gone, and the server itself to be there.
        var gone = false
        do {
            _ = try await URLSession.shared.data(for: URLRequest(url: try XCTUnwrap(URL(string: home + "/api/status")), timeoutInterval: 3))
        } catch {
            gone = true
        }
        XCTAssertTrue(gone, "\(home) still answers")
        let found = try await tvSession()
        let before = try XCTUnwrap(found, "run testHome first: nobody is signed in on the Apple TV")
        let signIn = try XCTUnwrap(before["id"] as? String)

        app.launchArguments = ["-WittyCheckPlay", item]
        app.launch()

        // The same sign-in, now counted as from the internet and peer to peer.
        let away = try await until("the Apple TV reaching the server peer to peer", seconds: 90) { () -> [String: Any]? in
            guard let now = try await self.tvSession(), (now["via"] as? String)?.hasPrefix("p2p") == true else { return nil }
            return now
        }
        XCTAssertEqual(away["id"] as? String, signIn, "it is still the sign-in made at home")
        XCTAssertEqual(away["where"] as? String, "internet", "a peer-to-peer connection is never counted as at home")
        let address = away["ip"] as? String ?? ""
        XCTAssertFalse(address.hasPrefix("127.") || address.hasPrefix("10.") || address.hasPrefix("192.168.") || address == "::1",
                       "and never under an address of this machine or network: \(address)")
        let device = try await until("the device shown as connected") { () -> [String: Any]? in
            guard let now = try await self.tvDevice(), now["connected"] as? Bool == true else { return nil }
            return now
        }
        print("AwayCheck: the server sees \(address), \(away["where"] ?? ""), \(away["via"] ?? ""); the device is \(device["path"] ?? "")")

        // The film really plays: its place moves on, as the app reports it.
        let first = try await until("the film's place being reported", seconds: 60) { try await self.place(item) }
        let later = try await until("the film playing on", seconds: 60) { () -> Double? in
            guard let now = try await self.place(item), now >= first + 4 else { return nil }
            return now
        }
        print("AwayCheck: played from \(first) to \(later) seconds through the connection")
        picture("away-playing")

        // Off the screen the connection is ended; back on it starts again and the film carries on.
        XCUIDevice.shared.press(.home)
        #if os(tvOS)
        _ = try await until("the connection ending when the app leaves the screen", seconds: 30) { () -> Bool? in
            (try await self.tvDevice())?["connected"] as? Bool == true ? nil : true
        }
        #endif
        try await Task.sleep(nanoseconds: 5_000_000_000)
        app.activate()
        _ = try await until("the connection coming back with the app", seconds: 60) { () -> Bool? in
            (try await self.tvDevice())?["connected"] as? Bool == true ? true : nil
        }
        #if os(tvOS)
        let afterWaking = try await place(item) ?? first
        let onward = try await until("the film carrying on after coming back", seconds: 90) { () -> Double? in
            guard let now = try await self.place(item), now >= afterWaking + 4 else { return nil }
            return now
        }
        print("AwayCheck: after leaving the screen and coming back, played on to \(onward) seconds")
        #else
        // A phone pauses a film when the app leaves the screen, and leaves it paused. What can be seen
        // is the app asking the server things again, over the same sign-in.
        let lastSeen = away["lastSeen"] as? Int ?? 0
        let again = try await until("the app asking the server again after coming back", seconds: 90) { () -> Int? in
            guard let now = try await self.tvSession(), let seen = now["lastSeen"] as? Int, seen > lastSeen,
                  (now["via"] as? String)?.hasPrefix("p2p") == true else { return nil }
            return seen
        }
        print("AwayCheck: after leaving the screen and coming back, the app was heard from again, peer to peer (\(again - lastSeen) seconds on)")
        #endif
        picture("away-after-waking")
        app.terminate()
    }

    /// An invite link made on the server, taken in where the address goes: the app finds the server
    /// by it, shows it the invite, and signs in with the code that comes back.
    func testInvite() async throws {
        let before = try await forgetDevices()
        let made = try await ask("POST", "/api/v1/p2p/invite", body: ["password": try given("CHECK_PASSWORD")]) // an administrator's invite takes the password again
        let link = try XCTUnwrap((made.1 as? [String: Any])?["link"] as? String, "the server made no invite: \(made)")
        app.launchArguments = ["-WittyCheckInvite", link]
        app.launch()
        let device = try await until("the device on the server's list, by invite", seconds: 120) { () -> [String: Any]? in
            try await self.list("/api/v1/p2p/devices").first { ($0["platform"] as? String) == Self.platform && ($0["how"] as? String) == "invite" }
        }
        let session = try await until("the device signed in over the connection", seconds: 120) { try await self.newSession(since: before) }
        XCTAssertEqual(session["where"] as? String, "internet")
        print("AwayCheck: joined by an invite link; the device is \(device["path"] ?? device["lastPath"] ?? ""), the sign-in \(session["via"] ?? "")")
        picture("invite-signed-in")
        app.terminate()
    }

    /// Whatever the runs before left on the server is taken off its list, and its sign-ins noted, so
    /// that what is found afterwards can only have come from what the run itself did.
    private func forgetDevices() async throws -> Set<String> {
        for old in try await list("/api/v1/p2p/devices") {
            if let id = old["id"] as? String { _ = try await ask("DELETE", "/api/v1/p2p/devices/\(id)") }
        }
        return Set(try await list("/api/v1/sessions").compactMap { $0["id"] as? String })
    }

    private func newSession(since before: Set<String>) async throws -> [String: Any]? {
        try await list("/api/v1/sessions").first { now in
            guard let id = now["id"] as? String else { return false }
            return !before.contains(id) && (now["via"] as? String)?.hasPrefix("p2p") == true
        }
    }

    /// A TV that has never met its server: it shows a code, the code is typed into the server, and
    /// the two find each other through the public address book. Only run when the script is asked
    /// to use the public network (P2P_CHECK_PUBLIC=1), since nothing else can find a server by a code.
    func testJoinFromAway() async throws {
        guard ProcessInfo.processInfo.environment["CHECK_PUBLIC"] == "1" else {
            throw XCTSkip("joining by a code needs the public address book: run the script with P2P_CHECK_PUBLIC=1")
        }
        let before = try await forgetDevices()
        app.launchArguments = ["-WittyCheckJoin", "1"]
        app.launch()
        let shown = app.staticTexts["joinCode"]
        XCTAssertTrue(shown.waitForExistence(timeout: 60), "the code to type in never showed")
        let code = shown.label.replacingOccurrences(of: " ", with: "")
        picture("join-code")
        let took = try await ask("POST", "/api/v1/p2p/join", body: ["code": code, "password": try given("CHECK_PASSWORD")])
        XCTAssertEqual(took.0, 200, "the server didn't take the code: \(String(describing: took.1))")
        // The server tells the address book, the TV asks it, and they meet: a minute or two on the public network.
        let device = try await until("the Apple TV on the server's list, having found it by the code", seconds: 300) { () -> [String: Any]? in
            try await self.list("/api/v1/p2p/devices").first { ($0["platform"] as? String) == Self.platform && ($0["how"] as? String) == "invite" }
        }
        let session = try await until("the Apple TV signed in over the connection", seconds: 120) { try await self.newSession(since: before) }
        XCTAssertEqual(session["where"] as? String, "internet")
        print("AwayCheck: joined by the code \(code.prefix(2))…; the device is \(device["path"] ?? device["lastPath"] ?? ""), the sign-in \(session["via"] ?? "")")
        picture("join-signed-in")
        app.terminate()
    }

    /// You, From away, as it looks from away. Run after testAway with the server up; the remote is
    /// worked as a person would, so it isn't one of the script's steps: a changed menu would fail it.
    #if os(tvOS)
    func testLooksAtFromAway() async throws {
        guard ProcessInfo.processInfo.environment["CHECK_LOOK"] == "1" else { throw XCTSkip("only when asked: CHECK_LOOK=1") }
        app.launch()
        let remote = XCUIRemote.shared
        // The top menu's own name for whoever is signed in; the check's account is "owner".
        let you = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'owner'")).firstMatch
        XCTAssertTrue(you.waitForExistence(timeout: 60), "nobody is signed in")
        remote.press(.up)
        for _ in 0..<8 where !you.hasFocus { remote.press(.right) }
        remote.press(.select)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        picture("you")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'From away'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "You has no From away row")
        for _ in 0..<30 where !row.hasFocus { remote.press(.down) }
        picture("you-from-away-row")
        XCTAssertTrue(row.label.contains("Peer to peer"), "the row doesn't say how the server is reached: \(row.label)")
        remote.press(.select)
        let stop = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Stop connecting from away'")).firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 20), "From away didn't open")
        picture("from-away")
    }
    #endif

    /// Where the owner has got to in the film, in seconds, as the server keeps it.
    private func place(_ item: String) async throws -> Double? {
        guard let found = try await ask("GET", "/api/v1/items/\(item)").1 as? [String: Any] else { return nil }
        for key in ["positionSec", "progressSec", "position"] {
            if let seconds = found[key] as? Double, seconds > 0 { return seconds }
        }
        if let progress = found["progress"] as? [String: Any], let seconds = progress["positionSec"] as? Double, seconds > 0 { return seconds }
        return nil
    }
}
