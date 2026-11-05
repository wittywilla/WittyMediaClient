package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
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

// docs/APP-DESIGN.md, "Brand". The mark is the server's icon (web/public/icon.svg in WittyMediaServer)
// drawn here on its own 64 grid, so it's sharp at any size and needs no picture file.
private val MARK_TILE = Color(0xFF1B1E25)
private val MARK_LIGHT = Color(0xFF9D7BFF)
private val MARK_DARK = Color(0xFF5B3DF5)
private const val MARK_GRID = 64f
private const val MARK_RADIUS = 14f

fun markShape(size: Dp) = RoundedCornerShape(size * (MARK_RADIUS / MARK_GRID))

@Composable
fun BrandMark(size: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val k = this.size.width / MARK_GRID
        drawRoundRect(MARK_TILE, cornerRadius = CornerRadius(MARK_RADIUS * k))
        // Each shape has the gradient across its own box, top left to bottom right, as in the SVG.
        drawCircle(
            Brush.linearGradient(listOf(MARK_LIGHT, MARK_DARK), Offset(12 * k, 12 * k), Offset(52 * k, 52 * k)),
            radius = 20 * k, center = Offset(32 * k, 32 * k), style = Stroke(5 * k),
        )
        val play = Path().apply {
            moveTo(27 * k, 23 * k)
            lineTo(41 * k, 32 * k)
            lineTo(27 * k, 41 * k)
            close()
        }
        drawPath(play, Brush.linearGradient(listOf(MARK_LIGHT, MARK_DARK), Offset(27 * k, 23 * k), Offset(41 * k, 41 * k)))
    }
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

// Mark then wordmark: 32 and 10 apart on a phone, 72 and 20 apart on a TV. The app's own (WittyMediaClient)
// before a server is added; that server's on its own screens. Heard as the name.
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
        ServerMark(metrics.u(if (metrics.tv) 72 else 32), if (app) null else logo)
        Wordmark(brandName, app = app)
    }
}

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
