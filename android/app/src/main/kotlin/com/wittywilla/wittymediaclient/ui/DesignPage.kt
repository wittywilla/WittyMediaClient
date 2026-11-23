// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.input.key.onPreviewKeyEvent
import kotlinx.coroutines.launch
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

// Design 2's page for the app's own feature screens (the design canvas, Exp.dc.html table `gp`: connect, away,
// pairing, profiles, screen time, Play on…, watch party, skipping, Why this title, karaoke, modules, downloads,
// notices…): a small eyebrow, a big title, a lead line, then sections of rows, chips, notes or cards, the actions and a
// foot line. The same sections and words on a TV, a tablet and a phone; one column on a phone. Drawn only from the
// theme in force (its colours and corners) and W4's controls (Pressable, WittyButton); the twin of Apple's DesignPage.
// Every part that can be pressed has a test tag `design.<id>`, the id made from its words.

/** The sizes of a Design 2 page on this device: TV units on a TV (as Apple TV's), points on a phone or tablet. */
data class DesignSizes(
    val title: TextUnit, val body: TextUnit, val small: TextUnit, val tiny: TextUnit,
    val rowHeight: Dp, val chipHeight: Dp, val gap: Dp, val gap2: Dp, val leadWidth: Dp, val columns: Int,
    val phone: Boolean,
) {
    companion object {
        fun of(metrics: Metrics, widthDp: Float): DesignSizes {
            if (metrics.tv) {
                fun t(n: Int) = (n * metrics.unit).sp
                return DesignSizes(t(64), t(29), t(24), t(20), metrics.u(88), metrics.u(60), metrics.u(16), metrics.u(40), metrics.u(1100), 4, phone = false)
            }
            val tablet = WindowClasses.of(widthDp.toInt()) != WindowClass.Compact
            return DesignSizes(
                if (tablet) 40.sp else 30.sp, 17.sp, 15.sp, 13.sp, if (tablet) 56.dp else 52.dp, 36.dp, 10.dp,
                if (tablet) 28.dp else 22.dp, 620.dp, if (tablet) 3 else 2, phone = !tablet,
            )
        }
    }
}

val LocalDesignSizes = compositionLocalOf { DesignSizes.of(PhoneMetrics, 390f) }

/** A part's id from its words, for tests and for a screen's focus memory: "Show saved servers first" → show-saved-servers-first. */
fun designId(words: String): String = com.wittywilla.wittymediaclient.net.DesignPageSpec.slug(words)

/**
 * A whole screen: eyebrow, title and lead, then [content] (its sections), the [actions] and the [foot] line, scrolling.
 * Wide screens keep it to a readable column; a TV keeps it inside its safe area.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DesignPage(
    title: String,
    modifier: Modifier = Modifier,
    eyebrow: String = "",
    lead: String = "",
    foot: String = "",
    tag: String = "",
    actions: (@Composable FlowRowScope.() -> Unit)? = null,
    // Above the eyebrow: a server's lockup (its logo and coloured name) or a person's face, on the sign-in screens.
    top: (@Composable () -> Unit)? = null,
    // The top, title and lead centred over the page, as Design 2's Choose a server has them.
    centred: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val metrics = LocalMetrics.current
    val pageScroll = rememberScrollState()
    BoxWithConstraints(modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).then(if (tag.isNotEmpty()) Modifier.testTag("design.$tag") else Modifier)) {
        val sizes = DesignSizes.of(metrics, maxWidth.value)
        CompositionLocalProvider(LocalDesignSizes provides sizes) {
            Column(
                // Clear of the status and navigation bars when nothing around it is (DesignScreen already is, and
                // what it took is used up, so nothing is padded twice); the background still runs under them.
                Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(pageScroll).tvPageTop(metrics.tv, pageScroll)
                    .padding(horizontal = if (metrics.tv) metrics.u(DesignTokens.Tv.gutter.toInt()) else metrics.gutter, vertical = if (metrics.tv) metrics.u(60) else Space.S6),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(Modifier.fillMaxWidth().then(if (metrics.tv) Modifier else Modifier.widthIn(max = 760.dp))) {
                    if (top != null) Box(Modifier.fillMaxWidth().padding(bottom = sizes.gap * 1.6f), contentAlignment = if (centred) Alignment.Center else Alignment.TopStart) { top() }
                    DesignHead(title, eyebrow, lead, if (centred) Modifier.fillMaxWidth() else Modifier, centred = centred)
                    content()
                    DesignActions(foot, actions)
                }
            }
        }
    }
}

/**
 * A [DesignPage] that is a screen of its own in the app's stack: the system's Back (and a remote's) goes [onBack], and a
 * phone or a tablet has the back arrow above the page. A TV has its remote's Back alone.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DesignScreen(
    title: String,
    onBack: () -> Unit,
    eyebrow: String = "",
    lead: String = "",
    foot: String = "",
    tag: String = "",
    actions: (@Composable FlowRowScope.() -> Unit)? = null,
    top: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    BackHandler { onBack() }
    if (LocalMetrics.current.tv) {
        DesignPage(title, eyebrow = eyebrow, lead = lead, foot = foot, tag = tag, actions = actions, top = top, content = content)
        return
    }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).safeDrawingPadding().imePadding()) {
        BackArrow(onBack, Modifier.padding(Space.S1))
        DesignPage(title, Modifier.weight(1f), eyebrow = eyebrow, lead = lead, foot = foot, tag = tag, actions = actions, top = top, content = content)
    }
}

/**
 * The page's sizes for Design 2's parts drawn outside a [DesignPage]: a section inside another page (an item's), or an
 * overlay over the picture, so they are TV-sized on a TV and phone-sized on a phone.
 */
