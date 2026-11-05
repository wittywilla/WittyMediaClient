package com.wittywilla.wittymediaclient.ui

import android.app.Activity
import android.util.TypedValue
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Track
import com.wittywilla.wittymediaclient.player.VideoSession
import com.wittywilla.wittymediaclient.player.ViewPrefs
import com.wittywilla.wittymediaclient.player.ViewPrefsStore
import com.wittywilla.wittymediaclient.player.clock
import kotlinx.coroutines.delay
import java.util.Locale

// The website's video player on a phone (web/src/player/VideoPlayer.tsx, Controls.tsx, player.css), control
// for control: a gradient bar at the top (Back, the title, Info, Next episode, Mini player), a gradient bar at
// the bottom (the time over the seek bar, then Play and the tools), tapping the picture to play or pause, and
// the controls fading after 3.5 s while it plays. The player always uses its own dark colours.
private object Dark {
    val fg = Color(0xFFF1F2F5)
    val fg2 = Color(0xFFB4B9C6)
    val fg3 = Color(0xFF949AA8)
    val bg = Color(0xFF0F1115)
    val bg2 = Color(0xFF171A21)
    val bg3 = Color(0xFF1F232C)
    val bg4 = Color(0xFF2A2F3A)
    val panel = Color(0xFA14161C) // rgb(20 22 28 / .98)
    val scenes = Color(0xFA0E0F13)
    val border = Color(0x1AFFFFFF)
    val borderStrong = Color(0x33FFFFFF)
    val controlLine = Color(0xFF7B808C)
    val scrim = Color(0xAD000000) // black 68%
}

private val TOP_GRADIENT = Brush.verticalGradient(listOf(Color(0xB8000000), Color.Transparent))
private const val FADE_MS = 240
private const val DOUBLE_TAP_MS = 300L

// The widths the website's player changes at: ≤560 compact, ≤700 no volume or labels, wider the full layout.
private enum class Fit { Compact, Narrow, Wide }

private enum class Open { None, Speed, Scenes, Settings, Audio, Subtitles, Info, Keys }

private fun Item.episodeWords(): String =
    if (season != null && episode != null) "S$season · E$episode${episodeEnd?.let { "–$it" } ?: ""}" else ""

// The line under the title: the show and episode, else the year, then how it plays once that's known.
private fun subLine(it: Item?, mode: String): String {
    val head = if (it == null) "" else listOfNotNull(it.showTitle?.ifEmpty { null }, it.episodeWords().ifEmpty { null }).joinToString(" · ").ifEmpty { it.year?.toString().orEmpty() }
    val words = when (mode) { "direct" -> "Direct play"; "remux" -> "Rewrapped"; "transcode" -> "Transcoding"; else -> "" }
    return listOf(head, words).filter { it.isNotEmpty() }.joinToString(" · ")
}

private fun speedWords(s: Double): String = if (s == 1.0) "Normal" else "${trimmed(s)}×"
private fun trimmed(s: Double): String = if (s == s.toLong().toDouble()) s.toLong().toString() else s.toString()
private val SPEEDS = listOf(0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 16.0)

private fun language(t: Track): String =
    t.languageName.ifEmpty { if (t.language.isEmpty()) "Unknown" else Locale.forLanguageTag(t.language).displayLanguage.ifEmpty { t.language } }

private fun fullScreen(view: android.view.View, on: Boolean) {
    val window = (view.context as? Activity)?.window ?: return
    val bars = WindowCompat.getInsetsController(window, view)
    bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    if (on) bars.hide(WindowInsetsCompat.Type.systemBars()) else bars.show(WindowInsetsCompat.Type.systemBars())
}

// The picture, with subtitles drawn as the website draws its cues: white on black 72%, 3.2% of the height
// (16 to 36), lifted three lines to clear the controls.
@OptIn(UnstableApi::class)
@Composable
fun VideoSurface(session: VideoSession, modifier: Modifier = Modifier, cover: Boolean = false, subtitles: Boolean = true) {
    val density = LocalDensity.current
    AndroidView(
        factory = { context ->
            PlayerView(context).apply {
                useController = false
                setShutterBackgroundColor(android.graphics.Color.BLACK)
                setBackgroundColor(android.graphics.Color.BLACK)
                subtitleView?.setStyle(
                    CaptionStyleCompat(
                        android.graphics.Color.WHITE, 0xB8000000.toInt(), android.graphics.Color.TRANSPARENT,
                        CaptionStyleCompat.EDGE_TYPE_NONE, android.graphics.Color.WHITE, null,
                    ),
                )
            }
        },
        update = { view ->
            view.player = session.player
            view.resizeMode = if (cover) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT
            view.subtitleView?.visibility = if (subtitles) android.view.View.VISIBLE else android.view.View.GONE
            val heightDp = with(density) { view.height.toDp().value }
            if (heightDp > 0) {
                val size = (heightDp * 0.032f).coerceIn(16f, 36f)
                view.subtitleView?.setFixedTextSize(TypedValue.COMPLEX_UNIT_DIP, size)
                view.subtitleView?.setBottomPaddingFraction((size * 1.2f * 3f / heightDp).coerceAtMost(0.3f))
            }
        },
        onRelease = { it.player = null },
        modifier = modifier,
    )
}

// The website's round icon button in the player: transparent, white, pressed to .94.
@Composable
private fun PlayerIcon(icon: ImageVector, label: String, size: Dp, iconSize: Dp, onClick: () -> Unit, on: Boolean = false) {
    Pressable(
        onClick, Modifier.size(size), shape = CircleShape, fill = if (on) Color(0x2EFFFFFF) else Color.Transparent,
        label = label, pressScale = 0.94f, ring = false,
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(iconSize))
        }
    }
}

