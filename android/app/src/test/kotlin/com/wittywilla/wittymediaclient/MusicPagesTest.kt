package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Artist
import com.wittywilla.wittymediaclient.net.ArtistInfo
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.MusicHome
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.ui.MusicLook
import com.wittywilla.wittymediaclient.ui.MusicTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

// The music, audiobook and podcast pages as the website words and orders them (AudioLibrary.tsx, music/parts.tsx,
// music/ArtistPage.tsx, music/CoverFlow.tsx), ported from the iPhone's MusicPagesTests so both apps say the same. Where
// the website's code says otherwise, it wins: a whole hour is "1 h 0 min", as its fmtRuntime writes it.
class MusicPagesTest {
    @Test
    fun eachKindOfLibraryHasTheWebsitesTabs() {
        assertEquals(listOf("Home", "Albums", "Artists", "Songs", "Playlists"), MusicLook.tabs("music").map { it.second })
        assertEquals(listOf("Home", "Books", "Authors"), MusicLook.tabs("audiobooks").map { it.second })
        assertEquals(listOf("Home", "Podcasts"), MusicLook.tabs("podcasts").map { it.second })
        assertEquals(MusicTab.Artists, MusicTab.of("artists"))
        assertEquals(MusicTab.Home, MusicTab.of("nonsense"))
    }

    @Test
    fun sortsFollowTheTab() {
        assertEquals(listOf("Title", "Author", "Year", "Recently added", "Most played"), MusicLook.sorts(MusicTab.Albums, "audiobooks", "").map { it.label })
        assertTrue(MusicLook.sorts(MusicTab.Albums, "podcasts", "").isEmpty())
        assertEquals(listOf("Name", "Most albums"), MusicLook.sorts(MusicTab.Artists, "music", "").map { it.label })
        assertEquals(listOf("Name", "Most books"), MusicLook.sorts(MusicTab.Artists, "audiobooks", "").map { it.label })
        assertTrue(MusicLook.sorts(MusicTab.Songs, "music", "recent").isEmpty())
        assertEquals(6, MusicLook.sorts(MusicTab.Songs, "music", "liked").size)
        assertTrue(MusicLook.sorts(MusicTab.Home, "music", "").isEmpty())
        assertEquals("artist", MusicLook.startSort(MusicTab.Albums, "audiobooks"))
        assertEquals("name", MusicLook.startSort(MusicTab.Artists, "audiobooks"))
        assertEquals("title", MusicLook.startSort(MusicTab.Songs, "music"))
        // Newest and most start from that end.
        assertTrue(MusicLook.sorts(MusicTab.Albums, "music", "").first { it.key == "year" }.desc)
        assertFalse(MusicLook.sorts(MusicTab.Albums, "music", "").first { it.key == "title" }.desc)
        // The server sends years newest first: asking for oldest first turns the list round.
        assertTrue(MusicLook.reversed("year", false))
        assertFalse(MusicLook.reversed("year", true))
        assertTrue(MusicLook.reversed("title", true))
        assertEquals("Year: last to first. Switch to first to last", MusicLook.directionWords("Year", true))
    }

    private fun items(text: String): List<Item> = json.decodeFromString(text)

    private val twoTracks = """
        [{"id":1,"title":"One","runtimeSec":1800,"year":2013,"genres":["Ambient"],"progress":{"watched":true}},{"id":2,"title":"Two","runtimeSec":2040}]
    """

