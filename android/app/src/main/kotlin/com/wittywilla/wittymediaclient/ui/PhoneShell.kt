package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.GUIDE_PATH

// docs/APP-DESIGN.md, "The shell", as the server's website draws it at phone width (web/src/shell/, shell.css):
// a 52-high bar at the top with the library strip (or Back below the top pages), the floating bar of five at the
// bottom, the Menu drawer, and the mini players docked above the bar.

// One place in the menus: a library, Collections, Game PCs or an add-on's page.
data class MenuEntry(val key: String, val label: String, val icon: ImageVector, val route: Route)

// Whether the page has scrolled under the top bar, which then gains its surface. Pages with a picture at the top
// say so too: the bar sits over the picture with a soft shade instead.
class ShellScroll {
    var under by mutableStateOf(false)
    var hero by mutableStateOf(false)
}

val LocalShellScroll = compositionLocalOf { ShellScroll() }

// Room a page leaves at its top for the bar (status bar + 52 + 8), and at its bottom for the floating bar and docks.
val LocalTopRoom = compositionLocalOf { 0.dp }

// What a page has open over everything, its sheets: drawn after the bars, as the website's sit above its floating bar.
class OverShell {
    val sheets = mutableStateListOf<@Composable () -> Unit>()
}

val LocalOverShell = compositionLocalOf<OverShell?> { null }

private const val TOP_BAR = 52
private const val TAB_BAR = 60
private const val DOCK_SPACE = 88

@Composable
fun TracksScroll(state: ScrollState) {
    val shell = LocalShellScroll.current
    val under by remember(state) { derivedStateOf { state.value > 2 } }
    LaunchedEffect(under) { shell.under = under }
}

@Composable
fun TracksScroll(state: LazyListState) {
    val shell = LocalShellScroll.current
    val under by remember(state) { derivedStateOf { state.firstVisibleItemIndex > 0 || state.firstVisibleItemScrollOffset > 2 } }
    LaunchedEffect(under) { shell.under = under }
}

@Composable
fun TracksScroll(state: LazyGridState) {
    val shell = LocalShellScroll.current
    val under by remember(state) { derivedStateOf { state.firstVisibleItemIndex > 0 || state.firstVisibleItemScrollOffset > 2 } }
    LaunchedEffect(under) { shell.under = under }
}

// The page has a picture under the top bar, or, on Home, has one no longer.
@Composable
fun HeroPage(on: Boolean = true) {
    val shell = LocalShellScroll.current
    LaunchedEffect(on) { shell.hero = on }
}

// The website's top pages (TopBar.tsx): Home, the TV guide, Search, You, Settings and every place in the strip.
private fun isTopPage(route: Route, menu: List<MenuEntry>): Boolean =
    route == Route.Home || route == Route.Search || route == Route.Profile || menu.any { it.route.key == route.key } ||
        // A library in the strip stays a top page with its choices set (/library/{id}?genre=…), as the website's path does.
        (route is Route.Library && menu.any { (it.route as? Route.Library)?.library?.id == route.library.id }) ||
        (route as? Route.Page)?.path?.substringBefore('?')?.let { it == GUIDE_PATH || it == "/settings" } == true

