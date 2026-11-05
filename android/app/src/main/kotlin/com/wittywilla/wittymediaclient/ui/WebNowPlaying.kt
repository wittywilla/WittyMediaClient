package com.wittywilla.wittymediaclient.ui

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// The website's Now Playing on a phone (web/src/audio/NowPlaying.tsx, nowplaying.css): black in every theme, with a glow
// coloured from the artwork, the artwork with its reflection, the title and artist, the seek bar, the transport and the
// tools; Sleep, Queue and More at the top. A panel (the queue) takes the artwork's place, above a smaller transport.
internal object Np {
    val fg = Color.White
    val fg2 = Color.White.copy(alpha = 0.72f)
    val fg3 = Color.White.copy(alpha = 0.62f)
    val chip = Color.White.copy(alpha = 0.10f)
    val chip2 = Color.White.copy(alpha = 0.18f)
    val line = Color.White.copy(alpha = 0.14f)
    val panel = Color(0xF0101014)
    val menu = Color(0xFF15151A)
    val well = Color(0xFF24242C)
    val loved = Color(0xFFFF6B81)
    val past = Color.White.copy(alpha = 0.42f)
    val rule = Color.White.copy(alpha = 0.08f)
    val plate = Color.Black.copy(alpha = 0.35f)
    val frame = Color.White.copy(alpha = 0.45f)
    val control = Color.White.copy(alpha = 0.40f)
    val ghost = Color.White.copy(alpha = 0.26f)
}

private fun webIconPath(name: String, path: String) = androidx.compose.ui.graphics.vector.ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
    .addPath(androidx.compose.ui.graphics.vector.addPathNodes(spacedArcs(path)), fill = androidx.compose.ui.graphics.SolidColor(Color.Black)).build()

// The audio player's own icons, the website's paths (web/src/icons.tsx, web/src/audio/icons.tsx).
internal object NpIcons {
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
    val Visualizer by lazy { webIconPath("visualizer", "M4 13h2.5v8H4zm4.5-8H11v16H8.5zm4.5 5h2.5v11H13zm4.5-7H20v18h-2.5z") }
    val Turtle by lazy { webIconPath("turtle", "M9 6a6 6 0 016 6v1h2.400l1.800-2.600A2.500 2.500 0 0123.500 12a2.500 2.500 0 01-2.500 2.500h-1l-1.500 2h1V19h-3v-2H9.500v2h-3v-2.200L3 15a1 1 0 011-2h-.5A1.500 1.500 0 012 11.500 5.500 5.500 0 019 6zm0 2a3.500 3.500 0 00-3.300 3H13a4 4 0 00-4-3z") }
    val Karaoke by lazy { webIconPath("karaoke", "M15.500 2a6.500 6.500 0 11-6.400 7.700L3.600 18l2.400 2.400 8.300-5.500A6.500 6.500 0 0115.500 2zm-4.300 5.900a4.500 4.500 0 004.900 4.900zm1.400-1.400l4.900 4.900a4.500 4.500 0 00-4.900-4.900z") }
    val ReadOpen by lazy { webIconPath("read-open", "M21 5c-1.100-.3-2.300-.5-3.500-.5-2 0-4.100.4-5.500 1.500-1.400-1.100-3.500-1.500-5.500-1.500S2.400 4.900 1 6v14.600c0 .3.300.5.500.5h.3c1.300-.7 3.200-1.100 4.700-1.100 2 0 4.100.4 5.500 1.500 1.300-.9 3.800-1.500 5.500-1.500 1.700 0 3.400.3 4.800 1.100h.2c.3 0 .5-.2.500-.5V6c-.6-.4-1.200-.7-2-1zm0 13.500c-1.100-.3-2.300-.5-3.500-.5-1.700 0-4.200.7-5.500 1.500V8c1.300-.8 3.800-1.500 5.500-1.500 1.200 0 2.400.2 3.500.5z") }
    val Sliders by lazy { webIconPath("sliders", "M5 3h2v9.200a3 3 0 010 5.600V21H5v-3.200a3 3 0 010-5.600zm0 12a1 1 0 102 0 1 1 0 00-2 0zm6-12h2v3.200a3 3 0 010 5.600V21h-2v-9.200a3 3 0 010-5.600zm0 6a1 1 0 102 0 1 1 0 00-2 0zm6-6h2v11.200a3 3 0 010 5.600V21h-2v-1.200a3 3 0 010-5.600zm0 14a1 1 0 102 0 1 1 0 00-2 0z") }
    val File by lazy { webIconPath("file", "M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6zm4 18H6V4h7v5h5v11z") }
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
internal fun NpRound(icon: ImageVector, label: String, size: Dp, iconSize: Dp, on: Boolean = false, tint: Color? = null, fill: Color = Np.chip, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Pressable(onClick, modifier.size(size), shape = CircleShape, fill = if (on) Np.fg else fill, label = label, selected = on, enabled = enabled, disabledAlpha = 0.4f, pressScale = 0.94f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = tint ?: if (on) Color.Black else Np.fg, modifier = Modifier.size(iconSize))
        }
    }
}