@Composable
fun DesignSized(content: @Composable () -> Unit) {
    val sizes = DesignSizes.of(LocalMetrics.current, LocalConfiguration.current.screenWidthDp.toFloat())
    CompositionLocalProvider(LocalDesignSizes provides sizes) { content() }
}

/** The page's eyebrow, title and lead, for a screen that has its own frame (a sheet, a panel inside a page). */
@Composable
fun DesignHead(title: String, eyebrow: String = "", lead: String = "", modifier: Modifier = Modifier, centred: Boolean = false) {
    val s = LocalDesignSizes.current
    val scheme = MaterialTheme.colorScheme
    val align = if (centred) androidx.compose.ui.text.style.TextAlign.Center else null
    Column(modifier, horizontalAlignment = if (centred) Alignment.CenterHorizontally else Alignment.Start) {
        if (eyebrow.isNotEmpty()) {
            Text(
                eyebrow.uppercase(), color = LocalExtraColours.current.accentText, fontSize = s.small, fontWeight = FontWeight.Bold,
                letterSpacing = 0.08.em, modifier = Modifier.padding(bottom = s.gap * 0.6f),
            )
        }
        if (title.isNotEmpty()) {
            Text(
                title.replace('\'', '’'), color = scheme.onBackground, fontSize = s.title, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.03).em,
                lineHeight = s.title * 1.1f, textAlign = align, modifier = Modifier.semantics { heading() },
            )
        }
        if (lead.isNotEmpty()) {
            Text(
                lead, color = scheme.onSurfaceVariant, fontSize = s.body, lineHeight = s.body * 1.5f, textAlign = align,
                modifier = Modifier.padding(top = s.gap * 0.6f).widthIn(max = s.leadWidth),
            )
        }
    }
}

/** The actions in a row that wraps, and the foot line after them. Nothing is drawn when there is neither. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DesignActions(foot: String = "", actions: (@Composable FlowRowScope.() -> Unit)? = null) {
    val s = LocalDesignSizes.current
    if (actions != null) {
        FlowRow(
            Modifier.fillMaxWidth().padding(top = s.gap2).remoteRow(),
            horizontalArrangement = Arrangement.spacedBy(s.gap), verticalArrangement = Arrangement.spacedBy(s.gap),
        ) { actions() }
    }
    if (foot.isNotEmpty()) {
        Text(foot, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = s.small, lineHeight = s.small * 1.5f, modifier = Modifier.padding(top = s.gap2 * 0.6f))
    }
}

/** One section: its heading (none when blank), then what's in it, a column of rows or anything else. */
@Composable
fun DesignSection(title: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val s = LocalDesignSizes.current
    Column(modifier.fillMaxWidth().padding(top = s.gap2)) {
        if (title.isNotEmpty()) {
            Text(
                title, color = MaterialTheme.colorScheme.onBackground, fontSize = s.body, fontWeight = FontWeight.ExtraBold,
                modifier = Modifier.padding(bottom = s.gap).semantics { heading() },
            )
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) { content() }
    }
}

/**
 * A row: its words (and a line under them), a value at the end (in the accent's text colour when [on]), or [trailing]
 * in its place. With [onClick] it can be pressed and takes the ring; without, it is only read.
 */
