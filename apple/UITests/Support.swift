// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The UI tests drive the app against a real WittyMediaServer on this machine, which whoever runs them
/// starts first. They're told where it is through the environment, as xcodebuild passes it on:
///
///   TEST_RUNNER_WMC_SERVER=http://localhost:9000 TEST_RUNNER_WMC_USER=name TEST_RUNNER_WMC_PASSWORD=word \
///     xcodebuild test -project WittyMedia.xcodeproj -scheme WittyMedia-iOS -destination 'platform=iOS Simulator,name=iPhone 17'
///
/// With no server named every test skips itself, so a plain `xcodebuild test` still passes.
enum TestServer {
    static var address: String? { ProcessInfo.processInfo.environment["WMC_SERVER"] }
    static var user: String { ProcessInfo.processInfo.environment["WMC_USER"] ?? "" }
    static var password: String { ProcessInfo.processInfo.environment["WMC_PASSWORD"] ?? "" }

    /// Another account on the same server, by the names the environment gives: `WMC_USER_KIDS`, `WMC_PASSWORD_KIDS`.
    static func account(_ which: String) -> (user: String, password: String)? {
        let env = ProcessInfo.processInfo.environment
        guard let user = env["WMC_USER_\(which.uppercased())"] else { return nil }
        return (user, env["WMC_PASSWORD_\(which.uppercased())"] ?? "")
    }
}

extension XCTestCase {
    /// The app, started signed in to the test server (the debug build's `-WMCServer`, see AppModel.startForTests).
    /// `signedIn: false` stops at the sign-in screen. `extra` are more launch arguments.
    @MainActor
    func launchApp(signedIn: Bool = true, user: String? = nil, password: String? = nil, extra: [String] = []) throws -> XCUIApplication {
        guard let address = TestServer.address else { throw XCTSkip("No test server: set TEST_RUNNER_WMC_SERVER.") }
        let app = XCUIApplication()
        app.launchArguments = ["-WMCServer", address]
        if signedIn {
            app.launchArguments += ["-WMCUser", user ?? TestServer.user, "-WMCPassword", password ?? TestServer.password]
        }
        app.launchArguments += extra
        app.launch()
        return app
    }
}

extension XCUIElement {
    /// Waits for it, and fails the test in words when it never shows.
    @discardableResult
    func shown(_ seconds: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: seconds), "\(self) never showed", file: file, line: line)
        return self
    }
}
