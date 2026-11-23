// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SduiAction
import com.wittywilla.wittymediaclient.net.SduiAnswer
import com.wittywilla.wittymediaclient.net.SduiClient
import com.wittywilla.wittymediaclient.net.SduiCommands
import com.wittywilla.wittymediaclient.net.SduiCustomise
import com.wittywilla.wittymediaclient.net.SduiDevice
import com.wittywilla.wittymediaclient.net.SduiDocument
import com.wittywilla.wittymediaclient.net.SduiEffect
import com.wittywilla.wittymediaclient.net.SduiMarkdown
import com.wittywilla.wittymediaclient.net.SduiMemoryStore
import com.wittywilla.wittymediaclient.net.SduiNode
import com.wittywilla.wittymediaclient.net.SduiPage
import com.wittywilla.wittymediaclient.net.SduiPatch
import com.wittywilla.wittymediaclient.net.SduiPatches
import com.wittywilla.wittymediaclient.net.SduiPersonalInfo
import com.wittywilla.wittymediaclient.net.SduiPersonalSection
import com.wittywilla.wittymediaclient.net.SduiRouter
import com.wittywilla.wittymediaclient.net.SduiScreen
import com.wittywilla.wittymediaclient.net.SduiSectionItems
import com.wittywilla.wittymediaclient.net.SduiTarget
import com.wittywilla.wittymediaclient.net.SduiFileStore
import com.wittywilla.wittymediaclient.net.SduiTokens
import com.wittywilla.wittymediaclient.net.SduiTopShelf
import com.wittywilla.wittymediaclient.net.TvHomePlan
import com.wittywilla.wittymediaclient.net.SduiTransport
import com.wittywilla.wittymediaclient.net.SduiUnsupported
import com.wittywilla.wittymediaclient.net.ThemeColour
import com.wittywilla.wittymediaclient.net.ThemeTokens
import com.wittywilla.wittymediaclient.net.ThemeTranslator
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.str
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException

// The rules of server-driven pages that need no screen: reading a document, asking for one and keeping it, patches,
// paging, routes and actions, focus, theme tokens and Customise. The documents here are made up.
class SduiRulesTest {
    private fun doc(text: String): SduiDocument = json.decodeFromString(SduiDocument.serializer(), text)

    private val home = """
        {"version":1,"catalog":2,"page":{"id":"home","kind":"home","title":"Home","route":"/"},
         "layout":{"formFactor":"tv","class":"hd","canvas":{"width":1920,"height":1080},"scale":1,"breakpoint":"large",
           "safeArea":{"top":60,"right":80,"bottom":60,"left":80},"focusEngine":true,"density":"comfortable",
           "spacing":{"none":0,"xs":10,"s":20,"m":40,"l":60,"xl":100},"text":{"pageTitle":76,"heading":57,"title":48,"body":29,"caption":25},
           "budget":{"shelfItems":12}},
         "root":{"type":"Page","id":"page","props":{"title":"Home"},"children":[
           {"type":"Hero","id":"hero","focus":{"order":1,"default":true},"children":[
             {"type":"Card","id":"hero:1","props":{"style":"hero","title":"One","actions":[{"id":"play","label":"Play","primary":true,"action":{"type":"play","item":"1"}}]}}]},
           {"type":"Shelf","id":"jump","props":{"title":"Jump back in","cardStyle":"progress","card":{"width":420,"height":236},"more":{"url":"/api/v1/sdui/pages/home/sections/jump/items?cursor=2"}},"children":[
             {"type":"Card","id":"jump:3","focus":{"order":2,"group":"jump"},"action":{"type":"navigate","to":"/item/3"},"props":{"style":"progress","title":"Three","progress":0.415}},
             {"type":"Card","id":"jump:4","focus":{"order":3,"group":"jump"},"action":{"type":"navigate","to":"/show/4"},"props":{"style":"progress","title":"Four"}}]},
           {"type":"Shelf","id":"recent","state":"deferred","props":{"title":"Recently added","cardStyle":"poster","card":{"width":250,"height":375},"more":{"url":"/api/v1/sdui/pages/home/sections/recent/items?cursor=0"}}},
           {"type":"Hologram","id":"future","props":{"shiny":true},"futureField":[1,2],"children":[
             {"type":"Button","id":"b","focus":{"order":4},"action":{"type":"teleport","to":"mars"},"props":{"label":"Go"}}]}
         ]},
         "personal":{"editable":true,"allow":["reorder","hide","pin","density"],"sections":[{"id":"hero","title":"Featured"}],"url":"/api/v1/sdui/pages/home/personal"},
         "meta":{"etag":"W/\"a\"","ttlSeconds":60},"somethingNew":{"x":1}}
    """.trimIndent()

    // A library page with one grid, in the state given: the server's empty library (Podcasts with nothing in it, #77).
    private fun library(grid: String) = SduiScreen(doc("""
        {"version":1,"catalog":2,"page":{"id":"library","kind":"library","title":"Podcasts","route":"/library/5"},
         "root":{"type":"Page","id":"page","props":{"title":"Podcasts"},"children":[$grid]}}
    """.trimIndent()))

