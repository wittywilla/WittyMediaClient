// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlin.math.floor
import kotlin.math.roundToInt

// A TV's shelf shows a peek of the next card (docs/plans/DESIGN-2.md, section 2, `tv.shelf.peek`: 0.18 of it), so the
// row plainly goes on. The page's layout gives the card's width; this nudges it, by at most a fifth, so that whole cards
// and the peek fill the room from the shelf's start to the screen's edge.
object ShelfRules {
    private const val MOST = 0.2f

    // `visible` is the room from where the first card starts to the screen's edge, `gap` between cards, `width` the layout's
    // card width, `peek` the fraction of the next card to show and `count` the cards the shelf has. All in one unit.
    // A shelf with no more cards than fit needs no peek and keeps its width.
    fun cardWidth(visible: Float, gap: Float, width: Float, peek: Float, count: Int): Float {
        if (width <= 0f || visible <= 0f || peek <= 0f) return width
        val whole = floor((visible + gap) / (width + gap)).toInt().coerceAtLeast(1)
        if (count <= whole) return width
        // The nearest whole number of cards to what the width gives, with the peek after them.
        val k = ((visible - peek * width) / (width + gap)).roundToInt().coerceAtLeast(1)
        val fitted = (visible - k * gap) / (k + peek)
        return if (fitted in width * (1 - MOST)..width * (1 + MOST)) fitted else width
    }
}
