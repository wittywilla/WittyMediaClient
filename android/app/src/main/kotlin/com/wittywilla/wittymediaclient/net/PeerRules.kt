// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.net.URLDecoder

// Reaching a server from away, peer to peer: no port opened on anyone's router. The connecting is done by a Go
// library, Wittyconnect, built from the server's own source (WittyMediaServer's pkg/wittyconnect/mobile, under the
// AGPL; android/scripts/build-wittyconnect.sh). It gives back an address on this device, and loading the server from
// there is loading it from home. The server's docs/P2P.md is the design; Apple's apps do the same (PeerConnect.swift).
//
// What is here needs no library and is tested on the JVM: invites, the configuration the library takes, the state it
// reports, and what is kept about a server between runs. p2p/PeerManager.kt chooses between home and away.
object PeerRules {
    // What every request to the local address must carry: this header, or a cookie of this name.
    const val SECRET_HEADER = "X-Witty-Connect"
    const val SECRET_COOKIE = "wittyconnect"

    // On an answer from the local address itself, not the server: the way from away couldn't get through.
    const val ERROR_HEADER = "X-Witty-Connect-Error"

    // How long a connection from away is waited for, from what was kept and from an invite or a code.
    const val AWAY_WAIT_MS = 25_000L
    const val JOIN_WAIT_MS = 45_000L

    // While away, how often home is tried again; and at most how often a failed request starts a new search.
    const val HOME_EVERY_MS = 45_000L
    const val TROUBLE_EVERY_MS = 5_000L

    // The Go part's soft memory limit in an app: a TV stick has little to spare.
    const val MEMORY_MB_TV = 48
    const val MEMORY_MB = 64

    private const val MOST_HINTS = 12
    private const val LONGEST_HINT = 400
    private val BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".toSet()
    private val HINT_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/.:%-".toSet()
    private val SECRET_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".toSet()
    private val CODE_CHARS = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".toSet()

    // A server's or a device's connection ID: an Ed25519 key, in the text form libp2p gives it.
    fun isId(text: String): Boolean = text.length == 52 && text.startsWith("12D3KooW") && text.all { it in BASE58 }

    // Addresses worth handing to the library: multiaddrs, and nothing that could hide in one. This device's own
    // loopback leads nowhere useful from away.
    fun hints(list: List<String>): List<String> = list.asSequence()
        .map { it.trim() }
        .filter { a ->
            a.length <= LONGEST_HINT && a.all { it in HINT_CHARS } &&
                listOf("/ip4/", "/ip6/", "/dns/", "/dns4/", "/dns6/").any { a.startsWith(it) } &&
                !a.startsWith("/ip4/127.") && !a.startsWith("/ip6/::1/")
        }
        .distinct().take(MOST_HINTS).toList()

    // A port the local address may ask for again: none below 1024, which apps can't open.
    fun port(port: Int): Int = if (port in 1024..65535) port else 0

    // The configuration the library is started with, as the JSON it takes.
    fun configuration(key: String, serverId: String, hints: List<String>, port: Int = 0): String = JsonObject(
        mapOf(
            "key" to JsonPrimitive(key), "serverId" to JsonPrimitive(serverId),
            "hints" to JsonArray(hints(hints).map(::JsonPrimitive)), "port" to JsonPrimitive(port(port)),
        ),
    ).toString()

    // A code as a device with no keyboard shows it: eight letters and digits, none that reads as another across a room.
    fun isJoinCode(text: String): Boolean {
        val parts = text.split('-')
        return parts.size == 2 && parts.all { p -> p.length == 4 && p.all { it in CODE_CHARS } }
    }

    // What the library takes to look for the server that is told this device's code.
    fun joinConfiguration(key: String, code: String, name: String, platform: String): String = JsonObject(
        mapOf("key" to JsonPrimitive(key), "code" to JsonPrimitive(code), "name" to JsonPrimitive(name.take(60)), "platform" to JsonPrimitive(platform.take(24))),
    ).toString()

