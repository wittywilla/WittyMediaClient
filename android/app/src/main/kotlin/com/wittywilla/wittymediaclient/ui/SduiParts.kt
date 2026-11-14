// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.view.KeyEvent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.gestures.LocalBringIntoViewSpec
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.wittywilla.wittymediaclient.net.SduiAction
import com.wittywilla.wittymediaclient.net.SduiButton
import com.wittywilla.wittymediaclient.net.SduiControlSpec
import com.wittywilla.wittymediaclient.net.SduiItemActions
import com.wittywilla.wittymediaclient.net.isForm
import com.wittywilla.wittymediaclient.net.SduiMarkdown
import com.wittywilla.wittymediaclient.net.SduiView
import com.wittywilla.wittymediaclient.net.aspectOf
import com.wittywilla.wittymediaclient.net.child
import com.wittywilla.wittymediaclient.net.image
import com.wittywilla.wittymediaclient.net.int
import com.wittywilla.wittymediaclient.net.isOn
import com.wittywilla.wittymediaclient.net.ShelfRules
import com.wittywilla.wittymediaclient.net.objects
import com.wittywilla.wittymediaclient.net.str
import com.wittywilla.wittymediaclient.tv.TvLayer
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The server's components (docs/SDUI.md, Components), each as the app's own kind of thing: a row is a lazy row, a
// spotlight a pager on a touch screen and one focus stop on a TV, filters a row of chips with a sheet of choices.
// Sizes are the page's (`document.layout`); what is shown, and in how many lines, is what net/SduiScreen.kt laid out.

// Any component, by its type. One this app doesn't know is drawn as a column of what it holds.
@Composable
fun SduiNode(view: SduiView, parent: SduiView?, topLevel: Boolean = false) {
    val side = if (topLevel) LocalSduiSpan.current.side else 0.dp
    if (view.isForm) {
        SduiFormView(view, side)
        return
    }
    if (view.node.type == "QR") {
        SduiQr(view, side)
        return
    }
    when (view.type) {
        "Hero" -> SduiHero(view)
        "Shelf" -> SduiShelf(view, side)
        "Grid" -> SduiGridBlock(view, side)
        "Card" -> Box(Modifier.padding(horizontal = side)) { SduiCard(view, parent, LocalSdui.current.pt(parent?.cardWidth?.takeIf { it > 0 } ?: 160)) }
        "Tabs" -> SduiTabs(view, side, withContent = !topLevel)
        "Tab" -> Column { view.children.forEach { SduiNode(it, view, topLevel) } }
        "FilterBar" -> SduiFilterBar(view, side)
        "DetailHeader" -> SduiDetailHeader(view)
        "SeasonList" -> SduiSeasons(view, side)
        "TrackList", "List" -> Column(Modifier.padding(horizontal = side)) {
            SduiLongHead(view, pad = false)
            view.children.forEach { SduiLine(it, view) }
        }
        "Track", "ListItem" -> Box(Modifier.padding(horizontal = side)) { parent?.let { SduiLine(view, it) } }
        "Banner" -> SduiBanner(view, side)
        "Text" -> SduiTextBlock(view, Modifier.padding(horizontal = side))
        "Notice" -> SduiNotice(view, Modifier.padding(horizontal = side))
        "Divider" -> HorizontalDivider(Modifier.padding(horizontal = if (view.props.isOn("inset")) LocalSduiSpan.current.side else 0.dp), thickness = 1.dp, color = MaterialTheme.colorScheme.outline)
        "Spacer" -> LocalSdui.current.space(view.props.str("size").ifEmpty { "m" }).let { Spacer(Modifier.size(it)) }
        "Split" -> SduiSplit(view, side)
        "Button" -> Box(Modifier.padding(horizontal = side)) { SduiButtonView(view) }
        "Image" -> SduiImageBlock(view, Modifier.padding(horizontal = side))
        "SearchBox" -> SduiSearchBox(view, Modifier.padding(horizontal = side))
        "NativeView" -> SduiNativeView(view)
        "Dock" -> SduiDockBar(view, side)
        "Carousel" -> SduiCarousel(view, side)
        "CrossBar" -> SduiCrossBar(view, side)
        "WidgetGrid" -> SduiWidgetGrid(view, side)
        "Widget" -> Box(Modifier.padding(horizontal = side)) { SduiWidget(view) }
        "NumberedRow" -> SduiNumberedRow(view, side)
        "KeyLegend" -> Box(Modifier.padding(horizontal = side)) { KeyLegendRow() }
        "Credits" -> SduiCredits(view, side)
        else -> SduiStack(view, side)
    }
}

// The Dock at the foot of the page: a bar `layout.dock.height` tall that never scrolls, or on a phone (`sheet`) an Options
// button that opens its controls as a sheet.
@Composable
fun SduiDockBar(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    if (env.layout.dock.placement != "sheet") {
        SduiDock(view, side)
        return
    }
    var open by remember { mutableStateOf(false) }
    // A control pressed in the sheet hands over to what it opens.
    LaunchedEffect(env.control.value) { if (env.control.value != null) open = false }
    Box(Modifier.fillMaxWidth().padding(horizontal = side, vertical = env.space("s")), contentAlignment = Alignment.CenterEnd) {
        WebButton("Options", { open = true }, WebButtonKind.Ghost, small = true)
    }
    if (open) WebSheet(view.label, { open = false }, fromRight = false) {
        Column(Modifier.padding(env.space("m")), verticalArrangement = Arrangement.spacedBy(env.space("s"))) {
            view.children.filter { it.type == "Button" }.forEach { button ->
                SduiNode(button, view)
            }
        }
    }
}

// The screen's Dock: its buttons in one row that never moves, and the key legend of the input in use under them (which a
// touch screen doesn't show).
@Composable
private fun SduiDock(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val keys = view.children.filter { it.type == "KeyLegend" }
    // On a TV the bar sits on the picture's safe area, not on the screen's edge.
    val foot = if (env.tv) env.pt(env.layout.safeArea.bottom) else 0.dp
    Row(
        Modifier.fillMaxWidth().padding(horizontal = side).padding(bottom = foot).elevated(1, RoundedCornerShape(env.pt(14)), env.pt(14))
            .defaultMinSize(minHeight = if (env.tv) env.pt(DesignTokens.Tv.Dock.height.toFloat()) else 0.dp)
            .padding(horizontal = env.space("m"), vertical = env.space("s")).focusGroup(),
        horizontalArrangement = Arrangement.spacedBy(env.space("m")), verticalAlignment = Alignment.CenterVertically,
    ) {
        // The buttons scroll when there are too many; the key legend keeps its place at the trailing end.
        Row(Modifier.weight(1f, fill = false).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(env.space("s")), verticalAlignment = Alignment.CenterVertically) {
            view.children.filter { it.type != "KeyLegend" }.forEach { SduiNode(it, view) }
        }
        Spacer(Modifier.weight(1f))
        keys.forEach { SduiNode(it, view) }
    }
}

// MARK: headings and states

