// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.remote

import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.events
import com.wittywilla.wittymediaclient.net.json
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// The Remote Protocol's routes (docs/REMOTE-PROTOCOL.md). A refusal is an ApiError carrying the server's code.

suspend fun Api.remoteInfo(): RemoteInfo = json.decodeFromString(call("GET", "/remote-control"))

// As a device.
suspend fun Api.remoteAnnounce(body: String): Announced = json.decodeFromString(call("POST", "/remote-control/devices", body))
fun Api.remoteChannel(deviceId: String, opened: () -> Unit = {}): Flow<SseEvent> = events("/remote-control/devices/${encode(deviceId)}/channel", opened)
suspend fun Api.remoteAck(deviceId: String, body: String) { call("POST", "/remote-control/devices/${encode(deviceId)}/ack", body) }
suspend fun Api.remoteState(deviceId: String, body: String) { call("POST", "/remote-control/devices/${encode(deviceId)}/state", body) }
suspend fun Api.remoteLeave(deviceId: String) { call("DELETE", "/remote-control/devices/${encode(deviceId)}") }

// As a controller.
suspend fun Api.remoteDevices(): DeviceList = json.decodeFromString(call("GET", "/remote-control/devices"))
fun Api.remoteWatch(opened: () -> Unit = {}): Flow<SseEvent> = events("/remote-control/events", opened)
suspend fun Api.remoteCommand(deviceId: String, command: JsonObject): CommandAnswer =
    json.decodeFromString(call("POST", "/remote-control/devices/${encode(deviceId)}/commands", command.toString()))

// Whether this profile's limits leave remote control on (GET /me/limits). The server says it as `features.remote`;
// an `off` list naming it is read the same way. A server without profile limits has no such route: on.
suspend fun Api.remoteAllowedForProfile(): Boolean = try {
    val limits = json.parseToJsonElement(call("GET", "/me/limits")).jsonObject
    val feature = limits["features"]?.let { it as? JsonObject }?.get("remote")?.jsonPrimitive?.content
    val off = runCatching { limits["off"]?.jsonArray?.map { it.jsonPrimitive.content } }.getOrNull().orEmpty()
    feature != "false" && "remote" !in off
} catch (e: ApiError) {
    e.status == 404
}

fun remoteWords(e: ApiError): String = remoteErrorWords(e.status, e.code, e.message.orEmpty(), e.retryAfterSec)
