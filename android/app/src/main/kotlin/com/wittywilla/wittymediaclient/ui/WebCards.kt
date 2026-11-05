package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Show

// The website's cards at phone width (web/src/ui/Surface.tsx, components/common.tsx, styles.css): posters 104 wide
// (148 on a wider screen), landscape cards for episodes, the placeholder made from the title's colour, the hub
// heads and the sideways rows.

// The page's own sizes, by the website's breakpoints.
// In a grid a card takes its column's width instead.
val LocalCardFill = androidx.compose.runtime.compositionLocalOf<Dp?> { null }

@Composable
fun CardWidth(content: @Composable () -> Unit) {
    BoxWithConstraints { androidx.compose.runtime.CompositionLocalProvider(LocalCardFill provides maxWidth) { content() } }
}

@Composable
fun cardWidth(wide: Boolean = false): Dp {
    LocalCardFill.current?.let { return it }
    val w = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp
    return if (wide) (if (w <= 520) 232.dp else 260.dp) else (if (w <= 520) 104.dp else 148.dp)
}

// Words on artwork and the e-1 shadow under resting artwork.
private val ON_IMAGE = Color.White
fun Modifier.restingShadow(radius: Dp): Modifier =
    this.cssShadow(1.dp, 2.dp, Color(0x29000000), radius).cssShadow(2.dp, 8.dp, Color(0x24000000), radius)