// The heading over a row, a grid or a list: its title at the title size, a smaller line under it, and on a touch
// screen the way to everything the row is drawn from.
@Composable
fun SduiSectionHead(view: SduiView, side: Dp, seeAll: Boolean = true) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val title = view.text["title"]
    val subtitle = view.text["subtitle"]
    val all = view.seeAll.takeIf { seeAll && it.isNotEmpty() && !view.seeAllCard }
    if (title == null && subtitle == null && all == null) return
    Row(Modifier.fillMaxWidth().padding(horizontal = side).padding(bottom = env.space(if (env.tv) "s" else if (all != null) "xs" else "s")), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            if (title != null) Text(
                title, color = scheme.onBackground, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, maxLines = view.line("title", 1), overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { heading() },
            )
            if (subtitle != null) Text(subtitle, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (all != null) {
            val words = view.props.child("seeAll")?.str("label").orEmpty().ifEmpty { "See all" }
            Pressable({ env.act(SduiAction(type = "navigate", to = all)) }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "$words, ${title.orEmpty()}", ring = false) {
                Row(Modifier.heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(words, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), fontWeight = FontWeight.Medium)
                    Icon(WebIcons.Right, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

// The heading of something whose rows are the page's own items: a grid, a list, a track list, a phone's episodes.
@Composable
fun SduiLongHead(view: SduiView, pad: Boolean = true) {
    val side = if (pad) LocalSduiSpan.current.side else 0.dp
    if (view.type == "SeasonList") SduiSeasonHead(view, side) else SduiSectionHead(view, side)
}

// Where the items would be when there are none: the message, in the caption style.
@Composable
private fun SduiEmptyLine(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val words = view.text["empty"] ?: return
    // An empty section says what to do: a hint under the message and a button that runs emptyAction ("Scan now").
    val hint = view.props.str("emptyHint")
    val action = view.props.child("emptyAction")
    val label = action?.str("label").orEmpty()
    val run = action?.child("action")?.let { runCatching { com.wittywilla.wittymediaclient.net.json.decodeFromJsonElement(SduiAction.serializer(), it) }.getOrNull() }
    Column(Modifier.padding(horizontal = side), verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
        Text(words, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("caption"))
        if (hint.isNotEmpty()) Text(hint, color = LocalExtraColours.current.hint, fontSize = env.size("caption"))
        if (label.isNotEmpty() && run != null) {
            if (env.tv) WittyButton(label, { env.act(run) }, kind = ButtonKind.Secondary, pill = true, focusKey = view.id + "~empty")
            else WebButton(label, { env.act(run) }, WebButtonKind.Secondary, small = true)
        }
    }
}

// A section that couldn't be loaded: one line, and Retry, which asks its address again.
@Composable
private fun SduiFailedLine(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    Row(Modifier.padding(horizontal = side), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
        Text("Couldn't load this", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("body"))
        if (env.tv) WittyButton("Retry", { env.more(view.id, true) }, focusKey = view.id + "~retry")
        else WebButton("Retry", { env.more(view.id, true) }, WebButtonKind.Secondary, small = true)
    }
}

// The grey cards a row shows while its own are on their way: as many as are at least partly on screen.
@Composable
private fun SduiPlaceholderRow(view: SduiView, side: Dp, count: Int) {
    val env = LocalSdui.current
    val wide = env.pt(view.cardWidth.takeIf { it > 0 } ?: 120)
    val tall = env.pt(view.cardHeight.takeIf { it > 0 } ?: 180)
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState(), enabled = false).padding(horizontal = side).clearAndSetSemantics { contentDescription = "Loading" },
        horizontalArrangement = Arrangement.spacedBy(env.pt(env.layout.cardGap)),
    ) {
        repeat(count.coerceAtLeast(1)) { SduiPlaceholder(wide, tall, env.layout.cards[view.cardStyle]?.shape.orEmpty()) }
    }
}

// MARK: Shelf and Grid

// A row that scrolls sideways under a remote's focus as Android TV's rows do, whatever the page's column does.
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SduiRowScroll(content: @Composable () -> Unit) {
    val spec = LocalSduiRowSpec.current
    if (spec == null) content() else CompositionLocalProvider(LocalBringIntoViewSpec provides spec, content = content)
}

@Composable
fun SduiShelf(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val span = LocalSduiSpan.current
    val edge = if (side > 0.dp) side else 0.dp
    Column(Modifier.fillMaxWidth()) {
        SduiSectionHead(view, edge)
        when {
            view.deferred -> {
                // It comes within a screen of being seen when the page's column lays it out.
                LaunchedEffect(view.id) { env.more(view.id, false) }
                SduiPlaceholderRow(view, edge, view.placeholders)
            }
            view.failed -> SduiFailedLine(view, edge)
            view.empty || view.children.isEmpty() -> SduiEmptyLine(view, edge)
            else -> {
                val state = rememberLazyListState()
                val layoutWidth = env.pt(view.cardWidth.takeIf { it > 0 } ?: 120)
                // The next card peeks in by the layout's fraction of its width (layout.peek; net/ShelfRules.kt).
                val wide = ShelfRules.cardWidth(
                    visible = (span.content + span.side).value, gap = env.pt(env.layout.cardGap).value, width = layoutWidth.value,
                    peek = view.peek.toFloat(), count = view.children.size + if (view.seeAllCard) 1 else 0,
                ).dp
                val nearEnd by remember(view.children.size) { derivedStateOf { (state.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0) >= view.children.size - 4 } }
                if (view.hasMore && nearEnd) LaunchedEffect(view.children.size) { env.more(view.id, false) }
                val ring = if (env.tv) LocalMetrics.current.focusRing else 0.dp
                // focusGrow: the chosen card grows (1.45 on a television, 1.25 on a tablet, none on a phone, whose first card is
                // simply larger) and the ones after it step aside. detail: a panel under the row for the chosen card.
                val grows = view.props.isOn("focusGrow")
                val detail = view.props.isOn("detail")
                var chosen by remember(view.id) { mutableStateOf<String?>(null) }
                val chosenId = chosen ?: view.children.firstOrNull()?.id
                val scale = if (!grows) 1f else if (env.tv) 1.45f else if (env.tablet) 1.25f else 1f
                val touch = !env.tv
                val tall = env.pt(view.cardHeight.takeIf { it > 0 } ?: 180)
                SduiRowScroll { LazyRow(
                    (if (env.tv) Modifier.remoteRow() else Modifier).fillMaxWidth(), state = state,
                    // A TV's cards keep room for their ring and the little they grow by, so neither is cut off.
                    contentPadding = PaddingValues(start = (edge - ring).coerceAtLeast(0.dp), end = (edge - ring).coerceAtLeast(0.dp), top = if (env.tv) env.pt(12) else 0.dp, bottom = (if (env.tv) env.pt(12) else env.space("xs")) + tall * (scale - 1f)),
                    horizontalArrangement = Arrangement.spacedBy((env.pt(env.layout.cardGap) - ring * 2).coerceAtLeast(0.dp)),
                ) {
                    items(view.children, key = { it.id }, contentType = { "card" }) { card ->
                        if (!grows && !detail) SduiCard(card, view, wide)
                        else {
                            val first = !env.tv && !env.tablet && grows && card.id == view.children.first().id
                            SduiCard(card, view, if (first) wide * 1.25f else wide, grow = SduiGrow(scale, card.id == chosenId, touch && detail, { chosen = card.id }))
                        }
                    }
                    if (view.hasMore && view.id in env.loading) item(key = "~loading", contentType = "placeholder") {
                        SduiPlaceholder(wide, env.pt(view.cardHeight.takeIf { it > 0 } ?: 180), "")
                    }
                    // See all as the row's last card, in the shape of its cards, where the node asks for it.
                    if (view.seeAllCard && view.seeAll.isNotEmpty() && !view.hasMore) item(key = "~see-all", contentType = "see-all") {
                        val tall = env.pt(view.cardHeight.takeIf { it > 0 } ?: 180)
                        val words = view.props.child("seeAll")?.str("label").orEmpty().ifEmpty { "See all" }
                        Pressable({ env.act(SduiAction(type = "navigate", to = view.seeAll)) }, Modifier.width(wide), shape = RoundedCornerShape(env.pt(10)), fill = MaterialTheme.colorScheme.surface, label = "$words, ${view.label}", focusKey = view.id + "~see-all") {
                            Box(Modifier.size(wide, tall), contentAlignment = Alignment.Center) { Text(words, color = MaterialTheme.colorScheme.onSurface, fontSize = env.size("body"), fontWeight = FontWeight.Medium) }
                        }
                    }
                } }
                if (detail) SduiDetailPanel(view.children.firstOrNull { it.id == chosenId }, edge)
            }
        }
        if (span.side == 0.dp) Unit
    }
}

// A grid that isn't laid out as the page's own rows: one still on its way, empty or failed, or one inside something else.
@Composable
private fun SduiGridBlock(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val span = LocalSduiSpan.current
    Column(Modifier.fillMaxWidth()) {
        SduiSectionHead(view, side)
        when {
            view.deferred -> {
                LaunchedEffect(view.id) { env.more(view.id, false) }
                SduiPlaceholderRow(view, side, view.placeholders)
            }
            view.failed -> SduiFailedLine(view, side)
            view.empty || view.children.isEmpty() -> SduiEmptyLine(view, side)
            else -> {
                val across = (view.columns.takeIf { it > 0 } ?: 3)
                val between = env.pt(env.layout.cardGap)
                val wide = (span.content - between * (across - 1)) / across
                Column(Modifier.padding(horizontal = side), verticalArrangement = Arrangement.spacedBy(between)) {
                    view.children.chunked(across).forEach { cards -> Row(horizontalArrangement = Arrangement.spacedBy(between)) { cards.forEach { SduiCard(it, view, wide) } } }
                }
            }
        }
    }
}

// MARK: Hero

// A button of a spotlight's slide or of a title's header: the app's own button, filled when it is the main one.
@Composable
private fun SduiActionButton(button: SduiButton, focusKey: String, requestFocus: Boolean = false, requester: FocusRequester? = null, modifier: Modifier = Modifier, wide: Boolean = false) {
    val env = LocalSdui.current
    val icon = button.icon.takeIf { it.isNotEmpty() }?.let(::sduiIcon)
    if (env.tv) {
        WittyButton(button.label, { env.act(button.action) }, modifier, kind = if (button.primary) ButtonKind.Primary else ButtonKind.Secondary, icon = icon, pill = true, focusKey = focusKey, requestFocus = requestFocus, focusRequester = requester)
    } else {
        WebButton(button.label, { env.act(button.action) }, if (button.primary) WebButtonKind.Primary else WebButtonKind.Secondary, icon, modifier.then(if (wide) Modifier.fillMaxWidth() else Modifier))
    }
}

// A slide's or a header's facts on one line, a dot between them.
@Composable
private fun SduiFacts(words: String, modifier: Modifier = Modifier, lines: Int = 2) {
    val env = LocalSdui.current
    Text(words, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size(if (env.tv) "body" else "caption") * (if (env.tv) 1f else 1.08f), maxLines = lines, overflow = TextOverflow.Ellipsis, modifier = modifier)
}

// The title's logo art in place of its name, where it has one.
@Composable
private fun SduiLogoOrTitle(view: SduiView, role: String, maxWide: Dp, lines: Int) {
    val env = LocalSdui.current
    val logo = view.props.image("logo")
    val title = view.text["title"].orEmpty()
    var failed by remember(logo?.url) { mutableStateOf(false) }
    if (logo != null && logo.url.isNotEmpty() && !failed) {
        val context = LocalContext.current
        val request = remember(logo.url) { ImageRequest.Builder(context).data(env.url(logo.url)).build() }
        AsyncImage(request, title, contentScale = ContentScale.Fit, alignment = Alignment.BottomStart, modifier = Modifier.widthIn(max = maxWide).heightIn(max = env.pt(env.layout.textSize(role) * 2.4f)), onError = { failed = true })
    } else {
        Text(title, color = MaterialTheme.colorScheme.onBackground, fontSize = env.size(role), fontWeight = FontWeight.Bold, maxLines = lines, overflow = TextOverflow.Ellipsis, lineHeight = env.size(role) * 1.15f, modifier = Modifier.semantics { heading() })
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SduiHero(view: SduiView) {
    val env = LocalSdui.current
    val slides = view.children
    val scheme = MaterialTheme.colorScheme
    val reduce = LocalReduceMotion.current || env.layout.reducedMotion
    val seconds = if (reduce) 0 else view.props.int("autoAdvanceSec") ?: 0
    if (slides.isEmpty()) {
        // Empty or failed, a spotlight is left out; on its way, it is a grey block of its size.
        if (view.deferred) {
            LaunchedEffect(view.id) { env.more(view.id, false) }
            Skel(Modifier.fillMaxWidth().height(env.pt(view.cardHeight.takeIf { it > 0 } ?: 242)), 0.dp)
        }
        return
    }
    val page = scheme.background
    BoxWithConstraints(Modifier.fillMaxWidth().semantics { contentDescription = view.label }) {
        val wide = maxWidth
        val banner = view.props.str("style") == "banner"
        if (env.tv) {
            // The top of the screen: the backdrop behind a shade from the left, the words and buttons at the foot.
            var index by rememberSaveable { mutableIntStateOf(0) }
            var inside by remember { mutableStateOf(false) }
            var focused by remember { mutableIntStateOf(0) }
            val slide = slides[index.coerceIn(0, slides.lastIndex)]
            // It never moves on while one of its buttons has focus.
            LaunchedEffect(index, inside, seconds, slides.size) {
                if (seconds <= 0 || inside || slides.size < 2) return@LaunchedEffect
                delay(seconds * 1000L)
                index = (index + 1) % slides.size
            }
            val tall = env.pt(view.cardHeight.takeIf { it > 0 } ?: 620)
            val backdrop = slide.props.image("image")
            Box(Modifier.fillMaxWidth().height(tall)) {
                SduiPicture(backdrop, wide, wide / tall, null, Modifier.fillMaxSize(), alignment = Alignment.TopCenter)
                Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(0f to page, 0.35f to page.copy(alpha = 0.82f), 0.75f to Color.Transparent)))
                Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.6f to Color.Transparent, 1f to page)))
                val buttons = slide.actionButtons
                Column(
                    Modifier.align(Alignment.BottomStart).padding(start = LocalSduiSpan.current.side, bottom = env.space("s")).widthIn(max = env.pt(900)),
                    verticalArrangement = Arrangement.spacedBy(env.space("xs")),
                ) {
                    SduiLogoOrTitle(slide, "heading", env.pt(700), slide.line("title", 2))
                    slide.text["facts"]?.let { SduiFacts(it, lines = 1) }
                    slide.text["synopsis"]?.takeIf { view.props["showSynopsis"]?.toString() != "false" }?.let {
                        Text(it, color = scheme.onBackground.copy(alpha = 0.86f), fontSize = env.size("body"), maxLines = slide.line("synopsis", 3), overflow = TextOverflow.Ellipsis)
                    }
                    Row(
                        Modifier.padding(top = env.space("xs")).onFocusChanged { inside = it.hasFocus }
                            // Left and right past the ends of its buttons change the title.
                            .onPreviewKeyEvent {
                                if (it.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                                when (it.key.nativeKeyCode) {
                                    KeyEvent.KEYCODE_DPAD_RIGHT -> if (focused >= buttons.lastIndex && index < slides.lastIndex) { index++; true } else focused >= buttons.lastIndex
                                    KeyEvent.KEYCODE_DPAD_LEFT -> if (focused <= 0 && index > 0) { index--; true } else focused <= 0
                                    else -> false
                                }
                            }.focusGroup(),
                        horizontalArrangement = Arrangement.spacedBy(env.pt(16)),
                    ) {
                        buttons.forEachIndexed { i, button ->
                            // The same key on every slide, so focus stays on Play as the titles change.
                            SduiActionButton(
                                button, focusKey = "${view.id}~${button.id}", requestFocus = view.id == env.screen.focus.default && (button.primary || i == 0),
                                modifier = Modifier.onFocusChanged { if (it.isFocused) focused = i },
                            )
                        }
                    }
                    if (slides.size > 1) Row(Modifier.padding(top = env.space("xs")).clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(env.pt(8))) {
                        slides.forEachIndexed { i, _ -> Box(Modifier.size(env.pt(if (i == index) 28 else 12), env.pt(12)).clip(CircleShape).background(if (i == index) scheme.onBackground else scheme.onBackground.copy(alpha = 0.4f))) }
                    }
                }
            }
        } else {
            // A touch screen: swiped sideways from title to title, the dots under it.
            val pager = rememberPagerState { slides.size }
            val scope = rememberCoroutineScope()
            LaunchedEffect(pager.currentPage, pager.isScrollInProgress, seconds, slides.size) {
                if (seconds <= 0 || pager.isScrollInProgress || slides.size < 2) return@LaunchedEffect
                delay(seconds * 1000L)
                pager.animateScrollToPage((pager.currentPage + 1) % slides.size)
            }
            val screenTall = LocalConfiguration.current.screenHeightDp.dp
            val tall = when {
                // A tablet's is wide and short; a phone's billboard is tall, though never so tall its buttons leave the screen.
                env.tablet -> (wide * 9f / 21f).coerceAtMost(screenTall * 0.6f)
                banner -> wide * 9f / 16f
                else -> (wide * 1.5f).coerceAtMost(screenTall * 0.66f)
            }
            Column {
                HorizontalPager(pager, Modifier.fillMaxWidth().height(tall), key = { slides[it].id }) { at ->
                    val slide = slides[at]
                    Box(Modifier.fillMaxSize().semantics(mergeDescendants = false) { contentDescription = slide.label }) {
                        SduiPicture(slide.props.image("image"), wide, wide / tall, null, Modifier.fillMaxSize(), alignment = Alignment.TopCenter)
                        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.18f to page.copy(alpha = 0f), 0.44f to page.copy(alpha = 0.72f), 0.66f to page.copy(alpha = 0.94f), 1f to page)))
                        Column(Modifier.align(Alignment.BottomStart).padding(horizontal = LocalSduiSpan.current.side).padding(bottom = env.space("s")).then(if (env.tablet) Modifier.fillMaxWidth(0.5f) else Modifier.fillMaxWidth())) {
                            SduiLogoOrTitle(slide, "pageTitle", wide * 0.7f, slide.line("title", 2))
                            slide.text["facts"]?.let { SduiFacts(it, Modifier.padding(top = env.space("s"))) }
                            slide.text["synopsis"]?.takeIf { view.props["showSynopsis"]?.toString() != "false" && !banner }?.let {
                                Text(it, color = scheme.onBackground.copy(alpha = 0.86f), fontSize = env.size("body"), maxLines = slide.line("synopsis", 3), overflow = TextOverflow.Ellipsis, lineHeight = env.size("body") * 1.45f, modifier = Modifier.padding(top = env.space("s")))
                            }
                            FlowRow(Modifier.padding(top = env.space("m")), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                slide.actionButtons.forEach { SduiActionButton(it, focusKey = "${slide.id}~${it.id}") }
                            }
                        }
                    }
                }
                if (slides.size > 1) Row(Modifier.fillMaxWidth().padding(top = env.space("xs")), horizontalArrangement = Arrangement.Center) {
                    slides.forEachIndexed { i, slide ->
                        val on = i == pager.currentPage
                        Pressable({ scope.launch { pager.animateScrollToPage(i) } }, Modifier.size(24.dp), shape = CircleShape, fill = Color.Transparent, label = "Show ${slide.text["title"].orEmpty()}", selected = on, ring = false) {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Box(Modifier.size(if (on) 18.dp else 8.dp, 8.dp).clip(RoundedCornerShape(4.dp)).background(if (on) scheme.onBackground else scheme.onBackground.copy(alpha = 0.45f)))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: DetailHeader

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SduiDetailHeader(view: SduiView) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val p = view.props
    val side = LocalSduiSpan.current.side
    val images = p.child("images")
    val backdrop = images?.image("backdrop")
    val poster = images?.image("poster")
    val buttons = view.actionButtons
    val page = scheme.background
    if (view.failed) {
        // The title isn't there: say so, with a way Home.
        Column(Modifier.padding(horizontal = side), verticalArrangement = Arrangement.spacedBy(env.space("s"))) {
            Text("This title isn't available", color = scheme.onBackground, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold)
            if (env.tv) WittyButton("Home", { env.nav.reset(Route.Home) }, focusKey = view.id + "~home", requestFocus = true) else WebButton("Home", { env.nav.reset(Route.Home) })
        }
        return
    }
    BoxWithConstraints(Modifier.fillMaxWidth().semantics { contentDescription = view.label }) {
        val wide = maxWidth
        if (env.tv) {
            // The backdrop across the screen under a shade; the words at the left, the buttons in a row with the main one first and focused.
            Box(Modifier.fillMaxWidth().heightIn(min = env.pt(620))) {
                if (backdrop != null) {
                    SduiPicture(backdrop, wide, 16f / 9f, null, Modifier.matchParentSize(), alignment = Alignment.TopCenter)
                    Box(Modifier.matchParentSize().background(Brush.horizontalGradient(0f to page, 0.4f to page.copy(alpha = 0.85f), 0.85f to page.copy(alpha = 0.2f))))
                    Box(Modifier.matchParentSize().background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to page)))
                }
                Row(Modifier.padding(start = side, end = side, top = env.space("m"), bottom = env.space("s")), horizontalArrangement = Arrangement.spacedBy(env.space("m")), verticalAlignment = Alignment.Bottom) {
                    if (poster == null && p.str("kind") == "person") PersonInitials(view.text["title"].orEmpty(), env.pt(300))
                    if (poster != null && (p.str("layout") == "poster" || backdrop == null)) {
                        val shape = headerShape(poster, p.str("kind"))
                        val posterWide = env.pt(if (shape > 1f) 480 else 300)
                        SduiPicture(poster, posterWide, shape, sduiKindIcon(p.str("kind")), Modifier.width(posterWide).aspectRatio(shape).clip(RoundedCornerShape(env.pt(14))))
                    }
                    Column(Modifier.widthIn(max = env.pt(1000)), verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
                        SduiLogoOrTitle(view, "pageTitle", env.pt(800), view.line("title", 2))
                        view.text["tagline"]?.let { Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("body"), fontStyle = FontStyle.Italic, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        view.text["facts"]?.let { SduiFacts(it, lines = 1) }
                        view.text["overview"]?.let { Text(it, color = scheme.onBackground.copy(alpha = 0.86f), fontSize = env.size("body"), maxLines = view.line("overview", 4), overflow = TextOverflow.Ellipsis) }
                        view.progress?.let { SduiProgressLine(it, Modifier.padding(top = env.space("xs")).widthIn(max = env.pt(600))) }
                        Row(Modifier.padding(top = env.space("xs")).remoteRow(), horizontalArrangement = Arrangement.spacedBy(env.pt(16))) {
                            buttons.forEachIndexed { i, button ->
                                val main = button.primary || (i == 0 && buttons.none { it.primary })
                                SduiActionButton(button, focusKey = "${view.id}~${button.id}", requestFocus = main && view.id == env.screen.focus.default)
                            }
                        }
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxWidth()) {
                val compact = p.str("layout") == "compact"
                if (backdrop != null && !compact) {
                    val tall = if (env.tablet) (wide * 9f / 21f) else wide * 9f / 16f
                    Box(Modifier.fillMaxWidth().height(tall)) {
                        SduiPicture(backdrop, wide, wide / tall, null, Modifier.fillMaxSize(), alignment = Alignment.TopCenter)
                        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.5f to Color.Transparent, 1f to page)))
                    }
                } else {
                    Spacer(Modifier.height(LocalTopRoom.current))
                }
                // A tablet has the poster beside the words; so does a phone when the page asks for it or there is no backdrop.
                val showPoster = poster != null && (env.tablet || p.str("layout") == "poster" || backdrop == null || compact)
                Row(Modifier.padding(horizontal = side).padding(top = env.space("s")), horizontalArrangement = Arrangement.spacedBy(env.space("m"))) {
                    if (poster == null && p.str("kind") == "person") PersonInitials(view.text["title"].orEmpty(), if (env.tablet) 160.dp else 104.dp)
                    if (showPoster && poster != null) {
                        val shape = headerShape(poster, p.str("kind"))
                        // An episode's still is wide: it gets the room a poster's height would have had.
                        val posterWide = (if (env.tablet) 160.dp else if (compact) 72.dp else 104.dp) * (if (shape > 1f) 1.6f else 1f)
                        SduiPicture(poster, posterWide, shape, sduiKindIcon(p.str("kind")), Modifier.width(posterWide).aspectRatio(shape).restingShadow(10.dp).clip(RoundedCornerShape(10.dp)))
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
                        SduiLogoOrTitle(view, "pageTitle", wide * 0.7f, view.line("title", 2))
                        view.text["tagline"]?.let { Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("body"), fontStyle = FontStyle.Italic) }
                        view.text["facts"]?.let { SduiFacts(it, lines = 3) }
                    }
                }
                view.progress?.let { SduiProgressLine(it, Modifier.padding(horizontal = side).padding(top = env.space("m"))) }
                val main = buttons.firstOrNull { it.primary }
                val rest = buttons.filter { it !== main }
                if (main != null) SduiActionButton(main, focusKey = "${view.id}~${main.id}", modifier = Modifier.padding(horizontal = side).padding(top = env.space("m")), wide = !env.tablet)
                // The other actions: icons with their names under them, in a row that scrolls when there are many.
                if (rest.isNotEmpty()) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = side).padding(top = env.space("s")), horizontalArrangement = Arrangement.spacedBy(env.space("xs"))) {
                    rest.forEach { button ->
                        Pressable({ env.act(button.action) }, Modifier.widthIn(min = 72.dp).heightIn(min = 56.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = button.label, ring = false) {
                            Column(Modifier.padding(horizontal = 8.dp, vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(sduiIcon(button.icon), null, tint = scheme.onBackground, modifier = Modifier.size(22.dp))
                                Text(button.label, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), maxLines = 1)
                            }
                        }
                    }
                }
                view.text["overview"]?.let { words ->
                    // Four lines, and More to read the rest.
                    var open by rememberSaveable { mutableStateOf(false) }
                    var cut by remember { mutableStateOf(false) }
                    Column(Modifier.padding(horizontal = side).padding(top = env.space("m"))) {
                        Text(
                            words, color = scheme.onBackground.copy(alpha = 0.9f), fontSize = env.size("body"), lineHeight = env.size("body") * 1.45f,
                            maxLines = if (open) Int.MAX_VALUE else view.line("overview", 4), overflow = TextOverflow.Ellipsis, onTextLayout = { if (!open) cut = it.hasVisualOverflow },
                        )
                        if (cut || open) Pressable({ open = !open }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = if (open) "Less" else "More", ring = false) {
                            Box(Modifier.heightIn(min = 44.dp), contentAlignment = Alignment.CenterStart) { Text(if (open) "Less" else "More", color = LocalExtraColours.current.accentText, fontSize = env.size("caption"), fontWeight = FontWeight.SemiBold) }
                        }
                    }
                }
            }
        }
    }
}

