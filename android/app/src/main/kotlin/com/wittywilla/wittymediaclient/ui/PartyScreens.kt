// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.syncplay.Room
import com.wittywilla.wittymediaclient.net.syncplay.RoomSummary
import com.wittywilla.wittymediaclient.net.syncplay.SyncInfo
import com.wittywilla.wittymediaclient.net.syncplay.canEditQueue
import com.wittywilla.wittymediaclient.net.syncplay.hasNext
import com.wittywilla.wittymediaclient.net.syncplay.hasPrevious
import com.wittywilla.wittymediaclient.net.syncplay.keepsInStep
import com.wittywilla.wittymediaclient.net.syncplay.memberWords
import com.wittywilla.wittymediaclient.net.syncplay.normaliseCode
import com.wittywilla.wittymediaclient.net.syncplay.partyQueue
import com.wittywilla.wittymediaclient.net.syncplay.queueMoved
import com.wittywilla.wittymediaclient.net.syncplay.queueWithout
import com.wittywilla.wittymediaclient.net.syncplay.spacedCode
import com.wittywilla.wittymediaclient.net.syncplay.syncWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import java.io.IOException
import java.util.Locale
import kotlin.math.abs

// Watch parties (the server's docs/SYNCPLAY.md): starting one from a film or an episode, joining one by its code or an
// invitation, and the party's panel with who is there, the queue and, for the host, how it runs. The panel is the
// same in the player (down its side) and as a screen of its own.

private val PARTY_TINT = Color(0xFFBD2F85)

private fun failureWords(e: Exception): String = when (e) {
    is ApiError -> syncWords(e)
    is IOException -> "The server couldn't be reached. Check the connection."
    else -> "That didn't work. Try again."
}

// Watch party: start one for a title, join one, or (once in one) the party itself.
@Composable
internal fun PartyScreen(nav: Nav, itemId: Long?) {
    val hub = nav.app.remote
    val party = hub.party
    val room = party.room
    val route = nav.current
    if (room != null) {
        SettingsPage(nav, "Watch party", room.name.ifEmpty { "Code ${spacedCode(room.code)}" }) { PartyBody(nav, room) }
        return
    }
    val api = nav.app.api
    val scope = rememberCoroutineScope()
    var info by remember { mutableStateOf(party.info) }
    var item by remember(itemId) { mutableStateOf<Item?>(null) }
    var episodes by remember(itemId) { mutableStateOf<List<Item>>(emptyList()) }
    var name by remember { mutableStateOf("") }
    var everyone by remember { mutableStateOf(false) }
    var waitForAll by remember { mutableStateOf(true) }
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { hub.refreshParties()?.let { info = it } }
    LaunchedEffect(itemId) {
        if (itemId == null) return@LaunchedEffect
        val found = runCatching { api.item(itemId) }.getOrNull() ?: return@LaunchedEffect
        item = found
        // An episode brings the rest of its season along.
        found.showId?.let { show -> episodes = runCatching { api.show(show).episodes }.getOrDefault(emptyList()) }
    }
    // Into the party: its player opens (RemoteHub.partyChanged), and this screen makes way for it.
    fun entered() {
        if (nav.stack.size > 1) nav.stack.remove(route)
    }
    fun attempt(what: String, act: suspend () -> Unit) {
        if (busy.isNotEmpty()) return
        busy = what
        problem = ""
        scope.launch {
            try {
                act()
                entered()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = failureWords(e)
            } finally {
                busy = ""
            }
        }
    }
    val found = info
    SettingsPage(nav, "Watch party", "Watch something with other people at the same moment, each on their own screen. A pause pauses it for everyone.") {
        Problem(problem)
        when {
            found == null -> Note("Asking the server…", busy = true)
            !found.enabled -> Note("Watch parties are turned off on this server.")
            !found.canJoin -> Note("Watch parties are turned off for this profile.")
            else -> {
                val title = item
                if (title != null && found.canCreate && keepsInStep(title.kind)) StartGroup(
                    title, name, { name = it }, everyone, { everyone = !everyone }, waitForAll, { waitForAll = !waitForAll }, busy == "start",
                ) {
                    attempt("start") {
                        val queue = partyQueue(title, episodes, found.limits.queue)
                        val here = hub.video?.takeIf { it.itemId == title.id }?.liveFilmSec?.takeIf { it > 1 }
                        party.create(queue, 0, name, everyone, waitForAll, here)
                    }
                } else if (title != null && !found.canCreate) {
                    Note("This account can't start a watch party, but can join one with its code.")
                }
                JoinGroup(code, { code = it.take(CODE_TYPED) }, busy == "join", found) { attempt("join") { party.joinCode(code) } }
                RoomsGroup(found, busy) { listed -> attempt(listed.id) { party.joinRoom(listed.id); hub.accepted(listed) } }
            }
        }
    }
}

