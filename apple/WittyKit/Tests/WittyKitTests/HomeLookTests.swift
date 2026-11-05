import XCTest
@testable import WittyKit

final class HomeLookTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func item(_ json: String) throws -> Item { try decode(Item.self, json) }

    // MARK: Sections

    func testHomeHasTheWebsitesSectionsInTheWebsitesOrder() throws {
        let home = try decode(Home.self, #"""
        {"hubs":[
          {"key":"recent-1","title":"Recently added in Films","libraryId":1,"items":[{"id":1,"title":"A"}]},
          {"key":"view-4","title":"Short films","libraryId":1,"query":"sort=added&maxRuntime=40","items":[{"id":5,"title":"E"}]},
          {"key":"continue-reading","title":"Continue reading","items":[{"id":3,"title":"C"}]},
          {"key":"continue","title":"Continue watching","items":[{"id":2,"title":"B"}]},
          {"key":"nextup","title":"Next up","items":[{"id":6,"title":"F"}]},
          {"key":"recent-1","title":"Twice","libraryId":1,"items":[{"id":4,"title":"D"}]}],
         "featured":[],"libraries":[]}
        """#)
        let widgets = HomeWidgets.list(home, recommended: nil)
        XCTAssertEqual(widgets.map(\.id), ["hero", "libraries", "jump", "onnow", "foryou", "nextup", "view-4", "recent-1", "shuffle"],
                       "a second row with the same key is left out")
        XCTAssertEqual(widgets[2].hub?.items?.map(\.id), [2, 3], "watching before reading, whatever order they came in")
        XCTAssertNil(widgets[4].hub, "no recommendations yet")
        XCTAssertEqual(widgets[6].hub?.query, "sort=added&maxRuntime=40")
        XCTAssertEqual(widgets.last?.title, "Can’t decide?")
        let picked = try decode(Recommended.self, #"{"because":"Sol Levante","items":[{"id":9,"title":"G"}],"shows":[]}"#)
        let forYou = HomeWidgets.list(home, recommended: picked)[4]
        XCTAssertEqual(forYou.title, "Recommended for you")
        XCTAssertEqual(forYou.hub?.title, "Because you watch Sol Levante")
        XCTAssertEqual(Recommended(because: "", items: nil, shows: nil).title, "Recommended for you")
    }

    func testHomeIsEmptyOnlyWithNothingFeaturedAndEveryRowEmpty() throws {
        XCTAssertTrue(HomeWidgets.isEmpty(try decode(Home.self, #"{"hubs":[{"key":"recent-1","title":"R","items":[],"shows":null}],"featured":[]}"#)))
        XCTAssertFalse(HomeWidgets.isEmpty(try decode(Home.self, #"{"hubs":[],"featured":[{"id":1,"title":"A"}]}"#)))
        XCTAssertFalse(HomeWidgets.isEmpty(try decode(Home.self, #"{"hubs":[{"key":"recent-2","title":"R","items":[],"shows":[{"id":3,"title":"S"}]}],"featured":[]}"#)))
    }

    func testASavedLayoutIsReadAsTheWebsiteReadsIt() throws {
        let choices = try decode(HomeChoices.self, #"{"tvLook":{},"home":{"v":2,"order":["shuffle","hero"],"hidden":["continue","continue-reading","onnow"]},"updateLater":"1.4.0"}"#)
        let layout = HomeLayout.saved(choices.home)
        XCTAssertEqual(layout.order, ["shuffle", "hero"])
        XCTAssertEqual(layout.hidden, ["jump", "onnow"], "the old Continue rows hide Jump back in, once")
        XCTAssertEqual(choices.updateLater, "1.4.0")
        let old = HomeLayout.saved(try decode(HomeChoices.self, #"{"home":{"order":["hero","continue"],"hidden":null}}"#).home)
        XCTAssertEqual(old, HomeLayout(), "an order saved before version 2 is dropped")
        XCTAssertEqual(HomeLayout.saved(nil), HomeLayout())
        let unreadable = try decode(HomeChoices.self, #"{"home":"tall","updateLater":7}"#)
        XCTAssertNil(unreadable.home)
        XCTAssertNil(unreadable.updateLater)
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HomeLayout(order: ["a"], hidden: []))) as? [String: Any]
        XCTAssertEqual(written?["v"] as? Int, 2)
        XCTAssertEqual(written?["order"] as? [String], ["a"])
    }

    func testTheSavedOrderComesFirstThenTheRestInTheWebsitesOrder() throws {
        let home = try decode(Home.self, #"{"hubs":[{"key":"recent-1","title":"R","items":[]}],"featured":[]}"#)
        let widgets = HomeWidgets.list(home, recommended: nil)
        let layout = HomeLayout(order: ["shuffle", "recent-1", "gone"], hidden: [])
        let ordered = layout.ordered(widgets).map(\.id)
        XCTAssertEqual(ordered, ["shuffle", "recent-1", "hero", "libraries", "jump", "onnow", "foryou"])
        let moved = layout.moving("hero", to: 0, among: ordered)
        XCTAssertEqual(moved.order, ["hero", "shuffle", "recent-1", "libraries", "jump", "onnow", "foryou"])
        XCTAssertEqual(layout.moving("shuffle", to: 99, among: ordered).order.last, "shuffle")
        XCTAssertEqual(layout.toggling("onnow").hidden, ["onnow"])
        XCTAssertEqual(layout.toggling("onnow").toggling("onnow").hidden, [])
    }

    func testTheGreetingFollowsTheClock() {
        XCTAssertEqual(HomeGreeting.line(hour: 5, name: "Willow"), "Good morning, Willow")
        XCTAssertEqual(HomeGreeting.line(hour: 12, name: ""), "Good afternoon")
        XCTAssertEqual(HomeGreeting.words(hour: 17), "Good afternoon")
        XCTAssertEqual(HomeGreeting.words(hour: 18), "Good evening")
        XCTAssertEqual(HomeGreeting.words(hour: 4), "Good evening")
    }

    // MARK: The hero

    func testRunTimesAreTheWebsites() {
        XCTAssertEqual(Runtime.words(nil), "")
        XCTAssertEqual(Runtime.words(0), "")
        XCTAssertEqual(Runtime.words(30), "30 s")
        XCTAssertEqual(Runtime.words(0.2), "1 s")
        XCTAssertEqual(Runtime.words(2700), "45 min")
        XCTAssertEqual(Runtime.words(6720), "1 h 52 min")
    }

    func testTheHerosFactsAreADottedRowWithTheRatingAndScoreAndDisc() throws {
        let film = try item(#"{"id":1,"title":"A","kind":"video","year":2019,"runtimeSec":6720,"contentRating":"PG-13","rating":7.46,"genres":["Drama","War","History","Family"]}"#)
        XCTAssertEqual(HeroLook.facts(film), [.text("2019"), .text("1 h 52 min"), .rating("PG-13"), .score("7.5"), .text("Drama"), .text("War"), .text("History")])
        let disc = try item(#"{"id":2,"title":"B","kind":"dvd-iso","rating":0,"genres":[]}"#)
        XCTAssertEqual(HeroLook.facts(disc), [.text("DVD · interactive menus")], "menus not known count as there")
        let plain = try item(#"{"id":3,"title":"C","kind":"bluray-folder","disc":{"hasMenus":false}}"#)
        XCTAssertEqual(HeroLook.facts(plain), [.text("Blu-ray")])
        XCTAssertFalse(plain.hasDiscMenus)
        XCTAssertFalse(disc.hasDiscMenus, "only a disc known to have menus has the Disc menu button")
        XCTAssertTrue(try item(#"{"id":4,"title":"D","kind":"dvd-folder","disc":{"hasMenus":true}}"#).hasDiscMenus)
    }

    func testTheMainButtonIsWordedForWhatItIsAndGoesWhereItsPlayed() throws {
        let film = try item(#"{"id":1,"title":"A","kind":"video"}"#)
        XCTAssertEqual(OpenLook.label(film), "Play")
        XCTAssertEqual(OpenLook.action(film), .player(startOver: true))
        let started = try item(#"{"id":1,"title":"A","kind":"video","progress":{"resumeSec":120}}"#)
        XCTAssertEqual(OpenLook.label(started), "Resume")
        XCTAssertEqual(OpenLook.action(started), .player(startOver: false))
        let disc = try item(#"{"id":2,"title":"B","kind":"dvd-iso"}"#)
        XCTAssertEqual(OpenLook.label(disc), "Play")
        XCTAssertEqual(OpenLook.action(disc), .page("/play/2"), "a disc plays in the server's player")
        XCTAssertEqual(OpenLook.discMenu(disc), "/play/2?mode=menu")
        let book = try item(#"{"id":3,"title":"C","kind":"book","reader":"epub"}"#)
        XCTAssertEqual(OpenLook.label(book), "Read")
        XCTAssertEqual(OpenLook.action(book), .page("/read/3"))
        XCTAssertEqual(OpenLook.action(try item(#"{"id":3,"title":"C","kind":"book"}"#)), .page("/item/3"))
        let song = try item(#"{"id":4,"title":"D","kind":"audio","progress":{"resumeSec":40}}"#)
        XCTAssertEqual(OpenLook.label(song), "Continue listening")
        XCTAssertEqual(OpenLook.action(song), .listen)
        let cd = try item(#"{"id":5,"title":"E","kind":"cd-image"}"#)
        XCTAssertEqual(OpenLook.label(cd), "Insert disc")
        XCTAssertEqual(OpenLook.action(cd), .page("/cd/5?play=1"))
        XCTAssertEqual(OpenLook.action(try item(#"{"id":6,"title":"F","kind":"game","console":"snes"}"#)), .page("/game/6"))
        XCTAssertEqual(OpenLook.action(try item(#"{"id":7,"title":"G","kind":"game","console":"rig"}"#)), .item)
    }

    // MARK: Cards

    func testAFilmCardSaysItsYearAndLengthWithItsPlates() throws {
        let film = try item(#"{"id":1,"title":"A","kind":"bluray-iso","year":2001,"runtimeSec":5400,"progress":{"watched":true,"positionSec":5000,"durationSec":5400}}"#)
        let look = CardLook.item(film)
        XCTAssertEqual(look.title, "A")
        XCTAssertEqual(look.subtitle, "2001 · 1 h 30 min")
        XCTAssertEqual(look.shape, .poster)
        XCTAssertEqual(look.badges, [.disc("Blu-ray"), .seen])
        XCTAssertNil(look.progress, "no bar once it's watched")
        let going = try item(#"{"id":2,"title":"B","kind":"video","progress":{"positionSec":30,"durationSec":120}}"#)
        XCTAssertEqual(CardLook.item(going).progress, 0.25)
        XCTAssertEqual(CardLook.item(going).subtitle, "")
    }

    func testAnEpisodeIsAWideStillWithItsShowsName() throws {
        let episode = try item(#"{"id":1,"title":"Pilot","kind":"video","showId":4,"showTitle":"The Show","season":1,"episode":2,"runtimeSec":1500}"#)
        let wide = CardLook.item(episode)
        XCTAssertEqual(wide.shape, .wide)
        XCTAssertEqual(wide.title, "The Show")
        XCTAssertEqual(wide.subtitle, "S1 · E2 · Pilot")
        let poster = CardLook.item(episode, wide: false)
        XCTAssertEqual(poster.shape, .poster)
        XCTAssertEqual(poster.title, "Pilot")
        XCTAssertEqual(poster.subtitle, "S1 · E2 · 25 min")
    }

    func testSongsBooksAndCDsSayWhoTheyreBy() throws {
        let song = CardLook.item(try item(#"{"id":1,"title":"One","kind":"audio","album":"Album","artist":"Solo","albumArtist":""}"#))
        XCTAssertEqual(song.title, "One")
        XCTAssertEqual(song.subtitle, "Solo")
        XCTAssertEqual(song.shape, .square)
        let cd = CardLook.item(try item(#"{"id":2,"title":"Live","kind":"cd-image","albumArtist":"Band","runtimeSec":3000}"#))
        XCTAssertEqual(cd.badges, [.disc("CD")])
        XCTAssertEqual(cd.subtitle, "Band")
        XCTAssertEqual(CardLook.item(try item(#"{"id":3,"title":"Book","kind":"book","year":1999,"runtimeSec":300}"#)).subtitle, "1999")
        XCTAssertEqual(CardLook.item(try item(#"{"id":3,"title":"Book","kind":"book","artist":"Author"}"#)).subtitle, "Author")
    }

    func testAShowCardCountsItsSeasonsAndWhatsLeft() throws {
        let show = CardLook.show(try decode(Show.self, #"{"id":1,"title":"S","year":2019,"seasonCount":3,"episodeCount":30,"unwatched":4}"#))
        XCTAssertEqual(show.subtitle, "2019 · 3 seasons")
        XCTAssertEqual(show.badges, [.unwatched(4)])
        let seen = CardLook.show(try decode(Show.self, #"{"id":2,"title":"T","seasonCount":1,"episodeCount":8,"unwatched":0}"#))
        XCTAssertEqual(seen.subtitle, "1 season")
        XCTAssertEqual(seen.badges, [.seen])
        let fresh = CardLook.show(try decode(Show.self, #"{"id":3,"title":"U","seasonCount":1,"episodeCount":8,"unwatched":8}"#))
        XCTAssertEqual(fresh.badges, [], "nothing watched yet: no count")
    }

    func testCommercialsStayOutOfHomeUnlessSwitchedOn() throws {
        let libraries = try decode([Library].self, #"""
        [{"id":1,"name":"Films","type":"movies","scanning":true},{"id":2,"name":"Ads","type":"commercials"},{"id":3,"name":"Spots","type":"commercials","showMain":true}]
        """#)
        XCTAssertEqual(libraries.filter(\.inMainMenus).map(\.id), [1, 3])
        XCTAssertEqual(libraries.first?.scanning, true)
    }

    // MARK: On TV now

    func testOnNowPutsFavouritesFirstAndSaysWhatsOn() throws {
        let guide = try decode(Guide.self, #"""
        {"channels":[
          {"key":"a","number":"1","name":"One","kind":"tuner","programmes":[{"start":1000,"end":4600,"title":"News","itemId":null}]},
          {"key":"b","number":"2","name":"Two","kind":"library","favourite":true,"programmes":[{"start":0,"end":900,"title":"Gone"}]},
          {"key":"c","number":"3","name":"Three","kind":"tuner","favourite":true,"programmes":[{"start":1000,"end":9000,"title":"Film","itemId":12}]}]}
        """#)
        let channels = OnNowLook.ordered(guide.channels ?? [])
        XCTAssertEqual(channels.map(\.key), ["b", "c", "a"])
        XCTAssertEqual(OnNowLook.title(channels[0], at: 1300), "Off air")
        XCTAssertEqual(OnNowLook.detail(channels[0], at: 1300), "Two")
        XCTAssertEqual(OnNowLook.title(channels[1], at: 1300), "Film")
        XCTAssertEqual(OnNowLook.programme(channels[1], at: 1300)?.itemId, 12)
        XCTAssertEqual(OnNowLook.detail(channels[2], at: 1300), "One · 55 min left")
        XCTAssertEqual(OnNowLook.fraction(channels[2], at: 1900), 0.25)
        XCTAssertEqual(OnNowLook.title(channels[2], at: 5000), "No guide data")
        XCTAssertEqual(OnNowLook.spoken(channels[2], at: 1300), "Channel 1, One: News")
        XCTAssertEqual(OnNowLook.spoken(channels[0], at: 1300), "Channel 2, Two: nothing listed")
        XCTAssertEqual(OnNowLook.left(20), "1 min")
        XCTAssertEqual(OnNowLook.left(3900), "1h 5m")
        XCTAssertEqual(OnNowLook.left(7200), "2h")
    }

    func testCantDecideSaysTheYearLengthAndTwoGenres() throws {
        XCTAssertEqual(ShuffleLook.facts(try item(#"{"id":1,"title":"A","year":1994,"runtimeSec":8520,"genres":["Crime","Drama","Thriller"]}"#)),
                       "1994 · 2 h 22 min · Crime, Drama")
        XCTAssertEqual(ShuffleLook.facts(try item(#"{"id":1,"title":"A","genres":[]}"#)), "")
    }

    // MARK: A newer server

    func testTheUpdateNoticeIsForAdminsUntilTheyPutItOff() {
        XCTAssertTrue(UpdateNews.shows(update: "1.5.0", isAdmin: true, later: nil))
        XCTAssertTrue(UpdateNews.shows(update: "1.5.0", isAdmin: true, later: "1.4.0"), "Later was for an older version")
        XCTAssertFalse(UpdateNews.shows(update: "1.5.0", isAdmin: true, later: "1.5.0"))
        XCTAssertFalse(UpdateNews.shows(update: "1.5.0", isAdmin: false, later: nil))
        XCTAssertFalse(UpdateNews.shows(update: "", isAdmin: true, later: nil))
        XCTAssertEqual(UpdateNews.title("1.5.0"), "WittyMediaServer 1.5.0 is available")
    }

    func testTheUpdateNoticeLeadsWithTheNewestChange() throws {
        let status = try decode(UpdateStatus.self, #"""
        {"current":"1.4.0","method":"docker","phase":"idle","canApply":false,"latest":{"version":"1.5.0","changes":[
          {"version":"1.5.0","notes":"Intro\n- **DVDs and Blu-rays in Firefox.** They play now.\n- A [link](https://example.com) fixed\n"},
          {"version":"1.4.1","notes":"* `code` change:\n+ third"}]}}
        """#)
        XCTAssertEqual(UpdateNews.headline(status.latest?.changes ?? []).first, "DVDs and Blu-rays in Firefox")
        XCTAssertEqual(UpdateNews.sentence(status), "DVDs and Blu-rays in Firefox, and 3 more changes.")
        XCTAssertEqual(UpdateNews.action(status), "How to update")
        XCTAssertEqual(UpdateNews.action(nil), "Update")
        let links = UpdateNews.headline([UpdateChange(version: "1", notes: "- See [the guide](/help/x) for `more`.")])
        XCTAssertEqual(links.first, "See the guide for more")
        XCTAssertEqual(links.more, 0)
        let long = String(repeating: "word ", count: 30)
        let cut = UpdateNews.headline([UpdateChange(version: "1", notes: "- " + long)]).first
        XCTAssertTrue(cut.hasSuffix("word…"), cut)
        XCTAssertLessThanOrEqual(cut.count, 89)
        XCTAssertEqual(UpdateNews.sentence(try decode(UpdateStatus.self, #"{"current":"1"}"#)), "A newer version of the server is ready to install.")
        XCTAssertEqual(UpdateNews.sentence(try decode(UpdateStatus.self, #"{"latest":{"version":"2","changes":[{"version":"2","notes":"- One\n- Two"}]}}"#)),
                       "One, and 1 more change.")
    }

    // MARK: What's asked of the server

    private func server(_ respond: @escaping @Sendable (StandInServer.Request) -> Data) throws -> StandInServer {
        let made = try StandInServer(respond: respond)
        addTeardownBlock { made.stop() }
        return made
    }

    func testHomeAsksForWhatTheWebsiteAsksFor() async throws {
        let stand = try server { request in
            if request.path.hasPrefix("/api/v1/items") { return StandInServer.answer(body: #"{"items":[{"id":8,"title":"Random"}],"total":1}"#) }
            if request.path.hasPrefix("/api/v1/guide") { return StandInServer.answer(body: #"{"channels":[]}"#) }
            return StandInServer.answer(body: #"{"home":{"v":2,"order":["shuffle"],"hidden":[]},"updateLater":"1.2.0"}"#)
        }
        let client = WittyClient(base: stand.address, token: "t")
        let picked = try await client.shuffle()
        XCTAssertEqual(picked?.id, 8)
        _ = try await client.onNow()
        let choices = try await client.homeChoices()
        XCTAssertEqual(choices.home?.order, ["shuffle"])
        XCTAssertEqual(stand.requests.map(\.path), [
            "/api/v1/items?sort=random&limit=1&noEpisodes=1&watchable=1",
            "/api/v1/guide?hours=1&limit=16",
            "/api/v1/me/ui",
        ])
    }

    func testSavingTheLayoutKeepsTheAccountsOtherChoices() async throws {
        let stand = try server { request in
            request.line.hasPrefix("PUT") ? StandInServer.answer(body: "{}") : StandInServer.answer(body: #"{"tvLook":{"theme":"x"},"home":{"v":1}}"#)
        }
        let client = WittyClient(base: stand.address, token: "t")
        try await client.saveHomeLayout(HomeLayout(order: ["hero"], hidden: ["onnow"]))
        XCTAssertEqual(stand.requests.map(\.line).map { $0.split(separator: " ").prefix(2).joined(separator: " ") }, ["GET /api/v1/me/ui", "PUT /api/v1/me/ui"])
    }
}
