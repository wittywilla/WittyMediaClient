package com.wittywilla.wittymediaclient.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.wittywilla.wittymediaclient.games.GamePageScreen
import com.wittywilla.wittymediaclient.games.GamePlayerScreen
import com.wittywilla.wittymediaclient.games.GameStart
import com.wittywilla.wittymediaclient.games.GamesLibraryScreen
import com.wittywilla.wittymediaclient.games.GamesNav
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library

// WittyPlay, the server's games, in the app's own screen stack: a games library in couch mode, a game's page and
// the player (the code is in the games package). A game's PC library (console "rig") isn't here: it plays through
// Moonlight. These are the only ways in, so the rest of the app needs one line where it opens a library or an item.

data class GamesRoute(val screen: GamesScreen) : Route {
    override val key = "games-" + screen.key
}

sealed interface GamesScreen {
    val key: String

    data class Library(val id: Long, val console: String = "") : GamesScreen {
        override val key = "library-$id-$console"
    }

    data class Game(val id: Long) : GamesScreen {
        override val key = "game-$id"
    }

    data class Play(val id: Long, val start: GameStart) : GamesScreen {
        override val key = "play-$id"
    }
}

// Where a library or an item goes when it's one of the server's games, or null for everything else.
fun gamesRouteFor(library: Library): Route? =
    if (library.type == "games" && library.console != "rig") GamesRoute(GamesScreen.Library(library.id)) else null

fun gamesRouteFor(item: Item): Route? =
    if (item.kind == "game" && item.console != "rig") GamesRoute(GamesScreen.Game(item.id)) else null

@Composable
fun GamesRouteScreen(nav: Nav, route: GamesRoute) {
    val games = remember(nav, nav.app.api) {
        GamesNav(
            api = nav.app.api,
            back = { nav.back() },
            openGame = { id -> nav.push(GamesRoute(GamesScreen.Game(id))) },
            play = { id, start -> nav.push(GamesRoute(GamesScreen.Play(id, start))) },
            openLibrary = { id -> nav.replace(GamesRoute(GamesScreen.Library(id))) },
        )
    }
    when (val screen = route.screen) {
        is GamesScreen.Library -> GamesLibraryScreen(games, screen.id, screen.console)
        is GamesScreen.Game -> GamePageScreen(games, screen.id)
        // Saved and stopped, or the game ended itself: back to where it was started from.
        is GamesScreen.Play -> GamePlayerScreen(nav.app, screen.id, screen.start) { if (nav.current == route) nav.pop() }
    }
}
