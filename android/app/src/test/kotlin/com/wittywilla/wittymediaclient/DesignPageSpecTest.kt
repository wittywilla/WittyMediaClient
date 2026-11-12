// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.A1
import com.wittywilla.wittymediaclient.net.A2
import com.wittywilla.wittymediaclient.net.BackStep
import com.wittywilla.wittymediaclient.net.Cc
import com.wittywilla.wittymediaclient.net.DesignPageSpec
import com.wittywilla.wittymediaclient.net.R
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.secC
import com.wittywilla.wittymediaclient.net.secN
import com.wittywilla.wittymediaclient.net.secP
import com.wittywilla.wittymediaclient.net.secR
import org.junit.Assert.assertEquals
import org.junit.Test

class DesignPageSpecTest {
    // The canvas's `connect` page, as it is written there.
    private val connect = DesignPageSpec.mk(
        "Welcome", "Choose your server", "Saved servers come first. Servers found on your network are below.",
        listOf(
            secR("Saved", listOf(R("WittyMediaServer", "Last used", true, "Living room"), R("Gran’s server", "", false, "From away"))),
            secR("Found on this network", listOf(R("Basement NAS", "", false, "192.168.1.31"))),
            secP("", listOf(Cc("Enter an address"), Cc("Join from away"), Cc("Scan a QR code"))),
            secN("", "Notes are not stops for focus.", true),
            secR("On this device", listOf(R("Show saved servers first", "On", true), R("Version", "0.8", pressable = false))),
        ),
        listOf(A1("Connect"), A2("Cancel")),
    )

    @Test fun idsAreSlugsOfTheWords() {
        assertEquals("show-saved-servers-first", DesignPageSpec.slug("Show saved servers first"))
        assertEquals("gran-s-server", DesignPageSpec.slug("Gran’s server"))
        assertEquals("item", DesignPageSpec.slug("…"))
        assertEquals("custom", R("Anything", id = "custom").id)
    }

    @Test fun focusRunsTopToBottomAndSkipsWhatOnlySaysSomething() {
        assertEquals(
            listOf("wittymediaserver", "gran-s-server", "basement-nas", "enter-an-address", "join-from-away", "scan-a-qr-code", "show-saved-servers-first", "connect", "cancel"),
            connect.focusOrder,
        )
        assertEquals("wittymediaserver", connect.startFocus)
        assertEquals("connect", connect.copy(start = "connect").startFocus)
        assertEquals("wittymediaserver", connect.copy(start = "nothing").startFocus)
    }

    @Test fun backFollowsTheLadder() {
        assertEquals(BackStep.StageToBar, connect.back)
        assertEquals(BackStep.CloseLayer, connect.copy(layer = true).back)
    }

    @Test fun cardsAcrossNeverMoreThanTwoOnAPhone() {
        val s = secC("Themes", emptyList(), 6)
        assertEquals(2, DesignPageSpec.columns(s, phone = true, tablet = false))
        assertEquals(6, DesignPageSpec.columns(s, phone = false, tablet = true))
        assertEquals(4, DesignPageSpec.columns(secC("x", emptyList()), phone = false, tablet = false))
    }

    @Test fun readsTheSameJsonAsApple() {
        val text = """{"title":"Mix","sections":[{"kind":"rows","rows":[{"id":"v","title":"Voice","value":"20%","on":true}]},{"kind":"chips","chips":[{"title":"Reset"}]}],"actions":[{"title":"Done","primary":true}],"layer":true}"""
        val spec = json.decodeFromString(DesignPageSpec.serializer(), text)
        assertEquals("v", spec.sections[0].rows[0].id)
        assertEquals(listOf("v", "reset", "done"), spec.focusOrder)
        assertEquals(spec, json.decodeFromString(DesignPageSpec.serializer(), json.encodeToString(DesignPageSpec.serializer(), spec)))
    }
}