    @Test
    fun aTvPageWithOnlyEmptySectionsIsAnEmptyPage() {
        fun rows(grid: String) = com.wittywilla.wittymediaclient.ui.SduiRows.flatten(library(grid), true) { 4 }
        val empty = """{"type":"Grid","id":"all","state":"empty","props":{"title":"All","emptyText":"Nothing here yet."}}"""
        assertTrue(com.wittywilla.wittymediaclient.ui.SduiRows.nothingToShow(rows(empty)))
        val loading = """{"type":"Grid","id":"all","state":"deferred","props":{"title":"All"}}"""
        assertFalse("still on its way", com.wittywilla.wittymediaclient.ui.SduiRows.nothingToShow(rows(loading)))
        val full = """{"type":"Grid","id":"all","props":{"title":"All"},"children":[{"type":"Card","id":"c1","props":{"title":"One"}}]}"""
        assertFalse("a card to land on", com.wittywilla.wittymediaclient.ui.SduiRows.nothingToShow(rows(full)))
        val withHero = """{"type":"Hero","id":"hero","children":[{"type":"Card","id":"h","props":{"title":"H"}}]},$empty"""
        assertFalse("a page with something else on it", com.wittywilla.wittymediaclient.ui.SduiRows.nothingToShow(rows(withHero)))
        assertFalse("nothing at all isn't an empty library", com.wittywilla.wittymediaclient.ui.SduiRows.nothingToShow(emptyList()))
    }

    @Test
    fun aDocumentReadsWithFieldsAndComponentsItHasNeverHeardOf() {
        val d = doc(home)
        assertEquals("Home", d.page.title)
        assertEquals(1080, d.layout!!.canvas.height)
        val screen = SduiScreen(d)
        // An unknown component is a plain column of its children, and they are still there.
        val future = screen.visible.first { it.id == "future" }
        assertEquals("Stack", future.type)
        assertEquals("b", future.children.single().id)
        // An unknown action does nothing.
        assertEquals(SduiEffect.Nothing, SduiRouter().effect(future.children.single().node.action))
        // An unknown state is ready, and null where a list or an object belongs is nothing.
        val odd = doc("""{"version":1,"root":{"type":"Page","id":"page","children":[{"type":"Shelf","id":"s","state":"sparkling","props":null,"children":null,"tokens":null}]}}""")
        val shelf = SduiScreen(odd).visible[1]
        assertFalse(shelf.deferred || shelf.failed || shelf.empty)
        assertEquals(0, shelf.cards)
    }

    @Test
    fun whatIsLaidOutFollowsTheDeviceProfile() {
        val screen = SduiScreen(doc(home))
        assertEquals(1760, screen.layout.contentWidth)
        assertEquals(60, screen.layout.sectionGap)
        val recent = screen.visible.first { it.id == "recent" }
        // As many placeholders as are at least partly on screen: (1760 + 40) / (250 + 40) + 1.
        assertEquals(7, recent.placeholders)
        assertFalse("a deferred row doesn't page until it has its first cards", recent.hasMore)
        val card = screen.visible.first { it.id == "jump:3" }
        assertEquals("Three, 42 percent watched", card.label)
        assertEquals(42, card.progress)
        assertEquals("navigate /item/3", card.action)
        // A window that changed without crossing a breakpoint: as many cards as fit, never fewer than two, three for small ones.
        val phone = screen.layout.copy(breakpoint = "compact", spacing = mapOf("xs" to 4, "s" to 8, "m" to 16))
        assertEquals(3, phone.columnsFor(379, 120))
        assertEquals(2, phone.columnsFor(300, 224))
        assertEquals(5, phone.columnsFor(648, 120))
    }

    @Test
    fun focusFollowsThePagesOrderAndEachGroupRemembers() {
        val plan = SduiScreen(doc(home)).focus
        assertEquals(listOf("hero", "jump:3", "jump:4", "b"), plan.order)
        assertEquals("hero", plan.default)
        assertEquals(mapOf("jump" to listOf("jump:3", "jump:4")), plan.groups)
        // Three stops down the page: the hero, the row, the button.
        assertEquals(listOf("hero", "jump", "b"), plan.stops.map { it.id })
        val row = plan.stopAfter("hero")!!
        assertEquals("jump", row.id)
        assertEquals("the first card, the first time", "jump:3", plan.entry(row, null))
        assertEquals("the card it was left on, after", "jump:4", plan.entry(row, "jump:4"))
        assertEquals("a card that has gone is forgotten", "jump:3", plan.entry(row, "jump:9"))
        assertEquals("b", plan.stopAfter("jump:4")!!.id)
        assertEquals("hero", plan.stopBefore("jump:3")!!.id)
        assertNull(plan.stopBefore("hero"))
        assertNull(plan.stopAfter("b"))
        assertEquals("jump", plan.groupOf("jump:4"))
    }

    private fun items(text: String) = json.decodeFromString(SduiSectionItems.serializer(), text)

