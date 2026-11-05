package com.wittywilla.wittymediaclient.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.wittywilla.wittymediaclient.player.Equaliser
import com.wittywilla.wittymediaclient.player.Leveling
import com.wittywilla.wittymediaclient.player.SoundSettings
import com.wittywilla.wittymediaclient.player.number
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.Extra
import com.wittywilla.wittymediaclient.net.FoundLyrics
import com.wittywilla.wittymediaclient.net.LyricLine
import com.wittywilla.wittymediaclient.net.Lyrics
import com.wittywilla.wittymediaclient.player.Listening
import com.wittywilla.wittymediaclient.player.clock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Now Playing's panels as the website's (web/src/audio/LyricsPanel.tsx, ReadPanel.tsx, SoundPanel.tsx, controls.tsx,
// nowplaying.css), on its black: the words that follow the music and Fix for them, Read, and Sound. The iPhone has the
// same in MusicPanels.swift and MusicPlayerUI.swift.

// MARK: small parts

// A panel's head (`.np-side-head`): its name in 17 bold, something beside it, and Close; 12 8 8 18 inside.
@Composable
internal fun NpSideHead(title: String, closeLabel: String, close: () -> Unit, extra: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 8.dp, top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = Np.fg, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).semantics { heading() })
        extra()
        NpRound(WebIcons.Close, closeLabel, 44.dp, 20.dp, fill = Color.Transparent, onClick = close)
    }
}

// A note on black (`.np-note`): 13, 10 by 12 inside, on white at 8%, radius 10, 8 by 18 outside.
@Composable
internal fun NpNote(words: String, modifier: Modifier = Modifier) {
    Text(words, color = Np.fg, fontSize = 13.sp, lineHeight = 1.45.em, modifier = modifier.padding(horizontal = 18.dp, vertical = 8.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Np.rule).padding(horizontal = 12.dp, vertical = 10.dp))
}

// A hint (`.np-hint`): 13 at 72%, 6 by 18 outside.
@Composable
internal fun NpHint(words: String, modifier: Modifier = Modifier) {
    Text(words, color = Np.fg2, fontSize = 13.sp, lineHeight = 1.45.em, modifier = modifier.padding(horizontal = 18.dp, vertical = 6.dp))
}

internal enum class NpButtonKind { Primary, Plain, Ghost }

