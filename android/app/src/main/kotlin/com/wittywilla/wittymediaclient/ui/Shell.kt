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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
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

private data class Tab(val route: Route, val label: String, val icon: ImageVector)

private val TABS = listOf(
    Tab(Route.Home, "Home", Icons.Filled.Home),
    Tab(Route.Search, "Search", Icons.Filled.Search),
    Tab(Route.Profile, "Profile", Icons.Filled.Person),
)

@Composable
private fun TabButton(nav: Nav, tab: Tab, modifier: Modifier = Modifier, wide: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    val active = nav.current == tab.route
    val ink = if (active) scheme.onPrimary else scheme.onSurface
    FocusBox(
        { if (!active) nav.reset(tab.route) }, modifier,
        label = tab.label, state = if (active) "Selected" else null, selected = active,
        // A remote that has just chosen a tab stays on it, one press from what's below. Home has its
        // own first focus on Play. Elsewhere nothing would have focus, and the next press would land on Home.
        requestFocus = active && tab.route != Route.Home && LocalMetrics.current.tv,
        focusKey = "tab-${tab.label}", filled = if (active) scheme.primary else androidx.compose.ui.graphics.Color.Transparent, shape = Radius.FULL,
    ) {
        Row(
            Modifier.padding(horizontal = if (wide) Space.S5 else Space.S4, vertical = Space.S3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.S2),
        ) {
            Icon(tab.icon, contentDescription = null, tint = ink)
            if (wide) Text(tab.label, color = ink, style = MaterialTheme.typography.labelLarge)
        }
    }
}

// Home, Search and Profile. A phone has them in a floating pill at the bottom, within reach of a
// thumb. A TV has them along the top, where up from the first row gets to them.
@Composable
fun Shell(nav: Nav, content: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    Screen {
        if (metrics.tv) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    Modifier.fillMaxWidth().padding(start = metrics.gutter, end = metrics.gutter, top = metrics.edge, bottom = Space.S2).remoteRow(),
                    horizontalArrangement = Arrangement.spacedBy(Space.S3),
                ) {
                    TABS.forEach { TabButton(nav, it, wide = true) }
                }
                Box(Modifier.weight(1f)) { content() }
            }
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

// Who's signed in and to what, and the ways out of that. Everything here works with a remote.
@Composable
fun ProfileScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val context = LocalContext.current
    val server = nav.server
    var who by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { who = runCatching { nav.app.api.status().user?.name.orEmpty() }.getOrDefault("") }
    val version = remember { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty() }
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(horizontal = metrics.gutter, vertical = Space.S4)
            .padding(bottom = LocalBottomRoom.current),
        verticalArrangement = Arrangement.spacedBy(Space.S3),
    ) {
        Heading("Profile")
        ErrorText(nav.notice)
        if (who.isNotEmpty()) Secondary("Signed in as $who")
        if (server != null) {
            SectionTitle(server.name)
            Secondary(server.url)
            if (server.fingerprint.isNotEmpty()) Secondary("${s["fingerprintLabel"]}: ${server.fingerprint}")
        }
        ActionButton("Server settings", { nav.push(Route.Page(SETTINGS_PATH)) }, Modifier.fillMaxWidth(), focusKey = "settings")
        ActionButton("Sign out", nav::signOut, Modifier.fillMaxWidth(), focusKey = "switch")
        ActionButton(s["changeServer"].orEmpty(), nav::changeServer, Modifier.fillMaxWidth(), focusKey = "server")
        SectionTitle("About this app")
        Secondary("WittyMediaClient $version")
        ActionButton("Licences", { nav.push(Route.Notices) }, Modifier.fillMaxWidth(), focusKey = "notices")
        ActionButton("This app's log", { nav.push(Route.Logs) }, Modifier.fillMaxWidth(), focusKey = "logs")
        Secondary(s["legalConnect"].orEmpty())
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
