// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

// The server's pages as data (the server's docs/SDUI.md): the document a page arrives as, the device profile it was
// fitted to, the main menu and the catalogue. Every type here takes fields it doesn't know and leaves out ones it
// expected, so a newer server's page still reads; nothing here touches Android, so it's tested as plain Kotlin.

// The catalogue revision this app was built against, sent with every request.
const val SDUI_CATALOG = 3

// The only document version this app reads. A client refuses any other.
const val SDUI_VERSION = 1

private val NO_PROPS = JsonObject(emptyMap())

@Serializable
data class SduiDocument(
    val version: Int = 0,
    val catalog: Int = 0,
    val page: SduiPageInfo = SduiPageInfo(),
    val layout: SduiLayout? = null,
    val theme: SduiThemeScope? = null,
    val root: SduiNode = SduiNode(type = "Page", id = "page"),
    val screenTime: SduiScreenTime? = null,
    val personal: SduiPersonalInfo? = null,
    val meta: SduiMeta = SduiMeta(),
)

@Serializable
data class SduiPageInfo(
    val id: String = "",
    val kind: String = "",
    val title: String = "",
    val icon: String = "",
    val route: String = "",
    val variant: String = "",
    val params: Map<String, JsonElement> = emptyMap(),
)

@Serializable
data class SduiThemeScope(val scope: String = "", val tokens: Map<String, String> = emptyMap())

@Serializable
data class SduiScreenTime(val reason: String = "", val message: String = "", val nextAt: Long = 0)

@Serializable
data class SduiMeta(
    val etag: String = "",
    val generatedAt: String = "",
    val source: String = "",
    val configRevision: Int = 0,
    val ttlSeconds: Int = 0,
)

@Serializable
data class SduiNode(
    val type: String = "",
    val id: String = "",
    val props: JsonObject = NO_PROPS,
    val children: List<SduiNode> = emptyList(),
    val action: SduiAction? = null,
    val focus: SduiFocus? = null,
    val state: String = "",
    val scope: String = "",
    val tokens: Map<String, String> = emptyMap(),
)

@Serializable
data class SduiAction(
    val type: String = "",
    val to: String = "",
    val item: String = "",
    val url: String = "",
    val op: String = "",
    val params: JsonObject = NO_PROPS,
)

@Serializable
data class SduiFocus(val order: Int = 0, val group: String = "", val default: Boolean = false)

@Serializable
data class SduiSize(val width: Int = 0, val height: Int = 0)

@Serializable
data class SduiInsets(val top: Int = 0, val right: Int = 0, val bottom: Int = 0, val left: Int = 0)

@Serializable
data class SduiCardMetrics(
    val shape: String = "",
    val aspect: String = "",
    val columns: Int = 0,
    val width: Map<String, Int> = emptyMap(),
)

@Serializable
data class SduiBudget(
    val maxSections: Int = 0,
    val eagerSections: Int = 0,
    val shelfItems: Int = 0,
    val gridItems: Int = 0,
    val listItems: Int = 0,
    val pageSize: Int = 0,
    val heroItems: Int = 0,
    val repeats: Int = 0,
)

@Serializable
data class SduiTextLimits(val title: Int = 0, val subtitle: Int = 0, val synopsis: Int = 0, val overview: Int = 0)

// The device profile a page was fitted to. Sizes are in points: dp on a phone or tablet, and a TV's 1920 by 1080
// canvas, which this app draws at half a dp a point.
// Where the Dock goes: `bottom` (a bar `height` tall across the foot, outside the page's scroll) or `sheet` (a phone), and
// the size of the key legend's hints.
@Serializable
data class SduiDockSpec(val placement: String = "", val height: Int = 0, val hintSize: Int = 0)

