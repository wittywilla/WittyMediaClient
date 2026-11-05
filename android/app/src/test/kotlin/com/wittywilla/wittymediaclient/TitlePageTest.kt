package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.DiscInfo
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.ItemFacts
import com.wittywilla.wittymediaclient.net.LegalNotices
import com.wittywilla.wittymediaclient.net.LogoAnswer
import com.wittywilla.wittymediaclient.net.Season
import com.wittywilla.wittymediaclient.net.ShowDetail
import com.wittywilla.wittymediaclient.net.ShowFacts
import com.wittywilla.wittymediaclient.net.TitleAttached
import com.wittywilla.wittymediaclient.net.TitleListings
import com.wittywilla.wittymediaclient.net.TitleTarget
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.notice
import com.wittywilla.wittymediaclient.net.plainWords
import com.wittywilla.wittymediaclient.net.queryValue
import com.wittywilla.wittymediaclient.ui.TitleLook
import com.wittywilla.wittymediaclient.ui.markdownParts
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

// An item's and a show's page as the website words them (ItemPage.tsx, ShowPage.tsx, TitleExtras.tsx), ported from the
// iPhone's TitlePageTests so both apps say the same.
class TitlePageTest {
    private fun item(text: String): Item = json.decodeFromString(text)

    private val film = """
        {"id":7,"libraryId":2,"kind":"video","title":"Arrival","year":2016,"runtimeSec":6960,"rating":7.9,"poster":"tmdb:abc",
         "provider":"tmdb","providerId":"329865","width":1920,"height":800,"videoCodec":"hevc","container":"matroska,webm",
         "audioLangs":["eng","en","fre"],"subLangs":null,"sizeBytes":4210000000,"path":"/films/Arrival.mkv",
         "progress":{"positionSec":754,"durationSec":6960,"watched":false,"resumeSec":750}}
    """

    private val dvd = """
        {"id":9,"libraryId":4,"kind":"dvd-iso","title":"Heat","startMode":"title","insertEffect":false,"width":720,"height":576,"videoCodec":"mpeg2video",
         "disc":{"label":"HEAT","format":"dvd","hasMenus":true,"mainTitle":2,"scrambled":false,"content":"movie",
                 "titles":[{"number":1,"durationSec":30,"wide":false,"standard":"pal"},{"number":2,"durationSec":9000,"wide":true,"standard":"pal"}]},
         "sizeBytes":7800000000,"progress":{"positionSec":61,"durationSec":9000,"watched":false,"resumeSec":60,"discTitle":3}}
    """

    @Test
    fun anItemsPageReadsItsFactsBesideTheItem() {
        val facts = ItemFacts.read(film)
        assertEquals(7.9, facts.rating!!, 0.0)
        assertEquals(1920, facts.width)
        assertEquals(listOf("eng", "en", "fre"), facts.audioLangs)
        assertNull(facts.subLangs)
        assertEquals(4_210_000_000L, facts.sizeBytes)
        assertEquals("Arrival", item(film).title)
        // One odd fact is only absent: the page still shows.
        val odd = ItemFacts.read("""{"id":1,"title":"x","width":"wide","providerId":42,"disc":"none"}""")
        assertNull(odd.width)
        assertEquals("42", odd.providerId)
        assertNull(odd.disc)
        assertEquals(3, ItemFacts.read(dvd).discTitle)
        // Not an answer at all is nothing known.
        assertEquals(ItemFacts(), ItemFacts.read("not json"))
    }

    @Test
    fun aShowsFactsComeFromItsShow() {
        val text = """
            {"show":{"id":3,"title":"Severance","libraryId":5,"genres":["Drama","Mystery"],"contentRating":"TV-MA","network":"Apple TV+",
                     "status":"Running","provider":"tmdb-tv","providerId":"95396","view":"list","updatedAt":12},
             "seasons":[{"number":1,"title":"Season 1","episodeCount":9,"unwatched":3}],"episodes":[],"nextUpId":null}
        """
        val facts = ShowFacts.read(text)
        assertEquals("Apple TV+", facts.network)
        assertEquals("list", facts.view)
        assertEquals(5L, facts.libraryId)
        assertEquals("Severance", json.decodeFromString<ShowDetail>(text).show.title)
    }

