// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.content.Context
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SseRefused
import com.wittywilla.wittymediaclient.net.syncplay.ClockSample
import com.wittywilla.wittymediaclient.net.syncplay.Drift
import com.wittywilla.wittymediaclient.net.syncplay.PartyClock
import com.wittywilla.wittymediaclient.net.syncplay.PlayerFacts
import com.wittywilla.wittymediaclient.net.syncplay.Room
import com.wittywilla.wittymediaclient.net.syncplay.RoomEvent
import com.wittywilla.wittymediaclient.net.syncplay.RoomTracker
import com.wittywilla.wittymediaclient.net.syncplay.SeatLife
import com.wittywilla.wittymediaclient.net.syncplay.SeatStep
import com.wittywilla.wittymediaclient.net.syncplay.SeekPlan
import com.wittywilla.wittymediaclient.net.syncplay.SyncFollower
import com.wittywilla.wittymediaclient.net.syncplay.SyncInfo
import com.wittywilla.wittymediaclient.net.syncplay.SyncLimits
import com.wittywilla.wittymediaclient.net.syncplay.closedWords
import com.wittywilla.wittymediaclient.net.syncplay.hasNext
import com.wittywilla.wittymediaclient.net.syncplay.readRoomEvent
import com.wittywilla.wittymediaclient.net.syncplay.seekPlan
import com.wittywilla.wittymediaclient.net.syncplay.staleRoom
import com.wittywilla.wittymediaclient.net.syncplay.syncCommand
import com.wittywilla.wittymediaclient.net.syncplay.syncCreate
import com.wittywilla.wittymediaclient.net.syncplay.syncEnd
import com.wittywilla.wittymediaclient.net.syncplay.syncEvents
import com.wittywilla.wittymediaclient.net.syncplay.syncJoinCode
import com.wittywilla.wittymediaclient.net.syncplay.syncJoinRoom
import com.wittywilla.wittymediaclient.net.syncplay.syncKick
import com.wittywilla.wittymediaclient.net.syncplay.syncLeave
import com.wittywilla.wittymediaclient.net.syncplay.syncMakeHost
import com.wittywilla.wittymediaclient.net.syncplay.syncPing
import com.wittywilla.wittymediaclient.net.syncplay.syncReport
import com.wittywilla.wittymediaclient.net.syncplay.syncSet
import com.wittywilla.wittymediaclient.net.syncplay.syncWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObjectBuilder
import java.io.IOException
import java.util.Locale
import kotlin.math.abs

// A watch party, from this device's side (the server's docs/SYNCPLAY.md): the room as the server last described it,
// the server's clock, and the seat kept through a dropped connection. The rules are net/syncplay's; this is the
// connection. The server's state is the only truth: this device never says where its picture is, it asks for changes
// and says whether it has caught up.

fun steadyMs(): Double = SystemClock.elapsedRealtimeNanos() / 1_000_000.0

class PartySession(private val context: Context, private val scope: CoroutineScope, private val api: () -> Api) {
    var room by mutableStateOf<Room?>(null)
        private set
    var info by mutableStateOf<SyncInfo?>(null)
    val drift: Drift get() = info?.drift ?: Drift()
    val limits: SyncLimits get() = info?.limits ?: SyncLimits()
    // The connection dropped and the seat is being taken again.
    var reconnecting by mutableStateOf(false)
        private set

    var onRoom: ((Room) -> Unit)? = null
    var onOver: ((String) -> Unit)? = null

    private val prefs by lazy { context.getSharedPreferences("party", Context.MODE_PRIVATE) }
    private val tracker = RoomTracker()
    private var clock = PartyClock()
    private var listening: Job? = null
    private var pinging: Job? = null

    // What tells this app's seat from another window of the same sign-in: kept on the device, so the app closed and
    // opened again within the two minutes a seat is kept sits back down in it.
    val device: String by lazy {
        prefs.getString(KEY_DEVICE, null)?.takeIf { it.isNotEmpty() } ?: ("android-" + java.util.UUID.randomUUID().toString().take(8).lowercase(Locale.ROOT)).also {
            prefs.edit { putString(KEY_DEVICE, it) }
        }
    }

    fun serverNow(): Double = clock.serverNow(steadyMs())
    val rttMs: Double get() = clock.rttMs

    suspend fun create(items: List<Long>, index: Int, name: String, everyone: Boolean, waitForAll: Boolean, positionSec: Double?) {
        enter(api().syncCreate(items, index, name, everyone, waitForAll, device, positionSec))
    }

    suspend fun joinCode(code: String) = enter(api().syncJoinCode(code, device))

    suspend fun joinRoom(id: String) = enter(api().syncJoinRoom(id, device))

