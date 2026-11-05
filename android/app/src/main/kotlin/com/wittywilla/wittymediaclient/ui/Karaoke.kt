package com.wittywilla.wittymediaclient.ui

import android.app.Activity
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.wittywilla.wittymediaclient.net.lineIndex
import com.wittywilla.wittymediaclient.player.SoundShaping
import kotlinx.coroutines.delay

// Karaoke, as the website's (web/src/audio/Karaoke.tsx, nowplaying.css): big words that fill in as they're sung, a
// count-in before a line after a break, the next line waiting below, the voice turned down and the key moved to suit
// the singer. Over Now Playing, on its own near-black lit from the artwork. The iPhone has it in MusicPanels.swift.
@Composable
internal fun KaraokeScreen(nav: Nav, words: LyricsWords, title: String, artist: String, glow: Color, close: () -> Unit) {
    val listening = nav.app.listening
    val lyrics = words.lyrics
    val loading = words.loading || (lyrics == null && words.failed.isEmpty())
    val lines = lyrics?.timed.orEmpty()
    val offset = words.offset
    val screenH = LocalConfiguration.current.screenHeightDp.toFloat()
    val screenW = LocalConfiguration.current.screenWidthDp.toFloat()
    val compact = screenW <= 700
    val status = with(LocalDensity.current) { WindowInsets.statusBars.getTop(this).toDp() }
    val inset = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    val sound = listening.sound
    BackHandler(onBack = close)
    // Coming back, the voice and key are as they were: this was for the song, not for good. The screen too.
    val activity = androidx.activity.compose.LocalActivity.current
    var filled by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        onDispose {
            listening.setSound { it.copy(vocalCut = 0.0, keyShift = 0.0) }
            if (filled) activity?.let { showBars(it, true) }
        }
    }
    // Where the song is, a frame at a time, for the fill and the count-in.
    var ms by remember { mutableDoubleStateOf(listening.positionSec() * 1000 - offset) }
    LaunchedEffect(offset) {
        while (true) {
            withFrameNanos { }
            ms = listening.positionSec() * 1000 - offset
        }
    }
    // Whether there's a voice to take away at all, while it's trying to.
    var mono by remember { mutableStateOf(false) }
    LaunchedEffect(sound.vocalCut > 0) {
        mono = false
        while (sound.vocalCut > 0) {
            delay(1500)
            SoundShaping.nearlyMono()?.let { mono = it }
        }
    }
    val index = lineIndex(lines, ms)
    val now = lines.getOrNull(index)
    val next = lines.getOrNull(index + 1)
    fun goLine(by: Int) {
        val to = lines.getOrNull(maxOf(0, index + by)) ?: return
        listening.seekTo(maxOf(0.0, (to.t + offset) / 1000))
    }
    fun setKey(key: Double) = listening.setSound { it.copy(keyShift = key.coerceIn(-6.0, 6.0)) }
    // Coming in as Now Playing does: a fade and a 16 rise over 240 ms.
    val rise = remember { Animatable(0f) }
    LaunchedEffect(Unit) { rise.animateTo(1f, tween(240, easing = androidx.compose.animation.core.CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) }

    Box(
        Modifier.fillMaxSize().graphicsLayer { alpha = rise.value; translationY = (1 - rise.value) * 16.dp.toPx() }
            .background(Color(0xFF06060A)).clickable(remember { MutableInteractionSource() }, null) {}
            .drawBehind {
                // radial-gradient(80% 70% at 50% 40%, art/.28, transparent 80%)
                val rx = size.width * 0.8f
                val centre = androidx.compose.ui.geometry.Offset(size.width / 2, size.height * 0.4f)
                scale(1f, size.height * 0.7f / rx, centre) {
                    drawCircle(Brush.radialGradient(0f to glow.copy(alpha = 0.28f), 0.8f to Color.Transparent, center = centre, radius = rx), rx, centre)
                }
            }
            .semantics { contentDescription = "Karaoke: $title" },
    ) {
        Column(Modifier.fillMaxSize()) {
            // The song, Fill the screen and Leave.
            val side = (screenW * 0.03f).coerceIn(16f, 40f).dp
            Row(Modifier.fillMaxWidth().padding(start = side, end = side, top = maxOf(14.dp, status)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(title, color = Np.fg, fontSize = (screenH * 0.024f).coerceIn(16f, 24f).sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(artist, color = Np.fg2, fontSize = (screenH * 0.019f).coerceIn(14.4f, 19.2f).sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                NpRound(WebIcons.Full, if (filled) "Show the system's bars" else "Fill the screen", 44.dp, 20.dp, on = false) {
                    filled = !filled
                    activity?.let { showBars(it, !filled) }
                }
                NpRound(WebIcons.Close, "Leave karaoke", 44.dp, 20.dp, onClick = close)
            }
            // The stage: in the middle, (10, 3vh, 34) apart, (16, 5vw, 80) in from the sides.
            val big = (screenH * 0.074f).coerceIn(32f, 86.4f)
            val message = (screenH * 0.028f).coerceIn(17.6f, 32f)
            Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = (screenW * 0.05f).coerceIn(16f, 80f).dp), contentAlignment = Alignment.Center) {
                when {
                    lyrics == null || loading -> Text("Looking for the words…", color = Np.fg2, fontSize = message.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                    lines.isEmpty() -> Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            if (lyrics.plain.isNotEmpty()) "These words have no times, so they can't follow the music yet." else "No words for this song.",
                            color = Np.fg2, fontSize = message.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                        )
                        if (lyrics.plain.isNotEmpty()) Text(
                            lyrics.plain, color = Color.White, fontSize = 17.sp, lineHeight = 1.55.em, textAlign = TextAlign.Center,
                            modifier = Modifier.heightIn(max = (screenH * 0.38f).dp).verticalScroll(rememberScrollState()),
                        )
                        val sub = buildAnnotatedString {
                            append("A timed ")
                            withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(".lrc") }
                            append(" file beside the song gives karaoke what it needs, or use Lyrics, then Fix, then Tap along. ")
                            withLink(LinkAnnotation.Clickable("help", TextLinkStyles(SpanStyle(color = Np.fg, textDecoration = TextDecoration.Underline))) {
                                close()
                                nav.pop()
                                nav.push(Route.Help("/help/lyrics-karaoke#adding-your-own-lyrics"))
                            }) { append("How to add your own") }
                        }
                        Text(sub, color = Np.fg2, fontSize = 14.sp, lineHeight = 1.45.em, textAlign = TextAlign.Center)
                    }
                    else -> {
                        val count = com.wittywilla.wittymediaclient.ui.Karaoke.countIn(lines, ms)
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy((screenH * 0.03f).coerceIn(10f, 34f).dp, Alignment.CenterVertically)) {
                            if (index < 0 && (lines.firstOrNull()?.t ?: 0.0) > 5000) {
                                Text("Get ready…", color = Np.fg2, fontSize = message.sp, fontWeight = FontWeight.SemiBold)
                            }
                            // The line being sung, each word filling white as it's sung, over white at 34%.
                            Box(Modifier.fillMaxWidth().heightIn(min = (big * 1.14f * 2.3f).dp), contentAlignment = Alignment.Center) {
                                if (now != null && now.text.isNotEmpty()) {
                                    val timed = com.wittywilla.wittymediaclient.ui.Karaoke.words(now, next?.t)
                                    FlowRow(
                                        Modifier.clearAndSetSemantics { contentDescription = now.text },
                                        horizontalArrangement = Arrangement.Center, verticalArrangement = Arrangement.spacedBy(0.dp),
                                    ) {
                                        timed.forEach { word ->
                                            val fill = com.wittywilla.wittymediaclient.ui.Karaoke.fill(word, ms).toFloat()
                                            Text(
                                                word.text, fontSize = big.sp, fontWeight = FontWeight.ExtraBold, lineHeight = 1.14.em, letterSpacing = (-0.01).em,
                                                style = TextStyle(brush = Brush.horizontalGradient(0f to Color.White, fill to Color.White, fill to Color.White.copy(alpha = 0.34f), 1f to Color.White.copy(alpha = 0.34f))),
                                            )
                                        }
                                    }
                                } else {
                                    Text("♪", color = Np.fg3, fontSize = big.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.clearAndSetSemantics { })
                                }
                            }
                            val nextSize = (screenH * 0.034f).coerceIn(19.2f, 40f)
                            Text(next?.text ?: " ", color = Np.fg3, fontSize = nextSize.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.heightIn(min = (nextSize * 1.3f).dp))
                            Box(Modifier.size(1.dp).semantics { liveRegion = LiveRegionMode.Polite; contentDescription = now?.text.orEmpty() })
                        }
                        // The count-in: a ring at the top, each number popping in.
                        if (count > 0) CountIn(count, screenH, Modifier.align(Alignment.TopCenter).padding(top = (screenH * 0.05f).coerceIn(4f, 60f).dp))
                    }
                }
            }
            // The controls (`.kar-bar`): wrapping, in the middle, 8 apart.
            FlowRow(
                Modifier.fillMaxWidth().padding(horizontal = (screenW * 0.03f).coerceIn(12f, 40f).dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                NpRound(WebIcons.Prev, "Previous line", 52.dp, 20.dp) { goLine(-1) }
                Pressable(listening::toggle, Modifier.size(64.dp), shape = CircleShape, fill = Color.White, label = if (listening.isPlaying) "Pause" else "Play", pressScale = 0.96f, ring = false) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (listening.isPlaying) WebIcons.Pause else WebIcons.Play, null, tint = Color.Black, modifier = Modifier.size(30.dp)) }
                }
                NpRound(WebIcons.Next, "Next line", 52.dp, 20.dp) { goLine(1) }
                if (!compact) Box(Modifier.padding(horizontal = 4.dp).size(1.dp, 34.dp).background(Np.line))
                // The singer's voice: on, lower, lowest.
                Row(Modifier.clip(RoundedCornerShape(50)).background(Np.chip).padding(3.dp).semantics { contentDescription = "Singer's voice" }, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    com.wittywilla.wittymediaclient.ui.Karaoke.VOCALS.forEach { (cut, name) ->
                        val on = sound.vocalCut == cut
                        Pressable({ listening.setSound { it.copy(vocalCut = cut) } }, Modifier.heightIn(min = 46.dp), shape = RoundedCornerShape(50), fill = if (on) Color.White else Color.Transparent, label = name, selected = on, ring = false) {
                            Box(Modifier.heightIn(min = 46.dp).padding(horizontal = if (compact) 10.dp else 16.dp), contentAlignment = Alignment.Center) {
                                Text(name, color = if (on) Color.Black else Color.White, fontSize = if (compact) 13.sp else 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            }
                        }
                    }
                }
                Stepper(com.wittywilla.wittymediaclient.ui.Karaoke.keyWords(sound.keyShift), compact, "Key", "Lower key", sound.keyShift > -6, { setKey(sound.keyShift - 1) }, "Raise key", sound.keyShift < 6) { setKey(sound.keyShift + 1) }
                Stepper(com.wittywilla.wittymediaclient.ui.Karaoke.timingWords(offset), compact, "Timing of the words", "Words sooner", true, { words.setOffset(offset - 100) }, "Words later", true) { words.setOffset(offset + 100) }
            }
            val note = com.wittywilla.wittymediaclient.ui.Karaoke.note(mono, sound.vocalCut, sound.keyShift, lines.isNotEmpty(), now?.words?.isNotEmpty() == true)
            Text(
                note.ifEmpty { " " }, color = Np.fg2, fontSize = 13.sp, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().heightIn(min = 18.dp).padding(start = 16.dp, end = 16.dp, bottom = maxOf(10.dp, inset)),
            )
        }
    }
}

