// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import android.content.Context
import android.view.LayoutInflater
import androidx.annotation.OptIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.wittywilla.wittymediaclient.R
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.GuidePaging
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.SetRules
import com.wittywilla.wittymediaclient.net.Span
import com.wittywilla.wittymediaclient.net.TimeShiftRules
import com.wittywilla.wittymediaclient.net.TimeShiftRules.Seek
import com.wittywilla.wittymediaclient.net.Timeline
import com.wittywilla.wittymediaclient.net.startOver
import com.wittywilla.wittymediaclient.net.timeline
import com.wittywilla.wittymediaclient.net.catchup
import com.wittywilla.wittymediaclient.net.Tuned
import com.wittywilla.wittymediaclient.net.leaveChannel
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.tune
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID

// WittyTV's one player, as web/src/pages/tv/live.ts is the page's and LiveTv.swift is Apple TV's: the guide's preview
// and the channel on the whole screen are the same picture, so going from one to the other never tunes again. Moving
// on leaves the last channel at once, so the server stops a stream nobody watches.
@OptIn(UnstableApi::class)
object LiveTv {
    enum class State { Idle, Tuning, Playing, Failed }

    private const val TUNE_TRIES = 20
    private const val BUSY = 503

    private var context: Context? = null
    private var exo: ExoPlayer? = null

    // The channel asked for, which may still be starting.
    var key by mutableStateOf("")
        private set
    var state by mutableStateOf(State.Idle)
        private set

    // Why it failed, when it has.
    var why by mutableStateOf("")
        private set

    // What the server said about it: what's on, what's next, its notices.
    var info by mutableStateOf<Tuned?>(null)
        private set
    var playing by mutableStateOf(false)
        private set

    // How far behind the live edge, in seconds.
    var behind by mutableDoubleStateOf(0.0)
        private set

    // The programme being watched from its start (catch-up), or null for the channel as it is now.
    var fromStart by mutableStateOf<GuideProgramme?>(null)
        private set

    // On a library channel started over (server #648): the moment of the schedule this viewer's own stream started
    // from, the programme and breaks it is in, the moment the picture is at, and the break it is in, if any.
    var shiftFrom by mutableStateOf<Long?>(null)
        private set
    var timeline by mutableStateOf<Timeline?>(null)
        private set
    var sched by mutableStateOf<Double?>(null)
        private set
    var inBreak by mutableStateOf<Span?>(null)
        private set
    private var heardAt = 0L
    private var askedEnd = 0L
    private var pausedAt: Pair<Long, Double?>? = null
    private val window = androidx.media3.common.Timeline.Window()

    private var api = Api("", "")

    // One name for this player, so the server can tell when it has gone.
    private val viewer = UUID.randomUUID().toString()
    private var tuning: Job? = null
    private var clock: Job? = null
    private var quiet = false

    val isFailed: Boolean get() = state == State.Failed

    fun use(context: Context) {
        if (this.context == null) this.context = context.applicationContext
    }

