// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import com.wittywilla.wittymediaclient.net.DiscAnalysis
import com.wittywilla.wittymediaclient.net.DiscWords
import com.wittywilla.wittymediaclient.net.chooseDiscTitle
import com.wittywilla.wittymediaclient.net.discAnalysis
import com.wittywilla.wittymediaclient.net.forgetDiscChoice
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.rankDiscAgain
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// "Why this title" on a disc's page (phone and tablet; a TV shows the server's own disc page, which has the same):
// what Play plays and why, how sure the engine is, a TV disc's episodes and the film's other versions to play, and for
// an administrator another title to make the film, or the engine's pick back. Sections of the item's page in Design 2's
// parts (DesignPage.kt): rows for what can be played or chosen, chips for the choices.
@Composable
fun DiscWhySection(nav: Nav, kind: String, itemId: Long, playable: Boolean, modifier: Modifier = Modifier) {
    if (!nav.has("disc-ranking")) return
    val scope = rememberCoroutineScope()
    var analysis by remember { mutableStateOf<DiscAnalysis?>(null) }
    var said by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var ask by remember { mutableIntStateOf(0) }
    LaunchedEffect(itemId, ask) {
        // A small server works it out in the background: asked again until it has.
        repeat(PENDING_TRIES) {
            val got = runCatching { nav.app.api.discAnalysis(kind, itemId) }.getOrNull() ?: return@LaunchedEffect
            analysis = got
            if (!got.pending) return@LaunchedEffect
            delay(PENDING_WAIT_MS)
        }
    }
    val a = analysis ?: return
    if (a.pending) return
    fun run(done: String, call: suspend () -> DiscAnalysis) {
        if (busy) return
        busy = true
        scope.launch {
            try {
                analysis = call()
                said = done
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                said = problemWords(e, "Can't reach the server.")
            }
            busy = false
        }
    }
    val rank = a.rank
    val unit = DiscWords.unit(a.kind)
    DesignSized {
        DesignSection("Why this ${unit.lowercase()}", modifier) {
            if (rank != null && a.ranked && a.chosen == null) {
                DesignRow(DiscWords.level(rank.level, rank.confidence), value = DiscWords.sure(rank.confidence), on = true)
            }
            DesignNote(DiscWords.headline(a))
            if (rank != null) {
                val lines = rank.reasons.map { "For it: $it" } + rank.against.map { "Against it: $it" } + rank.warnings + rank.repairs +
                    rank.issues.map { (if (it.severity == "error") "Won't play: " else "") + it.what + if (it.ttn >= 0) " (${DiscWords.name(a.kind, it.ttn)})" else "" } +
                    (if (rank.paddedSectors > 0) listOf("${rank.paddedSectors} unreadable sectors were passed over as blank while reading the disc's index.") else emptyList())
                lines.take(MOST_LINES).forEach { DesignNote("· $it") }
                if (rank.feature?.assembled == true) DesignNote("The film runs through ${unit.lowercase()}s ${rank.feature.titles.joinToString(", ")} (${DiscWords.clock(rank.feature.durationSec)}).")
            }
        }
        if (rank != null && rank.episodes.isNotEmpty()) {
            DesignSection("Episodes") {
                rank.episodes.forEach { e ->
                    DesignRow(
                        "Episode ${e.index}", value = DiscWords.clock(e.durationSec), enabled = playable,
                        onClick = { nav.push(Route.Page(DiscWords.episodePath(itemId, e))) }, label = "Episode ${e.index} · ${DiscWords.clock(e.durationSec)}",
                    )
                }
            }
        }
        val versions = rank?.versions?.filter { !it.main }.orEmpty()
        if (versions.isNotEmpty()) {
            DesignSection("Other versions") {
                versions.forEach { v ->
                    val name = v.label.ifEmpty { DiscWords.name(a.kind, v.ttn) }
                    DesignRow(
                        name, value = DiscWords.clock(v.durationSec), enabled = playable,
                        onClick = { nav.push(Route.Page(DiscWords.versionPath(itemId, v))) }, label = name + " · " + DiscWords.clock(v.durationSec),
                    )
                }
            }
        }
        if (a.canChoose) {
            // An administrator's: the other candidates as rows, each made the film with a press; the engine's pick back
            // and ranking again as chips.
            val candidates = rank?.candidates?.filter { it.ttn != a.main }?.take(MOST_CANDIDATES).orEmpty()
            DesignSection("Candidates") {
                candidates.forEach { c ->
                    val name = DiscWords.name(a.kind, c.ttn)
                    DesignRow(
                        "Make $name the film", value = DiscWords.clock(c.durationSec),
                        onClick = { run("$name is now this disc's film") { nav.app.api.chooseDiscTitle(kind, itemId, c.ttn) } },
                        label = "Make $name the film · ${DiscWords.clock(c.durationSec)}",
                    )
                }
                DesignChips(Modifier.padding(top = LocalDesignSizes.current.gap * 0.5f)) {
                    if (a.chosen != null) DesignChip("Use the engine's pick", { run("The engine's pick is the film again") { nav.app.api.forgetDiscChoice(kind, itemId) } })
                    DesignChip("Rank again", { run("Ranked again") { nav.app.api.rankDiscAgain(kind, itemId).also { if (it.pending) ask++ } } })
                }
            }
        }
        if (said.isNotEmpty()) DesignNote(said, Modifier.padding(top = LocalDesignSizes.current.gap).semantics { liveRegion = LiveRegionMode.Polite })
    }
}

private const val PENDING_TRIES = 20
private const val PENDING_WAIT_MS = 3000L
private const val MOST_LINES = 8
private const val MOST_CANDIDATES = 4
