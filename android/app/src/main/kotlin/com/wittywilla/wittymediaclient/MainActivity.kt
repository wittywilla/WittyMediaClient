// SPDX-License-Identifier: GPL-3.0-or-later
//
// WittyMediaClient - Apps that connect to a WittyMediaServer, for TV boxes, phones, tablets and desktops.
// Copyright (C) 2026 WittyWilla and contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

package com.wittywilla.wittymediaclient

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.annotation.SuppressLint
import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import com.wittywilla.wittymediaclient.games.GameInputHub
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.wittywilla.wittymediaclient.player.OPEN_NOW_PLAYING
import com.wittywilla.wittymediaclient.net.NINTENDO_VENDOR
import com.wittywilla.wittymediaclient.net.nintendoKey
import com.wittywilla.wittymediaclient.ui.AppRoot
import com.wittywilla.wittymediaclient.ui.showSystemBars

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 and later draw this way whatever an app says. The screens leave room for the bars,
        // and AppRoot sets them to the server's theme once that's known. Dark until then, as the first screen is.
        showSystemBars(this, light = false, background = getColor(R.color.background))
        super.onCreate(savedInstanceState)
        noticeTap(intent)
        // For checking Home's hero with a title of one's choosing, in a debug build only:
        // `adb shell am start -n com.wittywilla.wittymediaclient/.MainActivity --el WittyHomeHero <item id>`.
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            (application as WittyApp).pinnedHero = intent.getLongExtra("WittyHomeHero", 0)
        }
        setContent { AppRoot(application as WittyApp) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        noticeTap(intent)
    }

    // Tapping the notification or a TV's card. It can only ask for the player's own screen.
    private fun noticeTap(intent: Intent?) {
        if (intent?.action == OPEN_NOW_PLAYING) (application as WittyApp).listening.wantsScreen = true
    }

    // Before any screen, a web view included: it would keep this for a page that has no use for it.
    // Lint reads this as the library's own override. It's the system's, on Activity, which any app may have.
    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // A game on screen reads controllers first: see games/GameInput.kt.
        if (GameInputHub.key(event)) return true
        if (event.action == KeyEvent.ACTION_DOWN) {
            (application as WittyApp).lastPad = if (event.device?.supportsSource(InputDevice.SOURCE_GAMEPAD) == true) event.deviceId else -1
        }
        if (event.keyCode == KeyEvent.KEYCODE_GUIDE) {
            if (event.action == KeyEvent.ACTION_DOWN) (application as WittyApp).onGuideKey?.invoke()
            return true
        }
        if (!(application as WittyApp).showingPage && event.device?.vendorId == NINTENDO_VENDOR) {
            nintendoKey(event.keyCode)?.let { meaning ->
                val said = KeyEvent(event.downTime, event.eventTime, event.action, meaning, event.repeatCount, event.metaState, event.deviceId, event.scanCode, event.flags, event.source)
                super.dispatchKeyEvent(said)
                return true // or Android would go on to act on the button's own name as well
            }
        }
        return super.dispatchKeyEvent(event)
    }

    // A controller's sticks, triggers and hat, while a game is on screen.
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean = GameInputHub.motion(event) || super.dispatchGenericMotionEvent(event)
}