@Composable
fun PhoneShell(nav: Nav, content: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val density = LocalDensity.current
    val status = with(density) { WindowInsets.statusBars.getTop(this).toDp() }
    val inset = with(density) { WindowInsets.navigationBars.getBottom(this).toDp() }
    val scroll = remember(nav.current.key) { ShellScroll() }
    val over = remember { OverShell() }
    var drawer by remember { mutableStateOf(false) }
    LaunchedEffect(nav.app.api.token) { nav.loadMenu() }
    LaunchedEffect(Unit) { if (nav.me == null) nav.me = runCatching { nav.app.api.status().user }.getOrNull() }
    // The drawer closes on any change of page.
    LaunchedEffect(nav.current.key) { drawer = false }
    BackHandler(drawer) { drawer = false }

    val video = nav.video?.takeIf { nav.current !is Route.Player }
    val listening = nav.app.listening.now != null
    val docked = video != null || listening
    // .content's bottom padding: 24 + the bar's space (60 + 16 + inset) + 88 while something is docked.
    val bottomRoom = 24.dp + TAB_BAR.dp + 16.dp + inset + if (docked) DOCK_SPACE.dp else 0.dp
    val topRoom = status + TOP_BAR.dp + 8.dp
    val top = isTopPage(nav.current, nav.menu)

    Box(Modifier.fillMaxSize().background(scheme.background)) {
        CompositionLocalProvider(LocalShellScroll provides scroll, LocalBottomRoom provides bottomRoom, LocalTopRoom provides topRoom, LocalOverShell provides over) {
            content()
        }
        TopBar(nav, scroll, status, top)

        // Docked above the floating bar, 16 above it.
        val aboveBar = 8.dp + inset + TAB_BAR.dp + 16.dp
        if (video != null) VideoDock(nav, video, aboveBar)
        else if (listening) PhoneMiniBar(nav, Modifier.align(Alignment.BottomCenter).padding(start = 8.dp, end = 8.dp, bottom = aboveBar))

        TabBar(nav, inset, Modifier.align(Alignment.BottomCenter)) { drawer = true }
        Drawer(nav, drawer, status) { drawer = false }
        over.sheets.forEach { sheet -> key(sheet) { sheet() } }
    }
}

// The top bar: status bar, then 52 high, 4 above and below, 16 at the sides, 8 apart. Transparent; once the page
// scrolls under it, the page colour at 85% with a hairline. Over a picture, a shade from the page colour instead.
@Composable
private fun TopBar(nav: Nav, scroll: ShellScroll, status: Dp, top: Boolean) {
    val page = MaterialTheme.colorScheme.background
    val border = MaterialTheme.colorScheme.outline
    val surface by animateFloatAsState(if (scroll.under) 1f else 0f, tween(150, easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)), label = "under")
    val shade by animateFloatAsState(if (scroll.hero && !scroll.under) 1f else 0f, tween(150, easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)), label = "shade")
    Box(Modifier.fillMaxWidth()) {
        // The shade over a picture: 80% at the top, 70% at 26, nothing 32 under the bar.
        if (shade > 0f) Box(
            Modifier.fillMaxWidth().height(status + (TOP_BAR + 32).dp).graphicsLayer { alpha = shade }
                .background(Brush.verticalGradient(0f to page.copy(alpha = 0.8f), 0.31f to page.copy(alpha = 0.7f), 1f to page.copy(alpha = 0f))),
        )
        // Under the clock the page colour is solid, as a browser's own bar is above the website; the strip itself is
        // the page colour at 85%, as the website's (which also blurs what's behind it).
        if (surface > 0f) Column(Modifier.fillMaxWidth().graphicsLayer { alpha = surface }) {
            Box(Modifier.fillMaxWidth().height(status).background(page))
            Box(
                Modifier.fillMaxWidth().height(TOP_BAR.dp).background(page.copy(alpha = 0.85f))
                    .drawWithContent { drawContent(); drawRect(border, Offset(0f, size.height), Size(size.width, 1.dp.toPx())) },
            )
        }
        Row(
            Modifier.padding(top = status).fillMaxWidth().height(TOP_BAR.dp).padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (top) LibraryStrip(nav, Modifier.weight(1f), overPicture = scroll.hero && !scroll.under)
            else {
                Spacer(Modifier.width(8.dp))
                // Back as the system's: a server page goes back inside itself first, as the website's history does.
                val dispatcher = androidx.activity.compose.LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher
                RoundBack { dispatcher?.onBackPressed() ?: nav.back() }
            }
        }
    }
}

// Back: a 40 circle of the page colour at 70%, the chevron at 24; pressed, .975.
@Composable
fun RoundBack(onClick: () -> Unit) {
    val page = MaterialTheme.colorScheme.background
    Pressable(onClick, Modifier.size(44.dp), shape = CircleShape, fill = Color.Transparent, label = LocalWords.current["back"] ?: "Back", pressScale = 0.975f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Box(Modifier.size(40.dp).clip(CircleShape).background(page.copy(alpha = 0.7f)), contentAlignment = Alignment.Center) {
                Icon(WebIcons.Left, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground, modifier = Modifier.size(24.dp))
            }
        }
    }
}

