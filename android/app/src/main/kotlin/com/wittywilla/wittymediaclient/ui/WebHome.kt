package com.wittywilla.wittymediaclient.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.ForYou
import com.wittywilla.wittymediaclient.net.albumsOnce
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.Home
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

// The website's Home on a phone (web/src/pages/HomePage.tsx): the hero, Your libraries, then Jump back in, On TV now,
// Because you watch, Next up, saved views, Recently added in each library, and Can't decide?.
private const val HERO_EVERY_MS = 9000L

@Composable
fun PhoneHome(nav: Nav, s: Map<String, String>) {
    var home by remember { mutableStateOf(nav.remembered<Home>("home")) }
    var error by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    var onNow by remember { mutableStateOf(emptyList<GuideChannel>()) }
    var forYou by remember { mutableStateOf<ForYou?>(null) }
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
    LaunchedEffect(Unit) {
        nav.hasGuide = runCatching { "live-tv" in nav.app.api.capabilities().features }.getOrDefault(false)
        if (nav.hasGuide) onNow = runCatching { nav.app.api.guide(1, 16).channels.sortedByDescending { it.favourite } }.getOrDefault(emptyList())
        forYou = runCatching { nav.app.api.forYou() }.getOrNull()
    }
    val h = home
    if (h == null) {
        if (error.isNotEmpty()) LoadFailed(nav, error) { attempt++ } else HomeSkeleton()
        return
    }
    val list = rememberLazyListState()
    TracksScroll(list)
    if (h.featured.isNotEmpty()) HeroPage()
    val bottom = LocalBottomRoom.current
    val top = LocalTopRoom.current
    val hubs = h.hubs.distinctBy { it.key }
    fun hub(key: String) = hubs.firstOrNull { it.key == key }
    val going = listOf("continue", "continue-reading", "continue-listening").mapNotNull(::hub)
    LazyColumn(state = list, contentPadding = PaddingValues(top = if (h.featured.isEmpty()) top else 0.dp, bottom = bottom)) {
        if (h.featured.isNotEmpty()) item(key = "hero") { Hero(nav, h.featured) }
        if (error.isNotEmpty()) item(key = "problem") { ErrorText(error, Modifier.padding(16.dp)) }
        item(key = "libraries") { LibraryTiles(nav, h.libraries.distinctBy { it.id }) }
        val jumpItems = going.flatMap { it.items }.distinctBy { it.id }
        val jumpShows = going.flatMap { it.shows }.distinctBy { it.id }
        if (jumpItems.isNotEmpty() || jumpShows.isNotEmpty()) item(key = "jump") {
            Column(Modifier.padding(bottom = 28.dp)) {
                HubHead("Jump back in")
                HubRow { itemCards(nav, jumpItems, jumpShows) }
            }
        }
        if (onNow.isNotEmpty()) item(key = "onnow") {
            Column(Modifier.padding(bottom = 28.dp)) {
                HubHead("On TV now", "Guide") { nav.push(Route.Page(com.wittywilla.wittymediaclient.net.GUIDE_PATH)) }
                HubRow { items(onNow, key = { it.key }) { OnNowCard(nav, it) } }
            }
        }
        forYou?.takeIf { it.items.isNotEmpty() || it.shows.isNotEmpty() }?.let { pick ->
            item(key = "foryou") {
                Column(Modifier.padding(bottom = 28.dp)) {
                    HubHead(if (pick.because.isNotEmpty()) "Because you watch ${pick.because}" else "Recommended for you")
                    HubRow { itemCards(nav, pick.items.distinctBy { it.id }, pick.shows.distinctBy { it.id }) }
                }
            }
        }
        val rest = listOfNotNull(hub("nextup")) + hubs.filter { it.key.startsWith("view-") } + hubs.filter { it.key.startsWith("recent-") }
        items(rest.filter { it.items.isNotEmpty() || it.shows.isNotEmpty() }, key = { it.key }) { row ->
            val library = h.libraries.firstOrNull { it.id == row.libraryId }
            val wide = library?.type in setOf("photos", "channels", "musicvideos")
            Column(Modifier.padding(bottom = 28.dp)) {
                HubHead(row.title, if (library != null) "See all" else null) { library?.let { nav.push(Route.Library(it)) } }
                HubRow { itemCards(nav, albumsOnce(row.items.distinctBy { it.id }), row.shows.distinctBy { it.id }, wide) }
            }
        }
        item(key = "shuffle") { CantDecide(nav) }
    }
}

