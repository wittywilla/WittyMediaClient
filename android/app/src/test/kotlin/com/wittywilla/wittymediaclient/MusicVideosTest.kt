package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.MusicLinkSide
import com.wittywilla.wittymediaclient.net.MusicLinks
import com.wittywilla.wittymediaclient.net.MusicVideoCard
import com.wittywilla.wittymediaclient.net.MusicVideoPage
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.ui.MusicLook
import com.wittywilla.wittymediaclient.ui.MusicVideoSongPlace
import com.wittywilla.wittymediaclient.ui.MusicVideos
import com.wittywilla.wittymediaclient.ui.MusicTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

// The website's music videos (music/MusicVideos.tsx, music/links.ts, creators/parts.tsx, gallery.ts), ported from the
// iPhone's MusicVideosTests. Where the website's code says otherwise, it wins: a search is written as its
// URLSearchParams writes it.
class MusicVideosTest {
    private inline fun <reified T> decode(text: String): T = json.decodeFromString(text)

    @Test
    fun onlyAMusicVideosLibraryMakesThemAvailable() {
        val some = decode<List<Library>>("""[{"id":1,"name":"Music","type":"music"},{"id":2,"name":"Concerts","type":"musicvideos"}]""")
        assertTrue(MusicVideos.available(some))
        assertFalse(MusicVideos.available(some.take(1)))
        assertFalse(MusicVideos.available(emptyList()))
        // The tab sits between Songs and Playlists, for music only.
        assertEquals(listOf("Home", "Albums", "Artists", "Songs", "Music videos", "Playlists"), MusicLook.tabs("music", videos = true).map { it.second })
        assertEquals(listOf("Home", "Books", "Authors"), MusicLook.tabs("audiobooks", videos = true).map { it.second })
        assertEquals(MusicTab.Videos, MusicTab.of("videos"))
    }

    @Test
    fun theTabAndTheShelfAskWhatTheWebsiteAsks() {
        assertEquals("/music/videos?limit=120&offset=0", MusicVideos.path("", 0))
        assertEquals("/music/videos?limit=120&offset=120&search=a-ha+%26+co", MusicVideos.path("a-ha & co", 120))
        assertEquals("/music/videos?limit=12&sort=latest", MusicVideos.LATEST_PATH)
    }

    @Test
    fun aPageOfVideosAsTheServerSendsIt() {
        val page = decode<MusicVideoPage>(
            """
            {"videos":[
              {"id":9,"libraryId":4,"title":"Take On Me","durationSec":225,"width":1920,"height":1080,"vertical":false,"creatorId":3,"creator":"a-ha",
               "hasAvatar":true,"uploadDate":"2024-05-31","tags":null,"views":2,"origViews":1500,"likes":0,"origLikes":0,"comments":0,"reaction":0,
               "positionSec":45,"watched":false,"updatedAt":17,
               "song":{"id":5,"libraryId":1,"title":"Take On Me","artist":"a-ha","album":"Hunting High and Low","runtimeSec":225,"updatedAt":3},"syncMs":4000},
              {"id":10,"libraryId":4,"title":"Live","durationSec":0,"vertical":true,"creatorId":3,"creator":"a-ha","hasAvatar":false,"uploadDate":"",
               "views":0,"origViews":0,"positionSec":0,"watched":true,"updatedAt":0}
            ],"more":true}
            """,
        )
        assertTrue(page.more)
        assertEquals(listOf(9L, 10L), page.videos.map { it.id })
        val first = page.videos[0]
        assertEquals(4000L, first.syncMs)
        assertEquals("Hunting High and Low", first.song?.album)
        assertEquals(1502L, MusicVideos.allViews(first))
        assertEquals(0.2, MusicVideos.progress(first), 0.0001)
        assertEquals("On Hunting High and Low", MusicVideos.songWords(first))
        assertNull(page.videos[1].song)
        assertNull(MusicVideos.songWords(page.videos[1]))
        assertEquals(0.0, MusicVideos.progress(page.videos[1]), 0.0)
        assertTrue(page.videos[1].vertical)
        // Nothing in it at all is still a page.
        assertEquals(emptyList<MusicVideoCard>(), decode<MusicVideoPage>("""{"videos":null}""").videos)
    }

    @Test
    fun theSongUnderAVideoGoesToItsAlbumHereOrElseItsArtist() {
        val here = decode<MusicLinkSide>("""{"id":5,"libraryId":1,"title":"T","artist":"A","album":"B","runtimeSec":200}""")
        assertEquals(MusicVideoSongPlace.Album(1, "B", "A"), MusicVideos.songPlace(here, 1))
        assertEquals(MusicVideoSongPlace.Artist(1, "A"), MusicVideos.songPlace(here, 2))
        val single = decode<MusicLinkSide>("""{"id":5,"libraryId":1,"title":"T","artist":"A","runtimeSec":200}""")
        assertEquals(MusicVideoSongPlace.Artist(1, "A"), MusicVideos.songPlace(single, 1))
        val card = decode<MusicVideoCard>("""{"id":1,"song":{"id":5,"libraryId":1,"title":"T","artist":"A","album":"","runtimeSec":1}}""")
        assertEquals("In your music", MusicVideos.songWords(card))
    }

