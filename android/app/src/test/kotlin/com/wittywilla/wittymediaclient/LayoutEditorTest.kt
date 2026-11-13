// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Dir
import com.wittywilla.wittymediaclient.net.EditorState
import com.wittywilla.wittymediaclient.net.ItemRef
import com.wittywilla.wittymediaclient.net.LayoutEditor
import com.wittywilla.wittymediaclient.net.PlacementsAnswer
import com.wittywilla.wittymediaclient.net.SduiCustomise
import com.wittywilla.wittymediaclient.net.SduiPersonalSection
import com.wittywilla.wittymediaclient.net.SduiPlacement
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The layout editor (docs/plans/DESIGN-2.md 7.3 and 7.5): pick up, move, drop, cancel, undo, what is said and what is sent.
class LayoutEditorTest {
    // What GET /sdui/placements answers, with the regions the server has.
    private val answer = json.decodeFromString<PlacementsAnswer>(
        """{"experience":"lumen","editable":true,
        "regions":[{"id":"brand","label":"Server name","positions":["start","center","top"]},
                   {"id":"nav","label":"Menu","positions":["start","end","top","bottom"],"locked":true},
                   {"id":"search","label":"Search","positions":["nav","top","floating"]},
                   {"id":"profile","label":"You","positions":["nav","top"],"locked":true},
                   {"id":"clock","label":"Clock","positions":["top","dock"]},
                   {"id":"dock","label":"Dock","positions":["top","bottom","side"]},
                   {"id":"legend","label":"Key legend"},
                   {"id":"hero","label":"Spotlight","styles":["billboard","banner","carousel","row"]}],
        "placements":{"brand":{"position":"start"},"nav":{"position":"top","visible":true},"search":{"position":"top"},"profile":{"position":"top"},
                      "clock":{"position":"top"},"dock":{"position":"bottom"},"legend":{"visible":true},"hero":{"style":"billboard","visible":true}},
        "own":{"search":{"position":"nav"}}}""",
    )

    private fun page(vararg ids: String, allow: Set<String> = setOf("reorder", "hide", "pin", "density", "cardSize"), locked: Set<String> = emptySet()) =
        SduiCustomise(ids.map { SduiPersonalSection(it, it.replaceFirstChar { c -> c.uppercase() }, locked = it in locked) }, allow)

    private fun start(page: SduiCustomise? = page("jump", "tv", "new", "settings", locked = setOf("settings")), editable: Boolean = true): EditorState =
        LayoutEditor.start(answer, page, editable)

    private val brand = ItemRef.region("brand")
    private val nav = ItemRef.region("nav")
    private val tv = ItemRef.section("tv")

    @Test fun `the regions come from the server and start where it says`() {
        val s = start()
        assertEquals("start", s.doc.regions["brand"]!!.position)
        assertEquals("top", s.doc.regions["nav"]!!.position)
        assertEquals("billboard", s.doc.regions["hero"]!!.style)
        assertTrue(s.doc.regions["legend"]!!.visible)
        assertEquals(8, s.caps.regions.size)
        assertEquals(listOf("brand", "nav", "search", "profile", "clock", "dock", "legend", "hero", "jump", "tv", "new", "settings"), LayoutEditor.items(s).map { it.id })
        assertFalse(s.dirty)
    }

    @Test fun `pick up with OK, arrows move, OK drops, and it is one change to undo`() {
        var s = LayoutEditor.focus(start(), tv)
        s = LayoutEditor.pickUp(s)
        assertEquals(tv, s.held)
        assertTrue(s.said.startsWith("Picked up Tv."))
        s = LayoutEditor.move(s, Dir.Up)
        assertEquals(listOf("tv", "jump", "new", "settings"), s.doc.page!!.sections.map { it.id })
        assertTrue(s.said, s.said.contains("moved up, now 1 of 4"))
        s = LayoutEditor.move(s, Dir.Down)
        s = LayoutEditor.move(s, Dir.Down)
        assertEquals(listOf("jump", "new", "tv", "settings"), s.doc.page!!.sections.map { it.id })
        s = LayoutEditor.drop(s)
        assertNull(s.held)
        assertTrue(s.said, s.said.startsWith("Dropped Tv, position 3 of 4"))
        assertTrue(s.dirty)
        assertEquals(1, s.undo.size)
        s = LayoutEditor.undo(s)
        assertEquals(listOf("jump", "tv", "new", "settings"), s.doc.page!!.sections.map { it.id })
        assertFalse(s.dirty)
        s = LayoutEditor.redo(s)
        assertEquals(listOf("jump", "new", "tv", "settings"), s.doc.page!!.sections.map { it.id })
    }

