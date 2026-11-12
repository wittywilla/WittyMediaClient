// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.remote

import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

// The Remote Protocol's messages (the server's docs/REMOTE-PROTOCOL.md is the whole wire format). Reading skips every
// field and event this app has never heard of; writing is done field by field, so nothing is sent that wasn't meant:
// a device with no volume of its own leaves `volume` out rather than sending a made-up one.

const val REMOTE_V = 1

@Serializable
data class RemoteLimits(
    val stateEveryMs: Long = 500,
    val commandEveryMs: Long = 200,
    val heartbeatSec: Int = 30,
    val idleSec: Int = 75,
    val reconnectSec: Int = 30,
    val ackTimeoutMs: Long = 8000,
    val queueItems: Int = 200,
    val stateBytes: Int = 32768,
    val commandBytes: Int = 8192,
)

// GET /remote-control: whether it is on, the versions spoken and the limits, so none is copied here.
@Serializable
data class RemoteInfo(
    val enabled: Boolean = false,
    val v: Int = REMOTE_V,
    val minV: Int = REMOTE_V,
    val controlOthers: Boolean = false,
    // This profile may play on and steer devices. False when its limits turn that off; an older server doesn't say.
    val canControl: Boolean = true,
    val navigateKeys: List<String> = emptyList(),
    val limits: RemoteLimits = RemoteLimits(),
)

@Serializable
data class RemoteCapabilities(val mediaKinds: List<String> = emptyList(), val features: List<String> = emptyList())

// What the server agreed to when this device announced itself.
@Serializable
data class Announced(
    val v: Int = REMOTE_V,
    val minV: Int = REMOTE_V,
    val deviceId: String = "",
    val name: String = "",
    val kind: String = "",
    val capabilities: RemoteCapabilities = RemoteCapabilities(),
    val heartbeatSec: Int = 30,
    val openWithinSec: Int = 30,
    val serverTimeMs: Long = 0,
)

@Serializable
data class RemoteTrack(val id: String = "", val label: String = "", val lang: String = "")

// What a device reports, and what a controller is shown. Everything but the status may be missing.
@Serializable
data class RemoteState(
    val v: Int = REMOTE_V,
    val status: String = "idle",
    val itemId: Long? = null,
    val positionSec: Double = 0.0,
    val durationSec: Double = 0.0,
    val rate: Double = 1.0,
    val volume: Double? = null,
    val muted: Boolean = false,
    val audio: String? = null,
    val subtitle: String? = null,
    val audioTracks: List<RemoteTrack> = emptyList(),
    val subtitleTracks: List<RemoteTrack> = emptyList(),
    val queue: List<Long> = emptyList(),
    val queueIndex: Int = 0,
    val screen: String? = null,
) {
    val isIdle: Boolean get() = status == "idle" || itemId == null
    val isPlaying: Boolean get() = status == "playing"

    // As it goes to the server: an idle device says so, with its volume and screen if it has them.
    fun toJson(): String = buildJsonObject {
        put("v", v)
        put("status", status)
        if (status != "idle" && itemId != null) {
            put("itemId", itemId)
            put("positionSec", clean(positionSec))
            put("durationSec", clean(durationSec))
            put("rate", clean(rate))
            audio?.let { put("audio", it) }
            subtitle?.let { put("subtitle", it) }
            if (audioTracks.isNotEmpty()) put("audioTracks", tracks(audioTracks))
            if (subtitleTracks.isNotEmpty()) put("subtitleTracks", tracks(subtitleTracks))
            if (queue.isNotEmpty()) {
                putJsonArray("queue") { queue.take(MAX_QUEUE).forEach { add(JsonPrimitive(it)) } }
                put("queueIndex", queueIndex)
            }
        }
        volume?.let { put("volume", clean(it).coerceIn(0.0, 1.0)) }
        put("muted", muted)
        screen?.let { put("screen", it) }
    }.toString()

    private fun tracks(list: List<RemoteTrack>): JsonArray = buildJsonArray {
        list.take(MAX_TRACKS).forEach { t ->
            add(buildJsonObject { put("id", t.id); put("label", t.label.take(MAX_LABEL)); put("lang", t.lang) })
        }
    }

    companion object {
        const val MAX_TRACKS = 64
        const val MAX_QUEUE = 200
        const val MAX_LABEL = 80
        private fun clean(n: Double) = if (n.isFinite()) n else 0.0
    }
}

// One device in a controller's list.
@Serializable
data class RemoteDevice(
    val id: String = "",
    val name: String = "",
    val kind: String = "other",
    val userId: Long = 0,
    val userName: String = "",
    val v: Int = REMOTE_V,
    val capabilities: RemoteCapabilities = RemoteCapabilities(),
    val online: Boolean = false,
    val mine: Boolean = false,
    val thisSession: Boolean = false,
    val state: RemoteState = RemoteState(),
    val stateAt: Long = 0,
    val title: String = "",
    val itemKind: String = "",
    val hidden: Boolean = false,
)

@Serializable
data class DeviceList(val devices: List<RemoteDevice> = emptyList(), val serverTimeMs: Long = 0)

@Serializable
data class CommandSender(val userName: String = "")

// A command as the device receives it. Fields a command doesn't use are simply absent.
@Serializable
data class RemoteCommand(
    val v: Int = REMOTE_V,
    val id: String = "",
    val type: String = "",
    val itemId: Long? = null,
    val queue: List<Long>? = null,
    val queueIndex: Int? = null,
    val positionSec: Double? = null,
    val bySec: Double? = null,
    val level: Double? = null,
    val muted: Boolean? = null,
    val audio: String? = null,
    val subtitle: String? = null,
    val rate: Double? = null,
    val key: String? = null,
    val sender: CommandSender = CommandSender(),
    val sentAt: Long = 0,
)

