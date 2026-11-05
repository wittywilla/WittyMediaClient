package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.wittywilla.wittymediaclient.net.ForYou
import com.wittywilla.wittymediaclient.net.GUIDE_PATH
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.Home
import com.wittywilla.wittymediaclient.net.HomeLayout
import com.wittywilla.wittymediaclient.net.Hub
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.UpdateStatus
import com.wittywilla.wittymediaclient.net.albumsOnce
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.IOException
import java.util.Calendar

// The website's Home on a phone (web/src/pages/HomePage.tsx): its sections in the order this person saved, with
// those they hid left out (HomeLook.kt has the rules); the hero under the library strip when it comes first; a
// greeting when nothing is featured; the notice of a newer server for administrators; a card while the libraries are
// empty or still being looked through; and Customize home at the foot, which rearranges and hides the sections.
private const val HERO_EVERY_MS = 9000L
private const val RETRY_MS = 5000L

// Saving the layout, and reading it back, one at a time and in turn, so an older answer never wins.
private val homeChoicesInTurn = Mutex()

// Pictures and creator videos are wide; a poster's shape would crop them.
private val WIDE_LIBRARIES = setOf("photos", "channels", "musicvideos")

// Why Home couldn't come: the server out of reach, which is tried again every few seconds, or what it said.
private data class Trouble(val offline: Boolean, val words: String)

// What the sections are drawn from.
private class HomeParts(
    val home: Home,
    // The libraries in the menus, for the tiles.
    val libraries: List<Library>,
    val channels: List<GuideChannel>,
    val forYou: ForYou?,
    val pick: Item?,
    val admin: Boolean,
    val another: () -> Unit,
)

@Composable
fun PhoneHome(nav: Nav, s: Map<String, String>) {
    val api = nav.app.api
    var home by remember { mutableStateOf(nav.remembered<Home>("home")) }
    var trouble by remember { mutableStateOf<Trouble?>(null) }
    // A refresh that failed while the page was already up: the page stays, with the reason.
    var problem by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    var onNow by remember { mutableStateOf(emptyList<GuideChannel>()) }
    var forYou by remember { mutableStateOf<ForYou?>(null) }
    var pick by remember { mutableStateOf<Item?>(null) }
    var roll by remember { mutableIntStateOf(0) }
    var layout by remember { mutableStateOf(nav.remembered<HomeLayout>("homeLayout") ?: HomeLayout()) }
    var editing by rememberSaveable { mutableStateOf(false) }
    // The newer version the server found, for administrators, and the one they put off.
    var update by remember { mutableStateOf("") }
    var putOff by remember { mutableStateOf("") }
    var updateStatus by remember { mutableStateOf<UpdateStatus?>(null) }
    var toast by remember { mutableStateOf("") }
    val admin = nav.me?.isAdmin == true

    LaunchedEffect(attempt) {
        try {
            val fresh = api.home()
            home = fresh
            nav.remember("home", fresh)
            trouble = null
            problem = ""
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) {
                val words = problemWords(e, s["errLost"].orEmpty())
                if (home == null) trouble = Trouble(e is IOException, words) else problem = words
            }
        }
    }
    // Offline, it tries again every few seconds, so Home comes back by itself when the server does.
    LaunchedEffect(trouble) {
        if (trouble?.offline != true) return@LaunchedEffect
        delay(RETRY_MS)
        attempt++
    }
    LaunchedEffect(Unit) {
        launch {
            nav.hasGuide = runCatching { "live-tv" in api.capabilities().features }.getOrDefault(false)
            if (nav.hasGuide) onNow = OnNowLook.ordered(runCatching { api.guide(1, OnNowLook.LIMIT).channels }.getOrDefault(emptyList()))
        }
        launch { forYou = runCatching { api.forYou() }.getOrNull() }
        launch {
            val chosen = homeChoicesInTurn.withLock { runCatching { api.homeChoices() }.getOrNull() } ?: return@launch
            if (!editing) {
                layout = HomeLayout.saved(chosen.home)
                nav.remember("homeLayout", layout)
            }
            putOff = chosen.updateLater.orEmpty()
        }
    }
    LaunchedEffect(roll) { runCatching { api.randomItem() }.getOrNull()?.let { pick = it } }
    LaunchedEffect(admin) { update = if (admin) runCatching { api.status().update }.getOrDefault("") else "" }
    val showsUpdate = UpdateNews.shows(update, admin, putOff)
    // A build that can't update itself has no /update: the notice still shows, without its first change.
    LaunchedEffect(showsUpdate) { updateStatus = if (showsUpdate) runCatching { api.updateStatus() }.getOrNull() else null }
    BackHandler(editing) { editing = false }

    fun save(next: HomeLayout) {
        layout = next
        nav.remember("homeLayout", next)
        nav.app.scope.launch {
            homeChoicesInTurn.withLock {
                try {
                    api.saveHomeLayout(next)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    toast = "Could not save the layout"
                }
            }
        }
    }

    fun later() {
        val version = update
        putOff = version
        nav.app.scope.launch {
            try {
                api.putOffUpdate(version)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                toast = "Could not save that"
            }
        }
    }

    val notice: (@Composable (Modifier) -> Unit)? = if (showsUpdate) { m -> UpdateNotice(nav, update, updateStatus, ::later, m) } else null
    val h = home
    val failed = trouble
    Box(Modifier.fillMaxSize()) {
        when {
            h == null && failed != null -> TroublePage(failed) { attempt++ }
            h == null -> HomeSkeleton()
            h.libraries.isEmpty() -> WelcomePage(nav, admin, notice)
            else -> {
                val parts = HomeParts(h, h.libraries.distinctBy { it.id }.filter { it.inMainMenus }, onNow, forYou, pick, admin) { roll++ }
                val widgets = layout.ordered(HomeWidgets.list(h, forYou)) { it.id }
                if (editing) {
                    HeroPage(false)
                    EditPage(nav, parts, widgets, layout, ::save) { editing = false }
                } else {
                    HomePage(nav, parts, widgets, layout, problem, notice) { editing = true }
                }
            }
        }
        if (toast.isNotEmpty()) Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = LocalBottomRoom.current - 4.dp))
    }
}

