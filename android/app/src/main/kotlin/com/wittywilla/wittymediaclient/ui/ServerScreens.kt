// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.content.Context
import android.os.Build
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import com.wittywilla.wittymediaclient.data.LogoCache
import com.wittywilla.wittymediaclient.data.STALE_CHOICES
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.data.fill
import com.wittywilla.wittymediaclient.data.focusAfterRemoval
import com.wittywilla.wittymediaclient.data.isStale
import com.wittywilla.wittymediaclient.data.manageOrder
import com.wittywilla.wittymediaclient.data.namesOf
import com.wittywilla.wittymediaclient.data.notReachedFor
import com.wittywilla.wittymediaclient.data.reachedWords
import com.wittywilla.wittymediaclient.data.shownName
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

// Removing servers this device remembers: what the list of servers and Manage servers share. Every removal goes
// through Nav.forgetServer. A phone or tablet removes at once and offers Undo; a TV asks first, as it has no Undo.

private const val UNDO_MS = 6000

// How long Undo is offered: longer for someone who has asked the device for more time to act.
private fun undoMs(context: Context): Long {
    val manager = context.getSystemService(AccessibilityManager::class.java)
    if (manager == null || Build.VERSION.SDK_INT < 29) return UNDO_MS.toLong()
    val both = AccessibilityManager.FLAG_CONTENT_TEXT or AccessibilityManager.FLAG_CONTENT_CONTROLS
    return manager.getRecommendedTimeoutMillis(UNDO_MS, both).toLong()
}

// "Removed {name}." with Undo, near the bottom, for as long as Nav still holds the removal. Leaving the screen
// it's on ends the offer, and so does the app going to the background (see AppRoot). After Undo it says so.
@Composable
fun UndoRemoval(nav: Nav, s: Map<String, String>, modifier: Modifier = Modifier, onUndone: (SavedServer) -> Unit) {
    val context = LocalContext.current
    val metrics = LocalMetrics.current
    val gone = nav.pendingForget
    var back by remember { mutableStateOf("") }
    DisposableEffect(Unit) { onDispose { nav.finishForget() } }
    if (gone == null) {
        Toast(back, { back = "" }, modifier)
        return
    }
    LaunchedEffect(gone) {
        delay(undoMs(context))
        nav.finishForget()
    }
    Row(
        modifier
            .clip(Radius.FULL)
            .background(MaterialTheme.colorScheme.surface)
            .padding(start = metrics.u(20), end = metrics.u(8))
            .semantics { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(metrics.u(8)),
    ) {
        Text(
            fill(s["removedServer"], "name" to shownName(gone.server)), color = MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.label, maxLines = 2, modifier = Modifier.weight(1f, fill = false),
        )
        WittyButton(
            s["undo"].orEmpty(),
            {
                nav.undoForget()?.let {
                    back = fill(s["removeUndone"], "name" to shownName(it))
                    onUndone(it)
                }
            },
            kind = ButtonKind.Quiet, focusKey = "undo-remove",
        )
    }
}

// Something that went as asked, in `ok` with a check: what was just removed, on the list of servers.
@Composable
fun Notice(text: String, modifier: Modifier = Modifier) {
    if (text.isEmpty()) return
    val ok = LocalExtraColours.current.ok
    val metrics = LocalMetrics.current
    Row(
        modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8)),
    ) {
        Icon(Symbols.Check, contentDescription = null, tint = ok, modifier = Modifier.size(metrics.u(if (metrics.tv) 30 else 20)))
        Text(text, color = ok, style = MaterialTheme.typography.body)
    }
}

// The bin on a card or a row: removes that server. `label` says which, for a screen reader.
@Composable
fun RemoveButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier, takeFocus: Boolean = false, focusKey: String? = null) {
    val metrics = LocalMetrics.current
    Pressable(onClick, modifier.size(metrics.minTarget), shape = CircleShape, label = label, takeFocus = takeFocus, focusKey = focusKey) {
        Icon(Symbols.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(metrics.u(22)))
    }
}

// "Remove {name}?", with what that means, and that it signs out when the server is the one in use.
@Composable
fun ConfirmRemove(s: Map<String, String>, server: SavedServer, inUse: Boolean, onYes: () -> Unit, onNo: () -> Unit) {
    val name = shownName(server)
    val body = fill(s["removeConfirmBody"], "name" to name, "address" to server.url) + if (inUse) "\n\n" + s["removeConfirmInUse"] else ""
    Confirm(body, s["remove"].orEmpty(), s["cancel"].orEmpty(), onYes, onNo, title = fill(s["removeConfirmTitle"], "name" to name))
}

