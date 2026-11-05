package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import java.util.Locale

// A film's, an episode's, a disc's and a show's page, as the server's own website builds them (web/src/pages/
// ItemPage.tsx, ShowPage.tsx and components/edit/TitleExtras.tsx): what their answers say beyond what every list
// uses. The iPhone reads the same in WittyKit's TitlePage.swift.

// What else GET /items/{id} says that only an item's page shows. Read beside Item from the same answer, so the item
// every list uses stays small. Anything that can't be read counts as absent: a page never fails over one odd fact.
data class ItemFacts(
    val rating: Double? = null,
    // The poster's source: empty when there's none, and cache:frame-… or cache:thumb-… for a frame of the video.
    val poster: String? = null,
    val backdrop: String? = null,
    val provider: String? = null,
    val providerId: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val videoCodec: String? = null,
    val container: String? = null,
    val audioLangs: List<String>? = null,
    val subLangs: List<String>? = null,
    val sizeBytes: Long? = null,
    val path: String? = null,
    val disc: DiscInfo? = null,
    // How a disc starts and whether it plays the tray, with the server's defaults already applied.
    val startMode: String? = null,
    val insertEffect: Boolean? = null,
    // Which of a disc's titles was being watched.
    val discTitle: Int? = null,
) {
    companion object {
        fun read(text: String): ItemFacts = read(objectOf(text))

        fun read(o: JsonObject): ItemFacts = ItemFacts(
            rating = o.number("rating"), poster = o.text("poster"), backdrop = o.text("backdrop"), provider = o.text("provider"),
            providerId = o.textOrNumber("providerId"), width = o.whole("width"), height = o.whole("height"), videoCodec = o.text("videoCodec"),
            container = o.text("container"), audioLangs = o.texts("audioLangs"), subLangs = o.texts("subLangs"), sizeBytes = o.long("sizeBytes"),
            path = o.text("path"), disc = o.obj("disc")?.let(DiscInfo::read), startMode = o.text("startMode"), insertEffect = o.flag("insertEffect"),
            discTitle = o.obj("progress")?.whole("discTitle"),
        )
    }
}

