// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.size.Precision
import com.wittywilla.wittymediaclient.net.SduiAction
import com.wittywilla.wittymediaclient.net.SduiCardStyles
import com.wittywilla.wittymediaclient.net.SduiFocusRules
import com.wittywilla.wittymediaclient.net.SduiItemActions
import com.wittywilla.wittymediaclient.net.SduiPresence
import com.wittywilla.wittymediaclient.net.strings
import androidx.compose.ui.graphics.graphicsLayer
import com.wittywilla.wittymediaclient.net.SduiImage
import com.wittywilla.wittymediaclient.net.SduiView
import com.wittywilla.wittymediaclient.net.aspectOf
import com.wittywilla.wittymediaclient.net.image
import com.wittywilla.wittymediaclient.net.str
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// The server's cards (docs/SDUI.md, Card styles): fourteen styles, each drawing what net/SduiScreen.kt says the style
// shows, in that order, with the line limits it gives. A style this app doesn't know is drawn as its shape.

// Words on a picture and the plate behind them, as the theme has them.
private val ON_IMAGE = Color.White

// A picture from the server, asked for at the address the page gave (it already carries the width to ask for) and
// decoded no larger than it is drawn: a TV stick has little memory. While it loads, and if there is none, its place
// is the card colour with the kind's icon.
@Composable
fun SduiPicture(
    image: SduiImage?, width: Dp, aspect: Float, icon: ImageVector?, modifier: Modifier = Modifier, contain: Boolean = false,
    alignment: Alignment = Alignment.Center,
) {
    val env = LocalSdui.current
    val context = LocalContext.current
    val scheme = MaterialTheme.colorScheme
    val wide = with(LocalDensity.current) { width.toPx() }.toInt().coerceAtLeast(1)
    val tall = (wide / aspect.coerceAtLeast(0.1f)).toInt().coerceAtLeast(1)
    val address = image?.url?.let(env::url).orEmpty()
    var failed by remember(address) { mutableStateOf(false) }
    Box(modifier.background(scheme.surfaceVariant), contentAlignment = Alignment.Center) {
        if (icon != null) Icon(icon, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size((width * 0.28f).coerceIn(16.dp, 72.dp)))
        if (address.isNotEmpty() && !failed) {
            // Never more pixels than the server was asked for, nor than the picture's place on this screen.
            val pixels = if (image != null && image.width in 1 until wide) image.width else wide
            val request = remember(address, pixels) {
                ImageRequest.Builder(context).data(address).size(pixels, (pixels.toFloat() * tall / wide).toInt().coerceAtLeast(1)).precision(Precision.INEXACT).build()
            }
            AsyncImage(
                request, null, contentScale = if (contain) ContentScale.Fit else ContentScale.Crop, alignment = alignment,
                modifier = Modifier.fillMaxSize().then(if (contain) Modifier.background(scheme.surfaceVariant).padding(width * 0.12f) else Modifier), onError = { failed = true },
            )
        }
    }
}

// A grey card standing in for one that's on its way.
@Composable
fun SduiPlaceholder(width: Dp, height: Dp, shape: String) {
    val env = LocalSdui.current
    Column(verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
        val radius = if (shape == "circle") width / 2 else env.pt(CARD_RADIUS)
        if (env.layout.reducedMotion) Box(Modifier.size(width, height).clip(RoundedCornerShape(radius)).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)))
        else Skel(Modifier.size(width, height), radius)
    }
}

private const val CARD_RADIUS = 10

@Composable
private fun Plate(words: String, modifier: Modifier, fill: Color = LocalExtraColours.current.scrim.copy(alpha = 0.68f), ink: Color = ON_IMAGE) {
    val env = LocalSdui.current
    Box(modifier.heightIn(min = env.pt(if (env.tv) 34 else 20)).widthIn(min = env.pt(if (env.tv) 34 else 20)).clip(RoundedCornerShape(env.pt(if (env.tv) 8 else 4))).background(fill).padding(horizontal = env.pt(if (env.tv) 10 else 6)), contentAlignment = Alignment.Center) {
        Text(words, color = ink, fontSize = env.size(if (env.layout.text.containsKey("badge")) "badge" else "caption"), fontWeight = FontWeight.Bold, letterSpacing = 0.02.em, maxLines = 1)
    }
}

