package com.wittywilla.wittymediaclient.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import coil3.compose.AsyncImage
import com.wittywilla.wittymediaclient.net.GuideCell
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.TvLook
import com.wittywilla.wittymediaclient.net.TvShape
import com.wittywilla.wittymediaclient.net.logoImageUrl
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Route
import com.wittywilla.wittymediaclient.ui.Symbols
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

// The top of the guide, as the server's page draws it (Hero.tsx and Preview.tsx) and Apple TV's GuideHero: the
// highlighted channel, its programme, what can be done with it and a live preview, in each theme's shape.

private fun TvShape.isOneOf(vararg shapes: TvShape) = this in shapes

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GuideHero(
    nav: Nav,
    dress: TvDress,
    channel: GuideChannel?,
    cell: GuideCell?,
    programme: GuideProgramme?,
    next: GuideProgramme?,
    now: Long,
    preview: String,
    previewName: String,
    onWatch: (String) -> Unit,
    onDetails: () -> Unit,
    onDay: () -> Unit,
    onFavourite: () -> Unit,
    onStep: (Int) -> Unit,
    onRecord: () -> Unit,
    onSaid: (String) -> Unit,
) {
    val p = dress.paint
    val shape = dress.shape
    val showsClock = shape.isOneOf(TvShape.Box, TvShape.Receiver, TvShape.Teletext, TvShape.Listings)
    val showsArt = dress.look.art && shape.art
    var art by remember { mutableStateOf<Long?>(null) }
    LaunchedEffect(programme?.itemId, showsArt) {
        art = null
        val id = programme?.itemId
        if (!showsArt || id == null) return@LaunchedEffect
        delay(400)
        art = id
    }
    val api = nav.app.api
    Box(
        Modifier
            .fillMaxWidth()
            .clipToBounds(),
    ) {
        // What's behind: the shape's own colours, and the programme's picture where the shape has one.
        Box(Modifier.matchParentSize().background(heroFill(dress))) {
            art?.let { id ->
                AsyncImage(
                    model = api.itemBackdropUrl(id), contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer(alpha = if (shape == TvShape.Outline) 0.12f else 0.22f, compositingStrategy = CompositingStrategy.Offscreen)
                        .drawWithContent {
                            drawContent()
                            drawRect(
                                Brush.horizontalGradient(0.3f to Color.Black, 0.85f to Color.Transparent, startX = 0f, endX = size.width),
                                blendMode = BlendMode.DstIn,
                            )
                        },
                )
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = dress.pt(dress.top + 16 + if (shape == TvShape.Teletext) 44 else 0), start = dress.pt(dress.edge), end = dress.pt(dress.edge))
                .padding(bottom = dress.pt(if (shape == TvShape.Compact) 8 else 16)),
            verticalAlignment = if (shape == TvShape.Cinema) Alignment.CenterVertically else Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(dress.pt(if (shape == TvShape.Cinema) 24 else 16)),
        ) {
            if (dress.look.previewSide == "left" && dress.look.preview != "off") GuidePreview(nav, dress, preview, previewName, onWatch)
            Column(Modifier.weight(1f)) {
                HeroMain(nav, dress, channel, cell, programme, next, now, onWatch, onDetails, onDay, onFavourite, onStep, onRecord, onSaid)
            }
            if (dress.look.previewSide == "right" && dress.look.preview != "off") GuidePreview(nav, dress, preview, previewName, onWatch)
            if (showsClock) HeroClock(dress, now)
        }
        if (shape == TvShape.Teletext) {
            Text(
                "P100  WITTYTV  GUIDE", style = dress.font(17.5f, tracking = 1.75f), color = p.soft,
                modifier = Modifier.padding(top = dress.pt(dress.top + 16), start = dress.pt(dress.edge)),
            )
        }
        Box(Modifier.matchParentSize().then(heroRules(dress)))
    }
}

private fun heroFill(dress: TvDress): Brush {
    val p = dress.paint
    return when (dress.shape) {
        TvShape.Modern -> Brush.verticalGradient(listOf(p.panel, p.bg))
        TvShape.Receiver -> Brush.verticalGradient(listOf(p.panel, p.panel))
        TvShape.Box -> Brush.verticalGradient(listOf(p.panel2, p.panel))
        else -> Brush.verticalGradient(listOf(p.bg, p.bg))
    }
}

