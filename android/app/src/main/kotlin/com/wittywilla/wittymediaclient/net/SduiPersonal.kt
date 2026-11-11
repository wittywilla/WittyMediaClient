// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// "Customise" (docs/SDUI.md, Personalisation): what one profile changes about one page for itself. The page says
// what may be changed (`document.personal`), the screen shows that list, and what comes of it is PUT back whole.
// Apart from the screen, so the rules are tested without one.

// A tab strip on the page, for choosing the tab it opens on.
data class SduiTabChoice(val tabs: String, val options: List<Pair<String, String>>, val selected: String)

// A section whose cards have a size to choose.
data class SduiSizeChoice(val section: String, val size: String)

data class SduiCustomise(
    // The page's top-level sections in the profile's order, hidden ones too.
    val sections: List<SduiPersonalSection>,
    val allow: Set<String>,
    val density: String = "",
    val cardSize: Map<String, String> = emptyMap(),
    val defaultTab: Map<String, String> = emptyMap(),
) {
    val canReorder: Boolean get() = "reorder" in allow
    val canHide: Boolean get() = "hide" in allow
    val canPin: Boolean get() = "pin" in allow
    val canDensity: Boolean get() = "density" in allow
    val canCardSize: Boolean get() = "cardSize" in allow
    val canDefaultTab: Boolean get() = "defaultTab" in allow

    // A locked section is never hidden and never moves.
    fun canMove(id: String): Boolean = canReorder && sections.firstOrNull { it.id == id }?.let { !it.locked && !it.pinned } == true

    // The sections that move, put back in the places locked ones leave free, pinned ones first as the server has them.
    private fun refilled(free: List<SduiPersonalSection>): SduiCustomise {
        val order = (free.filter { it.pinned } + free.filter { !it.pinned }).iterator()
        return copy(sections = sections.map { if (it.locked) it else order.next() })
    }

    // A section moved to a place among them all. Locked sections keep their places: the others move round them.
    fun moving(id: String, place: Int): SduiCustomise {
        if (!canMove(id)) return this
        val free = sections.filter { !it.locked }
        val moved = free.filter { it.id != id }.toMutableList()
        // The place is among every section; among the ones that move, it is how many of them come before it.
        val before = sections.take(place.coerceIn(0, sections.size)).count { !it.locked && it.id != id }
        moved.add(before.coerceIn(0, moved.size), free.first { it.id == id })
        return refilled(moved)
    }

    // Some places up or down among the sections that move, for a remote or the arrow buttons.
    fun nudging(id: String, by: Int): SduiCustomise {
        if (!canMove(id)) return this
        val free = sections.filter { !it.locked }.toMutableList()
        val at = free.indexOfFirst { it.id == id }
        val to = (at + by).coerceIn(free.count { it.pinned }, free.lastIndex)
        if (to == at) return this
        free.add(to, free.removeAt(at))
        return refilled(free)
    }

    fun togglingHidden(id: String): SduiCustomise =
        if (!canHide) this else copy(sections = sections.map { if (it.id == id && !it.locked) it.copy(hidden = !it.hidden) else it })

    // Pinned sections come first, in the order they were pinned: a newly pinned one goes after the others, and one
    // let go again leads the rest.
    fun togglingPinned(id: String): SduiCustomise {
        if (!canPin) return this
        val section = sections.firstOrNull { it.id == id && !it.locked } ?: return this
        val free = sections.filter { !it.locked && it.id != id }
        val pinned = free.count { it.pinned }
        return refilled(free.take(pinned) + section.copy(pinned = !section.pinned) + free.drop(pinned))
    }

    fun withDensity(value: String): SduiCustomise = if (!canDensity || value !in DENSITIES) this else copy(density = value)

    fun withCardSize(section: String, size: String): SduiCustomise = when {
        !canCardSize -> this
        size.isEmpty() -> copy(cardSize = cardSize - section)
        size in SIZES -> copy(cardSize = cardSize + (section to size))
        else -> this
    }

    fun withDefaultTab(tabs: String, tab: String): SduiCustomise =
        if (!canDefaultTab) this else copy(defaultTab = if (tab.isEmpty()) defaultTab - tabs else defaultTab + (tabs to tab))

    // What is sent: only what the page allows, and nothing a locked section can't have.
    fun toPersonal(): SduiPersonal = SduiPersonal(
        order = if (canReorder) sections.filter { !it.pinned }.map { it.id } else emptyList(),
        hidden = if (canHide) sections.filter { it.hidden && !it.locked }.map { it.id } else emptyList(),
        pinned = if (canPin) sections.filter { it.pinned && !it.locked }.map { it.id } else emptyList(),
        density = if (canDensity) density else "",
        cardSize = if (canCardSize) cardSize else emptyMap(),
        defaultTab = if (canDefaultTab) defaultTab else emptyMap(),
    )

    companion object {
        val DENSITIES = listOf("compact", "comfortable", "spacious")
        val SIZES = listOf("s", "m", "l")

        // What the page offers, with what the profile had already chosen for the things the page doesn't list
        // (card sizes, the tab it opens on).
        fun from(info: SduiPersonalInfo, saved: SduiPersonal = SduiPersonal()): SduiCustomise = SduiCustomise(
            sections = info.sections,
            allow = if (info.editable) info.allow.toSet() else emptySet(),
            density = info.density.ifEmpty { saved.density },
            cardSize = saved.cardSize,
            defaultTab = saved.defaultTab,
        )

        // The tab strips on a page, for "Opens on".
        fun tabChoices(root: SduiNode, saved: Map<String, String>): List<SduiTabChoice> {
            val out = ArrayList<SduiTabChoice>()
            fun walk(node: SduiNode) {
                if (node.type == "Tabs") {
                    val options = node.children.filter { it.type == "Tab" }.map { it.id to it.props.str("label") }
                    if (options.size > 1) out += SduiTabChoice(node.id, options, saved[node.id].orEmpty())
                }
                node.children.forEach(::walk)
            }
            walk(root)
            return out
        }

        // The page's rows and grids that say how big their cards are, with the size each has now.
        fun sizeChoices(root: SduiNode): List<Pair<SduiNode, String>> =
            root.children.filter { (it.type == "Shelf" || it.type == "Grid") && it.props.str("cardSize").isNotEmpty() }.map { it to it.props.str("cardSize") }
    }
}
