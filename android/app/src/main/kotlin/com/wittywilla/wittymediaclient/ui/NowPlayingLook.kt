package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.LyricLine
import com.wittywilla.wittymediaclient.net.Lyrics
import com.wittywilla.wittymediaclient.net.lineIndex
import com.wittywilla.wittymediaclient.player.number
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import java.util.Locale

// The rest of the website's Now Playing, as rules apart from the screen so they can be tested: the visualizer's
// choices (web/src/audio/NowPlaying.tsx, backdrop.ts), the words (LyricsPanel.tsx, lyrics.ts) and karaoke
// (Karaoke.tsx). The iPhone has the
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

// A word of a line and when it's sung, in milliseconds.
data class TimedWord(val text: String, val from: Double, val to: Double)

// Karaoke's rules (Karaoke.tsx, lyrics.ts).
object Karaoke {
    // The voice: on, lower, lowest, as how much of the middle of the mix is taken away.
    val VOCALS = listOf(0.0 to "Voice on", 0.6 to "Voice lower", 1.0 to "Voice lowest")
    private const val COUNT_FROM_MS = 3000.0
    private const val LONG_GAP_MS = 5000.0

    // When each word of a line is sung (wordTimes): its own times, each to the next word or a second and a half on,
    // within the line; or the line's time spread by length over its words, each with the space after it, taking at
    // least 1.2 seconds and 95 ms a letter, but no longer than the line has.
    fun words(line: LyricLine, next: Double?): List<TimedWord> {
        val end = line.end ?: next ?: (line.t + 5000)
        val timed = line.words.orEmpty()
        if (timed.isNotEmpty()) {
            return timed.mapIndexed { at, word -> TimedWord(word.text, word.t, timed.getOrNull(at + 1)?.t ?: minOf(end, word.t + 1500)) }
        }
        val parts = ArrayList<String>()
        val current = StringBuilder()
        for (c in line.text) {
            current.append(c)
            if (c.isWhitespace()) { parts += current.toString(); current.clear() }
        }
        if (current.isNotEmpty()) parts += current.toString()
        val singing = minOf(end - line.t, maxOf(1200.0, line.text.length * 95.0))
        val total = parts.sumOf { it.length }.takeIf { it > 0 } ?: 1
        var at = line.t
        return parts.map { text ->
            val span = text.length.toDouble() / total * singing
            TimedWord(text, at, at + span).also { at += span }
        }
    }

    // How far through a word is, 0 to 1.
    fun fill(word: TimedWord, ms: Double): Double = when {
        ms <= word.from -> 0.0
        ms >= word.to -> 1.0
        else -> (ms - word.from) / maxOf(1.0, word.to - word.from)
    }

    // The count-in before a line after a break: 3, 2, 1, or 0 for none. Only when the next line is three seconds
    // off or less, nothing is being sung, and the last line began at least five seconds before it.
    fun countIn(lines: List<LyricLine>, ms: Double): Int {
        val at = lineIndex(lines, ms)
        val up = lines.getOrNull(at + 1) ?: return 0
        val here = lines.getOrNull(at)
        val left = up.t - ms
        val quiet = here == null || up.t - (here.end ?: here.t) > 0 || here.text.isEmpty()
        val longGap = here == null || up.t - here.t >= LONG_GAP_MS
        return if (left > 0 && left <= COUNT_FROM_MS && quiet && longGap) kotlin.math.ceil(left / 1000).toInt() else 0
    }

    // "Key +2", "Key 0".
    fun keyWords(semitones: Double): String = "Key ${if (semitones > 0) "+" else ""}${number(semitones)}"

    // "Words on time", "Words +0.3 s".
    fun timingWords(ms: Double): String = if (ms == 0.0) "Words on time" else "Words ${if (ms > 0) "+" else ""}${String.format(Locale.ROOT, "%.1f", ms / 1000)} s"

    // The line under the controls. `lineHasWordTimes` is whether the line being sung has its own word times.
    fun note(mono: Boolean, vocalCut: Double, keyShift: Double, timed: Boolean, lineHasWordTimes: Boolean): String = when {
        mono -> "This recording is close to mono, so there's no way to separate the voice from it."
        vocalCut > 0 -> "The voice is turned down by removing what's in the middle of the mix. Echoes of it, and songs that spread it wide, will still come through."
        keyShift != 0.0 -> "A changed key can warble a little on long notes."
        timed && !lineHasWordTimes -> "Lines are timed; the fill within a line is an estimate."
        else -> ""
    }
}
