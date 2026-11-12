// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

// The layout editor (docs/plans/DESIGN-2.md 7.3 and 7.5, the canvas page LayoutEditor): the shell's regions and the page's
// own sections, picked up with OK, moved with the arrows, dropped with OK, put back with Back. Apart from the screen, so the
// move rules, the undo stack, the words said to a screen reader and what is sent are all tested without one.
//
// What the server lets be changed (GET/PUT/DELETE /sdui/placements for the profile, PUT /sdui/config/experience for
// everyone, GET/PUT/DELETE of a page's personal for its sections): a region's position, whether it shows and its style
// (the spotlight's); a section's order, whether it shows, whether it is pinned, its card size, and the page's density.

@Serializable
data class RegionDef(
    val id: String = "",
    val label: String = "",
    val positions: List<String> = emptyList(),
    val locked: Boolean = false,
    val styles: List<String> = emptyList(),
)

// GET /sdui/placements.
@Serializable
data class PlacementsAnswer(
    val experience: String = "",
    val regions: List<RegionDef> = emptyList(),
    val placements: Map<String, SduiPlacement> = emptyMap(),
    val own: Map<String, SduiPlacement> = emptyMap(),
    val editable: Boolean = false,
)

// Where a region is, whether it shows, and its style, as the editor holds them.
data class RegionState(val position: String = "", val visible: Boolean = true, val style: String = "")

enum class LayoutScope { Everyone, Me }

enum class Dir { Up, Down, Left, Right }

// One thing that can be picked up: a region of the shell or a section of the page.
data class ItemRef(val section: Boolean, val id: String) {
    companion object {
        fun region(id: String) = ItemRef(false, id)
        fun section(id: String) = ItemRef(true, id)
    }
}

// What the editor draws and edits: the regions by id, and the page's sections (null when the page has none to arrange).
data class LayoutDoc(val regions: Map<String, RegionState>, val page: SduiCustomise?)

// What this scope may change.
// `navDefault` is where the look puts the menu when no one has chosen a place: "start" (a sidebar or rail), "top" (tabs or a
// bar) or "bottom" (a phone's tab bar), from the page's shell.
data class LayoutCaps(val regions: List<RegionDef>, val sectionsEditable: Boolean, val navDefault: String = "start") {
    fun region(id: String): RegionDef? = regions.firstOrNull { it.id == id }
}

data class EditorState(
    val caps: LayoutCaps,
    val doc: LayoutDoc,
    // The document as it was last saved (or loaded): what "unsaved" is measured against.
    val saved: LayoutDoc = doc,
    val undo: List<LayoutDoc> = emptyList(),
    val redo: List<LayoutDoc> = emptyList(),
    val focus: ItemRef? = null,
    val held: ItemRef? = null,
    val heldFrom: LayoutDoc? = null,
    // The last thing said to a screen reader, and shown in the live region.
    val said: String = "",
) {
    val dirty: Boolean get() = doc != saved
    val canUndo: Boolean get() = held == null && undo.isNotEmpty()
    val canRedo: Boolean get() = held == null && redo.isNotEmpty()
}

object LayoutWords {
    fun position(p: String): String = when (p) {
        "start" -> "at the start"
        "end" -> "at the end"
        "top" -> "at the top"
        "bottom" -> "at the bottom"
        "center" -> "in the middle"
        "nav" -> "in the menu"
        "floating" -> "floating over the page"
        "dock" -> "in the dock"
        "side" -> "at the side"
        "" -> "where the look puts it"
        else -> p
    }

    // The short name of a position, for a choice's button.
    fun choice(p: String): String = when (p) {
        "start" -> "Start"
        "end" -> "End"
        "top" -> "Top"
        "bottom" -> "Bottom"
        "center" -> "Middle"
        "nav" -> "In the menu"
        "floating" -> "Floating"
        "dock" -> "In the dock"
        "side" -> "Side"
        else -> p.replaceFirstChar { it.uppercase() }
    }

    fun style(s: String): String = s.replaceFirstChar { it.uppercase() }

    // The form factors an administrator can switch between, as the canvas lists them.
    val formFactors = listOf("tv" to "TV", "desktop" to "Desktop", "tablet" to "Tablet", "phone" to "Phone", "headset" to "Headset")
}

object LayoutEditor {
    private const val MAX_UNDO = 100

    // A position's place in the order arrows step through: along the edge from the start round to the end.
    private fun rank(p: String): Int = when (p) {
        "start", "nav" -> 0
        "top" -> 1
        "center", "dock" -> 2
        "floating", "side" -> 3
        "bottom" -> 4
        "end" -> 5
        else -> 6
    }

