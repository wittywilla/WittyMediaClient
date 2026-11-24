// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString

// The bell's routes (the server's docs/NOTIFICATIONS.md): each profile's notifications, how many are unread, and the
// kinds it gets. The same calls the website and the Apple apps make.

@Serializable
data class Note(
    val id: Long = 0, val kind: String = "", val title: String = "", val body: String = "", val link: String = "",
    val at: Long = 0, val read: Boolean = false,
)

@Serializable
data class NoteList(val notes: List<Note>? = null, val unread: Int = 0, val latest: Long = 0)

@Serializable
data class NoteCount(val unread: Int = 0, val latest: Long = 0)

@Serializable
data class NoteChoice(val kind: String = "", val on: Boolean = true)

@Serializable
data class NoteChoices(val choices: List<NoteChoice>? = null)

@Serializable
private data class NoteIds(val ids: List<Long>)

suspend fun Api.noteCount(): NoteCount = json.decodeFromString(call("GET", "/me/notifications/count"))

suspend fun Api.notes(before: Long = 0, limit: Int = 30): NoteList =
    json.decodeFromString(call("GET", "/me/notifications?limit=$limit" + if (before > 0) "&before=$before" else ""))

// None named: every one.
suspend fun Api.markNotesRead(ids: List<Long> = emptyList()): NoteCount =
    json.decodeFromString(call("POST", "/me/notifications/read", if (ids.isEmpty()) "{}" else json.encodeToString(NoteIds(ids))))

// 0: every one.
suspend fun Api.clearNotes(id: Long = 0): NoteCount =
    json.decodeFromString(call("DELETE", "/me/notifications" + if (id > 0) "/$id" else ""))

suspend fun Api.noteChoices(): List<NoteChoice> = json.decodeFromString<NoteChoices>(call("GET", "/me/notifications/choices")).choices.orEmpty()

suspend fun Api.setNoteChoices(list: List<NoteChoice>): List<NoteChoice> =
    json.decodeFromString<NoteChoices>(call("PUT", "/me/notifications/choices", json.encodeToString(NoteChoices(list)))).choices.orEmpty()

// What each kind is called, and what it's about, as the website's Settings → Notifications says.
object NoteKinds {
    val names = mapOf(
        "episodes" to ("New episodes" to "When a scan finds new episodes of a show you can watch."),
        "recordings" to ("Recordings" to "When a recording you set up finishes, or fails."),
        "scans" to ("Failed scans" to "When a library scan stops on an error."),
        "modules" to ("Module updates" to "When modules you have get new versions."),
        "server" to ("Server updates" to "When a new version of WittyMediaServer is out."),
    )

    // A link is a path in the website; only one that is a path is followed.
    fun safeLink(link: String): String = if (link.startsWith("/") && !link.startsWith("//") && '\\' !in link) link else ""

    // Notes newer than `after` that haven't been read, oldest first: what a phone's own notifications show.
    fun fresh(list: List<Note>, after: Long, most: Int = 3): List<Note> =
        list.filter { it.id > after && !it.read }.sortedBy { it.id }.takeLast(most)
}
