package com.wittywilla.wittymediaclient.ui

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
import androidx.compose.ui.draw.drawWithContent
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

@Composable
private fun Badge(words: String, modifier: Modifier, fill: Color = Color(0xAD000000), ink: Color = ON_IMAGE) {
    Box(modifier.heightIn(min = 20.dp).widthIn(min = 20.dp).clip(RoundedCornerShape(4.dp)).background(fill).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
        Text(words, color = ink, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.02.em)
    }
}

private fun discBadge(it: Item): String? = when (it.kind) {
    "dvd-iso", "dvd-folder" -> "DVD"
    "bluray-iso", "bluray-folder" -> "Blu-ray"
    "cd-image" -> "CD"
    else -> null
}

// "1 h 40 min", "45 min", "30 s", as the website writes a length.
fun runtimeWords(sec: Double): String {
    val s = sec.toLong()
    return when {
        s <= 0 -> ""
        s < 60 -> "$s s"
        s < 3600 -> "${s / 60} min"
        s % 3600 / 60 == 0L -> "${s / 3600} h"
        else -> "${s / 3600} h ${s % 3600 / 60} min"
    }
}

fun isAudio(it: Item) = it.kind in setOf("audio", "track", "audiobook", "podcast", "cd-image") || it.album.isNotEmpty()

private fun cardSub(it: Item): String = when {
    it.showId != null -> listOf(it.season?.let { s -> "S$s · E${it.episode ?: 0}" }.orEmpty(), it.title).filter { s -> s.isNotEmpty() }.joinToString(" · ")
    isAudio(it) -> it.albumArtist.ifEmpty { it.artist }
    else -> listOfNotNull(it.year?.toString(), runtimeWords(it.runtimeSec).ifEmpty { null }).joinToString(" · ")
}

@Composable
private fun Progress(fraction: Float, modifier: Modifier) {
    Box(modifier.fillMaxWidth().height(3.dp).background(Color(0x47FFFFFF))) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(3.dp).background(MaterialTheme.colorScheme.primary))
    }
}

// A card for an item: an episode is a landscape card (232, 16:9) under its show's name; sound is a square; the rest a
// poster 2:3. Title 14 semibold (two lines; one on a landscape card), the facts 12 in textHint.
@Composable
fun WebItemCard(nav: Nav, item: Item, forceWide: Boolean = false, onOpen: (() -> Unit)? = null) {
    val wide = forceWide || item.showId != null
    val square = !wide && isAudio(item)
    val width = cardWidth(wide)
    val aspect = when { wide -> 16f / 9f; square -> 1f; else -> 2f / 3f }
    val api = nav.app.api
    val url = if (wide) api.backdropUrl(item) else api.posterUrl(item)
    val title = if (item.showId != null) item.showTitle?.ifEmpty { null } ?: item.title else if (square && item.album.isNotEmpty()) item.album else item.title
    val progress = item.progress?.takeIf { p -> !p.watched && p.positionSec > 0 && p.durationSec > 0 }?.let { p -> (p.positionSec / p.durationSec).toFloat() }
    Pressable(onOpen ?: { nav.open(item) }, Modifier.width(width), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = listOf(title, cardSub(item)).filter { s -> s.isNotEmpty() }.joinToString(", "), pressScale = 0.975f, ring = false) {
        Column(Modifier.width(width)) {
            Box(Modifier.fillMaxWidth().aspectRatio(aspect).restingShadow(10.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
                WebArt(if (item.poster.isEmpty() && !wide && item.updatedAt == 0L) null else url, title, width, aspect, Modifier.fillMaxSize())
                discBadge(item)?.let { words -> Badge(words, Modifier.align(Alignment.TopStart).padding(8.dp)) }
                if (item.progress?.watched == true) Box(Modifier.align(Alignment.TopEnd).padding(8.dp).size(20.dp).clip(CircleShape).background(Color(0xAD000000)), contentAlignment = Alignment.Center) {
                    Icon(WebIcons.Check, null, tint = ON_IMAGE, modifier = Modifier.size(14.dp))
                }
                if (progress != null) Progress(progress, Modifier.align(Alignment.BottomStart))
                Box(Modifier.fillMaxSize().artHairline(10.dp))
            }
            Text(title, color = MaterialTheme.colorScheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 18.sp, maxLines = if (wide) 1 else 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            val sub = cardSub(item)
            if (sub.isNotEmpty()) Text(sub, color = LocalExtraColours.current.hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

@Composable
fun WebShowCard(nav: Nav, s: Show) {
    val width = cardWidth()
    val sub = listOfNotNull(s.year?.toString(), if (s.seasonCount > 0) "${s.seasonCount} season${if (s.seasonCount == 1) "" else "s"}" else null).joinToString(" · ")
    Pressable({ nav.push(Route.Show(s.id)) }, Modifier.width(width), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = listOf(s.title, sub).joinToString(", "), pressScale = 0.975f, ring = false) {
        Column(Modifier.width(width)) {
            Box(Modifier.fillMaxWidth().aspectRatio(2f / 3f).restingShadow(10.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) {
                WebArt(nav.app.api.showPosterUrl(s), s.title, width, 2f / 3f, Modifier.fillMaxSize())
                if (s.unwatched in 1 until s.episodeCount) Badge("${s.unwatched}", Modifier.align(Alignment.TopEnd).padding(8.dp), MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.onPrimary)
                Box(Modifier.fillMaxSize().artHairline(10.dp))
            }
            Text(s.title, color = MaterialTheme.colorScheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 18.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            if (sub.isNotEmpty()) Text(sub, color = LocalExtraColours.current.hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
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

// A row that scrolls sideways, 16 apart, 12 above and 16 below, snapping to the start of a card.
@Composable
fun HubRow(content: LazyListScope.() -> Unit) {
    val state = rememberLazyListState()
    LazyRow(
        state = state,
        flingBehavior = rememberSnapFlingBehavior(state, SnapPosition.Start),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        content = content,
    )
}

fun LazyListScope.itemCards(nav: Nav, items: List<Item>, shows: List<Show> = emptyList(), wide: Boolean = false) {
    items(items, key = { "i${it.id}" }) { WebItemCard(nav, it, wide) }
    items(shows, key = { "s${it.id}" }) { WebShowCard(nav, it) }
}

// The website's buttons on a touch screen: 44 high, 16 inside, radius 10, 14 semibold, an 18 icon 8 before.
enum class WebButtonKind { Primary, Secondary, Ghost }

@Composable
fun WebButton(words: String, onClick: () -> Unit, kind: WebButtonKind = WebButtonKind.Secondary, icon: ImageVector? = null, modifier: Modifier = Modifier, small: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    val (fill, ink) = when (kind) {
        WebButtonKind.Primary -> scheme.primary to scheme.onPrimary
        WebButtonKind.Secondary -> scheme.surfaceVariant to scheme.onBackground
        WebButtonKind.Ghost -> Color.Transparent to scheme.onBackground
    }
    Pressable(onClick, modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = fill, label = words, pressScale = 0.975f, ring = false) {
        Row(
            Modifier.heightIn(min = 44.dp).then(if (kind == WebButtonKind.Ghost) Modifier.border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)) else Modifier)
                .padding(horizontal = if (small) 12.dp else 16.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (small) 6.dp else 8.dp, Alignment.CenterHorizontally),
        ) {
            if (icon != null) Icon(icon, null, tint = ink, modifier = Modifier.size(if (small) 16.dp else 18.dp))
            Text(words, color = ink, fontSize = if (small) 13.sp else 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
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
