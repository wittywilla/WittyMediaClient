package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import com.wittywilla.wittymediaclient.net.GUIDE_PATH
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.pagePath
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException

// Android TV's bar along the top and the three tabs only a TV has: Libraries, Games and Live TV
// (docs/APP-DESIGN.md, On a TV). Apple TV has the same (apple/App/TvTabs.swift), at the same sizes in TV units,
// with the same focus and the same Back.

private class TvTab(val route: Route, val word: String, val icon: ImageVector?)

// In the bar's order. You has no icon: it shows the person's avatar and name.
private val TV_TABS = listOf(
    TvTab(Route.Home, "homeTab", Symbols.Home),
    TvTab(Route.Libraries, "librariesTab", Symbols.Libraries),
    TvTab(Route.Games, "gamesTab", Symbols.Games),
    TvTab(Route.LiveTv, "liveTvTab", Symbols.LiveTv),
    TvTab(Route.Search, "searchTab", Symbols.Search),
    TvTab(Route.Profile, "youTab", null),
)

// The tabs Back leaves for Home, rather than leaving the app.
val TABS_BESIDE_HOME = setOf(Route.Libraries, Route.Games, Route.LiveTv, Route.Search, Route.Profile)

// You's avatar with 12 above and below it, the same for every pill.
private const val PILL_HEIGHT = 52

// Where focus is between the bar and the tab below it, for a page in a tab that has its own idea of Back.
class TvBar(private val nav: Nav, private val requesters: Map<Route, FocusRequester>) {
    var inBar by mutableStateOf(false)

    // Up to the chosen tab's pill.
    fun focusPill() {
        runCatching { requesters.getValue(nav.current).requestFocus() }
    }
}

val LocalTvBar = compositionLocalOf<TvBar?> { null }

// A tab's first screen under the bar. Back from inside it goes up to its pill; Back from the bar goes to Home's
// pill; Back on Home's pill leaves the app, as the system does.
@Composable
fun TvShell(nav: Nav, content: @Composable () -> Unit) {
    val requesters = remember { TV_TABS.associate { it.route to FocusRequester() } }
    val bar = remember { TvBar(nav, requesters) }
    val onTab = nav.stack.size == 1 && requesters.containsKey(nav.current)
    BackHandler(enabled = onTab && !(bar.inBar && nav.current == Route.Home)) {
        if (!bar.inBar) {
            bar.focusPill()
        } else {
            // Home comes back with its pill chosen and focused.
            nav.focusFor(Route.Home.key).last = pillKey(Route.Home)
            nav.reset(Route.Home)
        }
    }
    Column(Modifier.fillMaxSize()) {
        TvTopBar(nav, requesters) { bar.inBar = it }
        Box(Modifier.weight(1f)) { CompositionLocalProvider(LocalTvBar provides bar) { content() } }
    }
}

// The server's page as a tab's own: its Back closes what's open on it and goes back through it, then up to the bar;
// from the bar it's the bar's. The page has the remote's arrows to itself.
@Composable
private fun PageInTab(nav: Nav, route: Route, path: String) {
    val bar = LocalTvBar.current
    ServerPageScreen(nav, route, path, keptToGames = false, out = { bar?.focusPill() }, backEnabled = bar?.inBar != true)
}

private fun pillKey(route: Route) = "tab-${route.key}"

// Pills the gutter in from the sides and 24 below the top of the picture's safe area, as on Apple TV: Home, Libraries,
// Games, Live TV and Search from the left, You on its own at the right edge. Each keeps room for its ring round it, so
// the pills themselves start at the gutter and sit 16 apart. Focus goes along the whole row, You last. Up from a tab
// lands on that tab's pill, whichever pill happens to be above.
@Composable
private fun TvTopBar(nav: Nav, requesters: Map<Route, FocusRequester>, onFocus: (Boolean) -> Unit) {
    val metrics = LocalMetrics.current
    val ring = metrics.focusRing
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = metrics.gutter - ring, end = metrics.gutter - ring, top = metrics.tvSafeEnds + metrics.u(24) - ring, bottom = metrics.u(16) - ring)
            .focusProperties { onEnter = { requesters[nav.current]?.requestFocus() } }
            .onFocusChanged { onFocus(it.hasFocus) }
            .focusGroup(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(metrics.u(16) - ring * 2),
    ) {
        TV_TABS.forEach {
            // Space, not a line, keeps You apart from the rest, at the right edge.
            if (it.route == Route.Profile) Spacer(Modifier.weight(1f).widthIn(min = metrics.u(32)))
            TvTabPill(nav, it, requesters.getValue(it.route))
        }
    }
}

