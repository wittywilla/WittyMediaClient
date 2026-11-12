// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class AppearanceLookTests: XCTestCase {
    private let catalogue = ExperienceCatalogue(experiences: [
        .init(id: "lumen", name: "Lumen", tagline: "Quiet cinema", theme: "default", order: 1),
        .init(id: "rail", name: "Rail", tagline: "Library first", theme: "cinema", order: 2),
        .init(id: "aero", name: "Aero", tagline: "Glossy glass", theme: "aeroDay", order: 4),
    ])
    private let themes: [AppearancePage.ThemeChoice] = [
        .init(id: "default", name: "Witty", swatches: ["#0f1115", "#1f232c", "#7955ff"]),
        .init(id: "cinema", name: "Cinema", swatches: ["#000", "#111", "#e0a030"]),
        .init(id: "aeroDay", name: "Aero Day", dark: false, swatches: ["#cde", "#fff", "#38f"]),
        .init(id: "sunrise", name: "Sunrise", swatches: ["#ffe2b8", "#ffb36b", "#ff6a3d"], imported: true),
    ]

    private func inputs(state: ExperienceState? = nil, look: LookState = LookState(experience: "lumen", theme: "default"),
                        pick: Bool = true) -> AppearancePage.Inputs {
        .init(catalogue: catalogue, state: state, look: look, themes: themes, canPickFile: pick, profile: "Willow")
    }

    func testPageHasLookThemeImportAndTheTwoActions() {
        let page = AppearancePage.settings(inputs())
        XCTAssertEqual(page.title, "Look and theme")
        XCTAssertEqual(page.sections[0].heading, "Look")
        XCTAssertEqual(page.sections[0].cards.map(\.id), ["look-lumen", "look-rail", "look-aero"])
        XCTAssertEqual(page.sections[0].cards[1].subtitle, "Library first · Cinema")
        XCTAssertTrue(page.sections[0].cards[0].on)
        XCTAssertEqual(page.sections[1].cards.last?.id, "import-theme")
        XCTAssertEqual(page.sections[1].cards[3].subtitle, "Imported · yours")
        XCTAssertEqual(page.actions.map(\.id), ["use-on-this-device", "use-on-all-my-devices"])
    }

    func testNoImportCardWhereNoFileCanBePicked() {
        XCTAssertFalse(AppearancePage.settings(inputs(pick: false)).sections[1].cards.contains { $0.id == "import-theme" })
    }

    func testARequiredLookAndThemeAreShownLockedWithWhoRequiredThem() {
        let look = LookState(experience: "lumen", theme: "cinema",
                             requiredExperience: .init(value: "lumen", by: "Willow", scope: "profile"),
                             requiredTheme: .init(value: "cinema", by: "Willow", scope: "profile"))
        let page = AppearancePage.settings(inputs(look: look))
        XCTAssertEqual(page.sections[0].heading, "Look · Required by Willow")
        XCTAssertEqual(page.sections[0].cards.map(\.id), ["look-lumen"])
        XCTAssertEqual(page.sections[1].cards.map(\.id), ["theme-cinema"])
        XCTAssertEqual(page.foot, "Required by Willow")
        XCTAssertTrue(page.sections.contains { $0.kind == .note && $0.note.contains("Lumen look and the Cinema theme") })
    }

    func testRequiredLookWinsOverAPendingPick() {
        var i = inputs(look: LookState(experience: "rail", theme: "default", requiredExperience: .init(value: "rail", by: "Willow")))
        i.pendingExperience = "aero"
        XCTAssertEqual(i.shownExperience, "rail")
        XCTAssertFalse(i.lookEditable)
    }

    func testOnlyWhatTheProfileMayChooseIsOffered() {
        let state = ExperienceState(experience: "lumen", choice: .init(current: "lumen", options: [.init(value: "lumen", label: "Lumen"), .init(value: "aero", label: "Aero")]), editable: true)
        XCTAssertEqual(inputs(state: state).offered.map(\.id), ["lumen", "aero"])
    }

    func testChooserLocksWhenBothPartsAreRequired() {
        let look = LookState(experience: "lumen", theme: "cinema", requiredExperience: .init(value: "lumen", by: "Willow"),
                             requiredTheme: .init(value: "cinema", by: "Willow"))
        let page = AppearancePage.chooser(inputs(look: look))
        XCTAssertEqual(page.title, "Your look is set")
        XCTAssertEqual(page.eyebrow, "Welcome, Willow")
        XCTAssertEqual(page.sections[0].cards.map(\.id), ["look-lumen", "theme-cinema"])
        XCTAssertEqual(page.actions.map(\.title), ["Continue"])
        let open = AppearancePage.chooser(inputs())
        XCTAssertEqual(open.title, "Choose how it looks")
        XCTAssertEqual(open.actions.map(\.title), ["Use this"])
    }

    func testPickedCardIds() {
        XCTAssertEqual(AppearancePage.pick("look-aero").look, "aero")
        XCTAssertEqual(AppearancePage.pick("theme-cinema").theme, "cinema")
        XCTAssertNil(AppearancePage.pick("import-theme").look)
    }

    func testReadsTheServersAnswers() throws {
        let state = try JSONDecoder().decode(ExperienceState.self, from: Data(#"""
        {"experience":"rail","shell":{},"choice":{"current":"rail","options":[],"url":"/x","required":{"value":"rail","by":"Willow","scope":"profile"}},"editable":false}
        """#.utf8))
        XCTAssertEqual(state.choice?.required?.words, "Required by Willow")
        XCTAssertFalse(state.editable)
        let none = try JSONDecoder().decode(ExperienceState.self, from: Data(#"{"experience":"lumen","choice":null,"editable":false}"#.utf8))
        XCTAssertNil(none.choice)
        let look = try JSONDecoder().decode(LookState.self, from: Data(#"{"experience":"lumen","theme":"cinema","requiredTheme":{"value":"cinema","scope":"kids"},"profileThemes":true}"#.utf8))
        XCTAssertEqual(look.requiredTheme?.words, "Required by your administrator")
        XCTAssertTrue(look.profileThemes)
    }

    func testSetupRequiredAnswer() {
        let body = Data(#"{"error":"setup_required","message":"x","setupURL":"http://192.168.1.20:9797/setup"}"#.utf8)
        XCTAssertEqual(SetupRequired.from(status: 503, body: body)?.shown, "192.168.1.20:9797/setup")
        XCTAssertNil(SetupRequired.from(status: 500, body: body))
        XCTAssertNil(SetupRequired.from(status: 503, body: Data(#"{"error":"busy"}"#.utf8)))
    }

    func testPolicyKeepsWhatItDoesNotKnowAndSendsRequirements() throws {
        let json = Data(#"""
        {"default":{"tv":"bigpicture"},"allowed":["lumen"],"profileThemes":false,"required":{"everyone":{"theme":"cinema","by":"Willow","at":"2026-01-01T00:00:00Z"},"profiles":{"7":{"experience":"rail","by":"Willow"}}}}
        """#.utf8)
        var policy = LookPolicy(json: json)
        XCTAssertEqual(policy.everyone?.theme, "cinema")
        XCTAssertEqual(policy.profiles["7"]?.experience, "rail")
        policy.profileThemes = true
        policy.profiles["7"] = nil
        let sent = try JSONSerialization.jsonObject(with: policy.body()) as? [String: Any]
        XCTAssertEqual((sent?["default"] as? [String: String])?["tv"], "bigpicture")
        XCTAssertEqual(sent?["allowed"] as? [String], ["lumen"])
        XCTAssertEqual(sent?["profileThemes"] as? Bool, true)
        let required = sent?["required"] as? [String: Any]
        XCTAssertNil(required?["profiles"])
        XCTAssertEqual((required?["everyone"] as? [String: String]), ["theme": "cinema"])
        policy.everyone = nil
        XCTAssertNil((try JSONSerialization.jsonObject(with: policy.body()) as? [String: Any])?["required"])
    }
}
