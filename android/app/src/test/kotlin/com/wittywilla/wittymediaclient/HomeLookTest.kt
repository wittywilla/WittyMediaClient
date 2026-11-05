package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ForYou
import com.wittywilla.wittymediaclient.net.Guide
import com.wittywilla.wittymediaclient.net.Home
import com.wittywilla.wittymediaclient.net.HomeLayout
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.Show
import com.wittywilla.wittymediaclient.net.UpdateChange
import com.wittywilla.wittymediaclient.net.UpdateStatus
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.readHomeChoices
import com.wittywilla.wittymediaclient.net.withChoice
import com.wittywilla.wittymediaclient.ui.CardBadge
import com.wittywilla.wittymediaclient.ui.CardLook
import com.wittywilla.wittymediaclient.ui.CardShape
import com.wittywilla.wittymediaclient.ui.HeroFact
import com.wittywilla.wittymediaclient.ui.HeroLook
import com.wittywilla.wittymediaclient.ui.HomeGreeting
import com.wittywilla.wittymediaclient.ui.HomeWidgets
import com.wittywilla.wittymediaclient.ui.OnNowLook
import com.wittywilla.wittymediaclient.ui.OpenAction
import com.wittywilla.wittymediaclient.ui.OpenLook
import com.wittywilla.wittymediaclient.ui.ShuffleLook
import com.wittywilla.wittymediaclient.ui.UpdateNews
import com.wittywilla.wittymediaclient.ui.runtimeWords
import com.wittywilla.wittymediaclient.ui.title
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

// Home as the website builds it (web/src/pages/HomePage.tsx), as the iPhone's HomeLookTests check it: the sections and
// the order saved for them, the greeting, the hero, the main button, the cards, On TV now, Can't decide? and the
// notice of a newer server.
class HomeLookTest {
    private fun item(text: String): Item = json.decodeFromString(text)
    private fun home(text: String): Home = json.decodeFromString(text)

    // MARK: sections

    @Test
    fun homeHasTheWebsitesSectionsInTheWebsitesOrder() {
        val home = home(
            """
            {"hubs":[
              {"key":"recent-1","title":"Recently added in Films","libraryId":1,"items":[{"id":1,"title":"A"}]},
              {"key":"view-4","title":"Short films","libraryId":1,"query":"sort=added&maxRuntime=40","items":[{"id":5,"title":"E"}]},
              {"key":"continue-reading","title":"Continue reading","items":[{"id":3,"title":"C"}]},
              {"key":"continue","title":"Continue watching","items":[{"id":2,"title":"B"}]},
              {"key":"nextup","title":"Next up","items":[{"id":6,"title":"F"}]},
              {"key":"recent-1","title":"Twice","libraryId":1,"items":[{"id":4,"title":"D"}]}],
             "featured":[],"libraries":[]}
            """,
        )
        val widgets = HomeWidgets.list(home, null)
        assertEquals("a second row with the same key is left out", listOf("hero", "libraries", "jump", "onnow", "foryou", "nextup", "view-4", "recent-1", "shuffle"), widgets.map { it.id })
        assertEquals("watching before reading, whatever order they came in", listOf(2L, 3L), widgets[2].hub?.items?.map { it.id })
        assertNull("no recommendations yet", widgets[4].hub)
        assertEquals("sort=added&maxRuntime=40", widgets[6].hub?.query)
        assertEquals("Recently added in Films", widgets[7].title)
        assertEquals("Can’t decide?", widgets.last().title)
        val picked = json.decodeFromString<ForYou>("""{"because":"Sol Levante","items":[{"id":9,"title":"G"}],"shows":[]}""")
        val forYou = HomeWidgets.list(home, picked)[4]
        assertEquals("Recommended for you", forYou.title)
        assertEquals("Because you watch Sol Levante", forYou.hub?.title)
        assertEquals("Recommended for you", ForYou().title)
    }

