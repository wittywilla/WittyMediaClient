// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.remote

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

// The Remote Protocol's decisions, apart from any screen or network, so they can be tested without one.

object Feature {
    const val SEEK = "seek"
    const val VOLUME = "volume"
    const val QUEUE = "queue"
    const val AUDIO = "audio"
    const val SUBTITLES = "subtitles"
    const val NAVIGATE = "navigate"
    const val RATE = "rate"
}

val NAVIGATE_KEYS = listOf("up", "down", "left", "right", "select", "back", "home", "menu", "playpause")

// What this app says it can do, and only what its players really do. Films, episodes and other videos play in the
// video player and music and audiobooks in the listening service; discs, books, radio, games and photos open in the
// server's own pages, which nothing here can steer, so they aren't announced. A TV's sound is usually the
// television's own, fixed as far as the app can tell: such a device has no `volume`.
fun deviceCapabilities(volumeFixed: Boolean): RemoteCapabilities = RemoteCapabilities(
    mediaKinds = listOf("video", "audio"),
    features = listOfNotNull(
        Feature.SEEK, if (volumeFixed) null else Feature.VOLUME, Feature.QUEUE, Feature.AUDIO, Feature.SUBTITLES, Feature.NAVIGATE, Feature.RATE,
    ),
)

fun deviceKind(tv: Boolean, tablet: Boolean): String = if (tv) "tv" else if (tablet) "tablet" else "phone"

// What a remote offers for one device: only what the device listed, and only while it can hear.
data class RemoteOffer(
    val transport: Boolean,
    val seek: Boolean,
    val volume: Boolean,
    val queue: Boolean,
    val audio: Boolean,
    val subtitles: Boolean,
    val navigate: Boolean,
    val rate: Boolean,
)

fun offerFor(device: RemoteDevice): RemoteOffer {
    val has = { f: String -> device.online && f in device.capabilities.features }
    val state = device.state
    val open = device.online && !state.isIdle && !device.hidden
    return RemoteOffer(
        transport = device.online && state.status != "idle",
        seek = open && has(Feature.SEEK) && state.durationSec > 0,
        // The volume is the device's, whatever it plays, and is shown even for something hidden.
        volume = has(Feature.VOLUME),
        queue = open && has(Feature.QUEUE) && state.queue.size > 1,
        audio = open && has(Feature.AUDIO) && state.audioTracks.size > 1,
        subtitles = open && has(Feature.SUBTITLES) && state.subtitleTracks.isNotEmpty(),
        navigate = has(Feature.NAVIGATE),
        rate = open && has(Feature.RATE),
    )
}

// Whether a device can be asked to play a kind of item at all, and a queue of several.
fun canPlay(device: RemoteDevice, itemKind: String, queued: Int = 1): Boolean =
    device.online && itemKind in device.capabilities.mediaKinds && (queued <= 1 || Feature.QUEUE in device.capabilities.features)

// The devices a picker lists: never this app itself, online ones first, then by name.
fun pickerOrder(devices: List<RemoteDevice>): List<RemoteDevice> =
    devices.filterNot { it.thisSession }.sortedWith(compareBy<RemoteDevice> { !it.online }.thenBy { it.name.lowercase() }.thenBy { it.id })

// Where a playing device is now (docs/REMOTE-PROTOCOL.md, List devices): its last report, moved on by the time since
// at its speed. A paused, idle or buffering device stays where it said. Never past the end or before the start.
fun livePositionSec(state: RemoteState, stateAt: Long, serverNowMs: Long): Double {
    val moved = if (state.isPlaying && stateAt > 0) (serverNowMs - stateAt).coerceAtLeast(0) / 1000.0 * state.rate else 0.0
    val at = state.positionSec + moved
    return if (state.durationSec > 0) at.coerceIn(0.0, state.durationSec) else at.coerceAtLeast(0.0)
}