// The hero: 66% of the height (380 to 660), the backdrops cross-fading over 420 ms, shaded from the page colour at
// the foot. The title 30 at 650, the facts 14, two lines of the synopsis, Play and Details. Dots and pause at the top
// right; it moves on every 9 seconds, and not at all with Reduce Motion.
@Composable
private fun Hero(nav: Nav, featured: List<Item>) {
    val scheme = MaterialTheme.colorScheme
    val reduce = LocalReduceMotion.current
    var index by remember { mutableIntStateOf(0) }
    var paused by remember { mutableStateOf(reduce) }
    LaunchedEffect(index, paused, featured.size) {
        if (paused || featured.size < 2) return@LaunchedEffect
        delay(HERO_EVERY_MS)
        index = (index + 1) % featured.size
    }
    val item = featured[index.coerceIn(0, featured.lastIndex)]
    val page = scheme.background
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val screen = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp.dp
        val height = (screen * 0.66f).coerceIn(380.dp, 660.dp)
        val wide = maxWidth
        Box(Modifier.fillMaxWidth().height(height)) {
            Crossfade(item, animationSpec = tween(420, easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)), label = "hero") { shown ->
                WebArt(nav.app.api.backdropUrl(shown), "", wide, wide / height, Modifier.fillMaxSize())
            }
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.18f to page.copy(alpha = 0f), 0.44f to page.copy(alpha = 0.72f), 0.66f to page.copy(alpha = 0.94f), 1f to page)))
            Column(Modifier.align(Alignment.BottomStart).padding(start = 16.dp, end = 16.dp, bottom = 24.dp).fillMaxWidth()) {
                Text(item.title, color = scheme.onBackground, fontSize = 30.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em, lineHeight = 34.sp, modifier = Modifier.padding(bottom = 12.dp))
                Facts(item, Modifier.padding(bottom = 12.dp))
                if (item.overview.isNotEmpty()) Text(item.overview, color = scheme.onBackground.copy(alpha = 0.86f), fontSize = 15.sp, lineHeight = 23.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 20.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val resume = (item.progress?.resumeSec ?: 0.0) > 0
                    WebButton(if (resume) "Resume" else "Play", { nav.play(item) }, WebButtonKind.Primary, WebIcons.Play)
                    if (item.isDisc && item.disc?.hasMenus == true) WebButton("Disc menu", { nav.push(Route.Page("/play/${item.id}?mode=menu")) }, WebButtonKind.Secondary)
                    WebButton("Details", { nav.push(Route.Item(item.id)) }, WebButtonKind.Ghost, WebIcons.Info)
                }
            }
            if (featured.size >= 2) {
                Row(Modifier.align(Alignment.TopEnd).padding(top = LocalTopRoom.current, end = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Pressable({ paused = !paused }, Modifier.size(24.dp).padding(end = 0.dp), shape = CircleShape, fill = Color.Transparent, label = if (paused) "Start turning the featured titles" else "Stop turning the featured titles", ring = false) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (paused) WebIcons.Play else WebIcons.Pause, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(16.dp)) }
                    }
                    Spacer(Modifier.width(4.dp))
                    featured.forEachIndexed { i, f ->
                        val on = i == index
                        val w by animateDpAsState(if (on) 18.dp else 8.dp, tween(150), label = "dot")
                        Pressable({ index = i }, Modifier.size(24.dp), shape = CircleShape, fill = Color.Transparent, label = f.title, selected = on, ring = false) {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Box(Modifier.width(w).height(8.dp).clip(RoundedCornerShape(4.dp)).background(if (on) scheme.onBackground else scheme.onBackground.copy(alpha = 0.45f)))
                            }
                        }
                    }
                }
            }
        }
    }
    Spacer(Modifier.height(28.dp))
}

