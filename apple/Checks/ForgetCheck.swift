// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// Removing servers a device remembers, in a simulator, against two real WittyMediaServers.
/// `apple/scripts/forget-check.sh` starts the servers and runs these in order, looking at what the app
/// keeps on disk in between:
///
///   testSignInToBoth      a code approved on each server in turn: both are then under "Used before",
///                         and the device is signed in to the second
///   testRemoveTheOther    Manage servers, from You: the first server is removed (and put back with
///                         Undo, then removed again, on an iPhone); the second is still signed in
///   testRemoveTheOneInUse the server in use is removed: the app asks, signs out, tells the server,
///                         and is back at the list of servers
///   testRemoveFromTheList the list of servers: a swipe and Undo, Edit, the card's menu and Manage
///                         servers' "Remove all" on an iPhone; the card's menu, where focus goes, and
///                         Manage servers on an Apple TV
///   testAnOldList         a list from an older version, with one server in it twice: it shows once;
///                         and "Remove servers not reached for…" names what it will remove, then does
///   testAChangedServer    the first server's address is remembered with another key, as after a
///                         reinstall: the warning explains, and "Remove the old server" forgets it
///
/// What the script hands over, as TEST_RUNNER_ variables: CHECK_A and CHECK_B (the two servers'
/// addresses) and CHECK_USER and CHECK_PASSWORD (an account on both).
@MainActor
final class ForgetCheck: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.wittywilla.wittymediaclient")

    private func given(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("\(name) isn't set: run apple/scripts/forget-check.sh, which sets it")
        }
        return value
    }

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Asking a server

    private func ask(_ base: String, _ method: String, _ path: String, token: String = "", body: [String: Any]? = nil) async throws -> (Int, Any?) {
        var request = URLRequest(url: try XCTUnwrap(URL(string: base + path)), timeoutInterval: 10)
        request.httpMethod = method
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, try? JSONSerialization.jsonObject(with: data))
    }

    /// The check's own sign-in to a server, and whose it is.
    private func signIn(_ base: String) async throws -> (token: String, user: Int) {
        let answer = try await ask(base, "POST", "/api/v1/login", body: ["name": try given("CHECK_USER"), "password": try given("CHECK_PASSWORD"), "device": "check"])
        let fields = answer.1 as? [String: Any]
        let token = try XCTUnwrap(fields?["token"] as? String, "the check couldn't sign in to \(base): \(answer.0)")
        return (token, try XCTUnwrap((fields?["user"] as? [String: Any])?["id"] as? Int))
    }

    /// The app's own sign-ins on a server, by their ids: everything but the check's.
    private func appSignIns(_ base: String, token: String) async throws -> Set<String> {
        let all = (try await ask(base, "GET", "/api/v1/sessions", token: token).1 as? [[String: Any]]) ?? []
        return Set(all.filter { ($0["device"] as? String) != "check" }.compactMap { $0["id"] as? String })
    }

    private func until<T>(_ what: String, seconds: Double = 40, _ found: () async throws -> T?) async throws -> T {
        let end = Date().addingTimeInterval(seconds)
        var last = ""
        while Date() < end {
            do {
                if let got = try await found() { return got }
            } catch {
                last = "\(error)"
            }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        picture("gave-up")
        XCTFail("Waited \(Int(seconds)) seconds for \(what). \(last)")
        throw XCTSkip("gave up")
    }

    private func picture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: Finding and pressing

    /// A remembered server's card in the list of servers: its label has its address in full.
    private func card(_ address: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND NOT (label BEGINSWITH %@)", address, "Remove")).firstMatch
    }

    /// A server's row in Manage servers.
    private func row(_ address: String) -> XCUIElement { app.buttons["server." + address] }

    /// Whatever can be pressed and has these words: a button, or a line of a menu.
    private func labelled(_ words: String) -> [XCUIElement] {
        let named = NSPredicate(format: "label == %@", words)
        let buttons = app.buttons.matching(named).allElementsBoundByIndex
        return buttons.isEmpty ? app.descendants(matching: .any).matching(named).allElementsBoundByIndex : buttons
    }

    #if os(tvOS)
    /// The remote's focus is on something that can be pressed.
    private func focusIsSomewhere() -> Bool {
        app.buttons.allElementsBoundByIndex.contains { $0.hasFocus }
    }
    #endif

    #if os(tvOS)
    /// Moves the remote's focus until it is on the thing: down and then up a page, or across a question.
    private func focus(_ what: String, across: Bool = false, _ on: () -> Bool) async throws {
        for direction in across ? [XCUIRemote.Button.right, .left, .down, .up] : [XCUIRemote.Button.down, .up] {
            for _ in 0..<(across ? 3 : 30) {
                if on() { return }
                XCUIRemote.shared.press(direction)
                try await pause(0.35)
            }
        }
        if on() { return }
        picture("no-focus")
        XCTFail("The remote's focus never reached \(what)")
        throw XCTSkip("gave up")
    }

    private func focus(_ element: XCUIElement, _ what: String) async throws {
        XCTAssertTrue(element.waitForExistence(timeout: 20), "\(what) isn't on the screen")
        try await focus(what) { element.hasFocus }
    }
    #endif

    #if !os(tvOS)
    /// Scrolls until the thing can be touched: a network with many servers on it makes a long list.
    private func reveal(_ element: XCUIElement, _ what: String) async throws {
        XCTAssertTrue(element.waitForExistence(timeout: 20), "\(what) isn't on the screen")
        let window = app.windows.firstMatch
        for _ in 0..<16 where !element.isHittable || element.frame.maxY > window.frame.maxY - 120 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            try await pause(0.4)
        }
    }
    #endif

    /// Presses a button: a tap, or the remote's focus moved to it and Select.
    private func press(_ element: XCUIElement, _ what: String) async throws {
        #if os(tvOS)
        try await focus(element, what)
        XCUIRemote.shared.press(.select)
        #else
        try await reveal(element, what)
        element.tap()
        #endif
        try await pause(0.6)
    }

    /// Answers a question the app asked, with the button that has these words. The page under the
    /// question can have a button of the same words: the question's is the one that can be pressed.
    /// `only` for a menu of one line, which has the remote's focus as it opens.
    private func answer(_ words: String, only: Bool = false) async throws {
        _ = try await until("the question's \"\(words)\"", seconds: 15) { self.labelled(words).isEmpty ? nil : true }
        try await pause(0.8)
        #if os(tvOS)
        if !only { try await focus("\"\(words)\" in the question", across: true) { self.labelled(words).contains { $0.hasFocus } } }
        XCUIRemote.shared.press(.select)
        #else
        let found = labelled(words)
        try XCTUnwrap(found.last { $0.isHittable } ?? found.last).tap()
        #endif
        try await pause(1)
    }

    // MARK: Signing in

    /// The app, started at the list of servers and told a server: it shows a code, which is approved
    /// as from a phone. Returns once the server has the app's sign-in.
    private func signInApp(to base: String) async throws {
        let me = try await signIn(base)
        let before = try await appSignIns(base, token: me.token)
        app.launchArguments = ["-WittyCheckPicker", "1", "-WittyCheckServer", base]
        app.launch()
        let shown = app.staticTexts["pairCode"]
        XCTAssertTrue(shown.waitForExistence(timeout: 60), "the code to approve never showed for \(base)")
        let code = shown.label.filter { $0.isLetter || $0.isNumber }
        let approved = try await ask(base, "POST", "/api/v1/pair/approve", token: me.token, body: ["code": code, "userId": me.user, "password": try given("CHECK_PASSWORD")])
        XCTAssertEqual(approved.0, 200, "the server didn't take the approval: \(String(describing: approved.1))")
        _ = try await until("the app's sign-in on \(base)") { try await self.appSignIns(base, token: me.token).subtracting(before).first }
        // Long enough for what it learnt to be written down.
        try await pause(4)
        app.terminate()
    }

    private func signInToBoth() async throws {
        try await signInApp(to: try given("CHECK_A"))
        try await signInApp(to: try given("CHECK_B"))
    }

    // MARK: The runs

    func testSignInToBoth() async throws {
        try await signInToBoth()
        // Started plainly, it is still signed in to the second, and Manage servers lists both.
        app.launchArguments = ["-WittyCheckServers", "1"]
        app.launch()
        let a = try given("CHECK_A"), b = try given("CHECK_B")
        XCTAssertTrue(row(b).waitForExistence(timeout: 60), "the server in use isn't in Manage servers")
        XCTAssertTrue(row(a).exists, "the server used before isn't in Manage servers")
        XCTAssertTrue(row(b).label.contains("This server"), "the server in use isn't marked: \(row(b).label)")
        XCTAssertTrue(row(a).label.contains("Reached today"), "no last time: \(row(a).label)")
        picture("both")
        app.terminate()
        #if !os(tvOS)
        // And by hand: You, then "Servers on this device" under "On this device".
        app.launchArguments = []
        app.launch()
        try await press(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "You")).firstMatch, "the You tab")
        try await press(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Servers on this device")).firstMatch, "You's row for servers")
        XCTAssertTrue(row(a).waitForExistence(timeout: 20), "You's row didn't open Manage servers")
        picture("from-you")
        app.terminate()
        #endif
    }

    func testRemoveTheOther() async throws {
        let a = try given("CHECK_A"), b = try given("CHECK_B")
        let me = try await signIn(b)
        let before = try await appSignIns(b, token: me.token)
        XCTAssertFalse(before.isEmpty, "run testSignInToBoth first: the app isn't signed in to \(b)")
        app.launchArguments = ["-WittyCheckServers", "1"]
        app.launch()
        XCTAssertTrue(row(a).waitForExistence(timeout: 60), "Manage servers never showed \(a)")
        #if os(tvOS)
        try await press(row(a), "the row of \(a)")
        picture("asked")
        try await answer("Remove")
        _ = try await until("\(a) leaving the list") { self.row(a).exists ? nil : true }
        try await pause(1)
        XCTAssertTrue(row(b).hasFocus, "focus didn't go to the row that is left")
        #else
        // Not the server in use: it goes at once, and can be put back.
        try await press(row(a), "the row of \(a)")
        _ = try await until("\(a) leaving the list") { self.row(a).exists ? nil : true }
        let undo = app.buttons["undoRemove"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo was offered")
        picture("undo")
        undo.tap()
        _ = try await until("\(a) coming back with Undo") { self.row(a).exists ? true : nil }
        try await press(row(a), "the row of \(a)")
        _ = try await until("the time to undo running out", seconds: 15) { undo.exists ? nil : true }
        XCTAssertFalse(row(a).exists, "\(a) is still listed")
        #endif
        XCTAssertTrue(row(b).exists, "the other server went too")
        // Still signed in to the other, there and here.
        try await pause(2)
        let after = try await appSignIns(b, token: me.token)
        XCTAssertEqual(after, before, "the sign-in to the server that stayed was touched")
        picture("other-removed")
        app.terminate()
        app.launchArguments = ["-WittyCheckServers", "1"]
        app.launch()
        XCTAssertTrue(row(b).waitForExistence(timeout: 60), "after starting again, the app isn't signed in to \(b)")
        XCTAssertFalse(row(a).exists, "after starting again, \(a) is back")
        app.terminate()
    }

    func testRemoveTheOneInUse() async throws {
        let b = try given("CHECK_B")
        let me = try await signIn(b)
        let before = try await appSignIns(b, token: me.token)
        XCTAssertFalse(before.isEmpty, "run testSignInToBoth first: the app isn't signed in to \(b)")
        app.launchArguments = ["-WittyCheckServers", "1"]
        app.launch()
        try await press(row(b), "the row of \(b)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "You're using this server now")).firstMatch.waitForExistence(timeout: 10),
                      "the question doesn't say that this is the server in use")
        picture("in-use-asked")
        try await answer("Remove")
        // Back at the list of servers, with nothing remembered, and the server told.
        let enter = app.buttons["Enter an address"]
        XCTAssertTrue(enter.waitForExistence(timeout: 20), "the app didn't go back to the list of servers")
        #if os(tvOS)
        // Coming from a server's own screens, as after Change server, Apple TV may show no focus until the
        // remote is next pressed. That press must find something.
        try await pause(2)
        if !focusIsSomewhere() {
            XCUIRemote.shared.press(.down)
            try await pause(1)
        }
        XCTAssertTrue(focusIsSomewhere(), "the remote finds nothing to focus on the list of servers")
        #endif
        XCTAssertFalse(card(b).exists, "\(b) is still under Used before")
        XCTAssertFalse(app.buttons["Manage servers"].exists, "Manage servers is offered with nothing to manage")
        _ = try await until("the server ending the app's sign-in") { try await self.appSignIns(b, token: me.token).isDisjoint(with: before) ? true : nil }
        picture("in-use-removed")
        try await pause(3)
        app.terminate()
    }

    func testRemoveFromTheList() async throws {
        let a = try given("CHECK_A"), b = try given("CHECK_B")
        try await signInToBoth()
        app.launchArguments = ["-WittyCheckPicker", "1"]
        app.launch()
        XCTAssertTrue(card(a).waitForExistence(timeout: 60), "\(a) isn't under Used before")
        XCTAssertTrue(card(b).exists, "\(b) isn't under Used before")
        XCTAssertTrue(card(a).label.contains("Reached today"), "no last time on the card: \(card(a).label)")
        picture("list")
        #if os(tvOS)
        // The card's menu, which asks first; then focus goes to the card that is left.
        try await focus(card(a), "the card of \(a)")
        XCUIRemote.shared.press(.select, forDuration: 1.5)
        try await answer("Remove this server", only: true)
        picture("list-asked")
        try await answer("Remove")
        _ = try await until("\(a) leaving the list") { self.card(a).exists ? nil : true }
        try await pause(1.5)
        XCTAssertTrue(card(b).hasFocus, "focus didn't go to the card that is left")
        // Manage servers, which needs no gesture to find.
        try await press(app.buttons["Manage servers"], "Manage servers")
        XCTAssertTrue(row(b).waitForExistence(timeout: 10), "Manage servers doesn't list \(b)")
        try await press(app.buttons["Remove all servers"], "Remove all servers")
        picture("all-asked")
        try await answer("Remove all servers")
        let enter = app.buttons["Enter an address"]
        XCTAssertTrue(enter.waitForExistence(timeout: 10), "the app didn't go back to the list of servers")
        try await pause(1.5)
        XCTAssertTrue(enter.hasFocus, "with nothing left, focus isn't on Enter an address")
        XCTAssertFalse(app.buttons["Manage servers"].exists, "Manage servers is offered with nothing to manage")
        XCTAssertFalse(card(b).exists, "\(b) is still listed")
        #else
        let undo = app.buttons["undoRemove"]
        // A swipe removes at once, and Undo puts the card back where it was.
        try await reveal(card(a), "the card of \(a)")
        picture("list-used-before")
        card(a).swipeLeft(velocity: .fast)
        _ = try await until("\(a) leaving with a swipe") { self.card(a).exists ? nil : true }
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo was offered")
        picture("swiped")
        undo.tap()
        _ = try await until("\(a) coming back with Undo") { self.card(a).exists ? true : nil }
        XCTAssertGreaterThan(card(a).frame.minY, card(b).frame.minY, "it came back in another place")
        // Edit shows a button on each card.
        try await press(app.buttons["editServers"], "Edit")
        picture("editing")
        try await press(app.buttons["remove." + a], "Remove on the card of \(a)")
        _ = try await until("\(a) leaving with Edit") { self.card(a).exists ? nil : true }
        try await press(app.buttons["editServers"], "Done")
        _ = try await until("the time to undo running out", seconds: 15) { undo.exists ? nil : true }
        // The card's menu, by a long press, and Undo again.
        try await reveal(card(b), "the card of \(b)")
        card(b).press(forDuration: 1.2)
        try await pause(0.5)
        picture("menu")
        try await answer("Remove this server", only: true)
        _ = try await until("\(b) leaving by its menu") { self.card(b).exists ? nil : true }
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo was offered")
        undo.tap()
        _ = try await until("\(b) coming back with Undo") { self.card(b).exists ? true : nil }
        // Manage servers, and all of them at once.
        try await press(app.buttons["Manage servers"], "Manage servers")
        XCTAssertTrue(row(b).waitForExistence(timeout: 10), "Manage servers doesn't list \(b)")
        XCTAssertFalse(row(a).exists, "\(a) is listed in Manage servers after it was removed")
        try await press(app.buttons["Remove all servers"], "Remove all servers")
        picture("all-asked")
        try await answer("Remove all servers")
        XCTAssertTrue(app.staticTexts["This device remembers no servers."].waitForExistence(timeout: 10), "the empty list doesn't say so")
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Enter an address"].waitForExistence(timeout: 10), "the app didn't go back to the list of servers")
        XCTAssertFalse(card(b).exists, "\(b) is still listed")
        XCTAssertFalse(app.buttons["Manage servers"].exists, "Manage servers is offered with nothing to manage")
        #endif
        picture("list-empty")
        // Long enough for what was removed to be written down, and for the servers to be told.
        try await pause(5)
        app.terminate()
    }

    /// The script has written a list as an older version kept it: no times, and one server in it
    /// twice, by two addresses. It shows once, at the newer address, and the others are as they were.
    func testAnOldList() async throws {
        app.launchArguments = ["-WittyCheckPicker", "1"]
        app.launch()
        XCTAssertTrue(card("http://10.255.0.2:9797").waitForExistence(timeout: 60), "the server isn't listed at its newer address")
        XCTAssertFalse(card("http://10.255.0.1:9797").exists, "the server is still listed at its older address as well")
        XCTAssertTrue(card("http://10.255.0.9:9797").exists, "another server went missing")
        XCTAssertTrue(card("http://10.255.0.2:9797").label.contains("Not reached since this app was updated"), "a time was made up: \(card("http://10.255.0.2:9797").label)")
        XCTAssertTrue(card("http://10.255.0.9:9797").label.contains("Not reached lately"), "a server last reached long ago isn't marked: \(card("http://10.255.0.9:9797").label)")
        picture("old-list")
        // Manage servers can remove the ones not reached for a while: it says which before it does, and
        // one whose last time isn't known is only counted from when this app began keeping times.
        let shed = "http://10.255.0.9:9797"
        try await press(app.buttons["Manage servers"], "Manage servers")
        try await press(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove servers not reached for")).firstMatch, "Remove servers not reached for")
        try await press(app.buttons["1 year"], "1 year")
        XCTAssertTrue(app.staticTexts["Every server here was reached more recently than that."].waitForExistence(timeout: 10), "a year caught something, or nothing was said")
        XCTAssertTrue(row(shed).exists, "a server went without being asked about")
        try await press(app.buttons["90 days"], "90 days")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Not reached for 90 days or more (1): Shed.")).firstMatch.waitForExistence(timeout: 10),
                      "the question doesn't name exactly the server that will go")
        picture("old-asked")
        try await answer("Remove")
        _ = try await until("the server not reached for 90 days leaving") { self.row(shed).exists ? nil : true }
        XCTAssertTrue(row("http://10.255.0.2:9797").exists, "a server whose last time isn't known went too")
        // Long enough for the list to be written down.
        try await pause(3)
        app.terminate()
    }

    /// The script has written a list with the first server's address in it under another key. Choosing
    /// it shows the warning, with the safe choice first; removing the old server leaves the address
    /// free to be added as new.
    func testAChangedServer() async throws {
        let a = try given("CHECK_A")
        app.launchArguments = ["-WittyCheckPicker", "1"]
        app.launch()
        XCTAssertTrue(card(a).waitForExistence(timeout: 60), "\(a) isn't under Used before")
        // A moment for the simulator's network, which a press in the first seconds can find not yet there.
        try await pause(4)
        try await press(card(a), "the card of \(a)")
        XCTAssertTrue(app.staticTexts["This isn't the server you used before"].waitForExistence(timeout: 30), "no warning about a server that changed")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "If your server was reinstalled")).firstMatch.exists, "the warning doesn't explain a reinstall")
        #if os(tvOS)
        try await pause(1)
        XCTAssertTrue(app.buttons["Back"].firstMatch.hasFocus, "the safe choice doesn't have focus")
        #endif
        picture("changed")
        try await press(app.buttons["Remove the old server"], "Remove the old server")
        XCTAssertTrue(app.buttons["Enter an address"].waitForExistence(timeout: 20), "the app didn't go back to the list of servers")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The old server was removed")).firstMatch.waitForExistence(timeout: 5)
                      || app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "The old server was removed")).count > 0,
                      "nothing says the old server was removed")
        XCTAssertFalse(card(a).exists, "the old server is still under Used before")
        picture("changed-removed")
        try await pause(3)
        app.terminate()
    }
}
