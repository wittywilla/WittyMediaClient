package com.wittywilla.wittymediaclient.player

import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.util.EventLogger
import androidx.media3.session.MediaSession
import androidx.media3.ui.PlayerView
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Playback
import com.wittywilla.wittymediaclient.net.PlaybackRequest
import com.wittywilla.wittymediaclient.net.Track
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.ui.ActionButton
import com.wittywilla.wittymediaclient.ui.ErrorText
import com.wittywilla.wittymediaclient.ui.LocalFocusMemory
import com.wittywilla.wittymediaclient.ui.LocalMetrics
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Radius
import com.wittywilla.wittymediaclient.ui.Route
import com.wittywilla.wittymediaclient.ui.ServerImage
import com.wittywilla.wittymediaclient.ui.Space
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

private const val CONTROLS_HIDE_MS = 5_000L
private const val SEEK_COMMIT_MS = 800L
private const val NEXT_COUNTDOWN_SEC = 8
private const val PROFILE = "androidtv"
private const val LOST = "Lost contact with your server. Check that it is running, then try again."

private fun trackName(t: Track): String {
    val language = t.languageName.ifEmpty { if (t.language.isEmpty()) "Unknown" else Locale.forLanguageTag(t.language).displayLanguage.ifEmpty { t.language } }
    // A text subtitle's format means nothing to anyone. A picture-based one's does: it may have to be burned in.
    val codec = if (t.text) "" else t.codec.uppercase(Locale.ROOT)
    return listOf(language, t.title, codec, if (t.channels > 0) "${t.channels}ch" else "")
        .filter { it.isNotEmpty() }.joinToString(" · ")
}

private enum class Picker { None, Audio, Subtitles }

// What to ask the server for. A new value of this opens or changes the stream. Reload means the
// address may well be the same and the player has given up on it, so it has to open it again.
private data class Ask(
    val audio: Int? = null,
    val subtitle: Int? = null,
    val startSec: Double? = null,
    val convert: Boolean = false,
    val flatten3d: Boolean = false,
    val reload: Boolean = false,
    val waitMs: Long = 0,
    val attempt: Int = 0,
)

@OptIn(UnstableApi::class)
private fun newPlayer(context: Context): ExoPlayer =
    ExoPlayer.Builder(context, DefaultRenderersFactory(context).setEnableDecoderFallback(true))
        // Other apps go quiet for this, and this goes quiet for a call. Pulling out headphones pauses
        // rather than playing to the room.
        .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        .setHandleAudioBecomingNoisy(true)
        .build()
        .also {
            // What was chosen and why, in the system log, for a debug build only.
            if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) it.addAnalyticsListener(EventLogger())
        }

private fun hidesBars(view: android.view.View): () -> Unit {
    val window = (view.context as? Activity)?.window ?: return {}
    val bars = WindowCompat.getInsetsController(window, view)
    bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    bars.hide(WindowInsetsCompat.Type.systemBars())
    return { bars.show(WindowInsetsCompat.Type.systemBars()) }
}