// The website's small button (.btn.sm): radius 10, 44 high on a touch screen.
@Composable
private fun SmallButton(
    words: String?, icon: ImageVector?, label: String, onClick: () -> Unit,
    fill: Color = Dark.bg3, ink: Color = Dark.fg, border: Color = Color.Transparent,
    padding: Dp = 12.dp, minWidth: Dp = 0.dp, size: Int = 13,
) {
    Pressable(onClick, Modifier.height(44.dp).widthIn(min = minWidth), shape = RoundedCornerShape(10.dp), fill = fill, label = label, pressScale = 0.97f, ring = false) {
        Row(
            Modifier.fillMaxSize().border(1.dp, border, RoundedCornerShape(10.dp)).padding(horizontal = padding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        ) {
            if (icon != null) Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(16.dp))
            if (words != null) Text(words, color = ink, fontSize = size.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

@Composable
private fun Spinner(modifier: Modifier = Modifier, size: Dp = 28.dp) {
    val accent = MaterialTheme.colorScheme.primary
    val turn by rememberInfiniteTransition(label = "spin").animateFloat(0f, 360f, infiniteRepeatable(tween(800, easing = LinearEasing), RepeatMode.Restart), label = "turn")
    Canvas(modifier.size(size)) {
        val w = 3.dp.toPx()
        drawArc(Dark.bg4, 0f, 360f, false, topLeft = Offset(w / 2, w / 2), size = Size(this.size.width - w, this.size.height - w), style = Stroke(w))
        drawArc(accent, turn - 45f, 90f, false, topLeft = Offset(w / 2, w / 2), size = Size(this.size.width - w, this.size.height - w), style = Stroke(w))
    }
}

// The seek bar: 24 high, the bars 4 (6 while pressed), the rest at 26%, what's loaded at 34%, the played part in
// the accent, and a 2×6 mark at each scene after the first. A tap goes there; the website has no dragging.
@Composable
private fun SeekBar(session: VideoSession, marks: Boolean, modifier: Modifier = Modifier) {
    val accent = MaterialTheme.colorScheme.primary
    val duration = session.durationSec
    var width by remember { mutableIntStateOf(1) }
    var pressed by remember { mutableStateOf(false) }
    val chapters = session.stream?.chapters.orEmpty()
    Canvas(
        modifier
            .fillMaxWidth()
            .height(24.dp)
            .onSizeChanged { width = it.width }
            .semantics { contentDescription = "Position, ${clock(session.filmSec)} of ${clock(duration)}" }
            .pointerInput(duration) {
                detectTapGestures(
                    onPress = { pressed = true; tryAwaitRelease(); pressed = false },
                    onTap = { if (duration > 0) session.seekFilm(it.x / width * duration) },
                )
            },
    ) {
        val h = (if (pressed) 6 else 4).dp.toPx()
        val top = (size.height - h) / 2
        val r = CornerRadius(2.dp.toPx())
        fun bar(to: Double, colour: Color) {
            val w = (size.width * to.coerceIn(0.0, 1.0)).toFloat()
            if (w > 0) drawRoundRect(colour, Offset(0f, top), Size(w, h), r)
        }
        bar(1.0, Color(0x42FFFFFF))
        if (duration > 0) {
            bar(session.bufferedSec / duration, Color(0x57FFFFFF))
            bar(session.filmSec / duration, accent)
            if (marks) chapters.drop(1).forEach { c ->
                val x = (size.width * (c.start / duration)).toFloat()
                drawRect(Color(0xA6000000), Offset(x - 1.dp.toPx(), 9.dp.toPx()), Size(2.dp.toPx(), 6.dp.toPx()))
            }
        }
    }
}

@Composable
fun VideoPlayerScreen(nav: Nav, route: Route.Player) {
    val session = remember(route) { nav.attachVideo(route.id, if (route.startOver) 0.0 else null) }
    LaunchedEffect(session) { session.mini = false }
    val view = LocalView.current
    var full by remember { mutableStateOf(false) }
    DisposableEffect(full) {
        fullScreen(view, full)
        onDispose { if (full) fullScreen(view, false) }
    }
    var open by remember { mutableStateOf(Open.None) }
    // The controls: shown on any touch, and by playing or pausing; hidden after the chosen time while playing.
    var shown by remember { mutableStateOf(true) }
    var touched by remember { mutableLongStateOf(0L) }
    val hideAfter = session.prefs.hideAfter
    LaunchedEffect(touched, session.activity, session.playing, hideAfter, open) {
        shown = true
        if (hideAfter <= 0 || !session.playing || open == Open.Scenes) return@LaunchedEffect
        delay((hideAfter * 1000).toLong())
        if (session.playing) shown = false
    }
    var lastTap by remember { mutableLongStateOf(0L) }
    BackHandler { if (open != Open.None) open = Open.None else nav.minimizeVideo() }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent(PointerEventPass.Initial)
                        touched = System.nanoTime()
                    }
                }
            },
    ) {
        val fit = when { maxWidth <= 560.dp -> Fit.Compact; maxWidth <= 700.dp -> Fit.Narrow; else -> Fit.Wide }
        val stream = session.stream
        val item = session.item
        VideoSurface(
            session,
            Modifier.fillMaxSize().pointerInput(Unit) {
                // A tap plays or pauses; two quick taps also go full screen, as a double click does on the website.
                detectTapGestures(onTap = {
                    val now = System.currentTimeMillis()
                    session.playPause()
                    if (now - lastTap < DOUBLE_TAP_MS) { full = !full; lastTap = 0 } else lastTap = now
                })
            },
            cover = session.prefs.fit == "cover",
        )
        if (session.waiting && session.problem.isEmpty()) Spinner(Modifier.align(Alignment.Center))

        // The top bar.
        AnimatedVisibility(shown, enter = fadeIn(tween(FADE_MS)), exit = fadeOut(tween(FADE_MS)), modifier = Modifier.align(Alignment.TopStart)) {
            val compact = fit == Fit.Compact
            val top = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(TOP_GRADIENT)
                    .clickable(remember { MutableInteractionSource() }, null) {}
                    .padding(
                        start = if (compact) 10.dp else 20.dp, end = if (compact) 10.dp else 20.dp,
                        top = if (compact) maxOf(10.dp, top) else maxOf(16.dp, top), bottom = if (compact) 10.dp else 40.dp,
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(if (compact) 6.dp else 12.dp),
            ) {
                PlayerIcon(WebIcons.Back, "Back (keeps playing in the mini player)", 44.dp, 24.dp, nav::minimizeVideo)
                Column(Modifier.weight(1f)) {
                    Text(item?.title.orEmpty(), color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, letterSpacing = (-0.012).em, lineHeight = 19.sp)
                    Text(subLine(item, stream?.decision.orEmpty()), color = Dark.fg2, fontSize = if (compact) 12.sp else 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (stream != null) PlayerIcon(WebIcons.Info, "How this is playing", 44.dp, 24.dp, { open = Open.Info })
                session.nextId?.let { next ->
                    SmallButton(
                        if (fit == Fit.Wide) "Next episode" else null, WebIcons.Next, "Next episode", { nav.playVideoInstead(next) },
                        padding = if (fit == Fit.Wide) 12.dp else 9.dp, size = if (fit == Fit.Wide) 13 else 12,
                    )
                }
                PlayerIcon(WebIcons.Mini, "Mini player", 44.dp, 24.dp, nav::minimizeVideo)
            }
        }

        // Skip intro, the whole time the intro is on.
        val introStart = item?.introStart ?: 0.0
        val introEnd = item?.introEnd
        if (introEnd != null && session.filmSec >= introStart && session.filmSec < introEnd - 1 && session.problem.isEmpty()) {
            Pressable({ session.seekFilm(introEnd) }, Modifier.align(Alignment.BottomEnd).padding(end = 24.dp, bottom = 110.dp).height(44.dp), shape = RoundedCornerShape(10.dp), fill = Color.White, label = "Skip intro", ring = false) {
                Box(Modifier.padding(horizontal = 20.dp).fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("Skip intro ›", color = Color(0xFF111111), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        if (session.watchNextShown) WatchNextCard(nav, session, Modifier.align(Alignment.BottomEnd).padding(start = 16.dp, end = if (maxWidth < 352.dp) 16.dp else 24.dp, bottom = 110.dp))

        // The bottom bar.
        AnimatedVisibility(shown || open == Open.Scenes, enter = fadeIn(tween(FADE_MS)), exit = fadeOut(tween(FADE_MS)), modifier = Modifier.align(Alignment.BottomStart)) {
            BottomBar(session, fit, open, { open = if (open == it) Open.None else it }, full, { full = !full })
        }

        // The note about the connection.
        session.note?.let { note ->
            Box(
                Modifier.align(Alignment.TopCenter).padding(top = 84.dp, start = 16.dp, end = 16.dp).widthIn(max = 560.dp)
                    .cssShadow(10.dp, 30.dp, Color(0x73000000), 10.dp).clip(RoundedCornerShape(10.dp)).background(Dark.scrim)
                    .drawBehind { if (note.lost) drawRect(Color(0xFFE0A030), size = Size(3.dp.toPx(), size.height)) }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) { Text(note.text, color = Color.White, fontSize = 13.sp, lineHeight = 18.sp, textAlign = TextAlign.Center) }
        }

        if (session.problem.isNotEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    Modifier.padding(16.dp).widthIn(max = 420.dp).clip(RoundedCornerShape(14.dp)).background(Dark.scrim).padding(horizontal = 24.dp, vertical = 16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(session.problem, color = Dark.fg2, fontSize = 15.sp, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(10.dp))
                    SmallButton("Back", null, "Back", { nav.closeVideo() }, padding = 16.dp, size = 14)
                }
            }
        }

        when (open) {
            Open.Audio, Open.Subtitles -> TrackPicker(session, open == Open.Audio) { open = Open.None }
            Open.Settings -> ViewSettings(session, Modifier.align(Alignment.BottomEnd)) { open = Open.None }
            Open.Info -> InfoSheet(nav, session) { open = Open.None }
            Open.Keys -> KeysSheet { open = Open.None }
            else -> {}
        }
    }
}

@Composable
private fun BottomBar(session: VideoSession, fit: Fit, open: Open, toggle: (Open) -> Unit, full: Boolean, onFull: () -> Unit) {
    val compact = fit == Fit.Compact
    val wide = fit == Fit.Wide
    val stream = session.stream
    val bottom = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    val icon = if (compact) 36.dp else 44.dp
    val context = androidx.compose.ui.platform.LocalContext.current
    Box(Modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .background(Brush.verticalGradient(0f to Color.Transparent, 0.7f to Color(0xD1000000), 1f to Color(0xD1000000)))
                .clickable(remember { MutableInteractionSource() }, null) {}
                .padding(start = if (compact) 10.dp else 20.dp, end = if (compact) 10.dp else 20.dp, top = if (compact) 18.dp else 40.dp, bottom = maxOf(12.dp, bottom)),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            val time = "${clock(session.filmSec)} / ${clock(session.durationSec)}"
            if (session.prefs.seekBar) SeekBar(session, session.prefs.chapterMarks)
            Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (compact) 0.dp else 4.dp)) {
                PlayerIcon(if (session.playing) WebIcons.Pause else WebIcons.Play, if (session.playing) "Pause" else "Play", 44.dp, 32.dp, session::playPause)
                if (fit == Fit.Wide) {
                    var volume by remember { mutableFloatStateOf(session.player.volume) }
                    PlayerIcon(if (volume == 0f) WebIcons.Mute else WebIcons.Volume, if (volume == 0f) "Sound on" else "Mute", 44.dp, 24.dp, {
                        volume = if (volume == 0f) 1f else 0f
                        session.player.volume = volume
                    })
                    Slider(
                        volume, { volume = it; session.player.volume = it }, Modifier.width(88.dp).height(20.dp),
                        colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = MaterialTheme.colorScheme.primary, inactiveTrackColor = Color(0x47F1F2F5)),
                    )
                }
                if (!compact) Text(time, color = Dark.fg, fontSize = 13.sp, fontWeight = FontWeight.Medium, modifier = Modifier.padding(start = 8.dp).widthIn(min = if (wide) 110.dp else 0.dp), maxLines = 1)
                Spacer(Modifier.weight(1f))
                SmallButton("${trimmed(session.speed.toDouble())}×", null, "Playback speed", { toggle(Open.Speed) }, fill = Color(0x1AFFFFFF), padding = if (compact) 8.dp else 12.dp, minWidth = if (compact) 0.dp else 46.dp)
                if ((stream?.chapters?.size ?: 0) > 1) PlayerIcon(WebIcons.Chapters, "Scenes", icon, 24.dp, { toggle(Open.Scenes) }, on = open == Open.Scenes)
                if ((stream?.audio?.size ?: 0) > 1) PlayerIcon(WebIcons.Audio, "Audio & language", icon, 24.dp, { toggle(Open.Audio) })
                if ((stream?.subtitles?.size ?: 0) > 0) PlayerIcon(WebIcons.Subs, "Subtitles", icon, 24.dp, { toggle(Open.Subtitles) })
                val remote = session.prefs.remote
                SmallButton(
                    if (fit == Fit.Wide) "Remote" else null, WebIcons.Remote, "Remote",
                    { session.savePrefs(session.prefs.copy(remote = !remote), ViewPrefsStore.hasOwn(context, session.id)) },
                    fill = if (remote) MaterialTheme.colorScheme.primary else Dark.bg3, ink = if (remote) MaterialTheme.colorScheme.onPrimary else Dark.fg,
                )
                PlayerIcon(WebIcons.Settings, "Viewing settings", icon, 24.dp, { toggle(Open.Settings) })
                if (fit == Fit.Wide) {
                    Pressable({ toggle(Open.Keys) }, Modifier.size(44.dp), shape = CircleShape, fill = Color.Transparent, label = "Keyboard shortcuts", ring = false) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("?", color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Bold) }
                    }
                }
                PlayerIcon(WebIcons.Full, if (full) "Leave full screen" else "Full screen", icon, 24.dp, onFull)
            }
        }
        // On a narrow phone the time sits in the band above the seek bar.
        if (compact) Text(
            "${clock(session.filmSec)} / ${clock(session.durationSec)}", color = Dark.fg, fontSize = 11.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(start = 14.dp).height(18.dp).align(Alignment.TopStart), maxLines = 1, lineHeight = 18.sp,
        )
        if (open == Open.Speed) SpeedList(session, Modifier.align(Alignment.BottomEnd).padding(end = 20.dp, bottom = 64.dp)) { toggle(Open.Speed) }
        if (open == Open.Scenes) ScenesPanel(session, fit, Modifier.align(Alignment.BottomCenter)) { toggle(Open.Scenes) }
    }
}

