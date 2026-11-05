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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.media3.common.Player
import com.wittywilla.wittymediaclient.player.clock
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
    // From 900 across, the website's wider bar; folded, a round button in the corner.
    val wide = LocalConfiguration.current.screenWidthDp >= 900
    var said by remember { mutableStateOf("") }
    CompositionLocalProvider(LocalSay provides { said = it }) {
        Box(modifier.fillMaxWidth()) {
            when {
                listening.barCollapsed -> CollapsedBar(nav, Modifier.align(Alignment.CenterEnd).padding(end = if (wide) 8.dp else 0.dp))
                wide -> WideBar(nav, now, Modifier.align(Alignment.Center))
                else -> NarrowBar(nav, now)
            }
            Toast(said, { said = "" }, Modifier.align(Alignment.TopCenter).offset(y = (-56).dp))
        }
    }
}

// A phone's bar: the picture, the title and who, Play, Next and Up.
@Composable
private fun NarrowBar(nav: Nav, now: androidx.media3.common.MediaItem) {
    val listening = nav.app.listening
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val about = now.mediaMetadata
    val place = rememberAudioPlace(listening)
    val duration = listening.durationSec()
    val subtitle = listOf(about.artist?.toString().orEmpty().ifEmpty { about.albumArtist?.toString().orEmpty() }, about.albumTitle?.toString().orEmpty()).filter { it.isNotEmpty() }.joinToString(" · ")
    AnimatedVisibility(true, enter = fadeIn(tween(240))) {
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

// A round 40 button of the bar's (`.audio-bar .mp-ibtn`): clear, or the accent's tint and its words' colour when on.
@Composable
private fun BarButton(icon: ImageVector, label: String, on: Boolean = false, tint: Color? = null, iconSize: Dp = 22.dp, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    Pressable(onClick, modifier.size(40.dp), shape = CircleShape, fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent, label = label, selected = on, pressScale = 0.94f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(icon, null, tint = tint ?: if (on) extra.accentText else scheme.onBackground, modifier = Modifier.size(iconSize)) }
    }
}

// Back 15 and Forward 30 in the bar: the circular arrow with the number in it, 7.4 bold at 16.6 down, as the website's.
@Composable
private fun BarJump(back: Boolean, n: Int, label: String, onClick: () -> Unit) {
    val ink = MaterialTheme.colorScheme.onBackground
    Pressable(onClick, Modifier.size(40.dp), shape = CircleShape, fill = Color.Transparent, label = label, pressScale = 0.94f, ring = false) {
        Box(Modifier.size(24.dp)) {
            Icon(NpIcons.Jump, null, tint = ink, modifier = Modifier.fillMaxSize().graphicsLayer { if (!back) scaleX = -1f })
            val unit = 1.dp
            Text(
                "$n", color = ink, fontSize = with(LocalDensity.current) { (unit * 7.4f).toSp() }, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                lineHeight = with(LocalDensity.current) { (unit * 7.4f).toSp() }, modifier = Modifier.fillMaxWidth().offset(y = unit * (16.6f - 7.4f * 0.8f)),
            )
        }
    }
}

// The website's wider bar, from 900 across (`.audio-bar` at min-width 900): centred, at most 1320 wide, the 64 picture
// standing 22 out of its top; the title and who; Like and Add to a playlist; the whole transport; the time (over
// 1240), the volume, the queue, the visualizer (its word over 1240), full screen, Collapse and Stop.
@Composable
private fun WideBar(nav: Nav, now: androidx.media3.common.MediaItem, modifier: Modifier) {
    val listening = nav.app.listening
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val about = now.mediaMetadata
    val place = rememberAudioPlace(listening)
    val duration = listening.durationSec()
    val books = listening.keepsPlace
    val roomy = LocalConfiguration.current.screenWidthDp > 1240
    val trackId = now.mediaId.toLongOrNull() ?: 0L
    val library = about.extras?.getLong(com.wittywilla.wittymediaclient.player.EXTRA_LIBRARY) ?: 0L
    LaunchedEffect(library) { if (!books) listening.loadLikes(library) }
    LaunchedEffect(Unit) { listening.askAboutVisualizer() }
    var adding by remember { mutableStateOf(false) }
    var volume by remember { mutableStateOf(false) }
    val say = LocalSay.current
    val subtitle = when {
        listening.problem.isNotEmpty() -> listening.problem
        else -> listOf(about.artist?.toString().orEmpty().ifEmpty { about.albumArtist?.toString().orEmpty() }, about.albumTitle?.toString().orEmpty()).filter { it.isNotEmpty() }.joinToString(" · ")
    }
    fun open(queue: Boolean = false, visualizer: Boolean = false) {
        listening.screenWithQueue = queue
        listening.screenWithVisualizer = visualizer
        nav.openNowPlaying()
    }
    Box(modifier.widthIn(max = 1320.dp).fillMaxWidth().padding(horizontal = 16.dp)) {
        Row(
            Modifier.fillMaxWidth().cssShadow(10.dp, 30.dp, Color(0x73000000), 20.dp).clip(RoundedCornerShape(20.dp)).background(scheme.surface)
                .border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(20.dp)).padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 8.dp)
                .semantics { contentDescription = "Now playing" },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Spacer(Modifier.width(64.dp))
            Pressable({ open() }, Modifier.weight(1f).widthIn(min = 120.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "${about.title}, $subtitle", ring = false) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp)) {
                    Text(about.title?.toString().orEmpty(), color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (subtitle.isNotEmpty()) Text(subtitle, color = scheme.onSurfaceVariant, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                if (!books && trackId > 0) {
                    val liked = listening.liked[trackId] == true
                    BarButton(if (liked) WebIcons.HeartOn else WebIcons.Heart, if (liked) "Remove from liked songs" else "Add to liked songs", tint = if (liked) extra.accentText else null, iconSize = 20.dp) { listening.toggleLike(trackId, say) }
                }
                Box {
                    BarButton(WebIcons.AddList, "Add to a playlist", on = adding, iconSize = 20.dp) { adding = !adding }
                    if (adding) PopPanel({ adding = false }) {
                        PlaylistPicker(nav, listOf(com.wittywilla.wittymediaclient.net.Item(id = trackId, title = about.title?.toString().orEmpty())), done = { adding = false })
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                if (books) BarJump(true, 15, "Back 15 seconds") { listening.seekBy(-15.0) }
                else BarButton(NpIcons.Shuffle, "Shuffle", on = listening.shuffle) { listening.toggleShuffle() }
                BarButton(WebIcons.Prev, "Previous") { listening.previous() }
                Pressable(listening::toggle, Modifier.size(44.dp), shape = CircleShape, fill = scheme.primary, label = if (listening.isPlaying) "Pause" else "Play", pressScale = 0.94f, ring = false) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (listening.isPlaying) WebIcons.Pause else WebIcons.Play, null, tint = scheme.onPrimary, modifier = Modifier.size(22.dp)) }
                }
                BarButton(WebIcons.Next, "Next") { if (listening.canGoNext) listening.next() }
                if (books) BarJump(false, 30, "Forward 30 seconds") { listening.seekBy(30.0) }
                else {
                    val words = when (listening.repeat) { Player.REPEAT_MODE_ALL -> "Repeat all"; Player.REPEAT_MODE_ONE -> "Repeat this song"; else -> "Repeat off" }
                    BarButton(if (listening.repeat == Player.REPEAT_MODE_ONE) NpIcons.RepeatOne else NpIcons.Repeat, words, on = listening.repeat != Player.REPEAT_MODE_OFF) { listening.cycleRepeat() }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                if (roomy) Text("${clock(place)} / ${clock(duration)}", color = scheme.onSurfaceVariant, fontSize = 12.sp, maxLines = 1, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.padding(horizontal = 8.dp))
                Box {
                    val silent = listening.sound.muted || listening.sound.volume == 0.0
                    BarButton(if (silent) WebIcons.Mute else WebIcons.Volume, "Volume", on = volume, iconSize = 20.dp) { volume = !volume }
                    if (volume) PopPanel({ volume = false }) { VolumeCard(listening, onBlack = false) }
                }
                BarButton(if (books) WebIcons.Chapters else NpIcons.List, if (books) "Chapters" else "Queue", iconSize = 20.dp) { open(queue = true) }
                if (listening.visualizerHere) {
                    // Easy to see: a word beside the icon (over 1240), on the accent's tint.
                    Pressable({ open(visualizer = true) }, Modifier.padding(horizontal = 2.dp).heightIn(min = 40.dp), shape = RoundedCornerShape(50), fill = scheme.primary.copy(alpha = 0.14f), label = "Visualizer", pressScale = 0.94f, ring = false) {
                        Row(
                            Modifier.heightIn(min = 40.dp).border(1.5.dp, scheme.primary.copy(alpha = 0.4f), RoundedCornerShape(50)).padding(horizontal = if (roomy) 12.dp else 10.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(NpIcons.Visualizer, null, tint = extra.accentText, modifier = Modifier.size(18.dp))
                            if (roomy) Text("Visualizer", color = scheme.onBackground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        }
                    }
                }
                BarButton(WebIcons.Expand, "Full screen", iconSize = 20.dp) { open() }
                BarButton(WebIcons.Down, "Collapse the player", iconSize = 20.dp) { listening.collapseBar(true) }
                BarButton(WebIcons.Close, "Stop playing and close", iconSize = 20.dp) { listening.stop() }
            }
        }
        // The picture, standing out of the bar's top.
        Pressable({ open() }, Modifier.padding(start = 12.dp).offset(y = (-10).dp).size(64.dp).align(Alignment.TopStart).restingShadow(10.dp), shape = RoundedCornerShape(10.dp), fill = scheme.surfaceVariant, label = "Show the full player", pressScale = 0.96f, ring = false) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(WebIcons.Audio, null, tint = extra.hint, modifier = Modifier.size(22.dp))
                about.artworkUri?.toString()?.takeIf { it.isNotEmpty() }?.let { WebArt(it, "", 64.dp, 1f, Modifier.fillMaxSize(), placeholderless = true) }
            }
        }
        if (duration > 0) WebRange(
            (place / duration).toFloat(), { listening.seekTo((it * duration).toInt().toDouble()) },
            Modifier.fillMaxWidth().padding(start = 88.dp, end = 20.dp).offset(y = 2.dp),
        )
    }
}

