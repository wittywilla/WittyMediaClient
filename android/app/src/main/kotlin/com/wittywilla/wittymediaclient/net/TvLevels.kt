// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable

// How much of each screen a TV offers (the server's docs/TV-MODE.md). The table is the server's, in its SDUI
// catalogue (tvLevels), so this app's TV screens and the server's own TV mode make the same choices: browsing,
// playing, games and their controllers stay; editors with many fields, typing or dragging are a QR card that
// says to use the WittyMediaClient app on a computer, or a web browser. Whatever is set there is kept on the
// server, so it applies here too. These are the rules with nothing from Android, so they can be tested.

const val TV_FULL = "full"
const val TV_VIEW = "view"
const val TV_DESKTOP_ONLY = "desktopOnly"

@Serializable
data class TvScreenLevel(val id: String = "", val path: String = "", val level: String = TV_FULL, val title: String = "", val summary: String = "")

@Serializable
data class TvPartLevel(val id: String = "", val level: String = TV_FULL, val title: String = "")

@Serializable
data class TvLevelTable(
    val levels: List<String> = emptyList(),
    val default: String = TV_FULL,
    val note: String = "",
    val screens: List<TvScreenLevel> = emptyList(),
    val parts: List<TvPartLevel> = emptyList(),
)

// What GET /sdui/tv-summary/{id} answers: a few lines of what is set now, and the server's addresses at home.
@Serializable
data class TvSummary(val id: String = "", val lines: List<String> = emptyList(), val addresses: List<String> = emptyList())

// ":name" is one part of the address, and "*" at the end is the rest of it, or nothing.
fun tvPathMatches(pattern: String, path: String): Boolean {
    val pp = pattern.trim('/').split('/')
    val trimmed = path.substringBefore('?').substringBefore('#').trim('/')
    val ap = if (trimmed.isEmpty()) emptyList() else trimmed.split('/')
    for ((i, seg) in pp.withIndex()) {
        if (seg == "*" && i == pp.lastIndex) return true
        if (i >= ap.size) return false
        if (seg.startsWith(":")) { if (ap[i].isEmpty()) return false; continue }
        if (seg != ap[i]) return false
    }
    return ap.size == pp.size
}

// The screen an address is, or null for one a TV offers in full. The first match wins, as on the server.
fun TvLevelTable.screenFor(path: String): TvScreenLevel? = screens.firstOrNull { tvPathMatches(it.path, path) }

fun TvLevelTable.partLevel(id: String): String = parts.firstOrNull { it.id == id }?.level ?: TV_FULL

// Whether a TV shows the QR card for a server page instead of opening it. With no table (a server older
// than tvLevels) every server page is the card, as this app always did on a TV.
fun tvShowsCard(table: TvLevelTable?, path: String): Boolean =
    table == null || table.screenFor(path)?.level == TV_DESKTOP_ONLY

// Whether one of this app's own editors (the layout editor, name and logo) opens on a TV.
fun tvPartOpens(table: TvLevelTable?, id: String): Boolean = table?.partLevel(id)?.let { it != TV_DESKTOP_ONLY } ?: false

// The address to put in the QR code: the server's own, unless that is one only this device can open,
// then its first address on the home network.
fun tvCardAddress(base: String, path: String, home: List<String>): String {
    val host = base.substringAfter("://").substringBefore('/').substringBeforeLast(':').trim('[', ']')
    val local = host == "localhost" || host.endsWith(".localhost") || host == "127.0.0.1" || host == "::1"
    val root = (if (local) home.firstOrNull() else null) ?: base
    return root.trimEnd('/') + (if (path.startsWith("/")) path else "/$path")
}
