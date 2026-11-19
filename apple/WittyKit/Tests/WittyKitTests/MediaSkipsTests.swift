// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class MediaSkipsTests: XCTestCase {
    private let markers = SkipMarkers(intro: SkipRange(startSec: 10, endSec: 25), recap: SkipRange(startSec: 0, endSec: 10),
                                      credits: SkipRange(startSec: 100, endSec: 120), commercials: [SkipRange(startSec: 40, endSec: 50)])

    func testTheServersAnswerIsReadWithItsNulls() throws {
        let read = try JSONDecoder().decode(SkipMarkers.self, from: Data(#"""
        {"intro":null,"recap":{"startSec":0,"endSec":10},"credits":{"startSec":120,"endSec":150},"commercials":[],
         "source":"chapters","sources":{"credits":"chapters","recap":"chapters"}}
        """#.utf8))
        XCTAssertNil(read.intro)
        XCTAssertEqual(read.recap, SkipRange(startSec: 0, endSec: 10))
        XCTAssertEqual(read.sources?["credits"], "chapters")
        XCTAssertFalse(read.isEmpty)
        XCTAssertTrue(SkipMarkers(intro: nil).isEmpty)
        XCTAssertEqual(SkipMarkers(intro: try JSONDecoder().decode(Intro.self, from: Data(#"{"startSec":3,"endSec":30}"#.utf8))).intro?.endSec, 30)
    }

    func testEachPartOffersItsOwnButtonWhileItPlays() {
        func offer(_ at: Double) -> SkipOffer? { SkipRules.offer(markers, at: at, duration: 150, hasNext: false) }
        XCTAssertEqual(offer(2)?.label, "Skip recap")
        XCTAssertEqual(offer(2)?.to, 10)
        XCTAssertEqual(offer(12)?.label, "Skip intro")
        XCTAssertEqual(offer(45)?.label, "Skip adverts")
        XCTAssertEqual(offer(45)?.to, 50)
        XCTAssertEqual(offer(101)?.label, "Skip credits")
        XCTAssertNil(offer(30), "between the parts there's nothing to skip")
        XCTAssertNil(offer(24.5), "the last second of a part isn't worth a button")
        XCTAssertNil(offer(.nan))
        XCTAssertNil(SkipRules.offer(nil, at: 12, duration: 150, hasNext: false))
    }

    func testCreditsThatRunToTheEndOfferTheNextEpisodeOrNothing() {
        let toEnd = SkipMarkers(credits: SkipRange(startSec: 100, endSec: 150))
        XCTAssertNil(SkipRules.offer(toEnd, at: 105, duration: 150, hasNext: false), "nothing follows them, and nothing is next")
        let next = SkipRules.offer(toEnd, at: 105, duration: 150, hasNext: true)
        XCTAssertEqual(next?.label, "Next episode")
        XCTAssertEqual(next?.next, true)
        XCTAssertNil(SkipRules.offer(toEnd, at: 125, duration: 150, hasNext: true), "in the last half minute the player's own countdown takes over")
        XCTAssertNil(SkipRules.offer(SkipMarkers(credits: SkipRange(startSec: 100, endSec: 120)), at: 105, duration: 0, hasNext: true),
                     "with no length known, where the credits end means nothing")
    }

    func testARangeThatMakesNoSenseIsNeverOffered() {
        let odd = SkipMarkers(intro: SkipRange(startSec: 30, endSec: 10), recap: SkipRange(startSec: -5, endSec: 4))
        XCTAssertNil(SkipRules.offer(odd, at: 2, duration: 100, hasNext: false))
        XCTAssertNil(SkipRules.offer(odd, at: 20, duration: 100, hasNext: false))
    }

    func testAPartIsSkippedByItselfOnceWhenTheFilmPlaysIntoIt() {
        var tracker = SkipTracker()
        let prefs = SkipPrefs(intro: true)
        func tick(_ at: Double, playing: Bool = true) -> Double? {
            tracker.tick(now: at, rate: 1, playing: playing, offer: SkipRules.offer(markers, at: at, duration: 150, hasNext: false), prefs: prefs)
        }
        XCTAssertNil(tick(8), "the recap isn't one this device skips")
        XCTAssertNil(tick(9))
        XCTAssertEqual(tick(10.2), 25, "played into the intro")
        XCTAssertEqual(tracker.notice, SkipNotice(kind: .intro, from: 10.2))
        XCTAssertEqual(tracker.notice?.words, "Skipped the intro")
        XCTAssertNil(tick(11.2), "the player still says the old place for a moment: not a reason to do anything")
        XCTAssertNil(tick(25.3))
        XCTAssertNil(tick(26.3))
    }

    func testUndoGoesBackAndThePartThenPlays() {
        var tracker = SkipTracker()
        let prefs = SkipPrefs(intro: true)
        func tick(_ at: Double) -> Double? {
            tracker.tick(now: at, rate: 1, playing: true, offer: SkipRules.offer(markers, at: at, duration: 150, hasNext: false), prefs: prefs)
        }
        _ = tick(9.5)
        XCTAssertEqual(tick(10.5), 25)
        XCTAssertEqual(tracker.undo(), 10.5)
        XCTAssertNil(tracker.notice)
        XCTAssertNil(tick(10.6))
        XCTAssertNil(tick(11.6), "after Undo the intro plays through")
        XCTAssertNil(tracker.undo(), "there's nothing left to undo")
    }

    func testSeekingIntoAPartLeavesItAloneForGood() {
        var tracker = SkipTracker()
        let prefs = SkipPrefs(intro: true, recap: true, credits: true, adverts: true)
        func tick(_ at: Double) -> Double? {
            tracker.tick(now: at, rate: 1, playing: true, offer: SkipRules.offer(markers, at: at, duration: 150, hasNext: false), prefs: prefs)
        }
        XCTAssertNil(tick(30))
        tracker.seeked()
        XCTAssertNil(tick(12), "someone went back to the intro: they want to see it")
        XCTAssertNil(tick(13))
        // Back before it and playing through again: still theirs.
        tracker.seeked()
        XCTAssertNil(tick(9.9), "seeked into the recap's last moment")
        XCTAssertNil(tick(10.9))
        // A jump nobody announced (another device's remote) counts the same.
        XCTAssertNil(tick(44), "a jump into the adverts")
        XCTAssertNil(tick(45))
        // Further on, playing into the credits still skips them.
        tracker.seeked()
        XCTAssertNil(tick(98))
        XCTAssertNil(tick(99))
        XCTAssertEqual(tick(100.1), 120)
    }

    func testOpeningInsideAPartSkipsItAndPausedNothingIs() {
        var resumed = SkipTracker()
        XCTAssertEqual(resumed.tick(now: 3, rate: 1, playing: true, offer: SkipRules.offer(markers, at: 3, duration: 150, hasNext: false),
                                    prefs: SkipPrefs(recap: true)), 10, "a video that opens in the recap")
        var paused = SkipTracker()
        XCTAssertNil(paused.tick(now: 3, rate: 1, playing: false, offer: SkipRules.offer(markers, at: 3, duration: 150, hasNext: false),
                                 prefs: SkipPrefs(recap: true)))
        XCTAssertEqual(paused.tick(now: 3, rate: 1, playing: true, offer: SkipRules.offer(markers, at: 3, duration: 150, hasNext: false),
                                   prefs: SkipPrefs(recap: true)), 10, "once it plays")
    }

    func testOneSkipCanLandInTheNextPartAndSkipThatToo() {
        var tracker = SkipTracker()
        let prefs = SkipPrefs(intro: true, recap: true)
        func tick(_ at: Double) -> Double? {
            tracker.tick(now: at, rate: 1, playing: true, offer: SkipRules.offer(markers, at: at, duration: 150, hasNext: false), prefs: prefs)
        }
        XCTAssertEqual(tick(1), 10)
        XCTAssertNil(tick(2), "still on its way")
        XCTAssertEqual(tick(10.3), 25, "the recap ends where the intro starts")
        XCTAssertEqual(tracker.notice?.kind, .intro)
        XCTAssertNil(tick(25.4))
    }

    func testFastPlayingStillCountsAsPlayingAndNextEpisodeIsNeverPressed() {
        var fast = SkipTracker()
        let prefs = SkipPrefs(intro: true, credits: true)
        XCTAssertNil(fast.tick(now: 6, rate: 3, playing: true, offer: nil, prefs: prefs))
        XCTAssertEqual(fast.tick(now: 12, rate: 3, playing: true, offer: SkipRules.offer(SkipMarkers(intro: SkipRange(startSec: 10, endSec: 25)), at: 12, duration: 150, hasNext: false), prefs: prefs), 25,
                       "six seconds in one look at three times the speed")
        var end = SkipTracker()
        let toEnd = SkipMarkers(credits: SkipRange(startSec: 100, endSec: 150))
        _ = end.tick(now: 99, rate: 1, playing: true, offer: nil, prefs: prefs)
        XCTAssertNil(end.tick(now: 100.5, rate: 1, playing: true, offer: SkipRules.offer(toEnd, at: 100.5, duration: 150, hasNext: true), prefs: prefs))
        XCTAssertNil(end.notice)
    }

    func testPressingTheButtonSettlesThePart() {
        var tracker = SkipTracker()
        let prefs = SkipPrefs(intro: true)
        let offer = SkipRules.offer(markers, at: 12, duration: 150, hasNext: false)
        tracker.seeked()
        XCTAssertNil(tracker.tick(now: 12, rate: 1, playing: true, offer: offer, prefs: prefs))
        if let offer { tracker.pressed(offer) }
        XCTAssertNil(tracker.notice)
    }

    func testChoicesAreKeptOnTheDeviceAndOffUntilChosen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MediaSkipsTests"))
        defaults.removePersistentDomain(forName: "MediaSkipsTests")
        XCTAssertEqual(SkipPrefs.load(defaults), SkipPrefs())
        XCTAssertFalse(SkipPrefs.load(defaults).skips(.intro))
        XCTAssertTrue(SkipPrefs.load(defaults).fileAuto, "what a file says to skip is followed until turned off")
        var prefs = SkipPrefs()
        prefs.set(.intro, true)
        prefs.set(.commercial, true)
        SkipPrefs.save(prefs, defaults)
        XCTAssertTrue(SkipPrefs.load(defaults).skips(.intro))
        XCTAssertTrue(SkipPrefs.load(defaults).skips(.commercial))
        XCTAssertFalse(SkipPrefs.load(defaults).skips(.credits))
        SkipPrefs.save(SkipPrefs(), defaults)
        XCTAssertNil(defaults.data(forKey: SkipPrefs.key), "nothing chosen leaves nothing behind")
        let odd = try JSONDecoder().decode(SkipPrefs.self, from: Data(#"{"intro":"yes","recap":true,"later":1}"#.utf8))
        XCTAssertEqual(odd, SkipPrefs(recap: true))
    }

    func testAnAdministratorReadsWhereEachPartCameFrom() {
        let found = SkipMarkers(intro: SkipRange(startSec: 5, endSec: 25), credits: SkipRange(startSec: 82, endSec: 100),
                                sources: ["intro": "detected", "credits": "skip.json"])
        XCTAssertEqual(SkipRules.summary(found), ["Intro 0:05 to 0:25, found by comparing episodes", "Credits 1:22 to 1:40, from a .skip.json beside the file"])
        XCTAssertEqual(SkipRules.summary(nil), [])
        XCTAssertEqual(SkipKind.allCases.map(\.settingName), ["Recaps", "Intros", "Adverts", "Other parts someone named", "Previews", "Credits"])
    }

    /// A 0.8.1 server's answer for a film with a .wittyinfo: every part in `segments`, a preview only marked, a part
    /// someone named that skips itself, and a scene after the credits.
    private let wittyinfo = #"""
    {"intro":{"startSec":30,"endSec":95},"recap":null,"credits":{"startSec":5400,"endSec":5600},"commercials":[],
     "preview":{"startSec":5650,"endSec":5700,"action":"mark"},"postCredits":{"startSec":5580,"endSec":5640},
     "custom":[{"startSec":2000,"endSec":2100,"label":"Dream sequence","action":"auto"}],
     "segments":[{"kind":"intro","startSec":30,"endSec":95,"action":"button","source":"wittyinfo"},
      {"kind":"custom","startSec":2000,"endSec":2100,"label":"Dream sequence","action":"auto","source":"wittyinfo"},
      {"kind":"credits","startSec":5400,"endSec":5600,"action":"button","source":"wittyinfo"},
      {"kind":"postcredits","startSec":5580,"endSec":5640,"action":"button","source":"wittyinfo"},
      {"kind":"preview","startSec":5650,"endSec":5700,"action":"mark","source":"wittyinfo"},
      {"kind":"chapter-art","startSec":1,"endSec":2,"action":"button","source":"wittyinfo"}],
     "source":"wittyinfo","sources":{"intro":"wittyinfo","credits":"wittyinfo"}}
    """#

    func testAWittyinfosPartsComeFromItsSegments() throws {
        let read = try JSONDecoder().decode(SkipMarkers.self, from: Data(wittyinfo.utf8))
        XCTAssertEqual(read.segments?.count, 6)
        XCTAssertEqual(SkipRules.parts(read).map(\.kind), [.intro, .custom, .credits], "a scene after the credits, a part only marked and an unknown kind have no button")
        let named = SkipRules.offer(read, at: 2010, duration: 5700, hasNext: false)
        XCTAssertEqual(named?.label, "Skip dream sequence")
        XCTAssertEqual(named?.skipped, "Skipped dream sequence")
        XCTAssertEqual(named?.fileAuto, true)
        XCTAssertNil(SkipRules.offer(read, at: 5660, duration: 5700, hasNext: false), "a preview that's only marked")
    }

    func testCreditsStopWhereASceneAfterThemStarts() throws {
        let read = try JSONDecoder().decode(SkipMarkers.self, from: Data(wittyinfo.utf8))
        let credits = SkipRules.offer(read, at: 5450, duration: 5700, hasNext: true)
        XCTAssertEqual(credits?.label, "Skip credits", "not Next episode: there's a scene to see")
        XCTAssertEqual(credits?.to, 5580)
        XCTAssertNil(SkipRules.offer(read, at: 5590, duration: 5700, hasNext: true))
    }

    func testTheOlderFieldsCarryTheNewKindsToo() {
        let fields = SkipMarkers(credits: SkipRange(startSec: 500, endSec: 600, action: "mark"), preview: SkipRange(startSec: 100, endSec: 160),
                                 custom: [SkipRange(startSec: 300, endSec: 360, label: "Opening song")])
        XCTAssertEqual(SkipRules.offer(fields, at: 310, duration: 900, hasNext: false)?.label, "Skip opening song")
        XCTAssertEqual(SkipRules.offer(fields, at: 110, duration: 900, hasNext: false)?.label, "Skip preview")
        XCTAssertNil(SkipRules.offer(fields, at: 510, duration: 900, hasNext: false))
        let long = SkipOffer(kind: .custom, from: 0, to: 10, name: String(repeating: "Ab", count: 30))
        XCTAssertEqual(long.label, "Skip a" + String(String(repeating: "Ab", count: 30).dropFirst().prefix(38)) + "…")
        XCTAssertEqual(SkipOffer(kind: .custom, from: 0, to: 10).label, "Skip this part")
    }

    func testAFileSaysWhatSkipsItselfUnlessTurnedOff() throws {
        let read = try JSONDecoder().decode(SkipMarkers.self, from: Data(wittyinfo.utf8))
        let named = try XCTUnwrap(SkipRules.offer(read, at: 2010, duration: 5700, hasNext: false))
        let intro = try XCTUnwrap(SkipRules.offer(read, at: 40, duration: 5700, hasNext: false))
        XCTAssertTrue(SkipPrefs().skips(named))
        XCTAssertFalse(SkipPrefs().skips(intro))
        XCTAssertFalse(SkipPrefs(fileAuto: false).skips(named))
        XCTAssertFalse(SkipPrefs.none.skips(named))
        XCTAssertTrue(SkipPrefs(custom: true, fileAuto: false).skips(named))
        var tracker = SkipTracker()
        XCTAssertEqual(tracker.tick(now: 2010, rate: 1, playing: true, offer: named, prefs: SkipPrefs()), 2100)
        XCTAssertEqual(tracker.notice?.words, "Skipped dream sequence")
        let saved = try JSONDecoder().decode(SkipPrefs.self, from: Data(#"{"intro":true}"#.utf8))
        XCTAssertTrue(saved.fileAuto, "a set saved before this follows the file")
    }
}
