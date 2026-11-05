import XCTest
@testable import WittyKit

final class SoundLookTests: XCTestCase {
    func testSavedSoundSettingsArePutRightAndTheVoiceAndKeyAreNotKept() throws {
        let saved = try JSONDecoder().decode(SoundSettings.self, from: Data(#"""
        {"volume":3,"eqOn":true,"eqGains":[20,0,0,0,0,0,0,0,0,-40],"preamp":-30,"replayGain":"loud","gapless":false,"crossfade":99,"vocalCut":1,"keyShift":4}
        """#.utf8))
        XCTAssertEqual(saved.volume, 1)
        XCTAssertEqual(saved.eqGains.first, 12)
        XCTAssertEqual(saved.eqGains.last, -12)
        XCTAssertEqual(saved.preamp, -12)
        XCTAssertEqual(saved.replayGain, .off)
        XCTAssertFalse(saved.gapless)
        XCTAssertEqual(saved.crossfade, 12)
        XCTAssertEqual(saved.vocalCut, 0)
        XCTAssertEqual(saved.keyShift, 0)
        // A short list of gains is from somewhere else: the flat ones stand.
        let short = try JSONDecoder().decode(SoundSettings.self, from: Data(#"{"eqGains":[1,2]}"#.utf8))
        XCTAssertEqual(short.eqGains, Equaliser.presets[0].gains)
        XCTAssertTrue(short.gapless)

        let defaults = UserDefaults(suiteName: "SoundLookTests")!
        defaults.removePersistentDomain(forName: "SoundLookTests")
        var mine = SoundSettings()
        mine.eqOn = true
        mine.keyShift = 3
        SoundStore(defaults: defaults).save(mine)
        let back = SoundStore(defaults: defaults).load()
        XCTAssertTrue(back.eqOn)
        XCTAssertEqual(back.keyShift, 0)
    }

    func testCrossfadeLeavesAnAlbumAloneUnlessAsked() {
        var sound = SoundSettings()
        XCTAssertEqual(sound.fade(from: "A", to: "B"), 0)
        sound.crossfade = 6
        XCTAssertEqual(sound.fade(from: "A", to: "B"), 6)
        XCTAssertEqual(sound.fade(from: "A", to: "A"), 0)
        sound.crossfadeAlbums = true
        XCTAssertEqual(sound.fade(from: "A", to: "A"), 6)
        XCTAssertEqual(SoundSettings.crossfades.map(SoundSettings.crossfadeWords), ["Off", "2 seconds", "4 seconds", "6 seconds", "8 seconds", "12 seconds"])
        XCTAssertEqual(Equaliser.frequencies.map(Equaliser.hertz), ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"])
        XCTAssertEqual(Equaliser.decibels(3), "+3")
        XCTAssertEqual(Equaliser.decibels(-2), "-2")
    }

    func testLevelingNeverClips() {
        let tagged = Loudness(trackDb: -6, albumDb: -4, trackPeak: 0.5, albumPeak: nil)
        XCTAssertEqual(tagged.gain(.off), 0)
        XCTAssertEqual(tagged.gain(.track), -6)
        XCTAssertEqual(tagged.gain(.album), -4)
        // +8 asked for, but the peak leaves room for only about 6.
        let quiet = Loudness(trackDb: 8, albumDb: nil, trackPeak: 0.5, albumPeak: nil)
        XCTAssertEqual(quiet.gain(.track), -20 * log10(0.5), accuracy: 0.001)
        XCTAssertEqual(Loudness(trackDb: nil, albumDb: nil, trackPeak: nil, albumPeak: nil).gain(.album), 0)
    }

    func testKaraokeFillsWordsAndCountsIn() {
        let line = LyricLine(t: 10_000, text: "la la la")
        let words = Karaoke.words(line, next: 14_000)
        XCTAssertEqual(words.map(\.text), ["la ", "la ", "la"])
        XCTAssertEqual(words.first?.from, 10_000)
        // Short lines are sung over at least 1.2 s.
        XCTAssertEqual(words.last!.to, 11_200, accuracy: 0.01)
        XCTAssertEqual(Karaoke.fill(words[0], at: 9_000), 0)
        XCTAssertEqual(Karaoke.fill(words[0], at: 20_000), 1)
        let timed = LyricLine(t: 0, text: "a b", words: [LyricWord(t: 0, text: "a "), LyricWord(t: 400, text: "b")])
        XCTAssertEqual(Karaoke.words(timed, next: 3_000).map(\.to), [400, 1_900])

        let lines = [LyricLine(t: 1_000, end: 2_000, text: "one"), LyricLine(t: 9_000, text: "two"), LyricLine(t: 10_000, text: "three")]
        XCTAssertEqual(Karaoke.countIn(lines, at: 6_500), 3)
        XCTAssertEqual(Karaoke.countIn(lines, at: 8_100), 1)
        XCTAssertEqual(Karaoke.countIn(lines, at: 9_500), 0)
        XCTAssertEqual(Karaoke.countIn(lines, at: 0), 1)
        XCTAssertEqual(Karaoke.keyWords(2), "Key +2")
        XCTAssertEqual(Karaoke.timingWords(0), "Words on time")
        XCTAssertEqual(Karaoke.timingWords(-300), "Words -0.3 s")
    }

    func testVisualizerChoicesAndLevels() throws {
        let saved = try JSONDecoder().decode(VisualizerPrefs.self, from: Data(#"{"viz":false,"style":"plasma","shuffleEvery":7,"shufflePool":"all"}"#.utf8))
        XCTAssertFalse(saved.viz)
        XCTAssertEqual(saved.nativeStyle, "bars")
        XCTAssertEqual(saved.shuffleEvery, 0)
        XCTAssertEqual(saved.shufflePool, "all")
        XCTAssertTrue(try JSONDecoder().decode(VisualizerPrefs.self, from: Data("{}".utf8)).viz)
        XCTAssertEqual(VisualizerPrefs.shuffleChoices.map(VisualizerPrefs.everyWords),
                       ["Off: stay on this one", "Every 15 seconds", "Every 30 seconds", "Every minute", "Every 2 minutes", "Every 5 minutes", "Every 10 minutes"])
        XCTAssertEqual(VisualizerLevels.bins(0), 2..<2 + max(1, Int(2 * pow(170, 1 / 23.0)) - 2))
        XCTAssertLessThanOrEqual(VisualizerLevels.bins(22).upperBound, 341)
        XCTAssertEqual(VisualizerLevels.level(peak: 0, at: 5), 0)
        XCTAssertEqual(VisualizerLevels.level(peak: 255, at: 0), 1)
    }

    func testTheServersOwnPlayersHaveTheWholeScreen() {
        XCTAssertTrue(WebPlayer.isPlayer(path: "/play/12"))
        XCTAssertTrue(WebPlayer.isPlayer(path: "/cd/4"))
        XCTAssertFalse(WebPlayer.isPlayer(path: "/item/12"))
        XCTAssertFalse(WebPlayer.isPlayer(path: "/playlists"))
        XCTAssertFalse(WebPlayer.isPlayer(path: "/cdn"))
    }

    func testFixingTheWords() throws {
        XCTAssertEqual(LyricFile.stamp(62_500), "01:02.50")
        XCTAssertEqual(LyricFile.lines(" one \n\n two"), ["one", "two"])
        XCTAssertEqual(LyricFile.lrc(times: [1_000, 2_340], lines: ["a", "b"]), "[00:01.00]a\n[00:02.34]b\n")
        let found = try JSONDecoder().decode(FoundLyrics.self, from: Data(#"{"provider":"lrclib","id":"9","title":"T","artist":"A","durationSec":200,"hasSynced":true}"#.utf8))
        XCTAssertEqual(found.facts(songSeconds: 201), "Timed · same length")
        XCTAssertEqual(found.facts(songSeconds: 212), "Timed · 12 s different")
        XCTAssertEqual(found.facts(songSeconds: nil), "Timed")
        let lyrics = try JSONDecoder().decode(Lyrics.self, from: Data(#"{"synced":true,"lines":[{"t":1000,"text":"hi"}],"plain":"hi"}"#.utf8))
        XCTAssertEqual(LyricFile.draft(lyrics), "[00:01.00]hi")
    }
}
