// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.COLLECTIONS_PATH
import com.wittywilla.wittymediaclient.net.GAME_PCS_PATH
import com.wittywilla.wittymediaclient.net.GUIDE_PATH
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.tv.watchChannel
import com.wittywilla.wittymediaclient.net.Home
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.Show
import com.wittywilla.wittymediaclient.net.ShowDetail
import com.wittywilla.wittymediaclient.net.albumsOnce
import com.wittywilla.wittymediaclient.net.channelPath
import com.wittywilla.wittymediaclient.net.fraction
import com.wittywilla.wittymediaclient.net.minutesLeft
import com.wittywilla.wittymediaclient.net.onNow
import com.wittywilla.wittymediaclient.net.programmeAt
import com.wittywilla.wittymediaclient.net.hasOwnScreen
import com.wittywilla.wittymediaclient.net.isRigGame
import com.wittywilla.wittymediaclient.net.isRigGames
import com.wittywilla.wittymediaclient.net.isTrack
import com.wittywilla.wittymediaclient.net.pagePath
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlin.math.absoluteValue

fun episodeLabel(it: Item): String {
    val season = it.season ?: return ""
    val episode = it.episode ?: return ""
    if (episode < 0) return ""
    val ep = if (it.episodeEnd != null && it.episodeEnd != 0) "E$episode–${it.episodeEnd}" else "E$episode"
    return if (season == 0) "Special · $ep" else "S$season · $ep"
}

private fun itemSubtitle(it: Item) = when {
    it.isTrack -> it.albumArtist.ifEmpty { it.artist }
    else -> episodeLabel(it).ifEmpty { it.year?.toString().orEmpty() }
}

private fun progressOf(it: Item): Float? {
    val p = it.progress ?: return null
    if (p.watched || p.durationSec <= 0 || p.positionSec <= 0) return null
    return (p.positionSec / p.durationSec).toFloat()
}

@Composable
fun ItemCard(nav: Nav, it: Item, requestFocus: Boolean = false, scope: String = "") {
    PosterCard(
        it.showTitle?.takeIf { s -> s.isNotEmpty() } ?: it.title, itemSubtitle(it), nav.app.api.posterUrl(it), { nav.open(it) },
        aspect = if (it.isTrack) 1f else 2f / 3f, focusKey = "$scope-i${it.id}", requestFocus = requestFocus, progress = progressOf(it),
    )
}

@Composable
fun ShowCard(nav: Nav, s: Show, requestFocus: Boolean = false, scope: String = "") {
    val label = if (s.unwatched > 0) "${s.unwatched} unwatched" else s.year?.toString().orEmpty()
    PosterCard(s.title, label, nav.app.api.showPosterUrl(s), { nav.push(Route.Show(s.id)) }, focusKey = "$scope-s${s.id}", requestFocus = requestFocus)
}

@Composable
fun LoadFailed(nav: Nav, message: String, retry: () -> Unit) {
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(Space.S8), verticalArrangement = Arrangement.spacedBy(Space.S3)) {
        ErrorText(message)
        ActionButton("Try again", retry, requestFocus = true)
        ActionButton("Change server", nav::changeServer)
    }
}

fun Nav.play(item: Item) = when {
    item.isTrack -> playTrack(item)
    // The website's disc and CD players, as Play does there.
    item.isDisc && !app.isTv -> push(Route.Page("/play/${item.id}"))
    item.kind == "cd-image" && !app.isTv -> push(Route.Page("/cd/${item.id}?play=1"))
    item.isRigGame -> push(Route.Item(item.id))
    item.hasOwnScreen -> push(Route.Player(item.id, false))
    else -> push(gamesRouteFor(item) ?: Route.Page(item.pagePath()))
}

// Apple TV's hero sizes, in TV units: at least 620 high, its words up to half the screen.
private const val TV_HERO_HEIGHT = 620
private const val TV_HERO_WORDS = 900

