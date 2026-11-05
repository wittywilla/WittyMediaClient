package com.wittywilla.wittymediaclient.player

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.session.CacheBitmapLoader
import androidx.media3.session.CommandButton
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.toBitmap
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import com.wittywilla.wittymediaclient.MainActivity
import com.wittywilla.wittymediaclient.R
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException

// Music, audiobooks and podcasts, playing with or without the app's screens: the lock screen, the notification,
// a TV's now-playing card, headphone buttons and voice control all come from this session. Everything here is on
// the main thread, including the player's own callbacks.

private const val ARTWORK_PIXELS = 512
private const val BOOK_BACK_MS = 15_000L
private const val BOOK_FORWARD_MS = 30_000L
const val OPEN_NOW_PLAYING = "com.wittywilla.wittymediaclient.NOW_PLAYING"
const val EXTRA_KEEPS_PLACE = "keepsPlace"
const val EXTRA_LIBRARY = "library"

@OptIn(UnstableApi::class)
class ListeningService : MediaSessionService() {
    private var session: MediaSession? = null
    private var keeper: ListeningKeeper? = null

    override fun onCreate() {
        super.onCreate()
        val app = application as WittyApp
        val resolver = TrackResolver(app)
        val shaper = SoundShaper()
        SoundShaping.heard = shaper
        val player = ExoPlayer.Builder(this, ShapedRenderers(this, shaper).setEnableDecoderFallback(true))
            .setMediaSourceFactory(TrackSources(resolver))
            .setAudioAttributes(soundFor(false), true)
            .setHandleAudioBecomingNoisy(true)
            // Keeps the device and the Wi-Fi awake with the screen off, for as long as it's playing.
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setSeekBackIncrementMs(BOOK_BACK_MS)
            .setSeekForwardIncrementMs(BOOK_FORWARD_MS)
            .build()
        setMediaNotificationProvider(DefaultMediaNotificationProvider.Builder(this).build().apply { setSmallIcon(R.drawable.ic_notification) })
        val made = MediaSession.Builder(this, player)
            .setId(SESSION_ID)
            .setCallback(Callback())
            .setSessionActivity(openScreen())
            .setBitmapLoader(CacheBitmapLoader(ServerPictures(app)))
            .build()
        session = made
        keeper = ListeningKeeper(app, player, resolver, made) { stopSelf() }
        app.listening.serviceRunning = true
    }

    // Tapping the notification, or the card on a TV. The action only ever opens the player's screen.
    private fun openScreen(): PendingIntent = PendingIntent.getActivity(
        this, 0,
        Intent(OPEN_NOW_PLAYING).setComponent(ComponentName(this, MainActivity::class.java)),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo) = session

    override fun onDestroy() {
        (application as WittyApp).listening.serviceRunning = false
        SoundShaping.heard = null
        keeper?.release()
        keeper = null
        session?.run {
            player.release()
            release()
        }
        session = null
        super.onDestroy()
    }

    private inner class Callback : MediaSession.Callback {
        // Headphones, the lock screen and other apps can press the buttons. Only this app can say what's in the queue.
        override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
            if (controller.packageName == packageName) return MediaSession.ConnectionResult.accept(MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS, MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS)
            val commands = MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS.buildUpon()
                .removeAll(Player.COMMAND_CHANGE_MEDIA_ITEMS, Player.COMMAND_SET_MEDIA_ITEM)
                .build()
            return MediaSession.ConnectionResult.accept(MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS, commands)
        }

        // A track is only ever its item's number here, whatever came with it.
        override fun onAddMediaItems(session: MediaSession, controller: MediaSession.ControllerInfo, mediaItems: MutableList<MediaItem>): ListenableFuture<MutableList<MediaItem>> {
            val tracks = mediaItems.mapNotNull { item -> item.mediaId.toLongOrNull()?.let { item.buildUpon().setUri(itemUri(it)).build() } }
            return Futures.immediateFuture(tracks.toMutableList())
        }
    }

    companion object {
        const val SESSION_ID = "witty-listening"

        fun token(app: WittyApp) = SessionToken(app, ComponentName(app, ListeningService::class.java))

        // Speech ducks differently from music, and pauses instead when a notification sounds.
        fun soundFor(speech: Boolean): AudioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(if (speech) C.AUDIO_CONTENT_TYPE_SPEECH else C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()
    }
}

