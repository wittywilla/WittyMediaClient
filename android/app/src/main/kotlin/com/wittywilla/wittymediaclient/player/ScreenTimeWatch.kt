// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.PlaybackException
import androidx.media3.datasource.HttpDataSource
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.MyLimits
import com.wittywilla.wittymediaclient.net.Refusal
import com.wittywilla.wittymediaclient.net.ScreenTime
import com.wittywilla.wittymediaclient.net.ScreenTimeRules
import com.wittywilla.wittymediaclient.net.ScreenTimeTap
import com.wittywilla.wittymediaclient.net.myLimits
import com.wittywilla.wittymediaclient.net.myScreenTime
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// What the signed-in profile may do and how long it may still play, for the whole app (the server's
// docs/PROFILES.md). The server does the deciding and the stopping; this knows why, so every player can say so:
//
//   - it reads GET /me/limits once for each sign-in, for hiding what is turned off;
//   - for a profile with time rules it asks GET /me/screen-time once a minute while the app is up or music plays,
//     and at `until`, and hears the header and the refusals on every answer (ScreenTimeTap);
//   - a player calls `playbackFailed` first thing when its stream fails. A 403 with "screen-time" is this
//     profile's time being up, not a fault; any other failure asks the server before it's called a network fault.
//
// One for the app: there is one sign-in at a time. The notice itself is ui/ScreenTimeOverlay.kt.
object ScreenTimeWatch : ScreenTimeTap.Listener {
    // Null until read, and for a server without parental controls: everything is then offered, as before.
    var limits by mutableStateOf<MyLimits?>(null)
        private set
    var time by mutableStateOf<ScreenTime?>(null)
        private set

    // The time-up notice is showing.
    var telling by mutableStateOf(false)
        private set

    // Goes up each time the minutes-left line is due again.
    var noticeCount by mutableIntStateOf(0)
        private set

    private var app: WittyApp? = null
    private var api: Api? = null
    private var polling: Job? = null
    private var foreground = true
    private var lastStep = Int.MAX_VALUE
    private var limitsReadAt = 0L

    fun can(feature: String): Boolean = limits?.can(feature) ?: true

    // A new sign-in, or none. `enabled`: the server has parental controls at all.
    fun signedIn(app: WittyApp, api: Api, enabled: Boolean) {
        stop()
        this.app = app
        this.api = api
        if (!enabled || api.token.isEmpty()) return
        ScreenTimeTap.listener = this
        polling = app.scope.launch {
            // Quiet on failure: the limits hold on the server whether or not this app knows them.
            val read = runCatching { api.myLimits() }.getOrNull() ?: return@launch
            limits = read
            limitsReadAt = System.currentTimeMillis()
            if (!read.timed) return@launch
            take(read.screenTime)
            while (true) {
                delay(ScreenTimeRules.nextAskMs(time, System.currentTimeMillis()))
                if (foreground || app.listening.isPlaying) ask(api)
            }
        }
    }

    fun stop() {
        polling?.cancel()
        polling = null
        ScreenTimeTap.listener = null
        api = null
        limits = null
        time = null
        telling = false
        lastStep = Int.MAX_VALUE
        limitsReadAt = 0
    }

    // The app came to the front or left it. Coming back asks at once: a parent may have given time meanwhile, or
    // changed what this profile may do.
    fun shown(visible: Boolean) {
        foreground = visible
        if (!visible) return
        check()
        rereadLimits()
    }

    // The limits again, when they may have changed: not more than twice a minute, however often that's suspected.
    // A change to the time rules themselves is picked up at the next sign-in or switch.
    private fun rereadLimits() {
        val using = api ?: return
        val scope = app?.scope ?: return
        val now = System.currentTimeMillis()
        if (limits == null || now - limitsReadAt < REREAD_AFTER_MS) return
        limitsReadAt = now
        scope.launch { runCatching { using.myLimits() }.getOrNull()?.let { if (api === using) limits = it } }
    }

    // Ask now, for a profile with time rules.
    fun check() {
        val using = api ?: return
        if (limits?.timed != true) return
        app?.scope?.launch { ask(using) }
    }

    private suspend fun ask(using: Api) {
        try {
            val now = using.myScreenTime()
            if (api === using) take(now)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // No answer: nothing is known, and nothing is claimed.
        }
    }

    // A newer verdict, from asking or from a parent giving time.
    // `refused`: something was just refused for it, so the notice comes up even after an earlier OK.
    fun take(now: ScreenTime, refused: Boolean = false) {
        val was = time
        time = now
        if (!now.allowed && (refused || was == null || was.allowed)) {
            // Music has no screen of its own to leave: it stops here. The players with one are left by the notice.
            app?.listening?.pause()
            telling = true
        }
        if (now.allowed) {
            telling = false
            val step = ScreenTimeRules.noticeStep(now)
            if (step < lastStep) noticeCount++
            lastStep = step
        }
    }

    // OK on the notice: browsing goes on. Playing again brings it back.
    fun dismiss() {
        telling = false
    }

    // A failed request. True when it was this profile's time being up, which the notice now says.
    fun refusedBy(e: Throwable): Boolean {
        val refusal = Refusal.of(e) ?: return false
        if (!refusal.isScreenTime) return false
        refused(refusal)
        return true
    }

    // A player's stream failed. True: time is up, the notice says so, and the player should neither try again nor
    // call it a fault. False: carry on as before; the server is asked meanwhile, and the notice comes up if that
    // was why the stream ended early.
    fun playbackFailed(e: PlaybackException): Boolean {
        var cause: Throwable? = e
        var depth = 0
        while (cause != null && depth++ < 6) {
            if (cause is HttpDataSource.InvalidResponseCodeException) {
                if (cause.responseCode == 403) {
                    val refusal = Refusal.read(String(cause.responseBody, Charsets.UTF_8))
                    if (refusal.isScreenTime) {
                        refused(refusal)
                        return true
                    }
                }
                break
            }
            cause = cause.cause
        }
        check()
        return telling
    }

    override fun timeLeft(seconds: Int) {
        val scope = app?.scope ?: return
        scope.launch(Dispatchers.Main) {
            if (limits?.timed != true) return@launch
            if (seconds == 0 && time?.allowed != false) check()
            else ScreenTimeRules.withHeader(time, seconds, System.currentTimeMillis() / 1000)?.let { if (it != time) take(it) }
        }
    }

    override fun refused(refusal: Refusal) {
        val scope = app?.scope ?: return
        scope.launch(Dispatchers.Main) {
            when {
                // Whoever asked shows the server's own words for it. If the app still offered it, the limits have
                // changed since they were read: they're read again, so it stops being offered.
                refusal.isFeatureOff -> if (can(refusal.feature)) rereadLimits()
                // An answer still on its way from the profile before this one is not this profile's: ask.
                refusal.screenTime != null && limits?.timed != false -> take(refusal.screenTime, refused = true)
                else -> api?.let { using ->
                    val now = runCatching { using.myScreenTime() }.getOrNull()
                    if (now != null && api === using) take(now, refused = true)
                }
            }
        }
    }

    private const val REREAD_AFTER_MS = 30_000L
}
