package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.Lyrics
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import java.util.Locale

// The rest of the website's Now Playing, as rules apart from the screen so they can be tested: the visualizer's
// choices (web/src/audio/NowPlaying.tsx, backdrop.ts), the words (LyricsPanel.tsx, lyrics.ts). The iPhone has the
// same in WittyKit's SoundLook.swift and MusicLook.swift.

// The visualizer's choices, kept for the person on the server with their other interface choices (/me/ui,
// `musicPlayer`), as the website's readPrefs reads them.
data class VisualizerPrefs(
    val viz: Boolean = true,
    val style: String = "bars",
    val slow: Boolean = false,
    val shuffleEvery: Int = 0,
    val shufflePool: String = "mine",
) {
    // The style drawn here: one of the player's own, or Bars for an effect only the website's plugin draws.
    val nativeStyle: String get() = if (STYLES.any { it.first == style }) style else "bars"

    fun toJson(): JsonObject = JsonObject(
        mapOf(
            "viz" to JsonPrimitive(viz), "style" to JsonPrimitive(style), "slow" to JsonPrimitive(slow),
            "shuffleEvery" to JsonPrimitive(shuffleEvery), "shufflePool" to JsonPrimitive(shufflePool),
        ),
    )

    companion object {
        val STYLES = listOf("bars" to "Bars", "waves" to "Waves", "drift" to "Drift")
        val SHUFFLE_CHOICES = listOf(0, 15, 30, 60, 120, 300, 600)

        // Anything odd is put right: a style the website doesn't know stays, as its plugin may.
        fun read(saved: JsonElement?): VisualizerPrefs {
            val s = saved as? JsonObject ?: return VisualizerPrefs()
            fun prim(key: String) = s[key] as? JsonPrimitive
            val style = prim("style")?.takeIf { it.isString }?.content?.takeIf { it.length <= 48 } ?: "bars"
            val every = prim("shuffleEvery")?.takeIf { !it.isString }?.doubleOrNull
            return VisualizerPrefs(
                viz = prim("viz")?.booleanOrNull != false,
                style = style,
                slow = prim("slow")?.takeIf { !it.isString }?.booleanOrNull == true,
                shuffleEvery = SHUFFLE_CHOICES.firstOrNull { it.toDouble() == every } ?: 0,
                shufflePool = if (prim("shufflePool")?.takeIf { it.isString }?.content == "all") "all" else "mine",
            )
        }

        // "Off: stay on this one", "Every 15 seconds", "Every minute", "Every 2 minutes".
        fun everyWords(seconds: Int): String = when {
            seconds == 0 -> "Off: stay on this one"
            seconds < 60 -> "Every $seconds seconds"
            seconds == 60 -> "Every minute"
            else -> "Every ${seconds / 60} minutes"
        }

        // The Styles chip: the interval without "Every ", or "Styles" when it stays still.
        fun chipWords(seconds: Int): String = if (seconds > 0) everyWords(seconds).removePrefix("Every ") else "Styles"
    }
}

// What the lyrics panel says, in the website's words (LyricsPanel.tsx).
object LyricWords {
    // When a song has no words (`NoLyrics`). The last case has the website's two links: Settings and How lyrics work.
    fun none(lyrics: Lyrics): List<String> = when {
        lyrics.failed.isNotEmpty() -> listOf("The lyrics source couldn't be reached just now. It'll be tried again next time this song is opened.")
        lyrics.tried -> listOf(("No words found for this song online. " + if (lyrics.canEdit) "Fix lets you search under another name, or add them yourself." else "").trim())
        lyrics.online -> listOf("No words found for this song.")
        else -> listOf(
            "No words here. A .lrc file with the same name as the song, beside it, is used first.",
            if (lyrics.canEdit) "Or find them online for free, if you agree: turn on online lyrics in Settings. Your server sends only the artist, title, album and length."
            else "Whoever runs this server can also turn on finding them online.",
        )
    }

    // The timing between Sooner and Later: "On time", or "+0.25 s".
    fun offset(ms: Double): String = if (ms == 0.0) "On time" else "${if (ms > 0) "+" else ""}${String.format(Locale.ROOT, "%.2f", ms / 1000)} s"

    // A nudge, kept within two minutes either way.
    fun nudge(ms: Double, by: Double): Double = (ms + by).coerceIn(-120_000.0, 120_000.0)
}

// Fixing the words: Edit's draft and Tap along's file (LyricsPanel.tsx).
object LyricFile {
    // Where the words came from that Start over can take back to what was found.
    val STARTS_OVER = setOf("override", "lrclib", "mirror", "musixmatch")

    // An LRC time: "01:02.50".
    fun stamp(ms: Double): String {
        val t = maxOf(0L, ms.toLong())
        return String.format(Locale.ROOT, "%02d:%02d.%02d", t / 60000, (t / 1000) % 60, (t % 1000) / 10)
    }

    // Tap along's lines: the words, one line each, without the blank ones.
    fun lines(text: String): List<String> = text.split("\n").map { it.trim() }.filter { it.isNotEmpty() }

    // The timed lines as a file.
    fun lrc(times: List<Double>, lines: List<String>): String = times.zip(lines).joinToString("\n") { (t, line) -> "[${stamp(t)}]$line" } + "\n"

    // What Edit starts with: the timed lines, or the plain words.
    fun draft(lyrics: Lyrics): String = lyrics.timed.let { timed -> if (timed.isEmpty()) lyrics.plain else timed.joinToString("\n") { "[${stamp(it.t)}]${it.text}" } }

    // What Tap along times: the timed lines' words, or the plain words.
    fun tapText(lyrics: Lyrics): String = lyrics.timed.let { timed -> if (timed.isEmpty()) lyrics.plain else timed.joinToString("\n") { it.text } }
}
