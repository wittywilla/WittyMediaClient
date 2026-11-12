// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.p2p.PeerWay
import kotlinx.coroutines.launch

// "From away", under You, This device: how this device reaches its server when it isn't at home, in the same words
// and rows as Apple's apps (AwayViews.swift there). Shown only where the connector library is in the app.
@Composable
fun AwayScreen(nav: Nav, s: Map<String, String>) {
    val peers = nav.app.peers
    val scope = rememberCoroutineScope()
    val server = nav.server
    var stamp by remember { mutableIntStateOf(0) }
    var asking by remember { mutableStateOf(false) }
    var deviceId by remember { mutableStateOf("") }
    LaunchedEffect(stamp) { deviceId = peers.deviceId() }
    val kept = remember(server, stamp) { server?.let(peers::info) }
    val off = remember(server, stamp) { server?.let(peers::isOff) == true }
    val status = when {
        off -> s["awayOff"].orEmpty()
        kept != null -> s["awayReady"].orEmpty()
        else -> s["awayNotSetUp"].orEmpty()
    }
    val way = peers.way
    val now = when (way) {
        is PeerWay.Away -> way.state.words
        PeerWay.Home -> s["awayAtHomeNow"].orEmpty()
        PeerWay.None -> if (server != null && !com.wittywilla.wittymediaclient.net.PeerRoute.active) s["awayAtHomeNow"].orEmpty() else s["awayNoWay"].orEmpty()
    }
    val trouble = (way as? PeerWay.Away)?.state?.takeIf { !it.connected }?.error.orEmpty()
    SettingsPage(nav, s["rowAway"].orEmpty(), s["awayHint"].orEmpty()) {
        GroupedList(
            "",
            listOfNotNull(
                GroupRow(s["awayNow"].orEmpty(), value = now, detail = trouble, focusKey = "away-now", requestFocus = true),
                GroupRow(s["rowAway"].orEmpty(), value = status, focusKey = "away-state"),
                if (kept != null && !off && deviceId.isNotEmpty()) GroupRow(s["awayDevice"].orEmpty(), value = "…" + deviceId.takeLast(8), focusKey = "away-device") else null,
            ),
        )
        Text(
            s[if (off) "awayOffHint" else if (kept != null) "awayReadyHint" else "awaySetUpHint"].orEmpty(),
            color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary,
        )
        if (server != null) {
            when {
                off -> WittyButton(s["awayStart"].orEmpty(), {
                    peers.startAway(server)
                    nav.learnAwayNow()
                    stamp++
                }, Modifier.fillMaxWidth(), tall = true, focusKey = "away-start")
                kept != null -> WittyButton(s["awayStop"].orEmpty(), { asking = true }, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, tall = true, focusKey = "away-stop")
            }
        }
    }
    if (asking && server != null) {
        Confirm(
            s["awayStopConfirm"].orEmpty(), s["awayStop"].orEmpty(), s["cancel"].orEmpty(),
            onYes = {
                asking = false
                scope.launch {
                    val lost = peers.stopAway(server, nav.app.api.token)
                    stamp++
                    if (lost) nav.lostFromAway()
                }
            },
            onNo = { asking = false },
            title = s["rowAway"].orEmpty(),
        )
    }
}

// "Join from away", from the list of servers: for a device that has never been at home with its server. It shows a
// code; someone signed in types it into the server; the server is found, connected to, and signed in to.
@Composable
fun JoinAwayScreen(nav: Nav, s: Map<String, String>) {
    val peers = nav.app.peers
    val metrics = LocalMetrics.current
    var attempt by remember { mutableIntStateOf(0) }
    var code by remember { mutableStateOf("") }
    var words by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(attempt) {
        failed = false
        code = ""
        words = s["joinAwayWaiting"].orEmpty()
        val made = peers.newJoinCode()
        if (made == null) {
            words = s["awayNotHere"].orEmpty()
            failed = true
            return@LaunchedEffect
        }
        code = made
        val answer = peers.joinByCode(made)
        when {
            answer == null -> { words = s["joinAwayExpired"].orEmpty(); failed = true }
            !answer.ok -> { words = if (answer.reason == "unreachable") s["errAwayFailed"].orEmpty() else s["joinAwayRefused"].orEmpty(); failed = true }
            else -> {
                words = s["joinAwayFinding"].orEmpty()
                nav.joinedFromAway(answer)?.let { problem -> words = problem; failed = true }
            }
        }
    }
    SignInLayout(
        onBack = nav::pop,
        words = {
            SignInHeading(s["joinAwayTitle"].orEmpty(), detail = s["joinAwayHint"].orEmpty())
        },
        actions = {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                if (code.isNotEmpty() && !failed) {
                    Text(
                        code, color = MaterialTheme.colorScheme.onBackground, fontSize = if (metrics.tv) 72.sp else 40.sp, fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                    )
                }
                Note(words, busy = !failed, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                if (failed) WittyButton(s["pairNew"].orEmpty(), { attempt++ }, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, requestFocus = true, focusKey = "join-new")
                WittyButton(s["back"].orEmpty(), nav::pop, Modifier.fillMaxWidth(), tall = true, requestFocus = !failed, focusKey = "join-back")
            }
        },
    )
}

// Whether this server is kept for reaching from away (You's row value).
fun awayWords(nav: Nav, s: Map<String, String>, server: SavedServer?): String {
    val peers = nav.app.peers
    if (server == null) return ""
    return when {
        peers.isOff(server) -> s["awayOff"].orEmpty()
        peers.way is PeerWay.Away -> (peers.way as PeerWay.Away).state.words
        peers.info(server) != null -> s["awayReady"].orEmpty()
        else -> s["awayNotSetUp"].orEmpty()
    }
}
