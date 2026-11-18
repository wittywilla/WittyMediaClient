// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.wittywilla.wittymediaclient.net.ThemeTranslator

// Words over a picture, as the server draws them (its docs/UI-PLATFORMS.md; PR 444): a scrim in the page's own colour,
// at least the theme's `heroScrim` where the words are, fading out past them. A light theme gets a light scrim under dark
// words and a dark one under light words, so they read over any picture. The picture itself still fades into the page at
// its foot, so it never stops on a line (PR 411). Every hero and title header draws its shade from here.
object HeroScrim {
    // The theme in force's strength, 0 to 1.
    val strength: Float
        @Composable @ReadOnlyComposable
        get() = (LocalAppTheme.current?.heroScrim ?: ThemeTranslator.DEFAULT_HERO_SCRIM).toFloat()

    // Words at the foot, starting `wordsFrom` of the way down: clear at the top, the scrim from where the words begin,
    // and the page itself at the bottom edge. With the default theme's old 0.72 this is the shade the phone always had.
    fun foot(page: Color, strength: Float, wordsFrom: Float = 0.44f): Brush = Brush.verticalGradient(
        (wordsFrom - 0.26f).coerceAtLeast(0f) to page.copy(alpha = 0f),
        wordsFrom to page.copy(alpha = strength),
        (wordsFrom + 0.22f).coerceAtMost(0.99f) to page.copy(alpha = maxOf(strength, 0.94f)),
        1f to page,
    )

    // Words at the left, across `wordsTo` of the width: solid at the edge, the scrim across the words, clear beyond.
    // `least` keeps a shade that was already darker than the theme asks for as it was.
    fun side(page: Color, strength: Float, wordsTo: Float = 0.35f, clearAt: Float = 0.75f, least: Float = 0f, beyond: Float = 0f): Brush =
        Brush.horizontalGradient(
            0f to page,
            wordsTo to page.copy(alpha = maxOf(strength, least)),
            clearAt to page.copy(alpha = beyond),
        )
}
