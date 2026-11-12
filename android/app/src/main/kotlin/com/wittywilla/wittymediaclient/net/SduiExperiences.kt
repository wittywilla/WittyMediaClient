// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Experiences (docs/plans/DESIGN-2.md section 7, docs/CLIENT-API.md): a UI is layout, shell, shape, finish and type; a
// theme is colour. The server lists them, says which this profile has on this device, and whether an administrator
// requires one.

@Serializable
data class SduiExperienceInfo(val id: String = "", val name: String = "", val tagline: String = "", val description: String = "", val icon: String = "", val theme: String = "")

@Serializable
data class SduiExperienceList(val experiences: List<SduiExperienceInfo> = emptyList(), val default: String = "")

// A value an administrator requires: who, when, and for whom (everyone or a profile).
@Serializable
data class SduiRequired(val value: String = "", val by: String = "", val at: Long = 0, val scope: String = "")

@Serializable
data class SduiExperienceChoice(
    val current: String = "",
    val chosen: String = "",
    val options: List<SduiChoice> = emptyList(),
    val url: String = "",
    val required: SduiRequired? = null,
)

@Serializable
data class SduiExperienceState(val experience: String = "", val choice: SduiExperienceChoice = SduiExperienceChoice(), val editable: Boolean = false)

object SduiLook {
    // What `GET /theme` says an administrator requires: `look.requiredTheme` and `look.requiredExperience`.
    fun requiredTheme(theme: JsonObject): SduiRequired? = required(theme, "requiredTheme")
    fun requiredExperience(theme: JsonObject): SduiRequired? = required(theme, "requiredExperience")

    private fun required(theme: JsonObject, key: String): SduiRequired? {
        val look = runCatching { theme["look"]?.jsonObject }.getOrNull() ?: return null
        val r = runCatching { look[key]?.jsonObject }.getOrNull() ?: return null
        val value = r["value"]?.jsonPrimitive?.content.orEmpty()
        if (value.isEmpty()) return null
        return SduiRequired(value, r["by"]?.jsonPrimitive?.content.orEmpty(), r["at"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0, r["scope"]?.jsonPrimitive?.content.orEmpty())
    }

    // The words for a locked choice.
    fun lockedWords(r: SduiRequired) = if (r.by.isEmpty()) "Required by your administrator" else "Required by ${r.by}"

    // Whether the first-connect chooser is offered: the person has chosen nothing, an administrator requires nothing, and
    // there is a choice to make.
    fun offerFirst(state: SduiExperienceState?, seen: Boolean): Boolean =
        state != null && !seen && state.choice.required == null && state.choice.chosen.isEmpty() && state.choice.options.size > 1 && state.editable
}
