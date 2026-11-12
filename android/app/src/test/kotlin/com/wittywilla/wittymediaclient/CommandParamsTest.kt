// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SduiCommandParam
import com.wittywilla.wittymediaclient.net.SduiCommandSpec
import com.wittywilla.wittymediaclient.net.SduiCommands
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// Commands that take values beyond the item (catalogue revision 6): they fill {name} in the path and body.
class CommandParamsTest {
    private var before = 0

    // From revision 16 a template holds {item} inside its JSON string.
    @org.junit.Before fun revision() { before = SduiCommands.serverRevision; SduiCommands.serverRevision = 16 }
    @org.junit.After fun restore() { SduiCommands.serverRevision = before }

    private val room = SduiCommandSpec(
        "wittyplay.room.create", "POST", "/api/v1/rooms/{game}/new?code={code}", """{"name":"{name}","slots":"{slots}","item":"{item}"}""",
        listOf(SduiCommandParam("game", "string", true), SduiCommandParam("code"), SduiCommandParam("name"), SduiCommandParam("slots", "int")),
    )

    @Test fun `values fill the path escaped for a url and the body escaped for json`() {
        val r = SduiCommands.request(room, "g1", mapOf("game" to "a b/c", "code" to "x&y", "name" to "Say \"hi\"", "slots" to "4"))!!
        assertEquals("/api/v1/rooms/a%20b%2Fc/new?code=x%26y", r.path)
        assertEquals("""{"name":"Say \"hi\"","slots":4,"item":"g1"}""", r.body)
    }

    @Test fun `a value not given is an empty string, and a required one refuses`() {
        val r = SduiCommands.request(room, "g1", mapOf("game" to "g"))!!
        assertEquals("""{"name":"","slots":"","item":"g1"}""", r.body)
        assertEquals("/api/v1/rooms/g/new?code=", r.path)
        assertNull(SduiCommands.request(room, "g1", emptyMap()))
    }

    @Test fun `an int that is not a number refuses`() {
        assertNull(SduiCommands.request(room, "g1", mapOf("game" to "g", "slots" to "many")))
    }
}
