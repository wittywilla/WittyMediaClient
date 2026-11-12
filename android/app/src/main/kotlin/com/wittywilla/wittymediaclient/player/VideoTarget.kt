// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Playback

// The app's video player, as another device (the Remote Protocol) and a watch party see it. A phone's is the
// VideoSession kept while the app runs; a TV's belongs to its player screen. Each tells the hub when it opens and
// closes (RemoteHub.adopt, released), and asks its `steering` before it plays, pauses, seeks or moves on, which is all
// either player knows of any of this.
interface VideoTarget {
    val itemId: Long
    val exo: ExoPlayer
    val item: Item?
    val stream: Playback?
    val durationSec: Double
    val problem: String
    val ended: Boolean
    var steering: VideoSteering?

    // Where the picture is in the film now, read from the player rather than the last tick.
    val liveFilmSec: Double
        get() {
            val at = exo.currentPosition / 1000.0
            return (at + (stream?.timeOffsetSec ?: 0.0)).coerceAtLeast(0.0)
        }

    // How much of the stream the player knows of, in its own time; null when it doesn't say.
    val knownPlayerSec: Double?
        get() = exo.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.div(1000.0)

    // As the viewer's own press: through the steering first.
    fun togglePlay()
    fun seekFilm(targetSec: Double)
    fun askSpeed(rate: Float)

    // A place the player can only reach with a new stream from there, asked for by the steering itself.
    fun reopenAt(filmSec: Double)
    fun chooseAudio(index: Int)
    fun chooseSubtitle(index: Int)
    // Shows the speed the room plays at, without asking the steering: the room decided it.
    fun showSpeed(rate: Float) {}
}

// Something that steers a video player in the viewer's place: a watch party, whose room decides when everyone's
// picture moves. Each answers true when it has taken the press, and the player then does nothing itself.
interface VideoSteering {
    fun toggle(): Boolean
    fun seek(filmSec: Double): Boolean
    fun speed(rate: Float): Boolean
    // The item reached its end: a party moves everyone on together, and the player doesn't count down by itself.
    fun ended(): Boolean
}

// Where a video opened by another device or a party starts, and with which tracks.
data class PlaybackPreset(val startSec: Double? = null, val audio: Int? = null, val subtitle: Int? = null)
