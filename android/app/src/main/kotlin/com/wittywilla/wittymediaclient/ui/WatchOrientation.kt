// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.hardware.SensorManager
import android.view.OrientationEventListener
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext

// A phone turns to landscape for a video in the big player, as video apps do, and back to portrait when the video
// ends or the player closes (WittyMediaClient#160, the owner: "default to landscape when watching videos in the
// bigger player, and revert back to portrait once the video is done"). The player's Rotate button asks for portrait
// for that video instead. Never on a tablet or a TV, never for a video taller than it is wide, and never for sound
// alone or the mini player: their callers don't ask.
//
// Landscape is SENSOR_LANDSCAPE: either side, by how the phone is held, even with the system's rotation lock on.
// Back to portrait is PORTRAIT until the phone is held upright, then whatever the app had before (usually following
// the phone), so a phone still on its side doesn't flip straight back to landscape.

// Whether this device is a phone: the screen's narrow side under 600 dp, and not a TV.
@Composable
fun isPhoneForVideo(isTv: Boolean): Boolean = !isTv && LocalConfiguration.current.smallestScreenWidthDp < 600

// While `on`, the activity is in landscape (or portrait if `portrait` is chosen). Leaving `on` (or the composition)
// brings it back to portrait. A change of orientation doesn't restart anything: the activity handles its own
// configuration changes (AndroidManifest.xml), so the player and its video carry on.
@Composable
fun WatchOrientation(on: Boolean, portrait: Boolean) {
    val activity = LocalContext.current.findActivity() ?: return
    // Entering and leaving: what the app had is kept, and given back (by way of portrait) on the way out.
    DisposableEffect(activity, on) {
        if (!on) return@DisposableEffect onDispose { }
        val pending = WatchOrientationState.release
        val before = if (pending != null) {
            // Still on the way back from the last video: that one's "before" is the real one.
            pending.disable()
            WatchOrientationState.release = null
            WatchOrientationState.pendingBefore
        } else activity.requestedOrientation
        onDispose { backToPortrait(activity, before) }
    }
    // Landscape, or portrait when chosen, while on: changing it doesn't leave the player.
    SideEffect {
        if (on) {
            val want = if (portrait) ActivityInfo.SCREEN_ORIENTATION_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            if (activity.requestedOrientation != want) activity.requestedOrientation = want
        }
    }
}

private object WatchOrientationState {
    var release: OrientationEventListener? = null
    var pendingBefore: Int = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
}

private fun backToPortrait(activity: Activity, before: Int) {
    if (activity.requestedOrientation == before) return
    activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    if (before == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) return
    // Then, once the phone is held upright, back to what the app had (following the phone, as a rule).
    val listener = object : OrientationEventListener(activity, SensorManager.SENSOR_DELAY_NORMAL) {
        override fun onOrientationChanged(degrees: Int) {
            if (degrees == ORIENTATION_UNKNOWN) return
            if (degrees <= 30 || degrees >= 330) {
                disable()
                if (WatchOrientationState.release === this) WatchOrientationState.release = null
                if (activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) activity.requestedOrientation = before
            }
        }
    }
    if (listener.canDetectOrientation()) {
        WatchOrientationState.release = listener
        WatchOrientationState.pendingBefore = before
        listener.enable()
    } else {
        activity.requestedOrientation = before
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