    // The app was closed with a seat in a party: if the server still keeps it, sit back down.
    suspend fun comeBack(found: SyncInfo) {
        val kept = prefs.getString(KEY_ROOM, null).orEmpty()
        if (kept.isEmpty() || room != null) return
        if (found.rooms.none { it.id == kept && it.memberId.isNotEmpty() }) {
            prefs.edit { remove(KEY_ROOM) }
            return
        }
        try {
            joinRoom(kept)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            prefs.edit { remove(KEY_ROOM) }
        }
    }

    private fun enter(entered: Room) {
        stopTasks()
        tracker.clear()
        tracker.offer(entered)
        clock = PartyClock()
        clock.guess(entered.serverTimeMs, steadyMs())
        room = entered
        reconnecting = false
        prefs.edit { putString(KEY_ROOM, entered.id) }
        ClientLog.info("party", "In watch party ${entered.id.take(6)} as ${if (entered.isHost) "host" else "guest"}.")
        pinging = scope.launch { pings() }
        listening = scope.launch { listen(entered.id) }
        onRoom?.invoke(entered)
    }

    private fun stopTasks() {
        listening?.cancel()
        listening = null
        pinging?.cancel()
        pinging = null
    }

    private fun gone(words: String) {
        stopTasks()
        tracker.clear()
        room = null
        reconnecting = false
        prefs.edit { remove(KEY_ROOM) }
        onOver?.invoke(words)
    }

    // The person chose to go: the seat is given up at once.
    fun leave() {
        val was = room ?: return
        val using = api()
        scope.launch { runCatching { using.syncLeave(was.id, was.you) } }
        gone("")
    }

    // Signing out or switching profile: the stream stops, and the server gives the seat up as the sign-in ends.
    fun drop() {
        if (room == null) return
        stopTasks()
        tracker.clear()
        room = null
        prefs.edit { remove(KEY_ROOM) }
    }

    // Ends the party for everyone: the host's.
    suspend fun end() {
        val was = room ?: return
        api().syncEnd(was.id, was.you)
        gone("")
    }

    // A newer room replaces what was held; an older one, arriving late, is forgotten.
    private fun take(incoming: Room) {
        if (room == null || incoming.id != room?.id) return
        if (!tracker.offer(incoming)) return
        room = incoming
        onRoom?.invoke(incoming)
    }

    // A command to the room. The answer is the room after it, which everyone's player then follows, this one's too.
    // Refused as `stale` because someone else got there first, their change is the room now.
    suspend fun command(type: String, ifSeq: Long? = null, more: JsonObjectBuilder.() -> Unit = {}) {
        val now = room ?: return
        try {
            take(api().syncCommand(now.id, now.you, type, ifSeq, more))
        } catch (e: ApiError) {
            if (e.code == "stale") staleRoom(e.body)?.let { take(it); return }
            throw e
        }
    }

    fun report(state: String, rev: Long) {
        val now = room ?: return
        val using = api()
        scope.launch { runCatching { using.syncReport(now.id, now.you, state, rev) } }
    }

    suspend fun set(everyone: Boolean? = null, waitForAll: Boolean? = null) {
        val now = room ?: return
        api().syncSet(now.id, now.you, everyone, waitForAll)
    }

    suspend fun makeHost(member: String) {
        val now = room ?: return
        api().syncMakeHost(now.id, now.you, member)
    }

    suspend fun remove(member: String) {
        val now = room ?: return
        api().syncKick(now.id, now.you, member)
    }

    // A few quickly, to have a good offset before anything plays; then a steady heartbeat, which also keeps the seat.
    private suspend fun pings() {
        while (currentCoroutineContext().isActive) {
            delay(clock.nextPingMs(limits.pingEverySec))
            val now = room ?: return
            val sent = steadyMs()
            val answer = try {
                api().syncPing(now.id, now.you, sent, clock.rttMs)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                continue
            }
            clock.add(ClockSample(sent, answer.t1, answer.t2, steadyMs()))
        }
    }

