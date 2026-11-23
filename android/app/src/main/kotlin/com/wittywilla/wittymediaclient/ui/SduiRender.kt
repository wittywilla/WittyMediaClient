// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.gestures.BringIntoViewSpec
import androidx.compose.foundation.gestures.LocalBringIntoViewSpec
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.GUIDE_PATH
import com.wittywilla.wittymediaclient.net.SduiJump
import com.wittywilla.wittymediaclient.net.SduiScreen
import com.wittywilla.wittymediaclient.net.SduiScreenTime
import com.wittywilla.wittymediaclient.net.SduiTokens
import com.wittywilla.wittymediaclient.net.SduiView
import com.wittywilla.wittymediaclient.net.child
import com.wittywilla.wittymediaclient.net.str
import com.wittywilla.wittymediaclient.tv.GuideScreen
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// A page drawn: one scrolling column of the page's sections, rows of cards that scroll sideways inside it, a grid
// that pages as it is scrolled (docs/SDUI.md, Rules for renderers). Everything long is laid out lazily: a section,
// one row of a grid's cards, one row of a list is each an item of the page's one lazy column.

// The width sections have to themselves, and the room they leave at each side, on this screen.
class SduiSpan(val content: Dp, val side: Dp)

val LocalSduiSpan = compositionLocalOf { SduiSpan(360.dp, 16.dp) }

// One item of the page's column.
sealed class SduiRow(val key: String, val kind: String) {
    // A component drawn whole: a row of cards, a spotlight, a notice.
    class Block(val view: SduiView, val parent: SduiView?, val first: Boolean) : SduiRow(view.id, view.type)

    // The heading of something whose rows follow as items of their own.
    class Head(val view: SduiView, val first: Boolean) : SduiRow(view.id, "head-" + view.type)

    // One row of a grid's cards.
    class Cards(val grid: SduiView, val index: Int, val cards: List<SduiView>, val columns: Int, val nearEnd: Boolean) :
        SduiRow(grid.id + "~row~" + (cards.firstOrNull()?.id ?: index.toString()), "cards")

    // One row of a list: a list item, a track, or an episode on a phone.
    class Line(val view: SduiView, val parent: SduiView, val nearEnd: Boolean) : SduiRow(view.id, "line-" + view.type)

    // The app's own view, which takes the rest of the page.
    class Native(val view: SduiView) : SduiRow(view.id, "native")
}

object SduiRows {
    private val LONG = setOf("Grid", "List", "TrackList", "SeasonList", "Tabs", "NativeView")
    private const val NEAR_END_ROWS = 2
    private const val NEAR_END_LINES = 6

    // The page's sections as the items of one column. `columns` is how many cards a grid has across on this screen.
    fun flatten(screen: SduiScreen, tv: Boolean, asList: Boolean = false, columns: (SduiView) -> Int): List<SduiRow> {
        val out = ArrayList<SduiRow>()
        fun add(view: SduiView, parent: SduiView?) {
            val first = out.isEmpty()
            val ready = !view.deferred && !view.failed && !view.empty && view.children.isNotEmpty()
            when {
                view.type == "NativeView" && view.props.str("view") == "guide" -> out += SduiRow.Native(view)
                view.type == "Grid" && ready && asList -> {
                    // The Dock's View: the grid as a list, one line for each card.
                    out += SduiRow.Head(view, first)
                    view.children.forEachIndexed { i, child -> out += SduiRow.Line(child, view, i >= view.children.size - NEAR_END_LINES) }
                }
                view.type == "Grid" && ready -> {
                    out += SduiRow.Head(view, first)
                    val across = columns(view).coerceAtLeast(1)
                    val rows = view.children.chunked(across)
                    rows.forEachIndexed { i, cards -> out += SduiRow.Cards(view, i, cards, across, i >= rows.size - NEAR_END_ROWS) }
                }
                (view.type == "List" || view.type == "TrackList" || (view.type == "SeasonList" && !tv)) && ready -> {
                    out += SduiRow.Head(view, first)
                    view.children.forEachIndexed { i, child -> out += SduiRow.Line(child, view, i >= view.children.size - NEAR_END_LINES) }
                }
                view.type == "Tabs" -> {
                    out += SduiRow.Block(view, parent, first)
                    // Only the chosen tab was sent with anything in it.
                    view.children.forEach { tab -> tab.children.forEach { add(it, tab) } }
                }
                (view.type == "Stack" || view.type == "Tab" || view.type == "NativeView") && !view.node.type.equals("Form") && view.props.str("direction") != "row" && view.children.any { it.type in LONG } ->
                    view.children.forEach { add(it, view) }
                else -> out += SduiRow.Block(view, parent, first)
            }
        }
        for (child in screen.root.children) {
            add(child, screen.root)
            if (out.lastOrNull() is SduiRow.Native) break
        }
        // A lazy column refuses two items with one key; an ID the server repeated is told apart by its place.
        val seen = HashSet<String>()
        return out.mapIndexed { i, row -> if (seen.add(row.key)) row else keyed(row, row.key + "~" + i) }
    }

