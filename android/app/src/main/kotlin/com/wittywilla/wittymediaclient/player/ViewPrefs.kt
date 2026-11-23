// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.content.Context
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.Serializable

// The website's Viewing settings (web/src/player/viewPrefs.ts): kept on this device, for every video or for
// one, the same choices and defaults. Streaming is this device's alone, whatever the video.
@Serializable
data class ViewPrefs(
    val seekBar: Boolean = true,
    val chapterMarks: Boolean = true,
    val remote: Boolean = false,
    // floating or bar
    val remoteStyle: String = "floating",
    // Seconds; 0 is never.
    val hideAfter: Double = 3.5,
    // contain (Fit) or cover (Fill screen)
    val fit: String = "contain",
    // off, sbs or tab, and how to show it: 2d or anaglyph
    val stereo: String = "off",
    val stereoView: String = "2d",
)

object ViewPrefsStore {
    private const val FILE = "wms.view"
    private const val ALL = "all"
    private const val STREAMING = "streaming"

    private fun prefs(context: Context) = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    // A video's number is its server's: its own settings are kept under that server's tag. Those kept before this had
    // no tag, and count as the server in use's until they are saved again.
    private fun itemKey(context: Context, id: Long): String {
        val tag = (context.applicationContext as? com.wittywilla.wittymediaclient.WittyApp)?.store?.currentTag.orEmpty()
        return if (tag.isEmpty()) "item.$id" else "item.$tag.$id"
    }
    private fun oldKey(id: Long) = "item.$id"

    private fun read(context: Context, key: String): ViewPrefs? =
        prefs(context).getString(key, null)?.let { runCatching { json.decodeFromString<ViewPrefs>(it) }.getOrNull() }

    // This video's own, when it has them; otherwise everyone's.
    fun load(context: Context, id: Long): ViewPrefs = read(context, itemKey(context, id)) ?: read(context, oldKey(id)) ?: read(context, ALL) ?: ViewPrefs()
    fun hasOwn(context: Context, id: Long): Boolean = prefs(context).let { it.contains(itemKey(context, id)) || it.contains(oldKey(id)) }

    fun save(context: Context, id: Long, value: ViewPrefs, forThisVideo: Boolean) {
        val text = json.encodeToString(ViewPrefs.serializer(), value)
        prefs(context).edit().apply {
            remove(oldKey(id))
            if (forThisVideo) putString(itemKey(context, id), text) else { putString(ALL, text); remove(itemKey(context, id)) }
        }.apply()
    }

    // One server's videos, when it is removed.
    fun forgetServer(context: Context, tags: List<String>) {
        val edit = prefs(context).edit()
        prefs(context).all.keys.filter { key -> tags.any { key.startsWith("item.$it.") } }.forEach { edit.remove(it) }
        edit.apply()
    }

    // When no server is remembered, every video's are nobody's, untagged ones from before included.
    fun forgetVideos(context: Context) {
        val edit = prefs(context).edit()
        prefs(context).all.keys.filter { it.startsWith("item.") }.forEach { edit.remove(it) }
        edit.apply()
    }

    // auto (the server's choice), standard or robust.
    fun streaming(context: Context): String = prefs(context).getString(STREAMING, "auto") ?: "auto"
    fun setStreaming(context: Context, value: String) = prefs(context).edit().putString(STREAMING, value).apply()

    // How big subtitles are drawn on this device, for every video: 0.8 small to 1.5 extra large, as the website's sizes.
    val SUBTITLE_SIZES = listOf(0.8 to "Small", 1.0 to "Medium", 1.25 to "Large", 1.5 to "Extra large")
    fun subtitleSize(context: Context): Double = prefs(context).getFloat(SUBTITLE_SIZE, 1f).toDouble().coerceIn(0.5, 2.0)
    fun setSubtitleSize(context: Context, value: Double) = prefs(context).edit().putFloat(SUBTITLE_SIZE, value.toFloat()).apply()
    private const val SUBTITLE_SIZE = "subtitleSize"
}
