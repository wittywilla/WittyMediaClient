package com.wittywilla.wittymediaclient.games

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.Api
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sign

// The game library in couch mode, as the website's (the server's web/src/pages/games/Couch.tsx and Library.tsx):
// covers at the top, one at the front and the rest turned away; what's being played; the consoles; shelves; then
// every game, sorted as the website sorts it. A console narrows it to that console's games.

// A games library as the app's menus know it.
data class GamesLibraryRef(val id: Long, val name: String)

// What the games screens need from the app around them.
class GamesNav(
    val api: Api,
    val back: () -> Unit,
    val openGame: (Long) -> Unit,
    val play: (Long, GameStart) -> Unit,
    val openLibrary: (Long) -> Unit,
)

// What was last shown, for coming back from a game without a blank page.
object GamesCache {
    val homes = HashMap<Long, GamesHome>()
    val consoles = HashMap<Long, List<GameConsole>>()
    var libraries: List<GamesLibraryRef> = emptyList()
}

private val SORTS = listOf("popular" to "Most popular", "newest" to "Newest first", "oldest" to "Oldest first", "title" to "A to Z", "added" to "Recently added", "rating" to "Highest rated")

private enum class CouchTab { Home, Consoles, Search }

@Composable
fun GamesLibraryScreen(nav: GamesNav, libraryId: Long, startConsole: String = "") {
    val look = gameLook()
    val api = remember(nav.api) { GamesApi(nav.api) }
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(CouchTab.Home) }
    var console by remember { mutableStateOf(startConsole) }
    var libraries by remember { mutableStateOf(GamesCache.libraries) }
    var home by remember(libraryId) { mutableStateOf(GamesCache.homes[libraryId]) }
    var consoles by remember(libraryId) { mutableStateOf(GamesCache.consoles[libraryId].orEmpty()) }
    var failed by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }

    LaunchedEffect(libraryId, attempt) {
        failed = false
        runCatching { nav.api.libraries() }.onSuccess { all ->
            libraries = all.filter { it.type == "games" && it.console != "rig" }.map { GamesLibraryRef(it.id, it.name) }
            GamesCache.libraries = libraries
        }
        launch { runCatching { api.consoles(libraryId) }.onSuccess { consoles = it; GamesCache.consoles[libraryId] = it } }
        runCatching { api.home(libraryId) }.onSuccess { home = it; GamesCache.homes[libraryId] = it }.onFailure { if (home == null) failed = true }
    }

    // Back from a console, a tab or search comes home first.
    BackHandler(enabled = console.isNotEmpty() || tab != CouchTab.Home) {
        if (console.isNotEmpty() && startConsole.isEmpty()) console = "" else if (tab != CouchTab.Home) tab = CouchTab.Home else nav.back()
    }

    Column(Modifier.fillMaxSize().background(GameColours.background)) {
        CouchBar(nav, libraries, libraryId, tab) { picked, lib ->
            tab = picked
            console = ""
            if (lib != null && lib != libraryId) nav.openLibrary(lib)
        }
        when (tab) {
            CouchTab.Home -> LibraryHome(nav, api, libraryId, home, consoles, console, failed, { console = it }, { attempt++ })
            CouchTab.Consoles -> ConsolesPage(consoles) { c -> console = c; tab = CouchTab.Home }
            CouchTab.Search -> SearchPage(nav, api, libraryId, consoles)
        }
    }
}

