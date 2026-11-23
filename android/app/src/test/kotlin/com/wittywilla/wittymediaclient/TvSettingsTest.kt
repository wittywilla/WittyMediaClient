// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.TV_DESKTOP_ONLY
import com.wittywilla.wittymediaclient.net.TV_FULL
import com.wittywilla.wittymediaclient.net.TV_VIEW
import com.wittywilla.wittymediaclient.net.TvSettingsFile
import com.wittywilla.wittymediaclient.net.TvSettingsRow
import com.wittywilla.wittymediaclient.net.TvSettingsRules
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.ui.YouOpens
import com.wittywilla.wittymediaclient.ui.YouWho
import com.wittywilla.wittymediaclient.ui.youGroups
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// shared/data/tv-settings.json, the desktop Settings pages a TV draws itself, and how its values are read and kept.
class TvSettingsTest {
    private val repo = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "shared/data").isDirectory }
    private val file: TvSettingsFile = json.decodeFromString(File(repo, "shared/data/tv-settings.json").readText())
    private val strings: Map<String, String> = json.parseToJsonElement(File(repo, "shared/data/strings.en.json").readText()).jsonObject.mapValues { it.value.jsonPrimitive.content }
    private fun words(k: String) = if (k.isEmpty()) "" else strings[k] ?: k
    private fun row(page: String, key: String) = TvSettingsRules.page(file, page)!!.groups.flatMap { it.rows }.first { it.key == key || it.id == key }

    @Test
    fun everyWordIsTranslatedAndEveryRowIsKeptSomewhere() {
        val levels = setOf(TV_FULL, TV_VIEW, TV_DESKTOP_ONLY)
        assertTrue(file.pages.size >= 7)
        for (page in file.pages) {
            assertTrue(page.id, page.level in levels)
            for (k in listOf(page.title, page.lead)) assertTrue("$k on ${page.id}", k in strings)
            for (g in page.groups) {
                for (k in listOf(g.title, g.footer).filter { it.isNotEmpty() }) assertTrue("$k on ${page.id}", k in strings)
                for (r in g.rows) {
                    assertTrue("${r.label} on ${page.id}", r.label in strings)
                    if (r.help.isNotEmpty()) assertTrue(r.help, r.help in strings)
                    if (r.level.isNotEmpty()) assertTrue(r.level in levels)
                    when (r.kind) {
                        "bool", "enum", "int" -> assertTrue("${r.key} has no store", r.store in file.stores)
                        "link", "desktopOnly" -> assertTrue(r.to.startsWith("/") || r.to.startsWith("app:") || r.to.startsWith("tv:"))
                        "info", "list" -> assertTrue(r.store.isEmpty() || r.store in file.stores)
                        else -> error("unknown kind ${r.kind}")
                    }
                    if (r.to.startsWith("tv:")) assertTrue(TvSettingsRules.page(file, r.to.removePrefix("tv:")) != null)
                    // Option words: a key, or a language's own name.
                    r.options.forEach { assertTrue(it.label.isNotEmpty()) }
                }
            }
        }
    }

    @Test
    fun aSwitchReadsFlagsBooleansDefaultsAndItsOpposite() {
        val uploads = row("sharing", "uploads")
        assertTrue(TvSettingsRules.bool(uploads, JsonPrimitive("1")))
        assertFalse(TvSettingsRules.bool(uploads, JsonPrimitive("0")))
        assertTrue(TvSettingsRules.bool(uploads, JsonPrimitive(""))) // never saved: its default, on
        assertEquals(JsonPrimitive("0"), TvSettingsRules.encode(uploads, JsonPrimitive(false)))
        // Show the activity button is kept as activityHidden.
        val shown = row("activity", "activityHidden")
        assertTrue(TvSettingsRules.bool(shown, null))
        assertFalse(TvSettingsRules.bool(shown, JsonPrimitive(true)))
        assertEquals(JsonPrimitive(true), TvSettingsRules.encode(shown, JsonPrimitive(false)))
        // A choice kept as a number.
        val severity = row("skipping", "contentFilters.minSeverity")
        assertEquals("0", TvSettingsRules.choice(severity, null))
        assertEquals("2", TvSettingsRules.choice(severity, JsonPrimitive(2)))
        assertEquals(JsonPrimitive(3L), TvSettingsRules.encode(severity, JsonPrimitive("3")))
    }

    @Test
    fun aChangeIsSentAsTheWebSendsIt() {
        val stores = file.stores
        // /settings: the key alone, as text, with any key kept alongside it.
        val audio = row("appearance", "audioLanguage")
        assertEquals("""{"audioLanguage":"fr","menuLanguage":"fr"}""", TvSettingsRules.body(stores["server"]!!, null, audio, JsonPrimitive("fr")).toString())
        assertEquals("""{"audioLanguage":""}""", TvSettingsRules.body(stores["server"]!!, null, audio, JsonPrimitive("")).toString())
        val keep = row("activity", "activityKeepCount")
        assertEquals("""{"activityKeepCount":"550"}""", TvSettingsRules.body(stores["server"]!!, null, keep, JsonPrimitive(550L)).toString())
        assertEquals(1000L, TvSettingsRules.stepped(keep, 950, 1))
        assertEquals(5000L, TvSettingsRules.stepped(keep, 5000, 1))
        assertEquals(10L, TvSettingsRules.stepped(keep, 40, -1))
        // /me/ui: everything there now, with the change inside its object.
        val fresh = json.parseToJsonElement("""{"posterTilt":false,"autoSkip":{"intro":true,"recap":false}}""")
        val credits = row("skipping", "autoSkip.credits")
        assertEquals(
            """{"posterTilt":false,"autoSkip":{"intro":true,"recap":false,"credits":true}}""",
            TvSettingsRules.body(stores["ui"]!!, fresh, credits, JsonPrimitive(true)).toString(),
        )
        // /me/streaming: its prefs, home and away together.
        val streaming = json.parseToJsonElement("""{"prefs":{"home":"","away":"h720-b4000"},"profile":{},"remote":{"maxHeight":1080}}""")
        val home = row("quality", "prefs.home")
        assertEquals("""{"home":"h1080-b8000","away":"h720-b4000"}""", TvSettingsRules.body(stores["streaming"]!!, streaming, home, JsonPrimitive("h1080-b8000")).toString())
    }

    @Test
    fun valuesAreShownInTheirOwnWords() {
        val streaming = json.parseToJsonElement("""{"prefs":{"home":"h1080-b6000","away":""},"profile":{},"remote":{"maxHeight":1080,"maxKbps":8000}}""")
        val page = TvSettingsRules.page(file, "quality")!!
        val groups = TvSettingsRules.visible(file, page, admin = false)
        val view = TvSettingsRules.asModule(file, page, groups, mapOf("streaming" to streaming), ::words)
        val rows = view.pages.single().groups.flatMap { it.rows }
        val home = rows.first { it.key == "streaming:prefs.home" }
        // A choice made in the player that isn't one of these is named as such.
        assertEquals("Your own, set in the player", home.options.last().label)
        assertEquals("profile", home.scope) // changed here
        val values = view.values
        assertEquals("No limit", values["streaming:profile"]?.jsonPrimitive?.content)
        assertEquals("up to 1080p, 8 Mb/s at most", values["streaming:remote"]?.jsonPrimitive?.content)
        assertEquals("", values["streaming:prefs.away"]?.jsonPrimitive?.content)
    }

    @Test
    fun administratorsSeeTheServersRowsAndViewPagesAreRead() {
        val activity = TvSettingsRules.page(file, "activity")!!
        val mine = TvSettingsRules.visible(file, activity, admin = false).flatMap { it.rows }
        assertEquals(listOf("activityHidden"), mine.map { it.key })
        val theirs = TvSettingsRules.visible(file, activity, admin = true).flatMap { it.rows }
        assertTrue(theirs.any { it.key == "activityKeepDays" })
        val playback = TvSettingsRules.page(file, "playback")!!
        assertFalse(TvSettingsRules.pageVisible(playback, admin = false))
        assertFalse(TvSettingsRules.editable(file, playback, row("playback", "maxSpeed")))
        assertTrue(TvSettingsRules.editable(file, activity, row("activity", "activityKeepDays")))
        val about = mapOf<String, JsonElement>("about" to json.parseToJsonElement("""{"version":"0.8.1-alpha","modules":[{"name":"WittyDVD","version":"0.4.0"}]}"""))
        assertEquals(listOf("WittyDVD" to "0.4.0"), TvSettingsRules.items(row("about", "modules"), about))
        assertNull(TvSettingsRules.value(TvSettingsRow(kind = "link", to = "app:theme"), about, ::words))
        assertEquals(JsonObject(emptyMap()).toString(), "{}")
    }

    @Test
    fun aTvOpensItsOwnSettingsPagesAndTheCardsForAComputersEditors() {
        val tv = YouWho(admin = true, adult = true, hasGames = false, twoStepAvailable = false, onTv = true)
        val rows = youGroups(tv).flatMap { it.rows }.associate { it.key to it.opens }
        assertEquals(YouOpens.Tv("quality"), rows["rowVideoQuality"])
        assertEquals(YouOpens.Tv("skipping"), rows["rowSkipping"])
        assertEquals(YouOpens.Tv("playback"), rows["rowPlayback"])
        assertEquals(YouOpens.Tv("appearance"), rows["rowAppearance"])
        assertEquals(YouOpens.Tv("activity"), rows["rowActivity"])
        assertEquals(YouOpens.Tv("about"), rows["rowAboutServer"])
        assertEquals(YouOpens.Card("/settings/data-folder"), rows["rowDataFolder"])
        assertEquals(YouOpens.Page("/settings/network"), rows["rowNetwork"])
        val phone = youGroups(tv.copy(onTv = false)).flatMap { it.rows }.associate { it.key to it.opens }
        assertEquals(YouOpens.Page("/settings/playback"), phone["rowPlayback"])
        assertFalse("rowSkipping" in phone)
    }
}
