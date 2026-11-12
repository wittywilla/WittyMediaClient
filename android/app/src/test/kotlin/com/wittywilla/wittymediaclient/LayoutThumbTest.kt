// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.ThumbSpecs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LayoutThumbTest {
    @Test fun `the shipped looks each draw their own layout`() {
        val ids = listOf("lumen", "rail", "stage", "aero", "aeroNight", "aeroMeadow", "aeroSunset", "classic", "classicCable", "classicSatellite", "compact", "paper", "marquee", "crossbar", "bigpicture", "dashboard", "retro")
        val specs = ids.map { ThumbSpecs.forId(it) }
        assertEquals("every look has a different wireframe once nav, home, cards and finish are counted", 12, specs.toSet().size)
        assertEquals("sidebar", ThumbSpecs.forId("classic").nav)
        assertEquals("rail", ThumbSpecs.forId("rail").nav)
        assertEquals("widgets", ThumbSpecs.forId("dashboard").home)
        assertTrue(ThumbSpecs.forId("aero").glass)
    }

    @Test fun `an unknown look is the plain top-bar layout`() {
        assertEquals(ThumbSpecs.forId("lumen").nav, ThumbSpecs.forId("someone-elses").nav)
    }

    @Test fun `the servers descriptor wins over the table`() {
        val s = ThumbSpecs.from("lumen", "rail", "carousel", "square", true, "glass")
        assertEquals("rail", s.nav); assertEquals("carousel", s.home); assertEquals("square", s.cards); assertTrue(s.dock); assertTrue(s.glass)
        assertEquals(ThumbSpecs.forId("lumen"), ThumbSpecs.from("lumen", null, null, null, null, null))
    }

    @Test fun `menu styles map to the places a wireframe draws`() {
        assertEquals("rail", ThumbSpecs.navPlace("railDrawer")); assertEquals("bottom", ThumbSpecs.navPlace("bottomTabs"))
        assertEquals("side", ThumbSpecs.navPlace("tvSideMenu")); assertEquals("top", ThumbSpecs.navPlace("cableBar"))
    }
}
