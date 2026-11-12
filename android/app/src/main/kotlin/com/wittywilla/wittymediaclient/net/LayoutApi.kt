// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

// The routes the layout editor and the name editor drive, and no others (docs/CLIENT-API.md):
//   GET/PUT/DELETE /sdui/placements            the profile's own placements for this device
//   GET/PUT /sdui/config/experience             the administrator's, for everyone (If-Match: the ETag)
//   GET/PUT /settings                           brandName, brandColouring, brandSpans, brandMark (administrators)
//   GET /theme                                  brand: parts, mark, warnings
//   PUT/DELETE /branding/logo                   the logo, PNG or JPEG, at most 2 MB
// A page's own sections go through SduiClient (pages/{page}/personal), as Customise does.
class LayoutApi(private val api: Api, private val device: SduiDevice) {
    // MARK: placements for this profile

    // The regions and where they are on a device: this one, or (for an administrator looking at another form factor) a
    // form factor's, which has no device name of its own, so it is the form factor's placements that are read.
    suspend fun placements(formFactor: String? = null): PlacementsAnswer {
        val on = if (formFactor == null || formFactor == device.formFactor) device else device.copy(formFactor = formFactor, device = "")
        return json.decodeFromString(PlacementsAnswer.serializer(), api.call("GET", on.on("/sdui/placements")))
    }

    suspend fun savePlacements(placements: Map<String, SduiPlacement>) {
        api.call("PUT", device.on("/sdui/placements"), LayoutEditor.ownBody(placements))
    }

    suspend fun resetPlacements() {
        api.call("DELETE", device.on("/sdui/placements"))
    }

    // MARK: the administrator's, for everyone

    class Policy(val etag: String, val experiences: JsonObject)

    suspend fun policy(): Policy {
        val root = json.parseToJsonElement(api.call("GET", "/sdui/config/experience")).jsonObject
        return Policy(root["etag"]?.jsonPrimitive?.contentOrNull.orEmpty(), runCatching { root["experiences"]?.jsonObject }.getOrNull() ?: JsonObject(emptyMap()))
    }

    // Changes the administrator's placements: `change` is given what is there now and returns what to save. If another
    // administrator saved in between (412), it is read again and tried once more, so nothing is overwritten blindly.
    suspend fun updateEveryone(change: (JsonObject) -> JsonObject) {
        var attempt = 0
        while (true) {
            val now = policy()
            try {
                send("PUT", "/sdui/config/experience", change(now.experiences).toString().toByteArray(), "application/json", mapOf("If-Match" to now.etag))
                return
            } catch (e: ApiError) {
                if (e.status != 412 || attempt++ >= 1) throw e
            }
        }
    }

    // MARK: the server's name

    suspend fun settings(): Map<String, String> =
        json.decodeFromString(MapSerializer(String.serializer(), String.serializer()), api.call("GET", "/settings"))

    suspend fun saveSettings(values: Map<String, String>) {
        api.call("PUT", "/settings", buildJsonObject { values.forEach { (k, v) -> put(k, v) } }.toString())
    }

    suspend fun theme(): JsonObject = api.resolvedTheme()

    // The logo, as it came: the version the server keeps it as.
    suspend fun uploadLogo(bytes: ByteArray, mime: String): String {
        val answer = send("PUT", "/branding/logo", bytes, mime, emptyMap())
        return runCatching { json.parseToJsonElement(answer).jsonObject["brandLogo"]?.jsonPrimitive?.contentOrNull }.getOrNull().orEmpty()
    }

    suspend fun removeLogo() {
        api.call("DELETE", "/branding/logo")
    }

    // MARK: one request with a body the shared call doesn't carry: bytes, or headers of its own

    private suspend fun send(method: String, path: String, body: ByteArray, type: String, headers: Map<String, String>): String = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(api.base + "/api/v1" + path).method(method, body.toRequestBody(type.toMediaType()))
        headers.forEach { (k, v) -> request.header(k, v) }
        api.http.newCall(request.build()).execute().use { res ->
            val text = res.peekBody(MAX_ANSWER).string()
            if (res.code !in 200..299) {
                val words = runCatching { json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.contentOrNull }.getOrNull()
                    ?: "The server answered with an error (${res.code})."
                throw ApiError(res.code, words, code = errorCode(text), body = text.take(MAX_ANSWER.toInt()))
            }
            text
        }
    }

    private companion object {
        const val MAX_ANSWER = 64L * 1024
    }
}
