// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.syncplay

import com.wittywilla.wittymediaclient.net.sseBackoffMs
import kotlin.math.abs

// A watch party's rules, apart from any player (docs/SYNCPLAY.md, For developers): where the room is, what a player
// that is out of step does about it, and what happens when the connection drops. The same rules as the server's
// internal/syncplay/clock.go and the website's web/src/player/sync.ts; the tests share their cases.

// Where the room is at a server time: it holds at positionSec while paused, waiting, or before a start set in the
// future, and moves on from there at the room's speed otherwise.
fun roomPositionSec(state: RoomState, serverNowMs: Double): Double =
    if (state.paused || state.waiting || serverNowMs <= state.atMs) state.positionSec
    else state.positionSec + (serverNowMs - state.atMs) / 1000.0 * state.rate

// Whether the room is moving at this server time.
fun roomMoving(state: RoomState, serverNowMs: Double): Boolean = !state.paused && !state.waiting && serverNowMs > state.atMs

// What to do about being out of step: play at `rate` (a multiple of the room's speed), or jump by seekBySec.
data class Step(val rate: Double, val seekBySec: Double = 0.0)

// The drift rule. behind: seconds this player is behind the room (negative: ahead). nudging: whether it is already
// playing faster or slower, which carries on until it has settled rather than stopping when merely close.
fun correct(behind: Double, nudging: Boolean, drift: Drift = Drift()): Step {
    val off = abs(behind)
    if (off >= drift.seekSec) return Step(1.0, behind)
    if (off < (if (nudging) drift.settledSec else drift.stillSec)) return Step(1.0)
    return Step(if (behind > 0) 1 + drift.rate else 1 - drift.rate)
}

// What the player should be doing right now.
sealed interface SyncAct {
    // Paused, at the room's place: seek there first when given.
    data class Hold(val seekToSec: Double?) : SyncAct
    // Playing at this speed (the room's, or nudged), after a jump when given.
    data class Play(val speed: Double, val seekToSec: Double?, val nudging: Boolean) : SyncAct
}

// How far from the room's place a paused or waiting player may rest before it is moved.
const val HOLD_SLACK_SEC = 0.5

// One look, about twice a second. filmSec is where this player is in the film (not in its stream: see
// filmFromPlayer). loadSec is how long this player's jumps have been taking, so a jump while the room is moving
// lands where the room will be, not where it was.
fun decide(state: RoomState, serverNowMs: Double, filmSec: Double, nudging: Boolean, drift: Drift = Drift(), loadSec: Double = 0.0): SyncAct {
    if (!roomMoving(state, serverNowMs)) {
        return SyncAct.Hold(if (abs(filmSec - state.positionSec) > HOLD_SLACK_SEC) state.positionSec else null)
    }
    val room = roomPositionSec(state, serverNowMs)
    val step = correct(room - filmSec, nudging, drift)
    if (step.seekBySec != 0.0) return SyncAct.Play(state.rate, room + loadSec.coerceIn(0.0, MAX_AIM_AHEAD_SEC) * state.rate, false)
    return SyncAct.Play(state.rate * step.rate, null, step.rate != 1.0)
}

const val MAX_AIM_AHEAD_SEC = 8.0

// A player's clock and the film's are the same for a file played as it is. A stream the server converts from the
// middle (HLS started at an offset) counts from 0 at that place: `timeOffsetSec` in the playback answer is the
// difference, and every comparison with the room is made in the film's time.
fun filmFromPlayer(playerSec: Double, timeOffsetSec: Double): Double = (playerSec + timeOffsetSec).coerceAtLeast(0.0)

fun playerFromFilm(filmSec: Double, timeOffsetSec: Double): Double = filmSec - timeOffsetSec

// How a place in the film is reached in the stream that is open.
sealed interface SeekPlan {
    // The stream can't be moved at all (`seek: "none"`).
    data object None : SeekPlan
    data class InPlayer(val playerSec: Double) : SeekPlan
    // A growing stream that hasn't got there, or a place before where it starts: ask for a new one from there.
    data class NewStream(val startSec: Double) : SeekPlan
}

// seek is the playback answer's: "native" (anywhere), "restart" (only within what exists so far), "none".
// knownPlayerSec is how much of the stream the player knows of, or null when it doesn't say.
fun seekPlan(targetFilmSec: Double, timeOffsetSec: Double, seek: String, knownPlayerSec: Double?, durationSec: Double): SeekPlan {
    if (seek == "none") return SeekPlan.None
    val target = targetFilmSec.coerceIn(0.0, if (durationSec > 0) durationSec else Double.MAX_VALUE)
    val inPlayer = playerFromFilm(target, timeOffsetSec)
    val reachable = seek != "restart" || (inPlayer >= 0 && knownPlayerSec != null && inPlayer <= knownPlayerSec)
    return if (reachable) SeekPlan.InPlayer(inPlayer.coerceAtLeast(0.0)) else SeekPlan.NewStream(target)
}

