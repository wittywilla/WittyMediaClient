package com.wittywilla.wittymediaclient.player

import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.session.MediaController
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Item
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

// One line of the queue, in the order it will play.
data class QueueEntry(val index: Int, val mediaId: String, val title: String, val artist: String, val durationSec: Double, val artwork: Uri?)

// What the app's screens know about what's playing, and how they ask for it to change. The sound itself is in
// ListeningService. A controller is only held while the app is on screen, and only once there's a queue, so someone
// watching films pays nothing for this.
@OptIn(UnstableApi::class)
class Listening(private val app: WittyApp) {
    var now by mutableStateOf<MediaItem?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var queue by mutableStateOf<List<QueueEntry>>(emptyList())
        private set
    var nowIndex by mutableIntStateOf(0)
        private set
    var shuffle by mutableStateOf(false)
        private set
    var repeat by mutableIntStateOf(Player.REPEAT_MODE_OFF)
        private set
    var speed by mutableFloatStateOf(1f)
        private set
    var canGoNext by mutableStateOf(false)
        private set

    // Said by the service when it has given up. Empty means all is well.
    var problem by mutableStateOf("")

    // Goes up when the place changes by other than playing, so that a clock on screen looks again.
    var jumps by mutableIntStateOf(0)
        private set

    // Asked for by a tap on the notification, or a TV starting a queue, for when the screens are ready.
    var wantsScreen by mutableStateOf(false)

    var serviceRunning = false
    var keeper: ListeningKeeper? = null

    private var controller: MediaController? = null
    private var connecting: ListenableFuture<MediaController>? = null
    private val waiting = ArrayList<(MediaController) -> Unit>()
    private val prefs by lazy { app.getSharedPreferences("listening", Context.MODE_PRIVATE) }

