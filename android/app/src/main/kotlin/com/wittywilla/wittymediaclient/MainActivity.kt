package com.wittywilla.wittymediaclient

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
        setContent { AppRoot(application as WittyApp) }
    }

    // Before any screen, a web view included: it would keep this for a page that has no use for it.
    // Lint reads this as the library's own override. It's the system's, on Activity, which any app may have.
    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
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
}