    @Test
    fun whatIsAttachedToATitleReadsNullsAsNothing() {
        val attached = json.decodeFromString<TitleAttached>(
            """
            {"extras":[{"item":{"id":20,"title":"Making of","kind":"video"},"link":{"extraType":"behind-the-scenes"}}],
             "versions":[{"item":{"id":21,"title":"Arrival","height":2160},"link":{"label":"Director's cut"}},{"item":{"id":22,"title":"Arrival"},"link":null}],
             "studios":null,"director":"Denis Villeneuve","edition":["Remastered"],"tags":null,"hasBanner":false,"hasLogo":true}
            """,
        )
        assertTrue(attached.studios.isEmpty())
        assertTrue(attached.hasLogo)
        assertEquals(listOf("Director's cut · 2160p", "Arrival"), attached.versions.map(TitleLook::versionLabel))
        assertEquals(listOf("Behind the scenes"), attached.extras.map { TitleLook.extraName(it.link?.extraType) })
        assertEquals("Extra", TitleLook.extraName(null))
        val listed = json.decodeFromString<TitleListings>("""{"platforms":[{"key":"nfx","name":"Netflix"}],"asOf":0,"region":"GB","attribution":"Data from JustWatch."}""")
        assertEquals("You're looking at your own copy, on your own server. Listed for GB. Data from JustWatch.", TitleLook.listedNote(listed) { "never" })
        assertEquals(
            "You're looking at your own copy, on your own server. Listed for GB, as of 05/11/2026. Data from JustWatch.",
            TitleLook.listedNote(listed.copy(asOf = 1_793_836_800)) { "05/11/2026" },
        )
    }

    @Test
    fun timesAreSaidAsTheWebsiteSaysThem() {
        assertEquals("1 h 56 min", TitleLook.runtime(6960.0))
        assertEquals("45 min", TitleLook.runtime(2700.0))
        assertEquals("40 s", TitleLook.runtime(40.4))
        assertEquals("", TitleLook.runtime(0.0))
        assertEquals("", TitleLook.runtime(null))
        assertEquals("12:34", TitleLook.clock(754.0))
        assertEquals("1:02:05", TitleLook.clock(3725.0))
        assertEquals("0:00", TitleLook.clock(-3.0))
    }

    @Test
    fun codecsAndLanguagesHaveTheNamesPeopleKnow() {
        assertEquals("HEVC", TitleLook.codec("hevc"))
        assertEquals("MPEG-2", TitleLook.codec("mpeg2video"))
        assertEquals("THEORA", TitleLook.codec("theora"))
        assertEquals("German", TitleLook.language("ger"))
        assertEquals("Unknown", TitleLook.language(""))
        assertEquals("X-KLINGON", TitleLook.language("x-klingon"))
        // Any other code is named by the system, as the browser names it.
        assertEquals("Catalan", TitleLook.language("cat"))
        // English twice, as "eng" and "en", is said once.
        assertEquals("English, French", TitleLook.languages(listOf("eng", "en", "fre")))
    }

    @Test
    fun fourGenresShowAndMoreAreAnEllipsis() {
        assertEquals(listOf("A", "B") to false, TitleLook.genres(listOf("A", "B")))
        val five = TitleLook.genres(listOf("A", "B", "C", "D", "E"))
        assertEquals(listOf("A", "B", "C", "D"), five.first)
        assertTrue(five.second)
    }

