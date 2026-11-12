// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// A page as this app lays it out: what the composables in ui/Sdui*.kt draw from. Every component of a document
// becomes one SduiView holding what is shown of it and how: its role and label for TalkBack, each part of its text
// with its line limit, its text size, its cards' size and how many placeholders stand in while they load, what
// activating it does. The same views, written out by `normalised`, are what the server's conformance fixtures
// compare (pkg/sdui/conformance), so the description comes from what is drawn, not from a second reading of the page.

// How a card style draws what a card carries: catalogue revision 2's fourteen styles.
class SduiCardStyle(val style: String, val shape: String, val aspect: String, val shows: List<String>, val titleLines: Int, val subtitleLines: Int)

object SduiCardStyles {
    private fun style(name: String, shape: String, aspect: String, titleLines: Int, subtitleLines: Int, vararg shows: String) =
        SduiCardStyle(name, shape, aspect, shows.toList(), titleLines, subtitleLines)

    val ALL: List<SduiCardStyle> = listOf(
        style("poster", "poster", "2/3", 1, 1, "title", "subtitle", "progress", "watched", "unwatched", "badges"),
        style("landscape", "landscape", "16/9", 1, 1, "title", "subtitle", "badges"),
        style("progress", "landscape", "16/9", 1, 1, "title", "subtitle", "progress", "remaining"),
        style("episode", "landscape", "16/9", 1, 1, "title", "subtitle", "synopsis", "progress", "watched"),
        style("square", "square", "1/1", 1, 1, "title", "subtitle"),
        style("album", "square", "1/1", 1, 1, "title", "subtitle"),
        style("circle", "circle", "1/1", 2, 0, "title"),
        style("person", "circle", "1/1", 1, 1, "title", "subtitle"),
        style("book", "poster", "2/3", 2, 1, "title", "subtitle", "progress"),
        style("game", "poster", "3/4", 1, 1, "title", "subtitle", "badges"),
        style("photo", "square", "1/1", 0, 0),
        style("channel", "landscape", "16/9", 1, 2, "number", "title", "now", "next", "progress"),
        style("tile", "landscape", "16/9", 1, 0, "title", "count"),
        style("chip", "chip", "", 1, 0, "title"),
    )

    private val byName = ALL.associateBy { it.style }

    fun named(style: String): SduiCardStyle? = byName[style]

    // A style this app doesn't know is drawn as its shape: the picture, with the title and subtitle under it.
    val UNKNOWN = SduiCardStyle("", "", "", listOf("title", "subtitle"), 1, 1)
}

// The components this app draws. Any other type is drawn as a plain column of its children.
val SDUI_COMPONENTS = setOf(
    "Page", "Hero", "Shelf", "Grid", "Card", "Tabs", "Tab", "FilterBar", "DetailHeader", "SeasonList", "TrackList", "Track",
    "Banner", "Text", "Notice", "Divider", "Spacer", "Stack", "Split", "Button", "Image", "SearchBox", "List", "ListItem", "NativeView", "Dock", "KeyLegend",
)

// One button of a Hero slide or a DetailHeader: {id, label, icon, primary, action}.
class SduiButton(val id: String, val label: String, val icon: String, val primary: Boolean, val action: SduiAction?)

// One drawn component.
class SduiView internal constructor(
    val node: SduiNode,
    // The component it is drawn as: the node's own type, or Stack for one this app doesn't know.
    val type: String,
    val depth: Int,
    // What TalkBack is told. A role of "none" with no label is hidden from it.
    val role: String,
    val label: String,
    // What is shown, by part, and the most lines each part may take before it is cut with an ellipsis.
    val text: Map<String, String>,
    val lines: Map<String, Int>,
    // The size of its main text, in points.
    val textSize: Int,
    // How many cards, rows, tracks, tabs or slides it holds; null for what holds none.
    val cards: Int?,
    val placeholders: Int,
    val cardStyle: String,
    val cardWidth: Int,
    val cardHeight: Int,
    val columns: Int,
    val hasMore: Boolean,
    val seeAll: String,
    // The picture it asks for: its kind and width in pixels, or "icon <name>".
    val image: String,
    // For a card: the parts drawn, in reading order.
    val shows: List<String>,
    // A progress bar's fill, in whole percent.
    val progress: Int?,
    // Its buttons' labels in order, the primary one with a leading "*".
    val buttons: List<String>,
    val action: String,
    val children: List<SduiView>,
    // See all drawn as the row's last card, and the fraction of the next card that peeks in.
    val seeAllCard: Boolean = false,
    val peek: Double = 0.0,
) {
    val id: String get() = node.id
    val props: JsonObject get() = node.props
    val state: String get() = node.state
    val deferred: Boolean get() = node.state == "deferred"
    val failed: Boolean get() = node.state == "error"
    val empty: Boolean get() = node.state == "empty"

    fun line(part: String, otherwise: Int = Int.MAX_VALUE): Int = lines[part] ?: otherwise

    // The buttons of a Hero slide or a DetailHeader, as nodes would carry them.
    val actionButtons: List<SduiButton>
        get() = props.objects("actions").map { b ->
            SduiButton(b.str("id"), b.str("label"), b.str("icon"), b.isOn("primary"), b.child("action")?.let { runCatching { json.decodeFromJsonElement(SduiAction.serializer(), it) }.getOrNull() })
        }
}