// Whether a section has anything to show. One that hasn't is left out, as the website leaves it out.
private fun renders(widget: HomeWidget, parts: HomeParts): Boolean = when (widget.id) {
    HomeWidgets.HERO -> parts.home.featured.isNotEmpty()
    HomeWidgets.LIBRARIES -> parts.libraries.isNotEmpty()
    HomeWidgets.ON_NOW -> parts.channels.isNotEmpty()
    HomeWidgets.SHUFFLE -> parts.pick != null
    else -> widget.hub?.isEmpty == false
}

@Composable
private fun HomePage(nav: Nav, parts: HomeParts, widgets: List<HomeWidget>, layout: HomeLayout, problem: String, update: (@Composable (Modifier) -> Unit)?, customize: () -> Unit) {
    val list = rememberLazyListState()
    TracksScroll(list)
    val home = parts.home
    val shown = widgets.filter { it.id !in layout.hidden && renders(it, parts) }
    // The hero runs up under the strip when it's the first thing on the page.
    val onTop = update == null && shown.firstOrNull()?.id == HomeWidgets.HERO
    HeroPage(onTop)
    val greet = home.featured.isEmpty() || HomeWidgets.HERO in layout.hidden
    LazyColumn(state = list, contentPadding = PaddingValues(top = if (onTop) 0.dp else LocalTopRoom.current, bottom = LocalBottomRoom.current)) {
        // The website sets the notice in by a gutter of its own, inside the page's.
        if (update != null) item(key = "~update") { update(Modifier.padding(start = 32.dp, end = 32.dp, top = 12.dp)) }
        if (greet) item(key = "~greet") { Greeting(nav, Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp)) }
        if (!onTop && problem.isNotEmpty()) item(key = "~problem") { ErrorText(problem, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp)) }
        if (HomeWidgets.isEmpty(home)) item(key = "~empty") { EmptyCard(nav, parts, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 30.dp)) }
        shown.forEach { widget ->
            item(key = widget.id) { Section(nav, widget, parts, preview = false) }
            if (onTop && widget.id == HomeWidgets.HERO && problem.isNotEmpty()) item(key = "~problem") { ErrorText(problem, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp)) }
        }
        // A page action, not a heading: at the foot of the page.
        item(key = "~customize") {
            Box(Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 4.dp), contentAlignment = Alignment.Center) {
                WebButton("Customize home", customize, WebButtonKind.Ghost, small = true)
            }
        }
        item(key = "~foot") { PageFoot(nav) }
    }
}