    // The player, made the first time it's wanted.
    fun player(): ExoPlayer? {
        exo?.let { return it }
        val c = context ?: return null
        return ExoPlayer.Builder(c, DefaultRenderersFactory(c).setEnableDecoderFallback(true)).build().also { p ->
            p.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), !quiet)
            p.volume = if (quiet) 0f else 1f
            p.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    playing = isPlaying
                    if (isPlaying && state == State.Tuning) state = State.Playing
                }

                override fun onPlayerError(error: PlaybackException) {
                    if (key.isEmpty()) return
                    if (com.wittywilla.wittymediaclient.player.ScreenTimeWatch.playbackFailed(error)) return // this profile's time is up: the notice says so
                    why = "This channel can't be played right now."
                    state = State.Failed
                }
            })
            exo = p
        }
    }

    // A muted preview doesn't take the sound from anything else playing.
    var muted: Boolean
        get() = quiet
        set(value) {
            quiet = value
            exo?.let {
                it.volume = if (value) 0f else 1f
                it.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), !value)
            }
        }

    // Plays a channel, or carries on with it if it's the one already on. A programme watched from its start goes back
    // to the channel as it is now.
    fun watch(key: String, api: Api) {
        this.api = api
        if (key == this.key && state != State.Idle && !isFailed && fromStart == null) return
        begin(key, null)
    }

    // Plays a programme from its start, on a channel whose source keeps it (`tv-catchup`).
    // On a library channel it is the viewer's own stream of the channel from `from` (the programme's start if null).
    fun watchFromStart(key: String, programme: GuideProgramme, api: Api, from: Long? = null) {
        this.api = api
        val shift = if (TimeShiftRules.isLibrary(key)) from ?: programme.start else null
        if (key == this.key && fromStart == programme && shiftFrom == shift && state != State.Idle && !isFailed) return
        begin(key, programme, shift)
    }

    private fun begin(key: String, programme: GuideProgramme?, shift: Long? = null) {
        // The same channel another way (live after catch-up, or the other way round) is left first, and waited for,
        // so the server can't stop the new stream for the old one.
        val leaving = this.key.takeIf { it.isNotEmpty() && (it != key || fromStart != programme || shiftFrom != shift) }
        val sameKey = leaving == key
        val wasShift = shiftFrom != null
        if (leaving != null && !sameKey) leave(leaving, wasShift)
        this.key = key
        fromStart = programme
        shiftFrom = shift
        timeline = null
        inBreak = null
        sched = null
        pausedAt = null
        info = null
        why = ""
        state = State.Tuning
        tuning?.cancel()
        player()?.let {
            it.stop()
            it.clearMediaItems()
        }
        val using = api
        tuning = tvScope.launch {
            // A start-over stream replaced by one from a new moment is replaced by the server itself.
            if (sameKey && !(wasShift && shift != null)) runCatching { using.leaveChannel(key, viewer, wasShift) }
            tune(key, programme)
        }
        measure()
    }

    // Tries the channel again after it failed.
    fun retry() {
        val was = key
        val programme = fromStart
        val from = shiftFrom
        key = ""
        fromStart = null
        shiftFrom = null
        state = State.Idle
        if (programme != null) watchFromStart(was, programme, api, from) else watch(was, api)
    }

    // Nothing to show: the stream is left, and the server can stop it.
    fun stop() {
        tuning?.cancel()
        tuning = null
        clock?.cancel()
        clock = null
        exo?.let {
            it.stop()
            it.clearMediaItems()
        }
        if (key.isNotEmpty()) leave(key, shiftFrom != null)
        key = ""
        fromStart = null
        shiftFrom = null
        timeline = null
        inBreak = null
        info = null
        why = ""
        state = State.Idle
        behind = 0.0
    }

    fun pause() {
        if (canShift && exo?.isPlaying == true) pausedAt = System.currentTimeMillis() to schedNow()
        exo?.pause()
    }

    fun resume() {
        val p = exo ?: return
        // Back after longer than the server keeps: from where it paused, not whatever is left.
        val paused = pausedAt
        pausedAt = null
        val at = paused?.second
        if (paused != null && at != null && TimeShiftRules.restartAfterPause(paused.first, System.currentTimeMillis(), info?.bufferSec ?: 300.0)) {
            restartAt(at.toLong())
            return
        }
        if (key.isNotEmpty() && p.mediaItemCount > 0) p.play()
    }

    // A library channel can go further back than its window, by starting over from there.
    private val canShift: Boolean get() = TimeShiftRules.isLibrary(key) && (shiftFrom != null || info?.startOver == true)

    // Back or on within what the server keeps of the channel; on a library channel, further back by starting over.
    // Back only: live TV never skips ahead (#688), whatever asks (a key, a phone steering this TV).
    fun seek(by: Double) {
        if (by > 0) return
        val p = exo ?: return
        val length = p.duration
        if (canShift) {
            val s = schedNow()
            if (s != null && (shiftFrom != null || p.currentPosition + by * 1000 < 0) && goTo(s + by)) return
        }
        if (length == C.TIME_UNSET) return
        p.seekTo((p.currentPosition + (by * 1000).toLong()).coerceIn(0, length))
    }

    // The moment of the schedule the picture is at, from the stream's program date-times.
    fun schedNow(): Double? {
        val p = exo ?: return null
        val t = p.currentTimeline
        if (t.isEmpty || p.currentMediaItemIndex >= t.windowCount) return null
        t.getWindow(p.currentMediaItemIndex, window)
        if (window.windowStartTimeMs == C.TIME_UNSET) return null
        return (window.windowStartTimeMs + p.currentPosition) / 1000.0
    }

    // Where live is now, by the server's clock.
    private fun liveNow(): Double {
        val i = info ?: return System.currentTimeMillis() / 1000.0
        if (i.serverTime <= 0) return System.currentTimeMillis() / 1000.0
        return i.serverTime + (android.os.SystemClock.elapsedRealtime() - heardAt) / 1000.0
    }

    // A moment of the schedule: within what's loaded, a seek; further back, this viewer's stream from there; at live,
    // the channel everyone shares.
    // False when there's nothing to do but stay within the window: live, on the channel everyone shares.
    fun goTo(target: Double): Boolean {
        val p = exo ?: return false
        val s = schedNow() ?: return false
        val cur = p.currentPosition / 1000.0
        val end = if (p.duration == C.TIME_UNSET) cur else p.duration / 1000.0
        val live = liveNow()
        when (val plan = TimeShiftRules.plan(target, s, cur, 0.0, end, live, (timeline?.earliest ?: (live - 6 * 3600).toLong()).toDouble())) {
            Seek.Live -> if (shiftFrom == null) return false else goLive()
            is Seek.Within -> p.seekTo((plan.to * 1000).toLong())
            is Seek.Restart -> restartAt(plan.at)
        }
        return true
    }

    private fun restartAt(at: Long) {
        val programme = fromStart ?: info?.now ?: return
        if (key.isEmpty()) return
        begin(key, programme, at)
    }

    // The programme on now from its beginning: this viewer's own stream on a library channel, the archive on a tuner.
    fun startOver() {
        val p = info?.now ?: return
        if (!TimeShiftRules.canStartOver(info, liveNow().toLong())) return
        if (TimeShiftRules.isLibrary(key)) begin(key, p, p.start) else begin(key, p)
    }

    // Whether Start over is offered now.
    val canStartOver: Boolean get() = fromStart == null && TimeShiftRules.canStartOver(info, liveNow().toLong())

    // Past the whole break the picture is in, in one press. Only on a start-over stream: live keeps its breaks.
    fun skipBreak() {
        val b = inBreak ?: return
        goTo(b.end + 0.5)
    }

    fun goLive() {
        if (fromStart != null && key.isNotEmpty()) {
            begin(key, null)
            return
        }
        val p = exo ?: return
        p.seekToDefaultPosition()
        p.play()
    }

    private fun leave(key: String, shift: Boolean = false) {
        val leaving = api
        val name = viewer
        tvScope.launch { runCatching { leaving.leaveChannel(key, name, shift) } }
    }

    // How far behind the live edge it is, once a second while a channel is on.
    private fun measure() {
        if (clock?.isActive == true) return
        clock = tvScope.launch {
            while (isActive) {
                val p = exo
                val length = p?.duration ?: C.TIME_UNSET
                behind = if (p == null || length == C.TIME_UNSET || !p.isCurrentMediaItemDynamic) 0.0 else maxOf(0L, length - p.currentPosition) / 1000.0
                if (shiftFrom != null) {
                    val s = schedNow()
                    sched = s
                    if (s != null) behind = maxOf(0.0, liveNow() - s)
                    inBreak = TimeShiftRules.breakAt(timeline?.breaks, s)
                    // Past the programme the timeline told of: what's on from there, and its breaks.
                    val t = timeline
                    if (s != null && t != null && s >= t.programme.end && askedEnd != t.programme.end) {
                        askedEnd = t.programme.end
                        val k = key
                        runCatching { api.timeline(k, s.toLong()) }.getOrNull()?.let { if (k == key && shiftFrom != null) timeline = it }
                    }
                } else {
                    inBreak = null
                }
                delay(1000)
            }
        }
    }

    private suspend fun tune(key: String, programme: GuideProgramme?) {
        repeat(TUNE_TRIES) {
            try {
                val shift = shiftFrom
                val tuned = when {
                    programme != null && shift != null -> api.startOver(key, shift, viewer)
                    programme != null -> api.catchup(key, programme, viewer)
                    else -> api.tune(key, viewer)
                }
                if (key != this.key || programme != fromStart || shift != shiftFrom) return
                val address = tuned.streamUrl ?: tuned.url
                val url = address?.let { runCatching { api.mediaUrl(it) }.getOrNull() }
                if (url == null) {
                    why = "The server sent an address that can't be used."
                    state = State.Failed
                    return
                }
                info = tuned
                heardAt = android.os.SystemClock.elapsedRealtime()
                timeline = tuned.timeline
                val media = MediaItem.Builder().setUri(url)
                if (url.substringBefore('?').endsWith(".m3u8")) media.setMimeType(MimeTypes.APPLICATION_M3U8)
                player()?.let {
                    it.setMediaItem(media.build())
                    it.prepare()
                    it.playWhenReady = true
                }
                return
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                if (e.status == BUSY) {
                    // Still starting: the server says to wait and ask again.
                    delay(1000)
                    if (key != this.key) return
                } else if (e.status == 409 && shiftFrom != null) {
                    // That moment is live now: the channel everyone shares.
                    if (key == this.key) begin(key, null)
                    return
                } else {
                    if (key != this.key) return
                    why = when {
                        programme != null && e.status == 404 -> "That programme is no longer kept, so it can't be watched from the start."
                        programme != null -> problemText(e, "That programme can't be watched from the start right now.")
                        // A tuner's own reason ("the stream answered 404 …") is said after what it means.
                        else -> problemText(e, "").let { r -> if (r.isEmpty()) "This channel can't be played right now." else if (r.first().isLowerCase()) "This channel can't be played right now: $r." else r }
                    }
                    state = State.Failed
                    return
                }
            } catch (e: Exception) {
                if (key != this.key) return
                why = "This channel can't be played right now."
                state = State.Failed
                return
            }
        }
        why = "This channel didn't start in time. Try it again in a moment."
        state = State.Failed
    }

    // Asks again what's on, when the programme on the banner has ended.
    suspend fun refreshInfo() {
        if (key.isEmpty() || fromStart != null) return
        val fresh = runCatching { api.tune(key, viewer) }.getOrNull() ?: return
        if (fresh.key == null || fresh.key == key) info = fresh
    }
}

