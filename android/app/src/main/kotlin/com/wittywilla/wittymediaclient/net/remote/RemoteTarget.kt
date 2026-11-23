// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.remote

import android.view.KeyEvent
import com.wittywilla.wittymediaclient.net.Track
import kotlinx.serialization.json.JsonObject

// The rest of the Remote Protocol's decisions that need no screen: what this app reports while it plays, which key a
// `navigate` presses, and how a controller hands what plays here over to another device.

// What the video player says of itself, for a state report.
data class VideoFacts(
    val itemId: Long,
    // "playing", "paused" or "buffering".
    val status: String,
    val positionSec: Double,
    val durationSec: Double,
    val rate: Double,
    // Null when the device has no volume of its own (a TV's sound is the television's).
    val volume: Double?,
    val muted: Boolean,
    val audioIndex: Int?,
    val subtitleIndex: Int,
    val audio: List<Track> = emptyList(),
    val subtitles: List<Track> = emptyList(),
    val queue: RemoteQueue? = null,
    val screen: String? = null,
)

// The tracks as a controller lists them: the playback answer's index as the id, and a name a person reads.
// The language as the players name it (player/TrackWords.kt); a track with no language and no name is "Track 2".
fun remoteTracks(tracks: List<Track>): List<RemoteTrack> = tracks.distinctBy { it.index }.take(RemoteState.MAX_TRACKS).mapIndexed { i, t ->
    val language = com.wittywilla.wittymediaclient.player.TrackWords.language(t).ifEmpty { if (t.title.isBlank()) "Track ${i + 1}" else "" }
    val channels = com.wittywilla.wittymediaclient.player.TrackWords.channels(t.channels)
    RemoteTrack(trackId(t.index), listOf(language, t.title, channels).filter { it.isNotEmpty() }.distinct().joinToString(" · "), t.language)
}

fun videoState(f: VideoFacts): RemoteState {
    // A speed is shown to two places; anything that isn't one is normal.
    val rate = if (f.rate.isFinite() && f.rate > 0) Math.round(f.rate * 100) / 100.0 else 1.0
    val queue = f.queue?.takeIf { it.items.size > 1 && it.current == f.itemId }
    return RemoteState(
        status = f.status,
        itemId = f.itemId,
        positionSec = f.positionSec.coerceAtLeast(0.0),
        durationSec = f.durationSec.coerceAtLeast(0.0),
        rate = rate,
        volume = f.volume?.coerceIn(0.0, 1.0),
        muted = f.muted,
        audio = f.audioIndex?.takeIf { f.audio.isNotEmpty() }?.let { trackId(it) },
        subtitle = trackId(f.subtitleIndex),
        audioTracks = remoteTracks(f.audio),
        subtitleTracks = remoteTracks(f.subtitles),
        queue = queue?.items.orEmpty(),
        queueIndex = queue?.index ?: 0,
        screen = f.screen,
    )
}

// What the listening service says of itself.
data class MusicFacts(
    val itemId: Long,
    val playing: Boolean,
    val loading: Boolean,
    val positionSec: Double,
    val durationSec: Double,
    val rate: Double,
    val volume: Double?,
    val muted: Boolean,
    val queue: List<Long>,
    val queueIndex: Int,
    val screen: String? = null,
)

fun musicState(f: MusicFacts): RemoteState {
    val queue = f.queue.take(RemoteState.MAX_QUEUE)
    val fits = queue.size > 1 && f.queueIndex in queue.indices && queue[f.queueIndex] == f.itemId
    return RemoteState(
        status = if (f.loading) "buffering" else if (f.playing) "playing" else "paused",
        itemId = f.itemId,
        positionSec = f.positionSec.coerceAtLeast(0.0),
        durationSec = f.durationSec.coerceAtLeast(0.0),
        rate = if (f.rate.isFinite() && f.rate > 0) Math.round(f.rate * 100) / 100.0 else 1.0,
        volume = f.volume?.coerceIn(0.0, 1.0),
        muted = f.muted,
        queue = if (fits) queue else emptyList(),
        queueIndex = if (fits) f.queueIndex else 0,
        screen = f.screen,
    )
}

// The key a `navigate` presses on this device, as the remote's own would. Back, Home and Play/Pause are done by the
// app itself (they mean leaving a screen, going home and the player), so they have no key here.
fun navigateKeyCode(key: String): Int? = when (key) {
    "up" -> KeyEvent.KEYCODE_DPAD_UP
    "down" -> KeyEvent.KEYCODE_DPAD_DOWN
    "left" -> KeyEvent.KEYCODE_DPAD_LEFT
    "right" -> KeyEvent.KEYCODE_DPAD_RIGHT
    "select" -> KeyEvent.KEYCODE_DPAD_CENTER
    "menu" -> KeyEvent.KEYCODE_MENU
    else -> null
}

// What this device is announced as: the protocol's own rules, with the arrows and Select only on a TV, where the app
// is steered by a remote's keys. A phone's screen is touched, and its keys would land nowhere useful.
fun announcedCapabilities(tv: Boolean): RemoteCapabilities {
    val all = deviceCapabilities(volumeFixed = tv)
    return if (tv) all else all.copy(features = all.features - Feature.NAVIGATE)
}

// Something to play on another device: what plays here now (handed over at its place), or a title chosen on its page.
data class PlayOnSource(
    val itemId: Long,
    val title: String,
    val kind: String,
    val queue: List<Long> = listOf(itemId),
    val queueIndex: Int = 0,
    // Where it has got to, for what plays here; null starts from the account's own resume point.
    val positionSec: Double? = null,
    val audio: String? = null,
    val subtitle: String? = null,
    // It is playing on this device now, and stops here once the other has it.
    val playingHere: Boolean = false,
) {
    val queued: Int get() = queue.size
}

// The command that hands it over. A device that is announced and online hands over its own playback with `cast`,
// so the server works out the place and stops this one; otherwise it's an ordinary `play` at the place.
fun handOverCommand(source: PlayOnSource, myDeviceId: String, target: RemoteDevice): JsonObject {
    if (source.playingHere && myDeviceId.isNotEmpty()) return RemoteWire.cast(myDeviceId)
    val queue = source.queue.filter { it > 0 }.take(RemoteState.MAX_QUEUE)
    val index = queue.indexOf(source.itemId)
    return if (queue.size > 1 && index >= 0 && Feature.QUEUE in target.capabilities.features) {
        RemoteWire.playQueue(queue, index, source.positionSec)
    } else {
        RemoteWire.play(source.itemId, source.positionSec, source.audio, source.subtitle)
    }
}

// Whether this device must stop by itself once the other has taken over: a `cast` whose answer says the server
// stopped it needs nothing more (the `stop` arrives as a command).
fun stopsHereAfter(source: PlayOnSource, sentCast: Boolean, answer: CommandAnswer): Boolean =
    source.playingHere && !(sentCast && answer.sourceStopped == true)

// A device's line in a list: what it is doing, as far as this account may see.
fun deviceLine(device: RemoteDevice): String {
    val state = device.state
    return when {
        !device.online -> "Not connected"
        device.hidden && state.status != "idle" -> "Playing something you can't see"
        state.isIdle -> "Nothing playing"
        else -> {
            val what = device.title.ifEmpty { "something" }
            when (state.status) {
                "playing" -> "Playing $what"
                "paused" -> "Paused: $what"
                "buffering" -> "Loading $what"
                else -> what
            }
        }
    } + if (!device.mine && device.userName.isNotEmpty()) " · ${device.userName}" else ""
}