@Composable
private fun BoxScope.CardProgress(percent: Int) {
    val env = LocalSdui.current
    val high = env.pt(if (env.tv) 6 else 3)
    Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(high).background(Color(0x47FFFFFF))) {
        Box(Modifier.fillMaxWidth(percent.coerceIn(0, 100) / 100f).height(high).background(MaterialTheme.colorScheme.primary))
    }
}

// What a long press on a card offers on a touch screen: the card's own action, and what can be done with the title
// without opening it. Made from what the card carries; nothing here knows what kind of page it is on.
private class CardChoice(val words: String, val icon: ImageVector, val action: SduiAction)

private fun cardChoices(view: SduiView): List<CardChoice> {
    val p = view.props
    val out = ArrayList<CardChoice>()
    view.node.action?.let { out += CardChoice("Open", WebIcons.Info, it) }
    val play = p.str("playId")
    val item = p.str("itemId")
    if (play.isNotEmpty()) {
        out += CardChoice("Play", WebIcons.Play, SduiAction(type = "play", item = play))
        if (view.progress != null) out += CardChoice("Play from the start", WebIcons.Prev, SduiAction(type = "play", item = play, params = JsonObject(mapOf("resume" to JsonPrimitive(false)))))
    }
    if (item.toLongOrNull() != null || item.startsWith("show-")) {
        if (p.str("kind") in LISTABLE) out += CardChoice("Watch later", SduiSymbols.Clock, SduiAction(type = "command", op = "watchLater.add", item = item))
    }
    if (play.isNotEmpty() && play.toLongOrNull() != null && p.str("kind") in WATCHABLE) {
        out += if (p["watched"] == JsonPrimitive(true)) CardChoice("Mark unwatched", WebIcons.Check, SduiAction(type = "command", op = "watched.clear", item = play))
        else CardChoice("Mark watched", WebIcons.Check, SduiAction(type = "command", op = "watched.set", item = play))
    }
    return out
}

private val LISTABLE = setOf("movie", "show", "episode", "video")
private val WATCHABLE = setOf("movie", "episode", "video")

