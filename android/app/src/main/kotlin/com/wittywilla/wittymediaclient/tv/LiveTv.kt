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

    // Plays a channel, or carries on with it if it's the one already on.
    fun watch(key: String, api: Api) {
        this.api = api
        if (key == this.key && state != State.Idle && !isFailed) return
        if (this.key.isNotEmpty() && this.key != key) leave(this.key)
        this.key = key
        info = null
        why = ""
        state = State.Tuning
        tuning?.cancel()
        player()?.let {
            it.stop()
            it.clearMediaItems()
        }
        tuning = tvScope.launch { tune(key) }
        measure()
    }

    // Tries the channel again after it failed.
    fun retry() {
        val was = key
        key = ""
        state = State.Idle
        watch(was, api)
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
        if (key.isNotEmpty()) leave(key)
        key = ""
        info = null
        why = ""
        state = State.Idle
        behind = 0.0
    }

    fun pause() {
        exo?.pause()
    }

    fun resume() {
        val p = exo ?: return
        if (key.isNotEmpty() && p.mediaItemCount > 0) p.play()
    }

    // Back or on within what the server keeps of the channel.
    fun seek(by: Double) {
        val p = exo ?: return
        val length = p.duration
        if (length == C.TIME_UNSET) return
        p.seekTo((p.currentPosition + (by * 1000).toLong()).coerceIn(0, length))
    }

    fun goLive() {
        val p = exo ?: return
        p.seekToDefaultPosition()
        p.play()
    }

    private fun leave(key: String) {
        val leaving = api
        val name = viewer
        tvScope.launch { runCatching { leaving.leaveChannel(key, name) } }
    }

    // How far behind the live edge it is, once a second while a channel is on.
    private fun measure() {
        if (clock?.isActive == true) return
        clock = tvScope.launch {
            while (isActive) {
                val p = exo
                val length = p?.duration ?: C.TIME_UNSET
                behind = if (p == null || length == C.TIME_UNSET || !p.isCurrentMediaItemDynamic) 0.0 else maxOf(0L, length - p.currentPosition) / 1000.0
                delay(1000)
            }
        }
    }

    private suspend fun tune(key: String) {
        repeat(TUNE_TRIES) {
            try {
                val tuned = api.tune(key, viewer)
                if (key != this.key) return
                val address = tuned.streamUrl ?: tuned.url
                val url = address?.let { runCatching { api.mediaUrl(it) }.getOrNull() }
                if (url == null) {
                    why = "The server sent an address that can't be used."
                    state = State.Failed
                    return
                }
                info = tuned
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
                } else {
                    if (key != this.key) return
                    why = problemText(e, "This channel can't be played right now.")
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
        if (key.isEmpty()) return
        val fresh = runCatching { api.tune(key, viewer) }.getOrNull() ?: return
        if (fresh.key == null || fresh.key == key) info = fresh
    }
}

// The picture alone, as big as it's given, fitted inside it on black. The remote's arrows are the screen's to use.
@Composable
fun LivePicture(modifier: Modifier = Modifier) {
    AndroidView(
        factory = { c ->
            (LayoutInflater.from(c).inflate(R.layout.tv_live_picture, null) as PlayerView).apply {
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

    fun current(context: Context): String = prefs(context).getString(KEY, "").orEmpty()
    fun before(context: Context): String = prefs(context).getString("$KEY.before", "").orEmpty()

    fun remember(context: Context, channel: String) {
        val was = current(context)
        prefs(context).edit().apply {
            if (was.isNotEmpty() && was != channel) putString("$KEY.before", was)
            putString(KEY, channel)
        }.apply()
    }
}
