package com.wittywilla.wittymediaclient.net

import android.view.KeyEvent

// Which things have this app's own screens, and which open the server's own page inside the app.
// Video is built here. Everything else the server does, from music to books, photos, disc menus,
// the TV guide and its settings, is the server's page, so nothing it offers is out of reach and
// nothing has to be built twice. These are the decisions, kept apart from Android so they can be tested.

private val OWN_SCREEN_LIBRARIES = setOf("movies", "shows", "anime", "videos", "discs")

val Library.hasOwnScreen: Boolean get() = type in OWN_SCREEN_LIBRARIES || isRigGames

val Item.hasOwnScreen: Boolean get() = kind == "video" || isRigGame

// A row of songs or chapters shows each album or book once, under its own name.
fun albumsOnce(items: List<Item>): List<Item> {
    val seen = HashSet<String>()
    return items.mapNotNull { item ->
        if (item.kind != "audio" || item.album.isEmpty()) return@mapNotNull item
        val key = item.albumArtist.ifEmpty { item.artist } + "|" + item.album
        if (seen.add(key)) item.copy(title = item.album) else null
    }
}

fun Library.pagePath() = "/library/$id"
fun Item.pagePath() = "/item/$id"

const val GUIDE_PATH = "/tv"
fun channelPath(key: String) = "/tv/watch/" + java.net.URLEncoder.encode(key, "UTF-8")

// What the row on Home shows: favourites first, and nothing a device can't tune.
fun onNow(channels: List<GuideChannel>) = channels.filter { it.encrypted.isEmpty() }.sortedByDescending { it.favourite }

fun GuideChannel.programmeAt(now: Long) = programmes.firstOrNull { it.start <= now && now < it.end }

fun GuideProgramme.fraction(now: Long) = if (end > start) ((now - start).toFloat() / (end - start)).coerceIn(0f, 1f) else 0f

fun GuideProgramme.minutesLeft(now: Long) = ((end - now + 59) / 60).coerceAtLeast(1)
const val COLLECTIONS_PATH = "/collections"
const val SETTINGS_PATH = "/settings"

// The whole of the page's address. A TV asks for big screen mode: larger type and a stronger focus.
fun pageAddress(path: String, isTv: Boolean): String {
    if (!isTv) return path
    return path + (if ('?' in path) '&' else '?') + "tv=1"
}

// Android names a controller's buttons by where they sit, so a Nintendo pad's A, on the right, arrives as
// BUTTON_B, and its B, at the bottom, as BUTTON_A. Every other pad has its confirm button at the bottom. So on
// this app's own screens these say what the words printed on that pad mean. The server's page does the same for itself.
const val NINTENDO_VENDOR = 0x057e

fun nintendoKey(keyCode: Int): Int? = when (keyCode) {
    KeyEvent.KEYCODE_BUTTON_B -> KeyEvent.KEYCODE_DPAD_CENTER
    KeyEvent.KEYCODE_BUTTON_A -> KeyEvent.KEYCODE_BACK
    KeyEvent.KEYCODE_BUTTON_Y -> KeyEvent.KEYCODE_BUTTON_X
    KeyEvent.KEYCODE_BUTTON_X -> KeyEvent.KEYCODE_BUTTON_Y
    else -> null
}

// Where the page goes when Back has nothing left to go back through. It's never loaded: the web view catches it.
// A controller's buttons stay inside a web view, so this is the only way its B can leave one.
const val APP_BACK_PATH = "/.wittymedia-app-back"
const val OFFER_APP_BACK = "document.documentElement.dataset.appBack='$APP_BACK_PATH'"

// Whether the page has been shown a controller yet.
const val ASK_SEES_PAD = "(function(){try{return Array.from(navigator.getGamepads()).some(Boolean)}catch(e){return false}})()"

// The server's big screen mode is drawn for a screen 1920 wide, whatever a TV's density makes of it.
const val TV_VIEWPORT = "(function(){var m=document.querySelector('meta[name=viewport]');if(m)m.content='width=1920'})()"

// The oldest web view the server's pages are built for (`target` in its web/vite.config.ts). On anything older
// they're simply blank. Android 6 comes with version 44, and only an update changes that.
const val OLDEST_WEB_VIEW = 87

private val CHROME_VERSION = Regex("""Chrome/(\d+)\.""")

// From what a web view calls itself. One that doesn't say is given the benefit of the doubt.
fun webViewTooOld(userAgent: String): Boolean {
    val version = CHROME_VERSION.find(userAgent)?.groupValues?.get(1)?.toIntOrNull() ?: return false
    return version < OLDEST_WEB_VIEW
}

private val FILLS_THE_SCREEN = listOf("/play/", "/read/", "/tv/watch/", "/game/", "/couch-rig/", "/big")

// A player, a book or a game has the whole screen, and keeps it awake. The rest sits between the system's bars.
fun pageFillsScreen(path: String) = FILLS_THE_SCREEN.any { path.startsWith(it) } || (path.startsWith("/couch/") && "/play/" in path)

// What has its own idea of Back in the page. It says so itself in <html data-own-back>. A server older
// than that gets this list, as it was when it stopped changing.
private const val OLDER_OWN_BACK = "[role=dialog], [role=alertdialog], [role=menu], .modal, .picker-backdrop, .view-settings, .audio-bar.full, .reader, .player:not(.mini):not(.inline)"
const val ASK_OWN_BACK = "(function(){try{return !!document.querySelector(document.documentElement.dataset.ownBack||'$OLDER_OWN_BACK')}catch(e){return false}})()"
