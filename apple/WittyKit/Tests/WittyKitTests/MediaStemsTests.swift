// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class MediaStemsTests: XCTestCase {
    private func stem(_ name: String, mime: String = "audio/flac", approximate: Bool? = nil, multitrack: Bool? = nil) -> Stem {
        Stem(name: name, url: "/api/media/9/stems/\(name)", mime: mime, multitrack: multitrack, approximate: approximate)
    }

    func testTheServersAnswerIsRead() throws {
        let read = try JSONDecoder().decode(StemList.self, from: Data(#"""
        {"names":["vocals","instrumental","drums","bass","other"],
         "separation":{"approximate":{"available":true,"note":"Approximate: made by cancelling what the left and right channels share."},
                       "external":{"available":false,"reason":"not-configured"}},
         "stems":[{"name":"instrumental","url":"/api/media/9/stems/instrumental","mime":"audio/mp4","size":412345,"source":"approximate","approximate":true}]}
        """#.utf8))
        XCTAssertEqual(read.stems?.first?.approximate, true)
        XCTAssertEqual(read.separation?.external?.reason, "not-configured")
        XCTAssertTrue(StemOffer.separatorWords(read.separation?.external).hasPrefix("No stem separator is set up"))
    }

    func testAVoiceWithItsMusicIsTheRealThing() {
        let plan = StemPlan.plan([stem("vocals"), stem("instrumental")])
        XCTAssertEqual(plan?.mode, .parts)
        XCTAssertEqual(plan?.parts.map(\.name), ["vocals", "instrumental"])
        XCTAssertEqual(plan?.approximate, false)
        let pieces = StemPlan.plan([stem("drums"), stem("vocals"), stem("bass"), stem("other")])
        XCTAssertEqual(pieces?.mode, .parts)
        XCTAssertEqual(pieces?.parts.map(\.name), ["vocals", "drums", "bass", "other"])
        let both = StemPlan.plan([stem("vocals"), stem("instrumental"), stem("drums"), stem("bass")])
        XCTAssertEqual(both?.backing.map(\.name), ["instrumental"], "one file to fetch instead of three")
        let guess = StemPlan.plan([stem("vocals"), stem("instrumental", approximate: true), stem("drums"), stem("bass"), stem("other")])
        XCTAssertEqual(guess?.backing.map(\.name), ["drums", "bass", "other"], "real pieces beat an approximate instrumental")
    }

    func testTheMusicAloneIsFadedAgainstTheSong() {
        let plan = StemPlan.plan([stem("instrumental", mime: "audio/mp4", approximate: true)])
        XCTAssertEqual(plan?.mode, .blend)
        XCTAssertEqual(plan?.approximate, true)
        XCTAssertEqual(plan?.note, "This karaoke version is approximate: the voice is quieter, not gone, and the music is mono.")
        XCTAssertEqual(StemPlan.plan([stem("instrumental")])?.approximate, false)
    }

    func testWhatCantBeUsedIsLeftOutAndSaid() {
        XCTAssertNil(StemPlan.plan([]))
        XCTAssertNil(StemPlan.plan([stem("vocals")]), "a voice with nothing to put under it is no karaoke")
        XCTAssertNil(StemPlan.plan([stem("drums"), stem("bass")]))
        XCTAssertNil(StemPlan.plan([stem("vocals", mime: "audio/ogg"), stem("instrumental", mime: "audio/webm")]), "neither can be decoded here")
        let mixed = StemPlan.plan([stem("vocals", mime: "audio/ogg"), stem("instrumental", mime: "audio/wav")])
        XCTAssertEqual(mixed?.mode, .blend, "the Ogg voice can't be played, so the instrumental is faded against the song")
        XCTAssertEqual(mixed?.unplayable, ["vocals"])
        for mime in ["audio/flac", "audio/wav", "audio/mpeg", "audio/mp4", "audio/aac", "AUDIO/MP4"] { XCTAssertTrue(StemPlan.playable(mime: mime), mime) }
        for mime in ["audio/ogg", "audio/webm", "application/octet-stream", ""] { XCTAssertFalse(StemPlan.playable(mime: mime), mime) }
        XCTAssertFalse(StemPlan.playable(mime: nil))
    }

    func testAFileHoldingEveryPartIsUsedWhenThereAreNoSeparateOnes() {
        let plan = StemPlan.plan([stem("multitrack", mime: "audio/mp4", multitrack: true)])
        XCTAssertEqual(plan?.mode, .multitrack)
        XCTAssertEqual(plan?.parts.map(\.name), ["multitrack"])
        XCTAssertEqual(StemPlan.plan([stem("multitrack", mime: "audio/mp4", multitrack: true), stem("vocals"), stem("instrumental")])?.mode, .parts)
        XCTAssertEqual(StemPlan.plan([stem("multitrack", mime: "audio/mp4", multitrack: true), stem("instrumental", approximate: true)])?.mode, .multitrack)
    }

    func testTheVoiceMovesAndTheMusicStays() {
        XCTAssertEqual(StemMix.levels(.parts, voice: 0), StemMix.Levels(vocals: 0, backing: 1, song: 0))
        XCTAssertEqual(StemMix.levels(.parts, voice: 1), StemMix.Levels(vocals: 1, backing: 1, song: 0))
        XCTAssertEqual(StemMix.levels(.parts, voice: 0.5), StemMix.Levels(vocals: 0.25, backing: 1, song: 0))
        XCTAssertEqual(StemMix.levels(.multitrack, voice: 0.5).backing, 1)
        XCTAssertEqual(StemMix.levels(.parts, voice: 7).vocals, 1)
        XCTAssertEqual(StemMix.levels(.parts, voice: -1).vocals, 0)
        XCTAssertEqual(StemMix.levels(.parts, voice: .nan).vocals, 1, "an odd level is the recording")
    }

    func testFadingTheSongAgainstItsInstrumentalKeepsTheMusicLevel() {
        XCTAssertEqual(StemMix.levels(.blend, voice: 0), StemMix.Levels(vocals: 0, backing: 1, song: 0))
        XCTAssertEqual(StemMix.levels(.blend, voice: 1), StemMix.Levels(vocals: 0, backing: 0, song: 1))
        for voice in stride(from: 0.0, through: 1.0, by: 0.1) {
            let levels = StemMix.levels(.blend, voice: voice)
            XCTAssertEqual(levels.backing + levels.song, 1, accuracy: 0.0001, "the music, which both carry, adds up to itself at \(voice)")
        }
    }

    func testTheSliderIsSaidInWords() {
        XCTAssertEqual(StemMix.words(0), "Voice off")
        XCTAssertEqual(StemMix.words(0.4), "Voice 40%")
        XCTAssertEqual(StemMix.words(1), "Voice as recorded")
    }

    func testThePartsFollowTheSong() {
        typealias Clock = StemFollow.Clock
        XCTAssertEqual(StemFollow.order(song: Clock(time: 10, rate: 1), parts: Clock(time: 0, rate: 0), partsReady: false), .nothing, "not loaded yet")
        XCTAssertEqual(StemFollow.order(song: Clock(time: 10, rate: 1), parts: Clock(time: 0, rate: 0), partsReady: true), .lock(time: 10, rate: 1), "the song plays: start with it")
        XCTAssertEqual(StemFollow.order(song: Clock(time: 10, rate: 1), parts: Clock(time: 10.01, rate: 1), partsReady: true), .nothing, "together")
        XCTAssertEqual(StemFollow.order(song: Clock(time: 10, rate: 1), parts: Clock(time: 10.2, rate: 1), partsReady: true), .lock(time: 10, rate: 1), "drifted, or the song was seeked")
        XCTAssertEqual(StemFollow.order(song: Clock(time: 10, rate: 1.5), parts: Clock(time: 10, rate: 1), partsReady: true), .lock(time: 10, rate: 1.5), "the speed changed")
        XCTAssertEqual(StemFollow.order(song: Clock(time: 10, rate: 0), parts: Clock(time: 10.02, rate: 1), partsReady: true), .hold(at: 10), "the song paused")
        XCTAssertEqual(StemFollow.order(song: Clock(time: 30, rate: 0), parts: Clock(time: 10, rate: 0), partsReady: true), .hold(at: 30), "seeked while paused")
        XCTAssertEqual(StemFollow.order(song: Clock(time: 10, rate: 0), parts: Clock(time: 10.1, rate: 0), partsReady: true), .nothing)
        XCTAssertEqual(StemFollow.order(song: Clock(time: .nan, rate: 1), parts: Clock(time: 10, rate: 1), partsReady: true), .nothing)
    }

    func testASongWithoutStemsIsOfferedAKaraokeVersionWhenTheServerCanMakeOne() throws {
        func list(_ json: String) throws -> StemList { try JSONDecoder().decode(StemList.self, from: Data(json.utf8)) }
        let can = try list(#"{"stems":[],"separation":{"approximate":{"available":true},"external":{"available":false,"reason":"not-configured"}}}"#)
        XCTAssertEqual(StemOffer.of(can, plan: nil, featured: true), .make)
        XCTAssertEqual(StemOffer.of(can, plan: nil, featured: false), StemOffer.none, "an older server doesn't list the feature")
        XCTAssertEqual(StemOffer.of(can, plan: StemPlan.plan([stem("instrumental")]), featured: true), StemOffer.none, "it has one")
        let making = try list(#"{"stems":[],"separation":{"approximate":{"available":true,"task":"t1-2"}}}"#)
        XCTAssertEqual(StemOffer.of(making, plan: nil, featured: true), .making(task: "t1-2"))
        let cannot = try list(#"{"stems":[],"separation":{"approximate":{"available":false,"reason":"no-ffmpeg"}}}"#)
        XCTAssertEqual(StemOffer.of(cannot, plan: nil, featured: true), StemOffer.none)
        XCTAssertEqual(StemOffer.of(nil, plan: nil, featured: true), StemOffer.none)
    }
}