@Composable
private fun Section(nav: Nav, widget: HomeWidget, parts: HomeParts, preview: Boolean) {
    when (widget.id) {
        HomeWidgets.HERO -> if (parts.home.featured.isNotEmpty()) Hero(nav, parts.home.featured.distinctBy { it.id }, preview)
        HomeWidgets.LIBRARIES -> LibraryTiles(nav, parts.libraries, parts.admin, preview)
        HomeWidgets.ON_NOW -> if (parts.channels.isNotEmpty()) OnNowRow(nav, parts.channels, preview)
        HomeWidgets.SHUFFLE -> parts.pick?.let { CantDecide(nav, it, parts.another, preview) }
        // A row's library is looked up among them all, as one kept out of the menus still has its rows.
        else -> widget.hub?.takeIf { !it.isEmpty }?.let { HubSection(nav, it, parts.home.libraries, preview) }
    }
}

// MARK: Customize home

// Customize home (the website's editing mode): what it does and Reset and Done in a bar that stays under the strip,
// then every section, hidden ones too, as a dashed card with its name, Up, Down and Hide or Show, and a small look at
// it. A long press picks a section up, to drop it on another's place.
@Composable
private fun EditPage(nav: Nav, parts: HomeParts, widgets: List<HomeWidget>, layout: HomeLayout, save: (HomeLayout) -> Unit, done: () -> Unit) {
    val scroll = rememberScrollState()
    TracksScroll(scroll)
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val ids = widgets.map { it.id }
    val barBottom = LocalTopRoom.current - 8.dp
    val bottomRoom = LocalBottomRoom.current
    // Where each section is on the screen, for dropping one on another.
    val bounds = remember { HashMap<String, ClosedFloatingPointRange<Float>>() }
    var dragging by remember { mutableStateOf<String?>(null) }
    var moved by remember { mutableFloatStateOf(0f) }
    var fingerAt by remember { mutableFloatStateOf(0f) }
    var scrolledFrom by remember { mutableIntStateOf(0) }
    var view by remember { mutableStateOf(0f..0f) }
    val drop by rememberUpdatedState { id: String ->
        val target = bounds.entries.firstOrNull { it.key != id && fingerAt in it.value }?.key
        if (target != null) save(layout.moving(id, ids.indexOf(target), ids))
    }
    // Near the top or the foot while carrying a section, the page scrolls along.
    LaunchedEffect(dragging) {
        if (dragging == null) return@LaunchedEffect
        val edge = with(density) { 48.dp.toPx() }
        val step = with(density) { 8.dp.toPx() }
        while (true) {
            val by = when {
                fingerAt < view.start + edge -> -step
                fingerAt > view.endInclusive - edge -> step
                else -> 0f
            }
            if (by != 0f) scroll.scrollBy(by)
            withFrameNanos { }
        }
    }
    Box(
        Modifier.fillMaxSize().onGloballyPositioned {
            val top = it.positionInRoot().y
            view = (top + with(density) { (barBottom + 120.dp).toPx() })..(top + it.size.height - with(density) { bottomRoom.toPx() })
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(start = 16.dp, end = 16.dp, top = barBottom, bottom = bottomRoom)) {
            // In the flow 4 below the strip, it stays against the strip once the page scrolls.
            HomeTools({ save(HomeLayout()) }, done, Modifier.zIndex(1f).padding(top = 4.dp, bottom = 14.dp).graphicsLayer { translationY = maxOf(0f, scroll.value - 4.dp.toPx()) })
            widgets.forEachIndexed { place, widget ->
                key(widget.id) {
                    val hidden = widget.id in layout.hidden
                    val carried = dragging == widget.id
                    WidgetEditor(
                        widget.title, hidden, carried, place == 0, place == widgets.lastIndex,
                        up = { save(layout.moving(widget.id, place - 1, ids)) },
                        down = { save(layout.moving(widget.id, place + 1, ids)) },
                        toggle = { save(layout.toggling(widget.id)) },
                        modifier = Modifier
                            .padding(bottom = 12.dp)
                            .zIndex(if (carried) 0.5f else 0f)
                            .graphicsLayer { if (carried) translationY = moved + (scroll.value - scrolledFrom) }
                            .onGloballyPositioned { at -> val top = at.positionInRoot().y; bounds[widget.id] = top..(top + at.size.height) }
                            .pointerInput(widget.id) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = { from ->
                                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                        dragging = widget.id
                                        moved = 0f
                                        scrolledFrom = scroll.value
                                        fingerAt = (bounds[widget.id]?.start ?: 0f) + from.y
                                    },
                                    onDragEnd = { drop(widget.id); dragging = null },
                                    onDragCancel = { dragging = null },
                                    onDrag = { change, by ->
                                        change.consume()
                                        moved += by.y
                                        fingerAt += by.y
                                    },
                                )
                            },
                    ) {
                        if (widget.id == HomeWidgets.HERO && parts.home.featured.isEmpty() || widget.id == HomeWidgets.FOR_YOU && parts.forYou == null) {
                            Text("Nothing to show here right now.", color = LocalExtraColours.current.hint, fontSize = 15.sp)
                        } else {
                            Section(nav, widget, parts, preview = true)
                        }
                    }
                }
            }
            PageFoot(nav)
        }
    }
}

