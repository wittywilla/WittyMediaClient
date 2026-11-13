// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

// What catalogue revision 8 adds to a page (the server's docs/SDUI.md: Shell regions, Forms and controls, Detail panels,
// focusGrow and item actions), as plain Kotlin so it is tested without a screen: the compose side in ui/SduiRev8.kt draws it.

// One button of a card's `props.actions`: `glyph` is the key it carries (a select, b back, x and y the secondary and
// options keys of the shared pad map).
class SduiCardAction(val id: String, val label: String, val glyph: String, val action: SduiAction)

object SduiItemActions {
    // At most four, as the server sends them; one that has no action or label is left out.
    fun of(props: JsonObject): List<SduiCardAction> = props.objects("actions").take(4).mapNotNull { b ->
        val action = b.child("action")?.let { runCatching { json.decodeFromJsonElement(SduiAction.serializer(), it) }.getOrNull() } ?: return@mapNotNull null
        val label = b.str("label")
        if (label.isEmpty()) null else SduiCardAction(b.str("id"), label, b.str("glyph").lowercase(), action)
    }

    // What the A key (OK, a tap on the focused card) does: the item's `a` action when it has actions, else the card's own.
    fun select(card: SduiView): SduiAction? = of(card.props).firstOrNull { it.glyph == "a" }?.action ?: card.node.action

    // What a pad's X or Y key does on the card: the action carrying that glyph.
    fun forGlyph(card: SduiView, glyph: String): SduiAction? = of(card.props).firstOrNull { it.glyph == glyph }?.action

    // The detail panel's buttons for a card: its actions, or its one A action under the card's own label.
    fun buttons(card: SduiView): List<SduiCardAction> {
        val listed = of(card.props)
        if (listed.isNotEmpty()) return listed
        val own = card.node.action ?: return emptyList()
        return listOf(SduiCardAction("open", "Open", "a", own))
    }
}

// How a person card draws its presence: the tone of its badge by the card style's `badgeTones` (ok, warn, muted).
object SduiPresence {
    fun tone(style: String, badges: List<String>): String = badges.firstNotNullOfOrNull { SduiCardStyles.toneOf(style, it).takeIf { t -> t.isNotEmpty() } }.orEmpty()
}

// Whether a card is a focus stop on a device that has none of the server's own focus plan (a touch phone's keyboard, a
// screen reader): it has an action, or it is in a Shelf, Grid or List that says `focusable`.
object SduiFocusRules {
    fun focusable(card: SduiView): Boolean = card.node.focus != null || card.node.action != null || card.props.isOn("focusable")
}

