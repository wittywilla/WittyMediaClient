package com.wittywilla.wittymediaclient.ui

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.media3.common.Player
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.toBitmap
import com.wittywilla.wittymediaclient.player.EXTRA_LIBRARY
import com.wittywilla.wittymediaclient.player.Start
import com.wittywilla.wittymediaclient.player.clock
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// The website's Now Playing on a phone (web/src/audio/NowPlaying.tsx, nowplaying.css): black in every theme, with a glow
// coloured from the artwork, the artwork with its reflection, the title and artist, the seek bar, the transport and the
// tools; Sleep, Queue and More at the top. A panel (the queue) takes the artwork's place, above a smaller transport.
private object Np {
    val fg = Color.White
    val fg2 = Color.White.copy(alpha = 0.72f)
    val chip = Color.White.copy(alpha = 0.10f)
    val line = Color.White.copy(alpha = 0.14f)
    val panel = Color(0xF0101014)
    val menu = Color(0xFF15151A)
    val well = Color(0xFF24242C)
    val loved = Color(0xFFFF6B81)
}

private fun webIconPath(name: String, path: String) = androidx.compose.ui.graphics.vector.ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
    .addPath(androidx.compose.ui.graphics.vector.addPathNodes(spacedArcs(path)), fill = androidx.compose.ui.graphics.SolidColor(Color.Black)).build()

// The audio player's own icons, the website's paths (web/src/icons.tsx).
private object NpIcons {
    val Down by lazy { webIconPath("down", "M7.4 8.6L12 13.2l4.6-4.6L18 10l-6 6-6-6z") }
    val Shuffle by lazy { webIconPath("shuffle", "M17 4l4 3.5L17 11V8.5h-1.6a3 3 0 00-2.4 1.2l-4.6 6.1A5 5 0 014.4 18H3v-2h1.4a3 3 0 002.4-1.2l4.6-6.1a5 5 0 014-2H17zm0 9l4 3.5-4 3.5v-2.5h-1.6a5 5 0 01-4-2l-.5-.7 1.3-1.6.8 1.1a3 3 0 002.4 1.2H17zM3 6.5h1.4a5 5 0 014 2l.5.7-1.3 1.6-.8-1.1a3 3 0 00-2.4-1.2H3z") }
    val Repeat by lazy { webIconPath("repeat", "M17 2l4 4-4 4V7H7a2 2 0 00-2 2v3H3V9a4 4 0 014-4h10zM7 22l-4-4 4-4v3h10a2 2 0 002-2v-3h2v3a4 4 0 01-4 4H7z") }
    val RepeatOne by lazy { webIconPath("repeat-one", "M17 2l4 4-4 4V7H7a2 2 0 00-2 2v3H3V9a4 4 0 014-4h10zM7 22l-4-4 4-4v3h10a2 2 0 002-2v-3h2v3a4 4 0 01-4 4H7zm5.8-6.5h-1.6v-4.3l-1.3.4V10.300l2.700-.8h.2z") }
    val List by lazy { webIconPath("list", "M4 5.500a1.500 1.500 0 110 3 1.500 1.500 0 010-3zm0 5a1.500 1.500 0 110 3 1.500 1.500 0 010-3zm0 5a1.500 1.500 0 110 3 1.500 1.500 0 010-3zM8 6h13v2H8zm0 5h13v2H8zm0 5h13v2H8z") }
    val Moon by lazy { webIconPath("moon", "M12.300 3a9 9 0 108.700 11.300 7.400 7.400 0 01-8.700-11.300zm-2.600 2.700a9.400 9.400 0 008.600 10.300A7 7 0 119.700 5.700z") }
    val Heart by lazy { webIconPath("heart", "M12 20.6l-1.3-1.2C6 15.200 3 12.500 3 9.100 3 6.400 5.100 4.400 7.700 4.400c1.600 0 3.200.8 4.300 2 1.100-1.200 2.700-2 4.300-2C18.900 4.400 21 6.400 21 9.100c0 3.400-3 6.100-7.700 10.300zm-.1-2.700l.1.100.1-.1c4.100-3.700 6.900-6.200 6.900-8.800 0-1.700-1.300-2.900-3-2.900-1.300 0-2.600.8-3.100 2h-1.900c-.5-1.200-1.800-2-3.100-2-1.700 0-3 1.200-3 2.900 0 2.600 2.800 5.100 7 8.800z") }
    val HeartOn by lazy { webIconPath("heart-on", "M12 20.600l-1.300-1.200C6 15.200 3 12.500 3 9.100 3 6.400 5.100 4.400 7.700 4.400c1.600 0 3.200.8 4.300 2 1.100-1.200 2.700-2 4.300-2C18.900 4.400 21 6.400 21 9.100c0 3.400-3 6.100-7.700 10.300z") }
    val Station by lazy { webIconPath("station", "M12 10a2 2 0 110 4 2 2 0 010-4zM7.800 7.800a6 6 0 000 8.400l-1.400 1.400a8 8 0 010-11.200zm8.400 0l1.400-1.400a8 8 0 010 11.200l-1.400-1.400a6 6 0 000-8.400zM5 5a10 10 0 000 14l-1.400 1.400a12 12 0 010-16.800zm14 0l1.400-1.400a12 12 0 010 16.800L19 19a10 10 0 000-14z") }
    val AddList by lazy { webIconPath("add-list", "M3 6h13v2H3zm0 5h13v2H3zm0 5h9v2H3zm15-3h2v3h3v2h-3v3h-2v-3h-3v-2h3z") }
    // The jump arrow; forward is the same, mirrored.
    val Jump by lazy { webIconPath("jump", "M12 4V1L7 5l5 4V6a7.5 7.5 0 11-7.5 7.5h-2A9.5 9.5 0 1012 4z") }
}

