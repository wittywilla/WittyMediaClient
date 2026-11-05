package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

// How a person arranged Home (web/src/pages/HomePage.tsx), kept with their account under `home` in /me/ui, so it
// follows them to every device: the sections in their order, and those hidden. Apart from the screen, so it can be
// tested without one.
data class HomeLayout(val order: List<String> = emptyList(), val hidden: List<String> = emptyList(), val v: Int? = VERSION) {
    // The saved order first, then every section not placed yet, in the website's order.
    fun <T> ordered(widgets: List<T>, id: (T) -> String): List<T> {
        fun place(at: Int): Int = order.indexOf(id(widgets[at])).let { if (it < 0) 1000 + at else it }
        return widgets.indices.sortedWith(compareBy({ place(it) }, { it })).map { widgets[it] }
    }

    // One section moved to a place among them all, as they're shown.
    fun moving(id: String, place: Int, shown: List<String>): HomeLayout {
        val ids = shown.filter { it != id }.toMutableList()
        ids.add(place.coerceIn(0, ids.size), id)
        return HomeLayout(ids, hidden)
    }

    // A section hidden, or shown again.
    fun toggling(id: String): HomeLayout = HomeLayout(order, if (id in hidden) hidden - id else hidden + id)

    // As the website saves it: always at this version.
    fun toJson(): JsonObject = buildJsonObject {
        put("v", VERSION)
        putJsonArray("order") { order.forEach { add(JsonPrimitive(it)) } }
        putJsonArray("hidden") { hidden.forEach { add(JsonPrimitive(it)) } }
    }

    companion object {
        // Version 2 merged the Continue rows into Jump back in. An order saved before that is dropped once.
        const val VERSION = 2

        // What was saved, read as the website reads it: an older version's order is dropped, and a hidden Continue
        // row hides Jump back in.
        fun saved(saved: HomeLayout?): HomeLayout {
            if (saved == null) return HomeLayout()
            val hidden = saved.hidden.map { if (it.startsWith("continue")) "jump" else it }.distinct()
            return HomeLayout(if (saved.v == VERSION) saved.order else emptyList(), hidden)
        }
    }
}

// The parts of /me/ui Home reads. One that can't be read counts as not chosen.
data class HomeChoices(
    val home: HomeLayout? = null,
    // The newer version an administrator chose Later for, which hides its notice until the next one.
    val updateLater: String? = null,
)

private fun strings(element: JsonElement?): List<String> =
    (element as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }.orEmpty()

private fun uiObject(text: String): JsonObject = runCatching { json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: JsonObject(emptyMap())

fun readHomeChoices(text: String): HomeChoices {
    val ui = uiObject(text)
    val home = (ui["home"] as? JsonObject)?.let { saved ->
        HomeLayout(strings(saved["order"]), strings(saved["hidden"]), (saved["v"] as? JsonPrimitive)?.intOrNull)
    }
    val later = (ui["updateLater"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    return HomeChoices(home, later)
}

// The server keeps these choices whole, and the website keeps others there too: one choice changed, the rest kept.
fun withChoice(ui: String, key: String, value: JsonElement): String =
    JsonObject(uiObject(ui) + (key to value)).toString()
