// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// Xcode's accessibility audit on the main screens, in an app already signed in on this simulator (the test signs in
/// to nothing). Run with `TEST_RUNNER_WMC_AUDIT=1`, and the places to open: `TEST_RUNNER_WMC_LIBRARY` (a films or shows
/// library), `TEST_RUNNER_WMC_ITEM` (a title), `TEST_RUNNER_WMC_GAMES` (a games library). Every issue found is printed
/// as `AUDIT <screen> | <kind> | <element> | <description>`, and the test fails if there were any.
final class AccessibilityAuditTests: XCTestCase {
    private var found: [String] = []

    @MainActor
    func testMainScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["WMC_AUDIT"] == "1" else { throw XCTSkip("Set TEST_RUNNER_WMC_AUDIT=1, in an app already signed in.") }
        guard #available(iOS 17.0, tvOS 17.0, *) else { throw XCTSkip("The audit needs iOS or tvOS 17.") }
        let app = launchWithCode()
        audit("home", app)

        var routes: [(String, String)] = [("manage-libraries", "/manage/libraries"),
                                          ("wittyplay", "/page/wittyplay-online"),
                                          ("together", "/page/wittyplay-online?tab=together"),
                                          ("wittyplay-settings", "/page/wittyplay-settings")]
        if let library = env["WMC_LIBRARY"] {
            routes += [("library", "/library/\(library)"), ("manage-library", "/manage/library/\(library)")]
        }
        if let item = env["WMC_ITEM"] { routes.append(("title", "/item/\(item)")) }
        if let games = env["WMC_GAMES"] { routes.append(("games-library", "/wittyplay/library/\(games)")) }
        for (name, route) in routes {
            open(route, in: app)
            audit(name, app)
        }

        // You: this app's Settings.
        open("/", in: app)
        #if os(tvOS)
        // The top bar shows when focus goes up to it.
        for _ in 0..<5 { XCUIRemote.shared.press(.up); Thread.sleep(forTimeInterval: 0.5) }
        #endif
        // The You tab: "You" on a phone or tablet, the profile's pill (read as "You") in a television's top bar.
        let you = app.buttons.matching(NSPredicate(format: "label ==[c] 'You'")).firstMatch
        if you.waitForExistence(timeout: 10) {
            choose(you, in: app)
            Thread.sleep(forTimeInterval: 4)
            audit("you", app)
        } else {
            found.append("AUDIT you | navigation | You | the You tab was not found")
        }

        for line in found { print(line) }
        XCTAssertTrue(found.isEmpty, "\(found.count) accessibility issues:\n" + found.joined(separator: "\n"))
    }

    @available(iOS 17.0, tvOS 17.0, *)
    @MainActor
    private func open(_ route: String, in app: XCUIApplication) {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let url = URL(string: "wittymedia://route/" + (route.addingPercentEncoding(withAllowedCharacters: safe) ?? "")) else { return }
        // The system opens it in the app as it runs: XCUIApplication.open relaunches it, which signs a
        // simulator build out.
        XCUIDevice.shared.system.open(url)
        Thread.sleep(forTimeInterval: 6)
    }

    @available(iOS 17.0, tvOS 17.0, *)
    @MainActor
    private func audit(_ screen: String, _ app: XCUIApplication) {
        snap("audit-" + screen)
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)'" } ?? "-"
                self.found.append("AUDIT \(screen) | \(issue.auditType) | \(element) | \(issue.compactDescription): \(issue.detailedDescription)")
                return true
            }
        } catch {
            found.append("AUDIT \(screen) | error | - | \(error)")
        }
    }
}
