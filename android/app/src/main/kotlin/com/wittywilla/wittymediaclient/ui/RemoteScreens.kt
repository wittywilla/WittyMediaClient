// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.remote.Feature
import com.wittywilla.wittymediaclient.net.remote.PlayOnSource
import com.wittywilla.wittymediaclient.net.remote.RemoteDevice
import com.wittywilla.wittymediaclient.net.remote.RemoteWire
import com.wittywilla.wittymediaclient.net.remote.canPlay
import com.wittywilla.wittymediaclient.net.remote.deviceLine
import com.wittywilla.wittymediaclient.net.remote.handOverCommand
import com.wittywilla.wittymediaclient.net.remote.livePositionSec
import com.wittywilla.wittymediaclient.net.remote.offerFor
import com.wittywilla.wittymediaclient.net.remote.pickerOrder
import com.wittywilla.wittymediaclient.net.remote.remoteWords
import com.wittywilla.wittymediaclient.net.remote.stopsHereAfter
import com.wittywilla.wittymediaclient.player.DeviceWatcher
import com.wittywilla.wittymediaclient.player.RemoteSender
import com.wittywilla.wittymediaclient.player.SeekBar
import com.wittywilla.wittymediaclient.player.clock
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException
import kotlin.math.abs

// The Remote Protocol's screens for the person holding this device (docs/REMOTE-PROTOCOL.md, Being a controller):
// the devices this account may play on, "Play on…" for what plays here or a title, and a remote for one device. They
// are You's own kind of screen (SettingsPage, grouped rows), so they look the same on a phone, a tablet and a TV.

data class RemoteRoute(val screen: RemoteScreen) : Route {
    override val key = "remote-" + screen.key

    companion object {
        fun PlayOn(source: PlayOnSource) = RemoteRoute(RemoteScreen.PlayOn(source))
        fun Party(itemId: Long?) = RemoteRoute(RemoteScreen.Party(itemId))
        val Devices = RemoteRoute(RemoteScreen.Devices)
        fun Control(deviceId: String) = RemoteRoute(RemoteScreen.Control(deviceId))
    }
}

sealed interface RemoteScreen {
    val key: String

    data object Devices : RemoteScreen {
        override val key = "devices"
    }

    data class Control(val deviceId: String) : RemoteScreen {
        override val key = "control-$deviceId"
    }

    data class PlayOn(val source: PlayOnSource) : RemoteScreen {
        override val key = "play-on-${source.itemId}"
    }

    // Starting or joining a watch party, from a title (itemId) or from You; the party's own panel once in one.
    data class Party(val itemId: Long?) : RemoteScreen {
        override val key = "party-${itemId ?: 0}"
    }
}

@Composable
fun RemoteRouteScreen(nav: Nav, route: RemoteRoute) {
    when (val screen = route.screen) {
        RemoteScreen.Devices -> RemoteDevicesScreen(nav)
        is RemoteScreen.Control -> RemoteControlScreen(nav, screen.deviceId)
        is RemoteScreen.PlayOn -> PlayOnScreen(nav, screen.source)
        is RemoteScreen.Party -> PartyScreen(nav, screen.itemId)
    }
}

private fun kindIcon(kind: String): ImageVector = when (kind) {
    "tv" -> Symbols.Tv
    "phone" -> Symbols.Phone
    "tablet" -> Symbols.Tablet
    "web" -> Symbols.Browser
    "desktop" -> Symbols.Computer
    else -> Symbols.Devices
}

private val REMOTE_TINT = Color(0xFF3E5BD0)

// The devices, kept live while this is on screen.
@Composable
private fun rememberWatcher(nav: Nav): DeviceWatcher {
    val api = nav.app.api
    val watcher = remember(api) { DeviceWatcher(api) }
    LaunchedEffect(watcher) { watcher.run() }
    return watcher
}

// You → Remote control: every device this account may steer, each opening its remote.
@Composable
private fun RemoteDevicesScreen(nav: Nav) {
    val watcher = rememberWatcher(nav)
    SettingsPage(nav, "Remote control", "Play on and steer your other devices with the WittyMedia app or website open, and devices your administrator lets you control.") {
        DeviceRows(nav, watcher, null) { nav.push(RemoteRoute.Control(it.id)) }
    }
}