    @Test
    fun homeIsEmptyOnlyWithNothingFeaturedAndEveryRowEmpty() {
        assertTrue(HomeWidgets.isEmpty(home("""{"hubs":[{"key":"recent-1","title":"R","items":[],"shows":null}],"featured":[]}""")))
        assertFalse(HomeWidgets.isEmpty(home("""{"hubs":[],"featured":[{"id":1,"title":"A"}]}""")))
        assertFalse(HomeWidgets.isEmpty(home("""{"hubs":[{"key":"recent-2","title":"R","items":[],"shows":[{"id":3,"title":"S"}]}],"featured":[]}""")))
    }

    @Test
    fun aSavedLayoutIsReadAsTheWebsiteReadsIt() {
        val choices = readHomeChoices("""{"tvLook":{},"home":{"v":2,"order":["shuffle","hero"],"hidden":["continue","continue-reading","onnow"]},"updateLater":"1.4.0"}""")
        val layout = HomeLayout.saved(choices.home)
        assertEquals(listOf("shuffle", "hero"), layout.order)
        assertEquals("the old Continue rows hide Jump back in, once", listOf("jump", "onnow"), layout.hidden)
        assertEquals("1.4.0", choices.updateLater)
        val old = HomeLayout.saved(readHomeChoices("""{"home":{"order":["hero","continue"],"hidden":null}}""").home)
        assertEquals("an order saved before version 2 is dropped", HomeLayout(), old)
        assertEquals(HomeLayout(), HomeLayout.saved(null))
        val unreadable = readHomeChoices("""{"home":"tall","updateLater":7}""")
        assertNull(unreadable.home)
        assertNull(unreadable.updateLater)
        assertNull(readHomeChoices("not json").home)
        val written = HomeLayout(listOf("a"), emptyList()).toJson()
        assertEquals(2, written["v"]?.jsonPrimitive?.int)
        assertEquals(JsonArray(listOf(JsonPrimitive("a"))), written["order"])
        assertEquals(JsonArray(emptyList()), written["hidden"])
    }

    @Test
    fun theSavedOrderComesFirstThenTheRestInTheWebsitesOrder() {
        val widgets = HomeWidgets.list(home("""{"hubs":[{"key":"recent-1","title":"R","items":[]}],"featured":[]}"""), null)
        val layout = HomeLayout(listOf("shuffle", "recent-1", "gone"), emptyList())
        val ordered = layout.ordered(widgets) { it.id }.map { it.id }
        assertEquals(listOf("shuffle", "recent-1", "hero", "libraries", "jump", "onnow", "foryou"), ordered)
        val moved = layout.moving("hero", 0, ordered)
        assertEquals(listOf("hero", "shuffle", "recent-1", "libraries", "jump", "onnow", "foryou"), moved.order)
        assertEquals("shuffle", layout.moving("shuffle", 99, ordered).order.last())
        assertEquals("down one: after the next", listOf("recent-1", "shuffle", "hero", "libraries", "jump", "onnow", "foryou"), layout.moving("shuffle", 1, ordered).order)
        assertEquals(listOf("onnow"), layout.toggling("onnow").hidden)
        assertEquals(emptyList<String>(), layout.toggling("onnow").toggling("onnow").hidden)
        assertEquals("moving keeps what's hidden", listOf("onnow"), layout.toggling("onnow").moving("hero", 0, ordered).hidden)
    }

    @Test
    fun savingTheLayoutKeepsTheAccountsOtherChoices() {
        val saved = json.parseToJsonElement(withChoice("""{"tvLook":{"theme":"x"},"home":{"v":1}}""", "home", HomeLayout(listOf("hero"), listOf("onnow")).toJson())).jsonObject
        assertEquals(JsonObject(mapOf("theme" to JsonPrimitive("x"))), saved["tvLook"])
        assertEquals(JsonArray(listOf(JsonPrimitive("onnow"))), saved["home"]?.jsonObject?.get("hidden"))
        assertEquals(2, saved["home"]?.jsonObject?.get("v")?.jsonPrimitive?.int)
        val later = json.parseToJsonElement(withChoice("", "updateLater", JsonPrimitive("1.5.0"))).jsonObject
        assertEquals("1.5.0", later["updateLater"]?.jsonPrimitive?.content)
    }