    private fun keyed(row: SduiRow, key: String): SduiRow = SduiRowAlias(key, row)

    // The sections that say "nothing here" for themselves when they have nothing.
    private val EMPTY_KINDS = setOf("Grid", "List", "TrackList", "SeasonList", "Row", "Shelf")

    // A page whose every section is answered and empty: a library with nothing in it yet. Not one still loading or failed.
    fun nothingToShow(rows: List<SduiRow>): Boolean = rows.isNotEmpty() && rows.all {
        it is SduiRow.Block && it.view.type in EMPTY_KINDS && !it.view.deferred && !it.view.failed && (it.view.empty || it.view.children.isEmpty())
    }
}

// A row under another key, for the rare page that repeats an ID.
class SduiRowAlias(key: String, val row: SduiRow) : SduiRow(key, row.kind)

private val TALL_FIRST = setOf("Hero", "DetailHeader")


// A TV page with nothing in it: its title, the server's words for why, its hint, and the way on ("Scan now", or Customise),
// which takes the focus so the remote has somewhere to be.
@Composable
private fun SduiTvEmpty(title: String, empty: SduiView, customise: (() -> Unit)?, side: androidx.compose.ui.unit.Dp) {
    val env = LocalSdui.current
    val words = empty.text["empty"]?.ifEmpty { null } ?: "Nothing here yet."
    val hint = empty.props.str("emptyHint")
    val action = empty.props.child("emptyAction")
    val label = action?.str("label").orEmpty()
    val run = action?.child("action")?.let { runCatching { com.wittywilla.wittymediaclient.net.json.decodeFromJsonElement(com.wittywilla.wittymediaclient.net.SduiAction.serializer(), it) }.getOrNull() }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = side).padding(top = env.space("l")),
        verticalArrangement = Arrangement.spacedBy(env.space("s")),
    ) {
        if (title.isNotEmpty()) Text(title, color = MaterialTheme.colorScheme.onBackground, fontSize = env.size("pageTitle"), fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        Text(words, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("body"))
        if (hint.isNotEmpty()) Text(hint, color = LocalExtraColours.current.hint, fontSize = env.size("body"))
        Row(Modifier.padding(top = env.space("s")), horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
            if (label.isNotEmpty() && run != null) WittyButton(label, { env.act(run) }, kind = ButtonKind.Primary, pill = true, takeFocus = true, focusKey = empty.id + "~empty")
            if (customise != null) WittyButton("Customise", customise, kind = ButtonKind.Secondary, pill = true, icon = Symbols.Tune, takeFocus = label.isEmpty() || run == null, focusKey = "~customise")
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SduiPageView(
    top: Boolean, title: String, offline: Boolean, screenTime: SduiScreenTime?,
    refreshing: Boolean, onRefresh: () -> Unit, customise: (() -> Unit)?,
) {
    val env = LocalSdui.current
    val screen = env.screen
    val layout = env.layout
    BoxWithConstraints(Modifier.fillMaxSize().semantics { paneTitle = title }) {
        // Content keeps inside the safe area a TV's layout names; elsewhere the page's own margin, one m each side.
        val side = if (layout.safeArea.left > 0) env.pt(layout.safeArea.left) else env.space("m")
        val span = SduiSpan(maxWidth - side * 2, side)
        val points = (span.content.value / env.unit).toInt()
        val asList = env.listView.value
        val everything = remember(screen, points, asList) {
            SduiRows.flatten(screen, env.tv, asList) { grid ->
                val fixed = grid.columns.takeIf { it > 0 } ?: layout.cards[grid.cardStyle]?.columns ?: 0
                // A TV's grid has the columns its layout says; a window's has as many cards as fit it now.
                if (env.tv && fixed > 0) fixed else if (grid.cardWidth > 0) layout.columnsFor(points, grid.cardWidth) else fixed.coerceAtLeast(2)
            }
        }
        // The Dock is the screen's own bar, outside the page's scroll, at the foot (layout.dock.placement `bottom`), or a sheet
        // an Options button opens (`sheet`, a phone).
        val dock = everything.firstOrNull { it is SduiRow.Block && it.view.type == "Dock" }?.let { (it as SduiRow.Block).view }
        val rows = remember(everything) { everything.filter { !(it is SduiRow.Block && it.view.type == "Dock") } }
        val tallFirst = rows.firstOrNull()?.let { (it as? SduiRow.Block)?.view?.type in TALL_FIRST } == true
        // The bar over a phone's page sits on the picture when the page starts with one.
        if (!env.tv) HeroPage(tallFirst && !offline && screenTime == null)
        val native = rows.lastOrNull() as? SduiRow.Native
        val gap = env.pt(layout.sectionGap)
        val list = rememberLazyListState()
        val scope = rememberCoroutineScope()
        val reduce = LocalReduceMotion.current || layout.reducedMotion
        if (!env.tv) TracksScroll(list)
        // A page's own heading: not on a TV, where the top menu says where you are, nor over a picture, nor on Home.
        // The page's large title, Home's too, as the Apple apps draw it; not over a tall first section (a hero), not on a TV.
        // A layer shows its page's title at its top on a TV as well (docs/SDUI.md, layers).
        val inLayer = LocalSduiLayerClose.current != null
        // A TV page with nothing on it but empty sections (a library with nothing in it yet) is drawn as one empty state,
        // with its title and something focused, not a caption at the top edge with nothing to land on (#77).
        val emptyTv = env.tv && !inLayer && !offline && SduiRows.nothingToShow(rows)
        val heading = title.takeIf { (!env.tv || inLayer) && !tallFirst && it.isNotEmpty() }
        // On a TV the hints bar is drawn once, for a layer that is open, not again for the page under it.
        val hintsUnder = env.tv && !inLayer && env.nav.layer != null
        val topRoom = if (env.tv) env.space("s") else if (tallFirst && !offline && screenTime == null) 0.dp else LocalTopRoom.current
        // On a TV the screen's bottom edge needs room only when the column reaches it: a Dock or the frame's system dock below
        // already keeps that edge, and the room it took cut the page's tabs off the top to fit a row of cards.
        val bottomRoom = if (env.tv) (if (dock != null || LocalDockBelow.current) 0.dp else env.pt(layout.safeArea.bottom)) else LocalBottomRoom.current
        // The Dock's jump to a letter: choose one, then ask for pages until a title starting with it has come (at most 20), and
        // bring the grid to it.
        var wanted by remember { mutableStateOf<String?>(null) }
        val latest by androidx.compose.runtime.rememberUpdatedState(rows)
        env.control.value?.takeIf { it.kind == "jump" }?.let {
            SduiChooser("Jump to", SduiJump.LETTERS.map { l -> l to l }, "", { env.control.value = null }) { l -> env.control.value = null; wanted = l }
        }
        LaunchedEffect(wanted) {
            val letter = wanted ?: return@LaunchedEffect
            var tries = 0
            while (true) {
                val lead = (if (offline) 1 else 0) + (if (screenTime != null) 1 else 0) + (if (heading != null) 1 else 0)
                val shown = latest.filter { it !is SduiRow.Native }
                val at = shown.indexOfFirst { r ->
                    val cards = (r as? SduiRow.Cards)?.cards ?: (r as? SduiRow.Line)?.let { listOf(it.view) } ?: emptyList()
                    cards.any { SduiJump.letterOf(it.text["title"].orEmpty()) == letter }
                }
                if (at >= 0) { list.scrollToItem(at + lead); break }
                val grid = shown.firstNotNullOfOrNull { (it as? SduiRow.Cards)?.grid ?: (it as? SduiRow.Line)?.parent }
                if (grid == null || !grid.hasMore || tries++ >= SduiJump.MOST_PAGES) break
                val had = grid.children.size
                env.more(grid.id, false)
                var waited = 0
                while (waited++ < 40 && (latest.filter { it !is SduiRow.Native }.firstNotNullOfOrNull { (it as? SduiRow.Cards)?.grid ?: (it as? SduiRow.Line)?.parent }?.children?.size ?: had) == had) delay(150)
            }
            wanted = null
        }
        CompositionLocalProvider(LocalSduiSpan provides span) {
            val content: LazyListScope.() -> Unit = {
                if (offline) item(key = "~offline", contentType = "note") { SduiPageNote("Can't reach the server. This is how the page last was.", Modifier.padding(horizontal = side).padding(bottom = gap)) }
                if (screenTime != null) item(key = "~screen-time", contentType = "note") { SduiScreenTimeNote(screenTime, Modifier.padding(horizontal = side).padding(bottom = gap)) }
                if (heading != null) item(key = "~title", contentType = "title") {
                    Text(
                        heading, color = MaterialTheme.colorScheme.onBackground, fontSize = env.size("pageTitle"), fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = side).padding(top = env.space("xs"), bottom = env.space("m")).semantics { heading() },
                    )
                }
                val lead = (if (offline) 1 else 0) + (if (screenTime != null) 1 else 0) + (if (heading != null) 1 else 0)
                if (emptyTv) item(key = "~empty", contentType = "empty") { SduiTvEmpty(title, (rows.first() as SduiRow.Block).view, customise, side) }
                else itemsIndexed(rows.filter { it !is SduiRow.Native }, key = { _, row -> row.key }, contentType = { _, row -> row.kind }) { at, row ->
                    if (!env.tv) SduiRowView(row, gap) else {
                        // A remote going down the page: the section focus has come into goes to the top of the screen, its
                        // heading with it. The first one takes the page back to its very top.
                        var had by remember { mutableStateOf(false) }
                        Box(
                            Modifier.onFocusChanged { focus ->
                                if (focus.hasFocus == had) return@onFocusChanged
                                had = focus.hasFocus
                                if (!had) return@onFocusChanged
                                val inner = row is SduiRow.Line || (row is SduiRow.Cards && row.index > 0)
                                // A section that goes to the top goes past the column's room above it too, so what's before it
                                // isn't left showing there as a sliver.
                                val peek = if (at == 0) 0 else if (inner) -innerPeek(list, at + lead) else list.layoutInfo.beforeContentPadding
                                scope.launch {
                                    // After the system's own small move for what took focus has begun, so this one is the one that stands.
                                    withFrameNanos { }
                                    withFrameNanos { }
                                    // A section or row that shows whole with the page's top still in view leaves the page at its
                                    // top: moved up, what's above it (a page's tabs) would be cut to a sliver.
                                    if (fitsFromTop(list, at + lead)) {
                                        if (reduce) list.scrollToItem(0) else list.animateScrollToItem(0)
                                        return@launch
                                    }
                                    // A grid's first row goes up with the grid's heading, the row before it, over it.
                                    val head = row is SduiRow.Cards && row.index == 0 && at > 0
                                    val target = if (at == 0) 0 else at + lead - (if (head) 1 else 0)
                                    if (reduce) list.scrollToItem(target, peek) else list.animateScrollToItem(target, peek)
                                }
                            },
                        ) { SduiRowView(row, gap) }
                    }
                }
                if (native == null) {
                    if (layout.truncated) item(key = "~truncated", contentType = "note") { SduiPageNote("This page has more than this device shows at once.", Modifier.padding(horizontal = side).padding(top = gap)) }
                    if (customise != null && !emptyTv) item(key = "~customise", contentType = "customise") {
                        // "Customise", a pill with its sliders at the page's margin, as Apple's.
                        Box(Modifier.fillMaxWidth().padding(horizontal = side).padding(top = gap, bottom = env.space("xs")), contentAlignment = if (env.tv) Alignment.Center else Alignment.CenterStart) {
                            WittyButton("Customise", customise, kind = ButtonKind.Secondary, pill = true, icon = Symbols.Tune, focusKey = "~customise")
                        }
                    }
                    if (!env.tv) item(key = "~foot", contentType = "foot") { PageFoot(env.nav) }
                }
            }
            Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth()) { when {
                native != null -> Column(Modifier.fillMaxSize().padding(top = if (env.tv) 0.dp else topRoom)) {
                    // What comes before the app's own view keeps its place above it; the view takes the rest.
                    rows.filter { it !is SduiRow.Native }.forEach { SduiRowView(it, gap) }
                    Box(Modifier.weight(1f).fillMaxWidth()) { SduiNativeView(native.view) }
                }
                // On a TV the page's column is moved by the rule above, not by Android TV's own of bringing whatever has
                // focus a third of the way down, which cuts a spotlight's top off. Rows of cards keep the TV's rule sideways.
                env.tv -> CompositionLocalProvider(LocalSduiRowSpec provides LocalBringIntoViewSpec.current, LocalBringIntoViewSpec provides NearestEdge) {
                    LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(top = topRoom, bottom = bottomRoom), content = content)
                }
                else -> PullToRefreshBox(refreshing, onRefresh, Modifier.fillMaxSize()) {
                    LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(top = topRoom, bottom = bottomRoom), content = content)
                }
            } }
            if (dock != null && !hintsUnder) SduiScoped(dock, null) { SduiDockBar(dock, side) }
            }
        }
    }
}

