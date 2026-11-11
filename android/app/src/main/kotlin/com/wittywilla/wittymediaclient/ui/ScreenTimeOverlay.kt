// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.FEATURE_PARENTAL
import com.wittywilla.wittymediaclient.net.ScreenTime
import com.wittywilla.wittymediaclient.net.ScreenTimeRules
import com.wittywilla.wittymediaclient.net.askParentByPassword
import com.wittywilla.wittymediaclient.net.askParentByPin
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.player.ScreenTimeWatch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Date
import java.util.TimeZone

// Screen time and what is turned off, over whatever the app is showing (the server's docs/PROFILES.md, "Screen
// time" and "Asking a parent for more time"). One of these sits at the top of the app, so every player has it:
// a line a few minutes before time runs out, and when it does, a notice that says why and when playing can start
// again, with Ask a parent. Whatever was playing is left, with its place kept; browsing carries on.

// A tab the signed-in profile's limits turn off isn't offered: the Games tab without games, Live TV without it.
fun profileOffers(route: Route): Boolean = when (route) {
    Route.Games -> ScreenTimeWatch.can("games")
    Route.LiveTv -> ScreenTimeWatch.can("liveTv")
    else -> true
}

// The server's pages that play something, as the web client itself lists them.
private val PLAYING_PAGE = Regex("^/(watch|play|game|big|disc|tv/watch)(/|$)")

// Is this screen playing something that screen time counts? Apart from the screen, so it can be tested.
fun isPlayingRoute(route: Route): Boolean = when (route) {
    is Route.Player, Route.NowPlaying -> true
    is TvRoute -> route.screen is TvScreen.Channel
    is GamesRoute -> route.screen is GamesScreen.Play
    is Route.Page -> PLAYING_PAGE.containsMatchIn(route.path)
    is Route.Web -> PLAYING_PAGE.containsMatchIn(route.path)
    else -> false
}

// Leaves whatever is playing: each player saves its place and lets go of its stream as it goes.
private fun leavePlayers(nav: Nav) {
    if (nav.video != null) nav.closeVideo()
    var guard = 0
    while (isPlayingRoute(nav.current) && guard++ < 8) {
        if (nav.stack.size > 1) nav.pop() else nav.reset(Route.Home)
    }
    // A TV's Live TV tab plays the channel under the guide.
    if (nav.current == Route.LiveTv) nav.reset(Route.Home)
}