// The picture alone, as big as it's given, fitted inside it on black. The remote's arrows are the screen's to use.
@Composable
fun LivePicture(modifier: Modifier = Modifier, fullScreen: Boolean = false) {
    AndroidView(
        factory = { c ->
            (LayoutInflater.from(c).inflate(if (fullScreen) R.layout.tv_live_picture_full else R.layout.tv_live_picture, null) as PlayerView).apply {
                LiveTv.use(c)
                player = LiveTv.player()
                isFocusable = false
                descendantFocusability = android.view.ViewGroup.FOCUS_BLOCK_DESCENDANTS
            }
        },
        update = {
            if (it.player !== LiveTv.player()) it.player = LiveTv.player()
            // The picture doesn't count as using the TV, which would put up its screensaver.
            it.keepScreenOn = LiveTv.playing
        },
        onRelease = { it.player = null },
        modifier = modifier,
    )
}

// The last channel watched, for the preview that shows it, and for Last.
object LastChannel {
    private const val KEY = "wms.tv.last"
    private fun prefs(context: Context) = context.getSharedPreferences("wittytv", Context.MODE_PRIVATE)

    // A channel is its server's: kept under that server's tag (data/ServerRules.kt, serverTag).
    private fun key(context: Context): String {
        val tag = (context.applicationContext as? com.wittywilla.wittymediaclient.WittyApp)?.store?.currentTag.orEmpty()
        return if (tag.isEmpty()) KEY else "$KEY.$tag"
    }