    @Test
    fun theCaptionIsTheLibraryOrTheShowItsSeasonAndTheEpisode() {
        val episode = item("""{"id":5,"libraryId":2,"title":"Pilot","showId":3,"showTitle":"Severance","season":1,"episode":2}""")
        // No library for an episode, as the website's caption.
        assertEquals(listOf("Severance", "Season 1", "S1 · E2"), TitleLook.crumbs(episode, "TV").map { it.words })
        assertEquals(TitleLook.Goes.Show(3, 1), TitleLook.crumbs(episode, "TV")[1].goes)
        assertEquals(TitleLook.Goes.Show(3, null), TitleLook.crumbs(episode, "TV")[0].goes)
        assertEquals(TitleLook.Goes.Nowhere, TitleLook.crumbs(episode, null).last().goes)
        val special = item("""{"id":6,"title":"Xmas","showId":3,"showTitle":"Severance","season":0,"episode":1}""")
        assertEquals(listOf("Severance", "Specials", "Special · E1"), TitleLook.crumbs(special, null).map { it.words })
        val film = item(film)
        assertEquals(listOf(TitleLook.Crumb("Films", TitleLook.Goes.Library(2))), TitleLook.crumbs(film, "Films"))
        assertTrue(TitleLook.crumbs(film, null).isEmpty())
    }

    @Test
    fun theFactsTableSaysWhatTheFileIs() {
        val rows = TitleLook.facts(item(film), ItemFacts.read(film), admin = false)
        assertEquals(
            listOf(TitleLook.Fact("Video", "1920×800 HEVC"), TitleLook.Fact("Audio", "English, French"), TitleLook.Fact("Source", "MATROSKA,WEBM · 4.21 GB")),
            rows,
        )
        assertEquals(TitleLook.Fact("File", "/films/Arrival.mkv", wide = true), TitleLook.facts(item(film), ItemFacts.read(film), admin = true).last())
        val disc = TitleLook.facts(item(dvd), ItemFacts.read(dvd), admin = false)
        assertEquals(listOf("720×576 MPEG-2 · PAL 16:9", "DVD image · 7.80 GB", "HEAT · 2 titles · menus"), disc.map { it.value })
        // Nothing known but the item: still where it came from.
        assertEquals(listOf(TitleLook.Fact("Source", "")), TitleLook.facts(item("""{"id":1,"title":"x"}"""), ItemFacts(), admin = false))
    }

    @Test
    fun theFactsTakeAsManyColumnsAsFit() {
        assertEquals(1, TitleLook.factColumns(358.0))
        assertEquals(2, TitleLook.factColumns(364.0))
        assertEquals(3, TitleLook.factColumns(600.0))
        assertEquals(1, TitleLook.factColumns(10.0))
    }

    @Test
    fun moreHoldsWhatTheRowHasNoRoomFor() {
        val film = item(film)
        assertEquals(listOf(TitleLook.MoreRow.PlayFromStart), TitleLook.moreRows(film, ItemFacts.read(this.film), admin = false))
        assertEquals(
            listOf(TitleLook.MoreRow.PlayFromStart, TitleLook.MoreRow.Artwork, TitleLook.MoreRow.Edit, TitleLook.MoreRow.Refresh),
            TitleLook.moreRows(film, ItemFacts.read(this.film), admin = true),
        )
        // Nothing to start again and no next episode: no "⋯" at all.
        assertTrue(TitleLook.moreRows(item("""{"id":1,"title":"x","kind":"video"}"""), ItemFacts(), admin = false).isEmpty())
        // An episode is refreshed with its show.
        val episode = item("""{"id":5,"title":"Pilot","kind":"video","showId":3,"nextId":6}""")
        assertEquals(listOf(TitleLook.MoreRow.NextEpisode(6), TitleLook.MoreRow.Artwork, TitleLook.MoreRow.Edit), TitleLook.moreRows(episode, ItemFacts(), admin = true))
        assertEquals(
            listOf(
                TitleLook.MoreRow.ResumeDisc("Resume from 1:01", "/play/9?mode=title&ttn=3"), TitleLook.MoreRow.MainMenu("/play/9?mode=menu"),
                TitleLook.MoreRow.DiscSettings, TitleLook.MoreRow.Artwork, TitleLook.MoreRow.Edit, TitleLook.MoreRow.Refresh,
            ),
            TitleLook.moreRows(item(dvd), ItemFacts.read(dvd), admin = true),
        )
        val tv = ItemFacts(disc = DiscInfo(hasMenus = false, mainTitle = 1, content = "tv"))
        assertEquals(
            listOf(TitleLook.MoreRow.DiscFromStart("Play from the start", "/play/4?mode=title&start=0")),
            TitleLook.moreRows(item("""{"id":4,"title":"x","kind":"dvd-folder"}"""), tv, admin = false),
        )
        assertEquals("Play movie", TitleLook.MoreRow.DiscFromStart("Play movie", "").words)
        // Resuming a disc without its title goes to the main one, else the first.
        val noTitle = ItemFacts(disc = DiscInfo(mainTitle = 0))
        assertEquals(TitleLook.MoreRow.ResumeDisc("Resume from 1:01", "/play/9?mode=title&ttn=1"), TitleLook.moreRows(item(dvd), noTitle, admin = false).first())
    }

