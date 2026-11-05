package com.wittywilla.wittymediaclient.ui

import androidx.compose.runtime.Composable
import com.wittywilla.wittymediaclient.tv.ChannelScreen
import com.wittywilla.wittymediaclient.tv.GuideScreen
import com.wittywilla.wittymediaclient.tv.RecordingsScreen

// WittyTV on Android TV, in the app's own screen stack: the guide on the whole screen, a channel playing, and Recordings
// (the code is in the tv package, ported from Apple TV's). The Live TV tab shows the same guide under the bar.

data class TvRoute(val screen: TvScreen) : Route {
    override val key = "wittytv-" + screen.key
}

sealed interface TvScreen {
    val key: String

    data object Guide : TvScreen {
        override val key = "guide"
    }

    data class Channel(val start: String) : TvScreen {
        override val key = "channel-$start"
    }

    data object Recordings : TvScreen {
        override val key = "recordings"
    }
}

@Composable
fun TvRouteScreen(nav: Nav, route: TvRoute) {
    when (val screen = route.screen) {
        TvScreen.Guide -> GuideScreen(nav, inTab = false)
        is TvScreen.Channel -> ChannelScreen(nav, screen.start)
        TvScreen.Recordings -> RecordingsScreen(nav)
    }
}

// Past signing in: the screens a reminder can come up over.
val Route.signedIn: Boolean
    get() = this !is Route.Connect && this !is Route.Code && this !is Route.Mismatch && this !is Route.SignIn && this !is Route.Help && this != Route.Starting