@Composable
private fun DeviceRows(nav: Nav, watcher: DeviceWatcher, source: PlayOnSource?, busyId: String = "", choose: (RemoteDevice) -> Unit) {
    val listed = pickerOrder(watcher.devices)
    if (watcher.problem.isNotEmpty()) Problem(watcher.problem)
    when {
        !watcher.loaded -> Note("Looking for your devices…", busy = true)
        listed.isEmpty() -> Note("No other devices are reachable. Open the WittyMedia app or website on another device, signed in to this server, and it shows here.")
        else -> GroupedList(
            "Devices",
            listed.mapIndexed { index, device ->
                val fits = source == null || canPlay(device, source.kind, source.queued)
                val why = when {
                    source == null || fits -> deviceLine(device)
                    !device.online -> "Not connected"
                    else -> "Can't play this"
                }
                GroupRow(
                    title = device.name.ifEmpty { "Device" },
                    onClick = if (fits && (source == null || device.online)) ({ choose(device) }) else null,
                    icon = kindIcon(device.kind),
                    tint = if (device.online) REMOTE_TINT else MaterialTheme.colorScheme.onSurfaceVariant,
                    detail = why,
                    trailing = if (busyId == device.id) ({ Spinner(MaterialTheme.colorScheme.onSurfaceVariant, LocalMetrics.current.u(20)) }) else null,
                    focusKey = "device-${device.id}",
                    requestFocus = index == 0,
                )
            },
        )
    }
    // This device itself, as others see it, for someone wondering why it isn't listed.
    val hub = nav.app.remote
    Hint(if (hub.deviceId.isNotEmpty()) "This device is reachable as “${nav.app.deviceName}”." else "This device isn't listed here: other devices see it while the app is open, when Let other devices control this one is on in You → Playing on this device.")
}

// Play on…: what plays here (handed over at its place) or a title, on another device.
@Composable
private fun PlayOnScreen(nav: Nav, asked: PlayOnSource) {
    // A title named only by its id (from a server-driven page) is looked up first: what kind it is decides which
    // devices can play it.
    var source by remember(asked) { mutableStateOf(asked) }
    LaunchedEffect(asked) {
        if (asked.kind.isNotEmpty()) return@LaunchedEffect
        runCatching { nav.app.api.item(asked.itemId) }.getOrNull()?.let { source = asked.copy(title = it.title, kind = it.kind) }
    }
    if (source.kind.isEmpty()) {
        SettingsPage(nav, "Play on…") { Note("Looking it up…", busy = true) }
        return
    }
    val watcher = rememberWatcher(nav)
    val hub = nav.app.remote
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf("") }
    val title = source.title.ifEmpty { "this" }
    SettingsPage(nav, "Play on…", if (source.playingHere) "$title goes on from where it is, on the device you choose, and stops here." else "$title plays on the device you choose.") {
        Problem(problem)
        DeviceRows(nav, watcher, source, busy) { device ->
            if (busy.isNotEmpty()) return@DeviceRows
            busy = device.id
            problem = ""
            scope.launch {
                val api = nav.app.api
                val mine = hub.deviceId
                val command = handOverCommand(source, mine, device)
                val sentCast = (command["type"] as? JsonPrimitive)?.content == "cast"
                try {
                    val sender = RemoteSender(api, device.id, hub.info?.limits?.commandEveryMs ?: 200, scope) { problem = it }
                    val answer = sender.sendNow(command)
                    if (stopsHereAfter(source, sentCast, answer)) hub.stopHere(source)
                    hub.say("Now playing on ${device.name}")
                    nav.replace(RemoteRoute.Control(device.id))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: ApiError) {
                    problem = remoteWords(e)
                } catch (_: IOException) {
                    problem = "The server couldn't be reached. Check the connection."
                } finally {
                    busy = ""
                }
            }
        }
    }
}