// The bar of Customize home (shell.css `.home-tools`): the panel with a hairline and the resting shadow, radius 10,
// 10 by 14 inside; what to do in 13 textHint, then Reset and Done at the right.
@Composable
private fun HomeTools(reset: () -> Unit, done: () -> Unit, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier.fillMaxWidth().restingShadow(10.dp).clip(RoundedCornerShape(10.dp)).background(scheme.surface)
            .border(1.dp, scheme.outline, RoundedCornerShape(10.dp)).padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("Drag sections, or use the arrows. Hidden sections stay here until you show them again.", color = LocalExtraColours.current.hint, fontSize = 13.sp, lineHeight = 20.sp, modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            WebButton("Reset", reset, WebButtonKind.Ghost, small = true)
            WebButton("Done", done, WebButtonKind.Primary, small = true)
        }
    }
}

// One section in Customize home (`.widget.edit`): the panel in a dashed outline of text at 20%, radius 14; a bar 8 by
// 12 inside with the grip in textHint, the name in 15 semibold, Up and Down, and Hide or Show; then the small look.
// Hidden, it's faded to 55% with only its bar; carried, to 40%.
@Composable
private fun WidgetEditor(
    title: String, hidden: Boolean, carried: Boolean, first: Boolean, last: Boolean,
    up: () -> Unit, down: () -> Unit, toggle: () -> Unit, modifier: Modifier, preview: @Composable () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier.fillMaxWidth().alpha(if (carried) 0.4f else if (hidden) 0.55f else 1f).clip(RoundedCornerShape(14.dp)).background(scheme.surface)
            .dashedBorder(scheme.onBackground.copy(alpha = 0.2f), 14.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(WebIcons.Grip, null, tint = LocalExtraColours.current.hint, modifier = Modifier.size(18.dp))
            Text(title, color = scheme.onBackground, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            WebButton("Move $title up", up, WebButtonKind.Ghost, WebIcons.Up, small = true, square = true, enabled = !first)
            WebButton("Move $title down", down, WebButtonKind.Ghost, WebIcons.Down, small = true, square = true, enabled = !last)
            WebButton(if (hidden) "Show" else "Hide", toggle, WebButtonKind.Secondary, small = true)
        }
        if (!hidden) WidgetPreview(preview)
    }
}

// The small look at a section (`.widget-preview`): at most 280 high, 12 in at the sides and foot, fading out over its
// last fifth, with nothing in it to press or to read out.
@Composable
private fun WidgetPreview(content: @Composable () -> Unit) {
    Box(
        Modifier.fillMaxWidth().heightIn(max = 280.dp).clipToBounds()
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                drawRect(Brush.verticalGradient(0.8f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
            }
            .padding(start = 12.dp, end = 12.dp, bottom = 12.dp)
            .clearAndSetSemantics { },
    ) {
        Box(Modifier.fillMaxWidth().wrapContentHeight(Alignment.Top, unbounded = true)) { content() }
        // Over the look, so a press reaches the section around it and not what's drawn.
        Box(Modifier.matchParentSize().pointerInput(Unit) { })
    }
}

// MARK: the top of Home

// When nothing is featured: "Good morning, Willow" in 24 semibold over "Here's what's on your server." in textHint.
@Composable
private fun Greeting(nav: Nav, modifier: Modifier) {
    val me = nav.me
    val name = me?.displayName?.ifEmpty { me.name }.orEmpty()
    Column(modifier.fillMaxWidth()) {
        Text(
            HomeGreeting.line(Calendar.getInstance().get(Calendar.HOUR_OF_DAY), name), color = MaterialTheme.colorScheme.onBackground,
            fontSize = 24.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em, lineHeight = 28.sp,
            modifier = Modifier.padding(bottom = 4.dp).semantics { heading() },
        )
        Text("Here’s what’s on your server.", color = LocalExtraColours.current.hint, fontSize = 15.sp)
    }
}

// A newer server, for administrators (components/UpdateBanner.tsx, ui `Notice`): the card colour with an outline of
// text at 20%, radius 10, 12 by 16 inside; the version in 14 semibold, its first change, then Update, What's new and
// Later. Update and What's new open Settings, About on the server's page.
@Composable
private fun UpdateNotice(nav: Nav, version: String, status: UpdateStatus?, later: () -> Unit, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val about = { nav.push(Route.Page("/settings/about#updates", "About")) }
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)
            .border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)).padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(UpdateNews.title(version), color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 18.sp)
            if (status != null) Text(UpdateNews.sentence(status), color = scheme.onBackground, fontSize = 14.sp, lineHeight = 18.sp)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            WebButton(UpdateNews.action(status), about, WebButtonKind.Primary, small = true)
            WebButton("What’s new", about, WebButtonKind.Secondary, small = true)
            WebButton("Later", later, WebButtonKind.Ghost, small = true)
        }
    }
}