// What's on the channels right now, as on the server's own Home. Choosing one watches it.
@Composable
private fun OnNowRow(nav: Nav, channels: List<GuideChannel>) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val width = metrics.cardWidth * ON_NOW_WIDTH
    val now = remember { System.currentTimeMillis() / 1000 }
    Column(verticalArrangement = Arrangement.spacedBy(Space.S2)) {
        SectionTitle("On TV now", Modifier.padding(horizontal = metrics.gutter))
        LazyRow(
            Modifier.remoteRow(),
            contentPadding = PaddingValues(horizontal = metrics.gutter, vertical = Space.S1),
            horizontalArrangement = Arrangement.spacedBy(Space.S3),
        ) {
            items(channels, key = { it.key }) { channel ->
                val on = channel.programmeAt(now)
                val words = on?.title ?: "Nothing listed"
                FocusBox(
                    { if (nav.app.isTv) nav.watchChannel(channel.key) else nav.push(Route.Page(channelPath(channel.key))) }, Modifier.width(width),
                    label = "Channel ${channel.number}, ${channel.name}: $words", focusKey = "onnow-${channel.key}",
                ) {
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.S1)) {
                        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(Radius.MD).background(scheme.surfaceVariant)) {
                            on?.itemId?.let { ServerImage(nav.app.api.itemBackdropUrl(it), width, 16f / 9f, Modifier.fillMaxSize()) }
                            Text(channel.number, color = Color.White, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(Space.S2).background(Color(0x99000000), Radius.XS).padding(horizontal = Space.S1))
                            if (on != null) {
                                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(Space.S1).background(Color(0x99000000), Radius.XS)) {
                                    Box(Modifier.fillMaxWidth(on.fraction(now)).height(Space.S1).background(scheme.primary, Radius.XS))
                                }
                            }
                        }
                        Text(words, color = scheme.onBackground, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(horizontal = Space.S1))
                        Text(channel.name + if (on != null) " · ${on.minutesLeft(now)} min left" else "", color = scheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = Space.S1))
                    }
                }
            }
        }
    }
}

private const val HERO_ITEMS = 8
private val HERO_POSTER = 220.dp
private const val PAGE = 60

// Posters to fill the width. A card can be a little narrower than in a row: three fit across a phone.
@Composable
fun posterColumns() = GridCells.Adaptive(LocalMetrics.current.cardWidth - Space.S3)

