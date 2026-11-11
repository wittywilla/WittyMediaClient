// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.wittywilla.wittymediaclient.net.SduiClient
import com.wittywilla.wittymediaclient.net.SduiCustomise
import com.wittywilla.wittymediaclient.net.SduiDocument
import com.wittywilla.wittymediaclient.net.SduiPersonalInfo
import com.wittywilla.wittymediaclient.net.SduiPersonalSection
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.str
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// "Customise" for one page (docs/SDUI.md, Personalisation): the page's own sections in the profile's order, to move,
// hide and pin; how tightly the page is packed; how big each row's cards are; the tab a strip opens on. Only what
// the page allows is offered. Every change is saved as it is made (net/SduiPersonal.kt has the rules), so leaving
// any way keeps it. On a touch screen a long press picks a section up; on a TV each row has its own buttons.

// One change at a time, in turn, so an older one never lands after a newer one.
private val savesInTurn = Mutex()

@Composable
fun SduiCustomiseScreen(nav: Nav, client: SduiClient, document: SduiDocument, info: SduiPersonalInfo, done: (changed: Boolean) -> Unit) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    var state by remember { mutableStateOf(SduiCustomise.from(info)) }
    var changed by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf("") }
    // Card sizes and the tab a strip opens on aren't in the page itself: they are read from what the profile saved.
    LaunchedEffect(info.url) {
        val saved = runCatching { client.personal(info.url) }.getOrNull() ?: return@LaunchedEffect
        if (!changed) state = state.copy(cardSize = saved.cardSize, defaultTab = saved.defaultTab, density = state.density.ifEmpty { saved.density })
    }
    fun save(next: SduiCustomise) {
        if (next == state) return
        state = next
        changed = true
        nav.app.scope.launch {
            savesInTurn.withLock {
                try {
                    client.savePersonal(info.url, next.toPersonal())
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (!nav.handleExpired(e)) toast = problemWords(e, "Could not save the layout")
                }
            }
        }
    }
    fun reset() {
        nav.app.scope.launch {
            savesInTurn.withLock {
                try {
                    client.resetPersonal(info.url)
                    done(true)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (!nav.handleExpired(e)) toast = problemWords(e, "Could not reset the layout")
                }
            }
        }
    }

    val scroll = rememberScrollState()
    if (!env.tv) TracksScroll(scroll)
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val side = LocalSduiSpan.current.side.takeIf { env.tv } ?: 16.dp
    // Where each section is on the screen, for dropping one on another.
    val bounds = remember { HashMap<String, ClosedFloatingPointRange<Float>>() }
    var dragging by remember { mutableStateOf<String?>(null) }
    var moved by remember { mutableFloatStateOf(0f) }
    var fingerAt by remember { mutableFloatStateOf(0f) }
    var scrolledFrom by remember { mutableIntStateOf(0) }
    var view by remember { mutableStateOf(0f..0f) }
    val drop by rememberUpdatedState { id: String ->
        val target = bounds.entries.firstOrNull { it.key != id && fingerAt in it.value }?.key
        if (target != null) save(state.moving(id, state.sections.indexOfFirst { it.id == target }.let { at -> if (at > state.sections.indexOfFirst { s -> s.id == id }) at + 1 else at }))
    }
    // Near the top or the foot while carrying a section, the page scrolls along.
    LaunchedEffect(dragging) {
        if (dragging == null) return@LaunchedEffect
        val edge = with(density) { 48.dp.toPx() }
        val step = with(density) { 8.dp.toPx() }
        while (true) {
            val by = when {
                fingerAt < view.start + edge -> -step
                fingerAt > view.endInclusive - edge -> step
                else -> 0f
            }
            if (by != 0f) scroll.scrollBy(by)
            withFrameNanos { }
        }
    }
    val topRoom = if (env.tv) env.space("s") else LocalTopRoom.current
    val bottomRoom = if (env.tv) env.pt(env.layout.safeArea.bottom) else LocalBottomRoom.current
    val home = document.page.kind == "home"
    Box(
        Modifier.fillMaxSize().onGloballyPositioned {
            val top = it.positionInRoot().y
            view = (top + with(density) { topRoom.toPx() })..(top + it.size.height - with(density) { bottomRoom.toPx() })
        },
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(start = side, end = side, top = topRoom, bottom = bottomRoom), verticalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 16 else 12))) {
            // What this is, with Reset and Done.
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(env.pt(if (env.tv) 20 else 10))).background(scheme.surface).border(1.dp, scheme.outline, RoundedCornerShape(env.pt(if (env.tv) 20 else 10))).padding(horizontal = env.pt(if (env.tv) 32 else 14), vertical = env.pt(if (env.tv) 24 else 10)),
                verticalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 16 else 10)),
            ) {
                Text(if (home) "Customize home" else "Customize ${document.page.title}", color = scheme.onSurface, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                val how = when {
                    !state.canReorder && !state.canHide && !state.canPin -> "Choose how this page looks for you."
                    env.tv -> "Move sections up and down, pin the ones you want first, and hide the ones you don't use. Hidden sections stay here until you show them again."
                    else -> "Drag sections, or use the arrows. Hidden sections stay here until you show them again."
                }
                Text(how, color = hint, fontSize = env.size("caption"))
                Row(Modifier.then(if (env.tv) Modifier.remoteRow() else Modifier).align(Alignment.End), horizontalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 16 else 10))) {
                    if (env.tv) {
                        WittyButton("Done", { done(changed) }, kind = ButtonKind.Primary, pill = true, focusKey = "~done", requestFocus = true)
                        WittyButton("Reset", ::reset, pill = true, focusKey = "~reset")
                    } else {
                        WebButton("Reset", ::reset, WebButtonKind.Ghost, small = true)
                        WebButton("Done", { done(changed) }, WebButtonKind.Primary, small = true)
                    }
                }
            }
            val movable = state.sections.filter { state.canMove(it.id) }
            state.sections.forEach { section ->
                key(section.id) {
                    val carried = dragging == section.id
                    val at = movable.indexOfFirst { it.id == section.id }
                    SectionRow(
                        section, state, carried, first = at <= 0, last = at < 0 || at == movable.lastIndex,
                        up = { save(state.nudging(section.id, -1)) }, down = { save(state.nudging(section.id, 1)) },
                        pin = { save(state.togglingPinned(section.id)) }, hide = { save(state.togglingHidden(section.id)) },
                        modifier = Modifier
                            .zIndex(if (carried) 0.5f else 0f)
                            .graphicsLayer { if (carried) translationY = moved + (scroll.value - scrolledFrom) }
                            .onGloballyPositioned { where -> val top = where.positionInRoot().y; bounds[section.id] = top..(top + where.size.height) }
                            .then(
                                if (env.tv || !state.canMove(section.id)) Modifier else Modifier.pointerInput(section.id) {
                                    detectDragGesturesAfterLongPress(
                                        onDragStart = { from ->
                                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                            dragging = section.id
                                            moved = 0f
                                            scrolledFrom = scroll.value
                                            fingerAt = (bounds[section.id]?.start ?: 0f) + from.y
                                        },
                                        onDragEnd = { drop(section.id); dragging = null },
                                        onDragCancel = { dragging = null },
                                        onDrag = { change, by ->
                                            change.consume()
                                            moved += by.y
                                            fingerAt += by.y
                                        },
                                    )
                                },
                            ),
                    )
                }
            }
            if (state.canDensity) {
                ChoiceGroup("Spacing", "How tightly the page is packed.")
                Choices(listOf("compact" to "Compact", "comfortable" to "Comfortable", "spacious" to "Spacious"), state.density.ifEmpty { env.layout.density.ifEmpty { "comfortable" } }, "~density") { save(state.withDensity(it)) }
            }
            if (state.canCardSize) {
                val sized = remember(document) { SduiCustomise.sizeChoices(document.root) }
                if (sized.isNotEmpty()) ChoiceGroup("Card size", "How big each row's cards are.")
                sized.forEach { (node, size) ->
                    val name = state.sections.firstOrNull { it.id == node.id }?.title?.ifEmpty { null } ?: node.props.str("title").ifEmpty { node.id }
                    ChoiceLine(name) { Choices(listOf("s" to "Small", "m" to "Medium", "l" to "Large"), state.cardSize[node.id] ?: size, "~size~" + node.id) { save(state.withCardSize(node.id, it)) } }
                }
            }
            if (state.canDefaultTab) {
                val strips = remember(document, state.defaultTab) { SduiCustomise.tabChoices(document.root, state.defaultTab) }
                if (strips.isNotEmpty()) ChoiceGroup("Opens on", "The tab this page shows first.")
                strips.forEach { strip -> Choices(strip.options, strip.selected, "~tab~" + strip.tabs) { save(state.withDefaultTab(strip.tabs, it)) } }
            }
            if (!env.tv) PageFoot(nav)
        }
        if (toast.isNotEmpty()) Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = bottomRoom))
    }
}