// The server's clock, from this device's: corrected by the difference when an answer carrying `serverTimeMs`
// arrived. `localMs` is a clock that never jumps (the time since the device started).
class ServerClock {
    private var offsetMs: Long? = null

    fun heard(serverTimeMs: Long, localMs: Long) {
        if (serverTimeMs > 0) offsetMs = serverTimeMs - localMs
    }

    val known: Boolean get() = offsetMs != null
    fun now(localMs: Long): Long = localMs + (offsetMs ?: 0)
}

// A command a device was sent, checked before anything is done about it. The server has checked it too, but a
// device answers for itself: null means fine, otherwise the sentence for whoever holds the controller.
fun commandProblem(c: RemoteCommand, capabilities: RemoteCapabilities, maxQueue: Int = 200): String? {
    fun needs(feature: String) = if (feature in capabilities.features) null else CANT_DO
    fun finite(n: Double?) = n != null && n.isFinite()
    return when (c.type) {
        "play" -> when {
            c.queue.isNullOrEmpty() && (c.itemId == null || c.itemId <= 0) -> "That command didn't say what to play."
            !c.queue.isNullOrEmpty() && c.queue.size > maxQueue -> "That queue is too long."
            !c.queue.isNullOrEmpty() && (c.queueIndex ?: 0) !in c.queue.indices -> "That place isn't in the queue."
            !c.queue.isNullOrEmpty() && c.itemId != null && c.itemId != c.queue[c.queueIndex ?: 0] -> "That item isn't at that place in the queue."
            !c.queue.isNullOrEmpty() && c.queue.size > 1 && Feature.QUEUE !in capabilities.features -> CANT_DO
            c.positionSec != null && (!c.positionSec.isFinite() || c.positionSec < 0) -> "That isn't a place to start from."
            else -> null
        }
        "pause", "resume", "stop" -> null
        "seek" -> needs(Feature.SEEK) ?: if (finite(c.positionSec) || finite(c.bySec)) null else "That command didn't say where to go."
        "next", "previous" -> needs(Feature.QUEUE)
        "volume" -> needs(Feature.VOLUME) ?: if (finite(c.level) && c.level!! in 0.0..1.0) null else "The volume goes from 0 to 1."
        "mute" -> needs(Feature.VOLUME) ?: if (c.muted != null) null else "That command didn't say whether to mute."
        "audio" -> needs(Feature.AUDIO) ?: if (!c.audio.isNullOrEmpty()) null else "That command didn't say which sound track."
        "subtitle" -> needs(Feature.SUBTITLES) ?: if (!c.subtitle.isNullOrEmpty()) null else "That command didn't say which subtitles."
        "rate" -> needs(Feature.RATE) ?: if (finite(c.rate) && c.rate!! in 0.25..4.0) null else "The speed goes from 0.25 to 4."
        "navigate" -> needs(Feature.NAVIGATE) ?: if (c.key in NAVIGATE_KEYS) null else "This device doesn't have that key."
        // Every command gets an answer: one this app has never heard of gets this one.
        else -> CANT_DO
    }
}

const val CANT_DO = "This device can't do that."
const val NOTHING_PLAYING = "Nothing is playing."

// A track id is the playback answer's `index`, as text; "off" is no subtitles (-1 to the playback route).
fun trackIndex(id: String?): Int? = when {
    id == null -> null
    id == "off" -> -1
    else -> id.toIntOrNull()?.takeIf { it >= 0 }
}

fun trackId(index: Int): String = if (index < 0) "off" else index.toString()

// The queue a device was given, and where it is in it. A device told to play one item has a queue of one.
data class RemoteQueue(val items: List<Long> = emptyList(), val index: Int = 0) {
    val current: Long? get() = items.getOrNull(index)
    val hasNext: Boolean get() = index + 1 < items.size
    val hasPrevious: Boolean get() = index > 0

