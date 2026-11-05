package com.wittywilla.wittymediaclient.tv

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.TvShape
import com.wittywilla.wittymediaclient.net.Tuned
import com.wittywilla.wittymediaclient.net.guidePage
import com.wittywilla.wittymediaclient.net.lineup
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.uniqueChannels
import com.wittywilla.wittymediaclient.ui.LocalExtraColours
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Route
import com.wittywilla.wittymediaclient.ui.Spinner
import com.wittywilla.wittymediaclient.ui.TvRoute
import com.wittywilla.wittymediaclient.ui.TvScreen
import com.wittywilla.wittymediaclient.ui.label
import com.wittywilla.wittymediaclient.ui.section
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

// Watching a channel, as the server's page does it (web/src/pages/tv/TvPlayer.tsx and MiniGuide.tsx) and Apple TV's
// ChannelPlayer, in the account's WittyTV look: the banner that drops in on every change of channel, and the mini guide
// over the picture. Up and down change channel; Select brings up the mini guide, where up and down move and Select
// tunes; left and right go back and on in what the server keeps of the channel; Play/Pause pauses; Back closes the mini
// guide, then goes back to the guide.

// Where things sit over the picture: Apple TV's safe area (80 at the sides, 60 at the bottom) and the player's own room.
private const val SIDE = 80 + 77
private const val BOTTOM = 60 + 92

