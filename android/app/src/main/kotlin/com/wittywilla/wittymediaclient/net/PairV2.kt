// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request
import java.net.URLDecoder
import java.net.URLEncoder

// Signing a device in with a QR code and a PIN that changes (docs/CLIENT-API.md, "With a QR code and a PIN"), for
// servers with the `pair-qr` feature. The device shows both; an adult already signed in scans the code or types the
// device's letters, sees what is asking, and types the PIN. The rules are here, apart from any screen.

const val PAIR_QR_FEATURE = "pair-qr"

// What POST /auth/pair answers. The secret stays in memory on this device and is never shown.
@Serializable
data class PairSession(
    val sessionId: String = "",
    val deviceSecret: String = "",
    val pin: String = "",
    val pinExpiresAt: Long = 0,
    val period: Int = 30,
    val digits: Int = 6,
    val qr: String = "",
    val code: String = "",
    val approvePath: String = "/pair",
    val approveUrl: String = "",
    val expiresAt: Long = 0,
    val expiresInSec: Int = 300,
    val intervalSec: Int = 3,
)

// The PIN to show now, and when to ask for the next one.
@Serializable
data class PairPin(val pin: String = "", val pinExpiresAt: Long = 0, val period: Int = 30, val expiresAt: Long = 0)

// What is asking, for whoever approves. needsPassword: putting this profile on the device asks for the
// approver's own password again (an administrator's own account).
@Serializable
data class PairAskChoice(val id: Long = 0, val name: String = "", val kind: String = "adult", val needsPassword: Boolean = false)

@Serializable
data class PairAsk(
    val code: String = "",
    val sessionId: String = "",
    val device: String = "",
    val platform: String = "",
    val ip: String = "",
    val expiresAt: Long = 0,
    val needsPin: Boolean = false,
    val twoFactor: Boolean = false,
    val profiles: List<PairAskChoice> = emptyList(),
)

@Serializable
data class PairApproval(val pin: String = "", val userId: Long? = null, val check: String? = null, val password: String? = null, val otp: String? = null)

@Serializable
private data class PairCodeApproval(val code: String, val pin: String, val userId: Long? = null, val password: String? = null, val otp: String? = null)

@Serializable
private data class PairInviteAsk(val userId: Long, val password: String? = null, val otp: String? = null)

// What a QR code on a device says: wms://pair?v=1&s=<serverId>&u=<base url>&c=<sessionId>&k=<check>.
data class PairQr(val serverId: String, val base: String, val session: String, val check: String)

// Why a scanned code isn't used.
enum class QrProblem { NotOurs, OtherServer }

object PairRules {
    private const val SESSION_HEX = 32
    private const val MOST_CHARS = 1024

    // Reads a scanned code, or null when it isn't one of these. Nothing in it is trusted: the session must look
    // like one the server makes, and the check goes back to the server, which refuses an altered code.
    fun parseQr(text: String): PairQr? {
        val t = text.trim()
        if (t.length > MOST_CHARS || !t.startsWith("wms://pair?")) return null
        val fields = HashMap<String, String>()
        for (part in t.substringAfter('?').split('&')) {
            val name = part.substringBefore('=')
            if (name.isEmpty() || !part.contains('=') || name in fields) return null
            fields[name] = runCatching { URLDecoder.decode(part.substringAfter('='), "UTF-8") }.getOrNull() ?: return null
        }
        if (fields["v"] != "1") return null
        val session = fields["c"].orEmpty()
        val check = fields["k"].orEmpty()
        if (session.length != SESSION_HEX || session.any { it !in "0123456789abcdef" }) return null
        // base64url of 12 bytes; anything else never came from a server.
        if (check.isEmpty() || check.length > 64 || check.any { !(it.isLetterOrDigit() && it.code < 128) && it != '-' && it != '_' }) return null
        return PairQr(fields["s"].orEmpty(), fields["u"].orEmpty(), session, check)
    }

