package com.wittywilla.wittymediaclient.ui

import android.view.KeyEvent
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.SETTINGS_PATH
import com.wittywilla.wittymediaclient.net.Show
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

// The room the floating bar takes at the bottom of a phone's screen, which lists leave clear.
val LocalBottomRoom = compositionLocalOf { 0.dp }
private val PILL_ROOM = 88.dp

// The You tab has no icon: it shows the person's avatar.
private data class Tab(val route: Route, val label: String, val icon: ImageVector?)

private val TABS = listOf(
    Tab(Route.Home, "Home", Icons.Filled.Home),
    Tab(Route.Search, "Search", Icons.Filled.Search),
    Tab(Route.Profile, "", null),
)

@Composable
private fun TabButton(nav: Nav, tab: Tab, modifier: Modifier = Modifier, wide: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val active = nav.current == tab.route
    val ink = if (active) scheme.onPrimary else scheme.onSurface
    // You's name comes from the shared wording.
    val name = tab.label.ifEmpty { LocalWords.current["youTab"].orEmpty() }
    Pressable(
        { if (!active) nav.reset(tab.route) }, modifier,
        shape = Radius.FULL, fill = if (active) scheme.primary else Color.Transparent,
        label = name, state = if (active) "Selected" else null, selected = active,
        // A remote that has just chosen a tab stays on it, one press from what's below. Home has its
        // own first focus on Play. Elsewhere nothing would have focus, and the next press would land on Home.
        requestFocus = active && tab.route != Route.Home && metrics.tv,
        focusKey = "tab-$name",
    ) {
        // Every tab the same height, the avatar's (28 and 12 above and below), so a chosen icon tab's pill
        // sits in the middle of the bar like You's.
        Row(
            Modifier.height(metrics.u(TAB_HEIGHT)).padding(horizontal = if (wide) metrics.u(20) else metrics.u(16)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(8)),
        ) {
            if (tab.icon != null) {
                Icon(tab.icon, contentDescription = null, tint = ink, modifier = Modifier.size(metrics.u(24)))
            } else {
                // The person's avatar, ringed in the accent's words colour while You is chosen.
                val me = nav.me
                Avatar(
                    if (me == null) "?" else avatarName(me.displayName, me.name), metrics.u(28),
                    if (active) Modifier.ringOutside(CircleShape, scheme.onPrimary, 0.dp, metrics.u(2).coerceAtLeast(1.dp)) else Modifier,
                )
            }
            if (wide) Text(name, color = ink, style = MaterialTheme.typography.label)
        }
    }
}

private const val TAB_HEIGHT = 52

// Pages below the tabs: the website's shell on a phone or tablet; on a TV, as before.
@Composable
fun PageShell(nav: Nav, content: @Composable () -> Unit) {
    if (LocalMetrics.current.tv) content() else PhoneShell(nav, content)
}

// Home, Search and You in a floating pill at the bottom of a phone, within reach of a thumb. A TV has six
// along the top instead, where up from a tab's first row gets to them: see TvTabs.kt.
@Composable
fun Shell(nav: Nav, content: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    if (!metrics.tv) {
        PhoneShell(nav, content)
        return
    }
    // Whose avatar the You tab shows, when the app opened already signed in some other way.
    LaunchedEffect(Unit) {
        if (nav.me == null) nav.me = runCatching { nav.app.api.status().user }.getOrNull()
    }
    Screen {
        if (metrics.tv) {
            // docs/APP-DESIGN.md, "On a TV": six pills along the top, as Apple TV has them (TvTabs.kt).
            TvShell(nav, content)
        } else {
            Box(Modifier.fillMaxSize()) {
            // A phone on its side has its navigation bar and any camera cut-out at the sides. The margins
            // make room for them, and rows of cards still run to the edge of the screen rather than stop short.
            val sides = WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal).asPaddingValues()
            val direction = LocalLayoutDirection.current
            val clear = maxOf(sides.calculateLeftPadding(direction), sides.calculateRightPadding(direction))
            val listening = nav.app.listening.now != null
            CompositionLocalProvider(LocalBottomRoom provides if (listening) PILL_ROOM + MINI_HEIGHT else PILL_ROOM, LocalMetrics provides metrics.copy(gutter = metrics.gutter + clear)) { content() }
            // What scrolls under the clock and the battery fades out, so they can still be read.
            val page = MaterialTheme.colorScheme.background
            Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(Brush.verticalGradient(0f to page.copy(alpha = 0.92f), 1f to page.copy(alpha = 0f))))
            Column(
                Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = Space.S3),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Space.S2),
            ) {
                if (listening) {
                    MiniPlayer(
                        nav,
                        Modifier
                            .padding(horizontal = Space.S3)
                            .clip(Radius.LG)
                            .border(1.dp, MaterialTheme.colorScheme.outline, Radius.LG),
                    )
                }
                Row(
                    Modifier
                        .clip(Radius.FULL)
                        .background(MaterialTheme.colorScheme.surface)
                        .border(1.dp, MaterialTheme.colorScheme.outline, Radius.FULL)
                        .padding(Space.S1)
                        .semantics { role = Role.Tab },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Space.S1),
                ) {
                    TABS.forEach { TabButton(nav, it, wide = nav.current == it.route) }
                }
            }
            }
        }
    }
}