    @Test fun `Back puts it back exactly where it was`() {
        var s = LayoutEditor.pickUp(start(), tv)
        s = LayoutEditor.move(LayoutEditor.move(s, Dir.Down), Dir.Down)
        s = LayoutEditor.cancel(s)
        assertNull(s.held)
        assertFalse(s.dirty)
        assertTrue(s.undo.isEmpty())
        assertTrue(s.said.startsWith("Cancelled."))
        assertEquals(listOf("jump", "tv", "new", "settings"), s.doc.page!!.sections.map { it.id })
    }

    @Test fun `a section cannot be carried past the first or last place and says so`() {
        var s = LayoutEditor.pickUp(start(), ItemRef.section("jump"))
        val unchanged = s
        s = LayoutEditor.move(s, Dir.Up)
        assertEquals(unchanged.doc, s.doc)
        assertTrue(s.said.contains("already first"))
        s = LayoutEditor.move(s, Dir.Left)
        assertTrue(s.said.contains("up and down"))
    }

    @Test fun `a locked section stays where it is and cannot be hidden`() {
        val s = start()
        val settings = ItemRef.section("settings")
        val tried = LayoutEditor.pickUp(s, settings)
        assertNull(tried.held)
        assertTrue(tried.said, tried.said.contains("stays where it is"))
        val hid = LayoutEditor.setVisible(s, settings, false)
        assertEquals(s.doc, hid.doc)
        assertTrue(hid.said.contains("can't be hidden"))
    }

    @Test fun `Settings and You are the regions that cannot be hidden`() {
        val s = start()
        assertEquals(s.doc, LayoutEditor.setVisible(s, nav, false).doc)
        assertTrue(LayoutEditor.setVisible(s, nav, false).said.contains("can't be hidden"))
        assertEquals(s.doc, LayoutEditor.setVisible(s, ItemRef.region("profile"), false).doc)
        val hidden = LayoutEditor.setVisible(s, ItemRef.region("legend"), false)
        assertFalse(hidden.doc.regions["legend"]!!.visible)
        assertEquals("Key legend hidden", hidden.said)
        assertFalse(LayoutEditor.isVisible(hidden, ItemRef.region("legend")))
        assertTrue(LayoutEditor.setVisible(hidden, ItemRef.region("legend"), true).doc.regions["legend"]!!.visible)
    }

    @Test fun `arrows step a region through the places it has`() {
        var s = LayoutEditor.pickUp(start(), nav)
        // top is between start and bottom on the way round
        s = LayoutEditor.move(s, Dir.Right)
        assertEquals("bottom", s.doc.regions["nav"]!!.position)
        assertEquals("Menu now at the bottom", s.said)
        s = LayoutEditor.move(s, Dir.Right)
        assertEquals("end", s.doc.regions["nav"]!!.position)
        s = LayoutEditor.move(s, Dir.Right)
        assertTrue(s.said.contains("last place"))
        s = LayoutEditor.move(LayoutEditor.move(LayoutEditor.move(s, Dir.Left), Dir.Up), Dir.Up)
        assertEquals("start", s.doc.regions["nav"]!!.position)
        s = LayoutEditor.drop(s)
        assertEquals(1, s.undo.size)
    }

    @Test fun `a region with one place cannot be picked up`() {
        val s = LayoutEditor.pickUp(start(), ItemRef.region("legend"))
        assertNull(s.held)
        assertTrue(s.said.contains("only one place"))
    }

    @Test fun `a region at the look's own default steps onto its first or last place`() {
        val bare = LayoutEditor.start(answer.copy(placements = mapOf("brand" to SduiPlacement())), null, false)
        var s = LayoutEditor.pickUp(bare, brand)
        s = LayoutEditor.move(s, Dir.Right)
        assertEquals("start", s.doc.regions["brand"]!!.position)
    }