@Composable
fun ProfileGuard(nav: Nav, api: Api, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val signedIn = api.token.isNotEmpty() && nav.current.signedIn
    val enabled = signedIn && nav.has(FEATURE_PARENTAL)
    LaunchedEffect(api, enabled) {
        if (enabled) ScreenTimeWatch.signedIn(nav.app, api, true) else ScreenTimeWatch.stop()
    }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { ScreenTimeWatch.shown(true) }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { ScreenTimeWatch.shown(false) }
    if (!enabled) return

    val telling = ScreenTimeWatch.telling
    LaunchedEffect(telling) { if (telling) leavePlayers(nav) }

    // The line a few minutes before: up for a few seconds each time the minutes left pass a mark.
    val count = ScreenTimeWatch.noticeCount
    var showLine by remember { mutableStateOf(false) }
    LaunchedEffect(count) {
        if (count == 0) return@LaunchedEffect
        showLine = true
        delay(LINE_MS)
        showLine = false
    }
    val minutes = ScreenTimeRules.minutesLeftNotice(ScreenTimeWatch.time)
    // The guide isn't offered to a profile whose limits turn Live TV off, whichever screen found the server has one.
    val liveTv = ScreenTimeWatch.can("liveTv")
    LaunchedEffect(liveTv, nav.hasGuide) { if (!liveTv && nav.hasGuide) nav.hasGuide = false }
    Box(Modifier.fillMaxSize().safeDrawingPadding().padding(metrics.gutter), contentAlignment = Alignment.BottomCenter) {
        if (showLine && minutes != null && !telling) {
            Text(
                s[if (minutes == 1) "screenTimeLeftOne" else "screenTimeLeft"].orEmpty().replace("{n}", minutes.toString()),
                color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.label,
                modifier = Modifier
                    .clip(Radius.FULL)
                    .background(MaterialTheme.colorScheme.surface)
                    .padding(horizontal = metrics.u(20), vertical = metrics.u(12))
                    .semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
    }
    val st = ScreenTimeWatch.time
    if (telling && st != null && !st.allowed) TimeUpNotice(nav, s, st)
}

private const val LINE_MS = 8000L

// "You can watch again at 7:00." today, "tomorrow at 7:00." otherwise; nothing when the server gave no time.
@Composable
private fun whenAgain(s: Map<String, String>, st: ScreenTime): String {
    if (st.nextAt <= 0) return ""
    val context = LocalContext.current
    val clock = DateFormat.getTimeFormat(context).format(Date(st.nextAt * 1000))
    val today = ScreenTimeRules.nextIsToday(st.nextAt, System.currentTimeMillis(), TimeZone.getDefault())
    return s[if (today) "timeUpAgainToday" else "timeUpAgainTomorrow"].orEmpty().replace("{time}", clock)
}

@Composable
private fun TimeUpNotice(nav: Nav, s: Map<String, String>, st: ScreenTime) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val limits = ScreenTimeWatch.limits
    val hasPin = limits?.parentPin == true
    var asking by remember { mutableStateOf(false) }
    var minutes by remember { mutableIntStateOf(30) }
    var byPassword by remember { mutableStateOf(!hasPin) }
    var pin by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var wrong by remember { mutableIntStateOf(0) }
    var waits by remember { mutableIntStateOf(0) }
    var waitSec by remember { mutableIntStateOf(0) }
    val waiting = rememberWait(waitSec, waits)
    val title = s[
        when (st.reason) {
            "bedtime" -> "timeUpBedtime"
            "early" -> "timeUpEarly"
            else -> "timeUpTitle"
        },
    ].orEmpty()

    fun give() {
        if (busy || waiting > 0) return
        busy = true
        problem = ""
        scope.launch {
            try {
                val now = if (byPassword) nav.app.api.askParentByPassword(minutes, name.trim(), password) else nav.app.api.askParentByPin(minutes, pin)
                // Allowed again: the notice goes, and playing works from wherever they were.
                ScreenTimeWatch.take(now)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                if (nav.handleExpired(e)) return@launch
                // Wrong tries are counted for this profile and this device; after a few everyone waits, the right PIN included.
                if (e.status == 429) { waitSec = e.retryAfterSec; waits++ } else wrong++
                problem = problemWords(e, s["errLost"].orEmpty())
                pin = ""
                password = ""
            } catch (e: Exception) {
                problem = problemWords(e, s["errLost"].orEmpty())
            } finally {
                busy = false
            }
        }
    }

    if (!asking) {
        PanelDialog(title, ScreenTimeWatch::dismiss) {
            Text(st.message.ifEmpty { s["timeUpPlain"].orEmpty() }, color = scheme.onBackground, style = MaterialTheme.typography.body, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive })
            val again = whenAgain(s, st)
            if (again.isNotEmpty()) Text(again, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body)
            WittyButton(s["ok"].orEmpty(), ScreenTimeWatch::dismiss, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, requestFocus = true, focusKey = "time-ok")
            WittyButton(s["askParent"].orEmpty(), { asking = true; problem = "" }, Modifier.fillMaxWidth(), tall = true, focusKey = "time-ask")
            WittyButton(s["switchProfile"].orEmpty(), { ScreenTimeWatch.dismiss(); switchProfile(nav) }, Modifier.fillMaxWidth(), kind = ButtonKind.Quiet, icon = Symbols.Group, focusKey = "time-switch")
        }
        return
    }
    PanelDialog(s["askParent"].orEmpty(), { asking = false; problem = "" }) {
        Text(s["askParentHint"].orEmpty(), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body)
        Row(Modifier.fillMaxWidth().remoteRow(), horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
            ScreenTimeRules.EXTRA_CHOICES.forEach { m ->
                WittyButton(
                    s[if (m == 60) "extraHour" else "extraMinutes"].orEmpty().replace("{n}", m.toString()), { minutes = m },
                    Modifier.weight(1f), kind = if (minutes == m) ButtonKind.Primary else ButtonKind.Secondary, focusKey = "extra-$m",
                )
            }
        }
        if (byPassword) {
            WittyField(name, { name = it; problem = "" }, s["askParentName"].orEmpty(), kind = FieldKind.Username, icon = Symbols.Person, imeAction = ImeAction.Next, maxLength = 40)
            WittyField(
                password, { password = it; problem = "" }, s["askParentPassword"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
                imeAction = ImeAction.Go, onAction = ::give, isError = wrong > 0 && problem.isNotEmpty(), shake = wrong,
            )
        } else {
            WittyField(
                pin, { pin = ScreenTimeRules.typedPin(it); problem = "" }, s["parentsPinLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Key,
                imeAction = ImeAction.Go, onAction = ::give, isError = wrong > 0 && problem.isNotEmpty(), shake = wrong, maxLength = 12,
            )
        }
        Problem(listOf(problem, waitWords(s, waiting)).filter { it.isNotEmpty() }.joinToString(" "), Modifier.fillMaxWidth())
        val ready = if (byPassword) name.isNotBlank() && password.isNotEmpty() else ScreenTimeRules.pinReady(pin)
        WittyButton(s["giveMoreTime"].orEmpty(), ::give, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, enabled = ready && waiting == 0, tall = true, focusKey = "give-time")
        if (hasPin) {
            WittyButton(
                s[if (byPassword) "askUsePin" else "askUsePassword"].orEmpty(), { byPassword = !byPassword; problem = "" },
                Modifier.fillMaxWidth(), kind = ButtonKind.Quiet, focusKey = "ask-other-way",
            )
        }
        WittyButton(s["back"].orEmpty(), { asking = false; problem = "" }, Modifier.fillMaxWidth(), kind = ButtonKind.Quiet, focusKey = "ask-back")
    }
}
