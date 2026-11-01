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
import com.wittywilla.wittymediaclient.net.GAME_PCS_PATH
import com.wittywilla.wittymediaclient.net.Home
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.Show
import com.wittywilla.wittymediaclient.net.ShowDetail
import com.wittywilla.wittymediaclient.net.isRigGame
import com.wittywilla.wittymediaclient.net.isRigGames
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlin.math.absoluteValue

// What plays in this app for now. Discs, books and games stay in the web interface until their
// phases, and say so: see docs/DESIGN.md.
private val PLAYABLE = setOf("video", "audio", "radio")
private const val MUSIC_KIND = "audio"

fun episodeLabel(it: Item): String {
    val season = it.season ?: return ""
    val episode = it.episode ?: return ""
    if (episode < 0) return ""
    val ep = if (it.episodeEnd != null && it.episodeEnd != 0) "E$episode–${it.episodeEnd}" else "E$episode"
    return if (season == 0) "Special · $ep" else "S$season · $ep"
}

private fun itemSubtitle(it: Item) = episodeLabel(it).ifEmpty { it.year?.toString().orEmpty() }

private fun progressOf(it: Item): Float? {
    val p = it.progress ?: return null
    if (p.watched || p.durationSec <= 0 || p.positionSec <= 0) return null
    return (p.positionSec / p.durationSec).toFloat()
}

@Composable
fun ItemCard(nav: Nav, it: Item, requestFocus: Boolean = false, scope: String = "") {
    PosterCard(
        it.showTitle?.takeIf { s -> s.isNotEmpty() } ?: it.title, itemSubtitle(it), nav.app.api.posterUrl(it), { nav.push(Route.Item(it.id)) },
        aspect = if (it.kind == MUSIC_KIND) 1f else 2f / 3f, focusKey = "$scope-i${it.id}", requestFocus = requestFocus, progress = progressOf(it),
    )
}

@Composable
fun ShowCard(nav: Nav, s: Show, requestFocus: Boolean = false, scope: String = "") {
    val label = if (s.unwatched > 0) "${s.unwatched} unwatched" else s.year?.toString().orEmpty()
    PosterCard(s.title, label, nav.app.api.showPosterUrl(s), { nav.push(Route.Show(s.id)) }, focusKey = "$scope-s${s.id}", requestFocus = requestFocus)
}

@Composable
private fun LoadFailed(nav: Nav, message: String, retry: () -> Unit) {
    Column(Modifier.fillMaxSize().safeDrawingPadding().padding(Space.S8), verticalArrangement = Arrangement.spacedBy(Space.S3)) {
        ErrorText(message)
        ActionButton("Try again", retry, requestFocus = true)
        ActionButton("Change server", nav::changeServer)
    }
}

private fun Item.playRoute(): Route =
    if (kind in PLAYABLE) Route.Player(id, false) else Route.Item(id)

// The first thing on Home. On a phone, posters to swipe through, with the one in front named below
// and a Play pill, in the layout people know from the big music and video apps. On a TV, the
// picture across the top. Either way it's only a shortcut: every item is in the rows below too.
@Composable
private fun PhoneHero(nav: Nav, featured: List<Item>) {
    val pager = rememberPagerState { featured.size }
    val reduce = LocalReduceMotion.current
    val front = featured[pager.currentPage.coerceIn(0, featured.lastIndex)]
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        // Whatever the width, the poster in front sits in the middle.
        val side = ((maxWidth - HERO_POSTER) / 2).coerceAtLeast(0.dp)
        // The front poster's own colours would need a blur, which old phones can't do cheaply. A
        // dimmed backdrop fading into the page gives much the same depth.
        ServerImage(nav.app.api.backdropUrl(front), 400.dp, 1f, Modifier.fillMaxWidth().aspectRatio(1f).alpha(0.35f))
        Box(
            Modifier.matchParentSize().background(
                Brush.verticalGradient(0.3f to Color.Transparent, 1f to MaterialTheme.colorScheme.background),
            ),
        )
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(top = Space.S12), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.S3)) {
            HorizontalPager(
                state = pager,
                pageSize = PageSize.Fixed(HERO_POSTER),
                contentPadding = PaddingValues(horizontal = side),
                pageSpacing = Space.S3,
                modifier = Modifier.fillMaxWidth(),
            ) { page ->
                val item = featured[page]
                FocusBox(
                    { nav.push(Route.Item(item.id)) },
                    // Read as it draws, so a swipe costs a redraw and not a whole recomposition.
                    Modifier.graphicsLayer {
                        val apart = (pager.currentPage - page + pager.currentPageOffsetFraction).absoluteValue.coerceIn(0f, 1f)
                        if (!reduce) { val shrink = 1f - apart * 0.12f; scaleX = shrink; scaleY = shrink }
                        alpha = 1f - apart * 0.4f
                    },
                    label = item.showTitle?.ifEmpty { null } ?: item.title,
                    focusKey = "hero-${item.id}",
                ) {
                    ServerImage(nav.app.api.posterUrl(item), HERO_POSTER, 2f / 3f, Modifier.fillMaxWidth().aspectRatio(2f / 3f).clip(Radius.LG), placeholder = item.title)
                }
            }
            Text(
                front.showTitle?.ifEmpty { null } ?: front.title, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.headlineSmall,
                maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = Space.S6),
            )
            Secondary(listOfNotNull(front.year?.toString(), front.genres.firstOrNull()).joinToString(" · "))
            ActionButton("Play", { nav.push(front.playRoute()) }, primary = true, pill = true, icon = Icons.Filled.PlayArrow, focusKey = "hero-play")
        }
    }
}

