// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.MoreInfoRules
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MoreInfoTest {
    private val reply = json.parseToJsonElement("""{
      "channel":{"key":"c1","number":"7","name":"Seven","logo":"/l.png"},
      "programme":{"start":1000,"end":4600,"title":"The Show","sub":"Pilot","desc":"A thing.","year":2024,"rating":"TV-14","season":2,"episode":3,"lengthMin":60,"genres":["Drama","Crime","Mystery","Extra"],"new":true,"hd":true},
      "actions":{"watch":true,"record":false,"remind":true,"reminded":true,"open":true},
      "library":{"itemId":9},
      "credits":{"cast":[{"name":"Ann","character":"Mia","personId":4},{"name":"Guide Only","character":"Bob"}],"crew":[{"name":"Dee","job":"Director","personId":5}]},
      "schedule":[{"channel":"Seven","start":1000,"this":true},{"channel":"Eight","number":"8","start":9000}],
      "ids":{"imdb":"tt1","tmdb":"2"}}""") as JsonObject

    @Test fun `facts read in order and the genres are capped`() {
        assertEquals(listOf("2024", "TV-14", "S2 E3", "1 h", "Drama, Crime, Mystery", "New", "HD"), MoreInfoRules.facts(reply["programme"] as JsonObject))
    }

    @Test fun `the buttons are the servers`() {
        val i = MoreInfoRules.parse(reply)
        assertTrue(i.actions.watch); assertFalse(i.actions.record); assertTrue(i.actions.reminded); assertEquals(9L, i.itemId)
        assertEquals("tt1", i.imdb)
    }

    @Test fun `a person only the guide knows is not openable`() {
        val people = MoreInfoRules.parse(reply).people
        assertEquals(listOf("Ann", "Guide Only", "Dee"), people.map { it.name })
        assertEquals(listOf(true, false, true), people.map { it.openable })
        assertEquals("Director", people.last().role)
    }

    @Test fun `the other airings keep which is this one`() {
        val s = MoreInfoRules.parse(reply).schedule
        assertEquals(listOf(true, false), s.map { it.here })
        assertEquals("8", s[1].number)
    }

    @Test fun `an empty answer is an empty page and not a crash`() {
        val i = MoreInfoRules.parse(JsonObject(emptyMap()))
        assertEquals("", i.title); assertTrue(i.people.isEmpty()); assertTrue(i.facts.isEmpty())
    }
}
