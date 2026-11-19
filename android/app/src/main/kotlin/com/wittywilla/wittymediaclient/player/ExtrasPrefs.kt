// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.content.Context
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.Serializable

// What this device does with a video's intro, recap, adverts and credits, and whether artwork may move: You, Playing
// on this device. Kept on the device, as the Viewing settings are (ViewPrefs.kt): the server keeps no such choice for
// an account, and a phone on its battery and a TV on the wall want different answers anyway.
@Serializable
data class ExtrasChoices(
    val autoIntro: Boolean = false,
    val autoRecap: Boolean = false,
    val autoCredits: Boolean = false,
    val autoAdverts: Boolean = false,
    val autoPreview: Boolean = false,
    val autoCustom: Boolean = false,
    // What a video's own .wittyinfo says to skip by itself: on unless turned off, as on the website.
    val fileAuto: Boolean = true,
    // The looping video behind a song's or a title's artwork.
    val canvas: Boolean = true,
) {
    val auto: AutoSkip get() = AutoSkip(intro = autoIntro, recap = autoRecap, credits = autoCredits, adverts = autoAdverts, preview = autoPreview, custom = autoCustom, fileAuto = fileAuto)

    fun withAuto(value: AutoSkip): ExtrasChoices = copy(
        autoIntro = value.intro, autoRecap = value.recap, autoCredits = value.credits, autoAdverts = value.adverts,
        autoPreview = value.preview, autoCustom = value.custom, fileAuto = value.fileAuto,
    )
}

object ExtrasPrefs {
    private const val FILE = "wms.extras"
    private const val KEY = "choices"

    @Volatile
    private var held: ExtrasChoices? = null

    fun load(context: Context): ExtrasChoices = held ?: run {
        val text = context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString(KEY, null)
        (text?.let { runCatching { json.decodeFromString<ExtrasChoices>(it) }.getOrNull() } ?: ExtrasChoices()).also { held = it }
    }

    fun save(context: Context, value: ExtrasChoices) {
        held = value
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putString(KEY, json.encodeToString(ExtrasChoices.serializer(), value)).apply()
    }
}