    @Test
    fun theGreetingFollowsTheClock() {
        assertEquals("Good morning, Willow", HomeGreeting.line(5, "Willow"))
        assertEquals("Good afternoon", HomeGreeting.line(12, ""))
        assertEquals("Good afternoon", HomeGreeting.words(17))
        assertEquals("Good evening", HomeGreeting.words(18))
        assertEquals("Good evening", HomeGreeting.words(4))
    }

    // MARK: the hero

    @Test
    fun runTimesAreTheWebsites() {
        assertEquals("", runtimeWords(0.0))
        assertEquals("30 s", runtimeWords(30.0))
        assertEquals("1 s", runtimeWords(0.2))
        assertEquals("45 min", runtimeWords(2700.0))
        assertEquals("1 h 52 min", runtimeWords(6720.0))
        assertEquals("the hour kept whole", "2 h 0 min", runtimeWords(7200.0))
        assertEquals("minutes rounded", "1 h 31 min", runtimeWords(5430.0))
    }

    @Test
    fun theHerosFactsAreADottedRowWithTheRatingAndScoreAndDisc() {
        val film = item("""{"id":1,"title":"A","kind":"video","year":2019,"runtimeSec":6720,"contentRating":"PG-13","rating":7.46,"genres":["Drama","War","History","Family"]}""")
        val facts = HeroLook.facts(film)
        assertEquals(
            listOf(HeroFact.Words("2019"), HeroFact.Words("1 h 52 min"), HeroFact.Rating("PG-13"), HeroFact.Score("7.5"), HeroFact.Words("Drama"), HeroFact.Words("War"), HeroFact.Words("History")),
            facts,
        )
        assertEquals("no dot beside the rating's box", listOf(true, true, false, false, true, true, true), facts.indices.map { HeroLook.dotted(facts, it) })
        val disc = item("""{"id":2,"title":"B","kind":"dvd-iso","rating":0,"genres":[]}""")
        assertEquals("menus not known count as there", listOf(HeroFact.Words("DVD · interactive menus")), HeroLook.facts(disc))
        val plain = item("""{"id":3,"title":"C","kind":"bluray-folder","disc":{"hasMenus":false}}""")
        assertEquals("the disc's name even without menus", listOf(HeroFact.Words("Blu-ray")), HeroLook.facts(plain))
    }

    @Test
    fun theMainButtonIsWordedForWhatItIsAndGoesWhereItsPlayed() {
        val film = item("""{"id":1,"title":"A","kind":"video"}""")
        assertEquals("Play", OpenLook.label(film))
        assertEquals(OpenAction.Play, OpenLook.action(film))
        assertEquals("Resume", OpenLook.label(item("""{"id":1,"title":"A","kind":"video","progress":{"resumeSec":120}}""")))
        val disc = item("""{"id":2,"title":"B","kind":"dvd-iso"}""")
        assertEquals("Play", OpenLook.label(disc))
        assertEquals("a disc plays in the server's player", OpenAction.Server("/play/2"), OpenLook.action(disc))
        assertEquals("/play/2?mode=menu", OpenLook.discMenu(disc))
        val book = item("""{"id":3,"title":"C","kind":"book","reader":"epub"}""")
        assertEquals("Read", OpenLook.label(book))
        assertEquals(OpenAction.Server("/read/3"), OpenLook.action(book))
        assertEquals(OpenAction.Server("/item/3"), OpenLook.action(item("""{"id":3,"title":"C","kind":"book"}""")))
        val song = item("""{"id":4,"title":"D","kind":"audio","progress":{"resumeSec":40}}""")
        assertEquals("Continue listening", OpenLook.label(song))
        assertEquals(OpenAction.Listen, OpenLook.action(song))
        val cd = item("""{"id":5,"title":"E","kind":"cd-image"}""")
        assertEquals("Insert disc", OpenLook.label(cd))
        assertEquals(OpenAction.Server("/cd/5?play=1"), OpenLook.action(cd))
        assertEquals(OpenAction.Server("/game/6"), OpenLook.action(item("""{"id":6,"title":"F","kind":"game","console":"snes"}""")))
        assertEquals(OpenAction.Page, OpenLook.action(item("""{"id":7,"title":"G","kind":"game","console":"rig"}""")))
    }