// A card that a finger can push off either side to remove it. The same is on the card's long-press menu, in
// Edit, and among a screen reader's actions, so nothing depends on the swipe.
@Composable
fun SwipeToRemove(words: String, onRemove: () -> Unit, content: @Composable () -> Unit) {
    val scope = rememberCoroutineScope()
    val metrics = LocalMetrics.current
    val danger = MaterialTheme.colorScheme.error
    val offset = remember { Animatable(0f) }
    var width by remember { mutableIntStateOf(0) }
    Box(Modifier.fillMaxWidth().onSizeChanged { width = it.width }) {
        if (offset.value != 0f) {
            Box(
                Modifier.matchParentSize().clip(metrics.corner(14)).background(danger.copy(alpha = 0.16f)).padding(horizontal = metrics.u(16)),
                contentAlignment = if (offset.value > 0) Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                    Icon(Symbols.Delete, contentDescription = null, tint = danger, modifier = Modifier.size(metrics.u(20)))
                    Text(words, color = danger, style = MaterialTheme.typography.label)
                }
            }
        }
        Box(
            Modifier
                .offset { IntOffset(offset.value.roundToInt(), 0) }
                .draggable(
                    rememberDraggableState { moved -> scope.launch { offset.snapTo(offset.value + moved) } },
                    Orientation.Horizontal,
                    onDragStopped = { speed ->
                        val far = abs(offset.value) > width * SWIPE_PART || (abs(speed) > SWIPE_SPEED && speed * offset.value > 0)
                        if (far && width > 0) {
                            offset.animateTo(if (offset.value > 0) width.toFloat() else -width.toFloat())
                            onRemove()
                        } else {
                            offset.animateTo(0f)
                        }
                    },
                ),
        ) { content() }
    }
}

private const val SWIPE_PART = 0.4f
private const val SWIPE_SPEED = 2500f

