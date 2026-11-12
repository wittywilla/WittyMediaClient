// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.Artist
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.albumsWord
import com.wittywilla.wittymediaclient.net.artistsWord
import com.wittywilla.wittymediaclient.net.fullPagePath
import com.wittywilla.wittymediaclient.net.keepsPlace
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.player.Start
import com.wittywilla.wittymediaclient.player.clock
import com.wittywilla.wittymediaclient.player.hasPlaceToResume
import com.wittywilla.wittymediaclient.player.placeOn
import com.wittywilla.wittymediaclient.player.spokenClock
import com.wittywilla.wittymediaclient.player.whereToStart
import kotlinx.coroutines.CancellationException

// Music, audiobooks and podcasts: a library, an album or book, and its tracks. Choosing a track starts a queue in
// ListeningService, which carries on whatever happens to these screens. What isn't here, such as playlists,
// lyrics and following a podcast, is one button away on the server's own page.

private enum class Part { Albums, Artists, Songs }

private const val SONGS_PAGE = 100
private val ROW_ART = 48.dp
private val ALBUM_ART = 220.dp

// Asks when the screen first shows, and draws what it had in the meantime, as the other screens do.
@Composable
private fun <T : Any> rememberAnswer(nav: Nav, s: Map<String, String>, key: String, ask: suspend () -> T): Answer<T> {
    val answer = remember(key) { Answer(nav.remembered<T>(key)) }
    LaunchedEffect(key, answer.attempt) {
        answer.problem = ""
        try {
            val fresh = ask()
            answer.value = fresh
            nav.remember(key, fresh)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) answer.problem = problemWords(e, s["errLost"].orEmpty())
        }
    }
    return answer
}

private class Answer<T : Any>(first: T?) {
    var value by mutableStateOf(first)
    var problem by mutableStateOf("")
    var attempt by mutableIntStateOf(0)
}

@Composable
private fun <T : Any> Answered(nav: Nav, answer: Answer<T>, content: @Composable (T) -> Unit) {
    val value = answer.value
    when {
        value == null && answer.problem.isNotEmpty() -> LoadFailed(nav, answer.problem) { answer.attempt++ }
        value == null -> Loading()
        else -> content(value)
    }
}

// What's chosen says so with a tick as well as a colour.
@Composable
private fun Choice(words: String, chosen: Boolean, focusKey: String, choose: () -> Unit) {
    ActionButton(words, choose, selected = chosen, pill = true, focusKey = focusKey, icon = if (chosen) Icons.Filled.Check else null)
}

@Composable
private fun AlbumGrid(nav: Nav, s: Map<String, String>, library: Long, sort: String, artist: String?) {
    val answer = rememberAnswer(nav, s, "albums-$library-$sort-${artist.orEmpty()}") { nav.app.api.albums(library, sort, artist) }
    Answered(nav, answer) { albums ->
        if (albums.isEmpty()) Secondary("Nothing here yet.")
        ErrorText(answer.problem)
        val distinct = remember(albums) { albums.distinctBy { it.artist to it.title } }
        LazyVerticalGrid(
            posterColumns(),
            contentPadding = PaddingValues(bottom = Space.S6),
            horizontalArrangement = Arrangement.spacedBy(Space.S2),
            verticalArrangement = Arrangement.spacedBy(Space.S4),
        ) {
            items(distinct, key = { "${it.artist}|${it.title}" }) { album ->
                PosterCard(
                    album.title.ifEmpty { "No album" }, album.artist.takeIf { it != album.title }.orEmpty(), nav.app.api.coverUrl(album.coverItem),
                    { nav.push(Route.Album(library, album.title, album.artist)) },
                    aspect = 1f, focusKey = "a-${album.artist}-${album.title}", requestFocus = album === distinct.first(),
                )
            }
        }
    }
}