// Where focus starts and how it goes: every node that can take focus in reading order, the one focus starts on, and
// each focus group's members in order.
class SduiFocusPlan(val order: List<String>, val default: String, val groups: Map<String, List<String>>) {
    private val groupOf: Map<String, String> = groups.flatMap { (group, members) -> members.map { it to group } }.toMap()

    // One stop for a remote going up and down the page: a group with its members, or a single node on its own.
    class Stop(val id: String, val members: List<String>)

    // The page's stops in order. Up and down go to the previous or next one, landing on the member it last had focus
    // on; the page's order decides, never where things happen to be on screen.
    val stops: List<Stop> = run {
        val seen = LinkedHashMap<String, MutableList<String>>()
        order.forEach { id -> seen.getOrPut(groupOf[id]?.let { "g:$it" } ?: "n:$id") { mutableListOf() } += id }
        seen.map { (key, members) -> Stop(key.drop(2), members) }
    }

    fun groupOf(id: String): String? = groupOf[id]

    private fun stopIndex(id: String): Int = stops.indexOfFirst { id in it.members }

    // The stop above or below the one this node is in; null at the page's ends.
    fun stopAfter(id: String): Stop? = stopIndex(id).let { if (it < 0) null else stops.getOrNull(it + 1) }
    fun stopBefore(id: String): Stop? = stopIndex(id).let { if (it <= 0) null else stops.getOrNull(it - 1) }

    // Where a stop is entered: the member it last had focus on, else the page's default when it is in it, else its first.
    fun entry(stop: Stop, remembered: String?): String = when {
        remembered != null && remembered in stop.members -> remembered
        default in stop.members -> default
        else -> stop.members.first()
    }
}

class SduiScreen(val document: SduiDocument) {
    val layout: SduiLayout = document.layout ?: SduiLayout.FALLBACK
    val title: String get() = document.page.title
    val root: SduiView = build(document.root, 0, null)
    val focus: SduiFocusPlan = focusPlan(document.root)

    // Every view, depth first in display order.
    val visible: List<SduiView> by lazy { ArrayList<SduiView>().also { flatten(root, it) } }

    private fun flatten(view: SduiView, into: MutableList<SduiView>) {
        into += view
        view.children.forEach { flatten(it, into) }
    }

    private fun focusPlan(root: SduiNode): SduiFocusPlan {
        val byOrder = HashMap<Int, SduiNode>()
        fun collect(node: SduiNode) {
            node.focus?.let { byOrder[it.order] = node }
            node.children.forEach(::collect)
        }
        collect(root)
        val order = ArrayList<String>()
        var default = ""
        val groups = LinkedHashMap<String, MutableList<String>>()
        for (i in 1..byOrder.size) {
            val node = byOrder[i] ?: continue
            val focus = node.focus ?: continue
            order += node.id
            if (focus.default) default = node.id
            if (focus.group.isNotEmpty()) groups.getOrPut(focus.group) { mutableListOf() } += node.id
        }
        return SduiFocusPlan(order, default, groups)
    }

    private class Draft(val node: SduiNode, var type: String, val depth: Int) {
        var role = "none"
        var label = ""
        val text = LinkedHashMap<String, String>()
        val lines = LinkedHashMap<String, Int>()
        var textSize = 0
        var cards: Int? = null
        var placeholders = 0
        var cardStyle = ""
        var cardWidth = 0
        var cardHeight = 0
        var columns = 0
        var hasMore = false
        var seeAll = ""
        var seeAllCard = false
        var peek = 0.0
        var image = ""
        val shows = ArrayList<String>()
        var progress: Int? = null
        var buttons: List<String> = emptyList()
        var action = ""