    // MARK: cards

    @Test
    fun aFilmCardSaysItsYearAndLengthWithItsPlates() {
        val film = item("""{"id":1,"title":"A","kind":"bluray-iso","year":2001,"runtimeSec":5400,"progress":{"watched":true,"positionSec":5000,"durationSec":5400}}""")
        val look = CardLook.item(film)
        assertEquals("A", look.title)
        assertEquals("2001 · 1 h 30 min", look.subtitle)
        assertEquals(CardShape.Poster, look.shape)
        assertEquals(listOf(CardBadge.Disc("Blu-ray"), CardBadge.Seen), look.badges)
        assertNull("no bar once it's watched", look.progress)
        val going = item("""{"id":2,"title":"B","kind":"video","progress":{"positionSec":30,"durationSec":120}}""")
        assertEquals(0.25f, CardLook.item(going).progress)
        assertEquals("", CardLook.item(going).subtitle)
    }

    @Test
    fun anEpisodeIsAWideStillWithItsShowsName() {
        val episode = item("""{"id":1,"title":"Pilot","kind":"video","showId":4,"showTitle":"The Show","season":1,"episode":2,"runtimeSec":1500}""")
        val wide = CardLook.item(episode)
        assertEquals(CardShape.Wide, wide.shape)
        assertEquals("The Show", wide.title)
        assertEquals("S1 · E2 · Pilot", wide.subtitle)
        val poster = CardLook.item(episode, wide = false)
        assertEquals(CardShape.Poster, poster.shape)
        assertEquals("Pilot", poster.title)
        assertEquals("S1 · E2 · 25 min", poster.subtitle)
        assertEquals("Special · E1–2 · Bonus", CardLook.item(item("""{"id":2,"title":"Bonus","showId":4,"season":0,"episode":1,"episodeEnd":2}""")).subtitle)
    }

    @Test
    fun songsBooksAndCDsSayWhoTheyreBy() {
        val song = CardLook.item(item("""{"id":1,"title":"One","kind":"audio","album":"Album","artist":"Solo","albumArtist":""}"""))
        assertEquals("One", song.title)
        assertEquals("Solo", song.subtitle)
        assertEquals(CardShape.Square, song.shape)
        val cd = CardLook.item(item("""{"id":2,"title":"Live","kind":"cd-image","albumArtist":"Band","runtimeSec":3000}"""))
        assertEquals(listOf(CardBadge.Disc("CD")), cd.badges)
        assertEquals("Band", cd.subtitle)
        assertEquals("1999", CardLook.item(item("""{"id":3,"title":"Book","kind":"book","year":1999,"runtimeSec":300}""")).subtitle)
        assertEquals("Author", CardLook.item(item("""{"id":3,"title":"Book","kind":"book","artist":"Author"}""")).subtitle)
    }