// The shape of the picture beside a header's words: what the picture says it is, else its own size, else an episode's
// still is 16:9 (the server sends it as the episode's poster) and anything else a 2:3 poster.
internal fun headerShape(picture: com.wittywilla.wittymediaclient.net.SduiImage, kind: String): Float =
    aspectOf(picture.aspect).takeIf { it > 0f }
        ?: picture.takeIf { it.width > 0 && it.height > 0 }?.let { it.width.toFloat() / it.height }
        ?: if (kind == "episode") 16f / 9f else 2f / 3f

// How far through a title the profile is.
@Composable
private fun SduiProgressLine(percent: Int, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    val high = env.pt(if (env.tv) 8 else 4)
    Box(modifier.fillMaxWidth().height(high).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant).semantics { contentDescription = "$percent percent watched" }) {
        Box(Modifier.fillMaxWidth(percent.coerceIn(0, 100) / 100f).height(high).background(MaterialTheme.colorScheme.primary))
    }
}

// MARK: choosing from a list

// A list to choose one from: a sheet from the foot on a touch screen, a full-height list from the right edge on a TV.
@Composable
fun SduiChooser(title: String, options: List<Pair<String, String>>, current: String, close: () -> Unit, pick: (String) -> Unit) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    if (!env.tv) {
        WebSheet(title, close, fromRight = false) {
            SheetRows(options.map { (label, value) -> SheetRow(label, if (value == current) WebIcons.Check else null) { pick(value) } }, close)
        }
        return
    }
    TvLayer(close) {
      Box(Modifier.fillMaxSize(), contentAlignment = Alignment.CenterEnd) {
        Column(
            Modifier.fillMaxHeight().width(env.pt(640)).background(scheme.surface).padding(horizontal = env.space("m"), vertical = env.pt(env.layout.safeArea.top.coerceAtLeast(60))).focusGroup(),
            verticalArrangement = Arrangement.spacedBy(env.space("xs")),
        ) {
            Text(title, color = scheme.onSurface, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = env.space("s")).semantics { heading() })
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(env.pt(8))) {
                options.forEachIndexed { i, (label, value) ->
                    val on = value == current
                    Pressable(
                        { close(); pick(value) }, Modifier.fillMaxWidth(), shape = Radius.FULL, fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent,
                        label = label, selected = on, takeFocus = on || (i == 0 && options.none { it.second == current }),
                    ) {
                        Row(Modifier.fillMaxWidth().heightIn(min = env.pt(66)).padding(horizontal = env.pt(32)), verticalAlignment = Alignment.CenterVertically) {
                            Text(label, color = scheme.onSurface, fontSize = env.size("body"), modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (on) Icon(WebIcons.Check, null, tint = LocalExtraColours.current.accentText, modifier = Modifier.size(env.pt(32)))
                        }
                    }
                }
            }
        }
      }
    }
}

