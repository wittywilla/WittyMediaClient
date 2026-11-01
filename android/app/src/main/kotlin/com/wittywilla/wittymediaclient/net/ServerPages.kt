package com.wittywilla.wittymediaclient.net

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
const val COLLECTIONS_PATH = "/collections"
const val SETTINGS_PATH = "/settings"

// The whole of the page's address. A TV asks for big screen mode: larger type and a stronger focus.
fun pageAddress(path: String, isTv: Boolean): String {
    if (!isTv) return path
    return path + (if ('?' in path) '&' else '?') + "tv=1"
}

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