        fun say(part: String, words: String) { if (words.isNotEmpty()) text[part] = words }
        fun limit(part: String, most: Int) { if (most > 0) lines[part] = most }
    }

    private fun build(node: SduiNode, depth: Int, parent: SduiNode?): SduiView {
        val d = Draft(node, node.type, depth)
        d.action = actionWords(node.action)
        describe(d, parent)
        val children = node.children.map { build(it, depth + 1, node) }
        return SduiView(
            node, d.type, depth, d.role, d.label, d.text, d.lines, d.textSize, d.cards, d.placeholders, d.cardStyle, d.cardWidth,
            d.cardHeight, d.columns, d.hasMore, d.seeAll, d.image, d.shows, d.progress, d.buttons, d.action, children,
            d.seeAllCard, d.peek,
        )
    }

    // A row's or grid's own part: how many cards, their size, its placeholders while they're on their way, whether
    // it asks for more, its See all, and its heading.
    private fun collection(d: Draft) {
        val p = d.node.props
        d.cards = d.node.children.size
        p.child("card")?.let { card ->
            d.cardStyle = p.str("cardStyle")
            d.cardWidth = card.int("width") ?: 0
            d.cardHeight = card.int("height") ?: 0
            if (d.node.state == "deferred") d.placeholders = layout.placeholders(d.cardWidth)
        }
        p.int("columns")?.let { d.columns = it }
        d.hasMore = p.child("more") != null && d.node.state != "deferred" && d.node.state != "error"
        d.seeAll = p.child("seeAll")?.str("route").orEmpty()
        d.seeAllCard = p.child("seeAll") != null && p.isOn("seeAllCard")
        if (d.node.type == "Shelf" && (p["peek"] as? JsonPrimitive)?.booleanOrNull != false) d.peek = layout.peek
        d.say("title", p.str("title"))
        d.say("subtitle", p.str("subtitle"))
        d.say("empty", p.str("emptyText"))
        d.limit("title", 1)
        d.textSize = layout.textSize("title")
    }

