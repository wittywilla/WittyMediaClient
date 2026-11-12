// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net.syncplay

import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.Serializable

// A watch party's messages (the server's docs/SYNCPLAY.md, For developers). Fields this app doesn't know are skipped.

@Serializable
data class Drift(val stillSec: Double = 0.12, val settledSec: Double = 0.04, val seekSec: Double = 3.0, val rate: Double = 0.03)

@Serializable
data class SyncLimits(
    val members: Int = 16,
    val queue: Int = 200,
    val invites: Int = 32,
    val codeLength: Int = 6,
    val pingEverySec: Int = 5,
    val awaySec: Int = 20,
    val seatGraceSec: Int = 120,
    val waitTimeoutSec: Int = 15,
)

// A room in GET /syncplay: one this sign-in has a seat in (memberId), or one it is invited to.
@Serializable
data class RoomSummary(val id: String = "", val name: String = "", val hostName: String = "", val members: Int = 0, val invited: Boolean = false, val memberId: String = "")

@Serializable
data class SyncInfo(
    val enabled: Boolean = false,
    val canCreate: Boolean = false,
    // False when this profile's limits turn watch parties off; an older server doesn't say, and lets anyone join.
    val canJoin: Boolean = true,
    val drift: Drift = Drift(),
    val limits: SyncLimits = SyncLimits(),
    val rooms: List<RoomSummary> = emptyList(),
    val serverTimeMs: Long = 0,
)

// The one truth of a room: "at server time atMs, the position is positionSec".
@Serializable
data class RoomState(
    val rev: Long = 0,
    val seq: Long = 0,
    val itemId: Long = 0,
    val index: Int = 0,
    val positionSec: Double = 0.0,
    val atMs: Long = 0,
    val paused: Boolean = true,
    val waiting: Boolean = false,
    val rate: Double = 1.0,
)

@Serializable
data class Member(val id: String = "", val userId: Long = 0, val name: String = "", val host: Boolean = false, val you: Boolean = false, val state: String = "loading", val rttMs: Double = 0.0)

@Serializable
data class RoomItem(val id: Long = 0, val title: String = "", val kind: String = "", val runtimeSec: Double = 0.0)

@Serializable
data class Room(
    val id: String = "",
    val code: String = "",
    val name: String = "",
    val policy: String = "host",
    val waitForAll: Boolean = true,
    val hostId: String = "",
    val you: String = "",
    val canControl: Boolean = false,
    val blocked: Boolean = false,
    // This member's screen time has run out: it sits the party out, keeping its place, until a parent gives more.
    val timeUp: Boolean = false,
    val members: List<Member> = emptyList(),
    val queue: List<Long> = emptyList(),
    val items: List<RoomItem> = emptyList(),
    val state: RoomState = RoomState(),
    val serverTimeMs: Long = 0,
    val leadMs: Long = 300,
) {
    val me: Member? get() = members.firstOrNull { it.id == you }
    val isHost: Boolean get() = hostId.isNotEmpty() && hostId == you
    val everyoneControls: Boolean get() = policy == "everyone"
    val title: String get() = items.firstOrNull { it.id == state.itemId && it.id != 0L }?.title.orEmpty()
}

@Serializable
data class PingAnswer(val t0: Double = 0.0, val t1: Double = 0.0, val t2: Double = 0.0)

@Serializable
private data class ClosedData(val reason: String = "")

@Serializable
private data class StaleBody(val room: Room? = null)

sealed interface RoomEvent {
    data class Changed(val room: Room) : RoomEvent
    data class Closed(val reason: String) : RoomEvent
}

// An event with a name this app doesn't know, or data it can't read, is nothing.
fun readRoomEvent(event: SseEvent): RoomEvent? = runCatching {
    when (event.event) {
        "room" -> json.decodeFromString<Room>(event.data).takeIf { it.id.isNotEmpty() }?.let { RoomEvent.Changed(it) }
        "closed" -> RoomEvent.Closed(json.decodeFromString<ClosedData>(event.data).reason)
        else -> null
    }
}.getOrNull()

// A 409 `stale` carries the room as it is now.
fun staleRoom(body: String): Room? = runCatching { json.decodeFromString<StaleBody>(body).room?.takeIf { it.id.isNotEmpty() } }.getOrNull()