// One card. `parent` is the row or grid it is in, which says how big its picture is and whether titles are shown.
@Composable
fun SduiCard(view: SduiView, parent: SduiView?, width: Dp, modifier: Modifier = Modifier, grow: SduiGrow? = null) {
    val env = LocalSdui.current
    val p = view.props
    val known = SduiCardStyles.named(p.str("style"))
    val shape = known?.shape?.ifEmpty { null } ?: p.str("shape").ifEmpty { "poster" }
    SduiScoped(view, parent) {
        if (shape == "chip") {
            SduiChip(view, modifier)
            return@SduiScoped
        }
        val scheme = MaterialTheme.colorScheme
        val extra = LocalExtraColours.current
        val style = known?.style.orEmpty()
        val image = p.image("image")
        // The picture's shape: the row's own card where it gives one, else the style's, else the picture's.
        val aspect = parent?.takeIf { it.cardWidth > 0 && it.cardHeight > 0 }?.let { it.cardWidth.toFloat() / it.cardHeight }
            ?: aspectOf(known?.aspect.orEmpty()).takeIf { it > 0f } ?: aspectOf(image?.aspect.orEmpty()).takeIf { it > 0f }
            ?: when (shape) { "landscape" -> 16f / 9f; "square", "circle" -> 1f; else -> 2f / 3f }
        val round = shape == "circle"
        val corner: Shape = if (round) CircleShape else RoundedCornerShape(env.pt(CARD_RADIUS))
        // A card with no action is a stop for focus only when the page's focus plan says so or its row says `focusable` (a friend).
        val focusing = SduiFocusRules.focusable(view)
        val pick = SduiItemActions.select(view)
        var menu by remember { mutableStateOf(false) }
        val choices = remember(view) { if (env.tv) emptyList() else cardChoices(view) }
        val tile = style == "tile"
        val reduce = LocalReduceMotion.current || env.layout.reducedMotion
        val scale by androidx.compose.animation.core.animateFloatAsState(
            if (grow != null && grow.selected && !reduce) grow.scale else 1f, if (reduce) androidx.compose.animation.core.snap() else androidx.compose.animation.core.tween(180), label = "grow",
        )
        // The focused card grows from its leading edge and the cards after it step aside by what it gained.
        val aside = if (grow == null) 0.dp else width * (scale - 1f)
        val ringed = grow != null && grow.selected && reduce
        Box(
            modifier.padding(end = aside).width(width).graphicsLayer { scaleX = scale; scaleY = scale; transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 0f) }
                .then(if (grow == null) Modifier else Modifier.sduiSelects(grow, view.id)).sduiPadKeys(view),
        ) {
            Pressable(
                { if (grow != null && grow.tapSelects && !grow.selected) grow.onSelect() else env.act(pick) }, Modifier.width(width).then(if (ringed) Modifier.border(env.pt(3), scheme.primary, corner) else Modifier), shape = if (round) RoundedCornerShape(env.pt(CARD_RADIUS)) else corner, label = view.label,
                focusKey = view.id.takeIf { env.tv }, requestFocus = env.tv && view.id == env.screen.focus.default, enabled = focusing,
                pressScale = 0.975f, disabledAlpha = 1f, ring = env.tv, clip = false,
                onLongClick = if (choices.size > 1) ({ menu = true }) else null, longClickLabel = "More",
            ) {
                Column(Modifier.width(width).clearAndSetSemantics { }, horizontalAlignment = if (round) Alignment.CenterHorizontally else Alignment.Start) {
                    Box(
                        Modifier.fillMaxWidth().aspectRatio(aspect).then(if (env.tv) Modifier else Modifier.restingShadow(env.pt(CARD_RADIUS))).clip(corner).background(scheme.surfaceVariant)
                            .then(if (tile && image == null) Modifier.background(scheme.surface).border(1.dp, scheme.outline, corner) else Modifier),
                    ) {
                        if (tile && image == null) {
                            // A library or a collection without a picture: its icon on the accent, as the app's own tiles are.
                            Box(Modifier.padding(env.pt(if (env.tv) 24 else 12)).size(env.pt(if (env.tv) 76 else 38)).clip(RoundedCornerShape(env.pt(CARD_RADIUS))).background(scheme.primary.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
                                Icon(sduiIcon(p.str("icon").ifEmpty { p.str("kind") }), null, tint = extra.accentText, modifier = Modifier.size(env.pt(if (env.tv) 40 else 20)))
                            }
                        } else if (image == null && p.str("kind") == "person") {
                            // A person without a photo: their initials on the page's third background, as the spec has it.
                            Box(Modifier.fillMaxSize().background(scheme.surfaceVariant).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                                Text(initials(p.str("title")), color = scheme.onSurfaceVariant, fontSize = env.size("heading"), fontWeight = FontWeight.SemiBold)
                            }
                        } else {
                            // A channel's logo is fitted inside a plain tile; everything else fills its card.
                            SduiPicture(image, width, aspect, if (image == null && p.str("icon").isNotEmpty()) sduiIcon(p.str("icon")) else sduiKindIcon(p.str("kind")), Modifier.fillMaxSize(), contain = image?.kind == "logo")
                        }
                        if (tile) {
                            // The name over the picture, on a shade from the foot so it reads on any picture.
                            if (image != null) Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.4f to Color.Transparent, 1f to extra.scrim.copy(alpha = 0.8f))))
                            Column(Modifier.align(Alignment.BottomStart).padding(env.pt(if (env.tv) 24 else 12))) {
                                view.text["title"]?.let { Text(it, color = if (image != null) ON_IMAGE else scheme.onBackground, fontSize = env.size("body"), fontWeight = FontWeight.SemiBold, maxLines = view.line("title", 1), overflow = TextOverflow.Ellipsis) }
                                view.text["count"]?.let { Text(countWords(it, p.str("kind")), color = if (image != null) ON_IMAGE.copy(alpha = 0.8f) else extra.hint, fontSize = env.size("caption"), maxLines = 1) }
                            }
                        }
                        val edge = env.pt(if (env.tv) 14 else 8)
                        // A person's badge is their presence: a dot on the avatar in the style's tone, the same on every app.
                        val presence = if (style == "person") SduiPresence.tone(style, p.strings("badges")) else ""
                        if (presence.isNotEmpty()) PresenceDot(presence, Modifier.align(Alignment.BottomEnd).padding(edge / 2))
                        else view.text["badges"]?.let { Plate(it, Modifier.align(Alignment.TopStart).padding(edge)) }
                        view.text["number"]?.let { Plate(it, Modifier.align(Alignment.TopStart).padding(edge)) }
                        view.text["unwatched"]?.let { Plate(it, Modifier.align(Alignment.TopEnd).padding(edge), scheme.primary, scheme.onPrimary) }
                        if ("watched" in view.shows) Box(Modifier.align(Alignment.TopEnd).padding(edge).size(env.pt(if (env.tv) 34 else 20)).clip(CircleShape).background(extra.scrim.copy(alpha = 0.68f)), contentAlignment = Alignment.Center) {
                            Icon(WebIcons.Check, null, tint = ON_IMAGE, modifier = Modifier.size(env.pt(if (env.tv) 24 else 14)))
                        }
                        view.text["rank"]?.let {
                            Text(it, color = ON_IMAGE, fontSize = env.size("pageTitle") * 1.6f, fontWeight = FontWeight.Black, modifier = Modifier.align(Alignment.BottomStart).padding(start = edge), style = MaterialTheme.typography.display.copy(shadow = androidx.compose.ui.graphics.Shadow(Color.Black, blurRadius = 12f)))
                        }
                        if ("progress" in view.shows) view.progress?.let { CardProgress(it) }
                        if (!env.tv && !tile) Box(Modifier.fillMaxSize().border(1.dp, Color(0x14FFFFFF), corner))
                    }
                    if (!tile) CardWords(view, round)
                }
            }
            // The app's own sheet, as its other menus are.
            if (menu) WebSheet(p.str("title"), { menu = false }, fromRight = false) {
                SheetRows(choices.map { choice -> SheetRow(choice.words, choice.icon) { env.act(choice.action) } }, { menu = false })
            }
        }
    }
}

