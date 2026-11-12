// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.wittywilla.wittymediaclient.net.ExtrasFeature
import com.wittywilla.wittymediaclient.player.ExtrasPrefs
import com.wittywilla.wittymediaclient.player.SkipKind

// You, Playing on this device: which parts of a video skip themselves, and whether artwork may move. One of You's own
// screens, in its grouped rows with a switch each; a row is what's pressed, so a remote reaches it as one thing.
@Composable
internal fun PlayingHereScreen(nav: Nav, s: Map<String, String>) {
    val context = LocalContext.current
    var choices by remember { mutableStateOf(ExtrasPrefs.load(context)) }
    fun keep(next: com.wittywilla.wittymediaclient.player.ExtrasChoices) {
        choices = next
        ExtrasPrefs.save(context, next)
    }
    val on = s["on"].orEmpty()
    val off = s["off"].orEmpty()
    // Recaps, adverts and credits are only marked by a server that names skip-markers; an older one knows intros alone.
    val kinds = if (nav.has(ExtrasFeature.MARKERS)) listOf(SkipKind.Intro, SkipKind.Recap, SkipKind.Credits, SkipKind.Commercial) else listOf(SkipKind.Intro)
    val names = mapOf(SkipKind.Intro to "skipIntros", SkipKind.Recap to "skipRecaps", SkipKind.Credits to "skipCredits", SkipKind.Commercial to "skipAdverts")
    SettingsPage(nav, s["rowPlayingHere"].orEmpty(), s["playingHereHint"].orEmpty()) {
        GroupedList(
            s["skipAutoCaption"].orEmpty(),
            kinds.mapIndexed { index, kind ->
                val chosen = choices.auto.wants(kind)
                GroupRow(
                    s[names.getValue(kind)].orEmpty(), onClick = { keep(choices.withAuto(choices.auto.with(kind, !chosen))) },
                    icon = Symbols.Playback, tint = Color(0xFF3E5BD0), value = if (chosen) on else off,
                    chevron = false, selected = chosen, focusKey = "skip-${kind.key}", requestFocus = index == 0,
                    trailing = { Toggle(chosen) },
                )
            },
        )
        Hint(s["skipAutoHint"].orEmpty() + if (SkipKind.Credits in kinds) " " + s["skipCreditsHint"].orEmpty() else "")
        if (nav.has(ExtrasFeature.CANVAS)) {
            GroupedList(
                s["canvasCaption"].orEmpty(),
                listOf(
                    GroupRow(
                        s["canvasRow"].orEmpty(), onClick = { keep(choices.copy(canvas = !choices.canvas)) },
                        icon = Symbols.Palette, tint = Color(0xFF0E7C6F), value = if (choices.canvas) on else off,
                        chevron = false, selected = choices.canvas, focusKey = "canvas", trailing = { Toggle(choices.canvas) },
                    ),
                ),
            )
            Hint(s["canvasHint"].orEmpty())
        }
        // Being a device the account's other devices play on and steer (player/RemoteHub.kt), where the server has it.
        val hub = nav.app.remote
        if (hub.remoteOn) {
            GroupedList(
                s["remoteCaption"].orEmpty(),
                listOf(
                    GroupRow(
                        s["letOthersControl"].orEmpty(), onClick = { hub.chooseLetOthers(!hub.letOthers) },
                        icon = Symbols.Devices, tint = Color(0xFF3E5BD0), value = if (hub.letOthers) on else off,
                        chevron = false, selected = hub.letOthers, focusKey = "let-others", trailing = { Toggle(hub.letOthers) },
                    ),
                ),
            )
            Hint(s["letOthersHint"].orEmpty())
        }
    }
}