    @Test
    fun wordsOnThePages() {
        assertEquals("1 album", MusicLook.count(1, "album", "albums"))
        assertEquals("59 min", com.wittywilla.wittymediaclient.ui.runtimeWords(59.0 * 60))
        assertEquals("1 h 0 min", com.wittywilla.wittymediaclient.ui.runtimeWords(3600.0))
        assertEquals("1 h 4 min", com.wittywilla.wittymediaclient.ui.runtimeWords(3600.0 + 240))
        assertEquals(MusicLook.baseTitle("Across the Ocean"), MusicLook.baseTitle("Across the Ocean (Deluxe Edition)"))
        assertEquals(MusicLook.baseTitle("Across the Ocean"), MusicLook.baseTitle("Across the Ocean [2011 Remaster]"))
        assertNotEquals(MusicLook.baseTitle("Across the Ocean"), MusicLook.baseTitle("Collide"))
        val tracks = items(twoTracks)
        assertEquals("2 tracks · 1 h 4 min · 2013 · Ambient", MusicLook.albumFacts(tracks, "music"))
        assertEquals("2 episodes", MusicLook.albumFacts(tracks, "podcasts"))
        assertEquals("2 chapters · 1 h 4 min · 2013 · Ambient", MusicLook.albumFacts(tracks, "audiobooks"))
        assertEquals("1 track · 30 min · 2013 · Ambient", MusicLook.albumFacts(tracks.take(1), "music"))
        assertEquals(1, MusicLook.resumeIndex(tracks))
        assertEquals(1, MusicLook.playFrom("audiobooks", tracks))
        assertEquals(0, MusicLook.playFrom("podcasts", tracks))
        assertEquals("Press the heart on a song to keep it here.", MusicLook.emptySongs("liked", false).second)
        assertEquals("Nothing matches that", MusicLook.emptySongs("", true).first)
        assertEquals("", MusicLook.emptySongs("liked", true).second)
        assertEquals("Nothing played yet", MusicLook.emptySongs("recent", false).first)
        assertEquals("1,234 songs · 1 h 4 min", MusicLook.songsCount(List(1234) { if (it == 0) tracks[0] else if (it == 1) tracks[1] else Item() }, Locale.UK))
        assertEquals("1 song", MusicLook.songsCount(listOf(Item()), Locale.UK))
        assertEquals("Shows", MusicLook.albumShelf("podcasts"))
        assertEquals("3 podcasts", MusicLook.albumsCount(3, "podcasts"))
        assertEquals("1 author", MusicLook.artistsCount(1, "audiobooks"))
    }

    @Test
    fun aBooksPlayButtonSaysWhereItIs() {
        val started = items("""[{"id":1,"progress":{"positionSec":61,"watched":false}},{"id":2}]""")
        assertEquals("Continue", MusicLook.playWords("audiobooks", started))
        assertEquals("Play", MusicLook.playWords("music", started))
        assertEquals("Play newest", MusicLook.playWords("podcasts", started))
        assertEquals("Play", MusicLook.playWords("audiobooks", items("""[{"id":1,"progress":{"positionSec":3}}]""")))
        val episode = items("""[{"id":1,"aired":"2024-05-01","overview":"${"x".repeat(200)}"}]""").first()
        assertEquals(160, MusicLook.episodeLine(episode).length)
        assertTrue(MusicLook.episodeLine(episode).startsWith("2024-05-01 · x"))
    }

    @Test
    fun theSongsTabAsksForASortOnlyWhereItMeansSomething() {
        assertEquals("limit=2000&sort=title", MusicLook.songsQuery("", "title", false, "", ""))
        assertEquals("limit=2000&view=liked&sort=year&desc=1&genre=Hip+Hop&search=love+me", MusicLook.songsQuery("liked", "year", true, "Hip Hop", "love me"))
        assertEquals("limit=2000&view=recent", MusicLook.songsQuery("recent", "title", true, "", ""))
    }