// Which report, if any, this member owes the room: `ready` once its player has loaded the room's item, is near the
// room's place and could play; `buffering` when it stalls while the room plays. The room's own word for this member
// says whether it already knows, so a report lost on the way is simply sent again.
fun reportOwed(mine: String, rightItem: Boolean, playerReady: Boolean, nearSec: Double, roomMoving: Boolean): String? {
    val could = rightItem && playerReady && nearSec <= READY_WITHIN_SEC
    return when {
        could && mine != "ready" -> "ready"
        !could && mine == "ready" && roomMoving -> "buffering"
        else -> null
    }
}

const val READY_WITHIN_SEC = 2.0

// Room events can arrive out of order across a reconnect, or beside a command's own answer. The one with the
// highest rev is the truth; an older one is forgotten.
class RoomTracker {
    var room: Room? = null
        private set

    // True when this room replaced what was held.
    fun offer(next: Room): Boolean {
        val held = room
        if (held != null && held.id == next.id && next.state.rev < held.state.rev) return false
        room = next
        return true
    }

    fun clear() {
        room = null
    }
}

// A code as the server keeps it: capitals, with spaces, dashes and anything else that isn't a letter or digit gone.
fun normaliseCode(typed: String): String = typed.filter { it.isLetterOrDigit() }.uppercase()

// "KXM 4T7": easier to read out across a room.
fun spacedCode(code: String): String = if (code.length == 6) code.substring(0, 3) + " " + code.substring(3) else code

// What the members list says beside each person (docs/SYNCPLAY.md, While you watch).
fun memberWords(state: String): String = when (state) {
    "ready" -> "Ready"
    "loading" -> "Loading"
    "buffering" -> "Buffering"
    "lagging" -> "Catching up"
    "away" -> "Away"
    "blocked" -> "Can't watch this one"
    else -> ""
}

// Every refusal in docs/SYNCPLAY.md's table, as a sentence. The server's text for several is a program's, in
// lower case with no full stop, so these are the app's own.
fun syncErrorWords(status: Int, code: String, serverWords: String = ""): String = when (code) {
    "bad-request" -> "The watch party couldn't make sense of that."
    "disabled" -> "Watch parties are turned off on this server."
    "not-allowed" -> "This account can't start a watch party."
    "cant-watch" -> "This watch party is playing something this account can't watch."
    "host-only" -> "Only the host controls this watch party."
    "not-host" -> "Only the host can do that."
    "no-room" -> "No such watch party. Check the code."
    "not-member" -> "You no longer have a place in this watch party."
    "no-item" -> "That isn't in the library, or isn't something this account can watch."
    "stale" -> "Someone else changed the watch party first."
    "end-of-queue" -> "There's nothing more that way."
    "full" -> "This watch party has no seats left."
    "rate" -> if (status == 429 && serverWords.contains("tries", ignoreCase = true)) "Too many tries. Wait a minute, then try again." else "Slow down a little, then try again."
    "too-many" -> "There are too many watch parties, invitations or connections already. Close one and try again."
    else -> when (status) {
        413 -> "That was too long to send."
        429 -> "Too many tries. Wait a minute, then try again."
        else -> serverWords.trim().ifEmpty { "The server answered with an error ($status)." }
    }
}

// Why a party ended for this member (the stream's last event).
fun closedWords(reason: String): String = when (reason) {
    "closed" -> "The watch party has ended."
    "removed" -> "The host removed you from the watch party."
    "replaced" -> "This watch party was opened again from this device, so this player left it."
    "signed-out" -> "You were signed out, which left the watch party."
    "server-stopping" -> "The server is restarting, which ends watch parties."
    "gone" -> "Your place in the watch party was given up while the connection was down."
    else -> "The watch party has ended."
}

// A dropped stream (docs/SYNCPLAY.md, Seats, and coming back): the seat is kept for seatGraceSec, so within that
// this member joins again with the same device text, opens the stream again and measures the clock afresh. After
// it, or when the server says the room or the seat has gone, it's over.
sealed interface SeatStep {
    data class Rejoin(val afterMs: Long) : SeatStep
    data class Over(val reason: String) : SeatStep
}

class SeatLife(private val seatGraceSec: Int = 120) {
    private var failures = 0
    private var downSinceMs: Long? = null

    val reconnecting: Boolean get() = downSinceMs != null

    // The stream is open and the room has been heard from.
    fun opened() {
        failures = 0
        downSinceMs = null
    }

    // The stream dropped, or a rejoin failed for want of a network.
    fun dropped(nowMs: Long): SeatStep {
        val since = downSinceMs ?: nowMs.also { downSinceMs = it }
        if (nowMs - since > seatGraceSec * 1000L) return SeatStep.Over("gone")
        return SeatStep.Rejoin(sseBackoffMs(failures).also { failures++ })
    }

    // The server refused the rejoin or the stream.
    fun refused(status: Int, code: String, nowMs: Long): SeatStep = when {
        code == "no-room" || code == "not-member" || status == 404 -> SeatStep.Over("gone")
        code == "disabled" -> SeatStep.Over("closed")
        code == "cant-watch" || code == "full" -> SeatStep.Over("gone")
        status == 401 -> SeatStep.Over("signed-out")
        else -> dropped(nowMs)
    }
}
