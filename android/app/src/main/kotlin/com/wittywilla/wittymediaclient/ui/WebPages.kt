package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.Collection
import com.wittywilla.wittymediaclient.net.CollectionItems
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.ItemFacts
import com.wittywilla.wittymediaclient.net.BrandLogoAnswer
import com.wittywilla.wittymediaclient.net.ShowDetail
import com.wittywilla.wittymediaclient.net.ShowFacts
import com.wittywilla.wittymediaclient.net.TitleAttached
import com.wittywilla.wittymediaclient.net.TitleListings
import com.wittywilla.wittymediaclient.net.TitleTarget
import com.wittywilla.wittymediaclient.net.isRigGame
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

// The website's item, show and search pages on a phone (web/src/pages/ItemPage.tsx, ShowPage.tsx, SearchPage.tsx).

// One row in a sheet: 52 high, 16 inside, a 20 icon in textSecondary, the words 15 medium. One that can't be chosen
// now fades to 45%.
data class SheetRow(val words: String, val icon: ImageVector?, val danger: Boolean = false, val enabled: Boolean = true, val run: () -> Unit)

// The website's sheet on a phone: from the foot, panel colour, radius 20 at the top, the title 20 and a 44 close
// button; the "⋯" and Filters sheets slide in 24 from the right as they do there. In the phone's shell it's drawn
// over the shell's bars as well, as the website's sheets are above its floating bar.
@Composable
fun WebSheet(title: String, close: () -> Unit, fromRight: Boolean = true, footer: (@Composable () -> Unit)? = null, content: @Composable () -> Unit) {
    val host = LocalOverShell.current
    if (host == null) {
        SheetPanel(title, close, fromRight, footer, content)
        return
    }
    val panel = rememberUpdatedState<@Composable () -> Unit> { SheetPanel(title, close, fromRight, footer, content) }
    DisposableEffect(host) {
        val shown: @Composable () -> Unit = { panel.value() }
        host.sheets += shown
        onDispose { host.sheets -= shown }
    }
}

@Composable
private fun SheetPanel(title: String, close: () -> Unit, fromRight: Boolean, footer: (@Composable () -> Unit)?, content: @Composable () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val inset = with(LocalDensity.current) { WindowInsets.navigationBars.getBottom(this).toDp() }
    BackHandler { close() }
    val density = LocalDensity.current
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(true, enter = fadeIn(tween(150))) {
            Box(Modifier.fillMaxSize().background(Color(0x99000000)).clickable(remember { MutableInteractionSource() }, null, onClick = close))
        }
        AnimatedVisibility(
            true, Modifier.align(Alignment.BottomCenter),
            enter = fadeIn(tween(240)) + if (fromRight) slideInHorizontally(tween(240, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) { with(density) { 24.dp.roundToPx() } }
            else slideInVertically(tween(240, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f))) { with(density) { 24.dp.roundToPx() } },
        ) {
            Column(
                Modifier.fillMaxWidth().heightIn(max = (LocalConfiguration.current.screenHeightDp * 0.92f).dp)
                    .cssShadow(10.dp, 30.dp, Color(0x73000000), 20.dp)
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)).background(scheme.surface)
                    .clickable(remember { MutableInteractionSource() }, null) {}
                    .padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 20.dp + inset),
            ) {
                Row(Modifier.padding(bottom = 16.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(title, color = scheme.onSurface, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 23.sp, modifier = Modifier.weight(1f).padding(top = 10.dp))
                    Pressable(close, Modifier.size(44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "Close", ring = false) {
                        Box(Modifier.fillMaxSize().border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                            Icon(WebIcons.Close, null, tint = scheme.onSurface, modifier = Modifier.size(16.dp))
                        }
                    }
                }
                Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) { content() }
                if (footer != null) Row(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalArrangement = Arrangement.End) { footer() }
            }
        }
    }
}