    // Is this code from the server this app is signed in to? By the server's own ID where both are known, as the
    // device may reach the server at another address than this phone does. Otherwise by the address it names.
    // The answer only decides whether to ask: the question always goes to this app's own server, never to `u`.
    fun fitsServer(qr: PairQr, serverId: String, base: String): Boolean {
        if (qr.serverId.isNotEmpty() && serverId.isNotEmpty()) return qr.serverId == serverId
        val theirs = qr.base.toHttpUrlOrNull() ?: return false
        val ours = base.toHttpUrlOrNull() ?: return false
        return theirs.scheme == ours.scheme && theirs.host == ours.host && theirs.port == ours.port
    }

    fun problem(text: String, serverId: String, base: String): QrProblem? {
        val qr = parseQr(text) ?: return QrProblem.NotOurs
        return if (fitsServer(qr, serverId, base)) null else QrProblem.OtherServer
    }

    // The PIN changes on the server's clock, which this device's may not agree with. So the countdown goes by how
    // long this device has waited since the answer came, not by comparing clocks: `leftAtAnswer` seconds were left
    // when the answer came (pinExpiresAt minus the Date the server stamped it with, or the period when unknown).
    fun secondsLeftAtAnswer(pinExpiresAt: Long, serverNowSec: Long, period: Int): Int {
        val p = period.coerceIn(1, 3600)
        if (serverNowSec <= 0 || pinExpiresAt <= 0) return p
        return (pinExpiresAt - serverNowSec).toInt().coerceIn(0, p)
    }

    fun secondsLeft(leftAtAnswer: Int, waitedMs: Long): Int = (leftAtAnswer - (waitedMs / 1000).toInt()).coerceAtLeast(0)

    // How full the countdown ring is, 1 at the start of a PIN's life and 0 when it rolls over.
    fun share(leftAtAnswer: Int, waitedMs: Long, period: Int): Float =
        ((leftAtAnswer * 1000L - waitedMs).toFloat() / (period.coerceAtLeast(1) * 1000f)).coerceIn(0f, 1f)

    // When to ask for the next PIN: just after this one ends, and never in a tight loop if the clocks disagree.
    fun nextPinInMs(leftAtAnswer: Int): Long = (leftAtAnswer * 1000L + 400L).coerceIn(1000L, 60_000L)

    // "478206" as "478 206", which reads across a room; other lengths are left alone.
    fun shownPin(pin: String): String = if (pin.length == 6) pin.substring(0, 3) + " " + pin.substring(3) else pin

    // What is typed for a PIN: its digits, as many as the server's.
    fun typedPin(text: String, digits: Int = 6): String = text.filter { it in '0'..'9' }.take(digits)

    // How long to wait before the next poll: the server's interval, one more second each time it says "slow down" (and it stays slower),
    // and never less than a second or more than half a minute.
    fun pollWaitSec(current: Int, status: String, serverInterval: Int): Int = when (status) {
        "slow-down" -> maxOf(current, serverInterval) + 1
        else -> maxOf(current, serverInterval)
    }.coerceIn(1, 30)

    // A network that blinks: wait a little longer each time, up to ten seconds, and carry on.
    fun retryWaitSec(failures: Int): Int = (2 + failures.coerceAtLeast(0) * 2).coerceAtMost(10)
}

// Where a device's pairing is.
enum class PairPhase { Starting, Waiting, Approved, Denied, Expired, Locked, Busy, Failed }

// One answer to a poll: the status the server gave, by its word or by the answer's number when there is no word.
fun pairPhaseAfter(status: String, httpStatus: Int, hasToken: Boolean): PairPhase = when {
    status == "approved" -> if (hasToken) PairPhase.Approved else PairPhase.Failed
    status == "denied" -> PairPhase.Denied
    status == "locked" -> PairPhase.Locked
    status == "expired" || status == "answered" -> PairPhase.Expired
    status == "pending" || status == "slow-down" -> PairPhase.Waiting
    httpStatus == 404 || httpStatus == 410 -> PairPhase.Expired
    httpStatus == 403 -> PairPhase.Denied
    httpStatus == 429 -> PairPhase.Waiting
    httpStatus in 200..299 -> PairPhase.Waiting
    else -> PairPhase.Failed
}

val PairPhase.ended: Boolean get() = this != PairPhase.Starting && this != PairPhase.Waiting

