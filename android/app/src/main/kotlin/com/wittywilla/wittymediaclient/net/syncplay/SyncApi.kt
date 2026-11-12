// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.syncplay

import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.events
import com.wittywilla.wittymediaclient.net.json
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

// A watch party's routes (docs/SYNCPLAY.md). Create, join and commands answer with the room; the host's routes and
// reports answer only that they worked, and the room follows on the stream.

private fun body(member: String, more: JsonObjectBuilder.() -> Unit = {}): String = buildJsonObject {
    if (member.isNotEmpty()) put("member", member)
    more()
}.toString()

suspend fun Api.syncInfo(): SyncInfo = json.decodeFromString(call("GET", "/syncplay"))

suspend fun Api.syncCreate(items: List<Long>, index: Int, name: String, everyone: Boolean, waitForAll: Boolean, device: String, positionSec: Double? = null): Room =
    json.decodeFromString(
        call("POST", "/syncplay/rooms", body("") {
            if (items.size == 1) put("itemId", items[0]) else {
                putJsonArray("items") { items.forEach { add(JsonPrimitive(it)) } }
                put("index", index)
            }
            if (name.isNotBlank()) put("name", name.trim())
            put("policy", if (everyone) "everyone" else "host")
            put("waitForAll", waitForAll)
            put("device", device)
            positionSec?.let { put("positionSec", it) }
        }),
    )

suspend fun Api.syncJoinCode(code: String, device: String): Room =
    json.decodeFromString(call("POST", "/syncplay/join", body("") { put("code", normaliseCode(code)); put("device", device) }))

suspend fun Api.syncJoinRoom(roomId: String, device: String): Room =
    json.decodeFromString(call("POST", "/syncplay/join", body("") { put("roomId", roomId); put("device", device) }))

fun Api.syncEvents(roomId: String, member: String, opened: () -> Unit = {}): Flow<SseEvent> =
    events("/syncplay/rooms/${encode(roomId)}/events?member=${encode(member)}", opened)

suspend fun Api.syncCommand(roomId: String, member: String, type: String, ifSeq: Long? = null, more: JsonObjectBuilder.() -> Unit = {}): Room =
    json.decodeFromString(
        call("POST", "/syncplay/rooms/${encode(roomId)}/command", body(member) {
            put("type", type)
            ifSeq?.let { put("ifSeq", it) }
            more()
        }),
    )

suspend fun Api.syncReport(roomId: String, member: String, state: String, rev: Long) {
    call("POST", "/syncplay/rooms/${encode(roomId)}/report", body(member) { put("state", state); put("rev", rev) })
}

suspend fun Api.syncPing(roomId: String, member: String, t0: Double, rttMs: Double): PingAnswer =
    json.decodeFromString(call("POST", "/syncplay/rooms/${encode(roomId)}/ping", body(member) { put("t0", t0); put("rttMs", rttMs) }))

suspend fun Api.syncLeave(roomId: String, member: String) { call("POST", "/syncplay/rooms/${encode(roomId)}/leave", body(member)) }

// The host's.
suspend fun Api.syncSet(roomId: String, member: String, everyone: Boolean? = null, waitForAll: Boolean? = null, name: String? = null) {
    call("PUT", "/syncplay/rooms/${encode(roomId)}", body(member) {
        everyone?.let { put("policy", if (it) "everyone" else "host") }
        waitForAll?.let { put("waitForAll", it) }
        name?.let { put("name", it) }
    })
}
suspend fun Api.syncMakeHost(roomId: String, member: String, to: String) { call("POST", "/syncplay/rooms/${encode(roomId)}/host", body(member) { put("to", to) }) }
suspend fun Api.syncKick(roomId: String, member: String, whom: String) { call("POST", "/syncplay/rooms/${encode(roomId)}/kick", body(member) { put("whom", whom) }) }
suspend fun Api.syncInvite(roomId: String, member: String, userIds: List<Long>) {
    call("POST", "/syncplay/rooms/${encode(roomId)}/invite", body(member) { putJsonArray("userIds") { userIds.forEach { add(JsonPrimitive(it)) } } })
}
suspend fun Api.syncEnd(roomId: String, member: String) { call("DELETE", "/syncplay/rooms/${encode(roomId)}?member=${encode(member)}") }

fun syncWords(e: ApiError): String = syncErrorWords(e.status, e.code, e.message.orEmpty())
