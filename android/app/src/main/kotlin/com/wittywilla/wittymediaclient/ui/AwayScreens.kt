// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRowScope
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.p2p.PeerWay
import kotlinx.coroutines.launch

// "From away", under You, This device: how this device reaches its server when it isn't at home, in the same words
// and rows as Apple's apps (AwayViews.swift there). Shown only where the connector library is in the app.
@OptIn(ExperimentalLayoutApi::class)
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
    // The one thing to do about it: start again where it's turned off, or stop where it's kept.
    val act: @Composable FlowRowScope.() -> Unit = {
        if (server != null) {
            if (off) {
                WittyButton(s["awayStart"].orEmpty(), {
                    peers.startAway(server)
                    nav.learnAwayNow()
                    stamp++
                }, kind = ButtonKind.Primary, tall = true, focusKey = "away-start")
            } else if (kept != null) {
                WittyButton(s["awayStop"].orEmpty(), { asking = true }, kind = ButtonKind.Destructive, tall = true, focusKey = "away-stop")
            }
        }
    }
    // Design 2's page: the connection as rows, what that means, and the action.
    DesignScreen(
        s["rowAway"].orEmpty(), nav::pop, eyebrow = s["youTab"].orEmpty(), lead = s["awayHint"].orEmpty(), tag = "away",
        actions = if (server != null && (off || kept != null)) act else null,
    ) {
        DesignSection("") {
            DesignRow(s["awayNow"].orEmpty(), value = now, sub = trouble, on = way is PeerWay.Away && trouble.isEmpty(), focusKey = "away-now")
            DesignRow(s["rowAway"].orEmpty(), value = status, on = kept != null && !off, focusKey = "away-state")
            if (kept != null && !off && deviceId.isNotEmpty()) DesignRow(s["awayDevice"].orEmpty(), value = "…" + deviceId.takeLast(8), focusKey = "away-device")
        }
        DesignNote(
            s[if (off) "awayOffHint" else if (kept != null) "awayReadyHint" else "awaySetUpHint"].orEmpty(),
            Modifier.padding(top = LocalDesignSizes.current.gap), tone = true,
        )
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
    DesignScreen(
        s["joinAwayTitle"].orEmpty(), nav::pop, lead = s["joinAwayHint"].orEmpty(), tag = "join-away",
        actions = {
            if (failed) WittyButton(s["pairNew"].orEmpty(), { attempt++ }, kind = ButtonKind.Primary, tall = true, requestFocus = true, focusKey = "join-new")
            WittyButton(s["back"].orEmpty(), nav::pop, kind = ButtonKind.Secondary, tall = true, requestFocus = !failed, focusKey = "join-back")
        },
    ) {
        val ds = LocalDesignSizes.current
        DesignSection("") {
            if (code.isNotEmpty() && !failed) {
                Text(
                    code, color = MaterialTheme.colorScheme.onSurface, fontSize = ds.title * 1.15f, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace,
                    modifier = Modifier
                        .clip(metrics.corner(10))
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = ds.gap * 2.4f, vertical = ds.gap * 1.2f)
                        .semantics { contentDescription = code.toList().joinToString(" ") },
                )
            }
            // Said aloud as it changes: waiting, found, or what went wrong.
            DesignNote(words, busy = !failed, error = failed)
        }
    }
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