    @Test
    fun rowsPageAndDeferredSectionsFill() {
        var page = SduiPage(doc(home))
        assertEquals("/api/v1/sdui/pages/home/sections/jump/items?cursor=2", page.moreUrl("jump"))
        // The next page is appended; a card already there isn't shown twice.
        page = page.withItems("jump", items("""{"version":1,"section":"jump","items":[{"type":"Card","id":"jump:4"},{"type":"Card","id":"jump:5"}],"next":"/n?cursor=4"}"""))
        assertEquals(listOf("jump:3", "jump:4", "jump:5"), page.find("jump")!!.children.map { it.id })
        assertEquals("/n?cursor=4", page.moreUrl("jump"))
        // No next is the end.
        page = page.withItems("jump", items("""{"version":1,"section":"jump","items":[{"type":"Card","id":"jump:6"}]}"""))
        assertEquals("", page.moreUrl("jump"))
        assertFalse(SduiScreen(page.shown).visible.first { it.id == "jump" }.hasMore)
        // A deferred section's first answer takes the placeholders' place, with its props merged in.
        page = page.withItems("recent", items("""{"version":1,"section":"recent","props":{"title":"New here","total":2},"items":[{"type":"Card","id":"recent:1"}],"next":"/r?cursor=1"}"""))
        val recent = page.find("recent")!!
        assertEquals("", recent.state)
        assertEquals("New here", recent.props.str("title"))
        assertEquals("poster", recent.props.str("cardStyle"))
        assertEquals(listOf("recent:1"), recent.children.map { it.id })
        // Another season replaces what was there.
        page = page.withItems("recent", items("""{"version":1,"section":"recent","replace":true,"items":[{"type":"Card","id":"recent:9"}]}"""))
        assertEquals(listOf("recent:9"), page.find("recent")!!.children.map { it.id })
    }

    @Test
    fun aDeferredSectionThatIsEmptyGoesAndOneThatFailsSaysSo() {
        val page = SduiPage(doc(home))
        assertNull(page.withItems("recent", items("""{"version":1,"section":"recent","state":"empty"}""")).find("recent"))
        val failed = page.withFailure("recent")
        assertEquals("error", failed.find("recent")!!.state)
        assertEquals("Retry asks the same address again", "/api/v1/sdui/pages/home/sections/recent/items?cursor=0", failed.moreUrl("recent"))
        // A row that already has cards keeps them when its next page fails.
        assertEquals("", page.withFailure("jump").find("jump")!!.state)
        assertEquals(2, page.withFailure("jump").find("jump")!!.children.size)
    }

    private fun patch(text: String) = json.decodeFromString(SduiPatch.serializer(), text)

    @Test
    fun patchesApplyInOrderByID() {
        val before = doc(home)
        val after = SduiPatches.apply(
            before,
            listOf(
                patch("""{"op":"add","path":"#jump/children/0","node":{"type":"Card","id":"jump:1","props":{"title":"New"},"children":[]}}"""),
                patch("""{"op":"move","path":"#jump/children/0","from":"#jump:4"}"""),
                patch("""{"op":"remove","path":"#hero"}"""),
                patch("""{"op":"replace","path":"#jump","node":{"type":"Shelf","id":"jump","props":{"title":"Keep watching"}}}"""),
                patch("""{"op":"replace","path":"/personal","value":null}"""),
                patch("""{"op":"replace","path":"/page","value":{"id":"home","kind":"home","title":"Welcome"}}"""),
                patch("""{"op":"replace","path":"/meta","value":{"ttlSeconds":5}}"""),
            ),
        )!!
        val jump = SduiPage.find(after.root, "jump")!!
        assertEquals("a replaced node keeps its children", listOf("jump:4", "jump:1", "jump:3"), jump.children.map { it.id })
        assertEquals("Keep watching", jump.props.str("title"))
        assertNull(SduiPage.find(after.root, "hero"))
        assertNull(after.personal)
        assertEquals("Welcome", after.page.title)
        assertEquals(5, after.meta.ttlSeconds)
        assertEquals("the ETag is never in a patch", "W/\"a\"", after.meta.etag)
        assertEquals("the document patched is left as it was", 4, before.root.children.size)
        // The whole tree at once.
        val swapped = SduiPatches.apply(before, listOf(patch("""{"op":"replace","path":"/root","node":{"type":"Page","id":"page"}}""")))!!
        assertTrue(swapped.root.children.isEmpty())
    }

    @Test
    fun aPatchThatDoesNotFitIsRefusedWhole() {
        val before = doc(home)
        assertNull(SduiPatches.apply(before, listOf(patch("""{"op":"remove","path":"#nobody"}"""))))
        assertNull(SduiPatches.apply(before, listOf(patch("""{"op":"add","path":"#jump/children/9","node":{"type":"Card","id":"x"}}"""))))
        assertNull(SduiPatches.apply(before, listOf(patch("""{"op":"add","path":"#jump/children/zero","node":{"type":"Card","id":"x"}}"""))))
        assertNull(SduiPatches.apply(before, listOf(patch("""{"op":"transmogrify","path":"#jump"}"""))))
        assertNull(SduiPatches.apply(before, listOf(patch("""{"op":"replace","path":"/somewhere","value":1}"""))))
    }