// The usual renderers, with the sound going through the shaper on its way out (SoundShaper.kt).
@OptIn(UnstableApi::class)
class ShapedRenderers(context: android.content.Context, private val shaper: SoundShaper) : DefaultRenderersFactory(context) {
    override fun buildAudioSink(context: android.content.Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink =
        DefaultAudioSink.Builder(context).setAudioProcessors(arrayOf(shaper)).build()
}

// A cover from the server, with the sign-in, for the lock screen and the notification.
@OptIn(UnstableApi::class)
private class ServerPictures(private val app: WittyApp) : BitmapLoader {
    override fun supportsMimeType(mimeType: String) = Util.isBitmapFactorySupportedMimeType(mimeType)

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> = fromAnotherThread {
        BitmapFactory.decodeByteArray(data, 0, data.size) ?: throw IOException("Not a picture")
    }

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> = fromAnotherThread {
        val request = ImageRequest.Builder(app).data(uri.toString()).size(ARTWORK_PIXELS).allowHardware(false).build()
        SingletonImageLoader.get(app).execute(request).image?.toBitmap() ?: throw IOException("No picture")
    }

    private fun fromAnotherThread(make: suspend () -> Bitmap): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        app.scope.launch(Dispatchers.IO) {
            try {
                future.set(make())
            } catch (e: CancellationException) {
                future.cancel(false)
                throw e
            } catch (e: Exception) {
                future.setException(e)
            }
        }
        return future
    }
}