// Why an approval was refused, from the refusal's own JSON: {"reason": "wrong-pin", "triesLeft": 4, "twoFactor": true}.
data class PairRefusal(val reason: String = "", val triesLeft: Int = -1, val twoFactor: Boolean = false) {
    val needsPassword: Boolean get() = reason == "password-required"
    val wrongPin: Boolean get() = reason == "wrong-pin"
    // The session is over, whatever is typed next.
    val over: Boolean get() = reason == "locked" || reason == "expired" || reason == "used" || reason == "not-found"

    companion object {
        fun read(body: String): PairRefusal = runCatching {
            val o = json.parseToJsonElement(body).jsonObject
            PairRefusal(
                o["reason"]?.jsonPrimitive?.content.orEmpty(),
                o["triesLeft"]?.jsonPrimitive?.content?.toIntOrNull() ?: -1,
                o["twoFactor"]?.jsonPrimitive?.content == "true",
            )
        }.getOrDefault(PairRefusal())
    }
}

// An answer that isn't JSON `call` can read as it is: the device's two questions answer 403, 410 and 429 as
// part of the conversation, and carry the secret in a header.
data class PairAnswerRaw(val status: Int, val text: String, val serverNowSec: Long)

private const val SECRET_HEADER = "X-WMS-Pair-Secret"

private suspend fun Api.pairAsk(path: String, secret: String): PairAnswerRaw = withContext(Dispatchers.IO) {
    val request = Request.Builder().url("$base/api/v1$path").header(SECRET_HEADER, secret).build()
    http.newCall(request).execute().use { res ->
        PairAnswerRaw(res.code, res.peekBody(64 * 1024).string(), (res.headers.getDate("Date")?.time ?: 0L) / 1000)
    }
}

suspend fun Api.pairV2Start(device: String, platform: String): PairSession =
    json.decodeFromString(call("POST", "/auth/pair", json.encodeToString(PairStartRequest(device, platform))))

// The PIN to show now, or null once the session is no longer waiting for one.
suspend fun Api.pairV2Pin(session: String, secret: String): Pair<PairPin, Long>? {
    val answer = pairAsk("/auth/pair/$session/pin", secret)
    if (answer.status !in 200..299) return null
    return json.decodeFromString<PairPin>(answer.text) to answer.serverNowSec
}

// Denied, expired, locked and slow-down are answers here, not errors.
suspend fun Api.pairV2Poll(session: String, secret: String): Pair<PairPoll, Int> {
    val answer = pairAsk("/auth/pair/$session", secret)
    val poll = runCatching { json.decodeFromString<PairPoll>(answer.text) }.getOrDefault(PairPoll())
    return poll to answer.status
}

suspend fun Api.pairV2Info(qr: PairQr): PairAsk =
    json.decodeFromString(call("GET", "/auth/pair/${qr.session}/info?k=" + URLEncoder.encode(qr.check, "UTF-8")))

// A device's letters, typed: the same answer, which says whether a PIN is needed too.
suspend fun Api.pairAskByCode(code: String): PairAsk =
    json.decodeFromString(call("POST", "/pair/info", json.encodeToString(CodeOnly(code))))

suspend fun Api.pairV2Approve(session: String, approval: PairApproval) {
    call("POST", "/auth/pair/$session/approve", json.encodeToString(approval))
}

// A device found by its letters and not by a scan: the code with the PIN, as the web's /pair page sends it.
suspend fun Api.pairApproveByCode(code: String, pin: String, userId: Long?, password: String?, otp: String?) {
    call("POST", "/pair/approve", json.encodeToString(PairCodeApproval(code, pin, userId, password, otp)))
}

suspend fun Api.pairV2Deny(session: String) {
    call("POST", "/auth/pair/$session/deny", "{}")
}

// Six digits for the device to type; an administrator's own account asks for their password again.
suspend fun Api.pairInviteAs(userId: Long, password: String?, otp: String?): PairInvite =
    json.decodeFromString(call("POST", "/pair/invite", json.encodeToString(PairInviteAsk(userId, password, otp))))