// The website's buttons inside Now Playing, where its accent is white: primary white with black words, the others on
// the well or clear with a line; 44 high (68 for the big one), 12 inside, radius 10, 13 semibold.
@Composable
internal fun NpButton(words: String, kind: NpButtonKind = NpButtonKind.Plain, big: Boolean = false, enabled: Boolean = true, icon: ImageVector? = null, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val ink = if (kind == NpButtonKind.Primary) Color.Black else Np.fg
    val fill = when (kind) { NpButtonKind.Primary -> Np.fg; NpButtonKind.Plain -> Np.well; NpButtonKind.Ghost -> Color.Transparent }
    Pressable(onClick, modifier.heightIn(min = if (big) 68.dp else 44.dp), shape = RoundedCornerShape(10.dp), fill = fill, label = words, enabled = enabled, disabledAlpha = 0.45f, pressScale = 0.975f, ring = false) {
        Row(
            Modifier.heightIn(min = if (big) 68.dp else 44.dp).then(if (kind == NpButtonKind.Ghost) Modifier.border(1.dp, Np.ghost, RoundedCornerShape(10.dp)) else Modifier)
                .padding(horizontal = if (big) 16.dp else 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        ) {
            if (icon != null) Icon(icon, null, tint = ink, modifier = Modifier.size(16.dp))
            Text(words, color = ink, fontSize = if (big) 17.sp else 13.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        }
    }
}

// A text box on black (`.input`): the well, outlined in white at 40%, radius 10, 14.
@Composable
internal fun NpField(value: String, change: (String) -> Unit, label: String, modifier: Modifier = Modifier, placeholder: String = "", lines: Boolean = false, mono: Boolean = false, submit: () -> Unit = {}) {
    val style = TextStyle(color = Np.fg, fontSize = if (mono) 13.sp else 14.sp, fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default, lineHeight = if (lines) 1.5.em else TextStyle.Default.lineHeight)
    Box(
        modifier.heightIn(min = if (lines) 200.dp else 44.dp).clip(RoundedCornerShape(10.dp)).background(Np.well).border(1.dp, Np.control, RoundedCornerShape(10.dp))
            .padding(horizontal = 10.dp, vertical = if (lines) 10.dp else 0.dp).semantics { contentDescription = label },
        contentAlignment = if (lines) Alignment.TopStart else Alignment.CenterStart,
    ) {
        if (value.isEmpty() && placeholder.isNotEmpty()) Text(placeholder, style = style.copy(color = Np.fg3))
        BasicTextField(
            value, change, singleLine = !lines, textStyle = style, cursorBrush = SolidColor(Np.fg),
            keyboardOptions = KeyboardOptions(imeAction = if (lines) ImeAction.Default else ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit() }),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// MARK: the words

// A song's words, shared by Lyrics, Read and karaoke, and asked for only while one of them is open (lyrics.ts). They're
// kept for the sitting, unless the source couldn't be reached, and asked for again once someone has corrected them.
class LyricsWords(private val listening: Listening, private val api: () -> com.wittywilla.wittymediaclient.net.Api, private val scope: CoroutineScope, private val keeps: CoroutineScope) {
    var lyrics by mutableStateOf<Lyrics?>(null)
        private set
    var loading by mutableStateOf(false)
        private set
    var failed by mutableStateOf("")
        private set
    private var itemId = 0L
    private var asking: Job? = null
    private var saving: Job? = null

    // The listener's own timing, in milliseconds: later words are a positive number.
    val offset: Double get() = lyrics?.offsetMs ?: 0.0

    fun want(id: Long, wanted: Boolean) {
        failed = ""
        if (id <= 0 || !wanted) {
            asking?.cancel()
            loading = false
            itemId = id
            lyrics = listening.heldLyrics[id]
            return
        }
        if (itemId == id && (lyrics != null || loading)) return
        itemId = id
        listening.heldLyrics[id]?.let { lyrics = it; loading = false; return }
        lyrics = null
        load(id)
    }

    // After someone has corrected them.
    fun reload() {
        val id = itemId.takeIf { it > 0 } ?: return
        listening.heldLyrics.remove(id)
        lyrics = null
        load(id)
    }

    private fun load(id: Long) {
        asking?.cancel()
        loading = true
        val connection = api()
        asking = scope.launch {
            // The server was busy with another song: asked again after 3 seconds, four times in all.
            var tries = 0
            while (true) {
                try {
                    val found = connection.lyrics(id)
                    if (itemId != id) return@launch
                    if (found.retry && ++tries < LYRICS_ASKS) {
                        delay(LYRICS_RETRY_MS)
                        continue
                    }
                    if (found.failed.isEmpty()) listening.heldLyrics[id] = found
                    lyrics = found
                    loading = false
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (itemId == id) {
                        failed = e.message.orEmpty()
                        loading = false
                    }
                }
                return@launch
            }
        }
    }

    // A nudge, kept within two minutes either way, and saved half a second after the last.
    fun setOffset(ms: Double) {
        val id = itemId.takeIf { it > 0 } ?: return
        val now = lyrics ?: return
        val kept = LyricWords.nudge(ms, 0.0)
        val changed = now.copy(offsetMs = kept)
        lyrics = changed
        listening.heldLyrics[id] = changed
        val connection = api()
        saving?.cancel()
        // Saved even when the player has closed meanwhile, as the website's timer is.
        saving = keeps.launch {
            delay(500)
            runCatching { connection.setLyricsOffset(id, kept) }
        }
    }

    private companion object {
        const val LYRICS_ASKS = 4
        const val LYRICS_RETRY_MS = 3000L
    }
}

// The line sung now, read every 66 ms while playing and every 300 ms paused, as the website's useLineIndex.
@Composable
internal fun rememberLineIndex(listening: Listening, lyrics: Lyrics?, offset: Double): Int {
    var index by remember { mutableIntStateOf(-1) }
    LaunchedEffect(lyrics, offset, listening.isPlaying) {
        while (true) {
            index = lyrics?.lineAt(listening.positionSec(), offset) ?: -1
            delay(if (listening.isPlaying) 66 else 300)
        }
    }
    return index
}

// Lyrics that follow the music (`LyricsPanel`): the line being sung stays in the middle, and pressing a line goes to it.
// A finger on the list holds it still for four seconds. Words without times read as text. Sooner and Later fix the
// timing for this person alone, and an owner can correct the words for everyone with Fix.
@Composable
internal fun LyricsPanel(nav: Nav, words: LyricsWords, trackId: Long, title: String, artist: String, runtimeSec: Double, close: () -> Unit, said: (String) -> Unit) {
    val listening = nav.app.listening
    val lyrics = words.lyrics
    val offset = words.offset
    val lines = lyrics?.timed.orEmpty()
    val index = rememberLineIndex(listening, lyrics, offset)
    var fixing by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            NpSideHead("Lyrics", "Close the lyrics", close) {
                if (lyrics != null && lyrics.sourceName.isNotEmpty()) {
                    val credit = buildAnnotatedString {
                        if (lyrics.creditUrl.isNotEmpty()) withLink(LinkAnnotation.Url(lyrics.creditUrl, TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline)))) { append(lyrics.sourceName) }
                        else append(lyrics.sourceName)
                    }
                    Text(credit, color = Np.fg2, fontSize = 12.sp, maxLines = 1)
                }
            }
            if (words.loading) NpHint("Looking for the words…")
            if (words.failed.isNotEmpty()) NpNote(words.failed)
            if (lyrics != null && lyrics.instrumental) NpEmpty(listOf("This one has no words."), nav)
            if (lyrics != null && !words.loading && !lyrics.instrumental && lyrics.plain.isEmpty()) NpEmpty(LyricWords.none(lyrics), nav)
            when {
                lines.isNotEmpty() -> LyricLines(lines, index, offset, Modifier.weight(1f)) { at -> listening.seekTo(maxOf(0.0, (lines[at].t + offset) / 1000)) }
                lyrics != null && lyrics.plain.isNotEmpty() -> Text(
                    lyrics.plain, color = Np.fg, fontSize = 17.sp, lineHeight = 1.55.em,
                    modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, top = 4.dp, bottom = 16.dp),
                )
                else -> Spacer(Modifier.weight(1f))
            }
            if (lyrics != null && (lyrics.plain.isNotEmpty() || lyrics.canEdit)) {
                // The timing and Fix (`.np-lyric-tools`): over a hairline, 8 12 12 inside, 6 apart.
                Box(Modifier.fillMaxWidth().height(1.dp).background(Np.line))
                FlowRow(
                    Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp, bottom = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(6.dp), itemVerticalAlignment = Alignment.CenterVertically,
                ) {
                    if (lines.isNotEmpty()) {
                        Row(Modifier.semantics { contentDescription = "Timing" }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            NpChip("Sooner", small = true, label = "Sooner: the words come sooner") { words.setOffset(LyricWords.nudge(offset, -250.0)) }
                            Text(LyricWords.offset(offset), color = Np.fg2, fontSize = 13.sp, textAlign = TextAlign.Center, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.widthIn(min = 62.dp))
                            NpChip("Later", small = true, label = "Later: the words come later") { words.setOffset(LyricWords.nudge(offset, 250.0)) }
                            if (offset != 0.0) NpChip("Reset", small = true) { words.setOffset(0.0) }
                        }
                    }
                    if (lyrics.canEdit) NpChip("Fix", small = true, icon = WebIcons.Edit, iconSize = 16.dp) { fixing = true }
                }
            }
        }
        if (fixing && lyrics != null) FixLyrics(nav, trackId, title, artist, runtimeSec, lyrics, close = { fixing = false }) { done ->
            fixing = false
            said(done)
            words.reload()
        }
    }
}