    // An invite link: wittymedia://p2p/<server ID>?s=<secret>&n=<name>&a=<address>…&h=<home>&c=<code> Nothing in it is
    // believed further than this: the ID is what gets dialled and proved. h and c (from 0.8.5, in the QR code on Connect
    // a device) are the web address the server's page was opened at and the code beside the QR code: a device at
    // home asks there with the code first (WebJoin), where the server has to prove it made the code.
    fun invite(text: String): PeerInvite? {
        val trimmed = text.trim()
        if (trimmed.length > 4096) return null
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (!uri.scheme.equals("wittymedia", ignoreCase = true) || uri.host != "p2p") return null
        val id = uri.path.orEmpty().trim('/')
        val items = uri.rawQuery.orEmpty().split('&').filter { it.isNotEmpty() }.map { item ->
            val name = item.substringBefore('=')
            name to runCatching { URLDecoder.decode(item.substringAfter('=', ""), "UTF-8") }.getOrDefault("")
        }
        val secret = items.firstOrNull { it.first == "s" }?.second.orEmpty()
        if (!isId(id) || secret.length !in 16..64 || !secret.all { it in SECRET_CHARS }) return null
        val name = shownName(items.firstOrNull { it.first == "n" }?.second.orEmpty(), 80)
        // Both or neither: an address with no code, or a code with nowhere to use it, is no use.
        val home = inviteHome(items.firstOrNull { it.first == "h" }?.second.orEmpty())
        val code = WebJoin.clean(items.firstOrNull { it.first == "c" }?.second.orEmpty())
        val both = home.isNotEmpty() && code.isNotEmpty()
        return PeerInvite(id, secret, name, hints(items.filter { it.first == "a" }.map { it.second }), if (both) home else "", if (both) code else "")
    }

    // A web address fit for an invite's h: http or https, a host and maybe a port, nothing else (the server's
    // p2p.InviteHome). "" when it isn't one.
    fun inviteHome(text: String): String {
        if (text.length > 200) return ""
        val uri = runCatching { URI(text) }.getOrNull() ?: return ""
        val scheme = uri.scheme?.lowercase() ?: return ""
        val host = uri.host ?: return ""
        if ((scheme != "http" && scheme != "https") || host.isEmpty() || uri.rawUserInfo != null || uri.rawQuery != null || uri.rawFragment != null) return ""
        if (!uri.rawPath.isNullOrEmpty() && uri.rawPath != "/") return ""
        return scheme + "://" + uri.rawAuthority
    }

    // Where a server reached only from away is kept in the list of servers: an address of its own per server that
    // leads nowhere at home, as the desktop app names it.
    fun awayOnlyUrl(serverId: String): String = "http://p2p-" + serverId.takeLast(16).lowercase() + ".localhost"

    fun isAwayOnlyUrl(url: String): Boolean = url.startsWith("http://p2p-") && url.endsWith(".localhost")

    // The local address the library listens on.
    fun localBase(port: Int): String = "http://127.0.0.1:$port"

    // The secret as a web view's cookie: a page loaded from the local address carries it on every request, its
    // WebSockets included, and no script on the page can read it. Null for a secret that can't be one.
    fun secretCookie(secret: String): String? =
        if (secret.isEmpty() || !secret.all { it in SECRET_CHARS }) null
        else "$SECRET_COOKIE=$secret; Path=/; HttpOnly; SameSite=Strict"

