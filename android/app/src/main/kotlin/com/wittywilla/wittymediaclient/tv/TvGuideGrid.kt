package com.wittywilla.wittymediaclient.tv

import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.GuideCell
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.TvLook
import com.wittywilla.wittymediaclient.net.TvShape
import com.wittywilla.wittymediaclient.ui.Symbols

// The guide's grid, as GuidePage.tsx draws it and Apple TV's GuideTimes, GuideNowLine, GuideRow and GuideCellStyle do:
// the times over the grid, the line at the current time, and each channel's row of cells, in the theme's shape.

// The row of times over the grid, with the day and time in its corner.
@Composable
fun GuideTimes(dress: TvDress, from: Long, now: Long, slots: Int) {
    val p = dress.paint
    val shape = dress.shape
    val size = dress.timeSize
    val weight = when (shape) {
        TvShape.Receiver, TvShape.Teletext, TvShape.Listings, TvShape.Outline -> W.Regular
        TvShape.Modern, TvShape.Cinema, TvShape.Compact -> W.Semibold
        else -> W.Bold
    }
    val padding = if (shape == TvShape.Compact) 3f else 8f
    val height = size * 1.4f + padding * 2
    val fill = when (shape) {
        TvShape.Box -> Brush.verticalGradient(listOf(p.head, p.panel))
        TvShape.Compact -> Brush.verticalGradient(listOf(p.panel, p.panel))
        else -> Brush.verticalGradient(listOf(p.bg, p.bg))
    }
    val bottom = when (shape) {
        TvShape.Box -> Modifier.rule(Edge.Bottom, p.line, dress.pt(3))
        TvShape.Receiver, TvShape.Compact -> Modifier.rule(Edge.Bottom, p.line, dress.pt(1))
        TvShape.Listings -> Modifier.rule(Edge.Bottom, p.text, dress.pt(1))
        TvShape.Cinema -> Modifier.rule(Edge.Bottom, p.panel2, dress.pt(1))
        else -> Modifier
    }
    val corner = when (shape) {
        TvShape.Box -> Modifier.rule(Edge.Trailing, p.line, dress.pt(3))
        TvShape.Receiver, TvShape.Compact -> Modifier.rule(Edge.Trailing, p.line, dress.pt(1))
        TvShape.Listings -> Modifier.rule(Edge.Trailing, p.text, dress.pt(1))
        else -> Modifier
    }
    val tick: Color? = when (shape) {
        TvShape.Box, TvShape.Compact -> p.line
        TvShape.Modern, TvShape.Receiver, TvShape.Cinema -> p.panel2
        TvShape.Listings -> p.line
        else -> null
    }
    val upper = shape == TvShape.Box || shape == TvShape.Receiver || shape == TvShape.Teletext
    Row(Modifier.fillMaxWidth().height(dress.pt(height)).background(fill).then(bottom).semantics(mergeDescendants = true) { }) {
        val cornerColour = when (shape) {
            TvShape.Modern, TvShape.Listings, TvShape.Cinema, TvShape.Outline -> p.text
            TvShape.Teletext -> p.soft
            else -> p.accent
        }
        Row(
            Modifier
                .width(dress.pt(dress.channelWidth))
                .fillMaxHeight()
                .then(corner)
                .padding(horizontal = dress.pt(if (shape == TvShape.Compact) 8 else 10)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dress.pt(6)),
        ) {
            val tracking = if (shape == TvShape.Receiver) 1.5f else 0f
            val day = GuideRules.dayWord(from, now)
            Text(
                dress.words(if (upper) day.uppercase() else day, size, smallCaps = true), style = dress.font(size, W.Bold, tracking = tracking),
                color = cornerColour, maxLines = 1, softWrap = false,
            )
            val at = tvClock(from)
            Text(
                if (upper) at.uppercase() else at, style = dress.font(size, if (shape == TvShape.Modern) W.Semibold else W.Regular, italic = shape == TvShape.Listings, tracking = tracking),
                color = cornerColour, maxLines = 1, softWrap = false, overflow = TextOverflow.Clip,
            )
        }
        BoxWithConstraints(Modifier.weight(1f).fillMaxHeight().clipToBounds()) {
            val each = maxWidth / slots
            for (i in 0 until slots) {
                val at = tvClock(from + i * GuideRules.SLOT)
                Box(
                    Modifier
                        .absoluteOffset(x = each * i)
                        .width(each)
                        .fillMaxHeight()
                        .then(if (tick != null) Modifier.rule(Edge.Leading, tick, dress.pt(1)) else Modifier),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Text(
                        if (shape == TvShape.Box) at.uppercase() else at,
                        style = dress.font(size, weight, digits = shape == TvShape.Receiver, italic = shape == TvShape.Listings),
                        color = when (shape) {
                            TvShape.Modern, TvShape.Cinema, TvShape.Outline, TvShape.Teletext -> p.soft
                            TvShape.Receiver -> p.accent
                            else -> p.text
                        },
                        maxLines = 1, softWrap = false, overflow = TextOverflow.Clip,
                        modifier = Modifier.padding(start = dress.pt(if (shape == TvShape.Outline) 12 else if (shape == TvShape.Compact) 6 else 10)),
                    )
                }
            }
        }
    }
}

