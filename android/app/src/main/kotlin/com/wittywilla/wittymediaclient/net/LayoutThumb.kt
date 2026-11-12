// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable

// What a look's layout wireframe draws: the experience's `wire` for this form factor (GET /sdui/experiences; docs/SDUI.md,
// "Experiences": the layout a chooser draws). Nothing here is picked by an experience's id.
@Serializable
data class SduiWire(
    // top, side, rail, bottom, none
    val nav: String = "top",
    // pill, gloss, under, cable, bevel, tele, crossbar
    val style: String = "pill",
    // hero, banner, carousel, cross, tiles, widgets, list
    val home: String = "hero",
    // poster, landscape, plate, block, logo
    val cards: String = "poster",
    val dock: Boolean = false,
    // left, top, centre
    val brand: String = "left",
    // flat, gloss, bevel, glass, crt
    val finish: String = "flat",
    val open: Boolean = false,
)

object Wire {
    // The wire for a form factor, else the nearest the server sent (desktop), else the plain look.
    fun of(wires: Map<String, SduiWire>, formFactor: String): SduiWire = wires[formFactor] ?: wires["desktop"] ?: wires.values.firstOrNull() ?: SduiWire()

    // The menu's places as a wireframe draws them.
    fun glass(w: SduiWire) = w.finish == "glass" || w.finish == "gloss"
}
