package com.wittywilla.wittymediaclient.ui

import androidx.compose.animation.core.tween
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.player.Listening
import kotlinx.coroutines.delay

// The website's mini bar for music, books and podcasts on a phone (web/src/audio/MiniPlayer.tsx, audio.css): 8 from the
// sides and 16 above the floating bar, 66 high, panel colour, a hairline at text 20%, radius 20, the e-3 shadow. The
// 48 picture, the title and artist, Play (44, accent), Next and Up. The seek slider sits on its top edge, 16 in.

@Composable
private fun rememberAudioPlace(listening: Listening): Double {
    var place by remember { mutableDoubleStateOf(listening.positionSec()) }
    LaunchedEffect(listening.isPlaying, listening.now?.mediaId, listening.jumps) {
        place = listening.positionSec()
        while (listening.isPlaying) {
            delay(500)
            place = listening.positionSec()
        }
    }
    return place
}

// The website's range: a 4-high track (accent to the place, text at 28% after it) and a 14 white thumb, always shown.
@Composable
fun WebRange(fraction: Float, seek: (Float) -> Unit, modifier: Modifier = Modifier, label: String = "Position") {
    val accent = MaterialTheme.colorScheme.primary
    val rest = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.28f)
    var width by remember { mutableIntStateOf(1) }
    Canvas(
        modifier.height(14.dp).onSizeChanged { width = it.width }.semantics { contentDescription = label }
            .pointerInput(Unit) { detectTapGestures { seek((it.x / width).coerceIn(0f, 1f)) } }
            .pointerInput(Unit) { detectHorizontalDragGestures { change, _ -> seek((change.position.x / width).coerceIn(0f, 1f)) } },
    ) {
        val h = 4.dp.toPx()
        val top = (size.height - h) / 2
        val at = size.width * fraction.coerceIn(0f, 1f)
        drawRoundRect(rest, Offset(0f, top), Size(size.width, h), CornerRadius(2.dp.toPx()))
        drawRoundRect(accent, Offset(0f, top), Size(at, h), CornerRadius(2.dp.toPx()))
        drawCircle(Color(0x73000000), 7.dp.toPx(), Offset(at, size.height / 2 + 1.dp.toPx()))
        drawCircle(Color.White, 7.dp.toPx(), Offset(at, size.height / 2))
    }
}

@Composable
fun PhoneMiniBar(nav: Nav, modifier: Modifier = Modifier) {
    val listening = nav.app.listening
    val now = listening.now ?: return
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val about = now.mediaMetadata
    val place = rememberAudioPlace(listening)
    val duration = listening.durationSec()
    val subtitle = listOf(about.artist?.toString().orEmpty().ifEmpty { about.albumArtist?.toString().orEmpty() }, about.albumTitle?.toString().orEmpty()).filter { it.isNotEmpty() }.joinToString(" · ")
    AnimatedVisibility(true, modifier, enter = fadeIn(tween(240))) {
        Box(Modifier.fillMaxWidth().height(66.dp)) {
            Row(
                Modifier.fillMaxSize().cssShadow(10.dp, 30.dp, Color(0x73000000), 20.dp).clip(RoundedCornerShape(20.dp)).background(scheme.surface)
                    .border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(20.dp)).padding(8.dp)
                    .semantics { contentDescription = "Now playing" },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Pressable(nav::openNowPlaying, Modifier.size(48.dp), shape = RoundedCornerShape(10.dp), fill = scheme.surfaceVariant, label = "Open Now Playing", ring = false) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Icon(WebIcons.Audio, null, tint = extra.hint, modifier = Modifier.size(22.dp))
                        about.artworkUri?.toString()?.takeIf { it.isNotEmpty() }?.let { WebArt(it, "", 48.dp, 1f, Modifier.fillMaxSize(), placeholderless = true) }
                    }
                }
                Pressable(nav::openNowPlaying, Modifier.weight(1f), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "${about.title}, ${subtitle}", ring = false) {
                    Column(Modifier.padding(horizontal = 8.dp, vertical = 4.dp)) {
                        Text(about.title?.toString().orEmpty(), color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val second = when { listening.problem.isNotEmpty() -> listening.problem; listening.isLoading -> "Loading…"; else -> subtitle }
                        if (second.isNotEmpty()) Text(second, color = scheme.onSurfaceVariant, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Pressable(listening::toggle, Modifier.size(44.dp), shape = CircleShape, fill = scheme.primary, label = if (listening.isPlaying) "Pause" else "Play", pressScale = 0.94f, ring = false) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (listening.isPlaying) WebIcons.Pause else WebIcons.Play, null, tint = scheme.onPrimary, modifier = Modifier.size(22.dp)) }
                    }
                    Pressable({ if (listening.canGoNext) listening.next() }, Modifier.size(44.dp), shape = CircleShape, fill = Color.Transparent, label = "Next", pressScale = 0.94f, ring = false) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(WebIcons.Next, null, tint = scheme.onBackground, modifier = Modifier.size(22.dp)) }
                    }
                }
                Pressable(nav::openNowPlaying, Modifier.size(44.dp), shape = CircleShape, fill = Color.Transparent, label = "Open Now Playing", pressScale = 0.94f, ring = false) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(WebIcons.Up, null, tint = scheme.onBackground, modifier = Modifier.size(20.dp)) }
                }
            }
            if (duration > 0) WebRange(
                (place / duration).toFloat(), { listening.seekTo((it * duration).toInt().toDouble()) },
                Modifier.fillMaxWidth().padding(horizontal = 16.dp).offset(y = (-7).dp),
            )
        }
    }
}
