// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import java.util.Locale

// What a channel's player says about each audio, subtitle or picture choice, in plain words (the WittyTV player's Dock:
// docs/plans/DESIGN-2.md, section 4, "Banner and mini guide"). One rule for the words, so every choice reads alike.
data class TrackInfo(
    val language: String? = null,
    val label: String? = null,
    val channels: Int = 0,
    val height: Int = 0,
    val bitrate: Int = 0,
)

object TrackLabels {
    private fun language(code: String?): String? {
        if (code.isNullOrBlank() || code == "und") return null
        val name = Locale.forLanguageTag(code).getDisplayLanguage(Locale.ENGLISH)
        return name.takeIf { it.isNotBlank() && it != code } ?: code
    }

    private fun layout(channels: Int) = when (channels) {
        0 -> null
        1 -> "Mono"
        2 -> "Stereo"
        6 -> "5.1"
        8 -> "7.1"
        else -> "$channels channels"
    }

    // "English, 5.1", or the stream's own label, or "Track 2" when it says nothing.
    fun audio(t: TrackInfo, number: Int): String {
        val own = t.label?.takeIf { it.isNotBlank() }
        val parts = listOfNotNull(language(t.language) ?: own, layout(t.channels)).distinct()
        return parts.joinToString(", ").ifEmpty { "Track $number" }
    }

    fun subtitle(t: TrackInfo, number: Int): String {
        val own = t.label?.takeIf { it.isNotBlank() }
        return language(t.language)?.let { l -> if (own != null && own != l && !own.startsWith(l)) "$l ($own)" else l } ?: own ?: "Subtitles $number"
    }

    // "1080p" for a picture's height; the bitrate in Mb/s when two pictures are as tall.
    fun quality(t: TrackInfo, sameHeightAsOther: Boolean = false): String {
        val p = if (t.height > 0) "${t.height}p" else "Picture"
        return if (sameHeightAsOther && t.bitrate > 0) "$p, %.1f Mb/s".format(Locale.ROOT, t.bitrate / 1_000_000.0) else p
    }
}
