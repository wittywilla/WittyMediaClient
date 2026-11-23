// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.TV_DESKTOP_ONLY
import com.wittywilla.wittymediaclient.net.TV_FULL
import com.wittywilla.wittymediaclient.net.TV_VIEW
import com.wittywilla.wittymediaclient.net.TvLevelTable
import com.wittywilla.wittymediaclient.net.TvPartLevel
import com.wittywilla.wittymediaclient.net.TvScreenLevel
import com.wittywilla.wittymediaclient.net.levelOf
import com.wittywilla.wittymediaclient.net.settingsCondition
import com.wittywilla.wittymediaclient.net.summaryOf
import com.wittywilla.wittymediaclient.ui.TEST_MENU
import com.wittywilla.wittymediaclient.ui.YouNative
import com.wittywilla.wittymediaclient.ui.YouOpens
import com.wittywilla.wittymediaclient.ui.YouWho
import com.wittywilla.wittymediaclient.ui.youGroups
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The settings menu every client draws (the server's settingsmenu.json): this app's You page is drawn from it.
class SettingsMenuTest {
    private val admin = YouWho(admin = true, adult = true, hasGames = true, twoStepAvailable = true, onTv = false,
        fromAway = true, moduleSettings = true, looks = true, nativeProfiles = true, remote = true, parties = true, layoutEditor = true)

    @Test
    fun theYouPageIsTheMenuInItsOrder() {
        val groups = youGroups(admin)
        assertEquals(listOf("groupAccount", "groupHousehold", "groupYours", "groupModules", "groupDevice", "groupServer", "groupMaintenance", "groupHelp"), groups.map { it.key })
        assertEquals(listOf("rowNames", "rowPassword", "rowTwoStep", "rowDevices"), groups[0].rows.map { it.key })
        assertEquals(
            listOf("rowLook", "rowEditLayout", "rowTheme", "rowServers", "rowAway", "rowPlayingHere"),
            groups.single { it.key == "groupDevice" }.rows.map { it.key },
        )
        // The settings the web has had alone are rows here too, in their groups.
        val all = groups.flatMap { it.rows }.map { it.key }
        for (key in listOf("rowQuality", "rowPages", "rowNetwork", "rowDataFolder")) assertTrue(key, key in all)
        assertEquals("rowAppLog", groups.last().rows.last().key)
    }

    @Test
    fun everyRowHasAnIconAndWordsInThisApp() {
        val words = java.io.File("../../shared/data/strings.en.json").readText()
        for (g in TEST_MENU.groups) {
            assertTrue(g.key, "\"${g.key}\"" in words)
            for (r in g.rows) {
                assertTrue(r.id, r.icon.android.isNotEmpty())
                assertTrue("${r.key} has no words", "\"${r.key}\"" in words)
            }
        }
    }

    @Test
    fun rowsOpenTheAppsOwnScreensOrTheServersPages() {
        val rows = youGroups(admin).flatMap { it.rows }.associateBy { it.key }
        assertEquals(YouOpens.Native(YouNative.Names), rows.getValue("rowNames").opens)
        assertEquals(YouOpens.Sdui("/manage/libraries"), rows.getValue("rowLibraries").opens)
        assertEquals(YouOpens.Page("/settings/quality"), rows.getValue("rowQuality").opens)
        assertEquals(YouOpens.Native(YouNative.Log), rows.getValue("rowAppLog").opens)
        assertEquals("/settings/remote", rows.getValue("rowRemote").path)
        assertEquals("app.brand-editor", rows.getValue("rowNameAndLogo").part)
    }

    @Test
    fun conditionsAsTheServerNamesThem() {
        assertTrue(settingsCondition("notTv", setOf("admin"), emptySet()))
        assertFalse(settingsCondition("notTv", setOf("tv"), emptySet()))
        assertFalse(settingsCondition("notOff:games", emptySet(), setOf("games")))
        assertFalse("a condition this app doesn't know keeps the row out", settingsCondition("someday", setOf("admin"), emptySet()))
    }

    @Test
    fun aTvShowsTheRowsItCantChangeInTheirPlace() {
        val table = TvLevelTable(
            screens = listOf(
                TvScreenLevel("settings.remote", "/settings/remote", TV_DESKTOP_ONLY, "Remote Access", "remote"),
                TvScreenLevel("settings.playback", "/settings/playback", TV_VIEW, "Playback"),
            ),
            parts = listOf(TvPartLevel("app.brand-editor", TV_DESKTOP_ONLY, "Name and logo")),
        )
        val rows = TEST_MENU.groups.flatMap { it.rows }.associateBy { it.id }
        assertEquals(TV_DESKTOP_ONLY, table.levelOf(rows.getValue("remote")))
        assertEquals(TV_DESKTOP_ONLY, table.levelOf(rows.getValue("nameAndLogo")))
        assertEquals(TV_VIEW, table.levelOf(rows.getValue("playback")))
        assertEquals(TV_FULL, table.levelOf(rows.getValue("quality")))
        assertEquals(TV_FULL, table.levelOf(rows.getValue("servers")))
        assertEquals("remote", table.summaryOf(rows.getValue("remote")))
        // With no table (an older server) every server page on a TV is the card, as before.
        assertEquals(TV_DESKTOP_ONLY, (null as TvLevelTable?).levelOf(rows.getValue("quality")))
        // On a TV the rows are the same, less Sign in a TV, and with the top menu.
        val tv = youGroups(admin.copy(onTv = true)).flatMap { it.rows }.map { it.key }
        assertFalse("rowSignInTv" in tv)
        assertTrue("rowTopMenu" in tv)
        assertTrue("rowRemote" in tv)
    }
}
