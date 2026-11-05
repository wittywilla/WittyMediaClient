package com.wittywilla.wittymediaclient.player

import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.util.EventLogger
import androidx.media3.session.MediaSession
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Playback
import com.wittywilla.wittymediaclient.net.PlaybackRequest
import com.wittywilla.wittymediaclient.net.Show
import com.wittywilla.wittymediaclient.ui.Nav
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// The website's player session (web/src/player/PlayerPage.tsx, VideoPlayer.tsx): one video at a time, kept
// while the viewer goes elsewhere in the app, so leaving the full player keeps it playing in the mini player
// dock, as /play does. The screens draw it; this asks the server, plays, reports and recovers.

// What to ask the server for. A new value opens or changes the stream.
private data class VideoAsk(
    val audio: Int? = null,
    val subtitle: Int? = null,
    val burn: Boolean = false,
    val video: Int? = null,
    val flatten3d: Boolean = false,
    val startSec: Double? = null,
    val convert: Boolean = false,
    val reload: Boolean = false,
    val waitMs: Long = 0,
    val attempt: Int = 0,
)

// The website's words for a stream that won't play (web/src/api.ts, VideoPlayer.tsx, hooks.ts).
const val CANT_REACH = "Can't reach your server. Check that WittyMediaServer is running and that this device can reach it: on the same network, or through Remote Access."
private const val STREAM_ENDED = "The stream has ended on the server. Start playback again."
private const val CANT_PLAY_HERE = "This file can’t be played here."
private const val NOTE_MS = 6000L
private const val NOTES_KEPT = 8
private const val COUNTDOWN_FROM = 8
private const val TICK_MS = 250L

@OptIn(UnstableApi::class)
private fun newVideoPlayer(context: Context): ExoPlayer =
    ExoPlayer.Builder(context, DefaultRenderersFactory(context).setEnableDecoderFallback(true))
        .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        .setHandleAudioBecomingNoisy(true)
        .build()
        .also { if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) it.addAnalyticsListener(EventLogger()) }

// A note about the connection, as the website shows one over the picture. A lost connection stays until
// something replaces it.
data class NetNote(val text: String, val lost: Boolean = false, val at: Long = System.nanoTime())

@OptIn(UnstableApi::class)
class VideoSession(private val nav: Nav, val id: Long, private val startAt: Double?) {
    private val app = nav.app
    private val api get() = app.api
    val player: ExoPlayer = newVideoPlayer(app)
    private val media = MediaSession.Builder(app, player).setId("witty-video-$id-${System.nanoTime()}").build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var item by mutableStateOf<Item?>(null)
        private set
    var stream by mutableStateOf<Playback?>(null)
        private set
    var problem by mutableStateOf("")
        private set
    var playing by mutableStateOf(false)
        private set
    var waiting by mutableStateOf(true)
        private set
    var filmSec by mutableDoubleStateOf(0.0)
        private set
    var bufferedSec by mutableDoubleStateOf(0.0)
        private set
    var ended by mutableStateOf(false)
        private set
    var speed by mutableFloatStateOf(1f)
        private set
    var maxSpeed by mutableDoubleStateOf(4.0)
        private set
    var prefs by mutableStateOf(ViewPrefsStore.load(app, id))
        private set
    var mini by mutableStateOf(false)

    // Watch next: the next episode or in the list, else the server's recommendation.
    var next by mutableStateOf<Item?>(null)
        private set
    var nextShow by mutableStateOf<Show?>(null)
        private set
    var recommended by mutableStateOf(false)
        private set
    var countdown by mutableStateOf<Int?>(null)
        private set
    var dismissed by mutableStateOf(false)

    var note by mutableStateOf<NetNote?>(null)
        private set
    val notes = mutableStateListOf<String>()

    // Bumped by play and pause, which bring the controls back as on the website.
    var activity by mutableStateOf(0)
        private set

    private var ask by mutableStateOf(VideoAsk(startSec = startAt))
    private val clock = PlaybackClock()
    private val budget = RetryBudget()
    private var waitingForNetwork = false
    private var nextAsked = false
    private var closed = false

