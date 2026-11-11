// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// What goes on an Android TV's home screen, from the server's answer for a TV's own shelf (GET /sdui/topshelf, which
// docs/SDUI.md describes for Apple TV's Top Shelf): what the profile was in the middle of goes in the system's Watch
// Next row, and everything, in the server's order, in the app's own channel. Apart from Android, so it's tested as
// plain Kotlin; data/TvHome.kt writes it to the TV.

// One title on the home screen. `progress` is how far through it the profile is, 0 for none.
data class TvHomeCard(
    val id: String,
    val title: String,
    // The row it came from on the server: "Continue watching", "New in Films".
    val row: String,
    val image: String,
    // poster, wide or square.
    val shape: String,
    val progress: Double,
    // Where choosing it leads: its page, and playing it where the server offers that.
    val displayRoute: String,
    val playRoute: String,
) {
    // What choosing it on the home screen opens: it plays when it can be played, as a card there is expected to.
    val route: String get() = playRoute.ifEmpty { displayRoute }
}

class TvHomePlan(val channel: List<TvHomeCard>, val watchNext: List<TvHomeCard>, val refreshAfterSec: Int) {
    companion object {
        private const val MOST_IN_CHANNEL = 40
        private const val MOST_WATCH_NEXT = 10
        private const val USUAL_REFRESH_SEC = 900

        fun from(shelf: SduiTopShelf): TvHomePlan {
            val cards = shelf.sections.flatMap { section ->
                section.items.filter { it.id.isNotEmpty() && openable(it.displayRoute.ifEmpty { it.playRoute }) }.map {
                    TvHomeCard(it.id, it.title, section.title, it.image?.url.orEmpty(), it.shape, it.progress, it.displayRoute.takeIf(::openable).orEmpty(), it.playRoute.takeIf(::openable).orEmpty())
                }
            }.distinctBy { it.id }
            return TvHomePlan(
                channel = cards.take(MOST_IN_CHANNEL),
                // Only what was started and can be carried on: Watch Next is for picking up where one left off.
                watchNext = cards.filter { it.progress > 0.0 && it.progress < 1.0 && it.playRoute.isNotEmpty() }.take(MOST_WATCH_NEXT),
                refreshAfterSec = shelf.expiresInSec.takeIf { it > 0 } ?: USUAL_REFRESH_SEC,
            )
        }

        // The only places a card on the home screen may open: a title's page, or playing a title. Nothing else is
        // taken from outside the app as somewhere to go.
        fun openable(route: String): Boolean {
            val path = route.substringBefore('?')
            val parts = path.trim('/').split('/')
            return route.startsWith("/") && !route.startsWith("//") && parts.size == 2 &&
                parts[0] in setOf("item", "show", "album", "watch", "play", "collections") && parts[1].isNotEmpty() && parts[1].all { it.isLetterOrDigit() || it == '-' }
        }
    }
}