// The line at the current time, over the times and the rows: at the moment itself, with the time over it, as the page
// draws it.
@Composable
fun GuideNowLine(dress: TvDress, x: Dp, now: Long, modifier: Modifier = Modifier) {
    val p = dress.paint
    val shape = dress.shape
    val thin = shape == TvShape.Listings || shape == TvShape.Outline
    val pill = shape == TvShape.Modern || shape == TvShape.Outline
    val line = dress.pt(if (thin) 1 else 2)
    Layout(
        content = {
            Box(
                Modifier
                    .width(line)
                    .fillMaxHeight()
                    .then(if (thin) Modifier else Modifier.shadow(dress.pt(2), clip = false, ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.5f)))
                    .background(p.accent),
            )
            Text(
                tvClock(now),
                style = dress.font(if (shape == TvShape.Compact) 13.75f else 15f, W.Bold, italic = shape == TvShape.Listings),
                color = p.accentText, maxLines = 1, softWrap = false,
                modifier = Modifier
                    .background(p.accent, RoundedCornerShape(dress.pt(if (pill) 20f else dress.radius)))
                    .padding(horizontal = dress.pt(if (pill) 8 else if (shape == TvShape.Compact) 4 else 6), vertical = dress.pt(if (pill) 2 else 1)),
            )
        },
        modifier = modifier,
    ) { measurables, constraints ->
        val bar = measurables[0].measure(constraints.copy(minWidth = 0, minHeight = constraints.maxHeight))
        val label = measurables[1].measure(constraints.copy(minWidth = 0, minHeight = 0))
        layout(constraints.maxWidth, constraints.maxHeight) {
            val at = x.roundToPx()
            bar.place(at - bar.width / 2, 0)
            label.place(at - label.width / 2, dress.pt(if (shape == TvShape.Compact) 2 else 4).roundToPx())
        }
    }
}

// What a cell does with the remote, from the guide.
class CellActions(
    val focused: (row: Int, cell: GuideCell, focused: Boolean) -> Unit,
    val activate: (GuideChannel, GuideCell) -> Unit,
    val more: (GuideChannel, GuideCell) -> Unit,
    val watch: (GuideChannel) -> Unit,
    // Past the grid's left or right edge, which moves the time. True when it was taken.
    val earlier: () -> Boolean,
    val later: () -> Boolean,
    val requester: (row: Int, start: Long) -> FocusRequester,
    val forget: (row: Int, start: Long, FocusRequester) -> Unit,
)