// A floating panel in the player's colours: rgb(20 22 28 / .98), a hairline, radius 14, the e-3 shadow.
private fun Modifier.playerPanel(fill: Color = Dark.panel): Modifier =
    this.cssShadow(10.dp, 30.dp, Color(0x73000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(fill).border(1.dp, Dark.border, RoundedCornerShape(14.dp))

@Composable
private fun PanelHead(words: String) {
    Text(words.uppercase(), color = Dark.fg3, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em, modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 4.dp, bottom = 6.dp))
}

@Composable
private fun SpeedList(session: VideoSession, modifier: Modifier, close: () -> Unit) {
    val choices = SPEEDS.filter { it <= session.maxSpeed }
    Column(modifier.widthIn(min = 220.dp).heightIn(max = 420.dp).playerPanel().verticalScroll(rememberScrollState()).padding(8.dp)) {
        PanelHead("Playback speed")
        choices.forEach { s ->
            val chosen = session.speed.toDouble() == s
            Pressable({ session.changeSpeed(s.toFloat()); close() }, Modifier.fillMaxWidth().heightIn(min = 36.dp), shape = RoundedCornerShape(6.dp), fill = Color.Transparent, label = speedWords(s), selected = chosen, ring = false) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (s == 1.0) "Normal" else "${trimmed(s)}×", color = if (chosen) Color.White else Dark.fg2, fontSize = 14.sp, fontWeight = if (chosen) FontWeight.SemiBold else FontWeight.Normal, modifier = Modifier.weight(1f))
                    if (s > 4.0) Text("may be muted", color = Dark.fg3, fontSize = 11.sp)
                }
            }
        }
    }
}