// Back 15 and Forward 30 as the website draws them: the circular arrow with the number in it, 7.4 bold at 16.6 down.
@Composable
private fun JumpRound(back: Boolean, n: Int, label: String, size: Dp, iconSize: Dp, onClick: () -> Unit) {
    Pressable(onClick, Modifier.size(size), shape = CircleShape, fill = Np.chip, label = label, pressScale = 0.94f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Box(Modifier.size(iconSize)) {
                Icon(NpIcons.Jump, null, tint = Np.fg, modifier = Modifier.fillMaxSize().graphicsLayer { if (!back) scaleX = -1f })
                val unit = iconSize / 24
                Text(
                    "$n", color = Np.fg, fontSize = with(LocalDensity.current) { (unit * 7.4f).toSp() }, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                    lineHeight = with(LocalDensity.current) { (unit * 7.4f).toSp() },
                    modifier = Modifier.fillMaxWidth().offset(y = unit * (16.6f - 7.4f * 0.8f)),
                )
            }
        }
    }
}

// The artwork's colour, as the website works it out (web/src/audio/art.ts): the picture at 16×16, each pixel weighted by
// how colourful and bright it is, then lifted so that dark covers still glow. Grey without a picture.
fun artColour(bitmap: Bitmap?): Triple<Int, Int, Int> {
    if (bitmap == null) return Triple(120, 120, 135)
    val small = Bitmap.createScaledBitmap(bitmap, 16, 16, true)
    var r = 0.0; var g = 0.0; var b = 0.0; var total = 0.0
    for (y in 0 until 16) for (x in 0 until 16) {
        val p = small.getPixel(x, y)
        val pr = (p shr 16) and 0xff; val pg = (p shr 8) and 0xff; val pb = p and 0xff
        val max = maxOf(pr, pg, pb); val min = minOf(pr, pg, pb)
        val w = (max - min + 8.0) * (max + 24.0)
        r += pr * w; g += pg * w; b += pb * w; total += w
    }
    if (total <= 0) return Triple(120, 120, 135)
    r /= total; g /= total; b /= total
    val lift = minOf(2.2, 190.0 / maxOf(r, g, b, 1.0))
    fun c(v: Double) = Math.round(minOf(255.0, v * lift)).toInt()
    return Triple(c(r), c(g), c(b))
}

@Composable
private fun NpRound(icon: ImageVector, label: String, size: Dp, iconSize: Dp, on: Boolean = false, tint: Color? = null, onClick: () -> Unit) {
    Pressable(onClick, Modifier.size(size), shape = CircleShape, fill = if (on) Np.fg else Np.chip, label = label, selected = on, pressScale = 0.94f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = tint ?: if (on) Color.Black else Np.fg, modifier = Modifier.size(iconSize))
        }
    }
}

