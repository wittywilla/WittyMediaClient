// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.data

import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.tvprovider.media.tv.Channel
import androidx.tvprovider.media.tv.ChannelLogoUtils
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import com.wittywilla.wittymediaclient.MainActivity
import com.wittywilla.wittymediaclient.R
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.SduiClient
import com.wittywilla.wittymediaclient.net.TvHomeCard
import com.wittywilla.wittymediaclient.net.TvHomePlan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File
import java.security.MessageDigest

// An Android TV's home screen (docs/PLATFORMS.md, Android TV's home screen): the app's own channel of what is new and
// what was being watched, and the system's Watch Next row, both from the server's GET /sdui/topshelf. Written when
// someone signs in, when the app is left, and taken away when they sign out. The home screen draws the pictures
// itself and can't sign in to the server, so they are fetched into the app's cache and lent to it one by one.
// Lint reads the builders' setters as the library's own: they are inherited from a base class the library keeps to
// itself, and are the only way it gives to make a programme.
@SuppressLint("RestrictedApi")
object TvHome {
    const val OPEN_ROUTE = "com.wittywilla.wittymediaclient.OPEN_ROUTE"
    const val EXTRA_ROUTE = "route"

    private const val PREFS = "tv-home"
    private const val KEY_CHANNEL = "channel"
    private const val FOLDER = "tvhome"
    private const val MOST_PICTURES = 60
    private const val MAX_PICTURE_BYTES = 4L * 1024 * 1024

    // Android TV's home screens, which read the pictures: Android TV's own, Google TV's, and whatever else is Home here.
    private val LAUNCHERS = listOf("com.google.android.tvlauncher", "com.google.android.apps.tv.launcherx", "com.android.tv.launcher", "com.android.providers.tv")

    private fun usable(app: WittyApp) = app.isTv && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

    // Choosing a card opens the app itself, named outright, with the route to go to: no other app is asked.
    private fun opens(context: Context, route: String): Uri {
        val intent = Intent(OPEN_ROUTE).setComponent(ComponentName(context, MainActivity::class.java)).putExtra(EXTRA_ROUTE, route)
        return Uri.parse(intent.toUri(Intent.URI_INTENT_SCHEME))
    }

    private fun name(address: String): String =
        MessageDigest.getInstance("SHA-256").digest(address.toByteArray()).joinToString("") { "%02x".format(it) }.take(32) + ".img"

    // A picture from the server, kept in the cache and lent to the home screen. Null when it couldn't be fetched.
    private fun picture(app: WittyApp, folder: File, address: String, launchers: List<String>): Uri? {
        if (address.isEmpty()) return null
        val file = File(folder, name(address))
        if (!file.isFile || file.length() == 0L) {
            val fetched = runCatching {
                app.api.http.newCall(Request.Builder().url(app.api.base + address).build()).execute().use { res ->
                    if (!res.isSuccessful) return@use false
                    val bytes = res.peekBody(MAX_PICTURE_BYTES).bytes()
                    if (bytes.isEmpty()) return@use false
                    file.writeBytes(bytes)
                    true
                }
            }.getOrDefault(false)
            if (!fetched) return null
        }
        val uri = FileProvider.getUriForFile(app, app.packageName + ".files", file)
        launchers.forEach { runCatching { app.grantUriPermission(it, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } }
        return uri
    }

    private fun launchers(app: WittyApp): List<String> {
        val home = runCatching {
            app.packageManager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0).map { it.activityInfo.packageName }
        }.getOrDefault(emptyList())
        return (LAUNCHERS + home).distinct()
    }

    private fun channelId(app: WittyApp): Long {
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val kept = prefs.getLong(KEY_CHANNEL, -1)
        // Still there? Someone may have taken the app's channel off their home screen's list, or cleared the TV's data.
        if (kept >= 0) {
            val there = runCatching {
                app.contentResolver.query(TvContractCompat.buildChannelUri(kept), arrayOf(TvContractCompat.Channels._ID), null, null, null)?.use { it.count > 0 }
            }.getOrNull() == true
            if (there) return kept
        }
        val channel = Channel.Builder()
            .setType(TvContractCompat.Channels.TYPE_PREVIEW)
            .setDisplayName(app.applicationInfo.loadLabel(app.packageManager).toString())
            .setAppLinkIntentUri(Uri.parse(Intent(app, MainActivity::class.java).toUri(Intent.URI_INTENT_SCHEME)))
            .build()
        val made = app.contentResolver.insert(TvContractCompat.Channels.CONTENT_URI, channel.toContentValues()) ?: return -1
        val id = ContentUris.parseId(made)
        prefs.edit().putLong(KEY_CHANNEL, id).apply()
        runCatching {
            ContextCompat.getDrawable(app, R.drawable.ic_launcher_foreground)?.let { mark ->
                val logo = Bitmap.createBitmap(LOGO_PX, LOGO_PX, Bitmap.Config.ARGB_8888)
                Canvas(logo).apply { drawColor(app.getColor(R.color.background)); mark.setBounds(0, 0, LOGO_PX, LOGO_PX); mark.draw(this) }
                ChannelLogoUtils.storeChannelLogo(app, id, logo)
            }
        }
        // An app's first channel may be shown without asking; the system decides.
        runCatching { TvContractCompat.requestChannelBrowsable(app, id) }
        return id
    }

