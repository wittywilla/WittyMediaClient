// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import kotlinx.coroutines.launch

// How the video players fetch a stream (PlayerScreen.kt, VideoSession.kt).
//
// A server converting the video makes each segment as the player asks for it, and a small NAS
// converting a big file can take many seconds for one: ExoPlayer's own 8-second read timeout
// failed those, three tries later the player stopped, and after three new tries of its own the
// app gave up ("stops early on"). The server waits up to a minute for a segment that is coming
// (longer while FFmpeg is still making progress), so the player waits longer than that, and a
// 503 (the server is busy, or the stream moved) is tried again shortly, as hls.js does.
//
// The player's speed goes with every request (X-WMS-Playback-Rate), so the server converts as far
// ahead as that speed needs, and the buffer grows with it (bufferForSpeed).

private const val CONNECT_MS = 15_000
private const val READ_MS = 75_000
private const val RETRIES = 6
const val RATE_HEADER = "X-WMS-Playback-Rate"

@OptIn(UnstableApi::class)
class VideoFetch(context: Context) {
    private val http = DefaultHttpDataSource.Factory().setConnectTimeoutMs(CONNECT_MS).setReadTimeoutMs(READ_MS)
    val sources: MediaSource.Factory = DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http))
        .setLoadErrorHandlingPolicy(PatientRetries())

    // The sources share the factory's request properties, so this reaches the next request of a
    // stream already playing.
    fun rate(speed: Float) {
        http.setDefaultRequestProperties(if (speed == 1f || speed <= 0f) emptyMap() else mapOf(RATE_HEADER to speedText(speed)))
    }
}

fun speedText(speed: Float): String = if (speed == speed.toLong().toFloat()) speed.toLong().toString() else speed.toString()

@OptIn(UnstableApi::class)
private class PatientRetries : DefaultLoadErrorHandlingPolicy(RETRIES) {
    override fun getRetryDelayMsFor(info: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        val code = (info.exception as? HttpDataSource.InvalidResponseCodeException)?.responseCode
        return when (code) {
            503, 429 -> retryAfter503(info.errorCount)
            else -> super.getRetryDelayMsFor(info)
        }
    }
}

// 1 s, then 2 s, then 4 s: what the server's Retry-After says for a stream that moved or a full server.
fun retryAfter503(errorCount: Int): Long = minOf(1_000L shl (errorCount - 1).coerceIn(0, 2), 4_000L)

// ExoPlayer counts its buffer in the film's time and keeps the least of it in the viewer's time:
// at 2× it holds twice as many of the film's seconds before it stops loading, up to the most.
// The most is three times the least, so 3× still has a full 50 seconds of waiting room.
const val BUFFER_MIN_MS = 50_000
const val BUFFER_MAX_MS = 150_000

@OptIn(UnstableApi::class)
fun videoLoadControl(): LoadControl =
    DefaultLoadControl.Builder()
        .setBufferDurationsMs(BUFFER_MIN_MS, BUFFER_MAX_MS, DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS, DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS)
        .build()

// How many of the film's seconds the player keeps ahead at a speed: what DefaultLoadControl works out.
fun bufferForSpeed(speed: Float): Long = (BUFFER_MIN_MS * speed.coerceAtLeast(1f)).toLong().coerceAtMost(BUFFER_MAX_MS.toLong())


// The player's speed changed: every request says it from now on, and the server hears at once, before
// the next segment, so a resting conversion starts again if the lead it has is too short for the new speed.
fun sayRate(fetch: VideoFetch, speed: Float, stream: com.wittywilla.wittymediaclient.net.Playback?, scope: kotlinx.coroutines.CoroutineScope, api: com.wittywilla.wittymediaclient.net.Api) {
    fetch.rate(speed)
    val id = stream?.streamId.orEmpty()
    if (id.isEmpty() || stream?.protocol != "hls") return
    scope.launch { runCatching { api.setStreamRate(id, speed) } }
}