// What has to go on for as long as a queue does, whichever screens are up: telling the server where things
// got to, and picking playback up again when the network or a stream fails.
@OptIn(UnstableApi::class)
class ListeningKeeper(
    private val app: WittyApp,
    private val player: ExoPlayer,
    private val resolver: TrackResolver,
    private val session: MediaSession,
    private val finished: () -> Unit,
) : Player.Listener {
    private var saving: Job? = null
    private var retrying: Job? = null
    private var playingSince = 0L
    private var heardMs = 0L
    private var speech: Boolean? = null
    private val budget = RetryBudget()
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    init {
        player.addListener(this)
        app.listening.keeper = this
    }

    private fun MediaItem?.keepsPlace() = this?.mediaMetadata?.extras?.getBoolean(EXTRA_KEEPS_PLACE) == true

    private fun durationOf(item: MediaItem) = (item.mediaMetadata.durationMs ?: 0L) / 1000.0

    private fun heardSec(): Double {
        val running = if (playingSince > 0) SystemClock.elapsedRealtime() - playingSince else 0
        return (heardMs + running) / 1000.0
    }

    // Sent with the connection this started on, as the app can have moved on to another by the time it arrives.
    private suspend fun send(api: Api, id: Long, report: Report) {
        runCatching {
            when (report) {
                is Report.Place -> api.saveProgress(id, report.positionSec, report.durationSec)
                is Report.Listened -> api.recordListen(id, report.seconds)
            }
        }
    }

    private fun report(item: MediaItem?, positionMs: Long, reachedEnd: Boolean, api: Api = app.api): Job? {
        val id = item?.mediaId?.toLongOrNull() ?: return null
        val what = reportOn(item.keepsPlace(), positionMs / 1000.0, durationOf(item), heardSec(), reachedEnd) ?: return null
        return app.scope.launch { send(api, id, what) }
    }

    // Now, for leaving a server, while the sign-in still works. The caller can wait for it to arrive.
    fun reportNow(): Job? {
        val job = report(player.currentMediaItem, player.currentPosition, false)
        heardMs = 0
        if (playingSince > 0) playingSince = SystemClock.elapsedRealtime()
        return job
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (isPlaying) {
            playingSince = SystemClock.elapsedRealtime()
            app.listening.problem = ""
            saving?.cancel()
            saving = app.scope.launch {
                while (true) {
                    delay(PlaybackClock.SAVE_EVERY_SEC.toLong() * 1000)
                    budget.played(PlaybackClock.SAVE_EVERY_SEC)
                    val item = player.currentMediaItem
                    if (item.keepsPlace()) report(item, player.currentPosition, false)
                }
            }
        } else {
            saving?.cancel()
            if (playingSince > 0) heardMs += SystemClock.elapsedRealtime() - playingSince
            playingSince = 0
            // Saving on pause means a device that dies during a pause loses nothing.
            val item = player.currentMediaItem
            if (item.keepsPlace() && player.playbackState != Player.STATE_ENDED) report(item, player.currentPosition, false)
        }
    }

    // The one place that hears where the last track got to, once the player has moved on from it.
    override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
        val left = oldPosition.mediaItem ?: return
        val reachedEnd = reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION
        if (left.mediaId == newPosition.mediaItem?.mediaId && !reachedEnd) return
        report(left, oldPosition.positionMs, reachedEnd)
        heardMs = 0
        if (playingSince > 0) playingSince = SystemClock.elapsedRealtime()
    }

    override fun onPlaybackStateChanged(state: Int) {
        if (state == Player.STATE_ENDED) {
            report(player.currentMediaItem, player.currentPosition, true)
            heardMs = 0
        }
        if (state == Player.STATE_READY) stopWaitingForNetwork()
    }

    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
        if (mediaItem != null) matchSound(mediaItem.keepsPlace())
    }

    override fun onTimelineChanged(timeline: androidx.media3.common.Timeline, reason: Int) {
        if (!timeline.isEmpty) return
        retrying?.cancel()
        stopWaitingForNetwork()
        resolver.forgetAll()
        // Nothing left to play, so nothing to hold on to.
        finished()
    }

    // The same words for the system as for a person: books get Back and Forward on the lock screen, as Next would
    // lose a place, and songs get Previous and Next.
    private fun matchSound(speaking: Boolean) {
        if (speech == speaking) return
        speech = speaking
        player.setAudioAttributes(ListeningService.soundFor(speaking), true)
        session.setMediaButtonPreferences(
            if (speaking) {
                ImmutableList.of(
                    CommandButton.Builder(CommandButton.ICON_SKIP_BACK_15).setDisplayName("Back 15 seconds").setPlayerCommand(Player.COMMAND_SEEK_BACK).setSlots(CommandButton.SLOT_BACK).build(),
                    CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD_30).setDisplayName("Forward 30 seconds").setPlayerCommand(Player.COMMAND_SEEK_FORWARD).setSlots(CommandButton.SLOT_FORWARD).build(),
                )
            } else {
                ImmutableList.of()
            },
        )
    }

    // The same rules as a film: docs/CLIENT-API.md, "What a TV app must build itself".
    override fun onPlayerError(e: PlaybackException) {
        val status = (e.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode
        val id = player.currentMediaItem?.mediaId?.toLongOrNull()
        val recovery = recoveryFor(e.errorCode, status)
        if (id != null) resolver.forget(id)
        val wait = if (recovery == Recovery.GiveUp || (recovery == Recovery.Convert && (id == null || resolver.isConverting(id)))) null else budget.next()
        ClientLog.report(
            if (wait != null) "warn" else "error", "player",
            "Listening failed: ${e.errorCodeName}${if (status != null) ", the server answered $status" else ""}${if (wait != null) ", trying again" else ""}",
            stack = e.stackTraceToString(),
        )
        if (wait != null) {
            if (recovery == Recovery.Convert && id != null) resolver.convert(id)
            retrying?.cancel()
            retrying = app.scope.launch {
                delay(if (recovery == Recovery.WaitThenNewStream) wait else 0)
                player.prepare()
            }
            return
        }
        when {
            // With the network down the next track won't play either, so wait for it to come back.
            recovery == Recovery.WaitThenNewStream -> {
                app.listening.problem = failureWords(e.errorCode, status)
                waitForNetwork()
            }
            // One bad file shouldn't end an album.
            player.hasNextMediaItem() -> {
                budget.reset()
                player.seekToNextMediaItem()
                player.prepare()
            }
            else -> app.listening.problem = failureWords(e.errorCode, status)
        }
    }

    // The Sound panel, the volume or karaoke changed something. The shape itself is already set (SoundShaping).
    fun soundChanged(levelingChanged: Boolean) {
    }

    // A person pressing Try again, or Play, after it gave up.
    fun tryAgain() {
        budget.reset()
        retrying?.cancel()
        stopWaitingForNetwork()
        app.listening.problem = ""
        player.prepare()
        player.play()
    }

    private fun waitForNetwork() {
        if (networkCallback != null) return
        val network = app.getSystemService(ConnectivityManager::class.java) ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(n: Network) {
                val self = this
                // The app's scope is on the main thread, and this call isn't.
                app.scope.launch { if (networkCallback === self) tryAgain() }
            }
        }
        val listening = runCatching {
            // Android 6 has no default-network call: any network that reaches the internet will do there.
            if (Build.VERSION.SDK_INT >= 24) network.registerDefaultNetworkCallback(callback)
            else network.registerNetworkCallback(NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), callback)
        }.isSuccess
        if (listening) networkCallback = callback
    }

    private fun stopWaitingForNetwork() {
        val callback = networkCallback ?: return
        networkCallback = null
        runCatching { app.getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(callback) }
    }

    fun release() {
        report(player.currentMediaItem, player.currentPosition, false)
        saving?.cancel()
        retrying?.cancel()
        stopWaitingForNetwork()
        player.removeListener(this)
        if (app.listening.keeper === this) app.listening.keeper = null
    }
}
