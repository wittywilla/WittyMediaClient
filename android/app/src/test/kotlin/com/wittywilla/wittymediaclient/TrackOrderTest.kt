// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.TrackOrder
import com.wittywilla.wittymediaclient.net.TrackOrder.Group
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackOrderTest {
    private data class T(val id: Int, val title: String, val lang: String)

    private fun order(list: List<T>, device: List<String>, recent: List<String>) =
        TrackOrder.order(list, { it.lang }, { it.title }, { it.id < 0 }, device, recent)

    @Test fun codesOfOneLanguageAreOne() {
        assertEquals("en", TrackOrder.base("eng"))
        assertEquals("de", TrackOrder.base("ger"))
        assertEquals("de", TrackOrder.base("deu"))
        assertEquals("en", TrackOrder.base("en-GB"))
        assertEquals("pt", TrackOrder.base("pt_BR"))
        assertEquals("", TrackOrder.base("und"))
        assertEquals("", TrackOrder.base(null))
    }

    @Test fun offThenDeviceThenRecentThenTheRestByName() {
        val tracks = listOf(T(-1, "Off", ""), T(1, "Spanish", "spa"), T(2, "Greek", "gre"), T(3, "English", "eng"), T(4, "English SDH", "eng"), T(5, "Danish", "dan"), T(6, "Arabic", "ara"))
        val got = order(tracks, listOf("en-GB", "en"), listOf("es"))
        assertEquals(listOf(-1, 3, 4, 1, 6, 5, 2), got.map { it.first.id })
        assertEquals(listOf(Group.Off, Group.Device, Group.Device, Group.Recent, Group.Other, Group.Other, Group.Other), got.map { it.second })
    }

    @Test fun aRecentLanguageThatIsTheDevicesIsListedOnce() {
        val got = order(listOf(T(1, "French", "fra"), T(2, "German", "deu")), listOf("fr"), listOf("fr", "de"))
        assertEquals(listOf(Group.Device, Group.Recent), got.map { it.second })
    }

    @Test fun searchMatchesTheStartOfAnyWord() {
        val words = listOf("English", "SDH", "Text", "eng")
        assertTrue(TrackOrder.matches(words, "eng"))
        assertTrue(TrackOrder.matches(words, "sdh"))
        assertTrue(TrackOrder.matches(words, "en sd"))
        assertFalse(TrackOrder.matches(words, "span"))
        assertTrue(TrackOrder.matches(words, "  "))
    }

    @Test fun picksAreRememberedNewestFirstFiveAtMost() {
        var saved = ""
        for (c in listOf("eng", "spa", "fra", "deu", "ita", "jpn", "spa")) saved = TrackOrder.remember(saved, c)
        assertEquals(listOf("es", "ja", "it", "de", "fr"), TrackOrder.recent(saved))
        assertEquals(saved, TrackOrder.remember(saved, "und"))
    }
}
