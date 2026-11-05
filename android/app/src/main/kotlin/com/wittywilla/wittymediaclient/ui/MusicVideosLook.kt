package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.MusicLink
import com.wittywilla.wittymediaclient.net.MusicLinkSide
import com.wittywilla.wittymediaclient.net.MusicVideoCard
import java.net.URLEncoder
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

// The website's music videos, as rules apart from the screen so they can be tested: a music library's Music videos tab
// and its Home shelf (web/src/pages/music/MusicVideos.tsx, the video tile of creators/parts.tsx and gallery.ts), and Now
// Playing's Watch the video (audio/NowPlaying.tsx, music/links.ts). The iPhone has the same in WittyKit's MusicVideos.swift.

// Where the song under a music video goes: its album, when it's in this library and has one; else its artist.
sealed interface MusicVideoSongPlace {
    data class Album(val library: Long, val album: String, val artist: String) : MusicVideoSongPlace
    data class Artist(val library: Long, val name: String) : MusicVideoSongPlace
}

object MusicVideos {
    // How many the Music videos tab asks for at a time, and how many the Home shelf shows: the newest.
    const val PAGE_SIZE = 120
    const val SHELF_SIZE = 12

    // Whether there's anywhere music videos could come from: a music videos library this person can see. A music
    // library then has the Music videos tab and its shelf (`hasMusicVideos`).
    fun available(libraries: List<Library>): Boolean = libraries.any { it.type == "musicvideos" }

    // The tab's question: by artist, a page at a time, matching words when there are any, written as the website's
    // URLSearchParams writes them.
    fun path(search: String, offset: Int, limit: Int = PAGE_SIZE): String =
        "/music/videos?limit=$limit&offset=$offset" + if (search.isNotEmpty()) "&search=${URLEncoder.encode(search, "UTF-8")}" else ""

    // The Home shelf's question: the newest.
    const val LATEST_PATH = "/music/videos?limit=$SHELF_SIZE&sort=latest"

    // "1 video", "120+ videos": how many are showing, and whether there are more.
    fun count(n: Int, more: Boolean, locale: Locale = Locale.ROOT): String =
        "${java.text.NumberFormat.getIntegerInstance(locale).format(n)}${if (more) "+" else ""} ${if (n == 1) "video" else "videos"}"

    // What an empty tab says.
    fun empty(searching: Boolean): Pair<String, String> =
        if (searching) "Nothing matches that" to "" else "No music videos yet" to "Add a library of the kind Music videos & concerts, and its videos appear here by artist."

    fun songPlace(song: MusicLinkSide, library: Long): MusicVideoSongPlace =
        if (song.libraryId == library && song.album.isNotEmpty()) MusicVideoSongPlace.Album(library, song.album, song.artist)
        else MusicVideoSongPlace.Artist(song.libraryId, song.artist)

    // The words on the song under a tile: "On Its Album", or "In your music" for a song with no album.
    fun songWords(card: MusicVideoCard): String? {
        val song = card.song ?: return null
        return if (song.album.isNotEmpty()) "On ${song.album}" else "In your music"
    }

    // The website's viewsOf: what the source said, plus plays here.
    fun allViews(card: MusicVideoCard): Long = card.views + card.origViews

    // How far through it this person is, from 0 to 1: nothing once it's watched.
    fun progress(card: MusicVideoCard): Double =
        if (card.watched || card.durationSec <= 0 || card.positionSec <= 0) 0.0 else minOf(1.0, card.positionSec / card.durationSec)

    // "1.2K views · 3 weeks ago", as under a video tile.
    fun facts(card: MusicVideoCard, nowMs: Long = System.currentTimeMillis()): String =
        listOf(if (allViews(card) > 0) "${shortCount(allViews(card))} views" else "", ago(card.uploadDate, nowMs)).filter { it.isNotEmpty() }.joinToString(" · ")

    // Where to be in the other one (`placeIn`): the song's place in the video is the song's time plus where the song
    // starts in it. Null when they don't line up, or when that place is in the first second or the last two.
    fun place(inVideo: Boolean, at: Double, syncMs: Long?, length: Double): Double? {
        val offset = (syncMs ?: return null) / 1000.0
        val t = if (inVideo) at + offset else at - offset
        if (t < 1 || (length > 0 && t > length - 2)) return null
        return t
    }

    // A music video's page, from a place in it when there is one.
    fun watchPath(videoId: Long, at: Double? = null): String = if (at == null || at < 1) "/watch/$videoId" else "/watch/$videoId?t=${kotlin.math.floor(at).toLong()}"

    // Watch the video from a song that's playing: the video's page, at the same place when the two line up.
    fun watchPath(link: MusicLink, songAt: Double): String = watchPath(link.videoId, place(true, songAt, link.syncMs, link.video.runtimeSec))

    // 1234 to "1.2K" (`fmtCount`).
    fun shortCount(n: Long): String {
        fun short(value: Double, unit: String) = String.format(Locale.ROOT, "%.1f", value).removeSuffix(".0") + unit
        return when {
            n >= 1_000_000_000 -> short(n / 1e9, "B")
            n >= 1_000_000 -> short(n / 1e6, "M")
            n >= 1_000 -> short(n / 1e3, "K")
            else -> n.toString()
        }
    }

    // "today", "yesterday", "3 weeks ago" from a date the server writes as 2024-05-31 (`timeAgo`). Nothing for a date it
    // can't read.
    fun ago(date: String, nowMs: Long = System.currentTimeMillis()): String {
        val parts = date.split("-")
        if (parts.size !in 1..3 || parts[0].length != 4 || parts.drop(1).any { it.length != 2 } || parts.any { p -> p.any { it !in '0'..'9' } }) return ""
        val month = parts.getOrNull(1)?.toInt() ?: 1
        val day = parts.getOrNull(2)?.toInt() ?: 1
        if (month !in 1..12 || day !in 1..31) return ""
        val then = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply { clear(); set(parts[0].toInt(), month - 1, day) }.timeInMillis
        val days = kotlin.math.floor((nowMs - then) / 86_400_000.0).toLong()
        return when {
            days < 1 -> "today"
            days < 2 -> "yesterday"
            days < 7 -> "$days days ago"
            days < 30 -> "${days / 7} ${if (days < 14) "week" else "weeks"} ago"
            days < 365 -> "${days / 30} ${if (days < 60) "month" else "months"} ago"
            else -> "${days / 365} ${if (days < 730) "year" else "years"} ago"
        }
    }

    // A creator with no picture: their initial on a colour of their own, from their name (`hsl(h 35% 36%)`), the hue
    // from each of the name's characters in turn.
    fun avatarHue(name: String): Int {
        var h = 0
        var i = 0
        while (i < name.length) {
            val c = name[i]
            h = (h * 31 + c.code) % 360
            i += if (c.isHighSurrogate() && i + 1 < name.length && name[i + 1].isLowSurrogate()) 2 else 1
        }
        return h
    }
}
