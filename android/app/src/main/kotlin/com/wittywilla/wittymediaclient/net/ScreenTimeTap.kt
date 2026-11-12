// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import okhttp3.Interceptor
import okhttp3.Response

// Every signed-in answer from the server passes here once, so no screen has to remember to look: the time a
// profile has left (X-WMS-Screen-Time-Left, on anything that plays) and the two refusals parental controls make
// (403 with "code": "screen-time" or "feature-off"; the server's docs/PROFILES.md, "What an app has to handle").
// It changes nothing in the answer. Whoever shows the notice listens (player/ScreenTimeWatch.kt).
object ScreenTimeTap : Interceptor {
    interface Listener {
        fun timeLeft(seconds: Int)
        fun refused(refusal: Refusal)
    }

    @Volatile
    var listener: Listener? = null

    const val LEFT_HEADER = "X-WMS-Screen-Time-Left"
    private const val MOST_BYTES = 16L * 1024

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val response = chain.proceed(request)
        val hears = listener ?: return response
        // Only what was asked with a sign-in is this profile's.
        if (request.header("Authorization") == null) return response
        note(response.code, response.header(LEFT_HEADER), response.header("Content-Type"), hears) {
            runCatching { response.peekBody(MOST_BYTES).string() }.getOrDefault("")
        }
        return response
    }

    // Apart from OkHttp, for the players that fetch with their own client and for tests.
    fun note(status: Int, left: String?, contentType: String?, hears: Listener, body: () -> String) {
        left?.trim()?.toIntOrNull()?.let { if (it >= 0) hears.timeLeft(it) }
        if (status != 403 || contentType?.startsWith("application/json") != true) return
        val refusal = Refusal.read(body())
        if (refusal.isScreenTime || refusal.isFeatureOff) hears.refused(refusal)
    }
}