    @Test
    fun aNewerRenderKeepsWhatWasFetchedForSectionsItLeftAlone() {
        val before = doc(home)
        var page = SduiPage(before)
            .withItems("jump", items("""{"version":1,"section":"jump","items":[{"type":"Card","id":"jump:5"}]}"""))
            .withItems("recent", items("""{"version":1,"section":"recent","items":[{"type":"Card","id":"recent:1"}]}"""))
        val fresh = SduiPatches.apply(before, listOf(patch("""{"op":"replace","path":"#jump","node":{"type":"Shelf","id":"jump","props":{"title":"Changed"}}}""")))!!
        page = page.withBase(fresh)
        assertEquals("the changed row starts again", listOf("jump:3", "jump:4"), page.find("jump")!!.children.map { it.id })
        assertEquals("the untouched one keeps its cards", listOf("recent:1"), page.find("recent")!!.children.map { it.id })
    }

    // A stand-in server: answers by address, counts what it was asked, and can be unplugged.
    private class Server : SduiTransport {
        val asked = ArrayList<String>()
        val conditional = ArrayList<String?>()
        var reachable = true
        var answer: (String, String?) -> SduiAnswer = { _, _ -> SduiAnswer(404, """{"error":"no such page"}""") }

        override suspend fun request(method: String, path: String, body: String?, ifNoneMatch: String?): SduiAnswer {
            if (!reachable) throw IOException("unplugged")
            asked += "$method $path" + (body?.let { " $it" } ?: "")
            conditional += ifNoneMatch
            return answer(path, ifNoneMatch)
        }
    }

    private val tv = SduiDevice("androidtv", "tv", deviceClass = "4k", locale = "en-GB", capabilities = listOf("reducedMotion"), views = listOf("guide"))

    @Test
    fun everyRequestSaysWhatTheDeviceIsAndCanDraw() {
        val server = Server()
        server.answer = { _, _ -> SduiAnswer(200, home, "W/\"a\"") }
        val client = SduiClient(server, tv, SduiMemoryStore())
        runBlocking { client.page("library", mapOf("library" to "3", "genre" to "Sci Fi", "tab" to "")) }
        val asked = server.asked.single()
        assertTrue(asked, asked.startsWith("GET /api/v1/sdui/pages/library?genre=Sci+Fi&library=3&catalog=8&platform=androidtv&formFactor=tv&deviceClass=4k&locale=en-GB&capabilities=reducedMotion&views=guide"))
        // A section's own address gets the same parameters, and keeps the ones it came with.
        assertEquals("/x/items?cursor=12&catalog=9&platform=android&formFactor=phone&viewport=411x891", SduiDevice("android", "phone", viewport = "411x891").on("/x/items?cursor=12&catalog=9"))
        assertEquals("compact", SduiDevice.breakpoint(599))
        assertEquals("medium", SduiDevice.breakpoint(600))
        assertEquals("expanded", SduiDevice.breakpoint(840))
        assertEquals("large", SduiDevice.breakpoint(1200))
        assertEquals("phone", SduiDevice.formFactor(false, 411))
        assertEquals("tablet", SduiDevice.formFactor(false, 800))
        assertEquals("tv", SduiDevice.formFactor(true, 540))
        assertEquals("hd", SduiDevice.tvClass(1080, lowMemory = false))
        assertEquals("4k", SduiDevice.tvClass(2160, lowMemory = false))
        assertEquals("a stick short of memory never asks for 4K pictures", "hd", SduiDevice.tvClass(2160, lowMemory = true))
    }

    @Test
    fun aPageIsKeptWithItsETagAndStandsInWhenTheServerIsOutOfReach() {
        val server = Server()
        server.answer = { _, tag -> if (tag == "W/\"a\"") SduiAnswer(304, "") else SduiAnswer(200, home, "W/\"a\"") }
        val store = SduiMemoryStore()
        val client = SduiClient(server, tv, store)
        runBlocking {
            assertNull(client.keptPage("home"))
            val first = client.page("home")
            assertFalse(first.offline)
            assertEquals(listOf<String?>(null), server.conditional)
            // The second ask sends the ETag back and is answered 304: the kept page.
            val second = client.page("home")
            assertEquals("W/\"a\"", server.conditional.last())
            assertEquals(first.value, second.value)
            assertEquals("Home", client.keptPage("home")!!.page.title)
            // Unplugged: the last known good page, marked as such. A page never seen has nothing to stand in.
            server.reachable = false
            val third = client.page("home")
            assertTrue(third.offline)
            assertEquals(first.value, third.value)
            try {
                client.page("detail", mapOf("item" to "3"))
                fail("nothing was kept for that page")
            } catch (_: IOException) {
            }
            // Signing out takes it all along.
            client.forget()
            assertNull(client.keptPage("home"))
        }
    }

    @Test
    fun whatIsKeptIsBoundedAndRefusalsCarryTheServersWords() {
        val store = SduiMemoryStore(most = 3)
        repeat(10) { store.write("k$it", "v") }
        assertEquals(3, store.size)
        assertNull(store.read("k0"))
        assertNotNull(store.read("k9"))
        val server = Server()
        val client = SduiClient(server, tv, SduiMemoryStore())
        runBlocking {
            try {
                client.page("nothere")
                fail("a page that isn't there is an error")
            } catch (e: ApiError) {
                assertEquals(404, e.status)
                assertEquals("no such page", e.message)
            }
            server.answer = { _, _ -> SduiAnswer(200, """{"version":2,"root":{"type":"Page","id":"page"}}""", "W/\"z\"") }
            try {
                client.page("home")
                fail("a document version from the future is refused")
            } catch (_: SduiUnsupported) {
            }
        }
    }

