// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Amount
import com.wittywilla.wittymediaclient.net.CssColour
import com.wittywilla.wittymediaclient.net.Look
import com.wittywilla.wittymediaclient.net.SceneLayer
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LookRulesTest {
    private fun theme(text: String) = json.parseToJsonElement(text) as JsonObject

    @Test fun `css colours in every form`() {
        assertEquals(CssColour(1.0, 1.0, 1.0, 0.3), CssColour.parse("rgba(255,255,255,.3)"))
        assertEquals(1.0, CssColour.parse("#ff0000")!!.r, 0.0)
        assertEquals(0.5, CssColour.parse("rgb(0 0 0 / 50%)")!!.a, 0.001)
        assertNull(CssColour.parse("red"))
        assertNull(CssColour.parse(null))
    }

    @Test fun `the look is read from the themes answer`() {
        val look = Look.from(theme("""{"look":{"type":"rounded","effects":{"glass":"subtle","gloss":"full"},"scene":{"layers":[
            {"type":"gradient","angle":180,"stops":[{"at":0,"color":"#6fcfff"},{"at":100,"color":"#e1f8d6"}]},
            {"type":"shape","kind":"circle","x":12,"y":22,"size":9,"color":"rgba(255,255,255,.3)"},
            {"type":"image","file":"sky.png"},{"type":"nonsense"}]},
            "finish":{"gloss":{"highlight":"#fff","upper":"#8cf","lower":"#37c","glow":"#9df","edge":"#246"}}}}"""))
        assertEquals("rounded", look.type)
        assertEquals(Amount.Subtle, look.glass)
        assertEquals(Amount.Full, look.gloss)
        assertEquals(3, look.scene.size)
        assertTrue(look.scene[0] is SceneLayer.Gradient)
        assertNotNull(look.glossRecipe)
        assertNull("no glass recipe was sent", look.glassRecipe)
    }

    @Test fun `reduced motion keeps the first layer only`() {
        val look = Look.from(theme("""{"look":{"scene":{"layers":[{"type":"gradient","stops":[{"at":0,"color":"#000"},{"at":100,"color":"#fff"}]},{"type":"shape","x":1,"y":1,"size":1,"color":"#fff"}]}}}"""))
        assertEquals(2, look.sceneFor(false).size)
        assertEquals(1, look.sceneFor(true).size)
    }

    @Test fun `no look is the plain look`() {
        assertEquals(Look.NONE, Look.from(theme("""{"theme":"default"}""")))
        assertEquals(Amount.None, Look.NONE.glass)
    }
}
