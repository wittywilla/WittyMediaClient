// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.wittywilla.wittymediaclient.net.CanvasInfo
import com.wittywilla.wittymediaclient.net.ExtrasFeature
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.canvas
import com.wittywilla.wittymediaclient.net.detectIntros
import com.wittywilla.wittymediaclient.net.generateCanvas

// What an administrator can have the server make from a title's own page: a canvas cut from a film or an episode, and
// a show's intros and credits found by comparing its episodes by ear. On a phone or tablet they are rows in the
// page's "⋯", beside Artwork, Edit and Refresh; a TV's pages have no such menu, so they are buttons after Play. Both
// show the job's card on the page (ExtrasJobs.kt). Nobody else sees any of it, and nor does anyone on a server that
// doesn't name the feature.

// A film's or an episode's page.
class ItemExtras internal constructor(private val nav: Nav, private val itemId: Long, val job: ExtrasJob) {
    // Bumped when a canvas has been made, so the page asks for it afresh.
    var canvasAgain by mutableIntStateOf(0)
        private set
    var canvas by mutableStateOf<CanvasInfo?>(null)
        internal set

    private val admin: Boolean get() = nav.me?.isAdmin == true

    // Only where the server says it can: a video file, with an FFmpeg that can encode one.
    val canMakeCanvas: Boolean get() = admin && nav.has(ExtrasFeature.CANVAS_GENERATE) && canvas?.canGenerate == true && !job.busy
    val canvasWords: String get() = if (canvas?.available == true) "Make a new canvas" else "Make a canvas"

    fun makeCanvas() {
        job.start("Making a canvas", { it.generateCanvas(itemId) }, settled = { api -> api.canvas(itemId).task.isEmpty() }) { ok ->
            if (ok) {
                forgetCanvas(nav, itemId)
                canvasAgain++
            }
        }
    }

    // The rows to add to the page's "⋯".
    fun sheetRows(): List<SheetRow> = if (canMakeCanvas) listOf(SheetRow(canvasWords, WebIcons.Image) { makeCanvas() }) else emptyList()
}

@Composable
fun rememberItemExtras(nav: Nav, itemId: Long): ItemExtras {
    val job = rememberExtrasJob(nav)
    val extras = remember(itemId, job) { ItemExtras(nav, itemId, job) }
    val asks = nav.me?.isAdmin == true && nav.has(ExtrasFeature.CANVAS_GENERATE)
    // Whether one can be made is the server's to say, and only an administrator's page asks.
    LaunchedEffect(itemId, asks, extras.canvasAgain) {
        extras.canvas = if (asks) runCatching { nav.app.api.canvas(itemId) }.getOrNull() else null
    }
    return extras
}

// A show's page.
class ShowExtras internal constructor(private val nav: Nav, private val showId: Long, val job: ExtrasJob, private val found: () -> Unit) {
    val canFindIntros: Boolean get() = nav.me?.isAdmin == true && nav.has(ExtrasFeature.INTRO_DETECTION) && !job.busy

    fun findIntros() {
        job.start("Finding intros and credits", { it.detectIntros(showId) }) { ok -> if (ok) found() }
    }

    fun sheetRows(): List<SheetRow> = if (canFindIntros) listOf(SheetRow("Find intros and credits", WebIcons.Refresh) { findIntros() }) else emptyList()
}

// `found` is called when a search has finished, for the page to read the show again.
@Composable
fun rememberShowExtras(nav: Nav, showId: Long, found: () -> Unit): ShowExtras {
    val job = rememberExtrasJob(nav)
    return remember(showId, job) { ShowExtras(nav, showId, job, found) }
}

// On a TV's page for a film or an episode: the administrator's button and its card, then where to watch.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TvItemExtras(nav: Nav, item: Item, extras: ItemExtras) {
    Column(verticalArrangement = Arrangement.spacedBy(Space.S3)) {
        if (extras.canMakeCanvas) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.S2), verticalArrangement = Arrangement.spacedBy(Space.S2)) {
                ActionButton(extras.canvasWords, extras::makeCanvas, pill = true, focusKey = "make-canvas")
            }
        }
        ExtrasJobCard(extras.job)
        WhereToWatchSection(nav, item.id)
    }
}

// On a TV's page for a show. `episodeId` is one of its episodes, which is how the server is asked about the show.
@Composable
fun TvShowExtras(nav: Nav, episodeId: Long, extras: ShowExtras) {
    Column(verticalArrangement = Arrangement.spacedBy(Space.S3)) {
        if (extras.canFindIntros) ActionButton("Find intros and credits", extras::findIntros, pill = true, focusKey = "find-intros")
        ExtrasJobCard(extras.job)
        WhereToWatchSection(nav, episodeId)
    }
}