// A number in a ring, white on white at 12%, popping in from 1.18 and 40% over a second.
@Composable
private fun CountIn(count: Int, screenH: Float, modifier: Modifier) {
    val reduce = LocalReduceMotion.current
    val pop = remember(count) { Animatable(if (reduce) 1f else 0f) }
    LaunchedEffect(count) { if (!reduce) pop.animateTo(1f, tween(1000, easing = androidx.compose.animation.core.CubicBezierEasing(0f, 0f, 0.58f, 1f))) }
    val side = (screenH * 0.13f).coerceIn(64f, 130f).dp
    Box(
        modifier.size(side).graphicsLayer { val s = 1.18f - 0.18f * pop.value; scaleX = s; scaleY = s; alpha = 0.4f + 0.6f * pop.value }
            .clip(CircleShape).background(Color.White.copy(alpha = 0.12f)).border(3.dp, Color.White, CircleShape)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text("$count", color = Color.White, fontSize = (screenH * 0.074f).coerceIn(32f, 80f).sp, fontWeight = FontWeight.ExtraBold, style = TextStyle(fontFeatureSettings = "tnum"))
    }
}

// The key's and the words' steppers (`.kar-stepper`): − and + in 46 circles either side of what it is now.
@Composable
private fun Stepper(words: String, compact: Boolean, group: String, lower: String, canLower: Boolean, down: () -> Unit, raise: String, canRaise: Boolean, up: () -> Unit) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(Np.chip).padding(3.dp).semantics { contentDescription = group },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        @Composable
        fun Step(sign: String, label: String, enabled: Boolean, run: () -> Unit) {
            Pressable(run, Modifier.size(46.dp), shape = CircleShape, fill = Np.chip, label = label, enabled = enabled, disabledAlpha = 0.4f, ring = false) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(sign, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold) }
            }
        }
        Step("−", lower, canLower, down)
        Text(
            words, color = Color.White, fontSize = if (compact) 13.sp else 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
            style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.widthIn(min = if (compact) 74.dp else 92.dp).semantics { liveRegion = LiveRegionMode.Polite },
        )
        Step("+", raise, canRaise, up)
    }
}

// The system's bars, hidden while karaoke or Now Playing fills the screen, and back afterwards.
internal fun showBars(activity: Activity, show: Boolean) {
    val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
    if (show) controller.show(WindowInsetsCompat.Type.systemBars())
    else {
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }
}
