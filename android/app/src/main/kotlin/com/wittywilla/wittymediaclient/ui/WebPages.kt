package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
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
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.Collection
import com.wittywilla.wittymediaclient.net.CollectionItems
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.ShowDetail
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

// The website's item, show and search pages on a phone (web/src/pages/ItemPage.tsx, ShowPage.tsx, SearchPage.tsx).

// The picture across the top: 38% of the height (240 to 560), fading out from 40% down, under a shade of the page.
@Composable
private fun DetailHero(url: String) {
    HeroPage()
    val page = MaterialTheme.colorScheme.background
    val screen = LocalConfiguration.current.screenHeightDp.dp
    val height = (screen * 0.38f).coerceIn(240.dp, 560.dp)
    Box(Modifier.fillMaxWidth().height(height)) {
        WebArt(url, "", 400.dp, 1.3f, Modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
            drawContent()
            drawRect(Brush.verticalGradient(0.4f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
        })
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to page.copy(alpha = 0.15f), 0.35f to page.copy(alpha = 0.35f), 0.7f to page.copy(alpha = 0.7f), 1f to page)))
    }
}

private fun detailHeight(screenDp: Int): Dp = (screenDp.dp * 0.38f).coerceIn(240.dp, 560.dp)

@Composable
private fun PageTitle(text: String) {
    Text(
        text, color = MaterialTheme.colorScheme.onBackground, fontSize = 28.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em, lineHeight = 32.sp,
        style = TextStyle(shadow = Shadow(Color(0x73000000), Offset(0f, 2f), 12f)), modifier = Modifier.padding(bottom = 8.dp),
    )
}

// One row in a sheet: 52 high, 16 inside, a 20 icon in textSecondary, the words 15 medium.
data class SheetRow(val words: String, val icon: ImageVector?, val danger: Boolean = false, val run: () -> Unit)

// The website's sheet on a phone: from the foot, panel colour, radius 20 at the top, the title 20 and a 44 close
// button; the "⋯" and Filters sheets slide in 24 from the right as they do there.
@Composable
fun WebSheet(title: String, close: () -> Unit, fromRight: Boolean = true, footer: (@Composable () -> Unit)? = null, content: @Composable () -> Unit) {
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
            Pressable({ close(); row.run() }, Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = RoundedCornerShape(0.dp), fill = Color.Transparent, label = row.words, ring = false) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp).drawWithContent {
                        drawContent()
                        if (i < rows.lastIndex) drawRect(scheme.outline, Offset(32.dp.toPx(), size.height - 1.dp.toPx()), Size(size.width - 32.dp.toPx(), 1.dp.toPx()))
                    },
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

private fun sizeWords(bytes: Long): String = when {
    bytes >= 1L shl 30 -> String.format(Locale.ROOT, "%.2f GB", bytes / (1024.0 * 1024 * 1024))
    bytes >= 1L shl 20 -> String.format(Locale.ROOT, "%.0f MB", bytes / (1024.0 * 1024))
    else -> "$bytes B"
}

private fun codecWords(c: String): String = when (c.lowercase(Locale.ROOT)) { "h264" -> "H.264"; "hevc", "h265" -> "HEVC"; "av1" -> "AV1"; "vp9" -> "VP9"; "vp8" -> "VP8"; "mpeg2video" -> "MPEG-2"; else -> c.uppercase(Locale.ROOT) }

private fun containerWords(c: String): String = when { c.contains("matroska") -> "MKV"; c.contains("mp4") || c.contains("mov") -> "MP4"; c.isEmpty() -> ""; else -> c.substringBefore(',').uppercase(Locale.ROOT) }

private fun languageName(code: String): String = Locale.forLanguageTag(code).displayLanguage.ifEmpty { code }