// The remote for one device: what it plays and where, its transport, volume, tracks and speed, and on a TV its keys.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RemoteControlScreen(nav: Nav, deviceId: String) {
    val watcher = rememberWatcher(nav)
    val hub = nav.app.remote
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    var said by remember { mutableStateOf("") }
    val sender = remember(nav.app.api, deviceId) { RemoteSender(nav.app.api, deviceId, hub.info?.limits?.commandEveryMs ?: 200, scope) { said = it } }
    val device = watcher.devices.firstOrNull { it.id == deviceId }
    // Where it is now, moved on twice a second from what it last said.
    var nowSec by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(device?.state, device?.stateAt) {
        while (true) {
            device?.let { nowSec = livePositionSec(it.state, it.stateAt, watcher.serverNow()) }
            delay(TICK_MS)
        }
    }
    if (device == null) {
        SettingsPage(nav, "Remote") {
            if (!watcher.loaded) Note("Looking for the device…", busy = true)
            else Note(watcher.problem.ifEmpty { "That device has gone. It shows again when the app on it is open." })
        }
        return
    }
    val offer = offerFor(device)
    val state = device.state
    SettingsPage(nav, device.name.ifEmpty { "Remote" }, deviceLine(device)) {
        Problem(said)
        if (offer.transport && !device.hidden && !state.isIdle) {
            Column(verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                Text(device.title.ifEmpty { "Playing" }, color = scheme.onBackground, style = MaterialTheme.typography.label)
                if (offer.seek) {
                    SeekBar(
                        nowSec, state.durationSec, onTouched = {},
                        onSeekTo = { at -> nowSec = at; sender.drag(RemoteWire.seekTo(at)) },
                        trackColour = scheme.outline, ringColour = scheme.onBackground,
                    )
                }
                if (state.durationSec > 0) Text("${clock(nowSec)} / ${clock(state.durationSec)}", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
            }
        }
        if (offer.transport) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                val playing = state.isPlaying
                if (offer.queue) WittyButton("Previous", { sender.press(RemoteWire.simple("previous")) }, icon = WebIcons.Prev, focusKey = "r-previous")
                if (offer.seek) WittyButton("Back 10 s", { sender.press(RemoteWire.seekBy(-SKIP_SEC)) }, focusKey = "r-back")
                WittyButton(
                    if (playing) "Pause" else "Play", { sender.press(RemoteWire.simple(if (playing) "pause" else "resume")) },
                    kind = ButtonKind.Primary, icon = if (playing) WebIcons.Pause else WebIcons.Play, focusKey = "r-play", requestFocus = true,
                )
                if (offer.seek) WittyButton("Forward 10 s", { sender.press(RemoteWire.seekBy(SKIP_SEC)) }, focusKey = "r-forward")
                if (offer.queue) WittyButton("Next", { sender.press(RemoteWire.simple("next")) }, icon = WebIcons.Next, focusKey = "r-next")
                WittyButton("Stop", { sender.press(RemoteWire.simple("stop")) }, kind = ButtonKind.Destructive, focusKey = "r-stop")
            }
        } else if (device.online) {
            Note(if (device.hidden) "It's playing something this account can't see." else "Nothing is playing there. Choose Play on… on a title, or in the player, to put something on.")
        }
        if (offer.volume) VolumeControls(device, sender)
        if (offer.audio) {
            GroupedList(
                "Sound",
                state.audioTracks.map { t ->
                    GroupRow(
                        t.label.ifEmpty { t.lang.ifEmpty { "Track ${t.id}" } }, onClick = { sender.press(RemoteWire.audio(t.id)) },
                        chevron = false, selected = state.audio == t.id, focusKey = "audio-${t.id}",
                        trailing = if (state.audio == t.id) ({ Icon(WebIcons.Check, null, tint = scheme.primary) }) else null,
                    )
                },
            )
        }
        if (offer.subtitles) {
            val off = listOf(com.wittywilla.wittymediaclient.net.remote.RemoteTrack("off", "Off", ""))
            GroupedList(
                "Subtitles",
                (off + state.subtitleTracks).map { t ->
                    val chosen = (state.subtitle ?: "off") == t.id
                    GroupRow(
                        t.label.ifEmpty { t.lang.ifEmpty { "Track ${t.id}" } }, onClick = { sender.press(RemoteWire.subtitle(t.id)) },
                        chevron = false, selected = chosen, focusKey = "subtitle-${t.id}",
                        trailing = if (chosen) ({ Icon(WebIcons.Check, null, tint = scheme.primary) }) else null,
                    )
                },
            )
        }
        if (offer.rate) {
            Text("Speed", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                SPEEDS.forEach { r ->
                    ActionButton(if (r == 1.0) "Normal" else "$r×", { sender.press(RemoteWire.rate(r)) }, selected = abs(state.rate - r) < 0.01, pill = true, focusKey = "rate-$r")
                }
            }
        }
        if (offer.navigate) KeysPad(sender)
    }
}