// The website's `.home-card`, centred: the panel with a hairline, radius 20, 32 by 24 inside, no wider than 560; a 52
// circle of the accent at 14% with its 26 icon in accentText, the title in 20 semibold, the words in textHint, and what
// to do about it.
@Composable
private fun HomeCard(icon: ImageVector, title: String, words: String, modifier: Modifier = Modifier, action: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 560.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(scheme.surface)
                .border(1.dp, scheme.outline, RoundedCornerShape(20.dp)).padding(horizontal = 24.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(52.dp).clip(CircleShape).background(scheme.primary.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = extra.accentText, modifier = Modifier.size(26.dp))
            }
            Text(title, color = scheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp).semantics { heading() })
            Text(words, color = extra.hint, fontSize = 15.sp, lineHeight = 23.sp, textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 440.dp).padding(bottom = 8.dp))
            action()
        }
    }
}

// Nothing featured and every row empty: the libraries are still being looked through, or nothing was found in them.
@Composable
private fun EmptyCard(nav: Nav, parts: HomeParts, modifier: Modifier) {
    val scanning = parts.home.libraries.any { it.scanning }
    HomeCard(
        WebIcons.Refresh,
        if (scanning) "Your libraries are being scanned" else "Your libraries are empty",
        if (scanning) "Movies, shows, music and books appear here as they’re found. The first scan can take a few minutes."
        else "Nothing was found in their folders yet. Check the folders in Settings, Libraries, then scan again.",
        modifier,
    ) {
        if (parts.admin && !scanning) WebButton("Open library settings", { nav.push(Route.Page("/settings/libraries", "Libraries")) }, WebButtonKind.Secondary)
    }
}

// The server can't be reached, or Home didn't load: the card 8% of the screen down, and Try again.
@Composable
private fun TroublePage(trouble: Trouble, retry: () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = LocalTopRoom.current + maxHeight * 0.08f, bottom = LocalBottomRoom.current)) {
            HomeCard(
                WebIcons.Info,
                if (trouble.offline) "Can’t reach your server" else "Home didn’t load",
                if (trouble.offline) "Check that WittyMediaServer is running on its computer and that this device is on the same network. This page tries again by itself every few seconds."
                else trouble.words,
                Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
            ) {
                WebButton("Try again", retry, WebButtonKind.Primary, WebIcons.Refresh)
            }
        }
    }
}

// The first visit, before there's any library (HomePage.tsx Welcome): a welcome, what to do, and for administrators
// the way to add one, which is the server's Libraries settings.
@Composable
private fun WelcomePage(nav: Nav, admin: Boolean, update: (@Composable (Modifier) -> Unit)?) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val me = nav.me
    val name = me?.displayName?.ifEmpty { me.name }.orEmpty()
    val list = rememberScrollState()
    TracksScroll(list)
    HeroPage(false)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val screen = maxHeight
        Column(Modifier.fillMaxSize().verticalScroll(list).padding(start = 16.dp, end = 16.dp, top = LocalTopRoom.current, bottom = LocalBottomRoom.current)) {
            update?.invoke(Modifier.padding(bottom = 16.dp))
            Column(Modifier.fillMaxWidth().padding(top = screen * 0.04f, bottom = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.size(64.dp).clip(CircleShape).background(scheme.primary.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                        Icon(WebIcons.forLibrary("movies"), null, tint = extra.accentText, modifier = Modifier.size(32.dp))
                    }
                    Text(
                        "Welcome${if (name.isEmpty()) "" else ", $name"}! Let’s fill your server.", color = scheme.onBackground, fontSize = 30.sp,
                        fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em, lineHeight = 34.sp, textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 6.dp).semantics { heading() },
                    )
                    val words = buildAnnotatedString {
                        append(
                            if (admin) "Choose what kind of media you have, then point to the folder it’s in. Your files stay where they are; nothing is moved or changed. You can add more libraries any time. "
                            else "There’s nothing to watch, read or listen to yet. Whoever runs this server can add libraries in Settings, and they’ll appear here. ",
                        )
                        withLink(LinkAnnotation.Clickable("getting-started", TextLinkStyles(SpanStyle(color = extra.accentText, textDecoration = TextDecoration.Underline))) { nav.push(Route.Page("/help/getting-started", "Getting started")) }) {
                            append("Getting started")
                        }
                    }
                    Text(words, color = extra.hint, fontSize = 15.sp, lineHeight = 23.sp, textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 580.dp))
                }
                if (admin) LibraryTile("Add a library", "Another folder of media", WebIcons.Plus, true, Modifier.fillMaxWidth()) { nav.push(Route.Page("/settings/libraries", "Libraries")) }
            }
            PageFoot(nav)
        }
    }
}