// How far down a row inside a grid or list stands: a third of the way, with the rows before it showing above, but never so far
// that its own foot is cut off at the bottom of the window.
private fun innerPeek(list: androidx.compose.foundation.lazy.LazyListState, index: Int): Int {
    val info = list.layoutInfo
    val third = info.viewportSize.height * 3 / 10
    val size = info.visibleItemsInfo.firstOrNull { it.index == index }?.size ?: return third
    // The column's own room at its top, kept at its foot too, for the card that grows under focus.
    val room = info.viewportEndOffset - info.afterContentPadding - size - info.beforeContentPadding
    return third.coerceAtMost(room).coerceAtLeast(0)
}

// Whether the item at `index` ends inside the list's window while the list is scrolled to its very top.
private fun fitsFromTop(list: androidx.compose.foundation.lazy.LazyListState, index: Int): Boolean {
    val info = list.layoutInfo
    if (list.firstVisibleItemIndex != 0) return false
    val item = info.visibleItemsInfo.firstOrNull { it.index == index } ?: return false
    val end = item.offset + item.size + list.firstVisibleItemScrollOffset
    return end <= info.viewportEndOffset - info.afterContentPadding
}

// How a TV's own rule moves a row of cards under focus, kept for the rows inside a page whose column has its own.
@OptIn(ExperimentalFoundationApi::class)
val LocalSduiRowSpec = compositionLocalOf<BringIntoViewSpec?> { null }