// Also for a phone on its side, where a tall poster wouldn't leave room for its own title.
@Composable
private fun TvHero(nav: Nav, item: Item) {
    val metrics = LocalMetrics.current
    val height = if (metrics.tv) 340.dp else 260.dp
    Box(Modifier.fillMaxWidth().height(height)) {
        ServerImage(nav.app.api.backdropUrl(item), 960.dp, 16f / 9f, Modifier.matchParentSize().alpha(0.5f))
        Box(
            Modifier.matchParentSize().background(
                Brush.horizontalGradient(0f to MaterialTheme.colorScheme.background, 0.75f to Color.Transparent),
            ),
        )
        Box(
            Modifier.matchParentSize().background(
                Brush.verticalGradient(0.6f to Color.Transparent, 1f to MaterialTheme.colorScheme.background),
            ),
        )
        Column(Modifier.align(Alignment.CenterStart).padding(start = metrics.gutter).widthIn(max = 560.dp), verticalArrangement = Arrangement.spacedBy(Space.S2)) {
            Text(item.showTitle?.ifEmpty { null } ?: item.title, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.displaySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Secondary(listOfNotNull(item.year?.toString(), item.genres.firstOrNull(), item.contentRating.ifEmpty { null }).joinToString(" · "))
            if (item.overview.isNotEmpty()) Secondary(item.overview, maxLines = 2)
            Row(Modifier.remoteRow(), horizontalArrangement = Arrangement.spacedBy(Space.S3)) {
                ActionButton("Play", { nav.push(item.playRoute()) }, primary = true, pill = true, icon = Icons.Filled.PlayArrow, focusKey = "hero-play", requestFocus = true)
                ActionButton("More", { nav.push(Route.Item(item.id)) }, pill = true, focusKey = "hero-more")
            }
        }
    }
}

// A library's name to go to, along the top like tabs.
@Composable
private fun LibraryTabs(nav: Nav, libraries: List<Library>, extra: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    LazyRow(
        Modifier.remoteRow(),
        contentPadding = PaddingValues(horizontal = metrics.gutter),
        horizontalArrangement = Arrangement.spacedBy(Space.S2),
    ) {
        items(libraries, key = { it.id }) { lib ->
            ActionButton(lib.name, { nav.push(Route.Library(lib)) }, pill = true, focusKey = "lib-${lib.id}")
        }
        item(key = "extra") { extra() }
    }
}

@Composable
fun HomeScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    var home by remember { mutableStateOf(nav.remembered<Home>("home")) }
    var error by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    var gamePcs by remember { mutableStateOf(false) }
    val sideways = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    // Phones and tablets only: see rigChoice for why TVs don't play in the page.
    LaunchedEffect(Unit) {
        if (!nav.app.isTv && !nav.app.isFireTv) gamePcs = runCatching { nav.app.api.couchStatus().allowed }.getOrDefault(false)
    }
    LaunchedEffect(attempt) {
        error = ""
        try {
            val fresh = nav.app.api.home()
            home = fresh
            nav.remember("home", fresh)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) error = problemWords(e, s["errLost"].orEmpty())
        }
    }
    val h = home
    when {
        h == null && error.isNotEmpty() -> LoadFailed(nav, error) { attempt++ }
        h == null -> Loading()
        else -> LazyColumn(
            contentPadding = PaddingValues(bottom = LocalBottomRoom.current + Space.S6),
            verticalArrangement = Arrangement.spacedBy(Space.S5),
        ) {
            val hubs = h.hubs.filter { it.items.isNotEmpty() || it.shows.isNotEmpty() }.distinctBy { it.key }
            // Featured first, and otherwise whatever someone was in the middle of.
            val heroes = h.featured.ifEmpty { hubs.firstOrNull()?.items.orEmpty() }.distinctBy { it.id }.take(HERO_ITEMS)
            if (heroes.isNotEmpty()) {
                item(key = "hero") { if (metrics.tv || sideways) TvHero(nav, heroes.first()) else PhoneHero(nav, heroes) }
            } else {
                item(key = "top") { Box(Modifier.statusBarsPadding()) }
            }
            if (error.isNotEmpty() || nav.notice.isNotEmpty()) {
                item(key = "problem") {
                    Column(Modifier.padding(horizontal = metrics.gutter), verticalArrangement = Arrangement.spacedBy(Space.S2)) {
                        ErrorText(error)
                        ErrorText(nav.notice)
                        if (error.isNotEmpty()) ActionButton("Try again", { attempt++ }, focusKey = "retry")
                    }
                }
            }
            item(key = "libraries") {
                LibraryTabs(nav, h.libraries.distinctBy { it.id }) {
                    if (gamePcs) ActionButton("Game PCs", { nav.push(Route.Web(GAME_PCS_PATH)) }, pill = true, focusKey = "gamepcs")
                }
            }
            items(hubs, key = { it.key }) { hub ->
                Column(verticalArrangement = Arrangement.spacedBy(Space.S2)) {
                    SectionTitle(hub.title, Modifier.padding(horizontal = metrics.gutter))
                    LazyRow(
                        Modifier.remoteRow(),
                        contentPadding = PaddingValues(horizontal = metrics.gutter, vertical = Space.S1),
                        horizontalArrangement = Arrangement.spacedBy(Space.S3),
                    ) {
                        items(hub.items.distinctBy { it.id }, key = { "i${it.id}" }) { ItemCard(nav, it, scope = hub.key) }
                        items(hub.shows.distinctBy { it.id }, key = { "s${it.id}" }) { ShowCard(nav, it, scope = hub.key) }
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

@Composable
fun LibraryScreen(nav: Nav, s: Map<String, String>, library: Library) {
    val metrics = LocalMetrics.current
    val isShows = library.type == "shows" || library.type == "anime"
    val items = remember { mutableStateListOf<Item>() }
    val shows = remember { mutableStateListOf<Show>() }
    var total by remember { mutableIntStateOf(-1) }
    var error by remember { mutableStateOf("") }
    var wanted by remember { mutableIntStateOf(0) }

    LaunchedEffect(library.id, wanted) {
        error = ""
        try {
            // Repeated keys crash a lazy grid, and the library can change between pages.
            if (isShows) {
                val page = nav.app.api.shows(library.id, shows.size, PAGE)
                val seen = shows.mapTo(HashSet()) { it.id }
                shows.addAll(page.shows.filter { it.id !in seen }.distinctBy { it.id })
                total = page.total
            } else {
                val page = nav.app.api.items(library.id, items.size, PAGE)
                val seen = items.mapTo(HashSet()) { it.id }
                items.addAll(page.items.filter { it.id !in seen }.distinctBy { it.id })
                total = page.total
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) error = problemWords(e, s["errLost"].orEmpty())
        }
    }

    Screen {
        when {
            error.isNotEmpty() && total < 0 -> LoadFailed(nav, error) { error = ""; wanted++ }
            total < 0 -> Loading()
            else -> Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = metrics.gutter).padding(top = Space.S4), verticalArrangement = Arrangement.spacedBy(Space.S3)) {
                Heading(library.name)
                if (total == 0) Secondary("Nothing here yet.")
                ErrorText(error)
                if (error.isNotEmpty()) ActionButton("Try again", { error = ""; wanted++ }, focusKey = "retry")
                val loaded = if (isShows) shows.size else items.size
                LazyVerticalGrid(
                    posterColumns(),
                    contentPadding = PaddingValues(bottom = Space.S6),
                    horizontalArrangement = Arrangement.spacedBy(Space.S2),
                    verticalArrangement = Arrangement.spacedBy(Space.S4),
                ) {
                    // Near the end of what's loaded: fetch the next page.
                    if (isShows) {
                        items(shows, key = { it.id }) {
                            ShowCard(nav, it, requestFocus = it.id == shows.first().id)
                            if (it.id == shows.lastOrNull()?.id && loaded < total) LaunchedEffect(loaded) { wanted++ }
                        }
                    } else {
                        items(items, key = { it.id }) {
                            ItemCard(nav, it, requestFocus = it.id == items.first().id)
                            if (it.id == items.lastOrNull()?.id && loaded < total) LaunchedEffect(loaded) { wanted++ }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ShowScreen(nav: Nav, s: Map<String, String>, id: Long) {
    val metrics = LocalMetrics.current
    var detail by remember { mutableStateOf(nav.remembered<ShowDetail>("show-$id")) }
    var error by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    var season by rememberSaveable { mutableStateOf<Int?>(null) }
    LaunchedEffect(id, attempt) {
        error = ""
        try {
            val fresh = nav.app.api.show(id)
            detail = fresh
            nav.remember("show-$id", fresh)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) error = problemWords(e, s["errLost"].orEmpty())
        }
    }
    Screen {
        val d = detail
        when {
            d == null && error.isNotEmpty() -> LoadFailed(nav, error) { attempt++ }
            d == null -> Loading()
            else -> {
                val selected = season ?: d.seasons.firstOrNull()?.number
                LazyColumn(
                    Modifier.safeDrawingPadding(),
                    contentPadding = PaddingValues(horizontal = metrics.gutter, vertical = Space.S4),
                    verticalArrangement = Arrangement.spacedBy(Space.S2),
                ) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(Space.S2)) {
                            Heading(d.show.title)
                            if (d.show.overview.isNotEmpty()) Secondary(d.show.overview, maxLines = 4)
                            ErrorText(error)
                            d.nextUpId?.let { next ->
                                val episode = d.episodes.firstOrNull { it.id == next }?.let(::episodeLabel).orEmpty()
                                ActionButton(if (episode.isEmpty()) "Next up" else "Next up: $episode", { nav.push(Route.Item(next)) }, primary = true, pill = true, icon = Icons.Filled.PlayArrow, focusKey = "nextup", requestFocus = true)
                            }
                        }
                    }
                    item {
                        LazyRow(Modifier.remoteRow(), horizontalArrangement = Arrangement.spacedBy(Space.S2)) {
                            items(d.seasons.distinctBy { it.number }, key = { it.number }) { one ->
                                val title = one.title.ifEmpty { if (one.number == 0) "Specials" else "Season ${one.number}" }
                                ActionButton(title, { season = one.number }, selected = one.number == selected, pill = true, focusKey = "season-${one.number}", requestFocus = d.nextUpId == null && one.number == selected)
                            }
                        }
                    }
                    items(d.episodes.filter { it.season == selected }.distinctBy { it.id }, key = { it.id }) { ep ->
                        val watched = ep.progress?.watched == true
                        FocusBox(
                            { nav.push(Route.Item(ep.id)) }, Modifier.fillMaxWidth(),
                            label = "${episodeLabel(ep)}, ${ep.title}", state = if (watched) "Watched" else null,
                            focusKey = "ep-${ep.id}", filled = MaterialTheme.colorScheme.surface,
                        ) {
                            Column(Modifier.padding(Space.S3)) {
                                Text("${episodeLabel(ep)}  ${ep.title}", color = MaterialTheme.colorScheme.onBackground)
                                if (watched) Secondary("Watched")
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun runtimeText(sec: Double): String {
    if (sec <= 0) return ""
    val h = (sec / 3600).toInt()
    val m = ((sec % 3600) / 60).toInt()
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
            else -> FlowRow(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).safeDrawingPadding().padding(horizontal = metrics.gutter, vertical = Space.S6),
                horizontalArrangement = Arrangement.spacedBy(Space.S6),
                verticalArrangement = Arrangement.spacedBy(Space.S4),
            ) {
                // Beside the words where there's room, above them on a phone held upright.
                ServerImage(nav.app.api.posterUrl(it), metrics.cardWidth * 1.4f, 2f / 3f, Modifier.width(metrics.cardWidth * 1.4f).aspectRatio(2f / 3f).clip(Radius.LG), placeholder = it.title)
                Column(Modifier.widthIn(min = 280.dp, max = 640.dp).weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(Space.S3)) {
                    if (!it.showTitle.isNullOrEmpty()) Secondary("${it.showTitle} · ${episodeLabel(it)}")
                    Heading(it.title)
                    Secondary(listOfNotNull(it.year?.toString(), runtimeText(it.runtimeSec).ifEmpty { null }, it.contentRating.ifEmpty { null }).joinToString(" · "))
                    if (it.genres.isNotEmpty()) Secondary(it.genres.joinToString(", "))
                    ErrorText(error)
                    if (it.isRigGame) {
                        if (it.tagline.isNotEmpty()) Secondary(it.tagline)
                        RigPlayPanel(nav, it)
                    } else if (it.kind in PLAYABLE) {
                        // The server decides where Resume goes; 0 means start over.
                        val resume = (it.progress?.resumeSec ?: 0.0) > 0
                        Row(Modifier.remoteRow(), horizontalArrangement = Arrangement.spacedBy(Space.S3)) {
                            ActionButton(if (resume) "Resume" else "Play",{ nav.push(Route.Player(it.id, false)) }, primary = true, pill = true, icon = Icons.Filled.PlayArrow, focusKey = "play", requestFocus = true)
                            if (resume) ActionButton("Start over", { nav.push(Route.Player(it.id, true)) }, pill = true, focusKey = "startover")
                        }
                    } else {
                        Secondary("This kind of item can't play in this app yet. Open it in a web browser.")
                        ActionButton("Back", nav::pop, requestFocus = true)
                    }
                    if (it.overview.isNotEmpty()) Text(it.overview, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
