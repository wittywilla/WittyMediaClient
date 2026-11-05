package com.wittywilla.wittymediaclient.data

import android.content.Context
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.brandLogoUrl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

// Each added server's own logo, kept on this device by its version, so the list of servers shows it at once
// and a server that can't be reached still looks like itself. Only fetched from a server whose identity has
// been checked, and only once per version.
object LogoCache {
    private const val MOST_BYTES = 2L * 1024 * 1024

    private fun folder(context: Context) = File(context.cacheDir, "logos")

    private fun key(server: String): String =
        MessageDigest.getInstance("SHA-256").digest(server.toByteArray()).take(12).joinToString("") { "%02x".format(it) }

    private fun safe(version: String) = version.filter { it.isLetterOrDigit() && it.code < 128 }

    // The kept picture, or null when there's none for this version.
    fun file(context: Context, server: String, version: String): File? {
        val v = safe(version)
        if (v.isEmpty()) return null
        return File(folder(context), "${key(server)}-$v").takeIf { it.isFile }
    }

    // Fetches and keeps it, replacing any older one of the same server. Quiet on failure: the mark stands in.
    suspend fun keep(context: Context, server: String, version: String) = withContext(Dispatchers.IO) {
        val v = safe(version)
        if (v.isEmpty() || file(context, server, version) != null) return@withContext
        runCatching {
            val request = Request.Builder().url(brandLogoUrl(server, version)).build()
            Api(server, "", quick = true).http.newCall(request).execute().use { res ->
                val body = res.body
                if (!res.isSuccessful || body.contentLength() > MOST_BYTES) return@use
                val bytes = body.bytes().takeIf { it.size <= MOST_BYTES } ?: return@use
                val dir = folder(context).apply { mkdirs() }
                val prefix = key(server) + "-"
                dir.listFiles()?.filter { it.name.startsWith(prefix) }?.forEach { it.delete() }
                File(dir, prefix + v).writeBytes(bytes)
            }
        }
    }
}