// The libraries along the top: 15 bold, 20 apart, 44 high, starting 16 in; the current one in text colour with a
// 2-high underline in accentText. The last 20 fade out. Scrolls sideways; the current one is brought to the middle.
@Composable
private fun LibraryStrip(nav: Nav, modifier: Modifier, overPicture: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val accentText = LocalExtraColours.current.accentText
    val state = rememberScrollState()
    val current = nav.current.key
    // A library opened with something chosen (?genre=, ?tab=) is still that library's place in the strip.
    val currentLibrary = (nav.current as? Route.Library)?.library?.id
    var target by remember(current) { mutableStateOf<Pair<Int, Int>?>(null) }
    val viewWidth = remember { mutableStateOf(0) }
    LaunchedEffect(target, viewWidth.value) {
        val (x, w) = target ?: return@LaunchedEffect
        state.scrollTo((x - (viewWidth.value - w) / 2).coerceAtLeast(0))
    }
    Row(
        modifier
            .fillMaxHeight()
            .onGloballyPositioned { viewWidth.value = it.size.width }
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                val fade = 20.dp.toPx()
                drawRect(
                    Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), startX = size.width - fade, endX = size.width),
                    Offset(size.width - fade, 0f), Size(fade, size.height), blendMode = BlendMode.DstIn,
                )
            }
            .horizontalScroll(state)
            .padding(start = 16.dp, end = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        nav.menu.forEach { entry ->
            val on = entry.route.key == current || (currentLibrary != null && (entry.route as? Route.Library)?.library?.id == currentLibrary)
            Box(
                Modifier
                    .heightIn(min = 44.dp)
                    .fillMaxHeight()
                    .onGloballyPositioned { if (on) target = it.positionInParent().x.toInt() to it.size.width }
                    .clickable(remember { MutableInteractionSource() }, null) { if (entry.route.key != current) nav.openMenu(entry) }
                    .semantics { role = Role.Tab }
                    .drawWithContent {
                        drawContent()
                        if (on) drawRect(accentText, Offset(0f, size.height - 2.dp.toPx()), Size(size.width, 2.dp.toPx()))
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    entry.label, color = if (on) scheme.onBackground else scheme.onSurfaceVariant, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                    style = if (overPicture) MaterialTheme.typography.body.copy(shadow = androidx.compose.ui.graphics.Shadow(scheme.background.copy(alpha = 0.5f), Offset(0f, 1f), 0f)) else MaterialTheme.typography.body,
                )
            }
        }
    }
}

// The floating bar: 8 above the bottom inset, 16 from the sides (416 at most), 60 high, 4 inside, card fill, a 1-wide
// outline at text 20%, the 0 10 30 shadow. Five equal buttons 50 high: Home, TV guide, Search, Menu, You. The chosen
// one is a pill of the accent at 14% with its icon in accentText; the others textSecondary.
@Composable
private fun TabBar(nav: Nav, inset: Dp, modifier: Modifier, openMenu: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val accentText = LocalExtraColours.current.accentText
    val strong = scheme.onBackground.copy(alpha = 0.2f)
    val current = nav.current
    Row(
        modifier
            .padding(start = 16.dp, end = 16.dp, bottom = 8.dp + inset)
            .widthIn(max = 416.dp)
            .fillMaxWidth()
            .height(TAB_BAR.dp)
            .cssShadow(10.dp, 30.dp, Color(0x73000000), 30.dp)
            .clip(RoundedCornerShape(50))
            .background(scheme.surfaceVariant)
            .border(1.dp, strong, RoundedCornerShape(50))
            .padding(4.dp)
            .semantics { role = Role.Tab },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        @Composable
        fun Cell(label: String, chosen: Boolean, onClick: () -> Unit, inner: @Composable (Color) -> Unit) {
            Pressable(
                onClick, Modifier.weight(1f).height(50.dp), shape = RoundedCornerShape(50),
                fill = if (chosen) scheme.primary.copy(alpha = 0.14f) else Color.Transparent,
                label = label, state = if (chosen) "Selected" else null, selected = chosen, pressScale = 1f, ring = false,
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { inner(if (chosen) accentText else scheme.onSurfaceVariant) }
            }
        }
        val onGuide = (current as? Route.Page)?.path?.startsWith(GUIDE_PATH) == true
        Cell("Home", current == Route.Home, { if (current != Route.Home) nav.reset(Route.Home) }) { Icon(WebIcons.Home, null, tint = it, modifier = Modifier.size(24.dp)) }
        Cell("TV guide", onGuide, { if (!onGuide) nav.push(Route.Page(GUIDE_PATH)) }) { Icon(WebIcons.Tv, null, tint = it, modifier = Modifier.size(24.dp)) }
        Cell("Search", current == Route.Search, { if (current != Route.Search) nav.reset(Route.Search) }) { Icon(WebIcons.Search, null, tint = it, modifier = Modifier.size(24.dp)) }
        Cell("Menu", false, openMenu) { Icon(WebIcons.Menu, null, tint = it, modifier = Modifier.size(24.dp)) }
        val me = nav.me
        val name = if (me == null) "" else avatarName(me.displayName, me.name)
        Cell("You, $name", current == Route.Profile, { if (current != Route.Profile) nav.reset(Route.Profile) }) {
            Avatar(name.ifEmpty { "?" }, 32.dp)
        }
    }
}

