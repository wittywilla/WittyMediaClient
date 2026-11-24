// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import java.text.Collator
import java.util.Locale

// The order of the subtitle and sound track lists, as the web app has them (web/src/player/trackOrder.ts): Off first,
// then the tracks in this device's languages, then the ones picked lately, then the rest by name. And the search that
// narrows a long list. Plain Kotlin, so the unit tests run it.
object TrackOrder {
    enum class Group { Off, Device, Recent, Other }

    // A search box is offered from this many tracks.
    const val SEARCH_FROM = 9
    private const val RECENT_MAX = 5

    // "eng", "ger", "en-GB" and "EN" are all "en". Empty for "und" and nothing.
    fun base(code: String?): String {
        val c = code.orEmpty().trim().replace('_', '-')
        if (c.isEmpty() || c.lowercase(Locale.ROOT) in setOf("und", "unknown", "zxx", "mul")) return ""
        val first = c.substringBefore('-').lowercase(Locale.ROOT)
        // The old bibliographic three-letter codes some files still carry.
        BIBLIOGRAPHIC[first]?.let { return it }
        if (first.length == 3) THREE[first]?.let { return it }
        return first
    }

    // "eng" to "en", for every language that has a two-letter code.
    private val THREE: Map<String, String> by lazy {
        Locale.getISOLanguages().mapNotNull { two -> runCatching { Locale.forLanguageTag(two).isO3Language }.getOrNull()?.takeIf { it.isNotEmpty() }?.let { it to two } }.toMap()
    }

    private val BIBLIOGRAPHIC = mapOf(
        "ger" to "de", "fre" to "fr", "dut" to "nl", "chi" to "zh", "gre" to "el", "cze" to "cs", "per" to "fa", "rum" to "ro",
        "slo" to "sk", "ice" to "is", "alb" to "sq", "arm" to "hy", "baq" to "eu", "bur" to "my", "geo" to "ka", "mac" to "mk",
        "mao" to "mi", "may" to "ms", "tib" to "bo", "wel" to "cy", "scc" to "sr", "scr" to "hr",
    )

    // Sorts the list into its groups. device: the languages the device is set to, most wanted first.
    fun <T> order(items: List<T>, lang: (T) -> String?, title: (T) -> String, isOff: (T) -> Boolean, device: List<String>, recent: List<String>): List<Pair<T, Group>> {
        val dev = device.map(::base).filter { it.isNotEmpty() }.distinct()
        val rec = recent.map(::base).filter { it.isNotEmpty() && it !in dev }.distinct()
        val collator = Collator.getInstance()
        data class Ranked<T>(val item: T, val group: Group, val n: Int, val i: Int)
        val ranked = items.mapIndexed { i, t ->
            val b = base(lang(t))
            when {
                isOff(t) -> Ranked(t, Group.Off, 0, i)
                b.isNotEmpty() && b in dev -> Ranked(t, Group.Device, dev.indexOf(b), i)
                b.isNotEmpty() && b in rec -> Ranked(t, Group.Recent, rec.indexOf(b), i)
                else -> Ranked(t, Group.Other, 0, i)
            }
        }
        return ranked.sortedWith { a, b ->
            a.group.ordinal.compareTo(b.group.ordinal).takeIf { it != 0 }
                ?: a.n.compareTo(b.n).takeIf { it != 0 }
                ?: (if (a.group == Group.Other) collator.compare(title(a.item), title(b.item)) else 0).takeIf { it != 0 }
                ?: a.i.compareTo(b.i)
        }.map { it.item to it.group }
    }

    // Every word typed must start a word of the track's words ("spa", "sdh", "forced").
    fun matches(words: List<String>, query: String): Boolean {
        val q = query.trim().lowercase(Locale.ROOT).split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (q.isEmpty()) return true
        val have = words.joinToString(" ").lowercase(Locale.ROOT).split(Regex("[\\s·,()/-]+")).filter { it.isNotEmpty() }
        return q.all { w -> have.any { it.startsWith(w) } }
    }

    // The languages picked lately, newest first, as they are saved (comma-separated).
    fun remember(saved: String, code: String?): String {
        val b = base(code)
        if (b.isEmpty()) return saved
        return (listOf(b) + saved.split(',').filter { it.isNotEmpty() && it != b }).take(RECENT_MAX).joinToString(",")
    }

    fun recent(saved: String): List<String> = saved.split(',').filter { it.isNotEmpty() }
}
