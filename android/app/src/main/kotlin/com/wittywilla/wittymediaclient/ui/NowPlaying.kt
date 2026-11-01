package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import com.wittywilla.wittymediaclient.player.Listening
import com.wittywilla.wittymediaclient.player.QueueEntry
import com.wittywilla.wittymediaclient.player.SeekBar
import com.wittywilla.wittymediaclient.player.clock
import com.wittywilla.wittymediaclient.player.spokenClock
import com.wittywilla.wittymediaclient.player.speedWords
import kotlinx.coroutines.delay

// What's playing: the mini player over the app's own screens, and the whole-screen player with the queue.

// The pictures the built-in set doesn't have. Paths are the usual 24 by 24 glyphs.
object Glyphs {
    private fun glyph(name: String, path: String) = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
        .addPath(addPathNodes(path), fill = SolidColor(Color.Black))
        .build()

    val Pause by lazy { glyph("Pause", "M6 19h4V5H6v14zm8-14v14h4V5h-4z") }
    val Next by lazy { glyph("Next", "M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z") }
    val Previous by lazy { glyph("Previous", "M6 6h2v12H6zm3.5 6l8.5 6V6z") }
    val Shuffle by lazy { glyph("Shuffle", "M10.59 9.17L5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41l-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z") }
    val Repeat by lazy { glyph("Repeat", "M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z") }
    val RepeatOne by lazy { glyph("RepeatOne", "M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4zm-4-2V9h-1l-2 1v1h1.5v4H13z") }
}

private const val CLOCK_MS = 1000L
val MINI_HEIGHT = 64.dp
private val MINI_ART = 44.dp
private val BIG_PLAY = 72.dp

// The place on the track, looked at once a second while it's playing and not at all otherwise.
@Composable
private fun rememberPlace(listening: Listening): Double {
    var place by remember { mutableDoubleStateOf(listening.positionSec()) }
    LaunchedEffect(listening.isPlaying, listening.now?.mediaId, listening.jumps) {
        place = listening.positionSec()
        while (listening.isPlaying) {
            delay(CLOCK_MS)
            place = listening.positionSec()
        }
    }
    return place
}

