// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.io.IOException
import java.net.URLEncoder
import java.security.MessageDigest

// Asking the server for its pages (docs/SDUI.md, "What a client sends" and "HTTP API"): every request says what
// device this is and what it can draw; every answer is kept with its ETag, so the next ask is a 304 and a server
// out of reach still shows the page as it last was.

// What this device is, sent with every request. `viewport` is the window in points, "411x891", empty on a TV.
data class SduiDevice(
    val platform: String,
    val formFactor: String,
    val deviceClass: String = "",
    val viewport: String = "",
    val locale: String = "",
    val capabilities: List<String> = emptyList(),
    val views: List<String> = emptyList(),
    // A stable name of this app's own on this device, so a profile's layout can be chosen per device. Never
    // anything that identifies the hardware.
    val device: String = "",
) {
    val parameters: List<Pair<String, String>>
        get() = buildList {
            add("catalog" to SDUI_CATALOG.toString())
            add("platform" to platform)
            add("formFactor" to formFactor)
            if (deviceClass.isNotEmpty()) add("deviceClass" to deviceClass)
            if (viewport.isNotEmpty()) add("viewport" to viewport)
            if (locale.isNotEmpty()) add("locale" to locale)
            if (capabilities.isNotEmpty()) add("capabilities" to capabilities.joinToString(","))
            if (views.isNotEmpty()) add("views" to views.joinToString(","))
            if (device.isNotEmpty()) add("device" to device)
        }

    // An address with this device's parameters added. One the address already carries stays as it is.
    fun on(address: String): String {
        val has = address.substringAfter('?', "").split('&').mapTo(HashSet()) { it.substringBefore('=') }
        val extra = parameters.filter { it.first !in has }.joinToString("&") { "${it.first}=${enc(it.second)}" }
        return if (extra.isEmpty()) address else address + (if ('?' in address) "&" else "?") + extra
    }

    companion object {
        // The window's width class, by the breakpoints the server lays out for: a new one means asking again.
        fun breakpoint(widthPoints: Int): String = when {
            widthPoints < 600 -> "compact"
            widthPoints < 840 -> "medium"
            widthPoints < 1200 -> "expanded"
            else -> "large"
        }

        // A tablet from the medium breakpoint up, as the app's own shell decides; a TV is always a TV.
        fun formFactor(tv: Boolean, smallestWidthPoints: Int): String = when {
            tv -> "tv"
            smallestWidthPoints >= 600 -> "tablet"
            else -> "phone"
        }

        // 4K only when the interface itself is drawn at 2160 lines or more, and never on a device short of memory:
        // most Android TVs draw at 1080 even on a 4K panel, and a TV stick with 1 or 2 GB can't hold 4K posters.
        fun tvClass(surfaceHeightPixels: Int, lowMemory: Boolean): String = if (surfaceHeightPixels >= 2160 && !lowMemory) "4k" else "hd"
    }
}

private fun enc(text: String): String = URLEncoder.encode(text, "UTF-8")

class SduiAnswer(val status: Int, val body: String, val etag: String = "")

// One request to the server, `path` from its root ("/api/v1/sdui/..."). Throws IOException when it can't be reached.
fun interface SduiTransport {
    suspend fun request(method: String, path: String, body: String?, ifNoneMatch: String?): SduiAnswer
}

// Where answers are kept between runs. Keys are opaque; an implementation bounds what it keeps.
interface SduiStore {
    fun read(key: String): String?
    fun write(key: String, value: String)
    fun clear()
}

// Kept in memory only, the most recently used first: for tests, and for a device whose storage can't be written.
class SduiMemoryStore(private val most: Int = 32) : SduiStore {
    private val kept = object : LinkedHashMap<String, String>(most, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>?) = size > most
    }

    @Synchronized override fun read(key: String): String? = kept[key]
    @Synchronized override fun write(key: String, value: String) { kept[key] = value }
    @Synchronized override fun clear() = kept.clear()
    val size: Int @Synchronized get() = kept.size
}

