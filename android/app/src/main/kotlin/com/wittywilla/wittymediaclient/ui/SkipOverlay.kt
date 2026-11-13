// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import com.wittywilla.wittymediaclient.net.ExtrasFeature
import com.wittywilla.wittymediaclient.net.Intro
import com.wittywilla.wittymediaclient.net.SkipRange
import com.wittywilla.wittymediaclient.player.SkipTracker
import com.wittywilla.wittymediaclient.player.VideoSession
import kotlinx.coroutines.delay

// The Skip button's two looks, one for each player, and the TV player's tracker. What's on now and where the button
// goes come from SkipTracker; the players keep their own layout, focus and seeking.

// The TV player's tracker, running for as long as its screen is up. `said` holds what was just skipped by itself.
class TvSkipping(val tracker: SkipTracker) {
    var said by mutableStateOf("")
        internal set
    val now get() = tracker.now
    val label: String get() = tracker.now?.label ?: "Skip intro"

    // Should "next episode" be up already? True from where credits that run to the end begin.
    fun upNextDue(filmSec: Double): Boolean = tracker.upNextFromSec?.let { filmSec >= it } == true
}

@Composable
fun rememberTvSkipping(
    nav: Nav,
    id: Long,
    intro: () -> Intro?,
    filmSec: () -> Double,
    durationSec: () -> Double,
    live: () -> Boolean,
    nextId: () -> Long?,
    seek: (Double) -> Unit,
): TvSkipping {
    val skipping = remember(id) { TvSkipping(SkipTracker()) }
    val seekNow by rememberUpdatedState(seek)
    LaunchedEffect(skipping) {
        skipping.tracker.run(
            nav.app, id,
            hasMarkers = { nav.has(ExtrasFeature.MARKERS) },
            fallbackIntro = { intro()?.let { SkipRange(it.startSec, it.endSec) } },
            filmSec = filmSec, durationSec = durationSec, live = live, nextId = nextId,
            seek = { seekNow(it) }, playNext = nav::playInstead, said = { skipping.said = it },
        )
    }
    LaunchedEffect(skipping.said) {
        if (skipping.said.isNotEmpty()) {
            delay(SAID_MS)
            skipping.said = ""
        }
    }
    return skipping
}

// "Skipped the intro.", over the picture for a few seconds and read out by a screen reader. Nothing to focus. Its own
// scrim, as everything over a film has, so it reads on any picture.
@Composable
fun TvSkipNotice(skipping: TvSkipping, modifier: Modifier = Modifier) {
    val words = skipping.said
    if (words.isEmpty()) return
    DesignSized {
        val s = LocalDesignSizes.current
        Box(
            modifier.safeDrawingPadding().padding(LocalMetrics.current.gutter).background(SCRIM, Radius.FULL)
                .padding(horizontal = s.gap * 1.4f, vertical = s.gap * 0.8f).semantics { liveRegion = LiveRegionMode.Polite },
        ) { Text(words, color = Color.White, fontSize = s.small, fontWeight = FontWeight.Bold) }
    }
}

// The phone's and tablet's button: Design 2's chosen chip over the picture ("Skip intro ›"), for as long as the
// stretch is on. It takes focus when it appears (docs/plans/DESIGN-2.md, Player), and a screen reader hears it arrive.
@Composable
fun PhoneSkipButton(session: VideoSession, modifier: Modifier = Modifier) {
    val skip = session.skipping.now ?: return
    if (session.problem.isNotEmpty()) return
    DesignSized {
        DesignChip(
            "${skip.label} ›", { session.skipping.pressed(); session.seekFilm(skip.toSec) },
            modifier.semantics { liveRegion = LiveRegionMode.Polite }, on = true, label = skip.label, takeFocus = true, focusKey = "skip",
        )
    }
}

// What's over the picture is dark whatever the theme: the film is.
private val SCRIM = Color(0xCC000000)

private const val SAID_MS = 4_000L
