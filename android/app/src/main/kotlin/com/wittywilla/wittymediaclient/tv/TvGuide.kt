package com.wittywilla.wittymediaclient.tv

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.GuideCell
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideHit
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.TvShape
import com.wittywilla.wittymediaclient.net.legalNotices
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.record
import com.wittywilla.wittymediaclient.net.recordSeries
import com.wittywilla.wittymediaclient.ui.LoadFailed
import com.wittywilla.wittymediaclient.ui.Loading
import com.wittywilla.wittymediaclient.ui.LocalExtraColours
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Route
import com.wittywilla.wittymediaclient.ui.Symbols
import com.wittywilla.wittymediaclient.ui.TvRoute
import com.wittywilla.wittymediaclient.ui.TvScreen
import com.wittywilla.wittymediaclient.ui.section
import com.wittywilla.wittymediaclient.ui.secondary
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.TimeZone

// The programme guide on Android TV, as the server's page draws it (web/src/pages/tv/GuidePage.tsx, Hero.tsx and
// Preview.tsx) and Apple TV's GuideView does, under each of WittyTV's themes: at the top, the highlighted channel, its
// programme, what can be done with it and a live preview; below, the filters and times; then the grid, half an hour to a
// column. The remote moves the highlight cell by cell; past either edge of the grid it moves the time. Select watches
// what's on, or says more about what's later; holding Select offers everything else, and Play/Pause watches the
// channel.

// The highlighted row and the moment in it, as the page keeps them.
data class GuideSpot(val row: Int, val at: Long)

// What the details sheet is about.
data class GuideAsk(val channel: GuideChannel, val programme: GuideProgramme?, val cell: GuideCell, val day: Boolean = false)

// What the grid's cells do, as this composition has it.
private class GuideHandlers(
    val focused: (Int, GuideCell, Boolean) -> Unit,
    val activate: (GuideChannel, GuideCell) -> Unit,
    val watch: (GuideChannel) -> Unit,
    val earlier: () -> Unit,
    val later: () -> Unit,
)

// Which channel to come back to when the guide shows again after watching one.
object GuideReturn {
    var key = ""
}

fun nowSeconds() = System.currentTimeMillis() / 1000

// The theme this device shows, as the account's look reads its suggestion: Apple TV's effectiveThemeId.
fun Nav.effectiveThemeId(dark: Boolean): String = when (themeChoice) {
    "" -> themeId
    "auto" -> if (dark) "default" else "light"
    "custom" -> if (customTheme == null) themeId else "custom"
    else -> themeChoice
}

// Opens a channel full screen from anywhere.
fun Nav.watchChannel(key: String) {
    GuideReturn.key = key
    push(TvRoute(TvScreen.Channel(key)))
}