// Scrolls only as far as it takes to show what has focus, and not at all when it already shows.
@OptIn(ExperimentalFoundationApi::class)
private object NearestEdge : BringIntoViewSpec {
    override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float {
        val end = offset + size
        return when {
            offset >= 0 && end <= containerSize -> 0f
            offset < 0 && end > containerSize -> 0f
            kotlin.math.abs(offset) < kotlin.math.abs(end - containerSize) -> offset
            else -> end - containerSize
        }
    }
}

// One item of the page's column, with the room above it: the page's gap between sections, a card's between a grid's rows.
@Composable
private fun SduiRowView(row: SduiRow, gap: Dp) {
    val env = LocalSdui.current
    val span = LocalSduiSpan.current
    when (row) {
        is SduiRowAlias -> SduiRowView(row.row, gap)
        is SduiRow.Block -> Box(Modifier.padding(top = if (row.first) 0.dp else gap)) { SduiScoped(row.view, row.parent) { SduiNode(row.view, row.parent, topLevel = true) } }
        is SduiRow.Head -> Box(Modifier.padding(top = if (row.first) 0.dp else gap)) { SduiScoped(row.view, null) { SduiLongHead(row.view) } }
        is SduiRow.Cards -> SduiScoped(row.grid, null) {
            val between = env.pt(env.layout.cardGap)
            val width = (span.content - between * (row.columns - 1)) / row.columns
            if (row.nearEnd && row.grid.hasMore) LaunchedEffect(row.grid.children.size) { env.more(row.grid.id, false) }
            Row(Modifier.fillMaxWidth().padding(horizontal = span.side).padding(top = if (row.index == 0) 0.dp else between), horizontalArrangement = Arrangement.spacedBy(between)) {
                row.cards.forEach { card -> Column(Modifier.width(width)) { SduiCard(card, row.grid, width); SduiItemButtons(card) } }
            }
        }
        is SduiRow.Line -> SduiScoped(row.parent, null) {
            if (row.nearEnd && row.parent.hasMore) LaunchedEffect(row.parent.children.size) { env.more(row.parent.id, false) }
            Box(Modifier.padding(horizontal = span.side)) { SduiLine(row.view, row.parent) }
        }
        is SduiRow.Native -> SduiNativeView(row.view)
        else -> Unit
    }
}

