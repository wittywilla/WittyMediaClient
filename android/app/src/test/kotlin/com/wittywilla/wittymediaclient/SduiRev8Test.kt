// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SduiAction
import com.wittywilla.wittymediaclient.net.SduiCardStyleSpec
import com.wittywilla.wittymediaclient.net.SduiCardStyles
import com.wittywilla.wittymediaclient.net.SduiCommandParam
import com.wittywilla.wittymediaclient.net.SduiCommandSpec
import com.wittywilla.wittymediaclient.net.SduiCommands
import com.wittywilla.wittymediaclient.net.SduiControlSpec
import com.wittywilla.wittymediaclient.net.SduiDocument
import com.wittywilla.wittymediaclient.net.SduiEffect
import com.wittywilla.wittymediaclient.net.SduiFormValues
import com.wittywilla.wittymediaclient.net.SduiItemActions
import com.wittywilla.wittymediaclient.net.SduiPresence
import com.wittywilla.wittymediaclient.net.SduiRegionRules
import com.wittywilla.wittymediaclient.net.SduiRouter
import com.wittywilla.wittymediaclient.net.SduiScreen
import com.wittywilla.wittymediaclient.net.SduiTarget
import com.wittywilla.wittymediaclient.net.SDUI_CATALOG
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.withValue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

// Catalogue revision 8 on Android: the card-style table against the kit's, commands with typed params, item actions, presence,
// controls, forms, regions and layers.
class SduiRev8Test {
    private fun action(text: String) = json.decodeFromString(SduiAction.serializer(), text)
    private fun doc(text: String) = json.decodeFromString(SduiDocument.serializer(), text)

    @Test
    fun builtInCardStylesAreTheCatalogues() {
        val folder = System.getProperty("sdui.fixtures")?.let { File(it).parentFile }
        val table = folder?.let { File(it, "card-style-table.json") }?.takeIf { it.isFile }
        if (table == null) {
            if (System.getProperty("sdui.fixtures.required") != null) throw AssertionError("card-style-table.json was not found beside the fixtures")
            assumeTrue(false)
            return
        }
        val kit = json.parseToJsonElement(table.readText()).jsonObject
        assertEquals(SDUI_CATALOG, (kit["catalogRevision"] as JsonPrimitive).content.toInt())
        val want = (kit["cardStyles"] as JsonArray).map { it.jsonObject }
        assertEquals("the styles the app has", want.map { (it["style"] as JsonPrimitive).content }, SduiCardStyles.BUILT_IN.map { it.style })
        for (w in want) {
            val name = (w["style"] as JsonPrimitive).content
            val has = SduiCardStyles.BUILT_IN.first { it.style == name }
            assertEquals("$name shape", (w["shape"] as JsonPrimitive).content, has.shape)
            assertEquals("$name aspect", (w["aspect"] as JsonPrimitive).content, has.aspect)
            assertEquals("$name shows", (w["shows"] as JsonArray).map { (it as JsonPrimitive).content }, has.shows)
            assertEquals("$name titleLines", (w["titleLines"] as JsonPrimitive).content.toInt(), has.titleLines)
            assertEquals("$name subtitleLines", (w["subtitleLines"] as JsonPrimitive).content.toInt(), has.subtitleLines)
        }
    }

    @Test
    fun cardStylesComeFromTheServedCatalogue() {
        try {
            SduiCardStyles.use(listOf(SduiCardStyleSpec("person", "circle", "1/1", shows = listOf("title"), titleLines = 1, subtitleLines = 0, badgeTones = mapOf("Away" to "warn"))))
            assertEquals(listOf("title"), SduiCardStyles.named("person")!!.shows)
            assertEquals("warn", SduiCardStyles.toneOf("person", "Away"))
            assertEquals("a style the server doesn't send is unknown", null, SduiCardStyles.named("poster"))
        } finally {
            SduiCardStyles.reset()
        }
        assertNotNull(SduiCardStyles.named("poster"))
    }

    @Test
    fun presenceTonesFollowTheBadge() {
        val tones = mapOf("Playing" to "ok", "Online" to "ok", "Away" to "warn", "Offline" to "muted")
        try {
            SduiCardStyles.use(SduiCardStyles.BUILT_IN.map { SduiCardStyleSpec(it.style, it.shape, it.aspect, shows = it.shows, titleLines = it.titleLines, subtitleLines = it.subtitleLines, badgeTones = if (it.style == "person") tones else emptyMap()) })
            assertEquals("ok", SduiPresence.tone("person", listOf("Playing")))
            assertEquals("warn", SduiPresence.tone("person", listOf("Away")))
            assertEquals("muted", SduiPresence.tone("person", listOf("Offline")))
            assertEquals("", SduiPresence.tone("person", listOf("New")))
        } finally {
            SduiCardStyles.reset()
        }
    }