// The no-words messages (`.np-empty`), 15 at 72%, with the website's links: Settings, and how lyrics work.
@Composable
private fun NpEmpty(paragraphs: List<String>, nav: Nav) {
    val settings = "turn on online lyrics"
    Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val link = TextLinkStyles(SpanStyle(color = Np.fg, textDecoration = TextDecoration.Underline))
        paragraphs.forEach { words ->
            val text = buildAnnotatedString {
                val at = words.indexOf(settings)
                val lrc = words.indexOf(".lrc")
                when {
                    at >= 0 -> {
                        append(words.substring(0, at))
                        withLink(LinkAnnotation.Clickable("settings", link) { nav.pop(); nav.push(Route.Page("/settings/metadata#lyrics", "Settings")) }) { append(settings) }
                        append(words.substring(at + settings.length))
                    }
                    lrc >= 0 -> {
                        append(words.substring(0, lrc))
                        withStyle(SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 14.sp)) { append(".lrc") }
                        append(words.substring(lrc + 4))
                    }
                    else -> append(words)
                }
            }
            Text(text, color = Np.fg2, fontSize = 15.sp, lineHeight = 1.55.em)
        }
        if (paragraphs.size > 1) {
            val help = buildAnnotatedString {
                withLink(LinkAnnotation.Clickable("help", link) { nav.pop(); nav.push(Route.Help("/help/lyrics-karaoke#if-lyrics-are-missing-or-wrong")) }) { append("How lyrics work") }
            }
            Text(help, color = Np.fg2, fontSize = 15.sp, lineHeight = 1.55.em)
        }
    }
}

