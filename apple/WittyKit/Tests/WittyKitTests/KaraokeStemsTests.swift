// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class KaraokeStemsTests: XCTestCase {
    private func stem(_ id: String, _ role: String, gain: Double = 1, label: String = "") -> KaraokeStem {
        KaraokeStem(id: id, label: label, role: role, url: "/api/media/12/stems/\(id)?v=1a2b", mime: "audio/mp4", defaultGain: gain)
    }

    private func parts(version: String = "1a2b", improving: Bool = false, pollSec: Double = 0) -> KaraokeStatus {
        KaraokeStatus(state: "ready", quality: "stems", mix: "parts",
                      stems: [stem("vocals", "vocals"), stem("drums", "music", gain: 0.9), stem("bass", "music"), stem("other", "music")],
                      version: version, improving: improving, progress: improving ? 40 : -1, pollSec: pollSec)
    }

    private func blend(version: String = "q1", improving: Bool = false, pollSec: Double = 0) -> KaraokeStatus {
        KaraokeStatus(state: "ready", quality: "approximate", mix: "blend",
                      stems: [stem("full", "full", gain: 0.8), stem("instrumental", "music")],
                      version: version, improving: improving, progress: improving ? 40 : -1, pollSec: pollSec)
    }

    // MARK: Reading the server's answer

    func testReadsTheAnswerWithFieldsAndRolesItDoesNotKnow() throws {
        let json = """
        {"state":"ready","quality":"stems","mix":"parts","stems":[
          {"id":"vocals","label":"Vocals","role":"vocals","url":"/api/media/12/stems/vocals?v=1a2b","mime":"audio/mp4","defaultGain":1,"new":true},
          {"id":"piano","label":"Piano","role":"keys","url":"/api/media/12/stems/piano.flac?v=1a2b","mime":"application/octet-stream","defaultGain":7},
          {"label":"no id"},
          {"id":"bass","role":"music","url":"/api/media/12/stems/bass?v=1a2b","mime":"audio/flac"}],
         "version":"1a2b","improving":true,"progress":40,"canImprove":false,"reason":"","message":"","pollSec":3,"somethingNew":{"a":[1]}}
        """
        let status = try JSONDecoder().decode(KaraokeStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.state, "ready")
        XCTAssertEqual(status.stems.map(\.id), ["vocals", "piano", "bass"])
        XCTAssertEqual(status.stems[1].role, "keys")
        XCTAssertEqual(status.stems[1].defaultGain, 1, "a gain out of range is brought within it")
        XCTAssertEqual(status.stems[1].fileExtension, "flac")
        XCTAssertEqual(status.stems[0].fileExtension, "m4a")
        XCTAssertEqual(status.stems[2].fileExtension, "flac")
        XCTAssertEqual(status.stems[2].label, "Bass")
        XCTAssertEqual(status.version, "1a2b")
        XCTAssertTrue(status.improving)
        XCTAssertEqual(status.progress, 40)
        XCTAssertEqual(status.pollSec, 3)
        XCTAssertTrue(StemMix.playable(status))
        // A role nobody knows plays as music.
        XCTAssertEqual(StemMix.gains(status, StemLevels())["piano"], 1)
    }

    func testReadsAnAnswerWithNearlyNothingInIt() throws {
        let status = try JSONDecoder().decode(KaraokeStatus.self, from: Data(#"{"state":"unavailable","reason":"mono","message":"This song is in mono.","progress":-1,"stems":null}"#.utf8))
        XCTAssertEqual(status.state, "unavailable")
        XCTAssertEqual(status.message, "This song is in mono.")
        XCTAssertEqual(status.progress, -1)
        XCTAssertEqual(status.pollSec, 0)
        XCTAssertTrue(status.stems.isEmpty)
        let empty = try JSONDecoder().decode(KaraokeStatus.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.state, "")
        XCTAssertFalse(StemMix.playable(empty))
    }

    // MARK: How loud each part is

    func testPartsPlayAtTheirOwnLevels() {
        var levels = StemLevels()
        XCTAssertEqual(StemMix.gains(parts(), levels), ["vocals": 1, "drums": 0.9, "bass": 1, "other": 1])
        levels.setVocals(0.25)
        levels.setStem("bass", 0.5)
        XCTAssertEqual(StemMix.gains(parts(), levels), ["vocals": 0.25, "drums": 0.9, "bass": 0.5, "other": 1])
        XCTAssertEqual(StemMix.sliders(parts(), levels).map(\.id), ["vocals", "drums", "bass", "other"])
        XCTAssertEqual(StemMix.sliders(parts(), levels).map(\.label), ["Vocals", "Drums", "Bass", "Other"])
        XCTAssertEqual(StemMix.sliders(parts(), levels).map(\.level), [0.25, 0.9, 0.5, 1])
    }

    func testAWholeSongCopyAmongPartsIsNotPlayed() {
        var status = parts()
        status.stems.append(stem("full", "full"))
        XCTAssertNil(StemMix.gains(status, StemLevels())["full"])
        XCTAssertEqual(StemMix.played(status).map(\.id), ["vocals", "drums", "bass", "other"])
    }

    func testBlendCrossesBetweenTheWholeSongAndTheInstrumental() {
        var levels = StemLevels()
        // The voice starts from the whole song's suggested level.
        XCTAssertEqual(StemMix.vocalsLevel(blend(), levels), 0.8)
        var gains = StemMix.gains(blend(), levels)
        XCTAssertEqual(gains["full"] ?? -1, 0.8, accuracy: 1e-9)
        XCTAssertEqual(gains["instrumental"] ?? -1, 0.2, accuracy: 1e-9)
        levels.setVocals(0.25)
        levels.setStem("instrumental", 0.5)
        gains = StemMix.gains(blend(), levels)
        XCTAssertEqual(gains["full"] ?? -1, 0.125, accuracy: 1e-9)
        XCTAssertEqual(gains["instrumental"] ?? -1, 0.375, accuracy: 1e-9)
        // A straight line: the two always add up to the music's level.
        for v in stride(from: 0.0, through: 1.0, by: 0.1) {
            levels.setVocals(v)
            let g = StemMix.gains(blend(), levels)
            XCTAssertEqual((g["full"] ?? 0) + (g["instrumental"] ?? 0), 0.5, accuracy: 1e-9)
        }
        XCTAssertEqual(StemMix.sliders(blend(), levels).map(\.label), ["Vocals", "Music"])
        XCTAssertEqual(StemMix.sliders(blend(), levels).map(\.id), ["vocals", "instrumental"])
    }

    func testSingTakesTheVoiceOutAndKeepsItsSlider() {
        var levels = StemLevels()
        levels.setVocals(0.6)
        levels.toggleSing()
        XCTAssertEqual(StemMix.gains(parts(), levels)["vocals"], 0)
        XCTAssertEqual(StemMix.gains(parts(), levels)["drums"], 0.9)
        XCTAssertEqual(StemMix.vocalsLevel(parts(), levels), 0.6, "the slider stays where it was")
        XCTAssertEqual(StemMix.gains(blend(), levels), ["full": 0, "instrumental": 1])
        levels.toggleSing()
        XCTAssertEqual(StemMix.gains(parts(), levels)["vocals"], 0.6)
        levels.toggleSing()
        levels.setVocals(0.3)
        XCTAssertFalse(levels.sing, "moving the slider turns Sing off")
        XCTAssertEqual(StemMix.gains(parts(), levels)["vocals"], 0.3)
    }

    func testResetGoesBackToWhatTheServerSuggests() {
        var levels = StemLevels()
        levels.setVocals(0.1)
        levels.setStem("drums", 0.2)
        levels.toggleSing()
        levels.reset()
        XCTAssertEqual(levels, StemLevels())
        XCTAssertEqual(StemMix.gains(parts(), levels), ["vocals": 1, "drums": 0.9, "bass": 1, "other": 1])
    }

    func testLevelsStayWithinRangeAndStepByFive() {
        var levels = StemLevels()
        levels.setVocals(4)
        levels.setStem("bass", -1)
        XCTAssertEqual(levels.vocals, 1)
        XCTAssertEqual(levels.stems["bass"], 0)
        XCTAssertEqual(StemMix.stepped(0.5, by: 1), 0.55, accuracy: 1e-9)
        XCTAssertEqual(StemMix.stepped(0.02, by: -1), 0)
        XCTAssertEqual(StemMix.stepped(0.98, by: 1), 1)
        XCTAssertEqual(StemMix.percent(0.55), "55%")
    }

    func testWords() {
        XCTAssertEqual(StemMix.qualityWords(parts()), "Separated")
        XCTAssertEqual(StemMix.qualityWords(blend()), "Quick version")
        XCTAssertEqual(StemMix.preparingWords(40), "Preparing karaoke… 40%")
        XCTAssertEqual(StemMix.preparingWords(-1), "Preparing karaoke…")
        XCTAssertEqual(StemMix.improvingWords(40), "Preparing a better version… 40%")
        XCTAssertEqual(StemMix.improvingWords(-1), "Preparing a better version…")
    }

    // MARK: What's remembered

    func testLevelsAreKeptForEachPersonAndSingIsNot() throws {
        let name = "karaoke-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let mine = StemLevelsStore(server: "http://tv.local:9797", profile: "7", defaults: defaults)
        let theirs = StemLevelsStore(server: "http://tv.local:9797", profile: "8", defaults: defaults)
        let elsewhere = StemLevelsStore(server: "http://other.local:9797", profile: "7", defaults: defaults)
        var levels = StemLevels()
        levels.setVocals(0.35)
        levels.setStem("drums", 0.5)
        levels.toggleSing()
        mine.save(levels)
        let back = mine.load()
        XCTAssertEqual(back.vocals, 0.35)
        XCTAssertEqual(back.stems, ["drums": 0.5])
        XCTAssertFalse(back.sing)
        XCTAssertEqual(theirs.load(), StemLevels())
        XCTAssertEqual(elsewhere.load(), StemLevels())
        levels.reset()
        mine.save(levels)
        XCTAssertEqual(mine.load(), StemLevels())
    }

    // MARK: What to do next

    func testOpensAsksPreparesThenLoads() {
        var machine = KaraokeMachine()
        XCTAssertEqual(machine.open(song: 12), [.prepare(after: 0)])
        XCTAssertEqual(machine.phase, .asked)
        XCTAssertEqual(machine.open(song: 12), [], "asked once for a song")
        XCTAssertEqual(machine.answered(KaraokeStatus(state: "preparing", progress: 40, pollSec: 3)), [.poll(after: 3)])
        XCTAssertEqual(machine.phase, .preparing(progress: 40))
        XCTAssertEqual(machine.answered(blend(improving: true, pollSec: 3)), [.load(version: "q1"), .poll(after: 3)])
        XCTAssertEqual(machine.phase, .ready(quality: "approximate", version: "q1"))
        XCTAssertTrue(machine.improving)
        XCTAssertEqual(machine.progress, 40)
    }

    func testABetterVersionIsSwappedInOnceItsVersionChanges() {
        var machine = KaraokeMachine()
        _ = machine.open(song: 12)
        _ = machine.answered(blend(improving: true, pollSec: 3))
        // The same version again: keep asking, load nothing.
        XCTAssertEqual(machine.answered(blend(improving: true, pollSec: 3)), [.poll(after: 3)])
        XCTAssertEqual(machine.answered(parts(version: "2c3d")), [.swap(version: "2c3d")])
        XCTAssertEqual(machine.phase, .ready(quality: "stems", version: "2c3d"))
        XCTAssertFalse(machine.improving)
        XCTAssertEqual(machine.status?.mix, "parts")
        // Nothing more is on its way, so nothing more is asked.
        XCTAssertEqual(machine.answered(parts(version: "2c3d")), [])
    }

    func testReadyAndNotImprovingStopsAsking() {
        var machine = KaraokeMachine()
        _ = machine.open(song: 12)
        XCTAssertEqual(machine.answered(parts(pollSec: 3)), [.load(version: "1a2b")])
    }

    func testUnavailableSaysWhyAndStopsWhatWasPlaying() {
        var machine = KaraokeMachine()
        _ = machine.open(song: 12)
        XCTAssertEqual(machine.answered(KaraokeStatus(state: "unavailable", reason: "mono", message: "This song is in mono.")), [])
        XCTAssertEqual(machine.phase, .unavailable(message: "This song is in mono."))
        // Busy: the server says when to ask again.
        XCTAssertEqual(machine.answered(KaraokeStatus(state: "unavailable", reason: "busy", pollSec: 10)), [.poll(after: 10)])
        XCTAssertEqual(machine.phase, .unavailable(message: KaraokeMachine.noWords))
        XCTAssertEqual(machine.answered(parts()), [.load(version: "1a2b")])
        XCTAssertEqual(machine.answered(KaraokeStatus(state: "unavailable", message: "Turned off.")), [.stop])
        XCTAssertNil(machine.status)
        // A state nobody knows, and parts that can't be mixed, are both "not available".
        XCTAssertEqual(machine.answered(KaraokeStatus(state: "later")), [])
        XCTAssertEqual(machine.phase, .unavailable(message: KaraokeMachine.noWords))
        _ = machine.answered(KaraokeStatus(state: "ready", mix: "parts", stems: [stem("vocals", "vocals")], version: "x"))
        XCTAssertEqual(machine.phase, .unavailable(message: KaraokeMachine.noWords))
    }

    func testANetworkErrorKeepsTheStateAndWaitsLongerEachTime() {
        var machine = KaraokeMachine()
        _ = machine.open(song: 12)
        // The first ask itself failed: ask again, later.
        XCTAssertEqual(machine.networkFailed(), [.prepare(after: 6)])
        XCTAssertEqual(machine.phase, .asked)
        _ = machine.answered(blend(improving: true, pollSec: 3))
        XCTAssertEqual(machine.networkFailed(), [.poll(after: 6)])
        XCTAssertEqual(machine.networkFailed(), [.poll(after: 12)])
        XCTAssertEqual(machine.networkFailed(), [.poll(after: 24)])
        XCTAssertEqual(machine.networkFailed(), [.poll(after: 30)])
        XCTAssertEqual(machine.networkFailed(), [.poll(after: 30)])
        XCTAssertEqual(machine.phase, .ready(quality: "approximate", version: "q1"))
        XCTAssertEqual(machine.status?.version, "q1")
        // An answer starts the count again.
        XCTAssertEqual(machine.answered(blend(improving: true, pollSec: 3)), [.poll(after: 3)])
        XCTAssertEqual(machine.networkFailed(), [.poll(after: 6)])
        XCTAssertEqual(KaraokeMachine.backoff(failures: 0, base: 0), 1)
        XCTAssertEqual(KaraokeMachine.backoff(failures: 99, base: 3), 30)
    }

    func testAPartThatWillNotPlayFallsBackForTheRestOfTheSong() {
        var machine = KaraokeMachine()
        _ = machine.open(song: 12)
        _ = machine.answered(parts(improving: true, pollSec: 3))
        XCTAssertEqual(machine.stemsFailed(), [.stop])
        XCTAssertEqual(machine.phase, .fallback(message: KaraokeMachine.failedWords))
        XCTAssertEqual(machine.answered(parts(version: "9")), [])
        XCTAssertEqual(machine.networkFailed(), [])
        XCTAssertEqual(machine.phase, .fallback(message: KaraokeMachine.failedWords))
        XCTAssertEqual(machine.stemsFailed("Too big."), [.stop])
        XCTAssertEqual(machine.phase, .fallback(message: "Too big."))
    }

    func testAnotherSongStartsAgain() {
        var machine = KaraokeMachine()
        _ = machine.open(song: 12)
        _ = machine.answered(parts())
        XCTAssertEqual(machine.open(song: 13), [.stop, .prepare(after: 0)])
        XCTAssertEqual(machine.phase, .asked)
        XCTAssertNil(machine.status)
        XCTAssertEqual(machine.song, 13)
        XCTAssertEqual(machine.reset(), [.stop])
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.reset(), [])
        // Nothing is open, so a late answer does nothing.
        XCTAssertEqual(machine.answered(parts()), [])
        XCTAssertEqual(machine.networkFailed(), [])
        XCTAssertEqual(machine.stemsFailed(), [])
    }

    func testPreparingAgainWhilePlayingKeepsPlaying() {
        var machine = KaraokeMachine()
        _ = machine.open(song: 12)
        _ = machine.answered(blend())
        XCTAssertEqual(machine.answered(KaraokeStatus(state: "preparing", progress: 10, pollSec: 3)), [.poll(after: 3)])
        XCTAssertEqual(machine.phase, .ready(quality: "approximate", version: "q1"))
        XCTAssertTrue(machine.improving)
        XCTAssertEqual(machine.progress, 10)
    }
}
