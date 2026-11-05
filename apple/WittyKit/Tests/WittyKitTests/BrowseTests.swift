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
        XCTAssertEqual(LibraryWords.seeAll(35), "See all 35")
        XCTAssertEqual(LibraryWords.seeAll(20), "See all", "a row of 20 already shows them all")
        XCTAssertEqual(LibraryWords.seeAll(nil), "See all")
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

    // MARK: A library's page, as the website's

    func testALibraryWithoutCategoriesStudiosOrNetworksIsAGrid() throws {
        let json = #"""
        {"categories":[],"collections":[{"id":4,"name":"Mine","count":2,"art":[]}],
         "studios":[{"kind":"studio","name":"Ghibli","key":"ghibli","count":3}],"networks":null,
         "platforms":[{"key":"nfx","name":"Netflix","count":5}]}
        """#
        let shelves = try JSONDecoder().decode(Shelves.self, from: Data(json.utf8))
        XCTAssertFalse(shelves.bare, "a studio is enough for shelves")
        XCTAssertEqual(shelves.platforms?.first?.name, "Netflix")
        XCTAssertEqual(shelves.logos, [LogoRef(kind: "studio", name: "Ghibli"), LogoRef(kind: "platform", name: "Netflix")])
        XCTAssertTrue(Shelves(collections: shelves.collections, platforms: shelves.platforms).bare, "collections and services alone aren't")
        let many = Shelves(studios: (0..<50).map { ShelfBrand(kind: "studio", name: "S\($0)", key: "s\($0)", count: 1) })
        XCTAssertEqual(many.logos.count, 40, "the website's shelf shows the first 40")
    }

    func testThePageIsAGridOnceSomethingIsAskedFor() {
        var state = LibraryState()
        XCTAssertFalse(state.asGrid)
        XCTAssertNil(state.shownSort(grid: false))
        XCTAssertTrue(state.grid(bare: true))
        XCTAssertEqual(state.shownSort(grid: true), "title", "a grid is Title A to Z until another is chosen")
        XCTAssertFalse(state.turns)

        state.set("genre", "Drama")
        XCTAssertTrue(state.asGrid)
        XCTAssertFalse(state.turns, "a filter alone has no direction to turn")
        XCTAssertEqual(state.query(library: 3).path(limit: 1), "/browse?library=3&sort=title&genre=Drama&limit=1")
        state.set("genre", "")
        XCTAssertFalse(state.asGrid)
        XCTAssertTrue(LibraryState(all: true).asGrid)

        let rated = LibrarySort.all.first { $0.key == "rating" }!
        state.choose(rated, seed: 5)
        XCTAssertEqual(state.sort, "rating")
        XCTAssertTrue(state.descending)
        XCTAssertNil(state.seed)
        XCTAssertTrue(state.turns)
        state.choose(LibrarySort.all[0], seed: 77)
        XCTAssertEqual(state.query(library: 1).path(limit: 1), "/browse?library=1&sort=shuffle&seed=77&limit=1")
        XCTAssertFalse(state.turns)
        for key in ["newest", "oldest"] { XCTAssertFalse(LibraryState(sort: key).turns) }
        for key in ["added", "title", "quality"] { XCTAssertTrue(LibraryState(sort: key).turns) }
        XCTAssertFalse(LibraryState(sort: "nonsense").turns, "a sort the page doesn't list has no button")
    }

    func testASavedViewIsTheAddressWrittenDown() {
        let state = LibraryState(sort: "rating", descending: true, seed: 9, filters: ["watched": "no", "genre": "Sci-Fi & Fantasy", "decade": "1990"])
        // The filters in the website's order whatever order they were chosen in, then the sort.
        XCTAssertEqual(state.savedQuery, "genre=Sci-Fi+%26+Fantasy&decade=1990&watched=no&sort=rating&desc=1")
        XCTAssertEqual(state.suggestedName, "Sci-Fi & Fantasy, 1990s, Not watched yet")
        let back = LibraryState(query: state.savedQuery)
        XCTAssertEqual(back.filters, state.filters)
        XCTAssertEqual(back.sort, "rating")
        XCTAssertTrue(back.descending)
        XCTAssertNil(back.seed, "a shuffle's seed isn't kept")
        XCTAssertEqual(LibraryState(sort: "shuffle", seed: 4, all: true).address, "sort=shuffle&seed=4&view=all")
        XCTAssertEqual(LibraryState(query: "sort=shuffle&seed=4&view=all"), LibraryState(sort: "shuffle", seed: 4, all: true))
        // What the website saved reads the same, whichever way it escaped a space.
        XCTAssertEqual(LibraryState(query: "studio=Studio%20Ghibli&tag=a%2Bb&library=9&genre=").filters, ["studio": "Studio Ghibli", "tag": "a+b"])
        XCTAssertTrue(LibraryState(query: "view=all").asGrid)
        XCTAssertEqual(LibraryState(query: "").savedQuery, "")
        XCTAssertEqual(LibraryState(filters: ["search": "Amélie"]).savedQuery, "search=Am%C3%A9lie")
        XCTAssertEqual(LibraryState(filters: ["genre": String(repeating: "Drama ", count: 20)]).suggestedName.count, 60)
    }

    func testALibraryAddressOpensThatLibraryWithItsChoices() throws {
        let page = try XCTUnwrap(LibraryState.page("/library/3?genre=Sci-Fi+%26+Fantasy&sort=rating&desc=1"))
        XCTAssertEqual(page.library, 3)
        XCTAssertEqual(page.state, LibraryState(sort: "rating", descending: true, filters: ["genre": "Sci-Fi & Fantasy"]))
        XCTAssertEqual(LibraryState.page("/library/12")?.state, LibraryState())
        XCTAssertEqual(LibraryState.page("/library/4?tag=a%2Bb")?.state.filters, ["tag": "a+b"])
        XCTAssertNil(LibraryState.page("/library/3/fix"))
        XCTAssertNil(LibraryState.page("/brand/studio/Pixar?library=3"))
        XCTAssertNil(LibraryState.page("/library/x?genre=Drama"))
    }

    func testTheFiltersSheetIsInTheWebsitesOrder() {
        XCTAssertEqual(FilterSection.all.map(\.title), ["Category", "Type", "Studio", "Network", "Listed on", "Decade", "Year", "Age rating",
                                                        "Score", "Watched", "Picture", "Sound", "Audio language", "Subtitles", "Edition", "Tags"])
        XCTAssertEqual(BrowseFilter.groups.first { $0.key == "year" }?.limit, 10)
        XCTAssertEqual(BrowseFilter.groups.filter { $0.limit == 16 }.map(\.key), ["studio", "network"])
        let facets = Facets(groups: ["formats": [Facet(value: "none", label: nil, count: 2), Facet(value: "atmos", label: "Dolby Atmos", count: 1)]])
        XCTAssertEqual(BrowseFilter.groups.first { $0.key == "format" }?.choices(in: facets).map(\.value), ["atmos"])
        XCTAssertEqual(BrowseFilter.title(of: "tag"), "Tag")
        XCTAssertEqual(BrowseFilter.title(of: "platform"), "Listed on")
        XCTAssertEqual(BrowseFilter.title(of: "format"), "Sound")
        XCTAssertEqual(BrowseFilter.words("decade", "1980"), "1980s")
        XCTAssertEqual(BrowseFilter.words("disc", "tv"), "TV series")
        XCTAssertEqual(BrowseFilter.words("audio", "jpn"), "Japanese")
        XCTAssertEqual(BrowseFilter.words("subtitle", "mul"), "Several languages")
        XCTAssertEqual(BrowseFilter.words("watched", "yes"), "Watched")
        XCTAssertEqual(BrowseFilter.languageName(""), "Unknown")
        XCTAssertEqual(BrowseFilter.languageName("FRE"), "French")
    }

    func testACategoryWithoutAPictureHasTheWebsitesColours() {
        XCTAssertEqual(CategoryLook.hue("Drama"), 95)
        XCTAssertEqual(CategoryLook.hue("Sci-Fi & Fantasy"), 75)
        XCTAssertEqual(CategoryLook.hue("Ånimé 🎬"), 192, "a character outside the first plane counts as JavaScript reads it")
        XCTAssertEqual(CategoryLook.colours("Drama").from, "#486534")
        XCTAssertEqual(CategoryLook.colours("Drama").to, "#16311d")
        XCTAssertEqual(CategoryLook.hsl(380, 0.38, 0.14), "#311f16", "a hue past 360 goes round")
        let ends = CategoryLook.ends(degrees: 155, aspect: 16.0 / 9.0)
        XCTAssertEqual(ends.start.x, 0.303, accuracy: 0.001)
        XCTAssertEqual(ends.start.y, -0.251, accuracy: 0.001)
        XCTAssertEqual(ends.end.x, 0.697, accuracy: 0.001)
        XCTAssertEqual(ends.end.y, 1.251, accuracy: 0.001)
        let down = CategoryLook.ends(degrees: 180, aspect: 2)
        XCTAssertEqual(down.start.y, 0, accuracy: 0.0001)
        XCTAssertEqual(down.end.x, 0.5, accuracy: 0.0001)
    }

    func testALogoIsTheOneThatReadsOnThePage() {
        XCTAssertEqual(LogoLook.variant(opaque: true, background: 0, 0, 0), "original")
        XCTAssertEqual(LogoLook.variant(opaque: false, background: 0.06, 0.07, 0.08), "white")
        XCTAssertEqual(LogoLook.variant(opaque: false, background: 0.96, 0.94, 0.89), "dark")
        XCTAssertEqual(LogoRef(kind: "studio", name: "  Studio Ghibli ").key, "studio|studio ghibli")
    }

    func testTheLibraryPagesQuestionsGoToTheServer() async throws {
        let stand = try StandInServer { request in
            switch request.path {
            case "/api/v1/views": return StandInServer.answer(body: #"{"views":[{"id":2,"libraryId":3,"name":"Drama","query":"genre=Drama","pinned":true,"position":0}]}"#)
            case "/api/v1/match/queue?library=3&limit=1": return StandInServer.answer(body: #"{"rows":[],"total":4,"counts":{"review":4,"ok":10}}"#)
            case "/api/v1/libraries/3/scan": return StandInServer.answer(body: #"{"scanning":true,"progress":{"libraryId":3,"phase":"files","found":40,"done":12}}"#)
            case "/api/v1/listings/status": return StandInServer.answer(body: #"{"enabled":true,"region":"NL","newest":1700000000,"attribution":"JustWatch"}"#)
            case "/api/v1/logos/lookup": return StandInServer.answer(body: #"{"logos":[{"id":7,"kind":"studio","name":"Ghibli","status":"found","has":true,"version":2,"opaque":false}]}"#)
            default: return StandInServer.answer(status: "404 Not Found", body: #"{"error":"no"}"#)
            }
        }
        addTeardownBlock { stand.stop() }
        let client = WittyClient(base: stand.address, token: "t")
        let views = try await client.savedViews()
        XCTAssertEqual(views.first?.state.filters, ["genre": "Drama"])
        let waiting = try await client.matchesWaiting(library: 3)
        XCTAssertEqual(waiting, 4)
        let scan = try await client.scanState(library: 3)
        XCTAssertEqual(scan.progress.map(ScanState.words), "Scanning… 12/40")
        XCTAssertEqual(ScanState.words(.init()), "Scanning… 0/?")
        let listing = try await client.listingStatus()
        XCTAssertEqual(listing.region, "NL")
        let logos = try await client.logos([LogoRef(kind: "studio", name: "Ghibli")])
        XCTAssertEqual(logos.first?.hasPicture, true)
        XCTAssertEqual(client.logoURL(logos[0], variant: "white")?.absoluteString, "\(stand.address)/api/v1/logos/7/image?variant=white&v=2")
        let none = try await client.logos([])
        XCTAssertTrue(none.isEmpty, "nothing to look up asks nothing")
        XCTAssertEqual(stand.requests.map(\.line).map { String($0.prefix(4)) }, ["GET ", "GET ", "GET ", "GET ", "POST"])
        let body = try JSONSerialization.jsonObject(with: WittyClient.savedViewBody(library: 3, name: "Drama", query: "genre=Drama", pinned: true)) as? [String: Any]
        XCTAssertEqual(body?["libraryId"] as? Int, 3)
        XCTAssertEqual(body?["query"] as? String, "genre=Drama")
        XCTAssertEqual(body?["pinned"] as? Bool, true)
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
