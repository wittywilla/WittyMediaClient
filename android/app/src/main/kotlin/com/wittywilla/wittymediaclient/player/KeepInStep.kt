// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.os.Handler
import android.os.Looper
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import kotlin.math.abs

// A change of speed can leave the sound and the picture apart for good: a decoder that fell behind at
// 4× doesn't catch up by itself when the speed comes down again, and the time stretch keeps its own
// buffer (the owner's "4× then back to normal, and they're out of step"). A seek to where it is lines
// them up: the decoders and the stretch start afresh at the same place. Done once the speed has stayed
// put for a moment, so stepping through the menu seeks once, and only for a real change. The same as
// the website (web/src/player/speed.ts, keepInStep) and the Apple app.
const val REALIGN_AFTER_MS = 400L
const val REALIGN_MIN_CHANGE = 0.5f

// A change of speed from one rate to another big enough to line up after.
fun realignNeeded(from: Float, to: Float): Boolean = from > 0f && to > 0f && abs(to - from) >= REALIGN_MIN_CHANGE

class KeepInStep(private val player: Player) : Player.Listener {
    private val handler = Handler(Looper.getMainLooper())
    private var settled = player.playbackParameters.speed
    private val realign = Runnable {
        val now = player.playbackParameters.speed
        if (!realignNeeded(settled, now)) return@Runnable
        settled = now
        if (player.isPlaying && player.playbackState == Player.STATE_READY) player.seekTo(player.currentPosition)
    }

    override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
        handler.removeCallbacks(realign)
        handler.postDelayed(realign, REALIGN_AFTER_MS)
    }

    fun release() {
        handler.removeCallbacks(realign)
        player.removeListener(this)
    }
}