    private fun describe(d: Draft, parent: SduiNode?) {
        val node = d.node
        val p = node.props
        when (node.type) {
            "Page" -> { d.role = "main"; d.label = p.str("title") }
            "Shelf" -> { collection(d); d.role = "list"; d.label = p.str("title") }
            "Grid" -> {
                collection(d)
                // A grid is a list to TalkBack on a touch device.
                d.role = if (!layout.focusEngine && layout.formFactor != "desktop" && layout.formFactor != "web") "list" else "grid"
                d.label = p.str("title").ifEmpty { title }
            }
            "List" -> {
                d.cards = node.children.size
                d.role = "list"; d.label = p.str("title")
                d.say("title", p.str("title"))
                d.say("empty", p.str("emptyText"))
                d.hasMore = p.child("more") != null
            }
            "Card" -> card(d, parent)
            "Hero" -> {
                d.role = "region"; d.label = p.str("title").ifEmpty { "Featured" }
                d.cards = node.children.size
                p.child("size")?.let { d.cardWidth = it.int("width") ?: 0; d.cardHeight = it.int("height") ?: 0 }
                if (p.isOn("peek")) d.peek = layout.peek
                p.int("autoAdvanceSec")?.let { d.say("autoAdvance", "$it s") }
            }
            "Dock" -> {
                d.role = "toolbar"; d.label = p.str("title").ifEmpty { "Options" }
                d.cards = node.children.size
                d.buttons = node.children.filter { it.type == "Button" }.map { it.props.str("label") }
                d.cardHeight = layout.dock.height
                d.say("placement", p.str("placement"))
            }
            "KeyLegend" -> {
                d.say("keys", p.objects("entries").joinToString(" · ") { it.str("label") })
                d.textSize = layout.dock.hintSize
            }
            "Tabs" -> { d.role = "tablist"; d.cards = node.children.size }
            "Tab" -> {
                d.role = "tab"
                d.label = p.str("label") + if (p.isOn("selected")) ", selected" else ""
                d.say("title", p.str("label"))
                d.limit("title", 1)
            }
            "FilterBar" -> {
                d.role = "toolbar"; d.label = "Filter and sort"
                val buttons = ArrayList<String>()
                p.child("sort")?.let { buttons += "Sort: " + optionLabel(it, it.str("value")) }
                p.objects("fields").forEach { buttons += it.str("label") + ": " + optionLabel(it, it.str("value")).ifEmpty { "Any" } }
                d.buttons = buttons
                p.int("count")?.let { d.say("count", "$it titles") }
            }
            "DetailHeader" -> {
                d.role = "region"; d.label = p.str("title")
                d.say("title", p.str("title"))
                d.say("tagline", p.str("tagline"))
                d.say("facts", facts(p, " · "))
                d.say("overview", p.str("overview"))
                d.limit("title", 2)
                d.limit("overview", 4)
                d.textSize = layout.textSize("pageTitle")
                d.buttons = buttonLabels(p)
                d.progress = percent(p)
                p.child("images")?.let { d.image = join(imageWords(it, "backdrop"), imageWords(it, "poster")) }
            }
            "SeasonList" -> {
                d.role = "region"; d.label = "Episodes"
                d.cards = node.children.size
                d.buttons = p.objects("seasons").map { (if (it.isOn("selected")) "*" else "") + it.str("title") }
                d.hasMore = p.child("more") != null
                p.child("card")?.let { d.cardStyle = "episode"; d.cardWidth = it.int("width") ?: 0; d.cardHeight = it.int("height") ?: 0 }
            }
            "Credits" -> {
                // The cast's and the guest stars' cards in rows, then each department's people; how many of each were sent.
                d.role = "region"; d.label = p.str("title")
                d.cards = node.children.size
                d.say("title", p.str("title"))
                d.limit("title", 1)
                d.textSize = layout.textSize("heading")
                d.say("groups", p.objects("groups").joinToString(" · ") { g ->
                    val shown = g.int("shown") ?: 0
                    val total = g.int("total") ?: 0
                    g.str("label") + " " + shown + if (total > shown) " of $total" else ""
                })
                p.child("card")?.let { c -> d.cardStyle = "person"; d.cardWidth = c.int("width") ?: 0; d.cardHeight = c.int("height") ?: 0 }
                p.child("more")?.let { m -> d.hasMore = true; d.buttons = listOf(m.str("label").ifEmpty { "Show all" }) }
            }
            "TrackList" -> { d.role = "list"; d.label = "Tracks"; d.cards = node.children.size }
            "Track" -> {
                d.role = "button"
                val parts = ArrayList<String>()
                val list = parent?.props
                p.int("number")?.let { if (list == null || list.notOff("showNumbers")) parts += "Track $it" }
                parts += p.str("title")
                d.say("title", p.str("title"))
                d.limit("title", 1)
                if (list?.isOn("showArtist") == true) {
                    parts += p.str("artist")
                    d.say("subtitle", p.str("artist"))
                }
                p.int("durationSec")?.let {
                    if (list == null || list.notOff("showDuration")) {
                        parts += spokenDuration(it)
                        d.say("duration", clock(it))
                    }
                }
                d.label = join(parts)
                d.progress = percent(p)
            }
            "Banner" -> {
                d.role = if (node.action == null) "group" else "button"
                d.label = join(p.str("title"), p.str("text"), p.str("buttonLabel"))
                d.say("title", p.str("title"))
                d.say("text", p.str("text"))
                d.say("button", p.str("buttonLabel"))
                d.limit("title", 2)
                d.limit("text", 2)
                d.image = imageWords(p, "image")
            }
            "Text" -> {
                val role = p.str("role").ifEmpty { "body" }
                d.textSize = layout.textSize(role)
                d.role = when (role) { "pageTitle" -> "heading 1"; "heading" -> "heading 2"; "title" -> "heading 3"; else -> "text" }
                val shown = p.str("text")
                d.label = if (p.str("format") == "markdown") SduiMarkdown.plain(shown) else shown
                d.say("text", shown)
                p.int("maxLines")?.let { d.limit("text", it) }
            }
            "Notice" -> {
                d.role = if (p.str("tone") == "warning" || p.str("tone") == "danger") "alert" else "status"
                d.label = (p.str("title") + ". " + p.str("text")).removePrefix(". ")
                d.say("title", p.str("title"))
                d.say("text", p.str("text"))
                d.say("button", p.str("buttonLabel"))
            }
            "Button" -> {
                d.role = "button"; d.label = p.str("label")
                d.say("title", p.str("label"))
                d.limit("title", 1)
            }
            "Image" -> {
                d.image = imageWords(p, "image")
                val alt = p.str("alt")
                if (alt.isNotEmpty() || node.action != null) { d.role = "img"; d.label = alt }
            }
            "SearchBox" -> {
                d.role = "searchbox"; d.label = "Search"
                d.say("placeholder", p.str("placeholder"))
                d.say("query", p.str("query"))
            }
            "ListItem" -> {
                d.role = if (node.action != null) "button" else "text"
                d.label = join(p.str("title"), p.str("subtitle"), p.str("trailing"))
                d.say("title", p.str("title"))
                d.say("subtitle", p.str("subtitle"))
                d.say("trailing", p.str("trailing"))
                d.limit("title", 1)
                d.limit("subtitle", 1)
                d.image = imageWords(p, "image")
            }
            "Divider" -> d.role = "separator"
            "NativeView" -> { d.role = "group"; d.label = p.str("view") }
            "Stack", "Split", "Spacer" -> Unit
            // A type this app doesn't have is drawn as a plain column.
            else -> d.type = "Stack"
        }
    }