@Composable
fun SheetRows(rows: List<SheetRow>, close: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(scheme.surfaceVariant)) {
        rows.forEachIndexed { i, row ->
            Pressable(
                { close(); row.run() }, Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = RoundedCornerShape(0.dp), fill = Color.Transparent, label = row.words,
                enabled = row.enabled, disabledAlpha = 0.45f, ring = false,
            ) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).drawWithContent {
                        drawContent()
                        // A hairline over each row but the first, from where the words start to the edge.
                        if (i > 0) drawRect(scheme.outline, Offset(48.dp.toPx(), 0f), Size(size.width - 48.dp.toPx(), 1.dp.toPx()))
                    }.padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(Modifier.width(20.dp)) { if (row.icon != null) Icon(row.icon, null, tint = if (row.danger) scheme.error else scheme.onSurfaceVariant, modifier = Modifier.size(20.dp)) }
                    Text(row.words, color = if (row.danger) scheme.error else scheme.onSurface, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

// Save to: Watch later, then this person's own collections to tick, and a new one.
@Composable
private fun SaveDialog(nav: Nav, item: Long, show: Long, close: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf<List<Collection>?>(null) }
    var holding by remember { mutableStateOf(emptyList<Long>()) }
    var name by remember { mutableStateOf("") }
    var round by remember { mutableIntStateOf(0) }
    val body = CollectionItems(if (item > 0) listOf(item) else emptyList(), if (show > 0) listOf(show) else emptyList())
    val me = nav.me
    LaunchedEffect(round) {
        list = runCatching { nav.app.api.collections().filter { it.kind != "smart" && it.ownerId == me?.id } }.getOrDefault(emptyList())
        holding = runCatching { nav.app.api.holding(item, show) }.getOrDefault(holding)
    }
    WebSheet("Save to", close, fromRight = false, footer = { WebButton("Done", close, WebButtonKind.Primary) }) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (list?.none { it.system == "watchlater" } == true) WebButton("Watch later", {
                scope.launch { runCatching { holding = holding + nav.app.api.watchLater(body).collectionId; round++ } }
            }, WebButtonKind.Ghost)
        }
        list?.forEach { c ->
            val on = c.id in holding
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable {
                scope.launch {
                    runCatching {
                        if (on) { nav.app.api.removeFromCollection(c.id, body); holding = holding - c.id } else { nav.app.api.addToCollection(c.id, body); holding = holding + c.id }
                    }
                }
            }, verticalAlignment = Alignment.CenterVertically) {
                Checkbox(on, null, colors = CheckboxDefaults.colors(checkedColor = scheme.primary))
                Text(c.name, color = scheme.onSurface, fontSize = 15.sp)
            }
        }
        if (me != null && me.kind != "kids" && me.kind != "guest") {
            Row(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                WebInput(name, { name = it.take(200) }, "New collection", Modifier.weight(1f))
                WebButton("Add", {
                    if (name.isNotBlank()) scope.launch { runCatching { val c = nav.app.api.newCollection(name.trim()); nav.app.api.addToCollection(c.id, body); name = ""; round++ } }
                })
            }
        }
    }
}

// The website's text box: 44 high, card colour, the control colour's outline, radius 10, 14 words.
@Composable
fun WebInput(value: String, change: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, icon: ImageVector? = null, focus: FocusRequester? = null, submit: () -> Unit = {}) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    var focused by remember { mutableStateOf(false) }
    val line = if (focused) extra.accentText else extra.control
    Box(
        modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)
            .border(if (focused) 2.dp else 1.dp, line, RoundedCornerShape(10.dp)),
        contentAlignment = Alignment.CenterStart,
    ) {
        if (icon != null) Icon(icon, null, tint = extra.hint, modifier = Modifier.padding(start = 12.dp).size(20.dp))
        Box(Modifier.padding(start = if (icon != null) 40.dp else 12.dp, end = 16.dp).fillMaxWidth()) {
            if (value.isEmpty()) Text(placeholder, color = extra.hint, fontSize = 14.sp)
            BasicTextField(
                value, change, singleLine = true, textStyle = TextStyle(color = scheme.onSurface, fontSize = 14.sp), cursorBrush = SolidColor(scheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { submit() }, onDone = { submit() }),
                modifier = Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused }.then(if (focus != null) Modifier.focusRequester(focus) else Modifier),
            )
        }
    }
}

@Composable
private fun MoreButton(onClick: () -> Unit) {
    Pressable(onClick, Modifier.size(44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "More", pressScale = 0.975f, ring = false) {
        Box(Modifier.fillMaxSize().border(1.dp, MaterialTheme.colorScheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            Icon(WebIcons.More, null, tint = MaterialTheme.colorScheme.onBackground, modifier = Modifier.size(18.dp))
        }
    }
}

// The picture across the top: 38% of the height (240 to 560), a quarter of the way down the picture, fading out from
// 40% down under a shade of the page. Only the shade where there's no picture.
@Composable
private fun DetailHero(url: String?) {
    HeroPage()
    val page = MaterialTheme.colorScheme.background
    Box(Modifier.fillMaxWidth().height(detailHeight(LocalConfiguration.current.screenHeightDp))) {
        if (url != null) WebArt(
            url, "", 400.dp, 1.3f,
            Modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
                drawContent()
                drawRect(Brush.verticalGradient(0.4f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
            },
            placeholderless = true, alignment = BiasAlignment(0f, -0.5f),
        )
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to page.copy(alpha = 0.15f), 0.35f to page.copy(alpha = 0.35f), 0.7f to page.copy(alpha = 0.7f), 1f to page)))
    }
}

private fun detailHeight(screenDp: Int): Dp = TitleLook.heroHeight(screenDp.toDouble()).dp