// Kept as files in one folder, a file a key, the oldest thrown out past `most`: what makes a page open at once the
// next time, and at all with the server out of reach. A folder that can't be written keeps nothing, quietly.
class SduiFileStore(private val folder: File, private val most: Int = 48) : SduiStore {
    private fun file(key: String): File {
        val digest = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
        return File(folder, digest.joinToString("") { "%02x".format(it) }.take(40) + ".json")
    }

    @Synchronized override fun read(key: String): String? = runCatching { file(key).takeIf { it.isFile }?.readText() }.getOrNull()

    @Synchronized override fun write(key: String, value: String) {
        runCatching {
            folder.mkdirs()
            val target = file(key)
            val draft = File(folder, target.name + ".part")
            draft.writeText(value)
            if (!draft.renameTo(target)) { target.delete(); draft.renameTo(target) }
            val kept = folder.listFiles { f -> f.name.endsWith(".json") }.orEmpty()
            if (kept.size > most) kept.sortedBy { it.lastModified() }.take(kept.size - most).forEach { it.delete() }
        }
    }

    @Synchronized override fun clear() {
        runCatching { folder.listFiles()?.forEach { it.delete() } }
    }
}

// A document with where it came from: fresh from the server, or the last one kept because the server couldn't be reached.
class SduiLoaded<T>(val value: T, val etag: String, val offline: Boolean = false)

// The page isn't one this app can read: a document version from the future.
class SduiUnsupported(message: String) : Exception(message)

@Serializable
private data class Kept(val etag: String = "", val body: String = "")

@Serializable
private data class PersonalAnswer(val editable: Boolean = false, val personal: SduiPersonal = SduiPersonal())

class SduiClient(private val transport: SduiTransport, val device: SduiDevice, private val store: SduiStore) {
    private fun kept(key: String): Kept? = store.read(key)?.let { runCatching { json.decodeFromString(Kept.serializer(), it) }.getOrNull() }

    private fun keep(key: String, etag: String, body: String) {
        if (etag.isNotEmpty()) store.write(key, json.encodeToString(Kept.serializer(), Kept(etag, body)))
    }

    private fun refusal(answer: SduiAnswer): ApiError {
        val parsed = runCatching { json.parseToJsonElement(answer.body).jsonObject }.getOrNull()
        val words = parsed?.get("error")?.let { runCatching { it.jsonPrimitive.content }.getOrNull() } ?: "The server answered with an error (${answer.status})."
        return ApiError(answer.status, words, code = parsed?.get("code")?.let { runCatching { it.jsonPrimitive.content }.getOrNull() }.orEmpty(), body = answer.body.take(MAX_REFUSAL))
    }

    // GET with If-None-Match from what was kept. A 304 answers what was kept; so does a server out of reach, marked
    // offline; with nothing kept, that failure is the caller's to show.
    private suspend fun cached(address: String): SduiLoaded<String> {
        val had = kept(address)
        val answer = try {
            transport.request("GET", address, null, had?.etag)
        } catch (e: IOException) {
            if (had != null) return SduiLoaded(had.body, had.etag, offline = true)
            throw e
        }
        return when {
            answer.status == 304 && had != null -> SduiLoaded(had.body, had.etag)
            answer.status in 200..299 -> {
                keep(address, answer.etag, answer.body)
                SduiLoaded(answer.body, answer.etag)
            }
            else -> throw refusal(answer)
        }
    }

    private suspend fun send(method: String, address: String, body: String? = null): String {
        val answer = transport.request(method, address, body, null)
        if (answer.status !in 200..299) throw refusal(answer)
        return answer.body
    }

    fun pageAddress(page: String, params: Map<String, String> = emptyMap(), suffix: String = ""): String {
        val query = params.entries.filter { it.value.isNotEmpty() }.sortedBy { it.key }.joinToString("&") { "${enc(it.key)}=${enc(it.value)}" }
        return device.on("$ROOT/pages/${enc(page)}$suffix" + if (query.isEmpty()) "" else "?$query")
    }

