import XCTest
@testable import WittyKit

final class MusicPagesTests: XCTestCase {
    func testEachKindOfLibraryHasTheWebsitesTabs() {
        XCTAssertEqual(MusicTab.tabs(libraryType: "music").map(\.1), ["Home", "Albums", "Artists", "Songs", "Playlists"])
        XCTAssertEqual(MusicTab.tabs(libraryType: "audiobooks").map(\.1), ["Home", "Books", "Authors"])
        XCTAssertEqual(MusicTab.tabs(libraryType: "podcasts").map(\.1), ["Home", "Podcasts"])
        // A music videos library somewhere gives music, and only music, its Music videos between Songs and Playlists.
        XCTAssertEqual(MusicTab.tabs(libraryType: "music", musicVideos: true).map(\.1), ["Home", "Albums", "Artists", "Songs", "Music videos", "Playlists"])
        XCTAssertEqual(MusicTab.tabs(libraryType: "music", musicVideos: true).map(\.0)[4], .videos)
        XCTAssertEqual(MusicTab.tabs(libraryType: "audiobooks", musicVideos: true).map(\.1), ["Home", "Books", "Authors"])
        XCTAssertTrue(MusicSort.options(tab: .videos, libraryType: "music", songView: "").isEmpty)
    }

    func testSortsFollowTheTab() {
        XCTAssertEqual(MusicSort.options(tab: .albums, libraryType: "audiobooks", songView: "").map(\.label), ["Title", "Author", "Year", "Recently added", "Most played"])
        XCTAssertTrue(MusicSort.options(tab: .albums, libraryType: "podcasts", songView: "").isEmpty)
        XCTAssertEqual(MusicSort.options(tab: .artists, libraryType: "music", songView: "").map(\.label), ["Name", "Most albums"])
        XCTAssertTrue(MusicSort.options(tab: .songs, libraryType: "music", songView: "recent").isEmpty)
        XCTAssertEqual(MusicSort.options(tab: .songs, libraryType: "music", songView: "liked").count, 6)
        XCTAssertTrue(MusicSort.options(tab: .home, libraryType: "music", songView: "").isEmpty)
        XCTAssertEqual(MusicSort.start(tab: .albums, libraryType: "audiobooks"), "artist")
        XCTAssertEqual(MusicSort.start(tab: .artists, libraryType: "audiobooks"), "name")
        // The server sends years newest first: asking for oldest first turns the list round.
        XCTAssertTrue(MusicSort.reversed(sort: "year", desc: false))
        XCTAssertFalse(MusicSort.reversed(sort: "year", desc: true))
        XCTAssertTrue(MusicSort.reversed(sort: "title", desc: true))
    }

    func testWordsOnThePages() throws {
        XCTAssertEqual(MusicWords.count(1, ("album", "albums")), "1 album")
        XCTAssertEqual(MusicWords.runtime(59 * 60), "59 min")
        XCTAssertEqual(MusicWords.runtime(3600), "1 h")
        XCTAssertEqual(MusicWords.runtime(3600 + 240), "1 h 4 min")
        XCTAssertEqual(MusicWords.baseTitle("Across the Ocean (Deluxe Edition)"), MusicWords.baseTitle("Across the Ocean"))
        XCTAssertNotEqual(MusicWords.baseTitle("Collide"), MusicWords.baseTitle("Across the Ocean"))
        let tracks = try JSONDecoder().decode([Item].self, from: Data(#"""
        [{"id":1,"title":"One","runtimeSec":1800,"year":2013,"genres":["Ambient"],"progress":{"watched":true}},{"id":2,"title":"Two","runtimeSec":2040}]
        """#.utf8))
        XCTAssertEqual(MusicWords.albumFacts(tracks: tracks, kind: "music"), "2 tracks · 1 h 4 min · 2013 · Ambient")
        XCTAssertEqual(MusicWords.albumFacts(tracks: tracks, kind: "podcasts"), "2 episodes")
        XCTAssertEqual(MusicWords.resumeIndex(tracks), 1)
        XCTAssertEqual(SongViews.empty(view: "liked", filtered: false).text, "Press the heart on a song to keep it here.")
        XCTAssertEqual(SongViews.empty(view: "", filtered: true).title, "Nothing matches that")
    }

    func testAnArtistsSinglesSitUnderTheirAlbums() throws {
        let info = try JSONDecoder().decode(ArtistPageInfo.self, from: Data(#"""
        {"name":"A","albums":[{"title":"Old","year":2001,"tracks":10},{"title":"Single","year":2020,"tracks":2},{"title":"New","year":2019,"tracks":9}],"tracks":[],"top":[],"genres":[]}
        """#.utf8))
        let music = info.discography(newestFirst: true, books: false)
        XCTAssertEqual(music.full.map(\.title), ["New", "Old"])
        XCTAssertEqual(music.small.map(\.title), ["Single"])
        XCTAssertEqual(info.discography(newestFirst: false, books: true).full.map(\.title), ["New", "Old", "Single"])
        let home = try JSONDecoder().decode(MusicHome.self, from: Data(#"{"hero":[{"title":"X","artist":"Y","genre":"Jazz"}],"counts":{"albums":3}}"#.utf8))
        XCTAssertEqual(home.hero.first?.genre, "Jazz")
        XCTAssertTrue(home.songs.isEmpty)
        XCTAssertEqual(home.counts?.albums, 3)
    }
}