    private const val LOGO_PX = 240
    private const val FULL = 100_000

    private fun aspect(shape: String) = when (shape) {
        "wide" -> TvContractCompat.PreviewPrograms.ASPECT_RATIO_16_9
        "square" -> TvContractCompat.PreviewPrograms.ASPECT_RATIO_1_1
        else -> TvContractCompat.PreviewPrograms.ASPECT_RATIO_2_3
    }

    // Reads the server's shelf and writes the home screen from it. Answers how long until it should be read again, or
    // null when this isn't a TV that has such a home screen, or nothing could be read.
    suspend fun sync(app: WittyApp, client: SduiClient): Int? {
        if (!usable(app)) return null
        return withContext(Dispatchers.IO) {
            runCatching {
                val plan = TvHomePlan.from(client.topShelf())
                val folder = File(app.cacheDir, FOLDER).apply { mkdirs() }
                val to = launchers(app)
                val resolver = app.contentResolver
                val channel = channelId(app)
                val pictures = HashSet<String>()
                fun art(card: TvHomeCard): Uri? = picture(app, folder, card.image, to)?.also { pictures += name(card.image) }
                if (channel >= 0) {
                    resolver.delete(TvContractCompat.buildPreviewProgramsUriForChannel(channel), null, null)
                    plan.channel.forEachIndexed { at, card ->
                        val program = PreviewProgram.Builder()
                            .setChannelId(channel)
                            .setType(TvContractCompat.PreviewPrograms.TYPE_CLIP)
                            .setTitle(card.title)
                            .setDescription(card.row)
                            .setPosterArtAspectRatio(aspect(card.shape))
                            .setIntentUri(opens(app, card.route))
                            .setInternalProviderId(card.id)
                            .setWeight(plan.channel.size - at)
                        art(card)?.let { program.setPosterArtUri(it) }
                        if (card.progress > 0) program.setDurationMillis(FULL).setLastPlaybackPositionMillis((card.progress * FULL).toInt())
                        resolver.insert(TvContractCompat.PreviewPrograms.CONTENT_URI, program.build().toContentValues())
                    }
                }
                // The system's own row: only this app's entries are its to take away.
                resolver.delete(TvContractCompat.WatchNextPrograms.CONTENT_URI, null, null)
                val now = System.currentTimeMillis()
                plan.watchNext.forEachIndexed { at, card ->
                    val program = WatchNextProgram.Builder()
                        .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
                        .setType(TvContractCompat.WatchNextPrograms.TYPE_CLIP)
                        .setTitle(card.title)
                        .setPosterArtAspectRatio(aspect(card.shape))
                        .setIntentUri(opens(app, card.route))
                        .setInternalProviderId(card.id)
                        // The server's order is most recent first.
                        .setLastEngagementTimeUtcMillis(now - at * 1000L)
                        .setDurationMillis(FULL)
                        .setLastPlaybackPositionMillis((card.progress * FULL).toInt())
                    art(card)?.let { program.setPosterArtUri(it) }
                    resolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, program.build().toContentValues())
                }
                // Pictures of titles no longer shown go, and the folder never grows past a few dozen.
                folder.listFiles().orEmpty().filter { it.name !in pictures }.forEach { it.delete() }
                folder.listFiles().orEmpty().sortedByDescending { it.lastModified() }.drop(MOST_PICTURES).forEach { it.delete() }
                plan.refreshAfterSec
            }.getOrNull()
        }
    }

    // Signing out, or changing server: nothing of the last person's stays on the home screen.
    fun clear(app: WittyApp) {
        if (!usable(app)) return
        runCatching {
            val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val channel = prefs.getLong(KEY_CHANNEL, -1)
            if (channel >= 0) app.contentResolver.delete(TvContractCompat.buildPreviewProgramsUriForChannel(channel), null, null)
            app.contentResolver.delete(TvContractCompat.WatchNextPrograms.CONTENT_URI, null, null)
            File(app.cacheDir, FOLDER).deleteRecursively()
        }
    }
}
