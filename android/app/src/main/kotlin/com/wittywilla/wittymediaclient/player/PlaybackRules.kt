package com.wittywilla.wittymediaclient.player

import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import com.wittywilla.wittymediaclient.net.Track

// The player's decisions, apart from its screen, so they can be tested without one. The same rules
// as WittyKit's PlaybackRules.swift on Apple devices.

// Where the viewer is in the film. The old stream's time means nothing once a new one has been
// asked for, so nothing is read or saved from then until the new one is ready.
class PlaybackClock {
    var filmSec = 0.0
        private set
    private var lastSaved: Double? = null
    private var settled = false
    private var everSettled = false

    fun switching() {
        settled = false
    }

    fun ready() {
        settled = true
        everSettled = true
    }

    // The player's time, about once a second. True means: save now.
    fun tick(playerSec: Double, offsetSec: Double, playing: Boolean): Boolean {
        if (!settled || !playerSec.isFinite() || !offsetSec.isFinite()) return false
        filmSec = maxOf(0.0, playerSec + offsetSec)
        if (!playing || filmSec < NOT_BEFORE_SEC) return false
        val last = lastSaved
        if (last != null && kotlin.math.abs(filmSec - last) < SAVE_EVERY_SEC) return false
        lastSaved = filmSec
        return true
    }

    // Leaving, pausing or moving on: where to save, or null when nothing here is worth saving.
    fun lastPlace(): Double? = if (everSettled && filmSec >= NOT_BEFORE_SEC) filmSec else null

    companion object {
        const val SAVE_EVERY_SEC = 10.0
        const val NOT_BEFORE_SEC = 5.0
    }
}

// Trying again without doing it for ever: a stream that plays for a moment and fails again each
// time mustn't loop. Only half a minute of real playing earns the tries back.
class RetryBudget {
    private var used = 0
    private var goodSec = 0.0

    // How long to wait before trying again, or null to give up.
    fun next(): Long? {
        if (used >= ATTEMPTS) return null
        used++
        goodSec = 0.0
        return if (used == 1) 1_000L else used * 2_000L
    }

    fun played(sec: Double) {
        goodSec += sec
        if (goodSec >= GOOD_AFTER_SEC) used = 0
    }

    fun reset() {
        used = 0
        goodSec = 0.0
    }

    companion object {
        const val ATTEMPTS = 3
        const val GOOD_AFTER_SEC = 30.0
    }
}

// What to do about a failure: docs/CLIENT-API.md, "What a TV app must build itself".
enum class Recovery {
    NewStream, // a 401 needs a new token, a 404 means the stream went away, or the live window passed
    WaitThenNewStream, // a busy server (503) or a connection that dropped
    Convert, // this device can't decode what it was sent: ask for a conversion
    GiveUp,
}

// Frame processing failures are named by an API Media3 still marks as unstable.
@OptIn(UnstableApi::class)
fun recoveryFor(errorCode: Int, httpStatus: Int?): Recovery = when {
    httpStatus == 401 || httpStatus == 404 -> Recovery.NewStream
    httpStatus == 503 || httpStatus == 429 -> Recovery.WaitThenNewStream
    errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> Recovery.NewStream
    errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
        errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ||
        errorCode == PlaybackException.ERROR_CODE_IO_UNSPECIFIED ||
        errorCode == PlaybackException.ERROR_CODE_TIMEOUT -> Recovery.WaitThenNewStream
    errorCode == PlaybackException.ERROR_CODE_DECODER_INIT_FAILED ||
        errorCode == PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED ||
        errorCode == PlaybackException.ERROR_CODE_DECODING_FAILED ||
        errorCode == PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES ||
        errorCode == PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED ||
        errorCode == PlaybackException.ERROR_CODE_AUDIO_TRACK_INIT_FAILED ||
        errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED ||
        errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED ||
        errorCode == PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED -> Recovery.Convert
    else -> Recovery.GiveUp
}

// In plain words. The code goes in the log, not on the screen.
fun failureWords(errorCode: Int, httpStatus: Int?): String = when {
    httpStatus == 403 -> "This profile isn't allowed to play this."
    httpStatus == 503 -> "The server is busy. Try again in a moment."
    httpStatus != null && httpStatus >= 500 -> "The server had a problem playing this."
    httpStatus != null -> "The server wouldn't play this."
    recoveryFor(errorCode, null) == Recovery.WaitThenNewStream -> "Lost contact with your server. Check that it is running, then try again."
    recoveryFor(errorCode, null) == Recovery.Convert -> "This device can't play this, even after the server converted it."
    else -> "This can't be played."
}

// How far a press moves along the bar: a held key picks up speed.
fun seekStepSec(repeatCount: Int): Double = when {
    repeatCount < 8 -> 10.0
    repeatCount < 24 -> 30.0
    else -> 60.0
}

// Is the watch-next prompt due? 30 seconds before the end, when there's something next.
fun watchNextDue(filmSec: Double, durationSec: Double, hasNext: Boolean): Boolean =
    hasNext && durationSec > WATCH_NEXT_BEFORE_END_SEC && filmSec >= durationSec - WATCH_NEXT_BEFORE_END_SEC

const val WATCH_NEXT_BEFORE_END_SEC = 30.0

fun clock(sec: Double): String {
    val total = sec.toLong().coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

// The same clock for a screen reader: "1 hour 2 minutes 3 seconds".
fun spokenClock(sec: Double): String {
    val total = sec.toLong().coerceAtLeast(0)
    val parts = ArrayList<String>(3)
    fun add(n: Long, word: String) { if (n > 0) parts += "$n $word${if (n == 1L) "" else "s"}" }
    add(total / 3600, "hour")
    add((total % 3600) / 60, "minute")
    add(total % 60, "second")
    return if (parts.isEmpty()) "0 seconds" else parts.joinToString(" ")
}

object TrackMatch {
    private val TWO_LETTER = mapOf(
        "eng" to "en", "fre" to "fr", "fra" to "fr", "ger" to "de", "deu" to "de", "spa" to "es", "ita" to "it", "por" to "pt", "dut" to "nl", "nld" to "nl",
        "rus" to "ru", "jpn" to "ja", "kor" to "ko", "chi" to "zh", "zho" to "zh", "ara" to "ar", "hin" to "hi", "pol" to "pl", "tur" to "tr", "swe" to "sv",
        "nor" to "no", "nob" to "no", "nno" to "no", "dan" to "da", "fin" to "fi", "gre" to "el", "ell" to "el", "heb" to "he", "hun" to "hu", "cze" to "cs",
        "ces" to "cs", "rum" to "ro", "ron" to "ro", "tha" to "th", "vie" to "vi", "ind" to "id", "ukr" to "uk", "bul" to "bg", "hrv" to "hr", "slo" to "sk", "slk" to "sk",
    )

    // "eng", "en" and "en-US" all come out as "en". Empty for unknown.
    fun base(language: String?): String {
        val text = language.orEmpty().lowercase().split('-', '_').first()
        if (text == "und" || text == "unknown") return ""
        return TWO_LETTER[text] ?: text
    }

    // The language to ask the player for, or null when there's none to go on.
    fun languageFor(track: Track?): String? = base(track?.language).ifEmpty { null }
}