// A pill that shows a choice and opens the list to change it.
@Composable
private fun SduiChoicePill(words: String, focusKey: String, on: Boolean = false, open: () -> Unit) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    if (env.tv) {
        WittyButton(words, open, kind = if (on) ButtonKind.Primary else ButtonKind.Secondary, pill = true, focusKey = focusKey)
    } else {
        Pressable(open, Modifier.heightIn(min = 44.dp), shape = Radius.FULL, fill = Color.Transparent, label = words, ring = false) {
            Row(
                Modifier.heightIn(min = 36.dp).clip(Radius.FULL).background(if (on) scheme.primary.copy(alpha = 0.14f) else scheme.surfaceVariant).padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(words, color = if (on) LocalExtraColours.current.accentText else scheme.onBackground, fontSize = env.size("caption") * 1.08f, fontWeight = FontWeight.Medium, maxLines = 1)
                Icon(WebIcons.Down, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
            }
        }
    }
}

// MARK: FilterBar

// Filter and sort: Sort first, then each filter showing its choice. A choice asks for the page again with it.
@Composable
fun SduiFilterBar(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val p = view.props
    val sort = p.child("sort")
    val fields = p.objects("fields")
    // Which list is open: "sort", or a field's ID.
    var open by remember { mutableStateOf<String?>(null) }
    // The Dock's Sort and Filter open the choices of the bar that drives the grid (control.open).
    val asked = env.control.value?.takeIf { it.kind == "sort" || it.kind == "filter" }
    if (asked != null) LaunchedEffect(asked) {
        open = if (asked.kind == "sort" && sort != null) "sort" else fields.firstOrNull()?.str("id") ?: if (sort != null) "sort" else null
        env.control.value = null
    }
    Column(Modifier.fillMaxWidth().semantics { contentDescription = view.label }) {
        if (!env.tv) view.text["count"]?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("caption"), modifier = Modifier.padding(horizontal = side).padding(bottom = env.space("xs"))) }
        Row(
            (if (env.tv) Modifier.remoteRow() else Modifier).fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = side),
            horizontalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 16 else 8)), verticalAlignment = Alignment.CenterVertically,
        ) {
            var at = 0
            if (sort != null) {
                SduiChoicePill(view.buttons.getOrNull(at).orEmpty(), view.id + "~sort") { open = "sort" }
                at++
            }
            fields.forEach { field ->
                val id = field.str("id")
                SduiChoicePill(view.buttons.getOrNull(at).orEmpty(), view.id + "~" + id, on = field.str("value").isNotEmpty()) { open = id }
                at++
            }
            if (env.tv) view.text["count"]?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("caption"), modifier = Modifier.padding(start = env.space("s"))) }
        }
    }
    val showing = open ?: return
    if (showing == "sort" && sort != null) {
        SduiChooser("Sort by", sort.objects("options").map { it.str("label") to it.str("value") }, sort.str("value"), { open = null }) { open = null; env.ask(mapOf("sort" to it)) }
    } else {
        val field = fields.firstOrNull { it.str("id") == showing } ?: return
        // "Any" takes the filter away.
        val options = listOf("Any" to "") + field.objects("options").map { it.str("label") to it.str("value") }
        SduiChooser(field.str("label"), options, field.str("value"), { open = null }) { open = null; env.ask(mapOf(showing to it)) }
    }
}

