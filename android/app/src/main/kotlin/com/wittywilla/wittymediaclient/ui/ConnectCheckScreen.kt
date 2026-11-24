// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.ConnectRun
import com.wittywilla.wittymediaclient.net.ConnectSteps

// What a failed connection from away shows, instead of going back to the list of servers: each step of connecting
// with a tick or a cross, one sentence on the step that failed and the next thing to try, and the details (redacted)
// to copy or share. The same screen on Apple's apps and the desktop app (ConnectCheckView, connect.js).

object ConnectStepsData {
    @Volatile private var loaded: ConnectSteps? = null

    // The steps file as this app was built with it (shared/data/connect-steps.json, the server's own).
    fun get(context: Context): ConnectSteps = loaded ?: ConnectSteps.parse(
        context.assets.open("connect-steps.json").bufferedReader().use { it.readText() },
    ).also { loaded = it }
}

@Composable
fun ConnectCheckScreen(nav: Nav, s: Map<String, String>, run: ConnectRun, retry: (() -> Unit)?) {
    val context = LocalContext.current
    val app = context.applicationContext as WittyApp
    val steps = remember { ConnectStepsData.get(context) }
    val tv = LocalMetrics.current.tv
    val clipboard = LocalClipboardManager.current
    val failure = run.failure
    var copied by remember(run) { mutableStateOf(false) }
    var showAll by remember(run) { mutableStateOf(false) }
    val details = remember(run) {
        val version = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty()
        run.details(steps.steps, "WittyMediaClient ${app.platformName} $version", app.deviceName)
    }
    val ok = LocalExtraColours.current.accentText
    val bad = MaterialTheme.colorScheme.error
    DesignScreen(
        s["checkTitle"].orEmpty(), nav::pop, eyebrow = s["rowAway"].orEmpty(), lead = s["checkLead"].orEmpty(), tag = "connect-check",
        actions = {
            if (retry != null) WittyButton(s["checkTryAgain"].orEmpty(), { nav.pop(); retry() }, kind = ButtonKind.Primary, tall = true, requestFocus = true, focusKey = "check-again")
            // A TV has nowhere to paste or send the details: they're on the screen below instead.
            if (!tv) {
                WittyButton(s["checkCopy"].orEmpty(), {
                    clipboard.setText(AnnotatedString(details))
                    copied = true
                }, kind = ButtonKind.Secondary, tall = true, focusKey = "check-copy")
                WittyButton(s["checkShare"].orEmpty(), {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, details)
                    runCatching { context.startActivity(Intent.createChooser(send, s["checkShare"].orEmpty())) }
                }, kind = ButtonKind.Secondary, tall = true, focusKey = "check-share")
            }
            WittyButton(s["checkOtherServer"].orEmpty(), { nav.pop() }, kind = ButtonKind.Secondary, tall = true, requestFocus = retry == null, focusKey = "check-back")
        },
    ) {
        DesignSection("") {
            for ((step, state) in run.states(steps.steps)) {
                val word = when (state) {
                    "ok" -> s["checkStepDone"].orEmpty()
                    "fail" -> s["checkStepFailed"].orEmpty()
                    else -> s["checkStepSkipped"].orEmpty()
                }
                DesignRow(
                    step.title, value = word, on = state == "ok",
                    sub = if (state == "fail") failure?.say.orEmpty() else "",
                    focusKey = "check-step-${step.id}",
                    leading = { StepMark(state, ok, bad) },
                )
            }
        }
        if (copied) DesignNote(s["checkCopied"].orEmpty(), Modifier.padding(top = LocalDesignSizes.current.gap))
        failure?.let { f ->
            DesignNote((s["checkNext"] ?: "Next: {next}").replace("{next}", f.next), Modifier.padding(top = LocalDesignSizes.current.gap), tone = true)
        }
        if (tv) {
            // A TV can't copy or share them: one row that opens the whole log, so the buttons stay on the first screen.
            DesignSection("") {
                DesignRow(
                    s["checkDetails"].orEmpty(), value = (failure?.code.orEmpty() + if (showAll) "  −" else "  +").trim(),
                    sub = if (showAll) s["checkDetailsHint"].orEmpty() else "", onClick = { showAll = !showAll }, focusKey = "check-all",
                )
                if (showAll) Text(details, color = MaterialTheme.colorScheme.onSurfaceVariant, fontFamily = FontFamily.Monospace, fontSize = LocalDesignSizes.current.tiny)
            }
        } else {
            DesignSection(s["checkDetails"].orEmpty()) {
                DesignNote(s["checkDetailsHint"].orEmpty())
                failure?.let { f -> DesignRow(f.code, value = f.step, sub = f.error, focusKey = "check-code") }
            }
        }
    }
}

@Composable
private fun StepMark(state: String, ok: Color, bad: Color) {
    val size = LocalDesignSizes.current.body.value.let { (it * 1.4f).toInt() }
    Box(Modifier.size(size.dp())) {
        when (state) {
            "ok" -> Icon(Icons.Filled.Check, null, tint = ok)
            "fail" -> Icon(Icons.Filled.Close, null, tint = bad)
            else -> Text("–", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = LocalDesignSizes.current.body)
        }
    }
}

private fun Int.dp() = androidx.compose.ui.unit.Dp(this.toFloat())
