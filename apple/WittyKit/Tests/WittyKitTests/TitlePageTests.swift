import XCTest
@testable import WittyKit

final class TitlePageTests: XCTestCase {
    private func item(_ json: String) throws -> Item { try JSONDecoder().decode(Item.self, from: Data(json.utf8)) }
    private func facts(_ json: String) throws -> ItemFacts { try JSONDecoder().decode(ItemFacts.self, from: Data(json.utf8)) }

    private let film = #"""
    {"id":7,"libraryId":2,"kind":"video","title":"Arrival","year":2016,"runtimeSec":6960,"rating":7.9,"poster":"tmdb:abc",
     "provider":"tmdb","providerId":"329865","width":1920,"height":800,"videoCodec":"hevc","container":"matroska,webm",
     "audioLangs":["eng","en","fre"],"subLangs":null,"sizeBytes":4210000000,"path":"/films/Arrival.mkv",
     "progress":{"positionSec":754,"durationSec":6960,"watched":false,"resumeSec":750}}
    """#

    private let dvd = #"""
    {"id":9,"libraryId":4,"kind":"dvd-iso","title":"Heat","startMode":"title","insertEffect":false,"width":720,"height":576,"videoCodec":"mpeg2video",
     "disc":{"label":"HEAT","format":"dvd","hasMenus":true,"mainTitle":2,"scrambled":false,"content":"movie",
             "titles":[{"number":1,"durationSec":30,"wide":false,"standard":"pal"},{"number":2,"durationSec":9000,"wide":true,"standard":"pal"}]},
     "sizeBytes":7800000000,"progress":{"positionSec":61,"durationSec":9000,"watched":false,"resumeSec":60,"discTitle":3}}
    """#

    func testAnItemsPageReadsItsFactsBesideTheItem() throws {
        let facts = try facts(film)
        XCTAssertEqual(facts.rating, 7.9)
        XCTAssertEqual(facts.width, 1920)
        XCTAssertEqual(facts.audioLangs, ["eng", "en", "fre"])
        XCTAssertNil(facts.subLangs)
        XCTAssertEqual(facts.sizeBytes, 4_210_000_000)
        XCTAssertEqual(try item(film).title, "Arrival")
        // One odd fact is only absent: the page still shows.
        let odd = try self.facts(#"{"id":1,"title":"x","width":"wide","providerId":42,"disc":"none"}"#)
        XCTAssertNil(odd.width)
        XCTAssertEqual(odd.providerId, "42")
        XCTAssertNil(odd.disc)
        XCTAssertEqual(try self.facts(dvd).discTitle, 3)
    }

    func testAShowsFactsComeFromItsShow() throws {
        let json = #"""
        {"show":{"id":3,"title":"Severance","libraryId":5,"genres":["Drama","Mystery"],"contentRating":"TV-MA","network":"Apple TV+",
                 "status":"Running","provider":"tmdb-tv","providerId":"95396","view":"list","updatedAt":12},
         "seasons":[{"number":1,"title":"Season 1","episodeCount":9,"unwatched":3}],"episodes":[],"nextUpId":null}
        """#
        let facts = try JSONDecoder().decode(ShowFacts.self, from: Data(json.utf8))
        XCTAssertEqual(facts.network, "Apple TV+")
        XCTAssertEqual(facts.view, "list")
        XCTAssertEqual(facts.libraryId, 5)
        XCTAssertEqual(try JSONDecoder().decode(ShowDetail.self, from: Data(json.utf8)).show.title, "Severance")
    }

    func testWhatIsAttachedToATitleReadsNullsAsNothing() throws {
        let json = #"""
        {"extras":[{"item":{"id":20,"title":"Making of","kind":"video"},"link":{"extraType":"behind-the-scenes"}}],
         "versions":[{"item":{"id":21,"title":"Arrival","height":2160},"link":{"label":"Director's cut"}},{"item":{"id":22,"title":"Arrival"},"link":null}],
         "studios":null,"director":"Denis Villeneuve","edition":["Remastered"],"tags":null,"hasBanner":false,"hasLogo":true}
        """#
        let attached = try JSONDecoder().decode(TitleAttached.self, from: Data(json.utf8))
        XCTAssertNil(attached.studios)
        XCTAssertEqual(attached.hasLogo, true)
        XCTAssertEqual(attached.versions?.map(TitleLook.versionLabel), ["Director's cut · 2160p", "Arrival"])
        XCTAssertEqual(attached.extras?.map { TitleLook.extraName($0.link?.extraType) }, ["Behind the scenes"])
        XCTAssertEqual(TitleLook.extraName(nil), "Extra")
    }

    func testTimesAreSaidAsTheWebsiteSaysThem() {
        XCTAssertEqual(TitleLook.runtime(6960), "1 h 56 min")
        XCTAssertEqual(TitleLook.runtime(2700), "45 min")
        XCTAssertEqual(TitleLook.runtime(40.4), "40 s")
        XCTAssertEqual(TitleLook.runtime(0), "")
        XCTAssertEqual(TitleLook.runtime(nil), "")
        XCTAssertEqual(TitleLook.clock(754), "12:34")
        XCTAssertEqual(TitleLook.clock(3725), "1:02:05")
        XCTAssertEqual(TitleLook.clock(-3), "0:00")
    }

    func testCodecsAndLanguagesHaveTheNamesPeopleKnow() {
        XCTAssertEqual(TitleLook.codec("hevc"), "HEVC")
        XCTAssertEqual(TitleLook.codec("mpeg2video"), "MPEG-2")
        XCTAssertEqual(TitleLook.codec("theora"), "THEORA")
        XCTAssertEqual(TitleLook.language("ger"), "German")
        XCTAssertEqual(TitleLook.language(""), "Unknown")
        XCTAssertEqual(TitleLook.language("x-klingon"), "X-KLINGON")
        // English twice, as "eng" and "en", is said once.
        XCTAssertEqual(TitleLook.languages(["eng", "en", "fre"]), "English, French")
    }

    func testFourGenresShowAndMoreAreAnEllipsis() {
        XCTAssertEqual(TitleLook.genres(["A", "B"]).shown, ["A", "B"])
        XCTAssertFalse(TitleLook.genres(["A", "B"]).more)
        let five = TitleLook.genres(["A", "B", "C", "D", "E"])
        XCTAssertEqual(five.shown, ["A", "B", "C", "D"])
        XCTAssertTrue(five.more)
    }

    func testTheCaptionIsTheLibraryOrTheShowItsSeasonAndTheEpisode() throws {
        let episode = try item(#"{"id":5,"libraryId":2,"title":"Pilot","showId":3,"showTitle":"Severance","season":1,"episode":2}"#)
        XCTAssertEqual(TitleLook.crumbs(episode, libraryName: "TV").map(\.words), ["Severance", "Season 1", "S1 · E2"])
        XCTAssertEqual(TitleLook.crumbs(episode, libraryName: "TV")[1].goes, .show(3, season: 1))
        XCTAssertEqual(TitleLook.crumbs(episode, libraryName: nil).last?.goes, .nowhere)
        let special = try item(#"{"id":6,"title":"Xmas","showId":3,"showTitle":"Severance","season":0,"episode":1}"#)
        XCTAssertEqual(TitleLook.crumbs(special, libraryName: nil).map(\.words), ["Severance", "Specials", "Special · E1"])
        let film = try item(film)
        XCTAssertEqual(TitleLook.crumbs(film, libraryName: "Films"), [TitleLook.Crumb(words: "Films", goes: .library(2))])
        XCTAssertTrue(TitleLook.crumbs(film, libraryName: nil).isEmpty)
    }

    func testTheFactsTableSaysWhatTheFileIs() throws {
        let rows = TitleLook.facts(try item(film), try facts(film), admin: false)
        XCTAssertEqual(rows, [
            TitleLook.Fact("Video", "1920×800 HEVC"),
            TitleLook.Fact("Audio", "English, French"),
            TitleLook.Fact("Source", "MATROSKA,WEBM · 4.21 GB"),
        ])
        XCTAssertEqual(TitleLook.facts(try item(film), try facts(film), admin: true).last, TitleLook.Fact("File", "/films/Arrival.mkv", wide: true))
        let disc = TitleLook.facts(try item(dvd), try facts(dvd), admin: false)
        XCTAssertEqual(disc.map(\.value), ["720×576 MPEG-2 · PAL 16:9", "DVD image · 7.80 GB", "HEAT · 2 titles · menus"])
        // Nothing known but the item: still where it came from.
        XCTAssertEqual(TitleLook.facts(try item(#"{"id":1,"title":"x"}"#), ItemFacts(), admin: false), [TitleLook.Fact("Source", "")])
    }

    func testTheFactsTakeAsManyColumnsAsFit() {
        XCTAssertEqual(TitleLook.factColumns(width: 358), 1)
        XCTAssertEqual(TitleLook.factColumns(width: 364), 2)
        XCTAssertEqual(TitleLook.factColumns(width: 600), 3)
        XCTAssertEqual(TitleLook.factColumns(width: 10), 1)
    }

    func testMoreHoldsWhatTheRowHasNoRoomFor() throws {
        let film = try item(film)
        XCTAssertEqual(TitleLook.moreRows(film, try facts(self.film), admin: false), [.playFromStart])
        XCTAssertEqual(TitleLook.moreRows(film, try facts(self.film), admin: true), [.playFromStart, .artwork, .edit, .refresh])
        // Nothing to start again and no next episode: no "⋯" at all.
        let fresh = try item(#"{"id":1,"title":"x","kind":"video"}"#)
        XCTAssertTrue(TitleLook.moreRows(fresh, ItemFacts(), admin: false).isEmpty)
        // An episode is refreshed with its show.
        let episode = try item(#"{"id":5,"title":"Pilot","kind":"video","showId":3,"nextId":6}"#)
        XCTAssertEqual(TitleLook.moreRows(episode, ItemFacts(), admin: true), [.nextEpisode(6), .artwork, .edit])
        let disc = TitleLook.moreRows(try item(dvd), try facts(dvd), admin: true)
        XCTAssertEqual(disc, [.resumeDisc("Resume from 1:01", path: "/play/9?mode=title&ttn=3"), .mainMenu(path: "/play/9?mode=menu"),
                              .discSettings, .artwork, .edit, .refresh])
        let tv = ItemFacts(disc: DiscInfo(hasMenus: false, mainTitle: 1, content: "tv"))
        XCTAssertEqual(TitleLook.moreRows(try item(#"{"id":4,"title":"x","kind":"dvd-folder"}"#), tv, admin: false),
                       [.discFromStart("Play from the start", path: "/play/4?mode=title&start=0")])
        XCTAssertEqual(TitleLook.MoreRow.discFromStart("Play movie", path: "").words, "Play movie")
    }

    func testADiscStartsAsItsSettingsSay() throws {
        let heat = try item(dvd), facts = try facts(dvd)
        XCTAssertEqual(TitleLook.insertPath(heat, facts), "/play/9?mode=title")
        XCTAssertEqual(TitleLook.discHint(heat, facts, admin: false), "Insert DVD starts with the main feature.")
        let usual = ItemFacts()
        XCTAssertEqual(TitleLook.insertPath(heat, usual), "/play/9?mode=menu&insert=1")
        XCTAssertEqual(TitleLook.discHint(heat, usual, admin: true), "Insert DVD starts with the disc menu · with the tray effect — change it in Disc settings.")
        let bluray = try item(#"{"id":2,"title":"x","kind":"bluray-folder"}"#)
        XCTAssertEqual(TitleLook.discName(bluray), "Blu-ray")
        XCTAssertTrue(TitleLook.isDisc(bluray))
        XCTAssertFalse(TitleLook.isDisc(try item(film)))
        XCTAssertFalse(TitleLook.playable(heat, ItemFacts(disc: DiscInfo(scrambled: true))))
        XCTAssertTrue(TitleLook.playable(heat, facts))
    }

    func testASeasonSaysHowManyAreLeft() {
        func season(_ count: Int, _ left: Int?) -> Season {
            try! JSONDecoder().decode(Season.self, from: Data(#"{"number":1,"episodeCount":\#(count)\#(left.map { ",\"unwatched\":\($0)" } ?? "")}"#.utf8))
        }
        XCTAssertEqual(TitleLook.seasonLine(season(10, 3)), "10 ep · 3 left")
        XCTAssertEqual(TitleLook.seasonLine(season(10, 0)), "10 ep · watched")
        XCTAssertEqual(TitleLook.seasonLine(season(10, 10)), "10 ep")
        XCTAssertEqual(TitleLook.seasonLine(season(10, nil)), "10 ep")
    }

    func testAShowOpensAtTheNextEpisodesSeason() throws {
        let json = #"""
        {"show":{"id":3,"title":"S"},"nextUpId":12,
         "seasons":[{"number":0,"episodeCount":1},{"number":1,"episodeCount":2},{"number":2,"episodeCount":1}],
         "episodes":[{"id":10,"title":"a","season":1,"episode":1},{"id":11,"title":"b","season":1,"episode":2},
                     {"id":12,"title":"c","season":2,"episode":1,"progress":{"positionSec":125,"resumeSec":120}},{"id":13,"title":"d"}]}
        """#
        let detail = try JSONDecoder().decode(ShowDetail.self, from: Data(json.utf8))
        XCTAssertEqual(TitleLook.openingSeason(detail, asked: nil), 2)
        XCTAssertEqual(TitleLook.openingSeason(detail, asked: 1), 1)
        XCTAssertEqual(TitleLook.episodes(detail, season: 1).map(\.id), [10, 11])
        XCTAssertEqual(TitleLook.episodes(detail, season: -1).map(\.id), [13])
        XCTAssertEqual(TitleLook.otherVideos(detail).map(\.id), [13])
        let next = try XCTUnwrap(detail.episodes?.first { $0.id == 12 })
        XCTAssertEqual(TitleLook.playLabel(next).words, "Resume S2 · E1")
        XCTAssertEqual(TitleLook.playLabel(next).spoken, "Resume S2 · E1 from 2:05")
        XCTAssertEqual(TitleLook.playLabel(detail.episodes![0]).words, "Play S1 · E1")
        XCTAssertNil(TitleLook.playLabel(detail.episodes![0]).spoken)
        XCTAssertEqual(TitleLook.playLabel(detail.episodes![3]).words, "Play d")
        XCTAssertEqual(TitleLook.playlistNumber(detail.episodes![1]), "E2")
        XCTAssertEqual(TitleLook.playlistNumber(detail.episodes![3]), "–")
        // Nothing next: the first real season, not Specials.
        let quiet = try JSONDecoder().decode(ShowDetail.self, from: Data(json.replacingOccurrences(of: #""nextUpId":12"#, with: #""nextUpId":null"#).utf8))
        XCTAssertEqual(TitleLook.openingSeason(quiet, asked: nil), 1)
    }

    func testAShowsWordsAreTheWebsites() throws {
        XCTAssertEqual(TitleLook.seasonsLine(seasons: 1, episodes: 1), "1 season · 1 episodes")
        XCTAssertEqual(TitleLook.seasonsLine(seasons: 3, episodes: 24), "3 seasons · 24 episodes")
        XCTAssertEqual(TitleLook.episodeView(chosen: nil, show: "", server: "list"), "list")
        XCTAssertEqual(TitleLook.episodeView(chosen: "cards", show: "list", server: "list"), "cards")
        XCTAssertEqual(TitleLook.episodeView(chosen: "", show: "list", server: nil), "list")
        XCTAssertEqual(TitleLook.episodeView(chosen: nil, show: nil, server: nil), "cards")
        let episode = try item(#"{"id":1,"title":"x","aired":"2022-02-18","runtimeSec":3420}"#)
        XCTAssertEqual(TitleLook.episodeLine(episode), "2022-02-18 · 57 min")
        XCTAssertEqual(TitleLook.episodeLine(try item(#"{"id":1,"title":"x"}"#)), "")
    }

    func testTheCreditNamesWhereTheDetailsCameFrom() {
        XCTAssertEqual(TitleLook.credit(provider: "tvmaze", id: "82"),
                       "TV information from [TVmaze](https://www.tvmaze.com/shows/82), shared under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).")
        XCTAssertNotNil(TitleLook.credit(provider: "tmdb", id: "1"))
        XCTAssertNil(TitleLook.credit(provider: "tmdb", id: "1", show: true))
        XCTAssertNotNil(TitleLook.credit(provider: "tmdb-tv", id: "1", show: true))
        XCTAssertNil(TitleLook.credit(provider: "wikidata", id: "Q1", show: true))
        XCTAssertNil(TitleLook.credit(provider: "", id: nil))
        // An id can't break out of its link.
        XCTAssertEqual(TitleLook.credit(provider: "anilist", id: "1) [x](y"), "Anime information from [AniList](https://anilist.co/anime/1%29%20%5Bx%5D%28y).")
    }

    func testLinksGoWhereTheWebsitesGo() {
        XCTAssertEqual(TitleLook.genrePath(library: 2, "Sci-Fi & Fantasy"), "/library/2?genre=Sci-Fi%20%26%20Fantasy")
        XCTAssertEqual(TitleLook.brandPath("network", "Apple TV+", library: 5), "/brand/network/Apple%20TV%2B?library=5")
        XCTAssertEqual(TitleLook.editPath(.show, 3, section: "artwork"), "/show/3?edit=artwork")
        XCTAssertEqual(TitleLook.editPath(.item, 7), "/item/7")
    }

    func testSizesFollowTheWebsitesClamps() {
        XCTAssertEqual(TitleLook.titleSize(width: 390), 28.21, accuracy: 0.01)
        XCTAssertEqual(TitleLook.titleSize(width: 320), 28)
        XCTAssertEqual(TitleLook.titleSize(width: 2000), 44)
        XCTAssertEqual(TitleLook.heroHeight(window: 852), 323.76, accuracy: 0.01)
        XCTAssertEqual(TitleLook.heroHeight(window: 500), 240)
        XCTAssertEqual(TitleLook.heroHeight(window: 2000), 560)
    }

    func testAFrameOfTheVideoGetsAColourOfItsOwn() {
        XCTAssertTrue(TitleLook.isFrame(poster: "cache:frame-12.jpg"))
        XCTAssertFalse(TitleLook.isFrame(poster: "tmdb:abc"))
        XCTAssertEqual(TitleLook.artHue("Arrival"), TitleLook.artHue("Arrival"))
        XCTAssertEqual(TitleLook.artHue("ab"), (97 * 31 + 98) % 360)
        let red = TitleLook.rgb(hue: 0, saturation: 1, lightness: 0.5)
        XCTAssertEqual(red.0, 1, accuracy: 0.001)
        XCTAssertEqual(red.1, 0, accuracy: 0.001)
        let teal = TitleLook.rgb(hue: 180 + 360, saturation: 0.5, lightness: 0.25)
        XCTAssertEqual(teal.0, 0.125, accuracy: 0.001)
        XCTAssertEqual(teal.2, 0.375, accuracy: 0.001)
    }

    func testOnlySomeoneWhoMayPostOrAKidSaves() {
        XCTAssertTrue(TitleLook.canSave(isAdmin: false, kind: "adult"))
        XCTAssertTrue(TitleLook.canSave(isAdmin: false, kind: "kids"))
        XCTAssertTrue(TitleLook.canSave(isAdmin: false, kind: nil))
        XCTAssertFalse(TitleLook.canSave(isAdmin: false, kind: "guest"))
        XCTAssertTrue(TitleLook.canSave(isAdmin: true, kind: "guest"))
    }

    func testALegalNoticeIsTheServersWordsWithItsLink() throws {
        let json = #"""
        {"version":1,"linkText":"Legal","notices":{"metadata":{"text":"Details come from elsewhere.","section":"third-party"},"empty":{"text":""}}}
        """#
        let notices = try JSONDecoder().decode(LegalNotices.self, from: Data(json.utf8))
        let note = try XCTUnwrap(notices.notice("metadata"))
        XCTAssertEqual(note.words, "Details come from elsewhere.")
        XCTAssertEqual(note.link, "Legal")
        XCTAssertEqual(note.path, "/settings/legal#third-party")
        XCTAssertNil(notices.notice("empty"))
        XCTAssertNil(notices.notice("newer"))
    }

    func testALogoIsMatchedByItsNameWhateverItsCase() {
        XCTAssertEqual(LogoAnswer.key("studio", " Warner Bros. "), LogoAnswer.key("studio", "warner bros."))
        XCTAssertNotEqual(LogoAnswer.key("studio", "HBO"), LogoAnswer.key("network", "HBO"))
    }

    // MARK: A disc's sections

    private let discPage = #"""
    {"main":{"ttn":2,"label":"","durationSec":9000,"angles":2,"wide":true,"audio":["en","fr Commentary","en Commentary"],"subtitles":["nl"],
             "chapters":[{"n":1,"start":0,"label":""},{"n":2,"start":312.5,"label":"The bank"}]},
     "extras":[{"ttn":5,"label":"Making of","durationSec":1500,"chapters":[],"audio":[],"subtitles":[],"angles":1,"wide":false},
               {"ttn":4,"label":"","durationSec":90,"chapters":null,"audio":null,"subtitles":null,"angles":1,"wide":false}],
     "menus":[{"kind":"root","vts":1,"label":"Main menu"},{"kind":"title","vts":0,"label":"Title menu"}]}
    """#

    func testADiscsSectionsAreReadAsTheServerSendsThem() throws {
        let view = try JSONDecoder().decode(DiscView.self, from: Data(discPage.utf8))
        XCTAssertEqual(view.main?.ttn, 2)
        XCTAssertEqual(view.main?.chapters.map(\.start), [0, 312.5])
        XCTAssertEqual(view.extras.map(\.ttn), [5, 4])
        XCTAssertEqual(view.extras[1].chapters, [])
        XCTAssertEqual(view.menus.map(\.kind), ["root", "title"])
        // A disc that couldn't be read, or an answer with nothing in it, has no sections.
        XCTAssertEqual(try JSONDecoder().decode(DiscView.self, from: Data(#"{"main":null,"extras":null}"#.utf8)), DiscView.none)
        // The names it came with are the ones the page starts from.
        let labels = DiscLabels(view)
        XCTAssertEqual(labels.titles, ["5": "Making of"])
        XCTAssertEqual(labels.chapters, ["2": ["2": "The bank"]])
        // And what a disc's facts say of each title.
        let info = try facts(dvd).disc
        XCTAssertEqual(info?.titles?.last?.durationSec, 9000)
    }

    func testADiscPlaysAtTheWebsitesAddresses() {
        XCTAssertEqual(DiscPage.titlePath(9, ttn: 2), "/play/9?mode=title&ttn=2&start=0")
        XCTAssertEqual(DiscPage.titlePath(9, ttn: 2, chapter: 7), "/play/9?mode=title&ttn=2&chapter=7")
        XCTAssertEqual(DiscPage.titlePath(9, ttn: 2, chapter: 0), "/play/9?mode=title&ttn=2&start=0")
        XCTAssertEqual(DiscPage.menuPath(9, DiscView.Menu(kind: "chapter", vts: 1, label: "Scene selection")), "/play/9?mode=menu&menu=chapter&menuVts=1")
        XCTAssertEqual(DiscPage.menuPath(9, DiscView.Menu(kind: "title", vts: 0, label: "Title menu")), "/play/9?mode=menu&menu=title")
        let client = WittyClient(base: "http://media.local:8080", token: "t")
        XCTAssertEqual(client.discThumbURL(9, ttn: 2, scene: 0)?.absoluteString, "http://media.local:8080/api/v1/items/9/disc/thumb/2/0")
        XCTAssertEqual(client.discThumbURL(9, ttn: 2, scene: 4, retry: 2)?.absoluteString, "http://media.local:8080/api/v1/items/9/disc/thumb/2/4?retry=2")
        XCTAssertEqual(DiscPage.thumbRetries, [3, 6])
    }

    func testTheFeatureSaysWhatItIs() throws {
        let view = try JSONDecoder().decode(DiscView.self, from: Data(discPage.utf8))
        let main = try XCTUnwrap(view.main)
        XCTAssertEqual(DiscPage.featureLine(main), "2 h 30 min · 2 scenes · 2 video versions · widescreen")
        XCTAssertEqual(DiscPage.featureLanguages(main), "Audio: English, French · Subtitles: Dutch")
        XCTAssertTrue(DiscPage.showsScenes(main))
        let short = DiscView.Title(ttn: 1, durationSec: 2700, chapters: [DiscView.Chapter(n: 1, start: 0)], subtitles: ["en"])
        XCTAssertEqual(DiscPage.featureLine(short), "45 min · 1 scenes")
        // As the website writes it: subtitles without audio keep their dot.
        XCTAssertEqual(DiscPage.featureLanguages(short), " · Subtitles: English")
        XCTAssertEqual(DiscPage.featureLanguages(DiscView.Title(ttn: 1)), "")
        XCTAssertFalse(DiscPage.showsScenes(short))
    }

    func testTitlesAndScenesHaveTheirGivenNamesOrSayWhatTheyAre() throws {
        let view = try JSONDecoder().decode(DiscView.self, from: Data(discPage.utf8))
        var labels = DiscLabels(view)
        XCTAssertEqual(DiscPage.name(view.extras[0], labels, otherwise: DiscPage.bonusName(0)), "Making of")
        XCTAssertEqual(DiscPage.name(view.extras[1], labels, otherwise: DiscPage.bonusName(1)), "Bonus feature 2")
        XCTAssertEqual(DiscPage.name(view.main!, labels, otherwise: "Heat"), "Heat")
        XCTAssertEqual(DiscPage.sceneName(labels, ttn: 2, scene: 2), "The bank")
        XCTAssertEqual(DiscPage.sceneName(labels, ttn: 2, scene: 1), "Scene 1")
        XCTAssertEqual(DiscPage.scenePlayLabel(labels, ttn: 2, scene: 2), "Play scene 2: The bank")
        XCTAssertEqual(DiscPage.scenePlayLabel(labels, ttn: 2, scene: 1), "Play scene 1")
        XCTAssertEqual(DiscPage.bonusPlayLabel(view.extras[0], labels, index: 0), "Play Making of")
        XCTAssertEqual(DiscPage.bonusPlayLabel(view.extras[1], labels, index: 1), "Play bonus feature 2")
        labels.setTitle(2, "The film")
        labels.setChapter(4, 1, "Opening")
        labels.setTitle(5, "")
        XCTAssertEqual(labels.title(2), "The film")
        XCTAssertEqual(labels.chapter(4, 1), "Opening")
        // An emptied name is the default again.
        XCTAssertEqual(DiscPage.name(view.extras[0], labels, otherwise: DiscPage.bonusName(0)), "Bonus feature 1")
        // What goes to the server is what it keeps: names by title number and scene number.
        let sent = try JSONSerialization.jsonObject(with: JSONEncoder().encode(labels)) as? [String: Any]
        XCTAssertEqual(sent?["titles"] as? [String: String], ["2": "The film", "5": ""])
        XCTAssertEqual(sent?["chapters"] as? [String: [String: String]], ["2": ["2": "The bank"], "4": ["1": "Opening"]])
    }

    func testTheTableListsEveryTitleASecondLong() throws {
        let disc = try facts(dvd).disc
        XCTAssertEqual(DiscPage.allTitlesSummary(disc), "All 2 titles on the disc")
        XCTAssertNil(DiscPage.allTitlesSummary(DiscInfo(titles: [])))
        let info = DiscInfo(mainTitle: 2, titles: [
            DiscTitle(number: 1, durationSec: 0.4),
            DiscTitle(number: 2, durationSec: 9000, chapters: [0, 300, 600], audio: ["en ac3 6ch", "fr ac3 2ch", "en ac3 2ch", "de ac3 2ch"],
                      subtitles: ["en", "eng", "nl"]),
            DiscTitle(number: 3, durationSec: 95),
        ])
        let rows = DiscPage.titleRows(info)
        XCTAssertEqual(rows.map(\.ttn), [2, 3])
        XCTAssertEqual(rows[0], DiscPage.TitleRow(ttn: 2, number: "2 · Feature", length: "2:30:00", chapters: "3",
                                                  audio: "en ac3 6ch, fr ac3 2ch, en ac3 2ch", subtitles: "English, Dutch", feature: true))
        XCTAssertEqual(rows[1], DiscPage.TitleRow(ttn: 3, number: "3", length: "1:35", chapters: "0", audio: "", subtitles: "", feature: false))
    }

    func testAbovePhoneWidthTheWordsGoBesideThePoster() {
        let phone = TitleLayout(width: 390, window: 844)
        XCTAssertFalse(phone.wide)
        XCTAssertEqual(phone.heroHeight, TitleLook.heroHeight(window: 844))
        XCTAssertEqual(phone.rise, 96)
        XCTAssertEqual(phone.posterWidth, 132)
        XCTAssertEqual(phone.gap, 20)
        XCTAssertEqual(phone.column(width: 390, gutter: 16), 358)
        // An iPad upright: the backdrop at its tallest, the poster at its narrowest.
        let upright = TitleLayout(width: 820, window: 1180)
        XCTAssertTrue(upright.wide)
        XCTAssertEqual(upright.heroHeight, 560)
        XCTAssertEqual(upright.rise, 188.8, accuracy: 0.001)
        XCTAssertEqual(upright.posterWidth, 170)
        XCTAssertEqual(upright.gap, 24.6, accuracy: 0.001)
        XCTAssertEqual(upright.column(width: 820, gutter: 32), 561.4, accuracy: 0.001)
        // On its side.
        let across = TitleLayout(width: 1180, window: 820)
        XCTAssertEqual(across.heroHeight, 410, accuracy: 0.001)
        XCTAssertEqual(across.rise, 131.2, accuracy: 0.001)
        XCTAssertEqual(across.posterWidth, 200.6, accuracy: 0.001)
        XCTAssertEqual(across.gap, 35.4, accuracy: 0.001)
        XCTAssertEqual(across.column(width: 1180, gutter: 32), 880, accuracy: 0.001)
        // The clamps' other ends.
        let big = TitleLayout(width: 2000, window: 400)
        XCTAssertEqual(big.heroHeight, 320)
        XCTAssertEqual(big.rise, 120)
        XCTAssertEqual(big.posterWidth, 248)
        XCTAssertEqual(big.gap, 40)
        XCTAssertFalse(TitleLook.isWide(width: 760))
        XCTAssertTrue(TitleLook.isWide(width: 761))
        XCTAssertTrue(TitleLook.isNarrow(width: 700))
        XCTAssertFalse(TitleLook.isNarrow(width: 701))
    }

    func testGridsTakeAsManyColumnsAsFit() {
        XCTAssertEqual(TitleLook.gridColumns(width: 561.4, minimum: 170, gap: 16), 3)
        XCTAssertEqual(TitleLook.gridColumns(width: 880, minimum: 170, gap: 16), 4)
        XCTAssertEqual(TitleLook.gridColumns(width: 100, minimum: 170, gap: 16), 1)
        XCTAssertEqual(DiscPage.sceneColumns(page: 390, column: 358), 2)
        XCTAssertEqual(DiscPage.sceneColumns(page: 820, column: 561.4), 3)
        XCTAssertEqual(DiscPage.extraColumns(column: 358), 1)
        XCTAssertEqual(DiscPage.extraColumns(column: 561.4), 2)
        XCTAssertEqual(DiscPage.extraColumns(column: 880), 3)
        XCTAssertEqual(DiscPage.featurePictureWidth(card: 535.4, wordsNeed: 140), 375.4, accuracy: 0.001)
        XCTAssertEqual(DiscPage.featurePictureWidth(card: 854, wordsNeed: 140), 420)
        XCTAssertEqual(DiscPage.featurePictureWidth(card: 300, wordsNeed: 140), 220)
        XCTAssertEqual(TitleLook.episodeCard(width: 390).picture, 132)
        XCTAssertEqual(TitleLook.episodeCard(width: 390).lines, 2)
        XCTAssertEqual(TitleLook.episodeCard(width: 820).picture, 164, accuracy: 0.001)
        XCTAssertEqual(TitleLook.episodeCard(width: 820).gap, 16)
        XCTAssertEqual(TitleLook.episodeCard(width: 820).lines, 3)
        XCTAssertEqual(TitleLook.episodeCard(width: 1400).picture, 240)
        XCTAssertEqual(TitleLook.playlistPicture(width: 390), 52)
        XCTAssertEqual(TitleLook.playlistPicture(width: 1180), 72)
        XCTAssertEqual(TitleLook.sectionGap(width: 390), 28)
        XCTAssertEqual(TitleLook.sectionGap(width: 1180), 40.12, accuracy: 0.001)
        XCTAssertEqual(TitleLook.sectionGap(width: 2000), 44)
    }

    func testAWideRowHasRoomForWhatMoreHolds() throws {
        let film = try item(film)
        XCTAssertEqual(TitleLook.playWords(film, wide: false), "Resume")
        XCTAssertEqual(TitleLook.playWords(film, wide: true), "Resume from 12:34")
        XCTAssertEqual(TitleLook.playWords(try item(#"{"id":1,"title":"x","kind":"video"}"#), wide: true), "Play")
        let row = TitleLook.wideRow(film, try facts(self.film), admin: true)
        XCTAssertEqual(row.buttons, [.playFromStart])
        XCTAssertEqual(row.tools, [.artwork, .edit, .refresh])
        XCTAssertTrue(TitleLook.wideRow(film, try facts(self.film), admin: false).tools.isEmpty)
        let disc = TitleLook.wideRow(try item(dvd), try facts(dvd), admin: true)
        XCTAssertEqual(disc.buttons, [.resumeDisc("Resume from 1:01", path: "/play/9?mode=title&ttn=3"), .mainMenu(path: "/play/9?mode=menu")])
        XCTAssertEqual(disc.tools, [.discSettings, .artwork, .edit, .refresh])
        XCTAssertEqual(disc.tools.map(\.toolName), ["Disc settings", "Artwork", "Edit details", "Check for new details"])
        XCTAssertEqual(TitleLook.showTools(wide: false), [.artwork, .edit, .refresh])
        XCTAssertEqual(TitleLook.showTools(wide: true), [.edit, .artwork, .refresh])
        let next = try item(#"{"id":12,"title":"c","season":2,"episode":1,"progress":{"positionSec":125,"resumeSec":120}}"#)
        XCTAssertEqual(TitleLook.playLabel(next, wide: true).words, "Resume S2 · E1 from 2:05")
        XCTAssertNil(TitleLook.playLabel(next, wide: true).spoken)
        XCTAssertEqual(TitleLook.playLabel(try item(#"{"id":1,"title":"Pilot","season":1,"episode":1}"#), wide: true).words, "Play S1 · E1")
    }

    func testADiscsSectionsAndItsNamesAreOneRequestEach() async throws {
        let body = discPage
        let stand = try StandInServer { request in
            request.line.hasPrefix("PUT")
                ? StandInServer.answer(body: #"{"titles":{"2":"The film"},"chapters":{}}"#)
                : StandInServer.answer(body: body)
        }
        addTeardownBlock { stand.stop() }
        let client = WittyClient(base: stand.address, token: "t")
        let view = try await client.discView(9)
        XCTAssertEqual(view.main?.ttn, 2)
        let kept = try await client.setDiscLabels(9, DiscLabels(titles: ["2": "The film", "5": " "]))
        XCTAssertEqual(kept, DiscLabels(titles: ["2": "The film"]))
        XCTAssertEqual(stand.requests.map(\.line), ["GET /api/v1/items/9/disc HTTP/1.1", "PUT /api/v1/items/9/disc/labels HTTP/1.1"])
    }

    func testAnItemsPageIsOneRequest() async throws {
        let body = film
        let stand = try StandInServer { _ in StandInServer.answer(body: body) }
        addTeardownBlock { stand.stop() }
        let client = WittyClient(base: stand.address, token: "t")
        let (item, facts) = try await client.itemPage(7)
        XCTAssertEqual(item.id, 7)
        XCTAssertEqual(facts.provider, "tmdb")
        XCTAssertEqual(stand.requests.map(\.path), ["/api/v1/items/7"])
        XCTAssertEqual(client.titleLogoURL(.show, 3, version: 12)?.absoluteString, "\(stand.address)/api/v1/meta/show/3/art/logo?v=12")
        let logo = LogoAnswer(id: 4, kind: "network", name: "HBO", has: true, version: 2, opaque: false)
        XCTAssertEqual(client.logoImageURL(logo, variant: "white")?.absoluteString, "\(stand.address)/api/v1/logos/4/image?variant=white&v=2")
    }
}
