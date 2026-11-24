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
data class ConnectStep(val id: String, val title: String, val failed: String = "")

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
data class ConnectStepsFile(val version: Int = 1, val steps: List<ConnectStep> = emptyList(), val codes: List<ConnectCode> = emptyList())

// A step that failed, why, and what to try next. `error` is the technical words it came from, already redacted.
data class ConnectFailure(val step: String, val code: String, val say: String, val next: String, val error: String = "")

class ConnectSteps(val file: ConnectStepsFile) {
    val steps: List<ConnectStep> get() = file.steps

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
class ConnectRun(val kind: String, val server: String = "") {
    private val started = System.currentTimeMillis()
    val passed = mutableListOf<String>()
    var failure: ConnectFailure? = null
        private set
    private val log = mutableListOf<String>()

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
        log.forEach { appendLine("  $it") }
    }.let(Redact::clean)
}