    @Test
    fun aShowCardCountsItsSeasonsAndWhatsLeft() {
        val show = CardLook.show(json.decodeFromString<Show>("""{"id":1,"title":"S","year":2019,"seasonCount":3,"episodeCount":30,"unwatched":4}"""))
        assertEquals("2019 · 3 seasons", show.subtitle)
        assertEquals(listOf(CardBadge.Unwatched(4)), show.badges)
        val seen = CardLook.show(json.decodeFromString<Show>("""{"id":2,"title":"T","seasonCount":1,"episodeCount":8,"unwatched":0}"""))
        assertEquals("1 season", seen.subtitle)
        assertEquals(listOf(CardBadge.Seen), seen.badges)
        val fresh = CardLook.show(json.decodeFromString<Show>("""{"id":3,"title":"U","seasonCount":1,"episodeCount":8,"unwatched":8}"""))
        assertEquals("nothing watched yet: no count", emptyList<CardBadge>(), fresh.badges)
        assertEquals("no seasons yet still says so", "0 seasons", CardLook.show(json.decodeFromString<Show>("""{"id":4,"title":"V","unwatched":3}""")).subtitle)
    }

    @Test
    fun commercialsStayOutOfHomeUnlessSwitchedOn() {
        val libraries = json.decodeFromString<List<Library>>(
            """[{"id":1,"name":"Films","type":"movies","scanning":true},{"id":2,"name":"Ads","type":"commercials"},{"id":3,"name":"Spots","type":"commercials","showMain":true}]""",
        )
        assertEquals(listOf(1L, 3L), libraries.filter { it.inMainMenus }.map { it.id })
        assertTrue(libraries.first().scanning)
    }

    // MARK: On TV now

    @Test
    fun onNowPutsFavouritesFirstAndSaysWhatsOn() {
        val guide = json.decodeFromString<Guide>(
            """
            {"channels":[
              {"key":"a","number":"1","name":"One","kind":"tuner","programmes":[{"start":1000,"end":4600,"title":"News","itemId":null}]},
              {"key":"b","number":"2","name":"Two","kind":"library","favourite":true,"programmes":[{"start":0,"end":900,"title":"Gone"}]},
              {"key":"c","number":"3","name":"Three","kind":"tuner","favourite":true,"programmes":[{"start":1000,"end":9000,"title":"Film","itemId":12}]}]}
            """,
        )
        val channels = OnNowLook.ordered(guide.channels)
        assertEquals(listOf("b", "c", "a"), channels.map { it.key })
        assertEquals("Off air", OnNowLook.title(channels[0], 1300.0))
        assertEquals("Two", OnNowLook.detail(channels[0], 1300.0))
        assertEquals("Film", OnNowLook.title(channels[1], 1300.0))
        assertEquals(12L, OnNowLook.programme(channels[1], 1300.0)?.itemId)
        assertEquals("One · 55 min left", OnNowLook.detail(channels[2], 1300.0))
        assertEquals(0.25f, OnNowLook.fraction(channels[2], 1900.0))
        assertEquals("No guide data", OnNowLook.title(channels[2], 5000.0))
        assertEquals("Channel 1, One: News", OnNowLook.spoken(channels[2], 1300.0))
        assertEquals("Channel 2, Two: nothing listed", OnNowLook.spoken(channels[0], 1300.0))
        assertEquals("1 min", OnNowLook.left(20.0))
        assertEquals("1h 5m", OnNowLook.left(3900.0))
        assertEquals("2h", OnNowLook.left(7200.0))
    }

    @Test
    fun cantDecideSaysTheYearLengthAndTwoGenres() {
        assertEquals("1994 · 2 h 22 min · Crime, Drama", ShuffleLook.facts(item("""{"id":1,"title":"A","year":1994,"runtimeSec":8520,"genres":["Crime","Drama","Thriller"]}""")))
        assertEquals("", ShuffleLook.facts(item("""{"id":1,"title":"A","genres":[]}""")))
    }

    // MARK: a newer server