    private fun spec(op: String, path: String, body: String, vararg params: Pair<String, String>) =
        SduiCommandSpec(op, "PUT", path, body, params.map { SduiCommandParam(it.first, it.second, true) })

    @Test
    fun commandParametersAreTyped() {
        val before = SduiCommands.serverRevision
        SduiCommands.serverRevision = 16
        try { commandParameters() } finally { SduiCommands.serverRevision = before }
    }

    private fun commandParameters() {
        val online = spec("wittyplay.online.set", "/api/games/online/me", """{"sharePlaying":"{sharePlaying}","appearOnline":"{appearOnline}"}""", "sharePlaying" to "bool", "appearOnline" to "bool")
        val a = action("""{"type":"command","op":"wittyplay.online.set","params":{"sharePlaying":true,"appearOnline":false}}""")
        assertEquals("""{"sharePlaying":true,"appearOnline":false}""", SduiCommands.request(online, a.item, a.params)!!.body)

        val save = spec("wittyplay.state.save", "/api/play/{item}/action", """{"type":"save","slot":"{slot}"}""", "slot" to "int")
        val s = action("""{"type":"command","op":"wittyplay.state.save","item":"abc","params":{"slot":3}}""")
        val r = SduiCommands.request(save, s.item, s.params)!!
        assertEquals("""{"type":"save","slot":3}""", r.body)
        assertEquals("/api/play/abc/action", r.path)

        val kids = spec("wittyplay.kids.friends", "/api/games/online/kids/{item}", """{"friends":"{friends}"}""", "friends" to "ints")
        val k = action("""{"type":"command","op":"wittyplay.kids.friends","item":"7","params":{"friends":[1,2,3]}}""")
        assertEquals("""{"friends":[1,2,3]}""", SduiCommands.request(kids, k.item, k.params)!!.body)
        val none = action("""{"type":"command","op":"wittyplay.kids.friends","item":"7","params":{"friends":[]}}""")
        assertEquals("""{"friends":[]}""", SduiCommands.request(kids, none.item, none.params)!!.body)

        val shot = spec("wittyplay.memory.delete", "/api/games/{item}/shots/{name}", "", "name" to "string")
        val d = action("""{"type":"command","op":"wittyplay.memory.delete","item":"7","params":{"name":"a b.png"}}""")
        assertEquals("/api/games/7/shots/a%20b.png", SduiCommands.request(shot, d.item, d.params)!!.path)

        val created = spec("collection.create", "/api/collections", """{"name":"{name}","kind":"manual"}""", "name" to "string")
        val c = action("""{"type":"command","op":"collection.create","params":{"name":"Say \"hi\""}}""")
        assertEquals("""{"name":"Say \"hi\"","kind":"manual"}""", SduiCommands.request(created, c.item, c.params)!!.body)

        assertNull("a missing required value is no request", SduiCommands.request(save, "abc", JsonObject(emptyMap())))
    }

    @Test
    fun actionsCarryLayerAndConfirm() {
        val layer = action("""{"type":"navigate","to":"/page/online-options?item=1","as":"layer"}""")
        val open = SduiRouter().effect(layer) as SduiEffect.Open
        assertTrue(open.layer)
        assertTrue(open.target is SduiTarget.Page)
        assertFalse((SduiRouter().effect(action("""{"type":"navigate","to":"/item/3"}""")) as SduiEffect.Open).layer)
        val spec = SduiCommandSpec("watched.clear", "DELETE", "/api/v1/items/{item}/progress", "")
        val router = SduiRouter(commands = listOf(spec))
        val ask = router.effect(action("""{"type":"command","op":"watched.clear","item":"9","confirm":"Forget it?"}""")) as SduiEffect.Command
        assertEquals("Forget it?", ask.confirm)
    }

    private val shelfPage = """{"version":1,"catalog":8,"page":{"id":"p"},"root":{"type":"Page","id":"page","children":[
        {"type":"Shelf","id":"recent","props":{"title":"Recent","focusGrow":true,"detail":true,"cardStyle":"game"},"children":[
          {"type":"Card","id":"c1","props":{"title":"Star Tide","subtitle":"Resume","style":"game","actions":[
            {"id":"play","label":"Resume","glyph":"a","action":{"type":"play","item":"1"}},
            {"id":"online","label":"Play online","glyph":"x","action":{"type":"command","op":"wittyplay.room.create","item":"1"}}]},
           "action":{"type":"navigate","to":"/game/1"},"focus":{"order":1,"group":"recent","default":true}},
          {"type":"Card","id":"c2","props":{"title":"Plain","style":"game"},"action":{"type":"navigate","to":"/game/2"}},
          {"type":"Card","id":"f1","props":{"title":"Pip","style":"person","kind":"person","badges":["Playing"],"subtitle":"Playing Star Tide","focusable":true}}]}]}}"""

