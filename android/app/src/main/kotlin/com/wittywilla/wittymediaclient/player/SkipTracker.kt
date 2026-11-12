// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.MediaMarkers
import com.wittywilla.wittymediaclient.net.SkipRange
import com.wittywilla.wittymediaclient.net.markers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

// What can be skipped in the video that's playing, for both players: the TV's (PlayerScreen.kt) and the phone's and
// tablet's (VideoSession.kt). It asks the server where the intro, recap, adverts and credits are, says which is on
// now, and skips by itself where the person chose that. The rules are in SkipRules.kt; this only watches the clock.
class SkipTracker {
    // The stretch playing now that has a button, or null.
    var now by mutableStateOf<Skip?>(null)
        private set

    // From where "next episode" should be up, when the credits run to the end. Null leaves the usual half minute.
    var upNextFromSec by mutableStateOf<Double?>(null)
        private set

    private var markers by mutableStateOf<MediaMarkers?>(null)
    private var spans by mutableStateOf<List<SkipSpan>>(emptyList())
    private val auto = AutoSkipper()

    // Someone pressed the button: that stretch needn't skip itself later.
    fun pressed() {
        now?.let { auto.pressed(it.span) }
    }

    // Runs for as long as the video does. Everything it's given is read again whenever it changes: `hasMarkers` (the
    // server names skip-markers), `fallbackIntro` (the intro an older server sends with the stream or the item),
    // `filmSec` and `durationSec` (the film's own time, offset included), `live` (really playing, with no problem up).
    // `seek` goes to a place in the film; `playNext` starts the next episode; `said` is told what was skipped.
    suspend fun run(
        app: WittyApp,
        id: Long,
        hasMarkers: () -> Boolean,
        fallbackIntro: () -> SkipRange?,
        filmSec: () -> Double,
        durationSec: () -> Double,
        live: () -> Boolean,
        nextId: () -> Long?,
        seek: (Double) -> Unit,
        playNext: (Long) -> Unit,
        said: (String) -> Unit,
    ) = coroutineScope {
        launch {
            snapshotFlow { hasMarkers() }.collectLatest { has -> markers = if (has) ask(app.api, id) else null }
        }
        launch {
            snapshotFlow { SkipRules.spans(markers, fallbackIntro()) }.collect { spans = it }
        }
        launch {
            snapshotFlow {
                val length = durationSec()
                SkipRules.skipAt(spans, filmSec(), length) to SkipRules.upNextFrom(spans, length)
            }.collect { (skip, from) ->
                now = skip
                upNextFromSec = from
            }
        }
        launch {
            // The stretch that could skip itself now: the one with a button, else credits that run to the end.
            snapshotFlow { if (live()) now?.span ?: SkipRules.endCreditsAt(spans, filmSec(), durationSec()) else null }
                .distinctUntilChanged()
                .collectLatest { span ->
                    if (span == null || !auto.due(span, ExtrasPrefs.load(app).auto)) return@collectLatest
                    // Long enough for the clock to have been read since playing began: a film that resumes after its
                    // intro says 0:00 for a moment first, and mustn't be taken to the intro's end for it.
                    delay(SETTLE_MS)
                    auto.did(span)
                    val skip = now
                    if (skip != null && skip.span == span) {
                        seek(skip.toSec)
                        said(span.kind.done + ".")
                    } else {
                        // Credits to the end: what comes after them is the next episode, when there is one.
                        nextId()?.let(playNext)
                    }
                }
        }
    }

    // Once more after a moment if it fails: a busy server at the start of a film shouldn't cost the buttons. Null
    // (the intro that came with the stream stands in) when it still can't be read.
    private suspend fun ask(api: Api, id: Long): MediaMarkers? {
        repeat(2) { attempt ->
            try {
                return api.markers(id)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                if (attempt == 0) delay(RETRY_MS)
            }
        }
        return null
    }

    private companion object {
        const val SETTLE_MS = 1_200L
        const val RETRY_MS = 3_000L
    }
}