@Composable
private fun StartGroup(
    item: Item, name: String, setName: (String) -> Unit, everyone: Boolean, flipEveryone: () -> Unit,
    waitForAll: Boolean, flipWait: () -> Unit, busy: Boolean, start: () -> Unit,
) {
    val words = LocalWords.current
    GroupedList(
        "Start one",
        listOf(
            GroupRow(
                "Everyone can play, pause and seek", onClick = flipEveryone, icon = Symbols.Group, tint = PARTY_TINT, chevron = false,
                value = if (everyone) words["on"].orEmpty() else words["off"].orEmpty(), selected = everyone, trailing = { Toggle(everyone) }, focusKey = "p-everyone",
            ),
            GroupRow(
                "Wait for everyone", onClick = flipWait, icon = Symbols.Playback, tint = PARTY_TINT, chevron = false,
                detail = "Pauses for anyone still loading, for 15 seconds at most.",
                value = if (waitForAll) words["on"].orEmpty() else words["off"].orEmpty(), selected = waitForAll, trailing = { Toggle(waitForAll) }, focusKey = "p-wait",
            ),
        ),
    )
    WittyField(name, setName, "Name (optional)", maxLength = NAME_MOST)
    WittyButton("Start a watch party for ${item.title}", start, kind = ButtonKind.Primary, busy = busy, icon = Symbols.Group, requestFocus = true, focusKey = "p-start")
    Hint(if (item.season != null) "You'll be the host. The rest of the season follows this episode." else "You'll be the host. You get a code to give the people you want to watch with.")
}

@Composable
private fun JoinGroup(code: String, setCode: (String) -> Unit, busy: Boolean, info: SyncInfo, join: () -> Unit) {
    val ready = normaliseCode(code).length >= info.limits.codeLength
    WittyField(code, setCode, "Code", onAction = { if (ready) join() }, maxLength = CODE_TYPED)
    WittyButton("Join", join, enabled = ready, busy = busy, focusKey = "p-join")
    Hint("Capitals, spaces and dashes don't matter.")
}

@Composable
private fun RoomsGroup(info: SyncInfo, busy: String, join: (RoomSummary) -> Unit) {
    if (info.rooms.isEmpty()) return
    GroupedList(
        "Your watch parties",
        info.rooms.map { r ->
            GroupRow(
                r.name.ifEmpty { "${r.hostName}'s watch party" }, onClick = { join(r) }, icon = Symbols.Group, tint = PARTY_TINT,
                detail = (if (r.memberId.isNotEmpty()) "You have a place in it" else "${r.hostName} invited you") + " · ${r.members} watching",
                value = if (r.memberId.isNotEmpty()) "Go back in" else "Join",
                trailing = if (busy == r.id) ({ Spinner(MaterialTheme.colorScheme.onSurfaceVariant, LocalMetrics.current.u(20)) }) else null,
                focusKey = "room-${r.id}",
            )
        },
    )
}

// The party's panel in the player: down its side, over the picture, which plays on beside it.
@Composable
fun PartyPanel(nav: Nav, close: () -> Unit, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    BackHandler { close() }
    val room = nav.app.remote.party.room
    Column(
        modifier
            .background(scheme.background.copy(alpha = PANEL_ALPHA))
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
            .padding(metrics.u(if (metrics.tv) 32 else 16)),
        verticalArrangement = Arrangement.spacedBy(metrics.u(16)),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Watch party", color = scheme.onBackground, style = MaterialTheme.typography.title, modifier = Modifier.weight(1f))
            WittyButton("Close", close, kind = ButtonKind.Quiet, focusKey = "party-close")
        }
        if (room == null) {
            Note("You aren't in a watch party now.")
        } else {
            PartyBody(nav, room)
        }
    }
}