    // One Card: what its style shows of what it was given.
    private fun card(d: Draft, parent: SduiNode?) {
        val p = d.node.props
        d.role = "button"
        d.image = imageWords(p, "image")
        if (parent?.type == "Hero") {
            // A slide of a Hero is a group, not a button: its own buttons are what's pressed.
            d.role = "group"
            d.label = join(p.str("title"), facts(p, ", "))
            d.text["title"] = p.str("title")
            d.say("facts", facts(p, " · "))
            d.say("synopsis", p.str("synopsis"))
            d.lines["title"] = 2
            d.lines["synopsis"] = 3
            d.buttons = buttonLabels(p)
            d.action = ""
            return
        }
        d.label = cardLabel(p)
        val style = SduiCardStyles.named(p.str("style")) ?: SduiCardStyles.UNKNOWN
        val titles = parent == null || parent.props.notOff("showTitles")
        for (part in style.shows) {
            when (part) {
                "title", "subtitle" -> {
                    val words = p.str(part)
                    if (titles && words.isNotEmpty()) {
                        d.text[part] = words
                        d.shows += part
                        d.lines[part] = if (part == "title") style.titleLines else style.subtitleLines
                    }
                }
                "synopsis" -> p.str(part).takeIf { it.isNotEmpty() }?.let { d.text[part] = it; d.lines[part] = 2; d.shows += part }
                "remaining", "number" -> p.str(part).takeIf { it.isNotEmpty() }?.let { d.text[part] = it; d.shows += part }
                "now", "next" -> p.child(part)?.let { d.text[part] = it.str("title"); d.lines[part] = 1; d.shows += part }
                "progress" -> percent(p)?.let { d.progress = it; d.shows += part }
                "watched" -> if (p.isOn("watched")) d.shows += part
                "unwatched", "count" -> p.int(part)?.let { d.text[part] = it.toString(); d.shows += part }
                "badges" -> p.strings(part).takeIf { it.isNotEmpty() }?.let { d.text[part] = it.joinToString(" "); d.shows += part }
            }
        }
        p.int("rank")?.let { d.text["rank"] = it.toString(); d.shows.add(0, "rank") }
        if (d.image.isEmpty() && p.str("icon").isNotEmpty()) d.image = "icon " + p.str("icon")
    }

    // The page in the conformance kit's normalised shape (kit 1): what was laid out, said without pixels.
    fun normalised(): JsonObject = buildJsonObject {
        put("kit", 1)
        put("page", buildJsonObject {
            put("title", title)
            put("formFactor", layout.formFactor)
            put("breakpoint", layout.breakpoint)
            put("density", layout.density)
            put("contentWidth", layout.contentWidth)
            put("sectionGap", layout.sectionGap)
            put("scope", document.theme?.scope.orEmpty())
            layout.shell?.let { shell ->
                put("shell", buildJsonObject {
                    if (shell.experience.isNotEmpty()) put("experience", shell.experience) else put("layout", shell.layout)
                    put("nav", shell.nav)
                    if (shell.overlay) put("overlay", true)
                    put("size", shell.size)
                    if (shell.open > 0) put("open", shell.open)
                })
            }
        })
        put("visible", buildJsonArray { visible.forEach { add(element(it)) } })
        put("focus", buildJsonObject {
            put("order", JsonArray(focus.order.map(::JsonPrimitive)))
            put("default", focus.default)
            put("groups", JsonObject(focus.groups.mapValues { (_, members) -> JsonArray(members.map(::JsonPrimitive)) }))
        })
    }

