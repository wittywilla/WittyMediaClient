package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.BrowseHit
import com.wittywilla.wittymediaclient.net.Facet
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.ShelfCard
import com.wittywilla.wittymediaclient.net.Shelves
import kotlinx.coroutines.launch

// The website's library page for films, shows, discs and videos at phone width (web/src/pages/library/VideoLibrary.tsx,
// components/LibraryHeader.tsx, Filters.tsx): the name and count, Filters and "⋯", the SORT strip, then the shelves
// (categories, collections, studios, networks, Recently added, Highest rated, a row per category) or the grid.

private data class Sort(val key: String, val label: String, val desc: Boolean = false)

private val SORTS = listOf(
    Sort("shuffle", "Shuffle"), Sort("added", "Recently added", true), Sort("title", "Title A to Z"), Sort("newest", "Newest"),
    Sort("oldest", "Oldest"), Sort("rating", "Highest rated", true), Sort("quality", "Best quality", true),
)

private val FACETS = listOf(
    "genre" to ("Category" to "genres"), "kind" to ("Type" to "kinds"), "studio" to ("Studio" to "studios"), "network" to ("Network" to "networks"),
    "platform" to ("Listed on" to "platforms"), "decade" to ("Decade" to "decades"), "year" to ("Year" to "years"), "content" to ("Age rating" to "content"),
)
private val FACETS_AFTER = listOf(
    "resolution" to ("Picture" to "resolutions"), "format" to ("Sound" to "formats"), "audio" to ("Audio language" to "audio"),
    "subtitle" to ("Subtitles" to "subtitles"), "edition" to ("Edition" to "editions"), "tag" to ("Tags" to "tags"),
)
private val FILTER_NAMES = (FACETS + FACETS_AFTER).associate { it.first to it.second.first } + mapOf("minRating" to "Score", "watched" to "Watched", "search" to "Words")

private fun noun(type: String, n: Int): String {
    val (one, many) = when (type) { "movies" -> "film" to "films"; "shows", "anime" -> "show" to "shows"; "discs" -> "disc" to "discs"; else -> "video" to "videos" }
    return "$n ${if (n == 1) one else many}"
}

// artHue: the title's own hue for generated art.
private fun artHue(name: String): Float {
    var h = 0L
    var i = 0
    while (i < name.length) {
        val c = Character.codePointAt(name, i)
        h = (h * 31 + c) % 360
        i += Character.charCount(c)
    }
    return h.toFloat()
}