// Who is there, the queue and, for the host, how it runs: the same in the panel and on its own screen.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColumnScope.PartyBody(nav: Nav, room: Room) {
    val hub = nav.app.remote
    val party = hub.party
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val words = LocalWords.current
    val scope = rememberCoroutineScope()
    var chosenMember by remember { mutableStateOf<String?>(null) }
    var chosenItem by remember { mutableStateOf<Int?>(null) }
    var problem by remember { mutableStateOf("") }
    fun act(change: suspend () -> Unit) {
        problem = ""
        scope.launch {
            try {
                change()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = failureWords(e)
            }
        }
    }
    Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(metrics.u(4))) {
        Text("Code", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
        Text(spacedCode(room.code), color = scheme.onBackground, style = MaterialTheme.typography.title.copy(fontWeight = FontWeight.Bold))
        Text("Tell it to the people you want to watch with.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
    }
    if (party.reconnecting) Note("The connection dropped. Taking your place again…", busy = true)
    if (room.blocked) Note("The party has moved on to something this account can't watch. You keep your place, and join in again when it moves on.")
    if (room.timeUp) Note("Your screen time is up, so you're sitting this one out. You're back as soon as a parent gives more time.")
    Problem(problem)
    // How far this player is from the room, for anyone wondering whether it's working.
    val behind = hub.follower?.behind ?: Double.NaN
    if (!behind.isNaN()) {
        val off = abs(behind)
        Text(
            if (off < IN_STEP_SEC) "In step with the party." else String.format(Locale.ROOT, "%.1f s %s the party, catching up.", off, if (behind > 0) "behind" else "ahead of"),
            color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
    }
    // The queue, with what's playing marked. Whoever may control can play another now or step along it.
    if (room.queue.isNotEmpty()) {
        GroupedList(
            "Queue",
            room.queue.mapIndexed { index, id ->
                val title = room.items.firstOrNull { it.id == id && id != 0L }?.title?.ifEmpty { null } ?: "Not available on this account"
                val now = index == room.state.index
                GroupRow(
                    title, onClick = if (room.canControl) ({ chosenItem = if (chosenItem == index) null else index }) else null,
                    icon = if (now) WebIcons.Play else null, tint = PARTY_TINT, detail = if (now) "Playing now" else "",
                    selected = now, chevron = false, focusKey = "q-$index",
                )
            },
        )
        chosenItem?.takeIf { it in room.queue.indices }?.let { index ->
            FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                if (index != room.state.index) WittyButton("Play now", { chosenItem = null; act { party.command("select") { put("index", JsonPrimitive(index)) } } }, kind = ButtonKind.Primary, takeFocus = true, focusKey = "q-play")
                if (canEditQueue(room)) {
                    queueMoved(room, index, -1)?.let { (items, at) -> WittyButton("Move up", { chosenItem = index - 1; act { sendQueue(nav, items, at) } }, focusKey = "q-up") }
                    queueMoved(room, index, 1)?.let { (items, at) -> WittyButton("Move down", { chosenItem = index + 1; act { sendQueue(nav, items, at) } }, focusKey = "q-down") }
                    queueWithout(room, index)?.let { (items, at) -> WittyButton("Take out", { chosenItem = null; act { sendQueue(nav, items, at) } }, kind = ButtonKind.Destructive, focusKey = "q-out") }
                }
            }
        }
        if (room.canControl && (room.hasPrevious || room.hasNext)) {
            Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                if (room.hasPrevious) WittyButton("Previous", { act { party.command("previous") } }, icon = WebIcons.Prev, focusKey = "p-previous")
                if (room.hasNext) WittyButton("Next", { act { party.command("next") } }, icon = WebIcons.Next, focusKey = "p-next")
            }
        }
    }
    // Who is there, and how each is doing.
    GroupedList(
        "People",
        room.members.map { m ->
            val mine = m.id == room.you
            GroupRow(
                m.name + if (mine) " (you)" else "",
                onClick = if (room.isHost && !mine) ({ chosenMember = if (chosenMember == m.id) null else m.id }) else null,
                icon = Symbols.Person, tint = if (m.host) PARTY_TINT else scheme.onSurfaceVariant,
                detail = listOfNotNull(if (m.host) "Host" else null, memberWords(m.state).ifEmpty { null }).joinToString(" · "),
                chevron = false, focusKey = "m-${m.id}",
            )
        },
    )
    chosenMember?.let { id ->
        room.members.firstOrNull { it.id == id }?.let { m ->
            Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                WittyButton("Make ${m.name} host", { chosenMember = null; act { party.makeHost(m.id) } }, takeFocus = true, focusKey = "m-host")
                WittyButton("Remove ${m.name}", { chosenMember = null; act { party.remove(m.id) } }, kind = ButtonKind.Destructive, focusKey = "m-remove")
            }
        }
    }
    // How it runs: the host's.
    if (room.isHost) {
        GroupedList(
            "How it runs",
            listOf(
                GroupRow(
                    "Everyone can play, pause and seek", onClick = { act { party.set(everyone = !room.everyoneControls) } }, chevron = false,
                    value = if (room.everyoneControls) words["on"].orEmpty() else words["off"].orEmpty(), selected = room.everyoneControls,
                    trailing = { Toggle(room.everyoneControls) }, focusKey = "h-everyone",
                ),
                GroupRow(
                    "Wait for everyone", onClick = { act { party.set(waitForAll = !room.waitForAll) } }, chevron = false,
                    detail = "Pauses for anyone still loading, for 15 seconds at most.",
                    value = if (room.waitForAll) words["on"].orEmpty() else words["off"].orEmpty(), selected = room.waitForAll,
                    trailing = { Toggle(room.waitForAll) }, focusKey = "h-wait",
                ),
            ),
        )
    } else if (!room.canControl) {
        Hint("Only the host plays, pauses and seeks in this watch party.")
    }
    Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        WittyButton("Leave", { party.leave() }, focusKey = "p-leave")
        if (room.isHost) WittyButton("End for everyone", { act { party.end() } }, kind = ButtonKind.Destructive, focusKey = "p-end")
    }
}