// year · length · the rating's pill · the star · a disc's menus · up to three genres, 14 in textSecondary.
@Composable
fun Facts(it: Item, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val warn = LocalExtraColours.current.warn
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        var first = true
        @Composable
        fun dot() { if (!first) Text("·", color = hint, fontSize = 14.sp); first = false }
        it.year?.let { y -> dot(); Text("$y", color = scheme.onSurfaceVariant, fontSize = 14.sp) }
        runtimeWords(it.runtimeSec).takeIf { r -> r.isNotEmpty() }?.let { r -> dot(); Text(r, color = scheme.onSurfaceVariant, fontSize = 14.sp) }
        if (it.contentRating.isNotEmpty()) {
            Box(Modifier.heightIn(min = 20.dp).border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(4.dp)).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                Text(it.contentRating, color = scheme.onSurfaceVariant, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.02.em)
            }
            first = true
        }
        it.rating?.takeIf { r -> r > 0 }?.let { r ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Icon(WebIcons.Star, null, tint = warn, modifier = Modifier.size(14.dp))
                Text(String.format(java.util.Locale.ROOT, "%.1f", r), color = scheme.onSurfaceVariant, fontSize = 14.sp)
            }
            first = false
        }
        if (it.isDisc && it.disc?.hasMenus != false) { dot(); Text("${if (it.kind.startsWith("bluray")) "Blu-ray" else "DVD"} · interactive menus", color = scheme.onSurfaceVariant, fontSize = 14.sp) }
        it.genres.take(3).forEach { g -> dot(); Text(g, color = scheme.onSurfaceVariant, fontSize = 14.sp) }
    }
}

private fun countWords(l: Library): String {
    if (l.scanning) return "Scanning…"
    val (one, many) = when (l.type) {
        "movies" -> "title" to "titles"
        "discs" -> "disc" to "discs"
        "videos", "shorts", "channels", "musicvideos" -> "video" to "videos"
        "commercials" -> "commercial" to "commercials"
        "shows", "anime", "podcasts" -> "episode" to "episodes"
        "games" -> "game" to "games"
        "music" -> "track" to "tracks"
        "audiobooks" -> "file" to "files"
        "books" -> "book" to "books"
        "photos" -> "picture" to "pictures"
        "radio" -> "station" to "stations"
        else -> "item" to "items"
    }
    return "${String.format(java.util.Locale.getDefault(), "%,d", l.itemCount)} ${if (l.itemCount == 1) one else many}"
}

