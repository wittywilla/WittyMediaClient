// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.syncplay

import com.wittywilla.wittymediaclient.net.Item
import kotlin.math.abs

// Keeping one player in step with a room (docs/SYNCPLAY.md, A client's loop), with nothing of the player, the network
// or the clock in it: the player's facts and the room go in about twice a second and whenever the room changes, and
// orders come out. The same tick as the website's (web/src/remote/party.ts) and the Apple app's SyncFollower, so the
// three keep the same company in a room.

// What the player says of itself at one look.
data class PlayerFacts(
    // Where it is in the film (not in its stream: see filmFromPlayer), in seconds.
    val positionSec: Double,
    // Not playing and not trying to.
    val paused: Boolean,
    // It has the room's item open at all.
    val loaded: Boolean = true,
    // It has enough to play from where it is.
    val canPlay: Boolean = true,
    // A jump it was told to make hasn't landed yet.
    val seeking: Boolean = false,
    val ended: Boolean = false,
    // A jump is quick (a file, or a stream listed whole), so a paused picture can be put on the exact frame. False for
    // a stream the server starts again from wherever it's sent.
    val cheapSeek: Boolean = true,
)

// What to do after a look. Anything left null or false stays as it is.
data class SyncOrders(
    val pause: Boolean = false,
    val play: Boolean = false,
    // The speed to play at: the room's, times the nudge.
    val rate: Double? = null,
    // A place in the film to jump to.
    val seekTo: Double? = null,
    // Look again after this many milliseconds: a start set for a moment from now is kept to the millisecond.
    val againInMs: Long? = null,
    // "ready" or "buffering", to tell the room, with rev.
    val report: String? = null,
    val rev: Long = 0,
    // How far behind the room this player is, in seconds (negative: ahead). Null while the room holds still.
    val behind: Double? = null,
)

class SyncFollower(var drift: Drift = Drift()) {
    var nudging = false
        private set

    // How long the last jump took, in seconds: a jump while the room moves aims that much ahead.
    var lagSec = 0.0
        private set
    private var seekAtMs: Double? = null
    // A paused picture is sent to one place once: if it can't get there (past the end), asking again won't help.
    private var lastStill: Double? = null
    private var saidAtMs = Double.NEGATIVE_INFINITY
    private var stalledSinceMs: Double? = null

    // Another item was opened: nothing about the last one's jumps or stalls carries over.
    fun reset() {
        nudging = false
        seekAtMs = null
        lastStill = null
        stalledSinceMs = null
    }

    // `mine` is the room's word for this member ("ready", "loading"...), null when the room doesn't list it yet.
    fun tick(state: RoomState, mine: String?, serverNowMs: Double, localMs: Double, player: PlayerFacts): SyncOrders {
        if (!player.loaded) return SyncOrders(rev = state.rev)
        val target = roomPositionSec(state, serverNowMs)
        val moving = roomMoving(state, serverNowMs)
        var pause = false
        var play = false
        var rate: Double? = null
        var seekTo: Double? = null
        var again: Long? = null
        var behind: Double? = null

        fun jump(whileMoving: Boolean) {
            // Another isn't tried until the last has had its chance: a converted stream starts again from the new
            // place, which takes seconds.
            if (player.seeking) return
            seekAtMs?.let { if (localMs - it < RETRY_SEEK_MS) return }
            if (!whileMoving) {
                if (lastStill == target) return
                lastStill = target
            } else {
                lastStill = null
            }
            seekAtMs = localMs
            seekTo = (target + if (whileMoving) lagSec.coerceIn(0.0, MAX_AIM_AHEAD_SEC) * state.rate else 0.0).coerceAtLeast(0.0)
        }

        if (!moving) {
            if (!player.paused) pause = true
            if (abs(target - player.positionSec) > (if (player.cheapSeek) STILL_EXACT_SEC else HOLD_SLACK_SEC)) jump(false)
            // A start set in the future: look again on the moment rather than at the next tick.
            if (!state.paused && !state.waiting && serverNowMs <= state.atMs) again = (state.atMs - serverNowMs).toLong().coerceAtLeast(0)
            if (nudging) {
                nudging = false
                rate = state.rate
            }
        } else if (!player.ended) {
            if (player.paused) play = true
            val off = target - player.positionSec
            behind = off
            val step = correct(off, nudging, drift)
            if (step.seekBySec != 0.0) {
                jump(true)
                nudging = false
                rate = state.rate
            } else {
                nudging = step.rate != 1.0
                rate = state.rate * step.rate
            }
        }

        // Telling the room how this player is doing, when the room has it wrong.
        val ready = player.canPlay && !player.seeking && abs(target - player.positionSec) <= READY_WITHIN_SEC
        if (ready) {
            stalledSinceMs = null
            seekAtMs?.let {
                lagSec = ((localMs - it) / 1000.0).coerceIn(0.0, MAX_AIM_AHEAD_SEC)
                seekAtMs = null
            }
        } else if (moving && stalledSinceMs == null) {
            stalledSinceMs = localMs
        }
        var report: String? = null
        if (mine != null && localMs - saidAtMs >= REPORT_GAP_MS) {
            val stalledLong = stalledSinceMs?.let { localMs - it > STALL_MS } == true
            if (ready && mine != "ready") report = "ready"
            else if (!ready && moving && mine == "ready" && stalledLong) report = "buffering"
            if (report != null) saidAtMs = localMs
        }
        return SyncOrders(pause, play, rate, seekTo, again, report, state.rev, behind)
    }