// One section: its name, and what may be done with it. Hidden, it is faded; carried, more so.
@Composable
private fun SectionRow(
    section: SduiPersonalSection, state: SduiCustomise, carried: Boolean, first: Boolean, last: Boolean,
    up: () -> Unit, down: () -> Unit, pin: () -> Unit, hide: () -> Unit, modifier: Modifier,
) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val name = section.title.ifEmpty { section.id }
    val can = state.canMove(section.id)
    val corner = RoundedCornerShape(env.pt(if (env.tv) 24 else 14))
    Row(
        modifier.fillMaxWidth().alpha(if (carried) 0.4f else if (section.hidden) 0.55f else 1f).clip(corner).background(scheme.surface)
            .then(if (env.tv) Modifier.border(1.dp, scheme.outline, corner).remoteRow() else Modifier.dashedBorder(scheme.onBackground.copy(alpha = 0.2f), 14.dp))
            .padding(horizontal = env.pt(if (env.tv) 32 else 12), vertical = env.pt(if (env.tv) 16 else 8)),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 16 else 8)),
    ) {
        if (!env.tv) Icon(if (section.pinned) SduiSymbols.Pin else WebIcons.Grip, null, tint = if (can || section.pinned) hint else Color.Transparent, modifier = Modifier.size(18.dp))
        Column(Modifier.weight(1f)) {
            Text(name, color = scheme.onBackground, fontSize = env.size(if (env.tv) "body" else "caption") * (if (env.tv) 1f else 1.15f), fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val note = when {
                section.locked -> "Always here"
                section.hidden -> "Hidden"
                section.pinned -> "Pinned to the top"
                section.empty -> "Nothing to show here right now"
                else -> ""
            }
            if (note.isNotEmpty()) Text(note, color = hint, fontSize = env.size("caption"))
        }
        if (section.locked) return@Row
        if (state.canReorder && !section.pinned) {
            RowButton("Move $name up", WebIcons.Up, section.id + "~up", enabled = can && !first, onClick = up)
            RowButton("Move $name down", WebIcons.Down, section.id + "~down", enabled = can && !last, onClick = down)
        }
        if (state.canPin) RowButton(if (section.pinned) "Unpin $name" else "Pin $name to the top", SduiSymbols.Pin, section.id + "~pin", on = section.pinned, onClick = pin)
        if (state.canHide) {
            if (env.tv) WittyButton(if (section.hidden) "Show" else "Hide", hide, focusKey = section.id + "~hide")
            else WebButton(if (section.hidden) "Show" else "Hide", hide, WebButtonKind.Secondary, small = true, spoken = (if (section.hidden) "Show " else "Hide ") + name)
        }
    }
}