    private suspend fun listen(id: String) {
        val seat = SeatLife(limits.seatGraceSec)
        while (currentCoroutineContext().isActive) {
            val now = room ?: return
            var closed: String? = null
            val step: SeatStep = try {
                api().syncEvents(id, now.you).collect { event ->
                    when (val read = readRoomEvent(event)) {
                        is RoomEvent.Changed -> {
                            seat.opened()
                            reconnecting = false
                            take(read.room)
                        }
                        is RoomEvent.Closed -> closed = read.reason
                        null -> Unit
                    }
                }
                closed?.let { SeatStep.Over(it) } ?: seat.dropped(SystemClock.elapsedRealtime())
            } catch (e: SseRefused) {
                seat.refused(e.status, e.code, SystemClock.elapsedRealtime())
            } catch (e: IOException) {
                closed?.let { SeatStep.Over(it) } ?: seat.dropped(SystemClock.elapsedRealtime())
            }
            when (step) {
                is SeatStep.Over -> {
                    gone(closedWords(step.reason))
                    return
                }
                is SeatStep.Rejoin -> {
                    // The seat is kept for two minutes: take it again, with the same `device`.
                    reconnecting = true
                    delay(step.afterMs)
                    if (room?.id != id) return
                    try {
                        val again = api().syncJoinRoom(id, device)
                        clock.again()
                        tracker.clear()
                        tracker.offer(again)
                        room = again
                        onRoom?.invoke(again)
                    } catch (e: ApiError) {
                        val after = seat.refused(e.status, e.code, SystemClock.elapsedRealtime())
                        if (after is SeatStep.Over) {
                            gone(closedWords(after.reason))
                            return
                        }
                    } catch (_: IOException) {
                        // Still no network: round again.
                    }
                }
            }
        }
    }

    companion object {
        private const val KEY_DEVICE = "device"
        private const val KEY_ROOM = "room"
    }
}

// Keeps one video player in step with the room, and turns what the viewer does into commands for everyone. The
// decisions are SyncFollower's; this reads the player's facts for it and does what it answers.
class PartyFollower(val target: VideoTarget, private val party: PartySession, private val hub: RemoteHub, private val scope: CoroutineScope) : VideoSteering {
    private val rules = SyncFollower(party.drift)
    private var ticking: Job? = null
    private var waking: Job? = null
    // What this does to the player isn't the viewer doing it.
    private var quietUntil = 0.0
    private var seeking = false
    private var seenStream: String? = null
    private var toldOff = Double.NEGATIVE_INFINITY
    private var logged = 0.0
    private var stopped = false

    // How far behind the room this player was at the last look (negative: ahead), for the panel. Null while held.
    var behind by mutableDoubleStateOf(Double.NaN)
        private set

    private val listener = object : Player.Listener {
        override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
            if (reason == Player.DISCONTINUITY_REASON_SEEK) scope.launch { tick() }
        }

        override fun onPlaybackStateChanged(state: Int) {
            if (state == Player.STATE_READY) {
                seeking = false
                tick()
            }
        }

