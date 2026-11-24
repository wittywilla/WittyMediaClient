// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Note
import com.wittywilla.wittymediaclient.net.NoteChoices
import com.wittywilla.wittymediaclient.net.NoteKinds
import com.wittywilla.wittymediaclient.net.NoteList
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The bell's answers as the server sends them, and what a phone's own notifications would show.
class NotesTest {
    @Test
    fun readsTheServersList() {
        val l = json.decodeFromString<NoteList>(
            """{"notes":[{"id":9,"kind":"episodes","title":"New episode of A","body":"S1 E2 · B","link":"/show/4","at":1795000000,"read":false},
               {"id":7,"kind":"server","title":"WittyMediaServer 0.8.4-alpha is out","at":1794000000,"read":true}],"unread":1,"latest":9,"extra":true}""",
        )
        assertEquals(2, l.notes!!.size)
        assertEquals("/show/4", l.notes!![0].link)
        assertEquals("", l.notes!![1].body)
        assertEquals(1, l.unread)
        // A server with none sends an empty list, or null from an older Go.
        assertTrue(json.decodeFromString<NoteList>("""{"notes":null,"unread":0,"latest":0}""").notes.orEmpty().isEmpty())
        assertEquals(2, json.decodeFromString<NoteChoices>("""{"choices":[{"kind":"episodes","on":true},{"kind":"recordings","on":false}]}""").choices!!.size)
    }

    @Test
    fun onlyNewUnreadOnesReachThePhone() {
        val list = listOf(Note(id = 12), Note(id = 11, read = true), Note(id = 10), Note(id = 9), Note(id = 8), Note(id = 3))
        assertEquals(listOf(9L, 10L, 12L), NoteKinds.fresh(list, after = 5).map { it.id })
        assertEquals(listOf(12L), NoteKinds.fresh(list, after = 11).map { it.id })
        assertTrue(NoteKinds.fresh(list, after = 12).isEmpty())
    }

    @Test
    fun linksStayInsideTheApp() {
        assertEquals("/show/4", NoteKinds.safeLink("/show/4"))
        assertEquals("", NoteKinds.safeLink("https://elsewhere.example/x"))
        assertEquals("", NoteKinds.safeLink("//elsewhere.example/x"))
        assertEquals("", NoteKinds.safeLink("/\\elsewhere"))
        // Every kind the server sends has words.
        listOf("episodes", "recordings", "scans", "modules", "server").forEach { assertTrue(it, NoteKinds.names.containsKey(it)) }
    }
}