    fun ordered(positions: List<String>): List<String> = positions.sortedBy(::rank)

    fun stateOf(placements: Map<String, SduiPlacement>, regions: List<RegionDef>): Map<String, RegionState> =
        regions.associate { r ->
            val p = placements[r.id]
            r.id to RegionState(p?.position.orEmpty(), p?.visible ?: true, p?.style.orEmpty())
        }

    fun start(answer: PlacementsAnswer, page: SduiCustomise?, sectionsEditable: Boolean, navStyle: String = ""): EditorState {
        val doc = LayoutDoc(stateOf(answer.placements, answer.regions), page)
        return EditorState(LayoutCaps(answer.regions, sectionsEditable && page != null, navDefault(navStyle)), doc, focus = items(answer.regions, doc).firstOrNull())
    }

    // Where a menu style sits: a sidebar, rail or side menu at the start, tabs and bars at the top, a phone's tab bar at
    // the foot.
    fun navDefault(style: String): String = when (style) {
        "bottomTabs" -> "bottom"
        "topTabs", "floatingGlassBar", "cableBar", "bevelBar", "teleKeys", "crossbar", "ornamentTabs", "tvTopMenu" -> "top"
        else -> "start"
    }

    // Everything that can be picked up, in the order the page shows it: the regions, then the sections.
    fun items(regions: List<RegionDef>, doc: LayoutDoc): List<ItemRef> =
        regions.map { ItemRef.region(it.id) } + doc.page?.sections?.map { ItemRef.section(it.id) }.orEmpty()

    fun items(s: EditorState): List<ItemRef> = items(s.caps.regions, s.doc)

    fun label(s: EditorState, item: ItemRef): String =
        if (item.section) s.doc.page?.sections?.firstOrNull { it.id == item.id }?.let { it.title.ifEmpty { it.id } } ?: item.id
        else s.caps.region(item.id)?.label?.ifEmpty { item.id } ?: item.id

    fun canMove(s: EditorState, item: ItemRef): Boolean =
        if (item.section) s.caps.sectionsEditable && s.doc.page?.canMove(item.id) == true
        else (s.caps.region(item.id)?.positions?.size ?: 0) > 1

    fun focus(s: EditorState, item: ItemRef?): EditorState = if (s.held != null) s else s.copy(focus = item)

    // MARK: pick up, move, drop, cancel

    fun pickUp(s: EditorState, item: ItemRef? = s.focus): EditorState {
        item ?: return s
        if (s.held != null) return s
        val name = label(s, item)
        if (!canMove(s, item)) {
            val why = when {
                item.section && !s.caps.sectionsEditable -> "$name can't be moved in this view."
                item.section && s.doc.page?.sections?.firstOrNull { it.id == item.id }?.locked == true -> "$name always stays where it is."
                item.section && s.doc.page?.sections?.firstOrNull { it.id == item.id }?.pinned == true -> "$name is pinned to the top. Unpin it to move it."
                item.section -> "$name can't be moved on this page."
                else -> "$name has only one place."
            }
            return s.copy(focus = item, said = why)
        }
        val how = if (item.section) "Arrow up and down move it." else "Arrows move it between its places."
        return s.copy(focus = item, held = item, heldFrom = s.doc, said = "Picked up $name. $how OK drops it. Back puts it back.")
    }

    private fun moved(s: EditorState, doc: LayoutDoc, said: String) = s.copy(doc = doc, said = said)

    fun move(s: EditorState, dir: Dir): EditorState {
        val item = s.held ?: return s
        val name = label(s, item)
        if (item.section) {
            val page = s.doc.page ?: return s
            val by = when (dir) { Dir.Up -> -1; Dir.Down -> 1; else -> 0 }
            if (by == 0) return s.copy(said = "$name moves up and down.")
            val next = page.nudging(item.id, by)
            if (next == page) return s.copy(said = if (by < 0) "$name is already first." else "$name is already last.")
            val order = next.sections
            val at = order.indexOfFirst { it.id == item.id }
            val said = "$name moved ${if (by < 0) "up" else "down"}, now ${at + 1} of ${order.size}" +
                (order.getOrNull(at - 1)?.let { ", after ${it.title.ifEmpty { it.id }}" } ?: ", first")
            return moved(s, s.doc.copy(page = next), said)
        }
        val def = s.caps.region(item.id) ?: return s
        val places = ordered(def.positions)
        val here = places.indexOf(s.doc.regions[item.id]?.position.orEmpty())
        val to = when (dir) { Dir.Left, Dir.Up -> here - 1; else -> here + 1 }
        // A region at no place of its own (the look's default) steps onto its first or last.
        val target = if (here < 0) (if (to < 0 || dir == Dir.Right || dir == Dir.Down) 0 else places.lastIndex) else to
        if (target !in places.indices) return s.copy(said = "$name is already ${LayoutWords.position(places[here.coerceIn(0, places.lastIndex)])}, the last place that way.")
        val next = s.doc.regions[item.id].orDefault().copy(position = places[target])
        return moved(s, s.doc.copy(regions = s.doc.regions + (item.id to next)), "$name now ${LayoutWords.position(places[target])}")
    }