@Composable
private fun FactsTable(it: Item, admin: Boolean) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val rows = listOfNotNull(
        if (it.width > 0) "Video" to "${it.width}×${it.height} ${codecWords(it.videoCodec)}".trim() else null,
        it.audioLangs?.takeIf { l -> l.isNotEmpty() }?.let { l -> "Audio" to l.joinToString(", ") { c -> languageName(c) } },
        it.subLangs?.takeIf { l -> l.isNotEmpty() }?.let { l -> "Subtitles" to l.joinToString(", ") { c -> languageName(c) } },
        listOf(containerWords(it.container), if (it.sizeBytes > 0) sizeWords(it.sizeBytes) else "").filter { s -> s.isNotEmpty() }.joinToString(" · ").takeIf { s -> s.isNotEmpty() }?.let { s -> "Source" to s },
    )
    if (rows.isEmpty()) return
    Column(
        Modifier.padding(top = 24.dp).fillMaxWidth().drawWithContent { drawContent(); drawRect(scheme.outline, Offset.Zero, Size(size.width, 1.dp.toPx())) }.padding(top = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        rows.forEach { (key, value) ->
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(key.uppercase(), color = extra.hint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em)
                Text(value, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun Crumbs(parts: List<Pair<String, (() -> Unit)?>>) {
    val scheme = MaterialTheme.colorScheme
    FlowRow(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(2.dp), itemVerticalAlignment = Alignment.CenterVertically) {
        parts.forEachIndexed { i, (words, go) ->
            if (i > 0) Icon(WebIcons.Right, null, tint = LocalExtraColours.current.hint, modifier = Modifier.size(14.dp))
            Text(words, color = scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = if (go != null) Modifier.clickable(onClick = go) else Modifier)
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

@Composable
private fun BackLink(words: String, go: () -> Unit) {
    Pressable(go, Modifier.padding(top = 32.dp).heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = Color.Transparent, label = words, ring = false) {
        Row(Modifier.heightIn(min = 44.dp).padding(start = 4.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(WebIcons.Left, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            Text(words, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

private fun canSave(nav: Nav) = nav.me?.kind != "guest"

@Composable
fun PhoneItem(nav: Nav, s: Map<String, String>, id: Long) {
    val scheme = MaterialTheme.colorScheme
    var item by remember { mutableStateOf<Item?>(null) }
    var error by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    var more by remember { mutableStateOf(false) }
    var save by remember { mutableStateOf(false) }
    LaunchedEffect(id, attempt) {
        error = ""
        try { item = nav.app.api.item(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { if (!nav.handleExpired(e)) error = problemWords(e, s["errLost"].orEmpty()) }
    }
    val it = item
    if (it == null) {
        if (error.isNotEmpty()) LoadFailed(nav, error) { attempt++ } else ItemSkeleton()
        return
    }
    val admin = nav.me?.isAdmin == true
    val scroll = rememberScrollState()
    TracksScroll(scroll)
    val library = nav.menu.firstOrNull { e -> (e.route as? Route.Library)?.library?.id == it.libraryId }
    val resume = (it.progress?.resumeSec ?: 0.0) > 0
    val rows = buildList {
        if (it.isDisc) {
            if (it.disc?.hasMenus != false) add(SheetRow("Main menu", WebIcons.Menu) { nav.push(Route.Page("/play/${it.id}?mode=menu")) })
            add(SheetRow("Play movie", WebIcons.Play) { nav.push(Route.Page("/play/${it.id}?mode=title&start=0")) })
        } else {
            if (resume) add(SheetRow("Play from start", WebIcons.Play) { nav.push(Route.Player(it.id, true)) })
            it.nextId?.let { n -> add(SheetRow("Next episode", WebIcons.Next) { nav.push(Route.Item(n)) }) }
        }
        if (admin) {
            add(SheetRow("Artwork", WebIcons.Image) { nav.push(Route.Page("/item/${it.id}?edit=art")) })
            add(SheetRow("Edit", WebIcons.Edit) { nav.push(Route.Page("/item/${it.id}?edit=details")) })
            if (it.showId == null) add(SheetRow("Refresh", WebIcons.Refresh) { nav.push(Route.Page("/item/${it.id}?edit=refresh")) })
        }
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(bottom = LocalBottomRoom.current)) {
            DetailHero(nav.app.api.backdropUrl(it))
            Column(Modifier.offset(y = (-96).dp).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Box(Modifier.width(132.dp).aspectRatio(2f / 3f).cssShadow(10.dp, 30.dp, Color(0x73000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(scheme.surfaceVariant)) {
                    WebArt(nav.app.api.posterUrl(it), "", 132.dp, 2f / 3f, Modifier.fillMaxSize())
                }
                Column {
                    val crumbs = buildList<Pair<String, (() -> Unit)?>> {
                        if (library != null) add(library.label to { nav.openMenu(library) })
                        if (it.showId != null) {
                            add((it.showTitle ?: "") to { nav.push(Route.Show(it.showId)) })
                            add((if (it.season == 0) "Specials" else "Season ${it.season}") to { nav.push(Route.Show(it.showId)) })
                            add("S${it.season} · E${it.episode}" to null)
                        }
                    }
                    if (crumbs.isNotEmpty()) Crumbs(crumbs)
                    PageTitle(it.title)
                    if (it.tagline.isNotEmpty()) Text(it.tagline, color = scheme.onSurfaceVariant, fontSize = 17.sp, fontStyle = FontStyle.Italic, modifier = Modifier.padding(bottom = 8.dp))
                    Facts(it, Modifier.padding(bottom = 20.dp))
                    Row(Modifier.fillMaxWidth().padding(bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (it.isDisc) {
                            WebButton("Insert ${if (it.kind.startsWith("bluray")) "Blu-ray" else "DVD"}", { nav.push(Route.Page("/play/${it.id}?mode=menu&insert=1")) }, WebButtonKind.Primary, WebIcons.Disc, Modifier.weight(1f))
                        } else {
                            WebButton(if (resume) "Resume" else "Play", { nav.play(it) }, WebButtonKind.Primary, WebIcons.Play, Modifier.weight(1f))
                            if (canSave(nav)) WebButton("Save", { save = true }, WebButtonKind.Secondary, WebIcons.Plus)
                        }
                        if (rows.isNotEmpty()) MoreButton { more = true }
                    }
                    if (it.overview.isNotEmpty()) Text(it.overview, color = scheme.onBackground, fontSize = 15.sp, lineHeight = 24.sp, modifier = Modifier.padding(bottom = 20.dp))
                    FactsTable(it, admin)
                    BackLink(if (it.showId != null) "Back to ${it.showTitle}" else "Back to library") {
                        if (it.showId != null) nav.push(Route.Show(it.showId)) else if (library != null) nav.openMenu(library) else nav.back()
                    }
                }
            }
        }
        if (more) WebSheet(it.title, { more = false }) { SheetRows(rows) { more = false } }
        if (save) SaveDialog(nav, it.id, 0, close = { save = false })
    }
}

@Composable
fun PhoneShow(nav: Nav, s: Map<String, String>, id: Long) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    var detail by remember { mutableStateOf<ShowDetail?>(null) }
    var error by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    var season by remember { mutableStateOf<Int?>(null) }
    var more by remember { mutableStateOf(false) }
    var save by remember { mutableStateOf(false) }
    LaunchedEffect(id, attempt) {
        error = ""
        try { detail = nav.app.api.show(id) } catch (e: CancellationException) { throw e } catch (e: Exception) { if (!nav.handleExpired(e)) error = problemWords(e, s["errLost"].orEmpty()) }
    }
    val d = detail
    if (d == null) {
        if (error.isNotEmpty()) LoadFailed(nav, error) { attempt++ } else ItemSkeleton()
        return
    }
    val show = d.show
    val nextUp = d.episodes.firstOrNull { it.id == d.nextUpId }
    val chosen = season ?: nextUp?.season ?: d.seasons.firstOrNull { it.number > 0 }?.number ?: d.seasons.firstOrNull()?.number ?: 1
    val admin = nav.me?.isAdmin == true
    val scroll = rememberScrollState()
    TracksScroll(scroll)
    val library = nav.menu.firstOrNull { e -> (e.route as? Route.Library)?.library?.id == d.episodes.firstOrNull()?.libraryId }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(bottom = LocalBottomRoom.current)) {
            DetailHero(nav.app.api.showBackdropUrl(show))
            Column(Modifier.offset(y = (-96).dp).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Box(Modifier.width(132.dp).aspectRatio(2f / 3f).cssShadow(10.dp, 30.dp, Color(0x73000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(scheme.surfaceVariant)) {
                    WebArt(nav.app.api.showPosterUrl(show), "", 132.dp, 2f / 3f, Modifier.fillMaxSize())
                }
                Column {
                    PageTitle(show.title)
                    FlowRow(Modifier.padding(bottom = 20.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        val parts = listOfNotNull(show.year?.toString(), show.network.ifEmpty { null }, show.status.ifEmpty { null },
                            "${show.seasonCount} season${if (show.seasonCount == 1) "" else "s"} · ${show.episodeCount} episode${if (show.episodeCount == 1) "" else "s"}",
                            show.genres.joinToString(", ").ifEmpty { null })
                        parts.forEachIndexed { i, p ->
                            if (i > 0) Text("·", color = extra.hint, fontSize = 14.sp)
                            Text(p, color = scheme.onSurfaceVariant, fontSize = 14.sp)
                        }
                    }
                    Row(Modifier.fillMaxWidth().padding(bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        nextUp?.let { ep ->
                            val resume = (ep.progress?.resumeSec ?: 0.0) > 0
                            WebButton("${if (resume) "Resume" else "Play"} S${ep.season} · E${ep.episode}", { nav.play(ep) }, WebButtonKind.Primary, WebIcons.Play, Modifier.weight(1f))
                        }
                        if (canSave(nav)) WebButton("Save", { save = true }, WebButtonKind.Secondary, WebIcons.Plus)
                        if (admin) MoreButton { more = true }
                    }
                    if (show.overview.isNotEmpty()) Text(show.overview, color = scheme.onBackground, fontSize = 15.sp, lineHeight = 24.sp, modifier = Modifier.padding(bottom = 20.dp))
                    // The seasons, 108 wide, scrolling sideways; the chosen one ringed in the accent.
                    LazyRow(Modifier.padding(top = 4.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        items(d.seasons, key = { it.number }) { se ->
                            val on = se.number == chosen
                            Column(Modifier.width(108.dp).padding(vertical = 4.dp).clickable { season = se.number }) {
                                Box(
                                    Modifier.fillMaxWidth().aspectRatio(2f / 3f).then(if (on) Modifier.ringOutside(RoundedCornerShape(10.dp), scheme.primary, 2.dp, 2.dp) else Modifier)
                                        .clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant),
                                ) { WebArt(nav.app.api.seasonPosterUrl(show, se.number), se.title, 108.dp, 2f / 3f, Modifier.fillMaxSize()) }
                                Text(se.title.ifEmpty { if (se.number == 0) "Specials" else "Season ${se.number}" }, color = scheme.onBackground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
                                Text("${se.episodeCount} ep · ${if (se.unwatched == 0) "watched" else "${se.unwatched} left"}", color = extra.hint, fontSize = 12.sp)
                            }
                        }
                    }
                    Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        d.episodes.filter { it.season == chosen }.forEach { ep -> EpisodeRow(nav, ep) }
                    }
                    BackLink("Back to library") { if (library != null) nav.openMenu(library) else nav.back() }
                }
            }
        }
        if (more) WebSheet(show.title, { more = false }) {
            SheetRows(listOf(
                SheetRow("Artwork", WebIcons.Image) { nav.push(Route.Page("/show/${show.id}?edit=art")) },
                SheetRow("Edit", WebIcons.Edit) { nav.push(Route.Page("/show/${show.id}?edit=details")) },
                SheetRow("Refresh", WebIcons.Refresh) { nav.push(Route.Page("/show/${show.id}?edit=refresh")) },
            )) { more = false }
        }
        if (save) SaveDialog(nav, 0, show.id, close = { save = false })
    }
}

// An episode: the 132 picture (tapping it plays), then "S1 · E1" and the title, when it aired and how long, and two
// lines about it. Anywhere else opens the episode's page.
@Composable
private fun EpisodeRow(nav: Nav, ep: Item) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val progress = ep.progress?.takeIf { p -> !p.watched && p.positionSec > 0 && p.durationSec > 0 }?.let { p -> (p.positionSec / p.durationSec).toFloat() }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { nav.push(Route.Item(ep.id)) }.padding(8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.width(132.dp).aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant).clickable { nav.play(ep) }) {
            WebArt(nav.app.api.posterUrl(ep), "", 132.dp, 16f / 9f, Modifier.fillMaxSize())
            if (ep.progress?.watched == true) Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(20.dp).clip(RoundedCornerShape(50)).background(Color(0xAD000000)), contentAlignment = Alignment.Center) {
                Icon(WebIcons.Check, null, tint = Color.White, modifier = Modifier.size(14.dp))
            }
            if (progress != null) Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(3.dp).background(Color(0x47FFFFFF))) {
                Box(Modifier.fillMaxWidth(progress).height(3.dp).background(scheme.primary))
            }
        }
        Column(Modifier.weight(1f).padding(top = 2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("S${ep.season} · E${ep.episode}", color = extra.hint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(end = 6.dp))
                Text(ep.title, color = scheme.onBackground, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, lineHeight = 20.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            val sub = listOfNotNull(ep.aired.ifEmpty { null }, runtimeWords(ep.runtimeSec).ifEmpty { null }).joinToString(" · ")
            if (sub.isNotEmpty()) Text(sub, color = extra.hint, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp))
            if (ep.overview.isNotEmpty()) Text(ep.overview, color = scheme.onSurfaceVariant, fontSize = 13.sp, lineHeight = 19.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
private fun ItemSkeleton() {
    var show by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(250); show = true }
    if (!show) return
    val page = MaterialTheme.colorScheme.background
    Column(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxWidth().height(detailHeight(LocalConfiguration.current.screenHeightDp)).background(Brush.verticalGradient(listOf(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f), page))))
        Column(Modifier.offset(y = (-96).dp).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Skel(Modifier.width(132.dp).aspectRatio(2f / 3f), 14.dp)
            Skel(Modifier.size(80.dp, 12.dp))
            Skel(Modifier.fillMaxWidth(0.6f).height(32.dp))
            Skel(Modifier.fillMaxWidth(0.4f).height(15.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { Skel(Modifier.size(144.dp, 44.dp), 10.dp); Skel(Modifier.size(96.dp, 44.dp), 10.dp); Skel(Modifier.size(44.dp, 44.dp), 10.dp) }
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