// Over the app's own screens, with what most people want from it: what's on, Play or Pause, and Next. Paused,
// Next gives way to a way of stopping altogether.
@Composable
fun MiniPlayer(nav: Nav, modifier: Modifier = Modifier) {
    val listening = nav.app.listening
    val now = listening.now ?: return
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val about = now.mediaMetadata
    val place = rememberPlace(listening)
    val duration = listening.durationSec()
    Column(modifier.fillMaxWidth().background(scheme.surface)) {
        Box(Modifier.fillMaxWidth().height(2.dp).background(scheme.outline)) {
            val part = if (duration > 0) (place / duration).toFloat().coerceIn(0f, 1f) else 0f
            Box(Modifier.fillMaxWidth(part).fillMaxHeight().background(scheme.primary))
        }
        Row(
            // A TV may crop the edge of its picture.
            Modifier.fillMaxWidth().padding(horizontal = if (metrics.tv) metrics.gutter else Space.S2, vertical = if (metrics.tv) Space.S3 else Space.S1).remoteRow(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.S1),
        ) {
            FocusBox(
                { nav.openNowPlaying() }, Modifier.weight(1f),
                label = "Now playing: ${about.title}, ${about.artist}",
                state = if (listening.isPlaying) "Playing" else "Paused",
                focusKey = "mini-open",
            ) {
                Row(Modifier.padding(Space.S1), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S3)) {
                    ServerImage(about.artworkUri?.toString().orEmpty(), MINI_ART, 1f, Modifier.size(MINI_ART).clip(Radius.SM))
                    Column(Modifier.weight(1f)) {
                        Text(about.title?.toString().orEmpty(), color = scheme.onSurface, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (listening.problem.isNotEmpty()) {
                            Text(listening.problem, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                        } else if (listening.isLoading) {
                            Text("Loading…", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, maxLines = 1, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                        } else if (!about.artist.isNullOrEmpty()) {
                            Text(about.artist.toString(), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            RoundButton(if (listening.isPlaying) Glyphs.Pause else Icons.Filled.PlayArrow, if (listening.isPlaying) "Pause" else "Play", listening::toggle, focusKey = "mini-play")
            if (listening.isPlaying) {
                RoundButton(Glyphs.Next, "Next", listening::next, enabled = listening.canGoNext, focusKey = "mini-next")
            } else {
                RoundButton(Icons.Filled.Close, "Stop and clear the queue", listening::stop, focusKey = "mini-stop")
            }
        }
    }
}

// A remote walks down through these: the bar, then the buttons, then the queue. Left and right stay within a row,
// and on the bar they move it.
@Composable
private fun Controls(listening: Listening) {
    val place = rememberPlace(listening)
    val duration = listening.durationSec()
    val books = listening.keepsPlace
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.S2)) {
        if (duration > 0) {
            SeekBar(place, duration, {}, listening::seekTo, trackColour = scheme.outline, ringColour = scheme.onBackground)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Secondary(clock(place), Modifier.semantics { contentDescription = spokenClock(place) })
                Secondary(clock(duration), Modifier.semantics { contentDescription = "${spokenClock(duration)} long" })
            }
        }
        // Right from the last button leads across to the queue, on a screen with room for it beside these.
        Row(Modifier.fillMaxWidth().focusRestorer().focusGroup(), horizontalArrangement = Arrangement.spacedBy(Space.S2, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            if (books) {
                RoundButton(Glyphs.Previous, "Previous part", listening::previous, focusKey = "np-prev")
                ActionButton("−15", { listening.seekBy(-BOOK_BACK_SEC) }, pill = true, focusKey = "np-back")
            } else {
                RoundButton(Glyphs.Shuffle, "Shuffle", listening::toggleShuffle, selected = listening.shuffle, focusKey = "np-shuffle")
                RoundButton(Glyphs.Previous, "Previous", listening::previous, focusKey = "np-prev")
            }
            RoundButton(
                if (listening.isPlaying) Glyphs.Pause else Icons.Filled.PlayArrow, if (listening.isPlaying) "Pause" else "Play", listening::toggle,
                primary = true, size = BIG_PLAY, focusKey = "np-play", requestFocus = true,
            )
            if (books) {
                ActionButton("+30", { listening.seekBy(BOOK_FORWARD_SEC) }, pill = true, focusKey = "np-forward")
                RoundButton(Glyphs.Next, "Next part", listening::next, enabled = listening.canGoNext, focusKey = "np-next")
            } else {
                RoundButton(Glyphs.Next, "Next", listening::next, enabled = listening.canGoNext, focusKey = "np-next")
                RoundButton(
                    if (listening.repeat == Player.REPEAT_MODE_ONE) Glyphs.RepeatOne else Glyphs.Repeat,
                    when (listening.repeat) { Player.REPEAT_MODE_ONE -> "Repeat this one"; Player.REPEAT_MODE_ALL -> "Repeat the queue"; else -> "Repeat" },
                    listening::cycleRepeat, selected = listening.repeat != Player.REPEAT_MODE_OFF, focusKey = "np-repeat",
                )
            }
        }
        if (books) {
            Row(Modifier.fillMaxWidth().focusGroup(), horizontalArrangement = Arrangement.Center) {
                ActionButton("Speed ${speedWords(listening.speed)}", listening::cycleSpeed, pill = true, focusKey = "np-speed")
            }
        }
    }
}

private const val BOOK_BACK_SEC = 15.0
private const val BOOK_FORWARD_SEC = 30.0

@Composable
private fun QueueRow(listening: Listening, entry: QueueEntry, position: Int, last: Int, editing: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val isNow = entry.index == listening.nowIndex
    Row(Modifier.fillMaxWidth().remoteRow(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S1)) {
        FocusBox(
            { listening.jumpTo(entry.index) }, Modifier.weight(1f),
            label = listOf(entry.title, entry.artist).filter { it.isNotEmpty() }.joinToString(", "), state = if (isNow) "Playing" else null, selected = isNow,
            focusKey = "q-${entry.mediaId}-${entry.index}", filled = if (isNow) scheme.surfaceVariant else Color.Transparent,
        ) {
            Row(Modifier.padding(horizontal = Space.S3, vertical = Space.S2), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S3)) {
                Column(Modifier.weight(1f)) {
                    Text(entry.title, color = scheme.onBackground, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (entry.artist.isNotEmpty()) Secondary(entry.artist, maxLines = 1)
                }
                if (entry.durationSec > 0) Secondary(clock(entry.durationSec))
            }
        }
        if (editing) {
            // Shuffled, there's no order to move something within.
            if (!listening.shuffle) {
                RoundButton(Icons.Filled.KeyboardArrowUp, "Move ${entry.title} up", { listening.move(entry.index, entry.index - 1) }, enabled = position > 0, focusKey = "q-up-${entry.index}")
                RoundButton(Icons.Filled.KeyboardArrowDown, "Move ${entry.title} down", { listening.move(entry.index, entry.index + 1) }, enabled = position < last, focusKey = "q-down-${entry.index}")
            }
            RoundButton(Icons.Filled.Close, "Take ${entry.title} out of the queue", { listening.remove(entry.index) }, focusKey = "q-out-${entry.index}")
        }
    }
}

private fun LazyListScope.queueList(listening: Listening, editing: Boolean, onEdit: () -> Unit, onClear: () -> Unit) {
    item(key = "queue-head") {
        Row(Modifier.fillMaxWidth().padding(top = Space.S2).remoteRow(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S2)) {
            SectionTitle("Queue", Modifier.weight(1f))
            ActionButton(if (editing) "Done" else "Change", onEdit, focusKey = "q-edit")
            ActionButton("Clear", onClear, focusKey = "q-clear")
        }
    }
    val list = listening.queue
    itemsIndexed(list, key = { _, it -> "${it.mediaId}-${it.index}" }) { position, entry ->
        QueueRow(listening, entry, position, list.lastIndex, editing)
    }
}

// The whole screen. Upright, everything scrolls in one column. On a TV or sideways, the queue has its own side.
@Composable
fun NowPlayingScreen(nav: Nav) {
    val listening = nav.app.listening
    val metrics = LocalMetrics.current
    val configuration = LocalConfiguration.current
    val wide = metrics.tv || configuration.screenWidthDp > configuration.screenHeightDp
    var editing by rememberSaveable { mutableStateOf(false) }
    val now = listening.now
    // The queue was cleared from here or from elsewhere.
    LaunchedEffect(now == null) { if (now == null) nav.closeNowPlaying() }
    val about = now?.mediaMetadata
    val onClear = { listening.stop(); nav.closeNowPlaying() }

    @Composable
    fun Art(modifier: Modifier) {
        ServerImage(about?.artworkUri?.toString().orEmpty(), COVER, 1f, modifier.aspectRatio(1f).clip(Radius.LG), placeholder = about?.albumTitle?.toString().orEmpty())
    }

    @Composable
    fun Words(center: Boolean) {
        val align = if (center) TextAlign.Center else TextAlign.Start
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.S1)) {
            Text(about?.title?.toString().orEmpty(), color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.headlineSmall, textAlign = align, maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = Modifier.fillMaxWidth())
            val under = listOf(about?.artist?.toString().orEmpty(), about?.albumTitle?.toString().orEmpty()).filter { it.isNotEmpty() }.distinct().joinToString(" · ")
            if (under.isNotEmpty()) Text(under, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyLarge, textAlign = align, modifier = Modifier.fillMaxWidth())
            if (listening.isLoading) Text("Loading…", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, textAlign = align, modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite })
            ErrorText(listening.problem)
        }
    }

    Screen {
        if (wide) {
            Row(
                Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = metrics.gutter, vertical = if (metrics.tv) metrics.edge else Space.S4),
                horizontalArrangement = Arrangement.spacedBy(Space.S8),
            ) {
                Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(Space.S3, Alignment.CenterVertically)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.S6), verticalAlignment = Alignment.CenterVertically) {
                        Art(Modifier.size(if (metrics.tv) TV_COVER else SIDE_COVER))
                        Box(Modifier.weight(1f)) { Words(center = false) }
                    }
                    Controls(listening)
                }
                // The list keeps what's playing in view, unless someone is rearranging it.
                val queueScroll = rememberLazyListState()
                LaunchedEffect(listening.nowIndex, listening.queue.size, editing) {
                    if (!editing) queueScroll.scrollToItem(listening.queue.indexOfFirst { it.index == listening.nowIndex }.coerceAtLeast(0))
                }
                // Left from here goes back to the buttons. Past either end of the list stays in the list.
                LazyColumn(
                    state = queueScroll,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .focusProperties {
                            onExit = { if (requestedFocusDirection == FocusDirection.Up || requestedFocusDirection == FocusDirection.Down) cancelFocusChange() }
                        }
                        .focusGroup(),
                    verticalArrangement = Arrangement.spacedBy(Space.S1),
                ) {
                    queueList(listening, editing, { editing = !editing }, onClear)
                }
            }
        } else {
            LazyColumn(
                Modifier.fillMaxSize().safeDrawingPadding(),
                contentPadding = PaddingValues(horizontal = metrics.gutter, vertical = Space.S4),
                verticalArrangement = Arrangement.spacedBy(Space.S1),
            ) {
                item(key = "player") {
                    Column(verticalArrangement = Arrangement.spacedBy(Space.S4), horizontalAlignment = Alignment.CenterHorizontally) {
                        Art(Modifier.fillMaxWidth().widthIn(max = COVER))
                        Words(center = true)
                        Controls(listening)
                    }
                }
                queueList(listening, editing, { editing = !editing }, onClear)
            }
        }
    }
}

private val COVER = 360.dp
private val TV_COVER = 240.dp
private val SIDE_COVER = 120.dp