    private fun RegionState?.orDefault() = this ?: RegionState()

    fun drop(s: EditorState): EditorState {
        val item = s.held ?: return s
        val from = s.heldFrom ?: s.doc
        val name = label(s, item)
        val where = if (item.section) {
            val order = s.doc.page?.sections.orEmpty()
            "position ${order.indexOfFirst { it.id == item.id } + 1} of ${order.size}"
        } else LayoutWords.position(s.doc.regions[item.id]?.position.orEmpty())
        val kept = s.copy(held = null, heldFrom = null)
        if (from == s.doc) return kept.copy(said = "Dropped $name where it was.")
        return kept.copy(undo = (s.undo + from).takeLast(MAX_UNDO), redo = emptyList(), said = "Dropped $name, $where.")
    }

    fun cancel(s: EditorState): EditorState {
        val item = s.held ?: return s
        return s.copy(doc = s.heldFrom ?: s.doc, held = null, heldFrom = null, said = "Cancelled. ${label(s, item)} is back where it was.")
    }

    // MARK: a move made in one go: a drag that ended, or a screen reader's "Move up"

    // The item picked up, moved one step and dropped, as one change that can be undone.
    fun quickMove(s: EditorState, item: ItemRef, dir: Dir): EditorState {
        if (s.held != null) return s
        val picked = pickUp(s, item)
        if (picked.held == null) return picked
        val moved = move(picked, dir)
        val said = moved.said
        return drop(moved).copy(said = said)
    }

    // A region carried some places along its own (a drag that ended): positive goes later, negative earlier.
    fun stepRegion(s: EditorState, id: String, by: Int): EditorState {
        if (s.held != null || by == 0) return s
        val def = s.caps.region(id) ?: return s
        val places = ordered(def.positions)
        if (places.size < 2) return s.copy(said = "${def.label} has only one place.")
        val here = places.indexOf(s.doc.regions[id]?.position.orEmpty())
        val to = (if (here < 0) (if (by > 0) by - 1 else places.size + by) else here + by).coerceIn(0, places.lastIndex)
        if (to == here) return s.copy(said = "${def.label} is already ${LayoutWords.position(places[to])}.")
        return setPosition(s, id, places[to])
    }

    // A section dropped onto another (a drag that ended): it takes that one's place.
    fun dropSectionOn(s: EditorState, id: String, targetId: String): EditorState {
        if (s.held != null) return s
        val page = s.doc.page ?: return s
        val name = label(s, ItemRef.section(id))
        if (!s.caps.sectionsEditable || !page.canMove(id)) return s.copy(said = "$name can't be moved here.")
        val from = page.sections.indexOfFirst { it.id == id }
        val to = page.sections.indexOfFirst { it.id == targetId }
        if (from < 0 || to < 0 || from == to) return s
        val next = page.moving(id, if (to > from) to + 1 else to)
        if (next == page) return s.copy(said = "$name can't go there.")
        val at = next.sections.indexOfFirst { it.id == id }
        return commit(s, s.doc.copy(page = next), "$name moved to position ${at + 1} of ${next.sections.size}")
    }

    // MARK: changes that are made at once (the side panel, a screen reader's actions)

    private fun commit(s: EditorState, doc: LayoutDoc, said: String): EditorState {
        if (s.held != null) return s
        if (doc == s.doc) return s.copy(said = said)
        return s.copy(doc = doc, undo = (s.undo + s.doc).takeLast(MAX_UNDO), redo = emptyList(), said = said)
    }

    fun setPosition(s: EditorState, id: String, position: String): EditorState {
        val def = s.caps.region(id) ?: return s
        if (position !in def.positions) return s.copy(said = "${def.label} can't be there.")
        val next = s.doc.regions[id].orDefault().copy(position = position)
        return commit(s, s.doc.copy(regions = s.doc.regions + (id to next)), "${def.label} now ${LayoutWords.position(position)}")
    }