@Composable
fun PhoneLibrary(nav: Nav, library: Library, chosen: Map<String, String> = emptyMap()) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val api = nav.app.api
    val scope = rememberCoroutineScope()
    val filters = remember(library.id) { mutableStateOf(chosen) }
    var sort by remember(library.id) { mutableStateOf<Sort?>(null) }
    var desc by remember(library.id) { mutableStateOf(false) }
    var seed by remember { mutableIntStateOf(0) }
    var shelves by remember(library.id) { mutableStateOf<Shelves?>(null) }
    var total by remember(library.id) { mutableStateOf<Int?>(null) }
    var more by remember { mutableStateOf(false) }
    var filtering by remember { mutableStateOf(false) }
    LaunchedEffect(library.id) {
        shelves = runCatching { api.shelves(library.id) }.getOrDefault(Shelves())
        total = runCatching { api.browse(library.id, "sort=title", 0, 1).total }.getOrNull()
    }
    val s = shelves
    val noShelves = s != null && s.categories.isEmpty() && s.collections.isEmpty() && s.studios.isEmpty() && s.networks.isEmpty()
    val grid = sort != null || filters.value.isNotEmpty() || noShelves
    val chosen = sort ?: if (grid) SORTS[2] else null
    val query = buildString {
        append("sort=${if (chosen?.key == "shuffle") "random" else chosen?.key ?: "title"}")
        if (desc) append("&desc=1")
        if (chosen?.key == "shuffle") append("&seed=$seed")
        filters.value.forEach { (k, v) -> append("&$k=${api.encode(v)}") }
    }
    val columns = ((LocalConfiguration.current.screenWidthDp - 16) / 120).coerceAtLeast(2)
    val results = remember(library.id, query) { mutableStateListOf<BrowseHit>() }
    var gridTotal by remember(library.id, query) { mutableStateOf<Int?>(null) }
    var loading by remember(library.id, query) { mutableStateOf(false) }
    val state = androidx.compose.runtime.key(library.id) { rememberLazyGridState() }
    TracksScroll(state)
    suspend fun page() {
        if (loading || (gridTotal != null && results.size >= (gridTotal ?: 0))) return
        loading = true
        runCatching { api.browse(library.id, query, results.size, 120) }.onSuccess { results += it.results; gridTotal = it.total }
        loading = false
    }
    LaunchedEffect(library.id, query, grid) { if (grid) page() }
    val nearEnd by remember { derivedStateOf { state.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let { it > state.layoutInfo.totalItemsCount - 12 } == true } }
    LaunchedEffect(nearEnd) { if (nearEnd && grid) page() }

    Box(Modifier.fillMaxSize()) {
        LazyVerticalGrid(
            GridCells.Fixed(columns), state = state,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = LocalTopRoom.current - 8.dp, bottom = LocalBottomRoom.current),
            horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.weight(1f), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(library.name, color = scheme.onBackground, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                            (gridTotal.takeIf { grid } ?: total)?.let { Text(noun(library.type, it), color = extra.hint, fontSize = 14.sp, maxLines = 1, modifier = Modifier.padding(bottom = 3.dp)) }
                        }
                        val n = filters.value.size
                        WebButton(if (n > 0) "Filters ($n)" else "Filters", { filtering = true }, WebButtonKind.Ghost, WebIcons.Tune)
                        Pressable({ more = true }, Modifier.size(44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "More for ${library.name}", ring = false) {
                            Box(Modifier.fillMaxSize().border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                                Icon(WebIcons.More, null, tint = scheme.onBackground, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                    // SORT, then the choices in a sideways strip, then the direction when it means something.
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("SORT", color = extra.hint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.07.em)
                        Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()).padding(2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            SORTS.forEach { o ->
                                val on = chosen?.key == o.key
                                Pressable({ sort = o; desc = o.desc; if (o.key == "shuffle") seed = (1..1_000_000).random() }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = if (on) scheme.onBackground else Color.Transparent, label = o.label, selected = on, ring = false) {
                                    Box(Modifier.heightIn(min = 44.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                                        Text(o.label, color = if (on) scheme.background else scheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                    }
                                }
                            }
                        }
                        if (chosen != null && chosen.key !in setOf("shuffle", "newest", "oldest")) {
                            Pressable({ desc = !desc }, Modifier.size(44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = if (desc) "Last to first" else "First to last", ring = false) {
                                Box(Modifier.fillMaxSize().border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                                    Icon(if (desc) WebIcons.SortDown else WebIcons.SortUp, null, tint = scheme.onBackground, modifier = Modifier.size(16.dp))
                                }
                            }
                        }
                    }
                    if (filters.value.isNotEmpty()) {
                        FlowRow(Modifier.padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            filters.value.forEach { (k, v) ->
                                Row(Modifier.heightIn(min = 28.dp).clip(RoundedCornerShape(50)).background(scheme.surfaceVariant).padding(start = 12.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text("${FILTER_NAMES[k] ?: k}: $v", color = scheme.onBackground, fontSize = 13.sp)
                                    Pressable({ filters.value = filters.value - k }, Modifier.size(24.dp), shape = RoundedCornerShape(50), fill = Color.Transparent, label = "Remove", ring = false) {
                                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(WebIcons.Close, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(14.dp)) }
                                    }
                                }
                            }
                            WebButton("Clear all", { filters.value = emptyMap() }, WebButtonKind.Ghost, small = true)
                        }
                    }
                }
            }
            // While the shelves or the grid are on their way: the website's twelve loading posters (ui/Surface.tsx).
            if ((!grid && s == null) || (grid && gridTotal == null && results.isEmpty())) {
                items(12) { Skel(Modifier.fillMaxWidth().aspectRatio(2f / 3f), 10.dp) }
            }
            if (!grid && s != null) {
                item(span = { GridItemSpan(maxLineSpan) }) { ShelvesView(nav, library, s) { genre -> filters.value = mapOf("genre" to genre) } }
            } else if (grid) {
                items(results, key = { (it.item?.id ?: 0) * 2 + if (it.show != null) 1 else 0 }) { hit ->
                    CardWidth {
                        hit.item?.let { WebItemCard(nav, it) }
                        hit.show?.let { WebShowCard(nav, it) }
                    }
                }
                item(span = { GridItemSpan(maxLineSpan) }) { PageFoot(nav, "metadata") }
                if (gridTotal == 0) item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(Modifier.fillMaxWidth().padding(vertical = 64.dp, horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(Modifier.size(56.dp).clip(RoundedCornerShape(50)).background(scheme.surfaceVariant), contentAlignment = Alignment.Center) { Icon(WebIcons.Film, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(26.dp)) }
                        Text(if (filters.value.isNotEmpty()) "Nothing matches" else if (library.scanning) "Scanning…" else "Nothing here yet", color = scheme.onBackground, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
        if (more) {
            val admin = nav.me?.isAdmin == true
            val all = when (library.type) { "movies" -> "All films"; "shows", "anime" -> "All shows"; "discs" -> "All discs"; else -> "All videos" }
            val rows = buildList {
                if (!grid) add(SheetRow(all, null) { sort = SORTS[2]; desc = false })
                else if (!noShelves) add(SheetRow("Back to shelves", null) { sort = null; desc = false; filters.value = emptyMap() })
                if (admin) {
                    add(SheetRow("Fix matches", null) { nav.push(Route.Page("/fix-matches?library=${library.id}", "Fix matches")) })
                    add(SheetRow("Scan", WebIcons.Refresh) { scope.launch { runCatching { api.scan(library.id) } } })
                }
            }
            WebSheet(library.name, { more = false }) { SheetRows(rows) { more = false } }
        }
        if (filtering) FiltersSheet(nav, library, filters.value, { filters.value = it }) { filtering = false }
    }
}

@Composable
private fun ShelvesView(nav: Nav, library: Library, s: Shelves, openGenre: (String) -> Unit) {
    val api = nav.app.api
    Column(Modifier.padding(horizontal = 0.dp)) {
        @Composable
        fun Shelf(title: String, action: String? = null, go: (() -> Unit)? = null, content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit) {
            Column(Modifier.padding(bottom = 28.dp).layoutBleed()) {
                HubHead(title, action, go)
                HubRow(content)
            }
        }
        if (s.categories.isNotEmpty()) Shelf("Categories") { items(s.categories, key = { it.key }) { c -> CategoryCard(nav, c) { openGenre(c.genre.ifEmpty { c.name }) } } }
        if (s.collections.isNotEmpty()) Shelf("Collections", if (s.collections.any { it.key.isEmpty() }) "See all" else null, { nav.push(Route.Page("/collections", "Collections")) }) {
            items(s.collections, key = { "c${it.id}${it.key}" }) { c -> CategoryCard(nav, c) { nav.push(Route.Page("/collections/${c.id}", c.name)) } }
        }
        if (s.studios.isNotEmpty()) Shelf("Studios") { items(s.studios.take(40), key = { it.key }) { c -> LogoCard(c.name) { nav.push(Route.Page("/brand/studio/${api.encode(c.name)}?library=${library.id}", c.name)) } } }
        if (s.networks.isNotEmpty()) Shelf("Networks") { items(s.networks.take(40), key = { it.key }) { c -> LogoCard(c.name) { nav.push(Route.Page("/brand/network/${api.encode(c.name)}?library=${library.id}", c.name)) } } }
        BrowseRow(nav, library, "Recently added", "sort=added&desc=1")
        BrowseRow(nav, library, "Highest rated", "sort=rating&desc=1&minRating=6")
        s.categories.take(12).forEach { c ->
            val g = c.genre.ifEmpty { c.name }
            BrowseRow(nav, library, c.name, "genre=${api.encode(g)}&sort=rating&desc=1", if (c.count > 20) "See all ${c.count}" else null) { openGenre(g) }
        }
        Box(Modifier.layoutBleed()) { PageFoot(nav, "metadata") }
    }
}

// The rows run edge to edge: the grid's 16 at each side is taken back.
private fun Modifier.layoutBleed(): Modifier = this.layout { measurable, constraints ->
    val extra = 32.dp.roundToPx()
    val placeable = measurable.measure(constraints.copy(minWidth = constraints.maxWidth + extra, maxWidth = constraints.maxWidth + extra))
    layout(constraints.maxWidth, placeable.height) { placeable.place(-extra / 2, 0) }
}

@Composable
private fun BrowseRow(nav: Nav, library: Library, title: String, query: String, action: String? = null, go: (() -> Unit)? = null) {
    // Kept by library and query both: another library in the same place must not show this one's rows.
    var hits by remember(library.id, query) { mutableStateOf<List<BrowseHit>?>(null) }
    LaunchedEffect(library.id, query) { hits = runCatching { nav.app.api.browse(library.id, query, 0, 20).results }.getOrDefault(emptyList()) }
    val h = hits ?: return Box(Modifier.height(240.dp))
    if (h.isEmpty()) return
    Column(Modifier.padding(bottom = 28.dp).layoutBleed()) {
        HubHead(title, action, go)
        HubRow { itemCards(nav, h.mapNotNull { it.item }, h.mapNotNull { it.show }) }
    }
}

// A category: 220 wide, 16:9, radius 10, its picture (or its own colours) fading to the plate colour at the foot, the
// name 20 semibold over the count 13.
@Composable
private fun CategoryCard(nav: Nav, c: ShelfCard, open: () -> Unit) {
    val api = nav.app.api
    val h = artHue(c.name)
    val art = c.art.firstOrNull()
    val url = art?.let { if (it.type == "show") "${api.base}/api/shows/${it.id}/art/backdrop?v=${it.v}" else "${api.base}/api/items/${it.id}/backdrop?v=${it.v}" }
    Pressable(open, Modifier.width(220.dp).aspectRatio(16f / 9f), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "${c.name}, ${c.count} titles", pressScale = 0.975f, ring = false) {
        Box(
            Modifier.fillMaxSize().restingShadow(10.dp).clip(RoundedCornerShape(10.dp))
                .background(Brush.linearGradient(listOf(Color.hsl(h, 0.32f, 0.30f), Color.hsl((h + 40) % 360, 0.38f, 0.14f)))),
        ) {
            if (url != null) WebArt(url, "", 220.dp, 16f / 9f, Modifier.fillMaxSize(), placeholderless = true)
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.4f to Color.Transparent, 1f to Color(0xAD000000))))
            Column(Modifier.align(Alignment.BottomStart).padding(start = 16.dp, end = 16.dp, bottom = 12.dp)) {
                Text(c.name, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.24).sp, lineHeight = 23.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text("${c.count} title${if (c.count == 1) "" else "s"}", color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp)
            }
        }
    }
}

// A studio or network without its logo: the name on a 180×96 card.
@Composable
private fun LogoCard(name: String, open: () -> Unit) {
    Pressable(open, Modifier.size(180.dp, 96.dp), shape = RoundedCornerShape(10.dp), fill = MaterialTheme.colorScheme.surfaceVariant, label = name, pressScale = 0.975f, ring = false) {
        Box(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 16.dp), contentAlignment = Alignment.Center) {
            Text(name, color = MaterialTheme.colorScheme.onBackground, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.012).em, lineHeight = 19.sp, textAlign = TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
    }
}

// Filters: words in the title, then a group of chips for each facet the library has, Score and Watched.
@Composable
private fun FiltersSheet(nav: Nav, library: Library, current: Map<String, String>, change: (Map<String, String>) -> Unit, close: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    var facets by remember { mutableStateOf<Map<String, List<Facet>>?>(null) }
    var words by remember { mutableStateOf(current["search"].orEmpty()) }
    LaunchedEffect(library.id) { facets = runCatching { nav.app.api.facets(library.id) }.getOrDefault(emptyMap()) }
    fun set(k: String, v: String) = change(if (v.isEmpty() || current[k] == v) current - k else current + (k to v))
    WebSheet("Filters", close, footer = {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            WebButton("Clear all", { change(emptyMap()) }, WebButtonKind.Ghost)
            WebButton("Done", close, WebButtonKind.Primary)
        }
    }) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            WebInput(words, { words = it }, "Words in the title", Modifier.weight(1f)) { set("search", words.trim()) }
            WebButton("Find", { set("search", words.trim()) })
        }
        @Composable
        fun Group(title: String, chips: List<Triple<String, String, Int?>>, key: String) {
            if (chips.isEmpty()) return
            Text(title, color = scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 20.dp, bottom = 8.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                chips.forEach { (value, label, count) -> Chip(label, current[key] == value, count) { set(key, value) } }
            }
        }
        val f = facets ?: return@WebSheet
        FACETS.forEach { (k, names) -> Group(names.first, f[names.second].orEmpty().map { Triple(it.value, it.label.ifEmpty { it.value }, it.count) }, k) }
        Group("Score", listOf("9", "8", "7", "6").map { Triple(it, "$it or more", null) }, "minRating")
        Group("Watched", listOf(Triple("no", "Not watched yet", null), Triple("yes", "Watched", null)), "watched")
        FACETS_AFTER.forEach { (k, names) -> Group(names.first, f[names.second].orEmpty().filter { it.value != "none" }.map { Triple(it.value, it.label.ifEmpty { it.value }, it.count) }, k) }
    }
}

// The website's chip on a touch screen: 44 high, 12 inside, a pill outlined in text at 20%; chosen, inverted.
@Composable
fun Chip(words: String, chosen: Boolean, count: Int? = null, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Pressable(onClick, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = if (chosen) scheme.onBackground else Color.Transparent, label = words, selected = chosen, ring = false) {
        Row(
            Modifier.heightIn(min = 44.dp).border(1.dp, if (chosen) scheme.onBackground else scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(50)).padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val ink = if (chosen) scheme.background else scheme.onSurfaceVariant
            Text(words, color = ink, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            if (count != null) Text("$count", color = ink.copy(alpha = 0.7f), fontSize = 12.sp, modifier = Modifier.padding(start = 8.dp))
        }
    }
}
