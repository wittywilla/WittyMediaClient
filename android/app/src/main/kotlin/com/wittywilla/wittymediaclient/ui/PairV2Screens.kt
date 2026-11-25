// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.Manifest
import android.os.SystemClock
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.em
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.PAIR_QR_FEATURE
import com.wittywilla.wittymediaclient.net.PairApproval
import com.wittywilla.wittymediaclient.net.PairAsk
import com.wittywilla.wittymediaclient.net.PairInvite
import com.wittywilla.wittymediaclient.net.PairPhase
import com.wittywilla.wittymediaclient.net.PairQr
import com.wittywilla.wittymediaclient.net.PairRefusal
import com.wittywilla.wittymediaclient.net.PairRules
import com.wittywilla.wittymediaclient.net.PairSession
import com.wittywilla.wittymediaclient.net.Profile
import com.wittywilla.wittymediaclient.net.pairApproveByCode
import com.wittywilla.wittymediaclient.net.pairAskByCode
import com.wittywilla.wittymediaclient.net.pairInviteAs
import com.wittywilla.wittymediaclient.net.pairPhaseAfter
import com.wittywilla.wittymediaclient.net.pairV2Approve
import com.wittywilla.wittymediaclient.net.pairV2Deny
import com.wittywilla.wittymediaclient.net.pairV2Info
import com.wittywilla.wittymediaclient.net.pairV2Pin
import com.wittywilla.wittymediaclient.net.pairV2Poll
import com.wittywilla.wittymediaclient.net.pairV2Start
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.IOException

// Signing a device in with a QR code and a PIN that changes (docs/CLIENT-API.md, "With a QR code and a PIN"). Two
// screens: the one a device shows while it waits to be signed in, and the one an adult already signed in uses to
// answer it, by scanning the code or typing the device's letters. A server without `pair-qr` gets the older screens.

// What a camera read, as something to ask this app's own server about: a device's QR code, or the web address a
// device shows for phones without the app (…/pair?code=ABCD-EFGH), whose letters are all that is used of it.
sealed interface Scanned {
    data class Session(val qr: PairQr) : Scanned
    data class Letters(val code: String) : Scanned
    data object OtherServer : Scanned
    data object NotACode : Scanned
}

fun readScanned(text: String, serverId: String, base: String): Scanned {
    PairRules.parseQr(text)?.let { return if (PairRules.fitsServer(it, serverId, base)) Scanned.Session(it) else Scanned.OtherServer }
    val url = text.trim().toHttpUrlOrNull() ?: return Scanned.NotACode
    if (url.encodedPath != "/pair") return Scanned.NotACode
    val code = tvCodeTyped(url.queryParameter("code").orEmpty())
    return if (code.length == TV_CODE_LENGTH) Scanned.Letters(code) else Scanned.NotACode
}

