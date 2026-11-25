// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.bouncycastle.crypto.generators.SCrypt
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.io.encoding.Base64

// Enter a code: the code a server shows under Connect a device (Settings, Remote Access), typed here or read from
// its QR code. The same steps as the desktop app's desktop/code.js and the server's internal/server/api_connect.go.
// The app doesn't know which server on the network made the code, so it may ask several, and none of them learns
// it: both ends turn the code into two keys with scrypt; the app sends the first, which only says which code it
// means; the server has to prove it knows the code, bound to its identity key and both random numbers, before the
// app proves it does. A server that didn't make the code can't, and gets nothing more.
object WebJoin {
    // No I, L, O or U, which read as other symbols across a room.
    const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    const val LENGTH = 8
    private val SALT = "wittymedia-web-join-v1".toByteArray()
    private const val NONCE_BYTES = 16
    private val random = SecureRandom()

    // A code as a person typed it: either case, with or without the dash or spaces, and the letters that look like
    // digits taken for them. "" when it can't be one.
    fun clean(typed: String): String {
        val out = StringBuilder()
        for (typedChar in typed.uppercase()) {
            if (typedChar == ' ' || typedChar == '-' || typedChar == '\t') continue
            val c = when (typedChar) {
                'O' -> '0'
                'I', 'L' -> '1'
                else -> typedChar
            }
            if (c !in ALPHABET) return ""
            out.append(c)
            if (out.length > LENGTH) return ""
        }
        return if (out.length == LENGTH) out.toString() else ""
    }

    fun show(clean: String) = if (clean.length == LENGTH) clean.take(4) + "-" + clean.drop(4) else clean

    // Typed where an address goes, does this read as a code rather than a computer's name? Only as a code is shown:
    // its own symbols (no I, O or U, which are in most names), four and four. The desktop's looksLikeCode.
    private val CODE_SHAPE = Regex("^\\s*[0-9A-HJ-NP-TV-Z]{4}[\\s-]?[0-9A-HJ-NP-TV-Z]{4}\\s*$", RegexOption.IGNORE_CASE)

    fun looksLikeCode(typed: String): Boolean = CODE_SHAPE.matches(typed)

    class Keys(val find: ByteArray, val proof: ByteArray)

    // The server's p2p.DeriveWebJoin: scrypt, N=2^15, r=8, p=1, 32 MiB for a moment. Off the main thread.
    fun deriveNow(clean: String): Keys {
        val out = SCrypt.generate(clean.toByteArray(), SALT, 1 shl 15, 8, 1, 64)
        return Keys(out.copyOfRange(0, 32), out.copyOfRange(32, 64))
    }

    suspend fun derive(clean: String): Keys = withContext(Dispatchers.Default) { deriveNow(clean) }

    // The server's p2p.WebJoinProof: each part with its length first, so no two sets of parts read the same.
    fun proof(key: ByteArray, role: String, deviceNonce: ByteArray, serverNonce: ByteArray, identityKey: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        for (part in listOf("wittymedia web join 1".toByteArray(), role.toByteArray(), deviceNonce, serverNonce, identityKey.toByteArray())) {
            mac.update(byteArrayOf((part.size ushr 8).toByte(), part.size.toByte()))
            mac.update(part)
        }
        return mac.doFinal()
    }

    sealed interface Answer {
        // The server made the code, proved it, and signed this device in.
        data class SignedIn(val token: String, val user: User?, val serverName: String) : Answer

        // It doesn't know the code: another server's, or used, run out, or replaced by a newer one.
        data object NotHere : Answer

        // It made the code, but restarted since, which ends codes (0.8.5): its words, which say to show a new one.
        data class Restarted(val words: String) : Answer

        // Something answered but couldn't prove it made the code: nothing more was sent to it.
        data object Liar : Answer

        // It made the code but signed nobody in (too many tries, a wrong proof): its own words.
        data class Refused(val words: String) : Answer
    }

    // A refusal's machine-readable reason ("restarted"), from its JSON body.
    internal fun reasonOf(body: String): String =
        runCatching { (json.parseToJsonElement(body) as? JsonObject)?.get("reason")?.let { (it as? JsonPrimitive)?.content } }.getOrNull().orEmpty()

    @Serializable
    private data class Hello(val nonce: String = "", val proof: String = "", val publicKey: String = "")

    @Serializable
    private data class Welcome(val token: String = "", val user: User? = null, val serverName: String = "")

    // Asks one server, whose identity key the caller has just had it prove (identify). Throws IOException when it
    // can't be reached.
    suspend fun ask(api: Api, keys: Keys, identityKey: String, device: String, platform: String): Answer {
        val deviceNonce = ByteArray(NONCE_BYTES).also { random.nextBytes(it) }
        val find = keys.find.joinToString("") { "%02x".format(it) }
        val helloBody = JsonObject(mapOf("v" to JsonPrimitive(1), "find" to JsonPrimitive(find), "nonce" to JsonPrimitive(Base64.encode(deviceNonce))))
        val hello = try {
            json.decodeFromString(Hello.serializer(), api.call("POST", "/connect/hello", helloBody.toString()))
        } catch (e: ApiError) {
            if (e.status == 404 && reasonOf(e.body) == "restarted") return Answer.Restarted(e.message.orEmpty())
            return if (e.status == 404 || e.status == 405) Answer.NotHere else Answer.Refused(e.message.orEmpty())
        }
        val serverNonce = runCatching { Base64.decode(hello.nonce) }.getOrDefault(ByteArray(0))
        val said = runCatching { Base64.decode(hello.proof) }.getOrDefault(ByteArray(0))
        // The server proves first, with the key this app checked it holds. Anything else gets nothing more.
        val expected = proof(keys.proof, "server", deviceNonce, serverNonce, identityKey)
        if (hello.publicKey != identityKey || serverNonce.size != NONCE_BYTES || !MessageDigest.isEqual(said, expected)) return Answer.Liar
        val answerBody = JsonObject(
            mapOf(
                "v" to JsonPrimitive(1), "find" to JsonPrimitive(find), "nonce" to JsonPrimitive(Base64.encode(deviceNonce)),
                "serverNonce" to JsonPrimitive(Base64.encode(serverNonce)),
                "proof" to JsonPrimitive(Base64.encode(proof(keys.proof, "device", deviceNonce, serverNonce, identityKey))),
                "device" to JsonPrimitive(device), "platform" to JsonPrimitive(platform),
            ),
        )
        val welcome = try {
            json.decodeFromString(Welcome.serializer(), api.call("POST", "/connect/answer", answerBody.toString()))
        } catch (e: ApiError) {
            return Answer.Refused(e.message.orEmpty())
        }
        return if (welcome.token.isEmpty()) Answer.Refused("") else Answer.SignedIn(welcome.token, welcome.user, welcome.serverName)
    }
}