@OptIn(UnstableApi::class, ExperimentalLayoutApi::class)
@Composable
fun PlayerScreen(nav: Nav, id: Long, startOver: Boolean) {
    val context = LocalContext.current
    val view = LocalView.current
    val api = nav.app.api

    var item by remember { mutableStateOf<Item?>(null) }
    var stream by remember { mutableStateOf<Playback?>(null) }
    var ask by remember { mutableStateOf(Ask(startSec = if (startOver) 0.0 else null)) }
    var problem by remember { mutableStateOf("") }
    var controls by remember { mutableStateOf(true) }
    var picker by remember { mutableStateOf(Picker.None) }
    var playing by remember { mutableStateOf(false) }
    var filmSec by remember { mutableDoubleStateOf(0.0) }
    var interactions by remember { mutableIntStateOf(0) }
    var countdown by remember { mutableStateOf<Int?>(null) }
    var waitingForNetwork by remember { mutableStateOf(false) }
    var watchNextShown by remember { mutableStateOf(false) }
    var showInfo by remember { mutableStateOf(false) }
    val clock = remember { PlaybackClock() }
    val budget = remember { RetryBudget() }
    val rootFocus = remember { FocusRequester() }
    val player = remember { newPlayer(context) }
    // The system's now-playing card, media keys and voice control. One session per player, and only
    // while this screen is up: there's no playing in the background yet.
    val session = remember { MediaSession.Builder(context, player).setId("witty-$id").build() }

    fun currentFilmSec() = player.currentPosition / 1000.0 + (stream?.timeOffsetSec ?: 0.0)

    fun saveProgress() {
        val duration = stream?.durationSec ?: return
        val at = clock.lastPlace() ?: return
        // In the app's scope: the last save happens as this screen is leaving.
        nav.app.scope.launch { runCatching { api.saveProgress(id, at, duration) } }
    }

    fun tryAgain(start: Ask) {
        problem = ""
        ask = start.copy(startSec = clock.lastPlace() ?: start.startSec, reload = true, attempt = start.attempt + 1)
    }

    // Decided here rather than in the listener: the listener only hears what the player says.
    fun onFailure(e: PlaybackException) {
        val code = (e.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode
        val recovery = recoveryFor(e.errorCode, code)
        val wait = if (recovery == Recovery.GiveUp || (recovery == Recovery.Convert && ask.convert)) null else budget.next()
        ClientLog.report(
            if (wait != null) "warn" else "error",
            "player",
            "Playback failed: ${e.errorCodeName}${if (code != null) ", the server answered $code" else ""}${if (wait != null) ", trying again" else ""}",
            stack = e.stackTraceToString(),
            session = stream?.streamId.orEmpty(),
        )
        if (wait == null) {
            problem = failureWords(e.errorCode, code)
            // Out of tries on a network that's down: the network coming back is one more.
            waitingForNetwork = recovery == Recovery.WaitThenNewStream
            return
        }
        ask = ask.copy(
            startSec = clock.lastPlace() ?: ask.startSec,
            reload = true,
            convert = ask.convert || recovery == Recovery.Convert,
            waitMs = if (recovery == Recovery.WaitThenNewStream) wait else 0,
            attempt = ask.attempt + 1,
        )
    }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                playing = isPlaying
                // Saving on pause means a phone that dies during a pause loses nothing.
                if (!isPlaying) saveProgress()
            }
            override fun onPlayerError(e: PlaybackException) = onFailure(e)
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) clock.ready()
                if (state == Player.STATE_ENDED) {
                    saveProgress()
                    if (stream?.nextId != null) countdown = NEXT_COUNTDOWN_SEC else nav.pop()
                }
            }
        }
        player.addListener(listener)
        val undoBars = hidesBars(view)
        onDispose {
            undoBars()
            player.removeListener(listener)
            session.release()
            player.release()
        }
    }

    // A network coming back is the moment to try again, rather than when a timer says so.
    DisposableEffect(Unit) {
        val network = context.getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                view.post {
                    if (waitingForNetwork && problem.isNotEmpty()) {
                        waitingForNetwork = false
                        budget.reset()
                        tryAgain(ask)
                    }
                }
            }
        }
        val listening = runCatching {
            // Android 6 has no default-network call: any network that reaches the internet will do there.
            if (Build.VERSION.SDK_INT >= 24) network?.registerDefaultNetworkCallback(callback)
            else network?.registerNetworkCallback(NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), callback)
        }.isSuccess
        onDispose { if (listening) runCatching { network?.unregisterNetworkCallback(callback) } }
    }

    // Ask the server what to play, and switch only if the answer is another address. A new `ask`
    // cancels this, which is why being cancelled is not a problem to show.
    LaunchedEffect(ask) {
        try {
            if (ask.waitMs > 0) delay(ask.waitMs)
            if (item == null) item = api.item(id)
            val answer = api.playback(
                id,
                PlaybackRequest(
                    PROFILE, ask.audio, ask.subtitle, ask.startSec,
                    capabilities = DeviceProfile.capabilities(context),
                    maxBitrateKbps = DeviceProfile.maxBitrateKbps(context),
                    forceTranscode = if (ask.convert) true else null,
                    flatten3d = if (ask.flatten3d) true else null,
                ),
            )
            val before = stream
            if (answer.protocol == "disc-session" || answer.url.isEmpty()) {
                problem = "This kind of item can't play in this app yet. Open it in a web browser."
                return@LaunchedEffect
            }
            val changed = ask.reload || answer.url != before?.url
            // An old conversion isn't needed once there's a new one.
            if (before != null && before.streamId.isNotEmpty() && before.streamId != answer.streamId) {
                val old = before.streamId
                nav.app.scope.launch { runCatching { api.stopStream(old) } }
            }
            stream = answer
            ClientLog.session = answer.streamId
            if (changed) {
                clock.switching()
                val current = item
                val media = MediaItem.Builder()
                    .setUri(api.mediaUrl(answer.url))
                    .setMediaMetadata(MediaMetadata.Builder().setTitle(current?.showTitle?.ifEmpty { null } ?: current?.title).setSubtitle(current?.title).build())
                if (answer.protocol == "hls") media.setMimeType(MimeTypes.APPLICATION_M3U8)
                val chosen = answer.subtitles.firstOrNull { it.index == answer.subtitleIndex }
                if (chosen != null && chosen.delivery == "sidecar" && chosen.url.isNotEmpty()) {
                    media.setSubtitleConfigurations(
                        listOf(
                            MediaItem.SubtitleConfiguration.Builder(android.net.Uri.parse(api.mediaUrl(chosen.url)))
                                .setMimeType(MimeTypes.TEXT_VTT)
                                .setLanguage(chosen.language)
                                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                                .build(),
                        ),
                    )
                }
                player.setMediaItem(media.build(), (answer.startAtSec * 1000).toLong())
                player.prepare()
                player.playWhenReady = true
            }
            // Tracks the player can switch itself: embedded, renditions and sidecars.
            val audio = answer.audio.firstOrNull { it.index == answer.audioIndex }
            val text = answer.subtitles.firstOrNull { it.index == answer.subtitleIndex }
            player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                .setPreferredAudioLanguage(TrackMatch.languageFor(audio))
                .setPreferredTextLanguage(TrackMatch.languageFor(text))
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, text == null || answer.subtitleDelivery == "burn")
                .build()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) {
                problem = problemWords(e, LOST)
                waitingForNetwork = e is java.io.IOException
            }
        }
    }

    // The clock. Stops with the screen; nothing here runs while the app is in the background,
    // because leaving pauses the player.
    LaunchedEffect(player) {
        while (true) {
            delay(1000)
            val isPlaying = player.isPlaying
            if (clock.tick(player.currentPosition / 1000.0, stream?.timeOffsetSec ?: 0.0, isPlaying)) saveProgress()
            filmSec = clock.filmSec
            if (isPlaying) budget.played(1.0)
        }
    }

    // Home on a TV or a phone call on a phone: the sound must stop, and the place must be saved.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        saveProgress()
        player.pause()
        controls = true
    }

    // Leaving: save the place and stop the conversion straight away. This runs
    // before the player's own effect above, so the player can still be read.
    DisposableEffect(Unit) {
        onDispose {
            saveProgress()
            ClientLog.session = ""
            val streamId = stream?.streamId.orEmpty()
            if (streamId.isNotEmpty()) nav.app.scope.launch { runCatching { api.stopStream(streamId) } }
        }
    }

    LaunchedEffect(countdown) {
        val left = countdown ?: return@LaunchedEffect
        val next = stream?.nextId ?: return@LaunchedEffect
        if (left <= 0) {
            nav.playInstead(next)
        } else {
            delay(1000)
            countdown = left - 1
        }
    }

    LaunchedEffect(controls, interactions, playing, picker) {
        if (controls && playing && picker == Picker.None) {
            delay(CONTROLS_HIDE_MS)
            controls = false
        }
    }
    LaunchedEffect(controls, picker, problem, countdown) {
        if (!controls && picker == Picker.None && problem.isEmpty() && countdown == null) runCatching { rootFocus.requestFocus() }
    }

    // Coming back to the controls from a list lands on the button that opened it. Coming back after
    // they hid starts from Play again, where OK does what people expect.
    val focusMemory = LocalFocusMemory.current
    LaunchedEffect(controls) { if (!controls) focusMemory.last = null }
    DisposableEffect(Unit) { onDispose { focusMemory.last = null } }

    // How far can be reached depends on the stream: a growing one has to be
    // reopened to go past what exists so far (see `seek` in docs/CLIENT-API.md).
    fun seekFilm(targetSec: Double) {
        val current = stream ?: return
        if (current.seek == "none") return
        val target = targetSec.coerceIn(0.0, current.durationSec.takeIf { it > 0 } ?: Double.MAX_VALUE)
        val inPlayer = target - current.timeOffsetSec
        val known = player.duration.takeIf { it != C.TIME_UNSET }?.div(1000.0)
        val reachable = current.seek != "restart" || (inPlayer >= 0 && known != null && inPlayer <= known)
        if (reachable) {
            player.seekTo((inPlayer * 1000).toLong())
        } else {
            ask = ask.copy(startSec = target, reload = true, waitMs = 0, attempt = ask.attempt + 1)
        }
        filmSec = target
    }
    // Where the intro ends, while it's on.
    fun introEnd(): Double? = stream?.intro?.takeIf { filmSec >= it.startSec && filmSec < it.endSec - 1 }?.endSec
    fun playPause() { if (player.isPlaying) player.pause() else player.play() }
    fun playNext() { stream?.nextId?.let(nav::playInstead) }

    // Back goes up one level at a time: `input-map.json`'s rule. On a phone the system's own back
    // gesture comes here too, without passing through key events.
    fun onBack() {
        when {
            countdown != null -> countdown = null
            showInfo -> showInfo = false
            picker != Picker.None -> picker = Picker.None
            controls && playing -> controls = false
            else -> nav.pop()
        }
    }
    BackHandler { onBack() }

    // Buttons from shared/data/input-map.json. With the controls hidden the arrows
    // seek or show the controls. With them showing, focus moves among the buttons.
    fun onKey(code: Int): Boolean {
        interactions++
        when (code) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_SPACE -> playPause()
            KeyEvent.KEYCODE_MEDIA_PLAY -> player.play()
            KeyEvent.KEYCODE_MEDIA_PAUSE -> player.pause()
            KeyEvent.KEYCODE_MEDIA_REWIND, KeyEvent.KEYCODE_BUTTON_L1, KeyEvent.KEYCODE_J -> seekFilm(currentFilmSec() - seekStepSec(0))
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.KEYCODE_BUTTON_R1, KeyEvent.KEYCODE_L -> seekFilm(currentFilmSec() + seekStepSec(0))
            KeyEvent.KEYCODE_MEDIA_NEXT -> playNext()
            KeyEvent.KEYCODE_CAPTIONS -> { if ((stream?.subtitles?.size ?: 0) > 0) picker = Picker.Subtitles }
            KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_ESCAPE -> onBack()
            KeyEvent.KEYCODE_DPAD_LEFT -> if (controls || picker != Picker.None) return false else seekFilm(currentFilmSec() - seekStepSec(0))
            KeyEvent.KEYCODE_DPAD_RIGHT -> if (controls || picker != Picker.None) return false else seekFilm(currentFilmSec() + seekStepSec(0))
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> if (controls || picker != Picker.None) return false else controls = true
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_BUTTON_A -> when {
                controls || picker != Picker.None -> return false
                // Up on screen by itself during the intro, so OK is for it.
                introEnd() != null -> introEnd()?.let(::seekFilm)
                else -> controls = true
            }
            else -> return false
        }
        return true
    }

    val current = stream
    val duration = current?.durationSec ?: 0.0
    val nextDue = watchNextDue(filmSec, duration, current?.nextId != null)
    // Once, so that someone who hides them during the credits isn't argued with.
    LaunchedEffect(nextDue) { if (nextDue && !watchNextShown) { watchNextShown = true; controls = true } }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            // Before focusable: key handlers only hear the focus target and what wraps it.
            .onPreviewKeyEvent { if (it.type == KeyEventType.KeyDown) onKey(it.key.nativeKeyCode) else false }
            .focusRequester(rootFocus)
            .focusable()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                interactions++
                controls = !controls
            }
            .semantics { contentDescription = item?.title.orEmpty().ifEmpty { "Player" } },
    ) {
        AndroidView(
            factory = { PlayerView(it).apply { useController = false; this.player = player } },
            // The picture doesn't count as using the phone, and a TV would put up its screensaver.
            update = { it.keepScreenOn = playing },
            modifier = Modifier.fillMaxSize(),
        )
        // Sound has no picture of its own.
        if (item?.kind == "audio" || item?.kind == "radio") {
            item?.let {
                ServerImage(api.posterUrl(it), 320.dp, 1f, Modifier.align(Alignment.Center).width(320.dp).aspectRatio(1f).clip(Radius.LG), placeholder = it.title)
            }
        }
        val left = countdown
        if (problem.isNotEmpty()) {
            Column(Modifier.align(Alignment.Center).safeDrawingPadding().padding(Space.S8), verticalArrangement = Arrangement.spacedBy(Space.S3)) {
                ErrorText(problem)
                ActionButton("Try again", { budget.reset(); tryAgain(ask) }, primary = true, takeFocus = true)
                ActionButton("Back", nav::pop)
            }
        } else if (left != null) {
            Column(Modifier.align(Alignment.Center).padding(Space.S8), verticalArrangement = Arrangement.spacedBy(Space.S3), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Next episode in $left", color = Color.White, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { contentDescription = "Next episode in $left seconds" })
                ActionButton("Play now", ::playNext, primary = true, takeFocus = true)
                ActionButton("Cancel", { countdown = null; nav.pop() })
            }
        } else if (showInfo && current != null) {
            Column(
                Modifier.align(Alignment.Center).safeDrawingPadding().widthIn(max = 560.dp).background(Color(0xEE101114), Radius.LG).verticalScroll(rememberScrollState()).padding(Space.S4),
                verticalArrangement = Arrangement.spacedBy(Space.S2),
            ) {
                Text(current.explain?.summary.orEmpty().ifEmpty { "How this is playing" }, color = Color.White, style = MaterialTheme.typography.titleMedium)
                current.explain?.lines.orEmpty().forEach { Text(it, color = Color(0xFFD0D0D8), style = MaterialTheme.typography.bodyMedium) }
                ActionButton("Close", { showInfo = false }, takeFocus = true)
            }
        } else if (picker != Picker.None && current != null) {
            TrackList(
                tracks = if (picker == Picker.Audio) current.audio else current.subtitles,
                selected = if (picker == Picker.Audio) current.audioIndex else current.subtitleIndex,
                allowOff = picker == Picker.Subtitles,
                onPick = { index ->
                    val at = clock.lastPlace() ?: currentFilmSec()
                    ask = if (picker == Picker.Audio) {
                        ask.copy(audio = index, startSec = at, reload = false, waitMs = 0, attempt = ask.attempt + 1)
                    } else {
                        ask.copy(subtitle = index, startSec = at, reload = false, waitMs = 0, attempt = ask.attempt + 1)
                    }
                    picker = Picker.None
                },
                modifier = Modifier.align(Alignment.Center).safeDrawingPadding(),
            )
        } else if (controls) {
            Controls(
                title = item?.showTitle?.ifEmpty { null } ?: item?.title.orEmpty(),
                subtitle = if (item?.showTitle.isNullOrEmpty()) "" else item?.title.orEmpty(),
                playing = playing,
                canSeek = current != null && current.seek != "none" && duration > 0,
                filmSec = filmSec,
                durationSec = duration,
                introEndSec = introEnd(),
                nextDue = nextDue,
                hasNext = current?.nextId != null,
                hasAudioChoice = (current?.audio?.size ?: 0) > 1,
                hasSubtitles = (current?.subtitles?.size ?: 0) > 0,
                hasInfo = current?.explain != null,
                stereo = current?.stereo.orEmpty().isNotEmpty(),
                flattened = ask.flatten3d,
                onInfo = { showInfo = true },
                onFlatten = {
                    ask = ask.copy(flatten3d = !ask.flatten3d, startSec = clock.lastPlace() ?: currentFilmSec(), reload = false, waitMs = 0, attempt = ask.attempt + 1)
                },
                onTouched = { interactions++ },
                onPlayPause = { interactions++; playPause() },
                onSeekBack = { interactions++; seekFilm(currentFilmSec() - seekStepSec(0)) },
                onSeekForward = { interactions++; seekFilm(currentFilmSec() + seekStepSec(0)) },
                onSeekTo = { interactions++; seekFilm(it) },
                onNext = ::playNext,
                onAudio = { picker = Picker.Audio },
                onSubtitles = { picker = Picker.Subtitles },
                onBack = nav::pop,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        } else {
            // The controls hide after a few seconds, and an intro shouldn't need them called back.
            // A remote's OK is sent here from onKey, and focus stays where the arrows keep seeking.
            introEnd()?.let { end ->
                ActionButton(
                    "Skip intro", { seekFilm(end) }, primary = true, pill = true,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .safeDrawingPadding()
                        .padding(LocalMetrics.current.gutter)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                )
            }
        }
    }
}