    @Test
    fun aRefreshPatchesTheRenderItHasOrTakesTheWholeDocument() {
        val server = Server()
        val client = SduiClient(server, tv, SduiMemoryStore())
        val have = doc(home)
        runBlocking {
            server.answer = { _, _ -> SduiAnswer(304, "") }
            assertNull("nothing changed", client.refreshed("home", emptyMap(), have))
            assertTrue(server.asked.last(), "/pages/home/diff?" in server.asked.last() && server.asked.last().endsWith("&since=W%2F%22a%22"))
            server.answer = { _, _ -> SduiAnswer(200, """{"etag":"W/\"b\"","since":"W/\"a\"","patches":[{"op":"remove","path":"#hero"}]}""") }
            val patched = client.refreshed("home", emptyMap(), have)!!
            assertNull(SduiPage.find(patched.root, "hero"))
            assertEquals("the answer's ETag is the new one", "W/\"b\"", patched.meta.etag)
            assertEquals("and what is kept is the patched page", "W/\"b\"", client.keptPage("home")!!.meta.etag)
            server.answer = { _, _ -> SduiAnswer(200, """{"etag":"W/\"c\"","document":{"version":1,"page":{"title":"Whole"},"root":{"type":"Page","id":"page"}}}""") }
            assertEquals("Whole", client.refreshed("home", emptyMap(), have)!!.page.title)
            // A patch that doesn't fit: the tree is dropped and the page asked for.
            server.answer = { path, _ ->
                if ("/diff" in path) SduiAnswer(200, """{"etag":"W/\"d\"","patches":[{"op":"remove","path":"#nobody"}]}""")
                else SduiAnswer(200, home.replace("\"title\":\"Home\",\"route\"", "\"title\":\"Asked again\",\"route\""), "W/\"d\"")
            }
            assertEquals("Asked again", client.refreshed("home", emptyMap(), have)!!.page.title)
        }
    }

    @Test
    fun routesComeFromTheCataloguesTable() {
        val router = SduiRouter()
        assertEquals(SduiTarget.Page("home", emptyMap(), "/"), router.resolve("/"))
        assertEquals(SduiTarget.Page("library", mapOf("library" to "3", "genre" to "Comedy", "sort" to "rating"), "/library/3?genre=Comedy&sort=rating"), router.resolve("/library/3?genre=Comedy&sort=rating"))
        assertEquals(mapOf("item" to "103"), (router.resolve("/item/103") as SduiTarget.Page).params)
        assertEquals(mapOf("show" to "5"), (router.resolve("/show/5") as SduiTarget.Page).params)
        val album = router.resolve("/album/4?artist=The+Examples&album=Album+1") as SduiTarget.Page
        assertEquals("detail", album.page)
        assertEquals(mapOf("album" to "Album 1", "artist" to "The Examples", "library" to "4"), album.params)
        assertEquals(mapOf("collection" to "12"), (router.resolve("/collections/12") as SduiTarget.Page).params)
        assertEquals("collections", (router.resolve("/collections") as SduiTarget.Page).page)
        assertEquals(mapOf("q" to "exam"), (router.resolve("/search?q=exam") as SduiTarget.Page).params)
        assertEquals("a page of one's own is asked for by its ID", "family-night", (router.resolve("/page/family-night") as SduiTarget.Page).page)
        assertEquals(SduiTarget.Native("settings", emptyMap(), "/settings"), router.resolve("/settings"))
        assertEquals(mapOf("section" to "libraries"), (router.resolve("/settings/libraries") as SduiTarget.Native).params)
        assertEquals(SduiTarget.Native("livePlayer", mapOf("key" to "lib-1"), "/tv/watch/lib-1"), router.resolve("/tv/watch/lib-1"))
        assertEquals("player", (router.resolve("/watch/9") as SduiTarget.Native).screen)
        assertEquals("guide", (router.resolve("/tv/guide") as SduiTarget.Native).screen)
        assertEquals("a place the table doesn't have", SduiTarget.Unknown("/nowhere/3?name=The+Examples"), router.resolve("/nowhere/3?name=The+Examples"))
        // A server's own table wins over the one the app was built with.
        val own = SduiRouter(json.decodeFromString("""[{"pattern":"/item/{item}","native":"player"},{"pattern":"/stage/{id}","page":"stage","params":{"act":"{id}","seat":"?seat"}}]"""))
        assertEquals("player", (own.resolve("/item/3") as SduiTarget.Native).screen)
        assertEquals(SduiTarget.Page("stage", mapOf("act" to "2", "seat" to "A1"), "/stage/2?seat=A1"), own.resolve("/stage/2?seat=A1"))
    }

    private fun action(text: String) = json.decodeFromString(SduiAction.serializer(), text)

