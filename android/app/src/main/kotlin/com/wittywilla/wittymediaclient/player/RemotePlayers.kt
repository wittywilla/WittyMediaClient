// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.media3.common.Player
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.keepsPlace
import com.wittywilla.wittymediaclient.net.remote.CANT_DO
import com.wittywilla.wittymediaclient.net.remote.Feature
import com.wittywilla.wittymediaclient.net.remote.MusicFacts
import com.wittywilla.wittymediaclient.net.remote.NOTHING_PLAYING
import com.wittywilla.wittymediaclient.net.remote.RemoteCapabilities
import com.wittywilla.wittymediaclient.net.remote.RemoteCommand
import com.wittywilla.wittymediaclient.net.remote.RemoteQueue
import com.wittywilla.wittymediaclient.net.remote.RemoteState
import com.wittywilla.wittymediaclient.net.remote.VideoFacts
import com.wittywilla.wittymediaclient.net.remote.musicState
import com.wittywilla.wittymediaclient.net.remote.navigateKeyCode
import com.wittywilla.wittymediaclient.net.remote.trackIndex
import com.wittywilla.wittymediaclient.net.remote.videoState
import com.wittywilla.wittymediaclient.ui.Route
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

// What another device's commands do to this app's own players, and what this app says it is playing
// (docs/REMOTE-PROTOCOL.md, Commands and State). Video is the hub's VideoTarget; music, audiobooks and podcasts are
// the listening service. Whichever is playing is the one a command reaches: a film first, since a film stops the music.
internal class HubPlayers(private val hub: RemoteHub) : DevicePlayers {
    private val app get() = hub.app
    private val listening get() = app.listening

    // Where the device is in its own interface, in a word, for a remote that shows it.
    private fun screen(): String {
        val nav = hub.nav ?: return "home"
        return when (nav.current) {
            is Route.Player, Route.NowPlaying -> "player"
            Route.Home -> "home"
            Route.Search -> "search"
            Route.Profile -> "settings"
            else -> "browse"
        }
    }

    override fun remoteState(abilities: RemoteCapabilities): RemoteState {
        val video = hub.video
        val item = video?.item
        if (video != null && item != null && video.problem.isEmpty()) {
            val exo = video.exo
            val status = when {
                video.stream == null || exo.currentMediaItem == null -> "buffering"
                exo.playbackState == Player.STATE_BUFFERING && exo.playWhenReady -> "buffering"
                exo.isPlaying -> "playing"
                else -> "paused"
            }
            val stream = video.stream
            val hasVolume = Feature.VOLUME in abilities.features
            return videoState(
                VideoFacts(
                    itemId = video.itemId, status = status, positionSec = video.liveFilmSec, durationSec = video.durationSec,
                    rate = exo.playbackParameters.speed.toDouble(),
                    volume = if (hasVolume) (hub.mutedLevel ?: exo.volume).toDouble() else null,
                    muted = hub.mutedLevel != null,
                    audioIndex = stream?.audioIndex, subtitleIndex = stream?.subtitleIndex ?: -1,
                    audio = stream?.audio.orEmpty(), subtitles = stream?.subtitles.orEmpty(),
                    queue = hub.videoQueue, screen = screen(),
                ),
            )
        }
        val now = listening.now
        val id = now?.mediaId?.toLongOrNull()
        if (now != null && id != null && listening.problem.isEmpty()) {
            val order = listening.queue
            val hasVolume = Feature.VOLUME in abilities.features
            return musicState(
                MusicFacts(
                    itemId = id, playing = listening.isPlaying, loading = listening.isLoading,
                    positionSec = listening.positionSec(), durationSec = listening.durationSec(), rate = listening.speed.toDouble(),
                    volume = if (hasVolume) listening.sound.volume else null, muted = listening.sound.muted,
                    queue = order.mapNotNull { it.mediaId.toLongOrNull() }, queueIndex = order.indexOfFirst { it.index == listening.nowIndex },
                    screen = screen(),
                ),
            )
        }
        return RemoteState(screen = screen())
    }

    override suspend fun remoteDo(command: RemoteCommand, abilities: RemoteCapabilities): String? {
        if (hub.nav == null) return CANT_DO
        when (command.type) {
            "play" -> return play(command)
            "navigate" -> return press(command.key.orEmpty())
        }
        val video = hub.video
        return when {
            video != null -> video(command, video)
            listening.now != null -> music(command)
            // Nothing to stop is already stopped.
            command.type == "stop" -> null
            else -> NOTHING_PLAYING
        }
    }

    // MARK: play

    private suspend fun play(command: RemoteCommand): String? {
        val queue = RemoteQueue.from(command)
        val id = queue.current ?: return "That command didn't say what to play."
        val item = try {
            app.api.item(id)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return "That can't be opened on this device."
        }
        val nav = hub.nav ?: return CANT_DO
        if (item.kind == "audio") {
            val books = keepsPlace(nav.libraryType(item.libraryId))
            if (hub.video != null) hub.closeVideo()
            val start = command.positionSec ?: placeOn(item, books)
            nav.startListening(listOf(item), Start(0, start), books)
            // The one asked for starts at once; the rest of its queue follows as each is looked up.
            if (queue.items.size > 1) app.scope.launch { fillQueue(queue, item, books) }
            return null
        }
        if (item.kind != "video") return "This device can't play that kind of thing."
        hub.videoQueue = queue.takeIf { it.items.size > 1 }
        hub.openVideo(id, PlaybackPreset(command.positionSec, trackIndex(command.audio), trackIndex(command.subtitle)))
        return null
    }