    @Test
    fun aDiscStartsAsItsSettingsSay() {
        val heat = item(dvd)
        val facts = ItemFacts.read(dvd)
        assertEquals("/play/9?mode=title", TitleLook.insertPath(heat, facts))
        assertEquals("Insert DVD starts with the main feature.", TitleLook.discHint(heat, facts, admin = false))
        val usual = ItemFacts()
        assertEquals("/play/9?mode=menu&insert=1", TitleLook.insertPath(heat, usual))
        assertEquals("Insert DVD starts with the disc menu · with the tray effect — change it in Disc settings.", TitleLook.discHint(heat, usual, admin = true))
        val bluray = item("""{"id":2,"title":"x","kind":"bluray-folder"}""")
        assertEquals("Blu-ray", TitleLook.discName(bluray))
        assertTrue(TitleLook.isDisc(bluray))
        assertFalse(TitleLook.isDisc(item(film)))
        assertFalse(TitleLook.playable(heat, ItemFacts(disc = DiscInfo(scrambled = true))))
        assertTrue(TitleLook.playable(heat, facts))
    }

    @Test
    fun aSeasonSaysHowManyAreLeft() {
        fun season(count: Int, left: Int?): Season =
            json.decodeFromString("""{"number":1,"episodeCount":$count${left?.let { ",\"unwatched\":$it" } ?: ""}}""")
        assertEquals("10 ep · 3 left", TitleLook.seasonLine(season(10, 3)))
        assertEquals("10 ep · watched", TitleLook.seasonLine(season(10, 0)))
        assertEquals("10 ep", TitleLook.seasonLine(season(10, 10)))
        assertEquals("10 ep", TitleLook.seasonLine(season(10, null)))
    }

    @Test
    fun aShowOpensAtTheNextEpisodesSeason() {
        val text = """
            {"show":{"id":3,"title":"S"},"nextUpId":12,
             "seasons":[{"number":0,"episodeCount":1},{"number":1,"episodeCount":2},{"number":2,"episodeCount":1}],
             "episodes":[{"id":10,"title":"a","season":1,"episode":1},{"id":11,"title":"b","season":1,"episode":2},
                         {"id":12,"title":"c","season":2,"episode":1,"progress":{"positionSec":125,"resumeSec":120}},{"id":13,"title":"d"}]}
        """
        val detail = json.decodeFromString<ShowDetail>(text)
        assertEquals(2, TitleLook.openingSeason(detail, null))
        assertEquals(1, TitleLook.openingSeason(detail, 1))
        assertEquals(listOf(10L, 11L), TitleLook.episodes(detail, 1).map { it.id })
        assertEquals(listOf(13L), TitleLook.episodes(detail, -1).map { it.id })
        assertEquals(listOf(13L), TitleLook.otherVideos(detail).map { it.id })
        val next = detail.episodes.first { it.id == 12L }
        assertEquals("Resume S2 · E1", TitleLook.playLabel(next).words)
        assertEquals("Resume S2 · E1 from 2:05", TitleLook.playLabel(next).spoken)
        assertEquals("Play S1 · E1", TitleLook.playLabel(detail.episodes[0]).words)
        assertNull(TitleLook.playLabel(detail.episodes[0]).spoken)
        assertEquals("Play d", TitleLook.playLabel(detail.episodes[3]).words)
        assertEquals("E2", TitleLook.playlistNumber(detail.episodes[1]))
        assertEquals("–", TitleLook.playlistNumber(detail.episodes[3]))
        // Nothing next: the first real season, not Specials.
        val quiet = json.decodeFromString<ShowDetail>(text.replace("\"nextUpId\":12", "\"nextUpId\":null"))
        assertEquals(1, TitleLook.openingSeason(quiet, null))
        // No seasons at all: the first, which is none.
        assertEquals(0, TitleLook.openingSeason(ShowDetail(), null))
    }