    fun next(): RemoteQueue? = if (hasNext) copy(index = index + 1) else null
    fun previous(): RemoteQueue? = if (hasPrevious) copy(index = index - 1) else null

    // The player moved by itself (the next episode started): follow it when the item is in the queue, otherwise the
    // queue is over and what plays now stands alone.
    fun movedTo(itemId: Long): RemoteQueue {
        if (current == itemId) return this
        val ahead = items.withIndex().firstOrNull { it.index > index && it.value == itemId }?.index
        val found = ahead ?: items.indexOf(itemId)
        return if (found >= 0) copy(index = found) else RemoteQueue(listOf(itemId), 0)
    }

    companion object {
        fun from(c: RemoteCommand): RemoteQueue {
            val list = c.queue.orEmpty()
            return if (list.isNotEmpty()) RemoteQueue(list, (c.queueIndex ?: 0).coerceIn(0, list.lastIndex)) else RemoteQueue(listOfNotNull(c.itemId), 0)
        }
    }
}

// Every refusal in the protocol's Errors table, as a sentence. The server's own sentence is used where it is one
// (its codes come with plain ones); these stand in when it sent none, and for the codes whose server text is a
// program's ("unknown command type").
fun remoteErrorWords(status: Int, code: String, serverWords: String, retryAfterSec: Int = 0): String {
    val said = serverWords.trim()
    return when (code) {
        "bad-command" -> "This app sent that device something it couldn't make sense of."
        "version" -> "This app is too old for this server's remote control. Update the app."
        "disabled" -> "Remote control is turned off on this server."
        "no-session" -> "Sign in again to use remote control."
        "not-allowed-there" -> said.ifEmpty { "The account on that device isn't allowed to play that." }
        "no-device" -> "That device has gone, or isn't one you can control."
        "no-item" -> "That isn't in the library, or isn't something you can play."
        "no-command" -> "That device had already stopped waiting."
        "offline" -> "That device isn't connected."
        "unsupported" -> "That device can't do that."
        // The device's own reason, written for whoever holds the controller.
        "refused" -> said.ifEmpty { "That device said no." }
        "nothing-playing" -> "Nothing is playing there to move."
        "rate" -> if (retryAfterSec > 1) "Slow down a little: try again in $retryAfterSec seconds." else "Slow down a little, then try again."
        "too-many" -> said.ifEmpty { "Too many devices or remotes are connected. Close one and try again." }
        "busy" -> "That device is busy with other commands. Try again in a moment."
        "timeout" -> "That device didn't answer in time."
        else -> when (status) {
            413 -> "That was too long to send."
            429 -> "Slow down a little, then try again."
            else -> said.ifEmpty { "The server answered with an error ($status)." }
        }
    }
}

// Commands no faster than the server allows (`commandEveryMs`). Something dragged, such as a volume or a place on
// the bar, sends its latest value when the time comes and never the ones in between. A press is sent as it is, or
// waits its turn.
class CommandPacer(private val everyMs: Long) {
    private var lastSentMs = Long.MIN_VALUE / 2
    private val latest = LinkedHashMap<String, JsonObject>()

    // How long to wait before the next command may go: 0 means now.
    fun waitMs(nowMs: Long): Long = (lastSentMs + everyMs - nowMs).coerceAtLeast(0)

    fun sent(nowMs: Long) {
        lastSentMs = nowMs
    }

    // A value that replaces any not yet sent of the same kind.
    fun offer(command: JsonObject) {
        val kind = command["type"]?.jsonPrimitive?.content.orEmpty()
        latest.remove(kind)
        latest[kind] = command
    }

    // The next waiting value, oldest kind first, when it's time.
    fun take(nowMs: Long): JsonObject? {
        if (waitMs(nowMs) > 0 || latest.isEmpty()) return null
        val first = latest.entries.first()
        latest.remove(first.key)
        return first.value
    }

    val pending: Boolean get() = latest.isNotEmpty()
}