// The device's side. `older` is the screen for a server without the QR code and PIN.
@Composable
fun PairWithQr(nav: Nav, s: Map<String, String>, onBack: () -> Unit, onUsePassword: () -> Unit, older: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    var useOlder by remember { mutableStateOf(false) }
    // The server's features, once read, say which; until then it's tried, and a server that has no such route says so.
    if (useOlder || (nav.features.isNotEmpty() && !nav.has(PAIR_QR_FEATURE))) {
        older()
        return
    }
    var round by remember { mutableIntStateOf(0) }
    var session by remember { mutableStateOf<PairSession?>(null) }
    var pin by remember { mutableStateOf("") }
    var leftAtAnswer by remember { mutableIntStateOf(0) }
    var answeredAt by remember { mutableLongStateOf(0L) }
    var phase by remember { mutableStateOf(PairPhase.Starting) }
    var problem by remember { mutableStateOf("") }
    var lostContact by remember { mutableStateOf(false) }
    var forCamera by remember { mutableStateOf(false) }

    LaunchedEffect(round) {
        session = null
        pin = ""
        problem = ""
        lostContact = false
        phase = PairPhase.Starting
        val api = nav.app.api
        try {
            // The sign-in this ends in is kept with the server's key, so the server proves it's itself first.
            nav.server?.let { nav.clearToSend(it) }?.let {
                problem = it
                phase = PairPhase.Failed
                return@LaunchedEffect
            }
            val start = try {
                api.pairV2Start(nav.app.deviceName, nav.app.platformName)
            } catch (e: ApiError) {
                when (e.status) {
                    404, 405 -> { useOlder = true; return@LaunchedEffect }
                    429 -> { phase = PairPhase.Busy; problem = s["pairBusy"].orEmpty(); return@LaunchedEffect }
                    else -> throw e
                }
            }
            session = start
            pin = start.pin
            leftAtAnswer = PairRules.secondsLeftAtAnswer(start.pinExpiresAt, 0, start.period)
            answeredAt = SystemClock.elapsedRealtime()
            phase = PairPhase.Waiting
            val began = SystemClock.elapsedRealtime()
            coroutineScope {
                // The PIN, asked for again as each one ends. The first ask also says how long this one has left.
                val pins = launch {
                    var failures = 0
                    while (true) {
                        val got = try {
                            api.pairV2Pin(start.sessionId, start.deviceSecret)
                        } catch (_: IOException) {
                            delay(PairRules.retryWaitSec(failures++) * 1000L)
                            continue
                        } ?: break // no longer waiting for a PIN: the poll says why
                        failures = 0
                        pin = got.first.pin
                        leftAtAnswer = PairRules.secondsLeftAtAnswer(got.first.pinExpiresAt, got.second, got.first.period)
                        answeredAt = SystemClock.elapsedRealtime()
                        delay(PairRules.nextPinInMs(leftAtAnswer))
                    }
                }
                var wait = start.intervalSec.coerceAtLeast(1)
                var failures = 0
                var ended: PairPhase? = null
                var token = ""
                while (ended == null) {
                    delay(wait * 1000L)
                    // The server forgets a session after its five minutes; so does this, if the server can't be asked.
                    if (SystemClock.elapsedRealtime() - began > (start.expiresInSec + EXPIRY_SLACK_SEC) * 1000L) { ended = PairPhase.Expired; break }
                    val (poll, status) = try {
                        api.pairV2Poll(start.sessionId, start.deviceSecret)
                    } catch (_: IOException) {
                        // A network that blinks is no reason to give up on a code that's still good.
                        lostContact = true
                        wait = PairRules.retryWaitSec(failures++)
                        continue
                    }
                    lostContact = false
                    failures = 0
                    val now = pairPhaseAfter(poll.status, status, poll.token.isNotEmpty())
                    if (now == PairPhase.Waiting) wait = PairRules.pollWaitSec(wait, poll.status, poll.intervalSec) else { ended = now; token = poll.token }
                }
                pins.cancel()
                session = null
                if (ended == PairPhase.Approved) {
                    nav.signedIn(token)
                } else {
                    phase = ended ?: PairPhase.Failed
                    problem = s[
                        when (ended) {
                            PairPhase.Denied -> "pairDenied"
                            PairPhase.Locked -> "pairLocked"
                            PairPhase.Expired -> "pairExpired"
                            else -> "errInvalid"
                        },
                    ].orEmpty()
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            session = null
            phase = PairPhase.Failed
            problem = problemWords(e, s["errLost"].orEmpty())
        }
    }

    val showing = session
    val now by produceState(SystemClock.elapsedRealtime(), showing != null) {
        while (showing != null) {
            value = SystemClock.elapsedRealtime()
            delay(TICK_MS)
        }
    }
    val ended = showing == null && phase != PairPhase.Starting
    val actionButtons: @Composable () -> Unit = {
        if (ended) {
            if (phase == PairPhase.Busy) WittyButton(s["usePassword"].orEmpty(), onUsePassword, kind = ButtonKind.Primary, tall = true, takeFocus = true, focusKey = "pair-password", modifier = if (metrics.tv) Modifier.fillMaxWidth() else Modifier)
            else WittyButton(s["pairNew"].orEmpty(), { round++ }, kind = ButtonKind.Primary, tall = true, takeFocus = true, focusKey = "pair-new", modifier = if (metrics.tv) Modifier.fillMaxWidth() else Modifier)
        }
        val server = nav.server
        if (server != null && server.publicKey.isNotEmpty()) {
            WittyButton(s["codeTitle"].orEmpty(), { nav.push(Route.Code(server)) }, kind = ButtonKind.Secondary, focusKey = "typed-code", modifier = if (metrics.tv) Modifier.fillMaxWidth() else Modifier)
        }
        if (phase != PairPhase.Busy) WittyButton(s["usePassword"].orEmpty(), onUsePassword, kind = ButtonKind.Secondary, requestFocus = showing != null, focusKey = "use-password", modifier = if (metrics.tv) Modifier.fillMaxWidth() else Modifier)
        WittyButton(s["changeServer"].orEmpty(), nav::changeServer, kind = ButtonKind.Quiet, focusKey = "change-server")
    }
    val pinPart: @Composable () -> Unit = {
        DesignSection("") {
            if (showing != null) {
                val seconds = PairRules.secondsLeft(leftAtAnswer, now - answeredAt)
                val share = PairRules.share(leftAtAnswer, now - answeredAt, showing.period)
                PinCard(s, pin, seconds, share)
                val address = remember(showing.approvePath) { runCatching { nav.app.api.mediaUrl(showing.approvePath) }.getOrDefault("") }
                DesignNote(s["pairQrOrType"].orEmpty().replace("{code}", showing.code).replace("{address}", address))
                DesignNote(s[if (lostContact) "errLost" else "pairWaiting"].orEmpty(), busy = true)
            } else if (!ended) {
                Spinner(scheme.onSurfaceVariant, metrics.u(if (metrics.tv) 40 else 24))
            }
            DesignNote(problem, error = true)
        }
    }
    val qrPart: @Composable () -> Unit = {
        if (showing != null) {
            // The app's own code carries the server's ID and a check, for the app to scan. A phone without the
            // app reads the web address instead, with its own camera, and types the PIN on the page it opens.
            val web = remember(showing.approveUrl, showing.approvePath) {
                runCatching { showing.approveUrl.ifEmpty { nav.app.api.mediaUrl(showing.approvePath) } }.getOrDefault("")
            }
            val camera = forCamera && web.isNotEmpty()
            DesignSection("") {
                QrCard(if (camera) web else showing.qr, s[if (camera) "pairQrScanCamera" else "pairQrScanApp"].orEmpty())
                if (web.isNotEmpty()) {
                    DesignChips {
                        DesignChip(s[if (camera) "pairQrUseApp" else "pairQrUseCamera"].orEmpty(), { forCamera = !forCamera }, focusKey = "pair-qr-kind")
                    }
                }
            }
        }
    }
    val body: @Composable () -> Unit = { pinPart(); qrPart() }
    if (metrics.tv) {
        // On a TV the page is one centred column, as Who's watching is: the lockup, the title, the PIN and the code to
        // scan, then the other ways in stacked under them. Nothing hugs the left edge or runs off the top.
        val widthDp = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp.toFloat()
        androidx.compose.runtime.CompositionLocalProvider(LocalDesignSizes provides DesignSizes.of(metrics, widthDp)) {
            TvWhoPage(
                s["pairQrTitle"].orEmpty(),
                top = { Lockup(nav.brandName, nav.brandLogo) },
                problem = {
                    if (showing != null) Text(s["pairQrHint"].orEmpty(), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(bottom = metrics.u(12)).widthIn(max = metrics.u(900)))
                },
                profiles = {
                    // The PIN and its notes beside the code to scan, so the other ways in stay on screen under them.
                    Row(Modifier.widthIn(max = metrics.u(1300)), horizontalArrangement = Arrangement.spacedBy(metrics.u(56))) {
                        Column(Modifier.weight(1f)) { pinPart() }
                        Column(Modifier.widthIn(max = metrics.u(380))) { qrPart() }
                    }
                },
                actions = { actionButtons() },
                foot = {},
                onBack = onBack,
            )
        }
        return
    }
    // Design 2's page under this server's lockup: the PIN and the code to scan, then the other ways in.
    DesignScreen(
        s["pairQrTitle"].orEmpty(), onBack, lead = if (showing != null) s["pairQrHint"].orEmpty() else "", tag = "pairing", centred = true,
        top = { Lockup(nav.brandName, nav.brandLogo) },
        actions = { actionButtons() },
    ) {
        body()
    }
}

private const val TICK_MS = 250L
private const val EXPIRY_SLACK_SEC = 15

// The PIN, large enough to read across a room, with a ring that empties as it runs out, in the page's panel. It is
// read aloud as its digits when asked for, and not each time it changes: every thirty seconds would be all anyone heard.
@Composable
private fun PinCard(s: Map<String, String>, pin: String, seconds: Int, share: Float, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    val ds = LocalDesignSizes.current
    val scheme = MaterialTheme.colorScheme
    val spoken = s["pairPinSpoken"].orEmpty().replace("{pin}", pin.toList().joinToString(" ")).replace("{n}", seconds.toString())
    Row(
        modifier
            .clip(metrics.corner(10))
            .background(scheme.surface)
            .padding(horizontal = ds.gap * 2.4f, vertical = ds.gap * 1.2f)
            .clearAndSetSemantics { contentDescription = spoken },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(ds.gap * 2),
    ) {
        Column {
            Text(s["pairPinLabel"].orEmpty().uppercase(), color = LocalExtraColours.current.accentText, fontSize = ds.tiny, fontWeight = FontWeight.Bold, letterSpacing = 0.08.em)
            Text(
                PairRules.shownPin(pin), color = scheme.onSurface,
                style = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = ds.title * 1.15f, letterSpacing = 0.12.em),
            )
        }
        val ring = metrics.u(if (metrics.tv) 72 else 44)
        val accent = scheme.primary
        val track = scheme.outline
        Box(Modifier.size(ring), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(ring)) {
                val stroke = this.size.minDimension * 0.1f
                val inset = stroke / 2
                val arc = Size(this.size.width - stroke, this.size.height - stroke)
                drawArc(track, 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(stroke))
                drawArc(accent, -90f, 360f * share, false, Offset(inset, inset), arc, style = Stroke(stroke, cap = StrokeCap.Round))
            }
            Text(seconds.toString(), color = scheme.onSurface, fontSize = ds.small, fontWeight = FontWeight.Bold)
        }
    }
}