private fun runtimeText(sec: Double): String {
    if (sec <= 0) return ""
    val h = (sec / 3600).toInt()
    val m = ((sec % 3600 + 30) / 60).toInt()
    return if (h > 0) "$h h $m min" else "$m min"
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ItemScreen(nav: Nav, s: Map<String, String>, id: Long) {
    val metrics = LocalMetrics.current
    var item by remember { mutableStateOf(nav.remembered<Item>("item-$id")) }
    var error by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(id, attempt) {
        error = ""
        try {
            val fresh = nav.app.api.item(id)
            item = fresh
            nav.remember("item-$id", fresh)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) error = problemWords(e, s["errLost"].orEmpty())
        }
    }
    Screen {
        val it = item
        when {
            it == null && error.isNotEmpty() -> LoadFailed(nav, error) { attempt++ }
            it == null -> Loading()
            else -> Box(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                // Making a canvas for an administrator, where to watch, and the title's canvas (TitleAdmin.kt, CanvasLoop.kt).
                val made = rememberItemExtras(nav, it.id)
                // The picture behind, fading into the page, as on Home.
                ServerImage(nav.app.api.backdropUrl(it), 960.dp, 16f / 9f, Modifier.fillMaxWidth().height(BACKDROP_HEIGHT).alpha(0.4f))
                CanvasBackdrop(nav, it.id, Modifier.fillMaxWidth().height(BACKDROP_HEIGHT).alpha(0.4f), made.canvasAgain)
                Box(Modifier.fillMaxWidth().height(BACKDROP_HEIGHT).background(Brush.verticalGradient(0.2f to Color.Transparent, 1f to MaterialTheme.colorScheme.background)))
                val upright = !metrics.tv && LocalConfiguration.current.screenWidthDp < UPRIGHT_BELOW_DP
                FlowRow(
                Modifier.fillMaxWidth().safeDrawingPadding().padding(horizontal = metrics.gutter, vertical = Space.S6),
                horizontalArrangement = Arrangement.spacedBy(Space.S6, if (upright) Alignment.CenterHorizontally else Alignment.Start),
                verticalArrangement = Arrangement.spacedBy(Space.S4),
            ) {
                // Beside the words where there's room, above them on a phone held upright.
                ServerImage(nav.app.api.posterUrl(it), metrics.cardWidth * 1.4f, 2f / 3f, Modifier.width(metrics.cardWidth * 1.4f).aspectRatio(2f / 3f).clip(Radius.LG), placeholder = it.title)
                Column((if (upright) Modifier.fillMaxWidth() else Modifier.widthIn(min = 280.dp, max = 640.dp).weight(1f, fill = false)), verticalArrangement = Arrangement.spacedBy(Space.S3)) {
                    if (!it.showTitle.isNullOrEmpty()) Secondary("${it.showTitle} · ${episodeLabel(it)}")
                    Heading(it.title)
                    Secondary(listOfNotNull(it.year?.toString(), runtimeText(it.runtimeSec).ifEmpty { null }, it.contentRating.ifEmpty { null }).joinToString(" · "))
                    if (it.genres.isNotEmpty()) Secondary(it.genres.joinToString(", "))
                    ErrorText(error)
                    if (it.isRigGame) {
                        if (it.tagline.isNotEmpty()) Secondary(it.tagline)
                        RigPlayPanel(nav, it)
                    } else if (it.hasOwnScreen) {
                        // The server decides where Resume goes; 0 means start over.
                        val resume = (it.progress?.resumeSec ?: 0.0) > 0
                        Row(Modifier.remoteRow(), horizontalArrangement = Arrangement.spacedBy(Space.S3)) {
                            ActionButton(if (resume) "Resume" else "Play",{ nav.push(Route.Player(it.id, false)) }, primary = true, pill = true, icon = Icons.Filled.PlayArrow, focusKey = "play", requestFocus = true)
                            if (resume) ActionButton("Start over", { nav.push(Route.Player(it.id, true)) }, pill = true, focusKey = "startover")
                            // Watch party and Play on…, where the server and this profile have them (RemoteScreens.kt).
                            if (it.kind == "video" && nav.has(com.wittywilla.wittymediaclient.player.SYNCPLAY_FEATURE)) ActionButton("Watch party", { nav.push(RemoteRoute.Party(it.id)) }, pill = true, focusKey = "party")
                            if (nav.app.remote.canControl) ActionButton("Play on…", { nav.push(RemoteRoute.PlayOn(com.wittywilla.wittymediaclient.net.remote.PlayOnSource(it.id, it.title, it.kind))) }, pill = true, focusKey = "play-on")
                        }
                    } else {
                        ActionButton("Open", { nav.replace(Route.Page(it.pagePath())) }, primary = true, pill = true, icon = Icons.Filled.PlayArrow, requestFocus = true)
                    }
                    if (it.overview.isNotEmpty()) Text(it.overview, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (it.hasOwnScreen && !it.isRigGame) TvItemExtras(nav, it, made)
                }
            }
            }
        }
    }
}

private val BACKDROP_HEIGHT = 340.dp
private const val ON_NOW_HOURS = 1
private const val ON_NOW_CHANNELS = 20
private const val ON_NOW_WIDTH = 1.5f
private val EPISODE_PICTURE = 120.dp
private const val UPRIGHT_BELOW_DP = 600
