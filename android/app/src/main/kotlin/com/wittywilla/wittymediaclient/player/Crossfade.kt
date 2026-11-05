package com.wittywilla.wittymediaclient.player

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.wittywilla.wittymediaclient.WittyApp
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

// Crossing from one song into the next, as the website's two decks do it (web/src/audio/player.tsx, watchEnd and
// handOff). One ExoPlayer can't play two songs at once, so a second one plays the end of the song going out: it's made
// ready, paused, where the crossing starts, and when the song gets there it carries on from that place while the main
// player moves on to the next song. The main player, which the lock screen and the queue follow, fades in over the
// crossing as the other fades out, with equal power, so the middle isn't a dip. Only songs sent as they are, as on the
// website, and never within an album unless asked.
@OptIn(UnstableApi::class)
class Crossfade(
    private val app: WittyApp,
    private val player: ExoPlayer,
    private val resolver: TrackResolver,
    private val makeTail: () -> ExoPlayer,
    private val level: () -> Unit,
) {
    private var tail: ExoPlayer? = null
    private var readyFor: String? = null
    private var readyAtMs = 0L
    private var crossing = 0.0
    private var watching: Job? = null
    private var handoff: Job? = null
    private var fading: Job? = null

    // How loud the main player is in a crossing, and the one going out: 1 and 0 when there isn't one.
    var mainShare = 1.0
        private set
    private var tailShare = 0.0

    // The main player's own move to the next song, which isn't someone skipping.
    private var movingTo: String? = null

    // While a song plays, every quarter of a second.
    fun playing(on: Boolean) {
        watching?.cancel()
        if (!on) return
        watching = app.scope.launch {
            while (true) {
                watch()
                delay(250)
            }
        }
    }

    // A pause in the middle of a crossing ends it: the song going out stops there.
    fun paused() = finish()

    // The player moved: unless it's the crossing's own move, someone moved, skipped or changed the queue, so whatever
    // was crossing ends now, and what was ready is dropped.
    fun moved(to: String?) {
        if (to != null && to == movingTo) {
            movingTo = null
            return
        }
        interrupted()
    }

    fun interrupted() {
        handoff?.cancel()
        handoff = null
        dropReady()
        finish()
    }

    private fun watch() {
        val sound = app.listening.sound
        val item = player.currentMediaItem ?: return
        val music = item.mediaMetadata.extras?.getBoolean(EXTRA_KEEPS_PLACE) != true
        val next = player.nextMediaItemIndex
        if (!music || sound.crossfade <= 0 || player.repeatMode == Player.REPEAT_MODE_ONE || app.listening.sleepAfterThis || next == C.INDEX_UNSET || fading != null) {
            dropReady()
            return
        }
        val nextItem = player.getMediaItemAt(next)
        val id = item.mediaId.toLongOrNull() ?: return
        val nextId = nextItem.mediaId.toLongOrNull() ?: return
        if (!resolver.isDirect(id) || !resolver.isDirect(nextId)) return
        crossing = sound.fade(item.mediaMetadata.albumTitle?.toString(), nextItem.mediaMetadata.albumTitle?.toString())
        val duration = player.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: return
        if (crossing <= 0 || crossing * 1000 >= duration) {
            dropReady()
            return
        }
        val speed = player.playbackParameters.speed.coerceAtLeast(0.1f)
        val leftSec = (duration - player.currentPosition) / 1000.0 / speed
        if (leftSec > crossing + 20) return
        // Made ready, paused, where the crossing will start.
        val startMs = (duration - crossing * 1000 * speed).toLong()
        if (readyFor != item.mediaId || readyAtMs != startMs) {
            prepare(item, startMs)
            return
        }
        val ready = tail ?: return
        if (handoff == null && leftSec <= crossing + 1.5 && ready.playbackState == Player.STATE_READY) {
            val waitMs = ((startMs - player.currentPosition) / speed).toLong() - 25
            handoff = app.scope.launch {
                delay(waitMs.coerceAtLeast(0))
                handoff = null
                if (player.isPlaying && player.currentMediaItem?.mediaId == readyFor) handOff()
            }
        }
    }

    private fun prepare(item: MediaItem, startMs: Long) {
        val deck = tail ?: makeTail().also { tail = it }
        deck.playWhenReady = false
        deck.volume = 0f
        deck.playbackParameters = player.playbackParameters
        deck.setMediaItem(item, startMs)
        deck.prepare()
        readyFor = item.mediaId
        readyAtMs = startMs
    }

    private fun dropReady() {
        if (readyFor == null) return
        readyFor = null
        if (fading == null) tail?.run { stop(); clearMediaItems() }
    }

    // The song going out carries on from here on the other player, and the main one moves on, silent at first.
    private fun handOff() {
        val deck = tail ?: return
        val seconds = crossing
        readyFor = null
        mainShare = 0.0
        tailShare = 1.0
        level()
        deck.playbackParameters = PlaybackParameters(player.playbackParameters.speed, player.playbackParameters.pitch)
        deck.play()
        movingTo = player.getMediaItemAt(player.nextMediaItemIndex).mediaId
        player.seekToNextMediaItem()
        val began = System.nanoTime()
        fading = app.scope.launch {
            while (true) {
                val part = minOf(1.0, (System.nanoTime() - began) / 1e9 / seconds)
                mainShare = sin(part * PI / 2)
                tailShare = cos(part * PI / 2)
                level()
                if (part >= 1) break
                delay(60)
            }
            fading = null
            finish()
        }
    }

    private fun finish() {
        fading?.cancel()
        fading = null
        tailShare = 0.0
        if (mainShare != 1.0) {
            mainShare = 1.0
            level()
        }
        if (readyFor == null) tail?.run { stop(); clearMediaItems() }
    }

    // The volume the tail plays at, as the main player's own volume with its share.
    fun levelTail(volume: Float) {
        tail?.volume = (volume * tailShare).toFloat()
    }

    fun release() {
        watching?.cancel()
        handoff?.cancel()
        fading?.cancel()
        tail?.release()
        tail = null
    }
}