// The couch bar: the libraries, Consoles and Search as pills, and Back. A phone shows their icons alone.
@Composable
private fun CouchBar(nav: GamesNav, libraries: List<GamesLibraryRef>, current: Long, tab: CouchTab, pick: (CouchTab, Long?) -> Unit) {
    val look = gameLook()
    val words = look.tv || look.tablet
    Row(
        Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(horizontal = if (look.tv) look.gutter else look.gutter, vertical = if (look.tv) 12.dp else 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (look.tv) 8.dp else 4.dp),
    ) {
        if (!look.tv) {
            Pressable(nav.back, Modifier.size(40.dp), radius = 20.dp, label = "Back", fill = GameColours.card.copy(alpha = 0.7f)) {
                Icon(GameIcons.Back, null, Modifier.align(Alignment.Center).size(22.dp), tint = GameColours.text)
            }
            Spacer(Modifier.width(4.dp))
        }
        val shown = libraries.ifEmpty { listOf(GamesLibraryRef(current, "Home")) }
        LazyRow(
            Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(if (look.tv) 8.dp else 4.dp),
            contentPadding = PaddingValues(vertical = look.rowRoom, horizontal = 4.dp),
        ) {
            items(shown, key = { "lib${it.id}" }) { lib ->
                val chosen = tab == CouchTab.Home && lib.id == current
                Tab(if (shown.size > 1) lib.name else "Home", GameIcons.Home, chosen, words || shown.size > 1) { pick(CouchTab.Home, lib.id) }
            }
            item("consoles") { Tab("Consoles", GameIcons.Library, tab == CouchTab.Consoles, words) { pick(CouchTab.Consoles, null) } }
            item("search") { Tab("Search", GameIcons.Search, tab == CouchTab.Search, words) { pick(CouchTab.Search, null) } }
        }
    }
}