// A tab's icon and name, or You's avatar and the person's name. The chosen one has the accent behind it and its words
// in `accentText`; the others are `textSecondary`. Choosing one keeps focus on it, one press from what's below.
@Composable
private fun TvTabPill(nav: Nav, tab: TvTab, requester: FocusRequester) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val words = LocalWords.current
    val chosen = nav.current == tab.route
    val ink = if (chosen) LocalExtraColours.current.accentText else scheme.onSurfaceVariant
    val title = words[tab.word].orEmpty()
    val me = nav.me
    val person = if (me == null) "" else avatarName(me.displayName, me.name)
    Pressable(
        {
            if (!chosen) {
                // The tab opens with focus still on its pill, rather than on its page's own first focus.
                nav.focusFor(tab.route.key).last = pillKey(tab.route)
                nav.reset(tab.route)
            }
        },
        shape = Radius.FULL,
        fill = if (chosen) scheme.primary.copy(alpha = ACCENT_TINT) else Color.Transparent,
        label = title,
        state = if (chosen) "Selected" else null,
        selected = chosen,
        focusKey = pillKey(tab.route),
        focusRequester = requester,
    ) {
        Row(
            Modifier.height(metrics.u(PILL_HEIGHT)).padding(horizontal = metrics.u(24)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            if (tab.icon != null) {
                // Material Symbols leave more room round their shapes than SF Symbols, so the box is larger for the
                // same size of icon as Apple TV's.
                Icon(tab.icon, contentDescription = null, tint = ink, modifier = Modifier.size(metrics.u(BAR_ICON)))
                Text(title, color = ink, style = MaterialTheme.typography.label, maxLines = 1)
            } else {
                Avatar(person.ifEmpty { "?" }, metrics.u(28))
                Text(person.ifEmpty { title }, color = ink, style = MaterialTheme.typography.label, maxLines = 1)
            }
        }
    }
}

private const val ACCENT_TINT = 0.14f
private const val BAR_ICON = 44
private const val TILE_ICON = 40

// What a tab says when its server has nothing for it: what's missing, and who adds it.
@Composable
private fun TvEmpty(title: String, detail: String) {
    val metrics = LocalMetrics.current
    Box(Modifier.fillMaxSize().padding(metrics.u(32)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
            Text(title, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.section, modifier = Modifier.semantics { heading() })
            Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, textAlign = TextAlign.Center)
        }
    }
}

// The libraries this profile can see, asked for again each time a tab shows them.
@Composable
private fun rememberLibraries(nav: Nav, s: Map<String, String>, attempt: Int): Pair<List<Library>?, String> {
    var libraries by remember { mutableStateOf(nav.remembered<List<Library>>("libraries")) }
    var error by remember { mutableStateOf("") }
    LaunchedEffect(attempt) {
        error = ""
        try {
            val fresh = nav.app.api.libraries().distinctBy { it.id }
            libraries = fresh
            nav.remember("libraries", fresh)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) error = problemWords(e, s["errLost"].orEmpty())
        }
    }
    return libraries to error
}

// Every library this profile can see, as tiles: the phone's Menu list as a page. Each opens as it does from Home.
@Composable
fun LibrariesScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val ring = metrics.focusRing
    var attempt by remember { mutableIntStateOf(0) }
    val (libraries, error) = rememberLibraries(nav, s, attempt)
    when {
        libraries == null && error.isNotEmpty() -> LoadFailed(nav, error) { attempt++ }
        libraries == null -> Loading()
        libraries.isEmpty() -> TvEmpty(s["librariesNone"].orEmpty(), s["librariesNoneDetail"].orEmpty())
        // The tiles keep their rings' room inside them: 32 between tiles, the first at the gutter.
        else -> LazyVerticalGrid(
            GridCells.Fixed(LIBRARY_COLUMNS),
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = metrics.gutter - ring, end = metrics.gutter - ring, top = metrics.u(24) - ring, bottom = metrics.u(32)),
            horizontalArrangement = Arrangement.spacedBy(metrics.u(32) - ring * 2),
            verticalArrangement = Arrangement.spacedBy(metrics.u(32) - ring * 2),
        ) {
            items(libraries, key = { it.id }) { library -> LibraryTile(library) { nav.open(library) } }
        }
    }
}

private const val LIBRARY_COLUMNS = 4