    @Test
    fun aShowsWordsAreTheWebsites() {
        assertEquals("1 season · 1 episodes", TitleLook.seasonsLine(1, 1))
        assertEquals("3 seasons · 24 episodes", TitleLook.seasonsLine(3, 24))
        assertEquals("list", TitleLook.episodeView(null, "", "list"))
        assertEquals("cards", TitleLook.episodeView("cards", "list", "list"))
        assertEquals("list", TitleLook.episodeView("", "list", null))
        assertEquals("cards", TitleLook.episodeView(null, null, null))
        assertEquals("2022-02-18 · 57 min", TitleLook.episodeLine(item("""{"id":1,"title":"x","aired":"2022-02-18","runtimeSec":3420}""")))
        assertEquals("", TitleLook.episodeLine(item("""{"id":1,"title":"x"}""")))
    }

    @Test
    fun theCreditNamesWhereTheDetailsCameFrom() {
        assertEquals(
            "TV information from [TVmaze](https://www.tvmaze.com/shows/82), shared under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).",
            TitleLook.credit("tvmaze", "82"),
        )
        assertNotNull(TitleLook.credit("tmdb", "1"))
        assertNull(TitleLook.credit("tmdb", "1", show = true))
        assertNotNull(TitleLook.credit("tmdb-tv", "1", show = true))
        assertNotNull(TitleLook.credit("wikidata", "Q1"))
        assertNull(TitleLook.credit("wikidata", "Q1", show = true))
        assertNull(TitleLook.credit("", null))
        // An id can't break out of its link.
        assertEquals("Anime information from [AniList](https://anilist.co/anime/1%29%20%5Bx%5D%28y).", TitleLook.credit("anilist", "1) [x](y"))
    }

    @Test
    fun fineprintsLinksAreReadOutOfItsWords() {
        assertEquals(
            listOf("Details from " to null, "TMDB" to "https://www.themoviedb.org", ". This product uses the TMDB API." to null),
            markdownParts("Details from [TMDB](https://www.themoviedb.org). This product uses the TMDB API."),
        )
        assertEquals(listOf("plain" to null), markdownParts("plain"))
        val credit = markdownParts(TitleLook.credit("anilist", "1) [x](y")!!)
        assertEquals("https://anilist.co/anime/1%29%20%5Bx%5D%28y", credit[1].second)
    }

    @Test
    fun linksGoWhereTheWebsitesGo() {
        assertEquals("/library/2?genre=Sci-Fi%20%26%20Fantasy", TitleLook.genrePath(2, "Sci-Fi & Fantasy"))
        assertEquals("/library/2?tag=Cult%20classic", TitleLook.tagPath(2, "Cult classic"))
        assertEquals("/library/2?platform=nfx", TitleLook.platformPath(2, "nfx"))
        assertEquals("/brand/network/Apple%20TV%2B?library=5", TitleLook.brandPath("network", "Apple TV+", 5))
        assertEquals("/show/3?edit=artwork", TitleLook.editPath(TitleTarget.Show, 3, "artwork"))
        assertEquals("/item/7", TitleLook.editPath(TitleTarget.Item, 7))
        // Letters beyond ASCII are sent as their UTF-8 bytes.
        assertEquals("Caf%C3%A9", queryValue("Café"))
    }

