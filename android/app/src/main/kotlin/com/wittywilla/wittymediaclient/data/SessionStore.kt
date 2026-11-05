package com.wittywilla.wittymediaclient.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// A server this device has used, with the identity key it proved.
@Serializable
data class SavedServer(
    val url: String,
    val name: String,
    val serverId: String = "",
    val publicKey: String = "",
    val fingerprint: String = "",
)

// The sign-in, and the key of the server it belongs to. They're sealed together, so changing the
// list of servers can't make a token go to another machine.
@Serializable
data class SignIn(val token: String, val pin: String = "")

private const val MAX_RECENT = 8

// The most recent first, once per address and once per server.
fun rememberServer(recent: List<SavedServer>, server: SavedServer): List<SavedServer> {
    val others = recent.filter { it.url != server.url && (server.serverId.isEmpty() || it.serverId != server.serverId) }
    return (listOf(server) + others).take(MAX_RECENT)
}

// Which server this device uses and its sign-in. The token is encrypted with a
// key held by Android's Keystore, and app backups are off (see the manifest).
class SessionStore(context: Context) {
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)

    var server: String
        get() = prefs.getString(KEY_SERVER, "") ?: ""
        set(v) = prefs.edit().putString(KEY_SERVER, v).apply()

    val signIn: SignIn?
        get() = runCatching { json.decodeFromString<SignIn>(decrypt(prefs.getString(KEY_TOKEN, "") ?: "")) }
            .getOrNull()?.takeIf { it.token.isNotEmpty() }

    val token: String get() = signIn?.token.orEmpty()

    fun forgetToken() {
        prefs.edit().remove(KEY_TOKEN).apply()
    }

    // This device's theme for a server: "" for the server's own, "auto" for light or dark with the
    // device, or a theme's id. Kept per server, on this device only.
    fun themeChoice(server: String): String = prefs.getString(KEY_THEME + server, "") ?: ""

    fun chooseTheme(server: String, choice: String) {
        prefs.edit().putString(KEY_THEME + server, choice).apply()
    }

    var recent: List<SavedServer>
        get() = runCatching { json.decodeFromString<List<SavedServer>>(prefs.getString(KEY_RECENT, "[]") ?: "[]") }.getOrDefault(emptyList())
        set(v) = prefs.edit().putString(KEY_RECENT, json.encodeToString(v)).apply()

    fun remember(server: SavedServer) {
        recent = rememberServer(recent, server)
    }

    fun find(url: String): SavedServer? = recent.find { it.url == url }

    // The address, the key it proved and the token are kept together, in one write. False means
    // this device couldn't seal it, so it lasts only until the app closes.
    fun signedIn(server: SavedServer, token: String): Boolean {
        val sealed = encrypt(json.encodeToString(SignIn(token, server.publicKey)))
        val edit = prefs.edit()
            .putString(KEY_SERVER, server.url)
            .putString(KEY_RECENT, json.encodeToString(rememberServer(recent, server)))
        if (sealed == null) edit.remove(KEY_TOKEN) else edit.putString(KEY_TOKEN, sealed)
        edit.apply()
        return sealed != null
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    // Some devices' Keystores fail outright. That has to end in signing in again, not a crash, and
    // it never falls back to keeping the token in the clear.
    private fun encrypt(plain: String): String? = try {
        val cipher = Cipher.getInstance(TRANSFORM).apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.iv + cipher.doFinal(plain.toByteArray())
        Base64.encodeToString(sealed, Base64.NO_WRAP)
    } catch (e: GeneralSecurityException) {
        ClientLog.warn("app", "The sign-in couldn't be kept on this device: ${e.javaClass.simpleName}")
        null
    } catch (e: ProviderException) {
        ClientLog.warn("app", "The sign-in couldn't be kept on this device: ${e.javaClass.simpleName}")
        null
    }

    // A value that can't be read (the key was reset) means signing in again.
    private fun decrypt(stored: String): String {
        if (stored.isEmpty()) return ""
        return runCatching {
            val raw = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw, 0, IV_BYTES))
            String(cipher.doFinal(raw, IV_BYTES, raw.size - IV_BYTES))
        }.getOrDefault("")
    }

    private companion object {
        const val KEY_SERVER = "server"
        const val KEY_TOKEN = "signin"
        const val KEY_RECENT = "recent"
        const val KEY_THEME = "theme:"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "wittymediaclient-session"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
