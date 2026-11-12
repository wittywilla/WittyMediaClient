// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.wittywilla.wittymediaclient.net.DvrRules
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.RecordingRule
import com.wittywilla.wittymediaclient.net.SeriesOptions
import com.wittywilla.wittymediaclient.net.changeRecordingRule
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.record
import com.wittywilla.wittymediaclient.net.recordSeries
import com.wittywilla.wittymediaclient.ui.LocalMetrics
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.body
import com.wittywilla.wittymediaclient.ui.secondary
import com.wittywilla.wittymediaclient.ui.section
import com.wittywilla.wittymediaclient.ui.title
import com.wittywilla.wittymediaclient.ui.u
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// A recording's options, on a server with `tv-dvr-rules-2`, as the server's page offers them: a few minutes before and
// after, and for a series, only new episodes, on any channel, and how many to keep. A server without it records as
// before, with no options asked.

// What's being recorded: one programme, a new series, or a series whose options are being changed.
sealed interface RecordWhat {
    data class One(val channel: GuideChannel, val programme: GuideProgramme) : RecordWhat
    data class Series(val channel: GuideChannel, val programme: GuideProgramme) : RecordWhat
    data class Rule(val rule: RecordingRule) : RecordWhat
}

@Composable
fun RecordOptions(nav: Nav, what: RecordWhat, onSaid: (String) -> Unit, onClose: () -> Unit) {
    val api = nav.app.api
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val rule = (what as? RecordWhat.Rule)?.rule
    val series = what !is RecordWhat.One
    var before by remember { mutableIntStateOf(rule?.padBefore ?: 0) }
    var after by remember { mutableIntStateOf(rule?.padAfter ?: 0) }
    var newOnly by remember { mutableStateOf(rule?.newOnly ?: false) }
    var anyChannel by remember { mutableStateOf(rule?.anyChannel ?: false) }
    var keep by remember { mutableIntStateOf(rule?.keep ?: 0) }
    var error by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    val title = when (what) {
        is RecordWhat.One -> what.programme.title
        is RecordWhat.Series -> what.programme.title
        is RecordWhat.Rule -> what.rule.title
    }

    fun save() {
        if (saving) return
        saving = true
        val options = SeriesOptions(anyChannel = anyChannel, newOnly = newOnly, keep = keep, padBefore = before, padAfter = after)
        scope.launch {
            try {
                when (what) {
                    is RecordWhat.One -> {
                        val p = what.programme
                        api.record(what.channel.key, p.title, p.sub, p.start, p.end, before, after)
                        onSaid("Recording ${p.title}")
                    }
                    is RecordWhat.Series -> {
                        api.recordSeries(what.channel.key, what.programme.title, options)
                        onSaid("Every airing of ${what.programme.title} will be recorded")
                    }
                    is RecordWhat.Rule -> {
                        api.changeRecordingRule(what.rule.id, options)
                        onSaid("${what.rule.title}: changed")
                    }
                }
                onClose()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemText(e, "That couldn't be recorded.")
            } finally {
                saving = false
            }
        }
    }

    TvSheet(onClose) {
        Column(
            Modifier.widthIn(max = metrics.u(1300)).fillMaxWidth().padding(horizontal = metrics.gutter, vertical = metrics.edge),
            verticalArrangement = Arrangement.spacedBy(metrics.u(24)),
        ) {
            Text(
                if (rule != null) "Series: $title" else if (series) "Record every airing of $title" else "Record $title",
                style = MaterialTheme.typography.title, color = scheme.onBackground, modifier = Modifier.semantics { heading() },
            )
            if (what is RecordWhat.One) {
                Text(
                    "Channel ${what.channel.number} ${what.channel.name} · ${GuideRules.dayName(what.programme.start)}, ${GuideRules.span(what.programme.start, what.programme.end)}",
                    style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant,
                )
            }
            if (series) {
                Column(Modifier.focusGroup(), verticalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                    Tick("New episodes only", newOnly) { newOnly = it }
                    val channelName = when (what) {
                        is RecordWhat.Series -> "${what.channel.number} ${what.channel.name}"
                        is RecordWhat.Rule -> what.rule.channel
                        is RecordWhat.One -> "${what.channel.number} ${what.channel.name}"
                    }
                    Tick("On any channel, not only $channelName", anyChannel) { anyChannel = it }
                }
                Options("Recordings to keep", DvrRules.KEEP.map { it to DvrRules.keepWords(it) }, keep) { keep = it }
            }
            Options("Start early", DvrRules.PADDING.map { it to DvrRules.padWords(it) }, before) { before = it }
            Options("End late", DvrRules.PADDING.map { it to DvrRules.padWords(it) }, after) { after = it }
            Text(
                "Starting early and ending late catches a programme that doesn't keep to the guide's times, and uses a tuner for longer.",
                style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant,
            )
            if (error.isNotEmpty()) Text(error, style = MaterialTheme.typography.body, color = scheme.error)
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                SheetButton(
                    when {
                        rule != null -> "Save"
                        series -> "Record every airing"
                        else -> "Record"
                    },
                    ::save, kind = SheetKind.Primary, takeFocus = true,
                )
                SheetButton("Cancel", onClose, kind = SheetKind.Quiet)
            }
        }
    }
}

@Composable
private fun Tick(words: String, on: Boolean, set: (Boolean) -> Unit) {
    SheetButton(words, { set(!on) }, selected = on, icon = if (on) TvSymbols.Ticked else TvSymbols.Unticked)
}

@Composable
private fun Options(title: String, options: List<Pair<Int, String>>, value: Int, set: (Int) -> Unit) {
    val metrics = LocalMetrics.current
    Column(verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        Text(title, style = MaterialTheme.typography.section, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.semantics { heading() })
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(vertical = metrics.u(16) - metrics.focusRing, horizontal = metrics.u(8) - metrics.focusRing)
                .focusGroup(),
            horizontalArrangement = Arrangement.spacedBy(metrics.u(16) - metrics.focusRing * 2),
        ) {
            for ((n, words) in options) SheetButton(words, { set(n) }, selected = value == n)
        }
    }
}
