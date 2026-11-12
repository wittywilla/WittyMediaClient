// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.data

import android.content.Context
import android.content.SharedPreferences
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
    // The version of the server's own logo when it was last opened, or empty for the app's mark. The picture is
    // kept on the device by LogoCache, so the list of servers shows it without asking any of them.
    val brandLogo: String = "",
    // When this server last proved who it is to this device, in milliseconds since 1970. 0: not known, as it was
    // remembered before the app kept this.
    val lastSeen: Long = 0,
)

// The sign-in, and the key of the server it belongs to. They're sealed together, so changing the
// list of servers can't make a token go to another machine.
@Serializable
data class SignIn(val token: String, val pin: String = "")

// What was taken out of the settings when a server was removed, held in memory so that Undo can put it back.
class TakenOut(val settings: Map<String, String>, val current: String, val sealedSignIn: String?)

// Which server this device uses and its sign-in. The token is encrypted with a
// key held by Android's Keystore, and app backups are off (see the manifest).
class SessionStore(context: Context) {
    private val app = context.applicationContext
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)

    var server: String
        get() = prefs.getString(KEY_SERVER, "") ?: ""
        set(v) = prefs.edit().putString(KEY_SERVER, v).apply()

    val signIn: SignIn?
        get() = runCatching { json.decodeFromString<SignIn>(decrypt(prefs.getString(KEY_TOKEN, "") ?: "")) }
            .getOrNull()?.takeIf { it.token.isNotEmpty() }

    val token: String get() = signIn?.token.orEmpty()

    // Whether a sign-in is stored at all, readable or not.
    val hasSignIn: Boolean get() = prefs.contains(KEY_TOKEN)

    fun forgetToken() {
        prefs.edit().remove(KEY_TOKEN).apply()
    }

    // This device's theme for a server: "" for the server's own, "auto" for light or dark with the
    // device, or a theme's id. Kept per server, on this device only.
    fun themeChoice(server: String): String = prefs.getString(KEY_THEME + server, "") ?: ""

    fun chooseTheme(server: String, choice: String) {
        prefs.edit().putString(KEY_THEME + server, choice).apply()
    }

    // The libraries this profile added to a TV's top menu, by id, in the order added. Kept per server and per
    // profile, on this device only.
    fun topMenu(server: String, profile: String): List<Long> =
        (prefs.getString("$KEY_TOP_MENU$server|$profile", "") ?: "").split(',').mapNotNull { it.toLongOrNull() }

    fun keepTopMenu(server: String, profile: String, ids: List<Long>) {
        prefs.edit().putString("$KEY_TOP_MENU$server|$profile", ids.joinToString(",")).apply()
    }

    // A server's themes as last read, kept by id and the list's modTime, so they're read again only when they change.
    fun themeTokens(server: String, id: String, modTime: Long): String? =
        prefs.getString("$KEY_TOKENS$server|$id|$modTime", null)

    fun keepThemeTokens(server: String, id: String, modTime: Long, tokens: String) {
        val edit = prefs.edit()
        prefs.all.keys.filter { it.startsWith("$KEY_TOKENS$server|$id|") }.forEach { edit.remove(it) }
        edit.putString("$KEY_TOKENS$server|$id|$modTime", tokens).apply()
    }

    var recent: List<SavedServer>
        get() = runCatching { json.decodeFromString<List<SavedServer>>(prefs.getString(KEY_RECENT, "[]") ?: "[]") }.getOrDefault(emptyList())
        set(v) = prefs.edit().putString(KEY_RECENT, json.encodeToString(v)).apply()

    fun remember(server: SavedServer) {
        val edit = prefs.edit()
        remembering(edit, recent, rememberServer(recent, server))
        edit.apply()
    }

    // A remembered server has just proved itself, perhaps somewhere new: its entry takes the address and the time,
    // and what was kept for it follows. Nothing happens for a server that isn't remembered.
    fun reached(server: SavedServer, now: Long) {
        val before = recent
        val after = reachedServer(before, server, now) ?: return
        if (after == before) return
        val edit = prefs.edit()
        remembering(edit, before, after)
        edit.apply()
    }

    fun find(url: String): SavedServer? = recent.find { it.url == url }

    // The server in use, as a tag for what is kept by its own numbers (serverTag).
    val currentTag: String get() = serverTag(find(server) ?: SavedServer(server, ""))

    // When this version first ran: what a server never reached since then counts from (seenOrSince).
    val recentSince: Long
        get() {
            val had = prefs.getLong(KEY_RECENT_SINCE, 0)
            if (had > 0) return had
            val now = System.currentTimeMillis()
            prefs.edit().putLong(KEY_RECENT_SINCE, now).apply()
            return now
        }

    // Writes the list, and takes what each server kept along: to its new address when it moved, and away when the
    // server is no longer in the list. All in the one write the caller applies.
    private fun remembering(edit: SharedPreferences.Editor, before: List<SavedServer>, after: List<SavedServer>) {
        edit.putString(KEY_RECENT, json.encodeToString(after))
        val names = prefs.all.keys.toSet()
        for (step in dataSteps(before, after)) {
            when (step) {
                is DataStep.Wipe -> {
                    ServerKeys.of(names, step.url).forEach { edit.remove(it) }
                    LogoCache.forget(app, step.url)
                }
                is DataStep.Move -> move(edit, names, step.from, step.to)
            }
        }
    }

    private fun move(edit: SharedPreferences.Editor, names: Set<String>, from: String, to: String) {
        for (name in ServerKeys.of(names, from)) {
            val there = ServerKeys.movedTo(name, from, to)
            // What the server already has under its new address stays.
            if (there !in names) prefs.getString(name, null)?.let { edit.putString(there, it) }
            edit.remove(name)
        }
        if (server == from) edit.putString(KEY_SERVER, to)
        LogoCache.move(app, from, to)
    }

    // Once, as the app starts: a list from an older version is made one entry per server, what each kept is
    // brought along, and what was left behind under addresses no remembered server has is deleted. Doing it
    // again changes nothing.
    fun tidy() {
        val stored = recent
        val merged = mergeServers(stored, server)
        val edit = prefs.edit()
        var names = prefs.all.keys.toSet()
        if (merged.servers != stored) {
            edit.putString(KEY_RECENT, json.encodeToString(merged.servers))
            ClientLog.info("app", "The list of servers was tidied: ${stored.size} became ${merged.servers.size}")
        }
        var current = server
        for ((from, to) in merged.moved) {
            move(edit, names, from, to)
            if (current == from) current = to
            names = names.filterNot { ServerKeys.owns(from, it) }.toSet() + ServerKeys.of(names, from).map { ServerKeys.movedTo(it, from, to) }
        }
        val urls = merged.servers.map { it.url } + current
        ServerKeys.orphans(names, urls).forEach { edit.remove(it) }
        edit.apply()
        LogoCache.keepOnly(app, urls)
    }

    // Removing a server: its entry, the settings kept for it, and the address in use and the sign-in when they're
    // its own, in one write. What comes back is what Undo needs.
    fun takeOut(plan: ForgetPlan): TakenOut {
        val taken = TakenOut(
            settings = plan.removeKeys.mapNotNull { key -> prefs.getString(key, null)?.let { key to it } }.toMap(),
            current = if (plan.wasCurrent) server else "",
            sealedSignIn = if (plan.forgetSignIn) prefs.getString(KEY_TOKEN, null) else null,
        )
        val edit = prefs.edit().putString(KEY_RECENT, json.encodeToString(plan.recent))
        plan.removeKeys.forEach { edit.remove(it) }
        if (plan.wasCurrent) edit.putString(KEY_SERVER, "")
        if (plan.forgetSignIn) edit.remove(KEY_TOKEN)
        edit.apply()
        return taken
    }

    // Undo: back as it was, unless another server has been signed in to since, whose sign-in then stays.
    fun putBack(plan: ForgetPlan, taken: TakenOut) {
        val edit = prefs.edit().putString(KEY_RECENT, json.encodeToString(putBack(recent, plan)))
        taken.settings.forEach { (key, value) -> edit.putString(key, value) }
        if (server.isEmpty() && !prefs.contains(KEY_TOKEN)) {
            if (taken.current.isNotEmpty()) edit.putString(KEY_SERVER, taken.current)
            if (taken.sealedSignIn != null) edit.putString(KEY_TOKEN, taken.sealedSignIn)
        }
        edit.apply()
    }

    // Every name in the settings file, for working out which belong to a server.
    val names: Set<String> get() = prefs.all.keys.toSet()

    // The address, the key it proved and the token are kept together, in one write. False means
    // this device couldn't seal it, so it lasts only until the app closes.
    fun signedIn(server: SavedServer, token: String): Boolean {
        val sealed = encrypt(json.encodeToString(SignIn(token, server.publicKey)))
        val edit = prefs.edit()
        remembering(edit, recent, rememberServer(recent, server))
        edit.putString(KEY_SERVER, server.url)
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
        const val KEY_RECENT_SINCE = "recentSince"
        const val KEY_TOKEN = "signin"
        const val KEY_RECENT = "recent"
        const val KEY_THEME = ServerKeys.THEME
        const val KEY_TOP_MENU = ServerKeys.TOP_MENU
        const val KEY_TOKENS = ServerKeys.TOKENS
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "wittymediaclient-session"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