    @Test
    fun watchTheVideoFromHereWhenTheTwoLineUp() {
        val links = decode<MusicLinks>(
            """
            {"itemId":5,"role":"song","tied":[{"songId":5,"videoId":9,"state":"tied","how":"isrc","syncMs":4000,
              "song":{"id":5,"libraryId":1,"title":"T","artist":"A","runtimeSec":200},"video":{"id":9,"libraryId":4,"title":"T","artist":"A","runtimeSec":220}}],
             "suggested":[],"canEdit":false}
            """,
        )
        val tied = links.tied.first()
        assertEquals("song", links.role)
        // Thirty seconds into the song is four seconds later in the video.
        assertEquals(34.0, MusicVideos.place(true, 30.0, tied.syncMs, tied.video.runtimeSec)!!, 0.0)
        assertEquals(30.0, MusicVideos.place(false, 34.0, 4000, 200.0)!!, 0.0)
        assertEquals("/watch/9?t=34", MusicVideos.watchPath(tied, 30.9))
        // At the very start, near the end, or when they don't line up: the video from wherever its page starts it.
        assertEquals("/watch/9", MusicVideos.watchPath(tied, 217.0))
        assertNull(MusicVideos.place(false, 4.5, 4000, 200.0))
        assertNull(MusicVideos.place(true, 30.0, null, 220.0))
        assertEquals(3000.0, MusicVideos.place(true, 3000.0, 0, 0.0)!!, 0.0)
        assertEquals("/watch/9", MusicVideos.watchPath(9))
        // An item that can't be tied answers with nothing to tie.
        val none = decode<MusicLinks>("""{"itemId":7,"role":"","tied":[],"suggested":[],"canEdit":true}""")
        assertTrue(none.tied.isEmpty())
        assertTrue(none.canEdit)
    }

    @Test
    fun theWordsOnTheTab() {
        assertEquals("1 video", MusicVideos.count(1, false))
        assertEquals("120+ videos", MusicVideos.count(120, true))
        assertEquals("1,234 videos", MusicVideos.count(1234, false, java.util.Locale.UK))
        assertEquals("Nothing matches that", MusicVideos.empty(true).first)
        assertEquals("", MusicVideos.empty(true).second)
        assertEquals("No music videos yet", MusicVideos.empty(false).first)
    }

    @Test
    fun countsAndDatesUnderATile() {
        assertEquals("999", MusicVideos.shortCount(999))
        assertEquals("1K", MusicVideos.shortCount(1000))
        assertEquals("1.2K", MusicVideos.shortCount(1234))
        assertEquals("1.5M", MusicVideos.shortCount(1_500_000))
        assertEquals("2B", MusicVideos.shortCount(2_000_000_000))
        val now = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { clear(); set(2024, Calendar.JUNE, 30, 15, 0, 0) }.timeInMillis
        assertEquals("today", MusicVideos.ago("2024-06-30", now))
        assertEquals("yesterday", MusicVideos.ago("2024-06-29", now))
        assertEquals("5 days ago", MusicVideos.ago("2024-06-25", now))
        assertEquals("1 week ago", MusicVideos.ago("2024-06-20", now))
        assertEquals("4 weeks ago", MusicVideos.ago("2024-06-01", now))
        assertEquals("1 month ago", MusicVideos.ago("2024-05-10", now))
        assertEquals("2 months ago", MusicVideos.ago("2024-05-01", now))
        assertEquals("6 months ago", MusicVideos.ago("2024-01", now))
        assertEquals("2 years ago", MusicVideos.ago("2022", now))
        assertEquals("", MusicVideos.ago("", now))
        assertEquals("", MusicVideos.ago("20240531", now))
        val card = decode<MusicVideoCard>("""{"id":1,"views":0,"origViews":1234,"uploadDate":"2024-06-29"}""")
        assertEquals("1.2K views · yesterday", MusicVideos.facts(card, now))
        assertEquals("", MusicVideos.facts(decode<MusicVideoCard>("""{"id":1}"""), now))
    }

    @Test
    fun aCreatorWithNoPictureKeepsTheirColour() {
        // The website's Avatar: each character into the hue, times 31, within 360.
        assertEquals(65, MusicVideos.avatarHue("A"))
        assertEquals((65 * 31 + 66) % 360, MusicVideos.avatarHue("AB"))
        assertEquals(0, MusicVideos.avatarHue(""))
        // A character outside the first plane counts once, by its first half, as `for (const c of name)` reads it.
        assertEquals("😀".first().code % 360, MusicVideos.avatarHue("😀"))
    }
}
