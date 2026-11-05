import XCTest
@testable import WittyKit

final class BrowseTests: XCTestCase {
    func testShelvesKeepTheServersOrderAndLeaveOutHiddenCategories() throws {
        let json = #"""
        {"categories":[
          {"key":"drama","name":"Drama","genre":"Drama","count":12,"hidden":false,"position":0,"art":[{"type":"item","id":7,"v":3}]},
          {"key":"war","name":"War","genre":"War","count":2,"hidden":true,"position":1,"art":[]},
          {"key":"family","name":"Family","genre":"Family","count":4,"hidden":false,"position":2,"art":null}],
         "collections":null,"studios":[],"networks":[],"platforms":[]}
        """#
        let shelves = try JSONDecoder().decode(Shelves.self, from: Data(json.utf8))
        XCTAssertEqual(shelves.shown.map(\.name), ["Drama", "Family"])
        XCTAssertEqual(shelves.shown.first?.art?.first, CategoryArt(type: "item", id: 7, v: 3))
        XCTAssertNil(shelves.collections)
    }

    func testABrowseAnswerHoldsFilmsAndShows() throws {
        let json = #"""
        {"results":[{"type":"item","item":{"id":4,"title":"A film","kind":"video"}},
                    {"type":"show","show":{"id":9,"title":"A show"}}],"total":2}
        """#
        let answer = try JSONDecoder().decode(BrowseResult.self, from: Data(json.utf8))
        XCTAssertEqual(answer.items.map(\.id), [4])
        XCTAssertEqual(answer.shows.map(\.id), [9])
        XCTAssertEqual(answer.results?.map(\.id), ["item4", "show9"])
        let empty = try JSONDecoder().decode(BrowseResult.self, from: Data(#"{"results":null,"total":0}"#.utf8))
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testABrowseAsksForExactlyWhatWasChosen() {
        XCTAssertEqual(BrowseQuery(library: 3).path(limit: 20), "/browse?library=3&sort=title&limit=20")
        XCTAssertEqual(BrowseQuery(library: 3, sort: "added", descending: true).path(offset: 40, limit: 20),
                       "/browse?library=3&sort=added&desc=1&limit=20&offset=40")
        XCTAssertEqual(BrowseQuery(library: 3, sort: "rating", descending: true, filters: ["minRating": "6"]).path(limit: 20),
                       "/browse?library=3&sort=rating&desc=1&minRating=6&limit=20")
        // A genre's name can't add a parameter of its own.
        XCTAssertEqual(BrowseQuery(library: 1, filters: ["genre": "Sci-Fi & Fantasy"]).path(limit: 5),
                       "/browse?library=1&sort=title&genre=Sci-Fi%20%26%20Fantasy&limit=5")
        // Filters go in the website's order whatever order they were chosen in, and an empty one is none.
        let several = BrowseQuery(library: 2, filters: ["watched": "no", "decade": "1990", "genre": "Drama", "year": ""])
        XCTAssertEqual(several.path(limit: 1), "/browse?library=2&sort=title&genre=Drama&decade=1990&watched=no&limit=1")
        XCTAssertEqual(several.chosen.map(\.key), ["genre", "decade", "watched"])
        // Something that isn't one of the website's filters is never sent.
        XCTAssertEqual(BrowseQuery(library: 2, filters: ["library": "9"]).path(limit: 1), "/browse?library=2&sort=title&limit=1")
    }

    func testFacetsKeepWhatTheyCanReadAndSayTheirChoicesPlainly() throws {
        let facets = try JSONDecoder().decode(Facets.self, from: Data(#"""
        {"genres":[{"value":"Drama","count":3}],"years":null,"formats":"odd","kinds":[{"value":"bluray","count":1}]}
        """#.utf8))
        XCTAssertEqual(facets["genres"].map(\.value), ["Drama"])
        XCTAssertTrue(facets["years"].isEmpty)
        XCTAssertTrue(facets["formats"].isEmpty, "a group in a shape this app doesn't know is left out")
        XCTAssertEqual(BrowseFilter.words("kind", "bluray"), "Blu-rays")
        XCTAssertEqual(BrowseFilter.words("minRating", "7"), "7 or more")
        XCTAssertEqual(BrowseFilter.words("watched", "no"), "Not watched yet")
        XCTAssertEqual(BrowseFilter.title(of: "genre"), "Category")
        XCTAssertEqual(BrowseFilter.title(of: "minRating"), "Score")
    }

    func testTheSortsAreTheWebsites() {
        XCTAssertEqual(LibrarySort.all.map(\.label), ["Shuffle", "Recently added", "Title A to Z", "Newest", "Oldest", "Highest rated", "Best quality"])
        XCTAssertEqual(LibrarySort.all.filter(\.descending).map(\.key), ["added", "rating", "quality"])
    }

    func testALibrarysSizeIsSaidInItsOwnWords() {
        XCTAssertEqual(LibraryWords.count(35, type: "movies"), "35 titles")
        XCTAssertEqual(LibraryWords.count(1, type: "shows"), "1 episode")
        XCTAssertEqual(LibraryWords.count(6, type: "audiobooks"), "6 files")
        XCTAssertEqual(LibraryWords.count(3, type: "something new"), "3 items")
        XCTAssertEqual(LibraryWords.titles(1, type: "anime"), "1 show")
        XCTAssertEqual(LibraryWords.titles(35, type: "movies"), "35 films")
    }

    func testCategoryArtIsTheBackdropOfAFilmOrAShow() {
        let client = WittyClient(base: "http://127.0.0.1:9797")
        XCTAssertEqual(client.backdropURL(CategoryArt(type: "item", id: 7, v: 3))?.absoluteString, "http://127.0.0.1:9797/api/v1/items/7/backdrop?v=3")
        XCTAssertEqual(client.backdropURL(CategoryArt(type: "show", id: 2, v: nil))?.absoluteString, "http://127.0.0.1:9797/api/v1/shows/2/art/backdrop?v=0")
    }

    func testOnlyAHandMadeCollectionTakesTitles() throws {
        let list = try JSONDecoder().decode([TitleCollection].self, from: Data(#"""
        [{"id":1,"ownerId":1,"name":"Watch later","kind":"manual","count":2},{"id":2,"ownerId":1,"name":"Unwatched","kind":"smart"}]
        """#.utf8))
        XCTAssertEqual(list.filter(\.takesTitles).map(\.id), [1])
    }

    func testHomeMakesOneJumpBackInRowThenRecommendationsThenTheRest() throws {
        let json = #"""
        {"hubs":[
          {"key":"recent-1","title":"Recently added in Films","libraryId":1,"items":[{"id":1,"title":"A"}]},
          {"key":"continue","title":"Continue watching","items":[{"id":2,"title":"B"}]},
          {"key":"continue-reading","title":"Continue reading","items":[{"id":3,"title":"C"}]},
          {"key":"recent-2","title":"Recently added in Shows","libraryId":2,"items":[],"shows":[]},
          {"key":"recent-1","title":"Twice","libraryId":1,"items":[{"id":4,"title":"D"}]}]}
        """#
        let home = try JSONDecoder().decode(Home.self, from: Data(json.utf8))
        let rows = HomeRows.rows(home, recommended: Recommended(because: "Sol Levante", items: [], shows: nil))
        XCTAssertEqual(rows.map(\.key), ["jump", "recent-1"], "an empty row, and a second row with the same key, are left out")
        XCTAssertEqual(rows.first?.items?.map(\.id), [2, 3])
        XCTAssertEqual(rows.first?.title, "Jump back in")
        let picked = try JSONDecoder().decode(Recommended.self, from: Data(#"{"because":"Sol Levante","items":[{"id":9,"title":"E"}],"shows":[]}"#.utf8))
        XCTAssertEqual(HomeRows.rows(home, recommended: picked).map(\.title), ["Jump back in", "Because you watch Sol Levante", "Recently added in Films"])
        XCTAssertEqual(Recommended(because: "", items: nil, shows: nil).title, "Recommended for you")
    }

    func testSearchResultsAreGroupedByWhatTheyAre() throws {
        func item(_ id: Int64, library: Int64?) throws -> Item {
            var fields: [String: Any] = ["id": id, "title": "T\(id)"]
            if let library { fields["libraryId"] = library }
            return try JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        let show = try JSONDecoder().decode(Show.self, from: Data(#"{"id":5,"title":"A show"}"#.utf8))
        let types: [Int64: String] = [1: "movies", 2: "music", 3: "books", 4: "anime"]
        let groups = SearchGroups.group(items: try [item(10, library: 2), item(11, library: 1), item(12, library: 3), item(13, library: 9), item(14, library: nil)],
                                        shows: [show], libraryTypes: types)
        XCTAssertEqual(groups.map(\.title), ["Films", "Shows", "Music", "Books", "Everything else"])
        XCTAssertEqual(groups[1].shows.map(\.id), [5])
        XCTAssertEqual(groups.last?.items.map(\.id), [13, 14])
        let unknown = SearchGroups.group(items: try [item(1, library: nil)], shows: [], libraryTypes: [:])
        XCTAssertEqual(unknown.map(\.title), ["Results"], "with nothing else to set them apart, results aren't 'everything else'")
    }
}