// The column under the picture: the page's 16 at the sides, no wider than 720.
private fun columnWidth(screenDp: Int): Dp = minOf(screenDp - 32, 720).dp

// Under the poster (`.crumbs`): the library, or the show, its season and the episode's number, 13 semibold in
// textSecondary with 14 chevrons in textHint, 6 apart.
@Composable
private fun Crumbs(nav: Nav, crumbs: List<TitleLook.Crumb>) {
    val scheme = MaterialTheme.colorScheme
    FlowRow(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(2.dp), itemVerticalAlignment = Alignment.CenterVertically) {
        crumbs.forEachIndexed { i, crumb ->
            if (i > 0) Icon(WebIcons.Right, null, tint = LocalExtraColours.current.hint, modifier = Modifier.size(14.dp))
            val go: (() -> Unit)? = when (val goes = crumb.goes) {
                is TitleLook.Goes.Library -> { { nav.openLibraryPage(goes.id) } }
                is TitleLook.Goes.Show -> { { nav.push(Route.Show(goes.id, goes.season)) } }
                TitleLook.Goes.Nowhere -> null
            }
            Text(crumb.words, color = scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = if (go != null) Modifier.clickable(onClick = go) else Modifier)
        }
    }
}

// The facts under the title: when it aired or its year, its length, its rating box, the star, and four genres that
// each open the library with that one chosen.
@Composable
private fun ItemMeta(nav: Nav, item: Item, facts: ItemFacts, modifier: Modifier) {
    val first = item.aired.ifEmpty { null } ?: item.year?.takeIf { y -> y != 0 }?.toString()
    val runtime = TitleLook.runtime(item.runtimeSec)
    val rated = item.contentRating.ifEmpty { null }
    val stars = facts.rating?.takeIf { r -> r > 0 }
    val (genres, more) = TitleLook.genres(item.genres)
    MetaRow(modifier) {
        if (first != null) Dotted(true) { MetaWords(first) }
        if (runtime.isNotEmpty()) Dotted(true) { MetaWords(runtime) }
        if (rated != null) MetaPill(rated)
        // Every fact has its dot but the rating box and the one after it.
        if (stars != null) Dotted(rated == null) { MetaStar(stars) }
        if (genres.isNotEmpty()) Dotted(!(rated != null && stars == null)) {
            val line = buildAnnotatedString {
                genres.forEachIndexed { i, genre ->
                    if (i > 0) append(", ")
                    withLink(LinkAnnotation.Clickable("genre-$i") { nav.openLibraryWith(item.libraryId, "genre", genre, TitleLook.genrePath(item.libraryId, genre)) }) { append(genre) }
                }
                if (more) append("…")
            }
            Text(line, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
        }
    }
}

// The facts table (`.facts`): a hairline, 20, then as many columns of at least 170 as fit, 24 apart and rows 16 apart;
// each key 11 semibold in capitals in textHint over its value 14 medium. The file takes a whole row, in 12 mono.
@Composable
private fun FactsTable(facts: List<TitleLook.Fact>, column: Dp, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val columns = TitleLook.factColumns(column.value.toDouble())
    @Composable
    fun Cell(fact: TitleLook.Fact) {
        Column(Modifier.semantics(mergeDescendants = true) {}) {
            Text(fact.key.uppercase(Locale.ROOT), color = hint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em, modifier = Modifier.padding(bottom = 2.dp))
            if (fact.wide) Text(fact.value, color = scheme.onSurfaceVariant, fontSize = 12.sp, fontFamily = FontFamily.Monospace, lineHeight = 1.5.em)
            else Text(fact.value, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
    }
    Column(
        modifier.fillMaxWidth().drawWithContent { drawContent(); drawRect(scheme.outline, Offset.Zero, Size(size.width, 1.dp.toPx())) }.padding(top = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        facts.filter { !it.wide }.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                row.forEach { Box(Modifier.weight(1f)) { Cell(it) } }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        facts.filter { it.wide }.forEach { Cell(it) }
    }
}

// Which way a page didn't come: gone (removed, or not this profile's), broken (the server's fault), or lost on the
// way, with the app's words for why.
private sealed interface PageProblem {
    val words: String

    data class Gone(override val words: String) : PageProblem
    data class Broken(override val words: String) : PageProblem
    data class Lost(override val words: String) : PageProblem
}

private fun pageProblem(e: Exception, lost: String): PageProblem {
    val words = problemWords(e, lost)
    return when {
        e is ApiError && e.status >= 500 -> PageProblem.Broken(words)
        e is ApiError && e.status >= 400 -> PageProblem.Gone(words)
        else -> PageProblem.Lost(words)
    }
}

// "⋯"'s rows on an item's page, each going where the website's does. The server's own page has an administrator's
// tools: its edit window at Artwork or Match, and Refresh and Disc settings in its "⋯".
private fun itemSheetRow(nav: Nav, item: Item, row: TitleLook.MoreRow, playable: Boolean): SheetRow = when (row) {
    is TitleLook.MoreRow.ResumeDisc -> SheetRow(row.words, WebIcons.Play, enabled = playable) { nav.push(Route.Page(row.path)) }
    is TitleLook.MoreRow.DiscFromStart -> SheetRow(row.words, WebIcons.Play, enabled = playable) { nav.push(Route.Page(row.path)) }
    is TitleLook.MoreRow.MainMenu -> SheetRow(row.words, WebIcons.Menu, enabled = playable) { nav.push(Route.Page(row.path)) }
    TitleLook.MoreRow.DiscSettings -> SheetRow(row.words, WebIcons.Settings) { nav.push(Route.Page(TitleLook.editPath(TitleTarget.Item, item.id))) }
    TitleLook.MoreRow.PlayFromStart -> SheetRow(row.words, WebIcons.Play) { nav.push(Route.Player(item.id, true)) }
    is TitleLook.MoreRow.NextEpisode -> SheetRow(row.words, WebIcons.Next) { nav.push(Route.Item(row.id)) }
    TitleLook.MoreRow.Artwork -> SheetRow(row.words, WebIcons.Image) { nav.push(Route.Page(TitleLook.editPath(TitleTarget.Item, item.id, "artwork"))) }
    TitleLook.MoreRow.Edit -> SheetRow(row.words, WebIcons.Edit) { nav.push(Route.Page(TitleLook.editPath(TitleTarget.Item, item.id, "match"))) }
    TitleLook.MoreRow.Refresh -> SheetRow(row.words, WebIcons.Refresh) { nav.push(Route.Page(TitleLook.editPath(TitleTarget.Item, item.id))) }
}

private fun canSave(nav: Nav) = nav.me?.let { TitleLook.canSave(it.isAdmin, it.kind) } == true

// A problem with something just done, above the buttons: 14 in the danger colour.
@Composable
private fun ProblemLine(words: String) {
    Text(words, color = MaterialTheme.colorScheme.error, fontSize = 14.sp, modifier = Modifier.padding(bottom = 12.dp))
}

// An item's page (ItemPage.tsx at phone size): the picture, the poster, where it belongs, its title or logo, the facts,
// one row of buttons, what it's about and where that came from, the facts table, the extras, and the way back.
@Composable
fun PhoneItem(nav: Nav, s: Map<String, String>, id: Long) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val api = nav.app.api
    var page by remember(id) { mutableStateOf<Pair<Item, ItemFacts>?>(null) }
    var problem by remember(id) { mutableStateOf<PageProblem?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    var attached by remember(id) { mutableStateOf<TitleAttached?>(null) }
    var listings by remember(id) { mutableStateOf<TitleListings?>(null) }
    var logos by remember(id) { mutableStateOf<Map<String, BrandLogoAnswer>>(emptyMap()) }
    var more by remember { mutableStateOf(false) }
    var save by remember { mutableStateOf(false) }
    LaunchedEffect(id, attempt) {
        problem = null
        try { page = api.itemPage(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { if (!nav.handleExpired(e)) problem = pageProblem(e, s["errLost"].orEmpty()) }
    }
    LaunchedEffect(id) {
        coroutineScope {
            val found = async { runCatching { api.attached(TitleTarget.Item, id) }.getOrNull() }
            val listed = async { runCatching { api.listings(TitleTarget.Item, id) }.getOrNull() }
            attached = found.await()
            listings = listed.await()
        }
        logos = lookUpLogos(api, attached?.studios.orEmpty().map { "studio" to it } + listings?.platforms.orEmpty().map { "platform" to it.name })
    }
    val loaded = page
    if (loaded == null) {
        when (val p = problem) {
            null -> ItemSkeleton()
            is PageProblem.Gone -> TitleEmpty(WebIcons.Info, "This title isn’t available", "It may have been removed, or this profile may not be allowed to see it.") {
                WebButton("Back to home", { nav.reset(Route.Home) })
            }
            is PageProblem.Broken -> TitleEmpty(WebIcons.Info, "This title couldn’t be loaded", "The server didn’t answer properly. This is usually brief, and doesn’t mean anything has gone.") {
                WebButton("Try again", { attempt++ })
            }
            is PageProblem.Lost -> TitleEmpty(WebIcons.Info, "This title couldn’t be loaded", p.words) { WebButton("Try again", { attempt++ }) }
        }
        return
    }
    val (it, facts) = loaded
    val admin = nav.me?.isAdmin == true
    val disc = TitleLook.isDisc(it)
    val playable = TitleLook.playable(it, facts)
    val column = columnWidth(LocalConfiguration.current.screenWidthDp)
    val scroll = rememberScrollState()
    TracksScroll(scroll)
    val rows = TitleLook.moreRows(it, facts, admin).map { row -> itemSheetRow(nav, it, row, playable) }
    val credit = TitleLook.credit(facts.provider, facts.providerId)
    val scrambled = disc && facts.disc?.scrambled == true
    val poster = if (facts.poster.isNullOrEmpty()) null else api.posterUrl(it)
    val backdrop = if (facts.poster.isNullOrEmpty() && facts.backdrop.isNullOrEmpty()) null else api.backdropUrl(it)
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(bottom = LocalBottomRoom.current)) {
            DetailHero(backdrop)
            Column(Modifier.pullUp(96.dp).padding(horizontal = 16.dp).widthIn(max = 720.dp)) {
                TitlePoster(poster, if (TitleLook.isFrame(facts.poster)) it.title else null)
                Column(Modifier.padding(top = 20.dp)) {
                    val crumbs = TitleLook.crumbs(it, nav.menu.firstOrNull { e -> e.key == "lib:${it.libraryId}" }?.label)
                    if (crumbs.isNotEmpty()) Crumbs(nav, crumbs)
                    TitleHeading(it.title, if (attached?.hasLogo == true) api.titleLogoUrl(TitleTarget.Item, it.id, it.updatedAt) else null, column)
                    if (it.tagline.isNotEmpty() && !it.isRigGame) Text(it.tagline, color = scheme.onSurfaceVariant, fontSize = 17.sp, fontStyle = FontStyle.Italic, modifier = Modifier.padding(bottom = 8.dp))
                    ItemMeta(nav, it, facts, Modifier.padding(bottom = 20.dp))
                    if (it.isRigGame) Box(Modifier.padding(bottom = 20.dp)) { RigPlayPanel(nav, it) }
                    if (disc) {
                        // A disc: Insert and "⋯", no Save on a phone; what Insert does is said under them.
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                WebButton("Insert ${TitleLook.discName(it)}", { nav.push(Route.Page(TitleLook.insertPath(it, facts))) }, WebButtonKind.Primary, WebIcons.Disc, Modifier.weight(1f), enabled = playable)
                                if (rows.isNotEmpty()) MoreButton { more = true }
                            }
                            Text(TitleLook.discHint(it, facts, admin), color = extra.hint, fontSize = 12.sp)
                        }
                    } else {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (!it.isRigGame) {
                                val resume = (it.progress?.resumeSec ?: 0.0) > 0
                                WebButton(
                                    if (resume) "Resume" else "Play", { nav.play(it) }, WebButtonKind.Primary, WebIcons.Play, Modifier.weight(1f),
                                    spoken = if (resume) "Resume from ${TitleLook.clock(it.progress?.positionSec)}" else null,
                                )
                            }
                            if (canSave(nav)) WebButton("Save", { save = true }, WebButtonKind.Secondary, WebIcons.Plus)
                            if (rows.isNotEmpty()) MoreButton { more = true }
                        }
                    }
                    if (it.overview.isNotEmpty()) Text(it.overview, color = scheme.onBackground, fontSize = 15.sp, lineHeight = 24.sp, modifier = Modifier.padding(top = 24.dp))
                    if (credit != null) FinePrint(credit, Modifier.padding(top = if (it.overview.isEmpty()) 24.dp else 20.dp))
                    if (scrambled) {
                        val danger = scheme.error
                        Text(
                            "This disc is encrypted, so it can't be played: encrypted media isn't supported, and nothing here bypasses copy protection.",
                            color = scheme.onBackground, fontSize = 14.sp, lineHeight = 1.45.em,
                            modifier = Modifier.padding(top = if (credit != null) 0.dp else if (it.overview.isEmpty()) 24.dp else 20.dp).fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp)).background(danger.copy(alpha = 0.11f)).border(1.dp, danger.copy(alpha = 0.5f), RoundedCornerShape(10.dp))
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                        )
                    }
                    FactsTable(TitleLook.facts(it, facts, admin), column, Modifier.padding(top = 24.dp))
                    attached?.let { a -> TitleExtras(nav, TitleTarget.Item, a, listings, it.libraryId, logos, Modifier.padding(top = 16.dp)) }
                    val show = it.showId
                    if (show != null) TitleBackLink("Back to ${it.showTitle.orEmpty()}", Modifier.padding(top = 32.dp)) { nav.push(Route.Show(show, it.season ?: -1)) }
                    else TitleBackLink("Back to library", Modifier.padding(top = 32.dp)) { nav.openLibraryPage(it.libraryId) }
                    LegalLine(nav, "metadata", Modifier.padding(top = 16.dp))
                }
            }
            // The page has its own notice, so the foot is the version alone, as the website hides its general one.
            PageFoot(nav, "")
        }
        if (more) WebSheet(it.title, { more = false }) { SheetRows(rows) { more = false } }
        if (save) SaveDialog(nav, it.id, 0, close = { save = false })
    }
}