@Composable
fun GuideScreen(nav: Nav) {
    val api = nav.app.api
    val context = LocalContext.current
    val view = LocalView.current
    LiveTv.use(context)
    remember { GuideRules.timeFormat = android.text.format.DateFormat.getTimeFormat(context); 0 }
    val scope = rememberCoroutineScope()
    val store = remember(api) { GuideStore(api) }
    val appColours = tvAppColours(MaterialTheme.colorScheme, LocalExtraColours.current)
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    LaunchedEffect(appColours) { TvLookStore.follow(appColours) }
    val dress = rememberDress(TvLookStore.look)
    var from by remember { mutableLongStateOf(GuideRules.floorSlot(nowSeconds())) }
    var spot by remember { mutableStateOf(GuideSpot(0, nowSeconds())) }
    var now by remember { mutableLongStateOf(nowSeconds()) }
    var ask by remember { mutableStateOf<GuideAsk?>(null) }
    var lookOpen by remember { mutableStateOf(false) }
    var searchOpen by remember { mutableStateOf(false) }
    var dayOpen by remember { mutableStateOf(false) }
    // A cell held with Select: everything else that can be done with it.
    var menu by remember { mutableStateOf<Pair<GuideChannel, GuideCell>?>(null) }
    var toast by remember { mutableStateOf("") }
    var notices by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var placed by remember { mutableStateOf(false) }
    var width by remember { mutableStateOf(1920f) }
    val listState = rememberLazyListState()
    val requesters = remember { HashMap<Pair<Int, Long>, FocusRequester>() }
    var focusedKey by remember { mutableStateOf<Pair<Int, Long>?>(null) }

    val slots = GuideRules.slots(dress.look.hours, width.toDouble())
    val to = from + slots * GuideRules.SLOT
    // The grid's own width: the page less its edges and the channels.
    val trackWidth = width - dress.edge * 2 - dress.channelWidth
    val perSecond = trackWidth.toDouble() / (to - from)
    val current = store.rows[spot.row]
    val cells = GuideRules.cells(current, from, to, perSecond)
    val currentCell = GuideRules.cellAt(spot.at, cells)
    val visible by remember { derivedStateOf { listState.layoutInfo.visibleItemsInfo.map { it.index } } }

    fun say(words: String) {
        view.announceForAccessibility(words)
        toast = words
        scope.launch {
            delay(3000)
            if (toast == words) toast = ""
        }
    }

    // Focus on the cell of a row at a moment, once it's drawn.
    fun focusCell(row: Int, at: Long) {
        scope.launch {
            val shown = listState.layoutInfo.visibleItemsInfo
            if (shown.none { it.index == row && it.offset >= 0 && it.offset + it.size <= listState.layoutInfo.viewportEndOffset }) {
                val fits = (shown.size - 1).coerceAtLeast(1)
                listState.scrollToItem((row - fits / 2).coerceAtLeast(0))
            }
            repeat(FOCUS_TRIES) {
                withFrameNanos { }
                val rowCells = GuideRules.cells(store.rows[row], from, from + slots * GuideRules.SLOT, perSecond)
                val cell = GuideRules.cellAt(at, rowCells) ?: return@repeat
                val wanted = row to cell.start
                if (focusedKey == wanted) return@launch
                requesters[wanted]?.let { runCatching { it.requestFocus() } }
            }
        }
    }

    fun reload() {
        val rows = if (visible.isEmpty()) listOf(spot.row) else visible
        scope.launch { for (r in rows.map { it / GuideRules.PAGE * GuideRules.PAGE }.toSet()) store.ensure(r) }
    }

    fun shift(seconds: Long, at: Long? = null) {
        val next = GuideRules.shifted(from, seconds, now)
        val span = slots * GuideRules.SLOT
        val target = at ?: maxOf(next, minOf(next + span - 1, spot.at + seconds))
        from = next
        store.setFrom(next)
        spot = spot.copy(at = target.coerceIn(next, next + span - 1))
        reload()
        focusCell(spot.row, spot.at)
    }

    fun goAt(at: Long, row: Int? = null) {
        from = GuideRules.floorSlot(at)
        store.setFrom(from)
        spot = GuideSpot(row ?: spot.row, at)
        reload()
        focusCell(spot.row, at)
    }

    fun goNow() = goAt(nowSeconds())

    val today = GuideRules.startOfDay(now)
    fun goDay(n: Int) {
        if (n == 0) {
            goNow()
            return
        }
        shift(today + n * 86400L - GuideRules.startOfDay(from))
    }

    fun moveRow(r: Int) {
        val row = r.coerceIn(0, ((store.total ?: 1) - 1).coerceAtLeast(0))
        spot = spot.copy(row = row)
        scope.launch {
            store.ensure(row)
            focusCell(row, spot.at)
        }
    }

    fun cycleKind() {
        val k = store.filter.kind
        store.choose(GuideFilter(kind = if (k.isEmpty()) "library" else if (k == "library") "tuner" else ""))
    }

    fun watch(key: String) {
        ask = null
        nav.watchChannel(key)
    }

    fun record(channel: GuideChannel, p: GuideProgramme) {
        scope.launch {
            try {
                api.record(channel.key, p.title, p.sub, p.start, p.end)
                say("Recording ${p.title}")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                say(problemText(e, "That couldn't be recorded."))
            }
        }
    }

    fun series(channel: GuideChannel, p: GuideProgramme) {
        scope.launch {
            try {
                api.recordSeries(channel.key, p.title)
                say("Every airing of ${p.title} will be recorded")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                say(problemText(e, "That couldn't be recorded."))
            }
        }
    }

    fun favourite(channel: GuideChannel) {
        val on = !channel.favourite
        scope.launch {
            try {
                store.setFavourite(channel, on)
                say(if (on) "${channel.name} added to favourites" else "${channel.name} removed from favourites")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                say(problemText(e, "That didn't work. Try again."))
            }
        }
    }

    fun activate(channel: GuideChannel, cell: GuideCell) {
        if (!channel.canTune || cell.kind == GuideCell.Kind.Group) {
            ask = GuideAsk(channel, cell.programmeAt(spot.at), cell)
            return
        }
        val live = if (cell.kind == GuideCell.Kind.None) cell.start <= now + 60 else cell.isOn(now)
        if (live) watch(channel.key) else ask = GuideAsk(channel, cell.programme, cell)
    }

    fun details(day: Boolean) {
        val c = current ?: return
        val cell = currentCell ?: return
        ask = GuideAsk(c, cell.programmeAt(spot.at), cell, day)
    }

    fun go(hit: GuideHit) {
        searchOpen = false
        val i = store.index(hit.channel)
        if (i != null) {
            goAt(hit.start, i)
            scope.launch { store.ensure(i) }
        } else {
            store.choose(GuideFilter())
            val at = store.lineup.indexOfFirst { it.key == hit.channel }.coerceAtLeast(0)
            goAt(hit.start, at)
            scope.launch {
                store.ensure(at)
                focusCell(at, hit.start)
            }
        }
    }

    // The channel just watched, in the middle of the rows, at now, with the highlight and focus on it: in the Live TV tab
    // too, as Apple TV's guide places it.
    fun placeFirstFocus() {
        if (placed || store.total == null) return
        placed = true
        var r = 0
        val back = GuideReturn.key
        if (back.isNotEmpty()) store.index(back)?.let { r = it }
        GuideReturn.key = ""
        val at = nowSeconds()
        from = GuideRules.floorSlot(at)
        store.setFrom(from)
        spot = GuideSpot(r, at)
        scope.launch {
            store.ensure(r)
            focusCell(r, at)
        }
    }

    // Focus has moved onto a cell, which the top of the page follows. Past either edge of the grid, the time moves.
    // What the cells do, read afresh each time from this composition: one object for the whole grid, so a row whose
    // own things haven't changed isn't drawn again when the highlight moves.
    val latest = rememberUpdatedState(
        GuideHandlers(
            focused = { r, cell, on ->
                if (on) {
                    focusedKey = r to cell.start
                    spot = GuideSpot(r, maxOf(cell.start, from))
                } else if (focusedKey == r to cell.start) {
                    focusedKey = null
                }
            },
            activate = ::activate,
            watch = { c -> if (c.canTune) watch(c.key) },
            // Past the left edge: half an hour earlier, unless it's as early as the guide goes.
            earlier = {
                if (from <= GuideRules.floorSlot(now) - GuideRules.EARLIEST) focusCell(spot.row, spot.at) else shift(-GuideRules.SLOT, from - GuideRules.SLOT)
            },
            // Past the right edge: on to what's after the cell that was highlighted.
            later = {
                val end = currentCell?.end ?: to
                shift(GuideRules.SLOT, maxOf(end, to))
            },
        ),
    )
    val actions = remember {
        CellActions(
            focused = { r, cell, on -> latest.value.focused(r, cell, on) },
            activate = { c, cell -> latest.value.activate(c, cell) },
            more = { c, cell -> menu = c to cell },
            watch = { c -> latest.value.watch(c) },
            earlier = { latest.value.earlier(); true },
            later = { latest.value.later(); true },
            requester = { r, start -> requesters.getOrPut(r to start) { FocusRequester() } },
            forget = { r, start, req -> if (requesters[r to start] === req) requesters.remove(r to start) },
        )
    }

    LaunchedEffect(api) {
        launch { TvLookStore.load(api, nav.effectiveThemeId(dark), appColours) }
        launch { TvReminders.load(api) }
        store.setFrom(from)
        store.ensure(0)
        store.loadLineup()
        TvChannels.list = store.lineup
        TvLogos.ask(store.lineup.mapNotNull { it.brand }, api)
        if (notices.isEmpty()) runCatching { api.legalNotices() }.getOrNull()?.let { notices = it }
        placeFirstFocus()
    }
    // A changed filter starts at the top.
    LaunchedEffect(store.filter) {
        spot = GuideSpot(0, spot.at)
        store.ensure(0)
    }
    // The clock, a little at a time, and the guide kept current while it's open.
    LaunchedEffect(Unit) {
        var minutes = 0
        while (true) {
            delay(30_000)
            now = nowSeconds()
            minutes++
            if (minutes % 10 == 0) {
                store.refresh()
                reload()
            }
        }
    }
    // A row moved to from the top of the page comes into the middle of the grid.
    LaunchedEffect(spot.row) {
        if (focusedKey == null && visible.isNotEmpty() && spot.row !in visible) {
            listState.scrollToItem((spot.row - visible.size / 2).coerceAtLeast(0))
        }
    }

    // What the preview would show: the highlighted channel, the last one watched, or nothing.
    val previewWanted = when (dress.look.preview) {
        "off" -> ""
        "last" -> LastChannel.current(context).ifEmpty { if (current?.canTune == true) current.key else "" }
        else -> current?.let { if (it.canTune) it.key else "" } ?: ""
    }
    // Each channel the preview shows runs a stream, so it waits for the highlight to settle, and one that was only
    // flicked past isn't tuned at all.
    LaunchedEffect(previewWanted) {
        LiveTv.muted = !dress.look.previewSound
        if (previewWanted.isEmpty()) {
            LiveTv.stop()
            return@LaunchedEffect
        }
        if (previewWanted == LiveTv.key && !LiveTv.isFailed) return@LaunchedEffect
        delay(1500)
        LiveTv.watch(previewWanted, api)
    }
    // Out of the guide to anything but a channel: nothing is watched any more. Into a channel: it carries on there.
    DisposableEffect(Unit) {
        onDispose {
            view.post {
                val keeps = nav.stack.any { it is TvRoute && (it.screen is TvScreen.Channel || it.screen == TvScreen.Guide) } || nav.current == Route.LiveTv
                if (!keeps) LiveTv.stop()
            }
        }
    }

    val previewName = run {
        val c = current
        if (c != null && c.key == previewWanted) "${c.number} ${c.name}"
        else (store.lineup.firstOrNull { it.key == previewWanted } ?: TvChannels.list.firstOrNull { it.key == previewWanted })?.let { "${it.number} ${it.name}" } ?: ""
    }

    CompositionLocalProvider(LocalTvApi provides api) {
        BoxWithConstraints(Modifier.fillMaxSize().background(dress.paint.bg)) {
            width = maxWidth.value / TV_UNIT
            when {
                store.total == 0 && store.filter.isAll -> TvEmptyMessage(
                    "No channels yet",
                    if (nav.me?.isAdmin == true) "Make channels out of your library in one click, or add a tuner or an IPTV playlist, in the server's TV settings."
                    else "Ask whoever runs this server to set some up.",
                )
                store.total == null && store.error.isNotEmpty() -> LoadFailed(nav, store.error) {
                    store.error = ""
                    scope.launch { store.ensure(0) }
                }
                // The first time only: a filter changed later keeps the page while its rows come.
                store.total == null && !placed -> Loading()
                else -> Column(Modifier.fillMaxSize().padding(bottom = dress.pt(dress.foot / 2))) {
                    GuideHero(
                        nav, dress, current, currentCell, currentCell?.programmeAt(spot.at),
                        GuideRules.next(currentCell?.programmeAt(spot.at), currentCell, current), now,
                        previewWanted, previewName,
                        onWatch = ::watch, onDetails = { details(false) }, onDay = { details(true) },
                        onFavourite = { current?.let { favourite(it) } }, onStep = { moveRow(spot.row + it) },
                        onRecord = { val c = current; val p = currentCell?.programmeAt(spot.at); if (c != null && p != null) record(c, p) },
                        onSaid = ::say,
                    )
                    GuideBar(nav, dress, store, from, now, today, onShift = { shift(it) }, onNow = ::goNow, onJump = { goAt(it) },
                        onDay = { dayOpen = true }, onSearch = { searchOpen = true }, onLook = { lookOpen = true })
                    if (store.error.isNotEmpty()) {
                        Text(
                            store.error, style = dress.font(25f, W.Bold), color = dress.paint.err,
                            modifier = Modifier.fillMaxWidth().background(dress.paint.panel).padding(horizontal = dress.pt(dress.edge), vertical = dress.pt(8)),
                        )
                    }
                    GuideGrid(
                        dress, store, listState, from, to, now, slots, trackWidth, perSecond, spot, actions,
                        Modifier.weight(1f),
                    )
                    if (dress.shape in listOf(TvShape.Box, TvShape.Receiver, TvShape.Teletext, TvShape.Listings)) {
                        GuideFooter(dress, store.filter.kind, onShift = { shift(it) }, onKind = ::cycleKind)
                    }
                    GuideLegal(dress, notices, store.lineup)
                }
            }
            if (toast.isNotEmpty()) GuideToast(dress, toast)
        }
        ask?.let { a ->
            GuideDetails(nav, a, now, onWatch = ::watch, onSaid = ::say, onRecord = { c, p -> record(c, p) }, onSeries = { c, p -> series(c, p) }, onClose = { ask = null })
        }
        if (lookOpen) TvLookPanel(nav, onClose = { lookOpen = false })
        if (searchOpen) GuideSearch(nav, onGo = ::go, onClose = { searchOpen = false })
        menu?.let { (c, cell) ->
            CellMenu(
                c, cell, now, close = { menu = null },
                onMore = { day -> menu = null; ask = GuideAsk(c, cell.programmeAt(spot.at), cell, day) },
                onWatch = { menu = null; watch(c.key) },
                onRemind = { p -> menu = null; scope.launch { say(TvReminders.toggle(c.key, p)) } },
                onRecord = { p -> menu = null; record(c, p) },
                onSeries = { p -> menu = null; series(c, p) },
                onFavourite = { menu = null; favourite(c) },
            )
        }
        if (dayOpen) {
            DayPicker(today, onDay = { dayOpen = false; goDay(it) }, onClose = { dayOpen = false })
        }
    }
}