    private fun element(v: SduiView): JsonObject = buildJsonObject {
        put("id", v.id)
        put("type", v.type)
        put("depth", v.depth)
        put("role", v.role)
        put("label", v.label)
        put("state", v.state)
        put("text", JsonObject(v.text.mapValues { JsonPrimitive(it.value) }))
        put("lines", JsonObject(v.lines.mapValues { JsonPrimitive(it.value) }))
        put("textSize", v.textSize)
        v.cards?.let { put("cards", it) }
        put("placeholders", v.placeholders)
        put("cardStyle", v.cardStyle)
        put("cardWidth", v.cardWidth)
        put("cardHeight", v.cardHeight)
        put("columns", v.columns)
        put("hasMore", v.hasMore)
        put("seeAll", v.seeAll)
        put("seeAllCard", v.seeAllCard)
        put("peek", v.peek)
        put("image", v.image)
        put("shows", JsonArray(v.shows.map(::JsonPrimitive)))
        v.progress?.let { put("progress", it) }
        put("buttons", JsonArray(v.buttons.map(::JsonPrimitive)))
        put("action", v.action)
        put("scope", v.node.scope)
    }

    companion object {
        // What activating something does, in words: "navigate /item/3", "play 3 from the start", "command watched.set 3".
        fun actionWords(a: SduiAction?): String = when (a?.type) {
            null -> ""
            "navigate", "native" -> a.type + " " + a.to
            "play" -> "play " + a.item + if ((a.params["resume"] as? JsonPrimitive)?.let { !it.isString && it.content == "false" } == true) " from the start" else ""
            "external" -> "external " + a.url
            "command" -> "command " + a.op + (if (a.item.isNotEmpty()) " " + a.item else "") + a.params.str("tab").let { if (it.isNotEmpty()) " $it" else "" }
            else -> a.type
        }

        private fun join(vararg parts: String): String = parts.filter { it.isNotEmpty() }.joinToString(", ")
        private fun join(parts: List<String>): String = parts.filter { it.isNotEmpty() }.joinToString(", ")

        private fun imageWords(p: JsonObject, key: String): String = p.child(key)?.let { it.str("kind") + " " + (it.int("width") ?: 0) }.orEmpty()

        // A fill from 0 to 1 as whole percent, halves rounded up.
        fun percent(p: JsonObject): Int? = p.num("progress")?.let { (it * 100 + 0.5).toInt() }

        private fun buttonLabels(p: JsonObject): List<String> = p.objects("actions").map { (if (it.isOn("primary")) "*" else "") + it.str("label") }

        fun facts(p: JsonObject, between: String): String = p.objects("facts").joinToString(between) { it.str("value") }

        private fun optionLabel(field: JsonObject, value: String): String =
            field.objects("options").firstOrNull { it.str("value") == value }?.str("label").orEmpty()

        // "4 minutes 3 seconds", as a track's length is said.
        fun spokenDuration(sec: Int): String {
            val m = sec / 60
            val s = sec % 60
            return when {
                m == 0 -> "$s seconds"
                s == 0 -> "$m minutes"
                else -> "$m minutes $s seconds"
            }
        }

        // "4:03", or "1:02:03" from an hour up.
        fun clock(sec: Int): String =
            if (sec >= 3600) "%d:%02d:%02d".format(sec / 3600, sec % 3600 / 60, sec % 60) else "%d:%02d".format(sec / 60, sec % 60)

        // A card's label for TalkBack: the parts its style shows, in the style's order, joined by ", ". A title that
        // isn't drawn (a photo's) is still said.
        fun cardLabel(p: JsonObject): String {
            val style = SduiCardStyles.named(p.str("style"))
            val shows = style?.shows ?: SduiCardStyles.UNKNOWN.shows
            val parts = ArrayList<String>()
            p.int("rank")?.let { parts += "Number $it" }
            if ("title" !in shows) parts += p.str("title")
            for (part in shows) {
                when (part) {
                    "title", "subtitle", "remaining" -> parts += p.str(part)
                    "number" -> p.str(part).takeIf { it.isNotEmpty() }?.let { parts += "Channel $it" }
                    "now", "next" -> p.child(part)?.let { parts += part + " " + it.str("title") }
                    "progress" -> percent(p)?.let { if (p.child("now") == null) parts += "$it percent watched" }
                    "watched" -> if (p.isOn("watched")) parts += "Watched"
                    "unwatched" -> p.int(part)?.let { parts += "$it unwatched" }
                    "count" -> p.int(part)?.let { parts += "$it items" }
                    "badges" -> parts += p.strings(part)
                }
            }
            return join(parts)
        }
    }
}