private enum class ScanStep { Off, Why, Denied, On }

// The approver's side: You → Sign in a TV. Scan the device's code or type its letters, see what is asking, choose
// who it signs in as, type the PIN it shows, and say yes or no. Or get six digits for the device to type instead.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ApproveDeviceScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val api = nav.app.api
    val me = nav.me ?: run { Screen { Loading() }; return }
    val adult = me.isAdmin || me.kind == "adult"
    var code by remember { mutableStateOf("") }
    var scanned by remember { mutableStateOf<PairQr?>(null) }
    var asking by remember { mutableStateOf<PairAsk?>(null) }
    var chosen by remember { mutableStateOf<Long?>(null) }
    var faces by remember { mutableStateOf(emptyMap<Long, Profile>()) }
    var pin by remember { mutableStateOf("") }
    var needsPassword by remember { mutableStateOf(false) }
    var twoFactor by remember { mutableStateOf(me.twoFactor) }
    var password by remember { mutableStateOf("") }
    var otp by remember { mutableStateOf("") }
    var invite by remember { mutableStateOf<PairInvite?>(null) }
    var inviting by remember { mutableStateOf(false) }
    var outcome by remember { mutableStateOf("") }
    var good by remember { mutableStateOf(false) }
    var wrong by remember { mutableIntStateOf(0) }
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var waits by remember { mutableIntStateOf(0) }
    var waitSec by remember { mutableIntStateOf(0) }
    val waiting = rememberWait(waitSec, waits)
    var scan by remember { mutableStateOf(ScanStep.Off) }
    // No camera on a TV, and none offered on a device without one: typing the letters is always there.
    val canScan = remember { !nav.app.isTv && hasCamera(context) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        scan = if (granted) ScanStep.On else ScanStep.Denied
    }
    // The pairing answer has usernames only; the profile list has the names and pictures people chose.
    LaunchedEffect(Unit) { runCatching { api.profiles().profiles }.getOrNull()?.let { list -> faces = list.associateBy { it.id } } }

    fun reset() {
        code = ""; scanned = null; asking = null; invite = null; inviting = false; outcome = ""; problem = ""
        pin = ""; password = ""; otp = ""; needsPassword = false; scan = ScanStep.Off
    }
    fun finish(words: String, ok: Boolean) {
        reset()
        good = ok
        outcome = words
    }
    // What a refusal means here: a wrong PIN is typed again, a wanted password is asked for, a session that's over ends.
    fun refused(e: ApiError) {
        val why = PairRefusal.read(e.body)
        when {
            e.status == 429 -> { waitSec = e.retryAfterSec; waits++; problem = problemWords(e, s["errLost"].orEmpty()) }
            why.needsPassword -> { needsPassword = true; twoFactor = twoFactor || why.twoFactor; problem = "" }
            why.over -> finish(problemWords(e, s["errLost"].orEmpty()), false)
            why.wrongPin || why.reason == "bad-check" -> {
                pin = ""
                wrong++
                problem = problemWords(e, s["errLost"].orEmpty()) + if (why.triesLeft >= 0) " " + s[if (why.triesLeft == 1) "pairTryLeft" else "pairTriesLeft"].orEmpty().replace("{n}", why.triesLeft.toString()) else ""
            }
            else -> { password = ""; otp = ""; wrong++; problem = problemWords(e, s["errLost"].orEmpty()) }
        }
    }
    fun run(block: suspend () -> Unit) {
        if (busy || waiting > 0) return
        busy = true
        problem = ""
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                if (!nav.handleExpired(e)) refused(e)
            } catch (e: Exception) {
                problem = problemWords(e, s["errLost"].orEmpty())
            } finally {
                busy = false
            }
        }
    }
    fun show(found: PairAsk) {
        asking = found
        chosen = found.profiles.firstOrNull()?.id ?: me.id
        needsPassword = found.profiles.firstOrNull()?.needsPassword == true
        twoFactor = found.twoFactor || me.twoFactor
        pin = ""
    }
    fun lookUp(letters: String) = run {
        try {
            show(api.pairAskByCode(letters))
        } catch (e: ApiError) {
            // Not a device's letters: typed again.
            if (e.status == 404) { code = ""; wrong++; problem = problemWords(e, s["errLost"].orEmpty()) } else throw e
        }
    }
    fun onScan(text: String) {
        if (busy || asking != null) return
        when (val read = readScanned(text, nav.server?.serverId.orEmpty(), api.base)) {
            is Scanned.Session -> { scan = ScanStep.Off; scanned = read.qr; run { show(api.pairV2Info(read.qr)) } }
            is Scanned.Letters -> { scan = ScanStep.Off; code = read.code; lookUp(read.code) }
            Scanned.OtherServer -> problem = s["pairQrOtherServer"].orEmpty()
            Scanned.NotACode -> problem = s["pairQrNotOurs"].orEmpty()
        }
    }
    fun approve() {
        val found = asking ?: return
        run {
            val who = chosen ?: me.id
            val secret = password.takeIf { needsPassword && it.isNotEmpty() }
            val second = otp.trim().takeIf { needsPassword && it.isNotEmpty() }
            val qr = scanned
            when {
                qr != null -> api.pairV2Approve(qr.session, PairApproval(pin, who, qr.check, secret, second))
                found.sessionId.isNotEmpty() && found.needsPin -> api.pairV2Approve(found.sessionId, PairApproval(pin, who, null, secret, second))
                else -> api.pairApproveByCode(code, pin, who, secret, second)
            }
            finish(s["signInTvDone"].orEmpty(), true)
        }
    }
    fun deny() {
        val found = asking ?: return
        run {
            val session = scanned?.session ?: found.sessionId
            if (session.isNotEmpty()) api.pairV2Deny(session) else api.pairDeny(code)
            finish(s["signInTvDenied"].orEmpty(), false)
        }
    }
    fun getInvite() = run {
        invite = api.pairInviteAs(me.id, password.takeIf { it.isNotEmpty() }, otp.trim().takeIf { it.isNotEmpty() })
        inviting = false
        password = ""
        otp = ""
        needsPassword = false
    }

    val waitText = waitWords(s, waiting)
    val plain = asking == null && invite == null && !inviting && outcome.isEmpty() && scan != ScanStep.On
    // Design 2's page: what's asking and the answer to it, as sections, each state with its own actions under it.
    DesignScreen(
        s["rowSignInTv"].orEmpty(), { if (plain) nav.pop() else reset() }, eyebrow = s["youTab"].orEmpty(),
        lead = if (plain) s[if (canScan) "approveHintScan" else "signInTvHint"].orEmpty() else "", tag = "sign-in-tv",
    ) {
        val found = asking
        val made = invite
        val gap = Modifier.padding(top = LocalDesignSizes.current.gap)
        val confirm: @Composable () -> Unit = {
            DesignNote(s["approvePasswordWhy"].orEmpty())
            WittyField(password, { password = it; problem = "" }, s["yourPasswordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password, imeAction = if (twoFactor) ImeAction.Next else ImeAction.Done, isError = wrong > 0 && problem.isNotEmpty(), shake = wrong)
            if (twoFactor) WittyField(otp, { otp = it.take(32); problem = "" }, s["switchCodeLabel"].orEmpty(), icon = Symbols.ShieldLock, imeAction = ImeAction.Done, maxLength = 32)
        }
        val trouble = listOf(problem, waitText).filter { it.isNotEmpty() }.joinToString(" ")
        when {
            !adult -> DesignNote(s["signInTvAdultOnly"].orEmpty(), gap, tone = true)
            outcome.isNotEmpty() -> {
                DesignSection("") { if (good) Done(outcome) else DesignNote(outcome, error = true) }
                DesignActions { WittyButton(s["signInTvAnother"].orEmpty(), { outcome = "" }, kind = ButtonKind.Primary, tall = true, takeFocus = true) }
            }
            made != null -> {
                DesignSection("") {
                    Text(
                        made.code, color = scheme.onSurface,
                        style = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = LocalDesignSizes.current.title * 1.15f, letterSpacing = 0.25.em),
                        modifier = Modifier
                            .clip(metrics.corner(10))
                            .background(scheme.surface)
                            .padding(horizontal = LocalDesignSizes.current.gap * 2.4f, vertical = LocalDesignSizes.current.gap * 1.2f)
                            .semantics { contentDescription = made.code.toList().joinToString(" ") },
                    )
                    DesignNote(s["signInTvInviteHint"].orEmpty().replace("{minutes}", (made.expiresInSec / 60).coerceAtLeast(1).toString()))
                }
                DesignActions { WittyButton(s["signInTvAnother"].orEmpty(), ::reset, kind = ButtonKind.Secondary, tall = true) }
            }
            inviting -> {
                DesignSection("") {
                    confirm()
                    DesignNote(trouble, error = true)
                }
                DesignActions {
                    WittyButton(s["approveGetCode"].orEmpty(), ::getInvite, kind = ButtonKind.Primary, busy = busy, enabled = password.isNotEmpty() && waiting == 0, tall = true)
                }
            }
            found != null -> {
                DesignSection("") {
                    DesignRow(
                        found.device, sub = listOf(found.platform, found.ip).filter { it.isNotEmpty() }.factsLine(),
                        leading = { IconTile(Symbols.Tv, LocalExtraColours.current.accentText) },
                    )
                    DesignNote(s["approveCheck"].orEmpty())
                }
                if (found.profiles.size > 1) {
                    DesignSection(s["signInTvAs"].orEmpty()) {
                        DesignChips {
                            found.profiles.forEach { choice ->
                                val known = faces[choice.id] ?: Profile(choice.id, choice.name, "", choice.kind)
                                DesignChip(
                                    avatarName(known.displayName, known.name), { chosen = choice.id; needsPassword = choice.needsPassword; problem = "" },
                                    on = chosen == choice.id, focusKey = "as-${choice.id}",
                                )
                            }
                        }
                    }
                }
                if (found.needsPin) {
                    DesignSection(s["approvePin"].orEmpty()) {
                        PinEntry(pin, busy, wrong) { pin = PairRules.typedPin(it); problem = "" }
                    }
                }
                if (needsPassword) DesignSection("") { confirm() }
                DesignNote(trouble, gap, error = true)
                val ready = (!found.needsPin || pin.length == CODE_LENGTH) && (!needsPassword || password.isNotEmpty()) && waiting == 0
                DesignActions {
                    WittyButton(s["signInTvApprove"].orEmpty(), ::approve, kind = ButtonKind.Primary, busy = busy, enabled = ready, tall = true, focusKey = "approve")
                    WittyButton(s["signInTvDeny"].orEmpty(), ::deny, kind = ButtonKind.Secondary, tall = true, focusKey = "deny")
                }
            }
            scan == ScanStep.On -> {
                DesignSection("") {
                    QrScanner(s["approveScanning"].orEmpty(), ::onScan, onFailed = { scan = ScanStep.Off; problem = s["approveCameraFailed"].orEmpty() })
                    DesignNote(s["approveScanning"].orEmpty())
                    DesignNote(problem, error = true)
                }
                DesignActions { WittyButton(s["approveTypeInstead"].orEmpty(), { scan = ScanStep.Off; problem = "" }, kind = ButtonKind.Secondary, tall = true) }
            }
            else -> {
                if (canScan) {
                    when (scan) {
                        // Said before the system asks, so the question isn't a surprise.
                        ScanStep.Why -> {
                            DesignNote(s["approveCameraWhy"].orEmpty(), gap, tone = true)
                            DesignActions {
                                WittyButton(s["approveCameraAllow"].orEmpty(), { permission.launch(Manifest.permission.CAMERA) }, kind = ButtonKind.Primary, tall = true)
                            }
                        }
                        ScanStep.Denied -> DesignNote(s["approveCameraDenied"].orEmpty(), gap, tone = true)
                        else -> DesignActions {
                            WittyButton(
                                s["approveScan"].orEmpty(), { problem = ""; scan = if (cameraAllowed(context)) ScanStep.On else ScanStep.Why },
                                kind = ButtonKind.Primary, icon = Symbols.Qr, tall = true, focusKey = "scan",
                            )
                        }
                    }
                }
                DesignSection("") {
                    if (canScan) DesignNote(s["approveOrType"].orEmpty())
                    TvCodeEntry(code, busy, wrong) { typed ->
                        code = tvCodeTyped(typed)
                        problem = ""
                        if (code.length == TV_CODE_LENGTH) { scanned = null; lookUp(code) }
                    }
                    DesignNote(trouble, error = true)
                }
                DesignActions {
                    WittyButton(
                        s["signInTvInvite"].orEmpty(),
                        {
                            // An administrator's own sign-in is only handed out with their password again.
                            if (me.isAdmin) { inviting = true; needsPassword = true; problem = "" } else getInvite()
                        },
                        kind = ButtonKind.Secondary,
                    )
                }
            }
        }
    }
}

// The PIN a device shows: six boxes over the number keyboard, as the two-factor code is typed.
@Composable
private fun PinEntry(pin: String, checking: Boolean, wrong: Int, modifier: Modifier = Modifier, onPin: (String) -> Unit) {
    val field = remember { FocusRequester() }
    LaunchedEffect(wrong) { runCatching { field.requestFocus() } }
    Box(modifier) {
        CodeBoxes(pin, checking, wrong)
        BasicTextField(
            pin, { if (!checking) onPin(it) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
            modifier = Modifier.matchParentSize().graphicsLayer { alpha = 0f }.focusRequester(field),
        )
    }
}