// The lines (`.np-lines`): 30% of the panel's width above and below, fading out at both ends; each line 6 by 10 inside,
// bold, 2.3% of the screen's height (18.4 to 26.4), 1.3 apart; to come at 62%, sung at 42%, the one being sung white and
// a little larger, unless motion is reduced.
@Composable
private fun LyricLines(lines: List<LyricLine>, index: Int, offset: Double, modifier: Modifier, seek: (Int) -> Unit) {
    val state = rememberLazyListState()
    val reduce = LocalReduceMotion.current
    var heldUntil by remember { mutableLongStateOf(0L) }
    val size = (LocalConfiguration.current.screenHeightDp * 0.023f).coerceIn(18.4f, 26.4f)
    LaunchedEffect(index) {
        if (index < 0 || System.currentTimeMillis() < heldUntil) return@LaunchedEffect
        val info = state.layoutInfo
        val seen = info.visibleItemsInfo.firstOrNull { it.index == index }
        if (seen == null) {
            // Out of sight: brought into view first, then centred once it's been laid out.
            state.scrollToItem(index)
            androidx.compose.runtime.withFrameNanos { }
        }
        val shown = state.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index } ?: return@LaunchedEffect
        val centre = (state.layoutInfo.viewportStartOffset + state.layoutInfo.viewportEndOffset) / 2f
        val by = shown.offset + shown.size / 2f - centre
        if (reduce || seen == null) state.scrollBy(by) else state.animateScrollBy(by)
    }
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val padding = maxWidth * 0.3f
        LazyColumn(
            Modifier.fillMaxSize()
                .pointerInput(Unit) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                        heldUntil = System.currentTimeMillis() + 4000
                    }
                }
                .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                .drawWithContent {
                    drawContent()
                    drawRect(Brush.verticalGradient(0f to Color.Transparent, 0.12f to Color.Black, 0.88f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                },
            state = state, contentPadding = PaddingValues(horizontal = 8.dp, vertical = padding),
        ) {
            itemsIndexed(lines) { at, line ->
                val colour by animateColorAsState(if (at == index) Color.White else if (at < index) Np.past else Np.fg3, tween(150), label = "line")
                val grow by animateFloatAsState(if (at == index && !reduce) 1.03f else 1f, tween(150), label = "grow")
                Text(
                    line.text.ifEmpty { "♪" }, color = colour, fontSize = size.sp, fontWeight = FontWeight.Bold, lineHeight = 1.3.em,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                        .clickable(onClickLabel = null) { heldUntil = 0L; seek(at) }
                        .semantics { contentDescription = "${clock(line.t / 1000)}: ${line.text.ifEmpty { "a break" }}" }
                        .padding(horizontal = 10.dp, vertical = 6.dp)
                        .graphicsLayer { scaleX = grow; scaleY = grow; transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 0.5f) },
                )
            }
        }
    }
}

// Fixing the words (`FixLyrics`), on top of the panel as it uses all of it: Other versions found online (when the
// server may look), Edit and Tap along. Each saves for everyone on this server.
@Composable
private fun FixLyrics(nav: Nav, trackId: Long, title: String, artist: String, runtimeSec: Double, lyrics: Lyrics, close: () -> Unit, saved: (String) -> Unit) {
    val api = nav.app.api
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(if (lyrics.online) "search" else "edit") }
    var query by remember { mutableStateOf("$artist $title".trim()) }
    var found by remember { mutableStateOf<List<FoundLyrics>?>(null) }
    var busy by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf(LyricFile.draft(lyrics)) }
    var error by remember { mutableStateOf("") }
    fun run(work: suspend () -> Unit) {
        busy = true
        error = ""
        scope.launch {
            try {
                work()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message.orEmpty()
            }
            busy = false
        }
    }
    fun find() {
        val asked = query.trim()
        if (asked.isNotEmpty()) run { found = api.searchLyrics(trackId, asked) }
    }
    Column(Modifier.fillMaxSize().background(Np.menu).clickable(remember { MutableInteractionSource() }, null) {}.semantics { contentDescription = "Fix the lyrics of $title" }) {
        NpSideHead("Fix the lyrics", "Close", close)
        Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            @Composable
            fun Tab(words: String, which: String) {
                val on = tab == which
                Pressable({ tab = which }, Modifier.heightIn(min = 40.dp), shape = RoundedCornerShape(50), fill = if (on) Np.fg else Np.chip, label = words, selected = on, ring = false) {
                    Box(Modifier.heightIn(min = 40.dp).padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
                        Text(words, color = if (on) Color.Black else Np.fg, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    }
                }
            }
            if (lyrics.online) Tab("Other versions", "search")
            Tab("Edit", "edit")
            Tab("Tap along", "tap")
        }
        if (error.isNotEmpty()) NpNote(error)
        val body = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 14.dp)
        when (tab) {
            "search" -> Column(body, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    NpField(query, { query = it.take(300) }, "Search for lyrics", Modifier.weight(1f), submit = ::find)
                    NpButton("Search", NpButtonKind.Primary, enabled = !busy && query.isNotBlank(), onClick = ::find)
                }
                if (found?.isEmpty() == true) Text("Nothing found. Try fewer words.", color = Np.fg2, fontSize = 13.sp)
                found.orEmpty().forEach { f ->
                    Pressable(
                        { run { api.chooseLyrics(trackId, f.provider, f.id); saved("Lyrics changed") } }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp), fill = Np.chip,
                        label = "${f.title}, ${f.facts(runtimeSec)}", enabled = !busy, pressScale = 1f, ring = false,
                    ) {
                        Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
                            Text(f.title, color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            val who = listOf(f.artist, f.album).filter { it.isNotEmpty() }.joinToString(" · ")
                            if (who.isNotEmpty()) Text(who, color = Np.fg2, fontSize = 12.sp)
                            Text(f.facts(runtimeSec), color = Np.fg2, fontSize = 12.sp)
                        }
                    }
                }
            }
            "edit" -> Column(body, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NpField(draft, { draft = it }, "The lyrics", Modifier.fillMaxWidth(), placeholder = "[00:12.50]A line, with the time it starts\nor plain words with no times", lines = true, mono = true)
                Text("Kept on this server and used in place of everything else. Nothing is written beside your music.", color = Np.fg2, fontSize = 13.sp, lineHeight = 1.45.em)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    NpButton("Save", NpButtonKind.Primary, enabled = !busy && draft.isNotBlank()) { run { api.saveLyrics(trackId, draft); saved("Lyrics saved") } }
                    NpButton("This song has no words", enabled = !busy) { run { api.markInstrumental(trackId); saved("Marked as having no words") } }
                    if (lyrics.source in LyricFile.STARTS_OVER) NpButton("Start over", NpButtonKind.Ghost, enabled = !busy, icon = WebIcons.Refresh) { run { api.forgetLyrics(trackId); saved("Back to what was found") } }
                }
            }
            else -> TapAlong(nav, LyricFile.tapText(lyrics), busy, body) { file -> run { api.saveLyrics(trackId, file); saved("Timing saved") } }
        }
    }
}