// The website's library tile at a TV's size: the library's icon on the accent, then its name.
@Composable
private fun LibraryTile(library: Library, onClick: () -> Unit) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val shape = metrics.corner(14)
    Pressable(onClick, Modifier.fillMaxWidth(), shape = shape, fill = scheme.surface, label = library.name, focusKey = "library-${library.id}") {
        Row(
            Modifier.fillMaxWidth().border(metrics.u(1), scheme.outline, shape).padding(metrics.u(16)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(16)),
        ) {
            Box(
                Modifier.size(metrics.u(60)).background(scheme.primary.copy(alpha = ACCENT_TINT), metrics.corner(10)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(library.tileSymbol, contentDescription = null, tint = LocalExtraColours.current.accentText, modifier = Modifier.size(metrics.u(TILE_ICON)))
            }
            Text(library.name, color = scheme.onBackground, style = MaterialTheme.typography.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// The website's icon for each kind of library (its icons.tsx, `libIcon`), as Apple TV has them.
private val Library.tileSymbol: ImageVector
    get() = when (type) {
        "games" -> Symbols.GamesFilled
        "photos" -> Symbols.PhotoFilled
        "shorts" -> Symbols.ShortsFilled
        "channels", "musicvideos" -> Symbols.ChannelFilled
        "radio" -> Symbols.RadioFilled
        "movies" -> Symbols.MovieFilled
        "shows" -> Symbols.TvFilled
        "anime" -> Symbols.StarFilled
        "music" -> Symbols.MusicFilled
        "podcasts" -> Symbols.MicFilled
        "audiobooks" -> Symbols.HeadphonesFilled
        "books" -> Symbols.BookFilled
        "videos" -> Symbols.VideocamFilled
        else -> Symbols.AlbumFilled
    }

// Games the server plays: a shared PC's games go through Moonlight instead.
private val Library.isWittyPlay get() = type == "games" && console != "rig"

// WittyPlay's games. One games library opens straight in; several are a row each, as Home's rows are: the library's
// name and a pill for the whole of it, then its covers.
@Composable
fun GamesTabScreen(nav: Nav, s: Map<String, String>) {
    var attempt by remember { mutableIntStateOf(0) }
    val (libraries, error) = rememberLibraries(nav, s, attempt)
    val games = libraries?.filter { it.isWittyPlay }
    when {
        games == null && error.isNotEmpty() -> LoadFailed(nav, error) { attempt++ }
        games == null -> Loading()
        games.isEmpty() -> TvEmpty(s["gamesNone"].orEmpty(), s["gamesNoneDetail"].orEmpty())
        games.size == 1 -> GamesLibraryInTab(nav, games.first())
        else -> {
            val metrics = LocalMetrics.current
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(top = metrics.u(24), bottom = metrics.u(24)),
                verticalArrangement = Arrangement.spacedBy(metrics.u(20)),
            ) {
                items(games, key = { it.id }) { GamesShelf(nav, s, it) }
            }
        }
    }
}

// One games library as the tab's own page, with Back from it going up to the bar.
@Composable
private fun GamesLibraryInTab(nav: Nav, library: Library) {
    PageInTab(nav, Route.Games, library.pagePath())
}

// One games library's row: its name and a pill that opens it, then its covers.
@Composable
private fun GamesShelf(nav: Nav, s: Map<String, String>, library: Library) {
    val metrics = LocalMetrics.current
    var games by remember(library.id) { mutableStateOf<List<Item>?>(null) }
    LaunchedEffect(library.id) {
        games = try {
            nav.app.api.popularGames(library.id, SHELF_LENGTH).items.distinctBy { it.id }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            nav.handleExpired(e)
            emptyList()
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        Row(
            Modifier.padding(horizontal = metrics.gutter).focusGroup(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(16)),
        ) {
            SectionTitle(library.name)
            WittyButton(s["gamesAll"].orEmpty(), { nav.open(library) }, focusKey = "games-all-${library.id}")
        }
        LazyRow(
            Modifier.focusGroup(),
            contentPadding = PaddingValues(horizontal = metrics.gutter, vertical = metrics.u(24)),
            horizontalArrangement = Arrangement.spacedBy(metrics.u(24)),
        ) {
            items(games.orEmpty(), key = { it.id }) { game ->
                PosterCard(game.title, game.console.uppercase(), nav.app.api.posterUrl(game), { nav.open(game) }, aspect = GAME_BOX, focusKey = "game-${game.id}")
            }
        }
    }
}

private const val SHELF_LENGTH = 20
private const val GAME_BOX = 3f / 4f

// Live TV: the server's guide, under the bar. A server with no channels says so.
@Composable
fun LiveTvScreen(nav: Nav, s: Map<String, String>) {
    var has by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(Unit) {
        has = try {
            "live-tv" in nav.app.api.capabilities().features && nav.app.api.guide(1, 1).channels.isNotEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            nav.handleExpired(e)
            false
        }
        nav.hasGuide = has == true
    }
    when (has) {
        null -> Loading()
        false -> TvEmpty(s["liveTvNone"].orEmpty(), s["liveTvNoneDetail"].orEmpty())
        true -> PageInTab(nav, Route.LiveTv, GUIDE_PATH)
    }
}