@Composable
private fun NpChip(words: String, on: Boolean = false, icon: ImageVector? = null, onClick: () -> Unit) {
    Pressable(onClick, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = if (on) Np.fg else Np.chip, label = words, selected = on, ring = false) {
        Row(Modifier.heightIn(min = 44.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (icon != null) Icon(icon, null, tint = if (on) Color.Black else Np.fg, modifier = Modifier.size(20.dp))
            Text(words, color = if (on) Color.Black else Np.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

private data class MenuItem(val words: String, val icon: ImageVector? = null, val chosen: Boolean = false, val run: () -> Unit)

// The website's pop menu: #15151a, a hairline, radius 14, 6 inside, at least 220 wide; rows 44 high.
@Composable
private fun PopMenu(items: List<MenuItem>, modifier: Modifier, close: () -> Unit) {
    Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null, onClick = close)) {
        Column(
            modifier.widthIn(min = 220.dp, max = 340.dp).cssShadow(10.dp, 30.dp, Color(0x73000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(Np.menu)
                .border(1.dp, Np.line, RoundedCornerShape(14.dp)).padding(6.dp).verticalScroll(rememberScrollState()),
        ) {
            items.forEach { item ->
                Pressable({ item.run(); close() }, Modifier.fillMaxWidth().heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = item.words, selected = item.chosen, ring = false) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (item.icon != null) Icon(item.icon, null, tint = Np.fg, modifier = Modifier.size(18.dp))
                        Text((if (item.chosen) "✓ " else "") + item.words, color = Np.fg, fontSize = 14.sp, fontWeight = if (item.chosen) FontWeight.Bold else FontWeight.Normal, maxLines = 1)
                    }
                }
            }
        }
    }
}

private enum class NpMenu { None, Playlist, Sleep, More, Speed }

@Composable
fun WebNowPlaying(nav: Nav) {
    val listening = nav.app.listening
    val now = listening.now
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    BackHandler { nav.pop() }
    if (now == null) {
        LaunchedEffect(Unit) { nav.pop() }
        return
    }
    val about = now.mediaMetadata
    val books = listening.keepsPlace
    val library = about.extras?.getLong(EXTRA_LIBRARY) ?: 0L
    val trackId = now.mediaId.toLongOrNull() ?: 0L
    val art = about.artworkUri?.toString()
    var glow by remember { mutableStateOf(Triple(120, 120, 135)) }
    LaunchedEffect(art) {
        glow = if (art == null) Triple(120, 120, 135) else runCatching {
            val request = ImageRequest.Builder(context).data(art).size(64).allowHardware(false).build()
            artColour(SingletonImageLoader.get(context).execute(request).image?.toBitmap())
        }.getOrDefault(Triple(120, 120, 135))
    }
    var liked by remember(library) { mutableStateOf(emptySet<Long>()) }
    LaunchedEffect(library) { if (!books && library > 0) liked = runCatching { nav.app.api.likes(library).toSet() }.getOrDefault(emptySet()) }
    var panel by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(NpMenu.None) }
    var toast by remember { mutableStateOf("") }
    var maxSpeed by remember { mutableStateOf(4.0) }
    LaunchedEffect(Unit) { maxSpeed = runCatching { nav.app.api.playerPrefs().maxSpeed }.getOrDefault(4.0) }
    // Opening: a fade and a 16 rise over 240 ms.
    val rise = remember { Animatable(0f) }
    LaunchedEffect(Unit) { rise.animateTo(1f, tween(240, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) }
    val status = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
    val inset = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    val screenH = LocalConfiguration.current.screenHeightDp
    val screenW = LocalConfiguration.current.screenWidthDp
    val locale = androidx.core.os.ConfigurationCompat.getLocales(LocalConfiguration.current)[0] ?: Locale.ROOT
    val tint = Color(glow.first, glow.second, glow.third)

    Box(
        Modifier.fillMaxSize().background(Color.Black).graphicsLayer { alpha = rise.value; translationY = (1 - rise.value) * 16.dp.toPx() }
            .drawWithContent {
                // radial-gradient(90% 60% at 50% 0%, art/.34, art/.10 55%, transparent 80%)
                val rx = size.width * 0.9f
                val ry = size.height * 0.6f
                val centre = androidx.compose.ui.geometry.Offset(size.width / 2, 0f)
                scale(1f, ry / rx, centre) {
                    drawCircle(Brush.radialGradient(0f to tint.copy(alpha = 0.34f), 0.55f to tint.copy(alpha = 0.10f), 0.8f to Color.Transparent, center = centre, radius = rx), rx, centre)
                }
                drawContent()
            },
    ) {
        Column(Modifier.fillMaxSize()) {
            // The top bar: Close at the start; Add to a playlist, Sleep, Queue, Like and More at the end.
            Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = maxOf(14.dp, status), bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                NpRound(NpIcons.Down, "Close the full player", 44.dp, 20.dp) { nav.pop() }
                Spacer(Modifier.weight(1f))
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (trackId > 0) NpRound(NpIcons.AddList, "Add to a playlist", 44.dp, 20.dp) { menu = NpMenu.Playlist }
                    val sleepSet = listening.sleepAt != null || listening.sleepAfterThis
                    NpRound(NpIcons.Moon, if (sleepSet) "Sleep timer: stops ${listening.sleepAt?.let { "at " + SimpleDateFormat("HH:mm", locale).format(Date(it)) } ?: "after this one"}" else "Sleep timer", 44.dp, 20.dp, on = sleepSet) { menu = NpMenu.Sleep }
                    NpRound(if (books) WebIcons.Chapters else NpIcons.List, if (books) "Chapters" else "Queue", 44.dp, 20.dp, on = panel) { panel = !panel }
                    if (!books && library > 0) {
                        val on = trackId in liked
                        NpRound(if (on) NpIcons.HeartOn else NpIcons.Heart, if (on) "Remove from liked songs" else "Add to liked songs", 44.dp, 20.dp, tint = if (on) Np.loved else null) {
                            liked = if (on) liked - trackId else liked + trackId
                            scope.launch { runCatching { nav.app.api.react(trackId, if (on) 0 else 1) }.onFailure { liked = if (on) liked + trackId else liked - trackId } }
                        }
                    }
                    NpRound(WebIcons.More, "More", 44.dp, 20.dp) { menu = NpMenu.More }
                }
            }
            val playSize = (screenH * 0.10f).coerceIn(66f, 96f).dp
            Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (panel) {
                    QueuePanel(nav, glow, Modifier.weight(1f)) { panel = false }
                } else {
                    Column(
                        Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy((screenH * 0.013f).coerceIn(6f, 16f).dp, Alignment.CenterVertically),
                    ) {
                        val side = minOf(screenW * 0.66f, screenH * 0.32f).dp
                        val reflection = (screenH * 0.044f).coerceIn(16f, 40f).dp
                        Box(Modifier.padding(bottom = (screenH * 0.04f).coerceIn(16f, 36f).dp)) {
                            Box(Modifier.size(side).cssShadow(16.dp, 60.dp, Color(0x8C000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(Np.well)) {
                                WebArt(art, about.albumTitle?.toString() ?: about.title?.toString().orEmpty(), side, 1f, Modifier.fillMaxSize())
                            }
                            // The reflection: the artwork's foot, mirrored, fading from 34%.
                            if (art != null) Box(
                                Modifier.offset(y = side + 8.dp).size(side, reflection).clip(RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp))
                                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                                    .drawWithContent { drawContent(); drawRect(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.34f), Color.Transparent)), blendMode = BlendMode.DstIn) },
                            ) {
                                WebArt(art, "", side, 1f, Modifier.size(side).graphicsLayer { scaleY = -1f }.offset(y = 0.dp), placeholderless = true)
                            }
                        }
                        Column(Modifier.widthIn(max = 760.dp).padding(horizontal = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(about.title?.toString().orEmpty(), color = Np.fg, fontSize = (screenH * 0.036f).coerceIn(22.4f, 44.8f).sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.022).em, lineHeight = ((screenH * 0.036f).coerceIn(22.4f, 44.8f) * 1.12f).sp, textAlign = TextAlign.Center)
                            val artist = about.artist?.toString().orEmpty().ifEmpty { about.albumArtist?.toString().orEmpty() }
                            if (artist.isNotEmpty()) Text(
                                artist, color = Np.fg2, fontSize = (screenH * 0.021f).coerceIn(16f, 20.8f).sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                                modifier = Modifier.padding(top = 2.dp).clip(RoundedCornerShape(6.dp)).then(if (!books && library > 0) Modifier.clickable { nav.pop(); nav.push(Route.Artist(library, artist)) } else Modifier).padding(horizontal = 8.dp, vertical = 2.dp),
                            )
                        }
                        NpSeek(nav)
                        Transport(nav, books, playSize, small = false)
                        // The tools: speed (and the music-only chips to come).
                        FlowRow(Modifier.fillMaxWidth().padding(top = 2.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            NpChip(com.wittywilla.wittymediaclient.player.speedWords(listening.speed)) { menu = NpMenu.Speed }
                        }
                    }
                }
                if (panel) Transport(nav, books, 56.dp, small = true, Modifier.padding(top = 8.dp, bottom = maxOf(10.dp, inset)))
                else Spacer(Modifier.height(inset))
            }
        }
        when (menu) {
            NpMenu.Sleep -> {
                val set = listening.sleepAt != null || listening.sleepAfterThis
                val stopsAt = listening.sleepAt?.let { SimpleDateFormat("HH:mm", locale).format(Date(it)) }
                fun inMinutes(m: Int) = { listening.sleep(System.currentTimeMillis() + m * 60_000L, false) }
                PopMenu(
                    listOfNotNull(
                        if (set) MenuItem("Turn it off${stopsAt?.let { " (stops at $it)" } ?: ""}") { listening.sleep(null, false) } else null,
                        MenuItem("In 15 minutes", run = inMinutes(15)), MenuItem("In 30 minutes", run = inMinutes(30)), MenuItem("In 45 minutes", run = inMinutes(45)),
                        MenuItem("In 1 hour", run = inMinutes(60)), MenuItem("In 90 minutes", run = inMinutes(90)),
                        MenuItem(if (books) "At the end of this chapter" else "After this song", chosen = listening.sleepAfterThis) { listening.sleep(null, true) },
                    ),
                    Modifier.align(Alignment.TopEnd).padding(top = maxOf(14.dp, status) + 52.dp, end = 12.dp),
                ) { menu = NpMenu.None }
            }
            NpMenu.Speed -> PopMenu(
                listOf(0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f, 2.5f, 3f).filter { it <= maxSpeed }.map { s ->
                    MenuItem(com.wittywilla.wittymediaclient.player.speedWords(s), chosen = kotlin.math.abs(listening.speed - s) < 0.01f) { listening.chooseSpeed(s) }
                },
                Modifier.align(Alignment.BottomCenter).padding(bottom = 120.dp),
            ) { menu = NpMenu.None }
            NpMenu.More -> {
                val album = about.albumTitle?.toString().orEmpty()
                val artist = about.albumArtist?.toString().orEmpty().ifEmpty { about.artist?.toString().orEmpty() }
                PopMenu(
                    listOfNotNull(
                        if (!books && trackId > 0) MenuItem("Start a station from this song", NpIcons.Station) {
                            scope.launch {
                                val tracks = runCatching { nav.app.api.songRadio(trackId) }.getOrDefault(emptyList())
                                if (tracks.size >= 2) listening.play(tracks, Start(0), false)
                            }
                        } else null,
                        if (album.isNotEmpty() && library > 0) MenuItem(if (books) "Go to book" else "Go to album") { nav.pop(); nav.push(Route.Album(library, album, artist)) } else null,
                        if (!books && artist.isNotEmpty() && library > 0) MenuItem("Go to artist") { nav.pop(); nav.push(Route.Artist(library, artist)) } else null,
                        MenuItem("Stop and close", WebIcons.Close) { listening.stop(); nav.pop() },
                    ),
                    Modifier.align(Alignment.TopEnd).padding(top = maxOf(14.dp, status) + 52.dp, end = 12.dp),
                ) { menu = NpMenu.None }
            }
            NpMenu.Playlist -> PlaylistMenu(nav, trackId, Modifier.align(Alignment.TopEnd).padding(top = maxOf(14.dp, status) + 52.dp, end = 12.dp), { toast = it }) { menu = NpMenu.None }
            NpMenu.None -> {}
        }
        if (toast.isNotEmpty()) Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = 140.dp))
    }
}