private fun countWords(count: String, kind: String): String = when {
    kind == "collection" -> if (count == "1") "1 title" else "$count titles"
    count == "1" -> "1 item"
    else -> "$count items"
}

// The words under a card's picture: each part the style shows, in its order, cut at the lines it allows.
@Composable
private fun CardWords(view: SduiView, centred: Boolean) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val align = if (centred) TextAlign.Center else TextAlign.Start
    var first = true
    @Composable
    fun line(words: String, lines: Int, title: Boolean) {
        // The title in the title size and the rest in the caption size, as the specification says for every device.
        Text(
            words, color = if (title) scheme.onBackground else hint, fontSize = env.size(if (title) "title" else "caption"),
            fontWeight = if (title) FontWeight.SemiBold else FontWeight.Normal, maxLines = lines.coerceAtLeast(1), overflow = TextOverflow.Ellipsis, textAlign = align,
            modifier = Modifier.fillMaxWidth().padding(top = env.pt(if (first) (if (env.tv) 14 else 8) else (if (env.tv) 4 else 2))),
        )
        first = false
    }
    for (part in view.shows) {
        val words = view.text[part] ?: continue
        when (part) {
            "title" -> line(words, view.line("title", 1), title = true)
            "subtitle", "synopsis", "remaining" -> line(words, view.line(part, 1), title = false)
            "now" -> line(words, view.line(part, 1), title = false)
            "next" -> line("Next: $words", view.line(part, 1), title = false)
        }
    }
}

// A pill with a name alone: a genre.
@Composable
private fun SduiChip(view: SduiView, modifier: Modifier) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    Pressable(
        { env.act(view.node.action) }, modifier, shape = Radius.FULL, fill = scheme.surfaceVariant, label = view.label,
        focusKey = view.id.takeIf { env.tv }, requestFocus = env.tv && view.id == env.screen.focus.default, ring = env.tv,
    ) {
        Box(Modifier.heightIn(min = env.pt(if (env.tv) 66 else 44)).padding(horizontal = env.pt(if (env.tv) 32 else 16)), contentAlignment = Alignment.Center) {
            Text(view.text["title"].orEmpty(), color = scheme.onBackground, fontSize = env.size("body"), fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// Up to two initials of a name, for a person without a photo.
internal fun initials(name: String): String =
    name.split(' ', '-').filter { it.isNotBlank() }.let { words -> (words.take(1) + words.drop(1).takeLast(1)).joinToString("") { it.take(1).uppercase() } }