    @Test
    fun actionsBecomeWhatTheAppDoes() {
        val router = SduiRouter()
        assertEquals(SduiEffect.Play("101", resume = true), router.effect(action("""{"type":"play","item":"101","params":{"resume":true}}""")))
        assertEquals(SduiEffect.Play("101", resume = false), router.effect(action("""{"type":"play","item":"101","params":{"resume":false}}""")))
        assertEquals(SduiEffect.Play("101", resume = true), router.effect(action("""{"type":"play","item":"101"}""")))
        // An album page's Shuffle and Add to queue (server 0.8.1-alpha): every song of its album, in a new order or after
        // what is playing.
        assertEquals(SduiEffect.Play("101", resume = false, shuffle = true), router.effect(action("""{"type":"play","item":"101","params":{"resume":false,"shuffle":true}}""")))
        assertEquals(SduiEffect.Queue("101"), router.effect(action("""{"type":"command","op":"queue.add","item":"101"}""")))
        assertEquals(SduiEffect.Nothing, router.effect(action("""{"type":"command","op":"queue.add"}""")))
        assertEquals(SduiEffect.Open(SduiTarget.Native("share", mapOf("item" to "101"), "")), router.effect(action("""{"type":"native","to":"share","params":{"item":"101"}}""")))
        assertEquals(SduiEffect.Open(SduiTarget.Page("detail", mapOf("item" to "7"), "/item/7")), router.effect(action("""{"type":"navigate","to":"/item/7"}""")))
        assertEquals(SduiEffect.External("https://example.org/a"), router.effect(action("""{"type":"external","url":"https://example.org/a"}""")))
        assertEquals("only a web page opens in the browser", SduiEffect.Nothing, router.effect(action("""{"type":"external","url":"intent://evil"}""")))
        assertEquals(SduiEffect.Back, router.effect(action("""{"type":"back"}""")))
        assertEquals(SduiEffect.SelectTab("artists"), router.effect(action("""{"type":"command","op":"selectTab","params":{"tab":"artists"}}""")))
        assertEquals(SduiEffect.Refresh, router.effect(action("""{"type":"command","op":"refresh"}""")))
        assertEquals(SduiEffect.Nothing, router.effect(action("""{"type":"command","op":"selfDestruct","item":"1"}""")))
        assertEquals(SduiEffect.Nothing, router.effect(null))
        val later = router.effect(action("""{"type":"command","op":"watchLater.add","item":"101"}""")) as SduiEffect.Command
        val request = SduiCommands.request(later.spec, later.item)!!
        assertEquals("POST", request.method)
        assertEquals("/api/v1/collections/watch-later/items", request.path)
        assertEquals("""{"items":["101"]}""", request.body)
        // A show's ID is "show-<n>", which the server's routes take as it is.
        val show = router.effect(action("""{"type":"command","op":"watchLater.add","item":"show-5"}""")) as SduiEffect.Command
        assertEquals("""{"items":["show-5"]}""", SduiCommands.request(show.spec, show.item)!!.body)
        val showWatched = router.effect(action("""{"type":"command","op":"watched.set","item":"show-5"}""")) as SduiEffect.Command
        assertEquals("/api/v1/items/show-5/progress", SduiCommands.request(showWatched.spec, showWatched.item)!!.path)
        val watched = router.effect(action("""{"type":"command","op":"watched.set","item":"9"}""")) as SduiEffect.Command
        assertEquals("/api/v1/items/9/progress", SduiCommands.request(watched.spec, watched.item)!!.path)
        val cleared = router.effect(action("""{"type":"command","op":"watched.clear","item":"9"}""")) as SduiEffect.Command
        assertEquals("DELETE", SduiCommands.request(cleared.spec, cleared.item)!!.method)
        assertNull(SduiCommands.request(cleared.spec, cleared.item)!!.body)
    }

    @Test
    fun tokensGoOnTopOfTheThemeInnermostLast() {
        val theme = ThemeTranslator.translate(ThemeTokens(id = "t", colors = mapOf("bg" to "#101010", "fg" to "#f0f0f0", "accent" to "#7955ff")))
        assertEquals(theme, SduiTokens.over(theme, emptyMap()))
        val page = mapOf("accent" to "#B24A00")
        val node = mapOf("accent" to "#2A6FDB", "accentFg" to "#FFFFFF", "bg2" to "#202020", "unheardOf" to "#123456", "fg" to "not a colour")
        val scoped = SduiTokens.resolve(theme, page, null, node)
        assertEquals(ThemeColour.parse("#2A6FDB"), scoped.accent)
        assertEquals(ThemeColour.WHITE, scoped.onAccent)
        assertEquals(ThemeColour.parse("#202020"), scoped.panel)
        assertEquals("what isn't a colour changes nothing", theme.text, scoped.text)
        assertEquals(theme.background, scoped.background)
        // The page's own accent alone: its companions follow it, and words in it still read on the page.
        val evening = SduiTokens.resolve(theme, page)
        assertEquals(ThemeColour.parse("#B24A00"), evening.accent)
        assertTrue(evening.accentText.contrast(evening.background) >= 4.5)
        assertTrue(evening.onAccent.contrast(evening.accent) >= ThemeColour.INK.contrast(evening.accent) || evening.onAccent == ThemeColour.INK)
    }

    private fun info(vararg sections: SduiPersonalSection, allow: List<String> = listOf("reorder", "hide", "pin", "density", "cardSize", "defaultTab"), editable: Boolean = true) =
        SduiPersonalInfo(editable, allow, sections.toList(), url = "/api/v1/sdui/pages/home/personal")

