package com.wittywilla.wittymediaclient

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.wittywilla.wittymediaclient.ui.AppRoot

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 and later draw this way whatever an app says. The screens leave room for the bars.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent { AppRoot(application as WittyApp) }
    }
}
