// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * A Design 2 page as data (the design canvas's `gp` pages, docs/design-2/canvas/Exp.dc.html: `mk`, `secR`, `secP`,
 * `secN`, `secC`, `R`, `Cc`, `A1`, `A2`): a small eyebrow, a big title, a lead line, sections of rows, chips, a note or
 * cards, the actions and a foot line. The app draws it with `DesignSpecPage` (ui/DesignPage.kt); the same spec reads the
 * same on a TV, a tablet and a phone (one column there). The twin of Apple's WittyKit `DesignPageSpec`: the builders
 * have the canvas's names, so a page is copied across as it is drawn:
 * `DesignPageSpec.mk("Welcome", "Choose your server", "…", listOf(secR("Saved", listOf(R("Home", "Last used", true)))))`.
 *
 * Every row, chip, card and action has an `id` (its title in lower case with dashes, unless given) that a press reports,
 * and that a UI test finds as `design.<id>`. Focus goes through them top to bottom, starting at `start`.
 */
@Serializable
data class DesignPageSpec(
    val eyebrow: String = "",
    val title: String = "",
    val lead: String = "",
    val sections: List<Section> = emptyList(),
    val actions: List<Action> = emptyList(),
    val foot: String = "",
    /** Shown over another screen (a sheet, a dialog): Back closes it. Otherwise it is the Stage, and Back goes to the Bar. */
    val layer: Boolean = false,
    /** Where focus starts: an item's id. Empty is the first thing that can take focus, top to bottom. */
    val start: String = "",
) {
    @Serializable
    enum class Kind { rows, chips, note, cards }

    @Serializable
    data class Section(
        val heading: String = "",
        val kind: Kind,
        val rows: List<Row> = emptyList(),
        val chips: List<Chip> = emptyList(),
        val cards: List<Card> = emptyList(),
        val note: String = "",
        val tone: Boolean = false,
        /** Cards across; null is the device's own (two on a phone, three on a tablet, four on a TV). */
        val columns: Int? = null,
    )

    /** `R(title, value, on, detail)`: a title in bold, a detail line under it, a value on the right (the accent when on). */
    @Serializable
    data class Row(
        val title: String,
        val value: String = "",
        val on: Boolean = false,
        val detail: String = "",
        /** Whether pressing it does something; a row that only says something isn't a stop for focus. */
        val pressable: Boolean = true,
        @SerialName("id") private val idGiven: String = "",
    ) {
        val id: String get() = idGiven.ifEmpty { slug(title) }
    }

    /** `Cc(title, on)`: a chip, filled when on. */
    @Serializable
    data class Chip(val title: String, val on: Boolean = false, @SerialName("id") private val idGiven: String = "") {
        val id: String get() = idGiven.ifEmpty { slug(title) }
    }

    /** A card in `secC`: a title, a line under it and optionally three swatches (`#rrggbb`), ringed when chosen. */
    @Serializable
    data class Card(
        val title: String,
        val subtitle: String = "",
        val on: Boolean = false,
        val swatches: List<String> = emptyList(),
        @SerialName("id") private val idGiven: String = "",
    ) {
        val id: String get() = idGiven.ifEmpty { slug(title) }
    }

    /** `A1` (the primary action) or `A2` (a secondary one). */
    @Serializable
    data class Action(val title: String, val primary: Boolean = false, @SerialName("id") private val idGiven: String = "") {
        val id: String get() = idGiven.ifEmpty { slug(title) }
    }

    /** Everything that can take focus, top to bottom: rows that do something, chips, cards, then the actions. */
    val focusOrder: List<String>
        get() = sections.flatMap { s ->
            when (s.kind) {
                Kind.rows -> s.rows.filter { it.pressable }.map { it.id }
                Kind.chips -> s.chips.map { it.id }
                Kind.cards -> s.cards.map { it.id }
                Kind.note -> emptyList()
            }
        } + actions.map { it.id }

    /** Where focus starts: `start` when it names something that can take focus, else the first such thing. */
    val startFocus: String? get() = focusOrder.let { o -> if (start in o) start else o.firstOrNull() }

    /** What Back does on this page, by the Back ladder: a layer closes; the Stage hands focus to the Bar. */
    val back: BackStep get() = BackLadder.next(BackState(layerOpen = layer, zone = if (layer) Zone.Layer else Zone.Stage, barOnHome = false))

    companion object {
        fun mk(eyebrow: String, title: String, lead: String, sections: List<Section>, actions: List<Action> = emptyList(), foot: String = "") =
            DesignPageSpec(eyebrow, title, lead, sections, actions, foot)

        /** Cards across on this device: the section's own, at most two on a phone; else two, three or four. */
        fun columns(section: Section, phone: Boolean, tablet: Boolean): Int {
            val device = if (phone) 2 else if (tablet) 3 else 4
            val asked = section.columns ?: return device
            if (asked <= 0) return device
            return if (phone) minOf(asked, 2) else asked
        }

        /** A title as an id: lower case, ASCII letters and digits, dashes between words. */
        fun slug(title: String): String {
            val out = StringBuilder()
            var dash = false
            for (c in title.lowercase()) {
                if (c.isLetterOrDigit() && c.code < 128) {
                    if (dash && out.isNotEmpty()) out.append('-')
                    out.append(c)
                    dash = false
                } else dash = true
            }
            return out.toString().ifEmpty { "item" }
        }
    }
}

// The canvas's builders, in its spelling, so a `gp` line reads the same here.
fun secR(heading: String, rows: List<DesignPageSpec.Row>) = DesignPageSpec.Section(heading, DesignPageSpec.Kind.rows, rows = rows)
fun secP(heading: String, chips: List<DesignPageSpec.Chip>) = DesignPageSpec.Section(heading, DesignPageSpec.Kind.chips, chips = chips)
fun secN(heading: String, text: String, tone: Boolean = false) = DesignPageSpec.Section(heading, DesignPageSpec.Kind.note, note = text, tone = tone)
fun secC(heading: String, cards: List<DesignPageSpec.Card>, columns: Int? = null) = DesignPageSpec.Section(heading, DesignPageSpec.Kind.cards, cards = cards, columns = columns)

@Suppress("FunctionName")
fun R(title: String, value: String = "", on: Boolean = false, detail: String = "", pressable: Boolean = true, id: String = "") =
    DesignPageSpec.Row(title, value, on, detail, pressable, id)

@Suppress("FunctionName")
fun Cc(title: String, on: Boolean = false, id: String = "") = DesignPageSpec.Chip(title, on, id)

@Suppress("FunctionName")
fun A1(title: String, id: String = "") = DesignPageSpec.Action(title, primary = true, idGiven = id)

@Suppress("FunctionName")
fun A2(title: String, id: String = "") = DesignPageSpec.Action(title, primary = false, idGiven = id)