private fun heroRules(dress: TvDress): Modifier {
    val p = dress.paint
    return when (dress.shape) {
        TvShape.Box -> Modifier.rule(Edge.Bottom, p.line, dress.pt(4))
        TvShape.Receiver -> Modifier.rule(Edge.Bottom, p.accent, dress.pt(1))
        TvShape.Listings -> Modifier.drawWithContent {
            drawContent()
            val w = dress.pt(1).toPx()
            drawRect(p.text, Offset(0f, size.height - w), androidx.compose.ui.geometry.Size(size.width, w))
            drawRect(p.text, Offset(0f, size.height - w * 2 - dress.pt(2).toPx()), androidx.compose.ui.geometry.Size(size.width, w))
        }
        TvShape.Compact -> Modifier.rule(Edge.Bottom, p.line, dress.pt(1))
        else -> Modifier
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HeroMain(
    nav: Nav,
    dress: TvDress,
    channel: GuideChannel?,
    cell: GuideCell?,
    programme: GuideProgramme?,
    next: GuideProgramme?,
    now: Long,
    onWatch: (String) -> Unit,
    onDetails: () -> Unit,
    onDay: () -> Unit,
    onFavourite: () -> Unit,
    onStep: (Int) -> Unit,
    onRecord: () -> Unit,
    onSaid: (String) -> Unit,
) {
    val p = dress.paint
    val shape = dress.shape
    val real = programme != null && cell?.kind == GuideCell.Kind.Programme
    // Words over the programme's picture keep a shadow in the background's colour.
    val shadow = if (shape == TvShape.Modern || shape == TvShape.Outline) Shadow(p.bg, Offset(0f, dress.pt(1).value * 2), dress.pt(3).value * 2) else null
    val factsTop = dress.pt(if (shape == TvShape.Modern) 6 else if (shape == TvShape.Cinema || shape == TvShape.Outline) 8 else 3)
    ChannelLine(dress, channel)
    HeroTitle(dress, programme?.title ?: channel?.name ?: " ", shadow)
    HeroMeta(dress, channel, programme, shadow, factsTop)
    if (real && programme != null) HeroWhen(dress, programme, now, shadow)
    if (next != null) {
        Text(
            buildAnnotatedString {
                append("Next ")
                withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = p.text)) { append(tvClock(next.start)) }
                append(" " + next.title)
            },
            style = dress.font(dress.heroFacts).copy(shadow = shadow), color = p.soft, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = factsTop),
        )
    }
    val desc = programme?.desc
    if (shape != TvShape.Compact && !desc.isNullOrEmpty()) {
        Text(desc, style = dress.font(dress.heroFacts).copy(shadow = shadow), color = p.soft, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = dress.pt(4)))
    }
    val security = channel?.security
    if (security?.state == "encrypted") {
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(security.label + ". ") }
                append(security.detail)
            },
            style = dress.font(dress.heroFacts).copy(shadow = shadow), color = p.soft, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = dress.pt(4)),
        )
    }
    channel?.notices.orEmpty().forEach {
        Text(it, style = dress.font(dress.heroFacts).copy(shadow = shadow), color = p.soft, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = dress.pt(4)))
    }
    HeroActions(nav, dress, channel, cell, programme, now, onWatch, onDetails, onDay, onFavourite, onStep, onRecord, onSaid)
}