    @Test
    fun itemActionsAreButtonsWithGlyphs() {
        val screen = SduiScreen(doc(shelfPage))
        val cards = screen.root.children.single().children
        val first = cards[0]
        assertEquals(listOf("a", "x"), SduiItemActions.of(first.props).map { it.glyph })
        assertEquals("the A key plays", "play 1", SduiScreen.actionWords(SduiItemActions.select(first)))
        assertEquals("command wittyplay.room.create 1", SduiScreen.actionWords(SduiItemActions.forGlyph(first, "x")))
        assertNull(SduiItemActions.forGlyph(first, "y"))
        // An item with none: its own action is the A action.
        assertEquals("navigate /game/2", SduiScreen.actionWords(SduiItemActions.select(cards[1])))
        assertEquals(listOf("Open"), SduiItemActions.buttons(cards[1]).map { it.label })
        // A person with no action: the label is its shown parts joined, and it takes focus because its row says focusable.
        assertEquals("Pip, Playing Star Tide, Playing", cards[2].label)
        assertTrue(com.wittywilla.wittymediaclient.net.SduiFocusRules.focusable(cards[2]))
        assertFalse(com.wittywilla.wittymediaclient.net.SduiFocusRules.focusable(SduiScreen(doc(shelfPage.replace(""","focusable":true""", ""))).root.children.single().children[2]))
    }

    private val formPage = """{"version":1,"catalog":8,"page":{"id":"p"},"root":{"type":"Page","id":"page","children":[
        {"type":"Form","id":"online","props":{"title":"Friends","submitLabel":"Save","cancelLabel":"Cancel"},"action":{"type":"command","op":"wittyplay.online.set"},"children":[
          {"type":"List","id":"rows","children":[
            {"type":"ListItem","id":"rows:share","props":{"title":"Show","control":{"type":"switch","name":"sharePlaying","value":true}}},
            {"type":"ListItem","id":"rows:appear","props":{"title":"Appear","control":{"type":"switch","name":"appearOnline","value":false,"disabled":true,"why":"A guest has none."}}},
            {"type":"ListItem","id":"rows:vol","props":{"title":"Volume","control":{"type":"slider","name":"volume","value":40,"min":0,"max":100,"step":5,"unit":"%"}}},
            {"type":"ListItem","id":"rows:mode","props":{"title":"Mode","control":{"type":"select","name":"mode","value":"a","options":[{"value":"a","label":"Alpha"},{"value":"b","label":"Beta"}]}}}]}]}]}}"""

    @Test
    fun formsCollectTheirControlsValues() {
        val screen = SduiScreen(doc(formPage))
        val form = screen.root.children.single()
        assertEquals("a Form is a column to the kit", "Stack", form.type)
        val values = SduiFormValues.of(form)
        assertFalse(values.changed)
        val row = form.children.single().children[0]
        val control = SduiControlSpec.of(row.props)!!
        assertEquals("switch", control.type)
        assertTrue(control.bool)
        val disabled = SduiControlSpec.of(form.children.single().children[1].props)!!
        assertTrue(disabled.disabled)
        assertEquals("A guest has none.", disabled.why)
        values.set("sharePlaying", JsonPrimitive(false))
        values.set("volume", JsonPrimitive(55))
        assertTrue(values.changed)
        val sent = values.submit(form.node.action!!)
        assertEquals("""{"sharePlaying":false,"volume":55,"mode":"a"}""", sent.params.toString())
        assertEquals("wittyplay.online.set", sent.op)
        values.set("sharePlaying", JsonPrimitive(true))
        values.set("volume", JsonPrimitive(40))
        assertFalse("back to what it was is no change", values.changed)
        values.set("mode", JsonPrimitive("b"))
        values.saved()
        assertFalse(values.changed)
        assertEquals(JsonPrimitive("b"), values["mode"])
        // A slider, select or field outside a Form runs its action with the value.
        assertEquals("""{"value":"b"}""", action("""{"type":"command","op":"x"}""").withValue(JsonPrimitive("b")).params.toString())
    }

    @Test
    fun regionsStayWhileTheScopeShows() {
        val online = doc("""{"version":1,"catalog":8,"page":{"id":"o"},"theme":{"scope":"wittyplay"},"layout":{"formFactor":"tv","shell":{"placements":{"systemDock":{"position":"side"}}}},"root":{"type":"Page","id":"page"},
            "regions":{"statusBar":[{"id":"who","kind":"profile","text":"Playing as Sam"},{"id":"server","kind":"server"}],"systemDock":[{"id":"home","label":"Home","icon":"home","route":"/page/online"},{"id":"c","label":"Controllers","icon":"game","route":"/page/wittyplay-controllers","as":"layer"}]}}""")
        val first = SduiRegionRules.after(online, null)!!
        assertEquals(2, first.regions.statusBar.size)
        assertEquals("layer", first.regions.systemDock[1].layer)
        assertTrue(first.dockOnSide)
        val sameScope = doc("""{"version":1,"catalog":8,"page":{"id":"t"},"theme":{"scope":"wittyplay"},"root":{"type":"Page","id":"page"}}""")
        assertEquals(first, SduiRegionRules.after(sameScope, first))
        val elsewhere = doc("""{"version":1,"catalog":8,"page":{"id":"h"},"root":{"type":"Page","id":"page"}}""")
        assertNull(SduiRegionRules.after(elsewhere, first))
    }

