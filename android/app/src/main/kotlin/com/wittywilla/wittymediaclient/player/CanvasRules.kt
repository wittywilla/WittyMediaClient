// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.Address
import com.wittywilla.wittymediaclient.net.CanvasInfo
import java.net.URI

// A canvas is a short silent video that loops behind a song's or a title's artwork (the server's docs/MUSIC.md,
// "Canvas"). It is decoration: it costs a video decoder, a download and battery, so the still artwork stays whenever
// any of those is short. The decision is here, apart from the screen, so it can be tested.

// What the device and the person say, read when a screen with a canvas comes up.
data class CanvasConditions(
    // The server names the `canvas` feature.
    val serverHas: Boolean,
    // The person's own switch, in You, Playing on this device.
    val wanted: Boolean = true,
    val batterySaver: Boolean = false,
    val dataSaver: Boolean = false,
    val metered: Boolean = false,
    // Away from home, where the server's own limit on what's sent applies (and slows a canvas down with it).
    val awayFromHome: Boolean = false,
    // The system's animations are turned off (the app's reduceMotion).
    val reduceMotion: Boolean = false,
    val lowRam: Boolean = false,
    // A film is playing, full screen or in the mini player: one video decoder at a time.
    val filmPlaying: Boolean = false,
)

enum class CanvasBlock { OldServer, TurnedOff, BatterySaver, DataSaver, Metered, AwayFromHome, ReduceMotion, LowRam, FilmPlaying }

object CanvasRules {
    // Why the canvas stays off, or null when it may play. The person's own choice comes first, then what never
    // changes about the device, then what changes from hour to hour.
    fun blocked(c: CanvasConditions): CanvasBlock? = when {
        !c.serverHas -> CanvasBlock.OldServer
        !c.wanted -> CanvasBlock.TurnedOff
        c.reduceMotion -> CanvasBlock.ReduceMotion
        c.lowRam -> CanvasBlock.LowRam
        c.batterySaver -> CanvasBlock.BatterySaver
        c.dataSaver -> CanvasBlock.DataSaver
        c.metered -> CanvasBlock.Metered
        c.awayFromHome -> CanvasBlock.AwayFromHome
        c.filmPlaying -> CanvasBlock.FilmPlaying
        else -> null
    }

    // The most a canvas may be here: the server's own limit for one beside the media.
    const val MAX_BYTES = 64L * 1024 * 1024

    // Is what the server found something this app can loop? MP4 and WebM, as the server serves them.
    fun playable(info: CanvasInfo): Boolean =
        info.available && info.url.startsWith("/") && !info.url.startsWith("//") && (info.mime == "video/mp4" || info.mime == "video/webm" || info.mime.isEmpty())

    // Is the server this app is connected to on the home network? By its address: a private address, a name with no
    // dots or one ending in .local. Anything else may be the internet, where the server limits what it sends.
    fun awayFromHome(base: String): Boolean {
        val host = runCatching { URI(base).host }.getOrNull()?.lowercase() ?: return true
        return !Address.isPrivateHost(if (host.contains(':') && !host.startsWith("[")) "[$host]" else host)
    }

    // How a video is stretched to fill a view while keeping its shape (centre-crop): the scale along x and along y to
    // give a TextureView, which otherwise stretches the picture to its own shape. 1 and 1 when either size is unknown.
    fun coverScale(viewW: Int, viewH: Int, videoW: Int, videoH: Int): Pair<Float, Float> {
        if (viewW <= 0 || viewH <= 0 || videoW <= 0 || videoH <= 0) return 1f to 1f
        val scale = maxOf(viewW.toFloat() / videoW, viewH.toFloat() / videoH)
        return (videoW * scale / viewW) to (videoH * scale / viewH)
    }

    // The name a canvas is kept under on this device: the item and the version in its address, so a new file on the
    // server is a new file here, and nothing from an address can name a path.
    fun fileName(id: Long, url: String): String {
        val version = url.substringAfter("v=", "").substringBefore('&').filter { it.isLetterOrDigit() || it == '-' }.take(40)
        return "canvas-$id-${version.ifEmpty { "0" }}"
    }
}
