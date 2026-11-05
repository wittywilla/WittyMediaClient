import XCTest
@testable import WittyKit

final class ServerPagesTests: XCTestCase {
    private func track(_ id: Int64, _ title: String, album: String? = nil, artist: String? = nil, number: Int? = nil, kind: String = "audio") throws -> Item {
        var fields: [String: Any] = ["id": id, "title": title, "kind": kind]
        if let album { fields["album"] = album }
        if let artist { fields["albumArtist"] = artist }
        if let number { fields["track"] = number }
        return try JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    func testARowShowsEachAlbumOnce() throws {
        let row = try [
            track(1, "One", album: "First", artist: "Band"),
            track(2, "Two", album: "First", artist: "Band"),
            track(3, "Three", album: "First", artist: "Someone else"),
            track(4, "Loose"),
            track(5, "A film", kind: "video"),
        ]
        XCTAssertEqual(ServerPages.albumsOnce(row).map(\.id), [1, 3, 4, 5])
    }

    func testACardIsNamedForItsAlbum() throws {
        let song = try track(1, "One", album: "First", artist: "Band")
        XCTAssertEqual(song.cardTitle, "First")
        XCTAssertEqual(song.cardSubtitle, "Band")
        XCTAssertEqual(try track(2, "Loose").cardTitle, "Loose")
    }

    func testTracksComeInOrderWithTheUnnumberedLast() throws {
        let all = try [
            track(1, "Later", album: "First", number: 2),
            track(2, "Unnumbered", album: "First"),
            track(3, "Sooner", album: "First", number: 1),
            track(4, "Elsewhere", album: "Second", number: 1),
        ]
        XCTAssertEqual(ServerPages.tracks(of: "First", in: all).map(\.id), [3, 1, 2])
    }

    func testTheListGoesOnAndThenStops() {
        XCTAssertEqual(ServerPages.next(after: 1, in: [1, 2]), 2)
        XCTAssertNil(ServerPages.next(after: 2, in: [1, 2]))
        XCTAssertNil(ServerPages.next(after: 9, in: [1, 2]), "something that isn't in the list has nothing after it")
    }

    func testAChannelsKeyStaysOnePieceOfTheAddress() {
        XCTAssertEqual(WittyClient.pathPart("lib-5"), "lib-5")
        XCTAssertEqual(WittyClient.pathPart("../settings?x=1"), "%2E%2E%2Fsettings%3Fx%3D1")
    }

    func testAnEncryptedChannelCannotBeTuned() throws {
        let plain = try JSONDecoder().decode(GuideChannel.self, from: Data(#"{"key":"lib-1","number":"2","name":"Films"}"#.utf8))
        XCTAssertTrue(plain.canTune)
        XCTAssertEqual(plain.label, "2  Films")
        let refused = try JSONDecoder().decode(GuideChannel.self, from: Data(#"{"key":"tun-1","name":"Pay","encrypted":"Encrypted"}"#.utf8))
        XCTAssertFalse(refused.canTune)
    }

    func testNowAndNextInTheGuide() throws {
        let json = #"{"key":"lib-1","name":"Films","programmes":[{"start":100,"end":200,"title":"First"},{"start":200,"end":400,"title":"Second"},{"start":400,"end":500,"title":"Third"}]}"#
        let channel = try JSONDecoder().decode(GuideChannel.self, from: Data(json.utf8))
        XCTAssertEqual(channel.on(at: 150)?.title, "First")
        XCTAssertEqual(channel.on(at: 200)?.title, "Second", "a programme starts on its first second")
        XCTAssertEqual(channel.next(after: 150)?.title, "Second")
        XCTAssertNil(channel.on(at: 900))
        XCTAssertNil(channel.next(after: 450))
        let first = try XCTUnwrap(channel.on(at: 150))
        XCTAssertEqual(first.fraction(at: 150), 0.5)
        XCTAssertEqual(first.fraction(at: 900), 1, "never past the end")
        XCTAssertEqual(first.minutesLeft(at: 199), 1)
    }

    func testChannelButtonsGoRoundAndSkipWhatCannotPlay() throws {
        func channel(_ key: String, encrypted: String? = nil) throws -> GuideChannel {
            let extra = encrypted.map { #","encrypted":"\#($0)""# } ?? ""
            return try JSONDecoder().decode(GuideChannel.self, from: Data(#"{"key":"\#(key)","name":"\#(key)"\#(extra)}"#.utf8))
        }
        let all = try [channel("a"), channel("b", encrypted: "Encrypted"), channel("c")]
        XCTAssertEqual(ServerPages.channel(from: "a", by: 1, in: all)?.key, "c")
        XCTAssertEqual(ServerPages.channel(from: "a", by: -1, in: all)?.key, "c")
        XCTAssertEqual(ServerPages.channel(from: "c", by: 1, in: all)?.key, "a")
        XCTAssertEqual(ServerPages.channel(from: "gone", by: 1, in: all)?.key, "a")
        XCTAssertNil(ServerPages.channel(from: "a", by: 1, in: []))
    }

    func testWhatAppleTVOpensItself() throws {
        func library(_ type: String) throws -> Library {
            try JSONDecoder().decode(Library.self, from: Data(#"{"id":1,"name":"x","type":"\#(type)"}"#.utf8))
        }
        for type in ["movies", "shows", "music", "audiobooks", "podcasts", "photos", "games"] { XCTAssertTrue(try library(type).opensOnAppleTV, type) }
        for type in ["books", "radio"] { XCTAssertFalse(try library(type).opensOnAppleTV, type) }
        // The server's games have Apple TV's own screens; a PC's games go through Moonlight, as before.
        XCTAssertTrue(try library("games").hasGameScreens)
        let rigs = try JSONDecoder().decode(Library.self, from: Data(#"{"id":2,"name":"PC","type":"games","console":"rig"}"#.utf8))
        XCTAssertFalse(rigs.hasGameScreens)
        XCTAssertTrue(rigs.isRigGames)
        XCTAssertFalse(try library("music").opensHere, "on iPhone and iPad, music is the server's own page")
    }
}