// The simple way to fix the timing (`TapAlong`): it plays from the start, and a press marks each line as it begins.
@Composable
private fun TapAlong(nav: Nav, text: String, busy: Boolean, modifier: Modifier, save: (String) -> Unit) {
    val listening = nav.app.listening
    val lines = remember(text) { LyricFile.lines(text) }
    var times by remember { mutableStateOf(emptyList<Double>()) }
    var started by remember { mutableStateOf(false) }
    val at = times.size
    val done = at >= lines.size && lines.isNotEmpty()
    fun tap() { if (!done) times = times + Math.round(listening.positionSec() * 1000).toDouble() }
    fun start() {
        times = emptyList()
        started = true
        listening.seekTo(0.0)
        if (!listening.isPlaying) listening.toggle()
    }
    Column(
        modifier.onPreviewKeyEvent { if (started && it.key == Key.Spacebar && it.type == KeyEventType.KeyDown) { tap(); true } else false },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
    ) {
        when {
            lines.isEmpty() -> Text("Add the words under Edit first, then come back to time them.", color = Np.fg2, fontSize = 13.sp, modifier = Modifier.fillMaxWidth())
            !started -> {
                Text("The song starts from the beginning. Press the big button, or Space, as each line starts.", color = Np.fg, fontSize = 15.sp, textAlign = TextAlign.Center)
                NpButton("Start", NpButtonKind.Primary, onClick = ::start)
            }
            else -> {
                Text(lines.getOrNull(at - 1) ?: " ", color = Np.fg3, fontSize = 15.sp, textAlign = TextAlign.Center, modifier = Modifier.heightIn(min = 21.dp))
                Box(Modifier.heightIn(min = 52.dp), contentAlignment = Alignment.Center) {
                    Text(if (done) "That's all of them." else lines[at], color = Np.fg, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                }
                Text(lines.getOrNull(at + 1) ?: " ", color = Np.fg3, fontSize = 15.sp, textAlign = TextAlign.Center, modifier = Modifier.heightIn(min = 21.dp))
                NpButton("This line starts now (${minOf(at + 1, lines.size)} of ${lines.size})", NpButtonKind.Primary, big = true, enabled = !done, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), onClick = ::tap)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    NpButton("Undo the last one", enabled = at > 0) {
                        val back = times.getOrNull(at - 2) ?: 0.0
                        times = times.dropLast(1)
                        listening.seekTo(maxOf(0.0, back / 1000))
                    }
                    NpButton("Start again", NpButtonKind.Ghost, onClick = ::start)
                    NpButton("Save", NpButtonKind.Primary, enabled = done && !busy) { save(LyricFile.lrc(times, lines)) }
                }
            }
        }
    }
}

// MARK: Read

