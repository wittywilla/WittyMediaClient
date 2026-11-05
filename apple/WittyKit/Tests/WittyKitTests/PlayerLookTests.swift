import XCTest
@testable import WittyKit

final class PlayerLookTests: XCTestCase {
    func testTimesAreWrittenAsTheWebsiteWritesThem() {
        XCTAssertEqual(PlayerTime.format(0), "0:00")
        XCTAssertEqual(PlayerTime.format(65.9), "1:05")
        XCTAssertEqual(PlayerTime.format(3723), "1:02:03")
        XCTAssertEqual(PlayerTime.format(-4), "0:00")
        XCTAssertEqual(PlayerTime.format(.nan), "0:00")
    }

    func testSpeedsStopAtTheServersLimit() {
        XCTAssertEqual(PlayerSpeeds.offered(max: nil).last, 4)
        XCTAssertEqual(PlayerSpeeds.offered(max: 2).last, 2)
        XCTAssertEqual(PlayerSpeeds.offered(max: 16).count, PlayerSpeeds.all.count)
        XCTAssertEqual(PlayerSpeeds.words(1), "Normal")
        XCTAssertEqual(PlayerSpeeds.words(1.25), "1.25×")
        XCTAssertEqual(PlayerSpeeds.button(2), "2×")
    }

    func testViewChoicesForOneVideoWinUntilEverythingIsChosen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PlayerLookTests"))
        defaults.removePersistentDomain(forName: "PlayerLookTests")
        let store = ViewPrefsStore(defaults: defaults)
        XCTAssertEqual(store.load(item: 7).prefs, ViewPrefs())
        XCTAssertEqual(store.load(item: 7).scope, .global)

        store.save(ViewPrefs(seekBar: false), item: 7, scope: .item)
        XCTAssertEqual(store.load(item: 7).prefs.seekBar, false)
        XCTAssertEqual(store.load(item: 7).scope, .item)
        XCTAssertEqual(store.load(item: 8).prefs.seekBar, true, "another video keeps the global choices")

        store.save(ViewPrefs(hideAfter: 0, picture: "fill"), item: 7, scope: .global)
        XCTAssertEqual(store.load(item: 7).scope, .global, "choosing for everything takes this video's own away")
        XCTAssertEqual(store.load(item: 8).prefs.picture, "fill")
        XCTAssertEqual(store.load(item: 8).prefs.hideAfter, 0)
    }

    func testAnOddSavedChoiceFallsBackToTheDefault() throws {
        let prefs = try JSONDecoder().decode(ViewPrefs.self, from: Data(#"{"picture":"stretch","hideAfter":"soon","remote":true}"#.utf8))
        XCTAssertEqual(prefs.picture, "fit")
        XCTAssertEqual(prefs.hideAfter, 3.5)
        XCTAssertTrue(prefs.seekBar)
    }

    func testTrackTilesSayTheLanguageThenTheNameThenTheFormat() throws {
        let tracks = try JSONDecoder().decode([Track].self, from: Data(#"""
        [{"index":1,"language":"eng","languageName":"English","title":"Commentary","codec":"aac","channels":2},
         {"index":2,"language":"fra","codec":"ac3","channels":6},
         {"index":3,"language":"und"}]
        """#.utf8))
        let audio = TrackTile.audio(tracks, chosen: 2)
        XCTAssertEqual(audio.map(\.title), ["English", "French", "Unknown"])
        XCTAssertEqual(audio[0].sub, "Commentary")
        XCTAssertEqual(audio[0].detail, "AAC · 2 ch")
        XCTAssertEqual(audio.map(\.active), [false, true, false])
        let subtitles = TrackTile.subtitles(Array(tracks.prefix(1)), chosen: -1)
        XCTAssertEqual(subtitles.map(\.title), ["Off", "English"])
        XCTAssertTrue(subtitles[0].active)
    }

    func testTheSceneIsTheLastOneStarted() throws {
        let chapters = try JSONDecoder().decode([Chapter].self, from: Data(#"[{"start":0,"title":"Opening"},{"start":60},{"start":120,"title":""}]"#.utf8))
        let starts = chapters.map(\.start)
        XCTAssertEqual(Scenes.current(starts, at: 0), 0)
        XCTAssertEqual(Scenes.current(starts, at: 59.6), 1, "half a second early counts")
        XCTAssertEqual(Scenes.current(starts, at: 500), 2)
        XCTAssertEqual(Scenes.name(chapters, 0), "Opening")
        XCTAssertEqual(Scenes.name(chapters, 1), "Scene 2")
        XCTAssertEqual(Scenes.name(chapters, 2), "Scene 3")
    }

    func testThePlaybackAnswerCarriesChaptersAndTheWholeExplanation() throws {
        let answer = try JSONDecoder().decode(Playback.self, from: Data(#"""
        {"url":"/x.m3u8","chapters":[{"start":0,"title":"One"}],"explain":{"summary":"Direct","load":"none","streaming":"Standard"}}
        """#.utf8))
        XCTAssertEqual(answer.chapters?.first?.title, "One")
        XCTAssertEqual(answer.explain?.load, "none")
        XCTAssertEqual(answer.explain?.streaming, "Standard")
    }
}
