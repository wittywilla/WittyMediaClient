package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.albumsOnce
import com.wittywilla.wittymediaclient.net.channelPath
import com.wittywilla.wittymediaclient.net.fraction
import com.wittywilla.wittymediaclient.net.minutesLeft
import com.wittywilla.wittymediaclient.net.nintendoKey
import com.wittywilla.wittymediaclient.net.onNow
import com.wittywilla.wittymediaclient.net.programmeAt
import com.wittywilla.wittymediaclient.net.hasOwnScreen
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
    fun whatIsOnNowAndHowFarThrough() {
        val channel = GuideChannel(key = "lib-1", programmes = listOf(GuideProgramme(100, 200, "First"), GuideProgramme(200, 400, "Second")))
        assertEquals("First", channel.programmeAt(150)?.title)
        assertEquals("Second", channel.programmeAt(200)?.title)
        assertEquals(null, channel.programmeAt(900))
        assertEquals(0.5f, channel.programmeAt(150)!!.fraction(150))
        assertEquals(1f, channel.programmeAt(150)!!.fraction(900))
        assertEquals(1L, channel.programmeAt(150)!!.minutesLeft(199))
    }

    @Test
    fun theRowOnHomeHasFavouritesFirstAndNothingEncrypted() {
        val row = onNow(listOf(GuideChannel(key = "a"), GuideChannel(key = "b", encrypted = "Encrypted"), GuideChannel(key = "c", favourite = true)))
        assertEquals(listOf("c", "a"), row.map { it.key })
    }

    @Test
    fun aChannelsKeyIsOnePieceOfTheAddress() {
        assertEquals("/tv/watch/lib-1", channelPath("lib-1"))
        assertEquals("/tv/watch/..%2Fsettings", channelPath("../settings"))
    }

    @Test
    fun aNintendoPadsButtonsMeanWhatsPrintedOnThem() {
        assertEquals(android.view.KeyEvent.KEYCODE_DPAD_CENTER, nintendoKey(android.view.KeyEvent.KEYCODE_BUTTON_B))
        assertEquals(android.view.KeyEvent.KEYCODE_BACK, nintendoKey(android.view.KeyEvent.KEYCODE_BUTTON_A))
        assertEquals(android.view.KeyEvent.KEYCODE_BUTTON_X, nintendoKey(android.view.KeyEvent.KEYCODE_BUTTON_Y))
        assertEquals(null, nintendoKey(android.view.KeyEvent.KEYCODE_BUTTON_L1))
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