// MARK: the hero

// The hero: 66% of the height (380 to 660), the backdrops cross-fading over 420 ms, shaded from the page colour at
// the foot. The title 30 at 650, the facts 14, two lines of the synopsis, the main button, Disc menu for a disc with
// menus, and Details. Dots and pause at the top right; it moves on every 9 seconds, and not at all with Reduce Motion.
// In Customize home it's 240 high with its corners rounded, without the synopsis or the dots.
@Composable
private fun Hero(nav: Nav, featured: List<Item>, preview: Boolean) {
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
        val screen = LocalConfiguration.current.screenHeightDp.dp
        val height = if (preview) 240.dp else (screen * 0.66f).coerceIn(380.dp, 660.dp)
        val wide = maxWidth
        Box(Modifier.fillMaxWidth().height(height).then(if (preview) Modifier.clip(RoundedCornerShape(10.dp)) else Modifier)) {
            Crossfade(item, animationSpec = tween(420, easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)), label = "hero") { shown ->
                WebArt(nav.app.api.backdropUrl(shown), "", wide, wide / height, Modifier.fillMaxSize())
            }
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.18f to page.copy(alpha = 0f), 0.44f to page.copy(alpha = 0.72f), 0.66f to page.copy(alpha = 0.94f), 1f to page)))
            Column(Modifier.align(Alignment.BottomStart).padding(start = 16.dp, end = 16.dp, bottom = if (preview) 12.dp else 24.dp).fillMaxWidth()) {
                Text(item.title, color = scheme.onBackground, fontSize = 30.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em, lineHeight = 34.sp, modifier = Modifier.padding(bottom = 12.dp))
                val facts = HeroLook.facts(item)
                if (facts.isNotEmpty()) HeroFactsRow(facts, Modifier.padding(bottom = 12.dp))
                if (!preview && item.overview.isNotEmpty()) Text(item.overview, color = scheme.onBackground.copy(alpha = 0.86f), fontSize = 15.sp, lineHeight = 23.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(bottom = 20.dp))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    MainButton(nav, item)
                    if (item.isDisc && item.disc?.hasMenus == true) WebButton("Disc menu", { nav.push(Route.Page(OpenLook.discMenu(item))) }, WebButtonKind.Secondary)
                    WebButton("Details", { nav.push(Route.Item(item.id)) }, WebButtonKind.Ghost, WebIcons.Info)
                }
            }
            if (featured.size >= 2 && !preview) {
                Row(Modifier.align(Alignment.TopEnd).padding(top = LocalTopRoom.current, end = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Pressable({ paused = !paused }, Modifier.size(24.dp), shape = CircleShape, fill = Color.Transparent, label = if (paused) "Start turning the featured titles" else "Stop turning the featured titles", ring = false) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(if (paused) WebIcons.Play else WebIcons.Pause, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(16.dp)) }
                    }
                    Spacer(Modifier.width(4.dp))
                    featured.forEachIndexed { i, _ ->
                        val on = i == index
                        val w by animateDpAsState(if (on) 18.dp else 8.dp, tween(150), label = "dot")
                        Pressable({ index = i }, Modifier.size(24.dp), shape = CircleShape, fill = Color.Transparent, label = "Show featured title ${i + 1}", selected = on, ring = false) {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Box(Modifier.width(w).height(8.dp).clip(RoundedCornerShape(4.dp)).background(if (on) scheme.onBackground else scheme.onBackground.copy(alpha = 0.45f)))
                            }
                        }
                    }
                }
            }
        }
    }
    if (!preview) Spacer(Modifier.height(28.dp))
}

