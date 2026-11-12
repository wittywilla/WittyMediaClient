// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SduiExperienceList
import com.wittywilla.wittymediaclient.net.SduiWire
import com.wittywilla.wittymediaclient.net.Wire
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// A look's wireframe is drawn from the experience's `wire` (GET /sdui/experiences), by form factor.
class LayoutThumbTest {
    private val list = json.decodeFromString(SduiExperienceList.serializer(), """{"experiences":[
      {"id":"lumen","name":"Lumen","wire":{"tv":{"nav":"top","style":"pill","home":"hero","cards":"poster","dock":true,"brand":"left","finish":"flat"},
        "phone":{"nav":"bottom","style":"pill","home":"hero","cards":"poster","brand":"top","finish":"flat"}}},
      {"id":"aero","name":"Aero","wire":{"desktop":{"nav":"top","style":"gloss","home":"hero","cards":"poster","brand":"left","finish":"glass"}}},
      {"id":"plain","name":"Plain"}]}""")

    @Test fun `the wire is read for the form factor`() {
        val lumen = list.experiences[0].wire
        assertEquals("bottom", Wire.of(lumen, "phone").nav)
        assertEquals("top", Wire.of(lumen, "tv").nav)
        assertTrue(Wire.of(lumen, "tv").dock)
    }

    @Test fun `a form factor the server did not send takes desktop, else the plain look`() {
        assertEquals("gloss", Wire.of(list.experiences[1].wire, "tablet").style)
        assertEquals(SduiWire(), Wire.of(list.experiences[2].wire, "tv"))
    }

    @Test fun `glass and gloss finishes draw as glass`() {
        assertTrue(Wire.glass(SduiWire(finish = "glass")))
        assertTrue(Wire.glass(SduiWire(finish = "gloss")))
        assertFalse(Wire.glass(SduiWire(finish = "flat")))
    }
}
