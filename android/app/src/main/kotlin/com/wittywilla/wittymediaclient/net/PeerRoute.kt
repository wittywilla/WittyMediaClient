// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import java.net.CookieHandler
import java.net.URI

// Where the server is while it is reached from away: the local address the connector listens on, and the secret
// every request to it must carry (PeerRules.SECRET_HEADER, or the cookie). One at a time, as the app uses one server.
// The app's own requests (Api, and the pictures through it) carry the header; the players, which use Android's own
// HTTP, carry the cookie, which this hands to every request for the local address; web views are given the cookie
// themselves (WebPlayer.kt).
object PeerRoute {
    @Volatile
    var port: Int = 0
        private set

    @Volatile
    var secret: String = ""
        private set

    // Called when a request to the local address failed: the connection may need finding again. From any thread.
    @Volatile
    var onTrouble: (() -> Unit)? = null

    val active: Boolean get() = port > 0 && secret.isNotEmpty()

    val base: String get() = PeerRules.localBase(port)

    fun set(port: Int, secret: String) {
        this.secret = secret
        this.port = port
    }

    fun clear() {
        port = 0
        secret = ""
    }

    // A request for the local address now in use.
    fun matches(host: String?, port: Int): Boolean = active && port == this.port && (host == "127.0.0.1" || host == "localhost")

    fun trouble() {
        if (active) onTrouble?.invoke()
    }

    // The players use HttpURLConnection, which asks the default cookie handler for each request. Installed once, it
    // adds the secret for the local address and nothing for anywhere else, and passes on to whatever was there before.
    fun installCookies() {
        val before = CookieHandler.getDefault()
        if (before is Cookies) return
        CookieHandler.setDefault(Cookies(before))
    }

    private class Cookies(private val before: CookieHandler?) : CookieHandler() {
        override fun get(uri: URI, requestHeaders: Map<String, List<String>>): Map<String, List<String>> {
            val theirs = before?.get(uri, requestHeaders).orEmpty()
            if (!matches(uri.host, if (uri.port > 0) uri.port else 80)) return theirs
            val mine = PeerRules.SECRET_COOKIE + "=" + secret
            val had = theirs["Cookie"].orEmpty()
            return theirs + ("Cookie" to (had + mine))
        }

        override fun put(uri: URI, responseHeaders: Map<String, List<String>>) {
            before?.put(uri, responseHeaders)
        }
    }
}