// The hero's line of facts (`.meta`): 14 in textSecondary, 16 apart, wrapping 2 apart, with a dot in textHint in each
// gap. The age rating sits in an outlined box with no dots beside it, and the score follows a star in warn. A dot that
// would start a line falls outside the row and isn't drawn.
@Composable
private fun HeroFactsRow(facts: List<HeroFact>, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    FlowRow(modifier.clipToBounds(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        facts.forEachIndexed { at, fact ->
            Box(Modifier.heightIn(min = 22.dp), contentAlignment = Alignment.CenterStart) {
                when (fact) {
                    is HeroFact.Words -> Text(fact.words, color = scheme.onSurfaceVariant, fontSize = 14.sp, maxLines = 1)
                    is HeroFact.Rating -> Box(Modifier.heightIn(min = 20.dp).border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(4.dp)).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                        Text(fact.rating, color = scheme.onSurfaceVariant, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.02.em, maxLines = 1)
                    }
                    is HeroFact.Score -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Icon(WebIcons.Star, null, tint = extra.warn, modifier = Modifier.size(14.dp))
                        Text(fact.score, color = scheme.onSurfaceVariant, fontSize = 14.sp)
                    }
                }
                if (HeroLook.dotted(facts, at)) Text("·", color = extra.hint, fontSize = 14.sp, modifier = Modifier.offset(x = (-10).dp).clearAndSetSemantics { })
            }
        }
    }
}

// The main button for anything, worded for what it is and going where the website's goes (web/src/openItem.tsx): a
// book's or a note's icon, or Play.
@Composable
private fun MainButton(nav: Nav, item: Item) {
    val icon = when (item.kind) { "book" -> WebIcons.Book; "audio" -> WebIcons.Audio; else -> WebIcons.Play }
    WebButton(OpenLook.label(item), { nav.openMain(item) }, WebButtonKind.Primary, icon)
}