@Serializable
data class SduiLayout(
    val formFactor: String = "",
    @SerialName("class") val deviceClass: String = "",
    val canvas: SduiSize = SduiSize(),
    val scale: Int = 1,
    val breakpoint: String = "",
    val safeArea: SduiInsets = SduiInsets(),
    val focusEngine: Boolean = false,
    val density: String = "",
    val spacing: Map<String, Int> = emptyMap(),
    val text: Map<String, Int> = emptyMap(),
    val cards: Map<String, SduiCardMetrics> = emptyMap(),
    val hero: SduiSize = SduiSize(),
    val imageWidths: List<Int> = emptyList(),
    val budget: SduiBudget = SduiBudget(),
    val textLimits: SduiTextLimits = SduiTextLimits(),
    val externalLinks: Boolean = false,
    val reducedMotion: Boolean = false,
    val truncated: Boolean = false,
    // The frame the app draws around the page: the layout option chosen, and its menu (docs/SDUI.md, Layout options).
    // Null from a server without layout options.
    val shell: SduiShell? = null,
    // The fraction of the next card or slide that shows at the trailing edge of a scrolling row, and the Dock's bar.
    val peek: Double = 0.0,
    val dock: SduiDockSpec = SduiDockSpec(),
) {
    val compact: Boolean get() = breakpoint == "compact"
    val tv: Boolean get() = formFactor == "tv"

    fun space(step: String): Int = spacing[step] ?: 0
    fun textSize(role: String): Int = text[role] ?: 0

    // The distance between a page's sections: l, or m on a compact window.
    val sectionGap: Int get() = if (compact) space("m") else space("l")

    // The distance between cards in a row or grid: m, or s + xs on a compact window.
    val cardGap: Int get() = if (compact) space("s") + space("xs") else space("m")

    // The width sections have to themselves: the canvas (or the breakpoint's usual window) less the safe area, or
    // less two m where the system has its own.
    val contentWidth: Int
        get() {
            val width = if (canvas.width > 0) canvas.width else USUAL_WIDTHS[breakpoint] ?: 0
            return if (safeArea.left + safeArea.right > 0) width - safeArea.left - safeArea.right else width - 2 * space("m")
        }

    // How many grey placeholders a row of cards this wide shows while it loads: as many as are at least partly on
    // screen, and no more than the row's first page.
    fun placeholders(cardWidth: Int): Int {
        if (cardWidth <= 0) return 0
        val n = (contentWidth + cardGap) / (cardWidth + cardGap) + 1
        return maxOf(1, minOf(n, budget.shelfItems))
    }

    // A grid's columns when the window changed without crossing a breakpoint: as many cards as fit, at least 2 (3 for
    // cards under 130 points).
    fun columnsFor(contentWidth: Int, cardWidth: Int): Int {
        if (cardWidth <= 0) return 1
        val minimum = if (cardWidth < 130) 3 else 2
        return maxOf(minimum, (contentWidth + cardGap) / (cardWidth + cardGap))
    }

    companion object {
        private val USUAL_WIDTHS = mapOf("compact" to 390, "medium" to 720, "expanded" to 1024, "large" to 1440)

        // What stands in when a document has no layout at all, which the contract doesn't allow: the web's usual
        // numbers, as the server's own reference does.
        val FALLBACK = SduiLayout(
            formFactor = "web", scale = 2, breakpoint = "large", density = "comfortable",
            spacing = mapOf("none" to 0, "xs" to 4, "s" to 8, "m" to 16, "l" to 24, "xl" to 48),
            text = mapOf("pageTitle" to 28, "heading" to 20, "title" to 16, "body" to 14, "caption" to 12),
            imageWidths = listOf(120, 160, 240, 320, 480, 640, 960, 1280, 1920, 2560, 3840),
            budget = SduiBudget(30, 8, 20, 60, 50, 48, 6, 16), externalLinks = true,
        )
    }
}

// A page of a section's items: the next cards of a row or grid, a deferred row's first page, another season.
@Serializable
data class SduiSectionItems(
    val version: Int = 0,
    val section: String = "",
    val items: List<SduiNode> = emptyList(),
    val next: String = "",
    val props: JsonObject? = null,
    val replace: Boolean = false,
    val state: String = "",
)

// GET /sdui/navigation: the main menu for this profile on this device.
@Serializable
data class SduiNavigation(
    val version: Int = 0,
    val formFactor: String = "",
    val etag: String = "",
    val items: List<SduiNavItem> = emptyList(),
    // The frame the app draws its menu in (Layout options in docs/SDUI.md), and what this profile may choose on this
    // device. Both null from a server without layout options.
    val shell: SduiShell? = null,
    val layouts: SduiLayouts? = null,
)

// The layouts this profile may choose on this device, for You's Layout row: the one in use, the one chosen here (empty:
// following the server), the choices, and where a choice is saved.
@Serializable
data class SduiLayouts(
    val current: String = "",
    val chosen: String = "",
    val options: List<SduiChoice> = emptyList(),
    val url: String = "",
)

@Serializable
data class SduiChoice(val value: String = "", val label: String = "")

@Serializable
data class SduiNavItem(
    val id: String = "",
    val label: String = "",
    val icon: String = "",
    val kind: String = "",
    val page: String = "",
    val params: Map<String, String> = emptyMap(),
    val screen: String = "",
    val route: String = "",
    val placement: String = "",
)

// What a profile may change about a page, and the page's top-level sections in its order.
@Serializable
data class SduiPersonalInfo(
    val editable: Boolean = false,
    val allow: List<String> = emptyList(),
    val sections: List<SduiPersonalSection> = emptyList(),
    val density: String = "",
    val url: String = "",
)

@Serializable
data class SduiPersonalSection(
    val id: String = "",
    val title: String = "",
    val hidden: Boolean = false,
    val pinned: Boolean = false,
    val locked: Boolean = false,
    val empty: Boolean = false,
)

