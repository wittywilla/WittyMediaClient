// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// Where WittyPlay lives on the server's website, as its own frame knows it (WittyMediaServer web/src/shell/playPaths.ts),
// and as the Apple apps read it (WittyKit's WittyPlayPlace). With WittyPlay installed, the owner's choice for every app:
// games open WittyPlay, which takes the whole screen in its own frame (a status bar, a round dock, Return To Server).
object WittyPlayPlace {
    // WittyPlay Online's home: where Games goes.
    const val HOME = "/page/wittyplay-online"
    const val HOME_PAGE = "wittyplay-online"

    // WittyPlay's own settings: on a TV, its server-drawn page (there are no web pages there).
    const val SETTINGS = "/wittyplay/settings"
    const val SETTINGS_PAGE = "wittyplay-settings"

    // One games library as WittyPlay's server-drawn page, for a TV.
    const val LIBRARY_PAGE = "wittyplay-library"

    // The dock always starts with WittyPlay's own Home, so every one of its pages has one press back to it (the website's
    // dockFor in playPaths.ts).
    fun <T> dockFor(entries: List<T>, id: (T) -> String, route: (T) -> String, home: T): List<T> =
        if (entries.any { id(it) == "home" || route(it) == HOME }) entries else listOf(home) + entries

    // The dock's button for the page showing: its address and its tab, if it names one, are the page's own.
    fun isCurrent(buttonRoute: String, page: String, params: Map<String, String>): Boolean {
        if (buttonRoute.substringBefore('?') != "/page/$page") return false
        val tab = buttonRoute.substringAfter('?', "").split('&').firstOrNull { it.startsWith("tab=") }?.substringAfter('=')
        return tab == params["tab"]?.ifEmpty { null }
    }

    // One games library, as WittyPlay draws it.
    fun library(id: Long) = "/wittyplay/library/$id"

    // The address is one of WittyPlay's: its pages, its settings and its own views of the games libraries.
    fun isPlayPath(path: String): Boolean {
        val bare = path.substringBefore('?')
        return bare == HOME || bare == "/page/wittyplay" || bare.startsWith("/page/wittyplay-") || bare == "/design/play" ||
            bare == "/wittyplay" || bare.startsWith("/wittyplay/")
    }

    // A server page (an SDUI page's id) that is WittyPlay's.
    fun isPlayPage(page: String) = page == "wittyplay" || page.startsWith("wittyplay-")

    // WittyPlay is on this server: its menu entry is in the server's navigation.
    fun installed(items: List<SduiNavItem>) = items.any { isPlayPage(it.page) || isPlayPath(it.route) }

    // Where the frame's page went, for the app: staying in WittyPlay, a game to play in the app's own player, Return To
    // Server (Home), Search, or somewhere else of the app's.
    sealed interface Leave {
        data object Stay : Leave
        // As the frame asks: resume (resume=1), from a moment (slot=N), and with default settings only (safe=1).
        data class Play(val game: Long, val resume: Boolean = true, val slot: Int? = null, val safe: Boolean = false) : Leave
        data object Home : Leave
        data object Search : Leave
        data class Elsewhere(val path: String) : Leave
    }

    fun leave(path: String): Leave {
        val bare = path.substringBefore('?')
        val game = Regex("^/game/(\\d+)/?$").find(bare)?.groupValues?.get(1)?.toLongOrNull()
        return when {
            isPlayPath(path) -> Leave.Stay
            game != null -> {
                val q = path.substringAfter('?', "").split('&').filter { it.isNotEmpty() }.associate { it.substringBefore('=') to it.substringAfter('=', "") }
                val slot = q["slot"]?.toIntOrNull()
                Leave.Play(game, resume = slot == null && q["resume"] != "0", slot = slot, safe = q["safe"] == "1")
            }
            bare == "/" || bare.isEmpty() -> Leave.Home
            bare == "/search" -> Leave.Search
            else -> Leave.Elsewhere(path)
        }
    }
}
