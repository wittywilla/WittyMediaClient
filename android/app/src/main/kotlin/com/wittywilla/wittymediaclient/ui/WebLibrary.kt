// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.BrowseHit
import com.wittywilla.wittymediaclient.net.Facet
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.ShelfCard
import com.wittywilla.wittymediaclient.net.Shelves
import kotlinx.coroutines.launch

// The website's library page for films, shows, discs and videos at phone width (web/src/pages/library/VideoLibrary.tsx,
// components/LibraryHeader.tsx, Filters.tsx): the name and count, Filters and "⋯", the SORT strip, then the shelves
// (categories, collections, studios, networks, Recently added, Highest rated, a row per category) or the grid.

private data class Sort(val key: String, val label: String, val desc: Boolean = false)

private val SORTS = listOf(
    Sort("shuffle", "Shuffle"), Sort("added", "Recently added", true), Sort("title", "Title A to Z"), Sort("newest", "Newest"),
    Sort("oldest", "Oldest"), Sort("rating", "Highest rated", true), Sort("quality", "Best quality", true),
)

private val FACETS = listOf(
    "genre" to ("Category" to "genres"), "kind" to ("Type" to "kinds"), "studio" to ("Studio" to "studios"), "network" to ("Network" to "networks"),
    "platform" to ("Listed on" to "platforms"), "decade" to ("Decade" to "decades"), "year" to ("Year" to "years"), "content" to ("Age rating" to "content"),
)
private val FACETS_AFTER = listOf(
    "resolution" to ("Picture" to "resolutions"), "format" to ("Sound" to "formats"), "audio" to ("Audio language" to "audio"),
    "subtitle" to ("Subtitles" to "subtitles"), "edition" to ("Edition" to "editions"), "tag" to ("Tags" to "tags"),
)
private val FILTER_NAMES = (FACETS + FACETS_AFTER).associate { it.first to it.second.first } + mapOf("minRating" to "Score", "watched" to "Watched", "search" to "Words")

private fun noun(type: String, n: Int): String {
    val (one, many) = when (type) { "movies" -> "film" to "films"; "shows", "anime" -> "show" to "shows"; "discs" -> "disc" to "discs"; else -> "video" to "videos" }
    return "$n ${if (n == 1) one else many}"
}

// artHue: the title's own hue for generated art.
private fun artHue(name: String): Float {
    var h = 0L
    var i = 0
    while (i < name.length) {
        val c = Character.codePointAt(name, i)
        h = (h * 31 + c) % 360
        i += Character.charCount(c)
    }
    return h.toFloat()
}

// The website's chip on a touch screen: 44 high, 12 inside, a pill outlined in text at 20%; chosen, inverted.
@Composable
fun Chip(words: String, chosen: Boolean, count: Int? = null, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Pressable(onClick, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = if (chosen) scheme.onBackground else Color.Transparent, label = words, selected = chosen, ring = false) {
        Row(
            Modifier.heightIn(min = 44.dp).border(1.dp, if (chosen) scheme.onBackground else scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(50)).padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val ink = if (chosen) scheme.background else scheme.onSurfaceVariant
            Text(words, color = ink, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            if (count != null) Text("$count", color = ink.copy(alpha = 0.7f), fontSize = 12.sp, modifier = Modifier.padding(start = 8.dp))
        }
    }
}