// Folded (`.audio-bar.collapsed`): a round button in the corner, the picture in a circle with how far through as a
// ring round it, and Play beside it. The picture opens the bar again.
@Composable
private fun CollapsedBar(nav: Nav, modifier: Modifier) {
    val listening = nav.app.listening
    val now = listening.now ?: return
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val place = rememberAudioPlace(listening)
    val duration = listening.durationSec()
    val part = if (duration > 0) (place / duration).toFloat().coerceIn(0f, 1f) else 0f
    Row(
        modifier.cssShadow(10.dp, 30.dp, Color(0x73000000), 40.dp).clip(RoundedCornerShape(50)).background(scheme.surface)
            .border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(50)).padding(start = 5.dp, end = 8.dp, top = 5.dp, bottom = 5.dp)
            .semantics { contentDescription = "Now playing" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(54.dp), contentAlignment = Alignment.Center) {
            Pressable({ listening.collapseBar(false) }, Modifier.size(48.dp), shape = CircleShape, fill = scheme.surfaceVariant, label = "Show the player: ${now.mediaMetadata.title}", pressScale = 0.96f, ring = false) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Icon(WebIcons.Audio, null, tint = extra.hint, modifier = Modifier.size(22.dp))
                    now.mediaMetadata.artworkUri?.toString()?.takeIf { it.isNotEmpty() }?.let { WebArt(it, "", 48.dp, 1f, Modifier.fillMaxSize(), placeholderless = true) }
                }
            }
            // How far through, as a ring round the picture.
            Canvas(Modifier.fillMaxSize()) {
                val ring = 2.dp.toPx()
                drawArc(extra.accentText, -90f, 360f * part, false, topLeft = Offset(ring / 2, ring / 2), size = Size(size.width - ring, size.height - ring), style = Stroke(ring))
            }
        }
        Pressable(listening::toggle, Modifier.size(44.dp), shape = CircleShape, fill = scheme.primary, label = if (listening.isPlaying) "Pause" else "Play", pressScale = 0.94f, ring = false) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (listening.isPlaying) WebIcons.Pause else WebIcons.Play, null, tint = scheme.onPrimary, modifier = Modifier.size(22.dp)) }
        }
    }
}