@Composable
fun DesignRow(
    title: String,
    modifier: Modifier = Modifier,
    value: String = "",
    sub: String = "",
    on: Boolean = false,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    enabled: Boolean = true,
    selected: Boolean = false,
    requestFocus: Boolean = false,
    takeFocus: Boolean = false,
    focusRequester: FocusRequester? = null,
    focusKey: String? = null,
    label: String? = null,
    state: String? = null,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val s = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val shape = metrics.corner(10)
    val id = "design." + designId(title)
    val inner: @Composable () -> Unit = {
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = s.rowHeight).padding(horizontal = s.gap * 1.4f, vertical = s.gap * 0.6f),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(s.gap),
        ) {
            if (leading != null) leading()
            Column(Modifier.weight(1f)) {
                Text(title, color = scheme.onSurface, fontSize = s.body, fontWeight = FontWeight.Bold, lineHeight = s.body * 1.3f)
                if (sub.isNotEmpty()) Text(sub, color = scheme.onSurfaceVariant, fontSize = s.tiny, lineHeight = s.tiny * 1.35f)
            }
            if (trailing != null) trailing()
            else if (value.isNotEmpty()) {
                Text(
                    value, color = if (on) LocalExtraColours.current.accentText else scheme.onSurfaceVariant, fontSize = s.small,
                    fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = if (s.phone) 150.dp else metrics.u(420)),
                )
            }
        }
    }
    if (onClick == null) {
        Box(modifier.fillMaxWidth().testTag(id).background(scheme.surface, shape).semantics(mergeDescendants = true) {}) { inner() }
        return
    }
    Pressable(
        onClick, modifier.fillMaxWidth().testTag(id), shape = shape, fill = scheme.surface,
        label = label ?: listOf(title, sub, value).filter { it.isNotEmpty() }.joinToString(", "), state = state, selected = selected,
        focusKey = focusKey ?: id, requestFocus = requestFocus, takeFocus = takeFocus, focusRequester = focusRequester,
        enabled = enabled, grows = false, onLongClick = onLongClick, focusStyle = FocusStyle.RingLift,
    ) { inner() }
}

/** A row that turns something on or off: its value says On or Off, and a press changes it. */
@Composable
fun DesignSwitchRow(
    title: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    sub: String = "",
    enabled: Boolean = true,
    requestFocus: Boolean = false,
) {
    val words = LocalWords.current
    val onWord = words["on"] ?: "On"
    val offWord = words["off"] ?: "Off"
    DesignRow(
        title, modifier, value = if (checked) onWord else offWord, sub = sub, on = checked, onClick = { onChange(!checked) },
        enabled = enabled, requestFocus = requestFocus, label = listOf(title, sub).filter { it.isNotEmpty() }.joinToString(", "),
        state = if (checked) onWord else offWord,
    )
}

/** A row of chips that wraps; Left and Right stay in it on a remote. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DesignChips(modifier: Modifier = Modifier, content: @Composable FlowRowScope.() -> Unit) {
    FlowRow(
        modifier.fillMaxWidth().remoteRow(),
        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
    ) { content() }
}

/** A chip: a pill, filled with the text colour when [on] (chosen), quiet otherwise. On a TV focus fills it. */
@Composable
fun DesignChip(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    on: Boolean = false,
    enabled: Boolean = true,
    requestFocus: Boolean = false,
    focusKey: String? = null,
    label: String? = null,
    // For a chip that has just appeared as the screen's main action (Skip intro over the picture), whatever had focus before.
    takeFocus: Boolean = false,
) {
    val s = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val fill = if (on) scheme.onBackground else scheme.onBackground.copy(alpha = 0.12f)
    Pressable(
        onClick, modifier.testTag("design." + designId(text)), shape = Radius.FULL, fill = fill, label = label ?: text,
        selected = on, enabled = enabled, requestFocus = requestFocus, takeFocus = takeFocus, focusKey = focusKey, focusStyle = FocusStyle.Fill,
    ) { active ->
        val ink = if (on || (active && metrics.focusFill)) scheme.background else scheme.onBackground
        Box(Modifier.defaultMinSize(minHeight = maxOf(s.chipHeight, metrics.minTarget * 0.8f)).padding(horizontal = s.gap * 1.4f), contentAlignment = Alignment.Center) {
            Text(text, color = ink, fontSize = s.small, fontWeight = FontWeight.Bold)
        }
    }
}

/** Words on their own: a plain note, or with [tone] a quiet panel of the accent. [error] marks a problem. */
@Composable
fun DesignNote(text: String, modifier: Modifier = Modifier, tone: Boolean = false, error: Boolean = false, busy: Boolean = false) {
    if (text.isEmpty()) return
    val s = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    // Still waiting (looking for servers, for an answer): a spinner before the words, which are said when they change.
    if (busy) {
        Row(
            modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(s.gap),
        ) {
            Spinner(scheme.onSurfaceVariant, s.small.value.dp * 1.2f)
            DesignNote(text, tone = tone, error = error)
        }
        return
    }
    val fill = when {
        error -> scheme.error.copy(alpha = 0.14f)
        tone -> scheme.primary.copy(alpha = 0.12f)
        else -> Color.Transparent
    }
    Text(
        (if (error) "! " else "") + text, color = if (error) scheme.onBackground else scheme.onSurfaceVariant, fontSize = s.small, lineHeight = s.small * 1.5f,
        modifier = modifier.widthIn(max = s.leadWidth).background(fill, RoundedCornerShape(metrics.u(metrics.themeRadius * 0.7f)))
            .padding(if (tone || error) s.gap else 0.dp)
            .then(if (error) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier),
    )
}