// Something to read while it plays (`ReadPanel`): the words at your own pace, and whatever came with the album. Text
// opens here, with Back; a booklet is a PDF, which opens in the device's own reader.
@Composable
internal fun ReadPanel(nav: Nav, trackId: Long, extras: List<Extra>, words: LyricsWords, close: () -> Unit) {
    val api = nav.app.api
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var shown by remember(trackId) { mutableStateOf<Pair<String, String>?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember(trackId) { mutableStateOf("") }
    fun open(extra: Extra) {
        busy = true
        error = ""
        scope.launch {
            try {
                if (extra.isBooklet) openBooklet(context, api, trackId, extra.name)
                else shown = extra.name to api.extraText(trackId, extra.name)
            } catch (e: CancellationException) {
                throw e
            } catch (e: android.content.ActivityNotFoundException) {
                error = "There's no app on this device that opens a PDF."
            } catch (e: Exception) {
                error = e.message.orEmpty()
            }
            busy = false
        }
    }
    val lyrics = words.lyrics
    val plain = lyrics?.plain.orEmpty()
    Column(Modifier.fillMaxSize()) {
        NpSideHead(shown?.first ?: "Read", "Close", close) {
            if (shown != null) NpChip("Back", small = true) { shown = null }
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(top = 4.dp, bottom = 14.dp)) {
            if (error.isNotEmpty()) NpNote(error)
            val opened = shown
            if (opened != null) ReadText(opened.second)
            else {
                if (extras.isNotEmpty()) FlowRow(Modifier.padding(start = 18.dp, end = 18.dp, bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    extras.forEach { extra -> NpChip(extra.name, icon = NpIcons.File, iconSize = 18.dp, enabled = !busy) { open(extra) } }
                }
                if (words.loading) NpHint("Looking for the words…")
                if (plain.isNotEmpty()) {
                    ReadText(plain)
                    if (lyrics != null && lyrics.sourceName.isNotEmpty()) {
                        val credit = buildAnnotatedString {
                            append("Words from ")
                            if (lyrics.creditUrl.isNotEmpty()) withLink(LinkAnnotation.Url(lyrics.creditUrl, TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline)))) { append(lyrics.sourceName) }
                            else append(lyrics.sourceName)
                            append(".")
                        }
                        Text(credit, color = Np.fg2, fontSize = 12.sp, modifier = Modifier.padding(start = 18.dp, end = 18.dp, top = 12.dp))
                    }
                } else if (!words.loading && extras.isEmpty()) {
                    NpHint("Nothing to read for this one yet: no words were found, and no booklet is beside the album. A PDF or a text file in the album's folder appears here.")
                }
            }
        }
    }
}

// Words to read (`.np-read-text`): 17, 1.55 apart, 18 in from the sides, kept as they're written.
@Composable
private fun ReadText(text: String) {
    androidx.compose.foundation.text.selection.SelectionContainer {
        Text(text, color = Np.fg, fontSize = 17.sp, lineHeight = 1.55.em, modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 4.dp))
    }
}

// A booklet: fetched with the sign-in into the app's own cache, then handed to whichever app reads PDFs on this device.
private suspend fun openBooklet(context: android.content.Context, api: com.wittywilla.wittymediaclient.net.Api, trackId: Long, name: String) {
    val folder = java.io.File(context.cacheDir, "booklets").apply { mkdirs() }
    val safe = name.replace(Regex("[^A-Za-z0-9._ -]"), "_").take(80).let { if (it.lowercase(java.util.Locale.ROOT).endsWith(".pdf")) it else "$it.pdf" }
    val file = java.io.File(folder, "$trackId-$safe")
    api.download(api.extraFileUrl(trackId, name), file)
    val uri = androidx.core.content.FileProvider.getUriForFile(context, context.packageName + ".files", file)
    val view = android.content.Intent(android.content.Intent.ACTION_VIEW).setDataAndType(uri, "application/pdf")
        .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(view)
}

// MARK: Sound