@Composable
fun ChannelScreen(nav: Nav, start: String) {
    val api = nav.app.api
    val context = LocalContext.current
    val view = LocalView.current
    LiveTv.use(context)
    remember { GuideRules.timeFormat = android.text.format.DateFormat.getTimeFormat(context); 0 }
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    val appColours = tvAppColours(MaterialTheme.colorScheme, LocalExtraColours.current)
    LaunchedEffect(appColours) { TvLookStore.follow(appColours) }
    val dress = rememberDress(TvLookStore.look)
    var key by remember { mutableStateOf(start) }
    var banner by remember { mutableStateOf(true) }
    var mini by remember { mutableStateOf(false) }
    var lineup by remember { mutableStateOf<List<GuideChannel>>(emptyList()) }
    var bannerShown by remember { mutableIntStateOf(0) }
    var now by remember { mutableLongStateOf(nowSeconds()) }
    val screen = remember { FocusRequester() }
    val channel = lineup.firstOrNull { it.key == key } ?: TvChannels.list.firstOrNull { it.key == key }

    fun showBanner() {
        banner = true
        bannerShown++
    }

    fun closeMini() {
        mini = false
    }

    fun tune(next: String) {
        closeMini()
        if (next == key) return
        key = next
        GuideReturn.key = next
        LastChannel.remember(context, next)
        LiveTv.watch(next, api)
        showBanner()
    }

    fun step(by: Int) {
        val list = lineup.ifEmpty { TvChannels.list }
        val next = GuideRules.channel(key, by, list) ?: return
        if (next.key != key) tune(next.key)
    }

    // Back to the guide this came from, or to one in this player's place: leaving a guide opened from here mustn't lead
    // back into the player, or Back could never get out.
    fun toGuide() {
        val below = nav.stack.dropLast(1)
        if (below.any { it == Route.LiveTv || (it is TvRoute && it.screen == TvScreen.Guide) }) nav.pop()
        else nav.replace(TvRoute(TvScreen.Guide))
    }

    LaunchedEffect(Unit) {
        GuideReturn.key = key
        LiveTv.muted = false
        LiveTv.watch(key, api)
        LastChannel.remember(context, key)
    }
    LaunchedEffect(api) {
        TvLookStore.load(api, nav.effectiveThemeId(dark), appColours)
        runCatching { api.lineup() }.getOrNull()?.let { lineup = uniqueChannels(it.channels) }
    }
    LaunchedEffect(key, channel?.brand) { TvLogos.ask(listOfNotNull(channel?.brand), api) }
    // What's on says itself for a moment on every change, then gets out of the way.
    LaunchedEffect(bannerShown) {
        if (!banner) return@LaunchedEffect
        delay(7000)
        banner = false
    }
    // When a programme ends the banner moves on to the next.
    val ends = LiveTv.info?.now?.end
    LaunchedEffect(ends) {
        val end = ends ?: return@LaunchedEffect
        val wait = end - nowSeconds()
        if (wait > 0) delay((wait + 2) * 1000)
        LiveTv.refreshInfo()
        showBanner()
    }
    LaunchedEffect(LiveTv.playing) { if (LiveTv.playing) showBanner() }
    // The banner's clock and progress, every five seconds.
    LaunchedEffect(Unit) {
        while (true) {
            now = nowSeconds()
            delay(5000)
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { LiveTv.resume() }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { LiveTv.pause() }
    // Focus on the picture whenever the mini guide isn't up, for the remote's arrows.
    LaunchedEffect(mini) {
        if (mini) return@LaunchedEffect
        repeat(4) {
            withFrameNanos { }
            runCatching { screen.requestFocus() }
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            LiveTv.muted = !TvLookStore.look.previewSound
            // Back to the guide: the preview carries on with this channel. Anywhere else: it stops.
            view.post {
                val toGuide = nav.current == Route.LiveTv || (nav.current as? TvRoute)?.screen == TvScreen.Guide || (nav.current as? TvRoute)?.screen is TvScreen.Channel
                if (!toGuide) LiveTv.stop()
            }
        }
    }
    BackHandler(enabled = mini) { closeMini() }

    CompositionLocalProvider(LocalTvApi provides api) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black)
                .focusRequester(screen)
                .onKeyEvent { e ->
                    if (mini || e.type != KeyEventType.KeyDown) return@onKeyEvent false
                    when (e.nativeKeyEvent.keyCode) {
                        KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_CHANNEL_UP -> { step(1); true }
                        KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_CHANNEL_DOWN -> { step(-1); true }
                        KeyEvent.KEYCODE_DPAD_LEFT -> { LiveTv.seek(-10.0); showBanner(); true }
                        KeyEvent.KEYCODE_DPAD_RIGHT -> { LiveTv.seek(10.0); showBanner(); true }
                        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> { mini = true; true }
                        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                            if (LiveTv.playing) LiveTv.pause() else if (LiveTv.behind > 20 && bannerShown > 0) LiveTv.goLive() else LiveTv.resume()
                            showBanner()
                            true
                        }
                        else -> false
                    }
                }
                .focusable(!mini),
        ) {
            LivePicture(Modifier.fillMaxSize())
            if (LiveTv.key == key && LiveTv.playing && LiveTv.info?.now?.kind == "slate") {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    SlateCard(dress, LiveTv.info?.name ?: channel?.name.orEmpty(), LiveTv.info?.next)
                }
            }
            if (LiveTv.state == LiveTv.State.Failed && LiveTv.key == key) {
                Failure(dress, channel, LiveTv.why, onTune = ::tune, onNext = { step(1) }, onGuide = ::toGuide)
            } else if (LiveTv.key != key || !LiveTv.playing) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Spinner(Color.White, dress.pt(64)) }
            }
            Box(Modifier.fillMaxSize().padding(start = dress.pt(SIDE), end = dress.pt(SIDE), bottom = dress.pt(BOTTOM)), contentAlignment = Alignment.BottomCenter) {
                if (mini) {
                    MiniGuide(dress, key, onTune = ::tune, onClose = ::closeMini, onFull = ::toGuide)
                } else {
                    AnimatedVisibility(banner, enter = fadeIn(), exit = fadeOut()) {
                        ChannelBanner(dress, channel, if (LiveTv.key == key) LiveTv.info else null, now)
                    }
                }
            }
            if (LiveTv.behind > 20 && !mini) {
                Box(Modifier.fillMaxSize().padding(top = dress.pt(60)), contentAlignment = Alignment.TopCenter) {
                    Text(
                        "${(LiveTv.behind / 60).roundToInt()} min behind live · Play/Pause twice for live",
                        style = MaterialTheme.typography.label, color = Color.White,
                        modifier = Modifier.background(Color.Black.copy(alpha = 0.6f), CircleShape).padding(horizontal = dress.pt(16), vertical = dress.pt(8)),
                    )
                }
            }
        }
    }
}

@Composable
private fun Failure(dress: TvDress, channel: GuideChannel?, why: String, onTune: (String) -> Unit, onNext: () -> Unit, onGuide: () -> Unit) {
    val p = dress.paint
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .clip(RoundedCornerShape(dress.pt(14)))
                .background(p.panel)
                .padding(dress.pt(32))
                .focusGroup(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(dress.pt(16)),
        ) {
            Text(channel?.let { "Channel ${it.number} ${it.name}" } ?: "This channel", style = MaterialTheme.typography.section, color = p.text)
            Text(why, style = MaterialTheme.typography.label.copy(fontWeight = FontWeight.Normal), color = p.text, textAlign = TextAlign.Center)
            Row(horizontalArrangement = Arrangement.spacedBy(dress.pt(16))) {
                channel?.alternative?.let { alt -> TvButton(dress, "Watch ${alt.number} ${alt.name} instead", { onTune(alt.key) }, on = true) }
                TvButton(dress, "Try again", { LiveTv.retry() })
                TvButton(dress, "Next channel", onNext)
                TvButton(dress, "Back to the guide", onGuide)
            }
        }
    }
}