private const val SEARCH_WAIT_MS = 350L
private const val SEARCH_MIN = 2
private const val SEARCH_LIMIT = 40

private sealed interface Found {
    data class AnItem(val item: Item) : Found
    data class AShow(val show: Show) : Found
}

@Composable
fun SearchScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    var text by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Found>?>(null) }
    var problem by remember { mutableStateOf("") }
    LaunchedEffect(text) {
        val wanted = text.trim()
        problem = ""
        if (wanted.length < SEARCH_MIN) { results = null; return@LaunchedEffect }
        delay(SEARCH_WAIT_MS)
        try {
            val shows = nav.app.api.searchShows(wanted, SEARCH_LIMIT).shows.map { Found.AShow(it) }
            val items = nav.app.api.searchItems(wanted, SEARCH_LIMIT).items.map { Found.AnItem(it) }
            results = shows + items
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) problem = problemWords(e, s["errLost"].orEmpty())
        }
    }
    Column(
        Modifier.fillMaxSize().statusBarsPadding().imePadding().padding(horizontal = metrics.gutter).padding(top = Space.S4),
        verticalArrangement = Arrangement.spacedBy(Space.S3),
    ) {
        Heading("Search")
        OutlinedTextField(
            value = text, onValueChange = { text = it }, label = { Text("Titles, shows and songs") }, singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrectEnabled = false),
            modifier = Modifier.fillMaxWidth().tvLeavable(),
        )
        ErrorText(problem)
        val list = results
        if (list != null && list.isEmpty()) Secondary("Nothing found for that.", Modifier.semantics { contentDescription = "Nothing found" })
        if (!list.isNullOrEmpty()) {
            LazyVerticalGrid(
                posterColumns(),
                contentPadding = PaddingValues(bottom = LocalBottomRoom.current + Space.S4),
                horizontalArrangement = Arrangement.spacedBy(Space.S2),
                verticalArrangement = Arrangement.spacedBy(Space.S3),
            ) {
                items(list, key = { if (it is Found.AShow) "s${it.show.id}" else "i${(it as Found.AnItem).item.id}" }) { found ->
                    when (found) {
                        is Found.AShow -> ShowCard(nav, found.show)
                        is Found.AnItem -> ItemCard(nav, found.item)
                    }
                }
            }
        }
    }
}

// Up and down scroll the words while there are more that way. Up from the top leaves, for Back.
private fun textScrollKey(key: Int, scroll: ScrollState, stepPx: Float, scope: CoroutineScope, reduce: Boolean): Boolean {
    val by = when {
        key == KeyEvent.KEYCODE_DPAD_DOWN -> stepPx
        key == KeyEvent.KEYCODE_DPAD_UP && scroll.canScrollBackward -> -stepPx
        else -> return false
    }
    scope.launch { if (reduce) scroll.scrollBy(by) else scroll.animateScrollBy(by) }
    return true
}

@Composable
private fun TextPage(nav: Nav, title: String, body: String) {
    val metrics = LocalMetrics.current
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val keyboardMode = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val stepPx = with(LocalDensity.current) { TEXT_STEP.toPx() }
    val reduce = LocalReduceMotion.current
    Screen {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = metrics.gutter, vertical = Space.S4),
            verticalArrangement = Arrangement.spacedBy(Space.S3),
        ) {
            Heading(title)
            ActionButton("Back", nav::back, requestFocus = true)
            // It takes focus so that a remote can get to it and scroll it.
            Box(
                Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .onPreviewKeyEvent { it.type == KeyEventType.KeyDown && textScrollKey(it.key.nativeKeyCode, scroll, stepPx, scope, reduce) }
                    .focusable(interactionSource = interaction)
                    .border(metrics.focusRing, if (focused && keyboardMode) MaterialTheme.colorScheme.onBackground else Color.Transparent, Radius.MD)
                    .padding(metrics.focusRing)
                    .verticalScroll(scroll)
                    .padding(Space.S2),
            ) {
                Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
fun NoticesScreen(nav: Nav) {
    val context = LocalContext.current
    val text = remember { runCatching { Assets.notice(context) }.getOrDefault("") }
    TextPage(nav, "Licences", text)
}

private const val LOG_LINES = 200
private val TEXT_STEP = 160.dp

// What the app has written about itself on this device. It is cleaned as it's written, and nothing
// leaves the device from here.
@Composable
fun LogsScreen(nav: Nav) {
    val context = LocalContext.current
    val text = remember {
        runCatching { File(context.filesDir, "logs/client.log").readLines().takeLast(LOG_LINES).joinToString("\n") }.getOrDefault("").ifEmpty { "Nothing has been logged yet." }
    }
    TextPage(nav, "This app's log", text)
}
