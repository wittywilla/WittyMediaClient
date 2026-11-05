import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import WittyKit

/// Music, audiobooks and podcasts: what the player decides, and what it asks the server, with no
/// sound and no screen. The same cases as Android's ListeningRulesTest.
final class ListeningTests: XCTestCase {
    private func track(_ id: Int64, progress: String? = nil, runtime: Double = 600) throws -> Item {
        let json = #"{"id":\#(id),"title":"Part \#(id)","kind":"audio","runtimeSec":\#(runtime)"# + (progress.map { #","progress":\#($0)"# } ?? "") + "}"
        return try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    // MARK: Where Play starts

    func testSongsAlwaysStartOver() throws {
        let tracks = [try track(1, progress: #"{"positionSec":120,"updatedAt":5}"#), try track(2)]
        XCTAssertEqual(ListeningRules.whereToStart(tracks, keepsPlace: false), ListeningStart(0))
        XCTAssertEqual(ListeningRules.placeOn(tracks[0], keepsPlace: false), 0)
        XCTAssertFalse(ListeningRules.hasPlaceToResume(tracks, keepsPlace: false))
    }

    func testABookCarriesOnFromThePartLastLeftInTheMiddle() throws {
        let tracks = [
            try track(1, progress: #"{"positionSec":600,"watched":true,"updatedAt":1}"#),
            try track(2, progress: #"{"positionSec":30,"updatedAt":2}"#),
            try track(3, progress: #"{"positionSec":90,"updatedAt":9}"#),
            try track(4),
        ]
        XCTAssertEqual(ListeningRules.whereToStart(tracks, keepsPlace: true), ListeningStart(2, atSec: 90))
        XCTAssertTrue(ListeningRules.hasPlaceToResume(tracks, keepsPlace: true))
        XCTAssertEqual(ListeningRules.placeOn(tracks[0], keepsPlace: true), 0, "a finished part starts over")
    }

    func testABookWithNothingInTheMiddleStartsAtTheFirstNotFinished() throws {
        let tracks = [try track(1, progress: #"{"positionSec":600,"watched":true}"#), try track(2), try track(3)]
        XCTAssertEqual(ListeningRules.whereToStart(tracks, keepsPlace: true), ListeningStart(1))
        XCTAssertTrue(ListeningRules.hasPlaceToResume(tracks, keepsPlace: true))
    }

    func testAFinishedBookStartsAgainAndOffersNoResume() throws {
        let tracks = [try track(1, progress: #"{"watched":true}"#), try track(2, progress: #"{"watched":true}"#)]
        XCTAssertEqual(ListeningRules.whereToStart(tracks, keepsPlace: true), ListeningStart(0))
        XCTAssertFalse(ListeningRules.hasPlaceToResume(tracks, keepsPlace: true))
        XCTAssertFalse(ListeningRules.hasPlaceToResume([try track(1), try track(2)], keepsPlace: true), "nothing started yet")
    }

    func testWhatKeepsItsPlace() {
        XCTAssertTrue(ListeningRules.keepsPlace(libraryType: "audiobooks"))
        XCTAssertTrue(ListeningRules.keepsPlace(libraryType: "podcasts"))
        XCTAssertFalse(ListeningRules.keepsPlace(libraryType: "music"))
        XCTAssertFalse(ListeningRules.keepsPlace(libraryType: ""))
    }

    // MARK: Speed

    func testSpeedGoesRoundAndSaysItself() {
        XCTAssertEqual(ListeningRules.nextSpeed(after: 1), 1.25)
        XCTAssertEqual(ListeningRules.nextSpeed(after: 2), 0.75)
        XCTAssertEqual(ListeningRules.nextSpeed(after: 1.3), 1.5, "an odd speed goes on to the next one up")
        XCTAssertEqual(ListeningRules.speedWords(1), "1×")
        XCTAssertEqual(ListeningRules.speedWords(1.5), "1.5×")
        XCTAssertEqual(ListeningRules.speedWords(1.25), "1.25×")
        XCTAssertEqual(ListeningRules.speedWords(0.75), "0.75×")
    }

    // MARK: What's told to the server

    func testASongIsCountedOnceHeardForFiveSeconds() {
        XCTAssertNil(ListeningRules.report(keepsPlace: false, positionSec: 100, durationSec: 200, listenedSec: 4.9, reachedEnd: false))
        XCTAssertEqual(ListeningRules.report(keepsPlace: false, positionSec: 100, durationSec: 200, listenedSec: 5, reachedEnd: true), .listened(seconds: 5))
    }

    func testABookSavesItsPlaceButNotTheFirstFewSeconds() {
        XCTAssertEqual(ListeningRules.report(keepsPlace: true, positionSec: 61, durationSec: 600, listenedSec: 0, reachedEnd: false),
                       .place(positionSec: 61, durationSec: 600))
        XCTAssertNil(ListeningRules.report(keepsPlace: true, positionSec: 4, durationSec: 600, listenedSec: 60, reachedEnd: false))
        XCTAssertEqual(ListeningRules.report(keepsPlace: true, positionSec: 590, durationSec: 600, listenedSec: 0, reachedEnd: true),
                       .place(positionSec: 600, durationSec: 600), "the end marks it as finished")
        XCTAssertNil(ListeningRules.report(keepsPlace: true, positionSec: 60, durationSec: 0, listenedSec: 0, reachedEnd: false), "no length, no place")
    }

    // MARK: Failures

    func testWhatAFailureMeans() {
        XCTAssertEqual(ListeningRules.recovery(for: URLError(.networkConnectionLost)), .waitThenNewStream)
        XCTAssertEqual(ListeningRules.recovery(for: APIError(status: 404, message: "gone")), .newStream)
        XCTAssertEqual(ListeningRules.recovery(for: APIError(status: 503, message: "busy")), .waitThenNewStream)
        XCTAssertEqual(ListeningRules.recovery(for: APIError(status: 403, message: "no")), .giveUp)
        let deep = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                           userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: -1005)])
        XCTAssertEqual(ListeningRules.recovery(for: deep), .waitThenNewStream, "the network, under the player's own error")
        XCTAssertEqual(ListeningRules.recovery(for: NSError(domain: "AVFoundationErrorDomain", code: -11828)), .convert)
        XCTAssertEqual(ListeningRules.recovery(for: NSError(domain: "CoreMediaErrorDomain", code: -12938)), .newStream)
    }

    func testFailuresInPlainWords() {
        XCTAssertEqual(ListeningRules.failureWords(.giveUp, status: 403), "This profile isn't allowed to play this.")
        XCTAssertEqual(ListeningRules.failureWords(.waitThenNewStream, status: 503), "The server is busy. Try again in a moment.")
        XCTAssertEqual(ListeningRules.failureWords(.waitThenNewStream, status: nil), "Lost contact with your server. Check that it is running, then try again.")
        XCTAssertEqual(ListeningRules.failureWords(.convert, status: nil), "This device can't play this, even after the server converted it.")
    }

    // MARK: Words

    func testWordsForEachKindOfLibrary() {
        XCTAssertEqual(ListeningRules.albumsWord(libraryType: "audiobooks"), "Books")
        XCTAssertEqual(ListeningRules.albumsWord(libraryType: "podcasts"), "Podcasts")
        XCTAssertEqual(ListeningRules.albumsWord(libraryType: "music"), "Albums")
        XCTAssertEqual(ListeningRules.artistsWord(libraryType: "audiobooks"), "Authors")
        XCTAssertEqual(ListeningRules.tracksWords(libraryType: "music", count: 1), "1 song")
        XCTAssertEqual(ListeningRules.tracksWords(libraryType: "audiobooks", count: 12), "12 parts")
        XCTAssertEqual(ListeningRules.tracksWords(libraryType: "podcasts", count: 3), "3 episodes")
        XCTAssertEqual(ListeningRules.lengthWords(2870), "48 min")
        XCTAssertEqual(ListeningRules.lengthWords(11_100), "3 h 5 min")
        XCTAssertEqual(ListeningRules.clock(187), "3:07")
        XCTAssertEqual(ListeningRules.clock(3723), "1:02:03")
        XCTAssertEqual(ListeningRules.clock(.nan), "0:00")
        XCTAssertEqual(ListeningRules.spokenClock(3723), "1 hour 2 minutes 3 seconds")
        XCTAssertEqual(ListeningRules.spokenClock(0), "0 seconds")
    }

    // MARK: The queue

    func testNextAndPreviousStopAtTheEndsUnlessTheQueueRepeats() {
        var queue = ListeningQueue(["a", "b", "c"], start: 2)
        XCTAssertNil(queue.next)
        XCTAssertEqual(queue.previous, 1)
        queue.repeatMode = .all
        XCTAssertEqual(queue.next, 0)
        queue.repeatMode = .one
        XCTAssertNil(queue.next, "repeating one doesn't stop a person moving on, but there's nowhere to go")
        XCTAssertEqual(queue.afterEnd, 2, "by itself it plays the same one again")
        queue.repeatMode = .off
        XCTAssertNil(queue.afterEnd)
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }

    func testShufflingKeepsTheOnePlayingFirstAndPlaysEveryOneOnce() {
        var queue = ListeningQueue(Array(0..<20), start: 7)
        queue.setShuffled(true)
        XCTAssertEqual(queue.order.first, 7)
        XCTAssertEqual(Set(queue.order), Set(0..<20))
        XCTAssertEqual(queue.now, 7)
        queue.setShuffled(false)
        XCTAssertEqual(queue.order, Array(0..<20))
        XCTAssertEqual(queue.next, 8)
    }

    func testAddingGoesAtTheEndAndPlayNextStraightAfter() {
        var queue = ListeningQueue(["a", "b", "c"], start: 0)
        queue.append(["d"])
        queue.insertNext(["x"])
        XCTAssertEqual(queue.entries, ["a", "x", "b", "c", "d"])
        XCTAssertEqual(queue.next, 1)
        queue.jump(to: 3)
        queue.setShuffled(true)
        queue.insertNext(["y"])
        XCTAssertEqual(queue.now, "c")
        XCTAssertEqual(queue.order[1], queue.entries.firstIndex(of: "y"), "shuffled, it still comes next")
        queue.append(["z"])
        XCTAssertEqual(queue.order.last, queue.entries.firstIndex(of: "z"))
        XCTAssertEqual(Set(queue.order.map { queue.entries[$0] }), Set(queue.entries))
    }

    func testTakingOutTheOnePlayingMovesOnToTheNext() {
        var queue = ListeningQueue(["a", "b", "c"], start: 1)
        XCTAssertTrue(queue.remove(at: 1))
        XCTAssertEqual(queue.now, "c")
        XCTAssertFalse(queue.remove(at: 0))
        XCTAssertEqual(queue.now, "c", "taking out one before it doesn't change what plays")
        XCTAssertTrue(queue.remove(at: 0))
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.now)
        var last = ListeningQueue(["a", "b"], start: 1)
        last.remove(at: 1)
        XCTAssertEqual(last.now, "a", "at the end, the one before")
    }

    func testMovingKeepsTheOnePlaying() {
        var queue = ListeningQueue(["a", "b", "c", "d"], start: 1)
        queue.move(from: 1, to: 3)
        XCTAssertEqual(queue.entries, ["a", "c", "d", "b"])
        XCTAssertEqual(queue.now, "b")
        queue.move(from: 0, to: 2)
        XCTAssertEqual(queue.entries, ["c", "d", "a", "b"])
        XCTAssertEqual(queue.now, "b")
        queue.move(from: 0, to: 9)
        XCTAssertEqual(queue.entries, ["c", "d", "a", "b"], "nowhere to go")
    }

    // MARK: What's asked of the server

    private func server(_ respond: @escaping @Sendable (StandInServer.Request) -> Data) throws -> StandInServer {
        let made = try StandInServer(respond: respond)
        addTeardownBlock { made.stop() }
        return made
    }

    func testAnAlbumIsAskedForByNameWithNothingAddedToTheQuery() async throws {
        let stand = try server { _ in StandInServer.answer(body: #"[{"id":3,"title":"One","kind":"audio","album":"Rock & Roll","track":1}]"#) }
        let client = WittyClient(base: stand.address, token: "t")
        let tracks = try await client.tracks(library: 4, album: "Rock & Roll", artist: "A=B?")
        XCTAssertEqual(tracks.map(\.id), [3])
        XCTAssertEqual(stand.requests.first?.path, "/api/v1/music/tracks?library=4&album=Rock%20%26%20Roll&artist=A%3DB%3F")
        XCTAssertTrue(stand.requests.first?.hasToken == true)
    }

    func testAListTheServerSendsAsNullIsEmpty() async throws {
        let stand = try server { _ in StandInServer.answer(body: "null") }
        let client = WittyClient(base: stand.address, token: "t")
        let albums = try await client.albums(library: 4, sort: "title")
        XCTAssertTrue(albums.isEmpty)
        let artists = try await client.artists(library: 4)
        XCTAssertTrue(artists.isEmpty)
        let songs = try await client.songs(library: 4, offset: 100, limit: 100)
        XCTAssertTrue(songs.isEmpty)
        XCTAssertEqual(stand.requests.map(\.path), [
            "/api/v1/music/albums?library=4&sort=title",
            "/api/v1/music/artists?library=4",
            "/api/v1/music/songs?library=4&offset=100&limit=100&sort=title",
        ])
    }

    func testAnArtistsAlbumsAndWhatIsHeardGoToTheServer() async throws {
        let stand = try server { request in
            request.line.hasPrefix("POST") ? StandInServer.answer(body: "{}")
                : StandInServer.answer(body: #"[{"artist":"Aurora Lane","title":"Paper Satellites","year":2023,"tracks":4,"durationSec":96,"coverItem":1,"genre":"Ambient"}]"#)
        }
        let client = WittyClient(base: stand.address, token: "t")
        let albums = try await client.albums(library: 3, sort: "year", artist: "Aurora Lane")
        XCTAssertEqual(albums, [Album(artist: "Aurora Lane", title: "Paper Satellites", year: 2023, tracks: 4, durationSec: 96, coverItem: 1)])
        XCTAssertEqual(albums.first?.key, "Aurora Lane|Paper Satellites")
        try await client.recordListen(9, seconds: 31)
        XCTAssertEqual(stand.requests.map(\.path), ["/api/v1/music/albums?library=3&sort=year&artist=Aurora%20Lane", "/api/v1/items/9/view"])
        XCTAssertEqual(client.coverURL(1)?.absoluteString, "\(stand.address)/api/v1/items/1/poster")
    }

    func testAConversionCanBeAskedFor() throws {
        let body = try JSONEncoder().encode(PlaybackRequest(profile: "appletv", startSec: 12, forceTranscode: true))
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(sent["forceTranscode"] as? Bool, true)
        XCTAssertEqual(sent["startSec"] as? Double, 12)
        let plain = try JSONEncoder().encode(PlaybackRequest(profile: "appletv"))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("forceTranscode"), "left out, the server decides")
    }

    func testWhichLibrariesHaveTheirOwnListeningScreens() throws {
        func library(_ type: String) throws -> Library {
            try JSONDecoder().decode(Library.self, from: Data(#"{"id":1,"name":"x","type":"\#(type)"}"#.utf8))
        }
        for type in ["music", "audiobooks", "podcasts"] { XCTAssertTrue(try library(type).hasListeningScreens, type) }
        for type in ["radio", "books", "movies"] { XCTAssertFalse(try library(type).hasListeningScreens, type) }
    }

    func testATrackOpensTheAlbumOfWhoeverTheAlbumIsBy() throws {
        func item(_ json: String) throws -> Item { try JSONDecoder().decode(Item.self, from: Data(json.utf8)) }
        XCTAssertEqual(try item(#"{"id":1,"title":"t","artist":"Guest","albumArtist":"Band"}"#).albumArtistName, "Band")
        XCTAssertEqual(try item(#"{"id":1,"title":"t","artist":"Guest","albumArtist":""}"#).albumArtistName, "Guest")
        XCTAssertEqual(try item(#"{"id":1,"title":"t"}"#).albumArtistName, "")
    }
}