    fun setStyle(s: EditorState, id: String, style: String): EditorState {
        val def = s.caps.region(id) ?: return s
        if (style !in def.styles) return s
        val next = s.doc.regions[id].orDefault().copy(style = style)
        return commit(s, s.doc.copy(regions = s.doc.regions + (id to next)), "${def.label} style ${style}")
    }

    fun setVisible(s: EditorState, item: ItemRef, visible: Boolean): EditorState {
        val name = label(s, item)
        if (item.section) {
            val page = s.doc.page ?: return s
            val section = page.sections.firstOrNull { it.id == item.id } ?: return s
            if (section.locked) return s.copy(said = "$name can't be hidden. It's how you reach what you need.")
            if (!page.canHide || !s.caps.sectionsEditable) return s.copy(said = "$name can't be hidden here.")
            if (section.hidden == !visible) return s.copy(said = "$name is already ${if (visible) "shown" else "hidden"}.")
            return commit(s, s.doc.copy(page = page.togglingHidden(item.id)), if (visible) "$name shown" else "$name hidden")
        }
        val def = s.caps.region(item.id) ?: return s
        if (def.locked && !visible) return s.copy(said = "${def.label} can't be hidden. It's how you reach Settings and You.")
        val cur = s.doc.regions[item.id].orDefault()
        val next = cur.copy(visible = visible)
        return commit(s, s.doc.copy(regions = s.doc.regions + (item.id to next)), if (visible) "${def.label} shown" else "${def.label} hidden")
    }

    fun isVisible(s: EditorState, item: ItemRef): Boolean =
        if (item.section) s.doc.page?.sections?.firstOrNull { it.id == item.id }?.hidden != true else s.doc.regions[item.id]?.visible != false

    fun togglePinned(s: EditorState, id: String): EditorState {
        val page = s.doc.page ?: return s
        val section = page.sections.firstOrNull { it.id == id } ?: return s
        if (!page.canPin || !s.caps.sectionsEditable || section.locked) return s.copy(said = "${section.title.ifEmpty { id }} can't be pinned.")
        val next = page.togglingPinned(id)
        return commit(s, s.doc.copy(page = next), if (section.pinned) "${section.title.ifEmpty { id }} unpinned" else "${section.title.ifEmpty { id }} pinned to the top")
    }

    fun setCardSize(s: EditorState, id: String, size: String): EditorState {
        val page = s.doc.page ?: return s
        if (!s.caps.sectionsEditable) return s
        return commit(s, s.doc.copy(page = page.withCardSize(id, size)), "Card size $size")
    }

    fun setDensity(s: EditorState, density: String): EditorState {
        val page = s.doc.page ?: return s
        if (!s.caps.sectionsEditable) return s
        return commit(s, s.doc.copy(page = page.withDensity(density)), "Spacing $density")
    }

    fun undo(s: EditorState): EditorState {
        if (!s.canUndo) return s
        val to = s.undo.last()
        return s.copy(doc = to, undo = s.undo.dropLast(1), redo = s.redo + s.doc, said = "Undone")
    }

    fun redo(s: EditorState): EditorState {
        if (!s.canRedo) return s
        val to = s.redo.last()
        return s.copy(doc = to, redo = s.redo.dropLast(1), undo = s.undo + s.doc, said = "Redone")
    }

    // The editor after a save: what is held now is what was saved.
    fun saved(s: EditorState, said: String = "Saved"): EditorState = s.copy(saved = s.doc, said = said)

    // MARK: what is sent

    // The regions that changed from what was in force when the editor opened, laid over `layer` (the placements that
    // scope already had: the profile's own, or the administrator's for this experience). A locked region is never
    // sent hidden.
    fun placementsPatch(base: Map<String, SduiPlacement>, layer: Map<String, SduiPlacement>, s: EditorState): Map<String, SduiPlacement> {
        val out = LinkedHashMap<String, SduiPlacement>(layer)
        for (def in s.caps.regions) {
            val cur = s.doc.regions[def.id] ?: continue
            val was = base[def.id]
            val wasPosition = was?.position.orEmpty()
            val wasVisible = was?.visible ?: true
            val wasStyle = was?.style.orEmpty()
            val old = out[def.id] ?: SduiPlacement()
            val position = if (cur.position != wasPosition && cur.position.isNotEmpty()) cur.position else old.position
            val visible = if (cur.visible != wasVisible && !(def.locked && !cur.visible)) cur.visible else old.visible
            val style = if (cur.style != wasStyle && cur.style.isNotEmpty()) cur.style else old.style
            val next = SduiPlacement(position, visible, style)
            if (next == SduiPlacement()) out.remove(def.id) else out[def.id] = next
        }
        return out
    }