    @Test
    fun theUpdateNoticeIsForAdminsUntilTheyPutItOff() {
        assertTrue(UpdateNews.shows("1.5.0", true, ""))
        assertTrue("Later was for an older version", UpdateNews.shows("1.5.0", true, "1.4.0"))
        assertFalse(UpdateNews.shows("1.5.0", true, "1.5.0"))
        assertFalse(UpdateNews.shows("1.5.0", false, ""))
        assertFalse(UpdateNews.shows("", true, ""))
        assertEquals("WittyMediaServer 1.5.0 is available", UpdateNews.title("1.5.0"))
    }

    @Test
    fun theUpdateNoticeLeadsWithTheNewestChange() {
        val status = json.decodeFromString<UpdateStatus>(
            """
            {"current":"1.4.0","method":"docker","phase":"idle","canApply":false,"latest":{"version":"1.5.0","changes":[
              {"version":"1.5.0","notes":"Intro\n- **DVDs and Blu-rays in Firefox.** They play now.\n- A [link](https://example.com) fixed\n"},
              {"version":"1.4.1","notes":"* `code` change:\n+ third"}]}}
            """,
        )
        assertEquals("DVDs and Blu-rays in Firefox", UpdateNews.headline(status.latest?.changes.orEmpty()).first)
        assertEquals("DVDs and Blu-rays in Firefox, and 3 more changes.", UpdateNews.sentence(status))
        assertEquals("How to update", UpdateNews.action(status))
        assertEquals("Update", UpdateNews.action(null))
        val links = UpdateNews.headline(listOf(UpdateChange("1", "- See [the guide](/help/x) for `more`.")))
        assertEquals("See the guide for more", links.first)
        assertEquals(0, links.second)
        val long = "word ".repeat(30)
        val cut = UpdateNews.headline(listOf(UpdateChange("1", "- $long"))).first
        assertTrue(cut, cut.endsWith("word…"))
        assertTrue(cut.length <= 89)
        assertEquals("A newer version of the server is ready to install.", UpdateNews.sentence(json.decodeFromString("""{"current":"1"}""")))
        assertEquals("One, and 1 more change.", UpdateNews.sentence(json.decodeFromString("""{"latest":{"version":"2","changes":[{"version":"2","notes":"- One\n- Two"}]}}""")))
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
    fun homeAsksForWhatTheWebsiteAsksFor() = withServer({ request ->
        when {
            request.path.startsWith("/api/v1/items") -> """{"items":[{"id":8,"title":"Random"}],"total":1}"""
            request.path.startsWith("/api/v1/guide") -> """{"channels":[]}"""
            else -> """{"home":{"v":2,"order":["shuffle"],"hidden":[]},"updateLater":"1.2.0"}"""
        }
    }) { api, asked ->
        runBlocking {
            assertEquals(8L, api.randomItem()?.id)
            api.guide(1, OnNowLook.LIMIT)
            val choices = api.homeChoices()
            assertEquals(listOf("shuffle"), choices.home?.order)
            assertEquals("1.2.0", choices.updateLater)
        }
        assertEquals(
            listOf("/api/v1/items?sort=random&limit=1&noEpisodes=1&watchable=1", "/api/v1/guide?hours=1&limit=16", "/api/v1/me/ui"),
            asked.map { it.path },
        )
    }

    @Test
    fun savingTheLayoutReadsTheChoicesFirstAndKeepsThem() = withServer({ request ->
        if (request.method == "PUT") "{}" else """{"tvLook":{"theme":"x"},"home":{"v":1}}"""
    }) { api, asked ->
        runBlocking { api.saveHomeLayout(HomeLayout(listOf("hero"), listOf("onnow"))) }
        assertEquals(listOf("GET /api/v1/me/ui", "PUT /api/v1/me/ui"), asked.map { "${it.method} ${it.path}" })
        val sent = json.parseToJsonElement(asked.last().body).jsonObject
        assertEquals("x", sent["tvLook"]?.jsonObject?.get("theme")?.jsonPrimitive?.content)
        assertEquals(JsonArray(listOf(JsonPrimitive("hero"))), sent["home"]?.jsonObject?.get("order"))
    }
}