        // Play and pause reach the player from places other than its buttons (headphones, the system's media
        // controls), so they are noticed here. Looked at a moment later, once the app has said whether it went away.
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (reason != Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST) return
            scope.launch { viewerChanged(playWhenReady) }
        }
    }

    private fun now() = steadyMs()

    fun start() {
        target.steering = this
        target.exo.addListener(listener)
        quietUntil = now() + QUIET_START_MS
        ticking = scope.launch {
            while (isActive) {
                tick()
                delay(TICK_MS)
            }
        }
    }

    fun stop() {
        if (stopped) return
        stopped = true
        ticking?.cancel()
        waking?.cancel()
        target.exo.removeListener(listener)
        if (target.steering === this) {
            target.steering = null
            // Out of the party, the player is the viewer's own again, at an ordinary speed.
            target.exo.setPlaybackParameters(PlaybackParameters(1f))
            target.showSpeed(1f)
        }
    }

    // The room this player is following, while it is: the room's item is this one, and this account may see it.
    private val room: Room?
        get() = party.room?.takeIf { !it.blocked && !it.timeUp && it.state.itemId == target.itemId }

    fun roomChanged() = tick()

    private fun quiet(ms: Double = QUIET_MS, change: () -> Unit) {
        quietUntil = maxOf(quietUntil, now() + ms)
        change()
    }

    private fun facts(): PlayerFacts {
        val exo = target.exo
        val stream = target.stream
        val position = target.liveFilmSec
        val duration = target.durationSec
        val state = exo.playbackState
        return PlayerFacts(
            positionSec = position,
            paused = !exo.playWhenReady,
            loaded = stream != null && exo.currentMediaItem != null && state != Player.STATE_IDLE,
            canPlay = state == Player.STATE_READY,
            seeking = seeking,
            ended = state == Player.STATE_ENDED || target.ended || (duration > 0 && position >= duration - END_SLACK_SEC),
            cheapSeek = stream?.seek == "native",
        )
    }

    private fun tick() {
        if (stopped) return
        // Behind other apps the picture has stopped; that is this device away, not a pause for everyone.
        if (!hub.inFront) return
        val room = room ?: return
        val exo = target.exo
        val stream = target.stream ?: return
        if (target.problem.isNotEmpty()) return
        // A new stream (a new item, or the same one asked for again): nothing of the last one's jumps carries over.
        if (stream.streamId != seenStream || stream.url.isEmpty()) {
            seenStream = stream.streamId
            seeking = false
            rules.reset()
            quietUntil = maxOf(quietUntil, now() + QUIET_START_MS)
        }
        rules.drift = party.drift
        val state = room.state
        val orders = rules.tick(state, room.me?.state, party.serverNow(), now(), facts())
        behind = orders.behind ?: Double.NaN
        if (orders.pause) quiet { exo.pause() }
        orders.seekTo?.let { seekTo(it) }
        val wanted = (orders.rate ?: state.rate).toFloat()
        if (orders.play) {
            quiet {
                exo.setPlaybackParameters(PlaybackParameters(wanted))
                exo.play()
            }
        } else if (orders.rate != null && exo.playWhenReady && abs(exo.playbackParameters.speed - wanted) > SPEED_SLACK) {
            // The pitch stays as it was, so a voice 3% faster still sounds like itself.
            quiet { exo.setPlaybackParameters(PlaybackParameters(wanted)) }
        }
        target.showSpeed(state.rate.toFloat())
        waking?.cancel()
        orders.againInMs?.let { wait ->
            waking = scope.launch {
                delay(wait)
                tick()
            }
        }
        orders.report?.let { party.report(it, orders.rev) }
        log(orders.behind, exo.playbackParameters.speed)
    }

    // To a place in the film, exactly. A stream the server converts starts again from there, as the player always goes
    // past what it has so far.
    private fun seekTo(film: Double) {
        val stream = target.stream ?: return
        when (val plan = seekPlan(film, stream.timeOffsetSec, stream.seek, target.knownPlayerSec, target.durationSec)) {
            is SeekPlan.InPlayer -> {
                seeking = true
                quiet { target.exo.seekTo((plan.playerSec * 1000).toLong()) }
            }
            is SeekPlan.NewStream -> {
                seeking = true
                quiet(QUIET_START_MS) { target.reopenAt(plan.startSec) }
            }
            SeekPlan.None -> Unit
        }
    }

    // The gap, a line every five seconds while playing: how well this device keeps up, for anyone who asks.
    private fun log(behind: Double?, rate: Float) {
        if (behind == null || now() - logged < LOG_EVERY_MS) return
        logged = now()
        ClientLog.info("party", String.format(Locale.ROOT, "Drift %+.3f s, rate %.2f, round trip %.0f ms.", -behind, rate, party.rttMs))
    }

    // MARK: what the viewer does

    private fun notYours() {
        if (now() - toldOff > TOLD_OFF_MS) {
            toldOff = now()
            hub.say(com.wittywilla.wittymediaclient.net.syncplay.syncErrorWords(403, "host-only"))
        }
    }

    private fun send(type: String, ifSeq: Long? = null, more: JsonObjectBuilder.() -> Unit = {}) {
        scope.launch {
            try {
                party.command(type, ifSeq, more)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                // The end of the queue, said by every player at once, is nothing to tell anyone.
                if (e.code != "end-of-queue" && e.code != "stale") hub.say(syncWords(e))
            } catch (_: IOException) {
                hub.say("The watch party couldn't be reached. Check the connection.")
            }
        }
    }

    override fun toggle(): Boolean {
        val room = room ?: return false
        if (!room.canControl) { notYours(); return true }
        send(if (room.state.paused) "play" else "pause")
        return true
    }

    override fun seek(filmSec: Double): Boolean {
        val room = room ?: return false
        if (!room.canControl) { notYours(); return true }
        send("seek") { put("positionSec", kotlinx.serialization.json.JsonPrimitive(filmSec.coerceAtLeast(0.0))) }
        return true
    }

    override fun speed(rate: Float): Boolean {
        val room = room ?: return false
        if (!room.canControl) { notYours(); return true }
        send("rate") { put("rate", kotlinx.serialization.json.JsonPrimitive(rate.toDouble().coerceIn(0.5, 2.0))) }
        return true
    }

    override fun ended(): Boolean {
        val room = room ?: return false
        // Every player reaches the end together and says "next"; the seq lets one of them count.
        if (room.canControl && room.hasNext) send("next", room.state.seq)
        return true
    }

    private fun viewerChanged(playing: Boolean) {
        if (stopped || !hub.inFront || now() < quietUntil) return
        val room = room ?: return
        if (target.problem.isNotEmpty() || facts().ended) return
        val state = room.state
        if (!playing && !state.paused && !state.waiting) {
            if (room.canControl) send("pause") else { notYours(); tick() }
        } else if (playing && state.paused) {
            if (room.canControl) send("play") else { notYours(); tick() }
        }
    }

    private companion object {
        const val TICK_MS = 500L
        const val QUIET_MS = 700.0
        const val QUIET_START_MS = 1500.0
        const val TOLD_OFF_MS = 8000.0
        const val LOG_EVERY_MS = 5000.0
        const val END_SLACK_SEC = 0.25
        const val SPEED_SLACK = 0.001f
    }
}