// MARK: Tabs

// A strip of tabs. Only the chosen one came with anything in it; choosing another asks for the page again.
@Composable
fun SduiTabs(view: SduiView, side: Dp, withContent: Boolean) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val accentText = LocalExtraColours.current.accentText
    val segments = view.props.str("style") == "segments"
    Column(Modifier.fillMaxWidth()) {
        Row(
            (if (env.tv) Modifier.remoteRow() else Modifier).fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = side).semantics { role = Role.Tab },
            horizontalArrangement = if (env.tv) Arrangement.spacedBy(env.pt(16), Alignment.CenterHorizontally) else Arrangement.spacedBy(if (segments) 0.dp else 20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val strip = if (segments && !env.tv) Modifier.clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant).padding(2.dp) else Modifier
            Row(strip, horizontalArrangement = if (env.tv) Arrangement.spacedBy(env.pt(16)) else Arrangement.spacedBy(if (segments) 0.dp else 20.dp)) {
                view.children.filter { it.type == "Tab" }.forEach { tab ->
                    val on = tab.props.isOn("selected")
                    val words = tab.text["title"].orEmpty()
                    when {
                        // A TV's are pills, centred above what they show.
                        // Chosen as focus rests on it, as Android TV's tabs are: after a moment, so passing over one on the way
                        // to another doesn't ask the server for each page between.
                        env.tv -> Pressable({ if (!on) env.act(tab.node.action) }, Modifier.chooseOnRest(on) { env.act(tab.node.action) }, shape = Radius.FULL, fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent, label = words, selected = on, state = if (on) "Selected" else null, focusKey = tab.id) {
                            Box(Modifier.heightIn(min = env.pt(66)).padding(horizontal = env.pt(32)), contentAlignment = Alignment.Center) { Text(words, color = if (on) accentText else scheme.onSurfaceVariant, fontSize = env.size("body"), fontWeight = FontWeight.Medium, maxLines = 1) }
                        }
                        // Views of the same thing: a segmented control.
                        segments -> Pressable({ env.act(tab.node.action) }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(8.dp), fill = if (on) scheme.background else Color.Transparent, label = words, selected = on, state = if (on) "Selected" else null, ring = false) {
                            Box(Modifier.heightIn(min = 40.dp).padding(horizontal = 18.dp), contentAlignment = Alignment.Center) { Text(words, color = if (on) scheme.onBackground else scheme.onSurfaceVariant, fontSize = env.size("caption") * 1.08f, fontWeight = FontWeight.SemiBold, maxLines = 1) }
                        }
                        // Sections of a page: words with a line under the chosen one.
                        else -> Pressable({ env.act(tab.node.action) }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(0.dp), fill = Color.Transparent, label = words, selected = on, state = if (on) "Selected" else null, ring = false) {
                            Box(
                                Modifier.heightIn(min = 44.dp).drawBehind { if (on) drawRect(accentText, Offset(0f, size.height - 2.dp.toPx()), Size(size.width, 2.dp.toPx())) },
                                contentAlignment = Alignment.Center,
                            ) { Text(words, color = if (on) scheme.onBackground else scheme.onSurfaceVariant, fontSize = env.size("body"), fontWeight = FontWeight.Bold, maxLines = 1) }
                        }
                    }
                }
            }
        }
        if (withContent) view.children.forEach { tab -> tab.children.forEach { Box(Modifier.padding(top = env.pt(env.layout.sectionGap))) { SduiNode(it, tab) } } }
    }
}

// Calls choose once focus has rested on something not yet chosen for a moment.
@Composable
private fun Modifier.chooseOnRest(chosen: Boolean, choose: () -> Unit): Modifier {
    var focused by remember { mutableStateOf(false) }
    val latest by androidx.compose.runtime.rememberUpdatedState(choose)
    LaunchedEffect(focused, chosen) {
        if (!focused || chosen) return@LaunchedEffect
        kotlinx.coroutines.delay(TAB_REST_MS)
        latest()
    }
    return onFocusChanged { focused = it.isFocused }
}

private const val TAB_REST_MS = 400L

// MARK: SeasonList

private fun seasonOptions(view: SduiView): List<Triple<String, String, Boolean>> =
    view.props.objects("seasons").map { Triple(it.str("title"), it.str("url"), it.isOn("selected")) }

// A phone's: "Episodes", and a button that names the season and opens the list of them.
@Composable
private fun SduiSeasonHead(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val seasons = seasonOptions(view)
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = side).padding(bottom = env.space("xs")), verticalAlignment = Alignment.CenterVertically) {
        Text(view.props.str("title").ifEmpty { "Episodes" }, color = MaterialTheme.colorScheme.onBackground, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).semantics { heading() })
        val current = seasons.firstOrNull { it.third }
        if (current != null && seasons.size > 1) SduiChoicePill(current.first, view.id + "~season") { open = true }
        else if (current != null) Text(current.first, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("caption"))
    }
    if (open) SduiChooser("Season", seasons.map { it.first to it.second }, seasons.firstOrNull { it.third }?.second.orEmpty(), { open = false }) { url -> open = false; env.season(view.id, url) }
}

// A TV's: a row of season pills, then the episodes as a row of cards. A phone's that has nothing to list yet says why.
@Composable
fun SduiSeasons(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    if (!env.tv) {
        Column(Modifier.fillMaxWidth()) {
            SduiSeasonHead(view, side)
            when {
                view.deferred -> { LaunchedEffect(view.id) { env.more(view.id, false) }; SduiPlaceholderRow(view, side, 3) }
                view.failed -> SduiFailedLine(view, side)
                else -> SduiEmptyLine(view, side)
            }
        }
        return
    }
    val seasons = seasonOptions(view)
    Column(Modifier.fillMaxWidth()) {
        Text(view.props.str("title").ifEmpty { "Episodes" }, color = scheme.onBackground, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = side).padding(bottom = env.space("xs")).semantics { heading() })
        if (seasons.size > 1) Row(Modifier.remoteRow().fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = side).padding(bottom = env.space("xs")), horizontalArrangement = Arrangement.spacedBy(env.pt(16))) {
            seasons.forEachIndexed { i, (title, url, on) ->
                Pressable({ if (!on) env.season(view.id, url) }, shape = Radius.FULL, fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent, label = title, selected = on, state = if (on) "Selected" else null, focusKey = view.id + "~season~" + i) {
                    Box(Modifier.heightIn(min = env.pt(66)).padding(horizontal = env.pt(32)), contentAlignment = Alignment.Center) { Text(title, color = if (on) LocalExtraColours.current.accentText else scheme.onSurfaceVariant, fontSize = env.size("body"), fontWeight = FontWeight.Medium, maxLines = 1) }
                }
            }
        }
        when {
            view.deferred -> { LaunchedEffect(view.id) { env.more(view.id, false) }; SduiPlaceholderRow(view, side, 4) }
            view.failed -> SduiFailedLine(view, side)
            view.children.isEmpty() -> SduiEmptyLine(view, side)
            else -> {
                val state = rememberLazyListState()
                val wide = env.pt(view.cardWidth.takeIf { it > 0 } ?: 420)
                val ring = LocalMetrics.current.focusRing
                val nearEnd by remember(view.children.size) { derivedStateOf { (state.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0) >= view.children.size - 3 } }
                if (view.hasMore && nearEnd) LaunchedEffect(view.children.size) { env.more(view.id, false) }
                SduiRowScroll {
                    LazyRow(Modifier.remoteRow().fillMaxWidth(), state = state, contentPadding = PaddingValues(horizontal = side - ring, vertical = env.pt(12)), horizontalArrangement = Arrangement.spacedBy(env.pt(env.layout.cardGap) - ring * 2)) {
                        items(view.children, key = { it.id }) { SduiCard(it, view, wide) }
                    }
                }
            }
        }
    }
}