// The seek bar and the times under it: white on white 28%, the elapsed and the whole length in 13 semibold.
@Composable
private fun NpSeek(nav: Nav) {
    val listening = nav.app.listening
    var place by remember { mutableStateOf(listening.positionSec()) }
    LaunchedEffect(listening.isPlaying, listening.now?.mediaId, listening.jumps) {
        place = listening.positionSec()
        while (listening.isPlaying) { kotlinx.coroutines.delay(500); place = listening.positionSec() }
    }
    val duration = listening.durationSec()
    Column(Modifier.fillMaxWidth().widthIn(max = 820.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalContentColor provides Color.White) {
            NpRange(if (duration > 0) (place / duration).toFloat() else 0f) { f -> listening.seekTo((f * duration).toInt().toDouble()); place = f * duration }
        }
        Row(Modifier.fillMaxWidth()) {
            Text(clock(place), color = Np.fg2, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(clock(duration), color = Np.fg2, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun NpRange(fraction: Float, seek: (Float) -> Unit) {
    var width by remember { mutableStateOf(1) }
    androidx.compose.foundation.Canvas(
        Modifier.fillMaxWidth().height(20.dp).onSizeChanged { width = it.width }
            .pointerInput(Unit) { detectTapGestures { seek((it.x / width).coerceIn(0f, 1f)) } }
            .pointerInput(Unit) { detectHorizontalDragGestures { change, _ -> seek((change.position.x / width).coerceIn(0f, 1f)) } },
    ) {
        val h = 4.dp.toPx(); val top = (size.height - h) / 2; val at = size.width * fraction.coerceIn(0f, 1f)
        drawRoundRect(Color.White.copy(alpha = 0.28f), androidx.compose.ui.geometry.Offset(0f, top), androidx.compose.ui.geometry.Size(size.width, h), androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()))
        drawRoundRect(Color.White, androidx.compose.ui.geometry.Offset(0f, top), androidx.compose.ui.geometry.Size(at, h), androidx.compose.ui.geometry.CornerRadius(2.dp.toPx()))
        drawCircle(Color(0x73000000), 7.dp.toPx(), androidx.compose.ui.geometry.Offset(at, size.height / 2 + 1.dp.toPx()))
        drawCircle(Color.White, 7.dp.toPx(), androidx.compose.ui.geometry.Offset(at, size.height / 2))
    }
}

// Shuffle, Previous, Play, Next and Repeat for music; Back 15, Previous, Play, Next and Forward 30 for books. 6 apart.
@Composable
private fun Transport(nav: Nav, books: Boolean, play: Dp, small: Boolean, modifier: Modifier = Modifier) {
    val listening = nav.app.listening
    val side = if (small) 44.dp else 46.dp
    val step = if (small) 48.dp else 56.dp
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        if (books) JumpRound(true, 15, "Back 15 seconds", side, 24.dp) { listening.seekBy(-15.0) }
        else NpRound(NpIcons.Shuffle, "Shuffle", side, 20.dp, on = listening.shuffle) { listening.toggleShuffle() }
        NpRound(WebIcons.Prev, "Previous", step, 28.dp) { listening.previous() }
        Pressable(listening::toggle, Modifier.size(play), shape = CircleShape, fill = Color.White, label = if (listening.isPlaying) "Pause" else "Play", pressScale = 0.96f, ring = false) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (listening.isPlaying) WebIcons.Pause else WebIcons.Play, null, tint = Color.Black, modifier = Modifier.size(36.dp)) }
        }
        NpRound(WebIcons.Next, "Next", step, 28.dp) { if (listening.canGoNext) listening.next() }
        if (books) JumpRound(false, 30, "Forward 30 seconds", side, 24.dp) { listening.seekBy(30.0) }
        else {
            val words = when (listening.repeat) { Player.REPEAT_MODE_ALL -> "Repeat all"; Player.REPEAT_MODE_ONE -> "Repeat this song"; else -> "Repeat off" }
            NpRound(if (listening.repeat == Player.REPEAT_MODE_ONE) NpIcons.RepeatOne else NpIcons.Repeat, words, side, 20.dp, on = listening.repeat != Player.REPEAT_MODE_OFF) { listening.cycleRepeat() }
        }
    }
}