// One channel's row: who it is, then its programmes.
@Composable
fun GuideRow(
    dress: TvDress,
    index: Int,
    channel: GuideChannel?,
    from: Long,
    to: Long,
    perSecond: Double,
    now: Long,
    current: Boolean,
    focusAt: Long?,
    actions: CellActions,
) {
    Row(Modifier.fillMaxWidth().height(dress.pt(dress.rowHeight))) {
        RowHeader(dress, index, channel, current, Modifier.width(dress.pt(dress.channelWidth)).fillMaxHeight())
        val cells = remember(channel, from, to, perSecond) { GuideRules.cells(channel, from, to, perSecond) }
        val focusedCell = focusAt?.let { GuideRules.cellAt(it, cells) }
        Box(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .then(if (dress.shape == TvShape.Modern || dress.shape == TvShape.Outline) Modifier.background(dress.paint.bg) else Modifier),
        ) {
            if (channel != null) {
                cells.forEachIndexed { i, cell ->
                    val start = maxOf(cell.start, from)
                    val end = minOf(cell.end, to)
                    val x = (start - from) * perSecond
                    val w = (end - start) * perSecond
                    androidx.compose.runtime.key(cell.start) {
                        GuideCellView(
                            dress, index, channel, cell, from, to, now, w.toFloat(), highlighted = cell == focusedCell, evenRow = index % 2 == 1,
                            reminded = TvReminders.has(channel.key, cell.start), first = i == 0, last = i == cells.lastIndex, actions = actions,
                            modifier = Modifier.absoluteOffset(x = dress.pt(x.toFloat())).width(dress.pt(maxOf(1.0, w).toFloat())).fillMaxHeight(),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RowHeader(dress: TvDress, index: Int, channel: GuideChannel?, current: Boolean, modifier: Modifier) {
    val p = dress.paint
    val shape = dress.shape
    val lit = current && dress.rowHighlight
    val ink = if (lit) p.hiText else p.text
    val n = dress.number
    val name = dress.name
    val inset = if (shape == TvShape.Modern || shape == TvShape.Outline) 3f else 0f
    val round = RoundedCornerShape(dress.pt(if (shape == TvShape.Modern || shape == TvShape.Outline) 10 else 0))
    val fill: Color = when (shape) {
        TvShape.Box -> p.ch
        TvShape.Modern -> if (lit) p.hi else p.ch
        TvShape.Cinema -> if (lit) p.hi else p.bg
        TvShape.Teletext, TvShape.Listings -> if (current) p.panel2 else p.bg
        TvShape.Outline -> Color.Transparent
        TvShape.Compact -> if (index % 2 == 1) p.panel else p.bg
        TvShape.Receiver -> p.bg
    }
    val rules = when (shape) {
        TvShape.Box -> Modifier.rule(Edge.Trailing, p.line, dress.pt(3)).strokeInside(p.bg, dress.pt(1), 0.dp)
        TvShape.Receiver -> Modifier.rule(Edge.Bottom, p.panel2, dress.pt(1)).rule(Edge.Trailing, p.line, dress.pt(1))
        TvShape.Listings -> Modifier.rule(Edge.Bottom, p.line, dress.pt(1)).rule(Edge.Trailing, p.text, dress.pt(1))
        TvShape.Cinema -> Modifier.rule(Edge.Bottom, p.panel, dress.pt(1))
        TvShape.Compact -> Modifier.rule(Edge.Bottom, p.panel2, dress.pt(1)).rule(Edge.Trailing, p.line, dress.pt(1))
        else -> Modifier
    }
    val accent = TvLook.channelAccent(channel?.accent, dress.look.colours.bg)
    Box(modifier.padding(vertical = dress.pt(inset)).padding(end = dress.pt(inset * 2))) {
        Box(
            Modifier
                .fillMaxSize()
                .then(if (shape == TvShape.Outline) Modifier.strokeInside(if (current) p.accent else p.line, dress.pt(if (current) 2 else 1), dress.pt(10)) else Modifier)
                .clip(round)
                .background(fill)
                .then(if (shape == TvShape.Box) Modifier.bevel(dress.pt(2)) else Modifier)
                .then(rules)
                .drawWithContent {
                    drawContent()
                    if (accent != null) {
                        drawRoundRect(tvColour(accent), Offset.Zero, Size(dress.pt(4).toPx(), size.height), CornerRadius(if (shape == TvShape.Modern) dress.pt(10).toPx() else 0f))
                    } else if (shape == TvShape.Receiver && current) {
                        drawRect(p.accent, Offset.Zero, Size(dress.pt(3).toPx(), size.height))
                    }
                }
                .padding(horizontal = dress.pt(if (shape == TvShape.Modern) 12 else 8))
                .semantics(mergeDescendants = true) { },
            contentAlignment = Alignment.CenterStart,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dress.pt(if (shape == TvShape.Modern) 10 else if (shape == TvShape.Compact) 4 else 7))) {
                if (channel != null) {
                    Text(
                        channel.number,
                        style = dress.font(n.size, n.weight, digits = shape == TvShape.Receiver, italic = shape == TvShape.Listings, tabular = true),
                        color = if (lit) p.hiText else if (shape == TvShape.Modern) p.soft else p.accent,
                        textAlign = TextAlign.End, maxLines = 1, softWrap = false,
                        modifier = Modifier.widthIn(min = dress.pt(if (shape == TvShape.Compact) 28 else 56)),
                    )
                    if (hasLogo(dress, channel)) {
                        ChannelLogo(dress, channel, dress.logo, highlighted = current)
                        Spacer(Modifier.weight(1f))
                    } else {
                        val upper = shape == TvShape.Modern || shape == TvShape.Receiver || shape == TvShape.Teletext
                        Text(
                            dress.words(if (upper) channel.name.uppercase() else channel.name, name.size, smallCaps = true),
                            style = dress.font(name.size, name.weight, tracking = if (shape == TvShape.Modern) 0.4f else if (shape == TvShape.Receiver) 0.8f else 0f),
                            color = if (shape == TvShape.Teletext && !current) p.soft else ink,
                            maxLines = if (shape == TvShape.Compact) 1 else 2, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (channel.favourite) {
                        Icon(Symbols.StarFilled, contentDescription = "Favourite", tint = if (lit) p.hiText else p.accent, modifier = Modifier.size(dress.pt(24)))
                    }
                    if (!channel.canTune) Text("🔒", style = dress.font(15f).copy(fontFamily = null), color = ink)
                } else {
                    Text("…", style = dress.font(name.size, W.Bold), color = p.soft)
                }
            }
        }
    }
}

// A cell of the grid, in its shape: a programme, a gap, or a run of short ones. Highlighted, it takes the theme's
// highlight, as on the page; it has no ring of its own.
@Composable
private fun GuideCellView(
    dress: TvDress,
    row: Int,
    channel: GuideChannel,
    cell: GuideCell,
    from: Long,
    to: Long,
    now: Long,
    width: Float,
    highlighted: Boolean,
    evenRow: Boolean,
    reminded: Boolean,
    first: Boolean,
    last: Boolean,
    actions: CellActions,
    modifier: Modifier,
) {
    val requester = remember(row, cell.start) { actions.requester(row, cell.start) }
    DisposableEffect(requester) { onDispose { actions.forget(row, cell.start, requester) } }
    TvFocusable(
        onClick = { actions.activate(channel, cell) },
        onLongClick = { actions.more(channel, cell) },
        modifier = modifier.onPreviewKeyEvent { e ->
            if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
            when (e.nativeKeyEvent.keyCode) {
                KeyEvent.KEYCODE_DPAD_LEFT -> first && actions.earlier()
                KeyEvent.KEYCODE_DPAD_RIGHT -> last && actions.later()
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY -> {
                    actions.watch(channel)
                    true
                }
                else -> false
            }
        },
        ring = false,
        grows = false,
        focusRequester = requester,
        label = cellLabel(channel, cell, now),
        onFocus = { actions.focused(row, cell, it) },
    ) { focused, pressed ->
        CellBody(dress, channel, cell, from, to, now, width, focused || highlighted, evenRow, reminded, pressed)
    }
}

private fun cellLabel(channel: GuideChannel, cell: GuideCell, now: Long): String {
    val p = cell.programme
    val time = if (cell.kind == GuideCell.Kind.None) "" else GuideRules.span(cell.start, cell.end)
    val on = if (cell.isOn(now)) ", on now" else ""
    val lock = if (channel.security?.state == "encrypted") ", ${channel.security.label}" else ""
    return "Channel ${channel.number}, ${channel.name}: " + listOf(cell.title, p?.sub ?: "", time).filter { it.isNotEmpty() }.joinToString(", ") + on + lock
}

@Composable
private fun CellBody(
    dress: TvDress,
    channel: GuideChannel,
    cell: GuideCell,
    from: Long,
    to: Long,
    now: Long,
    width: Float,
    lit: Boolean,
    evenRow: Boolean,
    reminded: Boolean,
    pressed: Boolean,
) {
    val p = dress.paint
    val shape = dress.shape
    val live = cell.isOn(now)
    val past = cell.end <= now
    val dim = cell.isDim
    val tiny = width < 34
    val small = width < 96
    val inset = if (shape == TvShape.Modern || shape == TvShape.Outline) 3f else if (shape == TvShape.Cinema) 2f else 0f
    val radius = if (shape == TvShape.Modern || shape == TvShape.Outline) 10f else if (shape == TvShape.Cinema) 4f else 0f
    val box = RoundedCornerShape(dress.pt(radius))
    val ink = when {
        lit -> p.hiText
        dim || (past && shape != TvShape.Outline && shape != TvShape.Compact) -> p.soft
        shape == TvShape.Outline || (shape == TvShape.Compact && !live) -> p.text
        live -> p.liveText
        else -> p.cellText
    }
    val soft = when {
        lit -> p.hiText
        dim || past -> p.soft
        shape == TvShape.Outline || (shape == TvShape.Compact && !live) -> p.soft
        live -> p.liveSoft
        else -> p.cellSoft
    }
    Box(
        Modifier
            .fillMaxSize()
            .padding(vertical = dress.pt(inset))
            .padding(end = dress.pt(inset))
            .then(if (pressed) Modifier.background(Color.Transparent) else Modifier),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .then(cellBorder(dress, lit, live, past, dim, radius))
                .clip(box)
                .then(cellFill(dress, cell, lit, live, past, dim, evenRow, width)),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (dress.look.progress && live && cell.kind != GuideCell.Kind.None) {
                val start = maxOf(cell.start, from)
                val end = minOf(cell.end, to)
                val share = ((now - start).toFloat() / maxOf(1L, end - start)).coerceIn(0f, 1f)
                if (shape == TvShape.Outline) {
                    Box(Modifier.align(Alignment.BottomStart).width(dress.pt(width * share)).height(dress.pt(2)).background(if (lit) p.hiText else p.accent))
                } else {
                    Box(Modifier.fillMaxHeight().width(dress.pt(width * share)).background(if (lit) p.hiText.copy(alpha = 0.14f) else p.lite))
                }
            }
            if (tiny) {
                if (cell.kind == GuideCell.Kind.Group) {
                    Text(
                        "${cell.group.size}", style = dress.font(13.75f, W.Bold).copy(fontFamily = null), color = ink, textAlign = TextAlign.Center,
                        maxLines = 1, softWrap = false, modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                Row(
                    Modifier.padding(horizontal = dress.pt(cellPadding(shape))),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(dress.pt(3)),
                ) {
                    val arrow = dress.font(13.75f).copy(fontFamily = null)
                    if (cell.start < from) Text("◄", style = arrow, color = ink)
                    Box(Modifier.weight(1f)) { CellWords(dress, channel, cell, ink, soft, small, reminded) }
                    if (cell.end > to) Text("►", style = arrow, color = ink)
                }
            }
        }
    }
}

private fun cellPadding(shape: TvShape) = when (shape) {
    TvShape.Modern -> 14f
    TvShape.Receiver, TvShape.Listings -> 10f
    TvShape.Teletext -> 8f
    TvShape.Cinema, TvShape.Outline -> 12f
    TvShape.Compact -> 6f
    TvShape.Box -> 6f
}

@Composable
private fun CellWords(dress: TvDress, channel: GuideChannel, cell: GuideCell, ink: Color, soft: Color, small: Boolean, reminded: Boolean) {
    val shape = dress.shape
    val p = cell.programme
    val details = listOf(
        if (cell.kind == GuideCell.Kind.None || small) "" else tvClock(cell.start),
        p?.year?.toString() ?: "",
        p?.genre ?: "",
    ).filter { it.isNotEmpty() }.joinToString(" · ")
    val under = if (dress.look.subtitles) (if (shape.details) details else p?.sub ?: "") else ""
    val lock = if (channel.canTune) "" else "🔒 "
    val reminder = if (reminded) " ⏰" else ""
    val t = dress.cellTitle
    val title = lock + cell.title + reminder
    val titleStyle = dress.font(t.size, if (cell.isDim) W.Regular else t.weight, tracking = if (shape == TvShape.Box) t.size * 0.01f else 0f)
    val underStyle = dress.font(dress.cellSmall, italic = shape == TvShape.Listings)
    if (shape == TvShape.Compact) {
        Row(horizontalArrangement = Arrangement.spacedBy(dress.pt(8))) {
            Text(title, style = titleStyle, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.alignByBaseline().weight(1f, fill = false))
            if (under.isNotEmpty()) Text(under, style = underStyle, color = soft, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.alignByBaseline())
        }
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(dress.pt(if (shape == TvShape.Modern) 3 else 0))) {
            Text(if (shape == TvShape.Teletext) title.uppercase() else title, style = titleStyle, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (under.isNotEmpty()) Text(under, style = underStyle, color = soft, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

private fun cellFill(dress: TvDress, cell: GuideCell, lit: Boolean, live: Boolean, past: Boolean, dim: Boolean, evenRow: Boolean, width: Float): Modifier {
    val p = dress.paint
    val shape = dress.shape
    return when {
        lit -> Modifier.background(p.hi)
        shape == TvShape.Outline -> Modifier
        dim || past -> Modifier.background(p.dim)
        cell.kind == GuideCell.Kind.Group -> Modifier.drawWithContent {
            // Stripes: the cell's colour, then a thin gap, across the run.
            val a = dress.pt(3).toPx()
            val gap = dress.pt(if (shape == TvShape.Modern) 2 else 3).toPx()
            val other = if (shape == TvShape.Modern) p.bg else p.cell2
            var x = 0f
            while (x < size.width) {
                drawRect(p.cell, Offset(x, 0f), Size(a, size.height))
                drawRect(other, Offset(x + a, 0f), Size(gap, size.height))
                x += a + gap
            }
            drawContent()
        }
        shape == TvShape.Box -> Modifier.background(Brush.verticalGradient(if (live) listOf(p.live, p.live2) else listOf(p.cell, p.cell2))).bevel(dress.pt(2))
        shape == TvShape.Compact -> Modifier.background(if (live) p.live else if (evenRow) p.panel else p.bg)
        else -> Modifier.background(if (live) p.live else p.cell)
    }
}

private fun cellBorder(dress: TvDress, lit: Boolean, live: Boolean, past: Boolean, dim: Boolean, radius: Float): Modifier {
    val p = dress.paint
    return when (dress.shape) {
        TvShape.Box -> Modifier.drawWithContent {
            drawContent()
            val w = dress.pt(2).toPx()
            drawRect(p.bg, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), style = Stroke(w))
            if (lit) drawRect(p.text, Offset(w * 1.5f, w * 1.5f), Size(size.width - w * 3, size.height - w * 3), style = Stroke(w))
        }
        TvShape.Modern -> if (!lit) Modifier else Modifier.drawWithContent {
            drawContent()
            val out = dress.pt(3).toPx()
            val w = dress.pt(2).toPx()
            drawRoundRect(p.accent, Offset(-out + w / 2, -out + w / 2), Size(size.width + out * 2 - w, size.height + out * 2 - w), CornerRadius(dress.pt(radius).toPx() - w / 2), style = Stroke(w))
        }
        TvShape.Receiver, TvShape.Compact -> Modifier.rule(Edge.Bottom, p.panel2, dress.pt(1)).rule(Edge.Trailing, p.panel2, dress.pt(1))
        TvShape.Listings -> Modifier.rule(Edge.Bottom, p.line, dress.pt(1)).rule(Edge.Trailing, p.line, dress.pt(1))
        TvShape.Outline -> when {
            lit -> Modifier.strokeInside(p.hi, dress.pt(1), dress.pt(radius))
            dim || past -> Modifier.strokeInside(p.line, dress.pt(1), dress.pt(radius), dash = floatArrayOf(5f, 4f))
            else -> Modifier.strokeInside(if (live) p.accent else p.line, dress.pt(1), dress.pt(radius))
        }
        else -> Modifier
    }
}
