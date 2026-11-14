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
        XCTAssertEqual(page.sections[0].cards.map(\.id), ["preview"])
        XCTAssertEqual(page.actions.map(\.title), ["Continue"])
    }

    func testTheChooserIsALayoutPageThenAColourPage() {
        var i = inputs()
        i.form = "phone"
        XCTAssertEqual(AppearancePage.firstStep(i), .layout)
        let layout = AppearancePage.chooser(i, step: .layout)
        XCTAssertEqual(layout.title, "Choose a layout")
        XCTAssertEqual(layout.sections.flatMap(\.cards).map(\.id), ["look-lumen", "look-rail", "look-aero"])
        XCTAssertTrue(layout.sections[0].cards.allSatisfy(\.portrait), "a phone previews its own layout, upright")
        XCTAssertEqual(layout.actions.map(\.title), ["Next"])

        i.pendingExperience = "rail"
        let colour = AppearancePage.chooser(i, step: .colour)
        XCTAssertEqual(colour.title, "Choose colours")
        XCTAssertEqual(colour.sections[0].heading, "Preview")
        XCTAssertEqual(colour.sections[0].cards.map(\.id), ["preview"])
        // The chosen look wears its own theme until one is picked: Rail's is Cinema.
        XCTAssertTrue(colour.sections[1].cards.first { $0.id == "theme-cinema" }?.on == true)
        XCTAssertEqual(colour.sections[0].cards[0].swatches, AppearancePage.swatches(for: "cinema", in: i.themes))
        // Every colour card draws the chosen layout in its own colours.
        let wire = colour.sections[0].cards[0].wire
        XCTAssertTrue(colour.sections[1].cards.allSatisfy { $0.wire == wire && $0.portrait })
        XCTAssertEqual(colour.actions.map(\.title), ["Use this", "Back"])

        i.pendingTheme = "aeroDay"
        let picked = AppearancePage.chooser(i, step: .colour)
        XCTAssertEqual(picked.sections[0].cards[0].swatches, AppearancePage.swatches(for: "aeroDay", in: i.themes))
    }

    func testARequiredLookOpensOnColoursAndARequiredThemeFinishesFromTheLayout() {
        let lookSet = inputs(look: LookState(experience: "rail", theme: "cinema", requiredExperience: .init(value: "rail", by: "Willow")))
        XCTAssertEqual(AppearancePage.firstStep(lookSet), .colour)
        XCTAssertEqual(AppearancePage.chooser(lookSet, step: .colour).actions.map(\.title), ["Use this"], "no layout page to go back to")
        let themeSet = inputs(look: LookState(experience: "rail", theme: "cinema", requiredTheme: .init(value: "cinema", by: "Willow")))
        XCTAssertEqual(AppearancePage.chooser(themeSet, step: .layout).actions.map(\.title), ["Continue"])
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

final class TvProblemPageTests: XCTestCase {
    func testKindFromTheServersWordsAndTheChannel() {
        XCTAssertEqual(TvProblem.kind(why: "That channel can't be played.", security: nil), .wontPlay)
        XCTAssertEqual(TvProblem.kind(why: "x", security: "encrypted"), .encrypted)
        XCTAssertEqual(TvProblem.kind(why: "No tuner is free right now.", security: nil), .noTuner)
    }

    func testAlwaysAWayForward() {
        let page = TvProblem.spec(why: "The tuner lost the signal.", kind: .wontPlay, number: "4", name: "Kids Cove",
                                  alternative: .init(number: "104", name: "Kids Cove HD"), fromStart: nil)
        XCTAssertEqual(page.eyebrow, "WittyTV · Ch 4 Kids Cove")
        XCTAssertEqual(page.lead, "The tuner lost the signal.")
        XCTAssertEqual(page.actions.map(\.id), ["alternative", "try-again", "next-channel", "back-to-the-guide"])
        XCTAssertEqual(page.startFocus, "alternative")
        XCTAssertEqual(page.back, .closeLayer)
    }

    func testEncryptedOffersNoRetryAndNotesWhatToDo() {
        let page = TvProblem.spec(why: "Encrypted.", kind: .encrypted, number: "9", name: "Pay", alternative: nil, fromStart: nil)
        XCTAssertFalse(page.actions.contains { $0.id == "try-again" })
        XCTAssertEqual(page.sections.first?.heading, "What can I do?")
        XCTAssertEqual(page.actions.last?.id, "back-to-the-guide")
    }

    func testBackToLiveOnlyWhenWatchingFromTheStart() {
        let page = TvProblem.spec(why: "x", kind: .wontPlay, number: "", name: "News", alternative: nil, fromStart: "Show")
        XCTAssertTrue(page.actions.contains { $0.id == "back-to-live" })
    }
}

final class MoreInfoSpecTests: XCTestCase {
    private func info(credits: String = "") throws -> ProgrammeInfo {
        let json = """
        {"channel":{"key":"c4","number":4,"name":"Four","catchupDays":7},
         "programme":{"start":1000,"end":4600,"kind":"broadcast","title":"The Quiet Orchard","sub":"Low Tide","desc":"A village.","genres":["Drama"],"rating":"PG","year":2024,"advisory":"Mild peril","new":true},
         "actions":{"watch":true,"record":true,"remind":true,"fromStart":true,"open":true,"watchLater":true},
         "library":{"itemId":9},
         \(credits)
         "trailers":[{"itemId":12,"title":"Trailer","type":"trailer","durationSec":95}],
         "schedule":[{"channel":"c5","channelName":"Five","start":9000,"this":false},{"channel":"c4","channelName":"Four","start":1000,"this":true}]}
        """
        return try JSONDecoder().decode(ProgrammeInfo.self, from: Data(json.utf8))
    }

    func testCastWithoutAPersonIdIsNotOpenable() throws {
        let i = try info(credits: #""credits":{"cast":[{"personId":5,"name":"Mara","character":"Nell"},{"personId":0,"name":"Guide Only","character":"Jon","source":"guide"},{"name":"No Id"}],"guests":[],"crew":[]},"#)
        let spec = MoreInfo.spec(i, now: Date(timeIntervalSince1970: 500))
        let cast = spec.sections.first { $0.heading == "Cast" }!.rows
        XCTAssertEqual(cast.map(\.pressable), [true, false, false])
        XCTAssertEqual(cast[0].id, "person-5")
        XCTAssertFalse(spec.focusOrder.contains { $0.hasPrefix("guide-") })
        XCTAssertEqual(Set(cast.map(\.id)).count, 3)
    }

    func testButtonsAreTheOnesTheServerOffered() throws {
        let spec = MoreInfo.spec(try info(), now: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(spec.actions.map(\.title), ["Watch", "Watch from the start", "Record", "Remind me", "Open item page", "Add to watch list"])
        XCTAssertTrue(spec.layer)
    }

    func testAdvisoryIsNeverShownAndOtherAiringsAre() throws {
        let spec = MoreInfo.spec(try info(), now: Date(timeIntervalSince1970: 500))
        let all = spec.sections.flatMap { $0.rows.map(\.title) + $0.rows.map(\.value) + [$0.note] }
        XCTAssertFalse(all.contains { $0.contains("peril") })
        XCTAssertEqual(spec.sections.first { $0.heading == "Also on" }?.rows.count, 1)
        XCTAssertEqual(spec.eyebrow, "WittyTV · Ch 4 · Four")
        XCTAssertEqual(spec.title, "The Quiet Orchard")
    }
}

final class CommandParamsTests: XCTestCase {
    private let catalog = SDUICatalog.builtIn

    private func body(_ r: (method: String, path: String, body: Data?)?) -> String { r?.body.map { String(decoding: $0, as: UTF8.self) } ?? "" }

    func testAnIntParamReplacesItsQuotedToken() {
        let r = SDUIRouter.request(for: catalog.command("wittyplay.state.save"), item: "s-9", params: ["slot": "3"])
        XCTAssertEqual(r?.path, "/api/play/s-9/action")
        XCTAssertEqual(body(r), #"{"type":"save","slot":3}"#)
    }

    func testAStringParamIsEscapedInTheBodyAndAPathParamInThePath() {
        let join = SDUIRouter.request(for: catalog.command("wittyplay.room.join"), item: "", params: ["code": #"HA"RB"#])
        XCTAssertEqual(body(join), #"{"room":"","code":"HA\"RB"}"#)
        let assign = SDUIRouter.request(for: catalog.command("wittyplay.controller.assign"), item: "s1", params: ["user": "a b/c", "seat": "2"])
        XCTAssertEqual(assign?.path, "/api/play/s1/seats/a%20b%2Fc")
        XCTAssertEqual(body(assign), #"{"seat":2}"#)
    }

    func testAnUnsetParamIsAnEmptyString() {
        let r = SDUIRouter.request(for: catalog.command("wittyplay.room.join"), item: "r1", params: [:])
        XCTAssertEqual(body(r), #"{"room":"r1","code":""}"#)
        let del = SDUIRouter.request(for: catalog.command("wittyplay.state.delete"), item: "7", params: ["slot": "2"])
        XCTAssertEqual(del?.method, "DELETE")
        XCTAssertEqual(del?.path, "/api/games/7/saves/2")
    }

    func testClientHandledCommandsMakeNoRequest() {
        XCTAssertNil(SDUIRouter.request(for: catalog.command("rewind.open"), item: "1"))
        XCTAssertNil(SDUIRouter.request(for: catalog.command("controller.remap"), item: "1"))
    }

    func testAValueLookingLikeATokenIsNotFilledAgain() {
        let r = SDUIRouter.request(for: catalog.command("wittyplay.room.join"), item: "r1", params: ["code": "{item}"])
        XCTAssertEqual(body(r), #"{"room":"r1","code":"{item}"}"#)
    }
}

final class PolicyPickerTests: XCTestCase {
    func testPressingCardsChoosesAndClears() {
        var r = LookPolicy.Requirement()
        r = LookPolicy.applying("look-rail", to: r)
        r = LookPolicy.applying("theme-cinema", to: r)
        XCTAssertEqual(r.experience, "rail")
        XCTAssertEqual(r.theme, "cinema")
        XCTAssertEqual(LookPolicy.applying("look-rail", to: r).experience, "")
        XCTAssertEqual(LookPolicy.applying("theme-none", to: r).theme, "")
        XCTAssertEqual(LookPolicy.applying("nonsense", to: r), r)
    }

    func testPickerMarksWhatIsRequired() {
        let page = LookPolicy.picker(who: "Pip", current: .init(experience: "rail"),
                                     looks: [.init(id: "lumen", name: "Lumen"), .init(id: "rail", name: "Rail")],
                                     themes: [.init(id: "default", name: "Witty")])
        XCTAssertEqual(page.sections[0].cards.filter(\.on).map(\.id), ["look-rail"])
        XCTAssertEqual(page.sections[1].cards.filter(\.on).map(\.id), ["theme-none"])
        XCTAssertEqual(page.title, "Require for Pip")
        XCTAssertEqual(page.start, "look-rail")
    }
}

final class LayoutWireTests: XCTestCase {
    /// A look as `GET /sdui/experiences` sends it (the `wire` of docs/SDUI.md, Experiences).
    private func look(_ json: String) throws -> ExperienceCatalogue.Info {
        try JSONDecoder().decode(ExperienceCatalogue.Info.self, from: Data(json.utf8))
    }

    private let lumen = #"{"id":"lumen","name":"Lumen","wire":{"desktop":{"nav":"top","style":"pill","home":"hero","cards":"poster","brand":"left","finish":"flat"},"phone":{"nav":"bottom","style":"pill","home":"hero","cards":"poster","brand":"top","finish":"flat"},"tv":{"nav":"top","style":"pill","home":"hero","cards":"poster","dock":true,"brand":"left","finish":"flat"}}}"#

    func testEveryScreenDrawsItsOwnWire() throws {
        let l = try look(lumen)
        XCTAssertEqual(LayoutWire.of(l, form: "desktop"), LayoutWire(nav: "top", style: "pill", home: "hero", cards: "poster", brand: "left", finish: "flat"))
        XCTAssertTrue(LayoutWire.of(l, form: "tv").dock)
        // A phone previews the look as a phone draws it: the owner's "show the MOBILE view".
        XCTAssertEqual(LayoutWire.of(l, form: "phone").nav, "bottom")
        // A form factor the server sent nothing for falls back to the web's, then the default.
        XCTAssertEqual(LayoutWire.of(l, form: "tablet"), LayoutWire())
    }

    func testWhatTheServerSendsIsRead() throws {
        let cable = try look(#"{"id":"classicCable","name":"Classic Cable","wire":{"desktop":{"nav":"top","style":"cable","home":"list","cards":"landscape","brand":"left","finish":"flat"}}}"#)
        XCTAssertEqual(LayoutWire.of(cable, form: "desktop").style, "cable")
        XCTAssertEqual(LayoutWire.of(cable, form: "desktop").home, "list")
        let classic = try look(#"{"id":"classic","name":"Classic","wire":{"desktop":{"nav":"side","open":true,"style":"pill","home":"hero","cards":"poster","brand":"top","finish":"flat"}}}"#)
        XCTAssertTrue(LayoutWire.of(classic, form: "desktop").open)
        XCTAssertEqual(LayoutWire.of(classic, form: "desktop").nav, "side")
    }

    func testALookWithNoWireOrFieldsGetsTheDefaultNotACrash() throws {
        XCTAssertEqual(LayoutWire.of(try look(#"{"id":"x","name":"X"}"#), form: "desktop"), LayoutWire())
        let partial = try look(#"{"id":"x","name":"X","wire":{"desktop":{"nav":"rail"}}}"#)
        XCTAssertEqual(LayoutWire.of(partial, form: "desktop").nav, "rail")
        XCTAssertEqual(LayoutWire.of(partial, form: "desktop").home, "hero")
    }

    func testEveryLookCardCarriesItsWireframe() throws {
        let cat = ExperienceCatalogue(experiences: [try look(lumen)])
        let page = AppearancePage.settings(.init(catalogue: cat, themes: []))
        XCTAssertNotNil(page.sections[0].cards.first?.wire)
        XCTAssertNil(page.sections[1].cards.first?.wire)
    }

    func testTheServersOwnTableDecodes() throws {
        let urls = ["WittyMediaServer/pkg/sdui/conformance/experience-wire-table.json"]
        var folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            folder = folder.deletingLastPathComponent()
            let file = folder.appendingPathComponent(urls[0])
            guard let data = try? Data(contentsOf: file) else { continue }
            struct Table: Decodable { let experiences: [ExperienceCatalogue.Info] }
            let table = try JSONDecoder().decode(Table.self, from: data)
            XCTAssertEqual(table.experiences.count, 14)
            XCTAssertTrue(table.experiences.allSatisfy { LayoutWire.of($0, form: "desktop").nav != "" && $0.wire["desktop"] != nil })
            XCTAssertEqual(LayoutWire.of(try XCTUnwrap(table.experiences.first { $0.id == "crossbar" }), form: "desktop").home, "cross")
            return
        }
        throw XCTSkip("The server's repository is not beside this one.")
    }
}