// The bar along the film. Left and right on a remote move it, and it only seeks once they stop:
// on a growing stream each seek can mean opening a new one. A finger does the same.
@Composable
private fun SeekBar(filmSec: Double, durationSec: Double, onTouched: () -> Unit, onSeekTo: (Double) -> Unit, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    var pending by remember { mutableStateOf<Double?>(null) }
    var width by remember { mutableIntStateOf(1) }
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val shown = (pending ?: filmSec).coerceIn(0.0, durationSec)
    val fraction = if (durationSec > 0) (shown / durationSec).toFloat() else 0f
    LaunchedEffect(pending) {
        val target = pending ?: return@LaunchedEffect
        delay(SEEK_COMMIT_MS)
        onSeekTo(target)
        pending = null
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(metrics.minTarget)
            .onKeyEvent {
                if (it.type != KeyEventType.KeyDown) return@onKeyEvent false
                val direction = when (it.key.nativeKeyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> -1
                    KeyEvent.KEYCODE_DPAD_RIGHT -> 1
                    else -> return@onKeyEvent false
                }
                onTouched()
                pending = (shown + direction * seekStepSec((it.nativeKeyEvent as KeyEvent).repeatCount)).coerceIn(0.0, durationSec)
                true
            }
            .focusable(interactionSource = interaction)
            .pointerInput(durationSec) {
                detectTapGestures { offset ->
                    onTouched()
                    onSeekTo(durationSec * (offset.x / size.width).coerceIn(0f, 1f))
                }
            }
            .pointerInput(durationSec) {
                detectHorizontalDragGestures(
                    onDragEnd = { pending?.let(onSeekTo); pending = null },
                    onDragCancel = { pending = null },
                ) { change, _ ->
                    onTouched()
                    width = size.width
                    pending = durationSec * (change.position.x / size.width).coerceIn(0f, 1f).toDouble()
                }
            }
            .semantics {
                contentDescription = "Position"
                stateDescription = "${spokenClock(shown)} of ${spokenClock(durationSec)}"
                progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f)
                setProgress { value -> onSeekTo(durationSec * value.coerceIn(0f, 1f)); true }
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        val track = if (focused) 8.dp else 4.dp
        Box(Modifier.fillMaxWidth().height(track).background(Color(0x66FFFFFF), Radius.FULL))
        Box(Modifier.fillMaxWidth(fraction).height(track).background(scheme.primary, Radius.FULL))
        if (focused) Box(Modifier.fillMaxWidth().fillMaxHeight().border(metrics.focusRing, Color.White, Radius.SM))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Controls(
    title: String,
    subtitle: String,
    playing: Boolean,
    canSeek: Boolean,
    filmSec: Double,
    durationSec: Double,
    introEndSec: Double?,
    nextDue: Boolean,
    hasNext: Boolean,
    hasAudioChoice: Boolean,
    hasSubtitles: Boolean,
    hasInfo: Boolean,
    stereo: Boolean,
    flattened: Boolean,
    onInfo: () -> Unit,
    onFlatten: () -> Unit,
    onTouched: () -> Unit,
    onPlayPause: () -> Unit,
    onSeekBack: () -> Unit,
    onSeekForward: () -> Unit,
    onSeekTo: (Double) -> Unit,
    onNext: () -> Unit,
    onAudio: () -> Unit,
    onSubtitles: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val metrics = LocalMetrics.current
    // The player is always dark, whatever the theme.
    Column(
        modifier
            .fillMaxWidth()
            .background(Color(0xCC000000))
            .safeDrawingPadding()
            .padding(horizontal = metrics.gutter, vertical = Space.S4),
        verticalArrangement = Arrangement.spacedBy(Space.S2),
    ) {
        Text(title, color = Color.White, style = MaterialTheme.typography.titleLarge)
        if (subtitle.isNotEmpty()) Text(subtitle, color = Color(0xFFD0D0D8), style = MaterialTheme.typography.bodyMedium)
        if (introEndSec != null) ActionButton("Skip intro", { onSeekTo(introEndSec) }, primary = true, requestFocus = true, focusKey = "c-skip")
        if (nextDue) ActionButton("Next episode", onNext, primary = true, requestFocus = introEndSec == null, focusKey = "c-next-due")
        if (canSeek) SeekBar(filmSec, durationSec, onTouched, onSeekTo)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.S2), verticalArrangement = Arrangement.spacedBy(Space.S2), itemVerticalAlignment = Alignment.CenterVertically) {
            ActionButton(if (playing) "Pause" else "Play", onPlayPause, primary = !nextDue && introEndSec == null, requestFocus = !nextDue && introEndSec == null, focusKey = "c-play")
            if (canSeek) {
                ActionButton("Back 10 s", onSeekBack, focusKey = "c-back")
                ActionButton("Forward 10 s", onSeekForward, focusKey = "c-forward")
            }
            if (hasAudioChoice) ActionButton("Audio", onAudio, focusKey = "c-audio")
            if (hasSubtitles) ActionButton("Subtitles", onSubtitles, focusKey = "c-subtitles")
            if (stereo) ActionButton(if (flattened) "Show as stored" else "Show in 2D", onFlatten, focusKey = "c-flatten")
            if (hasInfo) ActionButton("Info", onInfo, focusKey = "c-info")
            if (hasNext && !nextDue) ActionButton("Next episode", onNext, focusKey = "c-next")
            // On a remote or a phone Back does this too; this is for those who look for it.
            ActionButton("Leave", onBack, focusKey = "c-leave")
            if (durationSec > 0) {
                Text(
                    "${clock(filmSec)} / ${clock(durationSec)}", color = Color.White, style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.semantics { contentDescription = "${spokenClock(filmSec)} of ${spokenClock(durationSec)}" },
                )
            }
        }
    }
}

@Composable
private fun TrackList(
    tracks: List<Track>,
    selected: Int,
    allowOff: Boolean,
    onPick: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .widthIn(max = 520.dp)
            .background(Color(0xEE101114), Radius.LG)
            .verticalScroll(rememberScrollState())
            .padding(Space.S4),
        verticalArrangement = Arrangement.spacedBy(Space.S2),
    ) {
        if (allowOff) ActionButton("Off", { onPick(-1) }, Modifier.fillMaxWidth(), selected = selected == -1, takeFocus = selected == -1)
        tracks.distinctBy { it.index }.forEach { t ->
            ActionButton(trackName(t), { onPick(t.index) }, Modifier.fillMaxWidth(), selected = t.index == selected, takeFocus = t.index == selected)
        }
    }
}