// What a profile changed about a page: what PUT pages/{page}/personal takes, and GET answers.
@Serializable
data class SduiPersonal(
    val order: List<String> = emptyList(),
    val hidden: List<String> = emptyList(),
    val pinned: List<String> = emptyList(),
    val density: String = "",
    val cardSize: Map<String, String> = emptyMap(),
    val defaultTab: Map<String, String> = emptyMap(),
)

// GET /sdui/catalog, as far as a renderer needs it: the routes, the commands and the card styles.
@Serializable
data class SduiCatalog(
    val revision: Int = 0,
    val routes: List<SduiRouteSpec> = emptyList(),
    val commands: List<SduiCommandSpec> = emptyList(),
    val cardStyles: List<SduiCardStyleSpec> = emptyList(),
)

@Serializable
data class SduiRouteSpec(
    val pattern: String = "",
    val page: String = "",
    val native: String = "",
    val params: Map<String, String> = emptyMap(),
)

@Serializable
data class SduiCommandSpec(val op: String = "", val method: String = "", val path: String = "", val body: String = "")

@Serializable
data class SduiCardStyleSpec(
    val style: String = "",
    val shape: String = "",
    val aspect: String = "",
    val shows: List<String> = emptyList(),
    val titleLines: Int = 0,
    val subtitleLines: Int = 0,
)

// GET /sdui/pages/{page}/diff: patches from the render the client has, or the whole document.
@Serializable
data class SduiDiff(
    val etag: String = "",
    val since: String = "",
    val patches: List<SduiPatch>? = null,
    val document: SduiDocument? = null,
)

@Serializable
data class SduiPatch(
    val op: String = "",
    val path: String = "",
    val node: SduiNode? = null,
    val value: JsonElement? = null,
    val from: String = "",
)

// GET /sdui/topshelf: what the profile was in the middle of and what is new, for a TV's home screen.
@Serializable
data class SduiTopShelf(
    val version: Int = 0,
    val style: String = "",
    val expiresInSec: Int = 0,
    val sections: List<SduiTopShelfSection> = emptyList(),
)

@Serializable
data class SduiTopShelfSection(val title: String = "", val items: List<SduiTopShelfItem> = emptyList())

@Serializable
data class SduiImage(val url: String = "", val width: Int = 0, val height: Int = 0, val aspect: String = "", val kind: String = "")

@Serializable
data class SduiTopShelfItem(
    val id: String = "",
    val title: String = "",
    val shape: String = "",
    val progress: Double = 0.0,
    val image: SduiImage? = null,
    val displayRoute: String = "",
    val playRoute: String = "",
)

// Reading a node's properties. A property of another type than asked for counts as missing, as the server's own
// reference reads them.
fun JsonObject.str(key: String): String = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()

fun JsonObject.num(key: String): Double? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull

fun JsonObject.int(key: String): Int? = num(key)?.toInt()

fun JsonObject.isOn(key: String): Boolean = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull == true

// False only when the property is there and says so: for switches that are on unless turned off.
fun JsonObject.notOff(key: String): Boolean = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull != false

fun JsonObject.child(key: String): JsonObject? = this[key] as? JsonObject

fun JsonObject.list(key: String): List<JsonElement> = (this[key] as? JsonArray).orEmpty()

fun JsonObject.objects(key: String): List<JsonObject> = list(key).filterIsInstance<JsonObject>()

fun JsonObject.strings(key: String): List<String> =
    list(key).mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }

// A picture a node asks for: {url, width, height, aspect, kind}. The address already carries the width.
fun JsonObject.image(key: String): SduiImage? = child(key)?.let {
    SduiImage(it.str("url"), it.int("width") ?: 0, it.int("height") ?: 0, it.str("aspect"), it.str("kind"))
}

// "16/9" as a number; 0 when it isn't one.
fun aspectOf(text: String): Float {
    val parts = text.split('/')
    val w = parts.getOrNull(0)?.trim()?.toFloatOrNull() ?: return 0f
    val h = parts.getOrNull(1)?.trim()?.toFloatOrNull() ?: return 0f
    return if (h <= 0f) 0f else w / h
}

// The layout option a page is drawn in: its name (sidebar, topTabs, tvRows, compactList, streaming…), the menu's
// style (sidebar, rail, bottomTabs, topTabs, tvTopMenu, tvSideMenu), whether that menu lies over the page, its
// breadth in points, and how wide a TV's side menu opens while it has focus.
@Serializable
data class SduiShell(
    val layout: String = "",
    // Design 2's experience (lumen, rail, stage, aero, classic…), which takes the layout option's place.
    val experience: String = "",
    val nav: String = "",
    val overlay: Boolean = false,
    val size: Int = 0,
    val open: Int = 0,
)