// One artist or author: everything of theirs in this library.
@Composable
fun ArtistScreen(nav: Nav, s: Map<String, String>, library: Long, name: String) {
    val metrics = LocalMetrics.current
    Screen {
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = metrics.gutter).padding(top = Space.S4), verticalArrangement = Arrangement.spacedBy(Space.S3)) {
            Heading(name.ifEmpty { "Unknown" })
            AlbumGrid(nav, s, library, "year", name)
        }
    }
}

// One line of a list of tracks. OK or a tap plays from here. Beside it, and one press to the right on a remote,
// a button adds it to the queue instead.
@Composable
private fun TrackRow(
    nav: Nav,
    track: Item,
    index: Int,
    subtitle: String,
    showArt: Boolean,
    books: Boolean,
    requestFocus: Boolean = false,
    onPlay: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val listening = nav.app.listening
    val isNow = listening.now?.mediaId == track.id.toString()
    var added by remember { mutableStateOf(false) }
    val place = placeOn(track, books)
    val done = books && track.progress?.watched == true
    val state = when {
        isNow -> "Playing"
        done -> "Finished"
        place > 0 -> "${spokenClock(place)} in"
        else -> null
    }
    Row(Modifier.fillMaxWidth().remoteRow(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S2)) {
        FocusBox(
            onPlay, Modifier.weight(1f),
            label = listOf(track.title, subtitle).filter { it.isNotEmpty() }.joinToString(", "),
            state = state, selected = isNow, focusKey = "t-${track.id}", requestFocus = requestFocus,
            filled = if (isNow) scheme.surfaceVariant else scheme.surface,
        ) {
            Row(Modifier.padding(horizontal = Space.S3, vertical = Space.S2), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S3)) {
                if (showArt) {
                    ServerImage(nav.app.api.posterUrl(track), ROW_ART, 1f, Modifier.size(ROW_ART).clip(Radius.SM))
                } else {
                    Box(Modifier.width(Space.S8), contentAlignment = Alignment.CenterEnd) {
                        if (isNow) Icon(Icons.Filled.PlayArrow, null, tint = scheme.primary)
                        else Text((track.track ?: (index + 1)).toString(), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                Column(Modifier.weight(1f)) {
                    Text(track.title, color = scheme.onBackground, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val under = listOfNotNull(subtitle.ifEmpty { null }, if (done) "Finished" else null, if (place > 0) "${clock(place)} in" else null).joinToString(" · ")
                    if (under.isNotEmpty()) Secondary(under, maxLines = 1)
                }
                if (track.runtimeSec > 0) Secondary(clock(track.runtimeSec))
            }
        }
        RoundButton(
            if (added) Icons.Filled.Check else Icons.Filled.Add,
            if (added) "${track.title} is in the queue" else "Add ${track.title} to the queue",
            { if (!added) { nav.app.listening.addToQueue(listOf(track), books); added = true } },
            focusKey = "add-${track.id}",
        )
    }
}

// A round button with a picture and no words, except for those who can't see it.
@Composable
fun RoundButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    selected: Boolean = false,
    enabled: Boolean = true,
    size: Dp = LocalMetrics.current.minTarget,
    focusKey: String? = null,
    requestFocus: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    FocusBox(
        onClick, modifier, label = label, state = if (selected) "On" else null, selected = selected, focusKey = focusKey, requestFocus = requestFocus,
        enabled = enabled, filled = if (primary) scheme.primary else if (selected) scheme.outline else androidx.compose.ui.graphics.Color.Transparent, shape = Radius.FULL,
    ) {
        Box(Modifier.size(size), contentAlignment = Alignment.Center) {
            Icon(
                icon, null, Modifier.size(size * ICON_PART),
                tint = (if (primary) scheme.onPrimary else if (selected) scheme.primary else scheme.onSurface).copy(alpha = if (enabled) 1f else DISABLED_ALPHA),
            )
        }
    }
}

private const val ICON_PART = 0.56f
private const val DISABLED_ALPHA = 0.45f
private const val UPRIGHT_BELOW = 600