    val keepsPlace: Boolean get() = now?.mediaMetadata?.extras?.getBoolean(EXTRA_KEEPS_PLACE) == true

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            read(player)
            if (events.contains(Player.EVENT_POSITION_DISCONTINUITY)) jumps++
            // An empty queue: let go, so that the service can end. The next one starts it again.
            if (player.mediaItemCount == 0 && events.contains(Player.EVENT_TIMELINE_CHANGED)) disappeared()
        }
    }

    private fun read(player: Player) {
        now = player.currentMediaItem
        isPlaying = player.isPlaying
        isLoading = player.playbackState == Player.STATE_BUFFERING && player.playWhenReady
        nowIndex = player.currentMediaItemIndex
        shuffle = player.shuffleModeEnabled
        repeat = player.repeatMode
        speed = player.playbackParameters.speed
        canGoNext = player.hasNextMediaItem()
        queue = readQueue(player)
    }

    private fun readQueue(player: Player): List<QueueEntry> {
        val timeline = player.currentTimeline
        val count = timeline.windowCount
        if (count == 0) return emptyList()
        val order = playOrder(timeline.getFirstWindowIndex(player.shuffleModeEnabled), count) {
            timeline.getNextWindowIndex(it, Player.REPEAT_MODE_OFF, player.shuffleModeEnabled)
        }
        return order.map { i ->
            val item = player.getMediaItemAt(i)
            val about = item.mediaMetadata
            QueueEntry(i, item.mediaId, about.title?.toString().orEmpty(), about.artist?.toString().orEmpty(), (about.durationMs ?: 0L) / 1000.0, about.artworkUri)
        }
    }

    // Back on screen with something playing: catch up with what happened meanwhile. If the queue
    // finished and the service went with it, there's nothing to show.
    fun appeared() {
        if (serviceRunning) connect {} else clear()
    }

    private fun clear() {
        now = null
        queue = emptyList()
        isPlaying = false
        isLoading = false
    }

    // Off screen, nothing needs to hear about any of this. The service carries on.
    fun disappeared() {
        connecting?.let { MediaController.releaseFuture(it) }
        connecting = null
        controller = null
        waiting.clear()
    }

    private fun connect(then: (MediaController) -> Unit) {
        controller?.let { then(it); return }
        waiting += then
        if (connecting != null) return
        val future = MediaController.Builder(app, ListeningService.token(app))
            .setListener(object : MediaController.Listener {
                // The service has gone, which the system can do to a paused one.
                override fun onDisconnected(controller: MediaController) {
                    if (this@Listening.controller === controller) {
                        this@Listening.controller = null
                        connecting = null
                        clear()
                    }
                }
            })
            .buildAsync()
        connecting = future
        future.addListener({
            if (connecting !== future) return@addListener
            val made = runCatching { future.get() }.getOrElse {
                ClientLog.warn("player", "The listening service couldn't be reached: ${it.javaClass.simpleName}")
                connecting = null
                waiting.clear()
                return@addListener
            }
            controller = made
            made.addListener(listener)
            read(made)
            waiting.toList().forEach { it(made) }
            waiting.clear()
        }, MoreExecutors.directExecutor())
    }

    private fun savedSpeed(books: Boolean) = if (books) prefs.getFloat(KEY_BOOK_SPEED, 1f) else 1f

    fun play(tracks: List<Item>, start: Start, books: Boolean) {
        if (tracks.isEmpty()) return
        problem = ""
        val items = tracks.map { trackItem(it, books) }
        connect { c ->
            c.playbackParameters = PlaybackParameters(savedSpeed(books))
            c.shuffleModeEnabled = false
            c.setMediaItems(items, start.index.coerceIn(0, items.lastIndex), (start.atSec * 1000).toLong())
            c.prepare()
            c.play()
        }
    }

    fun playNext(tracks: List<Item>, books: Boolean) {
        val items = tracks.map { trackItem(it, books) }
        connect { c ->
            if (c.mediaItemCount == 0) play(tracks, Start(0), books)
            else c.addMediaItems((c.currentMediaItemIndex + 1).coerceAtMost(c.mediaItemCount), items)
        }
    }

    fun addToQueue(tracks: List<Item>, books: Boolean) {
        val items = tracks.map { trackItem(it, books) }
        connect { c ->
            if (c.mediaItemCount == 0) play(tracks, Start(0), books)
            else c.addMediaItems(items)
        }
    }

    private fun trackItem(track: Item, books: Boolean): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(track.title)
            .setArtist(track.artist.ifEmpty { track.albumArtist })
            .setAlbumArtist(track.albumArtist)
            .setAlbumTitle(track.album)
            .setTrackNumber(track.track)
            .setDurationMs((track.runtimeSec * 1000).toLong())
            .setArtworkUri(Uri.parse(app.api.posterUrl(track)))
            .setIsPlayable(true)
            .setIsBrowsable(false)
            .setMediaType(if (books) MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER else MediaMetadata.MEDIA_TYPE_MUSIC)
            .setExtras(Bundle().apply { putBoolean(EXTRA_KEEPS_PLACE, books); putLong(EXTRA_LIBRARY, track.libraryId) })
            .build()
        return MediaItem.Builder().setMediaId(track.id.toString()).setMediaMetadata(metadata).build()
    }

    fun positionSec(): Double = (controller?.currentPosition ?: 0L) / 1000.0

    fun durationSec(): Double {
        // The server's length first, so that a track says the same here as in the list it came from.
        val c = controller ?: return 0.0
        val told = c.currentMediaItem?.mediaMetadata?.durationMs?.takeIf { it > 0 }
        return (told ?: c.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: 0L) / 1000.0
    }

    // Also Play on a finished queue, which starts it again.
    fun toggle() {
        if (problem.isNotEmpty() || controller?.playerError != null) {
            keeper?.tryAgain()
            return
        }
        controller?.let { Util.handlePlayPauseButtonAction(it) }
    }

    fun pause() {
        controller?.pause()
    }

    // A film has started. The sound stops whether or not the player has heard from the system yet.
    fun pauseForVideo() {
        if (serviceRunning) connect { it.pause() }
    }

    fun next() {
        controller?.seekToNext()
    }

    fun previous() {
        controller?.seekToPrevious()
    }

    fun seekTo(sec: Double) {
        controller?.seekTo((sec * 1000).toLong().coerceAtLeast(0))
    }

    fun seekBy(sec: Double) = seekTo(positionSec() + sec)

    fun jumpTo(index: Int) {
        controller?.run {
            seekToDefaultPosition(index)
            if (playbackState == Player.STATE_IDLE) prepare()
            play()
        }
    }

    fun remove(index: Int) {
        controller?.removeMediaItem(index)
    }

    fun move(from: Int, to: Int) {
        controller?.run { if (to in 0 until mediaItemCount) moveMediaItem(from, to) }
    }

    fun toggleShuffle() {
        controller?.run { shuffleModeEnabled = !shuffleModeEnabled }
    }

    fun cycleRepeat() {
        controller?.run {
            repeatMode = when (repeatMode) {
                Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
                Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
                else -> Player.REPEAT_MODE_OFF
            }
        }
    }

    // The website's speed menu: a chosen speed, kept for books.
    fun chooseSpeed(chosen: Float) {
        controller?.playbackParameters = PlaybackParameters(chosen)
        if (keepsPlace) prefs.edit { putFloat(KEY_BOOK_SPEED, chosen) }
    }

    // The sleep timer, as the website's: a clock time to pause at, or the end of what's playing. Not kept.
    var sleepAt by mutableStateOf<Long?>(null)
        private set
    var sleepAfterThis by mutableStateOf(false)
        private set
    private var sleeper: Job? = null

    fun sleep(atMillis: Long?, afterThis: Boolean) {
        sleeper?.cancel()
        sleepAt = atMillis
        sleepAfterThis = afterThis
        if (atMillis == null && !afterThis) return
        val track = now?.mediaId
        sleeper = app.scope.launch {
            while (true) {
                kotlinx.coroutines.delay(250)
                val left = durationSec() - positionSec()
                val due = (atMillis != null && System.currentTimeMillis() >= atMillis) || (afterThis && (now?.mediaId != track || (durationSec() > 0 && left < 0.35)))
                if (due) {
                    pause()
                    sleepAt = null
                    sleepAfterThis = false
                    break
                }
            }
        }
    }

    fun cycleSpeed() {
        val chosen = nextSpeed(speed)
        controller?.playbackParameters = PlaybackParameters(chosen)
        if (keepsPlace) prefs.edit { putFloat(KEY_BOOK_SPEED, chosen) }
    }

    // Clears the queue, which also ends the service.
    fun stop() {
        problem = ""
        controller?.run {
            stop()
            clearMediaItems()
        }
    }

    // Leaving a server or an account. The last place is on its way before the sign-in ends, so the caller can
    // wait for it, and nothing keeps playing for the next person.
    fun forget(): Job {
        val sent = keeper?.reportNow()
        if (serviceRunning) {
            connect { c ->
                c.stop()
                c.clearMediaItems()
            }
        }
        clear()
        problem = ""
        return app.scope.launch { sent?.join() }
    }

    private companion object {
        const val KEY_BOOK_SPEED = "bookSpeed"
    }
}
