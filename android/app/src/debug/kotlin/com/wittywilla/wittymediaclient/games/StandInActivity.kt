package com.wittywilla.wittymediaclient.games

import android.net.Uri
import android.os.Bundle
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.CompositionLocalProvider
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.ui.LocalMetrics
import com.wittywilla.wittymediaclient.ui.PhoneMetrics
import com.wittywilla.wittymediaclient.ui.TvMetrics

// Debug builds only: plays the one game a WittyPlay stream version 2 stand-in on this machine serves (the stream
// session's wittyplay-probe), straight through the player, since a stand-in has none of the server's game routes. Only
// this machine's loopback is accepted: 10.0.2.2 from an emulator, or the device's own 127.0.0.1.
//
//   adb shell am start -n com.wittywilla.wittymediaclient/.games.StandInActivity --es url http://10.0.2.2:9821/stream --es console nes
class StandInActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as WittyApp
        // The controls come from the server this app is signed in to, as for any game.
        if (app.api.base.isEmpty() && app.store.server.isNotEmpty()) app.api = Api(app.store.server, app.store.token)
        val url = intent.getStringExtra("url") ?: "http://10.0.2.2:9821/stream"
        val host = Uri.parse(url).host.orEmpty()
        if (host != "10.0.2.2" && host != "127.0.0.1") {
            finish()
            return
        }
        val console = intent.getStringExtra("console") ?: "nes"
        // The stand-in's WebRTC candidates say 127.0.0.1, which an emulator reaches as 10.0.2.2.
        val endpoint = StreamEndpoint(url, if (host == "10.0.2.2") { sdp -> rewriteLoopback(sdp, host) } else null)
        val direct = DirectStream(endpoint, console, "Stand-in")
        setContent {
            CompositionLocalProvider(LocalMetrics provides if (app.isTv) TvMetrics else PhoneMetrics) {
                MaterialTheme(colorScheme = darkColorScheme()) {
                    GamePlayerScreen(app, 0, GameStart(resume = false), direct) { finish() }
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean = GameInputHub.key(event) || super.dispatchKeyEvent(event)

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean = GameInputHub.motion(event) || super.dispatchGenericMotionEvent(event)
}
