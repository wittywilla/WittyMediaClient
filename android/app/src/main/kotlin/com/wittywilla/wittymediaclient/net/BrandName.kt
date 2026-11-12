// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// The server's name as it is drawn in every frame: its coloured parts when the server sent them and they add up to the
// name, else the name in one colour, else the default name with Media in the accent (docs/CLIENT-API.md, brandParts).
object BrandName {
    const val DEFAULT = "WittyMediaServer"

    fun parts(name: String, parts: List<BrandPart>): List<BrandPart> {
        val joined = parts.joinToString("") { it.text }
        return when {
            parts.isNotEmpty() && joined.isNotEmpty() && (name.isEmpty() || joined == name) -> parts.filter { it.text.isNotEmpty() }
            name.isNotEmpty() -> listOf(BrandPart(name))
            else -> listOf(BrandPart("Witty"), BrandPart("Media", accent = true), BrandPart("Server"))
        }
    }

    fun plain(name: String, parts: List<BrandPart>): String = parts(name, parts).joinToString("") { it.text }
}