// A part of the page in its own theme scope's colours: the node's tokens over the page's, unless whatever holds it
// already drew with the same ones.
@Composable
fun SduiScoped(view: SduiView, parent: SduiView?, content: @Composable () -> Unit) {
    val tokens = view.node.tokens
    val base = LocalAppTheme.current
    if (tokens.isEmpty() || base == null || tokens == parent?.node?.tokens) content()
    else ThemeScope(remember(base, tokens) { SduiTokens.over(base, tokens) }, content)
}

// The app's own view in a page. The guide is WittyTV's own on a TV, and the server's guide page inside the app on a
// phone or tablet, as the app has always shown it. A view this app doesn't have is drawn as what the page holds in
// its place.
@Composable
fun SduiNativeView(view: SduiView) {
    val env = LocalSdui.current
    when {
        view.props.str("view") != "guide" -> Column { view.children.forEach { SduiNode(it, view, topLevel = true) } }
        env.tv -> GuideScreen(env.nav, embedded = true)
        else -> ServerPageScreen(env.nav, env.nav.current, GUIDE_PATH, keptToGames = false, inShell = true)
    }
}

// A line under the top of a page that says something about the page as a whole.
@Composable
fun SduiPageNote(words: String, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    Text(
        words, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("caption"),
        modifier = modifier.fillMaxWidth().clip(RoundedCornerShape(env.pt(10))).background(MaterialTheme.colorScheme.surface).padding(horizontal = env.space("m"), vertical = env.space("s")),
    )
}

