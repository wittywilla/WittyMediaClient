// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// A Dock's "jump to a letter" (docs/SDUI.md, `control.open`): A to Z and #, and the first title in a grid that starts with
// the letter. A title's first letter or digit counts; a leading "The " does not, as the server's title sort leaves it out.
object SduiJump {
    val LETTERS: List<String> = ('A'..'Z').map { it.toString() } + "#"
    const val MOST_PAGES = 20

    private val ARTICLES = listOf("the ", "a ", "an ")

    fun letterOf(title: String): String {
        var t = title.trim().lowercase()
        ARTICLES.firstOrNull { t.startsWith(it) && t.length > it.length }?.let { t = t.removePrefix(it) }
        val c = t.firstOrNull { it.isLetterOrDigit() } ?: return "#"
        return if (c in 'a'..'z') c.uppercase() else "#"
    }

    // The index of the first title for the letter, or -1.
    fun firstIndex(titles: List<String>, letter: String): Int = titles.indexOfFirst { letterOf(it) == letter }
}
