// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import androidx.media3.common.C
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import com.wittywilla.wittymediaclient.net.TrackInfo
import com.wittywilla.wittymediaclient.net.TrackLabels

// The choices the live player offers: audio, subtitles and picture quality, as the Dock lists them, and the choosing.
class TrackChoice(val label: String, val selected: Boolean, val choose: () -> Unit)

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object LiveTvTracks {
    private fun choices(type: Int): List<Pair<Tracks.Group, Int>> =
        LiveTv.player()?.currentTracks?.groups.orEmpty().filter { it.type == type }.flatMap { g -> (0 until g.length).filter { g.isTrackSupported(it) }.map { g to it } }

    private fun info(g: Tracks.Group, i: Int): TrackInfo {
        val f = g.getTrackFormat(i)
        return TrackInfo(f.language, f.label, f.channelCount.takeIf { it > 0 } ?: 0, f.height.takeIf { it > 0 } ?: 0, f.bitrate.takeIf { it > 0 } ?: 0)
    }

    fun audio(): List<TrackChoice> {
        val p = LiveTv.player() ?: return emptyList()
        return choices(C.TRACK_TYPE_AUDIO).mapIndexed { n, (g, i) ->
            TrackChoice(TrackLabels.audio(info(g, i), n + 1), g.isTrackSelected(i)) {
                p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, i)).build()
            }
        }
    }

    // Off first, then each language; the one showing is marked.
    fun subtitles(): List<TrackChoice> {
        val p = LiveTv.player() ?: return emptyList()
        val tracks = choices(C.TRACK_TYPE_TEXT)
        if (tracks.isEmpty()) return emptyList()
        val off = p.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT) || tracks.none { (g, i) -> g.isTrackSelected(i) }
        return listOf(
            TrackChoice("Off", off) {
                p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
            },
        ) + tracks.mapIndexed { n, (g, i) ->
            TrackChoice(TrackLabels.subtitle(info(g, i), n + 1), !off && g.isTrackSelected(i)) {
                p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                    .setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, i)).build()
            }
        }
    }

    // Automatic, then each picture the stream has, tallest first.
    fun quality(): List<TrackChoice> {
        val p = LiveTv.player() ?: return emptyList()
        val pictures = choices(C.TRACK_TYPE_VIDEO)
        if (pictures.size < 2) return emptyList()
        val heights = pictures.map { (g, i) -> info(g, i).height }
        val overridden = p.trackSelectionParameters.overrides.keys.any { it.type == C.TRACK_TYPE_VIDEO }
        return listOf(
            TrackChoice("Automatic", !overridden) {
                p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().clearOverridesOfType(C.TRACK_TYPE_VIDEO).build()
            },
        ) + pictures.sortedByDescending { (g, i) -> info(g, i).height }.map { (g, i) ->
            val t = info(g, i)
            TrackChoice(TrackLabels.quality(t, heights.count { it == t.height } > 1), overridden && g.isTrackSelected(i)) {
                p.trackSelectionParameters = p.trackSelectionParameters.buildUpon().setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, i)).build()
            }
        }
    }
}