private fun Nav.openMain(item: Item) {
    when (val action = OpenLook.action(item)) {
        OpenAction.Play -> push(Route.Player(item.id, false))
        OpenAction.Listen -> playTrack(item)
        OpenAction.Page -> push(Route.Item(item.id))
        is OpenAction.Server -> push(Route.Page(action.path))
    }
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

// MARK: the libraries

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

// A library's tile: 10 inside, panel colour, a hairline, radius 14: the 38 icon square in the accent at 14%, then the
// name 14 semibold over the count 12 in textHint. Add a library is dashed, on nothing, its icon on the card colour.
@Composable
private fun LibraryTile(name: String, sub: String, icon: ImageVector, add: Boolean, modifier: Modifier, open: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
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

// Your libraries: two across, 8 apart, then Add a library for administrators. Manage opens the libraries' settings.
@Composable
private fun LibraryTiles(nav: Nav, libraries: List<Library>, admin: Boolean, preview: Boolean) {
    if (libraries.isEmpty()) return
    Column(Modifier.padding(bottom = if (preview) 0.dp else 28.dp)) {
        if (!preview) HubHead("Your libraries", if (admin) "Manage" else null) { nav.push(Route.Page("/settings/libraries", "Libraries")) }
        val rows = (libraries.map<Library, Library?> { it } + if (admin) listOf(null) else emptyList()).chunked(2)
        Column(Modifier.padding(horizontal = if (preview) 0.dp else 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            rows.forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    pair.forEach { l ->
                        if (l != null) LibraryTile(l.name, countWords(l), WebIcons.forLibrary(l.type), false, Modifier.weight(1f)) { nav.open(l) }
                        else LibraryTile("Add a library", "Another folder of media", WebIcons.Plus, true, Modifier.weight(1f)) { nav.push(Route.Page("/settings/libraries", "Libraries")) }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

// MARK: rows

// One of Home's rows, its cards as the website draws them: wide for pictures and creator videos. See all opens the
// library; a saved view's keeps its choices, on the server's library page, which reads them from its address.
@Composable
private fun HubSection(nav: Nav, hub: Hub, libraries: List<Library>, preview: Boolean) {
    val library = libraries.firstOrNull { it.id == hub.libraryId }
    val wide = library?.type in WIDE_LIBRARIES
    Column(Modifier.padding(bottom = if (preview) 0.dp else 28.dp)) {
        if (!preview) HubHead(hub.title, if (hub.libraryId != null) "See all" else null) { nav.seeAll(hub, library) }
        HubRow(if (preview) 0.dp else 16.dp) { itemCards(nav, albumsOnce(hub.items.distinctBy { it.id }), hub.shows.distinctBy { it.id }, wide) }
    }
}

private fun Nav.seeAll(hub: Hub, library: Library?) {
    val id = hub.libraryId ?: return
    when {
        hub.query.isNotEmpty() -> push(Route.Page("/library/$id?${hub.query}", library?.name.orEmpty()))
        library != null -> open(library)
        else -> push(Route.Page("/library/$id"))
    }
}

// On TV now (pages/tv/OnNowRow.tsx): favourites first; Guide opens the TV guide.
@Composable
private fun OnNowRow(nav: Nav, channels: List<GuideChannel>, preview: Boolean) {
    Column(Modifier.padding(bottom = if (preview) 0.dp else 28.dp)) {
        if (!preview) HubHead("On TV now", "Guide") { nav.push(Route.Page(GUIDE_PATH)) }
        HubRow(if (preview) 0.dp else 16.dp) { items(channels, key = { it.key }) { OnNowCard(nav, it) } }
    }
}

// A channel: 230 wide, the picture 16:9 radius 10 on the card colour with the channel's number on a plate and a
// 4-high bar of how far in along the bottom, then what's on in 14 semibold and the channel with the time left in 13.
@Composable
private fun OnNowCard(nav: Nav, channel: GuideChannel) {
    val scheme = MaterialTheme.colorScheme
    val now = System.currentTimeMillis() / 1000.0
    val on = OnNowLook.programme(channel, now)
    Pressable({ nav.push(Route.Page("/tv/watch/${channel.key}")) }, Modifier.width(230.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = OnNowLook.spoken(channel, now), ring = false) {
        Column(Modifier.width(230.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)) {
                on?.itemId?.let { id -> WebArt("${nav.app.api.base}/api/items/$id/backdrop", "", 230.dp, 16f / 9f, Modifier.fillMaxSize(), placeholderless = true) }
                Text(channel.number, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(6.dp).clip(RoundedCornerShape(6.dp)).background(Color(0xAD000000)).padding(horizontal = 7.dp, vertical = 1.dp))
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color(0xAD000000))) {
                    Box(Modifier.fillMaxWidth(OnNowLook.fraction(channel, now)).height(4.dp).background(scheme.primary))
                }
            }
            Text(OnNowLook.title(channel, now), color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(OnNowLook.detail(channel, now), color = scheme.onSurfaceVariant, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// Can't decide? (shell.css `.shuffle`): a film or a disc at random on the panel, over its own backdrop at 16%, with
// its poster 90 wide, the title in 20 semibold, its facts, the main button, Details and Another.
@Composable
private fun CantDecide(nav: Nav, it: Item, another: () -> Unit, preview: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.padding(bottom = if (preview) 0.dp else 28.dp)) {
        if (!preview) HubHead("Can’t decide?")
        Box(Modifier.padding(horizontal = if (preview) 0.dp else 16.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(scheme.surface).border(1.dp, scheme.outline, RoundedCornerShape(14.dp))) {
            WebArt(nav.app.api.backdropUrl(it), "", 360.dp, 2f, Modifier.matchParentSize().alpha(0.16f), placeholderless = true)
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Box(Modifier.width(90.dp).aspectRatio(2f / 3f).cssShadow(10.dp, 24.dp, Color(0x80000000), 10.dp).clip(RoundedCornerShape(10.dp))) {
                    WebArt(nav.app.api.posterUrl(it), it.title, 90.dp, 2f / 3f, Modifier.fillMaxSize())
                }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(it.title, color = scheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                    val facts = ShuffleLook.facts(it)
                    if (facts.isNotEmpty()) Text(facts, color = LocalExtraColours.current.hint, fontSize = 15.sp)
                    FlowRow(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        MainButton(nav, it)
                        WebButton("Details", { nav.push(Route.Item(it.id)) }, WebButtonKind.Secondary, WebIcons.Info)
                        WebButton("Another", another, WebButtonKind.Ghost, WebIcons.Refresh)
                    }
                }
            }
        }
    }
}

// Home while it loads: the hero's shapes, the tiles and a row of posters.
@Composable
private fun HomeSkeleton() {
    val page = MaterialTheme.colorScheme.background
    var show by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(250); show = true }
    if (!show) return
    Column(Modifier.fillMaxSize()) {
        val screen = LocalConfiguration.current.screenHeightDp.dp
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