private const val FOCUS_TRIES = 8

// The channels as the guide last had them, for the remote to go through while one plays.
object TvChannels {
    var list: List<GuideChannel> = emptyList()
}

// The strip between the top and the grid: the filters, then the times to go to, search, the look and recordings.
@Composable
private fun GuideBar(
    nav: Nav,
    dress: TvDress,
    store: GuideStore,
    from: Long,
    now: Long,
    today: Long,
    onShift: (Long) -> Unit,
    onNow: () -> Unit,
    onJump: (Long) -> Unit,
    onDay: () -> Unit,
    onSearch: () -> Unit,
    onLook: () -> Unit,
) {
    val p = dress.paint
    val shape = dress.shape
    val filter = store.filter
    val all = filter.isAll
    val hasBoth = store.lineup.any { it.kind == "tuner" } && store.lineup.any { it.kind == "library" }
    val anyFavourite = store.lineup.any { it.favourite }
    val title = when (shape) {
        TvShape.Modern -> TvType(25f, W.Bold)
        TvShape.Receiver -> TvType(17.5f, W.Medium)
        TvShape.Teletext -> TvType(18.75f, W.Bold)
        TvShape.Listings -> TvType(30f, W.Bold)
        TvShape.Outline -> TvType(25f, W.Light)
        TvShape.Compact -> TvType(17.5f, W.Bold)
        else -> TvType(21.25f, W.Bold)
    }
    val titleColour = if (shape in listOf(TvShape.Modern, TvShape.Listings, TvShape.Cinema, TvShape.Outline, TvShape.Compact)) p.text else p.accent
    val fill = when (shape) {
        TvShape.Modern, TvShape.Receiver, TvShape.Listings, TvShape.Cinema, TvShape.Outline -> p.bg
        TvShape.Teletext -> p.panel2
        else -> p.panel
    }
    val rules = when (shape) {
        TvShape.Receiver -> Modifier.rule(Edge.Bottom, p.panel2, dress.pt(1))
        TvShape.Listings -> Modifier.rule(Edge.Bottom, p.text, dress.pt(1))
        TvShape.Cinema -> Modifier.rule(Edge.Top, p.panel2, dress.pt(1))
        else -> Modifier
    }
    val dayLabel = run {
        val n = GuideRules.daysBetween(today, from)
        when {
            n < 0 -> "Yesterday"
            n == 0 -> "Today"
            n == 1 -> "Tomorrow"
            else -> GuideRules.dayName(from)
        }
    }
    Row(
        Modifier
            .fillMaxWidth()
            .background(fill)
            .then(rules)
            .padding(horizontal = dress.pt(dress.edge - 8))
            .focusGroup(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
    ) {
        Text(
            dress.words(if (dress.capitals) "GUIDE" else "Guide", title.size, smallCaps = true),
            style = dress.font(title.size, title.weight, tracking = if (shape == TvShape.Receiver) 2.4f else 0f), color = titleColour,
            maxLines = 1, modifier = Modifier.semantics { heading() },
        )
        Row(
            Modifier
                .weight(1f)
                .horizontalScroll(rememberScrollState())
                .padding(vertical = dress.pt(10), horizontal = dress.pt(8)),
            horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
        ) {
            Chip(dress, "All", all) { store.choose(GuideFilter()) }
            if (anyFavourite || filter.favourites) Chip(dress, "★ Favourites", filter.favourites) { store.choose(GuideFilter(favourites = !filter.favourites)) }
            for (g in store.groups) Chip(dress, g, filter.group == g) { store.choose(GuideFilter(group = if (filter.group == g) "" else g)) }
            if (hasBoth) {
                Chip(dress, "My library", filter.kind == "library") { store.choose(GuideFilter(kind = if (filter.kind == "library") "" else "library")) }
                Chip(dress, "Live TV", filter.kind == "tuner") { store.choose(GuideFilter(kind = if (filter.kind == "tuner") "" else "tuner")) }
            }
        }
        Row(Modifier.padding(vertical = dress.pt(10)), horizontalArrangement = Arrangement.spacedBy(dress.pt(16)), verticalAlignment = Alignment.CenterVertically) {
            TvIconButton(dress, TvSymbols.ChevronLeft, "Half an hour earlier", { onShift(-GuideRules.SLOT) }, onBar = true)
            TvButton(dress, "Now", onNow, on = GuideRules.floorSlot(now) == from, onBar = true)
            TvIconButton(dress, Symbols.Next, "Half an hour later", { onShift(GuideRules.SLOT) }, onBar = true)
            for (j in GuideRules.jumps(now, TimeZone.getDefault())) TvButton(dress, j.label, { onJump(j.at) }, kind = TvButtonKind.Link, onBar = true)
            TvButton(dress, "$dayLabel ▾", onDay, onBar = true)
            TvIconButton(dress, Symbols.Search, "Search the schedule", onSearch, onBar = true)
            TvButton(dress, "Look", onLook, onBar = true)
            TvButton(dress, "Recordings", { nav.push(TvRoute(TvScreen.Recordings)) }, onBar = true)
            if (nav.me?.isAdmin == true) TvButton(dress, "Edit channels", { nav.push(Route.OnPhone("Edit channels", "/tv/channels")) }, onBar = true, icon = Symbols.Settings)
        }
    }
}

@Composable
private fun Chip(dress: TvDress, words: String, on: Boolean, action: () -> Unit) {
    TvButton(dress, words, action, kind = TvButtonKind.Chip, on = on, onBar = true, selected = on)
}

// The grid: the times, then a row for each channel, with the line at the current time over both.
@Composable
private fun GuideGrid(
    dress: TvDress,
    store: GuideStore,
    listState: androidx.compose.foundation.lazy.LazyListState,
    from: Long,
    to: Long,
    now: Long,
    slots: Int,
    trackWidth: Float,
    perSecond: Double,
    spot: GuideSpot,
    actions: CellActions,
    modifier: Modifier,
) {
    val p = dress.paint
    val total = store.total ?: 0
    Box(modifier.fillMaxWidth().padding(horizontal = dress.pt(dress.edge)).heightIn(min = dress.pt(260))) {
        Column(Modifier.fillMaxSize()) {
            GuideTimes(dress, from, now, slots)
            LazyColumn(Modifier.weight(1f).fillMaxWidth().clipToBounds().focusGroup(), state = listState) {
                items(total, key = { it }) { r ->
                    LaunchedEffect(r, store.filter) { store.ensure(r) }
                    GuideRow(dress, r, store.rows[r], from, to, perSecond, now, current = r == spot.row, focusAt = if (r == spot.row) spot.at else null, actions = actions)
                }
            }
            if (store.total == 0) {
                Text(
                    if (store.filter.favourites) "No favourites yet: hold Select on a channel to make it one." else "No channels match that.",
                    style = dress.font(25f, W.Bold), color = p.err, modifier = Modifier.padding(vertical = dress.pt(12)),
                )
            }
        }
        if (dress.look.nowLine && now >= from && now < to) {
            GuideNowLine(dress, dress.pt(dress.channelWidth + trackWidth * (now - from).toFloat() / (to - from)), now, Modifier.fillMaxSize())
        }
    }
}

// Underneath, on the shapes of the era: the coloured keys and what the remote does.
@Composable
private fun GuideFooter(dress: TvDress, kind: String, onShift: (Long) -> Unit, onKind: () -> Unit) {
    val p = dress.paint
    val shape = dress.shape
    Row(
        Modifier
            .fillMaxWidth()
            .background(if (shape == TvShape.Box) Brush.verticalGradient(listOf(p.panel, p.bg)) else Brush.verticalGradient(listOf(p.bg, p.bg)))
            .then(
                when (shape) {
                    TvShape.Box -> Modifier.rule(Edge.Top, p.line, dress.pt(3))
                    TvShape.Receiver -> Modifier.rule(Edge.Top, p.line, dress.pt(1))
                    TvShape.Listings -> Modifier.rule(Edge.Top, p.text, dress.pt(1))
                    else -> Modifier
                },
            )
            .padding(horizontal = dress.pt(dress.edge), vertical = dress.pt(6))
            .focusGroup(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
    ) {
        Key(dress, "A", "Day −", p.keyA) { onShift(-86400) }
        Key(dress, "B", "Day +", p.keyB) { onShift(86400) }
        Key(dress, "C", if (kind.isEmpty()) "All" else if (kind == "library") "Library" else "Live TV", p.keyC, onKind)
        Spacer(Modifier.weight(1f).width(dress.pt(16)))
        Text(
            "▲▼ Channel · ◄► Time · Select Watch · Hold Select for more · Play/Pause Watch the channel",
            style = dress.font(17.5f, italic = shape == TvShape.Listings), color = p.soft, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun Key(dress: TvDress, letter: String, words: String, colour: Color, action: () -> Unit) {
    TvButton(dress, action, kind = TvButtonKind.Link) { ink, style ->
        Box(
            Modifier
                .size(dress.pt(26))
                .background(colour, if (dress.shape == TvShape.Receiver || dress.shape == TvShape.Teletext) RectangleShape else CircleShape),
            contentAlignment = Alignment.Center,
        ) { Text(letter, style = dress.font(15f, W.Bold), color = dress.paint.keyText, maxLines = 1) }
        Text(if (dress.capitals) words.uppercase() else words, style = style, color = ink, maxLines = 1)
    }
}

// The short notices the owner's channels and logos come with, in the server's words.
@Composable
private fun GuideLegal(dress: TvDress, notices: Map<String, String>, lineup: List<GuideChannel>) {
    val shown = listOfNotNull(
        notices["tv"],
        if (dress.look.logos && lineup.any { it.logo?.startsWith("/") == true || TvLogos.info(it.brand)?.has == true }) notices["logos"] else null,
    )
    if (shown.isEmpty()) return
    Column(
        Modifier.fillMaxWidth().padding(horizontal = dress.pt(dress.edge), vertical = dress.pt(8)).semantics(mergeDescendants = true) { },
        verticalArrangement = Arrangement.spacedBy(dress.pt(4)),
    ) {
        for (n in shown) Text(n, style = dress.font(13.75f).copy(fontFamily = null), color = dress.paint.soft, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

// What was just done, said for a moment at the bottom, in the look's highlight.
@Composable
private fun GuideToast(dress: TvDress, words: String) {
    Box(Modifier.fillMaxSize().padding(bottom = dress.pt(60)), contentAlignment = Alignment.BottomCenter) {
        Text(
            words, style = MaterialTheme.typography.labelLarge, color = dress.paint.hiText,
            modifier = Modifier.background(dress.paint.hi, CircleShape).padding(horizontal = dress.pt(24), vertical = dress.pt(14)),
        )
    }
}

// What a guide with nothing in it says, in the app's own type, as Apple TV's EmptyMessage.
@Composable
fun TvEmptyMessage(title: String, detail: String) {
    Box(Modifier.fillMaxSize().padding(dress32()), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy((8 * TV_UNIT).dp)) {
            Text(title, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.section, modifier = Modifier.semantics { heading() })
            Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, textAlign = TextAlign.Center)
        }
    }
}

private fun dress32() = (32 * TV_UNIT).dp

// What holding Select on a cell offers, as Apple TV's context menu does.
@Composable
private fun CellMenu(
    channel: GuideChannel,
    cell: GuideCell,
    now: Long,
    close: () -> Unit,
    onMore: (Boolean) -> Unit,
    onWatch: () -> Unit,
    onRemind: (GuideProgramme) -> Unit,
    onRecord: (GuideProgramme) -> Unit,
    onSeries: (GuideProgramme) -> Unit,
    onFavourite: () -> Unit,
) {
    val later = cell.start > now && cell.kind == GuideCell.Kind.Programme
    val p = cell.programme
    val items = buildList {
        add(TvDialogButton("More about this") { onMore(false) })
        add(TvDialogButton("The whole day on ${channel.name}") { onMore(true) })
        if (channel.canTune) add(TvDialogButton("Watch ${channel.name} now", action = onWatch))
        if (later && channel.canTune && p != null && p.kind != "slate") {
            add(TvDialogButton(if (TvReminders.has(channel.key, cell.start)) "Remove the reminder" else "Remind me") { onRemind(p) })
        }
        if (channel.canRecord == true && cell.isBroadcast && cell.end > now && p != null) {
            add(TvDialogButton("Record this") { onRecord(p) })
            add(TvDialogButton("Record every airing") { onSeries(p) })
        }
        add(TvDialogButton(if (channel.favourite) "Remove from favourites" else "Add to favourites", action = onFavourite))
    }
    TvDialog(title = "", message = null, buttons = items, onClose = close, stacked = true)
}

// The days to go to, as Apple TV's dialog lists them.
@Composable
private fun DayPicker(today: Long, onDay: (Int) -> Unit, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    TvDialog(
        title = "Day",
        message = null,
        buttons = (0 until 15).map { n ->
            val name = when (n) {
                0 -> "Today"
                1 -> "Tomorrow"
                else -> GuideRules.dayName(today + n * 86400L + 3600)
            }
            TvDialogButton(name) { onDay(n) }
        } + TvDialogButton("Cancel", cancel = true, action = onClose),
        stacked = true,
        onClose = onClose,
    )
}
