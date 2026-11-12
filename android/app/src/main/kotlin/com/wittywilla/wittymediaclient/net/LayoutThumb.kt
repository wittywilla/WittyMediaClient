// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// What a look's layout preview draws (docs/design-2 canvas, Exp.dc.html `wireFor`/`wireSpec`): where the menu is and how it is
// styled, how Home is arranged, the shape of the cards and whether there is a dock. The server's `preview` descriptor on
// GET /sdui/experiences ({nav, home, cards, dock, brand, finish}) is read when it has one; until it does, a small table
// by the experience's id stands in, kept to what the shipped experiences are.
data class ThumbSpec(
    // top, bottom, rail, sidebar, side (a TV's side menu), crossbar, none
    val nav: String = "top",
    // billboard, banner, carousel, rows, widgets, list
    val home: String = "billboard",
    // poster, wide, square, plate, block
    val cards: String = "poster",
    val dock: Boolean = false,
    val glass: Boolean = false,
    val serif: Boolean = false,
)

object ThumbSpecs {
    private val BY_ID = mapOf(
        "lumen" to ThumbSpec("top", "billboard", "poster"),
        "rail" to ThumbSpec("rail", "banner", "plate"),
        "stage" to ThumbSpec("top", "billboard", "wide"),
        "aero" to ThumbSpec("top", "billboard", "poster", glass = true),
        "aeronight" to ThumbSpec("top", "billboard", "poster", glass = true),
        "aeromeadow" to ThumbSpec("top", "billboard", "poster", glass = true),
        "aerosunset" to ThumbSpec("top", "billboard", "poster", glass = true),
        "classic" to ThumbSpec("sidebar", "rows", "poster"),
        "classiccable" to ThumbSpec("top", "list", "block"),
        "classicsatellite" to ThumbSpec("top", "list", "block"),
        "compact" to ThumbSpec("rail", "list", "square"),
        "paper" to ThumbSpec("top", "banner", "poster", serif = true),
        "marquee" to ThumbSpec("top", "carousel", "poster"),
        "crossbar" to ThumbSpec("crossbar", "rows", "square"),
        "bigpicture" to ThumbSpec("top", "rows", "wide"),
        "dashboard" to ThumbSpec("top", "widgets", "wide"),
        "retro" to ThumbSpec("top", "list", "block"),
    )

    fun forId(id: String): ThumbSpec = BY_ID[id.lowercase().replace("-", "").replace("_", "")] ?: ThumbSpec()

    // A descriptor from the server: {nav, home, cards, dock, brand, finish}; whatever is missing is the table's value.
    fun from(id: String, nav: String?, home: String?, cards: String?, dock: Boolean?, finish: String?): ThumbSpec {
        val base = forId(id)
        return base.copy(
            nav = nav?.takeIf { it.isNotEmpty() } ?: base.nav, home = home?.takeIf { it.isNotEmpty() } ?: base.home,
            cards = cards?.takeIf { it.isNotEmpty() } ?: base.cards, dock = dock ?: base.dock, glass = finish?.let { it == "glass" || it == "gloss" } ?: base.glass,
        )
    }

    // The menu styles (navStyles) as the thumbnail's nav places.
    fun navPlace(style: String): String = when (style) {
        "sidebar" -> "sidebar"
        "rail", "railDrawer" -> "rail"
        "bottomTabs" -> "bottom"
        "tvSideMenu" -> "side"
        "crossbar" -> "crossbar"
        else -> "top"
    }
}
