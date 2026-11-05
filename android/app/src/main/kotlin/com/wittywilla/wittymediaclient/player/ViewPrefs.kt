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
    private fun itemKey(id: Long) = "item.$id"

    private fun read(context: Context, key: String): ViewPrefs? =
        prefs(context).getString(key, null)?.let { runCatching { json.decodeFromString<ViewPrefs>(it) }.getOrNull() }

    // This video's own, when it has them; otherwise everyone's.
    fun load(context: Context, id: Long): ViewPrefs = read(context, itemKey(id)) ?: read(context, ALL) ?: ViewPrefs()
    fun hasOwn(context: Context, id: Long): Boolean = prefs(context).contains(itemKey(id))

    fun save(context: Context, id: Long, value: ViewPrefs, forThisVideo: Boolean) {
        val text = json.encodeToString(ViewPrefs.serializer(), value)
        prefs(context).edit().apply {
            if (forThisVideo) putString(itemKey(id), text) else { putString(ALL, text); remove(itemKey(id)) }
        }.apply()
    }

    // auto (the server's choice), standard or robust.
    fun streaming(context: Context): String = prefs(context).getString(STREAMING, "auto") ?: "auto"
    fun setStreaming(context: Context, value: String) = prefs(context).edit().putString(STREAMING, value).apply()
}
