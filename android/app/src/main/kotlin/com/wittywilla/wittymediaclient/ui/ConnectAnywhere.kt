// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em

// Design 2's "Choose a server" parts, as Apple draws them (apple/App/ConnectParts.swift) and the desktop app's page
// (shared/connect): small-capital section labels with a hairline, a round avatar for each server, and the one distinct
// panel for connecting from anywhere, peer to peer, with its picture of the connection. docs/APP-DESIGN.md.

/** The blue that marks a server reached peer to peer, on every platform. */
val PeerBlue = Color(0xFF0A84FF)

// A few line icons on a 24 grid, the same paths as the desktop app's page, for what Symbols hasn't got.
private fun line(name: String, vararg paths: String): ImageVector = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
    for (d in paths) {
        addPath(
            PathParser().parsePathString(d).toNodes(), stroke = SolidColor(Color.Black), strokeLineWidth = 2f,
            strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round,
        )
    }
}.build()

object LineIcons {
    val Lock by lazy { line("lock", "M6.5 10.5h11a1.5 1.5 0 0 1 1.5 1.5v7a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19v-7a1.5 1.5 0 0 1 1.5-1.5z", "M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5") }
    val Tick by lazy { line("tick", "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z", "M8 12.2l2.7 2.7L16 9.6") }
    val Wifi by lazy { line("wifi", "M2.5 9a14 14 0 0 1 19 0", "M5.5 12.5a9.5 9.5 0 0 1 13 0", "M8.7 15.9a5 5 0 0 1 6.6 0", "M12 19.5h.01") }
    val Globe by lazy { line("globe", "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z", "M3 12h18", "M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9s1.3-6.4 3.8-9z") }
    val House by lazy { line("house", "M4 10.5L12 4l8 6.5", "M6 9v10a1 1 0 0 0 1 1h3.5v-5.5h3V20H17a1 1 0 0 0 1-1V9") }
}

/**
 * "YOUR SERVERS", "ON THIS NETWORK": small capitals, then a hairline to the edge. On a centred page (Choose a server)
 * the label sits in the middle with a hairline on both sides, so it lines up with the centred head above it.
 */
@Composable
fun ConnectSectionLabel(title: String, modifier: Modifier = Modifier) {
    val s = LocalDesignSizes.current
    val scheme = MaterialTheme.colorScheme
    val centred = LocalDesignCentred.current
    Row(modifier.fillMaxWidth().padding(top = s.gap2, bottom = s.gap * 0.6f), verticalAlignment = Alignment.CenterVertically) {
        if (centred) Box(Modifier.padding(end = s.gap).weight(1f).height(1.dp).background(scheme.outline))
        Text(
            title.uppercase(), color = scheme.onSurfaceVariant, fontSize = s.tiny, fontWeight = FontWeight.Bold, letterSpacing = 0.08.em,
            modifier = Modifier.semantics { heading() },
        )
        Box(Modifier.padding(start = s.gap).weight(1f).height(1.dp).background(scheme.outline))
    }
}

/** A section under a [ConnectSectionLabel]: the cards, a little apart. */
@Composable
fun ConnectSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        ConnectSectionLabel(title)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
    }
}

/** A colour a name picks, the same for the same name: Apple's GameShelves.titleHue in spirit. */
fun nameHue(name: String): Float {
    var h = 0
    for (c in name) h = (h * 31 + c.code) % 360
    return h.toFloat()
}

/**
 * A saved server's picture as Design 2 draws it: its own logo in a circle, or its first letter on a gradient its name
 * picks, with a blue dot when it is reached peer to peer.
 */
@Composable
fun ServerAvatar(name: String, logo: Any?, size: Dp, peer: Boolean) {
    val hue = nameHue(name.ifEmpty { "WittyMediaServer" })
    Box(Modifier.size(size)) {
        Box(
            Modifier.size(size).background(
                Brush.linearGradient(listOf(Color.hsv(hue, 0.55f, 0.85f), Color.hsv((hue + 29f) % 360f, 0.7f, 0.5f))), CircleShape,
            ),
            contentAlignment = Alignment.Center,
        ) {
            if (logo != null && logo != "") {
                ServerMark(size * 0.62f, logo)
            } else {
                Text(
                    (name.trim().firstOrNull() ?: 'W').uppercase(), color = Color.White, fontWeight = FontWeight.ExtraBold,
                    fontSize = with(androidx.compose.ui.platform.LocalDensity.current) { (size * 0.42f).toSp() },
                )
            }
        }
        if (peer) {
            Box(
                Modifier.align(Alignment.BottomEnd).offset(1.dp, 1.dp).size(size * 0.3f)
                    .background(PeerBlue, CircleShape).border(2.dp, MaterialTheme.colorScheme.surface, CircleShape),
            )
        }
    }
}