/** Cards in a grid: [columns] across (the page's own count when 0), one column fewer than two on a phone at most. */
@Composable
fun DesignCards(count: Int, modifier: Modifier = Modifier, columns: Int = 0, card: @Composable (index: Int) -> Unit) {
    val s = LocalDesignSizes.current
    val cols = (if (columns > 0) columns else s.columns).let { if (s.phone) minOf(it, 2) else it }.coerceAtLeast(1)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(s.gap * 0.7f)) {
        (0 until count).chunked(cols).forEach { line ->
            // Left and right stop at the row's ends, and up and down go straight to the card above or below: a grid
            // row restores no remembered card, or Down would bring focus back along its own row.
            Row(Modifier.fillMaxWidth().gridRow(), horizontalArrangement = Arrangement.spacedBy(s.gap * 0.7f)) {
                line.forEach { i -> Box(Modifier.weight(1f)) { card(i) } }
                repeat(cols - line.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** A card: a swatch of three colours (none when [swatch] is empty), its name and a line under it. */
@Composable
fun DesignCard(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    sub: String = "",
    swatch: List<Color> = emptyList(),
    on: Boolean = false,
    enabled: Boolean = true,
    // A symbol above the words, for a card that is a way to do something rather than a look or a theme.
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    requestFocus: Boolean = false,
    takeFocus: Boolean = false,
    focusKey: String? = null,
    // A picture of what the card stands for, above its words and in place of the swatch: a look's layout (W4's
    // LayoutThumb), drawn the card's width and as tall as it chooses.
    preview: (@Composable () -> Unit)? = null,
) {
    val s = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    Pressable(
        onClick, modifier.fillMaxWidth().testTag("design." + designId(title)), shape = metrics.corner(10), fill = scheme.surface,
        label = listOf(title, sub).filter { it.isNotEmpty() }.joinToString(", "), selected = on, enabled = enabled, grows = false,
        requestFocus = requestFocus, takeFocus = takeFocus, focusKey = focusKey,
    ) {
        Column(Modifier.fillMaxWidth().defaultMinSize(minHeight = if (icon != null) s.rowHeight * 2 else 0.dp).padding(s.gap * 0.8f)) {
            if (icon != null) {
                androidx.compose.material3.Icon(icon, contentDescription = null, tint = LocalExtraColours.current.accentText, modifier = Modifier.size(s.body.value.dp * 1.6f))
                Spacer(Modifier.height(s.gap * 0.8f))
            }
            if (preview != null) {
                Box(Modifier.fillMaxWidth().clip(metrics.corner(6))) { preview() }
                Spacer(Modifier.height(6.dp))
            } else if (swatch.isNotEmpty()) {
                Row(Modifier.fillMaxWidth().height(s.small.value.dp * 1.6f), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    swatch.forEachIndexed { i, c ->
                        Box((if (i < 2) Modifier.weight(if (i == 0) 2f else 1f) else Modifier.size(s.small.value.dp * 1.6f)).height(s.small.value.dp * 1.6f).background(c, RoundedCornerShape(5.dp)))
                    }
                }
                Spacer(Modifier.height(6.dp))
            }
            Text(title, color = scheme.onSurface, fontSize = s.small, fontWeight = FontWeight.ExtraBold)
            if (sub.isNotEmpty()) Text(sub, color = scheme.onSurfaceVariant, fontSize = s.tiny)
            if (on) Text("✓", color = LocalExtraColours.current.accentText, fontSize = s.small, fontWeight = FontWeight.Bold)
        }
    }
}

// On a TV a page taller than the screen scrolls to keep the focused thing in view, and that left the heading cut off
// at the top with Up unable to bring it back. Up from the topmost control now scrolls the page to its top, and the page
// starts there.
@androidx.compose.runtime.Composable
private fun Modifier.tvPageTop(tv: Boolean, scroll: androidx.compose.foundation.ScrollState): Modifier {
    if (!tv) return this
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    androidx.compose.runtime.LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(400)
        scroll.scrollTo(0)
    }
    return this.onPreviewKeyEvent { e ->
        if (e.type == androidx.compose.ui.input.key.KeyEventType.KeyDown && e.key == androidx.compose.ui.input.key.Key.DirectionUp) {
            val moved = focus.moveFocus(androidx.compose.ui.focus.FocusDirection.Up)
            if (!moved && scroll.value > 0) {
                scope.launch { scroll.animateScrollTo(0) }
                true
            } else moved
        } else false
    }
}