// MARK: rows of a list

// One row of a list, a track list, or a phone's episodes.
@Composable
fun SduiLine(view: SduiView, parent: SduiView) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val p = view.props
    val focusKey = view.id.takeIf { env.tv }
    val start = env.tv && view.id == env.screen.focus.default
    val press = view.node.action != null
    when (view.type) {
        "Track" -> {
            // What the app is playing now is in the accent's colour.
            val playing = env.nav.app.listening.now?.mediaId == p.str("itemId")
            val ink = if (playing) LocalExtraColours.current.accentText else scheme.onBackground
            Pressable({ env.act(view.node.action) }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(env.pt(10)), fill = Color.Transparent, label = view.label, enabled = press, disabledAlpha = 1f, focusKey = focusKey, requestFocus = start, ring = env.tv, pressScale = 1f) {
                Column(Modifier.fillMaxWidth().clearAndSetSemantics { }) {
                    Row(Modifier.fillMaxWidth().heightIn(min = env.pt(if (env.tv) 90 else 56)).padding(horizontal = env.pt(if (env.tv) 24 else 4)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
                        if (parent.props["showNumbers"]?.toString() != "false") Text(p.int("number")?.toString().orEmpty(), color = if (playing) ink else hint, fontSize = env.size("body"), textAlign = TextAlign.End, modifier = Modifier.width(env.pt(if (env.tv) 56 else 28)))
                        Column(Modifier.weight(1f)) {
                            Text(view.text["title"].orEmpty(), color = ink, fontSize = env.size("body"), maxLines = view.line("title", 1), overflow = TextOverflow.Ellipsis)
                            view.text["subtitle"]?.let { Text(it, color = hint, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                        }
                        view.text["duration"]?.let { Text(it, color = hint, fontSize = env.size("caption")) }
                    }
                    view.progress?.takeIf { it in 1..99 }?.let { SduiProgressLine(it) }
                }
            }
        }
        "Card" -> {
            // An episode on a phone: its still at the left with how far through it is, then its name, length and synopsis.
            val still = env.pt(if (env.tablet) 200 else 136)
            Pressable({ env.act(view.node.action) }, Modifier.fillMaxWidth().padding(vertical = env.space("xs")), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = view.label, enabled = press, disabledAlpha = 1f, ring = false, pressScale = 0.99f) {
                Row(Modifier.fillMaxWidth().clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
                    Box(Modifier.width(still).aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)) {
                        SduiPicture(p.image("image"), still, 16f / 9f, sduiKindIcon(p.str("kind")), Modifier.fillMaxSize())
                        if ("watched" in view.shows) Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(20.dp).clip(CircleShape).background(Color(0xAD000000)), contentAlignment = Alignment.Center) { Icon(WebIcons.Check, null, tint = Color.White, modifier = Modifier.size(14.dp)) }
                        view.progress?.let { percent ->
                            Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(3.dp).background(Color(0x47FFFFFF))) { Box(Modifier.fillMaxWidth(percent.coerceIn(0, 100) / 100f).height(3.dp).background(scheme.primary)) }
                        }
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        view.text["title"]?.let { Text(it, color = scheme.onBackground, fontSize = env.size("caption") * 1.08f, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                        view.text["subtitle"]?.let { Text(it, color = hint, fontSize = env.size("caption"), maxLines = view.line("subtitle", 1), overflow = TextOverflow.Ellipsis) }
                        view.text["synopsis"]?.let { Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), maxLines = view.line("synopsis", 2), overflow = TextOverflow.Ellipsis) }
                    }
                }
            }
        }
        else -> {
            val control = SduiControlSpec.of(p)
            if (control != null) {
                SduiControlLine(view, control)
                return
            }
            val image = p.image("image")
            val dense = parent.props.isOn("dense")
            // A row that does nothing is words to read, not a stop for a remote.
            Pressable({ env.act(view.node.action) }, Modifier.fillMaxWidth().focusProperties { canFocus = press }, shape = RoundedCornerShape(env.pt(10)), fill = Color.Transparent, label = view.label, enabled = press, disabledAlpha = 1f, focusKey = focusKey, requestFocus = start, ring = env.tv && press, pressScale = 1f) {
                Row(Modifier.fillMaxWidth().heightIn(min = env.pt(if (env.tv) 90 else if (dense) 44 else 56)).padding(horizontal = env.pt(if (env.tv) 24 else 4)).clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
                    val box = env.pt(if (env.tv) 66 else if (dense) 28 else 40)
                    if (image != null) SduiPicture(image, box, 1f, null, Modifier.size(box).clip(RoundedCornerShape(env.pt(6))))
                    else if (p.str("icon").isNotEmpty()) Icon(sduiIcon(p.str("icon")), null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(env.pt(if (env.tv) 40 else 22)))
                    Column(Modifier.weight(1f)) {
                        Text(view.text["title"].orEmpty(), color = scheme.onBackground, fontSize = env.size("body"), maxLines = view.line("title", 1), overflow = TextOverflow.Ellipsis)
                        view.text["subtitle"]?.let { Text(it, color = hint, fontSize = env.size("caption"), maxLines = view.line("subtitle", 1), overflow = TextOverflow.Ellipsis) }
                    }
                    view.text["trailing"]?.let { Text(it, color = hint, fontSize = env.size("caption"), maxLines = 1) }
                    if (press) Icon(WebIcons.Right, null, tint = hint, modifier = Modifier.size(env.pt(if (env.tv) 32 else 16)))
                }
            }
        }
    }
}

// MARK: Banner, Notice, Text