    @Test
    fun sizesFollowTheWebsitesClamps() {
        assertEquals(28.21, TitleLook.titleSize(390.0), 0.01)
        assertEquals(28.0, TitleLook.titleSize(320.0), 0.0)
        assertEquals(44.0, TitleLook.titleSize(2000.0), 0.0)
        assertEquals(323.76, TitleLook.heroHeight(852.0), 0.01)
        assertEquals(240.0, TitleLook.heroHeight(500.0), 0.0)
        assertEquals(560.0, TitleLook.heroHeight(2000.0), 0.0)
    }

    @Test
    fun aFrameOfTheVideoGetsAColourOfItsOwn() {
        assertTrue(TitleLook.isFrame("cache:frame-12.jpg"))
        assertFalse(TitleLook.isFrame("tmdb:abc"))
        assertFalse(TitleLook.isFrame(null))
        assertEquals(TitleLook.artHue("Arrival"), TitleLook.artHue("Arrival"))
        assertEquals((97 * 31 + 98) % 360, TitleLook.artHue("ab"))
        val red = TitleLook.rgb(0.0, 1.0, 0.5)
        assertEquals(1.0, red.first, 0.001)
        assertEquals(0.0, red.second, 0.001)
        val teal = TitleLook.rgb(180.0 + 360, 0.5, 0.25)
        assertEquals(0.125, teal.first, 0.001)
        assertEquals(0.375, teal.third, 0.001)
    }

    @Test
    fun onlySomeoneWhoMayPostOrAKidSaves() {
        assertTrue(TitleLook.canSave(false, "adult"))
        assertTrue(TitleLook.canSave(false, "kids"))
        assertTrue(TitleLook.canSave(false, null))
        assertFalse(TitleLook.canSave(false, "guest"))
        assertTrue(TitleLook.canSave(true, "guest"))
    }

    @Test
    fun aLegalNoticeIsTheServersWordsWithItsLink() {
        val notices = json.decodeFromString<LegalNotices>(
            """{"version":1,"linkText":"Legal","notices":{"metadata":{"text":"Details come from elsewhere.","section":"third-party"},"empty":{"text":""}}}""",
        )
        val note = notices.notice("metadata")!!
        assertEquals("Details come from elsewhere.", note.words)
        assertEquals("Legal", note.link)
        assertEquals("/settings/legal#third-party", note.path)
        assertNull(notices.notice("empty"))
        assertNull(notices.notice("newer"))
        // No words for the link is the usual one; a page's own kind with nothing asked for is nothing.
        assertEquals("Legal", LegalNotices(notices = notices.notices).notice("metadata")?.link)
        assertNull(notices.notice(""))
        // A server's words can't carry control characters or turn the text around.
        assertEquals("abc", plainWords(" a\u0007b‮c\n"))
        assertEquals("ab", plainWords("abcdef", 2))
    }

    @Test
    fun aLogoIsMatchedByItsNameWhateverItsCase() {
        assertEquals(LogoAnswer.key("studio", " Warner Bros. "), LogoAnswer.key("studio", "warner bros."))
        assertFalse(LogoAnswer.key("studio", "HBO") == LogoAnswer.key("network", "HBO"))
    }

    // MARK: what's asked of the server

    private class Asked(val method: String, val path: String, val body: String)

