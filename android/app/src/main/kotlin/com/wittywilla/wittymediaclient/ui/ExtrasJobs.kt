// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ExtrasFeature
import com.wittywilla.wittymediaclient.net.JobAnswer
import com.wittywilla.wittymediaclient.net.ServerTask
import com.wittywilla.wittymediaclient.net.TaskLook
import com.wittywilla.wittymediaclient.net.TasksHidden
import com.wittywilla.wittymediaclient.net.cancelTask
import com.wittywilla.wittymediaclient.net.followTask
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Something the server makes for a title when asked: a canvas cut from the video, a song's stems, a show's intros
// found by ear. Each is a task on the server (docs/TASKS.md), so asking answers at once and the work is followed from
// here: how far it is, a way to stop it where the server allows, and what came of it. Leaving the page stops the
// following, never the work.
class ExtrasJob internal constructor(private val nav: Nav, private val scope: CoroutineScope) {
    var title by mutableStateOf("")
        private set
    var task by mutableStateOf<ServerTask?>(null)
        private set
    var problem by mutableStateOf("")
        private set
    var busy by mutableStateOf(false)
        private set
    private var following: Job? = null

    val showing: Boolean get() = busy || task != null || problem.isNotEmpty()

    // Asks the server to start, then follows the task to its end. `settled` is asked now and then instead when this
    // account can't see the server's tasks: true once the thing being made is there or no longer being made. `done`
    // hears how it ended, to show what was made.
    fun start(title: String, ask: suspend (Api) -> JobAnswer, settled: (suspend (Api) -> Boolean)? = null, done: (ok: Boolean) -> Unit) {
        following?.cancel()
        this.title = title
        task = null
        problem = ""
        busy = true
        following = scope.launch {
            val api = nav.app.api
            try {
                val answer = ask(api)
                if (answer.exists || answer.task.isEmpty()) {
                    task = ServerTask(title = title, state = "done", result = if (answer.exists) "It was already there." else "Done.")
                    busy = false
                    done(true)
                    return@launch
                }
                task = ServerTask(id = answer.task, title = title, state = "queued")
                try {
                    if (!nav.has(ExtrasFeature.TASKS)) throw TasksHidden()
                    api.followTask(answer.task).collect { task = it.copy(title = it.title.ifEmpty { title }) }
                } catch (_: TasksHidden) {
                    // Not this account's to watch: wait for the thing itself.
                    task = ServerTask(id = answer.task, title = title, state = "running")
                    var ok = settled == null
                    if (settled != null) {
                        for (turn in 0 until SETTLE_TURNS) {
                            delay(SETTLE_EVERY_MS)
                            if (runCatching { settled(api) }.getOrDefault(false)) { ok = true; break }
                        }
                    }
                    task = ServerTask(id = answer.task, title = title, state = "done", result = if (settled == null) "Started. It carries on on the server." else if (ok) "Done." else "Still being made on the server.")
                }
                busy = false
                done(task?.let { !TaskLook.failed(it) } ?: true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                busy = false
                if (!nav.handleExpired(e)) problem = problemWords(e, "Lost contact with your server. Check that it is running, then try again.")
            }
        }
    }

    // Stops the work on the server, where it says it can be stopped. The stream then says it was.
    fun stop() {
        val id = task?.takeIf { it.canCancel }?.id ?: return
        scope.launch {
            try {
                nav.app.api.cancelTask(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!nav.handleExpired(e)) problem = problemWords(e, "Lost contact with your server.")
            }
        }
    }

    // Puts the card away. Work still going on carries on, on the server.
    fun close() {
        following?.cancel()
        following = null
        busy = false
        task = null
        problem = ""
    }

    private companion object {
        const val SETTLE_EVERY_MS = 2_000L
        const val SETTLE_TURNS = 450 // a quarter of an hour
    }
}

// A page's own job, followed for as long as the page is up.
@Composable
fun rememberExtrasJob(nav: Nav): ExtrasJob {
    val scope = rememberCoroutineScope()
    return remember(nav.app.api) { ExtrasJob(nav, scope) }
}

// The card for a job: what it is, how far along, what it said, and Stop or Close. On the page it was started from, in
// the page's own style: the website's buttons on a phone or tablet, focusable ones on a TV. Nothing when there's none.
@Composable
fun ExtrasJobCard(job: ExtrasJob, modifier: Modifier = Modifier, takeFocus: Boolean = false) {
    if (!job.showing) return
    val scheme = MaterialTheme.colorScheme
    val tv = LocalMetrics.current.tv
    val task = job.task
    val over = !job.busy
    val failed = job.problem.isNotEmpty() || (task != null && TaskLook.failed(task))
    val line = job.problem.ifEmpty { task?.let(TaskLook::line) ?: "Asking your server…" }
    val fraction = task?.let(TaskLook::fraction)
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(scheme.surfaceVariant).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(job.title, color = scheme.onSurface, fontSize = if (tv) 18.sp else 15.sp, fontWeight = FontWeight.SemiBold)
        if (!over) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (fraction == null) {
                    Spinner(scheme.primary, 18.dp, Modifier.semantics { contentDescription = "Working" })
                } else {
                    Box(
                        Modifier.weight(1f).height(6.dp).clip(RoundedCornerShape(50)).background(scheme.outline)
                            .semantics { contentDescription = job.title; progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f) },
                    ) { Box(Modifier.fillMaxWidth(fraction).height(6.dp).background(scheme.primary)) }
                }
            }
        }
        Text(
            line, color = if (failed) scheme.error else scheme.onSurfaceVariant, fontSize = if (tv) 16.sp else 14.sp,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val canStop = !over && task?.canCancel == true
            if (tv) {
                if (canStop) ActionButton("Stop", job::stop, focusKey = "job-stop", takeFocus = takeFocus)
                if (over) ActionButton("Close", job::close, focusKey = "job-close", takeFocus = takeFocus)
            } else {
                if (canStop) WebButton("Stop", job::stop, small = true)
                if (over) WebButton("Close", job::close, small = true)
            }
        }
    }
}
