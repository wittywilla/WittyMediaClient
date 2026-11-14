// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// The server's own SDUI catalogue, bundled (resources/sdui-catalog.json, written by scripts/sync-sdui-catalog.sh): the
// routes, commands and card styles the app draws with before the server's catalogue has answered, and in offline
// tests. It can't drift into a table kept by hand; SduiCatalogSyncTest checks it against a server checkout.
object SduiBuiltIn {
    const val RESOURCE = "/sdui-catalog.json"

    val catalog: SduiCatalog by lazy {
        val text = SduiBuiltIn::class.java.getResourceAsStream(RESOURCE)?.use { it.readBytes().decodeToString() }
            ?: error("the bundled SDUI catalogue is missing: run android/scripts/sync-sdui-catalog.sh")
        json.decodeFromString(SduiCatalog.serializer(), text)
    }
}