    @Test fun `pinned sections do not move and a pinned one leads`() {
        var s = start()
        s = LayoutEditor.togglePinned(s, "new")
        assertEquals("new", s.doc.page!!.sections.first().id)
        assertTrue(s.said.contains("pinned to the top"))
        val tried = LayoutEditor.pickUp(s, ItemRef.section("new"))
        assertNull(tried.held)
        assertTrue(tried.said.contains("pinned"))
        s = LayoutEditor.togglePinned(s, "new")
        assertTrue(s.said.contains("unpinned"))
    }

    @Test fun `a page that allows nothing cannot be rearranged`() {
        val none = start(page("a", "b", allow = emptySet()))
        assertNull(LayoutEditor.pickUp(none, ItemRef.section("a")).held)
        val off = start(editable = false)
        assertNull(LayoutEditor.pickUp(off, tv).held)
        assertTrue(LayoutEditor.pickUp(off, tv).said.contains("can't be moved in this view"))
        // but the regions are still its to change when the scope is the shell's
        assertNotNull(LayoutEditor.pickUp(off, brand).held)
    }

    @Test fun `hiding a section and showing it again`() {
        var s = start()
        s = LayoutEditor.setVisible(s, tv, false)
        assertTrue(s.doc.page!!.sections.first { it.id == "tv" }.hidden)
        assertEquals(listOf("tv"), LayoutEditor.hiddenSections(s.doc))
        assertEquals("Tv hidden", s.said)
        s = LayoutEditor.setVisible(s, tv, false)
        assertTrue(s.said.contains("already hidden"))
        s = LayoutEditor.setVisible(s, tv, true)
        assertTrue(LayoutEditor.hiddenSections(s.doc).isEmpty())
    }

    @Test fun `place, style, card size and spacing are one undoable change each`() {
        var s = start()
        s = LayoutEditor.setPosition(s, "dock", "top")
        s = LayoutEditor.setStyle(s, "hero", "carousel")
        s = LayoutEditor.setCardSize(s, "tv", "l")
        s = LayoutEditor.setDensity(s, "compact")
        assertEquals(4, s.undo.size)
        assertEquals("top", s.doc.regions["dock"]!!.position)
        assertEquals("carousel", s.doc.regions["hero"]!!.style)
        assertEquals("l", s.doc.page!!.cardSize["tv"])
        assertEquals("compact", s.doc.page!!.density)
        val third = LayoutEditor.undo(LayoutEditor.undo(LayoutEditor.undo(s)))
        assertEquals("billboard", third.doc.regions["hero"]!!.style)
        assertEquals("bottom", LayoutEditor.undo(third).doc.regions["dock"]!!.position)
        // a place or style the region does not have is refused
        assertEquals(s.doc, LayoutEditor.setPosition(s, "brand", "floating").doc)
        assertEquals(s.doc, LayoutEditor.setStyle(s, "hero", "huge").doc)
    }

    @Test fun `a new change after an undo clears redo and the stack is bounded`() {
        var s = start()
        s = LayoutEditor.setStyle(s, "hero", "banner")
        s = LayoutEditor.undo(s)
        assertTrue(s.canRedo)
        s = LayoutEditor.setStyle(s, "hero", "row")
        assertFalse(s.canRedo)
        var many = start()
        repeat(150) { many = LayoutEditor.setStyle(many, "hero", if (it % 2 == 0) "banner" else "row") }
        assertEquals(100, many.undo.size)
    }

    @Test fun `nothing is undone while something is held`() {
        var s = LayoutEditor.setStyle(start(), "hero", "banner")
        s = LayoutEditor.pickUp(s, tv)
        assertEquals(s, LayoutEditor.undo(s))
        assertFalse(s.canUndo)
        // and nothing is changed from the side panel until it is dropped
        assertEquals(s.doc, LayoutEditor.setPosition(s, "dock", "top").doc)
    }

    @Test fun `a screen reader moves a section in one go with Move up`() {
        val s = LayoutEditor.quickMove(start(), tv, Dir.Down)
        assertNull(s.held)
        assertEquals(listOf("jump", "new", "tv", "settings"), s.doc.page!!.sections.map { it.id })
        assertEquals(1, s.undo.size)
        assertTrue(s.said.contains("moved down"))
    }