@Composable
private fun ScenesPanel(session: VideoSession, fit: Fit, modifier: Modifier, close: () -> Unit) {
    val chapters = session.stream?.chapters.orEmpty()
    val current = chapters.indexOfLast { it.start <= session.filmSec + 0.5 }.coerceAtLeast(0)
    val narrow = fit != Fit.Wide
    val grid = rememberLazyGridState()
    LaunchedEffect(Unit) { grid.scrollToItem(current) }
    Column(
        modifier.padding(start = if (narrow) 8.dp else 20.dp, end = if (narrow) 8.dp else 20.dp, bottom = if (narrow) 64.dp else 70.dp)
            .fillMaxWidth().heightIn(max = 470.dp).playerPanel(Dark.scenes).padding(if (narrow) 12.dp else 14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Scenes", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text("${chapters.size} scenes", color = Dark.fg2, fontSize = 13.sp, modifier = Modifier.weight(1f))
            PlayerIcon(WebIcons.Close, "Close", 44.dp, 24.dp, close)
        }
        LazyVerticalGrid(
            if (narrow) GridCells.Fixed(2) else GridCells.Adaptive(168.dp), state = grid,
            horizontalArrangement = Arrangement.spacedBy(if (narrow) 10.dp else 14.dp), verticalArrangement = Arrangement.spacedBy(if (narrow) 10.dp else 12.dp),
        ) {
            itemsIndexed(chapters) { i, c ->
                val now = i == current
                Column {
                    Pressable({ session.seekFilm(c.start); close() }, Modifier.fillMaxWidth().aspectRatio(16f / 9f), shape = RoundedCornerShape(10.dp), fill = Color(0xFF22252C), label = c.title.ifEmpty { "Scene ${i + 1}" }, ring = false) {
                        Box(
                            Modifier.fillMaxSize().border(1.dp, Color(0x14FFFFFF), RoundedCornerShape(10.dp))
                                .then(if (now) Modifier.ringOutside(RoundedCornerShape(10.dp), Color.White, 2.dp, 2.dp) else Modifier),
                        ) {
                            Text("${i + 1}", color = Color(0x59FFFFFF), fontSize = 30.sp, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.Center))
                            Text(clock(c.start), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp).clip(RoundedCornerShape(4.dp)).background(Dark.scrim).padding(horizontal = 6.dp, vertical = 1.dp))
                            if (now) Text("Now playing", color = MaterialTheme.colorScheme.onPrimary, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.TopStart).padding(6.dp).clip(RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.primary).padding(horizontal = 6.dp, vertical = 1.dp))
                        }
                    }
                    Row(Modifier.padding(top = 6.dp)) {
                        Text("${i + 1}. ", color = Dark.fg3, fontSize = 13.sp, maxLines = 1)
                        Text(c.title.ifEmpty { "Scene ${i + 1}" }, color = if (now) Color.White else Dark.fg, fontSize = 13.sp, fontWeight = if (now) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

// The website's segmented choice: a bg-3 pill, the chosen one in text colour with page-coloured words.
@Composable
private fun <T> Segmented(options: List<Pair<T, String>>, chosen: T, choose: (T) -> Unit) {
    FlowRow(Modifier.clip(RoundedCornerShape(10.dp)).background(Dark.bg3), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        options.forEach { (value, words) ->
            val on = value == chosen
            Pressable({ choose(value) }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(8.dp), fill = if (on) Dark.fg else Color.Transparent, label = words, selected = on, ring = false) {
                Box(Modifier.heightIn(min = 44.dp).padding(horizontal = 9.dp, vertical = 5.dp), contentAlignment = Alignment.Center) {
                    Text(words, color = if (on) Dark.bg else Dark.fg2, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

// The website's switch: 44×24, the knob 18, grey off and accent on.
@Composable
private fun WebSwitch(on: Boolean, label: String, change: (Boolean) -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Pressable({ change(!on) }, Modifier.size(44.dp, 24.dp), shape = RoundedCornerShape(14.dp), fill = if (on) accent else Dark.controlLine, label = label, selected = on, ring = false) {
        Box(Modifier.fillMaxSize()) {
            Box(Modifier.offset(x = if (on) 23.dp else 3.dp, y = 3.dp).size(18.dp).clip(CircleShape).background(Color.White))
        }
    }
}

@Composable
private fun SettingRow(label: String, control: @Composable () -> Unit) {
    Row(
        Modifier.fillMaxWidth().drawBehind { drawRect(Dark.border, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx())) }.padding(vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, color = Dark.fg, fontSize = 14.sp, modifier = Modifier.weight(1f))
        control()
    }
}

@Composable
private fun ViewSettings(session: VideoSession, modifier: Modifier, close: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var own by remember { mutableStateOf(ViewPrefsStore.hasOwn(context, session.id)) }
    var streaming by remember { mutableStateOf(ViewPrefsStore.streaming(context)) }
    val p = session.prefs
    fun save(next: ViewPrefs) = session.savePrefs(next, own)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        Column(
            modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = 78.dp, start = 16.dp).widthIn(max = 380.dp).heightIn(max = maxHeight - 150.dp)
                .playerPanel().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Viewing settings", color = Dark.fg, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                PlayerIcon(WebIcons.Close, "Close", 44.dp, 24.dp, close)
            }
            SettingRow("Apply to") { Segmented(listOf(true to "This video", false to "Everything"), own) { own = it; session.savePrefs(session.prefs, it) } }
            SettingRow("Seek bar") { WebSwitch(p.seekBar, "Seek bar") { save(p.copy(seekBar = it)) } }
            SettingRow("Chapter marks") { WebSwitch(p.chapterMarks, "Chapter marks") { save(p.copy(chapterMarks = it)) } }
            SettingRow("Remote") { WebSwitch(p.remote, "Remote") { save(p.copy(remote = it)) } }
            SettingRow("Remote style") { Segmented(listOf("floating" to "Floating", "bar" to "In control bar"), p.remoteStyle) { save(p.copy(remoteStyle = it)) } }
            SettingRow("Hide controls after") { Segmented(listOf(2.0 to "2 s", 3.5 to "3.5 s", 6.0 to "6 s", 0.0 to "Never"), p.hideAfter) { save(p.copy(hideAfter = it)) } }
            SettingRow("Picture") { Segmented(listOf("contain" to "Fit", "cover" to "Fill screen"), p.fit) { save(p.copy(fit = it)) } }
            SettingRow("3D video") { Segmented(listOf("off" to "Off", "sbs" to "Side by side", "tab" to "Over-under"), p.stereo) { save(p.copy(stereo = it)) } }
            if (p.stereo != "off") SettingRow("Show 3D as") { Segmented(listOf("2d" to "2D (one eye)", "anaglyph" to "Red/cyan glasses"), p.stereoView) { save(p.copy(stereoView = it)) } }
            SettingRow("Streaming") {
                Segmented(listOf("auto" to "Server’s choice", "standard" to "Standard", "robust" to "Robust"), streaming) {
                    streaming = it
                    session.setStreaming(it)
                }
            }
            Text(if (own) "Saved for this video on this device." else "Saved for all videos on this device.", color = Dark.fg3, fontSize = 12.sp, modifier = Modifier.padding(top = 12.dp))
        }
    }
}

@Composable
private fun TrackPicker(session: VideoSession, audio: Boolean, close: () -> Unit) {
    val stream = session.stream ?: return
    data class Tile(val title: String, val sub: String, val detail: String, val chosen: Boolean, val pick: () -> Unit)
    val tiles = if (audio) {
        stream.audio.map { t ->
            Tile(language(t), t.title, listOf(t.codec.uppercase(Locale.ROOT), if (t.channels > 0) "${t.channels} ch" else "").filter { it.isNotEmpty() }.joinToString(" · "), t.index == stream.audioIndex) { session.chooseAudio(t.index) }
        }
    } else {
        val burned = stream.subtitleDelivery == "burn"
        listOf(Tile("Off", "", "", stream.subtitleIndex < 0) { session.chooseSubtitle(-1, false) }) + stream.subtitles.flatMap { t ->
            val styled = t.codec.lowercase(Locale.ROOT) in setOf("ass", "ssa")
            listOfNotNull(
                Tile(language(t), t.title, t.codec.uppercase(Locale.ROOT), t.index == stream.subtitleIndex && !(styled && burned)) { session.chooseSubtitle(t.index, false) },
                if (styled) Tile(language(t), "With its styling", "Drawn into the picture", t.index == stream.subtitleIndex && burned) { session.chooseSubtitle(t.index, true) } else null,
            )
        }
    }
    val accent = MaterialTheme.colorScheme.primary
    Box(
        Modifier.fillMaxSize().background(Color(0xD6000000)).clickable(remember { MutableInteractionSource() }, null, onClick = close).padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        BoxWithConstraints(Modifier.widthIn(max = 900.dp)) {
            val room = maxWidth
            Column(Modifier.verticalScroll(rememberScrollState()).clickable(remember { MutableInteractionSource() }, null) {}, horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if (audio) "Audio & language" else "Subtitles", color = Dark.fg, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em, modifier = Modifier.padding(bottom = 6.dp))
                val two = room <= 520.dp
                val gap = if (two) 10.dp else 16.dp
                val side = if (two) (room - gap) / 2 else 165.dp
                FlowRow(Modifier.padding(top = 18.dp, bottom = 22.dp), horizontalArrangement = Arrangement.spacedBy(gap, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(gap)) {
                    tiles.forEach { t ->
                        Pressable({ t.pick(); close() }, Modifier.size(side), shape = RoundedCornerShape(14.dp), fill = if (t.chosen) accent.copy(alpha = 0.22f) else Color(0x12FFFFFF), label = listOf(t.title, t.sub).filter { it.isNotEmpty() }.joinToString(", "), selected = t.chosen, ring = false) {
                            Box(Modifier.fillMaxSize().border(2.dp, if (t.chosen) accent else Dark.border, RoundedCornerShape(14.dp)).padding(12.dp)) {
                                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(t.title, color = Dark.fg, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, lineHeight = 20.sp, textAlign = TextAlign.Center)
                                    if (t.sub.isNotEmpty()) Text(t.sub, color = Dark.fg2, fontSize = 13.sp, textAlign = TextAlign.Center)
                                    if (t.detail.isNotEmpty()) Text(t.detail, color = Dark.fg3, fontSize = 12.sp, textAlign = TextAlign.Center)
                                }
                                if (t.chosen) Text("✓", color = Color.White, fontWeight = FontWeight.Bold, modifier = Modifier.align(Alignment.TopEnd).offset(y = (-2).dp))
                            }
                        }
                    }
                }
                SmallButton("Close", null, "Close", close, fill = Color.Transparent, border = Dark.borderStrong, minWidth = 140.dp, size = 14)
            }
        }
    }
}

@Composable
private fun WatchNextCard(nav: Nav, session: VideoSession, modifier: Modifier) {
    val next = session.next ?: return
    val head = when {
        session.countdown != null -> "Next episode in ${session.countdown}s"
        !session.recommended -> "Watch next"
        session.nextShow != null -> "Because you watched ${session.nextShow?.title?.ifEmpty { null } ?: session.item?.showTitle?.ifEmpty { null } ?: session.item?.title.orEmpty()}"
        else -> "You might also like"
    }
    val episode = next.showId != null
    Column(
        modifier.widthIn(max = 320.dp).fillMaxWidth().playerPanel().padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(head.uppercase(), color = Dark.fg3, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em)
        Row(
            Modifier.fillMaxWidth().clickable { nav.playVideoInstead(next.id) },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ServerImage(nav.app.api.posterUrl(next), 90.dp, if (episode) 16f / 9f else 2f / 3f, Modifier.width(90.dp).clip(RoundedCornerShape(6.dp)).background(Dark.bg3), placeholder = next.title)
            Column(Modifier.weight(1f)) {
                Text(session.nextShow?.title?.ifEmpty { null } ?: next.showTitle?.ifEmpty { null } ?: next.title, color = Dark.fg, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(if (episode) listOf(next.episodeWords(), next.title).filter { it.isNotEmpty() }.joinToString(" · ") else next.year?.toString().orEmpty(), color = Dark.fg3, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SmallButton("Play", WebIcons.Play, "Play", { nav.playVideoInstead(next.id) }, fill = MaterialTheme.colorScheme.primary, ink = MaterialTheme.colorScheme.onPrimary)
            SmallButton("Dismiss", null, "Dismiss", session::dismissNext, fill = Color.Transparent, border = Dark.borderStrong)
        }
    }
}

// A bottom sheet as the website's dialogs are on a phone: in the app's own colours, not the player's.
@Composable
private fun Sheet(title: String, close: () -> Unit, content: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val bottom = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    Box(Modifier.fillMaxSize().background(Color(0x99000000)).clickable(remember { MutableInteractionSource() }, null, onClick = close), contentAlignment = Alignment.BottomCenter) {
        Column(
            Modifier.fillMaxWidth().heightIn(max = 700.dp).clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)).background(scheme.surface)
                .clickable(remember { MutableInteractionSource() }, null) {}
                .verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 20.dp + bottom),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, color = scheme.onSurface, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Pressable(close, Modifier.size(44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "Close", ring = false) {
                    Box(Modifier.fillMaxSize().border(1.dp, scheme.outlineVariant, RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                        Icon(WebIcons.Close, contentDescription = null, tint = scheme.onSurface, modifier = Modifier.size(18.dp))
                    }
                }
            }
            content()
            Row(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalArrangement = Arrangement.End) {
                Pressable(close, Modifier.height(44.dp), shape = RoundedCornerShape(10.dp), fill = scheme.surfaceVariant, label = "Close", ring = false) {
                    Box(Modifier.padding(horizontal = 16.dp).fillMaxSize(), contentAlignment = Alignment.Center) { Text("Close", color = scheme.onSurface, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
                }
            }
        }
    }
}

@Composable
private fun InfoSheet(nav: Nav, session: VideoSession, close: () -> Unit) {
    val explain = session.stream?.explain
    val scheme = MaterialTheme.colorScheme
    val body = TextStyle(color = scheme.onSurface, fontSize = 15.sp, lineHeight = 23.sp)
    Sheet("How this is playing", close) {
        if (explain != null) {
            Text(explain.summary, style = body, modifier = Modifier.padding(top = 12.dp))
            Text(
                "What this means", style = body.copy(color = LocalExtraColours.current.accentText, textDecoration = TextDecoration.Underline),
                modifier = Modifier.clickable { close(); nav.minimizeVideo(); nav.push(Route.Help("/help/playing#quality-direct-play-and-converting")) },
            )
            val load = when (explain.load) { "none" -> "Nothing: your player does the work"; "light" -> "Very little"; "heavy" -> "A lot"; else -> "" }
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("The file" to explain.source, "Picture" to explain.picture, "Sound" to explain.sound, "Subtitles" to explain.subtitles, "Work for the server" to load, "Streaming" to explain.streaming)
                    .filter { it.second.isNotEmpty() }
                    .forEach { (term, value) ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(term, color = scheme.onSurfaceVariant, fontSize = 15.sp, modifier = Modifier.width(110.dp))
                            Text(value, style = body, modifier = Modifier.weight(1f))
                        }
                    }
            }
            if (session.notes.isNotEmpty()) {
                Text("What the player did", color = scheme.onSurface, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 14.dp, bottom = 6.dp))
                session.notes.forEach { Text("•  $it", style = body) }
            }
            if (explain.reasons.isNotEmpty()) {
                Text("Why it isn’t simpler", color = scheme.onSurface, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 14.dp, bottom = 6.dp))
                explain.reasons.forEach { Text("•  $it", style = body) }
            }
        }
        val stream = session.stream
        if (stream != null && stream.stereo.isNotEmpty()) {
            Text("This is a 3D film, stored with both eyes in one frame.", style = body, modifier = Modifier.padding(top = 14.dp))
            WittyButton(if (stream.flattened) "Show both eyes again" else "Show it in 2D", { session.flatten3d(!stream.flattened) }, Modifier.padding(top = 8.dp), kind = ButtonKind.Secondary)
        }
        if (stream != null && stream.videos.size > 1) {
            Text("This file holds ${stream.videos.size} video streams.", style = body, modifier = Modifier.padding(top = 14.dp))
            stream.videos.forEachIndexed { i, v ->
                WittyButton(
                    "${v.title.ifEmpty { "Stream ${i + 1}" }} · ${v.width}×${v.height}", { session.chooseVideo(v.index) }, Modifier.padding(top = 8.dp),
                    kind = if (v.index == stream.videoIndex) ButtonKind.Primary else ButtonKind.Secondary,
                )
            }
        }
    }
}

@Composable
private fun KeysSheet(close: () -> Unit) {
    val keys = listOf(
        "Space or K" to "Play or pause", "← and →" to "Back or forward 10 seconds", "↑ and ↓" to "Volume",
        "F" to "Full screen", "M" to "Mute", "R" to "Remote", "I" to "How this is playing", "< and >" to "Slower or faster",
        "?" to "This list", "Esc" to "Mini player",
    )
    Sheet("Keyboard shortcuts", close) {
        Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            keys.forEach { (key, what) ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(key, color = MaterialTheme.colorScheme.onSurface, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(110.dp))
                    Text(what, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
                }
            }
        }
    }
}

// The mini player dock (player.css, .player.mini): on a phone a 64-high bar 8 from the sides and 16 above the
// floating bar, the picture 114 wide at its start; Play or Pause, Expand and Stop. On a wide screen, a 16:9
// card in the bottom corner.
@Composable
fun VideoDock(nav: Nav, session: VideoSession, aboveBar: Dp, modifier: Modifier = Modifier) {
    LaunchedEffect(session) { session.mini = true }
    var lastTap by remember { mutableLongStateOf(0L) }
    val item = session.item
    BoxWithConstraints(modifier.fillMaxSize()) {
        if (maxWidth <= 700.dp) {
            Row(
                Modifier.align(Alignment.BottomCenter).padding(start = 8.dp, end = 8.dp, bottom = aboveBar).fillMaxWidth().height(64.dp)
                    .cssShadow(10.dp, 30.dp, Color(0x73000000), 10.dp).clip(RoundedCornerShape(10.dp)).background(Color.Black),
            ) {
                VideoSurface(
                    session,
                    Modifier.width(114.dp).height(64.dp).pointerInput(Unit) {
                        detectTapGestures(onTap = {
                            val now = System.currentTimeMillis()
                            if (now - lastTap < DOUBLE_TAP_MS) nav.expandVideo() else session.playPause()
                            lastTap = now
                        })
                    },
                    subtitles = false,
                )
                Row(
                    Modifier.weight(1f).fillMaxSize().background(Dark.bg2).padding(start = 8.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Column(Modifier.weight(1f).clickable(onClick = nav::expandVideo)) {
                        Text(item?.showTitle?.ifEmpty { null } ?: item?.title.orEmpty(), color = Dark.fg, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val second = if (item?.season != null) listOf(item.episodeWords(), item.title).filter { it.isNotEmpty() }.joinToString(" · ") else item?.year?.toString().orEmpty()
                        if (second.isNotEmpty()) Text(second, color = Dark.fg2, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    PlayerIcon(if (session.playing) WebIcons.Pause else WebIcons.Play, if (session.playing) "Pause" else "Play", 34.dp, 26.dp, session::playPause)
                    PlayerIcon(WebIcons.Expand, "Expand", 34.dp, 20.dp, nav::expandVideo)
                    PlayerIcon(WebIcons.Close, "Stop", 34.dp, 20.dp, nav::closeVideo)
                }
            }
        } else {
            val width = minOf(400.dp, maxWidth - 40.dp)
            Box(
                Modifier.align(Alignment.BottomEnd).padding(end = 20.dp, bottom = 20.dp).width(width).aspectRatio(16f / 9f)
                    .cssShadow(10.dp, 30.dp, Color(0x73000000), 10.dp).clip(RoundedCornerShape(10.dp)).background(Color.Black),
            ) {
                VideoSurface(session, Modifier.fillMaxSize().pointerInput(Unit) {
                    detectTapGestures(onTap = {
                        val now = System.currentTimeMillis()
                        if (now - lastTap < DOUBLE_TAP_MS) nav.expandVideo() else session.playPause()
                        lastTap = now
                    })
                }, subtitles = false)
                Column(
                    Modifier.align(Alignment.BottomStart).fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent, Color(0xD9000000))))
                        .padding(start = 8.dp, end = 8.dp, top = 26.dp, bottom = 6.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(item?.showTitle?.ifEmpty { null } ?: item?.title.orEmpty(), color = Dark.fg, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        PlayerIcon(WebIcons.Back, "Back 10 seconds", 34.dp, 20.dp, { session.seekFilm(session.filmSec - 10) })
                        PlayerIcon(if (session.playing) WebIcons.Pause else WebIcons.Play, if (session.playing) "Pause" else "Play", 34.dp, 26.dp, session::playPause)
                        val next = session.nextId
                        if (next != null) PlayerIcon(WebIcons.Next, "Next episode", 34.dp, 20.dp, { nav.playVideoInstead(next) }) else Spacer(Modifier.width(34.dp))
                        PlayerIcon(WebIcons.Expand, "Expand", 34.dp, 20.dp, nav::expandVideo)
                        Spacer(Modifier.weight(1f))
                        PlayerIcon(WebIcons.Close, "Stop", 34.dp, 20.dp, nav::closeVideo)
                    }
                }
            }
        }
    }
}