private suspend fun sendQueue(nav: Nav, items: List<Long>, index: Int) {
    nav.app.remote.party.command("queue") {
        put("items", buildJsonArray { items.forEach { add(JsonPrimitive(it)) } })
        put("index", JsonPrimitive(index))
    }
}

// Over every screen: the hub's line of news, and invitations to watch parties, with Accept and Decline.
@Composable
fun RemoteOverlay(nav: Nav) {
    val hub = nav.app.remote
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    Box(Modifier.fillMaxSize().safeDrawingPadding()) {
        Toast(hub.notice, { hub.notice = "" }, Modifier.align(Alignment.TopCenter).padding(top = metrics.u(16)))
        val invite = hub.invitations.firstOrNull()
        if (invite != null && hub.party.room == null) {
            val scope = rememberCoroutineScope()
            var busy by remember(invite.id) { mutableStateOf(false) }
            Column(
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(metrics.u(16))
                    .widthIn(max = metrics.u(380))
                    .background(scheme.surface, metrics.corner(14))
                    .padding(metrics.u(16))
                    .semantics(mergeDescendants = false) { liveRegion = LiveRegionMode.Polite },
                verticalArrangement = Arrangement.spacedBy(metrics.u(12)),
            ) {
                Text("${invite.hostName.ifEmpty { "Someone" }} invited you to a watch party", color = scheme.onSurface, style = MaterialTheme.typography.label)
                if (invite.name.isNotEmpty()) Text(invite.name, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
                Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                    WittyButton("Accept", {
                        busy = true
                        scope.launch {
                            try {
                                hub.party.joinRoom(invite.id)
                                hub.accepted(invite)
                            } catch (e: CancellationException) {
                                throw e
                            } catch (e: Exception) {
                                hub.say(failureWords(e))
                                hub.decline(invite)
                            } finally {
                                busy = false
                            }
                        }
                    }, kind = ButtonKind.Primary, busy = busy, focusKey = "invite-accept")
                    WittyButton("Decline", { hub.decline(invite) }, focusKey = "invite-decline")
                }
            }
        }
    }
}

// A title page's "⋯" rows for these: Play on another device, and a watch party for a video.
internal fun togetherRows(nav: Nav, item: Item): List<SheetRow> = listOfNotNull(
    if (item.kind == "video" && nav.has(com.wittywilla.wittymediaclient.player.SYNCPLAY_FEATURE)) SheetRow("Watch party", Symbols.Group) { nav.push(RemoteRoute.Party(item.id)) } else null,
    if ((item.kind == "video" || item.kind == "audio") && nav.app.remote.canControl) SheetRow("Play on another device", Symbols.Devices) {
        nav.push(RemoteRoute.PlayOn(com.wittywilla.wittymediaclient.net.remote.PlayOnSource(item.id, item.title, item.kind)))
    } else null,
)

private const val CODE_TYPED = 12
private const val NAME_MOST = 60
private const val IN_STEP_SEC = 0.25
private const val PANEL_ALPHA = 0.94f
