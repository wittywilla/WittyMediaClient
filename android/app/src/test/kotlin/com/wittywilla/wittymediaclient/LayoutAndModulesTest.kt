// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.ModuleSettingRow
import com.wittywilla.wittymediaclient.net.ModuleSettingsRules
import com.wittywilla.wittymediaclient.net.ModuleSettingsView
import com.wittywilla.wittymediaclient.net.SduiDevice
import com.wittywilla.wittymediaclient.net.SduiNavigation
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Layout options (docs/SDUI.md) and modules' settings (docs/SDUI-MODULES.md), as the app reads them.
class LayoutAndModulesTest {
    @Test
    fun theNavigationCarriesTheFrameAndTheChoice() {
        val nav = json.decodeFromString(
            SduiNavigation.serializer(),
            """{"version":1,"items":[],"shell":{"layout":"compactList","nav":"rail","size":72},
               "layouts":{"current":"compactList","chosen":"compactList","options":[{"value":"sidebar","label":"Sidebar"},{"value":"compactList","label":"Compact list"}],"url":"/api/v1/sdui/layout"}}""",
        )
        assertEquals("rail", nav.shell?.nav)
        assertEquals(72, nav.shell?.size)
        assertEquals(2, nav.layouts?.options?.size)
        assertEquals("/api/v1/sdui/layout", nav.layouts?.url)
        // An older server sends neither.
        assertNull(json.decodeFromString(SduiNavigation.serializer(), """{"version":1,"items":[]}""").shell)
    }

    @Test
    fun theDeviceNamesItselfForItsLayout() {
        val device = SduiDevice(platform = "android", formFactor = "tablet", device = "android-0a1b2c3d4e5f")
        assertTrue(device.on("/api/v1/sdui/navigation").contains("device=android-0a1b2c3d4e5f"))
        assertFalse(SduiDevice(platform = "android", formFactor = "phone").on("/x").contains("device="))
    }

    @Test
    fun onlyTheServersOwnSettingsAddressesAreFollowed() {
        assertEquals("/sdui/modules/wittyboardgames/settings", ModuleSettingsRules.path("/api/v1/sdui/modules/wittyboardgames/settings"))
        assertNull(ModuleSettingsRules.path("https://elsewhere.example/api/v1/sdui/modules/x/settings"))
        assertNull(ModuleSettingsRules.path("/api/v1/sdui/modules/../../users/settings"))
        assertNull(ModuleSettingsRules.path("/api/v1/sdui/modules/x"))
    }

    @Test
    fun aProfilesOwnValueGoesToItsOwnRouteAndIsAlwaysItsToChange() {
        val view = json.decodeFromString(
            ModuleSettingsView.serializer(),
            """{"module":"wittyboardgames","values":{"household":4,"ages":"kids","on":true},"editable":false}""",
        )
        val household = ModuleSettingRow(key = "household", kind = "int", label = "Players", min = 1, max = 12, unit = "people")
        val ages = ModuleSettingRow(key = "ages", kind = "enum", label = "Ages", scope = "profile")
        assertFalse(ModuleSettingsRules.editable(view, household))
        assertTrue(ModuleSettingsRules.editable(view, ages))
        assertEquals("/sdui/modules/w/settings/personal", ModuleSettingsRules.writePath("/sdui/modules/w/settings", ages))
        assertEquals("/sdui/modules/w/settings", ModuleSettingsRules.writePath("/sdui/modules/w/settings", household))
        assertEquals("4 people", ModuleSettingsRules.shown(view, household))
        assertTrue(ModuleSettingsRules.bool(view, "on"))
        assertEquals(12, ModuleSettingsRules.stepped(household, 12, 1))
        assertEquals(1, ModuleSettingsRules.stepped(household, null, -1))
        assertEquals("""{"values":{"ages":null}}""", ModuleSettingsRules.change("ages", null))
        assertFalse(ModuleSettingsRules.known(ModuleSettingRow(kind = "colour")))
    }

    @Test
    fun aNewServerTakesAShowsIdInItsOwnTemplates() {
        val spec = com.wittywilla.wittymediaclient.net.SduiCommandSpec(op = "watched.set", method = "POST", path = "/api/v1/items/{item}/progress", body = "{\"items\":[\"{item}\"]}")
        val r = com.wittywilla.wittymediaclient.net.SduiCommands.request(spec, "show-5")!!
        assertEquals("/api/v1/items/show-5/progress", r.path)
        assertEquals("{\"items\":[\"show-5\"]}", r.body)
    }
}
