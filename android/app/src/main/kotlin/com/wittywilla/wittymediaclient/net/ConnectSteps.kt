// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import com.wittywilla.wittymediaclient.diag.Redact
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

// The steps of connecting from away, and why one can fail, in the server's words (its pkg/connectsteps/steps.json,
// kept here as shared/data/connect-steps.json): the same codes the server's Recent tries shows, and the same
// sentences on every app. Tested against the file's own cases.

@Serializable
data class ConnectStep(val id: String, val title: String, val failed: String = "", val doing: String = "")

// The hint while connecting takes a while, and after how many seconds.
@Serializable
data class ConnectSlow(val after: Int = 10, val say: String = "")

@Serializable
data class ConnectCode(
    val code: String,
    val step: String = "",
    val reasons: List<String> = emptyList(),
    val match: List<String> = emptyList(),
    val say: String = "",
    val next: String = "",
)

@Serializable
data class ConnectStepsFile(val version: Int = 1, val steps: List<ConnectStep> = emptyList(), val slow: ConnectSlow = ConnectSlow(), val codes: List<ConnectCode> = emptyList())

// A step that failed, why, and what to try next. `error` is the technical words it came from, already redacted.
data class ConnectFailure(val step: String, val code: String, val say: String, val next: String, val error: String = "")

class ConnectSteps(val file: ConnectStepsFile) {
    val steps: List<ConnectStep> get() = file.steps
    val slow: ConnectSlow get() = file.slow

    // The failure behind a server's reason ("expired") and an error's words. A reason is looked for first, then the
    // words; with neither known, "unknown" at `step`, the step that was being tried.
    fun classify(reason: String, text: String, step: String): ConnectFailure {
        val r = reason.trim()
        val lower = text.lowercase(Locale.ROOT)
        fun pick(c: ConnectCode) = ConnectFailure(c.step.ifEmpty { step }, c.code, c.say, c.next, Redact.clean(text).take(400))
        if (r.isNotEmpty()) file.codes.firstOrNull { r in it.reasons }?.let { return pick(it) }
        if (lower.isNotEmpty()) file.codes.firstOrNull { c -> c.match.any { lower.contains(it) } }?.let { return pick(it) }
        return pick(file.codes.firstOrNull { it.code == "unknown" } ?: ConnectCode("unknown", say = "Something went wrong."))
    }

    fun of(code: String, step: String = ""): ConnectFailure = classify(code, "", step)

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun parse(text: String): ConnectSteps = ConnectSteps(json.decodeFromString(text))
    }
}

// One go at connecting: what was being joined, each step that got through, the one that failed, and a short log of
// what the app saw, for Copy details. Nothing in it is sent anywhere.
// Read by the connecting screen while the join goes on elsewhere, so what it reads is safe to read from any thread.
class ConnectRun(val kind: String, val server: String = "") {
    private val started = System.currentTimeMillis()
    val passed: MutableList<String> = java.util.concurrent.CopyOnWriteArrayList()
    @Volatile var failure: ConnectFailure? = null
        private set
    // The server's name, once the invite or the server says it.
    @Volatile var name: String = ""
        private set
    private val log: MutableList<String> = java.util.Collections.synchronizedList(mutableListOf())

    fun named(n: String) {
        if (n.isNotBlank()) name = n.trim().take(80)
    }

    fun note(line: String) {
        if (log.size < 60) log += "${elapsed()} ${Redact.clean(line).take(300)}"
    }

    fun pass(step: String) {
        if (step !in passed) passed += step
        note("ok: $step")
    }

    // A failure is shown on the step being tried: one whose words belong to an earlier step that already got through
    // (a time-out while signing in, say) moves to the step after the last that did.
    fun fail(failure: ConnectFailure): ConnectFailure {
        var f = failure
        val last = passed.maxOfOrNull { ORDER.indexOf(it) } ?: -1
        val at = ORDER.indexOf(f.step)
        if (at < 0 || at < last) f = f.copy(step = ORDER.getOrElse(last + 1) { ORDER.last() })
        this.failure = f
        note("failed: ${f.step} (${f.code})" + if (f.error.isNotEmpty()) ": ${f.error}" else "")
        return f
    }

    companion object {
        // The steps' order (connect-steps.json): their ids never change.
        val ORDER = listOf("read", "found", "secure", "signin")
    }

    private fun elapsed() = "+%.1fs".format(Locale.ROOT, (System.currentTimeMillis() - started) / 1000.0)

    // Each step's state: done, failed, or not reached. A step after the failed one is never shown as done.
    fun states(steps: List<ConnectStep>): List<Pair<ConnectStep, String>> {
        val at = steps.indexOfFirst { it.id == failure?.step }
        return steps.mapIndexed { i, s ->
            s to when {
                at >= 0 && i == at -> "fail"
                at >= 0 && i > at -> "skip"
                s.id in passed || at > i -> "ok"
                else -> "skip"
            }
        }
    }

    // While connecting, for the connecting screen: each step done ("ok"), being tried ("now"), still to come
    // ("wait") or failed; what the step being tried is doing; how long it has taken; and the slow hint once it has
    // taken a while.
    fun progress(steps: ConnectSteps, now: Long = System.currentTimeMillis()): ConnectProgress {
        val failed = failure
        val at = if (failed != null) -1 else steps.steps.indexOfFirst { it.id !in passed }
        val list = states(steps.steps).mapIndexed { i, (step, state) ->
            step to if (state != "skip" || failed != null) state else if (i == at) "now" else "wait"
        }
        val step = steps.steps.getOrNull(at)
        val ms = (now - started).coerceAtLeast(0)
        val slow = steps.slow
        return ConnectProgress(
            list, step?.id.orEmpty(), step?.let { it.doing.ifEmpty { it.title } }.orEmpty(), ms,
            if (failed == null && slow.say.isNotEmpty() && ms >= slow.after * 1000L) slow.say else "", failed,
        )
    }

    // Copy details: plain text a person can paste to whoever runs the server. Redacted: no keys, secrets or tokens.
    fun details(steps: List<ConnectStep>, app: String, device: String): String = buildString {
        val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss 'UTC'", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(started))
        appendLine("WittyMediaClient connection check")
        appendLine("When: $stamp")
        appendLine("App: $app")
        appendLine("Device: $device")
        appendLine("Joining: $kind" + if (server.isNotEmpty()) " (server …${server.takeLast(8)})" else "")
        for ((s, state) in states(steps)) appendLine("[${if (state == "ok") "x" else if (state == "fail") "!" else " "}] ${s.title}")
        failure?.let {
            appendLine("Failed: ${it.step}, ${it.code}")
            appendLine(it.say)
            appendLine("Next: ${it.next}")
            if (it.error.isNotEmpty()) appendLine("Error: ${it.error}")
        }
        appendLine("Log:")
        synchronized(log) { log.toList() }.forEach { appendLine("  $it") }
    }.let(Redact::clean)
}

// What the connecting screen shows for a run, at one moment.
data class ConnectProgress(
    val steps: List<Pair<ConnectStep, String>>,
    val step: String,
    val doing: String,
    val ms: Long,
    val slow: String,
    val failure: ConnectFailure?,
) {
    // How long connecting has taken, as a clock: 0:07, 1:02.
    val clock: String get() = (ms / 1000).let { "%d:%02d".format(Locale.ROOT, it / 60, it % 60) }
}
