// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// GET /items/{id}/disc/analysis as the server writes it (internal/server/api_discrank.go's discAnalysisView, with
/// library.DiscRank in it), and the words the disc page says from it.
final class DiscRankingTests: XCTestCase {
    /// A Blu-ray an administrator sees: ranked, nothing chosen, editions, a second opinion that differs.
    let bluray = #"""
    {"kind":"bluray","ranked":true,"pending":false,"main":800,"engineMain":800,"chosen":null,
     "rank":{"engine":"wittybluray 0.6.1","main":800,"confidence":0.92,"level":"high",
       "why":"Playlist 00800 is the longest playlist that plays its clips once, in order.",
       "reasons":["It runs 2:14:05, the longest of the disc's playlists","Its chapters are evenly spread"],
       "against":["Another playlist is nearly as long"],"runnerUp":801,
       "versions":[{"kind":"edition","ttn":800,"durationSec":8045,"label":"Theatrical cut","main":true},
                   {"kind":"edition","ttn":801,"durationSec":8645.5,"label":"Director's cut"}],
       "playAll":-1,
       "candidates":[{"ttn":800,"durationSec":8045,"chapters":32,"class":"feature","score":0.92,"reasons":["longest"]},
                     {"ttn":801,"durationSec":8645.5,"chapters":34,"class":"feature","score":0.71}],
       "decoys":3,"hidden":1,"repairs":["MovieObject.bdmv was read from the disc's backup copy"],"repairCount":2,
       "issues":[{"severity":"error","kind":"missing-clip","ttn":802,"what":"A clip it names isn't on the disc"}],"issueCount":1,
       "paddedSectors":0,"readRetries":0,
       "secondOpinion":{"source":"libbluray 1.3.4","agrees":false,"main":801,"differences":["playlist 00801, duration: 2:24:05 here, 2:24:04 there"]},
       "at":1767225600},
     "chosenBy":"","canChoose":true,"protected":false,
     "secondOpinion":{"enabled":true,"available":true,"version":"1.3.4"}}
    """#

    /// A DVD of episodes with a choice made, for someone who isn't an administrator.
    let dvd = #"""
    {"kind":"dvd","ranked":true,"pending":false,"main":2,"engineMain":1,
     "chosen":{"ttn":2,"by":1,"at":1767225600,"was":1},
     "rank":{"engine":"wittydvd 0.4.0","main":1,"confidence":0.41,"level":"","why":"","reasons":[],"runnerUp":-1,
       "feature":{"titles":[1,3],"durationSec":5400,"source":"chain","assembled":true,
                  "segments":[{"vts":1,"pgc":1,"cells":[1,2]}]},
       "episodes":[{"index":1,"ttn":4,"durationSec":1324,"startSec":0},
                   {"index":2,"ttn":1,"durationSec":1330,"startSec":2650,"chapter":5,"part":true}],
       "playAll":1,"candidates":[{"ttn":1,"durationSec":5400,"chapters":12,"class":"playall","score":0.4},
                                  {"ttn":2,"durationSec":1324,"chapters":6,"class":"episode","score":0.3}],
       "decoys":0,"hidden":0,"repairCount":0,"issueCount":0,"paddedSectors":7,"readRetries":2,"at":1767225600},
     "canChoose":false,"protected":false}
    """#

    private func decode(_ text: String) throws -> DiscAnalysis { try JSONDecoder().decode(DiscAnalysis.self, from: Data(text.utf8)) }

    func testABlurayAnalysisReadsAsTheServerWritesIt() throws {
        let a = try decode(bluray)
        XCTAssertTrue(a.isBluray)
        XCTAssertTrue(a.ranked)
        XCTAssertFalse(a.pending)
        XCTAssertEqual(a.main, 800)
        XCTAssertNil(a.chosen)
        XCTAssertTrue(a.canChoose)
        XCTAssertEqual(a.secondOpinion?.version, "1.3.4")
        let rk = try XCTUnwrap(a.rank)
        XCTAssertEqual(rk.confidence, 0.92)
        XCTAssertEqual(rk.versions.count, 2)
        XCTAssertEqual(rk.candidates.map(\.ttn), [800, 801])
        XCTAssertEqual(rk.candidates[0].class, "feature")
        XCTAssertEqual(rk.issues.first?.ttn, 802)
        XCTAssertEqual(rk.secondOpinion?.main, 801)
        XCTAssertNil(rk.feature)
        XCTAssertTrue(rk.episodes.isEmpty)
    }

    func testTheWordsForABluray() throws {
        let a = try decode(bluray)
        let rk = try XCTUnwrap(a.rank)
        XCTAssertEqual(DiscRanking.heading(a), "Why this playlist")
        XCTAssertEqual(DiscRanking.name(800, a), "Playlist 00800")
        XCTAssertEqual(DiscRanking.confidence(rk), "High confidence")
        XCTAssertEqual(DiscRanking.sure(rk.confidence), "92% sure")
        XCTAssertEqual(DiscRanking.why(a), "Playlist 00800 is the longest playlist that plays its clips once, in order.")
        XCTAssertNil(DiscRanking.chosenLine(a))
        XCTAssertEqual(DiscRanking.others(a).map(\.ttn), [801])
        XCTAssertEqual(DiscRanking.candidateLabel(DiscRanking.others(a)[0], a), "Playlist 00801 · 2:24:05 · feature")
        XCTAssertEqual(DiscRanking.otherVersions(rk).map { DiscRanking.versionLabel($0, a) }, ["Director's cut"])
        XCTAssertTrue(DiscRanking.offersSecondOpinion(a))
        let parts = DiscRanking.details(a)
        XCTAssertEqual(parts.map(\.heading), ["For Playlist 00800", "Against it", "", "The copy", "Second opinion", ""])
        XCTAssertEqual(parts[2].lines, ["3 playlists look like decoys and aren\u{2019}t listed. 1 more aren\u{2019}t shown."])
        XCTAssertEqual(parts[3].lines, ["MovieObject.bdmv was read from the disc's backup copy", "and 1 more mended",
                                         "Won\u{2019}t play: A clip it names isn't on the disc (Playlist 00802)"])
        XCTAssertEqual(parts[4].lines.first, "libbluray 1.3.4 reads it differently and picks Playlist 00801.")
        XCTAssertEqual(parts.last?.lines, ["wittybluray 0.6.1"])
    }

    func testTheWordsForADVDWithAChoiceAndEpisodes() throws {
        let a = try decode(dvd)
        let rk = try XCTUnwrap(a.rank)
        XCTAssertEqual(DiscRanking.heading(a), "Why this title")
        XCTAssertEqual(DiscRanking.chosenLine(a), "Title 2 was chosen as this disc\u{2019}s film; the engine picks Title 1.")
        XCTAssertEqual(DiscRanking.confidence(rk), "41% sure")
        XCTAssertEqual(DiscRanking.why(a), "The engine picked Title 1.")
        XCTAssertEqual(DiscRanking.clearMessage(a), "Play will play Title 1 again, for everyone.")
        XCTAssertEqual(rk.feature?.titles, [1, 3])
        XCTAssertEqual(rk.episodes.map(DiscRanking.episodeLabel), ["Episode 1", "Episode 2"])
        XCTAssertEqual(DiscRanking.episodeDetail(rk.episodes[0], a), "22:04 · title 4")
        XCTAssertEqual(DiscRanking.episodeDetail(rk.episodes[1], a), "22:10 · from 44:10 of title 1")
        XCTAssertEqual(DiscRanking.episodePath(9, rk.episodes[1]), "/play/9?mode=title&episode=2")
        XCTAssertFalse(DiscRanking.offersSecondOpinion(a))
        let parts = DiscRanking.details(a)
        XCTAssertEqual(parts.first?.lines, ["The film runs through titles 1, 3 (1:30:00), which play here as one."])
        XCTAssertEqual(parts.first { $0.heading == "The copy" }?.lines,
                       ["7 unreadable sectors were passed over as blank while reading the disc\u{2019}s index."])
    }

    func testPendingUnrankedAndBrokenFieldsStillRead() throws {
        let pending = try decode(#"{"kind":"dvd","ranked":false,"pending":true,"main":-1,"engineMain":-1,"chosen":null,"rank":null,"canChoose":false,"protected":false}"#)
        XCTAssertTrue(pending.pending)
        XCTAssertNil(pending.rank)
        XCTAssertEqual(DiscRanking.why(pending), "")
        XCTAssertTrue(DiscRanking.details(pending).isEmpty)
        XCTAssertTrue(DiscRanking.unrankedLine(pending).contains("longest sensible title"))
        // A field of the wrong kind, an unreadable candidate and fields the app doesn't know yet.
        let odd = try decode(#"{"kind":"bluray","ranked":"yes","main":5,"protected":true,"later":{"x":1},"rank":{"main":5,"confidence":3,"level":"medium","candidates":[{"durationSec":1},{"ttn":5,"durationSec":60}],"versions":[{"ttn":6,"kind":"angle","angle":2,"durationSec":60,"label":" "}]}}"#)
        XCTAssertFalse(odd.ranked)
        XCTAssertTrue(odd.protected)
        XCTAssertEqual(odd.engineMain, -1)
        XCTAssertEqual(odd.rank?.confidence, 1)
        XCTAssertEqual(odd.rank?.candidates.map(\.ttn), [5])
        XCTAssertEqual(odd.rank.map(DiscRanking.confidence), "Medium confidence")
        let version = try XCTUnwrap(odd.rank?.versions.first)
        XCTAssertEqual(DiscRanking.versionLabel(version, odd), "Playlist 6")
        XCTAssertEqual(DiscRanking.versionPath(3, version), "/play/3?mode=title&ttn=6&angle=2")
    }

    func testTheFourRoutes() async throws {
        let body = bluray
        let stand = try StandInServer { _ in StandInServer.answer(body: body) }
        addTeardownBlock { stand.stop() }
        let client = WittyClient(base: stand.address, token: "t")
        let read = try await client.discAnalysis(9, kind: "bluray-iso")
        let chosen = try await client.chooseDiscTitle(9, kind: "bluray-iso", ttn: 801)
        let cleared = try await client.clearDiscChoice(9, kind: "dvd-folder")
        let again = try await client.rankDiscAgain(9, kind: "bluray-iso", secondOpinion: true)
        XCTAssertEqual([read.main, chosen.main, cleared.main, again.main], [800, 800, 800, 800])
        XCTAssertEqual(stand.requests.map(\.line), [
            "GET /api/v1/modules/wittybluray/discs/9/analysis HTTP/1.1",
            "PUT /api/v1/modules/wittybluray/discs/9/choice HTTP/1.1",
            "DELETE /api/v1/modules/wittydvd/discs/9/choice HTTP/1.1",
            "POST /api/v1/modules/wittybluray/discs/9/analysis HTTP/1.1",
        ])
    }
}