// A show's page (ShowPage.tsx at phone size): as an item's, then its seasons as posters, Layout, and the chosen
// season's episodes as cards or a playlist.
@Composable
fun PhoneShow(nav: Nav, s: Map<String, String>, id: Long, asked: Int? = null) {
    val scheme = MaterialTheme.colorScheme
    val api = nav.app.api
    val scope = rememberCoroutineScope()
    var page by remember(id) { mutableStateOf<Pair<ShowDetail, ShowFacts>?>(null) }
    var problem by remember(id) { mutableStateOf<PageProblem?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    var attached by remember(id) { mutableStateOf<TitleAttached?>(null) }
    var listings by remember(id) { mutableStateOf<TitleListings?>(null) }
    var extrasIn by remember(id) { mutableStateOf(false) }
    var logos by remember(id) { mutableStateOf<Map<String, BrandLogoAnswer>>(emptyMap()) }
    var serverView by remember { mutableStateOf<String?>(null) }
    // The layout chosen here, over the show's own; "" goes back to the server's.
    var chosenView by remember(id) { mutableStateOf<String?>(null) }
    var season by remember(id, asked) { mutableStateOf(asked) }
    var said by remember(id) { mutableStateOf("") }
    var more by remember { mutableStateOf(false) }
    var save by remember { mutableStateOf(false) }
    LaunchedEffect(id, attempt) {
        problem = null
        try { page = api.showPage(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { if (!nav.handleExpired(e)) problem = pageProblem(e, s["errLost"].orEmpty()) }
    }
    LaunchedEffect(id) {
        coroutineScope {
            val found = async { runCatching { api.attached(TitleTarget.Show, id) }.getOrNull() }
            val listed = async { runCatching { api.listings(TitleTarget.Show, id) }.getOrNull() }
            val prefs = async { runCatching { api.playerPrefs() }.getOrNull() }
            attached = found.await()
            listings = listed.await()
            serverView = prefs.await()?.episodeView
        }
        extrasIn = true
    }
    val network = page?.second?.network.orEmpty()
    // The network's logo with the studios' and the services', in one question.
    LaunchedEffect(extrasIn, network) {
        if (!extrasIn) return@LaunchedEffect
        logos = lookUpLogos(api, attached?.studios.orEmpty().map { "studio" to it } + listings?.platforms.orEmpty().map { "platform" to it.name } +
            if (network.isEmpty()) emptyList() else listOf("network" to network))
    }
    val loaded = page
    if (loaded == null) {
        when (val p = problem) {
            null -> ItemSkeleton()
            // The website says why in the server's words; a connection that dropped can be tried again.
            else -> TitleEmpty(WebIcons.Info, "This show didn’t load", p.words, if (p is PageProblem.Lost) { { WebButton("Try again", { attempt++ }) } } else null)
        }
        return
    }
    val (detail, facts) = loaded
    val show = detail.show
    val admin = nav.me?.isAdmin == true
    val selected = season ?: TitleLook.openingSeason(detail, null)
    val episodes = TitleLook.episodes(detail, selected)
    val others = TitleLook.otherVideos(detail)
    val own = chosenView ?: facts.view.orEmpty()
    val view = TitleLook.episodeView(null, own, serverView)
    val next = detail.episodes.firstOrNull { e -> e.id == detail.nextUpId }
    val column = columnWidth(LocalConfiguration.current.screenWidthDp)
    val scroll = rememberScrollState()
    TracksScroll(scroll)
    fun setView(chosen: String) {
        chosenView = chosen
        // An administrator's choice is the show's, for everyone.
        if (admin) scope.launch {
            try { api.setShowView(show.id, chosen); said = "" } catch (e: CancellationException) { throw e } catch (e: Exception) { if (!nav.handleExpired(e)) said = problemWords(e, s["errLost"].orEmpty()) }
        }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(bottom = LocalBottomRoom.current)) {
            DetailHero(api.showBackdropUrl(show))
            Column(Modifier.pullUp(96.dp).padding(horizontal = 16.dp).widthIn(max = 720.dp)) {
                TitlePoster(api.showPosterUrl(show))
                Column(Modifier.padding(top = 20.dp)) {
                    TitleHeading(show.title, if (attached?.hasLogo == true) api.titleLogoUrl(TitleTarget.Show, show.id, show.updatedAt) else null, column)
                    ShowMeta(nav, show, facts, logos, Modifier.padding(bottom = 20.dp))
                    if (said.isNotEmpty()) ProblemLine(said)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (next != null) {
                            val label = TitleLook.playLabel(next)
                            WebButton(label.words, { nav.play(next) }, WebButtonKind.Primary, WebIcons.Play, Modifier.weight(1f), spoken = label.spoken)
                        }
                        if (canSave(nav)) WebButton("Save", { save = true }, WebButtonKind.Secondary, WebIcons.Plus)
                        if (admin) MoreButton { more = true }
                    }
                    if (show.overview.isNotEmpty()) Text(show.overview, color = scheme.onBackground, fontSize = 15.sp, lineHeight = 24.sp, modifier = Modifier.padding(top = 24.dp))
                    attached?.let { a -> TitleExtras(nav, TitleTarget.Show, a, listings, facts.libraryId, logos, Modifier.padding(top = if (show.overview.isEmpty()) 24.dp else 20.dp)) }
                    // The seasons, 108 wide, 12 apart, scrolling sideways; then Other videos for the episodes with none.
                    LazyRow(
                        Modifier.padding(top = 24.dp), contentPadding = PaddingValues(start = 2.dp, end = 2.dp, top = 4.dp, bottom = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(detail.seasons.distinctBy { it.number }, key = { it.number }) { se ->
                            SeasonTab(se.title.ifEmpty { if (se.number == 0) "Specials" else "Season ${se.number}" }, TitleLook.seasonLine(se), api.seasonPosterUrl(show, se.number), se.number == selected) { season = se.number }
                        }
                        if (others.isNotEmpty()) item(key = "other") { SeasonTab("Other videos", "${others.size}", null, selected == -1) { season = -1 } }
                    }
                    LayoutSwitch(view, own.isNotEmpty(), Modifier.padding(top = 8.dp, bottom = 12.dp), ::setView)
                    if (view == "list") EpisodeTable(nav, episodes) { ep -> nav.play(ep) }
                    else Column(Modifier.bleed(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) { episodes.forEach { ep -> EpisodeRow(nav, ep) { nav.play(ep) } } }
                    TitleBackLink("Back to library", Modifier.padding(top = 32.dp)) { facts.libraryId?.let { l -> nav.openLibraryPage(l) } ?: nav.back() }
                    TitleLook.credit(facts.provider, facts.providerId, show = true)?.let { FinePrint(it, Modifier.padding(top = 12.dp)) }
                    LegalLine(nav, "metadata", Modifier.padding(top = 16.dp))
                    if (network.isNotEmpty() && logos[BrandLogoAnswer.key("network", network)]?.has == true) LegalLine(nav, "logos", Modifier.padding(top = 16.dp))
                }
            }
            PageFoot(nav, "")
        }
        if (more) WebSheet(show.title, { more = false }) {
            SheetRows(listOf(
                SheetRow("Artwork", WebIcons.Image) { nav.push(Route.Page(TitleLook.editPath(TitleTarget.Show, show.id, "artwork"))) },
                SheetRow("Edit", WebIcons.Edit) { nav.push(Route.Page(TitleLook.editPath(TitleTarget.Show, show.id, "match"))) },
                SheetRow("Refresh", WebIcons.Refresh) { nav.push(Route.Page(TitleLook.editPath(TitleTarget.Show, show.id))) },
            )) { more = false }
        }
        if (save) SaveDialog(nav, 0, show.id, close = { save = false })
    }
}

// A show's facts: its year, rating box, network's logo (which opens the network's page), status, how many seasons and
// episodes, and its genres.
@Composable
private fun ShowMeta(nav: Nav, show: com.wittywilla.wittymediaclient.net.Show, facts: ShowFacts, logos: Map<String, BrandLogoAnswer>, modifier: Modifier) {
    val rated = facts.contentRating?.ifEmpty { null }
    val network = facts.network?.ifEmpty { null }
    val status = facts.status?.ifEmpty { null }
    val genres = facts.genres.orEmpty().joinToString(", ")
    val library = facts.libraryId
    // Every fact has its dot but the rating box and the one after it: the network, the status or the count.
    val afterPill = rated != null
    MetaRow(modifier) {
        show.year?.takeIf { it != 0 }?.let { Dotted(true) { MetaWords("$it") } }
        if (rated != null) MetaPill(rated)
        if (network != null) Dotted(!afterPill) {
            // `.meta-brand`: 1.6 lines high, no wider than 120.
            Box(
                Modifier.height(22.4.dp).then(if (library != null) Modifier.clickable { nav.push(Route.Page(TitleLook.brandPath("network", network, library))) } else Modifier),
                contentAlignment = Alignment.Center,
            ) { BrandLogo(nav.app.api, network, logos[BrandLogoAnswer.key("network", network)], 120.dp, 22.4.dp, 14, MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        if (status != null) Dotted(!(afterPill && network == null)) { MetaWords(status) }
        Dotted(!(afterPill && network == null && status == null)) { MetaWords(TitleLook.seasonsLine(show.seasonCount, show.episodeCount)) }
        if (genres.isNotEmpty()) Dotted(true) { MetaWords(genres) }
    }
}

// Grey shapes where an item or a show is coming, as the website's: the picture, the poster, and lines for the caption,
// the title, the facts, the buttons and the synopsis.
@Composable
private fun ItemSkeleton() {
    var show by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(250); show = true }
    if (!show) return
    val page = MaterialTheme.colorScheme.background
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(detailHeight(LocalConfiguration.current.screenHeightDp)).background(Brush.verticalGradient(listOf(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f), page))))
        Column(Modifier.pullUp(96.dp).padding(horizontal = 16.dp)) {
            Skel(Modifier.width(132.dp).aspectRatio(2f / 3f), 14.dp)
            Column(Modifier.padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Skel(Modifier.size(80.dp, 12.dp))
                Skel(Modifier.fillMaxWidth(0.6f).height(32.dp))
                Skel(Modifier.fillMaxWidth(0.4f).height(15.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Skel(Modifier.size(144.dp, 44.dp), 10.dp); Skel(Modifier.size(96.dp, 44.dp), 10.dp); Skel(Modifier.size(44.dp, 44.dp), 10.dp) }
                Skel(Modifier.fillMaxWidth().height(15.dp))
                Skel(Modifier.fillMaxWidth().height(15.dp))
                Skel(Modifier.fillMaxWidth(0.7f).height(15.dp))
            }
        }
    }
}

// Search: the title and the field, then Shows and Everything else, three across.
@Composable
fun PhoneSearch(nav: Nav, s: Map<String, String>) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    var text by remember { mutableStateOf(nav.remembered<String>("search-text") ?: "") }
    var query by remember { mutableStateOf(text) }
    var items by remember { mutableStateOf<List<Item>?>(null) }
    var shows by remember { mutableStateOf<List<com.wittywilla.wittymediaclient.net.Show>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (query.isEmpty()) runCatching { focus.requestFocus() } }
    LaunchedEffect(query) {
        nav.remember("search-text", query)
        if (query.isBlank()) { items = null; shows = emptyList(); return@LaunchedEffect }
        items = null
        failed = false
        try {
            coroutineScope {
                val a = async { nav.app.api.searchItems(query, 60).items }
                val b = async { nav.app.api.searchShows(query, 60).shows }
                items = a.await(); shows = b.await()
            }
        } catch (e: CancellationException) { throw e } catch (e: Exception) { failed = true; items = emptyList() }
    }
    val scroll = rememberScrollState()
    TracksScroll(scroll)
    Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(top = LocalTopRoom.current, bottom = LocalBottomRoom.current).padding(horizontal = 16.dp)) {
        Row(Modifier.padding(bottom = 20.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Search", color = scheme.onBackground, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em)
            if (query.isNotEmpty()) Text("“$query”", color = extra.hint, fontSize = 14.sp, modifier = Modifier.padding(bottom = 3.dp))
        }
        WebInput(text, { text = it }, "Search your libraries…", Modifier.fillMaxWidth().padding(bottom = 16.dp), WebIcons.Search, focus) { query = text.trim() }
        val found = items
        when {
            query.isBlank() -> Empty(WebIcons.Search, "Find anything on this server", "Type a title in the search box: movies, shows, episodes, music, books and games are all included.")
            found == null -> SkeletonGrid()
            failed -> Empty(WebIcons.Info, "The search didn't work", "")
            found.isEmpty() && shows.isEmpty() -> Empty(WebIcons.Search, "No results", "Nothing on this server matches “$query”. Try a shorter or different word.")
            else -> {
                if (shows.isNotEmpty()) {
                    GroupHead("Shows")
                    ThreeAcross(shows.size) { i -> WebShowCard(nav, shows[i]) }
                    GroupHead("Everything else")
                }
                ThreeAcross(found.size) { i -> WebItemCard(nav, found[i]) }
            }
        }
        PageFoot(nav, "search")
    }
}

@Composable
private fun GroupHead(words: String) {
    Text(words, color = MaterialTheme.colorScheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 28.dp, bottom = 12.dp))
}

// Three equal columns, 16 apart, rows 24 apart; each card takes the column's width.
@Composable
private fun ThreeAcross(count: Int, card: @Composable (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
        (0 until count).chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { i -> Box(Modifier.weight(1f)) { CardWidth { card(i) } } }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun SkeletonGrid() {
    Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
        repeat(3) {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) { repeat(3) { Skel(Modifier.weight(1f).aspectRatio(2f / 3f), 10.dp) } }
        }
    }
}

@Composable
private fun Empty(icon: ImageVector, title: String, words: String) {
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = LocalExtraColours.current.hint, modifier = Modifier.size(32.dp))
        Text(title, color = scheme.onBackground, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        if (words.isNotEmpty()) Text(words, color = scheme.onSurfaceVariant, fontSize = 14.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.widthIn(max = 420.dp))
    }
}
