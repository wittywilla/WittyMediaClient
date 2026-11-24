// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.Manifest
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.data.fill
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.FoundServer
import com.wittywilla.wittymediaclient.net.PairRefusal
import com.wittywilla.wittymediaclient.net.PeerRules
import com.wittywilla.wittymediaclient.net.ServerFinder
import com.wittywilla.wittymediaclient.net.WebJoin
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.p2p.PeerWay
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

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
        // The canvas's Invite and Join: a link (and its QR code) that brings another device in, and the code a TV
        // away from home shows, typed in here. Both sign the other device in as this account.
        if (server != null) AwayInvite(nav, s)
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

// "Join with a link or code", from the list of servers. A phone, tablet or Chromebook types the code a server shows
// under Connect a device, or pastes its invite link (its QR code is Scan a QR code, beside this). A TV has no
// keyboard to speak of: it shows a code of its own, which someone signed in types on a phone (You, From away).
@Composable
fun JoinAwayScreen(nav: Nav, s: Map<String, String>) {
    if (LocalMetrics.current.tv) JoinAwayTvScreen(nav, s) else JoinWithCodeOrLinkScreen(nav, s)
}

// How long Enter a code waits for this network's servers to be found, when none have been yet.
private const val FIND_FOR_CODE_MS = 10_000L

@Composable
private fun JoinWithCodeOrLinkScreen(nav: Nav, s: Map<String, String>) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // The servers on this network, which a code is asked of: looked for only while this screen is open.
    var found by remember { mutableStateOf(emptyList<FoundServer>()) }
    DisposableEffect(Unit) {
        val finder = ServerFinder(context) { found = it }
        finder.start()
        onDispose { finder.stop() }
    }
    var code by remember { mutableStateOf("") }
    var codeProblem by remember { mutableStateOf("") }
    var asking by remember { mutableStateOf(false) }
    fun askCode() {
        if (asking || code.isBlank()) return
        if (WebJoin.clean(code).isEmpty()) {
            codeProblem = s["errCodeFormat"].orEmpty()
            return
        }
        asking = true
        codeProblem = ""
        scope.launch {
            // Servers on this network answer a few seconds after the screen opens: a code typed quickly waits for them.
            if (found.isEmpty()) withTimeoutOrNull(FIND_FOR_CODE_MS) { while (found.isEmpty()) delay(250) }
            nav.enterCode(code, found.map { it.url })?.let { codeProblem = it }
            asking = false
        }
    }
    var link by remember { mutableStateOf("") }
    var linkProblem by remember { mutableStateOf("") }
    var joining by remember { mutableStateOf(false) }
    fun joinLink() {
        if (joining) return
        val typed = link.trim()
        // A code pasted where the link goes: asked as a code.
        if (PeerRules.invite(typed) == null && WebJoin.looksLikeCode(typed)) {
            code = typed
            link = ""
            askCode()
            return
        }
        val invite = PeerRules.invite(typed)
        if (invite == null) {
            linkProblem = s["joinPasteNotInvite"].orEmpty()
            return
        }
        joining = true
        scope.launch {
            nav.joinInvite(invite)?.let { linkProblem = it }
            joining = false
        }
    }
    DesignScreen(
        s["inviteTitle"].orEmpty(), nav::pop, eyebrow = s["remoteTitle"].orEmpty(), tag = "join-code-or-link",
        actions = { WittyButton(s["back"].orEmpty(), nav::pop, kind = ButtonKind.Secondary, tall = true, focusKey = "join-back") },
    ) {
        DesignSection(s["codeEnterTitle"].orEmpty()) {
            DesignNote(s["codeEnterHint"].orEmpty())
            WittyField(code, { code = it.take(12); codeProblem = "" }, s["codeEnterLabel"].orEmpty(), imeAction = ImeAction.Go, onAction = ::askCode, isError = codeProblem.isNotEmpty(), maxLength = 12)
            // Said aloud as it changes: looking, or what went wrong, naming the step.
            DesignNote(if (asking) s["codeLooking"].orEmpty() else codeProblem, busy = asking, error = !asking && codeProblem.isNotEmpty())
            DesignActions {
                WittyButton(s["connect"].orEmpty(), ::askCode, kind = ButtonKind.Primary, busy = asking, enabled = code.isNotBlank(), focusKey = "join-code")
            }
        }
        DesignSection(s["joinPasteTitle"].orEmpty()) {
            DesignNote(s["linkHint"].orEmpty())
            WittyField(link, { link = it; linkProblem = "" }, s["joinPasteField"].orEmpty(), kind = FieldKind.Address, imeAction = ImeAction.Go, onAction = ::joinLink, isError = linkProblem.isNotEmpty())
            DesignNote(if (joining) s["awayConnecting"].orEmpty() else linkProblem, busy = joining, error = !joining && linkProblem.isNotEmpty())
            DesignActions {
                WittyButton(s["joinPasteButton"].orEmpty(), ::joinLink, kind = ButtonKind.Primary, busy = joining, enabled = link.isNotBlank(), focusKey = "join-link")
            }
        }
    }
}

