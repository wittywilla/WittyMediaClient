// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.min

// The card for something a TV doesn't change itself (the server's TV levels, docs/TV-MODE.md): the same centred
// column as the sign-in screens ("Who's watching?"), scaled for across the room. The server's lockup small at the
// top under the soft glow, the setting's symbol and name as the heading, one short line, the QR code as the
// centrepiece on a white tile with "or open" and the address under it, what is set now in a card, Back focused, and
// a quiet line at the foot. No keys of a keyboard are drawn; Back on the remote leaves, as the button does.
// Every desktop-only page on a TV shows this (OnPhoneScreen), and Apple TV draws the same (EditorOnComputerPage).
@Composable
fun OnAComputerCard(
    title: String,
    line: String,
    address: String,
    summary: List<String>,
    onBack: () -> Unit,
    backLabel: String,
    orOpen: String,
    footer: String,
    icon: ImageVector? = null,
    lockup: (@Composable () -> Unit)? = null,
) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val density = LocalDensity.current
    fun sp(units: Int) = with(density) { metrics.u(units).toSp() }
    BackHandler { onBack() }
    Box(Modifier.fillMaxSize().background(scheme.background).signInGlow(scheme.primary).testTag("design.on-a-computer")) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding()) {
            // The code is as large as the screen allows with the rest still showing: a 720p TV has the same room in
            // TV units as a 1080p one, a phone's window less.
            val qr: Dp = min(metrics.u(360), maxHeight * 0.34f)
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = metrics.gutter, vertical = metrics.u(48)),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(metrics.u(22), Alignment.CenterVertically),
            ) {
                lockup?.invoke()
                Row(
                    Modifier.widthIn(max = metrics.u(1400)).semantics(mergeDescendants = true) { heading() },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(metrics.u(20), Alignment.CenterHorizontally),
                ) {
                    if (icon != null) Icon(icon, contentDescription = null, tint = LocalExtraColours.current.accentText, modifier = Modifier.size(metrics.u(64)))
                    Text(
                        title, color = scheme.onBackground, fontSize = sp(64), fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center,
                        lineHeight = sp(72), maxLines = 2,
                    )
                }
                if (line.isNotEmpty()) {
                    Text(line, color = scheme.onSurfaceVariant, fontSize = sp(32), textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = metrics.u(1300)))
                }
                if (address.isNotEmpty()) {
                    Box(Modifier.padding(top = metrics.u(6)).clip(metrics.corner(24)).background(Color.White).padding(metrics.u(28))) {
                        QrCode(address, qr, Modifier.semantics { contentDescription = "$orOpen $address" })
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(4))) {
                        Text(orOpen, color = scheme.onSurfaceVariant, fontSize = sp(26), textAlign = TextAlign.Center)
                        Text(
                            address, color = LocalExtraColours.current.accentText, fontSize = sp(34), fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = metrics.u(1400)),
                        )
                    }
                }
                if (summary.isNotEmpty()) {
                    Column(
                        Modifier.widthIn(max = metrics.u(1000)).clip(metrics.corner(20)).background(scheme.surface)
                            .padding(horizontal = metrics.u(40), vertical = metrics.u(20)).semantics(mergeDescendants = true) {},
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(metrics.u(4)),
                    ) {
                        summary.forEachIndexed { i, s ->
                            Text(
                                s, color = if (i == 0) scheme.onSurface else scheme.onSurfaceVariant, fontSize = sp(if (i == 0) 32 else 28),
                                fontWeight = if (i == 0) FontWeight.Bold else FontWeight.Normal, textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
                WittyButton(backLabel, onBack, Modifier.heightIn(min = metrics.minTarget).padding(top = metrics.u(6)), kind = ButtonKind.Primary, tall = true, takeFocus = true, focusKey = "on-a-computer-back")
                if (footer.isNotEmpty()) {
                    Text(footer, color = LocalExtraColours.current.hint, fontSize = sp(24), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().widthIn(max = metrics.u(1300)))
                }
            }
        }
    }
}

// The symbol for a setting's address, as You's rows have them.
fun onAComputerIcon(path: String): ImageVector {
    val p = path.substringBefore('?').substringBefore('#')
    return when {
        p.startsWith("/settings/libraries") || p.startsWith("/manage") || p.endsWith("/libraries") -> Symbols.Libraries
        p.startsWith("/settings/pages") -> Symbols.TopMenu
        p.startsWith("/settings/metadata") || p.startsWith("/settings/game-metadata") -> Symbols.ImageSearch
        p.startsWith("/fix-matches") -> Symbols.FixMatches
        p.startsWith("/settings/channels") || p.startsWith("/settings/tuners") || p.startsWith("/tv/channels") -> Symbols.LiveTv
        p.startsWith("/settings/transcoding") -> Symbols.Bolt
        p.startsWith("/settings/library-transcoding") -> Symbols.Autorenew
        p.startsWith("/settings/network") -> Symbols.Antenna
        p.startsWith("/settings/remote") -> Symbols.Globe
        p.startsWith("/settings/logs") -> Symbols.Article
        p.startsWith("/settings/diagnoser") -> Symbols.Stethoscope
        p.startsWith("/settings/modules") -> Symbols.Extension
        p.startsWith("/settings/backup") || p.startsWith("/settings/data-folder") -> Symbols.Backup
        p.startsWith("/settings/repair") -> Symbols.Build
        p.startsWith("/settings/reset") -> Symbols.Restart
        p.startsWith("/settings/appearance") -> Symbols.Brush
        p.startsWith("/markers") || p.startsWith("/canvas") -> Symbols.Videocam
        else -> Symbols.Computer
    }
}
