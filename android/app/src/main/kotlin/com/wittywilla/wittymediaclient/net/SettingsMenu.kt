// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable

// The settings menu every client draws (the server's pkg/sdui/data/settingsmenu.json, in its catalogue as
// settingsMenu; a copy in shared/data for a server that doesn't send it yet): this app's You page, its groups, rows,
// order and words, so the web, its TV mode, the desktop app and the Apple apps show the same list. These are its
// rules with nothing from Android, so they can be tested.

@Serializable
data class SettingsMenuIcon(val android: String = "", val apple: String = "", val web: String = "")

@Serializable
data class SettingsMenuRow(
    val id: String = "",
    val key: String = "",
    val title: String = "",
    val icon: SettingsMenuIcon = SettingsMenuIcon(),
    val tint: String = "",
    val native: String = "",
    val path: String = "",
    val sdui: Boolean = false,
    val part: String = "",
    val `when`: List<String> = emptyList(),
    val value: String = "",
    val summary: String = "",
)

@Serializable
data class SettingsMenuGroup(val id: String = "", val key: String = "", val title: String = "", val rows: List<SettingsMenuRow> = emptyList())

@Serializable
data class SettingsMenu(
    val note: String = "",
    val conditions: List<String> = emptyList(),
    val values: List<String> = emptyList(),
    val groups: List<SettingsMenuGroup> = emptyList(),
)

// Whether a row's condition holds for these facts (YouWho, as `facts`): unknown conditions keep the row out.
fun settingsCondition(cond: String, facts: Set<String>, off: Set<String>): Boolean = when {
    cond.startsWith("notOff:") -> cond.removePrefix("notOff:") !in off
    cond == "notTv" -> "tv" !in facts
    else -> cond in facts
}

// The groups this person sees, in the menu's order; a group left with no rows is left out.
fun SettingsMenu.visible(facts: Set<String>, off: Set<String>, opens: (SettingsMenuRow) -> Boolean = { true }): List<SettingsMenuGroup> =
    groups.map { g -> g.copy(rows = g.rows.filter { r -> r.`when`.all { settingsCondition(it, facts, off) } && opens(r) }) }.filter { it.rows.isNotEmpty() }

// What a TV may do with a row: its part's level, else its page's. With no table, every server page is the card.
fun TvLevelTable?.levelOf(row: SettingsMenuRow): String = when {
    row.part.isNotEmpty() -> this?.partLevel(row.part) ?: TV_DESKTOP_ONLY
    row.path.isEmpty() -> TV_FULL
    this == null -> TV_DESKTOP_ONLY
    else -> screenFor(row.path.substringBefore('#'))?.level ?: TV_FULL
}

// The TV summary a row shows where a TV can't change it: its own, else its page's.
fun TvLevelTable?.summaryOf(row: SettingsMenuRow): String =
    row.summary.ifEmpty { if (row.path.isEmpty()) "" else this?.screenFor(row.path.substringBefore('#'))?.summary.orEmpty() }
