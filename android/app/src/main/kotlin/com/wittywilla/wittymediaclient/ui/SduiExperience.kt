// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.SduiView
import com.wittywilla.wittymediaclient.net.str
import kotlinx.coroutines.delay

// The experiences' own components (docs/plans/DESIGN-2-SDUI-GAPS.md, section 2): a centred carousel, the console's category
// bar, the dashboard's widgets and a numbered row. Each draws from the page's layout and tokens, never from the experience.

// A row of big cards one at a time: the nearest to the middle is full size, its neighbours smaller, and the next one
// peeks. On a TV the focused card is the one grown. It is a Shelf with a focus scale.
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SduiCarousel(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val span = LocalSduiSpan.current
    Column(Modifier.fillMaxWidth()) {
        SduiSectionHead(view, side)
        val wide = env.pt(view.cardWidth.takeIf { it > 0 } ?: 200)
        LazyRow(
            Modifier.fillMaxWidth(), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = maxOf(side, ((span.content - wide) / 2).coerceAtLeast(0.dp))),
            horizontalArrangement = Arrangement.spacedBy(env.pt(env.layout.cardGap)),
        ) {
            items(view.children, key = { it.id }) { card ->
                var focused by remember { mutableStateOf(false) }
                Box(
                    Modifier.graphicsLayer { val s = if (focused) 1.08f else 0.94f; scaleX = s; scaleY = s }
                        .onFocusChanged { focused = it.hasFocus },
                ) { SduiCard(card, view, wide) }
            }
        }
    }
}

// The console's category bar: the categories along the top, the chosen one's items in a vertical list under it.
@Composable
fun SduiCrossBar(view: SduiView, side: Dp) = SduiTabs(view, side, withContent = true)

// The dashboard: widgets in a grid of `columns` cells, each `w` cells wide and `h` tall.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SduiWidgetGrid(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val span = LocalSduiSpan.current
    val columns = (view.props["columns"]?.toString()?.toIntOrNull() ?: 4).coerceAtLeast(1)
    val gap = env.space("s")
    val cell = (span.content - gap * (columns - 1)) / columns
    FlowRow(
        Modifier.fillMaxWidth().padding(horizontal = side).semantics { contentDescription = view.label },
        horizontalArrangement = Arrangement.spacedBy(gap), verticalArrangement = Arrangement.spacedBy(gap),
    ) {
        view.children.forEach { w ->
            val cols = (w.props["w"]?.toString()?.toIntOrNull() ?: 1).coerceIn(1, columns)
            val rows = (w.props["h"]?.toString()?.toIntOrNull() ?: 1).coerceAtLeast(1)
            Box(Modifier.width(cell * cols + gap * (cols - 1)).heightIn(min = (cell * 0.6f) * rows)) { SduiWidget(w) }
        }
    }
}

@Composable
fun SduiWidget(view: SduiView) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    Column(
        Modifier.fillMaxWidth().elevated(2, RoundedCornerShape(env.pt(14)), env.pt(14)).padding(env.space("m")),
        verticalArrangement = Arrangement.spacedBy(env.space("s")),
    ) {
        view.text["title"]?.let { Text(it, color = scheme.onSurface, fontSize = env.size("title"), fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() }) }
        if (view.text["kind"] == "clock") {
            var now by remember { mutableStateOf(System.currentTimeMillis()) }
            LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
            Text(android.text.format.DateFormat.format("HH:mm", now).toString(), color = scheme.onSurface, fontSize = env.size("display"), fontWeight = FontWeight.Bold)
        }
        if (view.children.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
            view.children.forEach { SduiNode(it, view) }
        }
    }
}

// A listing's row: the index or channel number in a column of its own, then the title and what is on.
@Composable
fun SduiNumberedRow(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth()) {
        SduiSectionHead(view, side)
        view.children.forEach { c ->
            Pressable(
                { env.act(c.node.action) }, Modifier.fillMaxWidth().padding(horizontal = side), shape = RoundedCornerShape(env.pt(10)),
                label = c.label, enabled = c.node.action != null, disabledAlpha = 1f, focusKey = c.id.takeIf { env.tv }, ring = env.tv,
            ) {
                Row(Modifier.fillMaxWidth().heightIn(min = env.pt(if (env.tv) 90 else 56)).padding(horizontal = env.space("s")), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("m"))) {
                    Text(c.props.str("number"), color = LocalExtraColours.current.accentText, fontSize = env.size("title"), fontWeight = FontWeight.Bold, modifier = Modifier.width(env.pt(if (env.tv) 90 else 48)))
                    Column(Modifier.weight(1f)) {
                        Text(c.text["title"].orEmpty(), color = scheme.onBackground, fontSize = env.size("body"), maxLines = c.line("title", 2), overflow = TextOverflow.Ellipsis)
                        c.text["subtitle"]?.let { Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    }
                }
            }
        }
    }
}