    @Test fun `a drag that ends over another section takes its place`() {
        val s = LayoutEditor.dropSectionOn(start(), "jump", "new")
        assertEquals(listOf("tv", "new", "jump", "settings"), s.doc.page!!.sections.map { it.id })
        assertEquals(1, s.undo.size)
        assertEquals(s.doc, LayoutEditor.dropSectionOn(s, "tv", "tv").doc)
        // the locked section keeps its place
        val onLocked = LayoutEditor.dropSectionOn(start(), "tv", "settings")
        assertEquals("settings", onLocked.doc.page!!.sections.last().id)
    }

    @Test fun `a drag of a region carries it some places along its own`() {
        val s = LayoutEditor.stepRegion(start(), "nav", -1)
        assertEquals("start", s.doc.regions["nav"]!!.position)
        assertEquals("end", LayoutEditor.stepRegion(start(), "nav", 5).doc.regions["nav"]!!.position)
        assertEquals(1, s.undo.size)
        assertTrue(LayoutEditor.stepRegion(s, "nav", -1).said.contains("already"))
    }

    // MARK: what is sent

    @Test fun `only what changed is sent, laid over what the profile already had`() {
        var s = start()
        s = LayoutEditor.setPosition(s, "dock", "top")
        s = LayoutEditor.setVisible(s, ItemRef.region("legend"), false)
        s = LayoutEditor.setStyle(s, "hero", "carousel")
        val patch = LayoutEditor.placementsPatch(answer.placements, answer.own, s)
        assertEquals(SduiPlacement("nav"), patch["search"])
        assertEquals(SduiPlacement("top"), patch["dock"])
        assertEquals(SduiPlacement("", false, ""), patch["legend"])
        assertEquals(SduiPlacement("", null, "carousel"), patch["hero"])
        assertNull(patch["brand"])
        assertNull(patch["nav"])
    }

    @Test fun `a locked region is never sent hidden`() {
        var s = start()
        s = s.copy(doc = s.doc.copy(regions = s.doc.regions + ("nav" to s.doc.regions["nav"]!!.copy(visible = false))))
        val patch = LayoutEditor.placementsPatch(answer.placements, emptyMap(), s)
        assertNull(patch["nav"])
    }

    @Test fun `an unchanged editor sends only what was already there`() {
        assertEquals(answer.own, LayoutEditor.placementsPatch(answer.placements, answer.own, start()))
    }

    @Test fun `the body of PUT placements is the strict shape the server reads`() {
        val body = json.parseToJsonElement(LayoutEditor.ownBody(mapOf("dock" to SduiPlacement("top"), "legend" to SduiPlacement("", false, "")))).jsonObject
        val p = body["placements"]!!.jsonObject
        assertEquals("top", p["dock"]!!.jsonObject["position"]!!.jsonPrimitive.content)
        assertEquals("false", p["legend"]!!.jsonObject["visible"]!!.jsonPrimitive.content)
        assertFalse(p["legend"]!!.jsonObject.containsKey("position"))
        assertEquals(setOf("placements"), body.keys)
    }

    private val policy: JsonObject = json.parseToJsonElement(
        """{"default":{"tv":"cableTv"},"allowed":["lumen","cableTv"],"placements":{"lumen":{"dock":{"position":"top"}},"rail":{"nav":{"position":"end"}}},
            "required":{"everyone":{"experience":"lumen","by":"admin","at":"2026-11-12T00:00:00Z"}},"profileThemes":true}""",
    ).jsonObject

    @Test fun `the administrator's layer is read out of the experience policy`() {
        assertEquals(mapOf("dock" to SduiPlacement("top")), LayoutEditor.layerOf(policy, "lumen"))
        assertTrue(LayoutEditor.layerOf(policy, "aero").isEmpty())
        assertTrue(LayoutEditor.layerOf(JsonObject(emptyMap()), "lumen").isEmpty())
    }