// How it sounds on this device (`SoundPanel`): between songs, the volume leveling and the equaliser, each in a section
// under a hairline. Kept on the device, as speakers differ.
@Composable
internal fun SoundPanel(nav: Nav, close: () -> Unit) {
    val listening = nav.app.listening
    val s = listening.sound
    Column(Modifier.fillMaxSize()) {
        NpSideHead("Sound", "Close sound settings", close)
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 16.dp)) {
            SoundSection("Between songs") {
                NpCheck("No gaps: start the next song right as this one ends", s.gapless) { listening.setSound { it.copy(gapless = !it.gapless) } }
                NpSelect("Crossfade", SoundSettings.CROSSFADES.map { it to SoundSettings.crossfadeWords(it) }, s.crossfade) { c -> listening.setSound { it.copy(crossfade = c) } }
                if (s.crossfade > 0) NpCheck("Also within an album. Off keeps songs that run together as they were made", s.crossfadeAlbums) { listening.setSound { it.copy(crossfadeAlbums = !it.crossfadeAlbums) } }
                SoundHint("Works for files sent as they are. Formats converted while playing, and CD images, follow their own rules.")
            }
            SoundSection("Volume leveling") {
                NpSelect("ReplayGain", Leveling.entries.map { it to it.words }, s.replayGain) { choice -> listening.setSound { it.copy(replayGain = choice) } }
                SoundHint("Uses the loudness tags in your files, which tagging tools such as MusicBrainz Picard or foobar2000 can add. Songs without them play as they are.")
            }
            SoundSection("Equaliser") {
                NpCheck("Use the equaliser", s.eqOn) { listening.setSound { it.copy(eqOn = !it.eqOn) } }
                val presets = Equaliser.PRESETS.map { it.id to it.name } + if (s.presetShown == "custom") listOf("custom" to "Your own") else emptyList()
                NpSelect("Preset", presets, s.presetShown, enabled = s.eqOn) { id ->
                    Equaliser.PRESETS.firstOrNull { it.id == id }?.let { preset -> listening.setSound { it.copy(eqPreset = preset.id, eqGains = preset.gains) } }
                }
                Column(Modifier.graphicsLayer { alpha = if (s.eqOn) 1f else 0.5f }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Equaliser.FREQUENCIES.forEachIndexed { band, frequency ->
                        val name = Equaliser.hertz(frequency)
                        EqRow(name, s.eqGains[band], "$name hertz", s.eqOn) { gain ->
                            listening.setSound { it.copy(eqGains = it.eqGains.toMutableList().also { g -> g[band] = gain }, eqPreset = "custom") }
                        }
                    }
                    EqRow("Level", s.preamp, "Overall level", s.eqOn) { gain -> listening.setSound { it.copy(preamp = gain) } }
                }
                SoundHint("If boosting makes loud parts crackle, lower the overall level a little.")
            }
        }
    }
}

// A section (`.np-sound section`): over a hairline, 10 above and 14 below, its name 14 bold, 8 between.
@Composable
private fun SoundSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(Np.line))
        Column(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            content()
        }
    }
}

@Composable
private fun SoundHint(words: String) {
    Text(words, color = Np.fg2, fontSize = 13.sp, lineHeight = 1.45.em)
}

// A band (`.np-eq label`): its name 44 wide in 12 semibold, the slider, and the dB 34 wide, 10 apart, at least 32 high.
@Composable
private fun EqRow(name: String, value: Double, label: String, enabled: Boolean, change: (Double) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 32.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(name, color = Np.fg2, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(44.dp))
        NpSlider(value, -12.0, 12.0, 1.0, label, "${number(value)} decibels", enabled, Modifier.weight(1f), change = change)
        Text(Equaliser.decibels(value), color = Np.fg2, fontSize = 12.sp, textAlign = TextAlign.End, style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.width(34.dp))
    }
}

// The website's checkbox on black: 20 square, white with a black tick when it's on, the words beside it in 14.
@Composable
internal fun NpCheck(words: String, on: Boolean, enabled: Boolean = true, flip: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 32.dp).toggleable(on, enabled = enabled, role = Role.Checkbox) { flip() },
        verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier.size(20.dp).clip(RoundedCornerShape(4.dp)).background(if (on) Color.White else Color.Transparent)
                .border(1.5.dp, Color.White.copy(alpha = if (on) 1f else 0.4f), RoundedCornerShape(4.dp)),
            contentAlignment = Alignment.Center,
        ) {
            if (on) Icon(WebIcons.Check, null, tint = Color.Black, modifier = Modifier.size(16.dp))
        }
        Text(words, color = Np.fg, fontSize = 14.sp, lineHeight = 1.35.em, modifier = Modifier.weight(1f))
    }
}

// The website's small select on black: the name, then the choice on the well with its small arrow, 44 high, which
// opens the choices under it.
@Composable
internal fun <T> NpSelect(label: String, choices: List<Pair<T, String>>, chosen: T, enabled: Boolean = true, choose: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val shown = choices.firstOrNull { it.first == chosen }?.second.orEmpty()
    val maxHeight = minOf(LocalConfiguration.current.screenHeightDp * 0.6f, 460f).dp
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(label, color = Np.fg, fontSize = 14.sp, modifier = Modifier.weight(1f))
        Box {
            Pressable({ open = true }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Np.well, label = "$label, $shown", enabled = enabled, disabledAlpha = 0.5f, ring = false) {
                Row(
                    Modifier.heightIn(min = 44.dp).border(1.dp, Np.control, RoundedCornerShape(10.dp)).padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(shown, color = Np.fg, fontSize = 13.sp, maxLines = 1)
                    androidx.compose.foundation.Canvas(Modifier.size(10.dp, 5.dp)) {
                        drawPath(androidx.compose.ui.graphics.Path().apply { moveTo(0f, 0f); lineTo(size.width, 0f); lineTo(size.width / 2, size.height); close() }, Np.fg)
                    }
                }
            }
            if (open) Popup(popupPositionProvider = UnderTheRight, onDismissRequest = { open = false }, properties = PopupProperties(focusable = true)) {
                Column(
                    Modifier.widthIn(min = 220.dp).heightIn(max = maxHeight).cssShadow(10.dp, 30.dp, Color(0x73000000), 14.dp).clip(RoundedCornerShape(14.dp))
                        .background(Np.menu).border(1.dp, Np.line, RoundedCornerShape(14.dp)).padding(6.dp).verticalScroll(rememberScrollState()),
                ) {
                    MenuRows(choices.map { (value, words) -> MenuItem(words, chosen = value == chosen) { choose(value) } }) { open = false }
                }
            }
        }
    }
}