// A DVD's or a Blu-ray's own description: its titles and which is the film.
data class DiscInfo(
    val label: String? = null,
    val hasMenus: Boolean? = null,
    val mainTitle: Int? = null,
    val titles: List<DiscTitle>? = null,
    val scrambled: Boolean? = null,
    // "movie" or "tv": a film, or episodes of a series.
    val content: String? = null,
) {
    companion object {
        fun read(o: JsonObject): DiscInfo = DiscInfo(
            label = o.text("label"), hasMenus = o.flag("hasMenus"), mainTitle = o.whole("mainTitle"),
            titles = (o["titles"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.let(DiscTitle::read) },
            scrambled = o.flag("scrambled"), content = o.text("content"),
        )
    }
}

// One title on a disc. `standard` is "pal" or "ntsc" on a DVD, and a Blu-ray's resolution, such as "1080p".
data class DiscTitle(val number: Int, val wide: Boolean? = null, val standard: String? = null) {
    companion object {
        fun read(o: JsonObject): DiscTitle? = o.whole("number")?.let { DiscTitle(it, o.flag("wide"), o.text("standard")) }
    }
}

// What else GET /shows/{id} says about the show that only its page shows: read from the answer's `show`.
data class ShowFacts(
    val libraryId: Long? = null,
    val genres: List<String>? = null,
    val contentRating: String? = null,
    val network: String? = null,
    val status: String? = null,
    val provider: String? = null,
    val providerId: String? = null,
    // Its own episode layout: "cards", "list", or empty for the server's.
    val view: String? = null,
) {
    companion object {
        fun read(text: String): ShowFacts {
            val o = objectOf(text).obj("show") ?: return ShowFacts()
            return ShowFacts(
                libraryId = o.long("libraryId"), genres = o.texts("genres"), contentRating = o.text("contentRating"), network = o.text("network"),
                status = o.text("status"), provider = o.text("provider"), providerId = o.textOrNumber("providerId"), view = o.text("view"),
            )
        }
    }
}

// Which kind of title a metadata route is about.
enum class TitleTarget(val word: String) { Item("item"), Show("show") }

// A title's extras, versions, studios and the rest beyond its row: /meta/{target}/{id}/attached. Nulls are nothing.
@Serializable
data class TitleAttached(
    val extras: List<AttachedExtra> = emptyList(),
    val versions: List<AttachedVersion> = emptyList(),
    val studios: List<String> = emptyList(),
    val director: String = "",
    val edition: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
    val hasLogo: Boolean = false,
)

@Serializable
data class AttachedExtra(val item: Item = Item(), val link: ExtraLink? = null)

@Serializable
data class ExtraLink(val extraType: String = "")

// Another version of the same title. Its item carries its height, for "· 1080p".
@Serializable
data class AttachedVersion(val item: Item = Item(), val link: VersionLink? = null)

@Serializable
data class VersionLink(val label: String = "")

// Which streaming services list a title: /meta/{target}/{id}/listings. asOf is in seconds since 1970.
@Serializable
data class TitleListings(val platforms: List<ListedPlatform> = emptyList(), val asOf: Long = 0, val region: String = "", val attribution: String = "")

@Serializable
data class ListedPlatform(val key: String = "", val name: String = "")

// The logo service's answer for one name (POST /logos/lookup): a logo, or only the name. An opaque picture has a
// background of its own, which can't change colour, so it goes on a white plate.
@Serializable
data class BrandLogoAnswer(val id: Long? = null, val kind: String = "", val name: String = "", val has: Boolean = false, val version: Long = 0, val opaque: Boolean = false) {
    companion object {
        // The key a page keeps an answer under, as the website matches them: case and spaces at the ends don't count.
        fun key(kind: String, name: String): String = kind + "|" + name.trim().lowercase(Locale.ROOT)
    }
}

@Serializable
data class LogoAsk(val kind: String, val name: String)

@Serializable
data class LogoLookup(val logos: List<LogoAsk>)

@Serializable
data class LogoAnswers(val logos: List<BrandLogoAnswer> = emptyList())

@Serializable
data class ShowView(val view: String)

// One of the server's short legal notices: its words, the words of its link, and where that goes.
data class NoticeLine(val words: String, val link: String, val path: String)

// A notice by its kind. An unknown kind is a newer server's, and is nothing here.
fun LegalNotices.notice(kind: String): NoticeLine? {
    val notice = notices[kind] ?: return null
    if (notice.text.isEmpty()) return null
    return NoticeLine(plainWords(notice.text, 2000), plainWords(linkText, 40).ifEmpty { "Legal" }, "/settings/legal" + if (notice.section.isEmpty()) "" else "#" + notice.section)
}

// Words from a server, kept to something a screen can show: no control characters or direction overrides, and not a
// page of text.
fun plainWords(text: String, limit: Int = 300): String {
    val shown = StringBuilder()
    var i = 0
    while (i < text.length) {
        val c = text.codePointAt(i)
        if (c >= 0x20 && c !in 0x7f..0x9f && c !in 0x202a..0x202e && c !in 0x2066..0x2069) shown.appendCodePoint(c)
        i += Character.charCount(c)
    }
    return shown.toString().trim().take(limit)
}

// A value in an address: letters, digits and -._~ as they are, everything else percent-encoded, so a name can't
// break out of its place.
fun queryValue(text: String): String {
    val out = StringBuilder()
    for (byte in text.toByteArray(Charsets.UTF_8)) {
        val b = byte.toInt() and 0xff
        val c = b.toChar()
        if (b < 0x80 && (c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c in "-._~")) out.append(c)
        else out.append('%').append(HEX[b shr 4]).append(HEX[b and 0xf])
    }
    return out.toString()
}

private const val HEX = "0123456789ABCDEF"

// Reading an answer leniently: a field of the wrong kind is absent.
private fun objectOf(text: String): JsonObject = runCatching { json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: JsonObject(emptyMap())

private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

// An id may come as words or as a number.
private fun JsonObject.textOrNumber(key: String): String? =
    (this[key] as? JsonPrimitive)?.let { if (it.isString) it.content else it.longOrNull?.toString() }

private fun JsonObject.whole(key: String): Int? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull

private fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.let { it.longOrNull ?: it.doubleOrNull?.toLong() }

private fun JsonObject.number(key: String): Double? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull

private fun JsonObject.flag(key: String): Boolean? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

private fun JsonObject.texts(key: String): List<String>? = (this[key] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