    fun current(context: Context): String = prefs(context).getString(key(context), "").orEmpty()
    fun before(context: Context): String = prefs(context).getString("${key(context)}.before", "").orEmpty()

    // One server's, when it is removed.
    fun forgetServer(context: Context, tags: List<String>) {
        val edit = prefs(context).edit()
        tags.forEach { edit.remove("$KEY.$it").remove("$KEY.$it.before") }
        edit.apply()
    }

    // With no server remembered, every channel is nobody's, the untagged one from before included. The guide's
    // sets are kept for each server, so they go too.
    fun forget(context: Context) {
        val edit = prefs(context).edit()
        prefs(context).all.keys.filter { it.startsWith(KEY) || it.startsWith(GuidePrefs.SET_PREFIX) }.forEach { edit.remove(it) }
        edit.apply()
    }

    fun remember(context: Context, channel: String) {
        val key = key(context)
        val was = current(context)
        prefs(context).edit().apply {
            if (was.isNotEmpty() && was != channel) putString("$key.before", was)
            putString(key, channel)
        }.apply()
    }
}

// The guide's choices that are this device's alone, as the page keeps them in its own storage: the set chosen, for each
// server and account, and how many channels a page shows.
object GuidePrefs {
    const val SET_PREFIX = "wms.tv.set."
    private const val PAGE_SIZE = "wms.tv.pageSize"
    private fun prefs(context: Context) = context.getSharedPreferences("wittytv", Context.MODE_PRIVATE)

    fun set(context: Context, server: String, account: Long): String? = prefs(context).getString(SetRules.prefKey(server, account), null)

    fun setSet(context: Context, server: String, account: Long, id: String) {
        val key = SetRules.prefKey(server, account)
        prefs(context).edit().apply { if (id == SetRules.ALL) remove(key) else putString(key, id) }.apply()
    }

    private const val SHORTCUTS = "wms.tv.shortcuts"
    fun shortcuts(context: Context): Boolean = prefs(context).getBoolean(SHORTCUTS, false)
    fun setShortcuts(context: Context, on: Boolean) = prefs(context).edit().putBoolean(SHORTCUTS, on).apply()

    fun pageSize(context: Context): Int = GuidePaging.size(prefs(context).getInt(PAGE_SIZE, GuidePaging.DEFAULT))
    fun setPageSize(context: Context, size: Int) = prefs(context).edit().putInt(PAGE_SIZE, GuidePaging.size(size)).apply()
}