// The Menu drawer: 240 wide, panel colour, a hairline at its edge, 12 inside. It slides in over 240 ms and is gone at
// once on closing; the scrim of black 60% covers everything else. The lockup, LIBRARIES, a row for each, the version.
@Composable
private fun Drawer(nav: Nav, open: Boolean, status: Dp, close: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    if (!open) return
    val inset = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(true, enter = fadeIn(tween(150))) {
            Box(Modifier.fillMaxSize().background(Color(0x99000000)).clickable(remember { MutableInteractionSource() }, null, onClick = close))
        }
        AnimatedVisibility(true, enter = slideInHorizontally(tween(240, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) { -it }) {
            Column(
                Modifier.width(240.dp).fillMaxHeight().cssShadow(10.dp, 30.dp, Color(0x73000000), 0.dp).background(scheme.surface)
                    .drawWithContent { drawContent(); drawRect(scheme.outline, Offset(size.width - 1.dp.toPx(), 0f), Size(1.dp.toPx(), size.height)) }
                    .verticalScroll(rememberScrollState())
                    .padding(start = 12.dp, end = 12.dp, top = 12.dp + status, bottom = 12.dp + inset),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Row(
                    Modifier.heightIn(min = 40.dp).padding(horizontal = 8.dp).padding(bottom = 12.dp).clickable { close(); nav.reset(Route.Home) },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    ServerMark(28.dp, nav.brandLogo)
                    val words = if (nav.brandName.isNotEmpty()) buildAnnotatedString { append(nav.brandName) } else buildAnnotatedString {
                        append("Witty"); withStyle(SpanStyle(color = extra.accentText)) { append("Media") }; append("Server")
                    }
                    Text(words, color = scheme.onSurface, fontSize = 17.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.012).em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text("LIBRARIES", color = extra.hint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em, modifier = Modifier.padding(start = 12.dp, end = 12.dp, top = 20.dp, bottom = 8.dp))
                if (nav.menu.isEmpty()) Text("No libraries yet", color = extra.hint, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                nav.menu.forEach { entry ->
                    val on = entry.route.key == nav.current.key
                    Pressable({ close(); if (!on) nav.openMenu(entry) }, Modifier.fillMaxWidth().heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent, label = entry.label, selected = on, ring = false) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(entry.icon, null, tint = if (on) extra.accentText else extra.hint, modifier = Modifier.size(18.dp))
                            Text(entry.label, color = if (on) scheme.onSurface else scheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                if (nav.serverVersion.isNotEmpty()) {
                    val (number, stage) = com.wittywilla.wittymediaclient.net.versionParts(nav.serverVersion)
                    Row(Modifier.padding(start = 12.dp, end = 12.dp, top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("WittyMediaServer $number", color = extra.hint, fontSize = 12.sp)
                        if (stage.isNotEmpty()) StagePill(stage)
                    }
                }
            }
        }
    }
}