// The queue, in place of the artwork: what's to come and how long, each row 56 high with its picture, title and artist,
// the current one tinted with the artwork's colour; Move down and Remove on each.
@Composable
private fun QueuePanel(nav: Nav, glow: Triple<Int, Int, Int>, modifier: Modifier, close: () -> Unit) {
    val listening = nav.app.listening
    val books = listening.keepsPlace
    val queue = listening.queue
    val current = queue.indexOfFirst { it.index == listening.nowIndex }
    val after = if (current >= 0) queue.drop(current + 1) else emptyList()
    val tint = Color(glow.first, glow.second, glow.third)
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Np.panel).border(1.dp, Np.line, RoundedCornerShape(20.dp))) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(if (books) "Chapters" else "Queue", color = Np.fg, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Text(if (after.isEmpty()) "Nothing after this" else "${after.size} to come · ${clock(after.sumOf { it.durationSec })}", color = Np.fg2, fontSize = 12.sp)
            }
            if (!books) Pressable({ after.indices.reversed().forEach { listening.remove(current + 1 + it) } }, Modifier.heightIn(min = 36.dp), shape = RoundedCornerShape(50), fill = Np.chip, label = "Clear what's to come", ring = false) {
                Box(Modifier.heightIn(min = 36.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) { Text("Clear what's to come", color = Np.fg, fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }
            }
            NpRound(WebIcons.Close, "Close", 36.dp, 18.dp, onClick = close)
        }
        LazyColumn(Modifier.weight(1f).padding(start = 8.dp, end = 8.dp, bottom = 10.dp)) {
            itemsIndexed(queue, key = { _, e -> "${e.index}-${e.mediaId}" }) { i, e ->
                val isNow = i == current
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(if (isNow) tint.copy(alpha = 0.24f) else Color.Transparent)
                        .clickable { listening.jumpTo(e.index) }.heightIn(min = 56.dp).padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(Modifier.size(44.dp).clip(RoundedCornerShape(6.dp)).background(Np.well)) { WebArt(e.artwork?.toString(), "", 44.dp, 1f, Modifier.fillMaxSize(), placeholderless = true) }
                    Column(Modifier.weight(1f)) {
                        Text(e.title, color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (e.artist.isNotEmpty()) Text(e.artist, color = Np.fg2, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (e.durationSec > 0) Text(clock(e.durationSec), color = Np.fg2, fontSize = 12.sp)
                    Pressable({ listening.move(e.index, e.index + 1) }, Modifier.size(36.dp), shape = CircleShape, fill = Color.Transparent, label = "Move down", ring = false) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(NpIcons.Down, null, tint = Np.fg, modifier = Modifier.size(18.dp)) }
                    }
                    Pressable({ listening.remove(e.index) }, Modifier.size(36.dp), shape = CircleShape, fill = Color.Transparent, label = "Remove", ring = false) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(WebIcons.Close, null, tint = Np.fg, modifier = Modifier.size(18.dp)) }
                    }
                }
            }
        }
    }
}