    private fun document(text: String, etag: String): SduiDocument {
        val doc = json.decodeFromString(SduiDocument.serializer(), text)
        if (doc.version != SDUI_VERSION) throw SduiUnsupported("This page was made for a newer app (version ${doc.version}).")
        return if (etag.isEmpty() || doc.meta.etag == etag) doc else doc.copy(meta = doc.meta.copy(etag = etag))
    }

    // A page as it was last kept, without asking: what to draw at once while the server is asked underneath.
    fun keptPage(page: String, params: Map<String, String> = emptyMap()): SduiDocument? =
        kept(pageAddress(page, params))?.let { runCatching { document(it.body, it.etag) }.getOrNull() }

    suspend fun page(page: String, params: Map<String, String> = emptyMap()): SduiLoaded<SduiDocument> {
        val loaded = cached(pageAddress(page, params))
        return SduiLoaded(document(loaded.value, loaded.etag), loaded.etag, loaded.offline)
    }

    // The page again, given the render this app has: null when nothing changed, else the new document, made by
    // patching the old one where the server still had it, and whole otherwise.
    suspend fun refreshed(page: String, params: Map<String, String>, have: SduiDocument): SduiDocument? {
        val since = have.meta.etag
        if (since.isEmpty()) return this.page(page, params).value
        val address = pageAddress(page, params, "/diff")
        val answer = transport.request("GET", "$address&since=${enc(since)}", null, null)
        if (answer.status == 304) return null
        if (answer.status !in 200..299) throw refusal(answer)
        val diff = json.decodeFromString(SduiDiff.serializer(), answer.body)
        if (diff.etag == since && diff.patches.isNullOrEmpty() && diff.document == null) return null
        val next = diff.document?.also { if (it.version != SDUI_VERSION) throw SduiUnsupported("This page was made for a newer app (version ${it.version}).") }
            ?: diff.patches?.let { SduiPatches.apply(have, it) }
            // A patch that doesn't fit: drop the tree and ask for the page.
            ?: return this.page(page, params).value
        val fresh = next.copy(meta = next.meta.copy(etag = diff.etag.ifEmpty { answer.etag }))
        keep(pageAddress(page, params), fresh.meta.etag, json.encodeToString(SduiDocument.serializer(), fresh))
        return fresh
    }

    // A section's page of items, from the address the page gave (props.more.url, a season's url).
    suspend fun items(url: String): SduiSectionItems = json.decodeFromString(SduiSectionItems.serializer(), send("GET", device.on(url)))

    suspend fun navigation(): SduiLoaded<SduiNavigation> {
        val loaded = cached(device.on("$ROOT/navigation"))
        return SduiLoaded(json.decodeFromString(SduiNavigation.serializer(), loaded.value), loaded.etag, loaded.offline)
    }

    fun keptNavigation(): SduiNavigation? =
        kept(device.on("$ROOT/navigation"))?.let { runCatching { json.decodeFromString(SduiNavigation.serializer(), it.body) }.getOrNull() }

    suspend fun catalog(): SduiCatalog = json.decodeFromString(SduiCatalog.serializer(), cached("$ROOT/catalog").value)

    suspend fun topShelf(): SduiTopShelf = json.decodeFromString(SduiTopShelf.serializer(), send("GET", device.on("$ROOT/topshelf")))

    // The profile's own arrangement of a page, at the address document.personal gave.
    suspend fun personal(url: String): SduiPersonal = json.decodeFromString(PersonalAnswer.serializer(), send("GET", url)).personal

    suspend fun savePersonal(url: String, personal: SduiPersonal) {
        send("PUT", url, json.encodeToString(SduiPersonal.serializer(), personal))
    }

    suspend fun resetPersonal(url: String) {
        send("DELETE", url)
    }

    // Carries out one of the catalogue's commands for an item.
    suspend fun command(spec: SduiCommandSpec, item: String) {
        val request = SduiCommands.request(spec, item) ?: return
        send(request.method, request.path, request.body)
    }

    fun forget() = store.clear()

    private companion object {
        const val ROOT = "/api/v1/sdui"
        const val MAX_REFUSAL = 64 * 1024
    }
}