    @Test
    fun customiseReordersHidesAndPinsWhatIsNotLocked() {
        var c = SduiCustomise.from(
            info(
                SduiPersonalSection("setup", "Notice", locked = true), SduiPersonalSection("hero", "Featured"), SduiPersonalSection("jump", "Jump back in"),
                SduiPersonalSection("onnow", "On TV now", empty = true), SduiPersonalSection("recent-1", "Recently added in Films"),
            ),
        )
        c = c.nudging("recent-1", -2)
        assertEquals("a locked section never moves", listOf("setup", "hero", "recent-1", "jump", "onnow"), c.sections.map { it.id })
        c = c.nudging("hero", -5)
        assertEquals(listOf("setup", "hero", "recent-1", "jump", "onnow"), c.sections.map { it.id })
        c = c.moving("hero", 5)
        assertEquals(listOf("setup", "recent-1", "jump", "onnow", "hero"), c.sections.map { it.id })
        c = c.moving("setup", 3).togglingHidden("setup").togglingPinned("setup")
        assertEquals("nor is it hidden or pinned", listOf("setup", "recent-1", "jump", "onnow", "hero"), c.sections.map { it.id })
        assertFalse(c.sections.first().hidden || c.sections.first().pinned)
        c = c.togglingHidden("hero").togglingPinned("jump").togglingPinned("onnow")
        assertEquals("pinned sections come first, in the order they were pinned", listOf("setup", "jump", "onnow", "recent-1", "hero"), c.sections.map { it.id })
        c = c.withDensity("compact").withDensity("cramped").withCardSize("recent-1", "l").withCardSize("jump", "xxl").withDefaultTab("views", "artists")
        val sent = c.toPersonal()
        assertEquals(listOf("setup", "recent-1", "hero"), sent.order)
        assertEquals(listOf("hero"), sent.hidden)
        assertEquals(listOf("jump", "onnow"), sent.pinned)
        assertEquals("compact", sent.density)
        assertEquals(mapOf("recent-1" to "l"), sent.cardSize)
        assertEquals(mapOf("views" to "artists"), sent.defaultTab)
        assertEquals("""{"order":["setup","recent-1","hero"],"hidden":["hero"],"pinned":["jump","onnow"],"density":"compact","cardSize":{"recent-1":"l"},"defaultTab":{"views":"artists"}}""", json.encodeToString(com.wittywilla.wittymediaclient.net.SduiPersonal.serializer(), sent))
        // Unpinned again, it leads the rest; and shown again.
        c = c.togglingPinned("jump").togglingHidden("hero")
        assertEquals(listOf("setup", "onnow", "jump", "recent-1", "hero"), c.sections.map { it.id })
        assertTrue(c.toPersonal().hidden.isEmpty())
    }

    @Test
    fun customiseOnlyChangesWhatThePageAllows() {
        val sections = arrayOf(SduiPersonalSection("a", "A"), SduiPersonalSection("b", "B"))
        val onlyHide = SduiCustomise.from(info(*sections, allow = listOf("hide")))
        assertEquals(listOf("a", "b"), onlyHide.nudging("b", -1).sections.map { it.id })
        val sent = onlyHide.togglingHidden("a").togglingPinned("b").withDensity("compact").withCardSize("a", "l").withDefaultTab("t", "x").toPersonal()
        assertEquals(listOf("a"), sent.hidden)
        assertTrue(sent.order.isEmpty() && sent.pinned.isEmpty() && sent.density.isEmpty() && sent.cardSize.isEmpty() && sent.defaultTab.isEmpty())
        // A profile whose editLayout switch is off may change nothing, whatever the page lists.
        val locked = SduiCustomise.from(info(*sections, editable = false))
        assertFalse(locked.canReorder || locked.canHide || locked.canPin || locked.canDensity || locked.canCardSize || locked.canDefaultTab)
        assertEquals(locked, locked.togglingHidden("a").nudging("a", 1))
        // What the profile chose before for things the page doesn't list is kept.
        val before = SduiCustomise.from(info(*sections), com.wittywilla.wittymediaclient.net.SduiPersonal(cardSize = mapOf("a" to "s"), defaultTab = mapOf("views" to "albums"), density = "spacious"))
        assertEquals(mapOf("a" to "s"), before.toPersonal().cardSize)
        assertEquals("spacious", before.density)
        // The page's tab strips and sized rows, for the choices offered.
        val root = json.decodeFromString(SduiNode.serializer(), """{"type":"Page","id":"page","children":[{"type":"Shelf","id":"s","props":{"cardSize":"m"}},{"type":"Tabs","id":"views","children":[{"type":"Tab","id":"albums","props":{"label":"Albums"}},{"type":"Tab","id":"artists","props":{"label":"Artists"}}]}]}""")
        val tabs = SduiCustomise.tabChoices(root, mapOf("views" to "artists")).single()
        assertEquals(listOf("albums" to "Albums", "artists" to "Artists"), tabs.options)
        assertEquals("artists", tabs.selected)
        assertEquals(listOf("s" to "m"), SduiCustomise.sizeChoices(root).map { it.first.id to it.second })
    }