// A square button of a row: an arrow, the pin. `on` is for one that is switched on.
@Composable
private fun RowButton(spoken: String, icon: ImageVector, focusKey: String, enabled: Boolean = true, on: Boolean = false, onClick: () -> Unit) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    if (!env.tv) {
        WebButton(spoken, onClick, if (on) WebButtonKind.Primary else WebButtonKind.Ghost, icon, small = true, square = true, enabled = enabled)
        return
    }
    Pressable(onClick, shape = Radius.FULL, fill = if (on) scheme.primary else scheme.surfaceVariant, label = spoken, state = if (on) "On" else null, enabled = enabled, focusKey = focusKey) {
        Box(Modifier.size(env.pt(66)), contentAlignment = Alignment.Center) { Icon(icon, null, tint = if (on) scheme.onPrimary else scheme.onSurface, modifier = Modifier.size(env.pt(34))) }
    }
}

@Composable
private fun ChoiceGroup(title: String, words: String) {
    val env = LocalSdui.current
    Column(Modifier.padding(top = env.space("s"))) {
        Text(title, color = MaterialTheme.colorScheme.onBackground, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        Text(words, color = LocalExtraColours.current.hint, fontSize = env.size("caption"))
    }
}

@Composable
private fun ChoiceLine(name: String, content: @Composable () -> Unit) {
    val env = LocalSdui.current
    Column(verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
        Text(name, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis)
        content()
    }
}

// One of a few, side by side: the chosen one filled.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Choices(options: List<Pair<String, String>>, current: String, focusKey: String, choose: (String) -> Unit) {
    val env = LocalSdui.current
    FlowRow((if (env.tv) Modifier.remoteRow() else Modifier), horizontalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 16 else 8)), verticalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 16 else 8))) {
        options.forEach { (value, label) ->
            val on = value == current
            if (env.tv) WittyButton(label, { choose(value) }, kind = if (on) ButtonKind.Primary else ButtonKind.Secondary, pill = true, focusKey = "$focusKey~$value")
            else WebButton(label, { choose(value) }, if (on) WebButtonKind.Primary else WebButtonKind.Secondary, small = true, spoken = if (on) "$label, selected" else label)
        }
    }
}