// Manage servers: every server this device remembers, with when it was last reached. One can be removed, or all,
// or those not reached for a time the person chooses, and they see which before anything goes. Nothing is ever
// removed on its own. Reached from the list of servers, and from You, where the server in use is in the list too.
@Composable
fun ManageServersScreen(nav: Nav, s: Map<String, String>) {
    val context = LocalContext.current
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val memory = LocalFocusMemory.current
    val tv = metrics.tv
    var servers by remember { mutableStateOf(manageOrder(nav.app.store.recent)) }
    var asking by remember { mutableStateOf<SavedServer?>(null) }
    var askingAll by remember { mutableStateOf(false) }
    var choosing by remember { mutableStateOf(false) }
    // The time chosen, in days, and the servers that is.
    var old by remember { mutableStateOf<Pair<Int, List<SavedServer>>?>(null) }
    var done by remember { mutableStateOf("") }
    var focusOn by remember { mutableStateOf<String?>(null) }
    val now = remember(servers) { System.currentTimeMillis() }

    fun keyOf(server: SavedServer) = "server-${server.url}"

    // Focus goes to the next row, else the one before, else Back: never nowhere.
    fun moveFocus(from: List<SavedServer>, removed: SavedServer) {
        val next = focusAfterRemoval(from.map(::keyOf), keyOf(removed)) ?: "servers-back"
        memory.last = next
        scope.launch {
            focusOn = null
            withFrameNanos { }
            focusOn = next
        }
    }

    // One at once, with Undo: for a server that isn't in use, on a phone or tablet.
    fun removeNow(server: SavedServer) {
        val before = servers
        done = ""
        nav.forgetServer(server, undoable = true)
        servers = manageOrder(nav.app.store.recent)
        moveFocus(before, server)
    }

    // After a yes: no Undo. Removing the one in use signs out and ends at the list of servers, which says so.
    fun removeAsked(list: List<SavedServer>) {
        if (list.isEmpty()) return
        val before = servers
        val said = if (list.size == 1) fill(s["removedServer"], "name" to shownName(list[0])) else fill(s["removedCount"], "count" to list.size.toString())
        val leaves = list.any(nav::uses)
        if (leaves) nav.pickerNotice = said
        // The one in use last: removing it closes this screen.
        list.sortedBy(nav::uses).forEach { nav.forgetServer(it, undoable = false) }
        if (leaves) return
        done = said
        servers = manageOrder(nav.app.store.recent)
        moveFocus(before, list[0])
    }

    Box(Modifier.fillMaxSize()) {
        SettingsPage(nav, s["manageServers"].orEmpty(), s["manageServersHint"].orEmpty()) {
            if (servers.isEmpty()) {
                Note(s["noServersRemembered"].orEmpty())
                WittyButton(s["back"].orEmpty(), nav::pop, Modifier.fillMaxWidth(), tall = true, requestFocus = true, takeFocus = focusOn == "servers-back", focusKey = "servers-back")
            } else {
                GroupedList(
                    "",
                    servers.mapIndexed { i, server ->
                        val name = shownName(server)
                        val stale = isStale(server.lastSeen, now, nav.app.store.recentSince)
                        GroupRow(
                            title = name,
                            detail = server.url + " · " + reachedWords(s, server.lastSeen, now),
                            leading = { ServerMark(metrics.u(if (tv) 40 else 32), LogoCache.file(context, server.url, server.brandLogo)) },
                            // On a TV the row itself is pressed, then asked; a phone has the button.
                            onClick = if (tv) { { asking = server } } else null,
                            chevron = false,
                            focusKey = keyOf(server),
                            requestFocus = tv && i == 0,
                            takeFocus = tv && focusOn == keyOf(server),
                            trailing = {
                                if (stale) Tag(s["staleServer"].orEmpty())
                                if (!tv) {
                                    RemoveButton(
                                        fill(s["removeServerNamed"], "name" to name),
                                        { if (nav.uses(server)) asking = server else removeNow(server) },
                                        takeFocus = focusOn == keyOf(server), focusKey = keyOf(server),
                                    )
                                }
                            },
                        )
                    },
                )
                // The order of the list of servers: what this device has used first, or what's found on the network.
                var savedFirst by remember { mutableStateOf(nav.app.store.savedFirst) }
                GroupedList("", listOf(GroupRow(
                    s["savedServersFirst"].orEmpty(), onClick = { savedFirst = !savedFirst; nav.app.store.savedFirst = savedFirst },
                    detail = s["savedServersFirstHint"].orEmpty(), chevron = false, focusKey = "saved-first", trailing = { Toggle(savedFirst) },
                )))
                WittyButton(s["removeOldServers"].orEmpty(), { choosing = true }, Modifier.fillMaxWidth(), tall = true, focusKey = "remove-old")
                WittyButton(s["removeAllServers"].orEmpty(), { askingAll = true }, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, tall = true, focusKey = "remove-all")
            }
            Notice(done, Modifier.fillMaxWidth())
        }
        if (!tv) {
            UndoRemoval(nav, s, Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(metrics.u(16))) {
                servers = manageOrder(nav.app.store.recent)
            }
        }
    }

    asking?.let { server ->
        ConfirmRemove(s, server, nav.uses(server), onYes = { asking = null; removeAsked(listOf(server)) }, onNo = { asking = null })
    }
    if (askingAll) {
        val body = fill(s["removeAllBody"], "count" to servers.size.toString(), "names" to namesOf(servers)) +
            if (servers.any(nav::uses)) "\n\n" + s["removeConfirmInUse"] else ""
        Confirm(
            body, s["removeAllServers"].orEmpty(), s["cancel"].orEmpty(),
            onYes = { askingAll = false; removeAsked(servers) }, onNo = { askingAll = false }, title = s["removeAllTitle"].orEmpty(),
        )
    }
    if (choosing) {
        AlertDialog(
            onDismissRequest = { choosing = false },
            containerColor = MaterialTheme.colorScheme.surface,
            title = { DialogTitle(s["removeOldTitle"].orEmpty()) },
            text = { Text(s["removeOldHint"].orEmpty(), color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.body) },
            confirmButton = {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                    STALE_CHOICES.forEach { days ->
                        WittyButton(
                            s["staleDays$days"].orEmpty(),
                            { choosing = false; old = days to notReachedFor(servers, days, System.currentTimeMillis(), nav.app.store.recentSince) },
                            Modifier.fillMaxWidth(),
                        )
                    }
                    WittyButton(s["cancel"].orEmpty(), { choosing = false }, Modifier.fillMaxWidth(), kind = ButtonKind.Quiet, takeFocus = true)
                }
            },
        )
    }
    old?.let { (days, which) ->
        if (which.isEmpty()) {
            AlertDialog(
                onDismissRequest = { old = null },
                containerColor = MaterialTheme.colorScheme.surface,
                text = { Text(s["removeOldNone"].orEmpty(), color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.body) },
                confirmButton = { WittyButton(s["back"].orEmpty(), { old = null }, takeFocus = true) },
            )
        } else {
            val body = fill(s["removeOldConfirmBody"], "period" to s["staleDays$days"].orEmpty(), "count" to which.size.toString(), "names" to namesOf(which)) +
                if (which.any(nav::uses)) "\n\n" + s["removeConfirmInUse"] else ""
            Confirm(
                body, s["remove"].orEmpty(), s["cancel"].orEmpty(),
                onYes = { old = null; removeAsked(which) }, onNo = { old = null }, title = s["removeOldConfirmTitle"].orEmpty(),
            )
        }
    }
}

@Composable
fun DialogTitle(text: String) {
    Text(text, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.headline, modifier = Modifier.semantics { heading() })
}