// Add to a playlist (web/src/audio/controls.tsx, PlaylistPicker): New playlist, then each of this person's own
// playlists; choosing one adds the song and says so. A new one is named in a field and made with "Make it".
@Composable
private fun PlaylistMenu(nav: Nav, trackId: Long, modifier: Modifier, said: (String) -> Unit, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    var lists by remember { mutableStateOf<List<com.wittywilla.wittymediaclient.net.Collection>?>(null) }
    var making by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { lists = runCatching { nav.app.api.collections().filter { it.kind == "manual" && it.system.isEmpty() } }.getOrDefault(emptyList()) }
    fun add(id: Long, called: String) = scope.launch {
        runCatching { nav.app.api.addToCollection(id, com.wittywilla.wittymediaclient.net.CollectionItems(listOf(trackId))) }
            .onSuccess { said("Added to $called"); close() }
            .onFailure { said(it.message ?: "Couldn't add it") }
    }
    if (making) {
        Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null, onClick = close)) {
            Row(
                modifier.widthIn(min = 220.dp, max = 340.dp).clip(RoundedCornerShape(14.dp)).background(Np.menu).border(1.dp, Np.line, RoundedCornerShape(14.dp)).padding(6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                WebInput(name, { name = it.take(120) }, "Name", Modifier.weight(1f))
                WebButton("Make it", {
                    val n = name.trim()
                    if (n.isNotEmpty()) scope.launch { runCatching { nav.app.api.newCollection(n) }.onSuccess { add(it.id, n) }.onFailure { said(it.message ?: "Couldn't make it") } }
                }, WebButtonKind.Primary, small = true)
            }
        }
        return
    }
    PopMenu(listOf(MenuItem("New playlist", WebIcons.Plus) { making = true }) + lists.orEmpty().map { c -> MenuItem(c.name) { add(c.id, c.name) } }, modifier) {
        if (!making) close()
    }
}