    @Test
    fun anArtistsSinglesSitUnderTheirAlbums() {
        val info: ArtistInfo = json.decodeFromString(
            """{"name":"A","albums":[{"title":"Old","year":2001,"tracks":10},{"title":"Single","year":2020,"tracks":2},{"title":"New","year":2019,"tracks":9}],"tracks":[],"top":[],"genres":[]}""",
        )
        val music = MusicLook.discography(info.albums, newestFirst = true, books = false, locale = Locale.UK)
        assertEquals(listOf("New", "Old"), music.first.map { it.title })
        assertEquals(listOf("Single"), music.second.map { it.title })
        assertEquals(listOf("New", "Old", "Single"), MusicLook.discography(info.albums, newestFirst = false, books = true, locale = Locale.UK).first.map { it.title })
        assertEquals("3 albums · 0 songs", MusicLook.artistFacts(info, false))
        val home: MusicHome = json.decodeFromString("""{"hero":[{"title":"X","artist":"Y","genre":"Jazz"}],"counts":{"albums":3},"continue":[{"id":4,"title":"Part"}]}""")
        assertEquals("Jazz", home.hero.first().genre)
        assertTrue(home.songs.isEmpty())
        assertEquals(3, home.counts.albums)
        assertEquals(4L, home.resume.first().id)
        // A Go nil list arrives as null.
        assertTrue(json.decodeFromString<MusicHome>("""{"hero":null,"recent":null}""").recent.isEmpty())
    }

    @Test
    fun artistsAreFoundAndSorted() {
        val artists = listOf(Artist("Björk", albums = 3), Artist("ABBA", albums = 8), Artist("Air", albums = 3))
        assertEquals(listOf("Björk"), MusicLook.shownArtists(artists, "BJÖ", "name", false, Locale.UK).map { it.name })
        assertEquals(listOf("Air", "Björk", "ABBA"), MusicLook.shownArtists(artists, "", "albums", false, Locale.UK).map { it.name })
        assertEquals(listOf("ABBA", "Björk", "Air"), MusicLook.shownArtists(artists, "", "albums", true, Locale.UK).map { it.name })
        // By name, the server's order, either way round.
        assertEquals(listOf("Air", "ABBA", "Björk"), MusicLook.shownArtists(artists, "", "name", true, Locale.UK).map { it.name })
    }

    @Test
    fun theCoverFlowAtPhoneSize() {
        // min(58vw, 42vh) on a phone; a book's own clamp, which outranks it.
        assertEquals(217.5f, MusicLook.coverSize(375f, 812f, false), 0.01f)
        assertEquals(0.42f * 500f, MusicLook.coverSize(375f, 500f, false), 0.01f)
        assertEquals(292.32f, MusicLook.coverSize(375f, 812f, true), 0.01f)
        assertEquals(400f, MusicLook.coverSize(1024f, 1366f, false), 0.01f)
        val front = MusicLook.coverPlace(0f, 200f, true)
        assertEquals(0f, front.x, 0f)
        assertEquals(1f, front.alpha, 0f)
        val right = MusicLook.coverPlace(1f, 200f, true)
        assertEquals(200f, right.x, 0.01f)
        assertEquals(-24f, right.turn, 0f)
        assertEquals(0.96f, right.scale, 0.0001f)
        assertEquals(0.87f, right.alpha, 0.0001f)
        val left = MusicLook.coverPlace(-2f, 200f, true)
        assertEquals(-2 * 200 * 0.72f - 200 * 0.28f, left.x, 0.01f)
        assertEquals(24f, left.turn, 0f)
        assertEquals(0.59f, left.alpha, 0.0001f)
        // Wider than a phone the covers turn further.
        assertEquals(-52f, MusicLook.coverPlace(1f, 200f, false).turn, 0f)
    }

    @Test
    fun gridsAndTypeFollowTheScreen() {
        // repeat(auto-fill, minmax(104px, 1fr)) in a 375 screen's 343: two; in 393's 361: three.
        assertEquals(2, MusicLook.columns(343f, 104f, 16f))
        assertEquals(3, MusicLook.columns(361f, 104f, 16f))
        assertEquals(2, MusicLook.columns(380f, 130f, 16f))
        assertEquals(30f, MusicLook.displaySize(375f), 0.01f)
        assertEquals(30.664f, MusicLook.displaySize(412f), 0.01f)
        assertEquals(22.4f, MusicLook.heroTitleSize(412f), 0.01f)
    }
}
