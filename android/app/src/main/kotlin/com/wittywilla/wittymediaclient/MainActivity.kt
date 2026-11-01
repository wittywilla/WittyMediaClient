package com.wittywilla.wittymediaclient

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.wittywilla.wittymediaclient.player.OPEN_NOW_PLAYING
import com.wittywilla.wittymediaclient.ui.AppRoot
import com.wittywilla.wittymediaclient.ui.showSystemBars

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 and later draw this way whatever an app says. The screens leave room for the bars,
        // and AppRoot sets them to the server's theme once that's known. Dark until then, as the first screen is.
        showSystemBars(this, light = false, background = getColor(R.color.background))
        super.onCreate(savedInstanceState)
        noticeTap(intent)
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
}