@Serializable
data class CommandAnswer(val ok: Boolean = false, val sourceStopped: Boolean? = null)

// What arrives on a device's channel.
sealed interface ChannelEvent {
    data class Hello(val deviceId: String, val capabilities: RemoteCapabilities, val heartbeatSec: Int, val serverTimeMs: Long) : ChannelEvent
    data class Command(val command: RemoteCommand) : ChannelEvent
    data class Bye(val reason: String) : ChannelEvent
}

@Serializable
private data class HelloData(val deviceId: String = "", val capabilities: RemoteCapabilities = RemoteCapabilities(), val heartbeatSec: Int = 30, val serverTimeMs: Long = 0)

@Serializable
private data class ByeData(val reason: String = "")

@Serializable
private data class GoneData(val id: String = "")

// An event this app doesn't know, or one whose data can't be read, is nothing: the stream carries on.
fun readChannelEvent(event: SseEvent): ChannelEvent? = runCatching {
    when (event.event) {
        "hello" -> json.decodeFromString<HelloData>(event.data).let { ChannelEvent.Hello(it.deviceId, it.capabilities, it.heartbeatSec, it.serverTimeMs) }
        "command" -> ChannelEvent.Command(json.decodeFromString<RemoteCommand>(event.data))
        "bye" -> ChannelEvent.Bye(json.decodeFromString<ByeData>(event.data).reason)
        else -> null
    }
}.getOrNull()

// What arrives on a controller's stream.
sealed interface WatchEvent {
    data class Snapshot(val list: DeviceList) : WatchEvent
    data class Device(val device: RemoteDevice) : WatchEvent
    data class Gone(val id: String) : WatchEvent
}

fun readWatchEvent(event: SseEvent): WatchEvent? = runCatching {
    when (event.event) {
        "snapshot" -> WatchEvent.Snapshot(json.decodeFromString<DeviceList>(event.data))
        "device" -> json.decodeFromString<RemoteDevice>(event.data).takeIf { it.id.isNotEmpty() }?.let { WatchEvent.Device(it) }
        "gone" -> json.decodeFromString<GoneData>(event.data).id.takeIf { it.isNotEmpty() }?.let { WatchEvent.Gone(it) }
        else -> null
    }
}.getOrNull()

// The list a controller keeps: a snapshot replaces it, a device event replaces or adds one, gone takes one out.
fun applyWatchEvent(devices: List<RemoteDevice>, event: WatchEvent): List<RemoteDevice> = when (event) {
    is WatchEvent.Snapshot -> event.list.devices
    is WatchEvent.Device -> if (devices.any { it.id == event.device.id }) devices.map { if (it.id == event.device.id) event.device else it } else devices + event.device
    is WatchEvent.Gone -> devices.filterNot { it.id == event.id }
}

// The messages this app sends.
object RemoteWire {
    fun announce(name: String, kind: String, capabilities: RemoteCapabilities, deviceId: String, v: Int = REMOTE_V): String = buildJsonObject {
        put("v", v)
        put("name", name.take(60))
        put("kind", kind)
        putJsonObject("capabilities") {
            putJsonArray("mediaKinds") { capabilities.mediaKinds.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("features") { capabilities.features.forEach { add(JsonPrimitive(it)) } }
        }
        if (deviceId.isNotEmpty()) put("deviceId", deviceId)
    }.toString()

    // `error` is shown to whoever holds the controller: a sentence, at most 200 characters.
    fun ack(id: String, error: String?): String = buildJsonObject {
        put("id", id)
        put("ok", error == null)
        if (error != null) put("error", error.take(200))
    }.toString()

    private fun command(type: String, more: (kotlinx.serialization.json.JsonObjectBuilder.() -> Unit)? = null): JsonObject = buildJsonObject {
        put("v", REMOTE_V)
        put("type", type)
        more?.invoke(this)
    }

    fun simple(type: String) = command(type)
    fun play(itemId: Long, positionSec: Double? = null, audio: String? = null, subtitle: String? = null) = command("play") {
        put("itemId", itemId)
        positionSec?.let { put("positionSec", it) }
        audio?.let { put("audio", it) }
        subtitle?.let { put("subtitle", it) }
    }
    fun playQueue(queue: List<Long>, index: Int, positionSec: Double? = null) = command("play") {
        putJsonArray("queue") { queue.forEach { add(JsonPrimitive(it)) } }
        put("queueIndex", index)
        positionSec?.let { put("positionSec", it) }
    }
    fun seekTo(positionSec: Double) = command("seek") { put("positionSec", positionSec) }
    fun seekBy(bySec: Double) = command("seek") { put("bySec", bySec) }
    fun volume(level: Double) = command("volume") { put("level", level.coerceIn(0.0, 1.0)) }
    fun mute(muted: Boolean) = command("mute") { put("muted", muted) }
    fun audio(id: String) = command("audio") { put("audio", id) }
    fun subtitle(id: String) = command("subtitle") { put("subtitle", id) }
    fun rate(rate: Double) = command("rate") { put("rate", rate.coerceIn(0.25, 4.0)) }
    fun navigate(key: String) = command("navigate") { put("key", key) }
    fun cast(from: String) = command("cast") { put("from", from) }
}
