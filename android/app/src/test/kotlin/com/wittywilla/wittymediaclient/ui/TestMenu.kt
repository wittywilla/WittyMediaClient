// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.SettingsMenu
import com.wittywilla.wittymediaclient.net.TvLevelTable
import com.wittywilla.wittymediaclient.net.json
import java.io.File

// The settings menu and TV table the app is built with (shared/data), for the tests: the server's own copies,
// which CI checks are the same (shared/scripts/sync-settings-menu.mjs).
val TEST_MENU: SettingsMenu by lazy { json.decodeFromString(File("../../shared/data/settingsmenu.json").readText()) }

// The You groups from that menu.
fun youGroups(who: YouWho): List<YouGroup> = youGroups(who, TEST_MENU)

// The server's TV table as it is in its repository beside this one, when it is there.
fun serverTvLevels(): TvLevelTable? =
    File("../../../WittyMediaServer/pkg/sdui/data/tvlevels.json").takeIf { it.exists() }?.let { json.decodeFromString(it.readText()) }
