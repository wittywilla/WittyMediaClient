// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

// WittyTV's More info for one programme (docs/CLIENT-API.md, "More info": `GET /tv/{key}/programme?start=`): the facts, the
// buttons the server says to show, the library title, the people, trailers, other airings. Parsed as the server sent it;
// a field it didn't send is not shown.

data class InfoPerson(val name: String, val role: String, val personId: Long, val photo: String) {
    // A person only the guide knows has no page to open: no link, no focus ring promising one.
    val openable: Boolean get() = personId > 0
}

data class InfoAiring(val channel: String, val number: String, val start: Long, val end: Long, val here: Boolean)

data class InfoActions(
    val watch: Boolean = false, val record: Boolean = false, val remind: Boolean = false, val reminded: Boolean = false,
    val fromStart: Boolean = false, val watchLater: Boolean = false, val inList: Boolean = false, val open: Boolean = false,
)

data class MoreInfo(
    val channelName: String, val channelNumber: String, val logo: String,
    val start: Long, val end: Long, val title: String, val sub: String, val desc: String,
    val facts: List<String>, val actions: InfoActions, val itemId: Long, val showId: Long,
    val people: List<InfoPerson>, val trailers: List<String>, val schedule: List<InfoAiring>,
    val imdb: String, val tmdb: String,
)

object MoreInfoRules {
    private fun obj(e: JsonElement?) = e as? JsonObject
    private fun arr(e: JsonElement?) = e as? JsonArray ?: JsonArray(emptyList())
    private fun text(o: JsonObject?, k: String) = (o?.get(k) as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
    private fun long(o: JsonObject?, k: String) = (o?.get(k) as? JsonPrimitive)?.let { it.longOrNull ?: it.content.toDoubleOrNull()?.toLong() } ?: 0L
    private fun flag(o: JsonObject?, k: String) = (o?.get(k) as? JsonPrimitive)?.booleanOrNull == true

    // The facts line, in reading order: year, rating, season and episode, length, genres.
    fun facts(p: JsonObject?): List<String> = buildList {
        long(p, "year").takeIf { it > 0 }?.let { add(it.toString()) }
        text(p, "rating").takeIf { it.isNotEmpty() }?.let { add(it) }
        val s = long(p, "season"); val e = long(p, "episode")
        if (s > 0 && e > 0) add("S$s E$e") else if (s > 0) add("Season $s")
        long(p, "lengthMin").takeIf { it > 0 }?.let { add(if (it >= 60) "${it / 60} h ${it % 60} min".replace(" 0 min", "") else "$it min") }
        arr(p?.get("genres")).mapNotNull { (it as? JsonPrimitive)?.content }.take(3).takeIf { it.isNotEmpty() }?.let { add(it.joinToString(", ")) }
        if (flag(p, "new")) add("New") else if (flag(p, "repeat")) add("Repeat")
        if (flag(p, "hd")) add("HD")
    }

    // Cast first, then guest stars, then crew; each with the role it has.
    fun people(credits: JsonObject?): List<InfoPerson> {
        fun of(list: JsonElement?, roleKey: String) = arr(list).mapNotNull { e ->
            val o = obj(e) ?: return@mapNotNull null
            val name = text(o, "name").ifEmpty { return@mapNotNull null }
            InfoPerson(name, text(o, roleKey).ifEmpty { text(o, "job") }, long(o, "personId"), text(o, "photo"))
        }
        return of(credits?.get("cast"), "character") + of(credits?.get("guests"), "character") + of(credits?.get("crew"), "job")
    }

    fun parse(root: JsonObject): MoreInfo {
        val ch = obj(root["channel"]); val p = obj(root["programme"]); val a = obj(root["actions"]); val lib = obj(root["library"]); val ids = obj(root["ids"])
        return MoreInfo(
            channelName = text(ch, "name"), channelNumber = text(ch, "number").ifEmpty { long(ch, "number").takeIf { it > 0 }?.toString().orEmpty() }, logo = text(ch, "logo"),
            start = long(p, "start"), end = long(p, "end"), title = text(p, "title"), sub = text(p, "sub"), desc = text(p, "desc"),
            facts = facts(p),
            actions = InfoActions(flag(a, "watch"), flag(a, "record"), flag(a, "remind"), flag(a, "reminded"), flag(a, "fromStart"), flag(a, "watchLater"), flag(a, "inList"), flag(a, "open")),
            itemId = long(lib, "itemId"), showId = long(lib, "showId"),
            people = people(obj(root["credits"])),
            trailers = arr(root["trailers"]).mapNotNull { text(obj(it), "title").ifEmpty { null } },
            schedule = arr(root["schedule"]).mapNotNull { e -> obj(e)?.let { InfoAiring(text(it, "channel").ifEmpty { text(it, "name") }, text(it, "number"), long(it, "start"), long(it, "end"), flag(it, "this")) } },
            imdb = text(ids, "imdb"), tmdb = text(ids, "tmdb"),
        )
    }
}