// The small Markdown subset a Text may hold: bold, italic, code, # to ### headings, - and 1. lists, paragraphs, and
// links to a route in the app or an http(s) address. Raw HTML is shown as the characters it is.
object SduiMarkdown {
    private val links = Regex("""\[([^\]]*)]\([^)]*\)""")
    private val marks = Regex("[*_`#>]+")
    private val spaces = Regex("""\s+""")

    // As TalkBack reads it: links by their text, marks removed, white space folded.
    fun plain(text: String): String = spaces.replace(marks.replace(links.replace(text, "$1"), ""), " ").trim()

    sealed interface Block {
        val spans: List<Span>
    }

    // level 1 to 3 for #, ##, ###.
    class Heading(val level: Int, override val spans: List<Span>) : Block
    class Paragraph(override val spans: List<Span>) : Block
    // `number` is 0 for a - item.
    class Item(val number: Int, override val spans: List<Span>) : Block

    class Span(val text: String, val bold: Boolean = false, val italic: Boolean = false, val code: Boolean = false, val link: String = "")

    private val heading = Regex("""^(#{1,3})\s+(.*)$""")
    private val bullet = Regex("""^-\s+(.*)$""")
    private val numbered = Regex("""^(\d+)\.\s+(.*)$""")

    fun blocks(text: String): List<Block> {
        val out = ArrayList<Block>()
        val paragraph = ArrayList<String>()
        fun flush() {
            if (paragraph.isNotEmpty()) out += Paragraph(spans(paragraph.joinToString(" ")))
            paragraph.clear()
        }
        for (raw in text.lines()) {
            val line = raw.trim()
            val h = heading.find(line)
            val b = bullet.find(line)
            val n = numbered.find(line)
            when {
                line.isEmpty() -> flush()
                h != null -> { flush(); out += Heading(h.groupValues[1].length, spans(h.groupValues[2])) }
                b != null -> { flush(); out += Item(0, spans(b.groupValues[1])) }
                n != null -> { flush(); out += Item(n.groupValues[1].toIntOrNull() ?: 1, spans(n.groupValues[2])) }
                else -> paragraph += line
            }
        }
        flush()
        return out
    }

    // Only a route in the app or an http(s) address is a link; anything else is its words alone.
    fun safeLink(to: String): Boolean = (to.startsWith("/") && !to.startsWith("//")) || to.startsWith("http://") || to.startsWith("https://")

    fun spans(text: String): List<Span> {
        val out = ArrayList<Span>()
        val plain = StringBuilder()
        var bold = false
        var italic = false
        fun flush() {
            if (plain.isNotEmpty()) out += Span(plain.toString(), bold, italic)
            plain.clear()
        }
        var i = 0
        while (i < text.length) {
            val c = text[i]
            when {
                text.startsWith("**", i) -> { flush(); bold = !bold; i += 2 }
                c == '*' -> { flush(); italic = !italic; i++ }
                c == '`' -> {
                    val end = text.indexOf('`', i + 1)
                    if (end < 0) { plain.append(c); i++ } else {
                        flush()
                        out += Span(text.substring(i + 1, end), bold, italic, code = true)
                        i = end + 1
                    }
                }
                c == '[' -> {
                    val match = links.matchAt(text, i)
                    if (match == null) { plain.append(c); i++ } else {
                        flush()
                        val to = text.substring(i + match.groupValues[1].length + 3, match.range.last)
                        out += Span(match.groupValues[1], bold, italic, link = if (safeLink(to)) to else "")
                        i = match.range.last + 1
                    }
                }
                else -> { plain.append(c); i++ }
            }
        }
        flush()
        return out
    }
}