    companion object {
        // A paused picture on a quick stream is put on the frame; on one the server converts, near enough is enough.
        const val STILL_EXACT_SEC = 0.08
        const val RETRY_SEEK_MS = 5000.0
        const val REPORT_GAP_MS = 1000.0
        // A stall shorter than this is the player catching its breath, not something to hold the room for.
        const val STALL_MS = 800.0
    }
}

// The room's queue, as the party's panel steps through it.
val Room.hasNext: Boolean get() = state.index + 1 < queue.size
val Room.hasPrevious: Boolean get() = state.index > 0

// Kinds of item this app's video player keeps in step. A party moved on to anything else is sat out, with the place kept.
fun keepsInStep(kind: String): Boolean = kind == "video" || kind.isEmpty()

// The kind of what a room plays now, as far as this member may see it.
val Room.nowKind: String get() = items.firstOrNull { it.id == state.itemId && it.id != 0L }?.kind.orEmpty()

// A queue with one entry taken out, as the `queue` command wants it: the item playing stays where it is in the
// queue, so taking out another doesn't interrupt it. Null when the entry is the one playing, or not there.
fun queueWithout(room: Room, index: Int): Pair<List<Long>, Int>? {
    if (index !in room.queue.indices || index == room.state.index) return null
    val items = room.queue.filterIndexed { i, _ -> i != index }
    return items to if (index < room.state.index) room.state.index - 1 else room.state.index
}

// One entry moved up (-1) or down (+1), and where the playing one ends up.
fun queueMoved(room: Room, index: Int, by: Int): Pair<List<Long>, Int>? {
    val to = index + by
    if (index !in room.queue.indices || to !in room.queue.indices) return null
    val items = room.queue.toMutableList()
    items.add(to, items.removeAt(index))
    val playing = when (room.state.index) {
        index -> to
        to -> index
        else -> room.state.index
    }
    return items to playing
}

// Whether this member may change the queue: a controller whose account can see every title in it.
fun canEditQueue(room: Room): Boolean = room.canControl && room.queue.none { it == 0L }

// What a party started on a title plays: an episode queues the rest of its season after it, in order, so the party
// moves on by itself when one ends; anything else is the title alone. At most `max` in all, as the server allows.
fun partyQueue(item: Item, episodes: List<Item>, max: Int = 200): List<Long> {
    val season = item.season ?: return listOf(item.id)
    if (item.showId == null) return listOf(item.id)
    val after = episodes
        .filter { it.showId == item.showId && it.season == season && it.id != item.id && (it.episode ?: 0) > (item.episode ?: 0) }
        .sortedWith(compareBy({ it.episode ?: 0 }, { it.id }))
        .map { it.id }
        .distinct()
    return (listOf(item.id) + after).take(max.coerceAtLeast(1))
}

// The server's clock for a party, before and after the pings have measured it: the room's own serverTimeMs is a
// guess good to a round trip, kept until the first ping answers.
class PartyClock {
    private val keeper = ClockKeeper()
    private var guessMs: Double? = null

    fun guess(serverTimeMs: Long, localMs: Double) {
        if (serverTimeMs > 0) guessMs = serverTimeMs - localMs
    }

    fun add(sample: ClockSample) = keeper.add(sample)

    fun serverNow(localMs: Double): Double = keeper.best?.let { localMs + it.offsetMs } ?: (localMs + (guessMs ?: 0.0))

    val rttMs: Double get() = keeper.rttMs

    fun nextPingMs(pingEverySec: Int): Long = keeper.nextPingMs(pingEverySec)

    fun again() = keeper.again()
}