    @Test
    fun markdownIsTheSmallSubsetAndNothingElse() {
        val blocks = SduiMarkdown.blocks("## Friday, 7 o'clock\nPick **one** each. The [full list](/collections/12) is *longer*.\n\n- popcorn\n1. `sofa`\n<b>not html</b> [bad](javascript:alert(1))")
        assertEquals(5, blocks.size)
        assertEquals(2, (blocks[0] as SduiMarkdown.Heading).level)
        val line = blocks[1].spans
        assertEquals(listOf("Pick ", "one", " each. The ", "full list", " is ", "longer", "."), line.map { it.text })
        assertTrue(line[1].bold)
        assertEquals("/collections/12", line[3].link)
        assertTrue(line[5].italic)
        assertEquals(0, (blocks[2] as SduiMarkdown.Item).number)
        val numbered = blocks[3] as SduiMarkdown.Item
        assertEquals(1, numbered.number)
        assertTrue(numbered.spans.first().code)
        val last = blocks[4] as SduiMarkdown.Paragraph
        assertTrue("raw HTML is the characters it is", last.spans.any { "<b>not html</b>" in it.text })
        assertEquals("a link that is neither a route nor a web page is only its words", "", last.spans.first { it.text == "bad" }.link)
        assertEquals("Friday, 7 o'clock Pick one each. The full list is longer.", SduiMarkdown.plain("## Friday, 7 o'clock\nPick **one** each. The [full list](/collections/12) is *longer*."))
        assertFalse(SduiMarkdown.safeLink("//evil.example"))
    }

    @Test
    fun aTvsHomeScreenIsMadeFromTheServersShelf() {
        val shelf = json.decodeFromString(SduiTopShelf.serializer(), """
            {"version":1,"style":"sectioned","expiresInSec":600,"sections":[
              {"title":"Continue watching","items":[
                {"id":"12","title":"Film 3","shape":"wide","progress":0.4,"image":{"url":"/api/items/12/backdrop?w=908","width":908,"height":512,"aspect":"16/9"},"displayRoute":"/item/12","playRoute":"/watch/12"},
                {"id":"13","title":"Finished","shape":"wide","progress":1,"displayRoute":"/item/13","playRoute":"/watch/13"},
                {"id":"14","title":"Can't be played now","shape":"wide","progress":0.5,"displayRoute":"/item/14"}]},
              {"title":"New in Films","items":[
                {"id":"12","title":"Film 3 again","shape":"poster","displayRoute":"/item/12"},
                {"id":"show-6","title":"A show","shape":"poster","displayRoute":"/show/6"},
                {"id":"x","title":"Somewhere else","shape":"poster","displayRoute":"https://example.org/x"},
                {"id":"y","title":"Settings","shape":"poster","displayRoute":"/settings/users"}]}]}
        """.trimIndent())
        val plan = TvHomePlan.from(shelf)
        assertEquals("each title once, in the server's order, and only ones that open a title", listOf("12", "13", "14", "show-6"), plan.channel.map { it.id })
        assertEquals("Watch Next is what was started and can be carried on", listOf("12"), plan.watchNext.map { it.id })
        assertEquals("a card plays when it can", "/watch/12", plan.channel.first().route)
        assertEquals("/show/6", plan.channel.last().route)
        assertEquals("Continue watching", plan.channel.first().row)
        assertEquals(600, plan.refreshAfterSec)
        assertTrue(TvHomePlan.openable("/album/5?artist=Sun+Tzu&album=The+Art+of+War"))
        assertFalse(TvHomePlan.openable("/settings"))
        assertFalse(TvHomePlan.openable("//evil.example/item/1"))
        assertFalse(TvHomePlan.openable("/item/1/../../settings"))
        assertEquals(900, TvHomePlan.from(SduiTopShelf()).refreshAfterSec)
    }

    @Test
    fun whatIsKeptOnTheDeviceSurvivesARestartAndIsBounded() {
        val folder = java.io.File.createTempFile("sdui", "").let { it.delete(); it }
        try {
            val store = SduiFileStore(folder, most = 3)
            assertNull(store.read("a"))
            store.write("a", "one")
            assertEquals("one", SduiFileStore(folder, most = 3).read("a"))
            repeat(6) { store.write("k$it", "v$it") }
            assertTrue(folder.listFiles()!!.size <= 3)
            assertEquals("v5", store.read("k5"))
            store.clear()
            assertNull(store.read("k5"))
        } finally {
            folder.deleteRecursively()
        }
    }

    @Test
    fun theNormalisedShapeSaysWhatWasLaidOut() {
        val n = SduiScreen(doc(home)).normalised()
        assertEquals(1, (n["kit"] as kotlinx.serialization.json.JsonPrimitive).content.toInt())
        val visible = n["visible"] as kotlinx.serialization.json.JsonArray
        assertEquals(listOf("page", "hero", "hero:1", "jump", "jump:3", "jump:4", "recent", "future", "b"), visible.map { (it as kotlinx.serialization.json.JsonObject).str("id") })
        val slide = visible[2] as kotlinx.serialization.json.JsonObject
        assertEquals("group", slide.str("role"))
        assertEquals("[\"*Play\"]", slide["buttons"].toString())
        assertTrue(n["focus"].toString().contains("\"default\":\"hero\""))
        assertFalse(JsonNull == n["page"])
    }
}
