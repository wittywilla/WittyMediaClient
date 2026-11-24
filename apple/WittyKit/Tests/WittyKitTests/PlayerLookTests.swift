// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
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
        XCTAssertEqual(audio.map(\.title), ["English", "French", "Track 3"], "never Unknown")
        XCTAssertEqual(audio[0].sub, "Commentary")
        XCTAssertEqual(audio[0].detail, "AAC · Stereo")
        XCTAssertEqual(audio.map(\.active), [false, true, false])
        let subtitles = TrackTile.subtitles(Array(tracks.prefix(1)), chosen: -1)
        XCTAssertEqual(subtitles.map(\.title), ["Off", "English"])
        XCTAssertTrue(subtitles[0].active)
    }

    // The same cases as Android's TrackWordsTest, so all three players name tracks alike.
    func testTracksAreNamedAsOnAndroid() throws {
        func track(_ json: String) throws -> Track { try JSONDecoder().decode(Track.self, from: Data(json.utf8)) }
        let english = TrackWords.audio(try track(#"{"index":1,"language":"eng","languageName":"English","codec":"ac3","channels":6}"#), number: 1)
        XCTAssertEqual(english, TrackName(title: "English", sub: "", detail: "AC3 · 5.1"))
        XCTAssertEqual(TrackWords.languageOf("ger"), "German")
        XCTAssertEqual(TrackWords.languageOf("deu"), "German")
        XCTAssertEqual(TrackWords.languageOf("fre"), "French")
        XCTAssertEqual(TrackWords.languageOf("jpn"), "Japanese")
        XCTAssertEqual(TrackWords.languageOf("und"), "")
        XCTAssertEqual(TrackWords.audio(try track(#"{"index":4,"codec":"aac","channels":2}"#), number: 2).title, "Track 2")
        XCTAssertEqual(TrackWords.subtitle(try track(#"{"index":7,"language":"und","codec":"subrip"}"#), number: 3).title, "Subtitles 3")
        let sdh = TrackWords.subtitle(try track(#"{"index":3,"language":"eng","languageName":"English","codec":"subrip","sdh":true}"#), number: 2)
        XCTAssertEqual(sdh, TrackName(title: "English", sub: "SDH", detail: "Text"))
        let forced = TrackWords.subtitle(try track(#"{"index":4,"language":"eng","title":"Signs","codec":"hdmv_pgs_subtitle","forced":true}"#), number: 3)
        XCTAssertEqual(forced, TrackName(title: "English", sub: "Signs · Forced", detail: "Pictures"))
        XCTAssertEqual(TrackWords.subtitle(try track(#"{"index":6,"language":"eng","title":"English SDH","sdh":true}"#), number: 1).sub, "English SDH")
        XCTAssertEqual(TrackWords.audio(try track(#"{"index":2,"language":"eng","commentary":true,"channels":2}"#), number: 2).sub, "Commentary")
    }

    func testTheQualityMenuMarksWhatIsInUse() throws {
        let menu = try JSONDecoder().decode(QualityMenu.self, from: Data(#"{"choice":"h720-b4000","sourceHeight":1080,"presets":[{"name":"720p","height":720,"kbps":4000},{"name":"480p","height":480,"kbps":1500}]}"#.utf8))
        XCTAssertEqual(menu.rows.map(\.name), ["Auto", "Original", "720p", "480p"])
        XCTAssertEqual(menu.rows.map(\.active), [false, false, true, false])
        XCTAssertEqual(menu.rows[1].detail, "1080p")
        XCTAssertEqual(menu.rows[3].detail, "1.5 Mbit/s")
        XCTAssertEqual(menu.shortName, "720p")
    }

    func testAScenesPictureIsAQuarterInBetweenTwoAndTwentySeconds() throws {
        let chapters = try JSONDecoder().decode([Chapter].self, from: Data(#"[{"start":0,"title":"Start"},{"start":60},{"start":300}]"#.utf8))
        XCTAssertEqual(Scenes.pictureSec(chapters, 0, duration: 400), 15)
        XCTAssertEqual(Scenes.pictureSec(chapters, 1, duration: 400), 80)
        XCTAssertEqual(Scenes.pictureSec(chapters, 2, duration: 400), 320)
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

final class PlayerRemoteTests: XCTestCase {
    func testAFileGreysOutTheDiscKeys() {
        XCTAssertFalse(RemoteKey.menu.worksForFile(audioTracks: 2, subtitleTracks: 1))
        XCTAssertFalse(RemoteKey.digit5.worksForFile(audioTracks: 2, subtitleTracks: 1))
        XCTAssertTrue(RemoteKey.play.worksForFile(audioTracks: 1, subtitleTracks: 0))
        XCTAssertFalse(RemoteKey.audio.worksForFile(audioTracks: 1, subtitleTracks: 0))
        XCTAssertTrue(RemoteKey.audio.worksForFile(audioTracks: 2, subtitleTracks: 0))
        XCTAssertFalse(RemoteKey.subtitle.worksForFile(audioTracks: 2, subtitleTracks: 0))
        XCTAssertEqual([RemoteKey.rew, .prev, .ff, .next].map(\.jump), [-10, -60, 30, 60])
    }

    func testTheStreamingChoiceIsKeptAndAskedFor() {
        let defaults = UserDefaults(suiteName: "PlayerRemoteTests")!
        defaults.removePersistentDomain(forName: "PlayerRemoteTests")
        XCTAssertEqual(DeviceStreaming.load(defaults), .auto)
        DeviceStreaming.save(.robust, defaults)
        XCTAssertEqual(DeviceStreaming.load(defaults), .robust)
        DeviceStreaming.save(.auto, defaults)
        XCTAssertNil(defaults.string(forKey: "wms.streaming"))
        XCTAssertNil(DeviceStreaming.auto.asked)
        XCTAssertEqual(DeviceStreaming.standard.asked, "standard")
        XCTAssertTrue(DeviceStreaming.auto.measures(serverMode: "robust"))
        XCTAssertFalse(DeviceStreaming.auto.measures(serverMode: "standard"))
        XCTAssertFalse(DeviceStreaming.standard.measures(serverMode: "robust"))
        XCTAssertTrue(DeviceStreaming.robust.measures(serverMode: nil))
        XCTAssertEqual(DeviceStreaming.allCases.map(\.words), ["Server’s choice", "Standard", "Robust"])
    }

    func testTheRemoteRemembersItsPlaceAndStaysInBounds() throws {
        let saved = try JSONDecoder().decode(RemoteGeometry.self, from: Data(#"{"x":40,"y":80,"scale":3,"alpha":0.55}"#.utf8))
        XCTAssertEqual(saved.scale, 1.6)
        XCTAssertEqual(saved.nextAlpha, 0.35)
        XCTAssertEqual(RemoteGeometry(alpha: 0.35).nextAlpha, 0.92)
        XCTAssertNil(try JSONDecoder().decode(RemoteGeometry.self, from: Data("{}".utf8)).x)
        let prefs = try JSONDecoder().decode(ViewPrefs.self, from: Data(#"{"remote":true,"remoteStyle":"sideways"}"#.utf8))
        XCTAssertTrue(prefs.remote)
        XCTAssertEqual(prefs.remoteStyle, "floating")
        XCTAssertFalse(ViewPrefs().remote)
    }
}