// A ListItem's control: `control: {type, name, value, ...}` (switch, select, field, slider).
class SduiControlSpec(
    val type: String,
    val name: String,
    val value: JsonElement?,
    val options: List<Pair<String, String>>,
    val placeholder: String,
    val maxLength: Int,
    val multiline: Boolean,
    val input: String,
    val min: Double,
    val max: Double,
    val step: Double,
    val unit: String,
    val disabled: Boolean,
    val why: String,
) {
    val bool: Boolean get() = (value as? JsonPrimitive)?.booleanOrNull == true
    val text: String get() = (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: (value as? JsonPrimitive)?.content.orEmpty()
    val number: Double get() = (value as? JsonPrimitive)?.content?.toDoubleOrNull() ?: min

    companion object {
        val TYPES = setOf("switch", "select", "field", "slider")

        // Null for a row with no control, or one of a type this app doesn't have (it is then an ordinary row).
        fun of(props: JsonObject): SduiControlSpec? {
            val c = props.child("control") ?: return null
            val type = c.str("type")
            if (type !in TYPES) return null
            return SduiControlSpec(
                type = type, name = c.str("name"), value = c["value"],
                options = c.objects("options").map { it.str("value") to it.str("label").ifEmpty { it.str("value") } },
                placeholder = c.str("placeholder"), maxLength = c.int("maxLength") ?: 0, multiline = c.isOn("multiline"), input = c.str("input").ifEmpty { "text" },
                min = c.num("min") ?: 0.0, max = c.num("max") ?: 100.0, step = c.num("step")?.takeIf { it > 0 } ?: 1.0, unit = c.str("unit"),
                disabled = c.isOn("disabled"), why = c.str("why"),
            )
        }
    }
}

// What a Form holds while it is edited: every named control's value as the person has left it. Save runs the form's command
// with them under their names; it is off until something has changed (a television's Save).
class SduiFormValues(initial: Map<String, JsonElement>, private val numeric: Set<String> = emptySet()) {
    private var base: Map<String, JsonElement> = initial
    private val edited = LinkedHashMap<String, JsonElement>()

    fun set(name: String, value: JsonElement) {
        if (name.isEmpty()) return
        if (base[name] == value) edited.remove(name) else edited[name] = value
    }

    operator fun get(name: String): JsonElement? = edited[name] ?: base[name]

    // Saved: what is shown now is what the server has.
    fun saved() {
        base = base + edited
        edited.clear()
    }

    val changed: Boolean get() = edited.isNotEmpty()

    // The Form's own command with the values: the action's params first, each named control's value over them. A control named
    // `<param>.<key>` goes into the object parameter `param` under `key` (a number field gives a number, an empty control gives no
    // key, and a key ending `[]` splits comma-separated text into a list).
    fun submit(form: SduiAction): SduiAction {
        val params = LinkedHashMap<String, JsonElement>(form.params)
        val objects = LinkedHashMap<String, LinkedHashMap<String, JsonElement>>()
        for (name in base.keys) {
            val value = get(name)!!
            val dot = name.indexOf('.')
            if (dot <= 0) { params[name] = value; continue }
            val bag = objects.getOrPut(name.substring(0, dot)) { LinkedHashMap() }
            var key = name.substring(dot + 1)
            val text = (value as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (text != null && text.isEmpty()) continue
            if (key.endsWith("[]")) {
                key = key.removeSuffix("[]")
                val parts = (text ?: (value as? JsonPrimitive)?.content.orEmpty()).split(',').map { it.trim() }.filter { it.isNotEmpty() }
                if (parts.isNotEmpty()) bag[key] = kotlinx.serialization.json.JsonArray(parts.map { p -> if (name in numeric) (p.toDoubleOrNull()?.let(::number) ?: JsonPrimitive(p)) else JsonPrimitive(p) })
            } else if (text != null && name in numeric) {
                bag[key] = text.toDoubleOrNull()?.let(::number) ?: JsonPrimitive(text)
            } else bag[key] = value
        }
        objects.forEach { (param, bag) -> params[param] = JsonObject(bag) }
        return form.copy(params = JsonObject(params))
    }

    private fun number(d: Double): JsonPrimitive = if (d == Math.floor(d)) JsonPrimitive(d.toLong()) else JsonPrimitive(d)

    companion object {
        // Every named control of the form's rows, with its value as sent. A row with no name or a disabled one is not collected.
        fun of(form: SduiView): SduiFormValues {
            val values = LinkedHashMap<String, JsonElement>()
            val numeric = HashSet<String>()
            fun walk(v: SduiView) {
                SduiControlSpec.of(v.props)?.takeIf { it.name.isNotEmpty() && !it.disabled }?.let { spec ->
                    (spec.value ?: if (spec.type == "field") JsonPrimitive("") else null)?.let { values[spec.name] = it }
                    if (spec.type == "field" && spec.input == "number") numeric += spec.name
                }
                v.children.forEach(::walk)
            }
            form.children.forEach(::walk)
            return SduiFormValues(values, numeric)
        }
    }
}

// A control row's action with its chosen value added to the params (select, field and slider run a command with `value`).
fun SduiAction.withValue(value: JsonElement): SduiAction = copy(params = JsonObject(params + ("value" to value)))

// The Form a view is: the server's Form component, which a renderer without it draws as a column of its children.
val SduiView.isForm: Boolean get() = node.type == "Form"

// The statusBar's items with `{user}` and `{server}` filled in: text may hold placeholders.
object SduiRegionText {
    fun fill(text: String, user: String, server: String): String = text.replace("{user}", user).replace("{server}", server)
}

// What the shell draws of a page's regions: the items, the theme scope they came with (they stay while the module's pages show,
// the same scope, and go when the person leaves them) and what an administrator or a profile hid or moved with placements.
class SduiRegionsState(val regions: SduiRegions, val scope: String, val hideStatusBar: Boolean, val hideSystemDock: Boolean, val dockOnSide: Boolean)

object SduiRegionRules {
    // The regions to keep after a page arrived: its own when it has some, the held ones while the page is still in the same
    // theme scope, none otherwise.
    fun after(page: SduiDocument, held: SduiRegionsState?): SduiRegionsState? {
        val scope = page.theme?.scope.orEmpty()
        val own = page.regions?.takeIf { it.statusBar.isNotEmpty() || it.systemDock.isNotEmpty() }
        val placements = page.layout?.shell?.placements.orEmpty()
        return when {
            own != null -> SduiRegionsState(
                own, scope, placements["statusBar"]?.visible == false, placements["systemDock"]?.visible == false, placements["systemDock"]?.position == "side",
            )
            held != null && scope.isNotEmpty() && scope == held.scope -> held
            else -> null
        }
    }
}
