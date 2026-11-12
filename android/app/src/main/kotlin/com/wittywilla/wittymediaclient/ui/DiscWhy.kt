// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
// an administrator another title to make the film, or the engine's pick back.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DiscWhySection(nav: Nav, itemId: Long, playable: Boolean, modifier: Modifier = Modifier) {
    if (!nav.has("disc-ranking")) return
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val scope = rememberCoroutineScope()
    var analysis by remember { mutableStateOf<DiscAnalysis?>(null) }
    var said by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var ask by remember { mutableIntStateOf(0) }
    LaunchedEffect(itemId, ask) {
        // A small server works it out in the background: asked again until it has.
        repeat(PENDING_TRIES) {
            val got = runCatching { nav.app.api.discAnalysis(itemId) }.getOrNull() ?: return@LaunchedEffect
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
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Why this ${unit.lowercase()}", color = scheme.onBackground, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        if (rank != null && a.ranked && a.chosen == null) Text(DiscWords.level(rank.level, rank.confidence) + " · " + DiscWords.sure(rank.confidence), color = LocalExtraColours.current.accentText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Text(DiscWords.headline(a), color = scheme.onBackground, fontSize = 15.sp, lineHeight = 22.sp)
        if (rank != null) {
            val lines = rank.reasons.map { "For it: $it" } + rank.against.map { "Against it: $it" } + rank.warnings + rank.repairs +
                rank.issues.map { (if (it.severity == "error") "Won't play: " else "") + it.what + if (it.ttn >= 0) " (${DiscWords.name(a.kind, it.ttn)})" else "" } +
                (if (rank.paddedSectors > 0) listOf("${rank.paddedSectors} unreadable sectors were passed over as blank while reading the disc's index.") else emptyList())
            lines.take(MOST_LINES).forEach { Text("· $it", color = hint, fontSize = 13.sp, lineHeight = 19.sp) }
            if (rank.feature?.assembled == true) Text("The film runs through ${unit.lowercase()}s ${rank.feature.titles.joinToString(", ")} (${DiscWords.clock(rank.feature.durationSec)}).", color = hint, fontSize = 13.sp)
            if (rank.episodes.isNotEmpty()) {
                Text("Episodes", color = scheme.onBackground, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp).semantics { heading() })
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    rank.episodes.forEach { e ->
                        WebButton("Episode ${e.index} · ${DiscWords.clock(e.durationSec)}", { nav.push(Route.Page(DiscWords.episodePath(itemId, e))) }, WebButtonKind.Secondary, WebIcons.Play, small = true, enabled = playable)
                    }
                }
            }
            val versions = rank.versions.filter { !it.main }
            if (versions.isNotEmpty()) {
                Text("Other versions", color = scheme.onBackground, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp).semantics { heading() })
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    versions.forEach { v ->
                        WebButton(v.label.ifEmpty { DiscWords.name(a.kind, v.ttn) } + " · " + DiscWords.clock(v.durationSec), { nav.push(Route.Page(DiscWords.versionPath(itemId, v))) }, WebButtonKind.Secondary, WebIcons.Play, small = true, enabled = playable)
                    }
                }
            }
        }
        if (a.canChoose) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (a.chosen != null) WebButton("Use the engine's pick", { run("The engine's pick is the film again") { nav.app.api.forgetDiscChoice(itemId) } }, WebButtonKind.Ghost, small = true)
                rank?.candidates?.filter { it.ttn != a.main }?.take(MOST_CANDIDATES)?.forEach { c ->
                    WebButton("Make ${DiscWords.name(a.kind, c.ttn)} the film · ${DiscWords.clock(c.durationSec)}", {
                        run("${DiscWords.name(a.kind, c.ttn)} is now this disc's film") { nav.app.api.chooseDiscTitle(itemId, c.ttn) }
                    }, WebButtonKind.Ghost, small = true)
                }
                WebButton("Rank again", { run("Ranked again") { nav.app.api.rankDiscAgain(itemId).also { if (it.pending) ask++ } } }, WebButtonKind.Ghost, small = true)
            }
        }
        if (said.isNotEmpty()) Text(said, color = hint, fontSize = 13.sp)
    }
}

private const val PENDING_TRIES = 20
private const val PENDING_WAIT_MS = 3000L
private const val MOST_LINES = 8
private const val MOST_CANDIDATES = 4