@Composable
fun SduiBanner(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val p = view.props
    val image = p.image("image")
    val span = LocalSduiSpan.current
    val compact = p.str("style") == "compact"
    val press = view.node.action != null
    val corner = RoundedCornerShape(env.pt(14))
    val wide = span.content
    // The whole banner is the button: one stop for a remote, one target for a finger.
    Pressable(
        { env.act(view.node.action) }, Modifier.padding(horizontal = (side - if (env.tv) LocalMetrics.current.focusRing else 0.dp).coerceAtLeast(0.dp)).fillMaxWidth(), shape = corner,
        fill = scheme.surface, label = view.label, enabled = press, disabledAlpha = 1f, focusKey = view.id.takeIf { env.tv }, requestFocus = env.tv && view.id == env.screen.focus.default,
        ring = env.tv, pressScale = 0.99f, grows = false,
    ) {
        if (compact && !env.tv) {
            Row(Modifier.fillMaxWidth().heightIn(min = 96.dp).border(1.dp, scheme.outline, corner).padding(12.dp).clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (image != null) SduiPicture(image, 72.dp, 1f, null, Modifier.size(72.dp).clip(RoundedCornerShape(10.dp)))
                else if (p.str("icon").isNotEmpty()) Icon(sduiIcon(p.str("icon")), null, tint = extra.accentText, modifier = Modifier.size(32.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    view.text["title"]?.let { Text(it, color = scheme.onBackground, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, maxLines = view.line("title", 2), overflow = TextOverflow.Ellipsis) }
                    view.text["text"]?.let { Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), maxLines = view.line("text", 2), overflow = TextOverflow.Ellipsis) }
                }
                view.text["button"]?.let { Text(it, color = extra.accentText, fontSize = env.size("caption"), fontWeight = FontWeight.SemiBold, maxLines = 1) }
            }
        } else {
            val tall = if (env.tv) env.pt(300) else if (env.tablet) wide * 9f / 21f else wide * 9f / 16f
            Box(Modifier.fillMaxWidth().height(tall).clearAndSetSemantics { }) {
                if (image != null) {
                    SduiPicture(image, wide, wide / tall, null, Modifier.fillMaxSize())
                    Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(0f to scheme.surface.copy(alpha = 0.92f), 0.7f to scheme.surface.copy(alpha = 0.25f))))
                } else {
                    Box(Modifier.fillMaxSize().border(1.dp, scheme.outline, corner))
                }
                Column(Modifier.align(Alignment.BottomStart).padding(env.pt(if (env.tv) 40 else 16)).fillMaxWidth(if (env.tv) 0.6f else 0.9f), verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
                    if (image == null && p.str("icon").isNotEmpty()) Icon(sduiIcon(p.str("icon")), null, tint = extra.accentText, modifier = Modifier.size(env.pt(if (env.tv) 56 else 28)))
                    view.text["title"]?.let { Text(it, color = scheme.onSurface, fontSize = env.size(if (env.tv) "heading" else "heading"), fontWeight = FontWeight.SemiBold, maxLines = view.line("title", 2), overflow = TextOverflow.Ellipsis) }
                    view.text["text"]?.let { Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("body"), maxLines = view.line("text", 2), overflow = TextOverflow.Ellipsis) }
                    view.text["button"]?.let {
                        Box(Modifier.padding(top = env.space("xs")).clip(Radius.FULL).background(scheme.primary).heightIn(min = env.pt(if (env.tv) 56 else 36)).padding(horizontal = env.pt(if (env.tv) 28 else 16)), contentAlignment = Alignment.Center) {
                            Text(it, color = scheme.onPrimary, fontSize = env.size(if (env.tv) "body" else "caption") * (if (env.tv) 1f else 1.08f), fontWeight = FontWeight.SemiBold, maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SduiNotice(view: SduiView, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val p = view.props
    val tone = when (p.str("tone")) { "success" -> extra.ok; "warning" -> extra.warn; "danger" -> scheme.error; else -> scheme.primary }
    val icon = p.str("icon").ifEmpty { when (p.str("tone")) { "warning", "danger" -> "warning"; "success" -> "check"; else -> "info" } }
    val button = view.text["button"]
    val corner = RoundedCornerShape(env.pt(14))
    @Composable
    fun words(modifier: Modifier) = Column(modifier, verticalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 6 else 2))) {
        view.text["title"]?.let { Text(it, color = scheme.onSurface, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold) }
        view.text["text"]?.let { Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("body")) }
    }
    @Composable
    fun press() {
        if (button == null) return
        if (env.tv) WittyButton(button, { env.act(view.node.action) }, kind = ButtonKind.Primary, pill = true, focusKey = view.id, requestFocus = view.id == env.screen.focus.default)
        else WebButton(button, { env.act(view.node.action) }, WebButtonKind.Primary, small = true)
    }
    Row(
        modifier.fillMaxWidth().clip(corner).background(scheme.surface).height(IntrinsicSize.Min).semantics { contentDescription = view.label },
    ) {
        // The bar at its leading edge, in the tone's colour.
        Box(Modifier.width(env.pt(if (env.tv) 8 else 4)).fillMaxHeight().background(tone))
        Row(Modifier.weight(1f).padding(env.pt(if (env.tv) 32 else 14)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
            Icon(sduiIcon(icon), null, tint = tone, modifier = Modifier.size(env.pt(if (env.tv) 48 else 22)))
            // The button is at the end, and under the words on a phone.
            if (env.tv || env.tablet) {
                words(Modifier.weight(1f))
                press()
            } else {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(env.space("s"))) {
                    words(Modifier)
                    press()
                }
            }
        }
    }
}

private fun textAlignOf(name: String): TextAlign = when (name) { "center" -> TextAlign.Center; "end" -> TextAlign.End; else -> TextAlign.Start }

// A heading or a block of text, plain or in the small Markdown subset. Links are to places in the app or to a web page.
@Composable
fun SduiTextBlock(view: SduiView, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val accentText = LocalExtraColours.current.accentText
    val p = view.props
    val role = p.str("role").ifEmpty { "body" }
    val words = view.text["text"].orEmpty()
    val colour = if (role == "caption") scheme.onSurfaceVariant else scheme.onBackground
    val weight = when (role) { "pageTitle" -> FontWeight.Bold; "heading", "title" -> FontWeight.SemiBold; else -> FontWeight.Normal }
    val align = textAlignOf(p.str("align"))
    val lines = view.lines["text"] ?: Int.MAX_VALUE
    val heading = view.role.startsWith("heading")
    val shape = modifier.fillMaxWidth().then(if (heading) Modifier.semantics { heading() } else Modifier)
    val size = env.size(role)
    if (p.str("format") != "markdown") {
        // Body text is at most 70 characters wide: about 35 times its own size.
        Text(words, color = colour, fontSize = size, fontWeight = weight, textAlign = align, maxLines = lines, overflow = TextOverflow.Ellipsis, lineHeight = size * 1.4f, modifier = if (role == "body" && align == TextAlign.Start) shape.widthIn(max = (size.value * 35 / (if (env.tv) 1f else 1f)).dp) else shape)
        return
    }
    val blocks = remember(words) { SduiMarkdown.blocks(words) }
    fun spans(block: SduiMarkdown.Block, lead: String = ""): AnnotatedString = buildAnnotatedString {
        append(lead)
        block.spans.forEach { span ->
            val style = SpanStyle(fontWeight = if (span.bold) FontWeight.Bold else null, fontStyle = if (span.italic) FontStyle.Italic else null, fontFamily = if (span.code) FontFamily.Monospace else null)
            // A link takes focus on a TV only by being pressed with the page's other things; everywhere it opens a route or a web page.
            if (span.link.isNotEmpty() && (span.link.startsWith("/") || env.layout.externalLinks)) {
                val action = if (span.link.startsWith("/")) SduiAction(type = "navigate", to = span.link) else SduiAction(type = "external", url = span.link)
                withLink(LinkAnnotation.Clickable(span.link, linkInteractionListener = { env.act(action) })) {
                    withStyle(style.copy(color = accentText, textDecoration = TextDecoration.Underline)) { append(span.text) }
                }
            } else withStyle(style) { append(span.text) }
        }
    }
    Column(shape.semantics(mergeDescendants = true) { contentDescription = view.label }, verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
        blocks.forEach { block ->
            when (block) {
                is SduiMarkdown.Heading -> {
                    val headingSize = env.size(when (block.level) { 1 -> "pageTitle"; 2 -> "heading"; else -> "title" })
                    Text(spans(block), color = scheme.onBackground, fontSize = headingSize, fontWeight = FontWeight.SemiBold, textAlign = align, lineHeight = headingSize * 1.25f, modifier = Modifier.fillMaxWidth().semantics { heading() })
                }
                is SduiMarkdown.Item -> Text(spans(block, if (block.number > 0) "${block.number}. " else "•  "), color = colour, fontSize = size, textAlign = align, lineHeight = size * 1.4f, modifier = Modifier.fillMaxWidth().padding(start = env.space("xs")))
                is SduiMarkdown.Paragraph -> Text(spans(block), color = colour, fontSize = size, fontWeight = weight, textAlign = align, maxLines = lines, overflow = TextOverflow.Ellipsis, lineHeight = size * 1.4f, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

// MARK: layout components

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SduiStack(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val p = view.props
    val gap = env.space(p.str("gap").ifEmpty { "m" })
    val align = p.str("align")
    if (p.str("direction") == "row") {
        val across = when (align) { "center" -> Alignment.CenterVertically; "end" -> Alignment.Bottom; else -> Alignment.Top }
        // A row of buttons is one group for a remote: left and right stay in it, and coming back lands where it was left.
        val group = if (env.tv && view.children.any { it.node.focus != null }) Modifier.remoteRow() else Modifier
        if (p["wrap"]?.toString() != "false") FlowRow(group.fillMaxWidth().padding(horizontal = side), horizontalArrangement = Arrangement.spacedBy(gap), verticalArrangement = Arrangement.spacedBy(gap), itemVerticalAlignment = across) { view.children.forEach { SduiNode(it, view) } }
        else Row(group.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = side), horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = across) { view.children.forEach { SduiNode(it, view) } }
    } else {
        val across = when (align) { "start" -> Alignment.Start; "center" -> Alignment.CenterHorizontally; "end" -> Alignment.End; else -> Alignment.Start }
        Column(Modifier.fillMaxWidth().padding(horizontal = side), verticalArrangement = Arrangement.spacedBy(gap), horizontalAlignment = across) { view.children.forEach { SduiNode(it, view) } }
    }
}

private val BREAKPOINTS = listOf("compact", "medium", "expanded", "large")

// Two things side by side on a wide screen, one above the other on a narrow one.
@Composable
private fun SduiSplit(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val p = view.props
    val gap = env.space(p.str("gap").ifEmpty { "m" })
    val below = p.str("stackBelow").ifEmpty { "medium" }
    val beside = env.tv || (env.layout.formFactor != "phone" && BREAKPOINTS.indexOf(env.layout.breakpoint) >= BREAKPOINTS.indexOf(below))
    val (a, b) = p.str("ratio").split(':').let { (it.getOrNull(0)?.toFloatOrNull() ?: 1f) to (it.getOrNull(1)?.toFloatOrNull() ?: 1f) }
    if (beside) Row(Modifier.fillMaxWidth().padding(horizontal = side), horizontalArrangement = Arrangement.spacedBy(gap)) {
        view.children.forEachIndexed { i, child -> Box(Modifier.weight(if (i == 0) a else b)) { SduiNode(child, view) } }
    } else Column(Modifier.fillMaxWidth().padding(horizontal = side), verticalArrangement = Arrangement.spacedBy(gap)) { view.children.forEach { SduiNode(it, view) } }
}

@Composable
private fun SduiButtonView(view: SduiView) {
    val env = LocalSdui.current
    val p = view.props
    val icon = p.str("icon").takeIf { it.isNotEmpty() }?.let(::sduiIcon)
    val words = view.text["title"].orEmpty()
    val variant = p.str("variant")
    if (env.tv) WittyButton(words, { env.act(view.node.action) }, kind = when (variant) { "primary" -> ButtonKind.Primary; "ghost" -> ButtonKind.Quiet; else -> ButtonKind.Secondary }, icon = icon, pill = true, focusKey = view.id, requestFocus = view.id == env.screen.focus.default)
    else WebButton(words, { env.act(view.node.action) }, when (variant) { "primary" -> WebButtonKind.Primary; "ghost" -> WebButtonKind.Ghost; else -> WebButtonKind.Secondary }, icon)
}

@Composable
private fun SduiImageBlock(view: SduiView, modifier: Modifier) {
    val env = LocalSdui.current
    val p = view.props
    val image = p.image("image")
    val aspect = aspectOf(p.str("aspect").ifEmpty { image?.aspect.orEmpty() }).takeIf { it > 0f } ?: (16f / 9f)
    val span = LocalSduiSpan.current
    // At the content's width, and never more than 960 points.
    val wide = minOf(span.content, env.pt(960))
    val corner = RoundedCornerShape(if (p["rounded"]?.toString() == "false") 0.dp else env.pt(14))
    val alt = view.label
    val picture = @Composable {
        SduiPicture(image, wide, aspect, null, Modifier.width(wide).aspectRatio(aspect).clip(corner).then(if (alt.isNotEmpty()) Modifier.semantics { contentDescription = alt; role = Role.Image } else Modifier.clearAndSetSemantics { }), contain = p.str("fit") == "contain")
    }
    Box(modifier) {
        if (view.node.action != null) Pressable({ env.act(view.node.action) }, shape = corner, label = alt.ifEmpty { "Open" }, focusKey = view.id.takeIf { env.tv }, ring = env.tv, grows = false) { picture() }
        else picture()
    }
}

// MARK: SearchBox

private const val SEARCH_WAIT_MS = 300L

// The field a search is typed into. On the search page it holds the search, and asks for the page again a moment
// after the last keystroke; anywhere else it opens the search page.
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SduiSearchBox(view: SduiView, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val p = view.props
    val here = env.screen.document.page.kind == "search"
    val prompt = view.text["placeholder"].orEmpty().ifEmpty { "Search" }
    if (!here) {
        Pressable({ env.act(view.node.action) }, modifier.fillMaxWidth().widthIn(max = env.pt(560)), shape = RoundedCornerShape(env.pt(10)), fill = scheme.surfaceVariant, label = "Search, $prompt", focusKey = view.id.takeIf { env.tv }, ring = env.tv) {
            Row(Modifier.fillMaxWidth().heightIn(min = env.pt(if (env.tv) 66 else 48)).padding(horizontal = env.space("s")), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("xs"))) {
                Icon(WebIcons.Search, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(env.pt(if (env.tv) 36 else 20)))
                Text(prompt, color = scheme.onSurfaceVariant, fontSize = env.size("body"), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        return
    }
    var text by rememberSaveable { mutableStateOf(p.str("query")) }
    val requester = remember { FocusRequester() }
    LaunchedEffect(text) {
        val wanted = text.trim()
        if (wanted == env.params["q"].orEmpty()) return@LaunchedEffect
        delay(SEARCH_WAIT_MS)
        env.ask(mapOf("q" to wanted))
    }
    // Focus starts here when the page says so: at once on a TV, and on a touch screen only before anything was searched
    // for, so coming back to results doesn't bring the keyboard up over them.
    if (p.isOn("autofocus") && (env.tv || text.isEmpty())) LaunchedEffect(Unit) { runCatching { requester.requestFocus() } }
    OutlinedTextField(
        value = text, onValueChange = { text = it }, label = { Text(prompt, maxLines = 1, overflow = TextOverflow.Ellipsis) }, singleLine = true,
        leadingIcon = { Icon(WebIcons.Search, null, modifier = Modifier.size(20.dp)) },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrectEnabled = false),
        modifier = modifier.fillMaxWidth().widthIn(max = if (env.tv) env.pt(1200) else 560.dp).focusRequester(requester).tvLeavable().semantics { contentDescription = view.label },
    )
}

// MARK: Credits

// Cast and crew (docs/SDUI.md, Credits; Design 2's item page): the cast as a row of round portraits with the part each
// played (initials without a photo), ending in "Show all cast"; then the crew as one row of "Job · Name" chips ending in
// "Show all credits". Either asks for the rest (props.more.url) and the section becomes "Cast and crew by department":
// the cast, the guest stars, then each department as a heading and its chips. Each person opens their page. On a TV the
// chip rows scroll sideways under focus; on a phone and tablet they wrap.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SduiCredits(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val groups = view.props.objects("groups")
    var expanded by rememberSaveable(view.id) { mutableStateOf(false) }
    val more = view.props.child("more")
    fun showAll() {
        expanded = true
        if (view.hasMore) env.more(view.id, true)
    }
    @Composable
    fun Heading(words: String, top: Dp) = Text(
        words, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = side).padding(top = top, bottom = env.space("xs")).semantics { heading() },
    )
    @Composable
    fun Chip(words: String, spoken: String, key: String, onClick: () -> Unit) = Pressable(
        onClick, shape = Radius.FULL, fill = scheme.surface, label = spoken, focusKey = key.takeIf { env.tv }, ring = env.tv,
    ) {
        Text(words, color = scheme.onBackground, fontSize = env.size("body"), maxLines = 1, modifier = Modifier.padding(horizontal = if (env.tv) env.pt(24) else 12.dp, vertical = if (env.tv) env.pt(12) else 8.dp))
    }
    @Composable
    fun Chips(label: String, content: @Composable () -> Unit) {
        if (env.tv) SduiRowScroll {
            Row(Modifier.remoteRow().fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = side).semantics { contentDescription = label }, horizontalArrangement = Arrangement.spacedBy(env.pt(16))) { content() }
        } else FlowRow(
            Modifier.fillMaxWidth().padding(horizontal = side).semantics { contentDescription = label },
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
        ) { content() }
    }
    @Composable
    fun Person(person: SduiView, withJob: Boolean) {
        val name = person.props.str("title")
        val job = person.props.str("subtitle")
        val words = if (withJob && job.isNotEmpty()) "$job · $name" else name
        Chip(words, if (job.isEmpty()) name else "$name, $job", person.id) { env.act(person.node.action) }
    }
    @Composable
    fun Portraits(people: List<SduiView>, label: String, tail: String?) {
        val wide = env.pt(view.cardWidth.takeIf { it > 0 } ?: 140)
        val ring = if (env.tv) LocalMetrics.current.focusRing else 0.dp
        SduiRowScroll { LazyRow(
            (if (env.tv) Modifier.remoteRow() else Modifier).fillMaxWidth().semantics { contentDescription = label },
            contentPadding = PaddingValues(start = (side - ring).coerceAtLeast(0.dp), end = (side - ring).coerceAtLeast(0.dp), top = if (env.tv) env.pt(12) else 0.dp, bottom = if (env.tv) env.pt(12) else 0.dp),
            horizontalArrangement = Arrangement.spacedBy((env.pt(if (env.tv) 40 else env.layout.cardGap) - ring * 2).coerceAtLeast(0.dp)),
        ) {
            items(people, key = { it.id }, contentType = { "person" }) { person -> SduiCard(person, view, wide) }
            if (tail != null) item(key = "~show-all-cast", contentType = "show-all") {
                Pressable(::showAll, Modifier.width(wide), shape = CircleShape, fill = scheme.surface, label = tail, focusKey = view.id + "~show-all-cast") {
                    Box(Modifier.size(wide), contentAlignment = Alignment.Center) { Text(tail, color = scheme.onSurface, fontSize = env.size("caption"), fontWeight = FontWeight.Medium, textAlign = TextAlign.Center, modifier = Modifier.padding(8.dp)) }
                }
            }
        } }
    }

    Column(Modifier.fillMaxWidth().semantics { contentDescription = view.label.ifEmpty { "Cast and crew" } }) {
        val title = if (expanded) "Cast and crew by department" else view.props.str("title").ifEmpty { "Cast and crew" }
        Text(title, color = scheme.onBackground, fontSize = env.size("heading"), fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = side).padding(bottom = env.space("xs")).semantics { heading() })
        when {
            view.deferred -> {
                LaunchedEffect(view.id) { env.more(view.id, false) }
                SduiPlaceholderRow(view, side, view.placeholders)
            }
            view.failed -> SduiFailedLine(view, side)
            view.empty || view.children.isEmpty() -> SduiEmptyLine(view, side)
            else -> {
                val byGroup = view.children.groupBy { it.props.str("group") }
                val order = groups.map { it.str("id") }.ifEmpty { byGroup.keys.toList() }
                fun isCast(id: String) = groups.firstOrNull { it.str("id") == id }?.str("role")?.let { it == "cast" || it == "guests" } ?: (id == "cast" || id == "guests")
                fun labelOf(id: String) = groups.firstOrNull { it.str("id") == id }?.str("label").orEmpty().ifEmpty { id.replaceFirstChar { it.uppercase() } }
                val cast = byGroup["cast"].orEmpty()
                val crewIds = order.filter { !isCast(it) && byGroup[it].orEmpty().isNotEmpty() }
                if (!expanded) {
                    if (cast.isNotEmpty()) Portraits(cast, "Cast", if (view.hasMore) "Show all cast" else null)
                    val crew = crewIds.flatMap { byGroup[it].orEmpty() }
                    if (crew.isNotEmpty() || view.hasMore || byGroup.keys.any { it != "cast" }) {
                        Heading("Crew", env.space("s"))
                        Chips("Crew") {
                            crew.forEach { Person(it, withJob = true) }
                            val words = more?.str("label").orEmpty().ifEmpty { "Show all" }.let { if (it == "Show all") "Show all credits" else it }
                            Chip(words, words, view.id + "~show-all") { showAll() }
                        }
                    }
                } else {
                    var first = true
                    order.forEach { id ->
                        val people = byGroup[id].orEmpty()
                        if (people.isEmpty()) return@forEach
                        if (isCast(id)) {
                            Heading(labelOf(id), if (first) 0.dp else env.space("s"))
                            Portraits(people, labelOf(id), null)
                        } else {
                            Heading(labelOf(id), if (first) 0.dp else env.space("s"))
                            Chips(labelOf(id)) { people.forEach { Person(it, withJob = true) } }
                        }
                        first = false
                    }
                    if (view.id in env.loading) SduiPlaceholderRow(view, side, 3)
                }
            }
        }
    }
}

// A person without a photo, on their own page: their initials in a circle on the page's third background, hidden from
// assistive technology (their name is read as the page's title).
@Composable
private fun PersonInitials(name: String, size: Dp) {
    val env = LocalSdui.current
    Box(Modifier.size(size).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        Text(initials(name), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("pageTitle"), fontWeight = FontWeight.SemiBold)
    }
}