@Composable
private fun Tab(name: String, icon: androidx.compose.ui.graphics.vector.ImageVector, chosen: Boolean, words: Boolean, onClick: () -> Unit) {
    val look = gameLook()
    val ink = if (chosen) GameColours.background else GameColours.secondary
    Pressable(onClick, radius = 999.dp, label = name, fill = if (chosen) GameColours.text else Color.Transparent) {
        Row(
            Modifier.heightIn(min = if (look.tv) 32.dp else 40.dp).padding(horizontal = if (words) 16.dp else 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon, null, Modifier.size(if (look.tv) 14.dp else 20.dp), tint = ink)
            if (words) Text(name, color = ink, fontSize = look.label, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

// The library's home, or one console's page of it.
@Composable
private fun LibraryHome(
    nav: GamesNav,
    api: GamesApi,
    libraryId: Long,
    home: GamesHome?,
    consoles: List<GameConsole>,
    console: String,
    failed: Boolean,
    pickConsole: (String) -> Unit,
    retry: () -> Unit,
) {
    val look = gameLook()
    val byId = remember(consoles) { consoles.associateBy { it.id } }
    val present = remember(consoles) { consoles.filter { it.count > 0 }.sortedByDescending { it.count } }
    val current = byId[console]
    var sort by remember(console) { mutableStateOf("popular") }
    val games = remember(libraryId, console, sort) { mutableStateListOf<GameItem>() }
    var total by remember(libraryId, console, sort) { mutableIntStateOf(-1) }
    var loading by remember(libraryId, console, sort) { mutableStateOf(false) }
    var consoleHero by remember(console) { mutableStateOf<List<GameItem>>(emptyList()) }
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val resumable = remember(home) { home?.`continue`.orEmpty().filter { it.save != null }.map { it.item.id }.toSet() }
    val favourites = remember(home) { home?.favouriteIds.orEmpty().toSet() }

    fun more() {
        if (loading || (total >= 0 && games.size >= total)) return
        loading = true
        scope.launch {
            runCatching { api.games(libraryId, console, sort, offset = games.size, limit = 60) }.onSuccess { page ->
                games += page.items.filter { g -> games.none { it.id == g.id } }
                total = if (page.items.isEmpty()) games.size else page.total
            }.onFailure { if (total < 0) total = 0 }
            loading = false
        }
    }
    LaunchedEffect(libraryId, console, sort) { more() }
    LaunchedEffect(console) {
        if (console.isNotEmpty()) runCatching { api.games(libraryId, console, "popular", limit = 40) }.onSuccess { r -> consoleHero = r.items.filter { it.hasPoster }.take(15) }
    }
    // More as the end comes near.
    LaunchedEffect(list, games.size, total) {
        snapshotFlow { list.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0 }.distinctUntilChanged().collect { last ->
            if (last >= list.layoutInfo.totalItemsCount - 4) more()
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val gap = if (look.tv) look.gap else if (maxWidth < 520.dp) 8.dp else 16.dp
        val cell = if (look.tv) 105.dp else if (maxWidth < 520.dp) 96.dp else 150.dp
        val columns = ((maxWidth - look.gutter * 2 + gap) / (cell + gap)).toInt().coerceAtLeast(2)
        LazyColumn(
            Modifier.fillMaxSize(),
            state = list,
            contentPadding = PaddingValues(bottom = 32.dp + if (look.tv) 0.dp else 24.dp),
        ) {
            if (current != null) {
                item("console-head") {
                    Column(Modifier.padding(horizontal = look.gutter, vertical = 8.dp)) {
                        Text(current.name, color = GameColours.text, fontSize = look.display, fontWeight = FontWeight.Bold, maxLines = 2)
                        Text("${current.count} ${if (current.count == 1) "game" else "games"}", color = GameColours.hint, fontSize = look.body)
                        if (!current.ready) Blocked(current.unavailable.ifEmpty { "This server has no core for the ${current.name} yet, so these games can't start. Ask whoever runs this server to install one." }, Modifier.padding(top = 8.dp))
                    }
                }
            }
            val heroItems = if (console.isEmpty()) home?.hero.orEmpty() else consoleHero
            if (heroItems.isNotEmpty()) item("hero-$console") { Hero(nav, api, heroItems, byId, resumable) }
            if (console.isEmpty() && home == null && failed) item("failed") { GameNote("This library didn't load", "Check this device's connection, then try again.", Modifier.fillMaxWidth(), "Try again", retry) }
            if (console.isEmpty() && home == null && !failed) item("wait") { Box(Modifier.fillMaxWidth().height(240.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = GameColours.accent) } }
            if (console.isEmpty() && home != null) {
                if (home.`continue`.isNotEmpty()) item("continue") {
                    Shelf("Continue playing") {
                        items(home.`continue`, key = { it.item.id }) { e -> ContinueCard(nav, api, e, byId[e.item.console]) }
                    }
                }
                if (present.isNotEmpty()) item("consoles") {
                    Shelf("Consoles") { items(present, key = { it.id }) { c -> ConsoleTile(c) { pickConsole(c.id) } } }
                }
                val shelves = listOf("Recently added" to home.recent, "Favourites" to home.favourites, "Most played" to home.mostPlayed) +
                    home.shelves.filter { it.kind == "series" }.map { it.name to it.items } + home.shelves.filter { it.kind == "genre" }.map { it.name to it.items }
                for ((name, items) in shelves) if (items.isNotEmpty()) item("shelf-$name") {
                    Shelf(name) { items(items, key = { it.id }) { g -> GameCard(nav, api, g, byId[g.console], g.id in favourites) } }
                }
            }
            item("all-head") {
                Column(Modifier.padding(top = look.sectionGap), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(Modifier.padding(horizontal = look.gutter), verticalAlignment = Alignment.Bottom) {
                        Text("Games", color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.SemiBold)
                        if (total >= 0) Text("  ${total} ${if (total == 1) "game" else "games"}", color = GameColours.secondary, fontSize = look.small)
                    }
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = look.gutter, vertical = look.rowRoom),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(SORTS, key = { it.first }) { (id, words) -> GameChip(words, sort == id, { sort = id }) }
                    }
                }
            }
            val rows = games.chunked(columns)
            for ((r, row) in rows.withIndex()) item("row-$console-$sort-$r") {
                Row(Modifier.padding(horizontal = look.gutter, vertical = gap / 2 + look.rowRoom / 4), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    for (g in row) Box(Modifier.weight(1f)) { GameCard(nav, api, g, byId[g.console], g.id in favourites, width = null) }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            if (total == 0) item("empty") { GameNote("No games here yet", "Put your own game files in this library's folder and scan it.", Modifier.fillMaxWidth()) }
            if (loading) item("loading") { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), color = GameColours.accent) } }
            item("bottom") { Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) }
        }
    }
}

// A titled row that scrolls sideways.
@Composable
private fun Shelf(title: String, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
    val look = gameLook()
    Column(Modifier.padding(top = look.sectionGap * 0.6f)) {
        GameSection(title)
        LazyRow(
            contentPadding = PaddingValues(horizontal = look.gutter, vertical = look.rowRoom.coerceAtLeast(8.dp)),
            horizontalArrangement = Arrangement.spacedBy(if (look.tv) look.gap else 16.dp),
            content = content,
        )
    }
}

// A game's box, standing on the card's floor whatever its shape, with its name and facts under it.
@Composable
fun GameCard(nav: GamesNav, api: GamesApi, game: GameItem, console: GameConsole?, favourite: Boolean = false, width: Dp? = gameLook().card) {
    val look = gameLook()
    Column(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Pressable({ nav.openGame(game.id) }, Modifier.fillMaxWidth().aspectRatio(0.75f), radius = 6.dp, label = game.title) {
            if (game.hasPoster) {
                GamePicture(api.posterUrl(game, if (look.tv) 320 else 320), game.title, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
            } else {
                GamePlaceholder(game.title, console?.shortName.orEmpty(), Modifier.fillMaxSize().clip(RoundedCornerShape(6.dp)))
            }
            if (favourite) {
                Box(Modifier.align(Alignment.TopEnd).padding(4.dp).size(24.dp).clip(RoundedCornerShape(12.dp)).background(Color(0x99000000)), contentAlignment = Alignment.Center) {
                    Icon(GameIcons.Star, "Favourite", Modifier.size(14.dp), tint = Color(0xFFFFC94D))
                }
            }
        }
        Text(game.title, color = GameColours.text, fontSize = if (look.tv) look.small else 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        val facts = listOfNotNull(console?.shortName?.takeIf { it.isNotEmpty() }, game.year?.toString()).joinToString(" · ")
        val rating = game.rating?.let { "★ %.1f  ".format(it) }.orEmpty()
        if (facts.isNotEmpty() || rating.isNotEmpty()) Text(rating + facts, color = GameColours.hint, fontSize = if (look.tv) look.small else 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// A game being played: its last save's picture, and a Play button that carries on.
@Composable
private fun ContinueCard(nav: GamesNav, api: GamesApi, e: GameContinue, console: GameConsole?) {
    val look = gameLook()
    val game = e.item
    val ready = console?.ready ?: true
    val thumb = e.save?.takeIf { it.hasThumb }?.let { api.saveThumbUrl(game.id, it.slot, it.updatedAt) }
    Column(Modifier.width(look.continueWidth), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Pressable(
            { if (ready) nav.play(game.id, GameStart(resume = e.save != null)) else nav.openGame(game.id) },
            Modifier.fillMaxWidth().aspectRatio(16f / 10f),
            label = "${if (e.save != null) "Resume" else "Play"} ${game.title}, last played ${GameWords.ago(e.lastPlayed)}",
            fill = GameColours.card,
        ) {
            when {
                thumb != null -> GamePicture(thumb, game.title, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                game.hasPoster -> GamePicture(api.posterUrl(game, 320), game.title, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                else -> GamePlaceholder(game.title, console?.shortName.orEmpty(), Modifier.fillMaxSize())
            }
            Box(Modifier.align(Alignment.BottomEnd).padding(8.dp).size(if (look.tv) 24.dp else 40.dp).clip(RoundedCornerShape(50)).background(GameColours.accent), contentAlignment = Alignment.Center) {
                Icon(GameIcons.Play, null, Modifier.size(if (look.tv) 14.dp else 22.dp), tint = GameColours.onAccent)
            }
        }
        Text(game.title, color = GameColours.text, fontSize = if (look.tv) look.body else 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        val played = game.playedSeconds
        Text(
            listOfNotNull(console?.shortName, if (played > 60) GameWords.played(played) else null, GameWords.ago(e.lastPlayed)).joinToString(" · "),
            color = GameColours.secondary, fontSize = if (look.tv) look.small else 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ConsoleTile(c: GameConsole, onClick: () -> Unit) {
    val look = gameLook()
    Pressable(
        onClick,
        Modifier.width(look.consoleWidth).heightIn(min = if (look.tv) 60.dp else 96.dp).border(BorderStroke(1.dp, GameColours.border), RoundedCornerShape(14.dp)),
        radius = 14.dp,
        label = "${c.name}: ${c.count} ${if (c.count == 1) "game" else "games"}${if (c.ready) "" else ", not set up yet"}",
        fill = GameColours.panel,
    ) {
        Column(Modifier.align(Alignment.Center).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(c.shortName, color = GameColours.text, fontSize = if (look.tv) look.title else 20.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${c.count} ${if (c.count == 1) "game" else "games"}", color = GameColours.secondary, fontSize = if (look.tv) look.small else 12.sp)
        }
    }
}

@Composable
fun Blocked(words: String, modifier: Modifier = Modifier, title: String = "") {
    val look = gameLook()
    val warn = Color(0xFFE0A030)
    Row(
        modifier.clip(RoundedCornerShape(10.dp)).border(1.dp, warn, RoundedCornerShape(10.dp)).background(warn.copy(alpha = 0.12f)).padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(GameIcons.Info, null, Modifier.size(20.dp), tint = warn)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (title.isNotEmpty()) Text(title, color = GameColours.text, fontSize = look.body, fontWeight = FontWeight.SemiBold)
            Text(words, color = GameColours.text, fontSize = if (look.tv) look.small else 13.sp)
        }
    }
}

// MARK: the covers at the top

// One at the front, the rest turned away on either side, standing on a shiny floor (the website's CoverFlow.tsx).
// Most interesting in the middle, with the rest spreading out on either side of it.
private fun centreOut(list: List<GameItem>): List<GameItem> {
    val out = ArrayDeque<GameItem>()
    list.forEachIndexed { i, g -> if (i % 2 == 1) out.addLast(g) else out.addFirst(g) }
    return out.toList()
}

private const val NEAR = 4

@Composable
private fun Hero(nav: GamesNav, api: GamesApi, list: List<GameItem>, consoles: Map<String, GameConsole>, resumable: Set<Long>) {
    val look = gameLook()
    val items = remember(list) { centreOut(list) }
    var index by remember(items) { mutableIntStateOf((items.size - 1) / 2) }
    val game = items.getOrNull(index) ?: return
    val c = consoles[game.console]
    val ready = c?.ready ?: true
    val resume = game.id in resumable
    val (windowW, windowH) = windowDp()
    val flowH: Dp = if (look.tv) 208.dp else min(windowW * 0.62f, windowH * 0.38f).dp
    val density = LocalDensity.current
    val front = remember { FocusRequester() }
    val mainButton = remember { FocusRequester() }
    var flowFocused by remember { mutableStateOf(false) }
    // Focus stays on the front cover as it changes; a TV starts there, as a console does.
    LaunchedEffect(index) { if (flowFocused) runCatching { front.requestFocus() } }
    LaunchedEffect(Unit) { if (look.tv) runCatching { front.requestFocus() } }
    Column(Modifier.fillMaxWidth().padding(bottom = look.sectionGap * 0.6f), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(flowH * 1.1f)
                .pointerInput(items) {
                    var travelled = 0f
                    val step = with(density) { (flowH * 0.32f).toPx() }
                    detectHorizontalDragGestures(onDragStart = { travelled = 0f }) { change, amount ->
                        travelled += amount
                        if (abs(travelled) >= step) {
                            index = (index - sign(travelled).toInt()).coerceIn(0, items.lastIndex)
                            travelled = 0f
                        }
                        change.consume()
                    }
                },
        ) {
            val from = (index - NEAR).coerceAtLeast(0)
            val to = (index + NEAR).coerceAtMost(items.lastIndex)
            // Furthest first, so the front one is drawn last, on top.
            val order = (from..to).sortedByDescending { abs(it - index) }
            for (i in order) {
                val g = items[i]
                val d = i - index
                val a = abs(d)
                val side = sign(d.toFloat())
                val x = if (d == 0) 0f else side * (0.74f + (a - 1) * 0.3f)
                val back = if (d == 0) 0f else 0.5f + a * 0.08f
                val dim = if (d == 0) 0f else min(0.62f, 0.3f + a * 0.08f)
                val depth = 3.2f / (3.2f + back)
                val artW = flowH * 0.75f
                androidx.compose.runtime.key(g.id) {
                    Column(
                        Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = flowH * 0.1f)
                            .width(artW)
                            .graphicsLayer {
                                translationX = x * flowH.toPx()
                                rotationY = -side * 58f
                                scaleX = depth
                                scaleY = depth
                                cameraDistance = 3.2f * flowH.toPx() / density.density
                                transformOrigin = TransformOrigin(0.5f, 1f)
                                alpha = if (a > NEAR - 1) 0f else 1f
                            },
                    ) {
                        Pressable(
                            { if (d == 0) nav.openGame(g.id) else index = i },
                            Modifier
                                .width(artW)
                                .height(flowH)
                                .then(if (d == 0) Modifier.focusProperties { down = mainButton } else Modifier)
                                .then(if (d == 0) Modifier.onPreviewKeyEvent { e ->
                                    if (e.nativeKeyEvent.action != KeyEvent.ACTION_DOWN) return@onPreviewKeyEvent false
                                    when (e.nativeKeyEvent.keyCode) {
                                        KeyEvent.KEYCODE_DPAD_LEFT -> if (index > 0) { index--; true } else false
                                        KeyEvent.KEYCODE_DPAD_RIGHT -> if (index < items.lastIndex) { index++; true } else false
                                        else -> false
                                    }
                                } else Modifier),
                            radius = 6.dp,
                            label = if (d == 0) "${g.title}. ${i + 1} of ${items.size}. Open" else null,
                            focusRequester = if (d == 0) front else null,
                            onFocus = { f -> if (d == 0) flowFocused = f },
                            grows = false,
                        ) {
                            GamePicture(api.posterUrl(g, 800), g.title, Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                            if (dim > 0) Box(Modifier.fillMaxSize().background(GameColours.background.copy(alpha = dim)))
                        }
                    }
                }
            }
        }
        Column(
            Modifier.padding(horizontal = look.gutter).padding(top = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(game.title, color = GameColours.text, fontSize = look.heroTitle, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val meta = listOfNotNull(c?.name?.ifEmpty { null } ?: c?.shortName, game.year?.toString(), game.studio.ifEmpty { null }).joinToString("  ·  ")
            if (meta.isNotEmpty()) Text(meta, color = GameColours.secondary, fontSize = look.small, textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (ready) GameButton(if (resume) "Resume" else "Play", { nav.play(game.id, GameStart(resume = resume)) }, kind = ButtonKind.Primary, icon = GameIcons.Play, focusRequester = mainButton)
                else GameButton("Needs setting up", { nav.openGame(game.id) }, icon = GameIcons.Settings, focusRequester = mainButton)
                GameButton("About this game", { nav.openGame(game.id) }, kind = ButtonKind.Ghost)
            }
        }
    }
}

// MARK: consoles and search

@Composable
private fun ConsolesPage(consoles: List<GameConsole>, open: (String) -> Unit) {
    val look = gameLook()
    val present = consoles.filter { it.count > 0 }.sortedByDescending { it.count }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = ((maxWidth - look.gutter * 2) / (if (look.tv) 130.dp else 150.dp)).toInt().coerceAtLeast(2)
        LazyColumn(contentPadding = PaddingValues(horizontal = look.gutter, vertical = 8.dp)) {
            item { Text("Consoles", color = GameColours.text, fontSize = look.display, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 16.dp)) }
            for (row in present.chunked(columns)) item {
                Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    for (c in row) Box(Modifier.weight(1f)) {
                        Pressable(
                            { open(c.id) },
                            Modifier.fillMaxWidth().heightIn(min = if (look.tv) 72.dp else 120.dp).border(1.dp, GameColours.border, RoundedCornerShape(14.dp)),
                            radius = 14.dp, fill = GameColours.panel, label = "${c.name}: ${c.count} games",
                        ) {
                            Column(Modifier.align(Alignment.Center).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(c.shortName, color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.Bold, maxLines = 1)
                                Text("${c.count} ${if (c.count == 1) "game" else "games"}", color = GameColours.secondary, fontSize = look.small)
                            }
                        }
                    }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            item { Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) }
        }
    }
}

// Letters on the screen for a TV, where there's no keyboard to hand; a phone types.
private val KEYS = ('A'..'Z').map { it.toString() } + ('0'..'9').map { it.toString() }

@Composable
private fun SearchPage(nav: GamesNav, api: GamesApi, libraryId: Long, consoles: List<GameConsole>) {
    val look = gameLook()
    var typed by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<GameItem>?>(null) }
    val byId = remember(consoles) { consoles.associateBy { it.id } }
    LaunchedEffect(typed) {
        val q = typed.trim()
        if (q.isEmpty()) {
            results = null
            return@LaunchedEffect
        }
        delay(250)
        runCatching { api.games(libraryId, sort = "title", search = q, limit = 60) }.onSuccess { results = it.items }
    }
    val field = @Composable {
        Box(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(GameColours.card).border(1.dp, GameColours.border, RoundedCornerShape(10.dp)).padding(horizontal = 14.dp, vertical = 12.dp),
        ) {
            if (typed.isEmpty()) Text("Game's name", color = GameColours.hint, fontSize = look.body)
            if (look.tv) {
                Text(typed, color = GameColours.text, fontSize = look.body)
            } else {
                BasicTextField(
                    typed, { typed = it }, Modifier.fillMaxWidth(),
                    singleLine = true, textStyle = TextStyle(color = GameColours.text, fontSize = look.body),
                    cursorBrush = SolidColor(GameColours.accent),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                )
            }
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val cell = if (look.tv) 105.dp else if (maxWidth < 520.dp) 96.dp else 150.dp
        val gap = if (look.tv) look.gap else 8.dp
        val keysWidth = if (look.tv) 220.dp else 0.dp
        val columns = ((maxWidth - keysWidth - look.gutter * 2 + gap) / (cell + gap)).toInt().coerceAtLeast(2)
        Row(Modifier.fillMaxSize().padding(horizontal = look.gutter), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            if (look.tv) {
                Column(Modifier.width(keysWidth).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    field()
                    val first = remember { FocusRequester() }
                    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
                    for ((r, row) in (KEYS + listOf(" ", "⌫", "Clear")).chunked(6).withIndex()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            for ((i, k) in row.withIndex()) {
                                Pressable(
                                    {
                                        typed = when (k) {
                                            "⌫" -> typed.dropLast(1)
                                            "Clear" -> ""
                                            else -> typed + if (typed.isEmpty()) k else k.lowercase()
                                        }
                                    },
                                    Modifier.weight(if (k == "Clear") 2f else 1f).height(24.dp),
                                    radius = 6.dp, fill = GameColours.panel, label = if (k == " ") "Space" else k,
                                    focusRequester = if (r == 0 && i == 0) first else null,
                                ) { Text(if (k == " ") "␣" else k, Modifier.align(Alignment.Center), color = GameColours.text, fontSize = look.small, fontWeight = FontWeight.SemiBold) }
                            }
                        }
                    }
                }
            }
            LazyColumn(Modifier.weight(1f).fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
                if (!look.tv) item { Column(Modifier.padding(bottom = 16.dp)) { field() } }
                val found = results
                when {
                    found == null -> item { GameNote("Find a game", if (look.tv) "Choose letters on the left." else "Type part of its name.", Modifier.fillMaxWidth()) }
                    found.isEmpty() -> item { GameNote("Nothing found", "No games here match “${typed.trim()}”.", Modifier.fillMaxWidth()) }
                    else -> for (row in found.chunked(columns)) item {
                        Row(Modifier.padding(vertical = gap / 2 + look.rowRoom / 4), horizontalArrangement = Arrangement.spacedBy(gap)) {
                            for (g in row) Box(Modifier.weight(1f)) { GameCard(nav, api, g, byId[g.console], width = null) }
                            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
                item { Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) }
            }
        }
    }
}