    private val smartPage = """{"version":1,"catalog":8,"page":{"id":"p"},"root":{"type":"Page","id":"page","children":[
        {"type":"Form","id":"rule","props":{"title":"Smart list","submitLabel":"Save"},"action":{"type":"command","op":"smartlist.create","params":{"name":"Mine"}},"children":[
          {"type":"List","id":"rows","children":[
            {"type":"ListItem","id":"rows:from","props":{"title":"From","control":{"type":"field","name":"rule.yearFrom","value":"1990","input":"number"}}},
            {"type":"ListItem","id":"rows:to","props":{"title":"To","control":{"type":"field","name":"rule.yearTo","value":"","input":"number"}}},
            {"type":"ListItem","id":"rows:genres","props":{"title":"Genres","control":{"type":"field","name":"rule.genres[]","value":"Sci-Fi, Drama"}}},
            {"type":"ListItem","id":"rows:kind","props":{"title":"Kind","control":{"type":"select","name":"rule.kind","value":"movie","options":[{"value":"movie","label":"Films"}]}}}]}]}]}}"""

    @Test
    fun objectParametersAreBuiltFromControlsNamedParamDotKey() {
        val form = SduiScreen(doc(smartPage)).root.children.single()
        val values = SduiFormValues.of(form)
        val sent = values.submit(form.node.action!!)
        assertEquals("""{"name":"Mine","rule":{"yearFrom":1990,"genres":["Sci-Fi","Drama"],"kind":"movie"}}""", sent.params.toString())
        values.set("rule.yearTo", JsonPrimitive("2005"))
        assertEquals("a number field gives a number", """{"name":"Mine","rule":{"yearFrom":1990,"yearTo":2005,"genres":["Sci-Fi","Drama"],"kind":"movie"}}""", values.submit(form.node.action!!).params.toString())
        val spec = SduiCommandSpec("smartlist.create", "POST", "/api/smart", """{"name":"{name}","rule":"{rule}"}""", listOf(SduiCommandParam("name", "string", true), SduiCommandParam("rule", "object", true)))
        val before = SduiCommands.serverRevision
        SduiCommands.serverRevision = 16
        try {
            assertEquals("""{"name":"Mine","rule":{"yearFrom":1990,"genres":["Sci-Fi","Drama"],"kind":"movie"}}""", SduiCommands.request(spec, "", sent.params)!!.body)
        } finally { SduiCommands.serverRevision = before }
    }

    @Test
    fun aNativeButtonCarriesItsItemAsParams() {
        val effect = SduiRouter().effect(action("""{"type":"native","to":"player","params":{"item":"42"}}""")) as SduiEffect.Open
        assertEquals(SduiTarget.Native("player", mapOf("item" to "42"), ""), effect.target)
    }

    @Test
    fun theNewServerPagesOpenThroughTheRenderer() {
        val router = SduiRouter()
        for ((route, page) in listOf("/creators" to "creators", "/creator/5" to "creator", "/comments/5" to "comments", "/markers/5" to "markers", "/canvas/5" to "canvas", "/smart-list" to "smart-list", "/versions/9" to "versions", "/devices" to "devices", "/year" to "year", "/studio/A%20B" to "studio")) {
            val target = router.resolve(route) as SduiTarget.Page
            assertEquals(route, page, target.page)
        }
        assertEquals("A B", (router.resolve("/studio/A%20B") as SduiTarget.Page).params["name"])
        assertEquals("5", (router.resolve("/markers/5") as SduiTarget.Page).params["item"])
        // A module's page from a settings slot: /page/<id>?item=<profile>.
        val slot = router.resolve("/page/wittyplay-kids?item=7") as SduiTarget.Page
        assertEquals("wittyplay-kids", slot.page)
        assertEquals("7", slot.params["item"])
    }

    @Test
    fun aQrIsAStackToTheKit() {
        val screen = SduiScreen(doc("""{"version":1,"catalog":8,"page":{"id":"p"},"root":{"type":"Page","id":"page","children":[{"type":"QR","id":"join","props":{"value":"/games?join=X","label":"Scan","size":"l","isRoute":true}}]}}"""))
        assertEquals("Stack", screen.root.children.single().type)
    }
}