@Composable
private fun ChannelLine(dress: TvDress, channel: GuideChannel?) {
    val p = dress.paint
    val shape = dress.shape
    val n = dress.heroNumber
    Row(Modifier.defaultMinSize(minHeight = dress.pt(26)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dress.pt(10))) {
        if (channel != null) {
            Text(
                channel.number,
                style = dress.font(n.size, n.weight, digits = shape == TvShape.Receiver, italic = shape == TvShape.Listings, tracking = if (shape == TvShape.Receiver) 2f else 0f, tabular = true),
                color = if (shape == TvShape.Modern) p.text else p.accent, maxLines = 1,
                modifier = Modifier
                    .then(if (shape == TvShape.Receiver) Modifier.border(dress.pt(1), p.accent) else Modifier)
                    .padding(horizontal = dress.pt(if (shape == TvShape.Receiver) 8 else 0)),
            )
            ChannelLogo(dress, channel, dress.heroLogo, highlighted = false)
            Column {
                val name = if (shape == TvShape.Receiver || shape == TvShape.Teletext) channel.name.uppercase() else channel.name
                Text(
                    dress.words(name, dress.heroChannel, smallCaps = true),
                    style = dress.font(dress.heroChannel, W.Bold, tracking = if (shape == TvShape.Receiver) 2f else 0f),
                    color = if (shape == TvShape.Teletext) p.soft else p.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                val d = channel.description
                if (shape != TvShape.Compact && !d.isNullOrEmpty()) {
                    Text(d, style = dress.font(dress.heroChannel, italic = shape == TvShape.Listings), color = if (shape == TvShape.Teletext) p.text else p.soft, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        } else {
            Icon(Symbols.Tv, contentDescription = null, tint = p.soft, modifier = Modifier.size(dress.pt(33)))
        }
    }
}

@Composable
private fun HeroTitle(dress: TvDress, words: String, shadow: Shadow?) {
    val p = dress.paint
    val shape = dress.shape
    val t = dress.heroTitle
    if (shape == TvShape.Teletext) {
        Text(
            words.uppercase(), style = dress.font(t), color = p.accent, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .padding(top = dress.pt(12))
                .graphicsLayer(scaleY = 1.7f, transformOrigin = TransformOrigin(0f, 0f))
                .padding(bottom = dress.pt(t.size * 0.75f))
                .semantics { heading() },
        )
    } else {
        val tracking = when (shape) {
            TvShape.Modern, TvShape.Cinema, TvShape.Outline -> -t.size * 0.022f
            TvShape.Receiver -> t.size * 0.03f
            else -> 0f
        }
        val boxShadow = if (shape == TvShape.Box) Shadow(Color.Black.copy(alpha = 0.6f), Offset(dress.pt(1).value * 2, dress.pt(1).value * 2), 0f) else shadow
        val top = when (shape) {
            TvShape.Modern -> 6
            TvShape.Cinema -> 12
            TvShape.Receiver, TvShape.Listings, TvShape.Outline -> 8
            TvShape.Compact -> 2
            else -> 4
        }
        Text(
            if (shape == TvShape.Receiver) words.uppercase() else words,
            style = dress.font(t.size, t.weight, tracking = tracking).copy(shadow = boxShadow), color = p.text,
            maxLines = if (shape == TvShape.Compact) 1 else 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = dress.pt(top)).semantics { heading() },
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HeroMeta(dress: TvDress, channel: GuideChannel?, programme: GuideProgramme?, shadow: Shadow?, top: androidx.compose.ui.unit.Dp) {
    val p = dress.paint
    val shape = dress.shape
    val facts = dress.font(dress.heroFacts).copy(shadow = shadow)
    val tags = listOfNotNull(
        programme?.rating, if (channel?.hd == true) "HD" else null, if (channel?.atsc3 == true) "ATSC 3.0" else null,
        when (channel?.security?.state) {
            "clear" -> "Clear"
            "unknown" -> channel.security.label
            else -> null
        },
    )
    val sub = programme?.sub
    if (sub.isNullOrEmpty() && programme?.year == null && programme?.genre.isNullOrEmpty() && tags.isEmpty()) {
        // An empty line still keeps its place, as the page's does.
        Spacer(Modifier.padding(top = top))
        return
    }
    Row(Modifier.padding(top = top), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dress.pt(10))) {
        if (!sub.isNullOrEmpty()) {
            val colour = when {
                shape.isOneOf(TvShape.Modern, TvShape.Cinema, TvShape.Outline, TvShape.Compact, TvShape.Teletext) -> p.soft
                shape == TvShape.Listings -> p.text
                else -> p.accent
            }
            val weight = when (shape) {
                TvShape.Box -> W.Bold
                TvShape.Teletext, TvShape.Listings, TvShape.Outline -> W.Regular
                else -> W.Medium
            }
            Text(sub, style = dress.font(dress.heroFacts, weight, italic = shape == TvShape.Listings).copy(shadow = shadow), color = colour, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false))
        }
        programme?.year?.let { Text(it.toString(), style = facts, color = p.soft, maxLines = 1) }
        programme?.genre?.takeIf { it.isNotEmpty() }?.let { Text(it, style = facts, color = p.soft, maxLines = 1) }
        for (tag in tags) {
            Text(
                tag, style = dress.font(15f, W.Bold), color = p.soft, maxLines = 1,
                modifier = Modifier
                    .border(dress.pt(1), p.soft, RoundedCornerShape(dress.pt(dress.radius)))
                    .padding(horizontal = dress.pt(5)),
            )
        }
    }
}

@Composable
private fun HeroWhen(dress: TvDress, programme: GuideProgramme, now: Long, shadow: Shadow?) {
    val p = dress.paint
    val shape = dress.shape
    val later = programme.start > now
    val on = programme.isOn(now)
    val barHeight = when (shape) {
        TvShape.Receiver, TvShape.Compact -> 4
        TvShape.Teletext -> 8
        TvShape.Listings, TvShape.Outline -> 2
        else -> 6
    }
    val top = if (shape == TvShape.Modern) 8 else if (shape == TvShape.Cinema || shape == TvShape.Outline) 8 else 5
    Row(Modifier.padding(top = dress.pt(top)).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dress.pt(10))) {
        Text(
            (if (later) GuideRules.dayName(programme.start) + ", " else "") + GuideRules.span(programme.start, programme.end),
            style = dress.font(dress.heroFacts, if (shape == TvShape.Listings || shape == TvShape.Outline) W.Regular else W.Bold).copy(shadow = shadow),
            color = p.text, maxLines = 1,
        )
        if (on) {
            val share = if (programme.end > programme.start) ((now - programme.start).toFloat() / (programme.end - programme.start)).coerceIn(0f, 1f) else 0f
            val corner = RoundedCornerShape(dress.pt(if (shape == TvShape.Receiver || shape == TvShape.Teletext) 0f else dress.radius))
            Box(
                Modifier
                    .weight(1f, fill = false)
                    .widthIn(min = dress.pt(80), max = dress.pt(320))
                    .fillMaxWidth()
                    .height(dress.pt(barHeight))
                    .clip(corner)
                    .background(if (shape == TvShape.Teletext) p.panel2 else if (shape == TvShape.Listings) p.line else p.lite),
            ) {
                Box(Modifier.fillMaxWidth(share).height(dress.pt(barHeight)).background(p.accent))
            }
            Text(GuideRules.left(programme.end - maxOf(now, programme.start)) + " left", style = dress.font(dress.heroFacts).copy(shadow = shadow), color = p.soft, maxLines = 1)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HeroActions(
    nav: Nav,
    dress: TvDress,
    channel: GuideChannel?,
    cell: GuideCell?,
    programme: GuideProgramme?,
    now: Long,
    onWatch: (String) -> Unit,
    onDetails: () -> Unit,
    onDay: () -> Unit,
    onFavourite: () -> Unit,
    onStep: (Int) -> Unit,
    onRecord: () -> Unit,
    onSaid: (String) -> Unit,
) {
    val p = dress.paint
    val shape = dress.shape
    val scope = rememberCoroutineScope()
    val later = (programme?.start ?: 0) > now
    val reminded = channel != null && programme != null && TvReminders.has(channel.key, programme.start)
    val itemId = programme?.itemId
    val isTitle = cell?.kind == GuideCell.Kind.Programme && itemId != null
    val isFilm = isTitle && programme?.showId == null
    val top = if (shape == TvShape.Modern || shape == TvShape.Outline) 12 else if (shape == TvShape.Cinema) 16 else 8
    // The buttons' rings sit in the room kept round each, so the gaps are the page's less that room.
    FlowRow(
        Modifier.padding(top = dress.pt(top)),
        horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
        verticalArrangement = Arrangement.spacedBy(dress.pt(12)),
    ) {
        val alt = channel?.alternative
        if (channel != null && alt != null) TvButton(dress, "Watch ${alt.number} ${alt.name} instead", { onWatch(alt.key) }, on = true)
        if (channel != null && channel.canTune) {
            if (later && programme != null) {
                TvButton(dress, if (reminded) "✓ Reminder set" else "Remind me", { scope.launch { onSaid(TvReminders.toggle(channel.key, programme)) } }, on = !reminded)
                TvButton(dress, "Watch channel", { onWatch(channel.key) }, icon = TvSymbols.FullScreen)
            } else {
                TvButton(dress, "Watch full screen", { onWatch(channel.key) }, on = true, icon = TvSymbols.FullScreen)
            }
        }
        if (isTitle && itemId != null) {
            TvButton(dress, "Start over", { nav.push(Route.Player(itemId, startOver = true)) }, icon = TvSymbols.StartOver)
            TvButton(dress, if (isFilm) "Open the film" else "Open the show", { nav.push(programme?.showId?.let { Route.Show(it) } ?: Route.Item(itemId)) }, icon = Symbols.Movie)
        }
        if (channel?.canRecord == true && cell?.isBroadcast == true && (programme?.end ?: 0) > now) {
            TvButton(dress, "● Record", onRecord)
        }
        if (channel != null) {
            TvIconButton(
                dress, if (channel.favourite) Symbols.StarFilled else Symbols.Star, "Favourite channel", onFavourite, selected = channel.favourite,
                tint = if (channel.favourite) p.accent else p.text,
            )
        }
        TvIconButton(dress, TvSymbols.ChevronDown, "Channel down", { onStep(1) })
        TvIconButton(dress, TvSymbols.ChevronUp, "Channel up", { onStep(-1) })
        TvIconButton(dress, Symbols.Info, "More about this programme", onDetails)
        TvButton(dress, "Day", onDay)
        if (dress.look.preview == "off") TvButton(dress, "Show preview", { TvLookStore.change("preview", "highlight", nav.app.api) })
    }
}

@Composable
private fun HeroClock(dress: TvDress, now: Long) {
    val p = dress.paint
    val shape = dress.shape
    val big = if (shape == TvShape.Teletext || shape == TvShape.Listings) 25f else 47.5f
    Column(horizontalAlignment = Alignment.End) {
        Text(
            tvClock(now), style = dress.font(big, if (shape == TvShape.Box) W.Bold else W.Regular, digits = shape == TvShape.Receiver, italic = shape == TvShape.Listings, tabular = true),
            color = p.accent, maxLines = 1,
        )
        val day = GuideRules.dayName(now)
        Text(
            if (shape == TvShape.Receiver) day.uppercase() else day, style = dress.font(if (shape == TvShape.Receiver) 16.25f else 25f, tracking = if (shape == TvShape.Receiver) 1.3f else 0f),
            color = p.soft, maxLines = 1,
        )
    }
}

// The little TV on the guide, with its own bar: smaller, larger, sound, full screen and hide. A column of the top of the
// page, not a layer over it, so it covers nothing.
@Composable
fun GuidePreview(nav: Nav, dress: TvDress, channel: String, name: String, onWatch: (String) -> Unit) {
    val p = dress.paint
    val shape = dress.shape
    val api = nav.app.api
    val most = TvLook.previewLimit(1920.0, 1080.0)
    val least = minOf(TvLook.PREVIEW_MIN, most)
    val width = maxOf(least, minOf(most, dress.look.previewW ?: TvLook.previewAuto(shape, 1920.0, 1080.0)))
    val radius = when (shape) {
        TvShape.Modern, TvShape.Outline -> 14f
        TvShape.Cinema -> 10f
        TvShape.Compact -> 6f
        else -> 0f
    }
    val pictureBar = shape == TvShape.Modern || shape == TvShape.Cinema
    val corner = RoundedCornerShape(dress.pt(radius))
    val border = when (shape) {
        TvShape.Modern, TvShape.Cinema -> Color.Transparent
        TvShape.Receiver -> p.accent
        TvShape.Teletext -> p.panel2
        TvShape.Listings -> p.text
        else -> p.line
    }
    val borderWidth = when (shape) {
        TvShape.Box -> 3
        TvShape.Receiver, TvShape.Listings, TvShape.Outline, TvShape.Compact -> 1
        TvShape.Modern, TvShape.Cinema -> 0
        else -> 2
    }
    fun size(way: Int) {
        val named = TvLook.previewSizes.map { it.first }.filter { it <= most }
        val next = if (way > 0) named.firstOrNull { it > width + 1 } ?: most else named.lastOrNull { it < width - 1 } ?: least
        TvLookStore.change("previewW", kotlin.math.floor(next + 0.5), api)
    }
    Box(
        Modifier
            .then(if (shape == TvShape.Receiver) Modifier.border(dress.pt(1), p.line).padding(dress.pt(4)) else Modifier)
            .semantics { },
    ) {
        Column(
            Modifier
                .width(dress.pt(width))
                .clip(corner)
                .then(if (borderWidth > 0) Modifier.strokeInside(border, dress.pt(borderWidth), dress.pt(radius)) else Modifier),
        ) {
            Box(Modifier.fillMaxWidth().height(dress.pt(width * 9 / 16)).background(Color.Black), contentAlignment = Alignment.Center) {
                if (LiveTv.key == channel && channel.isNotEmpty()) LivePicture(Modifier.fillMaxSize())
                if (LiveTv.key == channel && LiveTv.playing && LiveTv.info?.now?.kind == "slate") {
                    SlateCard(dress, LiveTv.info?.name ?: name, LiveTv.info?.next, scale = (width / 1920).toFloat())
                }
                val words: String? = when {
                    channel.isEmpty() -> "No preview for this channel"
                    LiveTv.key != channel -> name
                    LiveTv.state == LiveTv.State.Failed -> if (LiveTv.why.length > 90) "Not available" else LiveTv.why
                    else -> if (LiveTv.playing) null else "Tuning…"
                }
                if (words != null) {
                    Text(words, style = dress.font(15f).copy(fontFamily = null), color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.padding(dress.pt(8)))
                }
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .background(if (pictureBar) Color.Black else if (shape == TvShape.Teletext) p.panel2 else if (shape == TvShape.Listings || shape == TvShape.Outline) p.bg else p.panel)
                    .defaultMinSize(minHeight = dress.pt(56))
                    .padding(horizontal = dress.pt(2)),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
            ) {
                Text(
                    name, style = dress.font(18.75f).copy(fontFamily = null, fontWeight = FontWeight.Normal, fontStyle = FontStyle.Normal), color = if (pictureBar) Color.White else p.text,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = dress.pt(6)),
                )
                TvGlyphButton(dress, "−", "Smaller preview", { size(-1) }, enabled = width > least)
                TvGlyphButton(dress, "+", "Larger preview", { size(1) }, enabled = width < most)
                TvIconButton(dress, if (dress.look.previewSound) TvSymbols.Sound else TvSymbols.NoSound, "Preview sound", {
                    TvLookStore.change("previewSound", !dress.look.previewSound, api)
                    LiveTv.muted = dress.look.previewSound
                })
                TvIconButton(dress, TvSymbols.FullScreen, "Watch $name full screen", { if (channel.isNotEmpty()) onWatch(channel) }, enabled = channel.isNotEmpty())
                TvIconButton(dress, TvSymbols.Close, "Hide the preview", { TvLookStore.change(mapOf("preview" to JsonPrimitive("off")), api) })
            }
        }
    }
}

// "We'll be right back": the card over a channel's slate, when nothing is scheduled, so neither the preview nor the
// channel looks broken while it's on. Always over the picture, in the picture's colours.
@Composable
fun SlateCard(dress: TvDress, name: String, next: GuideProgramme?, scale: Float = 1f, modifier: Modifier = Modifier) {
    val s = maxOf(scale * 1.6f, 0.3f)
    val plain = dress.font(1f).copy(fontFamily = null)
    Column(
        modifier.padding(horizontal = dress.pt(34 * s), vertical = dress.pt(22 * s)),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(dress.pt(6 * s)),
    ) {
        Text(name, style = plain.copy(fontSize = dress.sp(maxOf(10f, 25 * s)), fontWeight = FontWeight.Bold), color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center)
        Text(
            "We'll be right back",
            style = plain.copy(fontSize = dress.sp(maxOf(14f, 47.5f * s)), fontWeight = FontWeight.Bold, shadow = Shadow(Color.Black.copy(alpha = 0.6f), Offset(dress.pt(2).value * 2, dress.pt(2).value * 2), 0f)),
            color = Color.White, textAlign = TextAlign.Center,
        )
        if (next != null) {
            Text("Coming up at ${tvClock(next.start)}: ${next.title}", style = plain.copy(fontSize = dress.sp(maxOf(9f, 21.25f * s))), color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center)
        }
    }
}

// A channel's picture: the owner's own upload first, then the logo service's. Without either, nothing.
@Composable
fun ChannelLogo(dress: TvDress, channel: GuideChannel, size: androidx.compose.ui.geometry.Size, highlighted: Boolean) {
    val url = channelLogoUrl(LocalTvApi.current, dress, channel, highlighted) ?: return
    AsyncImage(
        model = url, contentDescription = channel.name, contentScale = ContentScale.Fit,
        modifier = Modifier.width(dress.pt(size.width)).height(dress.pt(size.height)),
    )
}

private fun channelLogoUrl(api: com.wittywilla.wittymediaclient.net.Api, dress: TvDress, channel: GuideChannel, highlighted: Boolean): String? {
    if (!dress.look.logos) return null
    channel.logo?.takeIf { it.startsWith("/") }?.let { return runCatching { api.mediaUrl(it) }.getOrNull() }
    val info = TvLogos.info(channel.brand) ?: return null
    if (info.has != true) return null
    val dark = if (highlighted && dress.rowHighlight) dress.look.hiIsDark else dress.look.bgIsDark
    return api.logoImageUrl(info, if (info.opaque == true) "original" else if (dark) "white" else "dark")
}

// Whether a channel has a picture to show, for the row that shows its name otherwise.
fun hasLogo(dress: TvDress, channel: GuideChannel?): Boolean {
    if (!dress.look.logos || channel == null) return false
    return channel.logo?.startsWith("/") == true || TvLogos.info(channel.brand)?.has == true
}

