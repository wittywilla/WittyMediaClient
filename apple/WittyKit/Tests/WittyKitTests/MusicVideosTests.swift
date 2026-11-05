import XCTest
@testable import WittyKit

final class MusicVideosTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }

    func testOnlyAMusicVideosLibraryMakesThemAvailable() throws {
        let some = try decode([Library].self, #"[{"id":1,"name":"Music","type":"music"},{"id":2,"name":"Concerts","type":"musicvideos"}]"#)
        XCTAssertTrue(MusicVideos.available(in: some))
        XCTAssertFalse(MusicVideos.available(in: Array(some.prefix(1))))
        XCTAssertFalse(MusicVideos.available(in: []))
    }

    func testTheTabAndTheShelfAskWhatTheWebsiteAsks() {
        XCTAssertEqual(MusicVideos.path(search: "", offset: 0), "/music/videos?limit=120&offset=0")
        XCTAssertEqual(MusicVideos.path(search: "a-ha & co", offset: 120), "/music/videos?limit=120&offset=120&search=a-ha%20%26%20co")
        XCTAssertEqual(MusicVideos.latestPath, "/music/videos?limit=12&sort=latest")
    }

    func testAPageOfVideosAsTheServerSendsIt() throws {
        let page = try decode(MusicVideoPage.self, #"""
        {"videos":[
          {"id":9,"libraryId":4,"title":"Take On Me","durationSec":225,"width":1920,"height":1080,"vertical":false,"creatorId":3,"creator":"a-ha",
           "hasAvatar":true,"uploadDate":"2024-05-31","tags":null,"views":2,"origViews":1500,"likes":0,"origLikes":0,"comments":0,"reaction":0,
           "positionSec":45,"watched":false,"updatedAt":17,
           "song":{"id":5,"libraryId":1,"title":"Take On Me","artist":"a-ha","album":"Hunting High and Low","runtimeSec":225,"updatedAt":3},"syncMs":4000},
          {"id":10,"libraryId":4,"title":"Live","durationSec":0,"vertical":true,"creatorId":3,"creator":"a-ha","hasAvatar":false,"uploadDate":"",
           "views":0,"origViews":0,"positionSec":0,"watched":true,"updatedAt":0}
        ],"more":true}
        """#)
        XCTAssertTrue(page.more)
        XCTAssertEqual(page.videos.map(\.id), [9, 10])
        let first = page.videos[0]
        XCTAssertEqual(first.syncMs, 4000)
        XCTAssertEqual(first.song?.album, "Hunting High and Low")
        XCTAssertEqual(first.allViews, 1502)
        XCTAssertEqual(first.progress, 0.2, accuracy: 0.0001)
        XCTAssertEqual(first.songWords, "On Hunting High and Low")
        XCTAssertNil(page.videos[1].song)
        XCTAssertNil(page.videos[1].songWords)
        XCTAssertEqual(page.videos[1].progress, 0)
        XCTAssertTrue(page.videos[1].vertical)
        // Nothing in it at all is still a page.
        XCTAssertEqual(try decode(MusicVideoPage.self, #"{"videos":null}"#).videos, [])
    }

    func testTheSongUnderAVideoGoesToItsAlbumHereOrElseItsArtist() throws {
        let here = try decode(MusicLinkSide.self, #"{"id":5,"libraryId":1,"title":"T","artist":"A","album":"B","runtimeSec":200}"#)
        XCTAssertEqual(MusicVideos.songPlace(here, library: 1), .album(library: 1, album: "B", artist: "A"))
        XCTAssertEqual(MusicVideos.songPlace(here, library: 2), .artist(library: 1, name: "A"))
        let single = try decode(MusicLinkSide.self, #"{"id":5,"libraryId":1,"title":"T","artist":"A","runtimeSec":200}"#)
        XCTAssertEqual(MusicVideos.songPlace(single, library: 1), .artist(library: 1, name: "A"))
        let card = try decode(MusicVideoCard.self, #"{"id":1,"song":{"id":5,"libraryId":1,"title":"T","artist":"A","album":"","runtimeSec":1}}"#)
        XCTAssertEqual(card.songWords, "In your music")
    }

    func testWatchTheVideoFromHereWhenTheTwoLineUp() throws {
        let links = try decode(MusicLinks.self, #"""
        {"itemId":5,"role":"song","tied":[{"songId":5,"videoId":9,"state":"tied","how":"isrc","syncMs":4000,
          "song":{"id":5,"libraryId":1,"title":"T","artist":"A","runtimeSec":200},"video":{"id":9,"libraryId":4,"title":"T","artist":"A","runtimeSec":220}}],
         "suggested":[],"canEdit":false}
        """#)
        let tied = try XCTUnwrap(links.tied.first)
        XCTAssertEqual(links.role, "song")
        // Thirty seconds into the song is four seconds later in the video.
        XCTAssertEqual(MusicVideos.place(in: .video, at: 30, syncMs: tied.syncMs, length: tied.video.runtimeSec), 34)
        XCTAssertEqual(MusicVideos.place(in: .song, at: 34, syncMs: 4000, length: 200), 30)
        XCTAssertEqual(MusicVideos.watchPath(tied, songAt: 30.9), "/watch/9?t=34")
        // At the very start, near the end, or when they don't line up: the video from wherever its page starts it.
        XCTAssertEqual(MusicVideos.watchPath(tied, songAt: 217), "/watch/9")
        XCTAssertNil(MusicVideos.place(in: .song, at: 4.5, syncMs: 4000, length: 200))
        XCTAssertNil(MusicVideos.place(in: .video, at: 30, syncMs: nil, length: 220))
        XCTAssertEqual(MusicVideos.place(in: .video, at: 3000, syncMs: 0, length: 0), 3000)
        XCTAssertEqual(MusicVideos.watchPath(videoId: 9), "/watch/9")
        // An item that can't be tied answers with nothing to tie.
        let none = try decode(MusicLinks.self, #"{"itemId":7,"role":"","tied":[],"suggested":[],"canEdit":true}"#)
        XCTAssertTrue(none.tied.isEmpty)
        XCTAssertTrue(none.canEdit)
    }

    func testTheWordsOnTheTab() {
        XCTAssertEqual(MusicVideos.count(1, more: false), "1 video")
        XCTAssertEqual(MusicVideos.count(120, more: true), "120+ videos")
        XCTAssertEqual(MusicVideos.empty(searching: true).title, "Nothing matches that")
        XCTAssertEqual(MusicVideos.empty(searching: true).text, "")
        XCTAssertEqual(MusicVideos.empty(searching: false).title, "No music videos yet")
    }

    func testCountsAndDatesUnderATile() throws {
        XCTAssertEqual(MusicVideos.shortCount(999), "999")
        XCTAssertEqual(MusicVideos.shortCount(1000), "1K")
        XCTAssertEqual(MusicVideos.shortCount(1234), "1.2K")
        XCTAssertEqual(MusicVideos.shortCount(1_500_000), "1.5M")
        XCTAssertEqual(MusicVideos.shortCount(2_000_000_000), "2B")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-06-30T15:00:00Z"))
        XCTAssertEqual(MusicVideos.ago("2024-06-30", now: now), "today")
        XCTAssertEqual(MusicVideos.ago("2024-06-29", now: now), "yesterday")
        XCTAssertEqual(MusicVideos.ago("2024-06-25", now: now), "5 days ago")
        XCTAssertEqual(MusicVideos.ago("2024-06-20", now: now), "1 week ago")
        XCTAssertEqual(MusicVideos.ago("2024-06-01", now: now), "4 weeks ago")
        XCTAssertEqual(MusicVideos.ago("2024-05-10", now: now), "1 month ago")
        XCTAssertEqual(MusicVideos.ago("2024-05-01", now: now), "2 months ago")
        XCTAssertEqual(MusicVideos.ago("2024-01", now: now), "6 months ago")
        XCTAssertEqual(MusicVideos.ago("2022", now: now), "2 years ago")
        XCTAssertEqual(MusicVideos.ago("", now: now), "")
        XCTAssertEqual(MusicVideos.ago("20240531", now: now), "")
        let card = try decode(MusicVideoCard.self, #"{"id":1,"views":0,"origViews":1234,"uploadDate":"2024-06-29"}"#)
        XCTAssertEqual(card.facts(now: now), "1.2K views · yesterday")
        let bare = try decode(MusicVideoCard.self, #"{"id":1}"#)
        XCTAssertEqual(bare.facts(now: now), "")
    }

    func testACreatorWithNoPictureKeepsTheirColour() {
        // The website's Avatar: the name into a hue, at 35% and 36%.
        XCTAssertEqual(MusicVideos.avatarColour("a-ha"), CategoryLook.hsl(Double(CategoryLook.hue("a-ha")), 0.35, 0.36))
        XCTAssertEqual(MusicVideos.avatarColour("A"), CategoryLook.hsl(65, 0.35, 0.36))
    }
}