/** "Peer to peer" at the end of a server's card. */
@Composable
fun PeerChip(text: String) {
    val s = LocalDesignSizes.current
    Text(
        text, color = LocalExtraColours.current.accentText, fontSize = s.tiny, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
        modifier = Modifier.background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f), RoundedCornerShape(50))
            .padding(horizontal = s.gap * 0.9f, vertical = 4.dp),
    )
}

/**
 * The one distinct panel: connecting from anywhere, peer to peer. A globe badge, what it is, a small picture of the
 * connection (this device, a dashed line, Encrypted, a dashed line, your server), the ways in as real buttons, and
 * three promises with ticks.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ConnectAnywherePanel(words: Map<String, String>, buttons: @Composable ColumnScope.() -> Unit) {
    val s = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val corner = RoundedCornerShape(metrics.u(16))
    Column(
        Modifier.fillMaxWidth().padding(top = s.gap2)
            .background(Brush.linearGradient(listOf(scheme.primary.copy(alpha = 0.14f), scheme.surface)), corner)
            .border(1.dp, scheme.primary.copy(alpha = 0.35f), corner)
            .padding(s.gap * 1.6f),
        verticalArrangement = Arrangement.spacedBy(s.gap * 1.2f),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(s.gap * 1.2f)) {
            val badge = s.body.value.dp * 2.6f
            Box(Modifier.size(badge).background(scheme.primary.copy(alpha = 0.16f), RoundedCornerShape(metrics.u(10))), contentAlignment = Alignment.Center) {
                Icon(LineIcons.Globe, contentDescription = null, tint = extra.accentText, modifier = Modifier.size(badge * 0.55f))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    words["anywhereTitle"].orEmpty(), color = scheme.onSurface, fontSize = s.body * 1.15f, fontWeight = FontWeight.ExtraBold,
                    modifier = Modifier.semantics { heading() },
                )
                Text(words["anywhereHint"].orEmpty(), color = scheme.onSurfaceVariant, fontSize = s.small, lineHeight = s.small * 1.45f)
            }
        }
        ConnectionPicture(words)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(s.gap * 0.8f)) { buttons() }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // The picture above already says Encrypted: the promises add what it doesn't.
            for (key in listOf("anywherePromiseRouter", "anywherePromiseInvite")) {
                Row(
                    Modifier.background(Color(0x24808080), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Icon(LineIcons.Tick, contentDescription = null, tint = extra.ok, modifier = Modifier.size(s.tiny.value.dp * 1.2f))
                    Text(words[key].orEmpty(), color = scheme.onSurface, fontSize = s.tiny, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

// This device, a dashed line, the lock, a dashed line, the server: heard as one sentence.
@Composable
private fun ConnectionPicture(words: Map<String, String>) {
    val s = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val hint = extra.hint
    @Composable
    fun node(icon: ImageVector, label: String) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(icon, contentDescription = null, tint = scheme.onSurface, modifier = Modifier.size(s.body.value.dp * 1.6f))
            Text(label, color = scheme.onSurfaceVariant, fontSize = s.tiny, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    @Composable
    fun dashes(modifier: Modifier) {
        Canvas(modifier.height(10.dp)) {
            drawLine(hint, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), strokeWidth = 1.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(8f, 8f)))
        }
    }
    Row(
        Modifier.fillMaxWidth().padding(vertical = s.gap * 0.6f).semantics(mergeDescendants = true) { contentDescription = words["anywherePicture"].orEmpty() },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(s.gap * 0.6f),
    ) {
        node(if (metrics.tv) Symbols.Tv else Symbols.Phone, words["anywhereDevice"].orEmpty())
        dashes(Modifier.weight(1f))
        Row(
            Modifier.background(extra.ok.copy(alpha = 0.16f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(LineIcons.Lock, contentDescription = null, tint = extra.ok, modifier = Modifier.size(s.tiny.value.dp * 1.2f))
            Text(words["anywhereEncrypted"].orEmpty(), color = extra.ok, fontSize = s.tiny, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        dashes(Modifier.weight(1f))
        node(Symbols.Server, words["anywhereServer"].orEmpty())
    }
}