@Composable
private fun VolumeControls(device: RemoteDevice, sender: RemoteSender) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val state = device.state
    val level = (state.volume ?: 1.0).toFloat()
    var shown by remember(device.id) { mutableFloatStateOf(level) }
    var dragging by remember { mutableStateOf(false) }
    LaunchedEffect(level) { if (!dragging) shown = level }
    Text("Volume", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
    if (metrics.tv) {
        // A slider isn't a remote's thing: steps, as the TV's own volume keys.
        Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalAlignment = Alignment.CenterVertically) {
            WittyButton("Quieter", { shown = (shown - VOLUME_STEP).coerceAtLeast(0f); sender.drag(RemoteWire.volume(shown.toDouble())) }, icon = WebIcons.Volume, focusKey = "v-down")
            WittyButton("Louder", { shown = (shown + VOLUME_STEP).coerceAtMost(1f); sender.drag(RemoteWire.volume(shown.toDouble())) }, icon = WebIcons.Volume, focusKey = "v-up")
            WittyButton(if (state.muted) "Sound on" else "Mute", { sender.press(RemoteWire.mute(!state.muted)) }, icon = WebIcons.Mute, focusKey = "v-mute")
            Text("${(shown * 100).toInt()}%", color = scheme.onBackground, style = MaterialTheme.typography.label)
        }
    } else {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
            Pressable({ sender.press(RemoteWire.mute(!state.muted)) }, Modifier.size(metrics.minTarget), label = if (state.muted) "Sound on" else "Mute") {
                Icon(if (state.muted || shown == 0f) WebIcons.Mute else WebIcons.Volume, null, tint = scheme.onBackground)
            }
            Slider(
                shown,
                { dragging = true; shown = it; sender.drag(RemoteWire.volume(it.toDouble())) },
                Modifier.weight(1f).semantics { contentDescription = "Volume" },
                onValueChangeFinished = { dragging = false },
                colors = SliderDefaults.colors(thumbColor = scheme.primary, activeTrackColor = scheme.primary, inactiveTrackColor = scheme.outline),
            )
        }
    }
}

// A TV remote's keys, and on a touch screen a pad to swipe and tap as its touch surface.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun KeysPad(sender: RemoteSender) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    fun key(name: String) = sender.press(RemoteWire.navigate(name))
    Text("Its remote", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
    if (!metrics.tv) {
        // Swipe to move, tap to choose: what a TV remote's touch surface does.
        Box(
            Modifier
                .fillMaxWidth()
                .widthIn(max = metrics.u(420))
                .aspectRatio(1.6f)
                .background(scheme.surface, metrics.corner(14))
                .semantics { contentDescription = "Touch surface: swipe to move, tap to choose" }
                .pointerInput(Unit) { detectTapGestures { key("select") } }
                .pointerInput(Unit) {
                    var dx = 0f
                    var dy = 0f
                    detectDragGestures(
                        onDragStart = { dx = 0f; dy = 0f },
                        onDragEnd = {
                            val far = SWIPE_DP * density
                            if (abs(dx) > far || abs(dy) > far) key(if (abs(dx) > abs(dy)) (if (dx > 0) "right" else "left") else (if (dy > 0) "down" else "up"))
                        },
                    ) { change, drag ->
                        change.consume()
                        dx += drag.x
                        dy += drag.y
                    }
                },
            contentAlignment = Alignment.Center,
        ) { Text("Swipe to move, tap to choose", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, textAlign = TextAlign.Center) }
    }
    // The arrows round OK, as on the remote in the hand.
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(8)), modifier = Modifier.widthIn(max = metrics.u(420)).fillMaxWidth()) {
        WittyButton("Up", { key("up") }, icon = WebIcons.Up, focusKey = "k-up")
        Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalAlignment = Alignment.CenterVertically) {
            WittyButton("Left", { key("left") }, icon = WebIcons.Left, focusKey = "k-left")
            WittyButton("OK", { key("select") }, kind = ButtonKind.Primary, focusKey = "k-select")
            WittyButton("Right", { key("right") }, icon = WebIcons.Right, focusKey = "k-right")
        }
        WittyButton("Down", { key("down") }, icon = WebIcons.Down, focusKey = "k-down")
    }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        WittyButton("Back", { key("back") }, icon = WebIcons.Back, focusKey = "k-back")
        WittyButton("Home", { key("home") }, icon = WebIcons.Home, focusKey = "k-home")
        WittyButton("Menu", { key("menu") }, icon = WebIcons.Menu, focusKey = "k-menu")
        WittyButton("Play/Pause", { key("playpause") }, icon = WebIcons.Play, focusKey = "k-playpause")
    }
}

private const val TICK_MS = 500L
private const val SKIP_SEC = 10.0
private const val VOLUME_STEP = 0.1f
private const val SWIPE_DP = 24f
private val SPEEDS = listOf(0.75, 1.0, 1.25, 1.5, 2.0)