    val durationSec: Double get() = stream?.durationSec?.takeIf { it > 0 } ?: item?.runtimeSec ?: 0.0
    val nextId: Long? get() = stream?.nextId ?: item?.nextId

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            playing = isPlaying
            activity++
        }
        override fun onPlayerError(error: PlaybackException) = onFailure(error)
        override fun onPlaybackStateChanged(state: Int) {
            waiting = state == Player.STATE_BUFFERING || state == Player.STATE_IDLE
            if (state == Player.STATE_READY) clock.ready()
            if (state == Player.STATE_ENDED) {
                ended = true
                saveProgress()
                // Only an episode with one after it counts down; a recommendation never plays by itself.
                if (stream?.nextId != null || item?.nextId != null) countdown = COUNTDOWN_FROM
            }
        }
    }

    private val network = app.getSystemService(ConnectivityManager::class.java)
    private val networkBack = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(n: Network) {
            scope.launch {
                if (waitingForNetwork && problem.isNotEmpty()) {
                    waitingForNetwork = false
                    budget.reset()
                    tryAgain()
                }
            }
        }
    }

    init {
        player.addListener(listener)
        // Music stops for a film, as the website's player pauses it whenever /play is open.
        app.listening.pauseForVideo()
        if (Build.VERSION.SDK_INT >= 24) runCatching { network?.registerDefaultNetworkCallback(networkBack) }
        scope.launch { runCatching { maxSpeed = api.playerPrefs().maxSpeed } }
        scope.launch { snapshotFlow { ask }.collectLatest { open(it) } }
        scope.launch { tick() }
        scope.launch { snapshotFlow { countdown }.collectLatest { left -> runCountdown(left) } }
    }

    private suspend fun tick() {
        while (true) {
            delay(TICK_MS)
            val offset = stream?.timeOffsetSec ?: 0.0
            if (clock.tick(player.currentPosition / 1000.0, offset, player.isPlaying)) saveProgress()
            filmSec = clock.filmSec
            bufferedSec = player.bufferedPosition / 1000.0 + offset
            if (player.isPlaying) budget.played(TICK_MS / 1000.0)
            ended = player.playbackState == Player.STATE_ENDED
            // Seeking back out of the last 30 seconds hides the card again; the next one is kept.
            val due = durationSec > 0 && (filmSec >= durationSec - WATCH_NEXT_BEFORE_END_SEC || ended)
            if (due && !nextAsked) loadNext()
            note?.let { if (!it.lost && System.nanoTime() - it.at > NOTE_MS * 1_000_000) note = null }
        }
    }

    // Shown while it's due, loaded, not dismissed and not in the mini player.
    val watchNextShown: Boolean
        get() = next != null && !dismissed && !mini && durationSec > 0 && (filmSec >= durationSec - WATCH_NEXT_BEFORE_END_SEC || ended)

    private fun loadNext() {
        nextAsked = true
        scope.launch {
            runCatching {
                val following = nextId
                if (following != null) {
                    next = api.item(following)
                    recommended = false
                } else {
                    val pick = api.recommend(id)
                    next = pick.item
                    nextShow = pick.show
                    recommended = true
                }
            }
        }
    }

    private suspend fun runCountdown(left: Int?) {
        if (left == null) return
        if (left <= 0) {
            countdown = null
            nextId?.let { nav.playVideoInstead(it) }
            return
        }
        delay(1000)
        // Paused while minimised; stopped by Dismiss.
        while (mini) delay(200)
        if (countdown == left) countdown = left - 1
    }

    fun dismissNext() {
        dismissed = true
        countdown = null
    }

    fun note(text: String, lost: Boolean = false) {
        note = NetNote(text, lost)
        notes.add(text)
        while (notes.size > NOTES_KEPT) notes.removeAt(0)
    }

    private suspend fun robustKbps(streaming: String): Int? {
        val robust = streaming == "robust" || (streaming == "auto" && api.remoteStreaming() == "robust")
        return if (robust) api.speedtestKbps() else null
    }

    private suspend fun open(want: VideoAsk) {
        try {
            if (want.waitMs > 0) delay(want.waitMs)
            val current = item ?: api.item(id).also { item = it }
            // The website always says where to start: the place asked for, else where the viewer left off.
            val start = want.startSec ?: current.progress?.resumeSec?.takeIf { it > 0 } ?: 0.0
            val streaming = ViewPrefsStore.streaming(app)
            // Reading the device's decoders can take seconds the first time, so never on the main thread.
            val capabilities = withContext(Dispatchers.Default) { DeviceProfile.capabilities(app) }
            val answer = api.playback(
                id,
                PlaybackRequest(
                    PLAYBACK_PROFILE, want.audio, want.subtitle, start,
                    capabilities = capabilities,
                    maxBitrateKbps = DeviceProfile.maxBitrateKbps(app),
                    forceTranscode = if (want.convert) true else null,
                    flatten3d = if (want.flatten3d) true else null,
                    burnSubtitle = if (want.burn) true else null,
                    video = want.video,
                    streaming = streaming.takeIf { it != "auto" },
                    measuredKbps = robustKbps(streaming),
                ),
            )
            val before = stream
            if (answer.protocol == "disc-session" || answer.url.isEmpty()) {
                problem = "Playback failed: this kind of item opens in the disc player."
                return
            }
            if (before != null && before.streamId.isNotEmpty() && before.streamId != answer.streamId) {
                val old = before.streamId
                app.scope.launch { runCatching { api.stopStream(old) } }
            }
            val sidecar = answer.subtitles.firstOrNull { it.index == answer.subtitleIndex && it.delivery == "sidecar" && it.url.isNotEmpty() }
            val hadSidecar = before?.subtitles?.firstOrNull { it.index == before.subtitleIndex && it.delivery == "sidecar" }?.url
            val changed = want.reload || answer.url != before?.url || sidecar?.url != hadSidecar
            stream = answer
            ClientLog.session = answer.streamId
            if (changed) {
                clock.switching()
                val builder = MediaItem.Builder()
                    .setUri(api.mediaUrl(answer.url))
                    .setMediaMetadata(MediaMetadata.Builder().setTitle(current.showTitle?.ifEmpty { null } ?: current.title).setSubtitle(current.title).build())
                if (answer.protocol == "hls") builder.setMimeType(MimeTypes.APPLICATION_M3U8)
                if (sidecar != null) {
                    builder.setSubtitleConfigurations(
                        listOf(
                            MediaItem.SubtitleConfiguration.Builder(android.net.Uri.parse(api.mediaUrl(sidecar.url)))
                                .setMimeType(MimeTypes.TEXT_VTT)
                                .setLanguage(sidecar.language)
                                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                                .build(),
                        ),
                    )
                }
                // The server says where the player starts: 0 when the stream already starts at the place.
                player.setMediaItem(builder.build(), (answer.startAtSec * 1000).toLong())
                player.prepare()
                player.playWhenReady = true
                player.setPlaybackParameters(PlaybackParameters(speed))
            }
            val audio = answer.audio.firstOrNull { it.index == answer.audioIndex }
            val text = answer.subtitles.firstOrNull { it.index == answer.subtitleIndex }
            player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                .setPreferredAudioLanguage(TrackMatch.languageFor(audio))
                .setPreferredTextLanguage(TrackMatch.languageFor(text))
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, text == null || answer.subtitleDelivery == "burn")
                .build()
            if (want.attempt > 0 && before != null) note(if (want.waitMs > 0) "Reconnected, at the same place." else "The connection failed, so the video was asked for again from the same place.")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) {
                problem = when (e) {
                    is ApiError -> "Playback failed: " + e.message.orEmpty().ifEmpty { CANT_REACH }
                    else -> "Playback failed: $CANT_REACH"
                }
                waitingForNetwork = e is java.io.IOException
            }
        }
    }

    private fun onFailure(e: PlaybackException) {
        val code = (e.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode
        val recovery = recoveryFor(e.errorCode, code)
        // A decode failure is asked for again once as a conversion, from the same place.
        val wait = if (recovery == Recovery.GiveUp || (recovery == Recovery.Convert && ask.convert)) null else budget.next()
        ClientLog.report(
            if (wait != null) "warn" else "error", "player",
            "Playback failed: ${e.errorCodeName}${if (code != null) ", the server answered $code" else ""}${if (wait != null) ", trying again" else ""}",
            stack = e.stackTraceToString(), session = stream?.streamId.orEmpty(),
        )
        if (wait == null) {
            problem = "Playback failed: " + when {
                code == 404 -> STREAM_ENDED
                recovery == Recovery.WaitThenNewStream -> CANT_REACH
                recovery == Recovery.Convert -> CANT_PLAY_HERE
                else -> failureWords(e.errorCode, code)
            }
            waitingForNetwork = recovery == Recovery.WaitThenNewStream
            return
        }
        if (recovery == Recovery.WaitThenNewStream) note("Connection lost. Trying again…", lost = true)
        if (code == 404) note("The stream had ended on the server, so it was started again from the same place.")
        ask = ask.copy(
            startSec = clock.lastPlace() ?: ask.startSec,
            reload = true,
            convert = ask.convert || recovery == Recovery.Convert,
            waitMs = if (recovery == Recovery.WaitThenNewStream) wait else 0,
            attempt = ask.attempt + 1,
        )
    }

    private fun tryAgain() {
        problem = ""
        ask = ask.copy(startSec = clock.lastPlace() ?: ask.startSec, reload = true, attempt = ask.attempt + 1)
    }

    fun saveProgress() {
        val duration = durationSec.takeIf { it > 0 } ?: return
        val at = clock.lastPlace() ?: return
        app.scope.launch { runCatching { api.saveProgress(id, at, duration) } }
    }

    fun playPause() {
        if (ended) { seekFilm(0.0); player.play(); return }
        if (player.isPlaying) player.pause() else player.play()
    }

    // A growing stream has to be asked for again to go past what exists so far.
    fun seekFilm(targetSec: Double) {
        val current = stream ?: return
        if (current.seek == "none") return
        val target = targetSec.coerceIn(0.0, durationSec.takeIf { it > 0 } ?: Double.MAX_VALUE)
        val inPlayer = target - current.timeOffsetSec
        val known = player.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0)
        val reachable = current.seek != "restart" || (inPlayer >= 0 && known != null && inPlayer <= known - 1)
        if (reachable) player.seekTo((inPlayer * 1000).toLong()) else ask = ask.copy(startSec = target, reload = true, waitMs = 0)
        filmSec = target
        ended = false
    }

    fun changeSpeed(value: Float) {
        speed = value
        player.setPlaybackParameters(PlaybackParameters(value))
    }

    // Choosing a track asks again from the same place, as the website does.
    fun chooseAudio(index: Int) {
        ask = ask.copy(audio = index, startSec = filmSec, reload = false, waitMs = 0)
    }

    fun chooseSubtitle(index: Int, burn: Boolean) {
        ask = ask.copy(subtitle = index, burn = burn, startSec = filmSec, reload = burn || ask.burn, waitMs = 0)
    }

    fun chooseVideo(index: Int) {
        ask = ask.copy(video = index, startSec = filmSec, reload = true, waitMs = 0)
    }

    fun flatten3d(on: Boolean) {
        ask = ask.copy(flatten3d = on, startSec = filmSec, reload = true, waitMs = 0)
    }

    fun setStreaming(value: String) {
        ViewPrefsStore.setStreaming(app, value)
        ask = ask.copy(startSec = filmSec, reload = true, waitMs = 0)
    }

    fun savePrefs(value: ViewPrefs, forThisVideo: Boolean) {
        prefs = value
        ViewPrefsStore.save(app, id, value, forThisVideo)
    }

    // The app going to the background: the place is kept and the sound stops.
    fun backgrounded() {
        saveProgress()
        player.pause()
    }

    // Ending the session: the place is saved and the conversion stopped at once.
    fun close() {
        if (closed) return
        closed = true
        saveProgress()
        ClientLog.session = ""
        val streamId = stream?.streamId.orEmpty()
        if (streamId.isNotEmpty()) app.scope.launch { runCatching { api.stopStream(streamId) } }
        runCatching { network?.unregisterNetworkCallback(networkBack) }
        scope.cancel()
        player.removeListener(listener)
        media.release()
        player.release()
    }
}