// The website's chip (`.np-chip`): a pill of white at 10%, 44 high and 16 inside, 14 semibold; white with black words
// when it's on. Small (`.np-chip.small`) is 36 high, 12 inside and 13.
@Composable
internal fun NpChip(words: String, on: Boolean = false, icon: ImageVector? = null, iconSize: Dp = 20.dp, small: Boolean = false, modifier: Modifier = Modifier, enabled: Boolean = true, label: String = words, after: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    val high = if (small) 36.dp else 44.dp
    Pressable(onClick, modifier.heightIn(min = high), shape = RoundedCornerShape(50), fill = if (on) Np.fg else Np.chip, label = label, selected = on, enabled = enabled, disabledAlpha = 0.45f, ring = false) {
        Row(Modifier.heightIn(min = high).padding(horizontal = if (small) 12.dp else 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (icon != null) Icon(icon, null, tint = if (on) Color.Black else Np.fg, modifier = Modifier.size(iconSize))
            Text(words, color = if (on) Color.Black else Np.fg, fontSize = if (small) 13.sp else 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            after?.invoke()
        }
    }
}

internal data class MenuItem(val words: String, val icon: ImageVector? = null, val chosen: Boolean = false, val note: Boolean = false, val rule: Boolean = false, val run: () -> Unit = {})

// Where something opens from a button, as the website's Pop places it: right-aligned to the button, 8 below it when it
// fits (or above it for `up`), else the other way, and 8 from the screen's edges. At least 220 wide, at most the
// screen less 16, and at most min(60% of the height, 460) high. A press outside closes it.
@Composable
internal fun PopAt(anchor: Rect?, close: () -> Unit, up: Boolean = false, minWidth: Dp = 220.dp, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null, onClick = close)) {
        Layout(
            content = {
                Column(
                    Modifier.widthIn(min = minWidth).cssShadow(10.dp, 30.dp, Color(0x73000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(Np.menu)
                        .border(1.dp, Np.line, RoundedCornerShape(14.dp))
                        // A press inside isn't one outside.
                        .clickable(remember { MutableInteractionSource() }, null) {}
                        .padding(6.dp).verticalScroll(rememberScrollState()),
                    content = content,
                )
            },
            modifier = Modifier.fillMaxSize(),
        ) { parts, constraints ->
            val room = 8.dp.roundToPx()
            val w = constraints.maxWidth
            val h = constraints.maxHeight
            val card = parts.first().measure(Constraints(maxWidth = (w - 2 * room).coerceAtLeast(0), maxHeight = minOf((h * 0.6f).toInt(), 460.dp.roundToPx())))
            layout(w, h) {
                val b = anchor ?: Rect(w / 2f + card.width / 2f, h / 2f - card.height / 2f - room, w / 2f + card.width / 2f, h / 2f - card.height / 2f - room)
                val left = (b.right.toInt() - card.width).coerceIn(room, (w - card.width - room).coerceAtLeast(room))
                val below = b.bottom.toInt() + room
                val above = b.top.toInt() - card.height - room
                val fitsBelow = below + card.height <= h - room
                val top = if (up) (if (above >= room) above else below) else if (fitsBelow) below else maxOf(room, above)
                card.place(left, top)
            }
        }
    }
}

// The website's pop menu (`.mp-menu`): rows 44 high, 12 inside, 10 between an icon and the words, 14; a chosen one bold
// with a tick before it; notes in 12 at 72%, and rules.
@Composable
internal fun PopMenu(items: List<MenuItem>, anchor: Rect?, up: Boolean = false, minWidth: Dp = 220.dp, close: () -> Unit) {
    PopAt(anchor, close, up, minWidth) { MenuRows(items, close) }
}

@Composable
internal fun MenuRows(items: List<MenuItem>, close: () -> Unit) {
    items.forEach { item ->
        when {
            item.rule -> Box(Modifier.padding(horizontal = 8.dp, vertical = 4.dp).fillMaxWidth().height(1.dp).background(Np.line))
            item.note -> Text(item.words, color = Np.fg2, fontSize = 12.sp, lineHeight = 1.45.em, modifier = Modifier.widthIn(max = 260.dp).padding(horizontal = 12.dp, vertical = 6.dp))
            else -> Pressable({ item.run(); close() }, Modifier.fillMaxWidth().heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = item.words, selected = item.chosen, ring = false) {
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (item.chosen) Text("✓", color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                    if (item.icon != null) Icon(item.icon, null, tint = Np.fg, modifier = Modifier.size(18.dp))
                    Text(item.words, color = Np.fg, fontSize = 14.sp, fontWeight = if (item.chosen) FontWeight.Bold else FontWeight.Normal, maxLines = 1)
                }
            }
        }
    }
}

// Something said to a screen reader as it changes, as the website's `aria-live` line.
@Composable
internal fun Spoken(words: String) {
    Box(Modifier.size(1.dp).semantics { liveRegion = LiveRegionMode.Polite; contentDescription = words })
}

internal enum class NpPanel { None, Queue, Lyrics, Sound, Read }

private enum class NpMenu { None, Playlist, Sleep, More, Speed, Shuffle, Volume, SaveQueue }

// The visualizer's choices are saved one after another, as the website chains them, so the last one wins.
private val vizSaving = Mutex()

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
    val api = nav.app.api
    val about = now.mediaMetadata
    val books = listening.keepsPlace
    val music = !books
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
    LaunchedEffect(library) { if (!books && library > 0) liked = runCatching { api.likes(library).toSet() }.getOrDefault(emptySet()) }
    var panel by remember { mutableStateOf(if (listening.screenWithQueue) NpPanel.Queue else NpPanel.None) }
    var menu by remember { mutableStateOf(NpMenu.None) }
    val anchors = remember { mutableStateMapOf<NpMenu, Rect>() }
    var origin by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    fun Modifier.anchor(key: NpMenu) = onGloballyPositioned { anchors[key] = it.boundsInRoot() }
    fun at(key: NpMenu): Rect? = anchors[key]?.translate(-origin)
    var toast by remember { mutableStateOf("") }
    var said by remember { mutableStateOf("") }
    var maxSpeed by remember { mutableStateOf(4.0) }
    // The visualizer: whether the server has it, and this person's choices.
    var vizHere by remember { mutableStateOf(true) }
    var viz by remember { mutableStateOf(VisualizerPrefs()) }
    var vizLoaded by remember { mutableStateOf(false) }
    // What Styles is showing now, while it changes by itself.
    var shownStyle by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        val wantsViz = listening.screenWithVisualizer
        listening.screenWithQueue = false
        listening.screenWithVisualizer = false
        val prefs = runCatching { api.playerPrefs() }.getOrNull()
        maxSpeed = prefs?.maxSpeed ?: 4.0
        vizHere = prefs?.visualizer != false
        runCatching { VisualizerPrefs.read(api.musicPlayerChoice()) }.getOrNull()?.let { viz = if (wantsViz) it.copy(viz = true) else it }
        vizLoaded = true
    }
    fun setViz(change: (VisualizerPrefs) -> VisualizerPrefs) {
        val next = change(viz)
        viz = next
        nav.app.scope.launch { vizSaving.withLock { runCatching { api.saveMusicPlayerChoice(next.toJson()) } } }
    }
    // Styles: only ever because someone chose it, among the player's own styles.
    LaunchedEffect(viz.viz, viz.shuffleEvery, viz.style) {
        shownStyle = ""
        if (!viz.viz || viz.shuffleEvery <= 0) return@LaunchedEffect
        while (true) {
            delay(viz.shuffleEvery * 1000L)
            val current = shownStyle.ifEmpty { viz.nativeStyle }
            shownStyle = VisualizerPrefs.STYLES.map { it.first }.filter { it != current }.random()
        }
    }
    val style = shownStyle.ifEmpty { viz.nativeStyle }
    fun pickStyle(id: String, name: String) {
        shownStyle = ""
        setViz { it.copy(style = id, viz = true) }
        said = "Visualizer: $name"
    }
    // Opening: a fade and a 16 rise over 240 ms.
    val rise = remember { Animatable(0f) }
    LaunchedEffect(Unit) { rise.animateTo(1f, tween(240, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) }
    val status = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
    val inset = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    val screenH = LocalConfiguration.current.screenHeightDp
    val screenW = LocalConfiguration.current.screenWidthDp
    // The website's breakpoints: one column up to 860, and a phone's top bar up to 480.
    val compact = screenW <= 860
    val phone = screenW <= 480
    val locale = androidx.core.os.ConfigurationCompat.getLocales(LocalConfiguration.current)[0] ?: Locale.ROOT
    val tint = Color(glow.first, glow.second, glow.third)
    fun toggle(chosen: NpMenu) { menu = if (menu == chosen) NpMenu.None else chosen }
    fun togglePanel(chosen: NpPanel) { panel = if (panel == chosen) NpPanel.None else chosen }
    // The words, shared by Lyrics, Read and karaoke, and only asked for while one of them is open. Music only.
    val words = remember { LyricsWords(listening, { nav.app.api }, scope, nav.app.scope) }
    var karaoke by remember { mutableStateOf(false) }
    val lyricsWanted = music && (panel == NpPanel.Lyrics || panel == NpPanel.Read || karaoke)
    LaunchedEffect(trackId, lyricsWanted) { words.want(trackId, lyricsWanted) }
    LaunchedEffect(music) {
        if (!music && (panel == NpPanel.Lyrics || panel == NpPanel.Read)) panel = NpPanel.None
        if (!music) karaoke = false
    }
    val title = about.title?.toString().orEmpty()
    val artistName = about.artist?.toString().orEmpty().ifEmpty { about.albumArtist?.toString().orEmpty() }
    val runtime = (about.durationMs ?: 0L) / 1000.0
    // A song's music video, the first it's tied to, to go to at the same place: music only.
    var video by remember { mutableStateOf<com.wittywilla.wittymediaclient.net.MusicLink?>(null) }
    LaunchedEffect(trackId, music) {
        video = null
        if (music && trackId > 0) video = runCatching { api.musicLinks(trackId).tied.firstOrNull() }.getOrNull()
    }
    // On its page, as the website's, from here when the two line up. The song stops there.
    fun watchVideo() {
        val tied = video ?: return
        val path = MusicVideos.watchPath(tied, listening.positionSec())
        if (listening.isPlaying) listening.toggle()
        nav.pop()
        nav.push(Route.Page(path))
    }
    // What's playing, over where it's from, in the top bar of a tablet.
    var libraryType by remember(library) { mutableStateOf("") }
    LaunchedEffect(library) { if (library > 0) libraryType = nav.libraryType(library) }
    val kind = if (!books) "Now playing" else if (libraryType == "podcasts") "Podcast" else "Audiobook"
    // What came with the album, for Read.
    var extras by remember { mutableStateOf(emptyList<com.wittywilla.wittymediaclient.net.Extra>()) }
    LaunchedEffect(trackId, music) {
        extras = emptyList()
        if (music && trackId > 0) extras = runCatching { api.extras(trackId) }.getOrDefault(emptyList())
    }

    Box(
        Modifier.fillMaxSize().background(Color.Black).onGloballyPositioned { origin = it.boundsInRoot().topLeft }
            .graphicsLayer { alpha = rise.value; translationY = (1 - rise.value) * 16.dp.toPx() }
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
        // Behind everything but the glow: the visualizer, when the server has it and it's on.
        if (vizHere && vizLoaded && viz.viz) VisualizerBackground(style, viz.slow, tint, listening.isPlaying)
        Column(Modifier.fillMaxSize()) {
            // The top bar: Close at the start; the volume (not on a phone, which has its own), Add to a playlist,
            // Sleep, Queue, Like and More at the end. Between them on a tablet, what's playing and from where.
            val place: @Composable (Modifier) -> Unit = { m ->
                Column(m.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(kind, color = Np.fg2, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(about.albumTitle?.toString().orEmpty().ifEmpty { artistName }, color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            val topSide = if (compact) 12.dp else (screenW * 0.02f).coerceIn(12f, 24f).dp
            Box(Modifier.fillMaxWidth().padding(start = topSide, end = topSide, top = maxOf(14.dp, status), bottom = 4.dp), contentAlignment = Alignment.Center) {
                if (!compact) place(Modifier.widthIn(max = (screenW * 0.46f).dp))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NpRound(NpIcons.Down, "Close the full player", 44.dp, 20.dp) { nav.pop() }
                    if (compact && !phone) place(Modifier.weight(1f)) else Spacer(Modifier.weight(1f))
                    Row(horizontalArrangement = Arrangement.spacedBy(if (phone) 2.dp else if (compact) 4.dp else 6.dp)) {
                        if (!phone) {
                            val silent = listening.sound.muted || listening.sound.volume == 0.0
                            NpRound(if (silent) WebIcons.Mute else WebIcons.Volume, "Volume", 44.dp, 20.dp, on = menu == NpMenu.Volume, modifier = Modifier.anchor(NpMenu.Volume)) { toggle(NpMenu.Volume) }
                        }
                        if (trackId > 0) NpRound(NpIcons.AddList, "Add to a playlist", 44.dp, 20.dp, modifier = Modifier.anchor(NpMenu.Playlist)) { toggle(NpMenu.Playlist) }
                        val sleepSet = listening.sleepAt != null || listening.sleepAfterThis
                        NpRound(NpIcons.Moon, if (sleepSet) "Sleep timer: stops ${listening.sleepAt?.let { "at " + SimpleDateFormat("HH:mm", locale).format(Date(it)) } ?: "after this one"}" else "Sleep timer", 44.dp, 20.dp, on = sleepSet, modifier = Modifier.anchor(NpMenu.Sleep)) { toggle(NpMenu.Sleep) }
                        NpRound(if (books) WebIcons.Chapters else NpIcons.List, if (books) "Chapters" else "Queue", 44.dp, 20.dp, on = panel == NpPanel.Queue) { togglePanel(NpPanel.Queue) }
                        if (!books && library > 0) {
                            val on = trackId in liked
                            NpRound(if (on) NpIcons.HeartOn else NpIcons.Heart, if (on) "Remove from liked songs" else "Add to liked songs", 44.dp, 20.dp, tint = if (on) Np.loved else null) {
                                liked = if (on) liked - trackId else liked + trackId
                                scope.launch { runCatching { api.react(trackId, if (on) 0 else 1) }.onFailure { liked = if (on) liked + trackId else liked - trackId } }
                            }
                        }
                        NpRound(WebIcons.More, "More", 44.dp, 20.dp, modifier = Modifier.anchor(NpMenu.More)) { toggle(NpMenu.More) }
                    }
                }
            }
            // The website's sizes: a phone's buttons up to 480, a tablet's above; one column up to 860; and a low, wide
            // window keeps the artwork small and without its reflection.
            val lowWide = !compact && screenH <= 620
            val tall = if (phone) 46.dp else if (lowWide) 44.dp else 56.dp
            val taller = if (phone) 56.dp else if (lowWide) 50.dp else 66.dp
            val playSize = if (lowWide) 60.dp else (screenH * 0.10f).coerceIn(66f, 96f).dp
            val transportGap = (screenW * 0.012f).coerceIn(6f, 16f).dp
            val panelBox: @Composable (Modifier) -> Unit = { m ->
                // A panel (`.np-panel`): radius 20, on its own near-black, a hairline round it.
                Box(m.clip(RoundedCornerShape(20.dp)).background(Np.panel).border(1.dp, Np.line, RoundedCornerShape(20.dp))) {
                    when (panel) {
                        NpPanel.Queue -> QueuePanel(nav, glow, wide = !compact, anchor = Modifier.anchor(NpMenu.SaveQueue), saving = menu == NpMenu.SaveQueue, save = { toggle(NpMenu.SaveQueue) }, modifier = Modifier.fillMaxSize()) { panel = NpPanel.None }
                        NpPanel.Lyrics -> LyricsPanel(nav, words, trackId, title, artistName, runtime, { panel = NpPanel.None }) { toast = it }
                        NpPanel.Read -> ReadPanel(nav, trackId, extras, words) { panel = NpPanel.None }
                        NpPanel.Sound -> SoundPanel(nav) { panel = NpPanel.None }
                        else -> {}
                    }
                }
            }
            val main: @Composable (Modifier) -> Unit = { m ->
                Column(
                    m.verticalScroll(rememberScrollState()).padding(vertical = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy((screenH * 0.013f).coerceIn(6f, 16f).dp, Alignment.CenterVertically),
                ) {
                    val side = when {
                        compact -> minOf(screenW * 0.66f, screenH * 0.32f)
                        lowWide -> (screenH * 0.30f).coerceIn(110f, 220f)
                        else -> (screenH * 0.38f).coerceIn(150f, 440f)
                    }.dp
                    val reflection = (if (compact) (screenH * 0.044f).coerceIn(16f, 40f) else (screenH * 0.056f).coerceIn(26f, 64f)).dp
                    val below = if (compact) (screenH * 0.04f).coerceIn(16f, 36f).dp else if (lowWide) 8.dp else (screenH * 0.062f).coerceIn(30f, 72f).dp
                    Box(Modifier.padding(bottom = below)) {
                        Box(Modifier.size(side).cssShadow(16.dp, 60.dp, Color(0x8C000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(Np.well)) {
                            WebArt(art, about.albumTitle?.toString() ?: title, side, 1f, Modifier.fillMaxSize())
                        }
                        // The reflection: the artwork's foot, mirrored, fading from 34%.
                        if (art != null && !lowWide) Box(
                            Modifier.offset(y = side + 8.dp).size(side, reflection).clip(RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp))
                                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                                .drawWithContent { drawContent(); drawRect(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.34f), Color.Transparent)), blendMode = BlendMode.DstIn) },
                        ) {
                            WebArt(art, "", side, 1f, Modifier.size(side).graphicsLayer { scaleY = -1f }.offset(y = 0.dp), placeholderless = true)
                        }
                    }
                    Column(Modifier.widthIn(max = 760.dp).padding(horizontal = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(title, color = Np.fg, fontSize = (screenH * 0.036f).coerceIn(22.4f, 44.8f).sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.022).em, lineHeight = ((screenH * 0.036f).coerceIn(22.4f, 44.8f) * 1.12f).sp, textAlign = TextAlign.Center)
                        if (artistName.isNotEmpty()) Text(
                            artistName, color = Np.fg2, fontSize = (screenH * 0.021f).coerceIn(16f, 20.8f).sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                            modifier = Modifier.padding(top = 2.dp).clip(RoundedCornerShape(6.dp)).then(if (!books && library > 0) Modifier.clickable { nav.pop(); nav.push(Route.Artist(library, artistName)) } else Modifier).padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                        // Watch the video (`.np-video`): a chip 10 under the artist, 40 high, in 13.
                        if (video != null) Pressable(::watchVideo, Modifier.padding(top = 10.dp).heightIn(min = 40.dp), shape = RoundedCornerShape(50), fill = Np.chip, label = "Watch the video, from here when the two line up", ring = false) {
                            Row(Modifier.heightIn(min = 40.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(WebIcons.Play, null, tint = Np.fg, modifier = Modifier.size(16.dp))
                                Text("Watch the video", color = Np.fg, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                    NpSeek(nav)
                    Transport(nav, books, playSize, taller, tall, transportGap)
                    Tools(
                        compact, vizHere && vizLoaded, viz, style, tint, listening.speed,
                        setViz = ::setViz, pickStyle = ::pickStyle,
                        shuffleAnchor = Modifier.anchor(NpMenu.Shuffle), speedAnchor = Modifier.anchor(NpMenu.Speed),
                        shuffleOpen = menu == NpMenu.Shuffle, openShuffle = { toggle(NpMenu.Shuffle) }, openSpeed = { toggle(NpMenu.Speed) },
                    ) {
                        // The words' chips, for music.
                        if (music) {
                            NpChip("Lyrics", on = panel == NpPanel.Lyrics, icon = WebIcons.Mic) { togglePanel(NpPanel.Lyrics) }
                            NpChip("Karaoke", icon = NpIcons.Karaoke) { karaoke = true }
                            // How many things there are to read beside the album, in a white circle.
                            NpChip(
                                "Read", on = panel == NpPanel.Read, icon = NpIcons.ReadOpen, label = "Read the words, or the album's booklet" + if (extras.isNotEmpty()) ", ${extras.size}" else "",
                                after = if (extras.isEmpty()) null else {
                                    {
                                        Box(Modifier.heightIn(min = 20.dp).widthIn(min = 20.dp).clip(RoundedCornerShape(50)).background(Np.fg).padding(horizontal = 5.dp), contentAlignment = Alignment.Center) {
                                            Text("${extras.size}", color = Color.Black, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                                        }
                                    }
                                },
                            ) { togglePanel(NpPanel.Read) }
                        }
                    }
                }
            }
            if (compact) {
                // One column: a panel takes the place of the artwork, the title, the seek bar and the tools, above a
                // smaller transport.
                Column(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (panel != NpPanel.None) {
                        panelBox(Modifier.weight(1f).fillMaxWidth())
                        Transport(nav, books, 56.dp, 48.dp, 44.dp, transportGap, Modifier.padding(top = 4.dp, bottom = maxOf(10.dp, inset)))
                    } else {
                        main(Modifier.weight(1f).fillMaxWidth())
                        Spacer(Modifier.height(inset))
                    }
                }
            } else {
                // Wider, the panel sits beside the player.
                val gap = (screenW * 0.03f).coerceIn(16f, 40f).dp
                Row(Modifier.weight(1f).fillMaxWidth().padding(horizontal = gap), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    main(Modifier.weight(1f).fillMaxHeight().padding(bottom = inset))
                    if (panel != NpPanel.None) panelBox(Modifier.width((screenW * 0.42f).coerceIn(320f, 480f).dp).fillMaxHeight().padding(top = 4.dp, bottom = maxOf(8.dp, inset)))
                }
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
                    at(NpMenu.Sleep),
                ) { menu = NpMenu.None }
            }
            NpMenu.Speed -> PopMenu(
                listOf(0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f, 2.5f, 3f).filter { it <= maxSpeed }.map { s ->
                    MenuItem(com.wittywilla.wittymediaclient.player.speedWords(s), chosen = kotlin.math.abs(listening.speed - s) < 0.01f) { listening.chooseSpeed(s) }
                },
                at(NpMenu.Speed), up = true,
            ) { menu = NpMenu.None }
            NpMenu.Shuffle -> PopMenu(
                listOf(MenuItem("Change style by itself. It stays still unless you choose this.", note = true)) +
                    VisualizerPrefs.SHUFFLE_CHOICES.map { every -> MenuItem(VisualizerPrefs.everyWords(every), chosen = viz.shuffleEvery == every) { setViz { it.copy(shuffleEvery = every) } } },
                at(NpMenu.Shuffle), up = true, minWidth = 240.dp,
            ) { menu = NpMenu.None }
            NpMenu.More -> {
                val album = about.albumTitle?.toString().orEmpty()
                val artist = about.albumArtist?.toString().orEmpty().ifEmpty { about.artist?.toString().orEmpty() }
                PopMenu(
                    listOfNotNull(
                        MenuItem("Sound: equaliser and more", NpIcons.Sliders) { togglePanel(NpPanel.Sound) },
                        if (!books && trackId > 0) MenuItem("Start a station from this song", NpIcons.Station) {
                            scope.launch {
                                val tracks = runCatching { api.songRadio(trackId) }.getOrDefault(emptyList())
                                if (tracks.size >= 2) listening.play(tracks, Start(0), false)
                                else toast = "There isn't enough here yet to make a station from this song"
                            }
                        } else null,
                        if (album.isNotEmpty() && library > 0) MenuItem(if (books) "Go to book" else "Go to album") { nav.pop(); nav.push(Route.Album(library, album, artist)) } else null,
                        if (!books && artist.isNotEmpty() && library > 0) MenuItem("Go to artist") { nav.pop(); nav.push(Route.Artist(library, artist)) } else null,
                        if (video != null) MenuItem("Watch the video") { watchVideo() } else null,
                        MenuItem("Stop and close", WebIcons.Close) { listening.stop(); nav.pop() },
                    ),
                    at(NpMenu.More),
                ) { menu = NpMenu.None }
            }
            NpMenu.Playlist -> PlaylistMenu(nav, listOf(trackId), at(NpMenu.Playlist), { toast = it }) { menu = NpMenu.None }
            NpMenu.SaveQueue -> PlaylistMenu(nav, listening.queue.mapNotNull { it.mediaId.toLongOrNull() }, at(NpMenu.SaveQueue), { toast = it }) { menu = NpMenu.None }
            NpMenu.Volume -> PopAt(at(NpMenu.Volume), { menu = NpMenu.None }, minWidth = 240.dp) { VolumeCard(listening, onBlack = true) }
            else -> {}
        }
        if (karaoke) KaraokeScreen(nav, words, title, artistName, tint) { karaoke = false }
        if (toast.isNotEmpty()) Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = 140.dp))
        Spoken(said)
    }
}

// The tools under the transport (`.np-tools`), wrapping and centred, 6 apart on a phone and 8 wider. On a narrow screen
// the words come first, as they're what a thumb came here for: Lyrics, Karaoke and Read, then the visualizer's switch
// and its styles, then Slow, Styles and the speed. Wider, the visualizer's group comes first, a rule, then the words.
@Composable
private fun Tools(
    compact: Boolean, vizHere: Boolean, viz: VisualizerPrefs, style: String, tint: Color, speed: Float,
    setViz: ((VisualizerPrefs) -> VisualizerPrefs) -> Unit, pickStyle: (String, String) -> Unit,
    shuffleAnchor: Modifier, speedAnchor: Modifier, shuffleOpen: Boolean, openShuffle: () -> Unit, openSpeed: () -> Unit,
    words: @Composable () -> Unit = {},
) {
    val gap = if (compact) 6.dp else 8.dp
    FlowRow(
        Modifier.fillMaxWidth().padding(top = 2.dp, bottom = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(gap, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(gap),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        if (compact) words()
        if (vizHere) {
            // Easy to see: larger, with a word beside the icon, and lit with the artwork's colour when on.
            val on = viz.viz
            Pressable({ setViz { it.copy(viz = !it.viz) } }, Modifier.heightIn(min = if (compact) 44.dp else 48.dp), shape = RoundedCornerShape(50), fill = if (on) tint.copy(alpha = 0.45f) else Np.plate, label = "Visualizer", selected = on, ring = false) {
                Row(
                    Modifier.heightIn(min = if (compact) 44.dp else 48.dp).border(2.dp, if (on) Np.fg else Np.frame, RoundedCornerShape(50)).padding(horizontal = 18.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(NpIcons.Visualizer, null, tint = Np.fg, modifier = Modifier.size(22.dp))
                    Text("Visualizer", color = Np.fg, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            if (on) {
                // The styles: on white at 10%, 3 inside and 2 apart; sideways when there isn't room.
                Row(
                    Modifier.clip(RoundedCornerShape(50)).background(Np.chip).horizontalScroll(rememberScrollState()).padding(3.dp)
                        .semantics { contentDescription = "Visualizer style" },
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    VisualizerPrefs.STYLES.forEach { (id, name) ->
                        val chosen = style == id
                        Pressable({ pickStyle(id, name) }, Modifier.heightIn(min = 40.dp), shape = RoundedCornerShape(50), fill = if (chosen) Np.fg else Color.Transparent, label = name, selected = chosen, ring = false) {
                            Box(Modifier.heightIn(min = 40.dp).padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
                                Text(name, color = if (chosen) Color.Black else Np.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
        if (!compact) {
            if (vizHere && viz.viz) VizExtras(viz, setViz, shuffleAnchor, shuffleOpen, openShuffle)
            if (vizHere) Box(Modifier.padding(horizontal = 4.dp).size(1.dp, 30.dp).background(Np.line))
            words()
        }
        if (compact && vizHere && viz.viz) VizExtras(viz, setViz, shuffleAnchor, shuffleOpen, openShuffle)
        // The speed, as the website's select: 44 high, 10 inside, with its small arrow.
        Pressable(openSpeed, speedAnchor.heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = Np.chip, label = "Playback speed, ${com.wittywilla.wittymediaclient.player.speedWords(speed)}", ring = false) {
            Row(Modifier.heightIn(min = 44.dp).padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(com.wittywilla.wittymediaclient.player.speedWords(speed), color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                androidx.compose.foundation.Canvas(Modifier.size(10.dp, 5.dp)) {
                    drawPath(androidx.compose.ui.graphics.Path().apply { moveTo(0f, 0f); lineTo(size.width, 0f); lineTo(size.width / 2, size.height); close() }, Np.fg)
                }
            }
        }
    }
}

// Slow, and changing style by itself.
@Composable
private fun VizExtras(viz: VisualizerPrefs, setViz: ((VisualizerPrefs) -> VisualizerPrefs) -> Unit, shuffleAnchor: Modifier, shuffleOpen: Boolean, openShuffle: () -> Unit) {
    NpChip("Slow", on = viz.slow, icon = NpIcons.Turtle, label = "Slow: a slower, gentler pace") { setViz { it.copy(slow = !it.slow) } }
    NpChip(
        VisualizerPrefs.chipWords(viz.shuffleEvery), on = viz.shuffleEvery > 0 || shuffleOpen, icon = NpIcons.Shuffle, iconSize = 18.dp, modifier = shuffleAnchor,
        label = if (viz.shuffleEvery > 0) "Shuffling visualizers: ${VisualizerPrefs.everyWords(viz.shuffleEvery)}" else "Shuffle visualizers",
        onClick = openShuffle,
    )
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

// Shuffle, Previous, Play, Next and Repeat for music; Back 15, Previous, Play, Next and Forward 30 for books. `taller` is
// Previous and Next, `tall` the ones at the ends, `gap` between them all (clamp(6, 1.2vw, 16)).
@Composable
private fun Transport(nav: Nav, books: Boolean, play: Dp, taller: Dp, tall: Dp, gap: Dp, modifier: Modifier = Modifier) {
    val listening = nav.app.listening
    val glyph = if (taller >= 56.dp) 28.dp else 24.dp
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        if (books) JumpRound(true, 15, "Back 15 seconds", tall, 24.dp) { listening.seekBy(-15.0) }
        else NpRound(NpIcons.Shuffle, "Shuffle", tall, 20.dp, on = listening.shuffle) { listening.toggleShuffle() }
        NpRound(WebIcons.Prev, "Previous", taller, glyph) { listening.previous() }
        Pressable(listening::toggle, Modifier.size(play), shape = CircleShape, fill = Color.White, label = if (listening.isPlaying) "Pause" else "Play", pressScale = 0.96f, ring = false) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (listening.isPlaying) WebIcons.Pause else WebIcons.Play, null, tint = Color.Black, modifier = Modifier.size(36.dp)) }
        }
        NpRound(WebIcons.Next, "Next", taller, glyph) { if (listening.canGoNext) listening.next() }
        if (books) JumpRound(false, 30, "Forward 30 seconds", tall, 24.dp) { listening.seekBy(30.0) }
        else {
            val words = when (listening.repeat) { Player.REPEAT_MODE_ALL -> "Repeat all"; Player.REPEAT_MODE_ONE -> "Repeat this song"; else -> "Repeat off" }
            NpRound(if (listening.repeat == Player.REPEAT_MODE_ONE) NpIcons.RepeatOne else NpIcons.Repeat, words, tall, 20.dp, on = listening.repeat != Player.REPEAT_MODE_OFF) { listening.cycleRepeat() }
        }
    }
}

// The queue (`QueuePanel`): what's to come and how long, Save the queue as a playlist and Clear what's to come for
// music; each row 56 high with its picture, title and artist and the time, the current one tinted with the artwork's
// colour and its picture showing the playing bars; Move up (over 860 across), Move down and Remove on each. A tap on a
// row plays it. Moving isn't offered while the queue is shuffled, as the order on screen isn't the one in the queue.
@Composable
private fun QueuePanel(nav: Nav, glow: Triple<Int, Int, Int>, wide: Boolean, anchor: Modifier, saving: Boolean, save: () -> Unit, modifier: Modifier, close: () -> Unit) {
    val listening = nav.app.listening
    val books = listening.keepsPlace
    val heading = if (books) "Chapters" else "Queue"
    val queue = listening.queue
    val current = queue.indexOfFirst { it.index == listening.nowIndex }
    val after = if (current >= 0) queue.drop(current + 1) else emptyList()
    val tint = Color(glow.first, glow.second, glow.third)
    Column(modifier.fillMaxWidth()) {
        NpSideHead(heading, "Close the ${heading.lowercase(Locale.ROOT)}", close) {
            Text(if (after.isEmpty()) "Nothing after this" else "${after.size} to come · ${clock(after.sumOf { it.durationSec })}", color = Np.fg2, fontSize = 12.sp, maxLines = 1)
        }
        if (!books) Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NpRound(NpIcons.AddList, "Save the queue as a playlist", 44.dp, 20.dp, on = saving, modifier = anchor, onClick = save)
            NpChip("Clear what's to come", small = true, enabled = after.isNotEmpty()) { after.indices.reversed().forEach { listening.remove(after[it].index) } }
        }
        LazyColumn(Modifier.weight(1f).padding(start = 8.dp, end = 8.dp, bottom = 10.dp)) {
            itemsIndexed(queue, key = { _, e -> "${e.index}-${e.mediaId}" }) { i, e ->
                val isNow = i == current
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(if (isNow) tint.copy(alpha = 0.24f) else Color.Transparent), verticalAlignment = Alignment.CenterVertically) {
                    Row(
                        Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).clickable { listening.jumpTo(e.index) }.heightIn(min = 56.dp).padding(horizontal = 8.dp, vertical = 6.dp)
                            .semantics(mergeDescendants = true) { if (isNow) stateDescription = "Playing" },
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Box(Modifier.size(44.dp).clip(RoundedCornerShape(6.dp)).background(Np.well), contentAlignment = Alignment.Center) {
                            WebArt(e.artwork?.toString(), "", 44.dp, 1f, Modifier.fillMaxSize(), placeholderless = true)
                            if (isNow && listening.isPlaying) Box(Modifier.clip(RoundedCornerShape(6.dp)).background(Np.plate).padding(4.dp)) { PlayingBars(Color.White) }
                        }
                        Column(Modifier.weight(1f)) {
                            Text(e.title, color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (e.artist.isNotEmpty()) Text(e.artist, color = Np.fg2, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Text(clock(e.durationSec), color = Np.fg2, fontSize = 12.sp, style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"))
                    }
                    if (!listening.shuffle) {
                        if (wide) NpRound(WebIcons.Up, "Move ${e.title} up", 36.dp, 18.dp, fill = Color.Transparent, enabled = i > 0) { listening.move(e.index, e.index - 1) }
                        NpRound(NpIcons.Down, "Move ${e.title} down", 36.dp, 18.dp, fill = Color.Transparent, enabled = i < queue.lastIndex) { listening.move(e.index, e.index + 1) }
                    }
                    NpRound(WebIcons.Close, "Remove ${e.title} from the queue", 36.dp, 18.dp, fill = Color.Transparent) { listening.remove(e.index) }
                }
            }
        }
    }
}

// Add to a playlist (web/src/audio/controls.tsx, PlaylistPicker): New playlist, then each of this person's own
// playlists; choosing one adds the songs and says so. A new one is named in a field and made with "Make it".
@Composable
private fun PlaylistMenu(nav: Nav, ids: List<Long>, anchor: Rect?, said: (String) -> Unit, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    var lists by remember { mutableStateOf<List<com.wittywilla.wittymediaclient.net.Collection>?>(null) }
    var making by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { lists = runCatching { nav.app.api.collections().filter { it.kind == "manual" && it.system.isEmpty() } }.getOrDefault(emptyList()) }
    fun add(id: Long, called: String) = scope.launch {
        busy = true
        runCatching { nav.app.api.addToCollection(id, com.wittywilla.wittymediaclient.net.CollectionItems(ids)) }
            .onSuccess { said("Added to $called"); close() }
            .onFailure { said(it.message ?: "Couldn't add it") }
        busy = false
    }
    PopAt(anchor, close, minWidth = 240.dp) {
        if (making) {
            Column(Modifier.padding(6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                WebInput(name, { name = it.take(120) }, "Name", Modifier.fillMaxWidth())
                WebButton("Make it", {
                    val n = name.trim()
                    if (n.isNotEmpty()) scope.launch {
                        busy = true
                        runCatching { nav.app.api.newCollection(n) }.onSuccess { add(it.id, n) }.onFailure { said(it.message ?: "Couldn't make it"); busy = false }
                    }
                }, WebButtonKind.Primary, small = true, enabled = !busy && name.isNotBlank())
            }
        } else {
            MenuRows(listOf(MenuItem("New playlist", WebIcons.Plus) { making = true }), close = {})
            if (lists == null) Text("Loading…", color = Np.fg2, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
            MenuRows(lists.orEmpty().map { c -> MenuItem(c.name) { if (!busy) add(c.id, c.name) } }, close = {})
        }
    }
}
