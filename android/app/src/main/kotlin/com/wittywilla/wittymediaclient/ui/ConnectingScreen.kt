// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import com.wittywilla.wittymediaclient.data.LogoCache
import com.wittywilla.wittymediaclient.net.ConnectRun
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay

// One go at joining a server from a QR code, a code or a link, while it goes on: the run it ticks off, the job doing
// it (Cancel stops it), and the words to show if it ended without opening the server or showing the connection check.
class Joining(val run: ConnectRun, val retry: (() -> Unit)?) {
    var job: Job? = null
    var words by mutableStateOf("")
}

// The connecting screen: from a QR code scanned, a code typed or an invite link opened until the server opens. One
// centred card with the server's name (and logo, once known), each step ticking off as it gets through, what the
// step being tried is doing in plain words, the time so far and Cancel; after a while a hint that it can take up to a
// minute. A failure shows the connection check (each step, and what to do) in its place, or, for words alone (a code
// no server made, say), the step it stopped on and those words here. The same screen on Apple's apps
// (ConnectingView) and the desktop app (connect.js, connectingScreen).
@Composable
fun ConnectingScreen(nav: Nav, s: Map<String, String>, joining: Joining) {
    val context = LocalContext.current
    val steps = remember { ConnectStepsData.get(context) }
    val run = joining.run
    // Read again a few times a second: the join ticks the run off on another thread, and the clock moves on.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(joining) {
        while (true) {
            now = System.currentTimeMillis()
            delay(250)
        }
    }
    val p = run.progress(steps, now)
    val words = joining.words
    val ended = words.isNotEmpty()
    val known = remember(run.server, now / 2000) { nav.savedFor(run.server) }
    val name = run.name.ifEmpty { known?.name.orEmpty() }
    val ok = LocalExtraColours.current.accentText
    val bad = MaterialTheme.colorScheme.error
    // The name is the lockup's, over the title, as on the sign-in screens: not said twice.
    val title = s["connectingTitlePlain"].orEmpty()
    DesignScreen(
        title, { nav.stopJoining(joining) }, tag = "connecting", centred = true,
        top = { Lockup(name, known?.let { LogoCache.file(context, it.url, it.brandLogo) }) },
        foot = if (ended) "" else (s["connectingSoFar"] ?: "{time}").replace("{time}", p.clock),
        actions = {
            if (ended) {
                if (joining.retry != null) {
                    WittyButton(s["checkTryAgain"].orEmpty(), { nav.pop(); joining.retry.invoke() }, kind = ButtonKind.Primary, tall = true, requestFocus = true, focusKey = "connecting-again")
                }
                WittyButton(s["back"].orEmpty(), { nav.pop() }, kind = ButtonKind.Secondary, tall = true, requestFocus = joining.retry == null, focusKey = "connecting-back")
            } else {
                WittyButton(s["cancel"].orEmpty(), { nav.stopJoining(joining) }, kind = ButtonKind.Secondary, tall = true, requestFocus = true, focusKey = "connecting-cancel")
            }
        },
    ) {
        DesignSection("") {
            for ((step, state) in p.steps) {
                val word = when (state) {
                    "ok" -> s["checkStepDone"].orEmpty()
                    "now" -> s["checkStepNow"].orEmpty()
                    "fail" -> s["checkStepFailed"].orEmpty()
                    else -> s["checkStepSkipped"].orEmpty()
                }
                DesignRow(
                    step.title, value = if (state == "wait") "" else word, state = word, on = state == "ok",
                    sub = if (state == "fail") words else "",
                    focusKey = "connecting-step-${step.id}",
                    leading = { StepNow(state, ok, bad) },
                )
            }
        }
        // Said aloud as it changes: what's happening now, then the hint once it has taken a while.
        if (!ended) DesignNote(p.doing, busy = true)
        DesignNote(p.slow, tone = true)
    }
}

@Composable
private fun StepNow(state: String, ok: Color, bad: Color) {
    val size = Dp(LocalDesignSizes.current.body.value * 1.4f)
    Box(Modifier.size(size)) {
        when (state) {
            "ok" -> Icon(Icons.Filled.Check, null, tint = ok)
            "fail" -> Icon(Icons.Filled.Close, null, tint = bad)
            "now" -> Spinner(MaterialTheme.colorScheme.onSurfaceVariant, size * 0.8f)
            else -> Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = LocalDesignSizes.current.body)
        }
    }
}
