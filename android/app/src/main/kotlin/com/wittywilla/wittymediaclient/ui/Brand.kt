// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import coil3.compose.AsyncImage
import coil3.compose.AsyncImagePainter
import com.wittywilla.wittymediaclient.R

// docs/APP-DESIGN.md, "Brand". The marks are the family's own (BrandArt, generated from the same drawings as every
// icon, so they're sharp at any size and need no picture file), on the website's dark tile: the server, a W inside a
// thick lilac-to-violet ring with a gap and an amber dot; this app, a screen on a stand carrying the small ring with
// the W, violet into sky blue, with a mint dot. A mark stands for a server unless `client` says it's this app's own.
// markShape clips a server's own logo to about the tile's corners.
private const val MARK_GRID = 64f
private const val MARK_RADIUS = 14f

fun markShape(size: Dp) = RoundedCornerShape(size * (MARK_RADIUS / MARK_GRID))

@Composable
fun BrandMark(size: Dp, modifier: Modifier = Modifier, client: Boolean = false) {
    Image(imageVector = if (client) BrandArt.Client else BrandArt.Server, contentDescription = null, modifier = modifier.size(size))
}

// The server's own logo in the mark's square, or the mark until it arrives or if it can't be had. `logo` is
// anything Coil reads: the server's address for it, or the copy kept on this device.
@Composable
fun ServerMark(size: Dp, logo: Any?, modifier: Modifier = Modifier) {
    if (logo == null || logo == "") {
        BrandMark(size, modifier)
        return
    }
    var failed by remember(logo) { mutableStateOf(false) }
    var shown by remember(logo) { mutableStateOf(false) }
    Box(modifier.size(size).clip(markShape(size))) {
        if (failed || !shown) BrandMark(size)
        if (!failed) {
            AsyncImage(
                model = logo, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
                onState = {
                    shown = it is AsyncImagePainter.State.Success
                    failed = it is AsyncImagePainter.State.Error
                },
            )
        }
    }
}

// "WittyMediaClient" for the app itself, or a server's: "WittyMediaServer" with Media in the accent, or the
// server's own name in plain words. A TV reads it from across the room: 48 bold, the size of Display's
// neighbour, as Apple TV draws it.
@Composable
fun Wordmark(brandName: String, modifier: Modifier = Modifier, app: Boolean = false) {
    val metrics = LocalMetrics.current
    val style = if (metrics.tv) {
        MaterialTheme.typography.headline.copy(fontSize = with(LocalDensity.current) { metrics.u(48).toSp() }, fontWeight = FontWeight.Bold)
    } else {
        MaterialTheme.typography.headline.copy(fontWeight = FontWeight.Bold)
    }
    val ink = MaterialTheme.colorScheme.onBackground
    if (!app && brandName.isNotEmpty()) {
        Text(brandName, color = ink, style = style, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = modifier)
        return
    }
    val accent = LocalExtraColours.current.accentText
    val last = if (app) "Client" else "Server"
    val words = remember(accent, ink, last) {
        buildAnnotatedString {
            withStyle(SpanStyle(color = ink)) { append("Witty") }
            withStyle(SpanStyle(color = accent)) { append("Media") }
            withStyle(SpanStyle(color = ink)) { append(last) }
        }
    }
    Text(words, style = style, maxLines = 1, modifier = modifier)
}

// Mark then wordmark: 32 and 10 apart on a phone, 72 and 20 apart on a TV. The app's own (WittyMediaClient, with
// the client's mark) before a server is added; that server's (its logo, or the server mark) on its own screens.
// Heard as the name.
@Composable
fun Lockup(brandName: String, logo: Any?, modifier: Modifier = Modifier, app: Boolean = false) {
    val metrics = LocalMetrics.current
    Row(
        modifier.semantics(mergeDescendants = true) {
            contentDescription = if (app) "WittyMediaClient" else brandName.ifEmpty { "WittyMediaServer" }
            heading()
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 20 else 10)),
    ) {
        val mark = metrics.u(if (metrics.tv) 72 else 32)
        if (app) BrandMark(mark, client = true) else ServerMark(mark, logo)
        Wordmark(brandName, app = app)
    }
}

// Behind a TV's connect, server-picking and sign-in screens: the family's backdrop (drawable-nodpi/connect_backdrop,
// a dark scene with this app's mark faint on the right, no words; made by scripts/sync-brand.sh) filling the screen, under a veil of the theme's background so the words
// and cards on it read as they do on the plain background. A phone keeps the plain background and the glow.
@Composable
fun TvBackdrop(modifier: Modifier = Modifier, contentAlignment: Alignment = Alignment.TopStart, content: @Composable BoxScope.() -> Unit) {
    val background = MaterialTheme.colorScheme.background
    val veil = if (background.luminance() > 0.5f) VEIL_LIGHT else VEIL_DARK
    Box(modifier.fillMaxSize().background(background), contentAlignment = contentAlignment) {
        Image(painterResource(R.drawable.connect_backdrop), contentDescription = null, modifier = Modifier.matchParentSize(), contentScale = ContentScale.Crop)
        Box(Modifier.matchParentSize().background(background.copy(alpha = veil)))
        content()
    }
}

private const val VEIL_DARK = 0.5f
private const val VEIL_LIGHT = 0.82f

// The soft light at the top of the sign-in screens: the web's
// radial-gradient(70% 60% at 50% 0%, accent/.16, transparent 70%).
fun Modifier.signInGlow(accent: Color): Modifier = drawBehind {
    val rx = size.width * GLOW_WIDE
    val ry = size.height * GLOW_TALL
    if (rx <= 0f || ry <= 0f) return@drawBehind
    val centre = Offset(size.width / 2, 0f)
    // A circle squashed into the ellipse, about the top edge's middle.
    scale(scaleX = 1f, scaleY = ry / rx, pivot = centre) {
        drawCircle(
            Brush.radialGradient(0f to accent.copy(alpha = GLOW_ALPHA), GLOW_FADE to accent.copy(alpha = 0f), center = centre, radius = rx),
            radius = rx, center = centre,
        )
    }
}

private const val GLOW_WIDE = 0.7f
private const val GLOW_TALL = 0.6f
private const val GLOW_ALPHA = 0.16f
private const val GLOW_FADE = 0.7f