// Your libraries: two across, 8 apart. A tile is 10 inside, panel colour, a hairline, radius 14: the 38 icon square
// in the accent at 14%, then the name 14 semibold over the count 12 in textHint.
@Composable
private fun LibraryTiles(nav: Nav, libraries: List<Library>) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val admin = nav.me?.isAdmin == true
    Column(Modifier.padding(bottom = 28.dp)) {
        HubHead("Your libraries", if (admin) "Manage" else null) { nav.push(Route.Page("/settings/libraries", "Libraries")) }
        @Composable
        fun Tile(name: String, sub: String, icon: androidx.compose.ui.graphics.vector.ImageVector, add: Boolean, modifier: Modifier, open: () -> Unit) {
            Pressable(open, modifier, shape = RoundedCornerShape(14.dp), fill = if (add) Color.Transparent else scheme.surface, label = "$name, $sub", pressScale = 0.975f, ring = false) {
                Row(
                    Modifier.fillMaxWidth().then(if (add) Modifier.dashedBorder(scheme.outline, 14.dp) else Modifier.border(1.dp, scheme.outline, RoundedCornerShape(14.dp))).padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)).background(if (add) scheme.surfaceVariant else scheme.primary.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                        Icon(icon, null, tint = if (add) scheme.onSurfaceVariant else extra.accentText, modifier = Modifier.size(20.dp))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(name, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(sub, color = extra.hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        val tiles = libraries.map { l -> Triple(l.name, countWords(l), l) }
        val rows = (tiles.map { it as Any } + if (admin) listOf("add") else emptyList()).chunked(2)
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            rows.forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    pair.forEach { t ->
                        if (t is Triple<*, *, *>) {
                            val l = t.third as Library
                            Tile(l.name, t.second as String, WebIcons.forLibrary(l.type), false, Modifier.weight(1f)) { nav.push(Route.Library(l)) }
                        } else {
                            Tile("Add a library", "Another folder of media", WebIcons.Plus, true, Modifier.weight(1f)) { nav.push(Route.Page("/settings/libraries", "Libraries")) }
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

// On TV now: 230 wide, the picture 16:9 radius 10 with the channel's number on a plate and how far it's got.
@Composable
private fun OnNowCard(nav: Nav, channel: GuideChannel) {
    val scheme = MaterialTheme.colorScheme
    val now = System.currentTimeMillis() / 1000
    val on = channel.programmes.firstOrNull { it.start <= now && it.end > now }
    val left = on?.let { ((it.end - now) / 60).toInt() }
    val leftWords = left?.let { m -> if (m < 60) "$m min left" else if (m % 60 == 0) "${m / 60} h left" else "${m / 60} h ${m % 60} min left" }
    Pressable({ nav.push(Route.Page("/tv/watch/${channel.key}")) }, Modifier.width(230.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "Channel ${channel.number}, ${channel.name}: ${on?.title ?: "Off air"}", ring = false) {
        Column(Modifier.width(230.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)) {
                on?.itemId?.let { id -> WebArt("${nav.app.api.base}/api/items/$id/backdrop", "", 230.dp, 16f / 9f, Modifier.fillMaxSize()) }
                Text(channel.number, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(6.dp).clip(RoundedCornerShape(6.dp)).background(Color(0xAD000000)).padding(horizontal = 7.dp, vertical = 1.dp))
                if (on != null && on.end > on.start) {
                    val done = ((now - on.start).toFloat() / (on.end - on.start)).coerceIn(0f, 1f)
                    Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color(0xAD000000))) {
                        Box(Modifier.fillMaxWidth(done).height(4.dp).background(scheme.primary))
                    }
                }
            }
            Text(on?.title ?: if (channel.programmes.isEmpty()) "No guide data" else "Off air", color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(listOfNotNull(channel.name, leftWords).joinToString(" · "), color = scheme.onSurfaceVariant, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// Can't decide?: something picked at random, on a panel with its backdrop faintly behind.
@Composable
private fun CantDecide(nav: Nav) {
    val scheme = MaterialTheme.colorScheme
    var pick by remember { mutableStateOf<Item?>(null) }
    var roll by remember { mutableIntStateOf(0) }
    LaunchedEffect(roll) { pick = runCatching { nav.app.api.randomItem() }.getOrNull() }
    val it = pick ?: return
    Column(Modifier.padding(bottom = 28.dp)) {
        HubHead("Can’t decide?")
        Box(Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(scheme.surface).border(1.dp, scheme.outline, RoundedCornerShape(14.dp))) {
            WebArt(nav.app.api.backdropUrl(it), "", 360.dp, 2f, Modifier.matchParentSizeAlpha())
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Box(Modifier.width(90.dp).aspectRatio(2f / 3f).cssShadow(10.dp, 24.dp, Color(0x80000000), 10.dp).clip(RoundedCornerShape(10.dp))) {
                    WebArt(nav.app.api.posterUrl(it), it.title, 90.dp, 2f / 3f, Modifier.fillMaxSize())
                }
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(it.title, color = scheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    Text(listOfNotNull(it.year?.toString(), runtimeWords(it.runtimeSec).ifEmpty { null }, *it.genres.take(2).toTypedArray()).joinToString(" · "), color = LocalExtraColours.current.hint, fontSize = 15.sp)
                    FlowRow(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        WebButton(if ((it.progress?.resumeSec ?: 0.0) > 0) "Resume" else "Play", { nav.play(it) }, WebButtonKind.Primary, WebIcons.Play)
                        WebButton("Details", { nav.push(Route.Item(it.id)) }, WebButtonKind.Secondary, WebIcons.Info)
                        WebButton("Another", { roll++ }, WebButtonKind.Ghost, WebIcons.Refresh)
                    }
                }
            }
        }
    }
}

// The faint backdrop behind Can't decide? fills its box at 16%.
private fun Modifier.matchParentSizeAlpha(): Modifier = this.fillMaxSize().alpha(0.16f)

// Home while it loads: the hero's shapes, the tiles and a row of posters.
@Composable
private fun HomeSkeleton() {
    val page = MaterialTheme.colorScheme.background
    var show by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(250); show = true }
    if (!show) return
    Column(Modifier.fillMaxSize()) {
        val screen = androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp.dp
        Box(Modifier.fillMaxWidth().height((screen * 0.66f).coerceIn(380.dp, 660.dp)).background(Brush.verticalGradient(listOf(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f), page)))) {
            Column(Modifier.align(Alignment.BottomStart).padding(16.dp).padding(bottom = 8.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Skel(Modifier.fillMaxWidth(0.7f).height(32.dp))
                Skel(Modifier.fillMaxWidth(0.45f).height(15.dp))
                Skel(Modifier.fillMaxWidth(0.9f).height(15.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Skel(Modifier.size(104.dp, 44.dp), 10.dp); Skel(Modifier.size(104.dp, 44.dp), 10.dp) }
            }
        }
        Column(Modifier.padding(16.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Skel(Modifier.size(144.dp, 20.dp))
            Spacer(Modifier.height(4.dp))
            repeat(2) { Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Skel(Modifier.weight(1f).height(64.dp), 14.dp); Skel(Modifier.weight(1f).height(64.dp), 14.dp) } }
        }
    }
}