// No artwork: the card colour at the top, the title's colour from 64% down, and the title in white at the foot,
// unless the picture is 72 wide or less.
@Composable
fun Placeholder(title: String, modifier: Modifier = Modifier, centred: Boolean = true) {
    val card = MaterialTheme.colorScheme.surfaceVariant
    val colour = Color(avatarColour(title))
    BoxWithConstraints(modifier.background(Brush.verticalGradient(0f to card, 0.64f to colour, 1f to colour))) {
        if (maxWidth > 72.dp) {
            Box(Modifier.fillMaxSize().padding(12.dp), contentAlignment = if (centred) Alignment.BottomCenter else Alignment.BottomStart) {
                Text(title, color = ON_IMAGE, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, lineHeight = 20.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

// A picture from the server over its placeholder, which shows while it loads or if there is none.
@Composable
fun WebArt(url: String?, title: String, widthDp: Dp, aspect: Float, modifier: Modifier = Modifier, centred: Boolean = true, placeholderless: Boolean = false) {
    val context = LocalContext.current
    val px = with(LocalDensity.current) { widthDp.toPx() }.toInt().coerceAtLeast(1)
    var failed by remember(url) { mutableStateOf(false) }
    Box(modifier) {
        if (!placeholderless) Placeholder(title, Modifier.fillMaxSize(), centred)
        if (url != null && !failed) {
            val request = remember(url, px) { ImageRequest.Builder(context).data(url).size(px, (px / aspect).toInt().coerceAtLeast(1)).build() }
            AsyncImage(request, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(), onError = { failed = true })
        }
    }
}

// The hairline over artwork: white at 8%, inside the corner.
private fun Modifier.artHairline(radius: Dp): Modifier = this.border(1.dp, Color(0x14FFFFFF), RoundedCornerShape(radius))

// A plate on a card's picture (`.badge`), 20 high in 11 bold, 8 in from the corner: the kind of disc in white on the
// scrim at the left; how many episodes are left in onAccent on the accent, or a tick in a round scrim once it's all
// watched, at the right.
@Composable
private fun BoxScope.Plates(badges: List<CardBadge>) {
    badges.forEach { badge ->
        when (badge) {
            is CardBadge.Disc -> Plate(badge.name, Modifier.align(Alignment.TopStart).padding(8.dp))
            is CardBadge.Unwatched -> Plate("${badge.count}", Modifier.align(Alignment.TopEnd).padding(8.dp), MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimary)
            CardBadge.Seen -> Box(Modifier.align(Alignment.TopEnd).padding(8.dp).size(20.dp).clip(CircleShape).background(SCRIM), contentAlignment = Alignment.Center) {
                Icon(WebIcons.Check, null, tint = ON_IMAGE, modifier = Modifier.size(14.dp))
            }
        }
    }
}

@Composable
private fun Plate(words: String, modifier: Modifier, fill: Color = SCRIM, ink: Color = ON_IMAGE) {
    Box(modifier.heightIn(min = 20.dp).widthIn(min = 20.dp).clip(RoundedCornerShape(4.dp)).background(fill).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
        Text(words, color = ink, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.02.em)
    }
}

// The plate behind words on artwork: black at 68%.
private val SCRIM = Color(0xAD000000)

// "1 h 52 min", "45 min", "30 s", as the website writes a length (fmtRuntime): the minutes rounded, and "2 h 0 min"
// kept whole.
fun runtimeWords(sec: Double): String {
    if (sec == 0.0 || sec.isNaN()) return ""
    if (sec < 60) return "${maxOf(1L, Math.round(sec))} s"
    val hours = (sec / 3600).toLong()
    val minutes = Math.round((sec % 3600) / 60)
    return if (hours > 0) "$hours h $minutes min" else "$minutes min"
}

// CSS's linear-gradient at an angle: 0 points up, 90 right, as the website writes it.
private fun Modifier.angledGradient(angle: Float, from: Color, to: Color): Modifier = drawBehind {
    val turn = Math.toRadians(angle.toDouble())
    val dx = kotlin.math.sin(turn).toFloat()
    val dy = -kotlin.math.cos(turn).toFloat()
    val half = (kotlin.math.abs(size.width * dx) + kotlin.math.abs(size.height * dy)) / 2
    val centre = Offset(size.width / 2, size.height / 2)
    drawRect(Brush.linearGradient(listOf(from, to), centre - Offset(dx * half, dy * half), centre + Offset(dx * half, dy * half)))
}

@Composable
private fun Progress(fraction: Float, modifier: Modifier) {
    Box(modifier.fillMaxWidth().height(3.dp).background(Color(0x47FFFFFF))) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(3.dp).background(MaterialTheme.colorScheme.primary))
    }
}

// A card for an item, as the website's ItemCard: an episode is a landscape card (232, 16:9) of its still under its
// show's name; songs and CDs are square; the rest a poster 2:3. A frame from the video as a poster shows whole, 16:9 on
// the title's own colours. Title 14 semibold (two lines; one on a landscape card), the facts 12 in textHint.
@Composable
fun WebItemCard(nav: Nav, item: Item, forceWide: Boolean = false, onOpen: (() -> Unit)? = null) {
    val look = CardLook.item(item, forceWide || item.showId != null)
    val wide = look.shape == CardShape.Wide
    val width = cardWidth(wide)
    val aspect = when (look.shape) { CardShape.Wide -> 16f / 9f; CardShape.Square -> 1f; CardShape.Poster -> 2f / 3f }
    val url = nav.app.api.posterUrl(item)
    val label = (listOf(look.title, look.subtitle) + look.badges.map { it.spoken }).filter { s -> s.isNotEmpty() }.joinToString(", ")
    Pressable(onOpen ?: { nav.open(item) }, Modifier.width(width), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = label, pressScale = 0.975f, ring = false) {
        Column(Modifier.width(width)) {
            Box(Modifier.fillMaxWidth().aspectRatio(aspect).restingShadow(10.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
                when {
                    item.poster.isEmpty() -> Placeholder(item.title, Modifier.fillMaxSize())
                    item.hasGeneratedArt && !wide -> {
                        val hue = titleHue(item.title)
                        Box(Modifier.fillMaxSize().angledGradient(170f, Color.hsl(hue, 0.26f, 0.26f), Color.hsl((hue + 40) % 360, 0.34f, 0.11f)), contentAlignment = Alignment.Center) {
                            WebArt(url, item.title, width, 16f / 9f, Modifier.fillMaxWidth().aspectRatio(16f / 9f).cssShadow(6.dp, 18.dp, Color(0x66000000), 0.dp), placeholderless = true)
                        }
                    }
                    else -> WebArt(url, item.title, width, aspect, Modifier.fillMaxSize())
                }
                Plates(look.badges)
                look.progress?.let { Progress(it, Modifier.align(Alignment.BottomStart)) }
                Box(Modifier.fillMaxSize().artHairline(10.dp))
            }
            Text(look.title, color = MaterialTheme.colorScheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 18.sp, maxLines = if (wide) 1 else 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            if (look.subtitle.isNotEmpty()) Text(look.subtitle, color = LocalExtraColours.current.hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

// A show's card, as the website's ShowCard: "2019 · 3 seasons", with how many episodes are left or a tick.
@Composable
fun WebShowCard(nav: Nav, s: Show) {
    val width = cardWidth()
    val look = CardLook.show(s)
    val label = (listOf(look.title, look.subtitle) + look.badges.map { it.spoken }).joinToString(", ")
    Pressable({ nav.push(Route.Show(s.id)) }, Modifier.width(width), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = label, pressScale = 0.975f, ring = false) {
        Column(Modifier.width(width)) {
            Box(Modifier.fillMaxWidth().aspectRatio(2f / 3f).restingShadow(10.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
                WebArt(nav.app.api.showPosterUrl(s), s.title, width, 2f / 3f, Modifier.fillMaxSize())
                Plates(look.badges)
                Box(Modifier.fillMaxSize().artHairline(10.dp))
            }
            Text(s.title, color = MaterialTheme.colorScheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 18.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            Text(look.subtitle, color = LocalExtraColours.current.hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

// A hub's head: the title 20 at weight 650, and its action in 13 medium with a 16 chevron, 44 to tap.
@Composable
fun HubHead(title: String, action: String? = null, onAction: (() -> Unit)? = null) {
    // Only an action needs the 44 to tap; a plain head is just its words.
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = if (action != null) 0.dp else 12.dp).then(if (action != null) Modifier.heightIn(min = 44.dp) else Modifier), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = MaterialTheme.colorScheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.24).sp, lineHeight = 23.sp, modifier = Modifier.weight(1f))
        if (action != null && onAction != null) {
            Pressable(onAction, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = action, ring = false) {
                Row(Modifier.heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(action, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    Icon(WebIcons.Right, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

// A row that scrolls sideways, 16 apart, 12 above and 16 below, snapping to the start of a card. `side` is the room
// at its ends: the page's 16, or none in Customize home's small look at it.
@Composable
fun HubRow(content: LazyListScope.() -> Unit) = HubRow(16.dp, content)

@Composable
fun HubRow(side: Dp, content: LazyListScope.() -> Unit) {
    val state = rememberLazyListState()
    LazyRow(
        state = state,
        flingBehavior = rememberSnapFlingBehavior(state, SnapPosition.Start),
        contentPadding = PaddingValues(start = side, end = side, top = 12.dp, bottom = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        content = content,
    )
}

fun LazyListScope.itemCards(nav: Nav, items: List<Item>, shows: List<Show> = emptyList(), wide: Boolean = false) {
    items(items, key = { "i${it.id}" }) { WebItemCard(nav, it, wide) }
    items(shows, key = { "s${it.id}" }) { WebShowCard(nav, it) }
}

// The website's buttons on a touch screen: 44 high, 16 inside, radius 10, 14 semibold, an 18 icon 8 before. Small is
// `.btn.sm`: 12 inside, 13, a 16 icon 6 before. Square is only the icon, 44 square, with the words for a screen reader.
// Disabled, it fades to 45%.
enum class WebButtonKind { Primary, Secondary, Ghost }

@Composable
fun WebButton(
    words: String, onClick: () -> Unit, kind: WebButtonKind = WebButtonKind.Secondary, icon: ImageVector? = null, modifier: Modifier = Modifier,
    small: Boolean = false, square: Boolean = false, enabled: Boolean = true,
) {
    val scheme = MaterialTheme.colorScheme
    val (fill, ink) = when (kind) {
        WebButtonKind.Primary -> scheme.primary to scheme.onPrimary
        WebButtonKind.Secondary -> scheme.surfaceVariant to scheme.onBackground
        WebButtonKind.Ghost -> Color.Transparent to scheme.onBackground
    }
    Pressable(onClick, modifier.heightIn(min = 44.dp).then(if (square) Modifier.widthIn(min = 44.dp) else Modifier), shape = RoundedCornerShape(10.dp), fill = fill, label = words, enabled = enabled, pressScale = 0.975f, disabledAlpha = 0.45f, ring = false) {
        Row(
            Modifier.heightIn(min = 44.dp).then(if (square) Modifier.widthIn(min = 44.dp) else Modifier)
                .then(if (kind == WebButtonKind.Ghost) Modifier.border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)) else Modifier)
                .padding(horizontal = if (square) 0.dp else if (small) 12.dp else 16.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (small) 6.dp else 8.dp, Alignment.CenterHorizontally),
        ) {
            if (icon != null) Icon(icon, null, tint = ink, modifier = Modifier.size(if (small) 16.dp else 18.dp))
            if (!square) Text(words, color = ink, fontSize = if (small) 13.sp else 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

// The loading shapes: card at 60%, with a slow shimmer of text at 6%, still when motion is reduced.
@Composable
fun Skel(modifier: Modifier, radius: Dp = 4.dp) {
    val still = LocalReduceMotion.current
    val shine = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.06f)
    val x by rememberInfiniteTransition(label = "skel").animateFloat(-1f, 1f, infiniteRepeatable(tween(1200, easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)), RepeatMode.Restart), label = "x")
    Box(
        modifier.clip(RoundedCornerShape(radius)).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)).drawWithContent {
            drawContent()
            if (!still) {
                val w = size.width
                drawRect(Brush.horizontalGradient(listOf(Color.Transparent, shine, Color.Transparent), startX = x * w, endX = x * w + w))
            }
        },
    )
}

// The foot of a page, as the website's (App.tsx, components/common.tsx LegalNote and VersionTag): the server's short
// legal notice with a link to Legal, then "WittyMediaServer 0.6.2" and its stage. A page with a notice of its own
// (an item's "metadata") shows that one instead of the general one.
@Composable
fun PageFoot(nav: Nav, notice: String = "general") {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val (number, stage) = com.wittywilla.wittymediaclient.net.versionParts(nav.serverVersion)
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 28.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
        nav.legal?.notices?.get(notice)?.let { n ->
            val link = nav.legal?.linkText?.ifEmpty { null } ?: "Legal"
            val words = androidx.compose.ui.text.buildAnnotatedString {
                append(n.text + " ")
                pushStyle(androidx.compose.ui.text.SpanStyle(color = extra.accentText, textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline))
                append(link)
                pop()
            }
            Text(
                words, color = extra.hint, fontSize = 12.sp, lineHeight = 18.sp,
                modifier = Modifier.semantics { contentDescription = "Legal notice: ${n.text}" }
                    .clickableNoRipple { nav.push(Route.Page("/settings/legal" + if (n.section.isEmpty()) "" else "#${n.section}", link)) },
            )
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            Text("WittyMediaServer $number", color = scheme.onBackground, fontSize = 15.sp)
            if (stage.isNotEmpty()) StagePill(stage)
        }
    }
}

// The stage after a version: 11 bold in accentText on the accent at 16%, radius 4.
@Composable
fun StagePill(stage: String) {
    Text(
        stage.uppercase(), color = LocalExtraColours.current.accentText, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.05.em,
        modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)).padding(horizontal = 6.dp),
    )
}

private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier = this.then(
    Modifier.pointerInput(onClick) { detectTapGestures { onClick() } },
)
