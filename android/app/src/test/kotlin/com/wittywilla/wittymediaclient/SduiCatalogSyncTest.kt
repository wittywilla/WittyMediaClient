// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SDUI_CATALOG
import com.wittywilla.wittymediaclient.net.SduiBuiltIn
import com.wittywilla.wittymediaclient.net.SduiCardStyles
import com.wittywilla.wittymediaclient.net.SduiRouter
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.TimeUnit

// The catalogue the app draws with before the server answers is the server's own, bundled: it can't drift into a table
// kept by hand. android/scripts/sync-sdui-catalog.sh writes it.
class SduiCatalogSyncTest {
    private fun bundled(): String = SduiBuiltIn::class.java.getResourceAsStream(SduiBuiltIn.RESOURCE)!!.use { it.readBytes().decodeToString() }

    @Test
    fun theBundledCatalogueIsWholeAndOfThisAppsRevision() {
        val catalog = SduiBuiltIn.catalog
        assertEquals("the bundled catalogue is of another revision than this app speaks: bump SDUI_CATALOG with it", SDUI_CATALOG, catalog.revision)
        // Every row the server wrote is one this app reads: nothing is quietly left out.
        val raw = Json.parseToJsonElement(bundled()) as JsonObject
        assertEquals((raw["cardStyles"] as JsonArray).size, catalog.cardStyles.size)
        assertEquals((raw["routes"] as JsonArray).size, catalog.routes.size)
        assertEquals((raw["commands"] as JsonArray).size, catalog.commands.size)
        assertFalse(catalog.cardStyles.isEmpty() || catalog.routes.isEmpty() || catalog.commands.isEmpty())
        assertEquals(catalog.cardStyles.size, SduiCardStyles.BUILT_IN.size)
        val ops = SduiRouter.DEFAULT_COMMANDS.associateBy { it.op }
        for (op in listOf("watchLater.add", "watchLater.remove", "watched.set", "watched.clear", "refresh", "selectTab")) assertNotNull(op, ops[op])
        assertEquals("""{"items":["{item}"]}""", ops["watchLater.add"]?.body)
    }

    // The server checkout beside this one, or WITTYMEDIASERVER_SRC.
    private fun serverCheckout(): File? {
        fun usable(f: File) = File(f, "scripts/sdui-catalog/main.go").isFile
        System.getenv("WITTYMEDIASERVER_SRC")?.takeIf { it.isNotEmpty() }?.let { return File(it).takeIf(::usable) }
        var folder: File? = File(System.getProperty("user.dir")).absoluteFile
        repeat(9) {
            folder = folder?.parentFile ?: return null
            File(folder, "WittyMediaServer").takeIf(::usable)?.let { return it }
        }
        return null
    }

    // The bundled copy is what the server checkout beside this one prints now. It fails until
    // android/scripts/sync-sdui-catalog.sh is run after the server's catalogue changes.
    @Test
    fun theBundledCatalogueIsTheServers() {
        val server = serverCheckout()
        assumeTrue("No WittyMediaServer checkout beside this one (or WITTYMEDIASERVER_SRC) to compare the bundled catalogue with.", server != null)
        val go = ProcessBuilder("go", "run", "./scripts/sdui-catalog").directory(server).redirectError(ProcessBuilder.Redirect.to(File.createTempFile("sdui-catalog", ".log").apply { deleteOnExit() }))
        val process = runCatching { go.start() }.getOrNull()
        assumeTrue("Go isn't on this machine's PATH.", process != null)
        val printed = process!!.inputStream.use { it.readBytes().decodeToString() }
        assumeTrue("go run took too long", process.waitFor(5, TimeUnit.MINUTES))
        assertEquals("go run ./scripts/sdui-catalog failed", 0, process.exitValue())
        assertEquals("the bundled catalogue differs from the server's: run android/scripts/sync-sdui-catalog.sh",
            Json.parseToJsonElement(printed), Json.parseToJsonElement(bundled()))
    }
}
