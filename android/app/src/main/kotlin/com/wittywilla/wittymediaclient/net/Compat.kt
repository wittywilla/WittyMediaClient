package com.wittywilla.wittymediaclient.net

// Which app works with which server: docs/CLIENT-API.md in the server's repository, "Which app
// works with which server". Optional things are chosen by feature name, never by server version.

object Compat {
    const val API_VERSION = 1

    // The API additions this app can't do without.
    const val MINIMUM_API_REVISION = 5
    const val APP_KIND = "android"

    // Why this server can't be used by this app, as a reason the connect screen has words for.
    fun problem(caps: Capabilities, appVersion: String): String? = when {
        API_VERSION !in caps.apiVersions -> "app-old"
        caps.setupRequired -> "not-set-up"
        caps.apiRevision < MINIMUM_API_REVISION -> "server-old"
        isOlder(appVersion, caps.minClientVersions[APP_KIND].orEmpty()) -> "app-old"
        else -> null
    }

    // 0.2.0 against 0.10.0, and 0.6.0-alpha against 0.6.0. Anything unreadable is taken as fine, so
    // that an odd version string can never lock someone out.
    fun isOlder(version: String, than: String): Boolean {
        val a = parts(version) ?: return false
        val b = parts(than) ?: return false
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x < y
        }
        return false
    }

    private fun parts(version: String): List<Int>? {
        val numbers = version.trim().substringBefore('-').substringBefore('+')
        if (numbers.isEmpty()) return null
        return numbers.split('.').map { it.toIntOrNull() ?: return null }
    }
}

fun Capabilities.has(feature: String) = feature in features
