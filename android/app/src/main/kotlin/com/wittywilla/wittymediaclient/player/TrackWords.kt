// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.Track
import java.util.Locale

// How a video's sound tracks and subtitles are named in every native player: the TV's lists, the phone's tiles and
// the one-line labels a watch party shows. The same rule is in apple/WittyKit (PlayerLook.swift, TrackWords) and
// follows the website's picker (web/src/player/VideoPlayer.tsx): the language first, then the track's own name,
// then what kind it is. A track nobody labelled is "Track 2" or "Subtitles 2", never "Unknown".
data class TrackName(val title: String, val sub: String, val detail: String) {
    val line: String get() = listOf(title, sub, detail).filter { it.isNotEmpty() }.joinToString(" · ")
}

object TrackWords {
    // The older three-letter codes files carry, which Locale doesn't know by those letters.
    private val bibliographic = mapOf(
        "alb" to "sq", "arm" to "hy", "baq" to "eu", "bur" to "my", "chi" to "zh", "cze" to "cs", "dut" to "nl",
        "fre" to "fr", "geo" to "ka", "ger" to "de", "gre" to "el", "ice" to "is", "mac" to "mk", "mao" to "mi",
        "may" to "ms", "per" to "fa", "rum" to "ro", "slo" to "sk", "tib" to "bo", "wel" to "cy",
    )
    private val threeLetter: Map<String, String> by lazy {
        Locale.getISOLanguages().mapNotNull { two -> runCatching { Locale(two).isO3Language to two }.getOrNull() }
            .filter { it.first.isNotEmpty() }.toMap()
    }

    // "English" for eng, en, en-US or English's own name from the server; "" when there's no language to name.
    fun language(t: Track): String {
        t.languageName.trim().takeIf { it.isNotEmpty() }?.let { return it }
        return languageOf(t.language)
    }

    fun languageOf(code: String): String {
        val raw = code.trim().lowercase(Locale.ROOT).split('-', '_').firstOrNull().orEmpty()
        if (raw.isEmpty() || raw == "und" || raw == "unknown" || raw == "zxx" || raw == "mul") return ""
        val two = bibliographic[raw] ?: threeLetter[raw] ?: raw
        val name = Locale(two).getDisplayLanguage(Locale.ENGLISH)
        return if (name.isBlank() || name.equals(two, ignoreCase = true)) code.trim() else name
    }

    fun channels(n: Int): String = when (n) {
        0 -> ""
        1 -> "Mono"
        2 -> "Stereo"
        6 -> "5.1"
        8 -> "7.1"
        else -> "$n channels"
    }

    // Subtitles' formats in words: nobody knows what SUBRIP or HDMV_PGS_SUBTITLE means.
    fun subtitleKind(codec: String): String {
        val c = codec.lowercase(Locale.ROOT)
        return when {
            c == "ass" || c == "ssa" -> "Styled text"
            Regex("pgs|dvd_?sub|dvb_?sub|vobsub|xsub").containsMatchIn(c) -> "Pictures"
            c.isNotEmpty() -> "Text"
            else -> ""
        }
    }

    // The track's own name, when it says more than the language does.
    private fun own(t: Track, language: String): String {
        val title = t.title.trim()
        if (title.isEmpty()) return ""
        val l = title.lowercase(Locale.ROOT)
        return if (l == language.lowercase(Locale.ROOT) || l == t.language.trim().lowercase(Locale.ROOT)) "" else title
    }

    private fun marks(t: Track, title: String): List<String> = listOfNotNull(
        "Forced".takeIf { t.forced && !title.contains("forced", ignoreCase = true) },
        "SDH".takeIf { t.sdh && !title.contains("sdh", ignoreCase = true) && !title.contains("hearing", ignoreCase = true) },
        "Commentary".takeIf { t.commentary && !title.contains("comment", ignoreCase = true) },
    )

    private fun name(t: Track, number: Int, fallback: String, detail: String): TrackName {
        val language = language(t)
        val own = own(t, language)
        val title = language.ifEmpty { own.ifEmpty { "$fallback $number" } }
        val sub = (listOf(if (language.isEmpty()) "" else own) + marks(t, own)).filter { it.isNotEmpty() }.joinToString(" · ")
        return TrackName(title, sub, detail)
    }

    // `number` counts from 1 in the list as shown.
    fun audio(t: Track, number: Int): TrackName =
        name(t, number, "Track", listOf(t.codec.uppercase(Locale.ROOT), channels(t.channels)).filter { it.isNotEmpty() }.joinToString(" · "))

    fun subtitle(t: Track, number: Int): TrackName = name(t, number, "Subtitles", subtitleKind(t.codec))

    // Lists as shown: one row per track, numbered from 1.
    fun audioList(tracks: List<Track>): List<Pair<Track, TrackName>> = tracks.distinctBy { it.index }.mapIndexed { i, t -> t to audio(t, i + 1) }
    fun subtitleList(tracks: List<Track>): List<Pair<Track, TrackName>> = tracks.distinctBy { it.index }.mapIndexed { i, t -> t to subtitle(t, i + 1) }
}