// The banner every box of the era showed on a change of channel: the channel, what's on and how far through, what's
// next and the time.
@Composable
fun ChannelBanner(dress: TvDress, channel: GuideChannel?, info: Tuned?, now: Long) {
    val p = dress.paint
    val shape = dress.shape
    val programme = info?.now
    val radius = if (shape == TvShape.Receiver || shape == TvShape.Teletext || shape == TvShape.Listings) 0f else if (shape == TvShape.Outline) 14f else 6f
    val corner = RoundedCornerShape(dress.pt(radius))
    val plainBg = shape == TvShape.Receiver || shape == TvShape.Teletext || shape == TvShape.Listings || shape == TvShape.Outline || shape == TvShape.Compact
    Row(
        Modifier
            .fillMaxWidth()
            .shadow(dress.pt(13), corner, ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.5f))
            .clip(corner)
            .background(if (plainBg) Brush.verticalGradient(listOf(p.bg, p.bg)) else Brush.verticalGradient(listOf(p.panel2, p.bg)))
            .then(if (shape != TvShape.Teletext) Modifier.strokeInside(p.line, dress.pt(if (shape == TvShape.Receiver || shape == TvShape.Listings || shape == TvShape.Outline || shape == TvShape.Compact) 1 else 2), dress.pt(radius)) else Modifier)
            .then(if (shape == TvShape.Box) Modifier.bevel(dress.pt(2)) else Modifier)
            .padding(horizontal = dress.pt(14), vertical = dress.pt(10)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dress.pt(14)),
    ) {
        Column(
            Modifier
                .widthIn(min = dress.pt(100))
                .rule(Edge.Trailing, p.line, dress.pt(if (shape == TvShape.Receiver || shape == TvShape.Listings) 1 else 2))
                .padding(end = dress.pt(14)),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(dress.pt(2)),
        ) {
            if (channel != null) ChannelLogo(dress, channel, androidx.compose.ui.geometry.Size(80f, 40f), highlighted = false)
            Text(info?.number ?: channel?.number.orEmpty(), style = dress.font(37.5f, W.Bold, digits = shape == TvShape.Receiver), color = p.accent, maxLines = 1)
            Text(
                info?.name ?: channel?.name.orEmpty(), style = dress.font(17.5f, W.Bold), color = p.text, maxLines = 2, textAlign = TextAlign.Center,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = dress.pt(140)),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(dress.pt(3))) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dress.pt(8))) {
                val title = programme?.title ?: info?.name ?: channel?.name.orEmpty()
                Text(if (shape == TvShape.Teletext) title.uppercase() else title, style = dress.font(25f, W.Bold), color = p.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                programme?.rating?.let {
                    Text(it, style = dress.font(15f), color = p.text, modifier = Modifier.border(dress.pt(1), p.soft, RoundedCornerShape(dress.pt(dress.radius))).padding(horizontal = dress.pt(5)))
                }
            }
            Text(
                programme?.sub ?: if (info == null) "Tuning…" else if (programme == null) "No guide data" else "",
                style = dress.font(18.75f, W.Bold), color = p.accent, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            if (programme != null) {
                val small = dress.font(16.25f)
                Row(Modifier.padding(top = dress.pt(4)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dress.pt(8))) {
                    Text(tvClock(programme.start), style = small, color = p.soft, maxLines = 1)
                    val share = if (programme.end > programme.start) ((now - programme.start).toFloat() / (programme.end - programme.start)).coerceIn(0f, 1f) else 0f
                    Box(Modifier.weight(1f).height(dress.pt(8)).background(Color.Black.copy(alpha = 0.5f)).strokeInside(p.line, dress.pt(1), dress.pt(0))) {
                        Box(Modifier.fillMaxWidth(share).height(dress.pt(8)).background(p.accent))
                    }
                    Text(tvClock(programme.end), style = small, color = p.soft, maxLines = 1)
                }
            }
            info?.next?.let { Text("Next: ${it.title} · ${GuideRules.span(it.start, it.end)}", style = dress.font(16.25f), color = p.soft, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            info?.playing?.let { Text("Playing now: ${it.title}", style = dress.font(16.25f), color = p.soft, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            (info?.notices ?: channel?.notices).orEmpty().forEach { Text(it, style = dress.font(16.25f), color = p.accent, maxLines = 2, overflow = TextOverflow.Ellipsis) }
            Text("Select: now and next · ▲▼ channel · Back: the guide", style = dress.font(15f), color = p.soft, modifier = Modifier.padding(top = dress.pt(4)))
        }
        Text(tvClock(now), style = dress.font(25f, W.Bold, digits = shape == TvShape.Receiver, tabular = true), color = p.accent, maxLines = 1)
    }
}

// A few channels over the picture, with what's on them now and next, without leaving what's playing. Up and down move,
// Select tunes, Back closes.
@Composable
fun MiniGuide(dress: TvDress, tuned: String, onTune: (String) -> Unit, onClose: () -> Unit, onFull: () -> Unit) {
    val p = dress.paint
    val shape = dress.shape
    val api = LocalTvApi.current
    val radius = if (shape == TvShape.Teletext || shape == TvShape.Listings || shape == TvShape.Receiver) 0f else 6f
    val corner = RoundedCornerShape(dress.pt(radius))
    var rows by remember { mutableStateOf<List<GuideChannel>?>(null) }
    var error by remember { mutableStateOf("") }
    val now = remember { nowSeconds() }
    val listState = rememberLazyListState()
    val first = remember { FocusRequester() }
    LaunchedEffect(Unit) {
        try {
            rows = uniqueChannels(api.guidePage("/guide?hours=4&offset=0&limit=500").channels)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = problemText(e, "The guide couldn't be loaded.")
        }
    }
    Column(
        Modifier
            .widthIn(max = dress.pt(980))
            .shadow(dress.pt(13), corner, ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.5f))
            .clip(corner)
            .background(p.bg)
            .strokeInside(p.line, dress.pt(2), dress.pt(radius))
            .focusGroup(),
    ) {
        Row(
            Modifier.fillMaxWidth().background(p.panel).padding(horizontal = dress.pt(10), vertical = dress.pt(6)).focusGroup(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
        ) {
            Text("Now and next", style = dress.font(21.25f, W.Bold), color = p.accent, modifier = Modifier.weight(1f))
            TvButton(dress, "Full guide", onFull)
            TvButton(dress, "Close", onClose)
        }
        val list = rows
        when {
            error.isNotEmpty() -> Text(error, style = dress.font(21.25f), color = p.err, modifier = Modifier.padding(dress.pt(16)))
            list == null -> Text("Loading…", style = dress.font(21.25f), color = p.soft, modifier = Modifier.fillMaxWidth().padding(dress.pt(16)))
            else -> {
                val at = list.indexOfFirst { it.key == tuned }.coerceAtLeast(0)
                LaunchedEffect(list) {
                    listState.scrollToItem((at - 3).coerceAtLeast(0))
                    repeat(4) {
                        withFrameNanos { }
                        runCatching { first.requestFocus() }
                    }
                }
                LazyColumn(Modifier.fillMaxWidth().height(dress.pt(7 * 60 + 16)).focusGroup(), state = listState, contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = dress.pt(8))) {
                    items(list, key = { it.key }) { c ->
                        val on = c.programmes.firstOrNull { it.isOn(now) }
                        val next = c.programmes.filter { it.start > now && it.kind != "slate" }.minByOrNull { it.start }
                        TvFocusable(
                            { if (c.canTune) onTune(c.key) }, Modifier.fillMaxWidth(), ring = false, grows = false, enabled = c.canTune,
                            focusRequester = if (c.key == tuned) first else null, label = "${c.number} ${c.name}",
                        ) { focused, _ ->
                            MiniRow(dress, c, on, next, now, c.key == tuned, focused)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MiniRow(dress: TvDress, channel: GuideChannel, on: GuideProgramme?, next: GuideProgramme?, now: Long, tuned: Boolean, focused: Boolean) {
    val p = dress.paint
    val text = dress.font(21.25f)
    val small = dress.font(17.5f)
    Row(
        Modifier
            .fillMaxWidth()
            .background(if (focused) p.hi else Color.Transparent)
            .rule(Edge.Top, p.panel2, dress.pt(1))
            .defaultMinSize(minHeight = dress.pt(56))
            .padding(horizontal = dress.pt(10)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dress.pt(10)),
    ) {
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(color = if (focused) p.hiText else p.accent, fontWeight = FontWeight.Bold)) { append(channel.number) }
                append(" " + channel.name + if (tuned) " ●" else "")
            },
            style = text, color = if (focused) p.hiText else p.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(dress.pt(260)),
        )
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(dress.pt(8))) {
            Text(
                on?.title ?: if (channel.kind == "library") "Off air" else "No guide data", style = text.copy(fontWeight = FontWeight.Bold),
                color = if (focused) p.hiText else p.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.alignByBaseline().weight(1f, fill = false),
            )
            if (on != null) Text(GuideRules.left(on.end - now) + " left", style = small, color = if (focused) p.hiText else p.soft, maxLines = 1, softWrap = false, modifier = Modifier.alignByBaseline())
        }
        Text(
            next?.let { tvClock(it.start) + " " + it.title } ?: "", style = small, color = if (focused) p.hiText else p.soft, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(dress.pt(260)),
        )
    }
}
