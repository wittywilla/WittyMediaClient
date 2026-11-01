package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.Item
import java.util.Locale

// The listening player's decisions, apart from its service and its screens, so they can be tested without
// either. docs/CLIENT-API.md leaves these to the client.

data class Start(val index: Int, val atSec: Double = 0.0)

// A saved place on a track, or 0. Songs always start over.
fun placeOn(track: Item, keepsPlace: Boolean): Double {
    val progress = track.progress ?: return 0.0
    return if (keepsPlace && !progress.watched) progress.positionSec.coerceAtLeast(0.0) else 0.0
}

// Which track Play means: the one last left in the middle, else the first not finished, else the first again.
fun whereToStart(tracks: List<Item>, keepsPlace: Boolean): Start {
    if (!keepsPlace) return Start(0)
    val middle = tracks.indices.filter { placeOn(tracks[it], true) > 0 }.maxByOrNull { tracks[it].progress?.updatedAt ?: 0 }
    if (middle != null) return Start(middle, placeOn(tracks[middle], true))
    val unfinished = tracks.indexOfFirst { it.progress?.watched != true }
    return Start(unfinished.coerceAtLeast(0))
}

// Has this one been started, so that the button should say Resume and offer Start over?
fun hasPlaceToResume(tracks: List<Item>, keepsPlace: Boolean): Boolean =
    keepsPlace && tracks.any { placeOn(it, true) > 0 || it.progress?.watched == true } && tracks.any { it.progress?.watched != true }

private val SPEEDS = listOf(0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f)

fun nextSpeed(now: Float): Float = SPEEDS.firstOrNull { it > now + SAME_SPEED } ?: SPEEDS.first()

private const val SAME_SPEED = 0.01f

// "1.5×", and no longer than it needs to be.
fun speedWords(speed: Float): String = String.format(Locale.ROOT, "%.2f", speed).trimEnd('0').trimEnd('.') + "×"

// A song counts as played once it's been heard for this long: the same as the web player.
const val COUNTS_AS_LISTENED_SEC = 5.0

// What to tell the server when a track stops playing: where it got to for what keeps its place, and how
// long it was heard for songs. Moving on by itself means the end was reached, which marks it as finished.
sealed interface Report {
    data class Place(val positionSec: Double, val durationSec: Double) : Report
    data class Listened(val seconds: Double) : Report
}

fun reportOn(keepsPlace: Boolean, positionSec: Double, durationSec: Double, listenedSec: Double, reachedEnd: Boolean): Report? {
    if (!keepsPlace) return if (listenedSec >= COUNTS_AS_LISTENED_SEC) Report.Listened(listenedSec) else null
    if (durationSec <= 0) return null
    if (reachedEnd) return Report.Place(durationSec, durationSec)
    // A place in the first few seconds isn't worth saving: the rule every client shares.
    return if (positionSec >= PlaybackClock.NOT_BEFORE_SEC) Report.Place(positionSec, durationSec) else null
}

// The order a queue will play in. `next` is the player's own answer, as it knows the shuffle order.
inline fun playOrder(first: Int, count: Int, next: (Int) -> Int): List<Int> {
    val order = ArrayList<Int>(count)
    var at = first
    while (at in 0 until count && order.size < count) {
        order += at
        at = next(at)
    }
    return order
}

// A converted stream is an endless pipe from the server: it has no bytes to seek to, only a start time to ask for.
// The player is told it's a file of this many bytes a second, and the byte it asks for says the time to start from.
// The bitrate is only a shared scale. Times on screen come from the stream's own frames.
const val CONVERTED_BYTES_PER_SEC = 24_000L

fun convertedPosition(timeUs: Long): Long = timeUs * CONVERTED_BYTES_PER_SEC / 1_000_000L

fun convertedStartSec(position: Long): Double = position.toDouble() / CONVERTED_BYTES_PER_SEC
