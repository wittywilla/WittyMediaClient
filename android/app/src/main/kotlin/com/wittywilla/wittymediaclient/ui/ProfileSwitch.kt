// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.HouseholdProfile
import com.wittywilla.wittymediaclient.net.Profile
import com.wittywilla.wittymediaclient.net.household
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.switchProfile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// Who's watching?, on a device that's already signed in (the server's docs/PROFILES.md, "Switching profile").
// Choosing a profile signs this device in as it and out of the one before, in one step on the server: with its
// password or PIN, its two-factor code when it has one, or a tap where the server allows that at home. The new
// sign-in is kept with the same server key as the old one, and everything the app remembered of the profile before
// is forgotten, exactly as signing in does.

// What the answer to a try means for the screen. Apart from it, so the rules can be tested.
enum class SwitchOutcome { AskCode, WrongCode, WrongPassword, Wait, Failed }

fun switchOutcome(status: Int, twoFactor: Boolean, codeSent: Boolean): SwitchOutcome = when {
    twoFactor -> if (codeSent) SwitchOutcome.WrongCode else SwitchOutcome.AskCode
    status == 429 -> SwitchOutcome.Wait
    // 403, not 401: the device is still signed in to the profile it had.
    status == 403 -> SwitchOutcome.WrongPassword
    else -> SwitchOutcome.Failed
}

// The server lists nobody (the Classic sign-in screen, or away from home for a profile that isn't an adult's), or
// only the profile already here: there is nothing to switch to, and "Switch profile" signs out, as the doc says.
fun switchingSignsOut(profiles: List<HouseholdProfile>): Boolean = profiles.size <= 1

