import XCTest
@testable import WittyKit

final class ShellLookTests: XCTestCase {
    private func libraries() throws -> [Library] {
        try JSONDecoder().decode([Library].self, from: Data(#"""
        [{"id":1,"name":"Movies","type":"movies"},{"id":2,"name":"Ads","type":"commercials"},{"id":3,"name":"Shown ads","type":"commercials","showMain":true},
         {"id":4,"name":"Music","type":"music"}]
        """#.utf8))
    }

    func testTheMenuListsWhatTheWebsiteDoes() throws {
        let page = try JSONDecoder().decode(ModulePage.self, from: Data(#"{"id":"stats","title":"Stats","where":"main","icon":"chart"}"#.utf8))
        let hidden = try JSONDecoder().decode(ModulePage.self, from: Data(#"{"id":"x","title":"X","where":"settings"}"#.utf8))
        let all = NavPlaces.all(libraries: try libraries(), gamePCs: true, modulePages: [("wittystats", page), ("wittystats", hidden)])
        XCTAssertEqual(all.map(\.id), ["home", "tv", "lib:1", "lib:3", "lib:4", "collections", "couch", "m:wittystats:stats"])
        XCTAssertEqual(all.last?.path, "/m/wittystats/stats")
        XCTAssertEqual(NavPlaces.all(libraries: [], gamePCs: false, modulePages: []).map(\.id), ["home", "tv"])
    }

    func testThePersonsOrderAndHiddenPlaces() throws {
        let all = NavPlaces.all(libraries: try libraries(), gamePCs: false, modulePages: [])
        let prefs = NavPrefs(order: ["lib:4", "collections"], hidden: ["lib:1"])
        let arranged = NavPlaces.arrange(all, prefs)
        XCTAssertEqual(arranged.map(\.id), ["lib:4", "collections", "home", "tv", "lib:3"])
        XCTAssertEqual(NavPlaces.strip(arranged).map(\.id), ["lib:4", "collections", "lib:3"])
        XCTAssertEqual(NavPrefs.owner(#"{"order":["tv"],"grouped":true}"#)?.grouped, true)
        XCTAssertNil(NavPrefs.owner("not json"))
        XCTAssertTrue(NavPlaces.isTop(path: "/search", strip: arranged))
        XCTAssertTrue(NavPlaces.isTop(path: "/collections", strip: arranged))
        XCTAssertFalse(NavPlaces.isTop(path: "/item/4", strip: arranged))
        XCTAssertEqual(NavPlaces.group(NavPlace(id: "lib:4", label: "Music", path: "/library/4", kind: "music"), NavPrefs()), "Listen")
        XCTAssertEqual(NavPlaces.group(NavPlace(id: "couch", label: "Game PCs", path: "/couch"), NavPrefs()), "Play")
        XCTAssertNil(NavPlaces.group(NavPlace(id: "collections", label: "Collections", path: "/collections"), NavPrefs()))
    }

    func testTheVersionLine() {
        XCTAssertEqual(VersionTag.parts("0.4.0-alpha.3").number, "0.4.0")
        XCTAssertEqual(VersionTag.parts("v0.4.0-alpha.3").stage, "ALPHA")
        XCTAssertEqual(VersionTag.parts("1.2.3").stage, "")
        XCTAssertEqual(VersionTag.parts("dev").number, "dev")
        XCTAssertEqual(VersionTag.parts("dev").stage, "DEV")
    }

    func testTheActivityButtonsWords() throws {
        let busy = try JSONDecoder().decode(ActivityTasks.self, from: Data(#"""
        {"access":{"visible":true,"readOnly":false},"summary":{"active":2,"queued":1,"paused":1,"percent":40.4},
         "tasks":[{"id":"a","title":"Scan","libraryName":"Movies","state":"running","done":1204,"total":3000,"unit":"files"},
                  {"id":"b","title":"Clean up","state":"queued"},{"id":"c","title":"Copy","libraryName":"Anime","state":"running","canResume":true,"done":1288490188,"total":4294967296,"unit":"bytes"}]}
        """#.utf8))
        XCTAssertEqual(busy.label(), "Activity: 1 running, 1 paused, 1 waiting, 40% done")
        XCTAssertEqual(busy.busy, 3)
        XCTAssertEqual(ActivityTasks.grouped(busy.tasks ?? []).map(\.name), ["Anime", "Movies", "This server"])
        XCTAssertEqual(busy.tasks?.first?.countWords, "1,204 of 3,000 files")
        XCTAssertEqual(busy.tasks?.last?.stateWords, "Pausing…")
        XCTAssertEqual(busy.tasks?.last?.countWords, "1.2 GB of 4.0 GB")
        let idle = try JSONDecoder().decode(ActivityTasks.self, from: Data(#"{"access":{"visible":false}}"#.utf8))
        XCTAssertEqual(idle.label(), "Activity: nothing going on")
        XCTAssertFalse(idle.shown)
    }
}
