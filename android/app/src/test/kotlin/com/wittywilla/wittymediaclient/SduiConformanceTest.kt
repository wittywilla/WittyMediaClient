// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SduiDocument
import com.wittywilla.wittymediaclient.net.SduiPage
import com.wittywilla.wittymediaclient.net.SduiScreen
import com.wittywilla.wittymediaclient.net.SduiSectionItems
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.child
import com.wittywilla.wittymediaclient.net.objects
import com.wittywilla.wittymediaclient.net.str
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

// The server's conformance kit (pkg/sdui/conformance in the server's repository): for every fixture, the document the
// server sends is read with the app's own decoder, laid out as the app lays it out (SduiScreen, what the composables
// draw from), described in the kit's normalised shape, and compared with what the kit expects. And every "more" answer
// goes through what handles a real one. app/build.gradle.kts says where the fixtures are read from.
class SduiConformanceTest {
    private val folder: File? = System.getProperty("sdui.fixtures")?.let(::File)?.takeIf { File(it, "index.json").isFile }

    private fun fixtures(): List<JsonObject> {
        if (folder == null) {
            if (System.getProperty("sdui.fixtures.required") != null) fail("The SDUI conformance fixtures weren't found. Pass -PsduiFixtures=<the server's pkg/sdui/conformance/fixtures>.")
            assumeTrue("no SDUI conformance fixtures here", false)
        }
        val index = json.parseToJsonElement(File(folder, "index.json").readText()).jsonObject
        return index.objects("cases").map { json.parseToJsonElement(File(folder, it.str("file")).readText()).jsonObject }
    }

    // A missing key and its zero value are the same, and so are 10 and 10.0.
    private fun plain(e: JsonElement): JsonElement? = when (e) {
        is JsonNull -> null
        is JsonObject -> e.mapNotNull { (k, v) -> plain(v)?.let { k to it } }.sortedBy { it.first }.toMap(LinkedHashMap()).takeIf { it.isNotEmpty() }?.let(::JsonObject)
        is JsonArray -> e.map { plain(it) ?: JsonNull }.takeIf { it.isNotEmpty() }?.let(::JsonArray)
        is JsonPrimitive -> when {
            e.isString -> e.takeIf { it.content.isNotEmpty() }
            e.booleanOrNull != null -> e.takeIf { it.booleanOrNull == true }
            else -> e.doubleOrNull?.takeIf { it != 0.0 }?.let(::JsonPrimitive)
        }
    }

    private fun firstDifference(got: JsonObject, want: JsonObject): String {
        val g = got["visible"] as? JsonArray ?: JsonArray(emptyList())
        val w = want["visible"] as? JsonArray ?: JsonArray(emptyList())
        for (i in 0 until maxOf(g.size, w.size)) {
            val a = g.getOrNull(i)?.let(::plain) as? JsonObject
            val b = w.getOrNull(i)?.let(::plain) as? JsonObject
            if (a == b) continue
            val id = (b ?: a)?.str("id")
            val field = ((a?.keys.orEmpty()) + (b?.keys.orEmpty())).firstOrNull { a?.get(it) != b?.get(it) }
            return "element $i ($id), $field: got ${a?.get(field)}, want ${b?.get(field)}"
        }
        for (key in listOf("page", "focus", "kit")) if (got[key]?.let(::plain) != want[key]?.let(::plain)) return "$key: got ${got[key]}, want ${want[key]}"
        return "nothing found"
    }

    @Test
    fun everyFixtureLaysOutAsTheKitExpects() {
        val all = fixtures()
        var checked = 0
        val failures = ArrayList<String>()
        for (fixture in all) {
            val expected = fixture.child("expected") ?: continue
            val sent = expected.child("document")
            if (expected["notFound"]?.let { (it as? JsonPrimitive)?.booleanOrNull } == true || sent == null) {
                // A page that isn't there has no document to lay out: the case is the server's alone.
                checked++
                continue
            }
            val document = json.decodeFromJsonElement(SduiDocument.serializer(), sent)
            val got = SduiScreen(document).normalised()
            val want = expected.child("layout")!!
            if (plain(got) != plain(want)) failures += "${fixture.str("id")}: ${firstDifference(got, want)}" else checked++
        }
        assertTrue("the kit has cases", all.size >= 57)
        assertEquals("fixtures that don't lay out as expected:\n" + failures.joinToString("\n"), all.size, checked)
    }

    @Test
    fun everyMoreAnswerJoinsItsSection() {
        var answers = 0
        for (fixture in fixtures()) {
            val expected = fixture.child("expected") ?: continue
            val sent = expected.child("document") ?: continue
            val document = json.decodeFromJsonElement(SduiDocument.serializer(), sent)
            for (more in expected.objects("more")) {
                val section = more.str("section")
                val answer = json.decodeFromJsonElement(SduiSectionItems.serializer(), more.child("answer")!!)
                val before = SduiPage(document)
                val had = before.find(section)!!.children.map { it.id }
                val after = before.withItems(section, answer)
                val now = after.find(section)
                val came = answer.items.map { it.id }
                val name = "${fixture.str("id")} $section"
                when {
                    answer.state == "empty" && came.isEmpty() && had.isEmpty() -> assertEquals("$name is taken off the page", null, now)
                    answer.replace || before.find(section)!!.state == "deferred" -> assertEquals(name, came, now!!.children.map { it.id })
                    else -> assertEquals(name, had + came.filter { it !in had }, now!!.children.map { it.id })
                }
                if (now != null) {
                    assertEquals("$name asks on from the answer's next", answer.next, after.moreUrl(section))
                    // What the section holds now lays out too.
                    SduiScreen(after.shown).normalised()
                }
                answers++
            }
        }
        assertTrue("the kit has more answers", answers > 0)
    }
}
