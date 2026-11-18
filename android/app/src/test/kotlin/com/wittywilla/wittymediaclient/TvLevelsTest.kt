// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.TV_DESKTOP_ONLY
import com.wittywilla.wittymediaclient.net.TV_VIEW
import com.wittywilla.wittymediaclient.net.TvLevelTable
import com.wittywilla.wittymediaclient.net.TvPartLevel
import com.wittywilla.wittymediaclient.net.TvScreenLevel
import com.wittywilla.wittymediaclient.net.screenFor
import com.wittywilla.wittymediaclient.net.tvCardAddress
import com.wittywilla.wittymediaclient.net.tvPartOpens
import com.wittywilla.wittymediaclient.net.tvPathMatches
import com.wittywilla.wittymediaclient.net.tvShowsCard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TvLevelsTest {
    private val table = TvLevelTable(
        note = "Use a computer.",
        screens = listOf(
            TvScreenLevel("settings.libraries", "/settings/libraries", TV_DESKTOP_ONLY, "Libraries", "libraries"),
            TvScreenLevel("settings.pages", "/settings/pages/*", TV_DESKTOP_ONLY, "Pages"),
            TvScreenLevel("settings.users", "/settings/users", TV_VIEW, "Profiles"),
            TvScreenLevel("tv.channel-editor", "/tv/channels/:id", TV_DESKTOP_ONLY, "Channel editor"),
        ),
        parts = listOf(TvPartLevel("app.layout-editor", TV_DESKTOP_ONLY, "Editing the layout")),
    )

    @Test fun addressesMatchAsTheServerMatchesThem() {
        assertTrue(tvPathMatches("/settings/pages/*", "/settings/pages"))
        assertTrue(tvPathMatches("/settings/pages/*", "/settings/pages/page/home"))
        assertTrue(tvPathMatches("/tv/channels/:id", "/tv/channels/4?x=1"))
        assertFalse(tvPathMatches("/tv/channels/:id", "/tv/channels"))
        assertEquals("libraries", table.screenFor("/settings/libraries/")?.summary)
        assertNull(table.screenFor("/settings/games"))
    }

    @Test fun onlyEditorsAreTheCard() {
        assertTrue(tvShowsCard(table, "/settings/libraries"))
        assertTrue(tvShowsCard(table, "/tv/channels/new"))
        // View screens open: the server's page shows them with their controls off.
        assertFalse(tvShowsCard(table, "/settings/users"))
        // Console settings and controllers are a TV's own.
        assertFalse(tvShowsCard(table, "/settings/games"))
        assertFalse(tvShowsCard(table, "/controllers"))
        // An older server has no table: every server page is the card, as before.
        assertTrue(tvShowsCard(null, "/controllers"))
    }

    @Test fun ownEditors() {
        assertFalse(tvPartOpens(table, "app.layout-editor"))
        assertTrue(tvPartOpens(table, "app.something-else"))
        assertFalse(tvPartOpens(null, "app.layout-editor"))
    }

    @Test fun theAddressIsOneAPhoneCanOpen() {
        assertEquals("http://192.168.1.9:9797/settings/x", tvCardAddress("http://192.168.1.9:9797", "/settings/x", emptyList()))
        assertEquals("http://192.168.1.9:9797/settings/x", tvCardAddress("http://localhost:9797", "/settings/x", listOf("http://192.168.1.9:9797")))
        assertEquals("http://localhost:9797/settings/x", tvCardAddress("http://localhost:9797/", "settings/x", emptyList()))
    }
}
