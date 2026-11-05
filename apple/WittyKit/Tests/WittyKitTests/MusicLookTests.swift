import XCTest
@testable import WittyKit

final class MusicLookTests: XCTestCase {
    private func lyrics(_ json: String) throws -> Lyrics { try JSONDecoder().decode(Lyrics.self, from: Data(json.utf8)) }

    func testTheLineSungIsTheLastOneStartedAfterTheListenersCorrection() throws {
        let song = try lyrics(#"{"synced":true,"lines":[{"t":1000,"text":"One"},{"t":4000,"text":"Two"},{"t":9000,"text":"Three"}],"offsetMs":500}"#)
        XCTAssertEqual(song.lineAt(seconds: 0.5), -1, "before the first line")
        XCTAssertEqual(song.lineAt(seconds: 1.4), -1, "the correction makes the words later")
        XCTAssertEqual(song.lineAt(seconds: 1.5), 0)
        XCTAssertEqual(song.lineAt(seconds: 6), 1)
        XCTAssertEqual(song.lineAt(seconds: 300), 2)
        XCTAssertTrue(song.hasWords)
    }

    func testUntimedOrMissingWords() throws {
        let plain = try lyrics(#"{"synced":false,"lines":[{"t":0,"text":"x"}],"plain":"Just words"}"#)
        XCTAssertTrue(plain.timed.isEmpty, "lines that aren't synced aren't followed")
        XCTAssertTrue(plain.hasWords)
        XCTAssertEqual(plain.lineAt(seconds: 10), -1)
        XCTAssertFalse(try lyrics(#"{"instrumental":true,"plain":"  "}"#).hasWords)
    }

    func testTheArtColourIsTheBrightestColourLiftedFromBlack() {
        XCTAssertEqual(ArtColour.pick(rgba: []).red, ArtColour.neutral.red)
        // A dark red and a grey: the red wins, lifted to a usable brightness.
        let pixels: [UInt8] = [100, 10, 10, 255, 60, 60, 60, 255]
        let colour = ArtColour.pick(rgba: pixels)
        XCTAssertGreaterThan(colour.red, colour.green * 2)
        XCTAssertGreaterThan(colour.red, 150)
        XCTAssertLessThanOrEqual(colour.red, 255)
        // As on the website, the brightest channel is brought to 190, so even white glows softly.
        XCTAssertEqual(ArtColour.pick(rgba: [255, 255, 255, 255]).red, 190)
    }

    func testTheSleepTimerAndSpeedsSayWhatTheWebsiteSays() {
        XCTAssertEqual(SleepChoices.minutes.map(SleepChoices.words), ["In 15 minutes", "In 30 minutes", "In 45 minutes", "In 1 hour", "In 90 minutes"])
        XCTAssertEqual(SleepChoices.atTheEnd(books: false), "After this song")
        XCTAssertEqual(SleepChoices.atTheEnd(books: true), "At the end of this chapter")
        XCTAssertEqual(ListeningSpeeds.offered(max: 2), [0.75, 1, 1.25, 1.5, 1.75, 2])
        XCTAssertEqual(ListeningSpeeds.offered(max: nil).last, 3)
        XCTAssertEqual(QueueWords.toCome([]), "Nothing after this")
        XCTAssertEqual(QueueWords.toCome([200, 600]), "2 to come · 13:20")
    }

    func testASongWithNoWordsSaysWhy() throws {
        func lyrics(_ json: String) throws -> Lyrics { try JSONDecoder().decode(Lyrics.self, from: Data(json.utf8)) }
        XCTAssertEqual(LyricWords.none(try lyrics(#"{"failed":"timeout"}"#)).first, "The lyrics source couldn't be reached just now. It'll be tried again next time.")
        XCTAssertEqual(LyricWords.none(try lyrics(#"{"tried":true}"#)), ["No words found for this song online."])
        XCTAssertEqual(LyricWords.none(try lyrics(#"{"tried":true,"canEdit":true}"#)).first?.hasSuffix("or add them yourself."), true)
        XCTAssertEqual(LyricWords.none(try lyrics(#"{"tried":true,"canEdit":true}"#), fixHere: false), ["No words found for this song online."])
        XCTAssertEqual(LyricWords.none(try lyrics(#"{"online":true}"#)), ["No words found for this song."])
        XCTAssertEqual(LyricWords.none(try lyrics(#"{"online":false,"canEdit":false}"#)).last, "Whoever runs this server can also turn on finding them online.")
        XCTAssertEqual(LyricWords.offset(0), "On time")
        XCTAssertEqual(LyricWords.offset(250), "+0.25 s")
        XCTAssertEqual(LyricWords.offset(-1500), "-1.50 s")
        XCTAssertEqual(LyricWords.nudge(119_900, by: 250), 120_000)
    }

    func testOnlyHandMadePlaylistsTakeSongs() throws {
        let lists = try JSONDecoder().decode([TitleCollection].self, from: Data(#"""
        [{"id":1,"name":"Mine","kind":"manual"},{"id":2,"name":"Liked songs","kind":"manual","system":"liked"},{"id":3,"name":"Smart","kind":"smart"}]
        """#.utf8))
        XCTAssertEqual(lists.filter(\.isPlaylist).map(\.id), [1])
    }
}