    fun placementJson(p: Map<String, SduiPlacement>): JsonObject = buildJsonObject {
        for ((id, pl) in p) put(id, placementObject(pl))
    }

    private fun placementObject(pl: SduiPlacement): JsonObject = buildJsonObject {
        if (pl.position.isNotEmpty()) put("position", pl.position)
        pl.visible?.let { put("visible", it) }
        if (pl.style.isNotEmpty()) put("style", pl.style)
    }

    // The body of PUT /sdui/placements.
    fun ownBody(p: Map<String, SduiPlacement>): String = buildJsonObject { put("placements", placementJson(p)) }.toString()

    // MARK: the administrator's placements, inside the experience policy (GET/PUT /sdui/config/experience)

    // The layer the administrator already has for one experience.
    fun layerOf(policy: JsonObject, experience: String): Map<String, SduiPlacement> {
        val layer = runCatching { policy["placements"]?.jsonObject?.get(experience)?.jsonObject }.getOrNull() ?: return emptyMap()
        return layer.mapNotNull { (region, v) ->
            val o = runCatching { v.jsonObject }.getOrNull() ?: return@mapNotNull null
            region to SduiPlacement(
                o["position"]?.jsonPrimitive?.contentOrNull.orEmpty(), o["visible"]?.jsonPrimitive?.booleanOrNull, o["style"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            )
        }.toMap()
    }

    // The policy with one experience's layer replaced (null or empty: removed), every other part as it was read, so
    // the strict PUT loses nothing.
    fun policyWith(policy: JsonObject, experience: String, layer: Map<String, SduiPlacement>?): JsonObject {
        val all = LinkedHashMap<String, kotlinx.serialization.json.JsonElement>()
        runCatching { policy["placements"]?.jsonObject }.getOrNull()?.forEach { (k, v) -> all[k] = v }
        if (layer.isNullOrEmpty()) all.remove(experience) else all[experience] = placementJson(layer)
        val rest = LinkedHashMap<String, kotlinx.serialization.json.JsonElement>(policy)
        if (all.isEmpty()) rest.remove("placements") else rest["placements"] = JsonObject(all)
        return JsonObject(rest)
    }

    // Reset everything for everyone: every experience's layer goes.
    fun policyWithoutPlacements(policy: JsonObject): JsonObject = JsonObject(policy.filterKeys { it != "placements" })

    // MARK: where regions are drawn on the editor's page

    data class Zones(
        val top: List<String>,
        val left: List<String>,
        val right: List<String>,
        val bottom: List<String>,
        // In the body above the sections: a floating search, the spotlight.
        val body: List<String>,
        val hidden: List<String>,
    )

    // The page the editor draws: which region sits at the top, at the sides, at the foot, over the page, or is hidden.
    fun zones(regions: List<RegionDef>, doc: LayoutDoc, navDefault: String = "start"): Zones {
        val ids = regions.map { it.id }
        fun st(id: String) = doc.regions[id].orDefault()
        val navAt = st("nav").position.ifEmpty { navDefault }
        val top = ArrayList<String>()
        val left = ArrayList<String>()
        val right = ArrayList<String>()
        val bottom = ArrayList<String>()
        val body = ArrayList<String>()
        val hidden = ArrayList<String>()
        val navZone = when (navAt) {
            "top" -> top
            "bottom" -> bottom
            "end" -> right
            else -> left
        }
        for (id in ids) {
            if (!st(id).visible) { hidden += id; continue }
            val p = st(id).position
            val zone: MutableList<String> = when (id) {
                "nav" -> navZone
                "brand" -> if (p == "top" || p == "center") top else if (navAt == "top" || navAt == "bottom") top else navZone
                "search" -> when (p) { "top" -> top; "floating" -> body; else -> navZone }
                "profile" -> if (p == "top") top else navZone
                "clock" -> if (p == "dock" && "dock" in ids && st("dock").visible) dockZone(st("dock").position, top, bottom, right) else top
                "dock" -> dockZone(p, top, bottom, right)
                "legend" -> bottom
                "hero" -> body
                else -> body
            }
            zone += id
        }
        return Zones(top, left, right, bottom, body, hidden)
    }

    private fun dockZone(position: String, top: MutableList<String>, bottom: MutableList<String>, right: MutableList<String>) =
        when (position) { "top" -> top; "side" -> right; else -> bottom }

    // Hidden sections go in the same tray as hidden regions.
    fun hiddenSections(doc: LayoutDoc): List<String> = doc.page?.sections?.filter { it.hidden }?.map { it.id }.orEmpty()
}