// Screen time is over (docs/SDUI.md, Profiles with limits): the page still shows, and says why nothing plays and when
// there is time again.
@Composable
private fun SduiScreenTimeNote(time: SduiScreenTime, modifier: Modifier) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val again = remember(time.nextAt) {
        if (time.nextAt <= 0) "" else {
            val at = java.util.Date(time.nextAt * 1000)
            val day = if (android.text.format.DateUtils.isToday(at.time)) "" else android.text.format.DateFormat.format("EEEE ", at).toString()
            " More time from $day" + android.text.format.DateFormat.getTimeFormat(context).format(at) + "."
        }
    }
    SduiPageNote(time.message.ifEmpty { "Screen time is over for now." } + again, modifier)
}

// A page that couldn't be shown at all: not found, with a way Home; or the reason, with Retry.
@Composable
fun SduiTrouble(nav: Nav, words: String, gone: Boolean, retry: () -> Unit) {
    val tv = LocalMetrics.current.tv
    Column(
        Modifier.fillMaxSize().padding(horizontal = Space.S8).padding(top = if (tv) Space.S8 else LocalTopRoom.current + Space.S8),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.S3),
    ) {
        Text(if (gone) "This isn't available" else "Couldn't load this page", color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.section, modifier = Modifier.semantics { heading() })
        if (!gone) Text(words, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, textAlign = TextAlign.Center)
        if (gone) WittyButton("Home", { nav.reset(Route.Home) }, kind = ButtonKind.Primary, requestFocus = true, focusKey = "~home")
        else WittyButton("Try again", retry, kind = ButtonKind.Primary, requestFocus = true, focusKey = "~retry")
    }
}

// A page loading for the first time: three rows of grey cards, after a moment, so a quick answer shows nothing first.
@Composable
fun SduiSkeleton(top: Boolean) {
    val metrics = LocalMetrics.current
    var show by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(250); show = true }
    if (!show) return
    val card = if (metrics.tv) metrics.u(250) else 120.dp
    val between = if (metrics.tv) metrics.u(40) else 12.dp
    val side = if (metrics.tv) metrics.u(80) else 16.dp
    Column(
        Modifier.fillMaxSize().padding(start = side, top = if (metrics.tv) metrics.u(20) else LocalTopRoom.current + 8.dp).semantics { contentDescription = "Loading" },
        verticalArrangement = Arrangement.spacedBy(if (metrics.tv) metrics.u(60) else 24.dp),
    ) {
        repeat(3) {
            Column(verticalArrangement = Arrangement.spacedBy(between)) {
                Skel(Modifier.size(card * 1.4f, if (metrics.tv) metrics.u(40) else 20.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(between)) { repeat(8) { Skel(Modifier.size(card, card * 1.5f), 10.dp) } }
            }
        }
    }
}
