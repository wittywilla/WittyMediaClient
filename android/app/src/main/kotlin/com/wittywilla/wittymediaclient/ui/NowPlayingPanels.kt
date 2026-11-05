package com.wittywilla.wittymediaclient.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
        if (seen == null) state.scrollToItem(index)
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
