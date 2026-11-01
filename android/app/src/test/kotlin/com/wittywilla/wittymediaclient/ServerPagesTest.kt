package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.albumsOnce
import com.wittywilla.wittymediaclient.net.hasOwnScreen
import com.wittywilla.wittymediaclient.net.pageAddress
import com.wittywilla.wittymediaclient.net.pageFillsScreen
import com.wittywilla.wittymediaclient.net.pagePath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerPagesTest {
    @Test
    fun videoHasScreensHereAndTheRestIsTheServersPage() {
        for (type in listOf("movies", "shows", "anime", "videos", "discs")) assertTrue(type, Library(type = type).hasOwnScreen)
        for (type in listOf("music", "audiobooks", "podcasts", "radio", "books", "photos", "games")) assertFalse(type, Library(type = type).hasOwnScreen)
        assertTrue(Library(type = "games", console = "rig").hasOwnScreen)
        assertTrue(Item(kind = "video").hasOwnScreen)
        for (kind in listOf("audio", "book", "photo", "game", "dvd-iso", "bluray-folder", "cd-image", "radio")) assertFalse(kind, Item(kind = kind).hasOwnScreen)
        assertTrue(Item(kind = "game", console = "rig").hasOwnScreen)
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