    @Test fun `saving for everyone changes one experience's layer and loses nothing else`() {
        val next = LayoutEditor.policyWith(policy, "lumen", mapOf("dock" to SduiPlacement("side")))
        assertEquals("side", next["placements"]!!.jsonObject["lumen"]!!.jsonObject["dock"]!!.jsonObject["position"]!!.jsonPrimitive.content)
        assertEquals("end", next["placements"]!!.jsonObject["rail"]!!.jsonObject["nav"]!!.jsonObject["position"]!!.jsonPrimitive.content)
        assertEquals(policy["required"], next["required"])
        assertEquals(policy["allowed"], next["allowed"])
        assertEquals(policy["default"], next["default"])
        assertEquals(policy["profileThemes"], next["profileThemes"])
    }

    @Test fun `resetting an experience removes its layer, the last one removes placements altogether`() {
        val one = LayoutEditor.policyWith(policy, "lumen", null)
        assertFalse(one["placements"]!!.jsonObject.containsKey("lumen"))
        assertTrue(one["placements"]!!.jsonObject.containsKey("rail"))
        val none = LayoutEditor.policyWith(one, "rail", emptyMap())
        assertFalse(none.containsKey("placements"))
        assertEquals(policy["required"], none["required"])
        assertFalse(LayoutEditor.policyWithoutPlacements(policy).containsKey("placements"))
        assertEquals(policy["allowed"], LayoutEditor.policyWithoutPlacements(policy)["allowed"])
    }

    // MARK: where the regions are drawn

    @Test fun `the editor draws a top menu, its brand and search at the top and the sections in the body`() {
        val z = LayoutEditor.zones(answer.regions, start().doc)
        // the menu is at the top, the brand at its start, search and You at the top, the dock at the foot
        assertEquals(listOf("brand", "nav", "search", "profile", "clock"), z.top)
        assertEquals(listOf("dock", "legend"), z.bottom)
        assertEquals(listOf("hero"), z.body)
        assertTrue(z.left.isEmpty() && z.right.isEmpty() && z.hidden.isEmpty())
    }

    @Test fun `a side menu takes the left column with what sits in the menu`() {
        var s = LayoutEditor.setPosition(start(), "nav", "start")
        s = LayoutEditor.setPosition(s, "search", "nav")
        s = LayoutEditor.setPosition(s, "profile", "nav")
        val z = LayoutEditor.zones(answer.regions, s.doc)
        assertEquals(listOf("brand", "nav", "search", "profile"), z.left)
        assertEquals(listOf("clock"), z.top)
        val right = LayoutEditor.zones(answer.regions, LayoutEditor.setPosition(s, "nav", "end").doc)
        assertEquals(listOf("nav", "search", "profile"), right.right.filter { it != "brand" })
    }

    @Test fun `hidden regions leave the page for the tray, a floating search goes over the body`() {
        var s = LayoutEditor.setVisible(start(), ItemRef.region("legend"), false)
        s = LayoutEditor.setPosition(s, "search", "floating")
        val z = LayoutEditor.zones(answer.regions, s.doc)
        assertEquals(listOf("legend"), z.hidden)
        assertTrue("search" in z.body)
        assertFalse("legend" in z.bottom)
    }

    @Test fun `a menu with no chosen place is drawn where its style sits`() {
        val none = answer.copy(placements = answer.regions.associate { it.id to SduiPlacement() })
        val phone = LayoutEditor.start(none, null, false, navStyle = "bottomTabs")
        val z = LayoutEditor.zones(none.regions, phone.doc, phone.caps.navDefault)
        assertTrue("nav" in z.bottom)
        assertTrue("brand" in z.top)
        val side = LayoutEditor.start(none, null, false, navStyle = "rail")
        assertTrue("nav" in LayoutEditor.zones(none.regions, side.doc, side.caps.navDefault).left)
        assertEquals("top", LayoutEditor.navDefault("topTabs"))
        assertEquals("top", LayoutEditor.navDefault("tvTopMenu"))
        assertEquals("start", LayoutEditor.navDefault(""))
    }

    @Test fun `positions are ordered along the edge`() {
        assertEquals(listOf("start", "top", "bottom", "end"), LayoutEditor.ordered(listOf("start", "end", "top", "bottom")))
        assertEquals(listOf("top", "side", "bottom"), LayoutEditor.ordered(listOf("top", "bottom", "side")))
    }
}