// On a TV: for a device that has never been at home with its server. It shows a code; someone signed in types it
// on a phone (You, From away, A TV that shows a code); the server is found, connected to, and signed in to.
@Composable
private fun JoinAwayTvScreen(nav: Nav, s: Map<String, String>) {
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
    // An invite link pasted in, from the server's Remote Access page.
    val scope = rememberCoroutineScope()
    var link by remember { mutableStateOf("") }
    var linkProblem by remember { mutableStateOf("") }
    var joining by remember { mutableStateOf(false) }
    fun joinLink() {
        if (joining) return
        val invite = PeerRules.invite(link.trim())
        if (invite == null) { linkProblem = s["joinPasteNotInvite"].orEmpty(); return }
        joining = true
        scope.launch {
            nav.joinInvite(invite)?.let { linkProblem = it }
            joining = false
        }
    }
    DesignScreen(
        s["joinAwayTitle"].orEmpty(), nav::pop, eyebrow = s["remoteTitle"].orEmpty(), lead = s["joinAwayHint"].orEmpty(), tag = "join-away",
        actions = {
            if (failed) WittyButton(s["pairNew"].orEmpty(), { attempt++ }, kind = ButtonKind.Primary, tall = true, requestFocus = true, focusKey = "join-new")
            WittyButton(s["back"].orEmpty(), nav::pop, kind = ButtonKind.Secondary, tall = true, requestFocus = !failed, focusKey = "join-back")
        },
    ) {
        val ds = LocalDesignSizes.current
        // A phone, tablet or Chromebook can take an invite link instead: pasted here, it joins at once. A TV shows the
        // code alone, typed in on a phone or computer that's signed in.
        if (!metrics.tv) {
            DesignSection(s["joinPasteTitle"].orEmpty()) {
                DesignNote(s["joinPasteHint"].orEmpty())
                WittyField(link, { link = it; linkProblem = "" }, s["joinPasteField"].orEmpty(), kind = FieldKind.Address, imeAction = ImeAction.Go, onAction = ::joinLink, isError = linkProblem.isNotEmpty())
                DesignNote(linkProblem, error = true)
                DesignActions {
                    WittyButton(s["joinPasteButton"].orEmpty(), ::joinLink, kind = ButtonKind.Primary, busy = joining, enabled = link.isNotBlank(), focusKey = "join-link")
                }
            }
        }
        DesignSection(if (metrics.tv) "" else s["joinCodeSection"].orEmpty()) {
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
            // The same code as a QR code, holding only the code: a phone signed in to the server reads it under You, From away,
            // A TV that shows a code, so nobody types it.
            if (code.isNotEmpty() && !failed) QrCard(code, s["joinCodeQr"].orEmpty())
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AwayInvite(nav: Nav, s: Map<String, String>) {
    val api = nav.app.api
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val metrics = LocalMetrics.current
    var link by remember { mutableStateOf("") }
    var making by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    var invitePassword by remember { mutableStateOf("") }
    var inviteOtp by remember { mutableStateOf("") }
    var askPassword by remember { mutableStateOf(false) }
    var askOtp by remember { mutableStateOf(false) }
    var inviteProblem by remember { mutableStateOf("") }
    fun makeInvite() {
        if (making) return
        making = true
        inviteProblem = ""
        scope.launch {
            try {
                link = api.p2pInvite(invitePassword, inviteOtp)
                invitePassword = ""; inviteOtp = ""; askPassword = false; askOtp = false; copied = false
            } catch (e: ApiError) {
                when {
                    PairRefusal.read(e.body).needsPassword && !askPassword -> askPassword = true
                    e.twoFactor -> askOtp = true
                    else -> inviteProblem = e.message.orEmpty()
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                inviteProblem = problemWords(e, s["errUnreachable"].orEmpty())
            }
            making = false
        }
    }
    DesignSection(s["awayInviteTitle"].orEmpty()) {
        DesignNote(s["awayInviteHint"].orEmpty())
        if (link.isNotEmpty()) {
            QrCard(link, s["awayInviteQr"].orEmpty())
            DesignNote(s["awayInviteReady"].orEmpty(), tone = true)
            DesignRow(link, focusKey = "invite-link")
            DesignChips {
                if (!metrics.tv) {
                    DesignChip(s["awayInviteShare"].orEmpty(), {
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link)
                        runCatching { context.startActivity(Intent.createChooser(send, s["awayInviteShare"].orEmpty())) }
                    }, on = true, focusKey = "invite-share")
                }
                DesignChip(if (copied) s["awayInviteCopied"].orEmpty() else s["awayInviteCopy"].orEmpty(), { clipboard.setText(AnnotatedString(link)); copied = true }, focusKey = "invite-copy")
                DesignChip(s["awayInviteMake"].orEmpty(), ::makeInvite, focusKey = "invite-again")
            }
        } else {
            if (askPassword) {
                DesignNote(s["awayAdminPassword"].orEmpty(), tone = true)
                WittyField(invitePassword, { invitePassword = it }, s["awayPassword"].orEmpty(), kind = FieldKind.Password, imeAction = ImeAction.Go, onAction = ::makeInvite)
                if (askOtp) WittyField(inviteOtp, { inviteOtp = it }, s["awayTwoFactor"].orEmpty(), imeAction = ImeAction.Go, onAction = ::makeInvite)
            }
            DesignNote(inviteProblem, error = true)
            DesignActions {
                WittyButton(s["awayInviteMake"].orEmpty(), ::makeInvite, kind = ButtonKind.Primary, busy = making, icon = Symbols.Qr, focusKey = "invite-make")
            }
        }
    }

    var code by remember { mutableStateOf("") }
    var codePassword by remember { mutableStateOf("") }
    var codeOtp by remember { mutableStateOf("") }
    var codeAskOtp by remember { mutableStateOf(false) }
    var signing by remember { mutableStateOf(false) }
    var codeSaid by remember { mutableStateOf("") }
    var codeProblem by remember { mutableStateOf("") }
    // The TV's code read with the camera, on a phone or tablet that has one.
    var scanning by remember { mutableStateOf(false) }
    val canScan = remember { !nav.app.isTv && hasCamera(context) }
    val cameraAsk = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) scanning = true else codeProblem = s["remoteCameraDenied"].orEmpty()
    }
    fun signIn() {
        if (signing || code.isBlank() || codePassword.isEmpty()) return
        signing = true
        codeProblem = ""; codeSaid = ""
        scope.launch {
            try {
                api.p2pJoin(code.trim(), codePassword, codeOtp)
                codeSaid = fill(s["awayCodeDone"], "code" to code.trim().uppercase())
                code = ""; codePassword = ""; codeOtp = ""; codeAskOtp = false
            } catch (e: ApiError) {
                if (e.twoFactor) codeAskOtp = true else codeProblem = e.message.orEmpty()
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                codeProblem = problemWords(e, s["errUnreachable"].orEmpty())
            }
            signing = false
        }
    }
    DesignSection(s["awayCodeTitle"].orEmpty()) {
        DesignNote(s["awayCodeHint"].orEmpty())
        if (scanning) {
            QrScanner(s["awayCodeScanning"].orEmpty(), { text ->
                val read = text.trim().uppercase()
                if (PeerRules.isJoinCode(read)) { code = read; scanning = false; codeProblem = "" } else codeProblem = s["awayCodeNotOurs"].orEmpty()
            }, onFailed = { scanning = false; codeProblem = s["approveCameraFailed"].orEmpty() })
        }
        if (canScan) {
            DesignChips {
                DesignChip(s[if (scanning) "approveTypeInstead" else "awayCodeScan"].orEmpty(), {
                    codeProblem = ""
                    when {
                        scanning -> scanning = false
                        cameraAllowed(context) -> scanning = true
                        else -> cameraAsk.launch(Manifest.permission.CAMERA)
                    }
                }, on = !scanning, focusKey = "code-scan")
            }
        }
        WittyField(code, { code = it.take(12); codeSaid = "" }, s["awayCodeField"].orEmpty(), maxLength = 12)
        WittyField(codePassword, { codePassword = it }, s["awayPassword"].orEmpty(), kind = FieldKind.Password, imeAction = ImeAction.Go, onAction = ::signIn)
        if (codeAskOtp) WittyField(codeOtp, { codeOtp = it }, s["awayTwoFactor"].orEmpty(), imeAction = ImeAction.Go, onAction = ::signIn)
        DesignNote(codeProblem, error = true)
        DesignNote(codeSaid, tone = true)
        DesignActions {
            WittyButton(s["awayCodeSignIn"].orEmpty(), ::signIn, kind = ButtonKind.Secondary, busy = signing, enabled = code.isNotBlank() && codePassword.isNotEmpty(), focusKey = "code-sign-in")
        }
    }
}

