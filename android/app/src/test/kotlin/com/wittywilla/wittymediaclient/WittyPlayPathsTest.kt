// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.games.GamesApi
import com.wittywilla.wittymediaclient.games.problemFrom
import com.wittywilla.wittymediaclient.net.Api
import org.junit.Assert.assertEquals
import org.junit.Test

// The game API is WittyPlay's (module API 5): its addresses carry the module's prefix, and a server without it says so.
class WittyPlayPathsTest {
    private val games = GamesApi(Api("http://server.test", "t"))

    @Test
    fun aSessionsStreamAndASavesPictureAreWittyPlays() {
        assertEquals("http://server.test/api/v1/modules/wittyplay/play/a%2Fb/stream", games.streamEndpoint("a/b").url)
        assertEquals("http://server.test/api/v1/modules/wittyplay/games/7/saves/2/thumb?v=9", games.saveThumbUrl(7, 2, 9))
        // A game's own pictures stay the server's.
        assertEquals("http://server.test/api/v1/items/7/backdrop?v=0", games.backdropUrl(com.wittywilla.wittymediaclient.games.GameItem(id = 7)))
    }

    @Test
    fun aServerWithoutWittyPlayNamesIt() {
        assertEquals("WittyPlay isn't installed on this server. Ask whoever runs it to add it.", problemFrom(424, ""))
        assertEquals("WittyPlay is off", problemFrom(424, """{"error":"WittyPlay is off","module":"wittyplay","moduleName":"WittyPlay"}"""))
    }
}