    // The rest of a music queue, looked up a few at a time. If what's playing has changed meanwhile, the person has
    // moved on and the queue is left as they have it.
    private suspend fun fillQueue(queue: RemoteQueue, first: Item, books: Boolean) {
        val wanted = queue.items.filter { it != first.id && it > 0 }.distinct()
        val found = HashMap<Long, Item>()
        found[first.id] = first
        for (chunk in wanted.chunked(LOOKUPS_AT_ONCE)) {
            coroutineScope {
                chunk.map { id -> async { runCatching { app.api.item(id) }.getOrNull() } }.awaitAll()
            }.filterNotNull().forEach { found[it.id] = it }
        }
        if (listening.now?.mediaId != first.id.toString() || listening.queue.size != 1) return
        val items = queue.items.mapNotNull { found[it] }.filter { it.kind == "audio" }
        val at = items.indexOfFirst { it.id == first.id }
        if (items.size < 2 || at < 0) return
        val playing = listening.isPlaying
        listening.play(items, Start(at, listening.positionSec()), books)
        if (!playing) listening.pause()
    }

    // MARK: video

    private fun video(command: RemoteCommand, video: VideoTarget): String? {
        val exo = video.exo
        when (command.type) {
            "pause" -> if (exo.playWhenReady) video.togglePlay()
            "resume" -> if (!exo.playWhenReady) video.togglePlay()
            "stop" -> hub.closeVideo()
            "seek" -> {
                val at = command.positionSec ?: (video.liveFilmSec + (command.bySec ?: 0.0))
                if (video.stream?.seek == "none") return "This can't be moved to another place."
                video.seekFilm(at.coerceAtLeast(0.0))
            }
            "next", "previous" -> {
                val forward = command.type == "next"
                val queue = hub.videoQueue?.takeIf { it.current == video.itemId }
                val step = if (forward) queue?.next() else queue?.previous()
                when {
                    step != null -> {
                        hub.videoQueue = step
                        hub.openVideo(step.current ?: return CANT_DO, PlaybackPreset(startSec = 0.0))
                    }
                    forward && (video.stream?.nextId ?: video.item?.nextId) != null -> {
                        hub.videoQueue = null
                        hub.openVideo((video.stream?.nextId ?: video.item?.nextId)!!, null)
                    }
                    else -> return "There's nothing more that way."
                }
            }
            "volume" -> {
                val level = (command.level ?: return CANT_DO).toFloat()
                exo.volume = level
                if (level > 0) hub.mutedLevel = null
            }
            "mute" -> {
                if (command.muted == true && hub.mutedLevel == null) {
                    hub.mutedLevel = exo.volume
                    exo.volume = 0f
                } else if (command.muted == false) {
                    hub.mutedLevel?.let { exo.volume = it }
                    hub.mutedLevel = null
                }
            }
            "audio" -> {
                val index = trackIndex(command.audio)
                if (index == null || video.stream?.audio?.any { it.index == index } != true) return "That sound track isn't there."
                video.chooseAudio(index)
            }
            "subtitle" -> {
                val index = trackIndex(command.subtitle) ?: return "Those subtitles aren't there."
                if (index != -1 && video.stream?.subtitles?.any { it.index == index } != true) return "Those subtitles aren't there."
                video.chooseSubtitle(index)
            }
            "rate" -> video.askSpeed((command.rate ?: return CANT_DO).toFloat())
            else -> return CANT_DO
        }
        return null
    }

    // MARK: music, audiobooks and podcasts

    private fun music(command: RemoteCommand): String? {
        when (command.type) {
            "pause" -> listening.pause()
            "resume" -> if (!listening.isPlaying) listening.toggle()
            "stop" -> {
                hub.nav?.closeNowPlaying()
                listening.stop()
            }
            "seek" -> listening.seekTo((command.positionSec ?: (listening.positionSec() + (command.bySec ?: 0.0))).coerceAtLeast(0.0))
            "next" -> {
                if (!listening.canGoNext) return "There's nothing more that way."
                listening.next()
            }
            "previous" -> listening.previous()
            "volume" -> {
                val level = command.level ?: return CANT_DO
                listening.setSound { it.copy(volume = level, muted = if (level > 0) false else it.muted) }
            }
            "mute" -> listening.setSound { it.copy(muted = command.muted == true) }
            "rate" -> listening.chooseSpeed((command.rate ?: return CANT_DO).toFloat())
            "audio" -> return "This has only the one sound track."
            "subtitle" -> return "This has no subtitles."
            else -> return CANT_DO
        }
        return null
    }

    // MARK: the remote's keys

    // The keys of a TV remote, pressed from another device. Back, Home and Play/Pause do what the remote's own do in
    // this app; the arrows, Select and Menu go to whatever has the focus, as if pressed on the remote in the hand.
    private fun press(key: String): String? {
        val nav = hub.nav ?: return CANT_DO
        val activity = hub.currentActivity as? ComponentActivity ?: return "This device isn't showing the app."
        when (key) {
            "back" -> activity.onBackPressedDispatcher.onBackPressed()
            "home" -> {
                if (nav.current == Route.Home && nav.stack.size == 1) return "It's already at the top of Home."
                nav.reset(Route.Home)
            }
            "playpause" -> {
                val video = hub.video
                when {
                    video != null -> video.togglePlay()
                    listening.now != null -> listening.toggle()
                    else -> return NOTHING_PLAYING
                }
            }
            else -> {
                val code = navigateKeyCode(key) ?: return "This device doesn't have that key."
                val now = SystemClock.uptimeMillis()
                for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
                    activity.window.decorView.dispatchKeyEvent(KeyEvent(now, now, action, code, 0, 0, KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, InputDevice.SOURCE_DPAD))
                }
            }
        }
        return null
    }

    private companion object {
        const val LOOKUPS_AT_ONCE = 8
    }
}
