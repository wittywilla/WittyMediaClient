package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.albumsOnce
import com.wittywilla.wittymediaclient.net.albumsWord
import com.wittywilla.wittymediaclient.net.artistsWord
import com.wittywilla.wittymediaclient.net.hasOwnScreen
import com.wittywilla.wittymediaclient.net.isListening
import com.wittywilla.wittymediaclient.net.isTrack
import com.wittywilla.wittymediaclient.net.keepsPlace
import com.wittywilla.wittymediaclient.net.pageAddress
import com.wittywilla.wittymediaclient.net.pageFillsScreen
import com.wittywilla.wittymediaclient.net.pagePath
import com.wittywilla.wittymediaclient.net.webViewTooOld
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerPagesTest {
    @Test
    fun videoAndListeningHaveScreensHereAndTheRestIsTheServersPage() {
        for (type in listOf("movies", "shows", "anime", "videos", "discs", "music", "audiobooks", "podcasts")) assertTrue(type, Library(type = type).hasOwnScreen)
        for (type in listOf("radio", "books", "photos", "games")) assertFalse(type, Library(type = type).hasOwnScreen)
        assertTrue(Library(type = "games", console = "rig").hasOwnScreen)
        assertTrue(Item(kind = "video").hasOwnScreen)
        assertTrue(Item(kind = "audio").hasOwnScreen)
        for (kind in listOf("book", "photo", "game", "dvd-iso", "bluray-folder", "cd-image", "radio")) assertFalse(kind, Item(kind = kind).hasOwnScreen)
        assertTrue(Item(kind = "game", console = "rig").hasOwnScreen)
    }

    @Test
    fun onlyBooksAndPodcastsKeepAPlace() {
        assertTrue(keepsPlace("audiobooks"))
        assertTrue(keepsPlace("podcasts"))
        assertFalse(keepsPlace("music"))
        assertFalse(keepsPlace(""))
    }

    @Test
    fun aListeningLibraryIsOneOfThree() {
        for (type in listOf("music", "audiobooks", "podcasts")) assertTrue(type, Library(type = type).isListening)
        for (type in listOf("movies", "radio", "books")) assertFalse(type, Library(type = type).isListening)
        assertTrue(Item(kind = "audio").isTrack)
        assertFalse(Item(kind = "cd-image").isTrack)
    }

    @Test
    fun aLibrarysPartsAreCalledWhatTheyAre() {
        assertEquals("Albums", albumsWord("music"))
        assertEquals("Books", albumsWord("audiobooks"))
        assertEquals("Podcasts", albumsWord("podcasts"))
        assertEquals("Artists", artistsWord("music"))
        assertEquals("Authors", artistsWord("audiobooks"))
    }

    @Test
    fun pagesAreOnThisServerAlone() {
        assertEquals("/library/4", Library(id = 4).pagePath())
        assertEquals("/item/9", Item(id = 9).pagePath())
    }

    @Test
    fun aTvAsksForBigScreenMode() {
        assertEquals("/tv?tv=1", pageAddress("/tv", isTv = true))
        assertEquals("/library/3?genre=x&tv=1", pageAddress("/library/3?genre=x", isTv = true))
        assertEquals("/tv", pageAddress("/tv", isTv = false))
    }

    @Test
    fun aPlayerABookAndAGameHaveTheWholeScreen() {
        for (path in listOf("/play/1", "/read/1", "/tv/watch/lib-1", "/game/1", "/couch-rig/1", "/big", "/couch/1/play/2")) assertTrue(path, pageFillsScreen(path))
        for (path in listOf("/", "/library/1", "/item/1", "/tv", "/settings", "/couch", "/couch/1")) assertFalse(path, pageFillsScreen(path))
    }

    @Test
    fun anOldWebViewIsToldApartFromANewOne() {
        assertTrue(webViewTooOld("Mozilla/5.0 (Linux; Android 6.0) AppleWebKit/537.36 Chrome/44.0.2403.119 Mobile Safari/537.36"))
        assertFalse(webViewTooOld("Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/143.0.7499.24 Mobile Safari/537.36"))
        assertFalse(webViewTooOld("Something that doesn't say"))
    }

    @Test
    fun aRowShowsEachAlbumOnceUnderItsOwnName() {
        val row = listOf(
            Item(id = 1, kind = "audio", title = "One", album = "First", albumArtist = "Band"),
            Item(id = 2, kind = "audio", title = "Two", album = "First", albumArtist = "Band"),
            Item(id = 3, kind = "audio", title = "Three", album = "First", albumArtist = "Someone else"),
            Item(id = 4, kind = "audio", title = "Loose"),
            Item(id = 5, kind = "video", title = "A film"),
        )
        val shown = albumsOnce(row)
        assertEquals(listOf(1L, 3L, 4L, 5L), shown.map { it.id })
        assertEquals(listOf("First", "First", "Loose", "A film"), shown.map { it.title })
    }
}