private fun HouseholdProfile.asProfile() = Profile(id, name, displayName, kind, hasPassword, avatar)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WhoIsWatchingScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    var profiles by remember { mutableStateOf<List<HouseholdProfile>?>(null) }
    var chosen by remember { mutableStateOf<HouseholdProfile?>(null) }
    var password by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var needCode by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var wrong by remember { mutableIntStateOf(0) }
    var waits by remember { mutableIntStateOf(0) }
    var waitSec by remember { mutableIntStateOf(0) }
    val waiting = rememberWait(waitSec, waits)

    LaunchedEffect(Unit) {
        try {
            val list = nav.app.api.household().profiles
            if (switchingSignsOut(list)) nav.signOut() else profiles = list
        } catch (e: CancellationException) {
            throw e
        } catch (e: ApiError) {
            // A server without the list at all: signing out is what switching was.
            if (e.status == 404) nav.signOut() else if (!nav.handleExpired(e)) { profiles = emptyList(); problem = problemWords(e, s["errLost"].orEmpty()) }
        } catch (e: Exception) {
            profiles = emptyList()
            problem = problemWords(e, s["errLost"].orEmpty())
        }
    }

    fun go(to: HouseholdProfile, secret: String, typedCode: String) {
        if (busy || waiting > 0) return
        busy = true
        problem = ""
        scope.launch {
            try {
                // A password is about to leave this device: the server proves it is still itself first.
                val stopped = nav.server?.let { nav.clearToSend(it) }
                if (stopped != null) {
                    problem = stopped
                    return@launch
                }
                val result = nav.app.api.switchProfile(to.name, secret, typedCode, nav.app.deviceName)
                if (result.token.isEmpty()) {
                    problem = s["errInvalid"].orEmpty()
                    return@launch
                }
                // What was playing was the other profile's. Then the new sign-in takes the old one's place, with the
                // server's key it was pinned to, and every remembered screen goes.
                nav.closeVideo()
                nav.signedIn(result.token, result.user)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                when (switchOutcome(e.status, e.twoFactor, typedCode.isNotEmpty())) {
                    SwitchOutcome.AskCode -> { needCode = true; code = "" }
                    SwitchOutcome.WrongCode -> { needCode = true; code = ""; wrong++; problem = s["errWrongCode"].orEmpty() }
                    SwitchOutcome.WrongPassword -> {
                        // A tap that was refused means the server wants a password here after all.
                        if (chosen == null) chosen = to else { wrong++; problem = s["errWrongPassword"].orEmpty() }
                        password = ""
                        needCode = false
                        code = ""
                    }
                    SwitchOutcome.Wait -> {
                        waitSec = e.retryAfterSec
                        waits++
                        problem = problemWords(e, s["errLost"].orEmpty())
                        password = ""
                    }
                    SwitchOutcome.Failed -> if (!nav.handleExpired(e)) problem = problemWords(e, s["errLost"].orEmpty())
                }
            } catch (e: Exception) {
                problem = problemWords(e, s["errLost"].orEmpty())
            } finally {
                busy = false
            }
        }
    }

    fun pick(p: HouseholdProfile) {
        if (busy) return
        if (p.current) { nav.pop(); return }
        problem = ""
        password = ""
        code = ""
        needCode = false
        if (p.hasPassword) chosen = p else go(p, "", "")
    }

    val list = profiles
    val picked = chosen
    val memory = nav.focusFor("who-" + if (picked == null) "list" else if (needCode) "code" else "password")
    androidx.compose.runtime.CompositionLocalProvider(LocalFocusMemory provides memory) {
        when {
            list == null -> Screen { Loading() }
            picked != null -> {
                val field = remember { FocusRequester() }
                LaunchedEffect(picked.id, needCode, wrong) { runCatching { field.requestFocus() } }
                val back = { chosen = null; password = ""; code = ""; needCode = false; problem = "" }
                val submit = { if (needCode) { if (code.isNotBlank()) go(picked, password, code.trim()) } else if (password.isNotEmpty()) go(picked, password, "") }
                val wait = waitWords(s, waiting)
                SignInLayout(
                    back, centred = true,
                    words = {
                        FaceWithNames(picked.asProfile(), metrics.u(if (metrics.tv) 200 else 120), Modifier.align(Alignment.CenterHorizontally))
                        SignInHeading("", detail = s[if (needCode) "twoFactorHint" else if (picked.kind == "adult") "passwordHint" else "switchPinHint"].orEmpty(), centred = true)
                    },
                    actions = {
                        if (needCode) {
                            WittyField(
                                code, { code = it.take(CODE_MOST); problem = "" }, s["switchCodeLabel"].orEmpty(), icon = Symbols.Key,
                                imeAction = ImeAction.Go, onAction = submit, focusRequester = field, isError = problem.isNotEmpty(), shake = wrong, maxLength = CODE_MOST,
                            )
                        } else {
                            WittyField(
                                password, { password = it; problem = "" }, s[if (picked.kind == "adult") "passwordLabel" else "switchPinLabel"].orEmpty(),
                                kind = FieldKind.Password, icon = Symbols.Password, imeAction = ImeAction.Go, onAction = submit, focusRequester = field,
                                isError = problem.isNotEmpty() && wrong > 0, shake = wrong,
                            )
                        }
                        Problem(listOf(problem, wait).filter { it.isNotEmpty() }.joinToString(" "), Modifier.fillMaxWidth())
                        WittyButton(s["switchGo"].orEmpty(), submit, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, enabled = waiting == 0, tall = true, focusKey = "switch-go")
                    },
                )
            }
            else -> {
                val size = metrics.u(
                    when {
                        metrics.tv -> 200
                        metrics.tablet -> 140
                        else -> 104
                    },
                )
                val grid: @Composable () -> Unit = {
                    FlowRow(
                        Modifier.fillMaxWidth().remoteRow(),
                        horizontalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 48 else 24), Alignment.CenterHorizontally),
                        verticalArrangement = Arrangement.spacedBy(metrics.u(20)),
                        maxItemsInEachRow = if (metrics.tv || metrics.tablet) Int.MAX_VALUE else 2,
                    ) {
                        list.forEachIndexed { i, p ->
                            key(p.id) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    ProfileTile(p.asProfile(), size, { pick(p) }, requestFocus = if (list.any { it.current }) p.current else i == 0, focusKey = "switch-${p.id}")
                                    // Which one this device is on now; the others say whether they ask for a password.
                                    Text(
                                        when {
                                            p.current -> s["switchCurrent"].orEmpty()
                                            p.hasPassword -> s["switchLocked"].orEmpty()
                                            else -> ""
                                        },
                                        color = if (p.current) LocalExtraColours.current.accentText else LocalExtraColours.current.hint,
                                        style = MaterialTheme.typography.caption, textAlign = TextAlign.Center,
                                    )
                                }
                            }
                        }
                    }
                }
                val other: @Composable () -> Unit = {
                    WittyButton(s["otherAccount"].orEmpty(), nav::signOut, kind = ButtonKind.Quiet, focusKey = "other-account")
                }
                if (metrics.tv) {
                    androidx.activity.compose.BackHandler { nav.pop() }
                    TvBackdrop(contentAlignment = Alignment.Center) {
                        Column(
                            Modifier.padding(horizontal = metrics.gutter + metrics.tvSafeSides),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(metrics.u(40)),
                        ) {
                            SignInHeading(s["whoTitle"].orEmpty(), display = true, centred = true)
                            if (problem.isNotEmpty()) Problem(problem, centred = true)
                            grid()
                            other()
                        }
                    }
                } else {
                    SignInPage(nav::pop, wide = metrics.tablet) {
                        SignInHeading(s["whoTitle"].orEmpty(), display = true)
                        grid()
                        Problem(problem, Modifier.fillMaxWidth())
                        other()
                    }
                }
            }
        }
    }
}

// A code from an authenticator app, or a recovery code: the server takes at most 32 characters.
private const val CODE_MOST = 32