    // A stand-in for a server on this computer, answering every question with what `answer` says.
    private fun <T> withServer(answer: (Asked) -> String, test: (Api, List<Asked>) -> T): T {
        val socket = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        val asked = CopyOnWriteArrayList<Asked>()
        thread(isDaemon = true) {
            while (!socket.isClosed) {
                val client = runCatching { socket.accept() }.getOrNull() ?: break
                client.use {
                    val input = it.getInputStream().bufferedReader()
                    val first = input.readLine()?.split(" ") ?: return@use
                    var length = 0
                    while (true) {
                        val line = input.readLine()
                        if (line.isNullOrEmpty()) break
                        if (line.lowercase().startsWith("content-length:")) length = line.substringAfter(':').trim().toInt()
                    }
                    val body = CharArray(length)
                    var read = 0
                    while (read < length) read += input.read(body, read, length - read)
                    val request = Asked(first[0], first[1], String(body))
                    asked.add(request)
                    val bytes = answer(request).toByteArray()
                    val head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                    it.getOutputStream().apply { write(head.toByteArray()); write(bytes); flush() }
                }
            }
        }
        return try {
            test(Api("http://127.0.0.1:${socket.localPort}", "t"), asked)
        } finally {
            socket.close()
        }
    }

    @Test
    fun anItemsPageIsOneRequest() = withServer({ film }) { api, asked ->
        val (item, facts) = runBlocking { api.itemPage(7) }
        assertEquals(7L, item.id)
        assertEquals("tmdb", facts.provider)
        assertEquals(listOf("/api/v1/items/7"), asked.map { it.path })
        assertEquals("${api.base}/api/v1/meta/show/3/art/logo?v=12", api.titleLogoUrl(TitleTarget.Show, 3, 12))
        val logo = LogoAnswer(id = 4, kind = "network", name = "HBO", has = true, version = 2, opaque = false)
        assertEquals("${api.base}/api/v1/logos/4/image?variant=white&v=2", api.logoImageUrl(logo, "white"))
        assertNull(api.logoImageUrl(logo.copy(id = null), "white"))
    }

    @Test
    fun theExtrasLogosAndLayoutAreAskedForAsTheWebsiteAsks() = withServer({ request ->
        when {
            request.path.startsWith("/api/v1/logos") -> """{"logos":[{"id":4,"kind":"studio","name":"A24","status":"found","has":true,"version":1,"opaque":false}]}"""
            request.path.endsWith("/attached") -> """{"extras":null,"versions":null,"studios":["A24"],"director":"","edition":null,"tags":null,"hasLogo":false}"""
            request.path.endsWith("/listings") -> """{"platforms":null,"asOf":0,"region":"","attribution":""}"""
            else -> "{}"
        }
    }) { api, asked ->
        runBlocking {
            assertEquals(listOf("A24"), api.attached(TitleTarget.Show, 3).studios)
            assertTrue(api.listings(TitleTarget.Item, 7).platforms.isEmpty())
            assertEquals(true, api.lookUpLogos(listOf("studio" to "A24")).single().has)
            api.setShowView(3, "list")
        }
        assertEquals(
            listOf("GET /api/v1/meta/show/3/attached", "GET /api/v1/meta/item/7/listings", "POST /api/v1/logos/lookup", "PUT /api/v1/shows/3/view"),
            asked.map { "${it.method} ${it.path}" },
        )
        val lookup = json.parseToJsonElement(asked[2].body).jsonObject["logos"].toString()
        assertEquals("""[{"kind":"studio","name":"A24"}]""", lookup)
        assertEquals("list", json.parseToJsonElement(asked[3].body).jsonObject["view"]?.jsonPrimitive?.content)
    }

    @Test
    fun aShowsPageIsOneRequestAndItsLayoutComesWithTheServersPrefs() = withServer({ request ->
        if (request.path == "/api/v1/prefs") """{"maxSpeed":2,"episodeView":"list"}"""
        else """{"show":{"id":3,"title":"S","libraryId":5,"view":""},"seasons":[],"episodes":[]}"""
    }) { api, asked ->
        val (detail, facts) = runBlocking { api.showPage(3) }
        assertEquals("S", detail.show.title)
        assertEquals(5L, facts.libraryId)
        assertEquals("list", TitleLook.episodeView(null, facts.view, runBlocking { api.playerPrefs() }.episodeView))
        assertEquals(listOf("/api/v1/shows/3", "/api/v1/prefs"), asked.map { it.path })
    }
}