// Right-aligned under what opened it, or over it when there's no room, 8 from it and from the window's edges.
private object UnderTheRight : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val room = (8 * android.content.res.Resources.getSystem().displayMetrics.density).toInt()
        val left = (anchorBounds.right - popupContentSize.width).coerceIn(room, maxOf(room, windowSize.width - popupContentSize.width - room))
        val below = anchorBounds.bottom + room
        val top = if (below + popupContentSize.height <= windowSize.height - room) below else maxOf(room, anchorBounds.top - popupContentSize.height - room)
        return IntOffset(left, top)
    }
}

// The website's range on black for a value between two ends: a 4 high track, white to the value, and a 14 thumb, in a
// 32 high target. It moves in steps.
@Composable
internal fun NpSlider(value: Double, low: Double, high: Double, step: Double, label: String, spoken: String, enabled: Boolean, modifier: Modifier = Modifier, fill: Color = Color.White, track: Color = Color.White.copy(alpha = 0.28f), change: (Double) -> Unit) {
    var width by remember { mutableIntStateOf(1) }
    fun at(x: Float): Double {
        val raw = low + (x / width).coerceIn(0f, 1f) * (high - low)
        return (Math.round(raw / step) * step).coerceIn(low, high)
    }
    fun set(next: Double) { if (enabled && next != value) change(next) }
    androidx.compose.foundation.Canvas(
        modifier.height(32.dp).onSizeChanged { width = it.width }
            .semantics {
                contentDescription = label
                stateDescription = spoken
                progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), low.toFloat()..high.toFloat(), ((high - low) / step).toInt() - 1)
                if (enabled) setProgress { set((Math.round(it / step) * step).coerceIn(low, high)); true }
            }
            .pointerInput(enabled) { if (enabled) detectTapGestures { set(at(it.x)) } }
            .pointerInput(enabled) { if (enabled) detectHorizontalDragGestures { change, _ -> set(at(change.position.x)) } },
    ) {
        val h = 4.dp.toPx()
        val r = 7.dp.toPx()
        val top = (size.height - h) / 2
        val part = ((value - low) / (high - low)).toFloat().coerceIn(0f, 1f)
        val x = r + part * (size.width - 2 * r)
        drawRoundRect(track, Offset(0f, top), Size(size.width, h), CornerRadius(h / 2))
        drawRoundRect(fill, Offset(0f, top), Size(x, h), CornerRadius(h / 2))
        drawCircle(Color(0x73000000), r, Offset(x, size.height / 2 + 1.dp.toPx()))
        drawCircle(Color.White, r, Offset(x, size.height / 2))
    }
}

// MARK: the volume

// A tablet's volume (`Volume`, `.mp-volume`): Mute, and how loud, in steps of 2%. On Now Playing's black, or on the
// theme's own panel in the bar.
@Composable
internal fun VolumeCard(listening: com.wittywilla.wittymediaclient.player.Listening, onBlack: Boolean) {
    val scheme = androidx.compose.material3.MaterialTheme.colorScheme
    val s = listening.sound
    val shown = if (s.muted) 0.0 else s.volume
    val ink = if (onBlack) Np.fg else scheme.onBackground
    Row(Modifier.widthIn(min = 240.dp).padding(start = 2.dp, end = 8.dp, top = 2.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Pressable({ listening.setSound { it.copy(muted = !it.muted) } }, Modifier.size(44.dp), shape = androidx.compose.foundation.shape.CircleShape, fill = Color.Transparent, label = if (s.muted) "Turn the sound back on" else "Mute", selected = s.muted, pressScale = 0.94f, ring = false) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (shown == 0.0) WebIcons.Mute else WebIcons.Volume, null, tint = ink, modifier = Modifier.size(20.dp)) }
        }
        val percent = Math.round(shown * 100).toDouble()
        NpSlider(
            percent, 0.0, 100.0, 2.0, "Volume", "${percent.toInt()}%", true, Modifier.weight(1f),
            fill = if (onBlack) Color.White else scheme.primary, track = if (onBlack) Color.White.copy(alpha = 0.28f) else scheme.onBackground.copy(alpha = 0.28f),
        ) { v -> listening.setSound { it.copy(volume = v / 100, muted = false) } }
    }
}