    fun state(text: String): PeerState {
        val o = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return PeerState()
        fun str(k: String) = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
        val path = str("path").takeIf { it in setOf("connecting", "offline", "local", "direct", "relayed") } ?: "connecting"
        val community = path == "relayed" && (o["community"] as? JsonPrimitive)?.booleanOrNull == true
        // What a relay that carries whole connections said it allows; nothing from any other.
        fun int(k: String, lo: Int, hi: Int) = (o[k] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull?.takeIf { community && it in lo..hi } ?: 0
        return PeerState(
            path, str("transport"), community, plain(str("error"), 300),
            relayKbps = int("relayKbps", 100, 10_000_000),
            relayMaxHeight = int("relayMaxHeight", 144, 4320),
            relayAllows = if (community) plain(str("relayAllows"), 300) else "",
        )
    }

    // The server's answer to an invite or to a code this device showed. `code` is an ordinary sign-in code, to redeem
    // over the new connection like one typed on a TV.
    fun answer(text: String): PeerAnswer {
        val o = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return PeerAnswer()
        fun str(k: String) = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
        val digits = str("code")
        val id = str("serverId")
        return PeerAnswer(
            ok = (o["ok"] as? JsonPrimitive)?.booleanOrNull == true,
            code = digits.takeIf { it.length == 6 && it.all(Char::isDigit) }.orEmpty(),
            reason = str("reason").take(40),
            error = plain(str("error"), 300),
            serverName = plain(str("serverName"), 80),
            serverId = id.takeIf(::isId).orEmpty(),
            addrs = hints(runCatching { o["addrs"]?.jsonArray?.mapNotNull { (it as? JsonPrimitive)?.content } }.getOrNull().orEmpty()),
        )
    }

    // The server's addresses as the library last learnt them (KnownAddrs), as hints.
    fun knownAddrs(text: String): List<String> =
        hints(runCatching { json.parseToJsonElement(text).jsonArray.mapNotNull { it.jsonPrimitive.content } }.getOrNull().orEmpty())

    // Text from the other end, shown as text: one line, no control characters, cut to a length.
    // A name that came in a link, fit to show: no control characters, and none of the invisible ones that turn text
    // around, so a name can't be made to read as something else beside it. Cut between characters.
    fun shownName(text: String, limit: Int): String {
        val kept = text.filter { !it.isISOControl() && it !in INVISIBLE }.trim()
        val cut = StringBuilder()
        var i = 0
        var n = 0
        while (i < kept.length && n < limit) {
            val end = kept.offsetByCodePoints(i, 1)
            cut.append(kept, i, end)
            i = end
            n++
        }
        return cut.toString().trim()
    }

    private val INVISIBLE = setOf('\u061c', '\u200e', '\u200f', '\u202a', '\u202b', '\u202c', '\u202d', '\u202e', '\u2066', '\u2067', '\u2068', '\u2069', '\ufeff')

    private fun plain(text: String, limit: Int): String =
        text.filter { !it.isISOControl() }.trim().take(limit)
}

// How the server is being reached right now, as the library reports it.
data class PeerState(
    val path: String = "connecting",
    val transport: String = "",
    val community: Boolean = false,
    val error: String = "",
    // What the relay said it allows: kbit/s per connection and the picture height streams keep to (0: not said),
    // and the same in a sentence.
    val relayKbps: Int = 0,
    val relayMaxHeight: Int = 0,
    val relayAllows: String = "",
) {
    // Requests can be sent.
    val connected: Boolean get() = path == "local" || path == "direct" || path == "relayed"

    // A relay's limits, short: "4 Mbit/s, 720p".
    val relayLimits: String
        get() = listOfNotNull(
            relayKbps.takeIf { it > 0 }?.let { if (it >= 1000) "${"%.1f".format(java.util.Locale.ROOT, it / 1000.0).removeSuffix(".0")} Mbit/s" else "$it kbit/s" },
            relayMaxHeight.takeIf { it > 0 }?.let { "${it}p" },
        ).joinToString(", ")

    // In words, wherever the app says which server it is on. A relay is always said, with what it allows, so a
    // smaller picture has its reason in sight.
    val words: String
        get() = when (path) {
            "local" -> "Peer to peer · same network"
            "direct" -> "Peer to peer · direct"
            "relayed" -> when {
                !community -> "Peer to peer · connecting directly…"
                relayLimits.isNotEmpty() -> "Peer to peer · through a relay · $relayLimits"
                else -> "Peer to peer · through a relay"
            }
            "offline" -> "Peer to peer · reconnecting…"
            else -> "Peer to peer · connecting…"
        }
}

// home and code: where a device at home asks with the code first, and the code (both or neither; PeerRules.invite).
data class PeerInvite(val serverId: String, val secret: String, val name: String, val hints: List<String>, val home: String = "", val code: String = "")

data class PeerAnswer(
    val ok: Boolean = false,
    val code: String = "",
    val reason: String = "",
    val error: String = "",
    val serverName: String = "",
    val serverId: String = "",
    val addrs: List<String> = emptyList(),
)

// What is kept about one server for reaching it from away: its connection ID, where it was last, and the local port
// last used, so addresses already handed to a player still lead somewhere after the app comes back.
@Serializable
data class PeerInfo(val serverId: String, val hints: List<String> = emptyList(), val port: Int = 0) {
    // As kept: only what the rules allow, so a damaged or tampered file can't hand the library anything else.
    fun cleaned(): PeerInfo? = if (!PeerRules.isId(serverId)) null else PeerInfo(serverId, PeerRules.hints(hints), PeerRules.port(port))
}

// The server's answer to GET /p2p?device=…
@Serializable
data class PeerServerInfo(
    val enabled: Boolean = false,
    val serverId: String = "",
    val addrs: List<String> = emptyList(),
    val enrolled: Boolean = false,
    val serverName: String = "",
)
