// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SduiNavItem
import com.wittywilla.wittymediaclient.net.WittyPlayPlace
import com.wittywilla.wittymediaclient.net.WittyPlayPlace.Leave
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Games open WittyPlay's own frame, as on the website and the Apple apps; leaving it goes back to the app.
class WittyPlayPlaceTest {
    @Test
    fun wittyPlaysAddressesAreKnown() {
        assertTrue(WittyPlayPlace.isPlayPath("/page/wittyplay-online?tab=classics"))
        assertTrue(WittyPlayPlace.isPlayPath(WittyPlayPlace.library(4)))
        assertTrue(WittyPlayPlace.isPlayPath("/wittyplay"))
        assertFalse(WittyPlayPlace.isPlayPath("/page/wittyplayer"))
        assertFalse(WittyPlayPlace.isPlayPath("/library/4"))
        assertTrue(WittyPlayPlace.isPlayPage("wittyplay-controllers"))
        assertTrue(WittyPlayPlace.installed(listOf(SduiNavItem(id = "g", page = "wittyplay-online"))))
        assertFalse(WittyPlayPlace.installed(listOf(SduiNavItem(id = "m", page = "home"))))
    }

    @Test
    fun leavingTheFrameGoesBackToTheApp() {
        assertEquals(Leave.Stay, WittyPlayPlace.leave("/wittyplay/library/2"))
        assertEquals(Leave.Play(17), WittyPlayPlace.leave("/game/17"))
        assertEquals(Leave.Play(17, resume = true), WittyPlayPlace.leave("/game/17?resume=1"))
        assertEquals(Leave.Play(17, resume = false, slot = 3), WittyPlayPlace.leave("/game/17?slot=3"))
        assertEquals(Leave.Play(17, resume = false, safe = true), WittyPlayPlace.leave("/game/17?resume=0&safe=1"))
        assertEquals(Leave.Home, WittyPlayPlace.leave("/"))
        assertEquals(Leave.Search, WittyPlayPlace.leave("/search?q=zelda"))
        assertEquals(Leave.Elsewhere("/item/3"), WittyPlayPlace.leave("/item/3"))
    }
}
