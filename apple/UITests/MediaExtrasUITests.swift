// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

/// The server's media extras, driven as a person would: skip buttons and skipping by itself, canvases, karaoke
/// with a song's real voice track, where to watch, and an administrator's tools.
///
/// They need a server with media made for them, and are told which items those are (each test skips itself when
/// its item isn't named), beside the server and the administrator Support.swift asks for:
///
///   TEST_RUNNER_WMC_SKIP_ITEM     a video of 2½ minutes with a `.skip.json`: intro 5–20 s, adverts 40–50 s
///   TEST_RUNNER_WMC_WATCH_ITEM    a film the server knows offers for (with a canvas-less video file)
///   TEST_RUNNER_WMC_CANVAS_VIDEO  a video file to cut a canvas from, with none yet
///   TEST_RUNNER_WMC_SHOW          a show with two or more episodes that share a title tune
///   TEST_RUNNER_WMC_STEMS_SONG    a song with uploaded `vocals` and `instrumental`, and a canvas
///   TEST_RUNNER_WMC_PLAIN_SONG    a stereo song with no stems
///   TEST_RUNNER_WMC_MONO_SONG     a mono song with no stems
///   TEST_RUNNER_WMC_ALBUM         the stems song's album, as `library:album:artist`
///   TEST_RUNNER_WMC_USER_VIEWER   (and `_PASSWORD_VIEWER`) an account that isn't an administrator
///   TEST_RUNNER_WMC_SHOTS         a folder for pictures of each step, if wanted
final class MediaExtrasUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func named(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment["WMC_\(key)"], !value.isEmpty else {
            throw XCTSkip("Not told which item: set TEST_RUNNER_WMC_\(key).")
        }
        return value
    }

    /// A picture of the screen into the folder the run named, for whoever reads the run afterwards.
    @MainActor
    private func snap(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["WMC_SHOTS"], !folder.isEmpty else { return }
        #if os(tvOS)
        let kind = "tv"
        #else
        let kind = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(kind)-\(name).png"))
    }

    /// This device's choice of what to skip by itself, as the app keeps it: launch arguments are read as defaults.
    private func skipping(_ json: String) -> [String] {
        ["-wms.skip.auto", "<" + json.utf8.map { String(format: "%02x", $0) }.joined() + ">"]
    }

    /// Seconds of a "1:02 of 2:30" or "0:07".
    private func seconds(_ words: String) -> Int? {
        let first = words.split(separator: " ").first.map(String.init) ?? ""
        let parts = first.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count == first.split(separator: ":").count else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// Scrolls a page until something is on screen.
    @MainActor
    private func reach(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 12) {
        #if os(iOS)
        var left = swipes
        while !(element.exists && element.isHittable), left > 0 {
            app.swipeUp(velocity: .slow)
            left -= 1
        }
        #endif
        element.shown(10)
    }

    // MARK: Skipping

    #if os(iOS)
    @MainActor
    func testEachPartOffersItsSkipButtonAndTheButtonSkips() throws {
        let item = try named("SKIP_ITEM")
        let app = try launchApp(extra: ["-WMCOpen", "player:\(item)"] + skipping(#"{}"#))
        let intro = app.buttons["skip-intro"]
        intro.shown(40)
        snap("skip-intro")
        XCTAssertEqual(intro.label, "Skip intro")
        intro.tap()
        // The controls are shown by the touch: the film is now where the intro ends.
        let position = app.otherElements["Position"].firstMatch
        position.shown(5)
        let at = try XCTUnwrap(seconds(position.value as? String ?? ""), "the seek bar says where the film is")
        XCTAssertTrue((20...27).contains(at), "after Skip intro the film is just past 0:20, not at \(at) s")
        XCTAssertFalse(app.buttons["skip-intro"].exists)
        XCTAssertFalse(app.buttons["skip-undo"].exists, "a part skipped by hand has nothing to undo")
        // Twenty seconds on, the adverts.
        snap("dbg-after-intro")
        let adverts = app.buttons["skip-commercial"]
        adverts.shown(30)
        XCTAssertEqual(adverts.label, "Skip adverts")
        snap("skip-adverts")
        adverts.tap()
        let after = try XCTUnwrap(seconds(position.value as? String ?? ""))
        XCTAssertTrue((50...57).contains(after), "after Skip adverts the film is just past 0:50, not at \(after) s")
    }

    @MainActor
    func testAChosenPartIsSkippedByItselfOnceWithAWayBack() throws {
        let item = try named("SKIP_ITEM")
        let app = try launchApp(extra: ["-WMCOpen", "player:\(item)"] + skipping(#"{"intro":true}"#))
        let undo = app.buttons["skip-undo"]
        undo.shown(40)
        snap("skip-undo")
        XCTAssertEqual(undo.label, "Skipped the intro. Undo")
        XCTAssertFalse(app.buttons["skip-intro"].exists, "past the intro there's nothing to skip")
        undo.tap()
        // Back inside the intro, which now plays: its button is there, and it isn't skipped again.
        let intro = app.buttons["skip-intro"]
        intro.shown(10)
        let position = app.otherElements["Position"].firstMatch
        position.shown(5)
        let at = try XCTUnwrap(seconds(position.value as? String ?? ""))
        XCTAssertTrue((5...12).contains(at), "Undo goes back to where the film was, not to \(at) s")
        sleep(4)
        XCTAssertTrue(intro.exists, "the intro plays through after Undo")
        XCTAssertFalse(app.buttons["skip-undo"].exists)
        snap("skip-after-undo")
    }

    @MainActor
    func testSeekingBackIntoAPartPlaysIt() throws {
        let item = try named("SKIP_ITEM")
        let app = try launchApp(extra: ["-WMCOpen", "player:\(item)"] + skipping(#"{"intro":true}"#))
        app.buttons["skip-undo"].shown(40)
        // A touch on the picture pauses and shows the controls; then a touch on the seek bar, a person's own
        // choice to go back into the intro.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        let position = app.otherElements["Position"].firstMatch
        position.shown(5)
        position.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        app.buttons["skip-intro"].shown(10)
        app.buttons["Play"].firstMatch.tap()
        sleep(4)
        XCTAssertTrue(app.buttons["skip-intro"].exists, "seeked into, the intro is left alone")
        XCTAssertFalse(app.buttons["skip-undo"].exists)
        let at = try XCTUnwrap(seconds(position.value as? String ?? ""))
        XCTAssertTrue((12...19).contains(at), "the intro is playing on from where it was put, at \(at) s")
    }

    @MainActor
    func testTheGearHasTheSkippingChoices() throws {
        let item = try named("SKIP_ITEM")
        let app = try launchApp(extra: ["-WMCOpen", "player:\(item)"] + skipping(#"{}"#))
        app.buttons["skip-intro"].shown(40)
        let gear = app.buttons["Viewing settings"].firstMatch
        if !gear.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
        gear.shown(5)
        gear.tap()
        snap("dbg-gear")
        let choice = app.buttons["gear-skip-intro"]
        reach(choice, in: app)
        XCTAssertEqual(choice.value as? String, "Off")
        choice.tap()
        XCTAssertEqual(choice.value as? String, "On")
        snap("skip-gear")
    }
    #endif

    #if os(tvOS)
    @MainActor
    func testAppleTVOffersTheSkipButtonInThePlayer() throws {
        let item = try named("SKIP_ITEM")
        let app = try launchApp(extra: ["-WMCOpen", "player:\(item)"] + skipping(#"{}"#))
        let intro = app.buttons["Skip intro"]
        intro.shown(40)
        snap("skip-intro")
        // The system player gives its contextual action the Select press without it having been moved to.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Skip intro"].waitForNonExistence(timeout: 8), "pressed, the intro is behind")
        app.buttons["Skip adverts"].shown(30)
        snap("skip-adverts")
    }

    @MainActor
    func testAppleTVSkipsAChosenPartByItselfAndOffersUndo() throws {
        let item = try named("SKIP_ITEM")
        let app = try launchApp(extra: ["-WMCOpen", "player:\(item)"] + skipping(#"{"intro":true}"#))
        let undo = app.buttons["Skipped the intro · Undo"]
        undo.shown(40)
        snap("skip-undo")
        XCTAssertFalse(app.buttons["Skip intro"].exists)
        XCUIRemote.shared.press(.select)
        app.buttons["Skip intro"].shown(10)
        sleep(3)
        XCTAssertTrue(app.buttons["Skip intro"].exists, "the intro plays through after Undo")
    }
    #endif

    // MARK: You

    @MainActor
    func testYouHasTheChoicesForSkippingAndCanvases() throws {
        let app = try launchApp(extra: ["-WMCOpen", "settings"] + skipping(#"{}"#))
        app.staticTexts["Skipping and moving pictures"].firstMatch.shown(30)
        let intros = app.switches["auto-skip-intro"].firstMatch
        intros.shown(10)
        XCTAssertTrue(app.switches["auto-skip-recap"].exists && app.switches["auto-skip-credits"].exists && app.switches["auto-skip-commercial"].exists)
        XCTAssertTrue(app.switches["canvas-wanted"].firstMatch.exists, "the server lists canvases, so their switch is here")
        XCTAssertEqual(intros.value as? String, "0")
        #if os(tvOS)
        XCUIRemote.shared.press(.select)
        #else
        intros.switches.firstMatch.exists ? intros.switches.firstMatch.tap() : intros.tap()
        #endif
        XCTAssertEqual(intros.value as? String, "1")
        snap("settings")
    }

    // MARK: Canvas

    @MainActor
    func testASongsCanvasLoopsBehindThePlayerAndTheSwitchStillsIt() throws {
        let song = try named("STEMS_SONG")
        var app = try launchApp(extra: ["-WMCOpen", "song:\(song)"])
        app.otherElements["canvas-playing"].firstMatch.shown(40)
        sleep(2)
        snap("canvas-player")
        app.terminate()
        app = try launchApp(extra: ["-WMCOpen", "song:\(song)", "-wms.canvas.off", "YES"])
        #if os(tvOS)
        app.buttons["Pause"].firstMatch.shown(40)
        #else
        app.buttons["Karaoke"].firstMatch.shown(40)
        #endif
        sleep(4)
        XCTAssertFalse(app.otherElements["canvas-playing"].exists, "switched off, the artwork stays still")
        snap("canvas-off")
    }

    @MainActor
    func testAnAlbumsCoverComesAlive() throws {
        let album = try named("ALBUM")
        let app = try launchApp(extra: ["-WMCOpen", "album:\(album)"])
        app.otherElements["canvas-playing"].firstMatch.shown(40)
        sleep(2)
        snap("canvas-album")
    }

    // MARK: A title's page

    @MainActor
    func testATitleSaysWhereElseItCanBeWatched() throws {
        let item = try named("WATCH_ITEM")
        let app = try launchApp(extra: ["-WMCOpen", "item:\(item)"])
        let included = app.descendants(matching: .any)["watch-stream"].firstMatch
        reach(included, in: app)
        XCTAssertTrue(included.label.hasPrefix("Included with a subscription: Netflix"), included.label)
        XCTAssertTrue(app.staticTexts["watch-in-library"].firstMatch.exists || app.descendants(matching: .any)["watch-in-library"].firstMatch.exists)
        let credit = app.staticTexts["watch-credit"].firstMatch
        reach(credit, in: app)
        XCTAssertTrue(credit.label.contains("TMDB"), "the source's credit is shown with it: \(credit.label)")
        XCTAssertTrue(credit.label.contains("Offers in United States"))
        #if os(iOS)
        XCTAssertTrue(app.buttons["watch-link"].exists, "the offers page opens in the browser")
        #else
        XCTAssertFalse(app.buttons["watch-link"].exists, "Apple TV has no browser: the names are what it shows")
        #endif
        snap("where-to-watch")
    }

    @MainActor
    func testAnAdministratorHasACanvasCutFromTheVideoAndRemovesIt() throws {
        let item = try named("CANVAS_VIDEO")
        let app = try launchApp(extra: ["-WMCOpen", "item:\(item)"])
        let make = app.buttons["canvas-make"].firstMatch
        reach(make, in: app)
        #if os(tvOS)
        // Down from Play to the tools.
        for _ in 0..<6 where !make.hasFocus { XCUIRemote.shared.press(.down) }
        XCUIRemote.shared.press(.select)
        #else
        make.tap()
        #endif
        let result = app.staticTexts["media-job-result"].firstMatch
        result.shown(120)
        XCTAssertEqual(result.label, "The canvas is ready.")
        let remove = app.buttons["canvas-remove"].firstMatch
        remove.shown(10)
        XCTAssertTrue(app.staticTexts["canvas-status"].firstMatch.label.hasPrefix("Cut from the video by the server"))
        #if os(iOS)
        // It now loops at the top of the page.
        app.swipeDown()
        app.swipeDown()
        app.otherElements["canvas-playing"].firstMatch.shown(30)
        snap("canvas-title")
        reach(remove, in: app)
        remove.tap()
        #else
        app.otherElements["canvas-playing"].firstMatch.shown(30)
        snap("canvas-title")
        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.select)
        #endif
        let removed = NSPredicate(format: "label == 'The canvas was removed.'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: removed, object: result)], timeout: 30), .completed, result.label)
        XCTAssertFalse(app.buttons["canvas-remove"].exists)
        XCTAssertTrue(app.staticTexts["canvas-status"].firstMatch.label.hasPrefix("This title has no canvas"))
    }

    @MainActor
    func testAnAdministratorFindsAShowsIntrosByEar() throws {
        let show = try named("SHOW")
        let app = try launchApp(extra: ["-WMCOpen", "show:\(show)"])
        let find = app.buttons["intros-find"].firstMatch
        #if os(tvOS)
        find.shown(30)
        for _ in 0..<12 where !find.hasFocus { XCUIRemote.shared.press(.down) }
        XCUIRemote.shared.press(.select)
        #else
        reach(find, in: app)
        find.tap()
        #endif
        let result = app.staticTexts["media-job-result"].firstMatch
        result.shown(180)
        XCTAssertTrue(result.label.hasPrefix("Found an intro in"), result.label)
        snap("intros-found")
    }

    @MainActor
    func testSomeoneWhoIsntAnAdministratorSeesNoTools() throws {
        let item = try named("CANVAS_VIDEO")
        guard let viewer = TestServer.account("viewer") else { throw XCTSkip("No second account: set TEST_RUNNER_WMC_USER_VIEWER.") }
        let app = try launchApp(user: viewer.user, password: viewer.password, extra: ["-WMCOpen", "item:\(item)"])
        app.buttons["Play"].firstMatch.shown(40)
        #if os(iOS)
        for _ in 0..<5 { app.swipeUp() }
        #endif
        XCTAssertFalse(app.buttons["canvas-make"].exists)
        XCTAssertFalse(app.staticTexts["canvas-status"].exists)
    }
}
